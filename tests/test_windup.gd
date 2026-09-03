class_name TestWindup
extends SimTestCase
## The planted foot (`SimDecision.wind_up`): the mechanism, not the match.
##
## A struck long ball leaves `strike_at` ticks after the decision and from
## where the ball was forecast to be; a first-time strike leaves at once.


func run() -> void:
	_the_long_ball_waits_for_the_swing()
	_the_first_time_strike_goes_at_once()
	_a_challenge_inside_it_rushes_the_strike()
	_the_readers_read_the_backlift()


static func _settled_match() -> SimMatch:
	var opts := SimRunner.Options.new()
	opts.seed_value = 5
	opts.minutes = 2.0
	var m := SimRunner.build(opts)
	for i in 600:
		m.tick()
		if m.ctx.in_play and m.ctx.possession_player >= 0:
			break
	return m


## The holder over a ball rolling gently ahead of him in the middle of the
## pitch, one teammate thirty metres up it to hit, everybody else away.
static func _place(ctx: SimContext, holder: SimPlayer, mate: SimPlayer, roll: float) -> void:
	var dir := ctx.pitch.attack_dir(holder.team)
	var at := Vector3(-10.0 * dir, 0.0, 0.0)
	ctx.ball.reset(Vector3(at.x, SimConsts.BALL_RADIUS, at.z))
	ctx.ball.vel = Vector3(roll * dir, 0.0, 0.0)
	ctx.ball.last_touch_player = holder.id
	ctx.ball.last_touch_team = holder.team
	ctx.ball.last_touch_tick = ctx.tick_index - 30
	holder.pos = at + Vector3(-0.5 * dir, 0.0, 0.0)
	holder.vel = Vector3(roll * dir, 0.0, 0.0)
	holder.facing = 0.0 if dir > 0.0 else PI
	holder.spell_start_tick = ctx.tick_index - 60
	holder.touch_cooldown = 0.0
	holder.recovery_ticks = 0
	holder.commit_ticks = 0
	var far_z := ctx.pitch.half_width - 2.0
	for p in ctx.players:
		if p.id == holder.id or not p.on_pitch:
			continue
		p.vel = Vector3.ZERO
		p.recovery_ticks = 0
		p.commit_ticks = 0
		if p.id == mate.id:
			p.pos = at + Vector3(30.0 * dir, 0.0, 4.0)
		elif p.is_keeper:
			p.pos = Vector3((ctx.pitch.half_length - 1.0) * (dir if p.team != holder.team else -dir), 0.0, 0.0)
		else:
			p.pos = Vector3(-40.0 * dir, 0.0, far_z if p.id % 2 == 0 else -far_z)
	ctx.update_pressure()
	ctx.update_possession()


static func _lofted(ctx: SimContext, mate: SimPlayer, first_time: bool) -> Dictionary:
	return {
		"action": SimDecision.Action.LOFTED_PASS,
		"point": Vector3(mate.pos.x, 0.0, mate.pos.z),
		"flight": SimTouch.lofted_flight(SimConsts.horizontal_length(mate.pos - ctx.ball.pos)),
		"target": mate.id,
		"first_time": first_time,
	}


