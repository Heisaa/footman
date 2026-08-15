class_name SimBall
extends RefCounted
## The match ball: state plus a hand-written integrator.
##
## Godot's physics engine is deliberately not used (PLAN.md §2.1). A football
## needs a sphere over a plane with a correct sliding-to-rolling transition; a
## general rigid body solver costs determinism and speed and buys nothing.
##
## Spin is stored as an angular velocity vector (axis * rad/s). Sign convention
## follows the right hand rule in the sim's coordinate frame, so a ball rolling
## along +X without slipping has spin (0, 0, -v / r).

var pos := Vector3(0.0, SimConsts.BALL_RADIUS, 0.0)
var vel := Vector3.ZERO
var spin := Vector3.ZERO
## True when the ball is resting on the surface. It is cleared the moment
## anything gives the ball upward velocity.
var grounded := true

# --- Provenance -------------------------------------------------------------
# There is no possession flag (PLAN.md §3.3). Possession is derived from the
# last touch plus contest range, so the ball only records who touched it.
var last_touch_player := -1
var last_touch_team := -1
var last_touch_tick := -1
var last_touch_kind := -1
## Where the ball was when it was last touched. For the books: a goal scored by
## a touch that was never an attempt is written up as a shot from here.
var last_touch_pos := Vector3.ZERO
## The player a pass was aimed at, if the last touch was a pass. -1 otherwise.
var intended_target := -1

# Per-step decay factors, cached against the integration step size.
var _cached_dt := -1.0
var _spin_decay_step := 1.0
var _yaw_decay_step := 1.0


func reset(at: Vector3 = Vector3(0.0, SimConsts.BALL_RADIUS, 0.0)) -> void:
	pos = at
	pos.y = maxf(pos.y, SimConsts.BALL_RADIUS)
	vel = Vector3.ZERO
	spin = Vector3.ZERO
	grounded = is_equal_approx(pos.y, SimConsts.BALL_RADIUS)
	last_touch_player = -1
	last_touch_team = -1
	last_touch_tick = -1
	last_touch_kind = -1
	last_touch_pos = Vector3.ZERO
	intended_target = -1


func copy_state_from(other: SimBall) -> void:
	pos = other.pos
	vel = other.vel
	spin = other.spin
	grounded = other.grounded


## Applies a kick: replaces velocity outright (a struck ball's impulse dominates
## whatever it was doing) and sets spin.
func launch(new_vel: Vector3, new_spin: Vector3) -> void:
	vel = new_vel
	spin = new_spin
	if vel.y > 0.0:
		grounded = false
		# Lift the ball clear of the surface so the impact resolver does not
		# immediately re-capture it on the same tick. Relative, because the
		# surface the ball is sitting on is not at a fixed height.
		pos.y += 1e-4


## Advances the ball by `dt` seconds. `dt` is always the fixed simulation step
## or the forecast step -- never a frame delta.
func integrate(dt: float, env: SimEnv) -> void:
	if dt != _cached_dt:
		# `pow` is not worth calling once per step when the step size never
		# changes: the match ball always integrates at 1/60 and the forecast
		# scratch always at 1/30.
		_cached_dt = dt
		var exponent := dt * float(SimConsts.TICK_HZ)
		_spin_decay_step = pow(SimConsts.SPIN_DECAY, exponent)
		_yaw_decay_step = pow(SimConsts.GROUND_YAW_SPIN_DECAY, exponent)
	if grounded and vel.y > 1e-4:
		grounded = false
	if grounded:
		vel.y = 0.0
		_ground_step(dt, env)
		pos += vel * dt
		# The ball follows the grass rather than a plane, so its height is read
		# back off the surface at wherever it has arrived.
		pos.y = SimConsts.BALL_RADIUS + env.surface_height(pos.x, pos.z)
	else:
		_flight_step(dt)
		if pos.y <= SimConsts.BALL_RADIUS + env.surface_height(pos.x, pos.z):
			_resolve_impact(dt, env)


# --- Flight -----------------------------------------------------------------


func _flight_step(dt: float) -> void:
	var speed := vel.length()
	var acc := Vector3(0.0, -SimConsts.GRAVITY, 0.0)
	if speed > 1e-6:
		# Quadratic drag: 1/2 rho Cd A v^2, opposing motion. Cd is a function of
		# speed, not a constant -- see SimConsts.DRAG_COEFF_SLOW.
		acc -= vel * (SimConsts.drag_k(speed) * speed)
	if speed > 1e-6 and spin.length_squared() > 1e-8:
		# Magnus. The direction is spin x velocity; the magnitude is a lift
		# coefficient that saturates in the spin factor, so a ball turning at its
		# own rolling rate is not thrown about (see SimConsts.MAGNUS_CL_MAX).
		var cross := spin.cross(vel)
		var cross_len := cross.length()
		if cross_len > 1e-6:
			# |omega x v| = |omega_perp| |v|, so S = |omega_perp| r / |v| is
			# cross_len * r / |v|^2.
			var s := cross_len * SimConsts.BALL_RADIUS / (speed * speed)
			var cl := SimConsts.MAGNUS_CL_MAX * s / (s + SimConsts.MAGNUS_S_HALF)
			acc += cross * (SimConsts.MAGNUS_K * cl * speed * speed / cross_len)
	vel += acc * dt
	pos += vel * dt
	spin *= _spin_decay_step


# --- Ground contact ---------------------------------------------------------


