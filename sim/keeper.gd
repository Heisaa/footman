class_name SimKeeper
extends RefCounted
## Goalkeeper positioning and shot response (PLAN.md §3.4).
##
## Special-cased, but physically resolved rather than dice-rolled. Fingertip
## saves, tip-arounds and beaten-but-recovering keepers come out of the reach
## envelope and the reaction time, not from authored outcomes.

## Reaction time distribution, in seconds.
const REACTION_MEAN := 0.20
const REACTION_SD := 0.04
## How far a keeper can reach from a standing start, and after a full dive.
const REACH_STANDING := 1.35
const REACH_DIVING := 3.4
## Time a full dive takes to extend.
const DIVE_TIME := 0.55
## Distance from the line the keeper holds, per metre of ball distance.
const DEPTH_PER_METRE := 0.17
const DEPTH_MAX := 13.0
## Range at which a keeper can gather a slow ball inside their own area.
const GATHER_RANGE := 1.45
## How fast a held ball is drawn in to the keeper's hands, in metres per second.
## A ball caught at full stretch is a body's length away from his chest, and
## snapping it there is a teleport in front of goal — which is exactly where a
## teleport gets noticed.
const DRAW_IN_SPEED := 6.0


static func update(ctx: SimContext) -> void:
	for team in 2:
		var k: SimPlayer = ctx.teams[team].keeper()
		if k == null or not k.on_pitch:
			continue
		if _holding(ctx, k):
			_hold_and_distribute(ctx, k)
			continue
		_position(ctx, k)
		_shot_response(ctx, k)
		_try_gather(ctx, k)


## True while this keeper has the ball in hand.
static func _holding(ctx: SimContext, k: SimPlayer) -> bool:
	return ctx.ball.last_touch_player == k.id \
		and ctx.ball.last_touch_kind == SimTelemetry.Touch.KEEPER_CATCH \
		and ctx.in_play


## Where the ball sits while he has it: at his chest, in two hands.
##
## It used to be held at 0.6 m, which is the height of a ball being carried at
## arm's length by somebody's knee, and it made a caught ball look dropped. The
## whole reason a save is worth watching is the moment after it, when the ball
## stops being loose and is visibly *his*.
const HOLD_HEIGHT := 1.15
## And how far in front of him, along his facing. The hold point used to be his
## own centre line, which is inside the torso: the chest capsule is about 0.22 m
## from the axis at §9.3's proportions and the ball is 0.11 m across, so a ball
## "in his hands" was buried in his sternum with nothing of it showing. This is
## the two of them added -- the ball resting against the front of the chest,
## which is where the `KEEPER_HOLD` hands cup it.
const HOLD_REACH := 0.32
## And how long he keeps it, in seconds, from decisive to dithering. The old
## figure was one second flat for everybody, which is not a goalkeeper looking
## up, it is a goalkeeper being hurried by nobody.
const HOLD_MIN := 2.0
const HOLD_MAX := 3.6
## Where a punt is struck from, and how long before the release he drops it
## there. Both exist so a kick out of the hands reads as a kick out of the hands:
## the ball leaves the chest, falls to about knee height, and is hit.
const PUNT_HEIGHT := 0.55
const PUNT_DROP_TICKS := 15


