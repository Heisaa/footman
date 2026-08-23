class_name WorldGen
extends RefCounted
## Generation of people, clubs and a season (PLAN.md §8, §9.7).
##
## Everything is drawn from a passed-in `SimRng`, so a seed reproduces a world
## exactly and nothing here reads global randomness -- the same rule the sim
## lives under (`docs/INVARIANTS.md`).
##
## Two decisions shape all of it:
##
## **The club's reputation moves the mean and nothing else.** A better club has
## better players in the same distribution; it does not have more freaks, and a
## bottom-division side is not denied one. The giant at the small club is the
## premise of the whole register (§9.7).
##
## **One or two men in a squad are tails, and the rest are plausible pros.** A
## squad where everybody is remarkable has nobody remarkable in it. The tail is
## forced rather than waited for: drawing eighteen men and hoping is how you get
## a division of eighteen identical sides.

## How many men in a squad are built to be describable in four words.
const TAILS_PER_SQUAD_MIN := 1
const TAILS_PER_SQUAD_MAX := 2

## The quality band reputation moves through. The floor is a park side that
## still belongs on a pitch; the ceiling is the best club in the game.
const QUALITY_FLOOR := 0.30
const QUALITY_CEILING := 0.80
## How much one man varies from his club's level.
const QUALITY_SPREAD := 0.075

const AGE_MEAN := 25.5
const AGE_SPREAD := 4.6
const AGE_MIN := 17
const AGE_MAX := 38

const HEIGHT_MEAN := 1.79
const HEIGHT_SPREAD := 0.065
const GIANT_HEIGHT := 1.95
const SPRITE_HEIGHT := 1.64

## The kinds of tail a squad can be given, and how often each turns up. Weighted
## by what a crowd would talk about on the way home rather than evenly.
const TAIL_KINDS := [
	WorldNickname.HAMMER,
	WorldNickname.GIANT,
	WorldNickname.SPRITE,
	WorldNickname.WHIPPET,
	WorldNickname.BRAIN,
	WorldNickname.WALL,
	WorldNickname.FIREBRAND,
	WorldNickname.CALAMITY,
]
## Plain Array rather than PackedFloat32Array: a packed array is a constructor
## call and GDScript will not take one in a `const`.
const TAIL_WEIGHTS := [1.4, 1.2, 1.1, 1.2, 1.0, 1.0, 0.7, 0.5]

## Squad shape when nobody says otherwise: a first eleven, cover everywhere, two
## keepers.
const DEFAULT_SQUAD_ROLES := [
	SimRole.GK, SimRole.CB, SimRole.CB, SimRole.FB, SimRole.FB,
	SimRole.DM, SimRole.CM, SimRole.CM, SimRole.AM,
	SimRole.WIDE, SimRole.WIDE, SimRole.ST, SimRole.ST,
	SimRole.GK, SimRole.CB, SimRole.CM, SimRole.WIDE, SimRole.ST,
]


## The club's level as a quality for `SimAttributes.generate`.
static func quality_for(reputation: float) -> float:
	return lerpf(QUALITY_FLOOR, QUALITY_CEILING, clampf(reputation, 0.0, 1.0))


