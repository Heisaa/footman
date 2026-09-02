class_name SimReferee
extends RefCounted
## Offside, fouls, cards, advantage, added time and the whistle (PLAN.md §3.5).
##
## Offside is evaluated at the instant of the passing impulse. That is cheap
## here only because passes are discrete events in this model -- there is no
## frame in which the ball is "being passed".

## Probability a foul also brings a caution, before modifiers.
const CARD_BASE := 0.12
const CARD_PER_CLOSING_SPEED := 0.022
## A foul this bad is a straight dismissal.
const RED_THRESHOLD := 0.9
## Seconds of stoppage added for each class of interruption.
const STOPPAGE_GOAL := 30.0
const STOPPAGE_CARD := 20.0
const STOPPAGE_SET_PIECE := 2.0


static func reset_period(ctx: SimContext) -> void:
	ctx.offside_pending = -1
	ctx.offside_tick = -1
	ctx.stoppage_ticks = 0
	ctx.added_time_ticks = 0


static func update(ctx: SimContext) -> void:
	_track_shot(ctx)
	# Offside only bites when the flagged player actually plays the ball.
	if ctx.offside_pending >= 0 and ctx.tick_index > ctx.offside_tick:
		var ball := ctx.ball
		if ball.last_touch_tick == ctx.tick_index:
			if ball.last_touch_player == ctx.offside_pending:
				_whistle_offside(ctx)
			else:
				ctx.offside_pending = -1
		elif ctx.tick_index - ball.last_touch_tick > SimConsts.TICK_HZ * 4:
			ctx.offside_pending = -1


# --- Shot outcome -----------------------------------------------------------


## Watches the ball while a shot is in flight and records whether it was on
## target. A shot is on target if the shared forecast ever has it crossing the
## plane of the goal inside the frame.
static func _track_shot(ctx: SimContext) -> void:
	if ctx.active_shot.is_empty():
		return
	var age := ctx.tick_index - ctx.active_shot_tick
	var ball := ctx.ball
	if not ctx.in_play:
		# It has left the field, and nobody on the pitch ended it. Closing here
		# rather than on the next touch matters: the touch that follows a shot
		# gone wide is the goal kick, taken by the keeper, and waiting for it
		# credited him with saving a ball that had already missed.
		close_shot(ctx, false)
		return
	if age > 0 and (ball.last_touch_tick > ctx.active_shot_tick or age > SimConsts.TICK_HZ * 4):
		# Somebody else has touched it, or it is long since dead.
		close_shot(ctx, ball.last_touch_tick > ctx.active_shot_tick)
		return
	# Whether the ball is goal-bound *now*, live rather than latched. `on_target`
	# is a latch built on top of this, and the difference between the two was the
	# whole of what this block could not see: a shot briefly goal-bound that then
	# curls or drops away keeps the flag for ever, so the engine's accuracy read
	# high and the shots that quietly died were invisible.
	var bound := crosses_goal(ctx, int(ctx.active_shot["team"]))
	ctx.active_shot["bound"] = bound
	if bound:
		ctx.active_shot["on_target"] = true


## What became of a shot, recorded where it dies rather than inferred afterwards
## from a latched flag.
##
## The old rule set `blocked` only when a non-keeper touched a shot that was *not*
## on target, which is the wrong way round: a defender who gets a foot to a ball
## heading for the net is the definition of a block and was recorded as nothing at
## all. Measured on seed 7 that was most of the gap in the accounting -- 23 shots,
## about 18 on target, 5 saves and 3 goals, with ten unaccounted for.
##
## `bound` rather than `on_target` decides it, because by the time a touch is
## noticed the ball's velocity already carries the deflection: the live flag holds
## what the forecast said on the last tick before anybody reached it.
static func close_shot(ctx: SimContext, touched: bool) -> void:
	var shot := ctx.active_shot
	if shot.is_empty():
		return
	var bound := bool(shot.get("bound", false))
	var fate := "wide"
	if touched:
		var toucher := ctx.ball.last_touch_player
		var p: SimPlayer = ctx.players[toucher] if toucher >= 0 and toucher < ctx.players.size() else null
		if p == null:
			fate = "touched"
		elif p.team == int(shot["team"]):
			# His own side got to it first. Not a save and not a block: the shot
			# stopped being this shot.
			fate = "own player"
		elif p.is_keeper:
			# Which of the keeper's two paths took it. They are different models
			# and conflating them is what hid `_try_gather` doing the save's job.
			var how := "gathered" if ctx.ball.last_touch_kind == SimTelemetry.Touch.KEEPER_CATCH else "saved"
			var ever := " (was on target)" if bool(shot["on_target"]) else " (never on target)"
			fate = ("keeper %s" % how) if bound else ("keeper %s, wide%s" % [how, ever])
		elif bound:
			fate = "blocked"
			shot["blocked"] = true
		else:
			fate = "defender, wide"
	elif bool(shot["on_target"]):
		# It was goal-bound at some point, nobody touched it, and it did not go
		# in. The latch and the flight disagree, which is the curl or the drop.
		fate = "curled away"
	shot["fate"] = fate
	ctx.active_shot = {}


