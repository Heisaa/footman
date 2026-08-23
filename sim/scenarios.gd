class_name SimScenarios
extends RefCounted
## The library of named situations. See `SimScenario` for what one is and why.
##
## Every entry here is a situation the owner can name from the stand, because
## that is the whole point: a row in the table and a thing on screen have to be
## the same thing or the two halves cannot argue. Add one when there is a
## question about a moment that a whole match answers too slowly.
##
## **The one-on-one first** (owner, 2026-08-23). It is four variants rather than
## one because "one-on-one" is not one situation -- a keeper set on his line and
## a keeper committed to closing are opposite problems, and a striker with a man
## on his shoulder is a third. Splitting them is what lets a change say *which*
## of them it moved.

## The striker, and the man square with him. Slots rather than roles, so a
## scenario is reproducible: `SimSquadGen` fills the formation in slot order.
const _STRIKER := 9
const _SUPPORT := 10

## How fast the striker is running at goal when the situation starts.
const PACE := 5.5


static func all() -> Array[SimScenario]:
	return [
		one_v_one_clear(),
		one_v_one_onrushing(),
		one_v_one_angle(),
		one_v_one_chased(),
		cross_right(),
		cross_left(),
		cross_byline(),
	]


static func by_name(name: String) -> SimScenario:
	for s in all():
		if s.name == name:
			return s
	return null


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in all():
		out.append(s.name)
	return out


# --- The one-on-one ---------------------------------------------------------


## The plain version: through on goal, a keeper set on his line, nobody near.
##
## This is the one the engine should be best at and the one an eye judges most
## harshly, because everybody watching knows what a striker is supposed to do
## with it.
static func one_v_one_clear() -> SimScenario:
	return _one_v_one("1v1-clear", "through on goal, keeper on his line, nobody chasing",
		14.0, 0.0, 1.0, 60.0)


## The keeper has committed and is closing the space down. The chip and going
## round him are the football answers, and both are built acts
## (`SimDecision._add_chip`, `_round_the_keeper`).
static func one_v_one_onrushing() -> SimScenario:
	return _one_v_one("1v1-onrushing", "keeper has left his line and is closing",
		15.0, 0.0, 8.0, 60.0)


## The same ball from a angle wide of the post, where the goal is a narrow
## target and the square ball is a real option.
static func one_v_one_angle() -> SimScenario:
	return _one_v_one("1v1-angle", "in on goal from a tight angle, support arriving square",
		13.0, 12.0, 2.0, 60.0)


## A defender on his shoulder, which is what most of them actually are.
static func one_v_one_chased() -> SimScenario:
	return _one_v_one("1v1-chased", "through on goal with a defender on his shoulder",
		15.0, 0.0, 1.0, 2.5)


## `from_goal` and `across` place the striker, `keeper_out` puts the keeper off
## his line, and `trail` is the gap to the nearest recovering defender -- a large
## number meaning nobody is near enough to matter.
static func _one_v_one(name: String, title: String, from_goal: float, across: float,
		keeper_out: float, trail: float) -> SimScenario:
	var s := SimScenario.new()
	s.name = name
	s.title = title
	s.seconds = 5.0
	s.attacking_team = SimConsts.TEAM_HOME
	s.place = func(sc: SimScenario, ctx: SimContext) -> void:
		var team := sc.attacking_team
		var dir := ctx.pitch.attack_dir(team)
		var striker := ctx.players[_STRIKER]
		var at := Vector3(ctx.pitch.half_length * dir - dir * from_goal, 0.0, across)

		# The whole side stands where its own shape says it should for a ball
		# there, and then the handful this scenario is about are moved.
		sc.settle(ctx, at + Vector3(dir * 0.8, 0.0, 0.0), striker)

		striker.pos = at
		striker.vel = Vector3(dir * PACE, 0.0, 0.0)
		var to_goal := SimConsts.horizontal(ctx.pitch.target_goal(team) - at)
		striker.facing = atan2(to_goal.z, to_goal.x)

		# The defending keeper, off his line by `keeper_out` along the line from
		# the goal to the ball, which is where a keeper closing one down is.
		var keeper := _keeper_of(ctx, SimConsts.other_team(team))
		if keeper != null:
			var goal := ctx.pitch.target_goal(team)
			var out := SimConsts.horizontal(at - goal)
			if out.length() > 1e-3:
				keeper.pos = goal + out.normalized() * keeper_out
			else:
				keeper.pos = goal + Vector3(-dir * keeper_out, 0.0, 0.0)

		# A man square with him for the ball across, and the nearest defender
		# put on his shoulder or left where the shape had him.
		var mate := ctx.players[_SUPPORT]
		mate.pos = Vector3(at.x - dir * 1.0, 0.0, at.z + (10.0 if across <= 0.0 else -10.0))
		var chaser := _nearest_outfielder(ctx, SimConsts.other_team(team), at)
		if chaser != null and trail < 30.0:
			chaser.pos = at - Vector3(dir * trail, 0.0, 0.6)
			chaser.vel = Vector3(dir * PACE, 0.0, 0.0)

		ctx.update_possession()
	return s


