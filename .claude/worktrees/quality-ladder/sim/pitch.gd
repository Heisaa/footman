class_name SimPitch
extends RefCounted
## Pitch geometry for one match.
##
## Dimensions live here rather than in SimConsts so that small-sided prototype
## matches (PLAN.md §12) can run on a proportionally smaller pitch without every
## geometric query being wrong. Defaults are regulation.

var half_length := SimConsts.HALF_LENGTH
var half_width := SimConsts.HALF_WIDTH
var goal_half_width := SimConsts.GOAL_HALF_WIDTH
var goal_height := SimConsts.GOAL_HEIGHT
var penalty_depth := SimConsts.PENALTY_AREA_DEPTH
var penalty_half_width := SimConsts.PENALTY_AREA_HALF_WIDTH
var goal_area_depth := SimConsts.GOAL_AREA_DEPTH
var goal_area_half_width := SimConsts.GOAL_AREA_HALF_WIDTH
var penalty_spot_dist := SimConsts.PENALTY_SPOT_DIST
var centre_circle := SimConsts.CENTRE_CIRCLE_RADIUS

## Which way each team attacks this period, as a unit X component. Index by team.
var attack_x := PackedFloat32Array([1.0, -1.0])


## Regulation 105 x 68.
static func regulation() -> SimPitch:
	return SimPitch.new()


## A regulation pitch shrunk by `factor`, keeping eleven a side.
##
## The lever for a compressed match. Events per second of football are set by
## how far the ball and the players have to travel, so taking a fifth off every
## distance is worth about a fifth more football per second — and it buys that
## without touching one quantity the eye is calibrated to. Players still run at
## six to eight metres a second, the ball still slows at the same rate, the
## stride still matches the ground speed. A faster world would buy the same
## density and read as a video being scrubbed.
##
## The goal does not shrink with it, deliberately: the same target at the end of
## a shorter pitch is a higher chance of scoring from a given position, which is
## the second thing a compressed match needs. Everything else scales, so
## `scale_point` carries the formations onto it unchanged and the thirds, the
## offside line and the pressing zones all still mean what they meant.
static func scaled(factor: float) -> SimPitch:
	var f: float = clampf(factor, 0.3, 1.0)
	if is_equal_approx(f, 1.0):
		return regulation()
	var p := SimPitch.new()
	p.half_length = SimConsts.HALF_LENGTH * f
	p.half_width = SimConsts.HALF_WIDTH * f
	p.penalty_depth = SimConsts.PENALTY_AREA_DEPTH * f
	p.penalty_half_width = SimConsts.PENALTY_AREA_HALF_WIDTH * f
	p.goal_area_depth = SimConsts.GOAL_AREA_DEPTH * f
	p.goal_area_half_width = SimConsts.GOAL_AREA_HALF_WIDTH * f
	p.penalty_spot_dist = SimConsts.PENALTY_SPOT_DIST * f
	p.centre_circle = SimConsts.CENTRE_CIRCLE_RADIUS * f
	return p


## A proportionally reduced pitch for small-sided prototype matches.
static func small_sided(length: float = 72.0, width: float = 46.0) -> SimPitch:
	var p := SimPitch.new()
	var sx := length / SimConsts.PITCH_LENGTH
	var sz := width / SimConsts.PITCH_WIDTH
	p.half_length = length * 0.5
	p.half_width = width * 0.5
	p.goal_half_width = SimConsts.GOAL_HALF_WIDTH * 0.75
	p.goal_height = SimConsts.GOAL_HEIGHT * 0.9
	p.penalty_depth = SimConsts.PENALTY_AREA_DEPTH * sx
	p.penalty_half_width = SimConsts.PENALTY_AREA_HALF_WIDTH * sz
	p.goal_area_depth = SimConsts.GOAL_AREA_DEPTH * sx
	p.goal_area_half_width = SimConsts.GOAL_AREA_HALF_WIDTH * sz
	p.penalty_spot_dist = SimConsts.PENALTY_SPOT_DIST * sx
	p.centre_circle = SimConsts.CENTRE_CIRCLE_RADIUS * sz
	return p


