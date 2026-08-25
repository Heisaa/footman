class_name SimSetPiece
extends RefCounted
## The restart state machine (PLAN.md §3.5).
##
## A set piece suspends normal play, positions players from a routine, and
## releases after a delay. Routines are tactical assets: the roguelike layer
## unlocks them, so they are data-driven rather than hard-coded behaviour.

enum Kind { KICKOFF, THROW_IN, GOAL_KICK, CORNER, FREE_KICK, INDIRECT_FREE_KICK, PENALTY }

const KIND_NAMES := [
	"kick-off", "throw-in", "goal kick", "corner", "free kick", "indirect free kick", "penalty",
]


static func kind_name(kind: int) -> String:
	return KIND_NAMES[kind] if kind >= 0 and kind < KIND_NAMES.size() else "?"

## Minimum and maximum delay before a restart is taken, in ticks.
const MIN_DELAY := 36
const MAX_WAIT := SimConsts.TICK_HZ * 8
## The longer wait, for the restarts the kicking side reorganises around.
##
## A goal kick used to be struck six tenths of a second after the whistle, which
## is nobody's goal kick, and it made the push-out in `RESTART_SHAPE_DEPTH`
## invisible: the side was told to move thirteen metres up the pitch and the ball
## was gone before anyone had covered three of them. Three seconds is enough at a
## restart jog, and is still a quarter of what a goal kick takes in life.
const SETTLE_DELAY := SimConsts.TICK_HZ * 3
## Where the taker is asked to stand relative to the dead ball.
##
## `update` will not let him strike a ball he is not within CONTROL_RANGE of, and
## he was being asked to stand at 0.9 m for a free kick and 1.2 m for a goal
## kick -- at the boundary and outside it. He would arrive at his spot, stop, and
## never become ready, so every free kick and every goal kick sat there for the
## full eight-second timeout and was then taken by teleporting him onto the ball.
## Measured before the fix: goal kicks waited 7.6 s and free kicks 8.0 s, against
## a delay that was supposed to be six tenths of a second.
const TAKER_STANCE := SimConsts.CONTROL_RANGE * 0.7
## Ticks a thrower holds the ball over his head before he lets go of it. Half a
## second: long enough for the wind-up to be a wind-up on screen, short enough
## that a quick throw is still quick.
const THROW_WINDUP := SimConsts.TICK_HZ / 2
## How high off the grass a throw leaves the hands. A throw-in used to be
## launched from the ball's resting position at the touchline, which is a ball
## struck off the floor with somebody's arms waving above it; the solver then
## had to loft it from ground level and every throw came out as a scooped chip.
## Released from over the head it is a flatter ball over the same distance, which
## is what a throw is.
const THROW_HEIGHT := 2.1
## Required distance from the ball for the defending side.
const WALL_DISTANCE := 9.15
## How far the kicking side's outfielders stand off a goal kick, so that the
## keeper is visibly alone over the ball.
const KEEPER_CLEARANCE := 6.0
## How far outside the penalty area the defending side is put at a goal kick.
##
## The law says outside, and the spots have to say further than that or the rule
## reads as broken even when it is kept. At 1.5 m the diagnostic still found 0.2
## opponents a goal kick inside the area, which was not the gate failing -- that
## is exact, and it is checked at the instant of the strike -- but men standing
## on the paint with a 5 Hz trace catching them mid-stride. Two and a half metres
## puts the line between the two sides where an eye can see it.
const AREA_CLEARANCE := 2.5

## The deepest the ball may be, as a fraction of the half length, when the
## kicking side builds its restart shape around it.
##
## `SimMovement.shape_position` slides the whole formation with the ball, which
## is right in open play and wrong over a dead ball in your own six-yard box. A
## goal kick pulled the back four onto the goal line they were defending -- the
## pull is 0.36 of the ball's own depth, so from 47 metres out it is nearly
## seventeen metres of it, and the clamp against the goal line was doing the rest
## -- and left the side stretched over eighty metres with the front three already
## at halfway. No football team stands like that, and anyone watching can see it.
##
## A restart in your own half is a moment with nobody pressing the ball and eight
## seconds to use it, and what a side does with those eight seconds is push out.
## So the shape is built around the ball no deeper than the top of the kicking
## side's own third. Nothing else changes: the same formation, the same tactical
## line height, the same widths, so a deep-block side is still deeper than a
## high-line one. The back four end up around the edge of their own box, the
## midfield in front of them and the front line at halfway, which is the shape
## and is also considerably more compact than what it replaces.
##
## Zero, so the line is the halfway line: the side builds its restart shape as
## though the ball were already in the middle of the pitch. Clamping at the top
## of its own third instead was tried first and left the back four ten metres
## off their own goal line, which is a shape for a short goal kick and not for
## anything else. At the halfway line the back four stand on the edge of their
## own box, the midfield is around thirty metres out and the front line is into
## the opposition half, which is what a side taking a goal kick looks like.
const RESTART_SHAPE_DEPTH := 0.0


static func kickoff(ctx: SimContext, team: int) -> void:
	_begin(ctx, Kind.KICKOFF, team, Vector3(0.0, SimConsts.BALL_RADIUS, 0.0))
	ctx.phase = SimConsts.Phase.KICKOFF
	# Everyone into their own half; the kicking side puts one player on the ball.
	for p in ctx.players:
		var spot := SimMovement.shape_position(ctx, p)
		var dir := ctx.pitch.attack_dir(p.team)
		if spot.x * dir > -2.0:
			spot.x = -2.0 * dir
		ctx.restart_spots[p.id] = spot
	var taker := _nearest_of(ctx, team, Vector3.ZERO, true)
	if taker != null:
		ctx.restart_taker = taker.id
		ctx.restart_spots[taker.id] = Vector3(-0.6 * ctx.pitch.attack_dir(team), 0.0, 0.0)
	_snap_everyone(ctx)


