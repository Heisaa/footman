class_name TestStepIn
extends SimTestCase
## The step-in (`SimMovement.step_in_weight`): the mechanism, not the match.
##
## A defender who has arrived goal-side of a carrier meets him when the
## carrier runs at him, waits when he does not, and waits as the last man.


func run() -> void:
	_runs_at_him_and_is_met()


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


## The carrier on the ball 20 m from their goal, one of theirs 3 m goal-side
## of him, a second one level with the first and `cover_z` wide of him, and
## everybody else out of the way.
static func _place(ctx: SimContext, holder: SimPlayer, defender: SimPlayer, cover: SimPlayer,
		carrier_pace: float, cover_z: float) -> void:
	var dir := ctx.pitch.attack_dir(holder.team)
	var at := Vector3((ctx.pitch.half_length - 20.0) * dir, 0.0, 0.0)
	ctx.ball.reset(Vector3(at.x, SimConsts.BALL_RADIUS, at.z))
	ctx.ball.last_touch_player = holder.id
	ctx.ball.last_touch_team = holder.team
	holder.pos = at + Vector3(-0.4 * dir, 0.0, 0.0)
	holder.vel = Vector3(carrier_pace * dir, 0.0, 0.0)
	holder.facing = 0.0 if dir > 0.0 else PI
	var far_z := ctx.pitch.half_width - 2.0
	for p in ctx.players:
		if p.id == holder.id or not p.on_pitch:
			continue
		p.vel = Vector3.ZERO
		p.recovery_ticks = 0
		if p.id == defender.id:
			p.pos = at + Vector3(3.0 * dir, 0.0, 0.0)
		elif p.id == cover.id:
			p.pos = at + Vector3(3.0 * dir, 0.0, cover_z)
		elif p.is_keeper and p.team != holder.team:
			p.pos = Vector3((ctx.pitch.half_length - 1.0) * dir, 0.0, 0.0)
		else:
			p.pos = Vector3(-40.0 * dir, 0.0, far_z if p.id % 2 == 0 else -far_z)
	ctx.update_pressure()
	ctx.update_possession()


func _runs_at_him_and_is_met() -> void:
	var m := _settled_match()
	var ctx := m.ctx
	check(ctx.possession_player >= 0, "the match reached an uncontested holder")
	if ctx.possession_player < 0:
		return
	var holder := ctx.players[ctx.possession_player]
	var theirs: Array[SimPlayer] = []
	for id in ctx.teammate_ids(SimConsts.other_team(holder.team)):
		var q := ctx.players[id]
		if not q.is_keeper and q.on_pitch:
			theirs.append(q)
	var defender := theirs[0]
	var cover := theirs[1]

	_place(ctx, holder, defender, cover, 3.5, 5.0)
	var at := ctx.ball.ground_pos()
	check_greater(SimMovement._jockey_weight(ctx, defender, holder, at), 0.5,
		"the defender 3 m goal-side has arrived")
	check_greater(SimMovement.step_in_weight(ctx, defender, holder, at), 0.9,
		"a carrier running at him at 3.5 m/s with cover level is met")

	check_less(SimMovement.step_in_go(ctx, defender, holder, at), 0.01,
		"but the roll waits while the ball is under his sole")
	ctx.ball.pos.x += 0.6 * ctx.pitch.attack_dir(holder.team)
	at = ctx.ball.ground_pos()
	check_greater(SimMovement.step_in_go(ctx, defender, holder, at), 0.9,
		"and goes when the touch pushes it a control range off his foot")

	_place(ctx, holder, defender, cover, 0.0, 5.0)
	check_equal(SimMovement.step_in_weight(ctx, defender, holder, ctx.ball.ground_pos()), 0.0,
		"a carrier standing still is stood off")

	_place(ctx, holder, defender, cover, 6.0, 5.0)
	check_equal(SimMovement.step_in_weight(ctx, defender, holder, ctx.ball.ground_pos()), 0.0,
		"a carrier sprinting at him is not stepped in on; he retreats")

	_place(ctx, holder, defender, cover, 3.5, 40.0)
	check_equal(SimMovement.step_in_weight(ctx, defender, holder, ctx.ball.ground_pos()), 0.0,
		"the last man, nobody near enough to cover, delays")
