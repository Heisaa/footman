class_name SimTactics
extends RefCounted
## A tactical plan, expressed only as priors on the decision function.
##
## PLAN.md §5.1: tactics must not be behaviour switches. Every field here is a
## modifier on a value the decision or movement layer was going to use anyway,
## which is what makes overlapping instructions interact instead of one silently
## overwriting another.
##
## All axes are 0..1 with 0.5 neutral unless stated.

var display_name := "Balanced"

## How hard and how high the team presses. Drives territory weighting and the
## distance at which a defender commits to an engagement.
var press_intensity := 0.5
## How far up the pitch the press starts, as a fraction from own goal (0) to
## opponent goal (1).
var press_line := 0.5
## Defensive line height, same scale. Feeds formation home positions and the
## willingness to step up for an offside trap.
var line_height := 0.5
var offside_trap := 0.35

## Tempo: how quickly the ball is moved on. Raises the discount applied to
## future value, so a high-tempo side releases earlier.
var tempo := 0.65
## Directness: ground-versus-lofted bias and how far forward a pass is worth
## trying.
var directness := 0.5
## Risk appetite. Scales down the penalty for losing the ball.
var risk := 0.5
## Lateral spread of the formation's home positions.
var width := 0.5
## Expected-threat multipliers by third of the pitch across: left, centre, right.
## Written by `set_focus`, never by hand -- see it for why the three have to
## average to one.
var attacking_focus := PackedFloat32Array([1.0, 1.0, 1.0])
## Willingness to counter-attack directly on winning the ball.
var counter := 0.5

## Named patterns installed for this match (PLAN.md §5.3). Phase 5 fills these.
var patterns: Array[SimPattern] = []
## Zones painted on the whiteboard (Phase 7 authoring, Phase 5 semantics).
var press_zones: Array[Dictionary] = []
var target_zones: Array[Dictionary] = []
## Player-to-player partnerships biasing passes and supporting runs.
var links: Array[Vector2i] = []
## Per-slot movement instructions keyed by formation slot.
var slot_instructions := {}


func clone() -> SimTactics:
	var t := SimTactics.new()
	t.display_name = display_name
	t.press_intensity = press_intensity
	t.press_line = press_line
	t.line_height = line_height
	t.offside_trap = offside_trap
	t.tempo = tempo
	t.directness = directness
	t.risk = risk
	t.width = width
	t.attacking_focus = attacking_focus.duplicate()
	t.counter = counter
	# Deep copy: patterns carry per-match firing counts, and sharing them
	# between plans would pool one side's statistics into the other's.
	t.patterns = []
	for p in patterns:
		var copy := SimPattern.new(p.kind, p.strength)
		copy.cooldown_ticks = p.cooldown_ticks
		t.patterns.append(copy)
	t.press_zones = press_zones.duplicate(true)
	t.target_zones = target_zones.duplicate(true)
	t.links = links.duplicate()
	t.slot_instructions = slot_instructions.duplicate(true)
	return t


# --- Derived modifiers ------------------------------------------------------
# These are the only things the decision and movement layers read. Adding a
# tactical feature means adding a derivation here, not a branch there.

## Weight applied to the cost of conceding possession. Low risk means a heavily
## punished turnover.
func risk_weight() -> float:
	return lerpf(1.5, 0.45, risk)


## Discount on value that only arrives later. High tempo discounts the future
## harder, so the ball is released sooner.
func future_discount() -> float:
	return lerpf(0.95, 0.72, tempo)


## Multiplier on the expected value of a lofted or direct ball.
func direct_bias() -> float:
	return lerpf(0.75, 1.45, directness)


## Multiplier on the expected value of holding or retaining the ball.
func retention_bias() -> float:
	return lerpf(1.3, 0.8, directness)


## Distance at which a defender commits to closing the ball carrier down.
func engage_distance() -> float:
	return lerpf(5.0, 14.0, press_intensity)


## Number of players the shape is willing to send at the ball at once.
func press_commitment() -> int:
	return 1 + int(round(press_intensity * 2.0))


## X coordinate, in canonical (attacking +X) metres, of the defensive line with
## the ball at the halfway line. Neutral (0.5) reproduces the formation's own
## back-line depth, so a neutral plan applies no shift at all.
func line_x(pitch: SimPitch) -> float:
	return lerpf(-0.80, -0.42, line_height) * pitch.half_length


## Lateral spread multiplier applied to formation home positions.
func width_scale() -> float:
	return lerpf(0.78, 1.2, width)


