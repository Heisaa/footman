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
## a keeper committed to closing are opposite problems, a striker with a man on
## his shoulder is a third, and the channel he came through is a fourth.
## Splitting them is what lets a change say *which* of them it moved.

## The striker, and the man square with him. Slots rather than roles, so a
## scenario is reproducible: `SimSquadGen` fills the formation in slot order.
const _STRIKER := 9
const _SUPPORT := 10

## How fast the striker is running at goal when the situation starts.
const PACE := 5.5

## How fast a defender the ball has gone past is already running back. Below
## `PACE` because he has had to turn, which is the half-second the striker's
## head start is actually made of.
const RECOVERY_PACE := 4.5


static func all() -> Array[SimScenario]:
	return [
		one_v_one_clear(),
		one_v_one_onrushing(),
		one_v_one_angle(),
		one_v_one_chased(),
		cross_right(),
		cross_left(),
		cross_byline(),
		through_ball(),
		switch_play(),
		build_up(),
		pocket(),
		shot_edge(),
		volley(),
		long_range(),
		race_behind(),
		aerial_duel(),
		hold_up(),
		take_on(),
		corner_right(),
		corner_left(),
		free_kick_shot(),
		free_kick_wide(),
		penalty(),
		throw_final_third(),
		goal_kick(),
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


## The plain version: through on goal, a keeper set on his line, nobody chasing.
##
## This is the one the engine should be best at and the one an eye judges most
## harshly, because everybody watching knows what a striker is supposed to do
## with it.
static func one_v_one_clear() -> SimScenario:
	return _one_v_one("1v1-clear", "clean through the middle, keeper on his line",
		30.0, 0.0, 1.0, 60.0, 6.0)


## The keeper has committed and is closing the space down. The chip and going
## round him are the football answers, and both are built acts
## (`SimDecision._add_chip`, `_round_the_keeper`).
static func one_v_one_onrushing() -> SimScenario:
	return _one_v_one("1v1-onrushing", "through, and the keeper has left his line",
		26.0, -6.0, 11.0, 60.0, 5.0)


## The same ball into the right channel, where the goal is a narrow target by the
## time he arrives and the ball across is a real option.
static func one_v_one_angle() -> SimScenario:
	return _one_v_one("1v1-angle", "in behind down the right channel, support coming inside",
		24.0, 17.0, 2.0, 60.0, 4.0)


## A defender recovered onto his shoulder, which is what most of them actually
## are.
static func one_v_one_chased() -> SimScenario:
	return _one_v_one("1v1-chased", "away down the left with a defender on his shoulder",
		32.0, -14.0, 1.0, 2.5, 7.0)


## `from_goal` and `across` place the striker, `keeper_out` puts the keeper off
## his line, `trail` is the gap to the nearest recovering defender -- a large
## number meaning nobody is near enough to matter -- and `line_gap` is how far
## behind him the defensive line was left.
##
## **He starts a long way out on purpose** (owner, 2026-08-23). The first version
## of these put him fourteen metres from goal with the shape settled around him,
## which meant the whole defence was already goal-side and the situation was a
## penalty with a run-up: nothing was decided in it except where he put his
## shot. A one-on-one is a man who has *just* gone through, with the ground
## between him and the keeper still to be covered and men coming back at him,
## and that is what `from_goal` and `line_gap` together make.
static func _one_v_one(name: String, title: String, from_goal: float, across: float,
		keeper_out: float, trail: float, line_gap: float) -> SimScenario:
	var s := SimScenario.new()
	s.name = name
	s.title = title
	# Long enough to cover the ground. He has twenty-odd metres to run before
	# there is anything to decide, and a clock that stopped before he got there
	# would be measuring its own length.
	s.seconds = 7.0
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

		# The ball is played through the line rather than the striker being
		# dropped behind it, so the defence starts *higher up the pitch than he
		# is* and has to turn and chase. Everyone deeper than the line is pulled
		# up to it, which leaves nobody between him and the keeper -- the
		# difference between a man in behind and a man running at a back four.
		_raise_line(ctx, SimConsts.other_team(team), at.x - dir * line_gap, dir)

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

		# A man coming inside off the far side for the ball across, and the
		# nearest defender put on his shoulder or left in the recovering line.
		var mate := ctx.players[_SUPPORT]
		mate.pos = Vector3(at.x - dir * 6.0, 0.0, at.z + (12.0 if across <= 0.0 else -12.0))
		mate.vel = Vector3(dir * 4.0, 0.0, 0.0)
		var chaser := _nearest_outfielder(ctx, SimConsts.other_team(team), at)
		if chaser != null and trail < 30.0:
			chaser.pos = at - Vector3(dir * trail, 0.0, 0.6)
			chaser.vel = Vector3(dir * PACE, 0.0, 0.0)

		ctx.update_possession()
	return s


## Pulls every outfielder of `team` who is deeper than `line_x` up onto it, and
## turns them for their own goal.
##
## Only the deep ones move: a midfielder already ahead of the line is a man who
## did not need to be part of this, and dragging him back would be authoring a
## shape instead of describing a moment. The z of each is left alone, so the
## line keeps the spacing the side's own shape gave it.
static func _raise_line(ctx: SimContext, team: int, line_x: float, attack_dir: float) -> void:
	for p in ctx.players:
		if p.team != team or p.is_keeper:
			continue
		if p.pos.x * attack_dir <= line_x * attack_dir:
			continue
		p.pos.x = line_x
		# Already turned and running back, which is what makes the chase a race
		# rather than a standing start.
		p.vel = Vector3(attack_dir * RECOVERY_PACE, 0.0, 0.0)
		p.facing = 0.0 if attack_dir > 0.0 else PI


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

# --- Shared placement helpers ----------------------------------------------


## The boilerplate every scenario below repeats, in one place.
static func _make(name: String, title: String, seconds: float, place: Callable) -> SimScenario:
	var s := SimScenario.new()
	s.name = name
	s.title = title
	s.seconds = seconds
	s.attacking_team = SimConsts.TEAM_HOME
	s.place = place
	return s


## Players of a role, in slot order.
##
## Asked by role rather than by slot because the formation is not fixed: slot 10
## is a second striker in a 4-4-2 and a winger in a 4-3-3, and a scenario that
## meant "the striker" would be describing a different situation on every seed.
static func _of_role(ctx: SimContext, team: int, role: int) -> Array:
	var out := []
	for p in ctx.players:
		if p.team == team and p.role == role:
			out.append(p)
	return out


## One player of the first role in `roles` that the side actually has, `idx`-th
## in slot order. Falls back through the list, then to the man whose formation
## home is furthest forward, so no scenario can end up with a null.
static func _one(ctx: SimContext, team: int, roles: Array, idx := 0) -> SimPlayer:
	for role in roles:
		var found := _of_role(ctx, team, role)
		if found.size() > idx:
			return found[idx]
		if not found.is_empty():
			return found[found.size() - 1]
	return _furthest_forward(ctx, team)


## The outfielder whose formation home is highest up the pitch.
static func _furthest_forward(ctx: SimContext, team: int) -> SimPlayer:
	var best: SimPlayer = null
	var best_x := -INF
	var dir := ctx.pitch.attack_dir(team)
	for p in ctx.players:
		if p.team != team or p.is_keeper:
			continue
		var home: float = ctx.teams[team].formation.home_for(p.slot, ctx.pitch, team).x * dir
		if home > best_x:
			best_x = home
			best = p
	return best


## The defending side's back line, flattened onto `line_x`.
##
## `running` turns them for their own goal at `RECOVERY_PACE`, which is a line
## the ball has gone past; without it they are simply standing higher, which is a
## line that has not been broken yet.
static func _flatten_line(ctx: SimContext, team: int, line_x: float, attack_dir: float,
		running: bool) -> void:
	for p in ctx.players:
		if p.team != team or p.is_keeper:
			continue
		if p.pos.x * attack_dir <= line_x * attack_dir:
			continue
		p.pos.x = line_x
		if running:
			p.vel = Vector3(attack_dir * RECOVERY_PACE, 0.0, 0.0)
			p.facing = 0.0 if attack_dir > 0.0 else PI


## Puts the ball in the air on its way somewhere, keeping whose it is.
##
## `settle` has already handed it to a man; this only changes where it is and
## what it is doing, so the situation is "his ball, in flight" rather than a
## loose ball nobody struck.
static func _put_in_flight(ctx: SimContext, at: Vector3, vel: Vector3) -> void:
	ctx.ball.pos = at
	ctx.ball.vel = vel
	ctx.ball.grounded = at.y <= SimConsts.BALL_RADIUS + 1e-3


## Turns a player to face a point.
static func _face(p: SimPlayer, at: Vector3) -> void:
	var to := SimConsts.horizontal(at - p.pos)
	if to.length() > 1e-3:
		p.facing = atan2(to.z, to.x)


# --- The pass ---------------------------------------------------------------


## A midfielder on the ball at the top of his own half, forwards ahead of him,
## and a flat back line with grass behind it.
##
## The question is whether the ball in behind is ever *generated*, which
## `./run.sh behind` answers in a set geometry without ticking the clock and
## `docs/THE_FOOTBALL.md` 33 says has been the hole twice. Here the same ball has
## to survive a real defence and a real runner.
static func through_ball() -> SimScenario:
	return _make("through-ball", "midfielder on the ball, forwards ahead, a line to play past", 7.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3(6.0 * dir, 0.0, -4.0)
			var passer := _one(ctx, team, [SimRole.CM, SimRole.DM, SimRole.AM])
			sc.settle(ctx, at + Vector3(dir * 0.6, 0.0, 0.0), passer)
			passer.pos = at
			_face(passer, ctx.pitch.target_goal(team))
			# The line at twenty-two metres from their goal, standing rather than
			# recovering: it has not been broken, and whether it can be is the
			# question.
			_flatten_line(ctx, SimConsts.other_team(team), (ctx.pitch.half_length - 24.0) * dir,
				dir, false)
			# Two forwards on the shoulder of it, moving.
			var forwards := _of_role(ctx, team, SimRole.ST) + _of_role(ctx, team, SimRole.WIDE)
			var lane := -14.0
			for f in forwards.slice(0, 2):
				f.pos = Vector3((ctx.pitch.half_length - 25.5) * dir, 0.0, lane)
				f.vel = Vector3(dir * 4.0, 0.0, 0.0)
				_face(f, ctx.pitch.target_goal(team))
				lane += 20.0
			ctx.update_possession())


## The ball held on one flank with the whole shape shifted onto it, and a free
## man on the other.
##
## A side that never switches plays in one third of the pitch, which is
## `docs/THE_FOOTBALL.md` 30's picture from the other side.
static func switch_play() -> SimScenario:
	return _make("switch", "ball held on the left, the right wide man free", 7.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3(14.0 * dir, 0.0, -25.0)
			var holder := _widest(ctx, team, -25.0, at)
			sc.settle(ctx, at + Vector3(dir * 0.6, 0.0, 0.0), holder)
			holder.pos = at
			_face(holder, ctx.pitch.target_goal(team))
			# The far winger held wide and high, where a switch would find him.
			var far := _widest(ctx, team, 25.0, at)
			if far != holder:
				far.pos = Vector3(24.0 * dir, 0.0, 28.0)
				_face(far, ctx.pitch.target_goal(team))
			ctx.update_possession())


## A centre-back on the ball in his own third with the opposition front line
## twelve metres away.
##
## `none` is the good outcome here and `lost` the bad one, which is the one row
## in this table where that is true. It is worth the exception: playing out is
## the commonest thing a defence does with the ball and nothing else here asks
## whether the engine can do it.
static func build_up() -> SimScenario:
	return _make("build-up", "centre-back on it in his own third, pressed", 7.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((-ctx.pitch.half_length + 22.0) * dir, 0.0, -7.0)
			var cb := _one(ctx, team, [SimRole.CB])
			sc.settle(ctx, at + Vector3(dir * 0.6, 0.0, 0.0), cb)
			cb.pos = at
			_face(cb, ctx.pitch.target_goal(team))
			# Their front line twelve metres off him and closing.
			var pressers := _of_role(ctx, SimConsts.other_team(team), SimRole.ST) \
				+ _of_role(ctx, SimConsts.other_team(team), SimRole.WIDE)
			var lane := -10.0
			for q in pressers.slice(0, 3):
				q.pos = at + Vector3(dir * 12.0, 0.0, lane)
				q.vel = Vector3(-dir * 4.0, 0.0, 0.0)
				_face(q, at)
				lane += 10.0
			ctx.update_possession())


## A midfielder receiving between the lines with his back to goal and a man on
## him.
##
## The pocket is built (`SimOffBall._pocket_point`); what is untested is what
## happens to a man who gets there. Turning is `SimTouch.first_touch` and the
## half-turn is `SimMovement._orient_receiver`, and neither has ever been watched
## in the one situation they exist for.
static func pocket() -> SimScenario:
	return _make("pocket", "receiving between the lines, back to goal, marked", 6.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 32.0) * dir, 0.0, 3.0)
			var man := _one(ctx, team, [SimRole.AM, SimRole.CM])
			sc.settle(ctx, at + Vector3(-dir * 0.6, 0.0, 0.0), man)
			man.pos = at
			# Back to goal: facing his own keeper, which is how the ball arrives.
			_face(man, ctx.pitch.own_goal(team))
			var marker := _nearest_outfielder(ctx, SimConsts.other_team(team), at)
			if marker != null:
				marker.pos = at + Vector3(dir * 1.6, 0.0, 0.4)
				_face(marker, at)
			ctx.update_possession())


