class_name SimPatterns
extends RefCounted
## Named tactical patterns at run time (PLAN.md §5.3).
##
## A pattern is not new behaviour. It is a trigger condition plus a nudge to
## values the movement and decision layers were going to use anyway, exactly as
## §5.1 requires of everything in the tactical layer. What makes patterns worth
## having is not what they do mechanically but that they are *named, visible and
## counted*: "overlap left fired 11 times, 6 successful" is something a player
## can learn from, and "directness 0.7" is not.
##
## Each firing is logged, and each is judged after the fact so the post-match
## screen can report a success rate.

## How long a firing stays live before it is judged, in seconds.
const WINDOW := 4.0
const PRESS_WINDOW := 8.0
## How far up the pitch an overlap runs past the player it is overlapping.
const OVERLAP_AHEAD := 9.0


## Per-team evaluation, on the off-ball cadence. Cheap: a handful of distance
## checks per pattern, and most patterns reject on the first one.
static func update(ctx: SimContext) -> void:
	# Outcomes are judged every tick so a success is recorded the moment it
	# happens, but triggers only need the off-ball cadence: they are a dozen
	# distance checks per pattern and nothing about them changes in a sixtieth
	# of a second.
	_resolve_expired(ctx)
	if ctx.tick_index % SimConsts.OFF_BALL_DECISION_TICKS != 0:
		return
	for team in 2:
		for pattern in ctx.tactics(team).patterns:
			if not pattern.ready(ctx.tick_index):
				continue
			if _already_running(ctx, team, pattern.kind):
				continue
			_try_trigger(ctx, team, pattern)


static func _try_trigger(ctx: SimContext, team: int, pattern: SimPattern) -> void:
	# Most patterns are open-play moves. "Press the goal kick" is by definition
	# a dead-ball one, so the in-play test belongs per pattern rather than as a
	# single guard around the lot -- with one guard it could never fire at all.
	if pattern.kind != SimPattern.Kind.PRESS_THE_GOAL_KICK and not ctx.in_play:
		return
	match pattern.kind:
		SimPattern.Kind.OVERLAP_LEFT:
			_try_overlap(ctx, team, pattern, -1.0)
		SimPattern.Kind.OVERLAP_RIGHT:
			_try_overlap(ctx, team, pattern, 1.0)
		SimPattern.Kind.UNDERLAP:
			_try_underlap(ctx, team, pattern)
		SimPattern.Kind.SWITCH_FAR_SIDE:
			_try_switch(ctx, team, pattern)
		SimPattern.Kind.THIRD_MAN_RUN:
			_try_third_man(ctx, team, pattern)
		SimPattern.Kind.PRESS_THE_GOAL_KICK:
			_try_press_goal_kick(ctx, team, pattern)
		_:
			pass


# --- Triggers ---------------------------------------------------------------


## A wide player has the ball in the opponent half and the full-back behind them
## goes outside.
static func _try_overlap(ctx: SimContext, team: int, pattern: SimPattern, side: float) -> void:
	var carrier_id := ctx.possession_player
	if carrier_id < 0:
		return
	var carrier := ctx.players[carrier_id]
	if carrier.team != team or carrier.role != SimRole.WIDE:
		return
	if signf(carrier.pos.z) != side:
		return
	var dir := ctx.pitch.attack_dir(team)
	if carrier.pos.x * dir < 0.0:
		return
	# The full-back on the same flank, behind the ball.
	var runner: SimPlayer = null
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if p.id == carrier.id or p.role != SimRole.FB or not p.on_pitch:
			continue
		if signf(p.pos.z) != side:
			continue
		if p.pos.x * dir > carrier.pos.x * dir:
			continue
		if p.dist_to(carrier.pos) > 26.0:
			continue
		runner = p
		break
	if runner == null:
		return
	var target := Vector3(
		carrier.pos.x + dir * OVERLAP_AHEAD,
		0.0,
		side * (ctx.pitch.half_width - 3.0)
	)
	_fire(ctx, team, pattern, runner.id, carrier.id, ctx.pitch.clamp_to_pitch(target, 1.0), WINDOW)


## The same idea, but the runner goes inside rather than outside.
static func _try_underlap(ctx: SimContext, team: int, pattern: SimPattern) -> void:
	var carrier_id := ctx.possession_player
	if carrier_id < 0:
		return
	var carrier := ctx.players[carrier_id]
	if carrier.team != team or carrier.role != SimRole.WIDE:
		return
	var dir := ctx.pitch.attack_dir(team)
	if carrier.pos.x * dir < 4.0:
		return
	var side: float = signf(carrier.pos.z)
	var runner: SimPlayer = null
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if p.id == carrier.id or not p.on_pitch:
			continue
		if p.role != SimRole.CM and p.role != SimRole.AM and p.role != SimRole.FB:
			continue
		if p.dist_to(carrier.pos) > 24.0 or p.pos.x * dir > carrier.pos.x * dir:
			continue
		runner = p
		break
	if runner == null:
		return
	var target := Vector3(
		carrier.pos.x + dir * OVERLAP_AHEAD,
		0.0,
		side * ctx.pitch.half_width * 0.32
	)
	_fire(ctx, team, pattern, runner.id, carrier.id, ctx.pitch.clamp_to_pitch(target, 1.0), WINDOW)