## One player. `quality` is his own level, already varied off the club's.
static func player(
	rng: SimRng,
	id: int,
	role: int,
	quality: float,
	nation_weights: PackedFloat32Array,
	tail_kind: String = WorldNickname.NONE,
	side: float = 0.0,
	traits_already: Dictionary = {}
) -> WorldPlayer:
	var p := WorldPlayer.new()
	p.id = id
	p.role = role

	var nation := WorldNames.draw_nation(rng, nation_weights)
	var name_parts := WorldNames.draw_name(rng, nation)
	p.first_name = name_parts["first"]
	p.surname = name_parts["last"]
	p.nation = nation
	p.nation_code = name_parts["code"]
	p.country = name_parts["country"]
	p.familiar = WorldNames.familiar(rng, p.first_name, p.surname, nation)

	p.age = _draw_age(rng, tail_kind)
	# A lumpier draw for a tail: he is not merely better, he is uneven, which is
	# what makes him describable.
	var spread := 0.20 if tail_kind != WorldNickname.NONE else 0.12
	p.attrs = SimAttributes.generate(rng, role, quality, spread, side)
	p.height = _draw_height(rng, role, tail_kind)
	p.build = clampf(rng.gauss_clamped(0.5, 0.16, 2.0) + (p.height - HEIGHT_MEAN) * 0.9, 0.05, 0.95)
	# Age first, then the tail. The other way round the curve quietly undoes the
	# thing the man was built to be -- a thirty-three-year-old whippet had his
	# forced 0.93 of pace multiplied back down to 0.85 and stopped being a
	# whippet, so a seed in twelve produced a squad with nobody in it worth
	# describing. What a tail is, he is now.
	_age_curve(p)
	if tail_kind != WorldNickname.NONE:
		_force_tail(rng, p, tail_kind)

	p.appearance_seed = rng.next_u32()
	p.traits = WorldTraits.draw(rng, p.attrs, p.age, WorldTraits.draw_count(rng), traits_already)
	# A firebrand is a temperament as much as a number, and the archetype asks
	# for both. Give him the trait if the draw did not.
	if tail_kind == WorldNickname.FIREBRAND and not p.traits.has(WorldTraits.HOTHEAD):
		p.traits.append(WorldTraits.HOTHEAD)
	# "Local. The crowd knew his name before he made the bench" is not a thing
	# anybody says about a Dutchman the club signed at twenty-three.
	if nation == WorldNames.FOREIGN and p.traits.has(WorldTraits.ACADEMY):
		var without := PackedStringArray()
		for trait_id in p.traits:
			if trait_id != WorldTraits.ACADEMY:
				without.append(trait_id)
		p.traits = without

	p.archetype = WorldNickname.archetype(p.attrs, p.height, p.age, p.traits, role == SimRole.GK)
	p.epithet = WorldNickname.epithet(rng, p.archetype)
	# The body goes into the seed's low bits, because the seed is the only thing
	# about his looks that reaches the figure on screen. `WorldLook` says why.
	# It happens here rather than with the draw above because the body type reads
	# the archetype, and the archetype is not known until the traits are.
	p.appearance_seed = WorldLook.pack_for(p.appearance_seed, p)

	p.condition = rng.range_float(0.92, 1.0)
	p.sharpness = rng.range_float(0.80, 0.98)
	p.morale = rng.range_float(0.40, 0.75)
	p.trust = rng.range_float(0.35, 0.65)
	p.wage = wage_for(quality, p.age)
	p.contract_years = rng.range_int(1, 4)
	p.seasons_here = 0 if p.has_trait(WorldTraits.JOURNEYMAN) else rng.range_int(0, 3)
	return p


## A whole squad for a club, tails included. `roles` defaults to the shape in
## `DEFAULT_SQUAD_ROLES`.
static func squad(
	rng: SimRng,
	reputation: float,
	club_nation: int,
	first_id: int,
	roles: Array = []
) -> Array[WorldPlayer]:
	var shape: Array = roles if not roles.is_empty() else DEFAULT_SQUAD_ROLES
	var weights := WorldNames.nation_weights(club_nation)
	var level := quality_for(reputation)

	# Who the tails are, decided before anybody is drawn so they land anywhere
	# in the squad -- including on the bench, which is funnier and truer.
	var tail_count := rng.range_int(TAILS_PER_SQUAD_MIN, TAILS_PER_SQUAD_MAX)
	var tail_at := {}
	for _i in tail_count:
		var slot := rng.range_int(0, shape.size() - 1)
		if tail_at.has(slot):
			continue
		var kind: String = TAIL_KINDS[rng.weighted_index(PackedFloat32Array(TAIL_WEIGHTS))]
		# A keeper's tail is his own; the outfield kinds do not fit him.
		if shape[slot] == SimRole.GK:
			kind = WorldNickname.GLOVES if rng.chance(0.7) else WorldNickname.CALAMITY
		tail_at[slot] = kind

	var players: Array[WorldPlayer] = []
	var surnames := {}
	var familiars := {}
	# What the squad already is, so the eleventh man is not the third captain.
	var trait_tally := {}
	for i in shape.size():
		var role: int = shape[i]
		var kind: String = tail_at.get(i, WorldNickname.NONE)
		# Squad players are a shade below the eleven, which is what makes a
		# substitution a decision.
		var drop := 0.0 if i < 11 else 0.05
		var individual := clampf(rng.gauss_clamped(level - drop, QUALITY_SPREAD, 2.0), 0.05, 0.98)
		var p := player(rng, first_id + i, role, individual, weights, kind, _side_for(role, rng), trait_tally)
		for trait_id in p.traits:
			trait_tally[trait_id] = int(trait_tally.get(trait_id, 0)) + 1
		# Two Bloomfields in one squad reads as a bug rather than as brothers.
		# The name is redrawn and nothing else is: everything about the man was
		# settled before he was named.
		var guard := 0
		while surnames.has(p.surname) and guard < 8:
			var redraw := WorldNames.draw_name(rng, p.nation)
			p.first_name = redraw["first"]
			p.surname = redraw["last"]
			p.familiar = WorldNames.familiar(rng, p.first_name, p.surname, p.nation)
			guard += 1
		surnames[p.surname] = true
		# Two men called Kev is how it is in a real dressing room and unreadable
		# on a screen. The second falls back to the surname form, and to nothing
		# if that is taken as well.
		if familiars.has(p.familiar):
			p.familiar = WorldNames.familiar(rng, "", p.surname, p.nation)
			if familiars.has(p.familiar):
				p.familiar = ""
		if p.familiar != "":
			familiars[p.familiar] = true
		p.shirt = i + 1
		p.seed_knowledge(rng, rng.range_float(0.55, 0.80))
		players.append(p)
	_cap_epithets(players, tail_at.values())
	return players


