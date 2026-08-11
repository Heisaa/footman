class_name SimBallistics
extends RefCounted
## Solves for the launch velocity that puts the ball where a player intends.
##
## Every kick in the game is the same primitive -- an impulse plus a spin
## (PLAN.md §3.3) -- so all of the intent lives here and the touch module only
## chooses parameters and adds error.
##
## The solvers iterate against the real integrator rather than a vacuum
## approximation, because drag matters: a vacuum solution overshoots a 40 m pass
## by several metres.

var _scratch := SimBall.new()

## Sliding then rolling deceleration constants, derived once from the sphere
## slip factor. A struck ball with no spin slides until it has lost 2/7 of its
## speed, then rolls.
const _SLIDE_FRACTION := 1.0 - (5.0 / 7.0) * (5.0 / 7.0)  # 1 - (5/7)^2
const _ROLL_FRACTION := (5.0 / 7.0) * (5.0 / 7.0)

## How much of each correction the lofted solver applies, as an exponent on the
## ratio it measured. Below 1 it converges; at 1 it rings.
const CORRECTION_DAMPING := 0.55


## Launch speed for a ground pass that travels `distance` and arrives at
## `arrive_pace` metres per second.
func ground_pass_speed(distance: float, arrive_pace: float, env: SimEnv) -> float:
	var slide_decel: float = maxf(env.slide_friction * SimConsts.GRAVITY, 0.5)
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	var k := _SLIDE_FRACTION / (2.0 * slide_decel) + _ROLL_FRACTION / (2.0 * roll_decel)
	var needed := (distance + arrive_pace * arrive_pace / (2.0 * roll_decel)) / k
	return clampf(sqrt(maxf(needed, 0.0)), 2.0, 34.0)


## Distance a ground pass struck at `speed` will run before stopping.
func ground_pass_range(speed: float, env: SimEnv) -> float:
	var slide_decel: float = maxf(env.slide_friction * SimConsts.GRAVITY, 0.5)
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	var k := _SLIDE_FRACTION / (2.0 * slide_decel) + _ROLL_FRACTION / (2.0 * roll_decel)
	return k * speed * speed


## Velocity that lofts the ball from `from` to `to` with roughly the requested
## flight time. Iterates against the integrator to absorb drag.
func solve_lofted(from: Vector3, to: Vector3, flight_time: float, env: SimEnv, spin: Vector3 = Vector3.ZERO) -> Vector3:
	var delta := SimConsts.horizontal(to - from)
	var distance: float = maxf(delta.length(), 0.5)
	var dir := delta / distance
	var height_gain := to.y - from.y
	var t: float = clampf(flight_time, 0.35, 3.0)

	# Vacuum starting guess.
	var vh := distance / t
	var vy := (height_gain + 0.5 * SimConsts.GRAVITY * t * t) / t

	# Damped, and it keeps the best guess it saw rather than whatever the last
	# iteration happened to leave behind.
	#
	# The undamped version — correct vh by distance/reached outright — was fine
	# against a constant drag coefficient and fell apart the moment the
	# coefficient became a function of speed. Striking the ball harder now moves
	# it through the drag crisis and *lowers* its drag coefficient, so range
	# responds to launch speed faster than linearly, an overshoot comes back as a
	# bigger undershoot, and the iteration rings. It was returning 88 m/s launches
	# for a 45 m pass. Raising the exponent to 1.0 will bring that straight back.
	var best := dir * vh + Vector3(0.0, vy, 0.0)
	var best_err := INF
	for _i in 8:
		var launch := dir * vh + Vector3(0.0, vy, 0.0)
		var result := _simulate_to_ground(from, launch, spin, env, to.y, t * 2.5)
		var reached: float = maxf(result.x, 0.5)  # horizontal distance covered
		var elapsed: float = maxf(result.y, 0.05)  # time to reach target height
		var err := absf(reached - distance) / distance + absf(elapsed - t) / t
		if err < best_err:
			best_err = err
			best = launch
		if err < 0.02:
			break
		vh *= pow(clampf(distance / reached, 0.4, 2.5), CORRECTION_DAMPING)
		vy *= pow(clampf(t / elapsed, 0.4, 2.5), CORRECTION_DAMPING)
	return best