func _the_long_ball_waits_for_the_swing() -> void:
	var m := _settled_match()
	var ctx := m.ctx
	check(ctx.possession_player >= 0, "the match reached an uncontested holder")
	if ctx.possession_player < 0:
		return
	var holder := ctx.players[ctx.possession_player]
	var mate: SimPlayer = null
	for id in ctx.teammate_ids(holder.team):
		var q := ctx.players[id]
		if q.id != holder.id and not q.is_keeper and q.on_pitch:
			mate = q
			break
	_place(ctx, holder, mate, 2.0)
	var c := _lofted(ctx, mate, false)
	var seconds := SimDecision.windup_of(ctx, holder, c)
	check_between(seconds, 0.35, 0.46, "a thirty-metre lofted ball winds up for about four tenths")
	var decided := ctx.tick_index
	var struck_before := ctx.ball.last_touch_tick
	var forecast := ctx.trajectory_now().position_at(seconds)
	SimDecision._execute(ctx, holder, c, false)
	var ticks := int(ceil(seconds * float(SimConsts.TICK_HZ)))
	check_equal(holder.strike_at, decided + ticks, "the strike is queued strike_at ticks after the decision")
	check_equal(ctx.ball.last_touch_tick, struck_before, "and the ball has not been struck yet")
	check(holder.commit_ticks > 0 and holder.commit_planted and not holder.down,
		"the body is committed on its feet for the wind-up")
	var seen := ctx.telemetry.events.size()
	var struck_at := -1
	var from := Vector3.INF
	var stood := false
	for i in ticks + 5:
		m.tick()
		if holder.strike_at >= 0 and holder.commit_planted and holder.vel.length_squared() < 1e-6:
			stood = true
		while seen < ctx.telemetry.events.size():
			var e: Dictionary = ctx.telemetry.events[seen]
			seen += 1
			if e["ev"] == SimTelemetry.Ev.TOUCH and int(e["p"]) == holder.id and struck_at < 0:
				struck_at = int(e["t"])
				from = e["from"]
		if struck_at >= 0:
			break
	check_equal(struck_at, decided + ticks, "the ball leaves on the strike tick")
	check_less(SimConsts.horizontal_length(from - forecast), 0.25,
		"and from where the ball was forecast to be at the strike")
	check_equal(holder.strike_at, -1, "the state is cleared after the strike")
	check_less(holder.dist_to(from), SimConsts.CONTROL_RANGE + 0.1,
		"the body was carried to the ball for the strike")
	check(stood, "and stood still on the plant foot before it")


func _the_first_time_strike_goes_at_once() -> void:
	var m := _settled_match()
	var ctx := m.ctx
	if ctx.possession_player < 0:
		return
	var holder := ctx.players[ctx.possession_player]
	var mate: SimPlayer = null
	for id in ctx.teammate_ids(holder.team):
		var q := ctx.players[id]
		if q.id != holder.id and not q.is_keeper and q.on_pitch:
			mate = q
			break
	_place(ctx, holder, mate, 2.0)
	var c := _lofted(ctx, mate, true)
	check_equal(SimDecision.windup_of(ctx, holder, c), 0.0, "a first-time strike has no wind-up")
	SimDecision._execute(ctx, holder, c, true)
	check_equal(ctx.ball.last_touch_tick, ctx.tick_index, "and the ball leaves at once")
	check_equal(holder.strike_at, -1, "with nothing queued")


## A challenge landing inside the wind-up (`SimDuel._resolve_contest`): the
## strike goes now, scuffed by the share of the swing left, or is cancelled
## when the challenge takes the ball.
func _a_challenge_inside_it_rushes_the_strike() -> void:
	var m := _settled_match()
	var ctx := m.ctx
	if ctx.possession_player < 0:
		return
	var holder := ctx.players[ctx.possession_player]
	var mate: SimPlayer = null
	for id in ctx.teammate_ids(holder.team):
		var q := ctx.players[id]
		if q.id != holder.id and not q.is_keeper and q.on_pitch:
			mate = q
			break
	_place(ctx, holder, mate, 0.0)
	var dir := Vector3(ctx.pitch.attack_dir(holder.team), 0.0, 0.0)
	var full := SimTouch.strike_scale(holder, dir)
	holder.rushed = 1.0
	check_near(SimTouch.strike_scale(holder, dir), full * SimTouch.STRIKE_BEHIND, 1e-4,
		"a strike with no swing behind it has the range of one struck with no backlift")
	var calm := SimTouch.aim_sigma(ctx, holder, 0.6, 20.0, SimTouch.GROUND_AIM_BASE, dir)
	holder.rushed = 0.0
	check_near(calm, SimTouch.aim_sigma(ctx, holder, 0.6, 20.0, SimTouch.GROUND_AIM_BASE, dir)
		* SimTouch.FIRST_TIME_HARD, 1e-4, "and the aim error of the hardest first-time ball")

	var c := _lofted(ctx, mate, false)
	SimDecision._execute(ctx, holder, c, false)
	var queued := holder.strike_at
	check_greater(float(queued), float(ctx.tick_index), "the long ball is queued")
	var seen := ctx.telemetry.events.size()
	SimDecision.fire(ctx, holder, 0.5)
	var rushed := -1.0
	for i in range(seen, ctx.telemetry.events.size()):
		var e: Dictionary = ctx.telemetry.events[i]
		if e["ev"] == SimTelemetry.Ev.TOUCH and int(e["p"]) == holder.id:
			rushed = float(e.get("rushed", -1.0))
	check_equal(ctx.ball.last_touch_tick, ctx.tick_index, "rushed, the ball leaves now")
	check_near(rushed, 0.5, 1e-6, "logged with the share of the swing it had left")
	check_equal(holder.strike_at, -1, "and nothing is queued after it")
	check_equal(holder.rushed, 0.0, "the rush is the one strike's")

	_place(ctx, holder, mate, 0.0)
	SimDecision._execute(ctx, holder, c, false)
	SimDecision.cancel_windup(holder)
	check_equal(holder.strike_at, -1, "a challenge that takes the ball cancels the strike")
	check_equal(holder.commit_ticks, 0, "and releases the body")