## How many men in one squad may be called something other than their surname.
## An epithet everybody has is a surname (§9.7), and the natural draw hands one
## out oftener than the forcing does -- a weak side came out with five.
const EPITHETS_PER_SQUAD_MAX := 3


## Keeps the epithets that were built on purpose, drops the surplus the draw
## threw up, and never lets one squad hold two of the same kind.
##
## `archetype` is left alone: it is the truth about the man and the run layer may
## want it. What is taken away is only what he is *called*.
static func _cap_epithets(players: Array[WorldPlayer], forced: Array) -> void:
	var wanted := forced.duplicate()
	var kept := {}
	var settled := {}
	var count := 0
	# Two passes: the forced tails first, so a natural whippet never takes the
	# place of the one the squad was built around. A man settled in the first
	# pass is skipped in the second -- without that he is looked at twice, and
	# the second look sees his own archetype already taken and rubs his name
	# out, which left whole squads with nobody called anything.
	for pass_forced in [true, false]:
		for p in players:
			if p.epithet == "" or settled.has(p.id):
				continue
			var is_forced: bool = wanted.has(p.archetype)
			if is_forced != pass_forced:
				continue
			settled[p.id] = true
			if kept.has(p.archetype) or count >= EPITHETS_PER_SQUAD_MAX:
				p.epithet = ""
				continue
			kept[p.archetype] = true
			count += 1
			if is_forced:
				wanted.erase(p.archetype)


## A club, squad and all. `reputation` is the club's level, 0..1.
## How many clubs in one division may end with the same word. Six Albions in
## twelve is not a division, it is a draw with no memory.
const SAME_SUFFIX_LIMIT := 2

static func club(
	rng: SimRng,
	id: int,
	reputation: float,
	club_nation: int = WorldNames.ENG,
	taken: Dictionary = {}
) -> WorldClub:
	var c := WorldClub.new()
	c.id = id
	c.nation = club_nation

	# `taken` is the division so far: short names and nicknames already used,
	# and how many clubs have each suffix. Empty for a club drawn on its own.
	var short_names: Dictionary = taken.get("short", {})
	var suffixes: Dictionary = taken.get("suffix", {})
	var nicknames: Dictionary = taken.get("nickname", {})

	c.town = WorldClub.place_name(rng)
	c.short_name = WorldClub.abbreviate(c.town)
	for _i in 12:
		if not short_names.has(c.short_name):
			break
		c.town = WorldClub.place_name(rng)
		c.short_name = WorldClub.abbreviate(c.town)

	var suffix: String = WorldClub.CLUB_SUFFIX[rng.range_int(0, WorldClub.CLUB_SUFFIX.size() - 1)]
	for _i in 12:
		if int(suffixes.get(suffix, 0)) < SAME_SUFFIX_LIMIT:
			break
		suffix = WorldClub.CLUB_SUFFIX[rng.range_int(0, WorldClub.CLUB_SUFFIX.size() - 1)]
	c.name = "%s %s" % [c.town, suffix]

	c.nickname = WorldClub.CLUB_NICKNAMES[rng.range_int(0, WorldClub.CLUB_NICKNAMES.size() - 1)]
	for _i in 12:
		if not nicknames.has(c.nickname):
			break
		c.nickname = WorldClub.CLUB_NICKNAMES[rng.range_int(0, WorldClub.CLUB_NICKNAMES.size() - 1)]

	short_names[c.short_name] = true
	suffixes[suffix] = int(suffixes.get(suffix, 0)) + 1
	nicknames[c.nickname] = true

	c.ground = WorldClub.ground_name(rng, c.town)
	c.capacity = int(lerpf(4000.0, 42000.0, reputation) * rng.range_float(0.8, 1.2))
	c.reputation = reputation

	var primary: Color = SimPalette.KIT_COLOURS[rng.range_int(0, SimPalette.KIT_COLOURS.size() - 1)]
	c.kit = PackedColorArray([primary, SimPalette.CHALK])
	c.away_kit = PackedColorArray([SimPalette.CHALK, primary])

	c.formation = SimFormation.four_three_three()
	c.tactics = SimTactics.balanced()

	c.squad = squad(rng, reputation, club_nation, id * 100, [])
	for p in c.squad:
		p.club_id = id
	assign_shirts(c)

	# Period money, and it should look like it: a small club's whole wage bill
	# is a few thousand a week.
	var bill := 0
	for p in c.squad:
		bill += p.wage
	c.wage_budget = int(bill * rng.range_float(1.05, 1.25))
	c.balance = int(lerpf(60000.0, 3000000.0, reputation) * rng.range_float(0.7, 1.4))
	return c


