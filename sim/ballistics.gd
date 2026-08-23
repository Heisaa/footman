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
const _SLIP := 5.0 / 7.0
const _SLIDE_FRACTION := 1.0 - _SLIP * _SLIP
const _ROLL_FRACTION := _SLIP * _SLIP

## How much of each correction the lofted solver applies, as an exponent on the
## ratio it measured. Below 1 it converges; at 1 it rings.
const CORRECTION_DAMPING := 0.55


# --- The driven pass --------------------------------------------------------

## A firm pass is driven, not rolled. Nobody plays a twenty-metre ball in
## constant contact with the grass — it leaves the boot a few degrees up, skims
## in low hops, and sits down into a roll. The skim starts where the strike gets
## firm and grows with it, in metres per second of climb per metre per second of
## launch above `DRIVE_FROM`; the cap keeps the apex under a shin.
const DRIVE_FROM := 11.0
const DRIVE_LOFT_PER := 0.45
const DRIVE_LOFT_MAX := 2.0
## Backspin as a fraction of the rolling rate, at the two ends of the strike. A
## rolled pass is clipped under, and its backspin is the slide the two-phase law
## already describes. A driven ball is hit through the middle and skids on —
## given the roller's backspin it checked at every bounce like a wedge shot,
## measured on the bench at 4 m short over 22 m.
const ROLL_BACKSPIN := 0.55
const DRIVE_BACKSPIN := 0.2

## How steep the skim is for a ball leaving the boot at `h_speed` along the
## grass. Zero is a roller. One rule, read by the solver below and by
## `SimTouch.ground_pass`, so the ball that is solved is the ball that is struck.
static func drive_loft(h_speed: float) -> float:
	return clampf((h_speed - DRIVE_FROM) * DRIVE_LOFT_PER, 0.0, DRIVE_LOFT_MAX)


## And how flat it is hit, blending from the roller's backspin to the driven
## ball's as the skim grows.
static func drive_backspin(loft: float) -> float:
	return lerpf(ROLL_BACKSPIN, DRIVE_BACKSPIN, loft / DRIVE_LOFT_MAX)


## The complete prescription for a ground pass: launch speed, skim, and the
## backspin that matches, as `{"speed", "loft", "backspin"}`.
##
## A roller comes straight off the closed form. A driven ball cannot — the hops
## replace grass friction with drag and bounce losses in a mix no closed form
## sees, and fitting a scale factor instead would break the invariant the solve
## exists for: arrival pace is solved *against* the surface, so a wet or long
## pitch strikes the ball differently and it still arrives at the pace asked
## for. So the driven launch iterates the real integrator, like the lofted
## solver above it and for the same reason.
func ground_launch(distance: float, arrive_pace: float, env: SimEnv) -> Dictionary:
	var speed := ground_pass_speed(distance, arrive_pace, env)
	var loft := drive_loft(speed)
	if loft <= 0.0:
		return {"speed": speed, "loft": 0.0, "backspin": ROLL_BACKSPIN}
	var slide_decel: float = maxf(env.slide_friction * SimConsts.GRAVITY, 0.5)
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	var k := _SLIDE_FRACTION / (2.0 * slide_decel) + _ROLL_FRACTION / (2.0 * roll_decel)
	for i in 6:
		var reached := _driven_range(speed, arrive_pace, env)
		var short := distance - reached
		if absf(short) < 0.15:
			break
		# Newton step on the law's own slope, range = k v^2, which is close
		# enough to steer by even though the hops are what it cannot see.
		speed = clampf(speed + short / maxf(2.0 * k * speed, 0.5), DRIVE_FROM, 34.0)
	return {"speed": speed, "loft": drive_loft(speed), "backspin": drive_backspin(drive_loft(speed))}


## Where a driven ball launched at `h_speed` has decayed to `arrive_pace` —
## the point the pass model aims at and the point a receiver meets it. The same
## criterion the strike bench lands on, deliberately.
func _driven_range(h_speed: float, arrive_pace: float, env: SimEnv) -> float:
	_scratch.reset(Vector3(0.0, SimConsts.BALL_RADIUS, 0.0))
	var loft := drive_loft(h_speed)
	# Backspin for travel along +X. `SimBall`'s own convention: rolling without
	# slipping along +X is (0, 0, -v/r), so backspin is the positive z.
	var spin := Vector3(0.0, 0.0, h_speed / SimConsts.BALL_RADIUS * drive_backspin(loft))
	_scratch.launch(Vector3(h_speed, loft, 0.0), spin)
	var t := 0.0
	while t < 6.0:
		_scratch.integrate(SimConsts.FORECAST_DT, env)
		t += SimConsts.FORECAST_DT
		if _scratch.vel.length() <= arrive_pace:
			break
	return _scratch.pos.x


## Launch speed for a ground pass that travels `distance` and arrives at
## `arrive_pace` metres per second.
func ground_pass_speed(distance: float, arrive_pace: float, env: SimEnv) -> float:
	var slide_decel: float = maxf(env.slide_friction * SimConsts.GRAVITY, 0.5)
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	var k := _SLIDE_FRACTION / (2.0 * slide_decel) + _ROLL_FRACTION / (2.0 * roll_decel)
	var needed := (distance + arrive_pace * arrive_pace / (2.0 * roll_decel)) / k
	return clampf(sqrt(maxf(needed, 0.0)), 2.0, 34.0)