## How far a throw can be sent, in metres, for the weakest and the strongest
## thrower. A footballer throws about fifteen; a specialist gets past twenty-five
## and is a tactical asset because of it.
const THROW_SHORT := 13.0
const THROW_LONG := 26.0

## The three men a thrower is entitled to, as offsets in a frame where +X is the
## way his team attacks and +Z is infield from the touchline he is standing on.
##
## A throw-in used to be taken into whatever shape happened to be standing there,
## and the shape has no idea a throw-in is happening: `SimMovement.shape_position`
## slides the formation toward the ball, so the nearest men drifted *toward* the
## touchline and stood in each other's light while the thrower looked for someone
## to aim at. What he needs is what a real side gives him -- one short down the
## line to knock it back, one showing infield off the line, and one gone up the
## line behind the full-back -- and none of those three is a position the shape
## would ever produce on its own.
##
## They are offsets from the ball, so the same three exist at either end of
## either touchline, and they are only *offered*: the thrower still scores them
## against everyone else and can ignore all three.
## Spaced out rather than crowded on top of the thrower: the first cut had the
## short man five metres away, he won nearly every throw on pitch control alone,
## and the mean throw came out at seven metres, which is a tap and not a throw.
const THROW_SUPPORT := [
	Vector3(3.5, 0.0, 6.5),
	Vector3(-7.0, 0.0, 8.5),
	Vector3(16.0, 0.0, 4.0),
]


static func throw_in(ctx: SimContext, team: int, at: Vector3) -> void:
	var spot := Vector3(clampf(at.x, -ctx.pitch.half_length + 1.0, ctx.pitch.half_length - 1.0), SimConsts.BALL_RADIUS, at.z)
	_begin(ctx, Kind.THROW_IN, team, spot)
	_default_spots(ctx, spot, team, 3.0)
	_throw_support(ctx, spot, team)


## Assigns the three support positions to the three nearest outfielders who are
## not the taker, nearest man to nearest offer, so nobody crosses anybody.
static func _throw_support(ctx: SimContext, spot: Vector3, team: int) -> void:
	var dir := ctx.pitch.attack_dir(team)
	# Infield is whichever way the middle of the pitch is from this touchline.
	var infield := -signf(spot.z) if absf(spot.z) > 0.1 else 1.0
	var taken := {}
	for offset in THROW_SUPPORT:
		var point := ctx.pitch.clamp_to_pitch(
			spot + Vector3(offset.x * dir, 0.0, offset.z * infield), 1.5
		)
		var best: SimPlayer = null
		var best_d := INF
		for pid in ctx.team_players[team]:
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch or p.id == ctx.restart_taker or taken.has(p.id):
				continue
			var d := p.dist_to(point)
			if d < best_d:
				best_d = d
				best = p
		if best == null:
			return
		taken[best.id] = true
		ctx.restart_spots[best.id] = point


static func goal_kick(ctx: SimContext, team: int) -> void:
	var goal := ctx.pitch.own_goal(team)
	var spot := Vector3(goal.x + ctx.pitch.attack_dir(team) * ctx.pitch.goal_area_depth, SimConsts.BALL_RADIUS, 0.0)
	_begin(ctx, Kind.GOAL_KICK, team, spot)
	var keeper := ctx.teams[team].keeper()
	# The keeper takes it, so `_default_spots` must not also send the nearest
	# outfielder onto the ball — two players standing over a goal kick reads as
	# a bug to anyone watching.
	_default_spots(ctx, spot, team, 12.0, keeper == null, true, true)
	# And the law: the defending side waits outside the area. The radial clearance
	# above cannot say that -- twelve metres from a spot on the six-yard line is
	# still inside the box anywhere off the middle of it, which is where a striker
	# stands -- so the shape it produced is pushed out of the area as well.
	for p in ctx.players:
		if p.team == team or p.is_keeper or not ctx.restart_spots.has(p.id):
			continue
		ctx.restart_spots[p.id] = ctx.pitch.clamp_to_pitch(
			_out_of_penalty_area(ctx.pitch, team, ctx.restart_spots[p.id], AREA_CLEARANCE), 0.5
		)
	if keeper != null:
		ctx.restart_taker = keeper.id
		ctx.restart_spots[keeper.id] = spot - Vector3(ctx.pitch.attack_dir(team) * TAKER_STANCE, 0.0, 0.0)
		# A back three puts its middle centre-back on the spot's own line, so the
		# taker fix alone does not leave the keeper alone over the ball. Anyone
		# else on the kicking side stands off it.
		for p in ctx.players:
			if p.team != team or p.is_keeper or not ctx.restart_spots.has(p.id):
				continue
			var target: Vector3 = ctx.restart_spots[p.id]
			var away := target - spot
			away.y = 0.0
			var d := away.length()
			if d < KEEPER_CLEARANCE:
				var dir := away / d if d > 0.1 else Vector3(ctx.pitch.attack_dir(team), 0.0, 0.0)
				ctx.restart_spots[p.id] = ctx.pitch.clamp_to_pitch(spot + dir * KEEPER_CLEARANCE, 0.5)


