class_name TestBall
extends SimTestCase
## The Phase 1 exit criteria for the ball (PLAN.md §10).
##
## A chipped ball with sidespin must visibly bend, and a backspin pass must
## check up on the bounce. Both fall out of the integrator rather than being
## authored, so these tests are really checking that the physics is right.


func run() -> void:
	_projectile_range_is_plausible()
	_bounce_loses_energy()
	_rolling_ball_decelerates_gently()
	_struck_ball_reaches_rolling()
	_backspin_checks_up()
	_topspin_runs_on()
	_sidespin_bends_a_cross()
	_solve_direct_lands_a_bent_ball()
	_ground_solve_lands_a_curled_driven_pass()
	_bow_prediction_matches_a_simulated_flight()
	_ball_never_sinks()
	_forecast_agrees_with_the_integrator()
	_ground_predictors_are_the_integrator()


func _projectile_range_is_plausible() -> void:
	var env := dry_env()
	# 25 m/s at 30 degrees. In a vacuum this would carry 55 m; drag should pull
	# it back to somewhere in the high thirties or forties.
	var vel := Vector3(25.0 * cos(deg_to_rad(30.0)), 25.0 * sin(deg_to_rad(30.0)), 0.0)
	var b := launch_ball(vel)
	var start := b.pos
	# Carry is where it first lands, not where it stops. `grounded` only comes
	# back on once the bounces have died out, so breaking on it measured the
	# flight plus every hop after it -- and moved when the bounce did.
	for i in 400:
		var falling := b.vel.y < 0.0
		b.integrate(SimConsts.DT, env)
		# The impact is resolved inside the step that meets the grass, so the
		# landing shows up as the tick where a falling ball starts rising.
		if b.grounded or (falling and b.vel.y > 0.0):
			break
	check_between(b.pos.x - start.x, 33.0, 52.0, "a 25 m/s drive at 30 degrees should carry 35-50 m")


func _bounce_loses_energy() -> void:
	var env := dry_env()
	var b := SimBall.new()
	b.reset(Vector3(0.0, 3.0, 0.0))
	b.grounded = false
	# Fall, bounce, and measure the apex of the bounce.
	var bounced := false
	var apex := 0.0
	for i in 400:
		b.integrate(SimConsts.DT, env)
		if not bounced and b.vel.y > 0.0:
			bounced = true
		if bounced:
			apex = maxf(apex, b.pos.y)
			if b.vel.y < 0.0 and b.pos.y < apex - 0.05:
				break
	# Restitution is on velocity, so height scales with its square: 3 m at 0.6
	# comes back to about 1.08 m, less the drag on the way.
	check_between(apex, 0.7, 1.15, "a 3 m drop should bounce to roughly a metre")


func _rolling_ball_decelerates_gently() -> void:
	var env := dry_env()
	var b := SimBall.new()
	b.reset()
	# Give it exactly the spin of a rolling ball so there is no sliding phase.
	b.vel = Vector3(6.0, 0.0, 0.0)
	b.spin = Vector3(0.0, 0.0, -6.0 / SimConsts.BALL_RADIUS)
	advance(b, env, 2.0)
	# Rolling resistance is a constant deceleration, so the speed lost is a * t.
	# Derived from the environment rather than written out: when the constant
	# last moved, this assertion was the only thing still holding the old value.
	var expected: float = 6.0 - env.roll_decel * 2.0
	check_near(b.ground_speed(), expected, 0.25, "a rolling ball should shed exactly env.roll_decel")


func _struck_ball_reaches_rolling() -> void:
	var env := dry_env()
	var b := SimBall.new()
	b.reset()
	# Struck flat with no spin: it must slide, spin up, and settle into rolling.
	b.vel = Vector3(14.0, 0.0, 0.0)
	b.spin = Vector3.ZERO
	advance(b, env, 1.5)
	var slip := b.vel.x + SimConsts.BALL_RADIUS * b.spin.z
	check_near(slip, 0.0, 0.05, "a struck ball must settle into rolling without slipping")
	# It should have lost about two sevenths of its speed to the sliding phase.
	check_between(b.ground_speed(), 8.5, 10.5, "sliding costs roughly 2/7 of the launch speed")


