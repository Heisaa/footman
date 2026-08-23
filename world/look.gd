class_name WorldLook
extends RefCounted
## How a man's body gets from the record to the figure on screen (PLAN.md §9.1).
##
## The problem this solves: `appearance_seed` is the **only** thing about a
## player's looks that travels into the match. `SimPlayer` carries no height and
## no build -- the simulation does not read either -- so a record saying 2.04 m
## reached a presentation layer that derived its own height from the seed and
## drew an ordinary man. The giant was a giant in his attributes and nowhere
## else.
##
## So the body rides **in the seed's low bits**. Twelve of the thirty-two are
## given over to the body type, the height and the build; the other twenty stay
## free entropy for hair, skin and face, which is a million faces and plenty.
## Nothing in `sim/` changes, no side table has to be kept in step, and a seed is
## still one integer a caption can print and a person can type back in.
##
## An unpacked seed -- one from `SimSquadGen`, or any seed written before this --
## has the flag bit clear and presentation falls back to deriving a body from it,
## which is exactly what it did before. Old seeds keep drawing the same men.

# --- Body types -------------------------------------------------------------
#
# Five silhouettes rather than a continuous range, because the models are hand
# built in Blender: five bodies with height scaled on top is a week of work and
# a continuous morph target is a month of it. The archetype picks the body, so
# the man the squad was built around is the man whose shape you notice.

const STANDARD := 0
const GIANT := 1
const SPRITE := 2
const HEAVY := 3
const LEAN := 4

const TYPE_NAMES := ["standard", "giant", "sprite", "heavy", "lean"]

## Where the ordinary man stops being ordinary. Only the two extremes come from
## the archetype; these two come from the body he was drawn with.
const HEAVY_BUILD := 0.66
const LEAN_BUILD := 0.34

# --- Bit layout -------------------------------------------------------------
#
#   bits  0-2   body type      0-7
#   bits  3-7   height bucket  0-31 across HEIGHT_MIN..HEIGHT_MAX, about 1.5 cm
#   bits  8-10  build bucket   0-7
#   bits 11-18  tag            a fixed byte, so a seed that carries no body is
#                              recognised as carrying none
#   bits 19-31  free entropy for everything presentation invents
#
# **The tag is eight bits and not one.** A single flag bit is set in half of all
# the seeds that were never packed -- `SimSquadGen` draws a flat u32 for every
# test squad -- so half of those men would have had a body read out of noise:
# heights flat across the whole range instead of drawn round 1.79. A byte gets
# that to one seed in 256, and the thirteen bits left over are more variety than
# the hair and nose libraries can express anyway.

const TYPE_SHIFT := 0
const TYPE_MASK := 0x7
const HEIGHT_SHIFT := 3
const HEIGHT_MASK := 0x1F
const BUILD_SHIFT := 8
const BUILD_MASK := 0x7
const TAG_SHIFT := 11
const TAG_MASK := 0xFF
const TAG := 0xA7
const BODY_MASK := 0x7FFFF

const HEIGHT_MIN := 1.56
const HEIGHT_MAX := 2.04


static func type_name(body_type: int) -> String:
	return TYPE_NAMES[clampi(body_type, 0, TYPE_NAMES.size() - 1)]


## Which of the five bodies this man is. The archetype wins where it has an
## opinion, because it is the thing the squad was built around; otherwise the
## build decides, and most men are standard.
static func body_type_for(archetype: String, height: float, build: float) -> int:
	if archetype == WorldNickname.GIANT or height >= 1.94:
		return GIANT
	if archetype == WorldNickname.SPRITE or height <= 1.66:
		return SPRITE
	if build >= HEAVY_BUILD:
		return HEAVY
	if build <= LEAN_BUILD:
		return LEAN
	return STANDARD


## Writes the body into a seed, keeping its free bits. Returns the new seed.
static func pack(seed_value: int, body_type: int, height: float, build: float) -> int:
	var height_bucket := int(round(clampf(
		(height - HEIGHT_MIN) / (HEIGHT_MAX - HEIGHT_MIN), 0.0, 1.0) * float(HEIGHT_MASK)))
	var build_bucket := int(round(clampf(build, 0.0, 1.0) * float(BUILD_MASK)))
	var bits := (clampi(body_type, 0, TYPE_MASK) << TYPE_SHIFT) \
		| (height_bucket << HEIGHT_SHIFT) \
		| (build_bucket << BUILD_SHIFT) \
		| (TAG << TAG_SHIFT)
	return (seed_value & ~BODY_MASK) | bits


## The same, for a generated player: reads his own record.
static func pack_for(seed_value: int, player: WorldPlayer) -> int:
	return pack(seed_value, body_type_for(player.archetype, player.height, player.build),
		player.height, player.build)


## Does this seed carry a body, or is it one presentation has to invent?
static func is_packed(seed_value: int) -> bool:
	return ((seed_value >> TAG_SHIFT) & TAG_MASK) == TAG


static func body_type_of(seed_value: int) -> int:
	return (seed_value >> TYPE_SHIFT) & TYPE_MASK


## Height in metres, to about a centimetre and a half. Returns 0.0 for an
## unpacked seed, which is the caller's signal to derive one.
static func height_of(seed_value: int) -> float:
	if not is_packed(seed_value):
		return 0.0
	var bucket := (seed_value >> HEIGHT_SHIFT) & HEIGHT_MASK
	return lerpf(HEIGHT_MIN, HEIGHT_MAX, float(bucket) / float(HEIGHT_MASK))


## Build 0..1, to an eighth. Returns -1.0 for an unpacked seed.
static func build_of(seed_value: int) -> float:
	if not is_packed(seed_value):
		return -1.0
	return float((seed_value >> BUILD_SHIFT) & BUILD_MASK) / float(BUILD_MASK)
