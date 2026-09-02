class_name SimTempo
extends RefCounted
## The possession's own phase -- settle, probe, attack -- and the tempo it sets.
## `docs/THE_FOOTBALL.md` 37.
##
## Football is not played at one tempo. It is twenty seconds of the ball going
## sideways at the back, then three passes in two seconds, and this engine had
## one rate for both. The rate the eye names first -- a touch every second --
## could not be slowed without the pass total falling with it (28). The phase
## raises the variance and leaves the mean alone: the same football, with
## phases in it.
##
## One state per side, and only the side with the ball is in one. It is driven
## by where the ball is and by the pressure on it, never by a timer, and every
## change is logged with its cause. **What makes it football rather than a knob
## is that the acceleration is caused**: a side attacks the moment a man is free
## between the opponents' lines -- the pocket the link players (30) were built
## to stand in -- or the ball is in the final third, or it has just been won
## with a break on. It settles when the ball is deep and unpressed, and probes
## between the two. Hysteresis is a margin either side of every line, and a
## different condition to leave a phase than to enter it, so a ball rolling
## along a boundary does not flicker it.
##
## The phase reads out as one number, `tempo_of`: the plan's `tempo`, moved
## down for a settle and up for an attack. Everything on the ball that read
## `tactics.tempo` reads this instead -- the discount on value that arrives
## later, the pace the pass is struck at, the width of the passer's look -- so
## three phases release the ball at three rates through one prior. Two readers
## are explicit because they are not a tempo: the dwell (`scan_scale`) is worth
## more to a settling man and almost nothing to an attacking one, and a
## settling side rations its runs (`SimOffBall.SETTLE_QUOTA`).
##
## It is a decision prior and nothing else. **No station reads it.** A phase
## that moved the shape would be a boolean in a positioning rule, which is a
## station that teleports (`docs/INVARIANTS.md`).
##
## The manager's tempo is not here. When the manager decides it, it is a bias
## on `SimTactics.tempo` -- the centre the three phases spread around -- and
## nothing in this file changes. Every figure below is a first value, unturned
## (`PLAN.md` §11.1.1).

enum { SETTLE, PROBE, ATTACK }
const NAMES := ["settle", "probe", "attack"]

## Why a phase was entered. Logged with every change, tallied by `diagnose`.
enum Cause { WON_DEEP, WON, WORKED_OUT, PRESSED, FREE_BETWEEN, FINAL_THIRD, BREAK, RESET, PLAYED_BACK, LOST }
const CAUSE_NAMES := [
	"won deep", "won", "worked out", "pressed", "free between the lines",
	"final third", "break on", "played back behind their midfield", "played back deep", "lost",
]

## How far the plan's tempo moves in each phase. At the default 0.65 that is
## 0.30 settling and 0.95 attacking; `SimTactics.discount_at` turns it into
## 0.88 against 0.73 a second, and `SimDecision.arrival_pace` into a ball
## struck 7% softer against 9% firmer.
const SETTLE_DROP := 0.35
const ATTACK_LIFT := 0.30

## The dwell by phase: a settling man takes another look, an attacking man
## plays what is in front of him.
const SCAN_SCALE := [1.5, 1.0, 0.25]

## A settling side keeps the ball short: a ball over this length is taxed at
## this rate per metre, on top of the length bias every pass already pays.
const SETTLE_LONG_FROM := 20.0
const SETTLE_LONG_TAX := 0.03

## A man on the ball is free below this pressure, and being pressed above the
## second. Two numbers because they are an entry and an exit: a settle ends
## when he is pressed and a probe settles again only once he is free.
const FREE_PRESSURE := 0.3
const PRESSED := 0.6
## Hysteresis, in metres, either side of a third's line and behind their
## midfield line.
const MARGIN := 6.0
## How far inside both of their lines a man has to stand to be between them.
const BETWEEN_MARGIN := 3.0

## Tallies for `diagnose`. Reset from `SimMatch.setup`.
static var entered := PackedInt32Array([0, 0, 0])
static var refreshes := 0


static func reset(ctx: SimContext) -> void:
	ctx.tempo_phase = PackedInt32Array([PROBE, PROBE])
	ctx.tempo_since = PackedInt32Array([0, 0])
	ctx.tempo_spell = PackedInt32Array([-1, -1])
	entered = PackedInt32Array([0, 0, 0])
	refreshes = 0


static func phase_of(ctx: SimContext, team: int) -> int:
	return ctx.tempo_phase[team] if team >= 0 and team < ctx.tempo_phase.size() else PROBE


## The plan's tempo, moved by the phase. The one number the ball is played at.
static func tempo_of(ctx: SimContext, team: int) -> float:
	var t: float = ctx.tactics(team).tempo
	match phase_of(ctx, team):
		SETTLE:
			return clampf(t - SETTLE_DROP, 0.0, 1.0)
		ATTACK:
			return clampf(t + ATTACK_LIFT, 0.0, 1.0)
	return t


## What the dwell (`SimDecision.scan_gain`) is worth in this phase.
static func scan_scale(ctx: SimContext, team: int) -> float:
	return float(SCAN_SCALE[phase_of(ctx, team)])