## Called at half time. Teams change ends; the presentation may flip the camera
## instead, but the simulation is authoritative.
func swap_ends() -> void:
	attack_x[0] = -attack_x[0]
	attack_x[1] = -attack_x[1]


func attack_dir(team: int) -> float:
	return attack_x[team]


## Centre of the goal `team` is attacking.
func target_goal(team: int) -> Vector3:
	return Vector3(attack_x[team] * half_length, 0.0, 0.0)


## Centre of the goal `team` is defending.
func own_goal(team: int) -> Vector3:
	return Vector3(-attack_x[team] * half_length, 0.0, 0.0)


func in_bounds(p: Vector3) -> bool:
	return absf(p.x) <= half_length and absf(p.z) <= half_width


func clamp_to_pitch(p: Vector3, inset: float = 0.0) -> Vector3:
	return Vector3(
		clampf(p.x, -half_length + inset, half_length - inset),
		p.y,
		clampf(p.z, -half_width + inset, half_width - inset)
	)


## How far a ball struck from `from` along `dir` can run before it crosses a
## line, with `inset` metres of margin. INF for a direction that never leaves.
##
## The decision layer needs this to know whether an option it is about to score
## has anywhere to happen. A knock into space that puts the ball on the far side
## of the touchline is not a knock into space, and the value function cannot see
## it: the point it evaluates gets clamped back inside, so the option scores as
## though the ball stopped where it was aimed.
func run_room(from: Vector3, dir: Vector3, inset: float = 0.0) -> float:
	var room := INF
	var lx: float = half_length - inset
	var lz: float = half_width - inset
	if absf(dir.x) > 1e-5:
		var edge_x: float = lx if dir.x > 0.0 else -lx
		room = minf(room, maxf((edge_x - from.x) / dir.x, 0.0))
	if absf(dir.z) > 1e-5:
		var edge_z: float = lz if dir.z > 0.0 else -lz
		room = minf(room, maxf((edge_z - from.z) / dir.z, 0.0))
	return room


## True if the point is inside the penalty area `team` defends.
func in_own_penalty_area(team: int, p: Vector3) -> bool:
	if absf(p.z) > penalty_half_width:
		return false
	var goal_x := -attack_x[team] * half_length
	return absf(p.x - goal_x) <= penalty_depth and absf(p.x) <= half_length


## True if the point is inside the penalty area `team` attacks.
func in_opponent_penalty_area(team: int, p: Vector3) -> bool:
	if absf(p.z) > penalty_half_width:
		return false
	var goal_x := attack_x[team] * half_length
	return absf(p.x - goal_x) <= penalty_depth and absf(p.x) <= half_length


func penalty_spot(team: int) -> Vector3:
	return Vector3(attack_x[team] * (half_length - penalty_spot_dist), 0.0, 0.0)


## Signed distance past the goal line, positive when the ball has fully crossed.
func past_goal_line(p: Vector3) -> float:
	return absf(p.x) - half_length


## True if a point is between the posts and under the bar at the goal line.
func inside_goal_mouth(p: Vector3) -> bool:
	return absf(p.z) <= goal_half_width and p.y <= goal_height


## Scales a canonical position expressed for a regulation pitch onto this one.
func scale_point(p: Vector3) -> Vector3:
	return Vector3(
		p.x * half_length / SimConsts.HALF_LENGTH,
		p.y,
		p.z * half_width / SimConsts.HALF_WIDTH
	)


## Mirrors a canonical position (given for a team attacking +X) into the frame
## of the team that actually attacks in `attack_x[team]`.
func orient(team: int, p: Vector3) -> Vector3:
	var d := attack_x[team]
	return Vector3(p.x * d, p.y, p.z * d)
