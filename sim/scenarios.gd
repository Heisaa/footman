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