## Numbers the squad the way the period numbered it: one to eleven is the first
## team in formation order, keeper in one, and everybody else takes what is
## left. A squad number is identity -- the crowd knows the number before the
## name is legible -- so it has to say something about where the man stands.
static func assign_shirts(club: WorldClub) -> void:
	var next := 1
	var given := {}
	for p in club.best_eleven():
		p.shirt = next
		given[p.id] = true
		next += 1
	for p in club.squad:
		if given.has(p.id):
			continue
		p.shirt = next
		next += 1


## A division. Reputations are spread across the band so the table has a shape
## before a ball is kicked; `spread` is how far apart top and bottom are.
static func league(
	rng: SimRng,
	club_count: int,
	centre: float = 0.4,
	spread: float = 0.25,
	club_nation: int = WorldNames.ENG
) -> Array[WorldClub]:
	var clubs: Array[WorldClub] = []
	# Carried from club to club: no two towns, no two nicknames, and no more
	# than `SAME_SUFFIX_LIMIT` clubs ending with the same word.
	var taken := {"short": {}, "suffix": {}, "nickname": {}}
	for i in club_count:
		var t := 0.0 if club_count <= 1 else float(i) / float(club_count - 1)
		# Even along the band, then jittered, so the division is not a ladder.
		var reputation := clampf(centre + (t - 0.5) * spread * 2.0 + rng.gauss(0.0, 0.02), 0.05, 0.95)
		clubs.append(club(rng, i, reputation, club_nation, taken))
	return clubs


## Weekly wage in pounds, from quality and age. Deliberately period: a good
## player at a small club is on a few hundred a week.
static func wage_for(quality: float, age: int) -> int:
	var base := lerpf(90.0, 2600.0, pow(clampf(quality, 0.0, 1.0), 1.8))
	# A teenager is on nothing whatever he is worth; a man past thirty is on
	# what he was worth three years ago.
	var age_factor := 1.0
	if age < 21:
		age_factor = lerpf(0.35, 1.0, float(age - 16) / 5.0)
	elif age > 31:
		age_factor = lerpf(1.0, 0.75, float(age - 31) / 7.0)
	return int(round(base * age_factor / 10.0)) * 10


static func _draw_age(rng: SimRng, tail_kind: String) -> int:
	if tail_kind == WorldNickname.VETERAN:
		return rng.range_int(35, AGE_MAX)
	return clampi(int(round(rng.gauss_clamped(AGE_MEAN, AGE_SPREAD, 2.4))), AGE_MIN, AGE_MAX)


static func _draw_height(rng: SimRng, role: int, tail_kind: String) -> float:
	if tail_kind == WorldNickname.GIANT:
		return rng.range_float(GIANT_HEIGHT, 2.04)
	if tail_kind == WorldNickname.SPRITE:
		return rng.range_float(1.56, SPRITE_HEIGHT)
	# Keepers and centre-halves are picked for height in the first place.
	var mean := HEIGHT_MEAN
	if role == SimRole.GK or role == SimRole.CB:
		mean += 0.05
	return clampf(rng.gauss_clamped(mean, HEIGHT_SPREAD, 2.2), 1.56, 2.04)