## The ball travels with the keeper until he releases it.
##
## He decides *how* he is releasing it at the moment he gathers it rather than at
## the moment he lets go, which is the only way the action before it can be the
## right one -- a keeper who has not decided cannot wind up, and a release with
## no wind-up in front of it is a ball that leaves a standing man.
static func _hold_and_distribute(ctx: SimContext, k: SimPlayer) -> void:
	var state: Dictionary = ctx.keeper_state.get(k.id, {})
	if not state.has("release"):
		var tactics := ctx.tactics(k.team)
		var hold: float = lerpf(HOLD_MAX, HOLD_MIN, k.attrs.decisions)
		state = {
			"release": ctx.ball.last_touch_tick + int(round(hold * float(SimConsts.TICK_HZ))),
			# Whether he means to throw it. The man he throws it *to* is chosen at
			# the release, because by then everyone has moved.
			"throw": _short_option(ctx, k) != null \
				and ctx.rng.unit_float() > clampf(0.2 + tactics.directness * 0.65, 0.0, 0.95),
		}
		ctx.keeper_state[k.id] = state

	var to_release: int = int(state["release"]) - ctx.tick_index
	var throwing: bool = bool(state["throw"])
	var height := HOLD_HEIGHT
	if not throwing and to_release < PUNT_DROP_TICKS:
		# Dropping it onto his boot.
		height = lerpf(PUNT_HEIGHT, HOLD_HEIGHT, clampf(float(to_release) / float(PUNT_DROP_TICKS), 0.0, 1.0))
	var hands := Vector3(k.pos.x, height, k.pos.z) + k.heading_dir() * HOLD_REACH
	ctx.ball.pos = ctx.ball.pos.move_toward(hands, DRAW_IN_SPEED * SimConsts.DT)
	ctx.ball.vel = Vector3.ZERO
	ctx.ball.spin = Vector3.ZERO
	ctx.ball.grounded = false

	# The wind-up, for a throw only: the punt's own swing is short enough that
	# `SimTouch.apply` starting it at the strike lands in the right place.
	if throwing and to_release <= SimSetPiece.THROW_WINDUP:
		k.play_anim(SimConsts.Anim.THROW, float(SimSetPiece.THROW_WINDUP + 12) / float(SimConsts.TICK_HZ))
	elif to_release > 0:
		k.play_anim(SimConsts.Anim.KEEPER_HOLD, 0.2)

	# Carries it forward while he looks up -- but not out of his own area, which
	# is both the rule and the difference between a keeper walking to the edge of
	# the box and a keeper strolling to the halfway line with the ball under his
	# arm. The carry target is recomputed every tick from where he now is, so
	# without a limit on the *destination* it walks him upfield for as long as he
	# holds it: measured at the old one-second hold that was three metres and
	# invisible, and at a realistic hold it put him twenty-eight metres out.
	var dir := ctx.pitch.attack_dir(k.team)
	var goal_line := ctx.pitch.own_goal(k.team).x
	var edge := goal_line + dir * (ctx.pitch.penalty_depth - 1.5)
	var ahead := k.pos.x + dir * 6.0
	var carry := Vector3(ahead if (ahead - edge) * dir < 0.0 else edge, 0.0, k.pos.z * 0.5)
	k.steer_to(carry, k.max_speed() * 0.45)
	if to_release > 0:
		return
	ctx.keeper_state.erase(k.id)
	_release(ctx, k, throwing)


## Out of the hands: thrown overarm, or punted.
static func _release(ctx: SimContext, k: SimPlayer, throwing: bool) -> void:
	if throwing:
		var mate := _short_option(ctx, k)
		if mate != null:
			ctx.ball.pos = Vector3(k.pos.x, SimSetPiece.THROW_HEIGHT, k.pos.z) + k.heading_dir() * HOLD_REACH
			var d := k.dist_to(mate.pos)
			# Flat and fast. A keeper's throw is aimed at a full-back's chest, not
			# hung up for him, and it used to be rolled along the grass -- which is
			# a pass, and cannot be animated as a throw because it is not one.
			SimTouch.lofted_pass(ctx, k, mate.pos + mate.vel * 0.3, clampf(0.35 + d * 0.022, 0.35, 1.0),
				mate.id, SimTelemetry.Touch.KEEPER_THROW)
			return
	# In front of the boot, not on his axis: the same offset the hold uses, so the
	# ball is struck from where it has been sitting rather than jumping back into
	# him on the tick it leaves.
	ctx.ball.pos = Vector3(k.pos.x, PUNT_HEIGHT, k.pos.z) + k.heading_dir() * HOLD_REACH
	var target := _long_option(ctx, k)
	var punted := ctx.nearest_to(target, k.team, k.id)
	SimTouch.lofted_pass(ctx, k, target, 2.2, punted.id if punted != null else -1, SimTelemetry.Touch.LOFTED_PASS)


# --- Positioning ------------------------------------------------------------


## The arc a keeper holds when nothing in particular is happening: on the line
## between the ball and the centre of his goal, at a depth that grows with the
## ball's distance -- on his line for a close shot, sweeping high when play is
## away at the other end.
##
## Public because the restart code needs it too. A keeper used to be positioned
## for a set piece by `SimMovement.shape_position`, like an outfielder, and that
## function slides the whole formation toward the ball: at the opposition's goal
## kick it put him nearly thirty metres off his own line and walking further,
## which is a shape for a centre-half and not for a goalkeeper.
static func station(ctx: SimContext, k: SimPlayer, ball: Vector3) -> Vector3:
	var goal := ctx.pitch.own_goal(k.team)
	var to_ball := SimConsts.horizontal(ball - goal)
	var distance: float = maxf(to_ball.length(), 0.1)
	var dir := to_ball / distance
	var depth: float = clampf(0.45 + distance * DEPTH_PER_METRE, 0.45, DEPTH_MAX)
	depth *= lerpf(0.7, 1.25, k.attrs.command)
	var at := goal + dir * depth
	# Never stray outside the width of the six-yard area unless coming for a ball.
	at.z = clampf(at.z, -ctx.pitch.goal_area_half_width - 2.5, ctx.pitch.goal_area_half_width + 2.5)
	return at


