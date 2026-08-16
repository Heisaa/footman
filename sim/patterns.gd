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
## The one-two: the longest lay-off it can start from, how close the marker has to
## be for there to be anybody to go past, and how far past him the runner goes.
const ONE_TWO_MAX := 22.0
const ONE_TWO_MARKED := 6.0
const ONE_TWO_AHEAD := 12.0
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
		SimPattern.Kind.RUN_IN_BEHIND:
			_try_run_in_behind(ctx, team, pattern)
		SimPattern.Kind.ONE_TWO:
			_try_one_two(ctx, team, pattern)
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


## A forward sets off past the last defender, and the man on the ball is asked
## for the pass.
##
## **It was installed in a plan and had no trigger.** `high_press_direct` calls
## `install(Kind.RUN_IN_BEHIND, 0.8)`, the kind has a name and a cooldown, and
## `_try_trigger`'s match had no case for it — so it fell through `_: pass` and
## could never fire. A player choosing the direct plan was paying for a named
## pattern that did nothing, and the post-match screen reported it as zero fires
## rather than as missing, which is the one reading that looks like a tactical
## choice not coming off.
##
## The trigger is the football statement the off-ball layer cannot make on its
## own: `SimOffBall` scores a run in behind against a move into space every time,
## and a plan that says *go* wants the run made because the plan said so. So the
## conditions are the plan's, not the value function's — the carrier has a moment,
## the ball is far enough up that the pass exists, and there is a forward onside
## with grass to run into. Everything after that is the pattern layer's ordinary
## machinery: `movement_override` sends him, `pass_bias` lifts the ball to him,
## and `_succeeded` asks whether he got it.
static func _try_run_in_behind(ctx: SimContext, team: int, pattern: SimPattern) -> void:
	var carrier_id := ctx.possession_player
	if carrier_id < 0:
		return
	var carrier := ctx.players[carrier_id]
	if carrier.team != team or carrier.is_keeper:
		return
	# He has to be able to look up and hit it. The same test the switch makes,
	# for the same reason: a man under pressure plays what is nearest.
	if ctx.pressure_on(carrier) > 0.7:
		return
	var dir := ctx.pitch.attack_dir(team)
	# Not from deep inside our own half — the ball cannot be played that far, and
	# `SimOffBall._behind_point` refuses the run there on the same ground.
	if carrier.pos.x * dir < -ctx.pitch.half_length * 0.25:
		return
	var line := SimReferee.believed_offside_line(ctx, carrier) * dir
	var runner: SimPlayer = null
	var best := -INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if p.id == carrier_id or p.is_keeper or not p.on_pitch:
			continue
		if not SimRole.is_attacking(p.role):
			continue
		# Onside now, so the run starts legal and the timing of the release is
		# what decides it — the same contract `SimOffBall` BEHIND is written to.
		if p.pos.x * dir > line:
			continue
		# Ahead of the ball, or level with it.
		if (p.pos.x - carrier.pos.x) * dir < -6.0:
			continue
		if p.dist_to(carrier.pos) > 40.0:
			continue
		# The one nearest to going, so the pattern picks the man already on the
		# shoulder rather than the deepest forward on the pitch.
		var shoulder: float = p.pos.x * dir
		if shoulder > best:
			best = shoulder
			runner = p
	if runner == null:
		return
	var depth: float = minf(line + SimOffBall.BEHIND_DEPTH, ctx.pitch.half_length - 3.0)
	if depth - best < 4.0:
		return
	var target := Vector3(depth * dir, 0.0, runner.pos.z * 0.85)
	_fire(ctx, team, pattern, runner.id, carrier_id, ctx.pitch.clamp_to_pitch(target, 2.0), WINDOW)


