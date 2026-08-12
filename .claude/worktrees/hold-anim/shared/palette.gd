class_name SimPalette
extends RefCounted
## The master palette (PLAN.md §9.3).
##
## Twenty colours, bold and non-naturalistic, shared by kits, pitch, interface
## and backgrounds so the game reads as one object and can be re-skinned per
## competition. Nothing in the game should introduce a colour that is not here.

const INK := Color("221d26")
const PAPER := Color("fdf4e3")

const RED := Color("e8443c")
const CORAL := Color("f4776b")
const SALMON := Color("f79a86")
const ORANGE := Color("f2913a")
const AMBER := Color("f6c445")
const LEMON := Color("f0e35b")
const LIME := Color("a8cf46")
const GRASS := Color("5cb15a")
const PINE := Color("2f7d55")
const TEAL := Color("3fb0a4")
const SKY := Color("52aee0")
const BLUE := Color("3b6fce")
const NAVY := Color("2b3f7a")
const VIOLET := Color("7b5bc4")
const PLUM := Color("a8479b")
const PINK := Color("ef7fb4")
const BROWN := Color("8a5a3b")
const SAND := Color("d9b787")
const SLATE := Color("6b7a8f")
const CHALK := Color("f2f2ee")

const ALL := [
	INK, PAPER, RED, CORAL, SALMON, ORANGE, AMBER, LEMON, LIME, GRASS,
	PINE, TEAL, SKY, BLUE, NAVY, VIOLET, PLUM, PINK, BROWN, SAND, SLATE, CHALK,
]

## Colours a kit may use. Excludes the pitch greens and the line white so kits
## always separate from the background.
const KIT_COLOURS := [RED, CORAL, ORANGE, AMBER, LEMON, TEAL, SKY, BLUE, NAVY, VIOLET, PLUM, PINK, BROWN, SLATE, INK]

## Backgrounds behind the stadium: bold flat colour, the warm salmon register of
## the reference images.
const BACKDROPS := [SALMON, CORAL, AMBER, SKY, VIOLET, TEAL, LIME]


## A contrasting second kit colour for the given primary.
static func contrast_for(primary: Color) -> Color:
	return INK if primary.get_luminance() > 0.45 else CHALK


## True if two kits are too close to tell apart at a glance.
static func kits_clash(a: Color, b: Color) -> bool:
	var dh := absf(a.h - b.h)
	dh = minf(dh, 1.0 - dh)
	return dh < 0.08 and absf(a.get_luminance() - b.get_luminance()) < 0.2
