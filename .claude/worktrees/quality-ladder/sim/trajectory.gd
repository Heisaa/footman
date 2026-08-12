class_name SimTrajectory
extends RefCounted
## Shared forward prediction of the ball's flight.
##
## Computed once per tick by the match and read by every agent (PLAN.md §3.1).
## This is both a large saving -- 22 agents would otherwise each run their own
## integrator -- and a correctness property: all agents believe the same future,
## so two defenders never disagree about where the ball will land.

var points := PackedVector3Array()
var count := 0
## Index of the first sample at or below ball radius, or -1 if the ball never
## reaches the ground inside the horizon.
var ground_index := -1
## Index of the first sample outside the field of play, or -1.
var out_index := -1

var _scratch := SimBall.new()


func _init() -> void:
	points.resize(SimConsts.FORECAST_STEPS)
	count = SimConsts.FORECAST_STEPS


## Re-runs the forecast from the ball's current state. Called once per tick.
func recompute(ball: SimBall, env: SimEnv, pitch: SimPitch) -> void:
	if _try_rolling_forecast(ball, env, pitch):
		return
	_scratch.copy_state_from(ball)
	ground_index = -1
	out_index = -1
	var was_airborne := not _scratch.grounded
	for i in SimConsts.FORECAST_STEPS:
		_scratch.integrate(SimConsts.FORECAST_DT, env)
		points[i] = _scratch.pos
		if ground_index < 0 and was_airborne and _scratch.pos.y <= SimConsts.BALL_RADIUS + 1e-3:
			ground_index = i
		if out_index < 0 and not pitch.in_bounds(_scratch.pos):
			out_index = i
		was_airborne = not _scratch.grounded


## A ball rolling without slipping travels in a straight line under a constant
## deceleration, so its future has a closed form. This covers a large share of
## the match and saves seventy-five integration steps every tick.
func _try_rolling_forecast(ball: SimBall, env: SimEnv, pitch: SimPitch) -> bool:
	if not ball.grounded:
		return false
	var vx := ball.vel.x
	var vz := ball.vel.z
	var speed := sqrt(vx * vx + vz * vz)
	# Only when the spin already matches the velocity: anything else is
	# sliding, and sliding needs the real integrator.
	var slip_x := vx + SimConsts.BALL_RADIUS * ball.spin.z
	var slip_z := vz - SimConsts.BALL_RADIUS * ball.spin.x
	if slip_x * slip_x + slip_z * slip_z > SimConsts.SLIP_EPSILON * SimConsts.SLIP_EPSILON:
		return false

	ground_index = 0
	out_index = -1
	var dir_x := 0.0
	var dir_z := 0.0
	if speed > 1e-5:
		dir_x = vx / speed
		dir_z = vz / speed
	var decel: float = maxf(env.roll_decel, 0.01)
	var stop_time := speed / decel
	for i in count:
		var t := float(i + 1) * SimConsts.FORECAST_DT
		var travelled := 0.0
		if t >= stop_time:
			travelled = speed * stop_time - 0.5 * decel * stop_time * stop_time
		else:
			travelled = speed * t - 0.5 * decel * t * t
		var p := Vector3(ball.pos.x + dir_x * travelled, SimConsts.BALL_RADIUS, ball.pos.z + dir_z * travelled)
		points[i] = p
		if out_index < 0 and not pitch.in_bounds(p):
			out_index = i
	return true


func time_of_index(i: int) -> float:
	return float(i + 1) * SimConsts.FORECAST_DT


func horizon() -> float:
	return float(count) * SimConsts.FORECAST_DT


## Predicted position `t` seconds from now, linearly interpolated between
## samples. Clamps to the end of the horizon.
func position_at(t: float) -> Vector3:
	if count == 0:
		return Vector3.ZERO
	var f := t / SimConsts.FORECAST_DT - 1.0
	if f <= 0.0:
		return points[0]
	var i := int(floor(f))
	if i >= count - 1:
		return points[count - 1]
	return points[i].lerp(points[i + 1], f - float(i))


## Time at which the ball first touches the ground, or -1 if it does not inside
## the horizon.
func first_ground_time() -> float:
	return -1.0 if ground_index < 0 else time_of_index(ground_index)


func first_ground_point() -> Vector3:
	return points[count - 1] if ground_index < 0 else points[ground_index]


## First sample index at which the ball is within `range_m` of `from` and low
## enough to play, or -1. Used for interception and keeper reach tests.
func first_reachable_index(from: Vector3, range_m: float, max_height: float) -> int:
	for i in count:
		var p := points[i]
		if p.y > max_height:
			continue
		var dx := p.x - from.x
		var dz := p.z - from.z
		if dx * dx + dz * dz <= range_m * range_m:
			return i
	return -1