## Pushes the attributes a tail is named for into the tail, and takes something
## away in exchange. A man superb at one thing and ordinary at the rest is the
## §9.7 brief; a man superb at one thing and superb at everything else is a
## different game.
static func _force_tail(rng: SimRng, p: WorldPlayer, kind: String) -> void:
	match kind:
		WorldNickname.HAMMER:
			_raise(rng, p.attrs, ["power", "finishing"], 0.90)
			_lower(p.attrs, ["passing", "teamwork"], 0.45)
		WorldNickname.GIANT:
			_raise(rng, p.attrs, ["strength", "jumping", "heading"], 0.88)
			_lower(p.attrs, ["agility", "acceleration", "dribbling"], 0.35)
		WorldNickname.SPRITE:
			_raise(rng, p.attrs, ["agility", "dribbling", "awareness"], 0.88)
			_lower(p.attrs, ["strength", "jumping", "heading"], 0.25)
		WorldNickname.WHIPPET:
			_raise(rng, p.attrs, ["pace", "acceleration"], 0.93)
			_lower(p.attrs, ["decisions", "first_touch"], 0.42)
		WorldNickname.BRAIN:
			_raise(rng, p.attrs, ["decisions", "awareness", "passing"], 0.88)
			_lower(p.attrs, ["pace", "stamina"], 0.38)
		WorldNickname.WALL:
			_raise(rng, p.attrs, ["tackling", "positioning", "strength"], 0.90)
			_lower(p.attrs, ["technique", "dribbling"], 0.30)
		WorldNickname.FIREBRAND:
			_raise(rng, p.attrs, ["aggression", "work_rate"], 0.93)
			_lower(p.attrs, ["composure"], 0.20)
		WorldNickname.GLOVES:
			_raise(rng, p.attrs, ["reflexes", "handling", "command"], 0.90)
			_lower(p.attrs, ["distribution"], 0.40)
		WorldNickname.CALAMITY:
			# Under the bar `WorldNickname.archetype` sets, and under the
			# keeper's as well, because a calamity in goal is a calamity with
			# his hands rather than with his feet.
			_lower(p.attrs, ["first_touch", "composure", "handling", "command"], 0.11)
		_:
			pass


static func _raise(rng: SimRng, attrs: SimAttributes, keys: Array, floor_value: float) -> void:
	for key in keys:
		var v := maxf(float(attrs.get(key)), rng.range_float(floor_value, 0.99))
		attrs.set(key, clampf(v, 0.05, 0.99))


static func _lower(attrs: SimAttributes, keys: Array, ceiling: float) -> void:
	for key in keys:
		attrs.set(key, clampf(minf(float(attrs.get(key)), ceiling), 0.03, 0.99))


## What age does to a body. The mental attributes keep going up long after the
## legs stop, which is the whole reason a thirty-four-year-old is still worth a
## shirt.
static func _age_curve(p: WorldPlayer) -> void:
	var physical_scale := 1.0
	if p.age < 21:
		physical_scale = lerpf(0.86, 1.0, float(p.age - 16) / 5.0)
	elif p.age > 30:
		physical_scale = lerpf(1.0, 0.78, clampf(float(p.age - 30) / 8.0, 0.0, 1.0))
	for key in SimAttributes.PHYSICAL:
		p.attrs.set(key, clampf(float(p.attrs.get(key)) * physical_scale, 0.05, 0.99))

	var mental_shift := 0.0
	if p.age < 22:
		mental_shift = -lerpf(0.10, 0.0, float(p.age - 16) / 6.0)
	elif p.age > 27:
		mental_shift = lerpf(0.0, 0.06, clampf(float(p.age - 27) / 9.0, 0.0, 1.0))
	for key in SimAttributes.MENTAL:
		p.attrs.set(key, clampf(float(p.attrs.get(key)) + mental_shift, 0.05, 0.99))


## Which flank the man is likeliest to stand on, which is all `SimAttributes`
## reads it for -- his foot.
static func _side_for(role: int, rng: SimRng) -> float:
	if role == SimRole.FB or role == SimRole.WIDE:
		return -1.0 if rng.chance(0.5) else 1.0
	return 0.0