## How high a keeper's hands go, standing.
##
## A head reaches 2.35 m and this is the difference between claiming a cross and
## watching one drop over the top of everybody. It is the one advantage he has in
## a crowded six-yard box, and until it existed a ball hung up in his own area was
## somebody else's ball.
const CLAIM_HEIGHT := 2.8
## How far from him he can claim it, horizontally. A step and two hands, which
## goes further than a boot: `GATHER_RANGE` is a keeper picking a ball up off the
## floor and this is one coming to take it out of the air.
const CLAIM_RANGE := 1.9
## The margin, in seconds, by which he has to beat the first attacker to a ball
## he can only get his head to. Scaled by `command`, which is the whole of what
## the attribute means: a commanding keeper comes for balls a nervous one leaves.
const CLAIM_LEAD := 0.2
## How far up the pitch a ball in the air is worth walking the forecast for.
const CLAIM_SIGHT := 24.0


## Where to go and claim a ball in the air, or Vector3.INF to stay at home.
##
## The rule has two halves and the height decides which one applies. Above head
## reach the ball is his and nobody else's -- that is what hands are for, and he
## needs only to be there when it arrives. Between his boot and the top of a
## jumping centre-half it is a contest like any other, so he has to beat the
## first attacker to it by a margin or leave it to his defenders. A keeper who
## comes for everything is the one who gets lobbed, and a keeper who comes for
## nothing is the one a cross goes over.
##
## Only inside his own area, because outside it he may not use his hands and a
## claim that ends there is not a claim.
static func _claim_target(ctx: SimContext, k: SimPlayer) -> Vector3:
	var ball := ctx.ball
	if ball.grounded or ball.pos.y <= SimConsts.FOOT_REACH_HEIGHT:
		return Vector3.INF
	if ctx.possession_team == k.team:
		return Vector3.INF
	var goal := ctx.pitch.own_goal(k.team)
	if absf(ball.pos.x - goal.x) > ctx.pitch.penalty_depth + CLAIM_SIGHT:
		return Vector3.INF
	var boldness: float = lerpf(0.8, 1.2, k.attrs.command)
	var traj := ctx.trajectory_now()
	for i in range(0, traj.count, 2):
		var sample := traj.points[i]
		if sample.y <= SimConsts.FOOT_REACH_HEIGHT or sample.y > CLAIM_HEIGHT * boldness:
			continue
		var at := Vector3(sample.x, 0.0, sample.z)
		if not ctx.pitch.in_own_penalty_area(k.team, at):
			continue
		var t := traj.time_of_index(i)
		var mine := SimValueField.time_to_arrive(k, at, SimValueField.reaction_of(k) * 0.6)
		if mine > t:
			continue
		if sample.y > SimConsts.HEAD_REACH_HEIGHT:
			return at
		var needed := CLAIM_LEAD / boldness
		var contested := false
		for oid in ctx.opponent_ids(k.team):
			var o := ctx.players[oid]
			if not o.on_pitch:
				continue
			if SimValueField.time_to_arrive(o, at, SimValueField.reaction_of(o)) < mine + needed:
				contested = true
				break
		if not contested:
			return at
	return Vector3.INF


static func _position(ctx: SimContext, k: SimPlayer) -> void:
	var hold_at := station(ctx, k, ctx.ball.ground_pos())

	# A cross, a lofted ball or a clearance dropping into his own area. Ahead of
	# the sweep because it is the same decision made about a ball that has not
	# come down yet, and the sweep cannot see one: it only looks at the part of
	# the forecast a man could already head.
	var claim := _claim_target(ctx, k)
	if claim != Vector3.INF:
		k.steer_to(ctx.pitch.clamp_to_pitch(claim, 0.3), INF)
		return

	# Come off the line for a through ball when the keeper beats the attacker
	# to it. This is the whole of "sweeper keeper" -- a time comparison, not a
	# behaviour switch.
	var sweep := _sweep_target(ctx, k)
	if sweep != Vector3.INF:
		k.steer_to(sweep, INF)
		return

	# A man running clean through is the other case, and it is not a race for a
	# loose ball, so `_sweep_target` never sees it.
	var meet := _one_on_one(ctx, k)
	if meet != Vector3.INF:
		k.steer_to(ctx.pitch.clamp_to_pitch(meet, 0.3), INF)
		return

	k.steer_to(ctx.pitch.clamp_to_pitch(hold_at, 0.3), k.max_speed() * 0.7)


## How far out a carrier has to be before the keeper stops thinking about him.
##
## Thirty was the first try and it is a keeper who lives outside his box. A
## carrier thirty metres out has three seconds of running still to do and any
## number of things to do instead, and coming for him is not brave, it is
## abandoning the goal on a guess. Twenty-two is the edge of the D.
const ONE_ON_ONE_RANGE := 22.0
## A defender inside this cone, goal-side of the carrier, means somebody is
## covering and the keeper stays home. It widens toward the goal because a
## defender who is nearly level with the goal covers a much broader angle of it
## than one still back at the ball -- a flat corridor called half the covered
## breaks one-on-ones and sent the keeper out for them.
const COVER_WIDTH := 4.0
const COVER_SPREAD := 0.45
## And how hard the carrier has to be running at goal. Anything slower is a man
## with the ball near the box, which is most of a match.
const RUNNING_AT_GOAL := 2.5
## How much of the distance to the carrier the keeper takes off him, and the
## furthest out he will go doing it.
const CLOSE_DOWN_FRACTION := 0.55
const CLOSE_DOWN_MAX := 15.0
## Inside this, he stops narrowing the angle and goes for the ball.
const SMOTHER_RANGE := 5.0


