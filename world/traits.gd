class_name WorldTraits
extends RefCounted
## The two or three things that are true about a man besides his numbers
## (PLAN.md §8, §9.7).
##
## A trait is a handle for the writing: the scout report, the dressing room, the
## epithet, and what the assistant says when he picks the team. **Nothing in
## `sim/` reads a trait today** -- that wiring is a later pass, and each entry
## carries `sim_note` saying what it is meant to do when it happens, so the pass
## is a reading job rather than a design job.
##
## Traits are drawn against the player, not at random: an aggressive number
## makes `hothead` likely and `ice` impossible. That is what stops a squad of
## eighteen from being eighteen shuffles of the same deck.

const HOTHEAD := "hothead"
const ICE := "ice"
const LEADER := "leader"
const MOANER := "moaner"
const WORKHORSE := "workhorse"
const SHOWBOAT := "showboat"
const BIG_GAME := "big_game"
const FLAT_TRACK := "flat_track"
const GLASS := "glass"
const OX := "ox"
const LOYAL := "loyal"
const MERCENARY := "mercenary"
const ACADEMY := "academy"
const JOURNEYMAN := "journeyman"
const SUPERSTITIOUS := "superstitious"
const NIGHT_OWL := "night_owl"

## Each entry:
##   label      what the game calls it in copy
##   scout      the scout's sentence, in the flat voice of §9.7
##   sim_note   what it is intended to do in `sim/` when traits are wired
##   wants      attribute -> the value that makes it likely (0..1)
##   min_age / max_age  the ages it is available at
##   conflicts  traits it cannot share a man with
const CATALOGUE := {
	HOTHEAD: {
		"label": "Loses the head",
		"scout": "He will get himself sent off before Christmas.",
		"sim_note": "Raise duel commitment and the foul roll; lower composure under provocation.",
		"wants": {"aggression": 0.80, "composure": 0.30},
		"conflicts": [ICE],
	},
	ICE: {
		"label": "Ice in the veins",
		"scout": "Nothing that happens on a pitch appears to reach him.",
		"sim_note": "Shrink the penalty and one-on-one composure loss; ignore crowd and scoreline pressure.",
		"wants": {"composure": 0.85},
		"conflicts": [HOTHEAD],
	},
	LEADER: {
		"label": "Captain material",
		"scout": "The other ten look at him when it goes wrong.",
		"sim_note": "Lift teammate morale within a radius; slow the collapse after conceding.",
		"wants": {"decisions": 0.72, "teamwork": 0.72, "composure": 0.68},
		"min_age": 24,
		"conflicts": [MOANER],
	},
	MOANER: {
		"label": "Moans",
		"scout": "Every decision is somebody else's fault and he says so.",
		"sim_note": "Drag teammate morale when losing; refuse instructions he dislikes.",
		"wants": {"teamwork": 0.25},
		"conflicts": [LEADER],
	},
	WORKHORSE: {
		"label": "Runs all day",
		"scout": "He covers ground nobody asked him to cover.",
		"sim_note": "Cheaper off-ball errands and a slower stamina drain at high work rate.",
		"wants": {"work_rate": 0.82, "stamina": 0.75},
		"conflicts": [NIGHT_OWL],
	},
	SHOWBOAT: {
		"label": "Crowd-pleaser",
		"scout": "He would rather beat a man twice than pass it once.",
		"sim_note": "Bias the on-ball score toward dribbling; take the shot from further out.",
		"wants": {"dribbling": 0.78, "technique": 0.72, "teamwork": 0.35},
		"conflicts": [],
	},
	BIG_GAME: {
		"label": "Turns up on the night",
		"scout": "Ordinary on a Tuesday. Not ordinary in a cup tie.",
		"sim_note": "Lift sharpness in fixtures the run marks as big.",
		"wants": {},
		"conflicts": [FLAT_TRACK],
	},
	FLAT_TRACK: {
		"label": "Bully",
		"scout": "Unplayable against a poor side and invisible against a good one.",
		"sim_note": "Scale sharpness by the gap in opposition rating, both ways.",
		"wants": {},
		"conflicts": [BIG_GAME],
	},
	GLASS: {
		"label": "Made of glass",
		"scout": "He has never played thirty games in a season and he never will.",
		"sim_note": "Raise the injury roll; slow condition recovery between fixtures.",
		"wants": {"strength": 0.30},
		"conflicts": [OX],
	},
	OX: {
		"label": "Built like an ox",
		"scout": "You could play him Saturday, Tuesday and Saturday and he would ask for more.",
		"sim_note": "Lower the injury roll; recover condition faster.",
		"wants": {"strength": 0.80, "stamina": 0.78},
		"conflicts": [GLASS],
	},
	LOYAL: {
		"label": "Club man",
		"scout": "He would take a pay cut to stay here, and he has said so out loud.",
		"sim_note": "Trust decays slowly; refuses moves; wage demands lower.",
		"wants": {},
		"conflicts": [MERCENARY, JOURNEYMAN],
	},
	MERCENARY: {
		"label": "In it for the money",
		"scout": "He will go wherever the wage is, and he does not pretend otherwise.",
		"sim_note": "Morale follows wage rank in the squad; leaves for any better offer.",
		"wants": {},
		"conflicts": [LOYAL],
	},
	ACADEMY: {
		"label": "Came through the ranks",
		"scout": "Local. The crowd knew his name before he made the bench.",
		"sim_note": "Crowd lift at home; morale bonus while at this club.",
		"wants": {},
		"max_age": 26,
		"conflicts": [JOURNEYMAN],
	},
	JOURNEYMAN: {
		"label": "Been everywhere",
		"scout": "Eleven clubs. He knows every ground in the division and half the referees.",
		"sim_note": "No settling-in penalty at a new club; morale flat and hard to move.",
		"wants": {},
		"min_age": 29,
		"conflicts": [ACADEMY, LOYAL],
	},
	SUPERSTITIOUS: {
		"label": "Superstitious",
		"scout": "Left boot first, every time, and he will tell you why.",
		"sim_note": "Flavour only. Feeds dialogue and the dressing room; no sim effect intended.",
		"wants": {},
		"conflicts": [],
	},
	NIGHT_OWL: {
		"label": "Likes a night out",
		"scout": "Brilliant on his day. His day is not usually a Saturday.",
		"sim_note": "Random sharpness dips between fixtures; discipline events off the pitch.",
		"wants": {"work_rate": 0.30},
		"conflicts": [WORKHORSE],
	},
}