# --- The shot ---------------------------------------------------------------


## The ball at the top of the box with bodies between it and the goal.
##
## A shot from here is a real football option and so is the ball wide; what this
## row is for is the third case, the man who does neither because the lane is
## blocked and there is nothing else priced.
static func shot_edge() -> SimScenario:
	return _make("shot-edge", "at the top of the box, bodies in front", 5.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 19.0) * dir, 0.0, -2.0)
			var man := _one(ctx, team, [SimRole.CM, SimRole.AM])
			sc.settle(ctx, at + Vector3(dir * 0.5, 0.0, 0.0), man)
			man.pos = at
			_face(man, ctx.pitch.target_goal(team))
			# Two of theirs across the lane, four metres off him.
			var block := _of_role(ctx, SimConsts.other_team(team), SimRole.CB)
			var lane := -2.5
			for q in block.slice(0, 2):
				q.pos = at + Vector3(dir * 4.0, 0.0, lane)
				_face(q, at)
				lane += 5.0
			ctx.update_possession())


## A ball dropping to a striker inside the box, off a teammate.
##
## The volley is built (`SimTouch.VOLLEY_FULL`) and has never been watched. The
## ball is put in flight rather than crossed so the row is about the strike and
## not about the delivery, which `cross-*` already asks.
static func volley() -> SimScenario:
	return _make("volley", "a ball dropping to him in the box", 5.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 12.0) * dir, 0.0, 2.0)
			var st := _one(ctx, team, [SimRole.ST])
			var from := at + Vector3(-dir * 14.0, 0.0, -16.0)
			sc.settle(ctx, from, _widest(ctx, team, -16.0, from))
			st.pos = at
			_face(st, ctx.pitch.target_goal(team))
			# Dropping onto his boot rather than his head: at six metres up it
			# arrived at heading height every time and `SimTouch.VOLLEY_FULL` was
			# never once exercised in twenty-five situations.
			_put_in_flight(ctx, at + Vector3(-dir * 4.0, 1.9, -4.5),
				Vector3(dir * 4.0, -1.6, 4.5))
			ctx.update_possession())