## Where to stand when somebody is through on goal, or Vector3.INF if nobody is.
##
## The station in `_position` is an arc: 0.45 m off the line plus 0.17 per metre
## of ball distance, so a striker clean through from twelve metres out finds the
## keeper two and a half metres off his line, waiting for him. That is the one
## situation in football where a goalkeeper does the opposite of waiting. All he
## owns in a one-on-one is the angle he can take away, and the angle is worth
## more the further from his own goal he takes it -- standing still and letting
## the striker choose his corner is giving away the only thing he has.
##
## Written as a comparison rather than as a mode, like everything else in this
## module. There is no "one-on-one state": there is a carrier, a distance, a test
## for whether anybody is covering, and a station that comes out to meet him and
## goes back when a defender gets across. Inside `SMOTHER_RANGE` he stops
## narrowing and goes at the ball, which is the moment the whole thing is decided
## and is worth being able to see.
static func _one_on_one(ctx: SimContext, k: SimPlayer) -> Vector3:
	if ctx.possession_team == k.team or ctx.possession_player < 0:
		return Vector3.INF
	if ctx.possession_player >= ctx.players.size():
		return Vector3.INF
	var carrier := ctx.players[ctx.possession_player]
	if carrier.team == k.team or not carrier.on_pitch:
		return Vector3.INF
	var goal := ctx.pitch.own_goal(k.team)
	var to_goal := SimConsts.horizontal(goal - carrier.pos)
	var range_to_goal: float = to_goal.length()
	if range_to_goal > ONE_ON_ONE_RANGE or range_to_goal < 0.5:
		return Vector3.INF
	var dir := to_goal / range_to_goal
	# Running at the goal, not across the face of it. A man carrying it along the
	# byline is not through, however close he is.
	if carrier.vel.dot(dir) < RUNNING_AT_GOAL:
		return Vector3.INF

	for pid in ctx.team_players[k.team]:
		var d := ctx.players[pid]
		if d.id == k.id or not d.on_pitch:
			continue
		var rel := SimConsts.horizontal(d.pos - carrier.pos)
		var along: float = rel.dot(dir)
		if along < -1.5 or along > range_to_goal:
			continue
		if absf(rel.x * -dir.z + rel.z * dir.x) <= COVER_WIDTH + COVER_SPREAD * maxf(along, 0.0):
			return Vector3.INF

	if range_to_goal <= SMOTHER_RANGE:
		return ctx.ball.ground_pos()
	var limit: float = minf(CLOSE_DOWN_MAX, ctx.pitch.penalty_depth - 1.0)
	var advance: float = minf(range_to_goal * CLOSE_DOWN_FRACTION * lerpf(0.8, 1.15, k.attrs.command), limit)
	return goal - dir * advance


## Returns the point to sweep to, or Vector3.INF if the keeper should hold.
##
## Cheap rejections first: this walks the forecast against every opponent, so it
## must not run when the ball is nowhere near our goal.
static func _sweep_target(ctx: SimContext, k: SimPlayer) -> Vector3:
	if ctx.possession_team == k.team:
		return Vector3.INF
	var goal_x := ctx.pitch.own_goal(k.team).x
	if absf(ctx.ball.pos.x - goal_x) > ctx.pitch.penalty_depth + 26.0:
		return Vector3.INF
	if ctx.tick_index % SimConsts.OFF_BALL_DECISION_TICKS != k.id % SimConsts.OFF_BALL_DECISION_TICKS:
		return Vector3.INF
	var traj := ctx.trajectory_now()
	var goal := ctx.pitch.own_goal(k.team)
	for i in range(0, traj.count, 2):
		var sample := traj.points[i]
		if sample.y > SimConsts.HEAD_REACH_HEIGHT:
			continue
		# Only inside our own third, and only inside the penalty area: a keeper
		# who sweeps to the halfway line is a bug, not a sweeper keeper.
		if absf(sample.x - goal.x) > ctx.pitch.penalty_depth + 4.0:
			continue
		var t := traj.time_of_index(i)
		var keeper_time := SimValueField.time_to_arrive(k, sample, SimValueField.reaction_of(k) * 0.6)
		if keeper_time > t + 0.1:
			continue
		# Would an attacker beat us to it?
		var attacker_time := INF
		for oid in ctx.opponent_ids(k.team):
			var o := ctx.players[oid]
			if o.on_pitch:
				attacker_time = minf(attacker_time, SimValueField.time_to_arrive(o, sample, SimValueField.reaction_of(o)))
		if keeper_time < attacker_time - 0.15:
			return Vector3(sample.x, 0.0, sample.z)
	return Vector3.INF