## The nearest point outside the penalty area `team` defends, with `margin`
## metres to spare. Points already outside come back unchanged.
##
## The shortest way out, which is the way a player would walk it: forward past
## the eighteen-yard line if he is somewhere near the middle, sideways past the
## edge of the area if he is wide. Picking one of the two unconditionally is how
## a defending side ends up in a queue on the D or strung along the touchline.
static func _out_of_penalty_area(pitch: SimPitch, team: int, point: Vector3, margin: float) -> Vector3:
	if not pitch.in_own_penalty_area(team, point):
		return point
	var dir := pitch.attack_dir(team)
	var goal_x := -dir * pitch.half_length
	var front := goal_x + dir * (pitch.penalty_depth + margin)
	var flank := pitch.penalty_half_width + margin
	var out_front := absf(front - point.x)
	var side: float = signf(point.z) if absf(point.z) > 0.1 else 1.0
	var out_side := flank - absf(point.z)
	if out_front <= out_side:
		return Vector3(front, point.y, point.z)
	return Vector3(point.x, point.y, side * flank)


## True when every opponent is out of the area a goal kick is being taken from.
##
## Read as a condition on taking the kick rather than as a positioning rule,
## because positioning is a request and this is the law. The spots put them
## outside; this is what stops the ball being struck while somebody is still
## walking out.
static func _area_is_clear(ctx: SimContext) -> bool:
	for p in ctx.players:
		if p.team == ctx.restart_team or not p.on_pitch:
			continue
		if ctx.pitch.in_own_penalty_area(ctx.restart_team, p.pos):
			return false
	return true


static func corner(ctx: SimContext, team: int, side: float) -> void:
	var goal := ctx.pitch.target_goal(team)
	var spot := Vector3(goal.x - signf(goal.x) * 0.3, SimConsts.BALL_RADIUS, side * (ctx.pitch.half_width - 0.3))
	_begin(ctx, Kind.CORNER, team, spot)
	_corner_spots(ctx, team, spot)


static func free_kick(ctx: SimContext, team: int, at: Vector3, indirect: bool) -> void:
	var spot := ctx.pitch.clamp_to_pitch(Vector3(at.x, SimConsts.BALL_RADIUS, at.z), 0.6)
	spot.y = SimConsts.BALL_RADIUS
	_begin(ctx, Kind.INDIRECT_FREE_KICK if indirect else Kind.FREE_KICK, team, spot)
	# A free kick in your own half is a free eight seconds, same as a goal kick,
	# and the side takes it the same way: it pushes out. Past halfway the shape is
	# already where the ball is and the rule does nothing.
	_default_spots(ctx, spot, team, WALL_DISTANCE, true, true)
	if SimConsts.horizontal_length(ctx.pitch.target_goal(team) - spot) < FK_DELIVERY_RANGE:
		_load_box(ctx, team, spot)


## How far from goal a free kick is one the side loads the box for, and how many
## it sends. The range is `_take_free_kick`'s own delivery threshold, so the men
## are sent exactly when the ball can be put on their heads.
const FK_DELIVERY_RANGE := 42.0
const FK_BOX_MEN := 4


## Attackers into the box for a free kick that can be delivered into it.
##
## `_default_spots` stands both sides on their ordinary shape for a ball at the
## spot, and for a free kick twenty metres out that shape leaves the box empty --
## while `_take_free_kick` lofts the ball to nine metres from goal whatever is in
## there. Measured on `fk-shot`: the delivery came down **20.8 m from the nearest
## of ours**. A corner has had `_corner_spots` for this since it was written; the
## free kick never had the equivalent.
##
## A side loads the box for a free kick in the final third whether the ball ends
## up shot or delivered, so this does not have to know which the taker will pick.
## The men sent are the four the shape already had nearest the goal, which is the
## forwards without having to name them.
static func _load_box(ctx: SimContext, team: int, spot: Vector3) -> void:
	var goal := ctx.pitch.target_goal(team)
	var dir := ctx.pitch.attack_dir(team)
	# Mirrored onto the side the ball is coming from, as a corner is.
	var side: float = signf(spot.z) if absf(spot.z) > 1e-3 else 1.0
	var order: Array[SimPlayer] = []
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if p.is_keeper or not p.on_pitch or p.id == ctx.restart_taker:
			continue
		if not ctx.restart_spots.has(p.id):
			continue
		order.append(p)
	order.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool:
		var da: float = SimConsts.horizontal_length(goal - ctx.restart_spots[a.id])
		var db: float = SimConsts.horizontal_length(goal - ctx.restart_spots[b.id])
		return da < db)
	var offsets := [
		Vector3(-5.5, 0.0, -3.5), Vector3(-9.0, 0.0, 2.5),
		Vector3(-4.0, 0.0, 4.5), Vector3(-12.0, 0.0, -1.0),
	]
	for i in mini(FK_BOX_MEN, order.size()):
		var o: Vector3 = offsets[i]
		ctx.restart_spots[order[i].id] = ctx.pitch.clamp_to_pitch(
			goal + Vector3(o.x * dir, 0.0, o.z * side), 0.5)


