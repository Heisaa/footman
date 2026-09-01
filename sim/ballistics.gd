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
## already describes.
##
## The driven ball's is what sets the skim tail's length, and the skim tail is
## where an overhit sheds its excess -- each low hop's friction is capped by its
## own small normal impulse, so a flat spinless skim sheds almost nothing and a
## 22 m drive overhit by a weight error ran 8 m long. More backspin widens the
## slip at every contact and lets the skim shed pace: swept on `./run.sh strike`
## at 0.2 / 0.35 / 0.5 / 0.65, the rolled long sigma at 22 and 30 m went
## 8.0/8.2 -> 7.0/7.2 -> 6.5/7.1 and turned back up at 0.65. The check the
## backspin causes on landing is *not* a reason to hold it low -- it was once
## (0.55 measured 4 m short over 22 m), but that was before `ground_launch`
## iterated the integrator: the solver now strikes harder to land the same ball,
## so the bias re-solves and only the scatter moves. `GROUND_RANGE_SPREAD` is
## fitted to this value's bench rows; moving one means re-fitting the other.
const ROLL_BACKSPIN := 0.55
const DRIVE_BACKSPIN := 0.5

## How steep the skim is for a ball leaving the boot at `h_speed` along the
## grass. Zero is a roller. One rule, read by the solver below and by
## `SimTouch.ground_pass`, so the ball that is solved is the ball that is struck.
static func drive_loft(h_speed: float) -> float:
	return clampf((h_speed - DRIVE_FROM) * DRIVE_LOFT_PER, 0.0, DRIVE_LOFT_MAX)


## And how flat it is hit, blending from the roller's backspin to the driven
## ball's as the skim grows.
static func drive_backspin(loft: float) -> float:
	return lerpf(ROLL_BACKSPIN, DRIVE_BACKSPIN, loft / DRIVE_LOFT_MAX)


## The complete prescription for a ground pass: launch speed, skim, the
## backspin that matches, and the launch heading that answers the sidespin, as
## `{"speed", "loft", "backspin", "yaw"}`.
##
## The speed comes off the ground table (`_table_for`), which is this exact
## strike integrated once per surface, so a plain ball needs no iteration. A
## bent or lifted one does: the hops replace grass friction with drag and
## bounce losses in a mix no closed form sees, and the solve exists so that
## arrival pace is solved *against* the surface -- a wet or long pitch strikes
## the ball differently and it still arrives at the pace asked for.
##
## `curl` is sidespin in rad/s of yaw, solved with the strike rather than
## stapled on after it. Unlike the lofted solver's damped yaw iteration, the
## correction here is exact and costs nothing: rotating a launch about UP
## rotates the whole trajectory rigidly — the horizontal physics has no
## preferred direction and UP-spin is invariant under the turn — so the yaw
## that cancels the drift is read straight off the unrotated landing.
## `lift` is `BEND_LIFT` when the bend is meant, and the solve carries it so
## the clipped ball still decays to its arrival pace at its distance.
func ground_launch(distance: float, arrive_pace: float, env: SimEnv, curl: float = 0.0, lift: float = 0.0) -> Dictionary:
	var speed := ground_pass_speed(distance, arrive_pace, env)
	var loft := drive_loft(speed)
	if loft <= 0.0:
		# A roller: Magnus does nothing on the grass, so neither does the curl.
		return {"speed": speed, "loft": 0.0, "backspin": ROLL_BACKSPIN, "yaw": 0.0}
	if curl == 0.0 and lift == 0.0:
		# `ground_pass_speed` is read off the table of this exact strike, so
		# there is nothing left to iterate for.
		return {"speed": speed, "loft": loft, "backspin": drive_backspin(loft), "yaw": 0.0}
	var slide_decel: float = maxf(env.slide_friction * SimConsts.GRAVITY, 0.5)
	var roll_decel: float = maxf(env.roll_decel, 0.1)
	var k := _SLIDE_FRACTION / (2.0 * slide_decel) + _ROLL_FRACTION / (2.0 * roll_decel)
	var landing := Vector2(distance, 0.0)
	for i in 6:
		landing = _driven_range(speed, arrive_pace, env, curl, lift)
		var short := distance - landing.length()
		if absf(short) < 0.15:
			break
		# Newton step on the law's own slope, range = k v^2, which is close
		# enough to steer by even though the hops are what it cannot see.
		speed = clampf(speed + short / maxf(2.0 * k * speed, 0.5), DRIVE_FROM, 34.0)
	return {"speed": speed, "loft": drive_loft(speed), "backspin": drive_backspin(drive_loft(speed)),
		"yaw": atan2(landing.y, maxf(landing.x, 0.5))}