func _backspin_checks_up() -> void:
	var env := dry_env()
	var plain := SimBall.new()
	plain.reset()
	plain.vel = Vector3(12.0, 0.0, 0.0)
	advance(plain, env, 3.0)

	var back := SimBall.new()
	back.reset()
	back.vel = Vector3(12.0, 0.0, 0.0)
	# Backspin: the axis opposite to the rolling direction.
	back.spin = Vector3(0.0, 0.0, 12.0 / SimConsts.BALL_RADIUS * 0.6)
	advance(back, env, 3.0)

	check_less(back.pos.x, plain.pos.x - 1.0, "a backspun ball must check up short of a plain one")


func _topspin_runs_on() -> void:
	var env := dry_env()
	var plain := SimBall.new()
	plain.reset()
	plain.vel = Vector3(12.0, 0.0, 0.0)
	advance(plain, env, 3.0)

	var top := SimBall.new()
	top.reset()
	top.vel = Vector3(12.0, 0.0, 0.0)
	top.spin = Vector3(0.0, 0.0, -12.0 / SimConsts.BALL_RADIUS * 1.6)
	advance(top, env, 3.0)

	check_greater(top.pos.x, plain.pos.x + 0.4, "a topspun ball must run on past a plain one")


func _sidespin_bends_a_cross() -> void:
	# PLAN.md §3.1: the Magnus coefficient is tuned so that about 6 rad/s of
	# sidespin bends a 30 m cross by roughly 2 m.
	var env := dry_env()
	var straight := launch_ball(Vector3(18.0, 7.0, 0.0))
	var curled := launch_ball(Vector3(18.0, 7.0, 0.0), Vector3(0.0, 6.0, 0.0))
	var deflection := 0.0
	for i in 300:
		straight.integrate(SimConsts.DT, env)
		curled.integrate(SimConsts.DT, env)
		if curled.grounded or straight.grounded:
			break
		deflection = absf(curled.pos.z - straight.pos.z)
	check_between(deflection, 1.0, 3.5, "6 rad/s of sidespin should bend a 30 m ball by about 2 m")
	check_greater(absf(curled.pos.z), 0.5, "the curled ball must actually go sideways")


func _solve_direct_lands_a_bent_ball() -> void:
	# `solve_direct`'s yaw correction: a ball with real sidespin on it must bend
	# on the way and still cross the target on line. Structure, not a tuned
	# figure -- it went sideways, and it arrived.
	var env := dry_env()
	var solver := SimBallistics.new()
	var from := Vector3(0.0, SimConsts.BALL_RADIUS, 0.0)
	var to := Vector3(20.0, 1.2, 0.0)
	var spin := Vector3.UP * 45.0
	var vel := solver.solve_direct(from, to, 24.0, env, spin)
	var b := launch_ball(vel, spin, from)
	var bow := 0.0
	var crossed := false
	for i in 400:
		b.integrate(SimConsts.DT, env)
		if b.pos.x >= to.x:
			crossed = true
			break
		bow = maxf(bow, absf(b.pos.z))
		if b.grounded:
			break
	check(crossed, "a 24 m/s bent drive must reach a target 20 m out")
	check_less(absf(b.pos.z - to.z), 1.0, "the bent ball must still cross the target on line")
	check_greater(bow, 0.2, "the flight must actually leave the chord on the way")