## The block's window is the wind-up plus the flight, and the lane charges
## the same seconds as the defender's head start; a first-time strike gives
## neither of them anything.
func _the_readers_read_the_backlift() -> void:
	var m := _settled_match()
	var ctx := m.ctx
	if ctx.possession_player < 0:
		return
	var holder := ctx.players[ctx.possession_player]
	var mate: SimPlayer = null
	for id in ctx.teammate_ids(holder.team):
		var q := ctx.players[id]
		if q.id != holder.id and not q.is_keeper and q.on_pitch:
			mate = q
			break
	_place(ctx, holder, mate, 0.0)
	var dir := Vector3(ctx.pitch.attack_dir(holder.team), 0.0, 0.0)
	var from := ctx.ball.pos
	# A defender four metres along the line and two off it, facing the striker.
	var o: SimPlayer = null
	for id in ctx.opponent_ids(holder.team):
		var q := ctx.players[id]
		if not q.is_keeper and q.on_pitch:
			o = q
			break
	o.pos = from + dir * 4.0 + Vector3(0.0, 0.0, 2.0)
	o.vel = Vector3.ZERO
	o.facing = atan2(-dir.z, -dir.x)
	o.recovery_ticks = 0
	SimPerception.update(ctx)
	var read := SimDuel.block_chance(ctx, o, holder, from, dir, 22.0, 0.0, 0.0, 0.45)
	var unread := SimDuel.block_chance(ctx, o, holder, from, dir, 22.0, 0.0, 0.0, 0.0)
	check_greater(read, unread + 0.05, "a body two metres off the line gets there on the backlift and not off a first-time strike")
	# Priced and thrown from the same window: the survival `expected_goals`
	# charges for a wound-up shot is lower than for a first-time one.
	var aim := Vector3(ctx.pitch.target_goal(holder.team).x, 0.9, 0.0)
	var wound := SimDuel.block_survival(ctx, holder, from, aim, 22.0, 0.45)
	var instant := SimDuel.block_survival(ctx, holder, from, aim, 22.0, 0.0)
	check_less(wound, instant, "and the price reads the same window")
	# The lane: the same man a metre off a pass's line, with and without the head start.
	o.pos = from + dir * 6.0 + Vector3(0.0, 0.0, 1.6)
	var to := from + dir * 20.0
	var length := 20.0
	var with_start := SimDecision._cut_chance(ctx, holder, o, o.pos, from, dir, length, length - 2.0, 1.4, 0.0, 0.3)
	var without := SimDecision._cut_chance(ctx, holder, o, o.pos, from, dir, length, length - 2.0, 1.4, 0.0, 0.0)
	check_greater(with_start, without, "the lane charges the wind-up as the defender's head start")