func _resolve_impact(dt: float, env: SimEnv) -> void:
	pos.y = SimConsts.BALL_RADIUS + env.surface_height(pos.x, pos.z)
	# The ball bounces off the grass it actually hit, not off a horizontal plane.
	# A degree or two of tilt is what stops every bounce coming up the same way.
	var slope := env.surface_slope(pos.x, pos.z)
	var normal := Vector3(-slope.x, 1.0, -slope.z).normalized()
	var vn := vel.dot(normal)
	if vn < -SimConsts.BOUNCE_SNAP_VY:
		# A real bounce. The normal impulse sets a ceiling on how much tangential
		# impulse friction can deliver, which is why a fast flat ball skids on
		# and a dropping ball grips.
		var normal_impulse := SimConsts.BALL_MASS * (1.0 + env.restitution) * absf(vn)
		vel -= normal * ((1.0 + env.restitution) * vn)
		_apply_tangential_impulse(env.slide_friction * normal_impulse)
		grounded = false
	else:
		vel.y = 0.0
		grounded = true
		_ground_step(dt, env)


## Contact-point velocity relative to the (stationary) surface, horizontal only.
## Zero means rolling without slipping.
func _slip_velocity() -> Vector3:
	# u = v - r * (omega x n), with n = up.
	return Vector3(
		vel.x + SimConsts.BALL_RADIUS * spin.z,
		0.0,
		vel.z - SimConsts.BALL_RADIUS * spin.x
	)


## Applies a horizontal friction impulse opposing slip, capped at `max_impulse`.
## For a uniform sphere the impulse that exactly kills slip is 2/7 * m * |u|.
func _apply_tangential_impulse(max_impulse: float) -> void:
	var slip := _slip_velocity()
	var slip_speed := slip.length()
	if slip_speed < 1e-7:
		return
	var needed := SimConsts.SPHERE_SLIP_FACTOR * SimConsts.BALL_MASS * slip_speed
	var magnitude := minf(needed, max_impulse)
	var impulse := slip * (-magnitude / slip_speed)
	vel += impulse / SimConsts.BALL_MASS
	# dOmega = I^-1 * (r_contact x J), r_contact = -r * up, I = 2/5 m r^2.
	var lever := Vector3(0.0, -SimConsts.BALL_RADIUS, 0.0)
	spin += lever.cross(impulse) * (2.5 / (SimConsts.BALL_MASS * SimConsts.BALL_RADIUS * SimConsts.BALL_RADIUS))


func _ground_step(dt: float, env: SimEnv) -> void:
	# Gravity along the grass. A rolling sphere takes 5/7 of it; the rest spins
	# the ball up, and `_snap_to_rolling` keeps that bookkeeping honest. Only a
	# ball with pace on it is pushed, because rolling resistance holds a still
	# ball on a slope this gentle and the alternative is a ball that never
	# settles.
	if SimConsts.horizontal_length(vel) > SimConsts.SURFACE_SLOPE_MIN_SPEED:
		var slope := env.surface_slope(pos.x, pos.z)
		var push := SimConsts.SPHERE_ROLL_SLOPE * SimConsts.GRAVITY * dt
		vel.x -= slope.x * push
		vel.z -= slope.z * push
	var slip_speed := _slip_velocity().length()
	if slip_speed > SimConsts.SLIP_EPSILON:
		# Sliding: friction decelerates the ball and spins it up. This is why a
		# backspun pass checks up and a topspun one runs on.
		var friction_accel := env.slide_friction * SimConsts.GRAVITY
		var slip_reduction := SimConsts.SPHERE_SLIP_RATE * friction_accel * dt
		if slip_reduction >= slip_speed:
			# Slip would be exhausted inside this step: land exactly on rolling.
			_apply_tangential_impulse(INF)
			_snap_to_rolling()
		else:
			_apply_tangential_impulse(SimConsts.BALL_MASS * friction_accel * dt)
	else:
		_snap_to_rolling()
		var speed := SimConsts.horizontal_length(vel)
		if speed > 1e-5:
			var new_speed := maxf(0.0, speed - env.roll_decel * dt)
			vel.x *= new_speed / speed
			vel.z *= new_speed / speed
		else:
			vel.x = 0.0
			vel.z = 0.0
		_snap_to_rolling()
	# Spin about the vertical axis does nothing for rolling but scrubs off on grass.
	spin.y *= _yaw_decay_step


## Forces the spin that corresponds to rolling without slipping at the current
## velocity, leaving spin about the vertical axis alone.
func _snap_to_rolling() -> void:
	var inv_r := 1.0 / SimConsts.BALL_RADIUS
	spin.x = vel.z * inv_r
	spin.z = -vel.x * inv_r


# --- Queries ----------------------------------------------------------------


func speed() -> float:
	return vel.length()


func ground_speed() -> float:
	return SimConsts.horizontal_length(vel)


func ground_pos() -> Vector3:
	return Vector3(pos.x, 0.0, pos.z)


func height() -> float:
	return pos.y


## True if a standing player could play this ball with a foot.
func at_foot_height() -> bool:
	return pos.y <= SimConsts.FOOT_REACH_HEIGHT


## True if the ball has fully crossed the plane of a goal line, side lines aside.
func over_goal_line(pitch: SimPitch) -> bool:
	return absf(pos.x) > pitch.half_length + SimConsts.BALL_RADIUS


func over_touch_line(pitch: SimPitch) -> bool:
	return absf(pos.z) > pitch.half_width + SimConsts.BALL_RADIUS
