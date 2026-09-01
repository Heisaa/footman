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
## So the body rides **in the seed's low bits**, and so does everything else the
## record knows that the face should answer to: his age, his complexion, the
## colour family of his hair, and the archetype the squad was built around.
## Nothing in `sim/` changes, no side table has to be kept in step, and a seed is
## still one integer a caption can print and a person can type back in.
##
## The world draws the facts only it can know -- complexion and hair family come
## off the nation and the country, which the seed cannot carry -- and
## presentation turns them into a skin tone, a colour, a cut and a moustache.
## `SimAppearance.from_seed` is where that happens.
##
## An unpacked seed -- one from `SimSquadGen`, or any seed written before this --
## has the flag bit clear and presentation falls back to deriving a body from it,
## which is exactly what it did before. Old seeds keep drawing the same men.

# --- Body types -------------------------------------------------------------
#
# Silhouettes rather than a continuous range, because the models are hand
# built in Blender. The build decides which: skinny, regular, chubby or buff,
# and height is scaled on top, so a tall man can be any of them -- the beanpole
# and the ox are both here. Giant and sprite were bodies once, picked by height;
# they are indices still, so an old seed reads, but nothing is made one now:
# height is a number the nickname reads afterwards, not a shape.

const STANDARD := 0
const GIANT := 1
const SPRITE := 2
const HEAVY := 3
const LEAN := 4
const BUFF := 5

const TYPE_NAMES := ["standard", "giant", "sprite", "heavy", "lean", "buff"]

## Where the ordinary man stops being ordinary, on the build; and above
## `HEAVY_BUILD`, how strong he has to be for the bulk to be muscle.
const HEAVY_BUILD := 0.66
const LEAN_BUILD := 0.34
const BUFF_STRENGTH := 0.62

# --- Bit layout -------------------------------------------------------------
#
#   bits  0-2   body type      0-7
#   bits  3-7   height bucket  0-31 across HEIGHT_MIN..HEIGHT_MAX, about 1.5 cm
#   bits  8-10  build bucket   0-7
#   bits 11-18  tag            a fixed byte, so a seed that carries no body is
#                              recognised as carrying none
#   bits 19-20  complexion     FAIR, MEDIUM, DEEP
#   bits 21-22  hair family    DARK, BROWN, FAIR_HAIR, GINGER
#   bits 23-24  age band       YOUNG, PRIME, THIRTIES, VETERAN
#   bits 25-28  archetype      index into ARCHETYPES, 0 is none
#   bits 29-31  free entropy
#
# **Three free bits is not three bits of variety.** `SimAppearance.from_seed`
# seeds its RNG with the whole integer, so two men draw the same face only when
# every field above agrees as well: the same height to a centimetre and a half,
# the same build, age band, complexion, hair family and archetype. Packing a new
# field re-rolls every packed man's face, which is free until a world is saved
# and a decision after that.
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

const COMPLEXION_SHIFT := 19
const COMPLEXION_MASK := 0x3
const HAIR_SHIFT := 21
const HAIR_MASK := 0x3
const AGE_SHIFT := 23
const AGE_MASK := 0x3
const ARCHETYPE_SHIFT := 25
const ARCHETYPE_MASK := 0xF
const LOOK_MASK := 0x1FFFFFFF

# --- Complexion --------------------------------------------------------------
#
# Three bands, not a tone: the tone is presentation's ladder and it may change.
# The band is what the register knows -- an English league of 1985 to 1995 is
# mostly fair, with one or two Black players in most squads, and a man from
# Accra is not drawn off the same table as a man from Oslo.

const FAIR := 0
const MEDIUM := 1
const DEEP := 2
const COMPLEXION_NAMES := ["fair", "medium", "deep"]

## Fair, medium, deep -- by the four home nations, then by foreign country code.
## Unlisted countries take the "" row.
const COMPLEXION_WEIGHTS := {
	WorldNames.ENG: [0.86, 0.04, 0.10],
	WorldNames.SCO: [0.94, 0.02, 0.04],
	WorldNames.WAL: [0.94, 0.02, 0.04],
	WorldNames.IRL: [0.95, 0.02, 0.03],
	"NOR": [0.97, 0.03, 0.0], "SWE": [0.97, 0.03, 0.0], "DEN": [0.97, 0.03, 0.0],
	"ISL": [0.99, 0.01, 0.0], "NED": [0.90, 0.05, 0.05], "POL": [0.96, 0.04, 0.0],
	"YUG": [0.75, 0.25, 0.0],
	"GHA": [0.0, 0.04, 0.96], "NGA": [0.0, 0.04, 0.96],
	"": [0.80, 0.12, 0.08],
}

# --- Hair family -------------------------------------------------------------

const DARK := 0
const BROWN := 1
const FAIR_HAIR := 2
const GINGER := 3
const HAIR_NAMES := ["dark", "brown", "fair", "ginger"]

