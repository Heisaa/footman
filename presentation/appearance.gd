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
## (see `DECISIONS.md`). Four heads to a figure is a toy, five is a comic strip:
## it lengthens the body, which is what carries a stride and a shoulder charge,
## and it is still far above the three-heads-plus-a-bit of a real footballer, so
## the face stays legible at match distance.
const HEAD_FRACTION_MIN := 0.30
const HEAD_FRACTION_MAX := 0.35
## Heights. §9.7 wants archetypes rather than averages -- Hamish is enormous,
## Mouse is tiny -- so the range reaches further out than a squad list would and
## the draw below spends most of its mass in the middle anyway.
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

const HAIR_COLOURS := [
	Color("221d26"), Color("3a2a1e"), Color("6b4423"), Color("a8703a"),
	Color("d9a441"), Color("e8e0d0"), Color("8a8f98"), Color("c4523f"),
	Color("5b4a8a"), Color("3fa88a"),
]

## Single-piece meshes drawn from a small library, chosen by index.
const HAIR_STYLES := 8
## The moustache is in twice because it is the era's own face, and glasses are
## in because Mighty Mouse wore them: the accessory table is where a squad gets
## its four-word men, so it is weighted for the register rather than evenly.
const ACCESSORIES := [
	"none", "none", "none", "headband", "cap", "beard", "beard_full",
	"glasses", "moustache", "moustache",
]

var height := 1.78
var head_fraction := 0.37
## 0 is slight, 1 is heavy. Drives body width only; it has no simulation effect.
var build := 0.5
var skin: Color = SKIN_TONES[0]
var hair_style := 0
var hair_colour: Color = HAIR_COLOURS[0]
var accessory := "none"
var face := Face.NEUTRAL
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
	a.skin = SKIN_TONES[rng.range_int(0, SKIN_TONES.size() - 1)]
	a.hair_style = rng.range_int(0, HAIR_STYLES - 1)
	a.hair_colour = HAIR_COLOURS[rng.range_int(0, HAIR_COLOURS.size() - 1)]
	a.accessory = ACCESSORIES[rng.range_int(0, ACCESSORIES.size() - 1)]
	a.sleeves_long = rng.chance(0.75)
	a.socks_high = rng.chance(0.8)
	a.face = Face.NEUTRAL
	return a


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