const ALL := [
	HOTHEAD, ICE, LEADER, MOANER, WORKHORSE, SHOWBOAT, BIG_GAME, FLAT_TRACK,
	GLASS, OX, LOYAL, MERCENARY, ACADEMY, JOURNEYMAN, SUPERSTITIOUS, NIGHT_OWL,
]

## How often a trait turns up at all, before fit is considered. Anything not
## listed is 1.0.
##
## Fit alone is not enough: a trait that `wants` nothing fits every man equally
## and therefore lands on every man. The first squad printed had six players
## made of glass and five superstitious ones, which is not a squad of
## characters, it is a squad with two characters copied out eighteen times.
const RARITY := {
	BIG_GAME: 0.55,
	FLAT_TRACK: 0.45,
	GLASS: 0.50,
	OX: 0.70,
	LOYAL: 0.70,
	MERCENARY: 0.60,
	ACADEMY: 0.70,
	JOURNEYMAN: 0.60,
	SUPERSTITIOUS: 0.45,
	NIGHT_OWL: 0.60,
	MOANER: 0.70,
	SHOWBOAT: 0.80,
}

## How many traits a man has. Most have one; three is a character.
const COUNT_WEIGHTS := [0.50, 0.36, 0.14]


static func label(trait_id: String) -> String:
	var entry: Dictionary = CATALOGUE.get(trait_id, {})
	return str(entry.get("label", trait_id))


static func scout_line(trait_id: String) -> String:
	var entry: Dictionary = CATALOGUE.get(trait_id, {})
	return str(entry.get("scout", ""))


## What this trait is meant to do once traits reach `sim/`. Kept next to the
## trait so the wiring pass has nothing to invent.
static func sim_note(trait_id: String) -> String:
	var entry: Dictionary = CATALOGUE.get(trait_id, {})
	return str(entry.get("sim_note", ""))


## How well a man fits a trait, 0..1. A trait with no `wants` fits everybody
## equally and is decided by the draw alone.
static func fit(trait_id: String, attrs: SimAttributes, age: int) -> float:
	var entry: Dictionary = CATALOGUE.get(trait_id, {})
	if entry.is_empty():
		return 0.0
	if age < int(entry.get("min_age", 0)) or age > int(entry.get("max_age", 99)):
		return 0.0
	var rarity := float(RARITY.get(trait_id, 1.0))
	var wants: Dictionary = entry.get("wants", {})
	if wants.is_empty():
		return 0.5 * rarity
	var total := 0.0
	for key in wants:
		# Distance from the value the trait wants, so a man who is the opposite
		# of it scores near zero and never draws it.
		var want := float(wants[key])
		var have := float(attrs.get(key))
		total += clampf(1.0 - absf(have - want) * 1.6, 0.0, 1.0)
	return total / float(wants.size()) * rarity


## Draws `count` traits for a player. Fit decides the odds, conflicts are
## refused outright, and a man can end up with fewer than asked for if nothing
## fits him -- which is itself a character.
## `already` is how many men in this squad have each trait, and is what stops a
## side of eighteen from containing four captains. Optional: a player drawn on
## his own has nobody to be compared with.
static func draw(rng: SimRng, attrs: SimAttributes, age: int, count: int, already: Dictionary = {}) -> PackedStringArray:
	var chosen := PackedStringArray()
	var pool := ALL.duplicate()
	for _i in count:
		var weights := PackedFloat32Array()
		var candidates: Array = []
		for trait_id in pool:
			if _conflicts(trait_id, chosen):
				continue
			var f := fit(trait_id, attrs, age)
			# Each man who already has it cuts the next man's chance to a third.
			# Halving was not enough: a strong squad still came out with four
			# men who had ice in the veins and four who ran all day, because at
			# a good club a great many men fit those two.
			f /= pow(3.0, float(already.get(trait_id, 0)))
			if f <= 0.02:
				continue
			candidates.append(trait_id)
			weights.append(f)
		if candidates.is_empty():
			break
		var pick: int = rng.weighted_index(weights)
		var trait_id: String = candidates[pick]
		chosen.append(trait_id)
		pool.erase(trait_id)
	return chosen


## How many traits this man gets, from `COUNT_WEIGHTS`.
static func draw_count(rng: SimRng) -> int:
	return rng.weighted_index(PackedFloat32Array(COUNT_WEIGHTS)) + 1


static func _conflicts(trait_id: String, chosen: PackedStringArray) -> bool:
	var entry: Dictionary = CATALOGUE.get(trait_id, {})
	var against: Array = entry.get("conflicts", [])
	for other in chosen:
		if against.has(other):
			return true
	return false
