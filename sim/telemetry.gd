class_name SimTelemetry
extends RefCounted
## The match event log and positional trace.
##
## Three separate systems read this (PLAN.md §7): post-match attribution, the
## assistant manager, and the statistical test suite. It is built in from the
## start rather than retrofitted, and it is the only channel through which
## anything outside the sim learns what happened.

enum Ev {
	KICKOFF,
	TOUCH,
	PASS_ATTEMPT,
	PASS_OUTCOME,
	SHOT,
	DUEL,
	FOUL,
	CARD,
	RECOVERY,
	PATTERN,
	PHASE_CHANGE,
	GOAL,
	OFFSIDE,
	SET_PIECE,
	PERIOD,
	SUBSTITUTION,
	SAVE,
	OUT_OF_PLAY,
	## The end of one team's spell on the ball. Appended rather than inserted:
	## these are ints in a hashed log, and renumbering the enum would move every
	## digest for nothing.
	POSSESSION_END,
	## A body sold without the ball (`SimDecision._add_feint`). Appended, as above.
	FEINT,
	## A body thrown at a shot (`SimDuel.commit_blocks`), hit or miss. Appended.
	BLOCK_LUNGE,
	## Where the keeper sent a parry (`SimKeeper._take_the_save`). Appended.
	PARRY,
}

const EV_NAMES := [
	"kickoff", "touch", "pass_attempt", "pass_outcome", "shot", "duel", "foul",
	"card", "recovery", "pattern", "phase_change", "goal", "offside", "set_piece",
	"period", "substitution", "save", "out_of_play", "possession_end", "feint",
	"block_lunge", "parry",
]

## Touch kinds. Shared with the touch module.
enum Touch {
	DRIBBLE,
	GROUND_PASS,
	LOFTED_PASS,
	THROUGH_BALL,
	CROSS,
	SHOT,
	FIRST_TOUCH,
	CLEARANCE,
	HEADER,
	TACKLE,
	BLOCK,
	KEEPER_CATCH,
	KEEPER_PARRY,
	KEEPER_THROW,
	THROW_IN,
	## Taken down off the body: chest, thigh, whatever is in the way. Its own
	## kind rather than a first touch with a height on it, because the question
	## "how much of this match is played in the air" is answered by counting
	## these against headers, and a first touch on the floor is neither.
	CHEST,
	## Hooked away by a man who got to a loose ball first and could not take it
	## cleanly. Separated from `BLOCK` because a block is a ball struck too hard
	## to control, got in the way of, and this is the opposite fact -- nothing was
	## struck at him and he beat everyone to it. Counted as a block, a defender
	## jogging onto a ball nobody hit was a blocked shot in every instrument that
	## counts them (`docs/THE_FOOTBALL.md` 45).
	POKE,
}

const TOUCH_NAMES := [
	"dribble", "ground_pass", "lofted_pass", "through_ball", "cross", "shot",
	"first_touch", "clearance", "header", "tackle", "block", "keeper_catch",
	"keeper_parry", "keeper_throw", "throw_in", "chest", "poke",
]

var events: Array[Dictionary] = []
## Positional trace at 5 Hz: one entry per sample, each a PackedVector3Array of
## ball position followed by every player position, in fixed id order.
var trace: Array[PackedVector3Array] = []
## Parallel to `trace`, sample for sample: where the formation wanted each
## player at that instant, in player id order with no ball entry in front, and
## which arm of the movement ladder had him instead.
##
## Recorded with the trace and read by nothing in `sim/`. It exists because the
## question "is the side holding its shape" cannot be answered from positions
## alone: `SimMovement.shape_position` slides every station with play, so a man
## twenty metres from his formation home may be exactly where the shape put him
## or nowhere near it, and those look identical in the trace.
var shape_trace: Array[PackedVector3Array] = []
## And where he was actually being sent, which is the shape with the errand
## applied on top. Kept apart from `shape_trace` because "the errand moved his
## target" and "he is a long way behind his own target" are different faults and
## one distance cannot tell them apart.
var target_trace: Array[PackedVector3Array] = []
var errand_trace: Array[PackedInt32Array] = []
## And the hips, sample for sample: `SimPlayer.facing` per player. The body is
## its own state and may be held off the run (`look_target`), and positions
## alone cannot say whether a man is running, shuffling or backpedalling.
var facing_trace: Array[PackedFloat32Array] = []
var trace_enabled := true
var events_enabled := true