static func penalty(ctx: SimContext, team: int) -> void:
	var spot := ctx.pitch.penalty_spot(team)
	spot.y = SimConsts.BALL_RADIUS
	_begin(ctx, Kind.PENALTY, team, spot)
	# Everyone outside the box except the taker and the keeper.
	for p in ctx.players:
		if p.is_keeper:
			var own := ctx.pitch.own_goal(p.team)
			ctx.restart_spots[p.id] = Vector3(own.x + signf(-own.x) * 0.4, 0.0, 0.0)
			continue
		var dir := ctx.pitch.attack_dir(team)
		var edge := ctx.pitch.half_length - ctx.pitch.penalty_depth - 2.5
		ctx.restart_spots[p.id] = Vector3(edge * dir, 0.0, ctx.rng.range_float(-14.0, 14.0))
	var taker := _best_finisher(ctx, team)
	if taker != null:
		ctx.restart_taker = taker.id
		ctx.restart_spots[taker.id] = spot - Vector3(dir_of(ctx, team) * TAKER_STANCE, 0.0, 0.0)
	_snap_everyone(ctx)


static func dir_of(ctx: SimContext, team: int) -> float:
	return ctx.pitch.attack_dir(team)


# --- Shared machinery -------------------------------------------------------


static func _begin(ctx: SimContext, kind: int, team: int, spot: Vector3) -> void:
	ctx.in_play = false
	ctx.phase = SimConsts.Phase.SET_PIECE
	ctx.restart_kind = kind
	ctx.restart_team = team
	ctx.restart_pos = spot
	ctx.restart_ticks = 0
	ctx.restart_hold = 0
	ctx.restart_taker = -1
	ctx.restart_spots.clear()
	ctx.ball.reset(spot)
	ctx.ball.last_touch_team = team
	ctx.ball.last_touch_player = -1
	ctx.offside_pending = -1
	ctx.log_event(SimTelemetry.Ev.SET_PIECE, {
		"kind": kind,
		"team": team,
		"pos": spot,
		"minute": ctx.minute(),
	})


## Where a player stands for a restart.
##
## The kicking side's outfielders push out, on the rule in `RESTART_SHAPE_DEPTH`.
## The keeper does not -- he is either taking it or minding the goal.
##
## `push_defenders` gives the other side the same imaginary ball, and it is what
## a goal kick needs. The rule above was written for the kicking side alone, and
## the missing half is what put an opponent's chest in front of the ball.
## `SimMovement.shape_position` slides a shape toward the ball; measured in the
## frame the defending side attacks in, a ball on the six-yard line sits
## forty-seven metres up the pitch, so `BALL_PULL_X` carried their whole team
## seventeen metres onto it. A front line standing seventeen metres inside the
## opposition half by formation ended up on the edge of the penalty area, which
## is exactly where a goal kick struck along the grass hits somebody.
##
## With it on, both sides build their shape around the same point and the point
## is the halfway line: the kicking side comes up off its own goal line, the
## defending side drops back off the box, and the forty metres between the two
## banks is the picture a goal kick makes. It is off for an own-half free kick,
## where the defending side pressing high is a choice it is entitled to make.
static func _restart_shape(ctx: SimContext, p: SimPlayer, spot: Vector3, team: int, push_up: bool, push_defenders: bool = false) -> Vector3:
	if p.is_keeper:
		return SimKeeper.station(ctx, p, spot)
	var mine := p.team == team
	if not push_up or (not mine and not push_defenders):
		return SimMovement.shape_position(ctx, p)
	var canonical := ctx.pitch.orient(p.team, spot)
	var limit := -ctx.pitch.half_length * RESTART_SHAPE_DEPTH
	# Deep in his own half for the kicking side, far up it for the defending one:
	# the same line, met from either direction, and the shape is built at it.
	if (canonical.x >= limit) if mine else (canonical.x <= -limit):
		return SimMovement.shape_position(ctx, p)
	canonical.x = limit if mine else -limit
	canonical.y = 0.0
	return SimMovement.shape_position(ctx, p, ctx.pitch.orient(p.team, canonical))


## Puts everyone at their shape position, pushes the defending side back the
## required distance, and picks the nearest attacker as the taker.
static func _default_spots(ctx: SimContext, spot: Vector3, team: int, clearance_radius: float, pick_taker := true, push_up := false, push_defenders := false) -> void:
	for p in ctx.players:
		var target := _restart_shape(ctx, p, spot, team, push_up, push_defenders)
		if p.team != team:
			var away := target - spot
			away.y = 0.0
			var d := away.length()
			if d < clearance_radius:
				var dir := away / d if d > 0.1 else (ctx.pitch.own_goal(p.team) - spot).normalized()
				target = spot + dir * clearance_radius
		ctx.restart_spots[p.id] = ctx.pitch.clamp_to_pitch(target, 0.5)
	if not pick_taker:
		return
	var taker := _nearest_of(ctx, team, spot, true)
	if taker != null:
		ctx.restart_taker = taker.id
		ctx.restart_spots[taker.id] = spot - (spot - ctx.pitch.own_goal(team)).normalized() * TAKER_STANCE


