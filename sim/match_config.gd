class_name SimMatchConfig
extends RefCounted
## Everything a match needs to be reproducible from a seed.

enum Fidelity {
	FULL,     ## The player's match. Everything in PLAN.md §3 and §4.
	REDUCED,  ## Fast-forwarding the player's own match: same logic, coarser cadence.
}

var seed_value := 1
var home: SimTeam = null
var away: SimTeam = null
var pitch: SimPitch = SimPitch.regulation()
var env: SimEnv = SimEnv.new()
var fidelity := Fidelity.FULL

## Match length in minutes of match clock.
var minutes := 90.0

## Match-clock seconds per simulated second.
##
## At 1.0 the clock is real time and a 90-minute match takes 90 minutes to
## watch. Above 1.0 the clock runs fast: the scoreboard still reads 0-90 and
## the referee still adds the same stoppage time, but the whole thing is played
## out in `minutes / clock_rate` minutes of football. Nothing else in the sim
## changes — players run at human speeds, the ball obeys the same physics, and
## the tick is still 1/60 s — so a compressed match is not a sped-up one. What
## it is instead is a match containing proportionally fewer events, which is a
## tuning problem and is why this defaults to 1.0 (PLAN.md §11.1.1).
var clock_rate := 1.0

## How hard the football itself plays for a goal, from 0 at real time to 1 at the
## 30x match the 3D view opens with.
##
## `docs/INVARIANTS.md` asks for exactly this and says why: a match holds
## `5400 / clock_rate` seconds of football, so goals per match is goals per second
## of football times that, and holding goals per match steady across match lengths
## needs goals per second to scale with `clock_rate`. Fatigue is the model to
## copy -- drain scaled by `clock_rate` over a match `1 / clock_rate` as long
## cancels exactly. This is the same idea for the scoring side, and it is the
## reason a constant that affects scoring has to be reachable from one place.
##
## It is not a fiddle to hit a number, it is the football of the format. A side
## playing three minutes of football plays like a side chasing a game in the
## ninety-fourth minute, because that is what it is: there is no next possession
## to build toward and a ball kept is a ball wasted. Every constant that reads
## this keeps its measured, patient value at `clock_rate` 1, so the bands, the
## goldens and every measurement in `docs/STATUS.md` describe the same engine
## they always did.
##
## Logarithmic rather than linear because what it feeds saturates: past a point a
## side cannot play any more directly than it already is, and the difference
## between 30x and 60x is not twice the urgency.
func urgency() -> float:
	if urgency_override >= 0.0:
		return clampf(urgency_override, 0.0, 1.0)
	if _urgency < 0.0:
		_urgency = 0.0 if clock_rate <= 1.0 else clampf(log(clock_rate) / log(30.0), 0.0, 1.0)
	return _urgency

var _urgency := -1.0

## Forces the value above, for measurement. Below zero it derives from the clock
## as it should.
##
## It exists because the fit cannot otherwise be looked at. The compressed match
## holds three minutes of football, so a whole one of them has about five shots
## in it and `diagnose`'s shot table is empty — and `diagnose` is where the
## answer to "which stage of a chance is losing the goal" actually lives. With
## this, `./run.sh diagnose --minutes 10 --urgency 1` reports ten minutes of the
## compressed match's football at the length the instruments were built for.
var urgency_override := -1.0


# --- The compressed match's scoring fit --------------------------------------
#
# Three knobs, and deliberately only three, all of them here rather than beside
# the mechanics they scale. `docs/INVARIANTS.md`: "a constant that affects
# scoring wants to be reachable from one place rather than buried in an
# expression", and this is that place. Every one of them is 1.0 — a no-op — at
# `clock_rate` 1, so the ninety-minute engine the goldens, the §11 bands and
# `docs/STATUS.md` all describe is exactly the engine it was.
#
# This is a fit to a format, not a football finding. The owner's call, made with
# the arithmetic in front of them: a three-minute match holds 180 seconds of
# football, 2.7 goals in 180 seconds is 81 goals per ninety minutes of play, and
# nothing that reads as football produces that. So the compressed match is tuned
# to the scoreline and the real-time match is left alone. Anything measured
# through these values is a measurement of the format, and the honest way to ask
# what the football is doing is still `clock_rate` 1.
#
# Why these three. Goals are shots times conversion, so a fit needs one knob on
# each and a third to keep the shape from going somewhere silly. Appetite decides
# how often a sight of goal is taken rather than worked; the aim scale decides how
# many of those are on target; the keeper scale decides how many on target go in.
# Nothing here touches where players run, what a pass is worth or how the ball
# behaves, so the football between the shots is the football that was built.

## What a shot is worth over and above the goal it might be, multiplied. The
## engine's own comment beside `_add_shot`'s bias says this is not the knob for
## how often it shoots. In a football-first engine that is right. This is the
## format admitting it is using it as one anyway.
const SHOT_APPETITE_URGENT := 8.0
## Multiplier on `SimTouch.SHOT_AIM_BASE`, so below one is a straighter shot.
const SHOT_SIGMA_URGENT := 0.15
## Multiplier on the keeper's save chance. He still dives, still reads it, still
## has his attributes -- he just keeps out fewer of them.
const KEEPER_SAVE_URGENT := 0.15
## Multiplier on how far he can get to a ball, which is the larger half of him.
## Measured: halving the save roll alone moved conversion by a seventh, because
## most shots never reach the roll -- a keeper whose reach covers the shot has
## already gathered it. Below one the corners of the goal come back into play.
const KEEPER_REACH_URGENT := 0.35


func shot_appetite() -> float:
	return lerpf(1.0, SHOT_APPETITE_URGENT, urgency())


func shot_sigma_scale() -> float:
	return lerpf(1.0, SHOT_SIGMA_URGENT, urgency())


func keeper_save_scale() -> float:
	return lerpf(1.0, KEEPER_SAVE_URGENT, urgency())


func keeper_reach_scale() -> float:
	return lerpf(1.0, KEEPER_REACH_URGENT, urgency())


## Recording the positional trace costs memory and time; batch runs turn it off.
var trace_enabled := false
var events_enabled := true

## Multiplies every decision cadence in the engine: off-ball targets, chase
## assignment, perception refresh, the value-field ascent and the pressure map.
## Reduced fidelity halves them all (PLAN.md §2.5). The physical layer — ball
## integration, locomotion, separation, contact — is never strided, because
## that is where the behaviour a coarse run is meant to check actually lives.
func decision_stride() -> int:
	return 2 if fidelity == Fidelity.REDUCED else 1


## Ticks of simulation a match of this length takes. The clock rate divides it:
## the match clock still runs to `minutes`, but it gets there in fewer ticks.
func total_ticks() -> int:
	return int(round(minutes * 60.0 / maxf(clock_rate, 0.001) * float(SimConsts.TICK_HZ)))
