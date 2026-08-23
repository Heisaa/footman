class_name TestDistances
extends SimTestCase
## Every way of moving the ball, checked for going the distance it claims,
## struck by a stationary man and by a moving one.
##
## The lofted run-on (`SimTouch.LOFT_RUNON_SHARE`) was found by eye a session
## after it began: the flight solver was landing on its aim and the ball still
## finished forty percent long, and nothing in the suite watched where any ball
## *finishes*. This is that instrument, as a test: one drill context, every
## strike primitive, the ball integrated to the point a receiver could have it,
## and a band around where football expects it. `./run.sh strike` remains the
## precision bench; these bands are wide on purpose, sized to catch the
## forty-percent class of miss and survive ordinary retuning.
##
## Means over a couple of dozen strikes, because every strike rolls real noise
## from `ctx.rng`. No match is simulated; the whole case is integration of
## free flights and runs in well under a second.

const REPS := 24


func run() -> void:
	var ctx := _drill()
	_ground_passes(ctx, false)
	_ground_passes(ctx, true)
	_lofted_passes(ctx, false)
	_lofted_passes(ctx, true)
	_crosses(ctx)
	_shots(ctx)
	_headers(ctx)
	_small_touches(ctx)


static func _drill(seed_value: int = 5) -> SimContext:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = 1.0
	return SimRunner.build(opts).ctx


## The striker, pinned. A drill about the strike rules must not measure
## whichever squad the seed generated.
static func _striker(ctx: SimContext) -> SimPlayer:
	var p := ctx.players[9]
	p.attrs.passing = 0.7
	p.attrs.crossing = 0.7
	p.attrs.technique = 0.7
	p.attrs.first_touch = 0.7
	p.attrs.dribbling = 0.7
	p.attrs.heading = 0.6
	p.attrs.jumping = 0.6
	p.attrs.power = 0.7
	p.stamina = 1.0
	return p


## Puts the man and the ball at the origin, facing +X, moving or not, and
## leaves the ball wherever the last strike put it until reset again.
static func _place(ctx: SimContext, p: SimPlayer, moving: bool, ball_y: float = SimConsts.BALL_RADIUS, ball_vel: Vector3 = Vector3.ZERO) -> void:
	p.pos = Vector3.ZERO
	p.vel = Vector3(4.0, 0.0, 0.0) if moving else Vector3.ZERO
	p.facing = 0.0
	p.touch_cooldown = 0.0
	ctx.ball.reset(Vector3(0.05, ball_y, 0.0))
	ctx.ball.vel = ball_vel
	ctx.ball.grounded = ball_y <= SimConsts.BALL_RADIUS + 0.01 and ball_vel.y == 0.0


## Where a receiver could first cleanly have the ball: on the grass and at a
## pace a first touch handles -- `Taking it down` measures touches on balls
## arriving well past six -- capped at eight seconds.
static func _finish(ctx: SimContext) -> Vector3:
	var t := 0.0
	while t < 8.0:
		ctx.ball.integrate(SimConsts.FORECAST_DT, ctx.env)
		t += SimConsts.FORECAST_DT
		if ctx.ball.pos.y <= SimConsts.BALL_RADIUS + 0.05 and ctx.ball.vel.length() <= 6.0:
			break
	return ctx.ball.pos


## How near the flight comes to a point while still in the air.
static func _closest_in_air(ctx: SimContext, aim: Vector3) -> float:
	var best := 1e9
	var t := 0.0
	while t < 6.0:
		ctx.ball.integrate(SimConsts.FORECAST_DT, ctx.env)
		t += SimConsts.FORECAST_DT
		best = minf(best, SimConsts.horizontal_length(ctx.ball.pos - aim))
		if ctx.ball.pos.y <= SimConsts.BALL_RADIUS + 0.02 and ctx.ball.vel.y <= 0.0:
			break
	return best