func clear() -> void:
	events.clear()
	trace.clear()
	shape_trace.clear()
	target_trace.clear()
	errand_trace.clear()
	facing_trace.clear()


## `poss` is stamped on by `SimContext.log_event`, which is the only caller: it is
## the spell of possession that was live when the event was logged, and it is the
## join key everything in `tools/diagnostics.gd` pairs on. Before it existed the
## only way to ask what became of a touch was to guess by tick window, and
## `docs/DIAGNOSTICS.md` has the two ways that went wrong.
func log_event(kind: int, tick: int, data: Dictionary = {}) -> void:
	if not events_enabled:
		return
	data["ev"] = kind
	data["t"] = tick
	events.append(data)


## Every event belonging to one spell of possession, in order.
func in_possession(poss: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if int(e.get("poss", -1)) == poss:
			out.append(e)
	return out


func log_trace(sample: PackedVector3Array) -> void:
	if trace_enabled:
		trace.append(sample)


func log_shape(stations: PackedVector3Array, targets: PackedVector3Array, errands: PackedInt32Array,
		facings: PackedFloat32Array) -> void:
	if trace_enabled:
		shape_trace.append(stations)
		target_trace.append(targets)
		errand_trace.append(errands)
		facing_trace.append(facings)


func count_of(kind: int) -> int:
	var n := 0
	for e in events:
		if e["ev"] == kind:
			n += 1
	return n


func filter(kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e["ev"] == kind:
			out.append(e)
	return out


## Events matching a kind and an arbitrary set of key/value equality tests.
func filter_where(kind: int, conditions: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e["ev"] != kind:
			continue
		var ok := true
		for key in conditions:
			if not e.has(key) or e[key] != conditions[key]:
				ok = false
				break
		if ok:
			out.append(e)
	return out


## Canonical text serialisation of the event log. Two runs of the same seed on
## the same build must produce identical text; the golden-replay test hashes it.
func canonical_text() -> String:
	var parts := PackedStringArray()
	for e in events:
		var keys := e.keys()
		keys.sort()
		var fields := PackedStringArray()
		for key in keys:
			fields.append("%s=%s" % [key, _canonical_value(e[key])])
		parts.append(",".join(fields))
	return "\n".join(parts)


func digest() -> String:
	return canonical_text().sha256_text()


static func _canonical_value(v: Variant) -> String:
	match typeof(v):
		TYPE_FLOAT:
			# Quantise so that meaningless last-bit differences do not change the
			# hash, while any real divergence still does.
			return "%.4f" % v
		TYPE_VECTOR3:
			return "(%.4f,%.4f,%.4f)" % [v.x, v.y, v.z]
		_:
			return str(v)


static func ev_name(kind: int) -> String:
	return EV_NAMES[kind] if kind >= 0 and kind < EV_NAMES.size() else "?"


static func touch_name(kind: int) -> String:
	return TOUCH_NAMES[kind] if kind >= 0 and kind < TOUCH_NAMES.size() else "?"


## Played by the man taking the ball off the other side rather than by the man
## in possession. Asked here because there are three of them and every consumer
## needs all three: a list naming two counted the third as a carrier's own
## choice.
static func is_defensive_kind(kind: int) -> bool:
	return kind == Touch.TACKLE or kind == Touch.BLOCK or kind == Touch.POKE


static func is_pass_kind(kind: int) -> bool:
	return kind == Touch.GROUND_PASS or kind == Touch.LOFTED_PASS \
		or kind == Touch.THROUGH_BALL or kind == Touch.CROSS or kind == Touch.THROW_IN