static func _keeper_of(ctx: SimContext, team: int) -> SimPlayer:
	for p in ctx.players:
		if p.team == team and p.is_keeper:
			return p
	return null


static func _nearest_outfielder(ctx: SimContext, team: int, to: Vector3) -> SimPlayer:
	var best: SimPlayer = null
	var best_d := INF
	for p in ctx.players:
		if p.team != team or p.is_keeper:
			continue
		var d := p.dist_to(to)
		if d < best_d:
			best_d = d
			best = p
	return best

# --- The cross into the box -------------------------------------------------


## A wide man in the final third with the ball up, and nobody in the box yet.
##
## The box is deliberately *empty at the start*. Placing three men on the penalty
## spot would measure the delivery and nothing else, and the delivery is the half
## that already works: `docs/THE_FOOTBALL.md` 29 found the ball arriving at the
## right height for a box that had 0.00 of ours within three metres of it. The
## question this scenario is for is the whole chain -- does he cross, do the runs
## get made, is anybody there when it comes down -- so the runners have to be the
## engine's own.
##
## That is also why it gets seven seconds where the one-on-one gets five. A man
## has to cover thirty metres to attack a cross, and a scenario that ends before
## he can is measuring its own clock.
##
## **The two flanks are separate rows because they are no longer the same
## situation.** Since footedness landed (35, 36), a right-footed man wide right
## is crossing off his stronger foot and bending it away from the keeper, and the
## same man wide left is either wrapping his weaker foot round it or whipping it
## in off his right. If those two rows read alike, either the draw is not putting
## left-footers on the left or the foot is not reaching the cross.
static func cross_right() -> SimScenario:
	return _cross("cross-right", "wide on the right in the final third, box to be attacked",
		30.0, 26.0)


static func cross_left() -> SimScenario:
	return _cross("cross-left", "the same ball from the left, which is a different foot",
		30.0, -26.0)


## From the byline, where the cut-back is the football answer and the ball across
## the face is the other one.
static func cross_byline() -> SimScenario:
	return _cross("cross-byline", "to the byline, where the pull-back is on",
		46.0, 20.0)


## `along` is how far up the pitch the crosser stands, `across` how wide. Both
## have to clear `SimDecision._add_crosses`'s own gate -- past a third of the
## pitch and outside 45% of the half-width -- or the act is never a candidate and
## the row would be measuring a mechanic that cannot fire.
static func _cross(name: String, title: String, along: float, across: float) -> SimScenario:
	var s := SimScenario.new()
	s.name = name
	s.title = title
	s.seconds = 7.0
	s.attacking_team = SimConsts.TEAM_HOME
	s.place = func(sc: SimScenario, ctx: SimContext) -> void:
		var team := sc.attacking_team
		var dir := ctx.pitch.attack_dir(team)
		var at := Vector3(along * dir, 0.0, across)
		var ball_at := at + Vector3(dir * 0.6, 0.0, 0.0)
		# The widest man on that flank takes it, which is who would have it.
		var crosser := _widest(ctx, team, across, ball_at)
		sc.settle(ctx, ball_at, crosser)
		crosser.pos = at
		crosser.vel = Vector3(dir * 3.0, 0.0, 0.0)
		var up := SimConsts.horizontal(ctx.pitch.target_goal(team) - at)
		crosser.facing = atan2(up.z, up.x)
		ctx.update_possession()
	return s


## The outfielder whose shape station is furthest over on the given flank, for a
## ball at `ball_at`.
##
## Asked of `shape_position` and not of `p.pos`, because at the moment this runs
## nobody has been placed yet -- the side is still standing in the kick-off the
## scenario is replacing, where the flanks mean nothing. This is the same
## function `settle` is about to put everyone on, so the man it names is the man
## who would have been there.
static func _widest(ctx: SimContext, team: int, across: float, ball_at: Vector3) -> SimPlayer:
	var best: SimPlayer = null
	var best_z := -INF
	var side := signf(across)
	for p in ctx.players:
		if p.team != team or p.is_keeper:
			continue
		var z: float = SimMovement.shape_position(ctx, p, ball_at).z * side
		if z > best_z:
			best_z = z
			best = p
	return best