func _ground_passes(ctx: SimContext, moving: bool) -> void:
	var p := _striker(ctx)
	var who := "a moving man's" if moving else "a stationary man's"
	for distance in [10.0, 22.0, 30.0]:
		var aim := Vector3(distance, 0.0, 0.0)
		var mean := 0.0
		for i in REPS:
			_place(ctx, p, moving)
			var pace := SimDecision.arrival_pace(distance, ctx.tactics(p.team))
			SimTouch.ground_pass(ctx, p, aim, pace, -1)
			# A ground ball is met at the pace it was asked to arrive at, so its
			# finishing point for a receiver is where it decays to that pace.
			var t := 0.0
			while t < 8.0 and ctx.ball.vel.length() > pace:
				ctx.ball.integrate(SimConsts.FORECAST_DT, ctx.env)
				t += SimConsts.FORECAST_DT
			mean += ctx.ball.pos.x
		mean /= float(REPS)
		# Five metres either side, and the far edge is the wider one because the
		# ball is asked to still be *doing* the arrival pace when it gets there:
		# struck by a moving man it carries some of his run as well, and at the
		# floor `SimDecision.arrival_pace` was raised to (2026-08-23) a 22 m ball
		# came out 4.0 m long against a ceiling of 4.0.
		check_between(mean, distance - 5.0, distance + 5.0,
			"%s %d m ground pass must arrive about %d m out" % [who, distance, distance])


func _lofted_passes(ctx: SimContext, moving: bool) -> void:
	var p := _striker(ctx)
	var who := "a moving man's" if moving else "a stationary man's"
	for distance in [20.0, 30.0, 40.0]:
		var aim := Vector3(distance, 0.0, 0.0)
		var mean := 0.0
		for i in REPS:
			_place(ctx, p, moving)
			SimTouch.lofted_pass(ctx, p, aim, SimTouch.lofted_flight(distance), -1)
			mean += _finish(ctx).x
		mean /= float(REPS)
		check_between(mean, distance - 11.0, distance + 6.0,
			"%s %d m lofted pass must finish about %d m out" % [who, distance, distance])


func _crosses(ctx: SimContext) -> void:
	# A cross is attacked in the air, so what it owes is a flight through its
	# aim, not a finishing spot.
	var p := _striker(ctx)
	for distance in [22.0, 34.0]:
		var aim := Vector3(distance, 0.0, 0.0)
		var mean := 0.0
		for i in REPS:
			_place(ctx, p, false)
			SimTouch.lofted_pass(ctx, p, aim, SimTouch.lofted_flight(distance), -1,
				SimTelemetry.Touch.CROSS)
			mean += _closest_in_air(ctx, aim)
		mean /= float(REPS)
		check_less(mean, 7.0,
			"a %d m cross's flight must pass close to its aim" % distance)


func _shots(ctx: SimContext) -> void:
	var p := _striker(ctx)
	for moving in [false, true]:
		var who := "a moving man's" if moving else "a stationary man's"
		_place(ctx, p, moving)
		SimTouch.shot(ctx, p, Vector3(16.0, 1.0, 0.0), 0.8, false, 0.1)
		var speed := ctx.ball.vel.length()
		check_between(speed, SimConsts.SHOT_SPEED_MIN * 0.5, SimConsts.SHOT_SPEED_MAX * 1.1,
			"%s shot leaves inside the shot speed range" % who)
		check_greater(speed, 10.0, "%s shot is still a shot" % who)