## Where a driven ball launched at `h_speed` has decayed to `arrive_pace` —
## the point the pass model aims at and the point a receiver meets it. The same
## criterion the strike bench lands on, deliberately. Returns the landing as
## `(x, z)` in the launch frame: the sideways drift a `curl` puts on the hops
## is the whole reason `ground_launch` asks for the point and not the distance.
func _driven_range(h_speed: float, arrive_pace: float, env: SimEnv, curl: float = 0.0, lift: float = 0.0) -> Vector2:
	_scratch.reset(Vector3(0.0, SimConsts.BALL_RADIUS, 0.0))
	var loft := drive_loft(h_speed)
	# Backspin for travel along +X. `SimBall`'s own convention: rolling without
	# slipping along +X is (0, 0, -v/r), so backspin is the positive z.
	var spin := Vector3(0.0, curl, h_speed / SimConsts.BALL_RADIUS * drive_backspin(loft))
	_scratch.launch(Vector3(h_speed, loft + lift, 0.0), spin)
	var t := 0.0
	while t < 6.0:
		_scratch.integrate(SimConsts.FORECAST_DT, env)
		t += SimConsts.FORECAST_DT
		if _scratch.vel.length() <= arrive_pace:
			break
	return Vector2(_scratch.pos.x, _scratch.pos.z)


# --- The ground pass, tabulated ---------------------------------------------
#
# Every question the decision layer asks about a ground pass -- how hard to
# strike it, when it gets there, what pace it has left, where it stops -- is
# answered off one table: the engine's own strike (`drive_loft`,
# `drive_backspin`) launched at each speed and integrated at the match step, on
# a flat pitch. The predictor *is* the integrator, to a grid.
#
# It replaced a two-phase slide-then-roll closed form that had two errors of
# opposite sign. It knew nothing of the skim, so it under-struck every driven
# ball and then, at its own under-struck speed, overstated the journey by 5-17%
# over 15-40 m; and it assumed a spinless slide, so the backspun roller the
# engine actually plays ran 8-11% longer than it said. `_pass_success` prices
# every interception in the match off the travel time, and the ball it priced
# was not the ball that was struck. Measured 2026-09-01.
#
# One table per surface, keyed on the numbers that shape the run, and kept in
# a static: it is a pure function of the constants, not match state, so the
# rule about statics in `docs/INVARIANTS.md` does not apply. Built lazily,
# ~100 ms once per process per surface.

const TABLE_SPEED_MIN := 2.0
const TABLE_SPEED_MAX := 34.0
const TABLE_SPEED_STEP := 0.5
const TABLE_DIST_STEP := 0.5
const TABLE_DIST_MAX := 100.0
## Longer than any ball in the table takes to stop.
const TABLE_MAX_SECONDS := 20.0


class GroundTable:
	var speeds := 0
	var cols := 0
	## Per launch speed and distance column: seconds to reach the column, or
	## the time the ball stopped if it never does; and the ball's speed there,
	## zero if it stopped short.
	var time := PackedFloat32Array()
	var pace := PackedFloat32Array()
	## Per launch speed: where it stopped and when.
	var range := PackedFloat32Array()
	var stop_time := PackedFloat32Array()


static var _tables: Dictionary = {}


static func _table_for(env: SimEnv) -> GroundTable:
	var key := "%s|%s|%s" % [env.roll_decel, env.slide_friction, env.restitution]
	if _tables.has(key):
		return _tables[key]
	var t := _build_table(env)
	_tables[key] = t
	return t


