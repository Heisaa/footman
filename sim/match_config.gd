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
## it is instead is a match containing proportionally fewer events.
##
## Defaults to 10.0, the standard nine-minute match, everywhere — the owner
## never runs real-time games, so every instrument measures the match the
## player gets (DECISIONS.md, sixth amendment). `--clock-rate 1` recovers the
## patient engine for measurement; the fit knobs below are no-ops there, and
## `test_clock` guards that property.
var clock_rate := 10.0

## How hard the football itself plays for a goal, from 0 at real time to 1 at
## 30x, where the fit was made. The 3D view now opens at 10x — a nine-minute
## match — which lands at about 0.68; the anchor stays at 30 until the
## tuning-freeze refit (owner's call, DECISIONS.md sixth amendment).
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
## It exists to look at the fit in isolation. With the clock defaulting to 10
## everything measures the fit already; what cannot otherwise be seen is the
## fit *without* the shortened match — `./run.sh diagnose --minutes 90
## --clock-rate 1 --urgency 0.68` is the standard match's scoring pressure over
## a full ninety of football, which gives `diagnose`'s shot table a population
## the nine-minute match cannot. `--urgency 1` is the 30x anchor the fit was
## made at.
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
##
## Unsettled, and the only one of the four that is. It sits at 8 because forty
## compressed matches said it did nothing -- shots per team 2.29 to 2.40 across
## 1 to 8 -- and a knob that does nothing costs nothing to leave alone. Three
## seeds during the re-fit suggested it now moves shots by a fifth, but three
## seeds cannot see a shot count at all: the same seed swung 14 to 32 between
## configurations that never touched shooting. Forty matches beat three seeds, so
## it stays until a batch says otherwise. `docs/STATUS.md` has the comparison.
const SHOT_APPETITE_URGENT := 8.0
## Multiplier on `SimTouch.SHOT_AIM_BASE`, so below one is a straighter shot.
##
## Load-bearing, and it is what lets the two below stay near one. The fit reduces
## to a single curve: conversion is the goal-bound share times one minus the save
## rate, which predicted all eight measured configurations inside a tenth, and
## the compressed match needs about 0.57 of it. At this value the goal-bound
## share is about 0.78, which leaves room for a keeper saving a third. Left alone
## the share is about 0.50 and the equation has no solution at *any* keeper
## strength -- measured, the aim knob alone reached 1.80 goals against the old
## fit's 4.10 on the same instrument. That is the reason the format's unrealism
## is placed on the shooting rather than on the goalkeeper.
const SHOT_SIGMA_URGENT := 0.15
## Multiplier on the keeper's save chance. He still dives, still reads it, still
## has his attributes -- he just keeps out fewer of them.
const KEEPER_SAVE_URGENT := 0.7
## Multiplier on how far he can get to a ball, which is the larger half of him.
## Measured: halving the save roll alone moved conversion by a seventh, because
## most shots never reach the roll -- a keeper whose reach covers the shot has
## already gathered it. Below one the corners of the goal come back into play.
##
## Both keeper knobs were 0.15 and 0.35, fitted against a keeper who was quietly
## compensating with `SimKeeper._try_gather`. With the gather gone they left him
## saving 2% of what he faced -- one save in thirty minutes of football -- which
## is the single most visible thing on the screen, because the viewer is watching
## him during every shot. At 0.7 and 0.75 he saves about a third, against the
## 46% the same keeper manages at `clock_rate` 1, and the scoreline is unchanged.
const KEEPER_REACH_URGENT := 0.75


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