func _ground_solve_lands_a_curled_driven_pass() -> void:
	# `ground_launch` with the spin in hand: a driven ball with sidespin must
	# drift off its chord in the hops and still decay to its arrival pace on
	# the line it was aimed down. Same structure as the bent shot's test.
	var env := dry_env()
	var solver := SimBallistics.new()
	var curl := 25.0
	var launch := solver.ground_launch(22.0, 7.0, env, curl)
	var speed: float = launch["speed"]
	var loft: float = launch["loft"]
	var backspin: float = launch["backspin"]
	var yaw: float = launch["yaw"]
	check_greater(loft, 0.0, "a 22 m ball arriving at 7 m/s must be driven")
	var dir := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, yaw)
	var vel := dir * speed
	vel.y = loft
	var spin := -Vector3.UP.cross(dir) * (speed / SimConsts.BALL_RADIUS * backspin) \
		+ Vector3.UP * curl
	var b := launch_ball(vel, spin, Vector3(0.0, SimConsts.BALL_RADIUS, 0.0))
	var excursion := 0.0
	var t := 0.0
	while t < 6.0:
		b.integrate(SimConsts.DT, env)
		t += SimConsts.DT
		excursion = maxf(excursion, absf(b.pos.z))
		if b.vel.length() <= 7.0:
			break
	check_near(b.pos.x, 22.0, 2.0, "the curled drive must still decay to pace near its distance")
	check_less(absf(b.pos.z), 0.8, "the curled drive must come back onto its line")
	check_greater(excursion, 0.1, "the hops must actually leave the chord on the way")

	# And the *meant* bend, which is a lifted ball: the cross's spin, clipped
	# up (`BEND_LIFT`), must bend visibly more than the flat drive and still
	# come back onto its line.
	var l2 := solver.ground_launch(22.0, 7.0, env, 36.0, SimBallistics.BEND_LIFT)
	var s2: float = l2["speed"]
	var y2: float = l2["yaw"]
	var dir2 := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, y2)
	var vel2 := dir2 * s2
	vel2.y = float(l2["loft"]) + SimBallistics.BEND_LIFT
	var spin2 := -Vector3.UP.cross(dir2) * (s2 / SimConsts.BALL_RADIUS * float(l2["backspin"])) \
		+ Vector3.UP * 36.0
	var b2 := launch_ball(vel2, spin2, Vector3(0.0, SimConsts.BALL_RADIUS, 0.0))
	var excursion2 := 0.0
	var t2 := 0.0
	while t2 < 6.0:
		b2.integrate(SimConsts.DT, env)
		t2 += SimConsts.DT
		excursion2 = maxf(excursion2, absf(b2.pos.z))
		if b2.vel.length() <= 7.0:
			break
	check_less(absf(b2.pos.z), 1.0, "the lifted bend must come back onto its line")
	check_greater(excursion2, 0.3, "the lifted bend must be a visible one")
	check_greater(excursion2, excursion, "the lift is what buys the bend")


func _bow_prediction_matches_a_simulated_flight() -> void:
	# `curl_bow` against the integrator, by two-flight difference -- the way
	# every lateral figure in this project has been measured. Mid-journey,
	# because that is where the uncorrected path sits `a t^2 / 8` off its
	# launch line, which is the bow the predictor claims. Loose on purpose:
	# same sign, half to double.
	var env := dry_env()

	# In clean air.
	var straight := launch_ball(Vector3(18.0, 7.0, 0.0))
	var curled := launch_ball(Vector3(18.0, 7.0, 0.0), Vector3(0.0, 6.0, 0.0))
	var total := 0.0
	for i in 300:
		straight.integrate(SimConsts.DT, env)
		curled.integrate(SimConsts.DT, env)
		if straight.grounded:
			break
		total = straight.pos.x
	var mid_diff := 0.0
	straight = launch_ball(Vector3(18.0, 7.0, 0.0))
	curled = launch_ball(Vector3(18.0, 7.0, 0.0), Vector3(0.0, 6.0, 0.0))
	for i in 300:
		straight.integrate(SimConsts.DT, env)
		curled.integrate(SimConsts.DT, env)
		if straight.pos.x >= total * 0.5:
			mid_diff = curled.pos.z - straight.pos.z
			break
	var said := SimBallistics.curl_bow(6.0, 18.0, total)
	check_greater(said, 0.0, "positive curl must predict a bow to the left")
	check_less(mid_diff, 0.0, "positive curl must deflect toward -z, the striker's left")
	check_between(absf(mid_diff) / maxf(said, 0.001), 0.5, 2.0,
		"the airborne bow prediction must sit within half to double the flight")

	# And in the driven pass's hops.
	var solver := SimBallistics.new()
	var launch := solver.ground_launch(22.0, 7.0, env)
	var speed: float = launch["speed"]
	var loft: float = launch["loft"]
	var backspin: float = launch["backspin"]
	var base_spin := Vector3(0.0, 0.0, speed / SimConsts.BALL_RADIUS * backspin)
	var s2 := launch_ball(Vector3(speed, loft, 0.0), base_spin)
	var c2 := launch_ball(Vector3(speed, loft, 0.0), base_spin + Vector3.UP * 25.0)
	var drift := 0.0
	var t := 0.0
	while t < 6.0:
		s2.integrate(SimConsts.DT, env)
		c2.integrate(SimConsts.DT, env)
		t += SimConsts.DT
		if s2.pos.x >= 11.0:
			drift = c2.pos.z - s2.pos.z
			break
	var said_driven := SimBallistics.curl_bow(25.0, speed, 22.0, SimBallistics.DRIVEN_BOW_SHARE)
	check_less(drift, 0.0, "the driven ball's hops must drift toward the striker's left too")
	check_between(absf(drift) / maxf(said_driven, 0.001), 0.5, 2.0,
		"the driven bow prediction must sit within half to double the hops")

	# And the lifted bend's share, against the lifted flight.
	var s3 := launch_ball(Vector3(speed, loft + SimBallistics.BEND_LIFT, 0.0), base_spin)
	var c3 := launch_ball(Vector3(speed, loft + SimBallistics.BEND_LIFT, 0.0),
		base_spin + Vector3.UP * 36.0)
	var drift3 := 0.0
	var t3 := 0.0
	while t3 < 6.0:
		s3.integrate(SimConsts.DT, env)
		c3.integrate(SimConsts.DT, env)
		t3 += SimConsts.DT
		if s3.pos.x >= 11.0:
			drift3 = c3.pos.z - s3.pos.z
			break
	var said_lifted := SimBallistics.curl_bow(36.0, speed, 22.0, SimBallistics.BEND_BOW_SHARE)
	check_between(absf(drift3) / maxf(said_lifted, 0.001), 0.5, 2.0,
		"the lifted bow prediction must sit within half to double the flight")