## Twenty-eight metres out, square on, with the space in front of him to hit it.
##
## Whether the engine ever strikes one from range at all. `shot_appetite` is part
## of what decides it and is fitted to the compressed clock, so a zero here is a
## fact about the format as much as about the striker.
static func long_range() -> SimScenario:
	return _make("long-range", "twenty-eight metres, square on, space in front", 6.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 28.0) * dir, 0.0, 0.0)
			var man := _one(ctx, team, [SimRole.CM, SimRole.AM])
			sc.settle(ctx, at + Vector3(dir * 0.6, 0.0, 0.0), man)
			man.pos = at
			_face(man, ctx.pitch.target_goal(team))
			# Their line dropped off him, which is what leaves the shot on.
			_flatten_line(ctx, SimConsts.other_team(team), (ctx.pitch.half_length - 16.0) * dir,
				dir, false)
			ctx.update_possession())


# --- The duel ---------------------------------------------------------------


## The ball knocked in behind and two men running at it, level.
##
## Pace, the turn and `SimDuel` decide this and nothing else does. It is the
## cleanest test on this page of whether a foot race looks like a foot race.
static func race_behind() -> SimScenario:
	return _make("race", "a ball knocked in behind, striker and defender level", 6.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 30.0) * dir, 0.0, 6.0)
			var passer := _one(ctx, team, [SimRole.CM, SimRole.DM])
			sc.settle(ctx, at + Vector3(-dir * 12.0, 0.0, 0.0), passer)
			# Nobody of theirs ahead of the ball. Measured before this line: the
			# nearest defender to a ball knocked in behind was a defensive
			# midfielder the shape had left standing in its path, and the race
			# the row is named for was decided by a third man at 1.5 m/s.
			_flatten_line(ctx, SimConsts.other_team(team), at.x - dir * 5.0, dir, true)
			var st := _one(ctx, team, [SimRole.ST])
			st.pos = at + Vector3(-dir * 4.0, 0.0, 1.2)
			st.vel = Vector3(dir * PACE, 0.0, 0.0)
			_face(st, ctx.pitch.target_goal(team))
			var cb := _one(ctx, SimConsts.other_team(team), [SimRole.CB])
			cb.pos = at + Vector3(-dir * 4.0, 0.0, -1.2)
			cb.vel = Vector3(dir * PACE, 0.0, 0.0)
			_face(cb, ctx.pitch.target_goal(team))
			# The ball already running away from both of them.
			_put_in_flight(ctx, Vector3(at.x, SimConsts.BALL_RADIUS, at.z),
				Vector3(dir * 9.0, 0.0, 0.0))
			ctx.update_possession())


