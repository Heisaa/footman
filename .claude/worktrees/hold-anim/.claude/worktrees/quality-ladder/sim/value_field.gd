class_name SimValueField
extends RefCounted
## Spatial value: pitch control and expected threat (PLAN.md §4.1).
##
## Two rules govern this module:
##
## 1. Pitch control is evaluated at sampled points, never across a full grid.
##    The points that matter are teammates' current and near-future positions, a
##    handful of dribble targets and a few space probes -- 30 to 60 evaluations
##    instead of the one to two thousand a grid costs.
## 2. It is computed once per refresh and shared. No agent runs its own.
##
## A coarse full grid is available for the debug view and post-match heat maps
## only, and must never be on the decision path.

const GRID_X := 16
const GRID_Z := 12
## Logistic slope for converting an arrival-time difference into a probability.
const CONTROL_TAU := 0.42
## Peak expected threat, at roughly the penalty spot.
const XT_PEAK := 0.38

## Baked expected threat, in a canonical frame for a team attacking +X.
var _xt := PackedFloat32Array()

## Debug-only coarse pitch-control grid, refreshed at low frequency.
var debug_grid := PackedFloat32Array()
var debug_grid_tick := -1

## Scratch arrays reused every refresh so the decision path allocates nothing.
var _sample_points := PackedVector3Array()
var _sample_control := PackedFloat32Array()
var _sample_count := 0


func _init() -> void:
	_bake_expected_threat()


# --- Expected threat --------------------------------------------------------


func _bake_expected_threat() -> void:
	_xt.resize(GRID_X * GRID_Z)
	var peak := 0.0
	for ix in GRID_X:
		for iz in GRID_Z:
			var v := _raw_threat(_cell_centre(ix, iz))
			_xt[iz * GRID_X + ix] = v
			peak = maxf(peak, v)
	if peak > 0.0:
		var scale := XT_PEAK / peak
		for i in _xt.size():
			_xt[i] *= scale


## Canonical cell centre, in regulation-pitch metres, attacking +X.
static func _cell_centre(ix: int, iz: int) -> Vector3:
	var fx := (float(ix) + 0.5) / float(GRID_X)
	var fz := (float(iz) + 0.5) / float(GRID_Z)
	return Vector3(
		lerpf(-SimConsts.HALF_LENGTH, SimConsts.HALF_LENGTH, fx),
		0.0,
		lerpf(-SimConsts.HALF_WIDTH, SimConsts.HALF_WIDTH, fz)
	)


## Unnormalised positional value of a canonical point for a team attacking +X.
## Near zero in one's own third, rising steeply inside the box.
static func _raw_threat(p: Vector3) -> float:
	var dx := SimConsts.HALF_LENGTH - p.x
	var dz := absf(p.z)
	var d := sqrt(dx * dx + dz * dz)
	# Distance term: knocked down again right on the goal line so the peak sits
	# around the penalty spot rather than in the six-yard box.
	#
	# The decay rate matters more than it looks. Expected threat is what a pass
	# is worth, and it competes directly against expected goals when a player
	# decides whether to shoot. Too steep a decay makes every position outside
	# the box worthless, and the engine shoots from everywhere.
	var distance_term := exp(-0.085 * d) * (1.0 - exp(-d / 3.0))
	# Angle subtended by the goal mouth.
	var half := SimConsts.GOAL_HALF_WIDTH
	var theta := absf(atan2(half - p.z, maxf(dx, 0.4)) - atan2(-half - p.z, maxf(dx, 0.4)))
	var angle_term := pow(clampf(theta / 1.047, 0.0, 1.0), 0.75)
	return distance_term * maxf(angle_term, 0.05)