static func _build_table(env: SimEnv) -> GroundTable:
	var flat := env.duplicate_env()
	flat.surface_amplitude = 0.0
	flat.camber = 0.0
	var t := GroundTable.new()
	t.speeds = int(round((TABLE_SPEED_MAX - TABLE_SPEED_MIN) / TABLE_SPEED_STEP)) + 1
	t.cols = int(round(TABLE_DIST_MAX / TABLE_DIST_STEP)) + 1
	t.time.resize(t.speeds * t.cols)
	t.pace.resize(t.speeds * t.cols)
	t.range.resize(t.speeds)
	t.stop_time.resize(t.speeds)
	var ball := SimBall.new()
	for i in t.speeds:
		var v := TABLE_SPEED_MIN + float(i) * TABLE_SPEED_STEP
		var loft := drive_loft(v)
		ball.reset(Vector3(0.0, SimConsts.BALL_RADIUS, 0.0))
		# Backspin for travel along +X, `SimBall`'s convention.
		ball.launch(Vector3(v, loft, 0.0), Vector3(0.0, 0.0, v / SimConsts.BALL_RADIUS * drive_backspin(loft)))
		var row := i * t.cols
		t.time[row] = 0.0
		t.pace[row] = v
		var col := 1
		var elapsed := 0.0
		var last_x := 0.0
		var last_v := v
		while elapsed < TABLE_MAX_SECONDS:
			ball.integrate(SimConsts.DT, flat)
			elapsed += SimConsts.DT
			var speed := ball.vel.length()
			while col < t.cols and ball.pos.x >= float(col) * TABLE_DIST_STEP:
				var x := float(col) * TABLE_DIST_STEP
				var f := (x - last_x) / maxf(ball.pos.x - last_x, 1e-6)
				t.time[row + col] = lerpf(elapsed - SimConsts.DT, elapsed, f)
				t.pace[row + col] = lerpf(last_v, speed, f)
				col += 1
			last_x = ball.pos.x
			last_v = speed
			if ball.grounded and ball.ground_speed() < 1e-3:
				break
		t.range[i] = ball.pos.x
		t.stop_time[i] = elapsed
		while col < t.cols:
			t.time[row + col] = elapsed
			t.pace[row + col] = 0.0
			col += 1
	return t


## Bilinear read of one of the per-speed, per-distance arrays.
static func _read(t: GroundTable, arr: PackedFloat32Array, speed: float, distance: float) -> float:
	var fi: float = clampf((speed - TABLE_SPEED_MIN) / TABLE_SPEED_STEP, 0.0, float(t.speeds - 1))
	var fd: float = clampf(distance / TABLE_DIST_STEP, 0.0, float(t.cols - 1))
	var i := mini(int(fi), t.speeds - 2)
	var d := mini(int(fd), t.cols - 2)
	var wi := fi - float(i)
	var wd := fd - float(d)
	var a := lerpf(arr[i * t.cols + d], arr[i * t.cols + d + 1], wd)
	var b := lerpf(arr[(i + 1) * t.cols + d], arr[(i + 1) * t.cols + d + 1], wd)
	return lerpf(a, b, wi)


## Launch speed for a ground pass that travels `distance` and arrives at
## `arrive_pace` metres per second. The lowest speed in the table that still
## has that pace at that distance, interpolated; clamped to the table's ends
## like the old solve was.
func ground_pass_speed(distance: float, arrive_pace: float, env: SimEnv) -> float:
	var t := _table_for(env)
	# The distance column, interpolated once; then each row is two reads.
	var fd: float = clampf(distance / TABLE_DIST_STEP, 0.0, float(t.cols - 1))
	var d := mini(int(fd), t.cols - 2)
	var wd := fd - float(d)
	var pace := t.pace
	var cols := t.cols
	var hi := t.speeds - 1
	if lerpf(pace[hi * cols + d], pace[hi * cols + d + 1], wd) <= arrive_pace:
		return TABLE_SPEED_MAX
	var lo := 0
	var p_lo: float = lerpf(pace[d], pace[d + 1], wd)
	if p_lo >= arrive_pace:
		return TABLE_SPEED_MIN
	# Pace at a distance rises with the launch, so bisect the rows.
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		var p_mid: float = lerpf(pace[mid * cols + d], pace[mid * cols + d + 1], wd)
		if p_mid < arrive_pace:
			lo = mid
			p_lo = p_mid
		else:
			hi = mid
	var p_hi: float = lerpf(pace[hi * cols + d], pace[hi * cols + d + 1], wd)
	var f: float = clampf((arrive_pace - p_lo) / maxf(p_hi - p_lo, 1e-6), 0.0, 1.0)
	return TABLE_SPEED_MIN + (float(lo) + f) * TABLE_SPEED_STEP