## Where the two sides stand for a corner.
##
## **The z offsets are mirrored onto the flag the corner is taken from.** They
## were not, and the same near-post/far-post pattern was therefore laid out the
## same way round whichever side the ball came from -- so one flank's corner put
## the bodies where the ball swings and the other put them where it does not,
## from one list. Measured on the scenario pair, which is the same corner twice
## and differs in nothing else: `corner-left` won 0.4 headers a trial and scored
## 20%, `corner-right` 0.1 and 10%, and 28% of right corners ran the clock out
## with nobody having attacked the ball at all.
##
## **And the defenders are dealt in order rather than by `p.id % 7`.** Ten
## outfielders onto seven offsets by their id meant three spots held two men
## each, standing on the same square metre, while other spots stood empty.
static func _corner_spots(ctx: SimContext, team: int, spot: Vector3) -> void:
	var goal := ctx.pitch.target_goal(team)
	var dir := ctx.pitch.attack_dir(team)
	# Positive on the flag the corner is being taken from, so the first offset of
	# each list is the near post whichever side it comes from.
	var side: float = signf(spot.z) if absf(spot.z) > 1e-3 else 1.0
	var attackers := 0
	var defenders := 0
	for p in ctx.players:
		if p.team == team:
			if p.is_keeper:
				ctx.restart_spots[p.id] = ctx.pitch.own_goal(p.team) + Vector3(dir * 14.0, 0.0, 0.0)
				continue
			# Attackers fill the box; one stays out for the second ball.
			var offsets := [Vector3(-6.0, 0.0, -4.0), Vector3(-9.0, 0.0, 2.0), Vector3(-4.5, 0.0, 5.0), Vector3(-12.0, 0.0, -1.0), Vector3(-16.0, 0.0, 4.0), Vector3(-2.5, 0.0, -1.0)]
			var o: Vector3 = offsets[attackers % offsets.size()]
			attackers += 1
			ctx.restart_spots[p.id] = ctx.pitch.clamp_to_pitch(goal + Vector3(o.x * dir, 0.0, o.z * side), 0.5)
		else:
			if p.is_keeper:
				ctx.restart_spots[p.id] = ctx.pitch.own_goal(p.team) + Vector3(-dir * 1.0, 0.0, 0.0)
				continue
			# Defenders mark, spread across the six-yard area and the spot.
			var d_offsets := [Vector3(-5.0, 0.0, -3.0), Vector3(-7.5, 0.0, 1.0), Vector3(-4.0, 0.0, 4.5), Vector3(-11.0, 0.0, -2.0), Vector3(-3.0, 0.0, 0.5), Vector3(-14.0, 0.0, 3.0), Vector3(-9.0, 0.0, 6.0)]
			var d: Vector3 = d_offsets[defenders % d_offsets.size()]
			defenders += 1
			ctx.restart_spots[p.id] = ctx.pitch.clamp_to_pitch(goal + Vector3(d.x * dir, 0.0, d.z * side), 0.5)
	var taker := _nearest_of(ctx, team, spot, true)
	if taker != null:
		ctx.restart_taker = taker.id
		var stand := Vector3(-dir, 0.0, -signf(spot.z) * 0.8).normalized() * TAKER_STANCE
		ctx.restart_spots[taker.id] = spot + stand
	# The keeper of the defending side stands on the line.
	_snap_nobody(ctx)


## Teleports everyone to their restart spot. Used only for kickoffs and
## penalties, where play has genuinely stopped and walking there would waste
## simulated minutes.
static func _snap_everyone(ctx: SimContext) -> void:
	for p in ctx.players:
		if ctx.restart_spots.has(p.id):
			p.pos = ctx.restart_spots[p.id]
			p.vel = Vector3.ZERO
			var goal := ctx.pitch.target_goal(p.team)
			p.facing = atan2(goal.z - p.pos.z, goal.x - p.pos.x)


## For restarts where players jog into position rather than appearing there.
static func _snap_nobody(_ctx: SimContext) -> void:
	pass


static func _nearest_of(ctx: SimContext, team: int, point: Vector3, exclude_keeper: bool) -> SimPlayer:
	var best: SimPlayer = null
	var best_d := INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if not p.on_pitch or (exclude_keeper and p.is_keeper):
			continue
		var d := p.dist_to(point)
		if d < best_d:
			best_d = d
			best = p
	return best


static func _best_finisher(ctx: SimContext, team: int) -> SimPlayer:
	var best: SimPlayer = null
	var best_score := -INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if not p.on_pitch or p.is_keeper:
			continue
		var score: float = p.attrs.finishing + p.attrs.composure * 0.5
		if score > best_score:
			best_score = score
			best = p
	return best


# --- Ticking ----------------------------------------------------------------


## How long the ball sits before this restart may be taken.
##
## The long wait is for the restarts where both sides have somewhere to be: a
## goal kick and an own-half free kick, where the kicking side is pushing out on
## the rule in `RESTART_SHAPE_DEPTH`, and a corner or a penalty, where the box
## has to fill up. Everything else -- a throw-in, a kickoff, a free kick already
## high up the pitch -- is taken as soon as the taker reaches the ball, which is
## the difference between a quick restart and a slow one and is worth keeping.
## Floors for the compressed delays below, in ticks at 60 Hz: 0.3 s, 1.2 s, 2 s.
const MIN_DELAY_FLOOR := 18
const SETTLE_FLOOR := 72
## And the free kick near their goal, whose box men come from further. See
## `_min_delay`.
const FK_BOX_SETTLE := SimConsts.TICK_HZ * 6
const FK_BOX_FLOOR := SimConsts.TICK_HZ * 3
const MAX_WAIT_FLOOR := 120