## The ball is stuck on one flank and the far one is open.
static func _try_switch(ctx: SimContext, team: int, pattern: SimPattern) -> void:
	var carrier_id := ctx.possession_player
	if carrier_id < 0:
		return
	var carrier := ctx.players[carrier_id]
	if carrier.team != team:
		return
	if absf(carrier.pos.z) < ctx.pitch.half_width * 0.4:
		return
	# A switch is only on if the carrier has a moment on the ball.
	if ctx.pressure_on(carrier) > 0.7:
		return
	var far_z := -signf(carrier.pos.z) * ctx.pitch.half_width * 0.62
	var probe := Vector3(carrier.pos.x, 0.0, far_z)
	# And only if there is genuinely someone over there to switch to. Firing on
	# an empty far flank produces a pattern that fires constantly, changes
	# nothing, and reports a success rate of zero -- which is worse than not
	# having the pattern at all.
	var receiver := ctx.nearest_to(probe, team, carrier.id)
	if receiver == null or receiver.dist_to(probe) > 14.0:
		return
	if ctx.value.control_at(ctx, probe, team) < 0.6:
		return
	_fire(ctx, team, pattern, receiver.id, carrier.id, probe, WINDOW * 1.5)


## A pass has just gone into midfield; someone beyond it makes the run.
static func _try_third_man(ctx: SimContext, team: int, pattern: SimPattern) -> void:
	var ball := ctx.ball
	if ball.last_touch_team != team or not SimTelemetry.is_pass_kind(ball.last_touch_kind):
		return
	if ctx.tick_index - ball.last_touch_tick > 8:
		return
	var receiver_id := ball.intended_target
	if receiver_id < 0:
		return
	var receiver := ctx.players[receiver_id]
	var dir := ctx.pitch.attack_dir(team)
	var runner: SimPlayer = null
	var best := -INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if p.id == receiver_id or p.is_keeper or not p.on_pitch:
			continue
		if not SimRole.is_attacking(p.role):
			continue
		var ahead: float = (p.pos.x - receiver.pos.x) * dir
		if ahead < -4.0 or p.dist_to(receiver.pos) > 30.0:
			continue
		if ahead > best:
			best = ahead
			runner = p
	if runner == null:
		return
	var target := Vector3(runner.pos.x + dir * 11.0, 0.0, runner.pos.z * 0.8)
	_fire(ctx, team, pattern, runner.id, receiver_id, ctx.pitch.clamp_to_pitch(target, 1.5), WINDOW)


## The opponent has a goal kick: go and press it.
static func _try_press_goal_kick(ctx: SimContext, team: int, pattern: SimPattern) -> void:
	if ctx.in_play:
		return
	if ctx.restart_kind != SimSetPiece.Kind.GOAL_KICK:
		return
	if ctx.restart_team == team:
		return
	_fire(ctx, team, pattern, -1, -1, ctx.restart_pos, PRESS_WINDOW)


# --- Bookkeeping ------------------------------------------------------------


static func _fire(ctx: SimContext, team: int, pattern: SimPattern, runner_id: int, with_id: int, target: Vector3, window: float) -> void:
	pattern.fired += 1
	pattern.last_fired_tick = ctx.tick_index
	ctx.pattern_runs.append({
		"kind": pattern.kind,
		"team": team,
		"runner": runner_id,
		"with": with_id,
		"target": target,
		"fired": ctx.tick_index,
		"expires": ctx.tick_index + int(window * float(SimConsts.TICK_HZ)),
		"pattern": pattern,
	})
	ctx.log_event(SimTelemetry.Ev.PATTERN, {
		"kind": pattern.kind,
		"name": pattern.display_name,
		"team": team,
		"p": runner_id,
		"with": with_id,
		"pos": target,
		"minute": ctx.minute(),
		"phase": "fired",
	})


## Judges every firing whose window has closed. A pattern that is never judged
## is a pattern nobody can learn from.
static func _resolve_expired(ctx: SimContext) -> void:
	var i := 0
	while i < ctx.pattern_runs.size():
		var run: Dictionary = ctx.pattern_runs[i]
		if ctx.tick_index < int(run["expires"]):
			# Success can be settled early; failure has to wait for the window.
			if _succeeded(ctx, run):
				_close(ctx, run, true)
				ctx.pattern_runs.remove_at(i)
				continue
			i += 1
			continue
		_close(ctx, run, false)
		ctx.pattern_runs.remove_at(i)


