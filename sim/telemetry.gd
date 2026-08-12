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
}

const EV_NAMES := [
	"kickoff", "touch", "pass_attempt", "pass_outcome", "shot", "duel", "foul",
	"card", "recovery", "pattern", "phase_change", "goal", "offside", "set_piece",
	"period", "substitution", "save", "out_of_play",
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
}

const TOUCH_NAMES := [
	"dribble", "ground_pass", "lofted_pass", "through_ball", "cross", "shot",
	"first_touch", "clearance", "header", "tackle", "block", "keeper_catch",
	"keeper_parry", "keeper_throw", "throw_in", "chest",
]

var events: Array[Dictionary] = []
## Positional trace at 5 Hz: one entry per sample, each a PackedVector3Array of
## ball position followed by every player position, in fixed id order.
var trace: Array[PackedVector3Array] = []
var trace_enabled := true
var events_enabled := true


func clear() -> void:
	events.clear()
	trace.clear()


func log_event(kind: int, tick: int, data: Dictionary = {}) -> void:
	if not events_enabled:
		return
	data["ev"] = kind
	data["t"] = tick
	events.append(data)


func log_trace(sample: PackedVector3Array) -> void:
	if trace_enabled:
		trace.append(sample)


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


static func is_pass_kind(kind: int) -> bool:
	return kind == Touch.GROUND_PASS or kind == Touch.LOFTED_PASS \
		or kind == Touch.THROUGH_BALL or kind == Touch.CROSS or kind == Touch.THROW_IN