## A long ball dropping between a striker and a centre-back.
##
## The aerial duel, the header and the knock-down all exist; 22 headers in a
## match produced none at goal (**29**), and this is where that is watchable.
static func aerial_duel() -> SimScenario:
	return _make("aerial", "a long ball dropping between striker and centre-back", 6.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 28.0) * dir, 0.0, -3.0)
			var passer := _one(ctx, team, [SimRole.CB, SimRole.DM])
			sc.settle(ctx, at + Vector3(-dir * 30.0, 0.0, 0.0), passer)
			var st := _one(ctx, team, [SimRole.ST])
			st.pos = at + Vector3(-dir * 1.2, 0.0, 0.8)
			_face(st, ctx.pitch.target_goal(team))
			var cb := _one(ctx, SimConsts.other_team(team), [SimRole.CB])
			cb.pos = at + Vector3(dir * 1.2, 0.0, -0.8)
			_face(cb, at)
			# Coming down on the two of them from a long ball's height.
			_put_in_flight(ctx, at + Vector3(-dir * 8.0, 9.0, 0.0),
				Vector3(dir * 8.0, -5.0, 0.0))
			ctx.update_possession())


## A striker with his back to goal, a centre-back tight, and midfield arriving.
##
## Shielding is built and `_play_hold` sets it. What has never been looked at is
## whether the ball can be *held* until help arrives, which is the whole point of
## the act.
static func hold_up() -> SimScenario:
	return _make("hold-up", "back to goal, marked tight, runners coming from deep", 6.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 28.0) * dir, 0.0, 0.0)
			var st := _one(ctx, team, [SimRole.ST])
			sc.settle(ctx, at + Vector3(-dir * 0.6, 0.0, 0.0), st)
			st.pos = at
			_face(st, ctx.pitch.own_goal(team))
			var cb := _one(ctx, SimConsts.other_team(team), [SimRole.CB])
			cb.pos = at + Vector3(dir * 1.3, 0.0, 0.3)
			_face(cb, at)
			# Two coming through from midfield.
			var lane := -8.0
			for mid in (_of_role(ctx, team, SimRole.CM) + _of_role(ctx, team, SimRole.AM)).slice(0, 2):
				mid.pos = at + Vector3(-dir * 14.0, 0.0, lane)
				mid.vel = Vector3(dir * 4.5, 0.0, 0.0)
				_face(mid, ctx.pitch.target_goal(team))
				lane += 16.0
			ctx.update_possession())


