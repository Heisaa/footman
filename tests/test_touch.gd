class_name TestTouch
extends SimTestCase
## The touch model (PLAN.md §3.3) and the Phase 1 dribbling criterion.
##
## The headline requirement is that the ball is never glued to a foot: a
## dribbler pushes it ahead and runs onto it, and sometimes the touch gets away
## from them. Both of those are what the tests below measure.


func run() -> void:
	_dribble_puts_the_ball_ahead()
	_the_ball_is_never_glued_to_a_foot()
	_touches_sometimes_get_away()
	_pressure_widens_the_error()
	_first_touch_leaves_residual_pace()
	_pass_solver_lands_near_the_target()
	_execution_accuracy_falls_off_with_distance()


static func _drill_context(seed_value: int = 5) -> SimContext:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = 1.0
	return SimRunner.build(opts).ctx


func _dribble_puts_the_ball_ahead() -> void:
	var ctx := _drill_context()
	var p := ctx.players[9]
	p.pos = Vector3.ZERO
	p.vel = Vector3(5.0, 0.0, 0.0)
	p.facing = 0.0
	ctx.ball.reset(Vector3(0.5, SimConsts.BALL_RADIUS, 0.0))
	SimTouch.dribble(ctx, p, Vector3(1, 0, 0), 0.7)
	check_greater(ctx.ball.vel.x, p.vel.x, "a dribble touch must move the ball ahead of the runner")
	check_less(ctx.ball.vel.x, p.vel.x + 6.0, "but not blast it away")
	check_near(ctx.ball.vel.y, 0.0, 0.01, "a dribble touch keeps the ball down")


func _the_ball_is_never_glued_to_a_foot() -> void:
	# Run a real match and watch the distance from the ball to whoever last
	# touched it. If the ball were glued, that distance would sit near zero.
	#
	# Four minutes, not ten. Both bounds below are *shares of the samples*, and a
	# share is settled long before the whole-match count is: four minutes is
	# already fourteen thousand ticks, so the `> 1000 samples` floor has an order
	# of magnitude of headroom and the ratios move in the third decimal after the
	# first minute.
	var opts := SimRunner.Options.new()
	opts.seed_value = 21
	opts.minutes = 4.0
	var m := SimRunner.build(opts)
	var samples := 0
	var glued := 0
	var free_running := 0
	while not m.finished:
		m.tick()
		if not m.ctx.in_play:
			continue
		var holder := m.ctx.ball.last_touch_player
		if holder < 0:
			continue
		var d := m.ctx.players[holder].dist_to(m.ctx.ball.ground_pos())
		samples += 1
		if d < 0.35:
			glued += 1
		if d > 2.0:
			free_running += 1
	check_greater(float(samples), 1000.0, "the drill must have produced samples")
	check_less(float(glued) / float(samples), 0.25, "the ball must not sit on a player's foot")
	# Was 0.35, and it failed at 0.332 the moment rolling resistance went up
	# (SimConsts.ROLL_DECEL_DRY, 1.0 -> 1.6). That is the friction doing its job
	# rather than the ball becoming glued: a loose ball dies sooner, so it spends
	# fewer ticks out on its own before someone reaches it. The bound exists to
	# catch a ball welded to a foot, which would drive this toward zero, so it
	# still has plenty to say at 0.30 -- and it is deliberately a round number
	# below the measurement rather than fitted to it.
	check_greater(float(free_running) / float(samples), 0.30, "the ball must spend real time away from everyone")


