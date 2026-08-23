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

## The same, for an aimed ball, and the step-in an opponent has to have in hand
## to take one. Both belong to `control_at_pass` and to nothing else; a neutral
## race for loose grass keeps `CONTROL_TAU`.
##
## A race for a loose ball is genuinely graded — half a second down and you still
## have a share of it. A ball played to a man standing on the spot is not: either
## you are in front of it or he takes it, because `SimDuel._act` gives an arriving
## ball to whoever touches it first and he is already there. Read off
## `./run.sh control`, which strikes the ball instead of arguing about it: the
## engine cuts out 92% of balls with a defender a metre off the receiver, 48% at
## two, 20% at three, 5% at four and **none at all past that**. On the neutral
## clock the same eight rows came back 0.10, 0.16, 0.23, 0.30, 0.51, 0.70, 0.87,
## 0.98 — a gentle ramp over the whole twenty metres, smooth where the football
## is a cliff and steep where it is flat. That is the whole of why `space` had
## 0.07 of spread between the balls that arrived and the balls that did not,
## while carrying a mean of 0.60: it was discounting every pass in the match by
## forty points and telling them apart by nothing.
##
## `AIMED_STEP_IN` is the shift and `AIMED_TAU` is the sharpness, and they are one
## idea: a defender takes an aimed ball by getting *in front of* it and planting,
## which costs him a fixed time he has to have in hand, and once he has it he
## takes it nearly always. Drawing level with the flight is arriving second.
##
## Fitted to those eight rows and nothing else. `said` against what the engine
## then did now reads 0.11 / 0.52 / 0.86 / 0.96 / 1.00 against a ball kept 0.08 /
## 0.52 / 0.80 / 0.95 / 1.00. What is left above four metres is the receiver's own
## first touch, which `receiver_touch` owns and this term should not answer for.
##
## **`AIMED_TAU` is for a ball to feet only.** The winner-take-all clock is
## earned by one fact and one only — the receiver is standing on the spot, so he
## touches it first — and a ball played into space has no such man. There the
## contest is a real race between two runners, which is what `CONTROL_TAU` is,
## and `control_at_pass` picks between them on `into_space`. Run on the sharp
## clock, a ball in behind with a defender a metre off the line came back at
## 0.003: the defender reaches the landing spot with a second to spare, and
## winner-take-all turns that into a certainty. `AIMED_STEP_IN` applies to both,
## because getting in front of the ball is what an interception is either way.
##
## **All of it is measured against the defence this engine has now.** When the
## defensive pass lands and defenders step into lanes, the cliff moves out and
## these move with it. `./run.sh control` is ten seconds and is how.
const AIMED_STEP_IN := 0.70
const AIMED_TAU := 0.10

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


## How the map is built, and it is `docs/THE_FOOTBALL.md` **8b**.
##
## **It was single-step and is now not.** The old map was one hand-made function
## of distance and angle to goal: it said what a *shot* from a patch of grass is
## worth and called that the value of the grass. Football does not work that way
## -- a wide position in the final third is worth something precisely because of
## the ball that comes *next*, and to a single-step map it is just a bad shooting
## position. That is the whole of what the engine could not say, and it is why
## the middle third and the flanks read flat.
##
## So the value of a cell is the value of what happens from it, which is the
## textbook definition of expected threat:
##
##     v(c) = shot(c) * goal(c)  +  (1 - shot(c)) * SUM_c' move(c -> c') v(c')
##
## solved by iterating until it stops moving. `shot(c)` is how often a possession
## in that cell becomes an attempt, `goal(c)` what the attempt is worth, and the
## move kernel is where the ball goes when it is not a shot -- forward-weighted,
## shorter more often than longer, and losing the ball more often the further it
## goes. Nothing in it knows about players: the grid stays a pure lookup on a 5 Hz
## cadence, which is rule 1 at the top of this file, and the context correction
## stays where it was (`line_broken`).
##
## Baked once per match. Roughly a hundred thousand multiplies, which is a tenth
## of the work one tick of pitch control does.
const ITERATIONS := 40
## The longest ball the kernel considers, and how the weight falls with length: a
## footballer's next ball is usually short and occasionally very long.
const MOVE_MAX := 34.0
const MOVE_LAMBDA := 9.0
## How much more often the ball goes forward than backward. Football's own share
## of forward passes is about a third, against a sixth for each of the other
## directions, and this is that shape rather than a preference.
const MOVE_FORWARD_BIAS := 1.6
## What survives the move. A short ball is kept; a thirty-metre one is a coin
## toss, which is the honest half of why a long ball is not free value.
const MOVE_KEEP_NEAR := 0.90
const MOVE_KEEP_PER_M := 0.012
const MOVE_KEEP_FLOOR := 0.35
## How often a possession in a cell becomes a shot, by distance from goal. Steep,
## because it is what stops the map valuing the six-yard box as somewhere to pass
## *from*.
const SHOT_SHARE_LAMBDA := 11.0
const SHOT_SHARE_MAX := 0.62
const SHOT_SHARE_MIN := 0.015
## And what the attempt is worth from there. The distance decay of football's own
## conversion, times the angle the goal subtends.
const SHOT_VALUE_LAMBDA := 8.5