## True if the forecast has the ball crossing the goal `team` is attacking,
## between the posts and under the bar. The predicate half of `goal_crossing`.
static func crosses_goal(ctx: SimContext, team: int) -> bool:
	var goal := ctx.pitch.target_goal(team)
	var side := signf(goal.x)
	if ctx.ball.vel.x * side <= 0.5:
		return false
	var traj := ctx.trajectory_now()
	var prev := ctx.ball.pos
	for i in traj.count:
		var p := traj.points[i]
		if (p.x - goal.x) * side >= 0.0:
			var span := p.x - prev.x
			var f: float = 0.0 if absf(span) < 1e-5 else clampf((goal.x - prev.x) / span, 0.0, 1.0)
			var point := prev.lerp(p, f)
			return absf(point.z) <= ctx.pitch.goal_half_width and point.y <= ctx.pitch.goal_height
		prev = p
	return false


# --- Offside ----------------------------------------------------------------


## X of the offside line for `team`, in world coordinates: the second-last
## opponent, or the halfway line, whichever is further forward.
static func offside_line(ctx: SimContext, team: int) -> float:
	if not ctx.offside_on:
		return ctx.pitch.target_goal(team).x
	var dir := ctx.pitch.attack_dir(team)
	var first := -INF
	var second := -INF
	for oid in ctx.opponent_ids(team):
		var o := ctx.players[oid]
		if not o.on_pitch:
			continue
		var depth := o.pos.x * dir
		if depth > first:
			second = first
			first = depth
		elif depth > second:
			second = depth
	if is_inf(second):
		second = 0.0
	# Never behind the halfway line: you cannot be offside in your own half.
	return maxf(second, 0.0) * dir


## The offside line as a particular player believes it to be.
##
## Offsides come from misjudging the line, and a player's view of it is stale
## and noisy (PLAN.md §4.4). Using the true line here would mean forwards never
## stray, and a match would record no offsides at all.
static func believed_offside_line(ctx: SimContext, observer: SimPlayer) -> float:
	if not ctx.offside_on:
		return ctx.pitch.target_goal(observer.team).x
	var dir := ctx.pitch.attack_dir(observer.team)
	var first := -INF
	var second := -INF
	for oid in ctx.opponent_ids(observer.team):
		var o := ctx.players[oid]
		if not o.on_pitch:
			continue
		var depth: float = SimPerception.believed_pos(ctx, observer, o).x * dir
		if depth > first:
			second = first
			first = depth
		elif depth > second:
			second = depth
	if is_inf(second):
		second = 0.0
	return maxf(second, 0.0) * dir


## True if a point would be an offside position for `team` right now.
static func would_be_offside(ctx: SimContext, team: int, point: Vector3) -> bool:
	if not ctx.offside_on:
		return false
	var dir := ctx.pitch.attack_dir(team)
	var depth := point.x * dir
	if depth <= 0.0:
		return false
	if depth <= ctx.ball.pos.x * dir:
		return false
	return depth > offside_line(ctx, team) * dir + 0.15