# --- Shot response ----------------------------------------------------------


static func _shot_response(ctx: SimContext, k: SimPlayer) -> void:
	# The crossing test walks the whole forecast, so reject early: the ball has
	# to be moving toward this goal, fast, and in this half.
	var goal_x := ctx.pitch.own_goal(k.team).x
	if ctx.ball.vel.x * signf(goal_x) <= 1.0 or absf(ctx.ball.pos.x - goal_x) > 45.0:
		if not ctx.keeper_state.is_empty():
			ctx.keeper_state.erase(k.id)
		return
	var crossing := _goal_line_crossing(ctx, k)
	var state: Dictionary = ctx.keeper_state.get(k.id, {})
	if crossing.is_empty():
		if not state.is_empty():
			ctx.keeper_state.erase(k.id)
		return

	var shot_id: int = ctx.ball.last_touch_tick
	if state.get("shot", -1) != shot_id:
		# A new attempt on goal. Sample a reaction time, scaled by reflexes.
		var reaction: float = maxf(ctx.rng.gauss_clamped(REACTION_MEAN, REACTION_SD, 2.5), 0.06)
		reaction *= lerpf(1.35, 0.72, k.attrs.reflexes)
		state = {
			"shot": shot_id,
			"react_ticks": int(round(reaction * float(SimConsts.TICK_HZ))),
			"resolved": false,
		}
		ctx.keeper_state[k.id] = state

	if state["resolved"]:
		_take_the_save(ctx, k, state)
		return
	if state["react_ticks"] > 0:
		state["react_ticks"] -= 1
		return

	var point: Vector3 = crossing["point"]
	var time_left: float = crossing["time"]
	if time_left > 0.9:
		# Still time to set: move along the line toward the shot.
		k.steer_to(Vector3(k.pos.x, 0.0, clampf(point.z, -ctx.pitch.goal_half_width, ctx.pitch.goal_half_width)), INF)
		return

	# Where does the ball actually come closest to the keeper, and when?
	#
	# Measuring to the goal-line crossing instead is a real mistake: a keeper who
	# has come three metres off the line is much closer to a shot passing them
	# than to where it would eventually cross, and would be given no credit for
	# narrowing the angle -- which is the entire point of coming off the line.
	var approach := _closest_approach(ctx, k, crossing["index"])
	var margin: float = approach.x
	var dive_time: float = approach.y

	# Reach envelope: an ellipsoid that grows over the dive duration, sized by
	# height and agility.
	var extension: float = clampf(dive_time / DIVE_TIME, 0.0, 1.0)
	var reach: float = lerpf(REACH_STANDING, REACH_DIVING, extension)
	reach *= lerpf(0.85, 1.15, k.attrs.agility)
	# 1.0 at real time: `SimMatchConfig`, "the compressed match's scoring fit".
	reach *= ctx.config.keeper_reach_scale()

	state["resolved"] = true
	if margin > reach:
		# Beaten. The keeper still dives, which is what the player sees.
		_record_facing(ctx, k, margin, reach, false, false)
		k.play_anim(SimConsts.Anim.DIVE_LEFT if point.z < k.pos.z else SimConsts.Anim.DIVE_RIGHT, 0.8)
		return

	var closeness: float = 1.0 - clampf(margin / maxf(reach, 0.01), 0.0, 1.0)
	var ball_speed := ctx.ball.vel.length()
	# Calibrated so that roughly two thirds to three quarters of shots on target
	# are kept out, which is what the real save percentage looks like.
	var save_chance: float = clampf(0.78 + closeness * 0.20, 0.0, 0.97)
	save_chance *= lerpf(0.75, 1.12, k.attrs.handling)
	save_chance *= clampf(1.2 - ball_speed / 85.0, 0.75, 1.12)
	# 1.0 at real time: `SimMatchConfig`, "the compressed match's scoring fit".
	save_chance *= ctx.config.keeper_save_scale()
	k.play_anim(SimConsts.Anim.DIVE_LEFT if point.z < k.pos.z else SimConsts.Anim.DIVE_RIGHT, 0.8)
	if not ctx.rng.chance(save_chance):
		_record_facing(ctx, k, margin, reach, true, false)
		return
	_record_facing(ctx, k, margin, reach, true, true)

	# Saved. Parry versus catch is decided by margin and ball speed.
	var can_catch := closeness > 0.55 and ball_speed < 24.0 and ctx.rng.chance(lerpf(0.2, 0.9, k.attrs.handling))
	# Only a shot goes in the book as a save. This response fires for any ball
	# the forecast has going in -- a cross, a sliced clearance, a pass drifting
	# for the corner of the goal -- and a keeper claiming those has made a
	# claim, not a save. The dive is real either way; the ledger entry is not.
	if _shot_in_flight(ctx, k):
		ctx.log_event(SimTelemetry.Ev.SAVE, {
			"p": k.id,
			"team": k.team,
			"caught": can_catch,
			"margin": margin,
			"speed": ball_speed,
			"minute": ctx.minute(),
		})
	_resolve_pass_of_shot(ctx, k)
	# Decided, not yet done. The keeper commits before he can know — that is what
	# a dive is — but the ball keeps flying, and is taken when it arrives.
	state["caught"] = can_catch
	state["save_tick"] = ctx.tick_index + int(round(dive_time * float(SimConsts.TICK_HZ)))


