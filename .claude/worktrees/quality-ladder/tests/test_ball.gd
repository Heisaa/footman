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
	_ball_never_sinks()
	_forecast_agrees_with_the_integrator()


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
