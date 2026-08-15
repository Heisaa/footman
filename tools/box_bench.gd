class_name BoxBench
extends RefCounted
## `./run.sh box` — the one-on-one, in a set geometry nobody had to reach.
##
## The owner watches the box and sees the striker shoot early or turn the ball
## back. A match cannot answer whether that is the scoring or the scarcity: at
## current squad quality a diagnose run produces zero to three box touches, so
## the situation the complaint is about occurs a handful of times an hour and
## every measurement of it is noise. Same reasoning as `./run.sh behind` — set
## the situation instead of sampling it, ask the engine's own candidate list
## through `SimDecision.options_for`, and the row is a property of the rule.
##
## The grid is a striker running at goal with the ball, a keeper somewhere off
## his line, a defender recovering behind, and a teammate square at the far
## post. One question per row: **what does he do here, and what did each answer
## score?** The bench does not know the right answer and does not assert one.
## The verdict column names the best-scoring option; the owner says whether
## that is football.
##
## It runs at the standard compressed clock on purpose: `shot_appetite` is part
## of what decides this, and a bench that turned it off would be describing a
## match nobody watches.

## Striker distance from goal, in metres.
const STRIKER_FROM := [16.0, 11.0, 7.0]
## Keeper off his line, in metres. Half a metre is a keeper set; nine is one
## who has committed to closing down.
const KEEPER_OUT := [0.5, 5.0, 9.0]
## The recovering defender's gap behind the striker: on his shoulder, and gone.
const TRAILING := [3.0, 30.0]
## How fast the striker is running at goal.
const STRIKER_PACE := 6.0
## Where the square teammate stands: lateral of the striker, and a touch deeper.
const SQUARE_ACROSS := 9.0
const SQUARE_BACK := 1.0
## Everyone with nothing to do in the drill goes here. Upfield of the play so
## nobody accidentally becomes the offside line or a body in a lane.
const PARKED_Z := 31.0

const _STRIKER := 9
const _SQUARE := 10


static func run(flags: Dictionary) -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = int(flags.get("seed", 7))
	opts.minutes = 1.0
	var ctx := SimRunner.build(opts).ctx
	print("The one-on-one, in a set geometry  (standard clock, so the appetite is on)")
	print("  a striker at pace with the ball, a keeper off his line, a man recovering behind")
	print("  %-8s %-7s %-9s | %8s %8s %8s %8s %8s  %s" % [
		"striker", "keeper", "trailing", "drive", "chip", "carry", "square", "hold", "best"])
	for from in STRIKER_FROM:
		for out in KEEPER_OUT:
			for trail in TRAILING:
				print("  " + _one(ctx, from, out, trail))
	print("  every column is the option's full score in goal probability; `carry` is the")
	print("  best goal-ward dribble, `square` the best ball to the far-post man")