static func _succeeded(ctx: SimContext, run: Dictionary) -> bool:
	var team: int = run["team"]
	var kind: int = run["kind"]
	var ball := ctx.ball
	match kind:
		SimPattern.Kind.PRESS_THE_GOAL_KICK:
			# Winning the ball back in the opponent's half.
			if ball.last_touch_team != team or int(ball.last_touch_tick) <= int(run["fired"]):
				return false
			return ball.pos.x * ctx.pitch.attack_dir(team) > 0.0
		SimPattern.Kind.SWITCH_FAR_SIDE:
			# A ball actually played to the far side and received there.
			if ball.last_touch_team != team or int(ball.last_touch_tick) <= int(run["fired"]):
				return false
			var target: Vector3 = run["target"]
			return signf(ball.pos.z) == signf(target.z) and absf(ball.pos.z) > ctx.pitch.half_width * 0.3
		SimPattern.Kind.OVERLAP_LEFT, SimPattern.Kind.OVERLAP_RIGHT, SimPattern.Kind.UNDERLAP:
			# The move worked if the ball got to where the run was going, whether
			# or not the runner is the player who ended up touching it.
			if ball.last_touch_team != team or int(ball.last_touch_tick) <= int(run["fired"]):
				return false
			var target: Vector3 = run["target"]
			return SimConsts.horizontal_length(ball.pos - target) < 12.0
		_:
			# The runner got the ball.
			var runner: int = run["runner"]
			if runner < 0:
				return false
			return ball.last_touch_player == runner and int(ball.last_touch_tick) > int(run["fired"])


static func _close(ctx: SimContext, run: Dictionary, ok: bool) -> void:
	var pattern: SimPattern = run["pattern"]
	if ok:
		pattern.succeeded += 1
	ctx.log_event(SimTelemetry.Ev.PATTERN, {
		"kind": run["kind"],
		"name": pattern.display_name,
		"team": run["team"],
		"p": run["runner"],
		"ok": ok,
		"minute": ctx.minute(),
		"phase": "outcome",
	})


static func _already_running(ctx: SimContext, team: int, kind: int) -> bool:
	for run in ctx.pattern_runs:
		if int(run["team"]) == team and int(run["kind"]) == kind:
			return true
	return false


# --- Hooks the other modules call -------------------------------------------


## Where a pattern wants this player to run, or Vector3.INF for "no opinion".
## The movement layer treats it as one more contribution to the target, not as a
## behaviour switch.
static func movement_override(ctx: SimContext, p: SimPlayer) -> Vector3:
	for run in ctx.pattern_runs:
		if int(run["runner"]) == p.id:
			return run["target"]
	return Vector3.INF


## Multiplier applied to a pass candidate that a live pattern is asking for.
static func pass_bias(ctx: SimContext, player: SimPlayer, target_id: int, point: Vector3) -> float:
	var bias := 1.0
	for run in ctx.pattern_runs:
		if int(run["team"]) != player.team:
			continue
		var pattern: SimPattern = run["pattern"]
		var strength: float = 1.0 + pattern.strength
		match int(run["kind"]):
			SimPattern.Kind.SWITCH_FAR_SIDE:
				var target: Vector3 = run["target"]
				if signf(point.z) == signf(target.z) and absf(point.z) > ctx.pitch.half_width * 0.3:
					bias *= strength
			_:
				if target_id >= 0 and target_id == int(run["runner"]):
					bias *= strength
	return bias


## True while this team should be pressing a goal kick.
static func pressing_restart(ctx: SimContext, team: int) -> bool:
	for run in ctx.pattern_runs:
		if int(run["team"]) == team and int(run["kind"]) == SimPattern.Kind.PRESS_THE_GOAL_KICK:
			return true
	return false


## True if this team's plan says the keeper plays short from a goal kick.
static func keeper_plays_short(ctx: SimContext, team: int) -> bool:
	for pattern in ctx.tactics(team).patterns:
		if pattern.kind == SimPattern.Kind.KEEPER_PLAYS_SHORT:
			return true
	return false


## Records a keeper-short firing, which is a set-piece routine rather than a
## triggered run, so it is counted where it happens.
static func note_keeper_short(ctx: SimContext, team: int) -> void:
	for pattern in ctx.tactics(team).patterns:
		if pattern.kind != SimPattern.Kind.KEEPER_PLAYS_SHORT:
			continue
		pattern.fired += 1
		pattern.last_fired_tick = ctx.tick_index
		ctx.pattern_runs.append({
			"kind": pattern.kind,
			"team": team,
			"runner": -1,
			"with": -1,
			"target": ctx.restart_pos,
			"fired": ctx.tick_index,
			"expires": ctx.tick_index + int(WINDOW * float(SimConsts.TICK_HZ)),
			"pattern": pattern,
		})
		ctx.log_event(SimTelemetry.Ev.PATTERN, {
			"kind": pattern.kind,
			"name": pattern.display_name,
			"team": team,
			"minute": ctx.minute(),
			"phase": "fired",
		})
		return


## Per-match report: what fired, how often, and how often it worked.
static func summary(ctx: SimContext, team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pattern in ctx.tactics(team).patterns:
		out.append({
			"name": pattern.display_name,
			"fired": pattern.fired,
			"succeeded": pattern.succeeded,
			"rate": pattern.success_rate(),
		})
	return out