## What a ball of this length is worth in this phase, on top of its length bias.
static func length_scale(ctx: SimContext, team: int, distance: float) -> float:
	if phase_of(ctx, team) != SETTLE:
		return 1.0
	return 1.0 / (1.0 + maxf(distance - SETTLE_LONG_FROM, 0.0) * SETTLE_LONG_TAX)


## Advances both sides. Called from `SimMatch` at the pressure cadence, after
## possession has been derived; a scenario calls it once at its start.
static func advance(ctx: SimContext) -> void:
	refreshes += 1
	var holder_team := ctx.possession_team
	for team in ctx.tempo_phase.size():
		if team != holder_team:
			# A side without the ball is in no phase. A loose ball keeps the one
			# it had: the side that last had it is the likeliest to have it
			# next, and a fifty-fifty that reset both would settle every second
			# ball.
			if holder_team >= 0 and ctx.tempo_phase[team] != PROBE:
				_enter(ctx, team, PROBE, Cause.LOST)
			continue
		if ctx.tempo_spell[team] != ctx.possession_id:
			# A new spell starts where the ball was won: deep is a settle,
			# anywhere else a probe, and the triggers below may lift it at once.
			ctx.tempo_spell[team] = ctx.possession_id
			var deep := _ball_x(ctx, team) < -ctx.pitch.half_length / 3.0
			_enter(ctx, team, SETTLE if deep else PROBE, Cause.WON_DEEP if deep else Cause.WON)
		var next := _next(ctx, team, ctx.tempo_phase[team])
		if not next.is_empty():
			_enter(ctx, team, int(next["phase"]), int(next["cause"]))


## The ball, in metres up the pitch the way this side attacks.
static func _ball_x(ctx: SimContext, team: int) -> float:
	return ctx.ball.ground_pos().x * ctx.pitch.attack_dir(team)


## The transition, if any, for the side with the ball. Attack is entered from
## either other phase on its three triggers; every other move is one step.
static func _next(ctx: SimContext, team: int, current: int) -> Dictionary:
	var x := _ball_x(ctx, team)
	var third: float = ctx.pitch.half_length / 3.0
	# The holder is the man with it uncontested; a contested ball has nobody
	# free on it, and a keeper with it in his hands is never between the lines.
	var holder: SimPlayer = null
	if ctx.possession_player >= 0 and ctx.possession_player < ctx.players.size():
		holder = ctx.players[ctx.possession_player]
	var pressure: float = ctx.pressure_on(holder) if holder != null else 0.0
	if current != ATTACK:
		if x > third:
			return {"phase": ATTACK, "cause": Cause.FINAL_THIRD}
		if holder != null and not holder.is_keeper:
			if pressure < FREE_PRESSURE and between_the_lines(ctx, holder):
				return {"phase": ATTACK, "cause": Cause.FREE_BETWEEN}
			if x > -third + MARGIN and SimDecision.regain_urgency(ctx, holder) > 0.0:
				return {"phase": ATTACK, "cause": Cause.BREAK}
	match current:
		ATTACK:
			# Left only once the ball is back behind their midfield with room
			# to spare, and out of the final third by the same margin. All the
			# way back to the keeper is a settle at once.
			if x < -third - MARGIN and pressure < FREE_PRESSURE:
				return {"phase": SETTLE, "cause": Cause.PLAYED_BACK}
			var mid := SimOffBall.opponents_midfield_line(ctx, team)
			var back: float = third - MARGIN
			if not is_inf(mid):
				back = minf(back, mid - MARGIN)
			if x < back:
				return {"phase": PROBE, "cause": Cause.RESET}
		SETTLE:
			if x > -third + MARGIN:
				return {"phase": PROBE, "cause": Cause.WORKED_OUT}
			if holder != null and pressure > PRESSED:
				return {"phase": PROBE, "cause": Cause.PRESSED}
		PROBE:
			if x < -third - MARGIN and pressure < FREE_PRESSURE:
				return {"phase": SETTLE, "cause": Cause.PLAYED_BACK}
	return {}


## Whether this man stands between the opponents' midfield and their back
## line, inside both by `BETWEEN_MARGIN`. The pocket `SimOffBall._pocket_point`
## sends a link player to, read off the man instead of the station.
static func between_the_lines(ctx: SimContext, p: SimPlayer) -> bool:
	var mid := SimOffBall.opponents_midfield_line(ctx, p.team)
	if is_inf(mid):
		return false
	var dir := ctx.pitch.attack_dir(p.team)
	var line: float = SimReferee.offside_line(ctx, p.team) * dir
	if line - mid < SimOffBall.POCKET_GAP:
		return false
	var x := p.pos.x * dir
	return x > mid + BETWEEN_MARGIN and x < line - BETWEEN_MARGIN


static func _enter(ctx: SimContext, team: int, phase: int, cause: int) -> void:
	var from: int = ctx.tempo_phase[team]
	ctx.tempo_phase[team] = phase
	ctx.tempo_since[team] = ctx.tick_index
	if cause != Cause.LOST:
		entered[phase] += 1
	ctx.log_event(SimTelemetry.Ev.TEMPO, {
		"team": team, "phase": phase, "from": from, "cause": cause,
		"x": _ball_x(ctx, team),
	})