func _ball_never_sinks() -> void:
	var env := dry_env()
	var rng := SimRng.new(4)
	# Measured against the grass rather than against y = BALL_RADIUS: the pitch
	# is cambered, so the turf itself is up to twenty centimetres lower out by
	# the touchline than it is on the centre spot.
	var deepest := 999.0
	for trial in 40:
		var b := launch_ball(
			Vector3(rng.range_float(-25.0, 25.0), rng.range_float(0.0, 18.0), rng.range_float(-25.0, 25.0)),
			Vector3(rng.range_float(-40.0, 40.0), rng.range_float(-30.0, 30.0), rng.range_float(-40.0, 40.0))
		)
		for i in 600:
			b.integrate(SimConsts.DT, env)
			var turf := SimConsts.BALL_RADIUS + env.surface_height(b.pos.x, b.pos.z)
			deepest = minf(deepest, b.pos.y - turf)
	check_near(deepest, 0.0, 0.01, "the ball must never end up below the turf")


func _forecast_agrees_with_the_integrator() -> void:
	# Every agent believes the forecast, so it has to be close to the truth.
	var env := dry_env()
	var pitch := SimPitch.regulation()
	var traj := SimTrajectory.new()
	var b := launch_ball(Vector3(16.0, 8.0, 3.0), Vector3(0.0, 4.0, 0.0))
	traj.recompute(b, env, pitch)
	var predicted := traj.position_at(1.0)
	advance(b, env, 1.0)
	check_less(predicted.distance_to(b.pos), 0.9, "the shared forecast must track the real integrator")


func _ground_predictors_are_the_integrator() -> void:
	# The decision layer prices every ground pass off `ground_pass_speed` and
	# `ground_travel_time`, and the touch strikes what `ground_pass_speed`
	# says. So the ball that is priced has to be the ball that is struck: the
	# same launch, integrated at the match step, arrives when and as fast as
	# the table said. Held to the grid, not to a tuned figure.
	var env := dry_env()
	env.surface_amplitude = 0.0
	env.camber = 0.0
	var solver := SimBallistics.new()
	for pair in [[8.0, 6.0], [15.0, 4.0], [20.0, 8.0], [30.0, 10.0], [40.0, 12.0]]:
		var distance: float = pair[0]
		var pace: float = pair[1]
		var speed := solver.ground_pass_speed(distance, pace, env)
		var loft := SimBallistics.drive_loft(speed)
		var b := launch_ball(Vector3(speed, loft, 0.0),
			Vector3(0.0, 0.0, speed / SimConsts.BALL_RADIUS * SimBallistics.drive_backspin(loft)))
		var t := 0.0
		while b.pos.x < distance and t < 10.0:
			b.integrate(SimConsts.DT, env)
			t += SimConsts.DT
		var label := "%.0f m at %.0f m/s" % [distance, pace]
		check_near(b.vel.length(), pace, 0.25, "the struck ball must arrive at the pace it was solved for, " + label)
		check_near(t, solver.ground_travel_time(distance, speed, env), 0.03,
			"the priced journey must be the ball's, " + label)
		check_near(b.vel.length(), solver.ground_pace_after(speed, distance, env), 0.25,
			"the pace read back must be the ball's, " + label)
		while not (b.grounded and b.ground_speed() < 1e-3) and t < 20.0:
			b.integrate(SimConsts.DT, env)
			t += SimConsts.DT
		check_near(b.pos.x, solver.ground_pass_range(speed, env), 0.5,
			"the run to a stop must be the ball's, " + label)