## A restart delay under a compressed clock.
##
## Dead time is denominated in real seconds while the match budget is not, so
## compression multiplies what a restart costs as a share of the match: three
## seconds over a goal kick is a twentieth of a percent of a real ninety and a
## fiftieth of a three-minute one. Forty restarts a match at that price is most
## of the football.
##
## It does not divide all the way down, and the floors are the point. Part of
## every delay is players physically going somewhere — the kicking side pushing
## thirteen metres up the pitch on `RESTART_SHAPE_DEPTH`, the box filling for a
## corner — and no clock rate makes a body cover that ground faster. A settle
## compressed to a tenth of a second is the bug `SETTLE_DELAY` was written to
## fix, arriving from the other direction. What pays for the shorter window is
## the players being sent to their spots at a sprint instead of a jog, in
## `update`.
static func _compress(ctx: SimContext, ticks: int, floor_ticks: int) -> int:
	var rate: float = maxf(ctx.config.clock_rate, 1.0)
	return maxi(int(round(float(ticks) / rate)), mini(floor_ticks, ticks))


static func _min_delay(ctx: SimContext) -> int:
	match ctx.restart_kind:
		Kind.GOAL_KICK, Kind.PENALTY, Kind.CORNER:
			return _compress(ctx, SETTLE_DELAY, SETTLE_FLOOR)
		Kind.FREE_KICK, Kind.INDIRECT_FREE_KICK:
			var canonical := ctx.pitch.orient(ctx.restart_team, ctx.restart_pos)
			if canonical.x < -ctx.pitch.half_length * RESTART_SHAPE_DEPTH:
				return _compress(ctx, SETTLE_DELAY, SETTLE_FLOOR)
			# And a free kick near their goal, for the same reason a corner gets
			# it: the box has to fill. Nobody takes one of these in two thirds of
			# a second, and the engine did -- measured on `fk-shot`, the delivery
			# was struck at 0.68 s with the nearest of ours still 34 m from goal
			# and walking, so `_load_box` had sent four men into a box the ball
			# reached before they did. The wall going up costs the same wait
			# whether the taker ends up shooting or crossing.
			#
			# It gets a longer floor than the goal kick's, for the reason the
			# floor exists at all: the ground is different. A goal kick's push-out
			# is thirteen metres, and `_load_box` brings men from midfield -- 25 to
			# 35 of them, measured on the same row -- which no clock rate makes
			# them cover faster.
			if canonical.x > ctx.pitch.half_length - FK_DELIVERY_RANGE:
				return _compress(ctx, FK_BOX_SETTLE, FK_BOX_FLOOR)
			return _compress(ctx, MIN_DELAY, MIN_DELAY_FLOOR)
		_:
			return _compress(ctx, MIN_DELAY, MIN_DELAY_FLOOR)


static func update(ctx: SimContext) -> void:
	ctx.restart_ticks += 1
	for p in ctx.players:
		if not p.on_pitch:
			continue
		if ctx.restart_spots.has(p.id):
			# Three quarter pace is a side walking back into shape, which is what
			# a restart looks like when there is time for it. A compressed match
			# has correspondingly less, and the delays above come down with it,
			# so the same reorganisation has to be covered at a hurry instead.
			var pace: float = lerpf(0.75, 1.0, clampf((ctx.config.clock_rate - 1.0) / 9.0, 0.0, 1.0))
			p.steer_to(ctx.restart_spots[p.id], p.max_speed() * pace)
		else:
			p.desired_vel = Vector3.ZERO

	var taker: SimPlayer = null
	if ctx.restart_taker >= 0 and ctx.restart_taker < ctx.players.size():
		taker = ctx.players[ctx.restart_taker]
	if taker == null or not taker.on_pitch:
		taker = _nearest_of(ctx, ctx.restart_team, ctx.restart_pos, ctx.restart_kind != Kind.GOAL_KICK)
	if taker == null:
		ctx.in_play = true
		return
	# Restarts do not go through `SimDuel`, so this is the only thing stopping a
	# taker striking the ball from out of reach. It was a loose 1.4 m, which is
	# now visibly a stride short of the ball.
	var ready := taker.dist_to(ctx.restart_pos) <= SimConsts.CONTROL_RANGE
	if ready:
		ctx.restart_hold += 1
		if ctx.restart_kind == Kind.THROW_IN:
			# He has the ball in his hands from the moment he reaches it, and the
			# wind-up is what makes the throw read as a throw rather than as a
			# pass that happens to start at the touchline. Set here rather than at
			# the release, because at the release it is already over.
			taker.play_anim(SimConsts.Anim.THROW, float(THROW_WINDUP + 12) / float(SimConsts.TICK_HZ))
			if ctx.restart_hold < THROW_WINDUP:
				return
	if ctx.restart_ticks < _min_delay(ctx):
		return
	var waited := ctx.restart_ticks >= _compress(ctx, MAX_WAIT, MAX_WAIT_FLOOR)
	if not ready and not waited:
		return
	# A goal kick is not taken while an opponent is still in the area. He is
	# already walking out of it -- `goal_kick` put his spot outside -- so this
	# only ever holds the ball for the second or two that takes, and the timeout
	# above is still the backstop against a restart that never happens.
	if ctx.restart_kind == Kind.GOAL_KICK and not waited and not _area_is_clear(ctx):
		return
	if not ready:
		# Nobody got there. Put the taker on the ball rather than stalling.
		taker.pos = ctx.restart_pos - (ctx.restart_pos - ctx.pitch.own_goal(taker.team)).normalized() * (SimConsts.CONTROL_RANGE * 0.7)
		taker.vel = Vector3.ZERO
	_take(ctx, taker)


