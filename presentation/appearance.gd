class_name SimAppearance
extends RefCounted
## Procedural player appearance from a seed (PLAN.md §9.3).
##
## Mii-style: body type, skin tone, hair mesh and colour, face atlas index,
## accessory. A five-hundred-player database therefore has visual identity
## essentially for free -- and memorable-looking players are what make the
## man-management layer land at all.
##
## This is presentation. The simulation carries only the integer seed and never
## looks at anything in this file.

## Head as a fraction of total height. §9.3 asked for 35-40%; the owner cut it
## (see `DECISIONS.md`). It lengthens the body, which is what carries a stride,
## and it is still far above the three-heads-plus-a-bit of a real man, so the
## face stays legible at match distance.
const HEAD_FRACTION_MIN := 0.30
const HEAD_FRACTION_MAX := 0.35
## How far the head departs from a ball: 1.0 is round, and the two axes are drawn
## apart so a squad has long faces and wide ones. The face quad hangs off the
## head, so it stretches with it -- which is the Mii trick, and free.
const HEAD_WIDTH_MIN := 0.90
const HEAD_WIDTH_MAX := 1.12
const HEAD_HEIGHT_MIN := 0.88
const HEAD_HEIGHT_MAX := 1.14
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

## Expressions are swapped wholesale rather than rigged. §9.3: two dots and a
## simple mouth, swapped for the emotion. They deliver an enormous amount of
## character for almost no cost, so they are used constantly.
enum Face { NEUTRAL, EFFORT, DELIGHT, DESPAIR, ANGER }

const SKIN_TONES := [
	Color("f6d7ba"), Color("edbf98"), Color("dda173"), Color("c07f52"),
	Color("9c5f38"), Color("6f4227"), Color("4a2c1b"), Color("fae3cd"),
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
const HAIR_STYLES := 14
## Beards were here and came out: a sphere on the jaw is a blob whatever size it
## is, and it swallowed the mouth, which is half the expression. Facial hair
## belongs on the drawn face if it comes back at all.
const ACCESSORIES := ["none", "none", "none", "none", "headband", "cap"]

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
## The nose is a warmer, redder version of the man's own skin -- the reference
## art gives every figure a pink one. Derived rather than drawn from a table so
## it holds up across the skin tones: a pale pink button on a dark face reads as
## a mistake.
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
	a.hair_style = rng.range_int(0, HAIR_STYLES - 1)
	a.hair_colour = HAIR_COLOURS[rng.range_int(0, HAIR_COLOURS.size() - 1)]
	a.accessory = ACCESSORIES[rng.range_int(0, ACCESSORIES.size() - 1)]
	a.brow_style = rng.range_int(0, SimFaceAtlas.BROW_STYLES.size() - 1)
	a.eye_style = rng.range_int(0, SimFaceAtlas.EYE_STYLES.size() - 1)
	a.mouth_style = rng.range_int(0, SimFaceAtlas.MOUTH_STYLES.size() - 1)
	a.nose_style = rng.range_int(0, SimCharacterBuilder.NOSE_LIBRARY.size() - 1)
	a.nose_colour = _nose_colour(a.skin, rng)
	a.sleeves_long = rng.chance(0.75)
	a.socks_high = rng.chance(0.8)
	a.face = Face.NEUTRAL
	return a


## A ruddy version of a skin tone: hue pulled round to pink or warm red,
## saturation lifted, value left roughly where it was, then mixed back into the
## skin by an amount that varies per player. Some men get a faint warmth and some
## get a proper red nose.
static func _nose_colour(skin: Color, rng: SimRng) -> Color:
	# The hue runs from just short of a full turn (pink) to a warm orange-red.
	# Written as a signed offset and wrapped, because lerping 0.99 to 0.045 the
	# long way round passes through green.
	var hue: float = fposmod(lerpf(-0.015, 0.045, rng.unit_float()), 1.0)
	var target := Color.from_hsv(
		hue,
		clampf(skin.s * 1.15 + 0.2, 0.0, 0.62),
		clampf(skin.v * 1.03, 0.0, 1.0))
	# The top of this range was 0.85 and it produced a circus nose. A red nose is
	# a man who has been out in the cold, not a clown.
	return skin.lerp(target, rng.range_float(0.3, 0.62))


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
		SimConsts.Anim.EXHAUSTED:
			return Face.EFFORT
		_:
			# Fatigue shows on the face before it shows anywhere else.
			return Face.EFFORT if stamina < 0.35 else Face.NEUTRAL


## A two- or three-colour kit palette for a club, drawn from the master palette
## so the game stays coherent and can be re-skinned per competition.
static func kit_for(primary: Color) -> PackedColorArray:
	return PackedColorArray([primary, SimPalette.contrast_for(primary), SimPalette.INK])


## Picks an away kit that will not be mistaken for the home one.
static func away_kit(home: Color, seed_value: int) -> PackedColorArray:
	var rng := SimRng.new(seed_value)
	for attempt in 12:
		var candidate: Color = SimPalette.KIT_COLOURS[rng.range_int(0, SimPalette.KIT_COLOURS.size() - 1)]
		if not SimPalette.kits_clash(home, candidate):
			return kit_for(candidate)
	return kit_for(SimPalette.CHALK)