## The one-two: the man who has just laid it off goes past his marker, and the
## ball is asked for back.
##
## `docs/THE_FOOTBALL.md` 31. Half of it was already here and the half that was
## missing is the half that makes it a move rather than a prior:
## `SimDecision.give_and_go` prices the return ball and `SimOffBall._just_passed`
## lifts the passer's own run score, so the engine *valued* a one-two and never
## *made* one. Nothing committed the passer to going, nothing named the move, and
## §5.3 wants a small number of recognisable things a player can count.
##
## As a pattern all of that comes for free and from one place: `movement_override`
## sends him past his man, `pass_bias` lifts the ball back to him, `_succeeded`
## asks whether he got it, and it appears on the post-match screen with a rate.
## `destination_for` reads the override, so the return ball is aimed where he is
## going rather than at the yard he laid it off from -- which is the defect that
## made the third man fire seventy-one times and succeed none, and this move has
## exactly the same shape.
##
## The runner is the passer, which is what separates it from the third man: there
## the ball goes past the receiver to a man beyond him, here it comes straight
## back to the man who gave it.
static func _try_one_two(ctx: SimContext, team: int, pattern: SimPattern) -> void:
	var ball := ctx.ball
	if ball.last_touch_team != team or not SimTelemetry.is_pass_kind(ball.last_touch_kind):
		return
	if ctx.tick_index - ball.last_touch_tick > 8:
		return
	var passer_id := ball.last_touch_player
	if passer_id < 0:
		return
	var passer := ctx.players[passer_id]
	if passer.is_keeper or not passer.on_pitch:
		return
	# A short ball, played forward. A forty-metre diagonal is not a one-two, and
	# neither is a square ball across the back four.
	var receiver_id := ball.intended_target
	if receiver_id < 0 or receiver_id == passer_id:
		return
	var receiver := ctx.players[receiver_id]
	var dir := ctx.pitch.attack_dir(team)
	var gap := passer.dist_to(receiver.pos)
	if gap < 5.0 or gap > ONE_TWO_MAX:
		return
	if (receiver.pos.x - passer.pos.x) * dir < 2.0:
		return
	# There has to be a man to go past. An unmarked player who plays it and runs
	# has made a give-and-go, which the prior already handles; the pattern is the
	# one where a marker gets left behind.
	var marker := ctx.nearest_opponent(passer)
	if marker == null or marker.is_keeper or marker.dist_to(passer.pos) > ONE_TWO_MARKED:
		return
	# Past him on the goal side, and past the man he gave it to, which is what
	# makes the return ball worth anything.
	var target := Vector3(
		passer.pos.x + dir * ONE_TWO_AHEAD, 0.0,
		passer.pos.z + signf(passer.pos.z - marker.pos.z) * 3.0)
	_fire(ctx, team, pattern, passer_id, receiver_id, ctx.pitch.clamp_to_pitch(target, 1.5), WINDOW)


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
		if int(run["runner"]) != p.id:
			continue
		var target: Vector3 = run["target"]
		# A pattern's runner is skipped by `SimOffBall._assign`, so he has no
		# intent -- and `point_for` therefore never applies the check-back that
		# keeps a BEHIND runner onside. He ran to `line + BEHIND_DEPTH` and stood
		# there waiting to be flagged.
		#
		# Measured the day `RUN_IN_BEHIND` was given a trigger: offsides went from
		# 5.7 to 13.3 a team per football-90 and broke the §11 sanity ceiling of
		# 12. Two layers each had half of one rule, which is how the third man came
		# to be aimed at by dead reckoning as well.
		#
		# So the same rule, in the one place the pattern layer owns: until the ball
		# is actually coming to him, he holds a stride short of the line, and the
		# next tick sends him again. That is the arrival timed rather than the run
		# cancelled, and it is what `SimOffBall.point_for` already says in words.
		if int(run["kind"]) == SimPattern.Kind.RUN_IN_BEHIND \
				and ctx.ball.intended_target != p.id:
			var dir := ctx.pitch.attack_dir(p.team)
			var line: float = SimReferee.believed_offside_line(ctx, p) * dir
			if p.pos.x * dir > line - 0.4:
				return Vector3((line - 0.4) * dir, 0.0, target.z)
		return target
	return Vector3.INF


## Whether a live pattern ever has a ball to bias.
##
## A success rate of zero has two causes that look identical from outside: the
## ball the pattern asks for was played and did not come off, or **no such ball
## was ever on the man's list**, in which case the pattern is decoration and no
## amount of `strength` reaches it. The second is a gate upstream of every value
## knob, which is what this project keeps being caught by, so it is counted
## rather than argued about.
##
## Per kind: `weighed` is pass candidates scored anywhere on the pitch while a
## firing of that kind was live for the passer's side, and `offered` is the ones
## that actually met the bias condition and were lifted. `weighed` is deliberately
## the wider population — a pattern whose ball is 1 in 200 of everything the side
## considers is a pattern the softmax will not find.
##
## One-way, like every tally in `sim/`: never read back, and it never touches
## `ctx.rng`.
static var asked_weighed := PackedInt32Array()
static var asked_offered := PackedInt32Array()


static func reset_tallies() -> void:
	asked_weighed.resize(SimPattern.KIND_NAMES.size())
	asked_offered.resize(SimPattern.KIND_NAMES.size())
	for i in asked_weighed.size():
		asked_weighed[i] = 0
		asked_offered[i] = 0


## Multiplier applied to a pass candidate that a live pattern is asking for.
static func pass_bias(ctx: SimContext, player: SimPlayer, target_id: int, point: Vector3) -> float:
	var bias := 1.0
	for run in ctx.pattern_runs:
		if int(run["team"]) != player.team:
			continue
		var pattern: SimPattern = run["pattern"]
		var strength: float = 1.0 + pattern.strength
		var kind := int(run["kind"])
		if kind < asked_weighed.size():
			asked_weighed[kind] += 1
		var wanted := false
		match kind:
			SimPattern.Kind.SWITCH_FAR_SIDE:
				var target: Vector3 = run["target"]
				wanted = signf(point.z) == signf(target.z) \
					and absf(point.z) > ctx.pitch.half_width * 0.3
			_:
				wanted = target_id >= 0 and target_id == int(run["runner"])
		if wanted:
			if kind < asked_offered.size():
				asked_offered[kind] += 1
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