static func _take(ctx: SimContext, taker: SimPlayer) -> void:
	ctx.ball.reset(ctx.restart_pos)
	if ctx.restart_kind == Kind.THROW_IN:
		# It leaves his hands, not the grass. Over his own head rather than over
		# the spot, because that is where his hands are; he is standing behind the
		# line, so the ball is still behind it.
		ctx.ball.pos = Vector3(taker.pos.x, THROW_HEIGHT, taker.pos.z)
	ctx.in_play = true
	ctx.phase = SimConsts.Phase.BUILD_UP
	taker.touch_cooldown = 0.0
	# A man standing over a dead ball has set his body, and the aim error charged
	# by `SimTouch.facing_penalty` should not be reading whichever way he happened
	# to be jogging when he arrived. A throw-in taker walks out to the line facing
	# the touchline, so without this every throw is played over his own shoulder.
	# He is set looking upfield, which is what a taker does; a restart he then
	# plays backwards is still charged for it, and should be.
	var upfield := SimConsts.horizontal(ctx.pitch.target_goal(taker.team) - taker.pos)
	if upfield.length() > 1e-3:
		taker.facing = atan2(upfield.z, upfield.x)
	match ctx.restart_kind:
		Kind.KICKOFF:
			_take_kickoff(ctx, taker)
		Kind.THROW_IN:
			_take_throw(ctx, taker)
		Kind.GOAL_KICK:
			_take_goal_kick(ctx, taker)
		Kind.CORNER:
			_take_corner(ctx, taker)
		Kind.PENALTY:
			_take_penalty(ctx, taker)
		_:
			_take_free_kick(ctx, taker)
	ctx.restart_kind = -1
	ctx.restart_taker = -1
	ctx.restart_spots.clear()


static func _take_kickoff(ctx: SimContext, taker: SimPlayer) -> void:
	var mate := _pass_option(ctx, taker, 24.0, -1.0)
	ctx.log_event(SimTelemetry.Ev.KICKOFF, {"team": taker.team, "minute": ctx.minute()})
	if mate != null:
		SimTouch.ground_pass(ctx, taker, mate.pos, 3.5, mate.id)
	else:
		SimTouch.dribble(ctx, taker, ctx.pitch.target_goal(taker.team) - taker.pos, 0.4)


## How far this man can throw it.
static func throw_range(taker: SimPlayer) -> float:
	return lerpf(THROW_SHORT, THROW_LONG, taker.attrs.strength * 0.7 + taker.attrs.technique * 0.3)


## Who to throw it to.
##
## The old rule was "the nearest teammate ahead of me with the most space around
## him", and it is wrong in both halves. Nearest-with-space picks the man
## standing in an empty corner behind the play as readily as the man who has come
## to meet it, because it never asks what the ball would be worth when it got
## there; and requiring him to be forward of the taker throws away the ball back
## down the line, which is the safest throw in football and the one a side under
## pressure actually wants.
##
## So it is scored the way an open-play pass is scored, in the same units: what
## the team is worth with the ball there, times the chance of it arriving. Pitch
## control answers the second part and now counts the crowd, so a man with two
## opponents around him prices below a man with one. Retention is on the books
## through `SimDecision.possession_value`, which is what keeps the short throw
## competitive with the hopeful one up the line -- and, since that term stopped
## being flat, what stops the safe throw back down the line being free.
##
## Deliberately not softmaxed. A throw-in is taken by a man standing still with
## the game stopped and as long as he likes to look, which is the one moment in a
## match where the best option genuinely should be taken.
static func _throw_target(ctx: SimContext, taker: SimPlayer) -> SimPlayer:
	var reach := throw_range(taker)
	var best: SimPlayer = null
	var best_score := -INF
	for pid in ctx.team_players[taker.team]:
		var p := ctx.players[pid]
		if p.id == taker.id or not p.on_pitch or p.is_keeper:
			continue
		var d := p.dist_to(taker.pos)
		if d < 2.5 or d > reach:
			continue
		# A throw-in cannot be offside, but the man who is offside from it is
		# about to be in an offside position for whatever comes next, and a ball
		# thrown to him is a ball thrown away.
		var arrival := p.pos + p.vel * 0.35
		var control := ctx.value.control_at(ctx, arrival, taker.team, taker.id)
		var threat := ctx.value.xt_at(taker.team, arrival, ctx.pitch)
		# The ball is in the air and slow, and every metre of it is a metre the
		# defence has to close him down in. Longer throws are worth less than
		# their landing point says they are.
		var flight: float = 1.0 - clampf(d / reach, 0.0, 1.0) * 0.25
		var score := control * (threat + SimDecision.possession_value(ctx, taker.team, arrival)) * flight
		if score > best_score:
			best_score = score
			best = p
	return best


static func _take_throw(ctx: SimContext, taker: SimPlayer) -> void:
	var mate := _throw_target(ctx, taker)
	if mate == null:
		SimTouch.clearance(ctx, taker)
		return
	var d := taker.dist_to(mate.pos)
	# Every throw-in is a ball out of the hands and over the head, so every one of
	# them is lofted. It used to be rolled along the floor under nine metres,
	# which is not a throw-in and cannot be animated as one.
	var lead := mate.pos + mate.vel * 0.3
	SimTouch.lofted_pass(ctx, taker, lead, clampf(0.45 + d * 0.035, 0.45, 1.25), mate.id, SimTelemetry.Touch.THROW_IN)