## Called by the touch module the moment a pass is struck.
static func on_pass(ctx: SimContext, passer: SimPlayer, target_id: int) -> void:
	ctx.offside_pending = -1
	if target_id < 0 or target_id >= ctx.players.size():
		return
	if not ctx.in_play:
		return
	var receiver := ctx.players[target_id]
	if receiver.team != passer.team:
		return
	if would_be_offside(ctx, passer.team, receiver.pos):
		ctx.offside_pending = target_id
		ctx.offside_pos = receiver.pos
		ctx.offside_tick = ctx.tick_index


static func _whistle_offside(ctx: SimContext) -> void:
	var offender := ctx.players[ctx.offside_pending]
	ctx.log_event(SimTelemetry.Ev.OFFSIDE, {
		"p": offender.id,
		"team": offender.team,
		"pos": ctx.offside_pos,
		"minute": ctx.minute(),
	})
	ctx.offside_pending = -1
	add_stoppage(ctx, STOPPAGE_SET_PIECE)
	SimSetPiece.free_kick(ctx, SimConsts.other_team(offender.team), ctx.offside_pos, true)


# --- Fouls and cards --------------------------------------------------------


static func award_foul(ctx: SimContext, offender: SimPlayer, victim: SimPlayer, closing_speed: float) -> void:
	var spot := ctx.ball.ground_pos()
	var severity: float = clampf(closing_speed / 9.0 + offender.attrs.aggression * 0.3, 0.0, 1.3)
	ctx.log_event(SimTelemetry.Ev.FOUL, {
		"p": offender.id,
		"team": offender.team,
		"victim": victim.id,
		"pos": spot,
		"severity": severity,
		"minute": ctx.minute(),
	})
	victim.play_anim(SimConsts.Anim.FALL, SimPlayer.FALL_SECONDS + SimPlayer.FLOOR_SECONDS,
		SimConsts.Anim.GET_UP, SimPlayer.GET_UP_SECONDS)
	offender.queue_anim(SimConsts.Anim.PROTEST, 1.2)
	# A body going down is a committed move like a slide, at no speed: he goes
	# down where he is and nothing steers or pushes him until he is up -- which
	# is after the fall, a beat on the floor and the getting up, at least, and
	# longer for a slow riser.
	var floor_time: float = ctx.rng.range_float(0.6, 1.4)
	victim.commit_move(Vector3.ZERO, SimPlayer.FALL_SECONDS, false,
		maxf(floor_time - SimPlayer.FALL_SECONDS, SimPlayer.FLOOR_SECONDS + SimPlayer.GET_UP_SECONDS))
	add_stoppage(ctx, STOPPAGE_SET_PIECE)

	var card_chance: float = CARD_BASE + closing_speed * CARD_PER_CLOSING_SPEED
	card_chance *= lerpf(0.7, 1.5, offender.attrs.aggression)
	# Fouls that stop a promising attack are punished harder.
	if ctx.pitch.in_own_penalty_area(offender.team, spot) or ctx.value.xt_at(victim.team, spot, ctx.pitch) > 0.08:
		card_chance *= 1.5
	if ctx.rng.chance(clampf(card_chance, 0.0, 0.65)):
		_book(ctx, offender, severity >= RED_THRESHOLD)

	if ctx.pitch.in_own_penalty_area(offender.team, spot):
		SimSetPiece.penalty(ctx, victim.team)
	else:
		SimSetPiece.free_kick(ctx, victim.team, spot, false)


static func _book(ctx: SimContext, offender: SimPlayer, straight_red: bool) -> void:
	var red := straight_red
	if not red:
		offender.yellow_cards += 1
		red = offender.yellow_cards >= 2
	if red:
		offender.on_pitch = false
		offender.sent_off = true
	ctx.log_event(SimTelemetry.Ev.CARD, {
		"p": offender.id,
		"team": offender.team,
		"red": red,
		"minute": ctx.minute(),
	})
	add_stoppage(ctx, STOPPAGE_CARD)


# --- Clock ------------------------------------------------------------------


static func add_stoppage(ctx: SimContext, seconds: float) -> void:
	ctx.stoppage_ticks += int(seconds * float(SimConsts.TICK_HZ))
	# Added time is roughly the stoppage accrued, capped at a plausible amount.
	ctx.added_time_ticks = mini(ctx.stoppage_ticks, SimConsts.TICK_HZ * 60 * 5)