## Pace a ground pass struck at `speed` still has after running `distance`.
## Zero if it stops short.
func ground_pace_after(speed: float, distance: float, env: SimEnv) -> float:
	var t := _table_for(env)
	if distance > TABLE_DIST_MAX:
		return 0.0
	return _read(t, t.pace, speed, distance)


## Distance a ground pass struck at `speed` will run before stopping.
func ground_pass_range(speed: float, env: SimEnv) -> float:
	var t := _table_for(env)
	var fi: float = clampf((speed - TABLE_SPEED_MIN) / TABLE_SPEED_STEP, 0.0, float(t.speeds - 1))
	var i := mini(int(fi), t.speeds - 2)
	return lerpf(t.range[i], t.range[i + 1], fi - float(i))


## Time for the ball, struck at `speed`, to cover `distance` on the ground; the
## time it stops if it never gets there. Used for interception geometry, and
## the number every pass in the match is priced off.
func ground_travel_time(distance: float, speed: float, env: SimEnv) -> float:
	var t := _table_for(env)
	if distance > TABLE_DIST_MAX:
		var fi: float = clampf((speed - TABLE_SPEED_MIN) / TABLE_SPEED_STEP, 0.0, float(t.speeds - 1))
		var i := mini(int(fi), t.speeds - 2)
		return lerpf(t.stop_time[i], t.stop_time[i + 1], fi - float(i))
	return _read(t, t.time, speed, distance)


# --- The bend, predicted -----------------------------------------------------

## What one rough constant holds: the spin decays and the ball slows over the
## flight, both of which shrink the Magnus force the launch figures promise.
const CURL_BOW_DECAY := 0.7
## The share of a driven pass's journey the ball spends up in its hops, where
## Magnus acts. A roller bends not at all; a skimming drive bends about half as
## much as the same ball in clean air. Starting value, read against the
## two-flight test in `test_ball` -- if the measurement disagrees, this moves.
const DRIVEN_BOW_SHARE := 0.5
## The extra climb a *meant* bend is struck with, in m/s of launch loft on top
## of `drive_loft`. Sidespin only works in the air, and the first cut of the
## bent lane measured that out: an ordinary drive is airborne for half its
## journey and bowed 0.18 m over twenty metres -- less than a leg's free reach
## -- so the bent lane never opened. You cannot whip a flat skimmer; the meant
## bend is clipped up into knee-high hops (apex around 0.6 m) and the same
## spin gets most of the flight to work in.
const BEND_LIFT := 1.5
## And that lifted ball's airborne share, for `curl_bow`. Read against the
## lifted two-flight case in `test_ball`, like `DRIVEN_BOW_SHARE`.
const BEND_BOW_SHARE := 0.85