func _bake_expected_threat() -> void:
	var n := GRID_X * GRID_Z
	_xt.resize(n)
	var shot_share := PackedFloat32Array()
	var shot_value := PackedFloat32Array()
	shot_share.resize(n)
	shot_value.resize(n)
	var centres := PackedVector3Array()
	centres.resize(n)
	for ix in GRID_X:
		for iz in GRID_Z:
			var i := iz * GRID_X + ix
			var c := _cell_centre(ix, iz)
			centres[i] = c
			var d := SimConsts.horizontal_length(
				Vector3(SimConsts.HALF_LENGTH, 0.0, 0.0) - c)
			shot_share[i] = clampf(exp(-d / SHOT_SHARE_LAMBDA),
				SHOT_SHARE_MIN, SHOT_SHARE_MAX)
			shot_value[i] = _shot_value(c)
			_xt[i] = shot_share[i] * shot_value[i]

	# The kernel, once: for every cell, where the ball goes next and what
	# survives the trip. Held as flat arrays so the iteration below is a walk.
	var starts := PackedInt32Array()
	var targets := PackedInt32Array()
	var weights := PackedFloat32Array()
	starts.resize(n + 1)
	for i in n:
		starts[i] = targets.size()
		var from: Vector3 = centres[i]
		var total := 0.0
		var first := targets.size()
		for j in n:
			if j == i:
				continue
			var to: Vector3 = centres[j]
			var step := to - from
			var dist := SimConsts.horizontal_length(step)
			if dist > MOVE_MAX:
				continue
			# Forward is toward the goal being attacked, which is +X here.
			var forward: float = step.x / maxf(dist, 0.01)
			var w: float = exp(-dist / MOVE_LAMBDA) \
				* (1.0 + MOVE_FORWARD_BIAS * maxf(forward, 0.0))
			var keep: float = maxf(MOVE_KEEP_NEAR - dist * MOVE_KEEP_PER_M,
				MOVE_KEEP_FLOOR)
			targets.append(j)
			weights.append(w * keep)
			total += w
		# Normalised over the moves considered, so the kernel is a distribution
		# over where the ball goes and `keep` is what is lost on the way.
		if total > 0.0:
			for k in range(first, weights.size()):
				weights[k] /= total
	starts[n] = targets.size()

	var next := PackedFloat32Array()
	next.resize(n)
	for _pass in ITERATIONS:
		for i in n:
			var moved := 0.0
			for k in range(starts[i], starts[i + 1]):
				moved += weights[k] * _xt[targets[k]]
			next[i] = shot_share[i] * shot_value[i] + (1.0 - shot_share[i]) * moved
		for i in n:
			_xt[i] = next[i]

	var peak := 0.0
	for v in _xt:
		peak = maxf(peak, v)
	if peak > 0.0:
		var scale := XT_PEAK / peak
		for i in _xt.size():
			_xt[i] *= scale