## Velocity that sends the ball from `from` toward `to` at a given speed,
## choosing the flat trajectory root. Used for shots and driven passes.
func solve_direct(from: Vector3, to: Vector3, speed: float, env: SimEnv, spin: Vector3 = Vector3.ZERO) -> Vector3:
	var delta := SimConsts.horizontal(to - from)
	var distance: float = maxf(delta.length(), 0.5)
	var dir := delta / distance
	var height_gain := to.y - from.y
	var g := SimConsts.GRAVITY

	# Vacuum low-angle root. If the target is out of range at this speed, aim as
	# far as the speed allows.
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * distance * distance + 2.0 * height_gain * v2)
	var angle := 0.0
	if disc <= 0.0:
		angle = PI * 0.25
	else:
		angle = atan((v2 - sqrt(disc)) / (g * distance))

	for _i in 3:
		var vel := dir * (speed * cos(angle)) + Vector3(0.0, speed * sin(angle), 0.0)
		var height_at := _height_at_distance(from, vel, spin, env, distance)
		if height_at.y < -900.0:
			break
		var error := height_at.x - to.y
		# Small-angle correction: raising the launch angle by da lifts the ball
		# at the target by roughly distance * da for a flat trajectory.
		angle -= clampf(error / maxf(distance, 1.0), -0.25, 0.25)
		angle = clampf(angle, -0.35, 1.2)
	return dir * (speed * cos(angle)) + Vector3(0.0, speed * sin(angle), 0.0)


## Speed needed for a driven ground-height pass to cover `distance` in `time`.
func speed_for_arrival(distance: float, time: float) -> float:
	return clampf(distance / maxf(time, 0.15), 3.0, 34.0)


## Simulates a launch and returns (horizontal distance, time) at the moment the
## ball first falls back to `target_height` -- or to the grass under it, which
## is not the same height and, with a cambered pitch, is up to twenty
## centimetres lower out by the touchline.
##
## The descent test has to be against a height the ball can actually reach.
## Asking for y = 0 means the crossing never fires, the simulation runs on until
## the ball has finished bouncing and rolling, and the solver then "corrects" a
## perfectly good lofted pass into a flat drive.
func _simulate_to_ground(from: Vector3, vel: Vector3, spin: Vector3, env: SimEnv, target_height: float, max_time: float) -> Vector2:
	_scratch.pos = from
	_scratch.vel = vel
	_scratch.spin = spin
	_scratch.grounded = false
	var t := 0.0
	var rising := vel.y > 0.0
	while t < max_time:
		var prev := _scratch.pos
		_scratch.integrate(SimConsts.FORECAST_DT, env)
		t += SimConsts.FORECAST_DT
		if _scratch.vel.y <= 0.0:
			rising = false
		var land_height: float = maxf(target_height,
				SimConsts.BALL_RADIUS + env.surface_height(_scratch.pos.x, _scratch.pos.z))
		if not rising and _scratch.pos.y <= land_height:
			var travelled := SimConsts.horizontal_length(_scratch.pos - from)
			return Vector2(travelled, t)
		if _scratch.grounded:
			return Vector2(SimConsts.horizontal_length(prev - from), t)
	return Vector2(SimConsts.horizontal_length(_scratch.pos - from), t)


## Height of the ball when it has travelled `distance` horizontally, plus the
## time taken. Returns y = -1000 if the ball never gets there.
func _height_at_distance(from: Vector3, vel: Vector3, spin: Vector3, env: SimEnv, distance: float) -> Vector2:
	_scratch.pos = from
	_scratch.vel = vel
	_scratch.spin = spin
	_scratch.grounded = false
	var t := 0.0
	var last_h := from.y
	var last_d := 0.0
	while t < 4.0:
		_scratch.integrate(SimConsts.FORECAST_DT, env)
		t += SimConsts.FORECAST_DT
		var d := SimConsts.horizontal_length(_scratch.pos - from)
		if d >= distance:
			# Interpolate across the step for a smoother correction.
			var span: float = maxf(d - last_d, 1e-4)
			var f: float = clampf((distance - last_d) / span, 0.0, 1.0)
			return Vector2(lerpf(last_h, _scratch.pos.y, f), t)
		last_h = _scratch.pos.y
		last_d = d
		if _scratch.grounded and _scratch.ground_speed() < 0.3:
			break
	return Vector2(-1000.0, t)


## Time for the ball, launched flat at `speed`, to cover `distance` on the
## ground. Used for interception geometry.
func ground_travel_time(distance: float, speed: float, env: SimEnv) -> float:
	# Solve d = v0 t - 1/2 a t^2 with the blended deceleration.
	var a: float = maxf(env.roll_decel * 1.7, 0.3)
	var disc := speed * speed - 2.0 * a * distance
	if disc <= 0.0:
		return speed / a  # ball stops short; time until it stops
	return (speed - sqrt(disc)) / a
