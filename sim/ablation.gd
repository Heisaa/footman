class_name SimAblation
extends RefCounted
## Whether a term in the decision score ever changes what gets played.
##
## Links 1 to 3 of the chain. `docs/DIAGNOSTICS.md`, "The chain", has the other
## three and which instrument owns each.
##
## Start here, whatever the complaint. A term that never moves the pick produces a
## match identical in every count there is, so no statistic over a match can see
## one however many matches are run -- and a link that broke this early makes every
## measurement below it noise about something else.
##
## So this is measured per decision and counterfactually. At each decision the
## candidates are scored a second time with one term neutralised, and what is
## recorded is what that did to the choice. No second match, and -- the reason it
## is trustworthy -- no divergence cascade: two runs of one seed become different
## football within seconds of the first different decision, and a diff between
## them is a measurement of a different match rather than of the knob.
##
## Three failure modes, and the table separates them:
##
## - `in` at 0% -- the term is never applied to any candidate. It is not wired to
##   the situations it was written for. Nothing downstream can be its fault.
## - `on score` at ~0 -- it is applied and its value never varies, so it shifts
##   every option by the same amount and discriminates between none of them. The
##   `turnover_exposure` failure recorded in `SimDecision`: guessed thresholds,
##   a mean of 1.16, and no variance at all.
## - `flips` at 0% with a real `on score` -- it moves the numbers and is dominated
##   by something bigger. This is the one worth arguing about; the other two are
##   bugs.
##
## Same one-way-tap contract as `SimDebug`: off unless asked for, never touches
## `ctx.rng`, and nothing in `sim/` reads it back, so a match runs identically
## with it on. The pick is compared on the *best* option rather than on a second
## draw, because drawing again would consume the stream and change the match.
##
## It is deliberately not a telemetry event kind, for the reason `SimDebug` gives:
## `SimTelemetry.canonical_text` is hashed by the golden replay test and a
## diagnostic has no business moving a digest.
##
## It does not name `SimDecision`, which references it. The action names are
## mirrored below for that reason, as `SimDebug` mirrors them.

## The whole cost when nobody is watching: one boolean test per on-ball decision.
static var enabled := false

## Where in the score a term is applied, which is how it gets neutralised.
##
## `C_SELF` is a term `SimDecision.score_of` applies itself and neutralises by
## name. The rest are factors that went into a candidate when it was built and
## are recorded on it, so the instrument can take them back out exactly rather
## than rebuild the candidate -- which it could not do anyway, because candidate
## generation draws from `ctx.rng`.
const C_SELF := 0
const C_SUCCESS := 1
## Subtracted from `gain`, never divided out of it. Some of these multiply only
## part of the gain -- `focus_at` scales the map value and not the arrival credit
## added after it -- so what is recorded is the amount the factor contributed and
## not the factor itself.
const C_GAIN_ADD := 2
const C_BIAS := 3

const T_BIAS := 0
const T_POSSESSION := 1
const T_TERRITORY := 2
const T_EXPOSURE := 3
const T_RISK := 4
const T_DISCOUNT := 5
const T_RISK_HALF := 6
const T_FOCUS := 7
const T_ARRIVAL := 8
const T_OFF_BALANCE := 9
const T_RETENTION := 10
const T_DIRECT := 11
const T_LENGTH := 12
const T_CALL := 13
const T_BREAK := 14
const T_SECURE := 15
const T_GIVE_GO := 16
const T_PATTERN := 17
const T_LOFTED := 18
const T_TOUCH := 19
const T_STRETCH := 20
const T_SCAN := 21
const T_SET := 22
const T_DEVELOP := 23
const T_CURL := 24
const TERMS := 25

const TERM_NAMES := [
	"bias (every prior)", "possession_value", "territory", "turnover_exposure",
	"risk_weight", "future_discount", "the whole risk half", "focus_at",
	"arrival_gain", "off_balance", "retention_bias", "direct_bias",
	"length bias", "call_bias", "break_bias", "secure (regain)",
	"give_and_go", "pattern bias", "LOFTED_BIAS", "receiver_touch",
	"turnover_stretch", "scan_gain (the dwell)", "set_damp (the beat)",
	"develop (the run worth waiting for)", "curl (the bent lane)",
]

const TERM_COMPONENT := [
	C_SELF, C_SELF, C_SELF, C_SELF, C_SELF, C_SELF, C_SELF,
	C_GAIN_ADD, C_GAIN_ADD, C_SUCCESS,
	C_BIAS, C_BIAS, C_BIAS, C_BIAS, C_BIAS, C_BIAS, C_BIAS, C_BIAS, C_BIAS,
	C_BIAS,
	C_SELF, C_SELF, C_SUCCESS,
	C_SELF, C_SUCCESS,
]

## The slot each recorded factor is filed in, named for the call sites in
## `SimDecision` that file them.
const F_FOCUS := 0
const F_ARRIVAL := 1
const F_OFF_BALANCE := 2
const F_RETENTION := 3
const F_DIRECT := 4
const F_LENGTH := 5
const F_CALL := 6
const F_BREAK := 7
const F_SECURE := 8
const F_GIVE_GO := 9
const F_PATTERN := 10
const F_LOFTED := 11
const F_TOUCH := 12
const F_SET := 13
const F_CURL := 14
const FACTORS := 15

