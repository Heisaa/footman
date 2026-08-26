class_name SimAppearance
extends RefCounted
## Procedural player appearance from a seed (PLAN.md §9.1).
##
## Mii-style: body type, skin tone, hair mesh and colour, face atlas index,
## accessory. A five-hundred-player database therefore has visual identity
## essentially for free -- and memorable-looking players are what make the
## man-management layer land at all.
##
## This is presentation. The simulation carries only the integer seed and never
## looks at anything in this file.

## Head as a fraction of total height, the bare skull -- hair adds to it, and on
## a full cut it adds about a tenth. Measured off the owner's vinyl reference,
## where skull-to-chin is a third of the figure and the hair takes the silhouette
## past that (`DECISIONS.md`, eleventh). The eighth amendment cut this to 0.27-31
## from a different reference; this one is the squat toy and puts it back.
const HEAD_FRACTION_MIN := 0.31
const HEAD_FRACTION_MAX := 0.35
## How far the head departs from a ball: 1.0 is round, and the two axes are drawn
## apart so a squad has long faces and wide ones. The face quad hangs off the
## head, so it stretches with it -- which is the Mii trick, and free.
## Taller than wide, always. The long axis of the head runs top to bottom, which
## is the way round a head actually is; it was the other way and every figure was
## broad in the face. The variation inside that is small on purpose -- the shape
## of a head is supposed to be noticed second, after the man.
const HEAD_WIDTH_MIN := 0.90
const HEAD_WIDTH_MAX := 1.00
const HEAD_HEIGHT_MIN := 1.02
const HEAD_HEIGHT_MAX := 1.12
## Heights. A squad wants a giant and a small one in it, so the range reaches
## further out than a squad list would and the draw below spends most of its mass
## in the middle anyway.
const HEIGHT_MIN := 1.56
const HEIGHT_MAX := 2.04
const HEIGHT_TYPICAL_MIN := 1.70
const HEIGHT_TYPICAL_MAX := 1.88
## How often a player is drawn from a tail instead of the middle. Roughly one in
## seven: two per squad, which is the point -- an eleven of competent similar men
## is off-register even when every number in it is plausible.
const TAIL_CHANCE := 0.14

## Expressions are swapped wholesale rather than rigged: two dots and a
## simple mouth, swapped for the emotion. They deliver an enormous amount of
## character for almost no cost, so they are used constantly.
enum Face { NEUTRAL, EFFORT, DELIGHT, DESPAIR, ANGER }

## Skin, on a ladder from very pale to very deep. Less saturated and a touch
## pinker than the set this replaces, which ran orange -- the mid tones read as
## terracotta under a bright sun.
const SKIN_TONES := [
	Color("f0d2bd"), Color("e8c6ab"), Color("e3bb99"), Color("d4a179"),
	Color("bf885d"), Color("a26e46"), Color("845736"), Color("684427"),
	Color("4d321d"),
]

## Hair a person could have: black, browns, dark and light blond, ginger, grey
## and white. The table used to carry a teal and a violet, which made half a
## squad look like a bag of sweets.
const HAIR_COLOURS := [
	Color("1c1a1d"), Color("2b2118"), Color("3f2d1e"), Color("5a3a22"),
	Color("6b4423"), Color("8a5a2b"), Color("a8703a"), Color("c08a45"),
	Color("d9b871"), Color("b5561f"), Color("8c3b16"), Color("7a7a7d"),
	Color("b0b0b2"), Color("e3ded3"),
]

## Hair: a shell round the skull, pushed back to open the face. Style 0 is bald.
## The count comes off the library itself, so adding a cut is one line there.
## How far apart in brightness a man's hair and his skin have to be. Below this
## the head reads as one shape and the haircut is only a silhouette.
const HAIR_SKIN_SEPARATION := 0.16
## How often a man's hair is lighter than his face. About one in twelve: enough
## that a squad has one, not so much that it stops being worth noticing.
const LIGHT_HAIR_CHANCE := 0.08
## Beards were here and came out: a sphere on the jaw is a blob whatever size it
## is, and it swallowed the mouth, which is half the expression. Facial hair
## belongs on the drawn face if it comes back at all.
##
## The cap went the same way. Sized to clear a head of hair it covered the whole
## skull in kit colour and read as a hard hat, and no reference wears one.
const ACCESSORIES := ["none", "none", "none", "none", "headband"]

