class_name TestTempo
extends SimTestCase
## The possession's phase (`SimTempo`): the mechanism, not the match.
##
## Each check places the ball and the men and asks for the transition the
## situation causes. A whole-match figure -- seconds a touch by phase -- is
## `diagnose`'s `The tempo` block, and asserting one here would fail for
## whatever moved last.


func run() -> void:
	_the_phase_follows_the_ball_and_the_lines()
	_the_readers_move_together()


## A match a few seconds in, with an uncontested holder.
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


## Puts the holder on the ball at `x` metres up the pitch (his own attacking
## frame), the opponents' midfield trio at `mid`, their back line at `back`,
## and everybody else out of the way. Then refreshes what the phase reads.
static func _place(ctx: SimContext, holder: SimPlayer, x: float, mid: float, back: float) -> void:
	var dir := ctx.pitch.attack_dir(holder.team)
	var at := Vector3(x * dir, 0.0, 0.0)
	ctx.ball.reset(Vector3(at.x, SimConsts.BALL_RADIUS, at.z))
	ctx.ball.last_touch_player = holder.id
	ctx.ball.last_touch_team = holder.team
	holder.pos = at + Vector3(-0.6 * dir, 0.0, 0.0)
	holder.vel = Vector3.ZERO
	var far_z := ctx.pitch.half_width - 2.0
	for p in ctx.players:
		if p.id == holder.id or not p.on_pitch:
			continue
		p.vel = Vector3.ZERO
		if p.team == holder.team:
			p.pos = Vector3(-30.0 * dir, 0.0, far_z if p.id % 2 == 0 else -far_z)
			continue
		if p.is_keeper:
			p.pos = Vector3((ctx.pitch.half_length - 1.0) * dir, 0.0, 0.0)
		elif p.role == SimRole.DM or p.role == SimRole.CM or p.role == SimRole.AM:
			p.pos = Vector3(mid * dir, 0.0, far_z if p.id % 2 == 0 else -far_z)
		elif SimRole.is_defensive(p.role):
			p.pos = Vector3(back * dir, 0.0, far_z if p.id % 2 == 0 else -far_z)
		else:
			p.pos = Vector3(-45.0 * dir, 0.0, far_z if p.id % 2 == 0 else -far_z)
	ctx.update_pressure()
	ctx.update_possession()
	SimTempo.advance(ctx)


func _the_phase_follows_the_ball_and_the_lines() -> void:
	var m := _settled_match()
	var ctx := m.ctx
	check(ctx.possession_player >= 0, "the match reached an uncontested holder")
	if ctx.possession_player < 0:
		return
	var holder := ctx.players[ctx.possession_player]
	var team := holder.team
	var third := ctx.pitch.half_length / 3.0

	_place(ctx, holder, -third - 12.0, 5.0, 25.0)
	check_equal(SimTempo.phase_of(ctx, team), SimTempo.SETTLE, "a free man deep in his own third settles")

	_place(ctx, holder, -third + 2.0, 5.0, 25.0)
	check_equal(SimTempo.phase_of(ctx, team), SimTempo.SETTLE, "and a ball just over the line keeps settling: the margin is hysteresis")

	_place(ctx, holder, -third + 12.0, 5.0, 25.0)
	check_equal(SimTempo.phase_of(ctx, team), SimTempo.PROBE, "worked out of the third, the side probes")

	_place(ctx, holder, 15.0, 5.0, 25.0)
	check(SimTempo.between_the_lines(ctx, holder), "a man ten metres past their midfield and ten short of their line is between them")
	check_equal(SimTempo.phase_of(ctx, team), SimTempo.ATTACK, "and a free man between the lines is the attack")

	_place(ctx, holder, 3.0, 5.0, 25.0)
	check_equal(SimTempo.phase_of(ctx, team), SimTempo.ATTACK, "the ball behind their midfield by less than the margin stays an attack")

	_place(ctx, holder, -8.0, 5.0, 25.0)
	check_equal(SimTempo.phase_of(ctx, team), SimTempo.PROBE, "played back behind their midfield with room, it is a probe again")

	_place(ctx, holder, third + 5.0, -10.0, 8.0)
	check_equal(SimTempo.phase_of(ctx, team), SimTempo.ATTACK, "the ball in the final third is the attack whatever the lines")

	# The keeper's ball is deep and unpressed, and never between the lines.
	var keeper: SimPlayer = null
	for pid in ctx.team_players[team]:
		if ctx.players[pid].is_keeper:
			keeper = ctx.players[pid]
	if keeper != null:
		_place(ctx, keeper, -ctx.pitch.half_length + 8.0, 5.0, 25.0)
		check_equal(SimTempo.phase_of(ctx, team), SimTempo.SETTLE, "the keeper with it is a settle")


func _the_readers_move_together() -> void:
	var m := _settled_match()
	var ctx := m.ctx
	if ctx.possession_player < 0:
		return
	var holder := ctx.players[ctx.possession_player]
	var team := holder.team
	var plan := ctx.tactics(team)
	var third := ctx.pitch.half_length / 3.0

	_place(ctx, holder, -third - 12.0, 5.0, 25.0)
	var settle_tempo := SimTempo.tempo_of(ctx, team)
	var settle_scan := SimTempo.scan_scale(ctx, team)
	var settle_long := SimTempo.length_scale(ctx, team, 40.0)
	_place(ctx, holder, 15.0, 5.0, 25.0)
	var attack_tempo := SimTempo.tempo_of(ctx, team)
	var attack_scan := SimTempo.scan_scale(ctx, team)
	check_less(settle_tempo, plan.tempo, "a settling side plays under the plan's tempo")
	check_greater(attack_tempo, plan.tempo, "an attacking side plays over it")
	check_less(plan.discount_at(attack_tempo), plan.discount_at(settle_tempo),
		"so the attack discounts the future harder and releases sooner")
	check_greater(settle_scan, attack_scan, "the dwell is worth more settling than attacking")
	check_less(settle_long, 1.0, "and a settling side taxes the long ball")
	check_less(float(SimOffBall.SETTLE_QUOTA[SimOffBall.BEHIND]), float(SimOffBall.QUOTA[SimOffBall.BEHIND]),
		"and sends fewer men in behind")
