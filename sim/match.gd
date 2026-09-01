class_name SimMatch
extends RefCounted
## The fixed-step tick loop and the orchestration of every other module.
##
## The simulation owns all state and all logic. It never reads the scene tree,
## the frame delta, the system clock or input. Presentation asks it for
## snapshots and nothing else (PLAN.md §2.1).

var ctx := SimContext.new()
var finished := false

## Per-stage timing, in microseconds. Off by default: reading the clock inside
## the tick loop is exactly the kind of thing the sim must not do in a real run,
## so this is a tuning facility and nothing else ever reads it.
var profile_enabled := false
var profile := {}

var _stagger := 0

## How long the ball is left running after it has crossed a line, in seconds.
##
## The restart used to be built on the tick the ball crossed it, and
## `SimSetPiece._begin` resets the ball onto the restart spot — so a ball rolling
## out for a throw-in disappeared from the touchline and reappeared *at* it in
## the same frame, which is the one moment the eye is actually following it. It
## runs on now, under nothing but drag, and the restart is built when it has
## stopped being watched.
##
## Deliberately *not* compressed with the clock, unlike the restart delays in
## `SimSetPiece._compress`. Those are dead time whose price grows as a share of a
## shorter match; this one's does not. Balls go out of play at a rate per second
## of football, and a compressed match is a shorter match, so it holds
## proportionally fewer of them — two seconds each is the same small share of the
## match at any clock rate.
const DEAD_BALL_LINGER := 2.0

## The restart the ball has already earned, held until the linger runs out, and
## the ticks left of it. Decided at the crossing rather than at the restart,
## because by then the ball is metres past the line it crossed and neither the
## side that touched it last nor the point it went out at can be read off it.
var _pending_restart := {}
var _dead_ball_ticks := 0
## The man sent to fetch the ball while play is dead, and where he is going.
var _fetcher_id := -1
var _fetch_point := Vector3.ZERO