var height := 1.78
var head_fraction := 0.37
## 0 is slight, 1 is heavy. Drives body width only; it has no simulation effect.
var build := 0.5
var skin: Color = SKIN_TONES[0]
var hair_style := 0
var hair_colour: Color = HAIR_COLOURS[0]
var accessory := "none"
var face := Face.NEUTRAL
## Head shape, as scales on the head sphere. Round is 1, 1.
var head_width := 1.0
var head_height := 1.0
## The face he was born with: his brows, his eyes, his mouth -- drawn -- and his
## nose, which is a bump on the head rather than a mark on the texture, because
## that is what the reference art does and a drawn nose reads as a smudge. The
## expression is drawn over the top of the rest rather than replacing it, so a
## heavy-browed man still has heavy brows when he is delighted.
var brow_style := 0
var eye_style := 0
var mouth_style := 0
var nose_style := 0
## Two of the six figures in the reference wear a moustache, so a fair number of
## a squad should. The style is an index into the model's `MoustacheNN` set:
## 0 chevron, 1 walrus, 2 horseshoe; -1 is clean-shaven.
var moustache_style := -1
## The beard, `BeardNN`: 0 goatee, 1 full short beard, 2 stubble; -1 none.
## `_face_hair` pairs the two the way the era did.
var beard_style := -1
## True when there is a moustache at all; the primitive figure draws one shape.
var moustache: bool:
	get:
		return moustache_style >= 0
## The nose is the man's own skin a shade warmer, not a colour of its own --
## the toy reference has plain noses. Derived rather than drawn from a table so
## it holds up across the skin tones: a pale pink button on a dark face reads as
## a mistake. `_nose_colour` has the amount.
var nose_colour: Color = SKIN_TONES[0]
## Sleeve length, socks pulled up, and so on: tiny variations that make a squad
## look like a group of individuals rather than a clone army.
var sleeves_long := false
var socks_high := true


## Builds an appearance deterministically from a seed. The same seed always
## gives the same player, which is what lets the world layer store six bytes
## instead of a wardrobe.
static func from_seed(seed_value: int) -> SimAppearance:
	var a := SimAppearance.new()
	var rng := SimRng.new(seed_value)
	a.height = _height(rng)
	a.head_fraction = lerpf(HEAD_FRACTION_MIN, HEAD_FRACTION_MAX, rng.unit_float())
	# A bell rather than a flat draw, then pushed by height: the giant is built
	# like one and the small one is not a wide man who happens to be short.
	a.build = clampf(
		(rng.unit_float() + rng.unit_float()) * 0.5 + (a.height - 1.78) * 0.9, 0.0, 1.0)
	# A heavy man gets a wider head, but not by much -- the draw does most of it.
	a.head_width = clampf(
		lerpf(HEAD_WIDTH_MIN, HEAD_WIDTH_MAX, rng.unit_float()) + (a.build - 0.5) * 0.08,
		HEAD_WIDTH_MIN, HEAD_WIDTH_MAX)
	a.head_height = lerpf(HEAD_HEIGHT_MIN, HEAD_HEIGHT_MAX, rng.unit_float())
	a.skin = SKIN_TONES[rng.range_int(0, SKIN_TONES.size() - 1)]
	a.hair_style = rng.range_int(0, SimCharacterBuilder.HAIR_LIBRARY.size() - 1)
	a.hair_colour = _hair_colour(rng, a.skin)
	a.accessory = ACCESSORIES[rng.range_int(0, ACCESSORIES.size() - 1)]
	a.brow_style = rng.range_int(0, SimFaceAtlas.BROW_STYLES.size() - 1)
	a.eye_style = rng.range_int(0, SimFaceAtlas.EYE_STYLES.size() - 1)
	a.mouth_style = rng.range_int(0, SimFaceAtlas.MOUTH_STYLES.size() - 1)
	a.nose_style = rng.range_int(0, SimCharacterBuilder.NOSE_LIBRARY.size() - 1)
	a.nose_colour = _nose_colour(a.skin, rng)
	# A button is the man's own skin, always: a ball a shade redder than the
	# face is a clown's, where a bridged nose can carry the warmth.
	var nose_row: Array = SimCharacterBuilder.NOSE_LIBRARY[a.nose_style]
	if float(nose_row[1]) <= 0.0:
		a.nose_colour = a.skin
	_face_hair(a, rng)
	a.sleeves_long = rng.chance(0.75)
	a.socks_high = rng.chance(0.8)
	a.face = Face.NEUTRAL
	return a


