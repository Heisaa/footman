class_name WorldPlayer
extends RefCounted
## A footballer as the game outside the match knows him (PLAN.md §8).
##
## `SimPlayer` is the man on the pitch for ninety minutes and knows nothing
## about contracts or morale; this is the man the rest of the week happens to,
## and it is the authority. `to_sim_player` hands the match what it needs and
## the match hands nothing back -- the world writes to itself, from the
## telemetry, after the whistle.
##
## Nothing here is shown to the player as a number (PLAN.md §6.1). `attrs` is
## the truth, `known` is what the club believes, and the scout report is the
## only thing a human reads.

var id := -1

# --- Identity ---------------------------------------------------------------

var first_name := ""
var surname := ""
## `WorldNames.ENG` and friends. FOREIGN keeps its country in `country`.
var nation := WorldNames.ENG
var nation_code := "ENG"
var country := "England"
## What the terrace calls him: "Gaz". Everybody British has one.
var familiar := ""
## What the comic calls him: "Hot-Shot". Only the tails have one (§9.7).
var epithet := ""
## Which tail he is, from `WorldNickname`. Empty for most of a squad.
var archetype := WorldNickname.NONE
var age := 24
## The body the record intends, in metres, and how heavy he is built, 0..1.
##
## The **presentation layer still builds the figure from `appearance_seed`**, so
## these two agree with what is drawn only when the generator was given a body
## oracle to sample seeds against (`WorldGen.body_oracle`). Without one they are
## the record's intent and nothing more. `sim/` reads neither; a giant is
## currently a giant in his attributes, not in his height.
var height := 1.78
var build := 0.5
## Seed for the procedural appearance (PLAN.md §9.3). Travels to `SimPlayer` so
## presentation rebuilds the same face every time.
var appearance_seed := 0

# --- Football ---------------------------------------------------------------

var role := SimRole.CM
var attrs: SimAttributes = SimAttributes.new()
var traits := PackedStringArray()
## Squad number. Kept on the record because it is identity: the number is how
## the crowd knows him before the name is legible.
var shirt := 0

# --- Condition and standing -------------------------------------------------

## 0..1. Fitness across the week, dropped by a match and recovered by rest.
var condition := 1.0
## 0..1. Match sharpness, which is games rather than rest.
var sharpness := 0.9
## 0..1. How he feels about his football.
var morale := 0.6
## 0..1. What he thinks of the manager. Team talks and selection move it, and
## the roguelike run is largely a story about this number.
var trust := 0.5

# --- Contract ---------------------------------------------------------------

## Weekly wage in pounds. Period money, and it should look like it.
var wage := 400
var contract_years := 2
## Seasons at this club, for `academy` and `journeyman` to mean something.
var seasons_here := 0
var club_id := -1

# --- What the club knows ----------------------------------------------------

## Per attribute, what the club believes and how sure it is:
##   {"pace": {"estimate": 0.71, "confidence": 0.4}, ...}
##
## A scout, a training week and ninety minutes of telemetry all move these; the
## true `attrs` never move. Every screen reads from here.
var known := {}


func full_name() -> String:
	return "%s %s" % [first_name, surname]


## The name on the team sheet and in the event log: the epithet if he has one,
## the surname if he does not.
func display_name() -> String:
	return WorldNickname.stitch(epithet, surname)


## The name in the dressing room and in dialogue.
func familiar_name() -> String:
	if epithet != "":
		return epithet.replace("The ", "")
	if familiar != "":
		return familiar
	return first_name


## Sets up the belief table with a flat, ignorant prior. `confidence` 0 means
## the estimate is a guess drawn round the population mean.
func seed_knowledge(rng: SimRng, initial_confidence: float = 0.25) -> void:
	known = {}
	for key in SimAttributes.ALL:
		var truth := float(attrs.get(key))
		# The guess is the truth seen through fog: the less confident, the more
		# it drifts, and the drift is toward the middle rather than anywhere.
		var fog := (1.0 - initial_confidence) * 0.22
		var guess := lerpf(rng.gauss_clamped(truth, fog, 2.0), 0.5, (1.0 - initial_confidence) * 0.35)
		known[key] = {
			"estimate": clampf(guess, 0.03, 0.99),
			"confidence": clampf(initial_confidence, 0.0, 1.0),
		}


## What the club believes about one attribute. Falls back to the truth only if
## nobody ever seeded the table, which is a bug rather than a state.
func estimate_of(key: String) -> float:
	var entry: Dictionary = known.get(key, {})
	return float(entry.get("estimate", attrs.get(key)))


func confidence_of(key: String) -> float:
	var entry: Dictionary = known.get(key, {})
	return float(entry.get("confidence", 0.0))


## Watching him play, or scouting him, moves the estimate toward the truth and
## raises the confidence. `weight` is how much this observation is worth: a
## training session is small, a full match larger, a season of them decisive.
func observe(rng: SimRng, key: String, weight: float) -> void:
	var entry: Dictionary = known.get(key, null)
	if entry == null:
		return
	var truth := float(attrs.get(key))
	var conf := float(entry["confidence"])
	var est := float(entry["estimate"])
	# One observation is a noisy sample of the truth, not the truth. The noise
	# is what makes a scout wrong about a player rather than merely vague.
	var sample := rng.gauss_clamped(truth, 0.12, 2.0)
	var pull := clampf(weight * (1.0 - conf * 0.7), 0.0, 1.0)
	entry["estimate"] = clampf(lerpf(est, sample, pull), 0.03, 0.99)
	entry["confidence"] = clampf(conf + weight * (1.0 - conf) * 0.6, 0.0, 0.98)


## Mean confidence across the attributes his role is judged on. What a screen
## shows as "how well we know him".
func known_rating(for_role: int = -1) -> float:
	var weights: Dictionary = SimRole.attribute_weights(for_role if for_role >= 0 else role)
	var total := 0.0
	var weight_sum := 0.0
	for key in weights:
		total += confidence_of(key) * float(weights[key])
		weight_sum += float(weights[key])
	return total / maxf(weight_sum, 1e-6) if weight_sum > 0.0 else 0.0


## Estimated quality for a role, from the beliefs rather than the truth. This is
## what the assistant, the board and every list in the game sort by.
func believed_rating(for_role: int = -1) -> float:
	var weights: Dictionary = SimRole.attribute_weights(for_role if for_role >= 0 else role)
	var total := 0.0
	var weight_sum := 0.0
	for key in weights:
		total += estimate_of(key) * float(weights[key])
		weight_sum += float(weights[key])
	return total / maxf(weight_sum, 1e-6) if weight_sum > 0.0 else 0.5


func has_trait(trait_id: String) -> bool:
	return traits.has(trait_id)


## The man on the pitch. The match gets the true attributes, the display name
## and the appearance seed, and nothing else on this record exists to it.
func to_sim_player(sim_id: int, team_index: int) -> SimPlayer:
	var p := SimPlayer.new()
	p.configure(sim_id, team_index, role, attrs.clone(), display_name())
	p.shirt = shirt
	p.appearance_seed = appearance_seed
	p.stamina = condition
	p.sharpness = sharpness
	p.morale = morale
	return p