## What a shot from a point is worth, with nobody in the way: football's own
## conversion by distance, times the angle the goal mouth subtends.
##
## The terminal value of the iteration above, and the only place the map says
## anything about goals. `_raw_threat` used to be both this and the value of the
## grass at once, which is the confusion 8b names.
static func _shot_value(p: Vector3) -> float:
	var dx := SimConsts.HALF_LENGTH - p.x
	var dz: float = absf(p.z)
	var d := sqrt(dx * dx + dz * dz)
	var half := SimConsts.GOAL_HALF_WIDTH
	var theta: float = absf(atan2(half - p.z, maxf(dx, 0.4))
		- atan2(-half - p.z, maxf(dx, 0.4)))
	var angle_term: float = pow(clampf(theta / 1.047, 0.0, 1.0), 0.7)
	return exp(-d / SHOT_VALUE_LAMBDA) * maxf(angle_term, 0.02)


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


## How much of the defence a point has behind it, as a multiplier on what the
## grass is worth.
##
## `docs/THE_FOOTBALL.md` 8b. Expected threat is a single-step map: it prices a
## patch of grass by what possessions there historically become, and twenty-five
## metres from goal is worth the same whether the back four is in front of the
## receiver or behind him. Those are not the same football and the difference is
## the entire value of a ball played in behind.
##
## **The map itself stays single-step and this is not it.** Making `xt_at` know
## about players would mean handing it the context at every one of its call sites,
## and the grid is deliberately a cheap pure lookup on a 5 Hz cadence. This is the
## correction applied where the act *is* the line -- the ball in behind and what a
## receiver builds from it -- rather than everywhere, which is the honest half of
## 8b and leaves the other half named.
##
## Counted rather than modelled: men of the defending side who are goal-side of
## the point, out of their outfielders. A point with none of them behind it is a
## man through on goal; one with all of them is a pass into a full block.
static func line_broken(ctx: SimContext, team: int, point: Vector3, pitch: SimPitch) -> float:
	var dir := pitch.attack_dir(team)
	var goal := pitch.target_goal(team)
	var beyond := 0
	var total := 0
	for oid in ctx.opponent_ids(team):
		var o: SimPlayer = ctx.players[oid]
		if o.is_keeper or not o.on_pitch:
			continue
		total += 1
		# Between the point and the goal they are defending.
		if (o.pos.x - point.x) * dir > 0.0 and absf(o.pos.x - goal.x) < absf(point.x - goal.x):
			beyond += 1
	if total == 0:
		return 1.0
	var share := float(beyond) / float(total)
	return lerpf(BROKEN_CLEAR, BROKEN_BLOCKED, share)


## What a point with nobody behind it is worth against one with everybody behind
## it. Both are multipliers on the map, so a ball that breaks the last line is
## worth about twice the same grass reached in front of it.
const BROKEN_CLEAR := 1.45
const BROKEN_BLOCKED := 0.75

## **Applied to the through ball and not to the lofted one, and that is measured
## rather than an oversight.** Extending it to the ball over the top as well cost
## 1.28 goals a match over twenty seeds (4.45 to 3.17) and 1.15 shots: the lofted
## ball is the one act whose target is *already* chosen for being beyond the line,
## so the term is nearly always at its maximum there and all it does is buy more
## long balls, at the completion rate long balls have. The through ball is picked
## among options that are mostly not in behind, which is where telling them apart
## is worth something.


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