## Moustache and beard together, because the era paired them: a moustache on
## its own is the eighties, a goatee on its own the nineties, a full beard
## takes a moustache nearly always, and only a chevron sits over a goatee.
## Stubble goes under anything.
static func _face_hair(a: SimAppearance, rng: SimRng) -> void:
	var b := rng.unit_float()
	if b < 0.12:
		a.beard_style = 2    # stubble
	elif b < 0.24:
		a.beard_style = 0    # goatee
	elif b < 0.33:
		a.beard_style = 1    # full
	var m := rng.unit_float()
	var pick := rng.unit_float()
	match a.beard_style:
		1:
			if m < 0.85:
				a.moustache_style = [0, 1, 2][int(pick * 3.0) % 3]
		0:
			if m < 0.5:
				a.moustache_style = 0
		_:
			if m < 0.25:
				# The chevron twice: it was on half the league.
				a.moustache_style = [0, 0, 1, 2][int(pick * 4.0) % 4]


## A man's hair: drawn from the table, then held darker than his face unless he
## is one of the few it is not.
##
## Hair lighter than skin is a real thing and a striking one -- a blond or a
## white-haired man with a deep skin is a face you remember. It is also rare, and
## a squad where a third of the men have it looks like fancy dress. The draw is
## kept, so a pale man still gets the full table; it is only overruled when the
## hair came out lighter than the face, and then only most of the time.
static func _hair_colour(rng: SimRng, skin: Color) -> Color:
	var hair: Color = HAIR_COLOURS[rng.range_int(0, HAIR_COLOURS.size() - 1)]
	if hair.get_luminance() > skin.get_luminance() and not rng.chance(LIGHT_HAIR_CHANCE):
		hair = _darker_than(skin, rng)
	return _separate_hair(hair, skin)


## A hair colour darker than the given skin. The deepest skins have only the
## blacks under them, which is the right answer for them anyway.
static func _darker_than(skin: Color, rng: SimRng) -> Color:
	var below := []
	for candidate in HAIR_COLOURS:
		if (candidate as Color).get_luminance() < skin.get_luminance():
			below.append(candidate)
	if below.is_empty():
		return HAIR_COLOURS[0]
	return below[rng.range_int(0, below.size() - 1)]


## Hair, moved clear of the skin it sits on.
##
## The two tables are drawn from independently, so nothing stopped white hair
## landing on the palest skin or black on the deepest -- and a head whose hair
## and face are the same brightness is one shape, not two. The hair is pushed
## further the way it already leans, so black stays black and white stays white
## and the man keeps the hair he was given; it only flips when that end has run
## out of room.
##
## Brightness, not hue: a dark blond on a mid skin has to separate, and turning
## it green would separate it.
static func _separate_hair(hair: Color, skin: Color) -> Color:
	var on_skin := skin.get_luminance()
	var lum := hair.get_luminance()
	if absf(lum - on_skin) >= HAIR_SKIN_SEPARATION:
		return hair
	var below := on_skin - HAIR_SKIN_SEPARATION
	var above := on_skin + HAIR_SKIN_SEPARATION
	var darker := lum <= on_skin
	if darker and below < 0.03:
		darker = false
	elif not darker and above > 0.98:
		darker = true
	if darker:
		return hair.darkened(clampf(1.0 - below / maxf(lum, 0.001), 0.0, 0.94))
	return hair.lightened(clampf((above - lum) / maxf(1.0 - lum, 0.001), 0.0, 0.94))