## Records which of the save model's two stages resolved a shot, on the shot's
## own event.
##
## They multiply, and only the second one is calibrated. `save_chance` claims two
## thirds to three quarters of shots on target are kept out, and it is asked only
## of the shots the reach envelope has already passed — so the compound can never
## be more than that figure times the envelope's pass rate. Nothing measured the
## envelope: being beaten for reach returns without logging anything, so a keeper
## who stops half of what is goal-bound reads exactly like one whose roll is
## unlucky, and the two want opposite fixes.
##
## Stamped onto `ctx.active_shot` rather than logged as an event of its own, so
## these rows and `SimReferee.close_shot`'s fates describe one population and can
## be read against each other. The tick test is what makes that true:
## `_shot_response` fires for any ball the forecast has going in, a deflection or
## a sliced clearance included, and those are not shots.
static func _record_facing(ctx: SimContext, k: SimPlayer, margin: float, reach: float,
		reached: bool, saved: bool) -> void:
	if ctx.active_shot.is_empty() or ctx.ball.last_touch_tick != ctx.active_shot_tick:
		return
	if int(ctx.active_shot.get("team", -1)) == k.team:
		return
	ctx.active_shot["k_margin"] = margin
	ctx.active_shot["k_reach"] = reach
	ctx.active_shot["k_reached"] = reached
	ctx.active_shot["k_saved"] = saved


## Takes the ball at the end of a dive whose outcome was settled up to nine
## tenths of a second earlier.
##
## Applying that outcome at the moment it was decided was a plain teleport, and a
## conspicuous one because it always happened in front of goal: the ball jumped
## to where it *would* have crossed the line — five to nine metres on a normal
## shot, three times that on a hard one — and a save from head height dropped it
## to the grass on the way. The decision belongs where it is, because a keeper
## who waits for certainty has already been beaten. Only the touch moves.
static func _take_the_save(ctx: SimContext, k: SimPlayer, state: Dictionary) -> void:
	if not state.has("save_tick"):
		return
	var goal_x := ctx.pitch.own_goal(k.team).x
	var side := signf(goal_x)
	# The dive was timed off a forecast, so honour whichever comes first: the tick
	# the ball was predicted to come closest, or the ball actually drawing level.
	var arrived: bool = ctx.tick_index >= int(state["save_tick"])
	if not arrived and (ctx.ball.pos.x - k.pos.x) * side < 0.0:
		return
	state.erase("save_tick")

	if bool(state["caught"]):
		k.play_anim(SimConsts.Anim.KEEPER_CATCH, 0.6)
		# Caught where it was met, not at the keeper's chest. A save at full
		# stretch is two and a half metres from him, and `_hold_and_distribute`
		# draws it in from there.
		SimTouch.apply(ctx, k, SimTelemetry.Touch.KEEPER_CATCH, Vector3.ZERO, Vector3.ZERO)
		return

	# A parry goes wide or back into play, and it is a live ball. It keeps the
	# height it was met at: a shot pushed over the bar starts where the hand was.
	var pos := ctx.ball.pos
	var away := ctx.pitch.target_goal(k.team) - pos
	away.y = 0.0
	var out: float = signf(pos.z) if absf(pos.z) > 0.4 else (1.0 if ctx.rng.chance(0.5) else -1.0)
	var dir := (away.normalized() * 0.5 + Vector3(0.0, 0.0, out)).normalized()
	var speed: float = ctx.ball.vel.length() * ctx.rng.range_float(0.18, 0.42)
	pos.y = maxf(pos.y, SimConsts.BALL_RADIUS)
	# A dive can meet the ball level with the posts, and a parry struck from
	# behind them is a goal.
	if (pos.x - goal_x) * side > -0.4:
		pos.x = goal_x - side * 0.4
	ctx.ball.pos = pos
	SimTouch.apply(ctx, k, SimTelemetry.Touch.KEEPER_PARRY, dir * speed + Vector3(0.0, ctx.rng.range_float(0.5, 3.0), 0.0), Vector3.ZERO)


## Vertical reach is smaller than lateral: a keeper covers the ground faster
## than the top corner.
const VERTICAL_REACH_RATIO := 1.45


