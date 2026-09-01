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
	_the_ball_is_on_a_foot()
	_the_curl_comes_off_the_striking_foot()
	_momentum_reads_the_body()
	_the_first_touch_turns_the_body()
	_the_shield_is_the_body()


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


## `docs/THE_FOOTBALL.md` 35. The mechanism, not an outcome: the geometry of
## which side the ball is on, and that the side changes what a strike costs.
## Nothing here asserts that footedness makes the football better, because
## nobody has decided which way any match number should move for it.
func _the_ball_is_on_a_foot() -> void:
	var ctx := _drill_context()
	var p := ctx.players[9]
	p.pos = Vector3.ZERO
	p.vel = Vector3.ZERO
	p.facing = 0.0  # Facing +X, so +Z is his right.
	var right := Vector3(0, 0, 1)
	var left := Vector3(0, 0, -1)

	check_near(SimTouch.lateral_of(p, right), 1.0, 0.01, "+Z is the right of a man facing +X")
	check_near(SimTouch.lateral_of(p, left), -1.0, 0.01, "and -Z is his left")
	check_near(SimTouch.lateral_of(p, Vector3(1, 0, 0)), 0.0, 0.01, "straight ahead is neither")

	# A right-footer opens onto his left. The ball to his right is the awkward
	# one, and that is the whole asymmetry the mechanic exists to create.
	p.attrs.foot = SimAttributes.FOOT_RIGHT
	p.attrs.weak_foot = 0.2
	check_near(SimTouch.foot_cost(p, left), 0.0, 0.01, "a right-footer plays the ball to his left for nothing")
	check_greater(SimTouch.foot_cost(p, right), 0.4, "and pays to play it to his right")
	check_greater(SimTouch.aim_sigma(ctx, p, 0.6, 20.0, 0.05, right),
		SimTouch.aim_sigma(ctx, p, 0.6, 20.0, 0.05, left),
		"so the ball on his wrong side is struck worse")
	check_less(SimTouch.strike_range(p, right, 40.0), SimTouch.strike_range(p, left, 40.0),
		"and struck shorter")

	# Mirrored, or the model has a handedness of its own.
	p.attrs.foot = SimAttributes.FOOT_LEFT
	check_near(SimTouch.foot_cost(p, right), 0.0, 0.01, "and a left-footer is the mirror of him")
	check_greater(SimTouch.foot_cost(p, left), 0.4, "in both directions")

	# The dial has to reach both ends. A genuinely two-footed player pays
	# nothing either way, which is what stops this being a flat tax on everyone.
	p.attrs.weak_foot = 1.0
	check_near(SimTouch.foot_cost(p, right), 0.0, 0.01, "a two-footed man has no wrong side")
	check_near(SimTouch.foot_cost(p, left), 0.0, 0.01, "on either flank")