## How far a plan tilts toward the flanks, at the extreme. Wide bands go up by
## this and the middle comes down by twice it, which is what keeps the three
## averaging to one.
const FOCUS_TILT := 0.12


## Which way the side looks for its threat: +1 down the outside, -1 through the
## middle, 0 no opinion.
##
## The three multipliers have to average to one and that is not tidiness. Every
## candidate's gain is `xt_at(its own point) * focus_at(...)`, and `loss` is not
## multiplied by anything, so a triple averaging above one lifts every gain
## against a fixed loss and the plan comes out *more adventurous* rather than
## more lateral. `--ablate` would then report `focus_at` flipping picks, and it
## would be reporting the wrong mechanic.
##
## Until this existed nothing in the engine wrote `attacking_focus` at all. It
## sat at `[1.0, 1.0, 1.0]` through eight call sites, multiplying every gain in
## the decision layer by exactly one, in every plan, in every match --
## `docs/DIAGNOSTICS.md` link 1, and the first thing `--ablate` found.
func set_focus(wing: float) -> void:
	var w: float = clampf(wing, -1.0, 1.0) * FOCUS_TILT
	attacking_focus = PackedFloat32Array([1.0 + w, 1.0 - 2.0 * w, 1.0 + w])


## Multiplier on expected threat for a point, by its lateral third.
func focus_at(z: float, pitch: SimPitch) -> float:
	var t := (z + pitch.half_width) / (2.0 * pitch.half_width)
	var i: int = clampi(int(t * 3.0), 0, 2)
	return attacking_focus[i]


# --- Presets ----------------------------------------------------------------

static func balanced() -> SimTactics:
	var t := SimTactics.new()
	t.install(SimPattern.Kind.OVERLAP_LEFT)
	t.install(SimPattern.Kind.OVERLAP_RIGHT)
	t.install(SimPattern.Kind.SWITCH_FAR_SIDE, 0.6)
	t.install(SimPattern.Kind.ONE_TWO, 0.7)
	return t


## Installs a named pattern. PLAN.md §5.3 wants a small number of slots -- five
## to eight -- because the point of patterns is that a player can hold them all
## in their head and recognise them on the pitch.
const MAX_PATTERNS := 8


func install(kind: int, strength: float = 0.7) -> bool:
	if patterns.size() >= MAX_PATTERNS:
		return false
	for existing in patterns:
		if existing.kind == kind:
			return false
	patterns.append(SimPattern.new(kind, strength))
	return true


func has_pattern(kind: int) -> bool:
	for p in patterns:
		if p.kind == kind:
			return true
	return false


## High press, direct. One of the two contrasting plans the Phase 5 exit
## criterion measures.
static func high_press_direct() -> SimTactics:
	var t := SimTactics.new()
	t.display_name = "High press, direct"
	t.press_intensity = 0.9
	t.press_line = 0.82
	t.line_height = 0.82
	t.offside_trap = 0.7
	t.tempo = 0.85
	t.directness = 0.82
	t.risk = 0.75
	t.width = 0.6
	t.counter = 0.8
	# Wins it high and goes down the outside. It is the plan that gets bodies
	# beyond the ball quickest, and the ball into the box is now an act the
	# engine has -- `SimDecision._add_crosses`.
	t.set_focus(1.0)
	t.install(SimPattern.Kind.PRESS_THE_GOAL_KICK, 0.9)
	t.install(SimPattern.Kind.RUN_IN_BEHIND, 0.8)
	t.install(SimPattern.Kind.THIRD_MAN_RUN, 0.6)
	return t


## Deep block, patient. The other half of the Phase 5 comparison.
static func deep_block_patient() -> SimTactics:
	var t := SimTactics.new()
	t.display_name = "Deep block, patient"
	t.press_intensity = 0.15
	t.press_line = 0.22
	t.line_height = 0.2
	t.offside_trap = 0.15
	t.tempo = 0.22
	t.directness = 0.2
	t.risk = 0.25
	t.width = 0.42
	t.counter = 0.35
	# Sits in and works it through the middle when it gets it. Less strongly than
	# the press tilts the other way: a patient side is not refusing the flanks,
	# it is not built to reach them.
	t.set_focus(-0.6)
	t.install(SimPattern.Kind.KEEPER_PLAYS_SHORT, 0.9)
	t.install(SimPattern.Kind.SWITCH_FAR_SIDE, 0.8)
	t.install(SimPattern.Kind.UNDERLAP, 0.6)
	t.install(SimPattern.Kind.ONE_TWO, 0.9)
	return t
