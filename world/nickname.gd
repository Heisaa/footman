class_name WorldNickname
extends RefCounted
## The epithet that goes in front of the surname (PLAN.md §9.7).
##
## "Hot-Shot" Hamish and "Mighty" Mouse are the specification: an epithet is the
## cheapest way to make five hundred generated men memorable, and it is only
## worth anything if it is **true**. So the archetype is derived from the
## numbers -- what the sim will actually do with this man -- and only the wording
## is drawn from a pool. A man whose epithet says he shoots and who cannot shoot
## is worse than a man with no epithet at all.
##
## Most players do not get one. An epithet that everybody has is a surname, and
## the squad needs a background for the one or two to stand against; those men
## have `WorldNames.familiar` instead, which is what the terrace calls anybody.

## Archetypes, in the order they are tested. First one to clear its bar wins, so
## the list is ordered by what a crowd would notice first: the freak shot, the
## size, then the speed, then the head.
const HAMMER := "hammer"
const GIANT := "giant"
const SPRITE := "sprite"
const WHIPPET := "whippet"
const BRAIN := "brain"
const WALL := "wall"
const GLOVES := "gloves"
const FIREBRAND := "firebrand"
const VETERAN := "veteran"
const CALAMITY := "calamity"
const NONE := ""

## The bar an archetype has to clear. High enough that a good player does not
## trip it -- these are the tails, not the top third.
const TAIL := 0.86
const DEEP_TAIL := 0.90

const POOLS := {
	HAMMER: ["Hot-Shot", "Cannonball", "Thunderboots", "The Howitzer", "Rocket", "Sledgehammer", "Dynamite"],
	GIANT: ["Big", "The Lighthouse", "Tower", "The Barn Door", "Bruiser", "Timber", "The Ox"],
	SPRITE: ["Mighty", "Nipper", "Pocket", "The Flea", "Half-Pint", "Titch", "The Sprite"],
	WHIPPET: ["Whippet", "Flash", "Greyhound", "Quicksilver", "Rapid", "The Hare", "Turbo"],
	BRAIN: ["The Professor", "Brains", "The General", "Maestro", "Clockwork", "The Schemer", "Radar"],
	WALL: ["The Wall", "Chopper", "Ironside", "Granite", "The Bouncer", "Bolts", "The Gate"],
	GLOVES: ["Safe Hands", "The Cat", "The Spider", "Sticky", "The Limpet", "Buckets"],
	FIREBRAND: ["Mad", "Tinderbox", "The Hurricane", "Sparky", "Powder-Keg", "Wildfire"],
	VETERAN: ["Grandad", "The Old Man", "Vintage", "Antique", "The Veteran", "Uncle"],
	CALAMITY: ["Calamity", "Butterfingers", "Disaster", "Wobbly", "The Accident", "Custard"],
}


## The archetype a man falls into, or NONE. `height` is metres and `age` years;
## `traits` is what `WorldTraits.draw` gave him.
##
## Ordered rather than scored: a giant who can also shoot is a giant, because
## that is what anybody watching says first.
static func archetype(attrs: SimAttributes, height: float, age: int, traits: PackedStringArray, is_keeper: bool) -> String:
	if is_keeper:
		if attrs.reflexes >= TAIL and attrs.handling >= 0.78:
			return GLOVES
		if attrs.handling <= 0.22 or attrs.command <= 0.18:
			return CALAMITY
		return NONE

	if attrs.power >= TAIL and attrs.finishing >= 0.72:
		return HAMMER
	if height >= 1.94 and attrs.strength >= 0.72:
		return GIANT
	if height <= 1.66 and (attrs.agility >= 0.75 or attrs.dribbling >= 0.75):
		return SPRITE
	if attrs.pace >= DEEP_TAIL:
		return WHIPPET
	if attrs.decisions >= TAIL and attrs.awareness >= 0.78 and attrs.passing >= 0.75:
		return BRAIN
	if attrs.tackling >= TAIL and attrs.positioning >= 0.72:
		return WALL
	if traits.has(WorldTraits.HOTHEAD) and attrs.aggression >= DEEP_TAIL:
		return FIREBRAND
	if age >= 35:
		return VETERAN
	# The other tail: hopeless at the thing his shirt is for. Kept last so a man
	# with anything to be known for is known for that instead.
	#
	# The bar is deep because it is an *absolute* one and the rest are too: at a
	# club near the bottom the whole squad sits low, and at 0.18 a bad side came
	# out with three calamities in it, which reads as a joke rather than as a
	# club. A man this side of 0.13 is hopeless in any division.
	if attrs.first_touch <= 0.13 or attrs.passing <= 0.12:
		return CALAMITY
	return NONE


## The epithet itself. Draws from the archetype's pool, so two giants at the
## same club are not both "Big".
static func epithet(rng: SimRng, kind: String) -> String:
	if kind == NONE or not POOLS.has(kind):
		return ""
	var pool: Array = POOLS[kind]
	return pool[rng.range_int(0, pool.size() - 1)]


## How the epithet is written in front of a surname: 'Hot-Shot' Balfour.
##
## Always quoted, including the phrases. Unquoted, "Kenny The Sprite Weir" reads
## as a man with two middle names rather than as a man with a nickname, and the
## quotes are what tell you which part of it his mother gave him.
static func stitch(epithet_text: String, surname: String) -> String:
	if epithet_text == "":
		return surname
	return "'%s' %s" % [epithet_text, surname]