## Pace a ground pass struck at `speed` still has after running `distance`.
##
## The exact inverse of `ground_pass_speed`, and it has to be that rather than
## anything simpler. There are two friction models in this file: the two-phase
## slide-then-roll one the strike is solved against, and the single blended decel
## `ground_travel_time` uses. Backing the arrival pace out of the second gives
## about a metre a second too much over twenty-five, which is exactly the
## difference between a ball a runner catches and one he does not — it read a
## through ball out at 8.1 m/s that had been struck to arrive at 7.2. Nothing in
## `sim/` calls this; the instruments do, and they were getting it wrong.
func ground_pace_after(speed: float, distance: float, env: SimEnv) -> float:
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	return sqrt(maxf(ground_pass_range(speed, env) - distance, 0.0) * 2.0 * roll_decel)


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
	# And how far the launch is turned off the straight line, so that a ball with
	# sidespin on it bends back onto the point rather than away from it.
	#
	# The solver took `spin` from the first day and corrected only the two things
	# measured along the line of the ball -- how far it got and how long it took.
	# A curled ball's whole point is that it does not travel along that line, and
	# nothing here was looking sideways: measured, a cross at the engine's own
	# `SimTouch.CROSS_CURL` came down **1.5 m** off its target, and at a
	# footballer's spin it was six. Every bend the game could put on a ball was
	# therefore a bend away from where it was aimed, which is why there was
	# almost none. `solve_direct` has the same hole and it does not bite yet:
	# `SHOT_CURL` is small and a shot is over in half the time.
	var yaw := 0.0
	var best := dir * vh + Vector3(0.0, vy, 0.0)
	var best_err := INF
	for _i in 8:
		var aim_dir := dir.rotated(Vector3.UP, yaw)
		var launch := aim_dir * vh + Vector3(0.0, vy, 0.0)
		var result := _simulate_to_ground(from, launch, spin, env, to.y, t * 2.5)
		var reached: float = maxf(result.x, 0.5)  # horizontal distance covered
		var elapsed: float = maxf(result.y, 0.05)  # time to reach target height
		# How far to the side of the intended line it finished, positive toward
		# the left of it.
		var land := SimConsts.horizontal(_land_pos - from)
		var off := land.x * dir.z - land.z * dir.x
		var err := absf(reached - distance) / distance + absf(elapsed - t) / t \
			+ absf(off) / distance
		if err < best_err:
			best_err = err
			best = launch
		if err < 0.02:
			break
		vh *= pow(clampf(distance / reached, 0.4, 2.5), CORRECTION_DAMPING)
		vy *= pow(clampf(t / elapsed, 0.4, 2.5), CORRECTION_DAMPING)
		# Turning the launch by +a moves the ball toward the left of the line, so
		# a finish to the left is answered by turning the other way. Damped like
		# the other two corrections, and clamped: a solver that can spin the ball
		# round to face the other way is worse than one that gives up.
		yaw = clampf(yaw - clampf(off / reached, -0.5, 0.5) * CORRECTION_DAMPING,
			-0.6, 0.6)
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
## Where the flight above finished, for the caller that needs the point and not
## just the distance. Held here rather than returned because every other caller
## wants the two numbers.
var _land_pos := Vector3.ZERO


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
			_land_pos = _scratch.pos
			return Vector2(travelled, t)
		if _scratch.grounded:
			_land_pos = prev
			return Vector2(SimConsts.horizontal_length(prev - from), t)
	_land_pos = _scratch.pos
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


## The single deceleration that reproduces the slide-then-roll range, in m/s^2.
##
## `ground_pass_range` is `k v^2`, and constant deceleration gives `v^2 / 2a`, so
## the `a` the two agree on is `1 / 2k` and there is nothing to choose. It used to
## be `roll_decel * 1.7`, a fitted number that happened to sit 21% high at a
## rolling resistance of 1.6 and went to 38% high when that was raised -- so the
## interception geometry believed the ball was slower than the ball was, by an
## amount that depended on the grass. `_pass_success` prices every pass off the
## travel time this returns, and a long ball was being charged for a journey it
## did not make.
func blended_decel(env: SimEnv) -> float:
	var slide_decel: float = maxf(env.slide_friction * SimConsts.GRAVITY, 0.5)
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	var k := _SLIDE_FRACTION / (2.0 * slide_decel) + _ROLL_FRACTION / (2.0 * roll_decel)
	return 1.0 / (2.0 * maxf(k, 1e-6))


## Time for the ball, launched flat at `speed`, to cover `distance` on the
## ground. Used for interception geometry.
##
## The two phases solved in turn, not a single blended deceleration. `blended_decel`
## is the `a` that reproduces the *range*, which is what it was written for and all
## it is good for: matching the total distance to a stop says nothing about how long
## the ball takes to get anywhere short of it. Measured, a 25 m pass struck at
## 14.6 m/s takes 2.39 s and the blended answer was 2.21 -- 7% quick, and
## `_pass_success` prices every interception in the match off exactly this number,
## so every pass in the engine was charged for a journey quicker than the one it
## makes. It is the same class of error the note above records being fixed once
## before, surviving in the half of the model nobody had checked.
func ground_travel_time(distance: float, speed: float, env: SimEnv) -> float:
	var slide_decel: float = maxf(env.slide_friction * SimConsts.GRAVITY, 0.5)
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	# The slide, which ends when the ball has lost 2/7 of its speed.
	var rolling := speed * _SLIP
	var slide_span := _SLIDE_FRACTION * speed * speed / (2.0 * slide_decel)
	if distance <= slide_span:
		var d1 := speed * speed - 2.0 * slide_decel * distance
		return (speed - sqrt(maxf(d1, 0.0))) / slide_decel
	var t1 := (speed - rolling) / slide_decel
	# And the roll, from the speed the slide left it at.
	var disc := rolling * rolling - 2.0 * roll_decel * (distance - slide_span)
	if disc <= 0.0:
		return t1 + rolling / roll_decel  # ball stops short; time until it stops
	return t1 + (rolling - sqrt(disc)) / roll_decel
