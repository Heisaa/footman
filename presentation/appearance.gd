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

## Head as a fraction of total height. §9.3 asks for 35-40%.
const HEAD_FRACTION_MIN := 0.35
const HEAD_FRACTION_MAX := 0.40
const HEIGHT_MIN := 1.62
const HEIGHT_MAX := 1.95

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
const ACCESSORIES := ["none", "none", "none", "headband", "cap", "beard", "beard_full", "glasses"]

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
	a.height = lerpf(HEIGHT_MIN, HEIGHT_MAX, rng.unit_float())
	a.head_fraction = lerpf(HEAD_FRACTION_MIN, HEAD_FRACTION_MAX, rng.unit_float())
	a.build = rng.unit_float()
	a.skin = SKIN_TONES[rng.range_int(0, SKIN_TONES.size() - 1)]
	a.hair_style = rng.range_int(0, HAIR_STYLES - 1)
	a.hair_colour = HAIR_COLOURS[rng.range_int(0, HAIR_COLOURS.size() - 1)]
	a.accessory = ACCESSORIES[rng.range_int(0, ACCESSORIES.size() - 1)]
	a.sleeves_long = rng.chance(0.75)
	a.socks_high = rng.chance(0.8)
	a.face = Face.NEUTRAL
	return a


## Head radius in metres, from the height and the head fraction.
func head_radius() -> float:
	return height * head_fraction * 0.5


## Body width multiplier, so a heavy build reads as chunky rather than tall.
func body_width() -> float:
	return lerpf(0.82, 1.22, build)


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