static func _take_goal_kick(ctx: SimContext, taker: SimPlayer) -> void:
	var tactics := ctx.tactics(taker.team)
	var go_long := ctx.rng.unit_float() < clampf(0.25 + tactics.directness * 0.7, 0.0, 0.95)
	# A named routine overrides the default: "keeper plays short" is a thing the
	# player installed, so it should visibly happen and be counted.
	if SimPatterns.keeper_plays_short(ctx, taker.team) and _pass_option(ctx, taker, 26.0, 0.0) != null:
		go_long = false
		SimPatterns.note_keeper_short(ctx, taker.team)
	if go_long:
		var target := _long_ball_target(ctx, taker.team)
		var mate := ctx.nearest_to(target, taker.team, taker.id)
		SimTouch.lofted_pass(ctx, taker, target, 2.2, mate.id if mate != null else -1, SimTelemetry.Touch.LOFTED_PASS)
	else:
		var mate := _pass_option(ctx, taker, 26.0, 0.0)
		if mate == null:
			SimTouch.clearance(ctx, taker)
		else:
			SimTouch.ground_pass(ctx, taker, mate.pos, 4.0, mate.id)


static func _take_corner(ctx: SimContext, taker: SimPlayer) -> void:
	var goal := ctx.pitch.target_goal(taker.team)
	var dir := ctx.pitch.attack_dir(taker.team)
	var aim := goal + Vector3(-6.5 * dir, 2.1, ctx.rng.range_float(-3.0, 3.0))
	var mate := ctx.nearest_to(Vector3(aim.x, 0.0, aim.z), taker.team, taker.id)
	# The swing is the taker's foot, and it used to be the flag he stood at:
	# `-signf(taker.pos.z)`, which reads the same for both ends of the pitch while
	# the goal being attacked does not. One team's corners from a given corner
	# therefore swung in and the other's swung out, from the same expression.
	# `SimTouch.curl_for` asks the only question that decides it -- see
	# `docs/THE_FOOTBALL.md` 36 -- and a right-footer at the left flag whips it in.
	var curl := SimTouch.curl_for(ctx, taker, aim - ctx.ball.pos,
		SimTouch.CROSS_CURL, SimTouch.CROSS_CURL_SIGMA)
	SimTouch.lofted_pass(ctx, taker, aim, 1.35, mate.id if mate != null else -1, SimTelemetry.Touch.CROSS, curl)


static func _take_penalty(ctx: SimContext, taker: SimPlayer) -> void:
	var goal := ctx.pitch.target_goal(taker.team)
	var side: float = 1.0 if ctx.rng.chance(0.5) else -1.0
	var aim := Vector3(goal.x, ctx.rng.range_float(0.3, 1.5), side * (ctx.pitch.goal_half_width - 0.6) * ctx.rng.range_float(0.55, 0.95))
	SimTouch.shot(ctx, taker, aim, 0.72, false, 0.78)


static func _take_free_kick(ctx: SimContext, taker: SimPlayer) -> void:
	var goal := ctx.pitch.target_goal(taker.team)
	var distance := SimConsts.horizontal_length(goal - ctx.restart_pos)
	var direct_allowed := ctx.restart_kind == Kind.FREE_KICK
	if direct_allowed and distance < 30.0 and ctx.rng.chance(0.6):
		var aim := Vector3(goal.x, ctx.rng.range_float(0.6, 2.0), ctx.rng.range_float(-1.0, 1.0) * (ctx.pitch.goal_half_width - 0.5))
		SimTouch.shot(ctx, taker, aim, 0.8, false, 0.08)
		return
	if distance < 42.0:
		var aim := goal - Vector3(ctx.pitch.attack_dir(taker.team) * 9.0, -2.0, 0.0)
		var mate := ctx.nearest_to(Vector3(aim.x, 0.0, aim.z), taker.team, taker.id)
		SimTouch.lofted_pass(ctx, taker, aim, 1.5, mate.id if mate != null else -1, SimTelemetry.Touch.CROSS)
		return
	var option := _pass_option(ctx, taker, 30.0, 0.1)
	if option == null:
		SimTouch.clearance(ctx, taker)
	else:
		SimTouch.ground_pass(ctx, taker, option.pos, 4.0, option.id)


## Nearest teammate within range, optionally requiring them to be forward of the
## taker (`forwardness` > 0) or behind (`< 0`).
static func _pass_option(ctx: SimContext, taker: SimPlayer, max_range: float, forwardness: float) -> SimPlayer:
	var dir := ctx.pitch.attack_dir(taker.team)
	var best: SimPlayer = null
	var best_score := -INF
	for pid in ctx.team_players[taker.team]:
		var p := ctx.players[pid]
		if p.id == taker.id or not p.on_pitch:
			continue
		var d := p.dist_to(taker.pos)
		if d < 3.0 or d > max_range:
			continue
		var relative := (p.pos.x - taker.pos.x) * dir
		if forwardness > 0.0 and relative < 0.0:
			continue
		if forwardness < 0.0 and relative > 4.0:
			continue
		# Prefer a teammate with space.
		var opponent := ctx.nearest_opponent(p)
		var space := opponent.dist_to(p.pos) if opponent != null else 20.0
		var score: float = space - d * 0.2
		if score > best_score:
			best_score = score
			best = p
	return best


static func _long_ball_target(ctx: SimContext, team: int) -> Vector3:
	var dir := ctx.pitch.attack_dir(team)
	var best: SimPlayer = null
	var best_x := -INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if not p.on_pitch or p.is_keeper:
			continue
		if p.pos.x * dir > best_x:
			best_x = p.pos.x * dir
			best = p
	if best == null:
		return Vector3(dir * 10.0, 0.0, 0.0)
	return Vector3(best.pos.x + dir * 4.0, 0.0, best.pos.z)