## How far a ball struck at `speed` with `curl` rad/s of sidespin departs from
## its chord at mid-flight, in metres, signed: positive curl bows the path
## toward the striker's left (`UP.cross(vel)` -- `curl_for`'s convention).
##
## The closed form under the integrator's own constants: lift saturates in the
## spin factor S, the lateral acceleration is `MAGNUS_K * Cl * v^2`, and a
## constant sideways acceleration over a chord of time T bows it `a T^2 / 8`.
## The decision layer prices a bend with this *before* choosing it, which is
## why it exists -- the integrator answers the same question exactly and costs
## a flight per candidate. Validated against the integrator by two-flight
## difference in `test_ball`, the way every lateral figure here has been.
static func curl_bow(curl: float, speed: float, distance: float, airborne_share := 1.0) -> float:
	var v: float = maxf(speed, 1.0)
	var s: float = absf(curl) * SimConsts.BALL_RADIUS / v
	var cl: float = SimConsts.MAGNUS_CL_MAX * s / (s + SimConsts.MAGNUS_S_HALF)
	var accel: float = SimConsts.MAGNUS_K * cl * v * v
	var t: float = distance / v
	return signf(curl) * accel * t * t * 0.125 * airborne_share * CURL_BOW_DECAY


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
	# almost none. `solve_direct` had the same hole; it is closed the same way,
	# for the day a shot means its bend.
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
##
## Corrects the launch heading for sidespin the same way `solve_lofted` does --
## see the note there. A ball with a meant bend on it is aimed off the line so
## the bend brings it back onto the point.
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

	# Two corrections share the loop -- the height at the target, and the yaw
	# that answers the sidespin. Best guess kept, like `solve_lofted` and for
	# the same reason.
	var yaw := 0.0
	var best := dir * (speed * cos(angle)) + Vector3(0.0, speed * sin(angle), 0.0)
	var best_err := INF
	for _i in 5:
		var aim_dir := dir.rotated(Vector3.UP, yaw)
		var vel := aim_dir * (speed * cos(angle)) + Vector3(0.0, speed * sin(angle), 0.0)
		var height_at := _height_at_distance(from, vel, spin, env, distance)
		if height_at.x < -900.0:
			# Never covered the distance: nothing to measure, more angle.
			angle = clampf(angle + 0.25, -0.35, 1.2)
			continue
		var error := height_at.x - to.y
		# How far to the side of the intended line it crossed the target
		# distance, positive toward the left of it -- `solve_lofted`'s
		# convention, corrected the same way.
		var rel := SimConsts.horizontal(_at_distance_pos - from)
		var off := rel.x * dir.z - rel.z * dir.x
		var err := absf(error) / maxf(distance, 1.0) + absf(off) / distance
		if err < best_err:
			best_err = err
			best = vel
		# Small-angle correction: raising the launch angle by da lifts the ball
		# at the target by roughly distance * da for a flat trajectory.
		angle -= clampf(error / maxf(distance, 1.0), -0.25, 0.25)
		angle = clampf(angle, -0.35, 1.2)
		yaw = clampf(yaw - clampf(off / distance, -0.5, 0.5) * CORRECTION_DAMPING, -0.6, 0.6)
	return best


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


## Where the flight crossed the target distance, for `solve_direct`'s yaw
## correction. Held like `_land_pos` and for the same reason.
var _at_distance_pos := Vector3.ZERO


## Height of the ball when it has travelled `distance` horizontally, plus the
## time taken. Returns a height of -1000 if the ball never gets there.
func _height_at_distance(from: Vector3, vel: Vector3, spin: Vector3, env: SimEnv, distance: float) -> Vector2:
	_scratch.pos = from
	_scratch.vel = vel
	_scratch.spin = spin
	_scratch.grounded = false
	var t := 0.0
	var last_p := from
	var last_d := 0.0
	while t < 4.0:
		_scratch.integrate(SimConsts.FORECAST_DT, env)
		t += SimConsts.FORECAST_DT
		var d := SimConsts.horizontal_length(_scratch.pos - from)
		if d >= distance:
			# Interpolate across the step for a smoother correction.
			var span: float = maxf(d - last_d, 1e-4)
			var f: float = clampf((distance - last_d) / span, 0.0, 1.0)
			_at_distance_pos = last_p.lerp(_scratch.pos, f)
			return Vector2(lerpf(last_p.y, _scratch.pos.y, f), t)
		last_p = _scratch.pos
		last_d = d
		if _scratch.grounded and _scratch.ground_speed() < 0.3:
			break
	return Vector2(-1000.0, t)
