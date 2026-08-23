class_name WorldScout
extends RefCounted
## Turning what the club believes into what a human reads (PLAN.md §6.1).
##
## The player never sees an attribute (§6.1), so this is the only route from a
## number to a screen. It reads `WorldPlayer.known` -- the belief -- and never
## `attrs`, which is why a scout can be wrong, and why a player who has been
## watched for a season is described more sharply than one seen once.
##
## The voice is §9.7's: flat, plain, and it never tells you a thing was funny.

## Words for a value, worst to best. Eight bands is as fine as language gets
## before it starts lying about precision.
##
## Each one has to read after "He is", and each phrase below has to read after
## one of these, so the report is one grammar rather than a template with holes.
const BANDS := [
	"hopeless", "poor", "weak", "ordinary",
	"decent", "good", "excellent", "frightening",
]

## How sure the club is that any of it is true, worst to best. The last is
## empty: a man they have watched for a season needs no caveat.
const HEDGES := [
	"Nobody here has watched him properly. Treat all of that as a rumour.",
	"That is one look at him, and one look is not much.",
	"That is a fair few looks at him now.",
	"",
]

## The attribute a phrase is about, in the words a scout would use for it.
const PHRASES := {
	"pace": "over the ground",
	"acceleration": "off the mark",
	"stamina": "at lasting the ninety",
	"strength": "in a physical duel",
	"agility": "at turning",
	"jumping": "in the air",
	"first_touch": "at controlling it",
	"passing": "at finding a man",
	"technique": "on the ball",
	"finishing": "in front of goal",
	"power": "at striking it",
	"heading": "with his head",
	"tackling": "in the tackle",
	"dribbling": "at beating a man",
	"crossing": "at putting it in the box",
	"decisions": "at picking the right thing",
	"awareness": "at seeing it early",
	"positioning": "at standing where he should",
	"composure": "when it matters",
	"work_rate": "at getting round the pitch",
	"aggression": "at wanting it",
	"teamwork": "at playing for the ten others",
	"reflexes": "on his line",
	"handling": "at catching it",
	"command": "at coming for a cross",
	"distribution": "with it in his hands",
}


static func band_word(value: float) -> String:
	var index := clampi(int(floor(clampf(value, 0.0, 0.999) * BANDS.size())), 0, BANDS.size() - 1)
	return BANDS[index]


static func hedge(confidence: float) -> String:
	var index := clampi(int(floor(clampf(confidence, 0.0, 0.999) * HEDGES.size())), 0, HEDGES.size() - 1)
	return HEDGES[index]


## One line about the man, and it is the line the club would lead with: his best
## believed attribute, his worst, and what he is.
static func summary(p: WorldPlayer) -> String:
	var best := _extreme(p, true)
	var worst := _extreme(p, false)
	var opener := "%s, %d, %s." % [p.display_name(), p.age, SimRole.name_of(p.role)]
	if best == "":
		return "%s Nobody here has seen enough of him to say anything." % opener
	if best == worst:
		return "%s He is %s %s." % [opener, band_word(p.estimate_of(best)), PHRASES.get(best, best)]
	return "%s He is %s %s, and %s %s." % [
		opener,
		band_word(p.estimate_of(best)), PHRASES.get(best, best),
		band_word(p.estimate_of(worst)), PHRASES.get(worst, worst),
	]


## The full report: the summary, the traits in the scout's own words, and how
## much of this the club would stand behind.
static func report(p: WorldPlayer) -> String:
	var lines := PackedStringArray()
	lines.append(summary(p))
	for trait_id in p.traits:
		var scout_line := WorldTraits.scout_line(trait_id)
		if scout_line != "":
			lines.append(scout_line)
	var hedge_line := hedge(p.known_rating())
	if hedge_line != "":
		lines.append(hedge_line)
	return "\n".join(lines)


## The strongest or weakest thing the club believes about him, among the
## attributes his role is actually judged on -- a centre-half being poor with
## his hands is not a scouting note.
static func _extreme(p: WorldPlayer, want_best: bool) -> String:
	var weights: Dictionary = SimRole.attribute_weights(p.role)
	var chosen := ""
	var chosen_value := -1.0 if want_best else 2.0
	for key in weights:
		if float(weights[key]) < 0.35:
			continue
		if p.confidence_of(key) < 0.15:
			continue
		var value := p.estimate_of(key)
		if want_best and value > chosen_value:
			chosen_value = value
			chosen = key
		elif not want_best and value < chosen_value:
			chosen_value = value
			chosen = key
	return chosen