## A wide man facing a full-back in the final third, one against one, with the
## touchline on one side and the box on the other.
##
## `_try_beat` exists and the last line of the watching list says a carrier
## running into a defender is the softmax declining it. This row is where that
## claim can be checked rather than repeated.
static func take_on() -> SimScenario:
	return _make("take-on", "wide man against the full-back, final third", 6.0,
		func(sc: SimScenario, ctx: SimContext) -> void:
			var team := sc.attacking_team
			var dir := ctx.pitch.attack_dir(team)
			var at := Vector3((ctx.pitch.half_length - 26.0) * dir, 0.0, 24.0)
			var w := _widest(ctx, team, 24.0, at)
			sc.settle(ctx, at + Vector3(dir * 0.6, 0.0, 0.0), w)
			w.pos = at
			# Running, and the figure is not free: `SimDecision.BURST_PACE` is
			# 3.5, below which the engine holds that knocking it past a man is
			# not a foot race but a giveaway. Set at 3.0 the row sat under that
			# gate, so the take-on was never a candidate and `take-on` was
			# measuring its own placement rather than the act it is named for --
			# the third of these to do it. A winger receiving in the final third
			# with a full-back in front of him is running.
			w.vel = Vector3(dir * 5.0, 0.0, 0.0)
			_face(w, ctx.pitch.target_goal(team))
			var fb := _one(ctx, SimConsts.other_team(team), [SimRole.FB])
			if fb != null:
				fb.pos = at + Vector3(dir * 2.2, 0.0, 0.8)
				_face(fb, at)
			ctx.update_possession())