static func _one(ctx: SimContext, from_goal: float, keeper_out: float, trail: float) -> String:
	var team := SimConsts.TEAM_HOME
	var dir := ctx.pitch.attack_dir(team)
	_place(ctx, team, from_goal, keeper_out, trail, dir)
	SimOffBall.reset()
	ctx.tick_index = 0

	var striker := ctx.players[_STRIKER]
	var goal := ctx.pitch.target_goal(team)
	var to_goal := SimConsts.horizontal(goal - striker.pos).normalized()
	# `options_for` generates without picking, so nothing has scored the list
	# yet. Scored here exactly as `_score_all` does it: everything through
	# `score_of`, and the hold against the best of the rest.
	var cands := SimDecision.options_for(ctx, striker)
	var scores := PackedFloat32Array()
	scores.resize(cands.size())
	var best_other := -INF
	var best_other_i := -1
	for i in cands.size():
		if int(cands[i]["action"]) == SimDecision.Action.HOLD:
			continue
		scores[i] = SimDecision.score_of(ctx, striker, cands[i])
		if scores[i] > best_other:
			best_other = scores[i]
			best_other_i = i
	for i in cands.size():
		if int(cands[i]["action"]) == SimDecision.Action.HOLD:
			scores[i] = SimDecision._hold_score(ctx, striker, cands[i], best_other_i)
	var best_kind := "-"
	var best_score := -INF
	var drive := -INF
	var chip := -INF
	var carry := -INF
	var square := -INF
	var hold := -INF
	for i in cands.size():
		var c: Dictionary = cands[i]
		var score := scores[i]
		var kind := int(c["action"])
		var name := "?"
		match kind:
			SimDecision.Action.SHOOT:
				if bool(c.get("chip", false)):
					name = "chip"
					chip = maxf(chip, score)
				else:
					name = "drive"
					drive = maxf(drive, score)
			SimDecision.Action.DRIBBLE:
				var d: Vector3 = c.get("dir", Vector3.ZERO)
				name = "carry"
				if d.dot(to_goal) > 0.5:
					carry = maxf(carry, score)
			SimDecision.Action.HOLD:
				name = "hold"
				hold = maxf(hold, score)
			SimDecision.Action.GROUND_PASS:
				name = "pass"
				if int(c.get("target", -1)) == _SQUARE:
					square = maxf(square, score)
					name = "square"
			_:
				name = SimDebug.ACTION_NAMES[kind]
		if score > best_score:
			best_score = score
			best_kind = name
	return "%-8s %-7s %-9s | %8s %8s %8s %8s %8s  %s" % [
		"%.0f m" % from_goal, "%.1f m" % keeper_out,
		"%.0f m" % trail if trail < 20.0 else "gone",
		_fmt(drive), _fmt(chip), _fmt(carry), _fmt(square), _fmt(hold),
		best_kind]


static func _fmt(v: float) -> String:
	return "   -" if is_inf(v) else "%7.3f" % v


static func _place(ctx: SimContext, team: int, from_goal: float, keeper_out: float,
		trail: float, dir: float) -> void:
	var goal_x := ctx.pitch.half_length * dir
	var parked := 0
	for p in ctx.players:
		p.on_pitch = true
		p.vel = Vector3.ZERO
		p.recovery_ticks = 0
		p.touch_cooldown = 0.0
		if p.is_keeper:
			if p.team == team:
				p.pos = Vector3(-(ctx.pitch.half_length - 0.5) * dir, 0.0, 0.0)
			else:
				p.pos = Vector3((ctx.pitch.half_length - keeper_out) * dir, 0.0, 0.0)
			continue
		# Everybody parks behind the play and wide until given a job.
		p.pos = Vector3((ctx.pitch.half_length * 0.1) * -dir, 0.0,
			PARKED_Z * (1.0 if parked % 2 == 0 else -1.0))
		parked += 1

	var striker := ctx.players[_STRIKER]
	striker.pos = Vector3((ctx.pitch.half_length - from_goal) * dir - dir * 0.0, 0.0, 0.0)
	striker.pos.x = goal_x - dir * from_goal
	striker.vel = Vector3(dir * STRIKER_PACE, 0.0, 0.0)
	striker.facing = 0.0 if dir > 0.0 else PI

	var mate := ctx.players[_SQUARE]
	mate.pos = Vector3(striker.pos.x - dir * SQUARE_BACK, 0.0, SQUARE_ACROSS)
	mate.facing = striker.facing

	# The recovering defender, behind the striker on the goal side of nobody.
	var placed := false
	for p in ctx.players:
		if p.team == team or p.is_keeper or placed:
			continue
		p.pos = striker.pos - Vector3(dir * trail, 0.0, 0.6)
		p.vel = Vector3(dir * STRIKER_PACE * 0.9, 0.0, 0.0) if trail < 20.0 else Vector3.ZERO
		placed = true

	# The ball at the striker's feet, and his to play.
	ctx.ball.reset(striker.pos + Vector3(dir * 0.8, SimConsts.BALL_RADIUS, 0.0))
	ctx.ball.last_touch_player = striker.id
	ctx.ball.last_touch_team = team
	ctx.ball.last_touch_tick = 0