func _stage(name: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	profile[name] = int(profile.get(name, 0)) + (now - since)
	return now


func setup(config: SimMatchConfig) -> void:
	# The two layers that keep state outside the context. Static state outlives
	# the match that filled it, so a match built after another one in the same
	# process — a batch, the view's `R`, its rewind, the second pass of
	# `determinism` — has to start from the same blank the first one did.
	SimOffBall.reset()
	SimMovement.reset()
	SimDecision.reset()
	SimTouch.reset_tallies()
	SimPatterns.reset_tallies()
	SimAblation.reset()
	SimChoices.reset()
	ctx.config = config
	ctx.rng = SimRng.new(config.seed_value)
	ctx.env = config.env
	ctx.pitch = config.pitch
	ctx.ball = SimBall.new()
	ctx.trajectory = SimTrajectory.new()
	ctx.telemetry = SimTelemetry.new()
	ctx.telemetry.trace_enabled = config.trace_enabled
	ctx.telemetry.events_enabled = config.events_enabled
	ctx.ballistics = SimBallistics.new()
	ctx.value = SimValueField.new()
	ctx.teams = [config.home, config.away]
	ctx.teams[0].team_index = SimConsts.TEAM_HOME
	ctx.teams[1].team_index = SimConsts.TEAM_AWAY

	ctx.players.clear()
	ctx.team_players = [PackedInt32Array(), PackedInt32Array()]
	var next_id := 0
	for team_index in 2:
		var team: SimTeam = ctx.teams[team_index]
		for slot in team.players.size():
			var p: SimPlayer = team.players[slot]
			p.id = next_id
			p.team = team_index
			p.slot = slot
			p.on_pitch = true
			p.clock_rate = config.clock_rate
			p.sent_off = false
			p.yellow_cards = 0
			p.stamina = 1.0
			p.vel = Vector3.ZERO
			p.distance_run = 0.0
			p.touches = 0
			p.passes_attempted = 0
			p.passes_completed = 0
			p.shots = 0
			# Stagger off-ball evaluation so no single tick evaluates everyone.
			p.next_decision_tick = _stagger
			_stagger = (_stagger + 1) % SimConsts.OFF_BALL_DECISION_TICKS
			ctx.players.append(p)
			ctx.team_players[team_index].append(next_id)
			next_id += 1
		for pattern in team.ensure_tactics().patterns:
			pattern.reset_counts()
	ctx.pattern_runs.clear()

	ctx.pressure.resize(ctx.players.size())
	ctx.tick_index = 0
	ctx.clock = 0.0
	ctx.elapsed_clock = 0.0
	ctx.period = SimConsts.Period.FIRST_HALF
	ctx.phase = SimConsts.Phase.KICKOFF
	ctx.score = [0, 0]
	ctx.possession_count = [0, 0]
	ctx.possession_id = -1
	ctx.possession_start_tick = 0
	ctx.possession_start_pos = Vector3.ZERO
	ctx.possession_last_pos = Vector3.ZERO
	ctx.possession_attack_dir = 1.0
	ctx.last_pass_from = -1
	ctx.last_pass_to = -1
	ctx.last_pass_tick = -100000
	ctx.last_pass_arrival_tick = -100000
	_pending_restart = {}
	_dead_ball_ticks = 0
	_fetcher_id = -1
	finished = false
	SimSetPiece.kickoff(ctx, SimConsts.TEAM_HOME)
	# The shape's ball starts on the real one rather than walking out from the
	# corner flag over the first few seconds of the match. Both sides start in
	# their defending shape, which is what a kickoff looks like.
	ctx.shape_ball = ctx.ball.ground_pos()
	ctx.shape_phase = PackedFloat32Array([0.0, 0.0])


# --- The tick loop ----------------------------------------------------------


## Advances the simulation one fixed step. Never takes a delta.
func tick() -> void:
	if finished:
		return
	var dt := SimConsts.DT
	if profile_enabled:
		_tick_profiled(dt)
		return

	_refresh_shared_state()

	SimPatterns.update(ctx)
	if ctx.in_play:
		SimPerception.update(ctx)
		SimMovement.update(ctx)
		SimKeeper.update(ctx)
	elif _dead_ball_ticks > 0:
		_run_down()
	else:
		SimSetPiece.update(ctx)

	for p in ctx.players:
		if p.on_pitch:
			p.locomote(dt)
	_separate_players()

	if ctx.in_play:
		SimDuel.resolve_contacts(ctx)

	ctx.ball.integrate(dt, ctx.env)

	if ctx.in_play:
		SimReferee.update(ctx)
		_check_ball_out_of_play()
	elif _dead_ball_ticks > 0:
		_advance_dead_ball()

	_advance_clock(dt)
	_record_trace()
	ctx.tick_index += 1


func _tick_profiled(dt: float) -> void:
	var t := Time.get_ticks_usec()
	_refresh_shared_state()
	t = _stage("shared state", t)
	SimPatterns.update(ctx)
	t = _stage("patterns", t)

	if ctx.in_play:
		SimPerception.update(ctx)
		t = _stage("perception", t)
		SimMovement.update(ctx)
		t = _stage("movement", t)
		SimKeeper.update(ctx)
		t = _stage("keeper", t)
	elif _dead_ball_ticks > 0:
		_run_down()
		t = _stage("set_piece", t)
	else:
		SimSetPiece.update(ctx)
		t = _stage("set_piece", t)

	for p in ctx.players:
		if p.on_pitch:
			p.locomote(dt)
	t = _stage("locomotion", t)
	_separate_players()
	t = _stage("separation", t)

	if ctx.in_play:
		SimDuel.resolve_contacts(ctx)
		t = _stage("duel+decision", t)

	ctx.ball.integrate(dt, ctx.env)
	t = _stage("ball", t)

	if ctx.in_play:
		SimReferee.update(ctx)
		_check_ball_out_of_play()
		t = _stage("referee", t)
	elif _dead_ball_ticks > 0:
		_advance_dead_ball()
		t = _stage("referee", t)

	_advance_clock(dt)
	_record_trace()
	_stage("bookkeeping", t)
	ctx.tick_index += 1


## Everything computed once per tick and shared by every agent. The single most
## important performance rule in the design is that no agent ever runs its own
## trajectory prediction or its own value field (PLAN.md §2.5).
func _refresh_shared_state() -> void:
	# The forecast is computed lazily: agents that need it call
	# ctx.trajectory_now(), and the first caller in a tick pays for everyone.
	ctx.invalidate_trajectory()
	# Before anything reads a station: the shape's own ball follows the real one
	# at a pace a footballer can hold. Never strided -- it is an integration, and
	# a coarse tier that stepped it four times as far would make a different
	# shape rather than a cheaper one.
	ctx.advance_shape(SimConsts.DT)
	if ctx.tick_index % (SimConsts.PRESSURE_TICKS * ctx.config.decision_stride()) == 0:
		ctx.update_pressure()
	ctx.update_possession()


## Soft push-apart over the capsule radius, weighted by strength: the stronger
## player yields less. No impulses, no bounce (PLAN.md §3.2).
## Sorted by X, so separation only tests neighbouring pairs. Nearly sorted from
## one tick to the next, so the insertion sort is effectively linear.
var _sweep := PackedInt32Array()
var _sweep_x := PackedFloat32Array()


func _separate_players() -> void:
	var n := ctx.players.size()
	var min_d := SimConsts.PLAYER_SEPARATION
	var min_d2 := min_d * min_d

	if _sweep.size() != n:
		_sweep.resize(n)
		_sweep_x.resize(n)
		for i in n:
			_sweep[i] = i
	# Insertion sort on X, over a flat copy of the coordinates so the inner loop
	# never chases object references. Twenty-two players barely move between
	# ticks, so this almost always does nothing.
	for i in n:
		_sweep_x[i] = ctx.players[_sweep[i]].pos.x
	for i in range(1, n):
		var id := _sweep[i]
		var x := _sweep_x[i]
		var j := i - 1
		while j >= 0 and _sweep_x[j] > x:
			_sweep[j + 1] = _sweep[j]
			_sweep_x[j + 1] = _sweep_x[j]
			j -= 1
		_sweep[j + 1] = id
		_sweep_x[j + 1] = x

	for si in n:
		var a := ctx.players[_sweep[si]]
		if not a.on_pitch:
			continue
		for sj in range(si + 1, n):
			var b := ctx.players[_sweep[sj]]
			var dx := b.pos.x - a.pos.x
			if dx >= min_d:
				break  # Sorted by X: nothing further along can be closer.
			if not b.on_pitch:
				continue
			var dz := b.pos.z - a.pos.z
			var d2 := dx * dx + dz * dz
			if d2 >= min_d2 or d2 < 1e-8:
				continue
			var d := sqrt(d2)
			var overlap := min_d - d
			var nx := dx / d
			var nz := dz / d
			# Weight by strength: total share sums to 1.
			var sa: float = 0.4 + a.attrs.strength * 0.6
			var sb: float = 0.4 + b.attrs.strength * 0.6
			var share_a := sb / (sa + sb)
			a.pos.x -= nx * overlap * share_a
			a.pos.z -= nz * overlap * share_a
			b.pos.x += nx * overlap * (1.0 - share_a)
			b.pos.z += nz * overlap * (1.0 - share_a)
	# Keep everyone on the field of play, with a little run-off behind the line.
	for p in ctx.players:
		p.pos.x = clampf(p.pos.x, -ctx.pitch.half_length - 3.0, ctx.pitch.half_length + 3.0)
		p.pos.z = clampf(p.pos.z, -ctx.pitch.half_width - 3.0, ctx.pitch.half_width + 3.0)


func _check_ball_out_of_play() -> void:
	var b := ctx.ball
	if b.over_goal_line(ctx.pitch) or b.over_touch_line(ctx.pitch):
		# The ball has left the field, so whatever shot was live ended here and
		# ended by missing. It has to be closed from this side: `_track_shot`
		# runs out of `SimReferee.update`, which the tick loop only calls while
		# the ball is in play, so a shot gone wide stayed open through the dead
		# ball and was charged to the next man to touch it -- which at a goal
		# kick is the keeper. That is what made the fate table read "keeper
		# saved, wide" for balls the keeper never went near, and it hid the goal
		# kicks the gather gate had just given back.
		# A goal crosses the same line: `_score_goal` below stamps its own fate
		# and clears the record, so close only what is not one.
		if not (b.over_goal_line(ctx.pitch) and absf(b.pos.z) <= ctx.pitch.goal_half_width \
				and b.pos.y <= ctx.pitch.goal_height):
			SimReferee.close_shot(ctx, false)
	if b.over_goal_line(ctx.pitch):
		# Goal, corner, or goal kick.
		var crossing_z := b.pos.z
		var scoring_end: int = 0 if b.pos.x > 0.0 else 1
		var scorer_team := SimConsts.TEAM_HOME if ctx.pitch.attack_dir(SimConsts.TEAM_HOME) > 0.0 else SimConsts.TEAM_AWAY
		if scoring_end == 1:
			scorer_team = SimConsts.other_team(scorer_team)
		if absf(crossing_z) <= ctx.pitch.goal_half_width and b.pos.y <= ctx.pitch.goal_height:
			_score_goal(scorer_team)
			return
		var defending := SimConsts.other_team(scorer_team)
		var last_team := b.last_touch_team
		if last_team == defending:
			_queue_restart({"kind": SimSetPiece.Kind.CORNER, "team": scorer_team, "side": signf(crossing_z)})
		else:
			_queue_restart({"kind": SimSetPiece.Kind.GOAL_KICK, "team": defending})
		return
	if b.over_touch_line(ctx.pitch):
		var team := SimConsts.other_team(b.last_touch_team) if b.last_touch_team >= 0 else SimConsts.TEAM_HOME
		_queue_restart({
			"kind": SimSetPiece.Kind.THROW_IN,
			"team": team,
			"pos": Vector3(b.pos.x, 0.0, signf(b.pos.z) * ctx.pitch.half_width),
		})


## Stops play and leaves the ball to run on. Nothing is arranged until
## `_advance_dead_ball` runs the linger out: `SimSetPiece._begin` is what puts
## the ball on the restart spot, and calling it here is what used to make the
## ball teleport off the touchline as it crossed it.
##
## `in_play` is false for the whole linger, so no one chases the ball off the
## pitch, no contact is resolved and the referee is not watching a ball that is
## no longer in the game. Players carry on to the steering targets they already
## had and run down, which is what a side does over the two seconds after a ball
## goes out.
func _queue_restart(restart: Dictionary) -> void:
	ctx.in_play = false
	ctx.phase = SimConsts.Phase.DEAD_BALL
	_pending_restart = restart
	_dead_ball_ticks = maxi(1, int(round(DEAD_BALL_LINGER * float(SimConsts.TICK_HZ))))
	# One man goes and fetches it while the rest pull up, which is both what a
	# side does and what stops the linger costing four seconds a restart: the
	# taker is chosen from whoever is nearest when the restart is finally built,
	# so if everybody has stood still for two metres from where they stopped, he
	# is two seconds of jogging further away than he used to be. Measured on seed
	# 7 at ten minutes, a flat run-down took throw-ins from 2.9 s to 6.7 s and
	# goal kicks from 3.9 s to 6.3 s, against an eight-second timeout that then
	# teleports him onto the ball.
	var fetch := ctx.pitch.clamp_to_pitch(Vector3(ctx.ball.pos.x, 0.0, ctx.ball.pos.z), 0.4)
	var fetcher := ctx.nearest_to(fetch, int(restart["team"]))
	_fetcher_id = fetcher.id if fetcher != null else -1
	_fetch_point = fetch


## Nobody chases a ball that has left the field.
##
## `desired_vel` is a velocity and not a destination, and nothing recomputes it
## while play is dead — so whatever a player was doing on the tick the ball
## crossed, he goes on doing for the whole linger, in a straight line, at the
## speed he was doing it. For the keeper who has just been beaten that is a
## sprint at where the ball went, which is now through the back of his own net.
##
## He pulls up instead, and so does everyone else. `clamp_to_pitch` hands a
## player inside the field his own position straight back, and `steer_to`'s
## deadband turns that into a stop; anyone already over a line is walked back on
## by the same expression. It is not the shape reorganising — that is the
## restart's job, a couple of seconds from now — it is twenty-two people seeing
## the ball go out and stopping running.
func _run_down() -> void:
	for p in ctx.players:
		if not p.on_pitch:
			continue
		if p.id == _fetcher_id:
			p.steer_to(_fetch_point, p.max_speed() * 0.7)
			continue
		p.steer_to(ctx.pitch.clamp_to_pitch(p.pos), p.max_speed() * 0.5)


## And the netting stops a body, the same as it stops the ball.
##
## Pulling up takes a stride or two, and a keeper beaten from close range is over
## his line before he has started, so the run-down alone only shortens how far
## into the goal he goes. Restricted to the goal mouth, and to the linger: a
## winger's momentum carrying him over the touchline is football, and there is
## nothing there for him to run into.
func _hold_bodies_out_of_net() -> void:
	var limit: float = SimConsts.NET_DEPTH_TOP - SimConsts.PLAYER_RADIUS
	for p in ctx.players:
		if not p.on_pitch or absf(p.pos.z) > ctx.pitch.goal_half_width:
			continue
		if absf(p.pos.x) - ctx.pitch.half_length <= limit:
			continue
		p.pos.x = signf(p.pos.x) * (ctx.pitch.half_length + limit)
		p.vel.x = 0.0


func _advance_dead_ball() -> void:
	_catch_in_net()
	_hold_bodies_out_of_net()
	_dead_ball_ticks -= 1
	if _dead_ball_ticks > 0:
		return
	var restart := _pending_restart
	_pending_restart = {}
	_fetcher_id = -1
	if restart.is_empty():
		return
	match int(restart["kind"]):
		SimSetPiece.Kind.CORNER:
			SimSetPiece.corner(ctx, int(restart["team"]), float(restart["side"]))
		SimSetPiece.Kind.GOAL_KICK:
			SimSetPiece.goal_kick(ctx, int(restart["team"]))
		SimSetPiece.Kind.THROW_IN:
			SimSetPiece.throw_in(ctx, int(restart["team"]), restart["pos"])
		SimSetPiece.Kind.KICKOFF:
			SimSetPiece.kickoff(ctx, int(restart["team"]))


## The netting, for the two seconds a scored ball is left running.
##
## The goal is the one place on the pitch with something behind it, and until the
## linger there was never a tick where that mattered — the ball crossed the line
## and was on the centre spot before it had moved again. Now it runs on, and a
## ball that carries on out of the back of the goal and away into the stand is a
## worse picture than the teleport was. It is caught, not bounced: a net takes
## the pace out of a ball and drops it, which is the whole of the model here.
##
## Only a scored ball, which is the only one the netting is between: a ball wide
## of the post or over the bar passes outside the net the view draws, and one
## crossing for a corner or a goal kick is nowhere near it.
##
## All four panels the view draws, not just the back. The first version stopped
## the ball on the back netting alone, so a shot angled across the goal ran out
## through the side panel, and one still rising at the line went up through the
## sloping roof — through the net, on the one ball everyone is watching.
func _catch_in_net() -> void:
	if int(_pending_restart.get("kind", -1)) != SimSetPiece.Kind.KICKOFF:
		return
	var b := ctx.ball
	var depth: float = absf(b.pos.x) - ctx.pitch.half_length
	if depth < 0.0:
		# In front of the line — a ball the net has already dropped, rolling
		# back out of the goal mouth. Nothing there to catch it.
		return
	var line: float = signf(b.pos.x) * ctx.pitch.half_length
	# The back panel slopes from `NET_DEPTH_FOOT` on the grass to
	# `NET_DEPTH_TOP` at the top of the back netting, which is the same shape
	# `_build_net` draws.
	var limit: float = lerpf(SimConsts.NET_DEPTH_FOOT, SimConsts.NET_DEPTH_TOP,
		clampf(b.pos.y / SimConsts.NET_BACK_HEIGHT, 0.0, 1.0)) - SimConsts.BALL_RADIUS
	if depth >= limit:
		b.pos.x = line + signf(b.pos.x) * limit
		# Horizontal pace only. Zeroing the fall as well leaves the ball hanging
		# in the netting for the rest of the linger, because this runs every tick
		# and takes away whatever gravity has just given it; what should happen
		# is that it drops down the net and settles in the goal.
		b.vel.x = 0.0
		b.vel.z *= 0.25
		b.spin = Vector3.ZERO
	# The side panels, one down each post.
	var z_limit: float = ctx.pitch.goal_half_width - SimConsts.BALL_RADIUS
	if absf(b.pos.z) > z_limit:
		b.pos.z = signf(b.pos.z) * z_limit
		b.vel.z = 0.0
		b.vel.x *= 0.25
		b.spin = Vector3.ZERO
	# The roof, sloping from the crossbar down to the top of the back netting.
	var roof: float = lerpf(ctx.pitch.goal_height, SimConsts.NET_BACK_HEIGHT,
		clampf(depth / SimConsts.NET_DEPTH_TOP, 0.0, 1.0)) - SimConsts.BALL_RADIUS
	if b.pos.y > roof:
		b.pos.y = roof
		# A net catches: the climb is taken, the fall is left to gravity.
		b.vel.y = minf(b.vel.y, 0.0)
		b.vel.x *= 0.25
		b.vel.z *= 0.25
		b.spin = Vector3.ZERO


func _score_goal(team: int) -> void:
	ctx.score[team] += 1
	var scorer := ctx.ball.last_touch_player
	var scorer_team := ctx.ball.last_touch_team
	if not ctx.active_shot.is_empty() and int(ctx.active_shot["team"]) == team:
		ctx.active_shot["on_target"] = true
		ctx.active_shot["goal"] = true
		ctx.active_shot["fate"] = "goal"
	elif scorer_team == team and scorer >= 0:
		# A cross that sails in, a pass that runs in off nobody: the touch was
		# never an attempt, but it scored, and a goal the shot count cannot see
		# leaves the books reading four goals off three on target. Written up
		# the way the real ledgers do it -- if it went in, it was a shot.
		var p := ctx.players[scorer]
		p.shots += 1
		ctx.log_event(SimTelemetry.Ev.SHOT, {
			"p": scorer,
			"team": team,
			"from": ctx.ball.last_touch_pos,
			"aim": ctx.ball.pos,
			"quality": 0.0,
			"first_time": false,
			"dist": SimConsts.horizontal_length(ctx.ball.pos - ctx.ball.last_touch_pos),
			"on_target": true,
			"goal": true,
			"blocked": false,
			"fate": "goal",
			"minute": ctx.minute(),
		})
	ctx.active_shot = {}
	SimReferee.add_stoppage(ctx, SimReferee.STOPPAGE_GOAL)
	ctx.log_event(SimTelemetry.Ev.GOAL, {
		"team": team,
		"p": scorer,
		"own_goal": scorer_team != team,
		"minute": ctx.minute(),
		"score_h": ctx.score[0],
		"score_a": ctx.score[1],
	})
	for p in ctx.players:
		if p.team == team:
			p.play_anim(SimConsts.Anim.CELEBRATE, 1.5)
			p.morale = minf(1.0, p.morale + 0.05)
		else:
			p.play_anim(SimConsts.Anim.DEJECTED, 1.5)
			p.morale = maxf(0.0, p.morale - 0.04)
	# The goal itself is scored, logged and celebrated on the tick the ball
	# crosses; only the kick-off waits. Deferring the whole thing would hold the
	# celebration back by two seconds, which is the wrong half of it to delay.
	_queue_restart({"kind": SimSetPiece.Kind.KICKOFF, "team": SimConsts.other_team(team)})


## The only place the match clock and the simulated tick are allowed to differ.
##
## Everything downstream of here — the period boundaries, the referee's added
## time, the scoreboard — is expressed in match-clock seconds and needs no
## knowledge of the rate. `SimMatchConfig.clock_rate` is 10 everywhere — the
## standard nine-minute match — and at 1.0 this is the increment it always was.
func _advance_clock(dt: float) -> void:
	var step := dt * ctx.config.clock_rate
	ctx.clock += step
	ctx.elapsed_clock += step
	var half_length_s := ctx.config.minutes * 60.0 * 0.5
	match ctx.period:
		SimConsts.Period.FIRST_HALF:
			if ctx.clock >= half_length_s + float(ctx.added_time_ticks) * SimConsts.DT and ctx.in_play == false:
				_end_period()
			elif ctx.clock >= half_length_s + float(ctx.added_time_ticks) * SimConsts.DT + 30.0:
				# Hard stop if play never breaks down.
				_end_period()
		SimConsts.Period.SECOND_HALF:
			var full := ctx.config.minutes * 60.0
			if ctx.clock >= full + float(ctx.added_time_ticks) * SimConsts.DT and ctx.in_play == false:
				_end_period()
			elif ctx.clock >= full + float(ctx.added_time_ticks) * SimConsts.DT + 30.0:
				_end_period()
		_:
			pass


func _end_period() -> void:
	# A period ends the moment play breaks down, which includes a ball still
	# rolling out for a throw-in that will now never be taken. Dropping the
	# pending restart matters: the half-time kick-off below is issued straight
	# away, and a linger left running would rearrange everyone on top of it two
	# seconds later.
	_pending_restart = {}
	_dead_ball_ticks = 0
	_fetcher_id = -1
	if ctx.period == SimConsts.Period.FIRST_HALF:
		ctx.period = SimConsts.Period.SECOND_HALF
		ctx.clock = ctx.config.minutes * 60.0 * 0.5
		ctx.pitch.swap_ends()
		ctx.added_time_ticks = 0
		SimReferee.reset_period(ctx)
		ctx.log_event(SimTelemetry.Ev.PERIOD, {"period": ctx.period})
		for p in ctx.players:
			# Half-time recovery.
			p.stamina = minf(1.0, p.stamina + 0.12)
		SimSetPiece.kickoff(ctx, SimConsts.TEAM_AWAY)
	else:
		ctx.period = SimConsts.Period.FULL_TIME
		ctx.log_event(SimTelemetry.Ev.PERIOD, {"period": ctx.period})
		finished = true


func _record_trace() -> void:
	if not ctx.config.trace_enabled:
		return
	if ctx.tick_index % SimConsts.TRACE_TICKS != 0:
		return
	var sample := PackedVector3Array()
	sample.resize(ctx.players.size() + 1)
	sample[0] = ctx.ball.pos
	for i in ctx.players.size():
		sample[i + 1] = ctx.players[i].pos
	ctx.telemetry.log_trace(sample)
	# And where the shape wanted each of them, alongside. `shape_position` is a
	# pure function of the context -- no rng, no state written -- so sampling it
	# here cannot change the match, and the keeper takes his own station rather
	# than an outfielder's, so his entry is meaningless and the diagnostics skip
	# him.
	var stations := PackedVector3Array()
	var targets := PackedVector3Array()
	var errands := PackedInt32Array()
	var facings := PackedFloat32Array()
	stations.resize(ctx.players.size())
	targets.resize(ctx.players.size())
	errands.resize(ctx.players.size())
	facings.resize(ctx.players.size())
	for i in ctx.players.size():
		var p := ctx.players[i]
		stations[i] = SimMovement.shape_position(ctx, p)
		targets[i] = p.move_target
		errands[i] = p.errand
		facings[i] = p.facing
	ctx.telemetry.log_shape(stations, targets, errands, facings)


# --- Driving ----------------------------------------------------------------


## Runs the whole match. The headless entry point and the fast-forward path both
## use this; it is the same code as watching at 1x, only stepped faster.
func run_to_completion(max_ticks: int = 0) -> void:
	var limit := max_ticks if max_ticks > 0 else ctx.config.total_ticks() + SimConsts.TICK_HZ * 600
	var steps := 0
	while not finished and steps < limit:
		tick()
		steps += 1
	if not finished:
		# Safety valve: a match that will not end is a bug, and silently running
		# forever is worse than stopping and saying so.
		ctx.log_event(SimTelemetry.Ev.PERIOD, {"period": SimConsts.Period.FULL_TIME, "truncated": true})
		finished = true


## Fills a caller-owned snapshot. Presentation keeps two and interpolates.
func write_snapshot(snap: SimSnapshot) -> void:
	snap.resize(ctx.players.size())
	snap.tick = ctx.tick_index
	snap.clock = ctx.clock
	snap.period = ctx.period
	snap.phase = ctx.phase
	snap.ball_pos = ctx.ball.pos
	snap.ball_vel = ctx.ball.vel
	snap.ball_spin = ctx.ball.spin
	for i in ctx.players.size():
		var p := ctx.players[i]
		snap.player_id[i] = p.id
		snap.player_team[i] = p.team
		snap.player_shirt[i] = p.shirt
		snap.player_pos[i] = p.pos
		snap.player_vel[i] = p.vel
		snap.player_facing[i] = p.facing
		snap.player_stamina[i] = p.stamina
		snap.player_anim[i] = p.anim
		snap.player_on_pitch[i] = 1 if p.on_pitch else 0
	snap.score[0] = ctx.score[0]
	snap.score[1] = ctx.score[1]
	snap.attack_x[0] = ctx.pitch.attack_dir(0)
	snap.attack_x[1] = ctx.pitch.attack_dir(1)
	snap.half_length = ctx.pitch.half_length
	snap.half_width = ctx.pitch.half_width
	snap.in_play = ctx.in_play