## Recorded-factor slot per term, or -1 for the ones `score_of` applies itself.
const TERM_SLOT := [
	-1, -1, -1, -1, -1, -1, -1,
	F_FOCUS, F_ARRIVAL, F_OFF_BALANCE,
	F_RETENTION, F_DIRECT, F_LENGTH, F_CALL, F_BREAK, F_SECURE, F_GIVE_GO,
	F_PATTERN, F_LOFTED, F_TOUCH,
	-1, -1, F_SET,
	-1, F_CURL,
]

## Mirrors `SimDecision.Action`, deliberately rather than importing it: this file
## is referenced from `SimDecision`, and naming it back would be a cycle.
const ACTION_NAMES := ["hold", "carry", "pass", "lofted", "through", "cross", "shot", "clear", "set", "dummy", "feint"]
const ACTIONS := 10

const APPLIED := 0
const FLIPS := 1
const TVD := 2
const DSCORE := 3
const VAL_SUM := 4
const VAL_N := 5
const VAL_LO := 6
const VAL_HI := 7
const STRIDE := 8

## Double precision, and not for accuracy's sake in the football: these are sums
## of tens of thousands of small numbers, and in float32 the mean of a constant
## term came out above its own maximum. An instrument that prints a mean outside
## the range beside it has no way of being believed about anything else.
static var _tally := PackedFloat64Array()
## Which action stopped being the best and which became it, per term. Two counts
## per action: lost the pick, won it.
static var _flow := PackedFloat64Array()
static var decisions := 0.0


static func reset() -> void:
	_tally.resize(TERMS * STRIDE)
	for i in _tally.size():
		_tally[i] = 0.0
	for t in TERMS:
		_tally[t * STRIDE + VAL_LO] = INF
		_tally[t * STRIDE + VAL_HI] = -INF
	_flow.resize(TERMS * ACTIONS * 2)
	for i in _flow.size():
		_flow[i] = 0.0
	decisions = 0.0


static func note_decision() -> void:
	if _tally.size() != TERMS * STRIDE:
		reset()
	decisions += 1.0


## The value the term itself came out at, wherever it applied. A factor sitting
## at its neutral value is not recorded: that is the term not applying, which is
## what `in` counts, and averaging the neutral value into the range would hide
## how far the term actually swings where it bites.
static func note_value(term: int, v: float) -> void:
	var base := term * STRIDE
	_tally[base + VAL_SUM] += v
	_tally[base + VAL_N] += 1.0
	_tally[base + VAL_LO] = minf(_tally[base + VAL_LO], v)
	_tally[base + VAL_HI] = maxf(_tally[base + VAL_HI], v)


## One decision's counterfactual for one term. `dscore` is the mean absolute
## change to a candidate's score over the candidates the term touched, `tvd` is
## how far the softmax's distribution over actions moved, and `from`/`to` are the
## actions that swapped the top of the list, or -1 when nothing swapped.
static func note(term: int, dscore: float, tvd: float, from_action: int, to_action: int) -> void:
	var base := term * STRIDE
	_tally[base + APPLIED] += 1.0
	_tally[base + DSCORE] += dscore
	_tally[base + TVD] += tvd
	if from_action < 0:
		return
	_tally[base + FLIPS] += 1.0
	var f := term * ACTIONS * 2
	if from_action < ACTIONS:
		_flow[f + from_action * 2] += 1.0
	if to_action >= 0 and to_action < ACTIONS:
		_flow[f + to_action * 2 + 1] += 1.0


static func at(term: int, slot: int) -> float:
	var i := term * STRIDE + slot
	return _tally[i] if i >= 0 and i < _tally.size() else 0.0


## The action that most often lost the pick to this term, and the one that most
## often won it: "carry -> pass". Empty when the term never flipped one.
static func flip_text(term: int) -> String:
	if at(term, FLIPS) <= 0.0:
		return ""
	var f := term * ACTIONS * 2
	var lost := -1
	var won := -1
	for a in ACTIONS:
		if lost < 0 or _flow[f + a * 2] > _flow[f + lost * 2]:
			lost = a
		if won < 0 or _flow[f + a * 2 + 1] > _flow[f + won * 2 + 1]:
			won = a
	return "%s -> %s" % [ACTION_NAMES[lost], ACTION_NAMES[won]]


## What a factor slot reads as when the term is not there. Additive corrections
## contribute nothing; multiplicative priors are 1.
static func neutral_of(slot: int) -> float:
	return 0.0 if slot >= 0 and slot < FACTORS and _slot_is_additive(slot) else 1.0


static func _slot_is_additive(slot: int) -> bool:
	for t in TERMS:
		if TERM_SLOT[t] == slot:
			return TERM_COMPONENT[t] == C_GAIN_ADD
	return false
