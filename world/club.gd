class_name WorldClub
extends RefCounted
## A club (PLAN.md §8): who plays for it, what it is called, what it is worth
## and what it can pay.
##
## The register is the small club of §9.7 -- a town, a ground with a name, a
## nickname the crowd uses and a board that will not wait. Club names are built
## the way English lower-division names are built: a place, and then one of the
## eight words a football club is allowed to end with.

var id := -1
var name := ""
## Three letters for the scoreboard.
var short_name := ""
## What the crowd calls them: "The Iron", "The Hatters".
var nickname := ""
var town := ""
var nation := WorldNames.ENG
var ground := ""
var capacity := 12000

## 0..1, and the number everything else is drawn against: squad quality, wages,
## what the board expects. A run starts near the bottom of it.
var reputation := 0.35

var balance := 250000
var wage_budget := 12000

var squad: Array[WorldPlayer] = []
var formation: SimFormation = null
var tactics: SimTactics = null
var kit := PackedColorArray([SimPalette.RED, SimPalette.CHALK])
var away_kit := PackedColorArray([SimPalette.CHALK, SimPalette.NAVY])

## What a man is worth in somebody else's shirt. High enough that a good player
## still gets in ahead of a poor specialist, low enough that a settled side
## picks itself.
const OUT_OF_POSITION := 0.82

const PLACE_HEAD := [
	"Ash", "Brack", "Cad", "Dun", "Elms", "Fen", "Grim", "Hollow", "Ick", "Kirk",
	"Lang", "Mar", "Nether", "Ock", "Pen", "Quar", "Rams", "Shel", "Thur", "Upper",
	"Wold", "Yar", "Bram", "Cop", "Dray", "Eller", "Frod", "Gale", "Hex", "Ing",
]
const PLACE_TAIL := [
	"field", "worth", "moor", "haven", "by", "church", "ford", "bridge", "combe",
	"stead", "wick", "thorpe", "dale", "gate", "mouth", "bury", "cester", "ton",
]
const CLUB_SUFFIX := [
	"United", "Town", "City", "Rovers", "Athletic", "Wanderers", "Albion", "County",
]
const CLUB_NICKNAMES := [
	"The Iron", "The Hatters", "The Shakers", "The Bees", "The Cobblers",
	"The Quarrymen", "The Pilgrims", "The Colliers", "The Saddlers", "The Tanners",
	"The Grocers", "The Bantams", "The Terriers", "The Glovers", "The Trawlermen",
	"The Brickies", "The Millers", "The Chairboys", "The Stripes", "The Wasps",
]
const GROUND_TAIL := [
	"Park", "Road", "Lane", "Street", "Terrace", "Ground", "Meadow", "Field", "Hill", "End",
]
const GROUND_HEAD := [
	"Victoria", "Station", "Gas", "Brewery", "Cattle", "Priory", "Albert", "Mill",
	"Chapel", "Quarry", "Shipley", "Dock", "Bell", "Jubilee", "Foundry",
]


static func place_name(rng: SimRng) -> String:
	var head: String = PLACE_HEAD[rng.range_int(0, PLACE_HEAD.size() - 1)]
	var tail: String = PLACE_TAIL[rng.range_int(0, PLACE_TAIL.size() - 1)]
	# "Elms" + "stead" is Elmstead, not Elmsstead: English place names run the
	# two halves together and drop the doubled letter.
	if head.substr(head.length() - 1, 1).to_lower() == tail.substr(0, 1):
		head = head.substr(0, head.length() - 1)
	return head + tail


static func ground_name(rng: SimRng, place: String) -> String:
	var tail := _ground_tail(rng, place)
	# A third of them are named after the town, the way most of them are.
	if rng.chance(0.35):
		return "%s %s" % [place, tail]
	var head: String = GROUND_HEAD[rng.range_int(0, GROUND_HEAD.size() - 1)]
	return "%s %s" % [head, tail]