# --- The restarts -----------------------------------------------------------


## Every set piece is the engine's own routine, started rather than authored:
## `SimSetPiece` positions the two sides, waits, and takes it. A scenario that
## placed the bodies itself would be measuring a corner nobody plays.
##
## They get twelve seconds because a restart is a delay and then a situation.
## `SimSetPiece.MAX_WAIT` is eight seconds before a taker is teleported onto the
## ball, compressed by the clock rate, and a scenario shorter than that would be
## scoring the wait.
static func corner_right() -> SimScenario:
	return _restart("corner-right", "a corner from the right",
		func(ctx: SimContext, team: int) -> Vector3:
			return _corner_spot(ctx, team, 1.0),
		func(ctx: SimContext, team: int) -> void:
			SimSetPiece.corner(ctx, team, 1.0))


static func corner_left() -> SimScenario:
	return _restart("corner-left", "the same corner from the left",
		func(ctx: SimContext, team: int) -> Vector3:
			return _corner_spot(ctx, team, -1.0),
		func(ctx: SimContext, team: int) -> void:
			SimSetPiece.corner(ctx, team, -1.0))


static func _corner_spot(ctx: SimContext, team: int, side: float) -> Vector3:
	var goal := ctx.pitch.target_goal(team)
	return Vector3(goal.x - signf(goal.x) * 0.3, 0.0, side * (ctx.pitch.half_width - 0.3))


