class_name SimChoices
extends RefCounted
## The two-way coin the softmax tossed, for every decision in the match.
##
## Link 6 of the chain, and the two chains that begin at a decision rather than at a
## spell. `docs/DIAGNOSTICS.md`, "The chain", has the rest.
##
## It exists for one measurement, and the measurement is the only unconfounded one
## the project has. Every split in `tools/diagnostics.gd` compares what happened
## after a carry with what happened after a pass, and every one of them is
## confounded: a man who carries is a man who had grass in front of him, so the
## outcome beside the act is partly the act and mostly the situation it was chosen
## in. No amount of matches fixes that. It is the wrong question asked precisely.
##
## But options here are chosen by softmax and never by argmax, so when two kinds of
## act score close together **which one gets played is decided by `ctx.rng` and by
## nothing about the situation**. That is random assignment, and the engine has
## been running the trial a few thousand times a match since it was written.
## Condition on the near-ties, split by what came out, and the gap between the arms
## is the causal effect of the choice rather than a fact about where the choice was
## taken from.
##
## Two things make it better than a real trial. The propensity is not estimated, it
## is the number the engine used -- `p` below is exactly how likely the played kind
## was -- so how close a tie was to a coin flip is measured rather than assumed. And
## the two arms come from one match, so nothing about the football differs between
## them.
##
## What it cannot do is answer for the whole match. It is a *local* effect: it says
## what taking the pass instead of the carry was worth **on the decisions where the
## two were nearly equal**, which is the population the engine was undecided about.
## Where a carry wins by a mile it says nothing, and the softmax is not going to
## randomise those for anybody.
##
## A row per decision rather than a ring buffer, because the whole match is the
## sample: `SimDebug` keeps the last six hundred, which is half a minute.
##
## Same one-way-tap contract as the other two instruments: off unless asked for,
## never touches `ctx.rng`, nothing in `sim/` reads it back. It is not a telemetry
## event kind for the reason `SimDebug` gives -- `canonical_text` is hashed by the
## golden replay test.

static var enabled := false

## Slots of a row. The two kinds are the best-scoring action on the list and the
## best-scoring one that is a different action, `a` being the better of them.
const R_TICK := 0
const R_POSS := 1
const R_TEAM := 2
const R_KIND_A := 3
const R_KIND_B := 4
## The kind of act actually played. The near-tie arm is derived from it rather than
## stored beside it, so there is one answer to "what did he do" and not two.
const R_PLAYED := 5
## One bit per action kind that was generated at all.
##
## The distinction a chain lives on. A cross that was never a candidate and a cross
## that was scored and beaten are the same absence in every count in the project,
## and the fixes are in different functions -- the first is `_add_passes` not
## offering it, the second is what it is worth once offered. `SimDecision.lost`
## draws that line already but only in aggregate over a match, so it cannot say
## which *situations* went unserved.
const R_KINDS := 6
## Facts about the moment that no position can carry. Bit 0: a teammate was running
## in behind, which is the situation a through ball exists for.
const R_FLAGS := 7
const R_STRIDE := 8

const F_RUNNER_BEHIND := 1

static var _rows := PackedInt32Array()
## Kind A's share of the weight the softmax put on the two kinds together: the
## exact chance the coin came down on A, at the moment it was tossed.
static var _p := PackedFloat32Array()
## How far up the pitch the ball was, in metres toward the goal this team was
## attacking. It is here so the outcome can be the ground made *after* the
## decision rather than over the whole spell: half a spell's ground was covered
## before the coin was tossed, and including it is noise the arms do not differ in.
static var _progress := PackedFloat32Array()
## How wide he was, unsigned, in metres from the middle. The other half of "was
## this a situation for a cross", and the one a chain cannot ask the log for: a
## crossable moment where no cross was generated leaves no event behind at all.
static var _lateral := PackedFloat32Array()


static func reset() -> void:
	_rows.clear()
	_p.clear()
	_progress.clear()
	_lateral.clear()


static func note(tick: int, poss: int, team: int, kind_a: int, kind_b: int,
		played: int, p_a: float, progress: float, lateral: float,
		kinds: int, flags: int) -> void:
	_rows.append(tick)
	_rows.append(poss)
	_rows.append(team)
	_rows.append(kind_a)
	_rows.append(kind_b)
	_rows.append(played)
	_rows.append(kinds)
	_rows.append(flags)
	_p.append(p_a)
	_progress.append(progress)
	_lateral.append(lateral)


static func progress_of(row: int) -> float:
	return _progress[row] if row >= 0 and row < _progress.size() else NAN


static func lateral_of(row: int) -> float:
	return _lateral[row] if row >= 0 and row < _lateral.size() else NAN


static func generated(row: int, kind: int) -> bool:
	return (at(row, R_KINDS) & (1 << kind)) != 0


static func has_flag(row: int, flag: int) -> bool:
	return (at(row, R_FLAGS) & flag) != 0


static func count() -> int:
	return _p.size()


static func at(row: int, slot: int) -> int:
	var i := row * R_STRIDE + slot
	return _rows[i] if i >= 0 and i < _rows.size() else -1


static func p_of(row: int) -> float:
	return _p[row] if row >= 0 and row < _p.size() else NAN
