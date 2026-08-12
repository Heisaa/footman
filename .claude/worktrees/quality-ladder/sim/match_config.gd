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
