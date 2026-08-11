class_name SimPattern
extends RefCounted
## A named, recognisable tactical move (PLAN.md §5.3).
##
## Patterns are fragments of a tactical plan, not new behaviour. Each one nudges
## the decision or movement layer while its trigger holds, fires visibly, is
## counted in telemetry, and is reported after the match with a success rate.
## Named things with visible occurrences are far more learnable than parameters.

enum Kind {
	OVERLAP_LEFT,
	OVERLAP_RIGHT,
	THIRD_MAN_RUN,
	KEEPER_PLAYS_SHORT,
	SWITCH_FAR_SIDE,
	PRESS_THE_GOAL_KICK,
	RUN_IN_BEHIND,
	UNDERLAP,
}

const KIND_NAMES := [
	"Overlap left", "Overlap right", "Third-man run", "Keeper plays short",
	"Switch to the far side", "Press the goal kick", "Run in behind", "Underlap",
]

var kind := Kind.OVERLAP_LEFT
var display_name := "Overlap left"
## Strength of the nudge this pattern applies while active, 0..1.
var strength := 0.7

## Run-time bookkeeping, reset each match.
var fired := 0
var succeeded := 0
## Tick the pattern last fired, so it cannot retrigger every tick.
var last_fired_tick := -10000
## Minimum ticks between firings.
##
## PLAN.md §5.3 wants a small number of recognisable moves that a player can
## count and learn from. A pattern that fires two hundred times a match is not a
## move, it is a background hum, so the cooldowns are long on purpose.
var cooldown_ticks := 180

const COOLDOWNS := {
	Kind.OVERLAP_LEFT: 900,
	Kind.OVERLAP_RIGHT: 900,
	Kind.UNDERLAP: 900,
	Kind.THIRD_MAN_RUN: 600,
	Kind.SWITCH_FAR_SIDE: 1200,
	Kind.RUN_IN_BEHIND: 600,
	Kind.KEEPER_PLAYS_SHORT: 300,
	Kind.PRESS_THE_GOAL_KICK: 300,
}


func _init(p_kind: int = Kind.OVERLAP_LEFT, p_strength: float = 0.7) -> void:
	kind = p_kind
	strength = p_strength
	display_name = KIND_NAMES[p_kind]
	cooldown_ticks = COOLDOWNS.get(p_kind, 600)


func reset_counts() -> void:
	fired = 0
	succeeded = 0
	last_fired_tick = -10000


func success_rate() -> float:
	return 0.0 if fired == 0 else float(succeeded) / float(fired)


func ready(tick: int) -> bool:
	return tick - last_fired_tick >= cooldown_ticks


static func name_of(kind: int) -> String:
	return KIND_NAMES[kind] if kind >= 0 and kind < KIND_NAMES.size() else "?"