func _headers(ctx: SimContext) -> void:
	# A defender meeting a dropping cross, headed on at a clearing angle. What a
	# header buys is a fact about the neck and the incoming pace, and football
	# says the answer is five to twenty-five metres or so, roll included -- not a
	# pass, and never a forty-metre clearance off a forehead.
	var p := _striker(ctx)
	for moving in [false, true]:
		var who := "a moving man's" if moving else "a stationary man's"
		var mean := 0.0
		for i in REPS:
			_place(ctx, p, moving, 2.1, Vector3(-9.0, -4.0, 0.0))
			# At the power the clearing header is actually played with. The
			# primitive's own band belongs to the header at goal, which is a
			# different act -- `SimAerial.NOT_AT_GOAL_POWER` is the difference,
			# and testing the primitive flat out measured a header nobody plays.
			SimTouch.header(ctx, p, Vector3(1.0, 0.0, 0.0), 0.45, SimAerial.CLEAR,
				Vector3.INF, 0.0, SimAerial.NOT_AT_GOAL_POWER)
			mean += SimConsts.horizontal_length(_finish(ctx))
		mean /= float(REPS)
		check_between(mean, 4.0, 26.0,
			"%s defensive header must carry a football distance" % who)

	# The hard case the owner watched: a ball arriving with real pace -- a long
	# kick, a driven cross -- headed away. A neck redirects it, it does not
	# return it with interest; `SimTouch.HEADER_PACE_BONUS_MAX` is the cap.
	var hard := 0.0
	for i in REPS:
		_place(ctx, p, false, 2.1, Vector3(-16.0, -5.0, 0.0))
		SimTouch.header(ctx, p, Vector3(1.0, 0.0, 0.0), 0.45, SimAerial.CLEAR,
			Vector3.INF, 0.0, SimAerial.NOT_AT_GOAL_POWER)
		hard += SimConsts.horizontal_length(_finish(ctx))
	hard /= float(REPS)
	check_between(hard, 6.0, 30.0,
		"a header off a driven ball must not carry like a clearance kick")

	# And the other header, which is the one aimed at the goal. The floor is
	# structural rather than tuned: a ball leaving the forehead slower than this
	# gives a goalkeeper eleven metres away the better part of a second, and the
	# owner watched exactly that (2026-08-23). The ceiling is the struck shot --
	# a header is slower than a shot and not half of one.
	var at_goal := 0.0
	for i in REPS:
		_place(ctx, p, false, 2.1, Vector3(-14.0, -4.0, 0.0))
		SimTouch.header(ctx, p, Vector3(1.0, 0.0, 0.0), -0.1, SimAerial.AT_GOAL)
		at_goal += ctx.ball.vel.length()
	at_goal /= float(REPS)
	check_between(at_goal, 13.0, SimConsts.SHOT_SPEED_MAX,
		"a header at goal must leave the head fast enough to beat a keeper")


func _small_touches(ctx: SimContext) -> void:
	var p := _striker(ctx)

	# The settling touch: the smallest act the engine has.
	var mean := 0.0
	for i in REPS:
		_place(ctx, p, false)
		SimTouch.settle(ctx, p, Vector3(1, 0, 0), SimTouch.DRIBBLE_AHEAD_FLOOR)
		mean += _finish(ctx).length()
	check_less(mean / float(REPS), 2.5, "a settling touch keeps the ball at his feet")

	# A dribble touch, taken with room, by a moving man. What the touch claims
	# is a *gap*: the ball a few metres clear of a runner who keeps running, so
	# it is measured where he draws level with its pace, against the ground he
	# covered getting there -- total roll would charge it for his own running.
	mean = 0.0
	for i in REPS:
		_place(ctx, p, true)
		SimTouch.dribble(ctx, p, Vector3(1, 0, 0), 0.7)
		var t := 0.0
		while t < 4.0 and ctx.ball.vel.length() > 4.0:
			ctx.ball.integrate(SimConsts.FORECAST_DT, ctx.env)
			t += SimConsts.FORECAST_DT
		mean += ctx.ball.pos.x - 4.0 * t
	check_between(mean / float(REPS), 0.3, 7.0,
		"a dribble touch puts the ball metres clear of the runner, not tens")

	# The first touch on a ball arriving with pace: killed to within a couple of
	# strides, never played on twenty metres.
	mean = 0.0
	for i in REPS:
		_place(ctx, p, false, SimConsts.BALL_RADIUS, Vector3(-8.0, 0.0, 0.0))
		SimTouch.first_touch(ctx, p, Vector3(1, 0, 0))
		mean += _finish(ctx).length()
	check_less(mean / float(REPS), 4.5, "a first touch kills the ball near the man")