## The nose, from the man's own skin to a shade darker and warmer than it. The
## owner's toy reference has plain skin-coloured noses, so most are just that;
## the rest lean towards a warm red, never far enough to read as a clown's, and
## the further they lean the darker they go.
static func _nose_colour(skin: Color, rng: SimRng) -> Color:
	# How far off the skin this nose is. Squared so plain noses are the common
	# case and the warmest is the tail.
	var t := rng.unit_float()
	t = t * t
	# The hue runs from just short of a full turn (pink) to a warm orange-red.
	# Written as a signed offset and wrapped, because lerping 0.99 to 0.045 the
	# long way round passes through green.
	var hue: float = fposmod(lerpf(-0.01, 0.03, rng.unit_float()), 1.0)
	var target := Color.from_hsv(
		hue,
		clampf(skin.s * 1.1 + 0.08, 0.2, 0.5),
		clampf(skin.v * lerpf(1.0, 0.88, t), 0.0, 1.0))
	return skin.lerp(target, t * 0.3)


## Height: mostly the middle of a squad list, sometimes a tail. The middle is the
## average of two draws, so it clusters; the tail is a flat draw into the space
## beyond it, so the giant is as likely to be 2.04 as 1.90.
static func _height(rng: SimRng) -> float:
	if rng.chance(TAIL_CHANCE):
		if rng.chance(0.5):
			return lerpf(HEIGHT_MIN, HEIGHT_TYPICAL_MIN, rng.unit_float())
		return lerpf(HEIGHT_TYPICAL_MAX, HEIGHT_MAX, rng.unit_float())
	var bell := (rng.unit_float() + rng.unit_float()) * 0.5
	return lerpf(HEIGHT_TYPICAL_MIN, HEIGHT_TYPICAL_MAX, bell)


## Head radius in metres, from the height and the head fraction.
func head_radius() -> float:
	return height * head_fraction * 0.5


## Body width multiplier, so a heavy build reads as chunky rather than tall.
func body_width() -> float:
	return lerpf(0.76, 1.30, build)


## Which face to show for a simulation animation hint. The sim never asks for an
## expression; presentation infers one, which keeps the two layers apart.
static func face_for_anim(anim: int, stamina: float) -> int:
	match anim:
		SimConsts.Anim.CELEBRATE:
			return Face.DELIGHT
		SimConsts.Anim.DEJECTED, SimConsts.Anim.FALL:
			return Face.DESPAIR
		SimConsts.Anim.SLIDE, SimConsts.Anim.KICK_HARD, SimConsts.Anim.HEADER:
			return Face.EFFORT
		SimConsts.Anim.CHEST:
			# Not effort: a chest-down is a man concentrating, not straining.
			return Face.NEUTRAL
		SimConsts.Anim.EXHAUSTED:
			return Face.EFFORT
		_:
			# Fatigue shows on the face before it shows anywhere else.
			return Face.EFFORT if stamina < 0.35 else Face.NEUTRAL


## A two- or three-colour kit palette for a club, drawn from the master palette
## so the game stays coherent and can be re-skinned per competition.
static func kit_for(primary: Color) -> PackedColorArray:
	# Shirt, trim, shorts. The trim is the collar V, the cuffs, the sock hoops
	# and the boot stripes, and `SimPalette.trim_for` says why it is white on
	# almost every shirt rather than whichever of black and white contrasts.
	# The shorts are free to be a colour.
	return PackedColorArray([
		primary, SimPalette.trim_for(primary), SimPalette.shorts_for(primary)])


## Picks an away kit that will not be mistaken for the home one.
static func away_kit(home: Color, seed_value: int) -> PackedColorArray:
	var rng := SimRng.new(seed_value)
	for attempt in 12:
		var candidate: Color = SimPalette.KIT_COLOURS[rng.range_int(0, SimPalette.KIT_COLOURS.size() - 1)]
		if not SimPalette.kits_clash(home, candidate):
			return kit_for(candidate)
	return kit_for(SimPalette.CHALK)