## `docs/THE_FOOTBALL.md` 36. The sign is the point: the curl used to be
## zero-mean, so this asserts which way the ball goes and not how far.
func _the_curl_comes_off_the_striking_foot() -> void:
	var ctx := _drill_context()
	var p := ctx.players[9]
	p.pos = Vector3.ZERO
	p.vel = Vector3.ZERO
	p.facing = 0.0
	p.attrs.technique = 0.9
	p.attrs.weak_foot = 0.05  # One-footed, so the strong foot strikes everything.
	var ahead := Vector3(1, 0, 0)

	# Spin about +UP deflects the ball toward UP.cross(vel), which is the
	# striker`s left. The inside of the right boot turns it that way.
	p.attrs.foot = SimAttributes.FOOT_RIGHT
	var mean_right := 0.0
	for i in 200:
		mean_right += SimTouch.curl_for(ctx, p, ahead, SimTouch.CROSS_CURL, SimTouch.CROSS_CURL_SIGMA)
	check_greater(mean_right / 200.0, 0.5, "a right-footed strike bends to his left")

	p.attrs.foot = SimAttributes.FOOT_LEFT
	var mean_left := 0.0
	for i in 200:
		mean_left += SimTouch.curl_for(ctx, p, ahead, SimTouch.CROSS_CURL, SimTouch.CROSS_CURL_SIGMA)
	check_less(mean_left / 200.0, -0.5, "and a left-footed one to his right")

	# And the bend a viewer would actually name: a right-footed corner from the
	# left flag swings in. The taker stands at the corner facing the goalmouth,
	# which is what `SimSetPiece` sets his body to before he strikes it.
	var goal := ctx.pitch.target_goal(p.team)
	var flag := Vector3(goal.x, 0.0, -ctx.pitch.half_width)
	p.pos = flag
	p.attrs.foot = SimAttributes.FOOT_RIGHT
	var upfield := SimConsts.horizontal(goal - flag)
	p.facing = atan2(upfield.z, upfield.x)
	var aim := goal + Vector3(-6.5 * ctx.pitch.attack_dir(p.team), 2.1, 0.0)
	var curl := SimTouch.curl_for(ctx, p, aim - flag, SimTouch.CROSS_CURL, 0.0)
	# Positive yaw sends it to his left, and facing the goalmouth from that flag
	# his left is the goal.
	var bend := Vector3.UP.cross(SimConsts.horizontal(aim - flag).normalized()) * curl
	check_greater(bend.dot(SimConsts.horizontal(goal - aim).normalized()), 0.0,
		"a right-footed corner from the left flag swings toward the goal")


func _momentum_reads_the_body() -> void:
	# The run-up behind a strike is the pace along the hips, not the pace: the
	# body is its own state, and a shuffle across it carries no swing.
	var p := make_player(0.6, 0.6)
	p.facing = 0.0
	p.vel = Vector3(0.0, 0.0, 6.0)
	check_near(SimTouch.momentum_of(p), SimTouch.FACING_STATIC_SHARE, 1e-6, "a man shuffling across his hips has a standing man's run-up")
	p.vel = Vector3(-6.0, 0.0, 0.0)
	check_near(SimTouch.momentum_of(p), SimTouch.FACING_STATIC_SHARE, 1e-6, "and so has a backpedal")
	p.vel = Vector3(6.0, 0.0, 0.0)
	check_greater(SimTouch.momentum_of(p), 0.8, "a man running through his hips has most of it")
	check_near(SimTouch.strike_scale(p, Vector3(1, 0, 0)), 1.0, 1e-6, "and a ball straight ahead costs nothing either way")


func _the_first_touch_turns_the_body() -> void:
	# A ball running up the pitch, taken across into +X by a man facing along
	# its line: the hips turn with the ball, by no more than the ball turned.
	var ctx := _drill_context()
	var p := ctx.players[9]
	p.pos = Vector3.ZERO
	p.vel = Vector3.ZERO
	p.facing = PI * 0.5
	p.attrs.first_touch = 0.7
	p.attrs.technique = 0.7
	ctx.ball.reset(Vector3(0.0, SimConsts.BALL_RADIUS, -0.3))
	ctx.ball.vel = Vector3(0.0, 0.0, 6.0)
	SimTouch.first_touch(ctx, p, Vector3(1, 0, 0))
	check_near(angle_difference(p.facing, 0.0), 0.0, 0.05, "the first touch turns the body onto the ball it set")
	check_greater(p.look_target.x - p.pos.x, 1.0, "and holds the look there")


func _the_shield_is_the_body() -> void:
	var carrier := make_player()
	carrier.pos = Vector3.ZERO
	carrier.facing = 0.0
	var man := make_player()
	man.pos = Vector3(-2.0, 0.0, 0.0)
	check_near(SimDuel.shielded(carrier, man), 1.0, 1e-6, "a man square at his back is fully shielded")
	man.pos = Vector3(2.0, 0.0, 0.0)
	check_near(SimDuel.shielded(carrier, man), 0.0, 1e-6, "a man in his face is not")
	man.pos = Vector3(0.0, 0.0, 2.0)
	check_near(SimDuel.shielded(carrier, man), 0.5, 1e-6, "and side-on is half")