## Dark, brown, fair, ginger. The Scots and the Irish carry the ginger; the
## Scandinavians the fair. A deep complexion is dark whatever the table says.
const HAIR_WEIGHTS := {
	WorldNames.ENG: [0.34, 0.46, 0.15, 0.05],
	WorldNames.SCO: [0.34, 0.40, 0.13, 0.13],
	WorldNames.WAL: [0.42, 0.42, 0.11, 0.05],
	WorldNames.IRL: [0.40, 0.36, 0.10, 0.14],
	"NOR": [0.15, 0.35, 0.48, 0.02], "SWE": [0.15, 0.35, 0.48, 0.02],
	"DEN": [0.18, 0.37, 0.43, 0.02], "ISL": [0.15, 0.35, 0.45, 0.05],
	"NED": [0.25, 0.45, 0.28, 0.02], "POL": [0.30, 0.50, 0.19, 0.01],
	"YUG": [0.60, 0.36, 0.04, 0.0],
	"": [0.50, 0.35, 0.12, 0.03],
}

# --- Age band ----------------------------------------------------------------
#
# Four bands, because four is what a face shows: the boy, the pro, the man
# going grey at the temples, and the one the crowd calls old.

const YOUNG := 0
const PRIME := 1
const THIRTIES := 2
const VETERAN := 3
const AGE_NAMES := ["young", "prime", "thirties", "veteran"]

# --- Archetype ---------------------------------------------------------------
#
# The order is the index in the seed. Append; never reorder.
const ARCHETYPES := [
	WorldNickname.NONE, WorldNickname.HAMMER, WorldNickname.GIANT,
	WorldNickname.SPRITE, WorldNickname.WHIPPET, WorldNickname.BRAIN,
	WorldNickname.WALL, WorldNickname.GLOVES, WorldNickname.FIREBRAND,
	WorldNickname.VETERAN, WorldNickname.CALAMITY,
]

const HEIGHT_MIN := 1.56
const HEIGHT_MAX := 2.04


static func type_name(body_type: int) -> String:
	return TYPE_NAMES[clampi(body_type, 0, TYPE_NAMES.size() - 1)]


## Which body this man is: the build decides, and at the heavy end his strength
## says whether it is muscle or dinner. `archetype` and `height` are taken and
## ignored, so every caller reads the same way; the nickname is downstream of
## the body now, not upstream.
static func body_type_for(_archetype: String, _height: float, build: float, strength := 0.5) -> int:
	if build >= HEAVY_BUILD:
		return BUFF if strength >= BUFF_STRENGTH else HEAVY
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


## Writes the rest of what the face answers to. Returns the new seed.
static func pack_look(seed_value: int, complexion: int, hair_family: int, age: int, archetype: String) -> int:
	var bits := (clampi(complexion, 0, COMPLEXION_MASK) << COMPLEXION_SHIFT) \
		| (clampi(hair_family, 0, HAIR_MASK) << HAIR_SHIFT) \
		| (age_band(age) << AGE_SHIFT) \
		| (archetype_index(archetype) << ARCHETYPE_SHIFT)
	var keep := ~(LOOK_MASK & ~BODY_MASK)
	return (seed_value & keep) | bits


## The same, for a generated player: reads his own record.
static func pack_for(seed_value: int, player: WorldPlayer) -> int:
	var packed := pack(seed_value,
		body_type_for(player.archetype, player.height, player.build, player.attrs.strength),
		player.height, player.build)
	return pack_look(packed, player.complexion, player.hair_family, player.age, player.archetype)


static func age_band(age: int) -> int:
	if age < 21:
		return YOUNG
	if age < 30:
		return PRIME
	if age < 34:
		return THIRTIES
	return VETERAN


static func archetype_index(archetype: String) -> int:
	var i := ARCHETYPES.find(archetype)
	return maxi(i, 0)


## Draws a complexion band for a man of this nation and country.
static func draw_complexion(rng: SimRng, nation: int, code: String) -> int:
	return _draw_band(rng, COMPLEXION_WEIGHTS, nation, code)


## Draws a hair family for him. Dark on a deep complexion, always.
static func draw_hair_family(rng: SimRng, nation: int, code: String, complexion: int) -> int:
	if complexion == DEEP:
		return DARK
	return _draw_band(rng, HAIR_WEIGHTS, nation, code)


static func _draw_band(rng: SimRng, table: Dictionary, nation: int, code: String) -> int:
	var weights: Array
	if nation == WorldNames.FOREIGN:
		weights = table.get(code, table[""])
	else:
		weights = table.get(nation, table[""])
	var r := rng.unit_float()
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if r < acc:
			return i
	return weights.size() - 1


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


## The rest read -1 for an unpacked seed, and presentation draws its own.
static func complexion_of(seed_value: int) -> int:
	if not is_packed(seed_value):
		return -1
	return mini((seed_value >> COMPLEXION_SHIFT) & COMPLEXION_MASK, DEEP)


static func hair_family_of(seed_value: int) -> int:
	if not is_packed(seed_value):
		return -1
	return (seed_value >> HAIR_SHIFT) & HAIR_MASK


static func age_band_of(seed_value: int) -> int:
	if not is_packed(seed_value):
		return -1
	return (seed_value >> AGE_SHIFT) & AGE_MASK


## The archetype name, or "" for none or an unpacked seed.
static func archetype_of(seed_value: int) -> String:
	if not is_packed(seed_value):
		return ""
	var i := (seed_value >> ARCHETYPE_SHIFT) & ARCHETYPE_MASK
	if i >= ARCHETYPES.size():
		return ""
	return ARCHETYPES[i]