func _touches_sometimes_get_away() -> void:
	# The same intent, repeated, must not produce the same outcome: execution
	# error is where the 50/50s come from.
	var ctx := _drill_context(31)
	var p := ctx.players[9]
	var angles := PackedFloat32Array()
	for i in 200:
		p.pos = Vector3.ZERO
		p.vel = Vector3(6.0, 0.0, 0.0)
		p.touch_cooldown = 0.0
		ctx.ball.reset(Vector3(0.4, SimConsts.BALL_RADIUS, 0.0))
		SimTouch.dribble(ctx, p, Vector3(1, 0, 0), 0.6)
		angles.append(atan2(ctx.ball.vel.z, ctx.ball.vel.x))
	var spread := SimValidation.sd_of(angles)
	check_greater(spread, 0.01, "dribble touches must vary")
	check_less(spread, 0.5, "but not wildly")
	var worst := 0.0
	for a in angles:
		worst = maxf(worst, absf(a))
	check_greater(worst, spread * 1.8, "some touches must genuinely get away")


func _pressure_widens_the_error() -> void:
	var ctx := _drill_context(41)
	var p := ctx.players[9]
	p.pos = Vector3.ZERO
	p.vel = Vector3(4.0, 0.0, 0.0)
	ctx.pressure[p.id] = 0.0
	var calm := SimTouch.aim_sigma(ctx, p, p.attrs.passing, 20.0, 0.055)
	ctx.pressure[p.id] = 2.0
	var harried := SimTouch.aim_sigma(ctx, p, p.attrs.passing, 20.0, 0.055)
	check_greater(harried, calm * 1.15, "pressure must widen the error distribution")


func _first_touch_leaves_residual_pace() -> void:
	var ctx := _drill_context(51)
	var p := ctx.players[9]
	p.pos = Vector3.ZERO
	p.attrs.first_touch = 0.1
	p.attrs.technique = 0.1
	p.refresh_caps()
	var loose := 0
	for i in 60:
		p.touch_cooldown = 0.0
		ctx.ball.reset(Vector3(0.5, SimConsts.BALL_RADIUS, 0.0))
		ctx.ball.vel = Vector3(-18.0, 0.0, 0.0)
		SimTouch.first_touch(ctx, p, Vector3(1, 0, 0))
		if ctx.ball.ground_speed() > 3.0:
			loose += 1
	check_greater(float(loose), 20.0, "a poor first touch must leave the ball loose")


func _pass_solver_lands_near_the_target() -> void:
	var env := dry_env()
	var b := SimBallistics.new()
	for distance in [8.0, 18.0, 30.0]:
		var speed := b.ground_pass_speed(distance, 4.0, env)
		var run := b.ground_pass_range(speed, env)
		# A pass solved to arrive at 4 m/s is still travelling when it gets
		# there, so its total range is necessarily longer than the pass itself.
		check_greater(run, distance, "a pass must at least reach its target")
		var travel := b.ground_travel_time(distance, speed, env)
		check_between(travel, distance / 22.0, distance / 5.0, "a pass must arrive in a plausible time")
	# A lofted ball has to land near where it was aimed.
	var target := Vector3(28.0, 0.0, 6.0)
	var vel := b.solve_lofted(Vector3(0.0, SimConsts.BALL_RADIUS, 0.0), target, 1.5, env)
	var ball := launch_ball(vel)
	var closest := 999.0
	for i in 300:
		ball.integrate(SimConsts.DT, env)
		closest = minf(closest, SimConsts.horizontal_length(ball.pos - target))
		if ball.grounded:
			break
	check_less(closest, 3.0, "the lofted solver must land the ball near its target")


func _execution_accuracy_falls_off_with_distance() -> void:
	var ctx := _drill_context(61)
	var p := ctx.players[9]
	p.pos = Vector3.ZERO
	p.vel = Vector3.ZERO
	var near := SimTouch.execution_accuracy(ctx, p, p.attrs.passing, 10.0, 0.055, SimDecision.pass_tolerance(10.0))
	var far := SimTouch.execution_accuracy(ctx, p, p.attrs.passing, 45.0, 0.055, SimDecision.pass_tolerance(45.0))
	check_greater(near, 0.75, "a ten-metre pass is nearly always struck as intended")
	check_less(far, near - 0.15, "a forty-five-metre pass is not")