## How far a player can travel along `dir` in `seconds`, from the pace he is
## going now. The inverse of `time_to_arrive`, over the same two-stage model, and
## it exists because "aim it as far ahead as he can get" was being answered with
## `top speed x flight time`.
##
## Nobody is at top speed when a ball is struck to them. A man who has just turned
## into his run is at two metres a second and needs the best part of a second to
## reach seven, so the pass was aimed several metres past where he could be -- and
## several metres past is the difference between running onto it and being just
## short of it, which is what the ball in behind kept looking like.
static func reach_in(p: SimPlayer, dir: Vector3, seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var d := SimConsts.horizontal(dir)
	if d.length_squared() < 1e-6:
		return 0.0
	d = d.normalized()
	var a: float = maxf(p.max_accel(), 0.5)
	var vmax: float = maxf(p.max_speed(), 1.0)
	var v0: float = clampf(p.vel.x * d.x + p.vel.z * d.z, 0.0, vmax)
	var t1 := (vmax - v0) / a
	if seconds <= t1:
		return v0 * seconds + 0.5 * a * seconds * seconds
	return v0 * t1 + 0.5 * a * t1 * t1 + vmax * (seconds - t1)


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
func _weigh(t: float, t_best: float, tau: float = CONTROL_TAU) -> float:
	return exp(-(t - t_best) / tau)


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


## Control of the point a pass is aimed at, for the side playing it.
##
## `_control` prices a neutral race for loose grass, and an aimed ball is not
## one (docs/THE_FOOTBALL.md 24: "the arrival contest does not know the ball was
## aimed at somebody"). Two facts break the symmetry, and both are already in
## the engine's own resolution rule -- `SimDuel._act` gives the arriving ball
## to whoever touches it first, and the man it was aimed at is standing where
## it lands:
##
##  - The intended receiver pays no reaction. Reaction is the price of
##    responding to news, and the ball is not news to the man who asked for it:
##    he committed to the point when the pass was chosen.
##  - An opponent can only win the ball *at the point* by beating it there and
##    stepping in. Arriving level with the landing is arriving second -- the
##    receiver touches it first, and what is left to the defender is the
##    challenge after the touch, which the duel prices, not the pass. So an
##    opponent is charged his own reaction again as he arrives late on the
##    ball, ramping in over the reaction before it lands: it is news to him
##    where the flight ends, and it is not news to the man it was played to.
##
## Measured before this existed (`is it ordered?`, seed 7): the model said
## 0.46 on the contested middle band and 72% of those balls arrived -- and the
## share the gap works out to is one reaction time through `CONTROL_TAU`,
## which is why the charge is the defender's own reaction and not a new
## constant.
## `into_space` says the man it is for is running onto it rather than standing on
## it, and it decides which clock the contest is settled on. See `AIMED_TAU`.
func control_at_pass(ctx: SimContext, point: Vector3, team: int, ball_time: float,
		receiver_id: int, ignore_id: int = -1, into_space: bool = false) -> float:
	return _control(ctx, point, team, maxf(ball_time, 0.0), ignore_id, receiver_id,
		CONTROL_TAU if into_space else AIMED_TAU)


## Scratch arrival times, parallel to `_dist`.
var _time := PackedFloat32Array()


## `ball_time` below zero means "as soon as anyone can get there"; at or above
## zero it is a floor on every arrival, because nobody wins a ball before it
## turns up.
##
## `aimed_id` marks the man an aimed ball is for -- see `control_at_pass`. He
## pays no reaction, and every opponent pays his own reaction again as he
## arrives late on the ball. Negative for the neutral race, which is every
## caller except the pass model.
func _control(ctx: SimContext, point: Vector3, team: int, ball_time: float, ignore_id: int, aimed_id: int = -1, tau: float = CONTROL_TAU) -> float:
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
		var t := time_to_arrive(p, point, 0.0 if i == aimed_id else reaction_of(p))
		if ball_time >= 0.0:
			if aimed_id >= 0 and p.team != team:
				# An opponent is not floored at the ball on an aimed contest: his
				# earliness *is* his interception — a defender camped on the
				# landing spot before the ball turns up steps in front and takes
				# it, and flooring him level with the waiting receiver priced
				# exactly that ball as a coin flip (measured: balls aimed within
				# 2 m of an opponent went 4% to 10% of attempts while the floor
				# was in).
				#
				# What he pays is the step-in, and he pays all of it. It used to
				# be the read alone, ramped over his reaction, and that charged
				# nothing at all to the man who matters: a defender drawing level
				# with the flight came out *earlier* than the receiver the ball
				# was played to, so he won the weighting outright at a distance
				# where the engine has him taking the ball 0% of the time.
				# Arriving with the ball is arriving second. See `AIMED_STEP_IN`.
				t += AIMED_STEP_IN
			else:
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
		var w := _weigh(_time[i], best, tau)
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
##
## `at_time` is the same floor `control_at_time` applies, and it is what makes
## this answerable about a place nobody is yet: at or above zero every arrival is
## charged at least that long, so the question becomes who owns the grass *then*
## rather than who is standing nearest to it now. Below zero it is the plain
## snapshot.
func control_at_local(ctx: SimContext, point: Vector3, team: int, at_time: float = -1.0) -> float:
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
		if at_time >= 0.0:
			t = maxf(t, at_time)
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