## Twenty-one metres out and central, which is a shot.
static func free_kick_shot() -> SimScenario:
	return _restart("fk-shot", "free kick, twenty-one metres, central",
		func(ctx: SimContext, team: int) -> Vector3:
			return Vector3((ctx.pitch.half_length - 21.0) * ctx.pitch.attack_dir(team), 0.0, -1.0),
		func(ctx: SimContext, team: int) -> void:
			SimSetPiece.free_kick(ctx, team,
				Vector3((ctx.pitch.half_length - 21.0) * ctx.pitch.attack_dir(team), 0.0, -1.0), false))


## Wide and deep enough that the ball into the box is the act, not the shot.
static func free_kick_wide() -> SimScenario:
	return _restart("fk-wide", "free kick wide, a ball into the box",
		func(ctx: SimContext, team: int) -> Vector3:
			return Vector3((ctx.pitch.half_length - 30.0) * ctx.pitch.attack_dir(team), 0.0, 24.0),
		func(ctx: SimContext, team: int) -> void:
			SimSetPiece.free_kick(ctx, team,
				Vector3((ctx.pitch.half_length - 30.0) * ctx.pitch.attack_dir(team), 0.0, 24.0), false))


static func penalty() -> SimScenario:
	return _restart("penalty", "a penalty",
		func(ctx: SimContext, team: int) -> Vector3:
			return ctx.pitch.penalty_spot(team),
		func(ctx: SimContext, team: int) -> void:
			SimSetPiece.penalty(ctx, team))


## A throw in the final third, which is the one restart the engine takes most of.
static func throw_final_third() -> SimScenario:
	return _restart("throw-in", "a throw-in in the final third",
		func(ctx: SimContext, team: int) -> Vector3:
			return Vector3((ctx.pitch.half_length - 24.0) * ctx.pitch.attack_dir(team), 0.0,
				ctx.pitch.half_width),
		func(ctx: SimContext, team: int) -> void:
			SimSetPiece.throw_in(ctx, team,
				Vector3((ctx.pitch.half_length - 24.0) * ctx.pitch.attack_dir(team), 0.0,
					ctx.pitch.half_width)))


## Playing out from the back. `none` is the good outcome, as in `build-up`.
static func goal_kick() -> SimScenario:
	return _restart("goal-kick", "a goal kick, played out",
		func(ctx: SimContext, team: int) -> Vector3:
			return ctx.pitch.own_goal(team) + Vector3(-signf(ctx.pitch.own_goal(team).x) * 5.5, 0.0, 0.0),
		func(ctx: SimContext, team: int) -> void:
			SimSetPiece.goal_kick(ctx, team))


## The shared body of a restart scenario: settle the shape, then hand the whole
## situation to `SimSetPiece`, which overwrites the state with its own.
## `about` is where the restart will be taken from, and both sides are settled
## around it before the routine starts.
##
## The point matters more than it looks. Settled around the middle of the
## attacking third instead, a throw-in on the touchline had no teammate inside
## `SimSetPiece.throw_range` of the taker, `_throw_target` returned null, and
## nine throws in ten came out as `SimTouch.clearance` -- the row was measuring
## its own bad placement. Settled around the spot, the side is standing where it
## would be standing, and the routine walks it the rest of the way.
static func _restart(name: String, title: String, about: Callable, begin: Callable) -> SimScenario:
	return _make(name, title, 12.0, func(sc: SimScenario, ctx: SimContext) -> void:
		var team := sc.attacking_team
		sc.settle(ctx, about.call(ctx, team), _furthest_forward(ctx, team))
		begin.call(ctx, team)
		ctx.update_possession())