## A ground word that is not already the town's own ending: Yarfield play at
## Yarfield Park, never at Yarfield Field.
static func _ground_tail(rng: SimRng, place: String) -> String:
	var lower := place.to_lower()
	for _i in 8:
		var tail: String = GROUND_TAIL[rng.range_int(0, GROUND_TAIL.size() - 1)]
		if not lower.ends_with(tail.to_lower()):
			return tail
	return "Park"


## Three letters for the scoreboard, from the town rather than the suffix --
## every club in the division would otherwise be UNI.
static func abbreviate(place: String) -> String:
	return place.substr(0, 3).to_upper()


func size() -> int:
	return squad.size()


func keeper_count() -> int:
	var n := 0
	for p in squad:
		if p.role == SimRole.GK:
			n += 1
	return n


## What the club believes its best side is, in formation-slot order. Sorted by
## `believed_rating` for the slot's role, not by the truth: picking the team is
## a decision made on incomplete information and that is the point of §6.1.
##
## Greedy per slot in formation order, keepers first, and a man is only used
## once. Not optimal -- a manager is not optimal either.
func best_eleven(for_formation: SimFormation = null) -> Array[WorldPlayer]:
	var shape := for_formation if for_formation != null else ensure_formation()
	var used := {}
	var picked: Array[WorldPlayer] = []
	for slot in shape.size():
		var role: int = shape.roles[slot]
		var best: WorldPlayer = null
		var best_score := -1.0
		for p in squad:
			if used.has(p.id):
				continue
			# A keeper in an outfield slot, or the reverse, is never the answer.
			if (role == SimRole.GK) != (p.role == SimRole.GK):
				continue
			# A man out of position is worth less than the same rating suggests,
			# and without this the eleven fills up with whoever scores well on
			# a slot's weights -- a striker at right-back, which is not a
			# selection anybody would make.
			var out_of_position := 1.0 if p.role == role else OUT_OF_POSITION
			var score := p.believed_rating(role) * out_of_position * lerpf(0.85, 1.0, p.condition)
			if score > best_score:
				best_score = score
				best = p
		if best != null:
			used[best.id] = true
			picked.append(best)
	return picked


## Everybody not in `starters`, best first: the bench, in the order a manager
## would reach for them.
func remainder(starters: Array[WorldPlayer]) -> Array[WorldPlayer]:
	var used := {}
	for p in starters:
		used[p.id] = true
	var rest: Array[WorldPlayer] = []
	for p in squad:
		if not used.has(p.id):
			rest.append(p)
	rest.sort_custom(func(a, b): return a.believed_rating() > b.believed_rating())
	return rest


func ensure_formation() -> SimFormation:
	if formation == null:
		formation = SimFormation.four_three_three()
	return formation


func ensure_tactics() -> SimTactics:
	if tactics == null:
		tactics = SimTactics.balanced()
	return tactics


## The club as the match engine wants it. Ids are `team_index * 100 + n` so two
## sides in one match never collide, which is what `SimSquadGen` does too.
func to_sim_team(team_index: int, bench_size: int = 7) -> SimTeam:
	var team := SimTeam.new()
	team.team_index = team_index
	team.formation = ensure_formation()
	team.tactics = ensure_tactics()
	team.club_name = name
	team.short_name = short_name
	team.kit = kit if team_index == SimConsts.TEAM_HOME else away_kit

	var starters := best_eleven(team.formation)
	var next_id := team_index * 100
	for p in starters:
		team.players.append(p.to_sim_player(next_id, team_index))
		next_id += 1
	for p in remainder(starters):
		if team.bench.size() >= bench_size:
			break
		team.bench.append(p.to_sim_player(next_id, team_index))
		next_id += 1
	return team


## The truth about the side, for the abstract league model of §2.5 and for
## nothing a human reads.
func true_rating() -> float:
	var starters := best_eleven()
	if starters.is_empty():
		return 0.0
	var total := 0.0
	for p in starters:
		total += p.attrs.role_rating(p.role)
	return total / float(starters.size())