## Closest approach of the ball to the keeper before it crosses the line, as
## (distance, time). Distance is measured in the keeper's own reach space, so a
## ball at head height is further away than one at the same lateral offset along
## the ground.
static func _closest_approach(ctx: SimContext, k: SimPlayer, crossing_index: int) -> Vector2:
	var traj := ctx.trajectory_now()
	var best := INF
	var best_time := 0.0
	var limit: int = mini(crossing_index + 1, traj.count)
	for i in limit:
		var p := traj.points[i]
		var dx := p.x - k.pos.x
		var dz := p.z - k.pos.z
		# The keeper's hands start at roughly hip height when set.
		var dy: float = maxf(p.y - 0.85, 0.0) * VERTICAL_REACH_RATIO
		var d := sqrt(dx * dx + dz * dz + dy * dy)
		if d < best:
			best = d
			best_time = traj.time_of_index(i)
	if is_inf(best):
		return Vector2(99.0, 0.0)
	return Vector2(best, best_time)


## Where and when the ball would cross the plane of this keeper's goal line, if
## it is on target. Empty if the ball is not going in.
static func _goal_line_crossing(ctx: SimContext, k: SimPlayer) -> Dictionary:
	var goal := ctx.pitch.own_goal(k.team)
	var side := signf(goal.x)
	if ctx.ball.vel.x * side <= 0.5:
		return {}
	var traj := ctx.trajectory_now()
	var prev := ctx.ball.pos
	for i in traj.count:
		var p := traj.points[i]
		if (p.x - goal.x) * side >= 0.0:
			var span := (p.x - prev.x)
			var f: float = 0.0 if absf(span) < 1e-5 else clampf((goal.x - prev.x) / span, 0.0, 1.0)
			var point := prev.lerp(p, f)
			# Only balls that are actually going in. A keeper who dives at
			# everything near the goal manufactures saves out of shots that were
			# always going wide, and the statistics stop meaning anything.
			#
			# The frame is the referee's, to the millimetre. This used to allow a
			# ball radius of slack at each post and over the bar, and
			# `SimReferee._crosses_goal` does not -- so a ball passing just
			# outside the post was a shot the keeper saved and a shot the match
			# record called wide. Two implementations of "is this going in", and
			# the disagreement was worth half of every shot in a match:
			# `keeper saved, wide` ran at 23% and 52% on two seeds before these
			# two lines agreed. `docs/INVARIANTS.md`, two models of the same event.
			if not SimReferee.crosses_goal(ctx, SimConsts.other_team(k.team)):
				return {}
			return {"point": point, "index": i, "time": traj.time_of_index(i) - SimConsts.FORECAST_DT * (1.0 - f)}
		prev = p
	return {}


## A save closes out whatever the ball was carrying, so a shot does not linger
## as an unresolved pass.
static func _resolve_pass_of_shot(ctx: SimContext, _k: SimPlayer) -> void:
	ctx.ball.intended_target = -1


# --- Contact rules ----------------------------------------------------------


## True while an opponent's attempt on goal is still live and unresolved.
##
## Read off `ctx.active_shot`, which is the same record the referee fills in and
## the shot log carries, so there is one answer to "is this ball a shot" rather
## than two that can disagree.
static func _shot_in_flight(ctx: SimContext, k: SimPlayer) -> bool:
	if ctx.active_shot.is_empty():
		return false
	return int(ctx.active_shot.get("team", -1)) != k.team