## Expected threat at a point for a team, bilinearly interpolated.
func xt_at(team: int, point: Vector3, pitch: SimPitch) -> float:
	# Bring the point into the canonical attacking-+X regulation frame.
	var d := pitch.attack_dir(team)
	var cx := point.x * d * SimConsts.HALF_LENGTH / pitch.half_length
	var cz := point.z * d * SimConsts.HALF_WIDTH / pitch.half_width
	var fx: float = clampf((cx + SimConsts.HALF_LENGTH) / SimConsts.PITCH_LENGTH * float(GRID_X) - 0.5, 0.0, float(GRID_X - 1))
	var fz: float = clampf((cz + SimConsts.HALF_WIDTH) / SimConsts.PITCH_WIDTH * float(GRID_Z) - 0.5, 0.0, float(GRID_Z - 1))
	var ix := int(fx)
	var iz := int(fz)
	var ix2: int = mini(ix + 1, GRID_X - 1)
	var iz2: int = mini(iz + 1, GRID_Z - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var a: float = lerpf(_xt[iz * GRID_X + ix], _xt[iz * GRID_X + ix2], tx)
	var b: float = lerpf(_xt[iz2 * GRID_X + ix], _xt[iz2 * GRID_X + ix2], tx)
	return lerpf(a, b, tz)


# --- Pitch control ----------------------------------------------------------


## Time for a player to arrive at a point, from their current position *and*
## velocity. Velocity matters: it is why a committed run cannot be undone.
static func time_to_arrive(p: SimPlayer, point: Vector3, reaction: float = 0.0) -> float:
	var dx := point.x - p.pos.x
	var dz := point.z - p.pos.z
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.05:
		return reaction
	var inv := 1.0 / d
	var dir_x := dx * inv
	var dir_z := dz * inv
	var v_along := p.vel.x * dir_x + p.vel.z * dir_z
	var v_perp := absf(p.vel.x * -dir_z + p.vel.z * dir_x)
	var a: float = maxf(p.max_accel(), 0.5)
	var vmax: float = maxf(p.max_speed(), 1.0)
	# Momentum across the line of travel has to be shed before it helps.
	var turn_cost := v_perp / (a * 2.0)
	v_along = clampf(v_along, -vmax, vmax)

	var t := 0.0
	if v_along >= vmax:
		t = d / vmax
	else:
		var t1 := (vmax - v_along) / a
		var d1 := v_along * t1 + 0.5 * a * t1 * t1
		if d1 >= d:
			t = (-v_along + sqrt(maxf(v_along * v_along + 2.0 * a * d, 0.0))) / a
		else:
			t = t1 + (d - d1) / vmax
	return t + reaction + turn_cost


## Reaction delay before a player can act on new information. Awareness buys
## sharpness here.
static func reaction_of(p: SimPlayer) -> float:
	return p.reaction


## How much further than the nearest player someone can be and still plausibly
## win the race, given they might be running at it while the nearest is not.
const PRUNE_SLACK := 14.0

## Scratch distance buffer, so the pruning pass allocates nothing.
var _dist := PackedFloat32Array()


## Every player who could get there counts, not only the quickest one on each
## side.
##
## This used to compare the two fastest arrival times and nothing else, and that
## is a model which cannot see a crowd: a point with one defender near it and a
## point with five defenders near it come back with exactly the same number, so
## long as the nearest of them is the same distance away. It is the reason the
## engine would play a ball into an area the opposition owned outright — the
## question "who gets there first" had a perfectly good answer and the question
## "and then what" was never asked.
##
## What replaces it weighs everyone by how far behind the earliest arrival they
## are, and reads off the share of that weight belonging to the team asking. It
## is a strict generalisation: with one player in contention on each side the sum
## collapses to exp(-a)/(exp(-a) + exp(-b)), which *is* the logistic this
## function used to return, to the last decimal. Two opponents arriving together
## against one teammate now reads 0.33 where it used to read 0.50, and a lone
## striker against a back four reads what he is worth.
##
## The decay is CONTROL_TAU, so a man half a second behind the play counts about
## a third and a man two seconds behind counts for nothing. Crowding is therefore
## local in time as well as in space — bodies standing about at the far post do
## not dilute anything.
func _weigh(t: float, t_best: float) -> float:
	return exp(-(t - t_best) / CONTROL_TAU)


## Probability that `team` wins the ball at `point`.
##
## The full arrival-time model is only run for players who could plausibly win
## the race: a cheap squared-distance pass first, then the real model for the
## handful that survive. Typically that is four or five players instead of
## twenty-two, for no measurable change in the answer.
func control_at(ctx: SimContext, point: Vector3, team: int, ignore_id: int = -1) -> float:
	return _control(ctx, point, team, -1.0, ignore_id)


## Control at a point given a specific arrival time for the receiving side --
## used to ask "if the ball gets there in 1.2 s, do we win it?".
##
## The crowd term does most of its work here. A ball hung up for a second and a
## half puts everyone who can reach the landing spot on level terms — they are
## all waiting on the ball rather than on their own legs — so what decides it is
## simply how many of each side are standing there, which is what a long ball
## into a packed box is actually decided by.
func control_at_time(ctx: SimContext, point: Vector3, team: int, ball_time: float, ignore_id: int = -1) -> float:
	return _control(ctx, point, team, maxf(ball_time, 0.0), ignore_id)


## Scratch arrival times, parallel to `_dist`.
var _time := PackedFloat32Array()


## `ball_time` below zero means "as soon as anyone can get there"; at or above
## zero it is a floor on every arrival, because nobody wins a ball before it
## turns up.
func _control(ctx: SimContext, point: Vector3, team: int, ball_time: float, ignore_id: int) -> float:
	var n := ctx.players.size()
	if _dist.size() != n:
		_dist.resize(n)
		_time.resize(n)
	var near_own := INF
	var near_opp := INF
	for i in n:
		var p := ctx.players[i]
		if not p.on_pitch or p.id == ignore_id:
			_dist[i] = INF
			continue
		var dx := p.pos.x - point.x
		var dz := p.pos.z - point.z
		var d := sqrt(dx * dx + dz * dz)
		_dist[i] = d
		if p.team == team:
			near_own = minf(near_own, d)
		else:
			near_opp = minf(near_opp, d)

	var cut_own := near_own + PRUNE_SLACK
	var cut_opp := near_opp + PRUNE_SLACK
	# Arrival times first, and the earliest of them, so the weights below can be
	# taken relative to it and never overflow.
	var best := INF
	var any_own := false
	var any_opp := false
	for i in n:
		var d := _dist[i]
		if is_inf(d):
			continue
		var p := ctx.players[i]
		if d > (cut_own if p.team == team else cut_opp):
			_dist[i] = INF
			continue
		var t := time_to_arrive(p, point, reaction_of(p))
		if ball_time >= 0.0:
			t = maxf(t, ball_time)
		_time[i] = t
		best = minf(best, t)
		if p.team == team:
			any_own = true
		else:
			any_opp = true

	if not any_own and not any_opp:
		return 0.5
	if not any_own:
		return 0.0
	if not any_opp:
		return 1.0

	var w_own := 0.0
	var w_opp := 0.0
	for i in n:
		if is_inf(_dist[i]):
			continue
		var w := _weigh(_time[i], best)
		if ctx.players[i].team == team:
			w_own += w
		else:
			w_opp += w
	return w_own / (w_own + w_opp)


## Product of control and threat: the field off-ball attackers climb.
func value_at(ctx: SimContext, point: Vector3, team: int) -> float:
	return control_at(ctx, point, team) * xt_at(team, point, ctx.pitch) * ctx.tactics(team).focus_at(point.z, ctx.pitch)


# --- Local sampling ---------------------------------------------------------
#
# When several probes are evaluated around one place -- an off-ball player
# looking at four points a few metres apart -- the set of players who could
# possibly matter is the same for all of them. Gather it once.

var _local := PackedInt32Array()
var _local_count := 0
var _local_time := PackedFloat32Array()


## Collects the players near `centre` into the local set. Everything outside is
## too far to win any race inside the probe cluster.
func begin_local(ctx: SimContext, centre: Vector3, radius: float = 30.0) -> void:
	if _local.size() != ctx.players.size():
		_local.resize(ctx.players.size())
	_local_count = 0
	var r2 := radius * radius
	for p in ctx.players:
		if not p.on_pitch:
			continue
		var dx := p.pos.x - centre.x
		var dz := p.pos.z - centre.z
		if dx * dx + dz * dz <= r2:
			_local[_local_count] = p.id
			_local_count += 1


## Pitch control at a point, using only the local set gathered by begin_local.
## Counts the crowd the same way `_control` does, or an off-ball player would
## judge space by a different rule from the one the passer judges it by.
func control_at_local(ctx: SimContext, point: Vector3, team: int) -> float:
	if _local_count == 0:
		return 0.5
	if _local_time.size() < _local_count:
		_local_time.resize(_local_count)
	var best := INF
	var any_own := false
	var any_opp := false
	for i in _local_count:
		var p := ctx.players[_local[i]]
		var t := time_to_arrive(p, point, reaction_of(p))
		_local_time[i] = t
		best = minf(best, t)
		if p.team == team:
			any_own = true
		else:
			any_opp = true
	if not any_own:
		return 0.0
	if not any_opp:
		return 1.0
	var w_own := 0.0
	var w_opp := 0.0
	for i in _local_count:
		var w := _weigh(_local_time[i], best)
		if ctx.players[_local[i]].team == team:
			w_own += w
		else:
			w_opp += w
	return w_own / (w_own + w_opp)


## Value at a point, using the local set.
func value_at_local(ctx: SimContext, point: Vector3, team: int) -> float:
	return control_at_local(ctx, point, team) * xt_at(team, point, ctx.pitch) * ctx.tactics(team).focus_at(point.z, ctx.pitch)


# --- Debug grid -------------------------------------------------------------


## Coarse full-grid pitch control for the debug view and post-match heat maps.
## Never call this from the decision path.
func refresh_debug_grid(ctx: SimContext) -> void:
	if debug_grid.size() != GRID_X * GRID_Z:
		debug_grid.resize(GRID_X * GRID_Z)
	for ix in GRID_X:
		for iz in GRID_Z:
			var fx := (float(ix) + 0.5) / float(GRID_X)
			var fz := (float(iz) + 0.5) / float(GRID_Z)
			var point := Vector3(
				lerpf(-ctx.pitch.half_length, ctx.pitch.half_length, fx),
				0.0,
				lerpf(-ctx.pitch.half_width, ctx.pitch.half_width, fz)
			)
			debug_grid[iz * GRID_X + ix] = control_at(ctx, point, SimConsts.TEAM_HOME)
	debug_grid_tick = ctx.tick_index


## Expected threat grid, for drawing. Canonical frame, attacking +X.
func threat_grid() -> PackedFloat32Array:
	return _xt