## A keeper gathers a slow ball inside their own area, or takes a high one out of
## the air above it.
static func _try_gather(ctx: SimContext, k: SimPlayer) -> void:
	if not k.can_touch():
		return
	# A shot belongs to the save model from the moment it is struck until it
	# resolves, and this function may not have it.
	#
	# Without the gate the catch roll below quietly did the whole job.
	# `_goal_line_crossing` deliberately ignores a ball that is not going in --
	# its own comment says a keeper who dives at everything near the goal
	# manufactures saves out of shots that were always going wide -- and then
	# this picked those balls up regardless, three metres from a post, because
	# proximity was the only test. Measured across three seeds: three quarters of
	# every shot ended with the keeper touching the ball, better than a third of
	# them after they had already missed the target, and *nothing* went out of
	# play. The reach envelope, the reaction time and the dive were being
	# bypassed; seed 7 had fifteen shots end at the keeper and zero logged saves.
	#
	# It resolves the moment he touches it, so the parry, the rebound and the
	# loose ball afterwards are all still his -- `SimReferee.close_shot` clears
	# the record on any touch, and this is a gather again on the next tick.
	if _shot_in_flight(ctx, k):
		return
	if not ctx.pitch.in_own_penalty_area(k.team, k.pos):
		# Outside the area a keeper is just a player with bad feet.
		if k.dist_to(ctx.ball.pos) <= SimConsts.CONTROL_RANGE and ctx.ball.pos.y < SimConsts.FOOT_REACH_HEIGHT:
			SimTouch.clearance(ctx, k)
		return
	var high := ctx.ball.pos.y > SimConsts.FOOT_REACH_HEIGHT
	if ctx.ball.pos.y > CLAIM_HEIGHT * lerpf(0.8, 1.2, k.attrs.command):
		return
	if k.dist_to(ctx.ball.pos) > (CLAIM_RANGE if high else GATHER_RANGE):
		return
	var speed := ctx.ball.vel.length()
	var handled: float = clampf(lerpf(0.45, 0.97, k.attrs.handling) - speed / 45.0, 0.05, 0.97)
	if high:
		# A ball he has come for is a different question from a ball that arrives
		# at him. He has both hands to it by the time this is asked -- getting
		# there is `_claim_target`'s problem -- so what is left is whether he holds
		# it, which is handling for the catch and command for the bodies around
		# him. That is what the two attributes are for, and the pace term is far
		# gentler than the shot's because a cross is dropping rather than driven.
		handled = clampf(lerpf(0.6, 0.97, k.attrs.handling) * lerpf(0.82, 1.1, k.attrs.command)
			- speed / 110.0, 0.1, 0.95)
		handled *= lerpf(1.0, 0.78, clampf(ctx.pressure_on(k) / 2.0, 0.0, 1.0))
	if ctx.rng.chance(clampf(handled, 0.05, 0.97)):
		SimTouch.apply(ctx, k, SimTelemetry.Touch.KEEPER_CATCH, Vector3.ZERO, Vector3.ZERO)
	elif high:
		# He could not hold it, so he punches: two fists, away and wide, which is
		# the same ball a defender's clearing header is.
		SimTouch.clearance(ctx, k)
	else:
		SimTouch.poke(ctx, k, SimTelemetry.Touch.BLOCK)


## The keeper has the ball at his *feet* -- a back-pass, or a ball he came out
## for and could not pick up -- and has to play it like an outfielder. The ball
## in his hands is `_hold_and_distribute` and `_release`, which are a different
## act with different animation and different physics, and used to share this
## function with it.
static func decide_with_ball(ctx: SimContext, k: SimPlayer) -> void:
	var tactics := ctx.tactics(k.team)
	var short_option := _short_option(ctx, k)
	# `distribution` is what the attribute is for, and until now nothing on the
	# pitch read it: it sat in `SimRole.attribute_weights`, so it was priced into
	# `role_rating`, squad quality and every scout report, and changed nothing
	# (`docs/THE_FOOTBALL.md` 14). A keeper who can pass keeps it; one who cannot
	# hits it long, which is the one decision the attribute names.
	#
	# It shifts the plan's own threshold rather than replacing it — the plan still
	# decides whether this side plays out at all, and the keeper decides whether he
	# is the man to do it. A 0.2 distribution gives up about a fifth of the short
	# balls the plan asks for, a 0.9 takes a fifth more.
	var can_play: float = lerpf(-0.12, 0.12, k.attrs.distribution)
	var go_short := short_option != null \
		and ctx.rng.unit_float() > clampf(0.2 + tactics.directness * 0.65 - can_play, 0.0, 0.95)
	if go_short:
		if SimDebug.enabled:
			SimDebug.capture_choice(ctx, k, "throw short -> #%d" % short_option.shirt,
				PackedStringArray(["kick long"]))
		SimTouch.ground_pass(ctx, k, short_option.pos, 4.0, short_option.id, SimTelemetry.Touch.KEEPER_THROW)
		return
	var target := _long_option(ctx, k)
	var mate := ctx.nearest_to(target, k.team, k.id)
	if SimDebug.enabled:
		SimDebug.capture_choice(ctx, k, "kick long, %.0f m" % k.dist_to(target),
			PackedStringArray(["throw short -> #%d" % short_option.shirt] if short_option != null else []))
	SimTouch.lofted_pass(ctx, k, target, 2.2, mate.id if mate != null else -1, SimTelemetry.Touch.LOFTED_PASS)


static func _short_option(ctx: SimContext, k: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_space := 6.0
	for pid in ctx.team_players[k.team]:
		var p := ctx.players[pid]
		if p.id == k.id or not p.on_pitch:
			continue
		var d := p.dist_to(k.pos)
		if d < 6.0 or d > 30.0:
			continue
		var opponent := ctx.nearest_opponent(p)
		var space := opponent.dist_to(p.pos) if opponent != null else 25.0
		if space > best_space:
			best_space = space
			best = p
	return best


static func _long_option(ctx: SimContext, k: SimPlayer) -> Vector3:
	var dir := ctx.pitch.attack_dir(k.team)
	var best := Vector3(dir * 12.0, 0.0, 0.0)
	var best_x := -INF
	for pid in ctx.team_players[k.team]:
		var p := ctx.players[pid]
		if not p.on_pitch or p.is_keeper:
			continue
		if p.pos.x * dir > best_x:
			best_x = p.pos.x * dir
			best = Vector3(p.pos.x + dir * 3.0, 0.0, p.pos.z)
	return best
