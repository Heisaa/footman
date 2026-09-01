class_name BehindBench
extends RefCounted
## `./run.sh behind` — the ball in behind, struck in a geometry nobody had to
## reach.
##
## `./run.sh diagnose` measures the same pass over a match, and it cannot answer
## the question the eye asks. A match mixes the aim rule with the whole of the
## selection above it: change the weight a through ball is hit at and the softmax
## plays a different set of them, so the mean length moves for two reasons at once
## and neither is separable from the other. That is fine for "how much of this is
## happening" and useless for "is this ball hit right".
##
## So this sets the situation instead of sampling it. A passer, a runner, a flat
## back four and a keeper, at distances chosen rather than found, and one question
## per row: **the ball the engine would play here — can the man it is for get to
## it?** No match runs, no tick advances, nothing is random. The same geometry
## gives the same row on every build, so the row is a property of the rule.
##
## Read two columns and the verdict:
##
##   `arrives` is the ball's speed as it reaches the aim point. Above the runner's
##   top speed it is a ball nobody catches, however clear his run.
##   `ahead` against `covers` is where it was aimed against how far he can get
##   while it travels. Over is a ball played to a yard he never reaches.
##
## The bench does not know what the right answer is and does not assert one. It
## prints the ball; the owner says whether that is a through ball.

## The distances the grid is built from, all measured off the defensive line so a
## row reads as football rather than as pitch coordinates.
##
## `PASSER_BACK` is how far behind the last defender the man on the ball stands:
## 16 m is a midfielder at the top of the D's worth of build-up, 34 m is a centre
## back looking for the striker's run.
const PASSER_BACK := [16.0, 24.0, 32.0]
## How fast the runner is already going when the ball is struck. Standing, moving,
## and at a sprint — the three cases the aim rule treats differently, because a
## committed run is aimed at where he is going and everyone else is aimed at a
## projection.
const RUNNER_PACE := [0.0, 3.0, 6.5]
## How far off the shoulder he starts, toward his own goal. Onside by a metre,
## which is where a run in behind begins.
const RUNNER_ONSIDE := 1.0
## Where the defensive line sits, as a distance from the goal it is defending. 30 m
## is a side holding a high line just outside its own box.
const LINE_FROM_GOAL := 30.0
## The four of them, across the pitch.
const BACK_FOUR_Z := [-14.0, -5.0, 5.0, 14.0]
## Everyone with nothing to do in this drill goes here, wide of the touchline and
## upfield of the back four. Upfield matters: the offside line is the *second*
## deepest opponent, so a spare defender parked behind the four would quietly
## become the line and every run below would start offside.
const PARKED_Z := 31.0


static func run(flags: Dictionary) -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = int(flags.get("seed", 7))
	opts.minutes = 1.0
	var ctx := SimRunner.build(opts).ctx
	print("The ball in behind, in a set geometry  (no match, nothing random)")
	print("  a flat back four %.0f m off their own goal, the runner %.0f m onside of it" % [
		LINE_FROM_GOAL, RUNNER_ONSIDE])
	print("  %-9s %8s %9s %8s %8s %8s %8s %9s %10s  %s" % [
		"passer", "his pace", "run", "aimed", "ahead", "struck", "flight",
		"arrives", "he covers", "verdict"])
	for back in PASSER_BACK:
		for pace in RUNNER_PACE:
			print("  " + _one(ctx, back, pace))
	print("  `run` is committed when the off-ball layer has him on a timed run in")
	print("  behind, and projected when the aim is a guess made in its absence")


## One geometry, set up and asked. Returns the printed row.
static func _one(ctx: SimContext, back: float, pace: float) -> String:
	var team := SimConsts.TEAM_HOME
	var dir := ctx.pitch.attack_dir(team)
	# Depths are measured toward the goal this side is attacking, then turned back
	# into pitch coordinates once, here.
	var line_depth := ctx.pitch.half_length - LINE_FROM_GOAL
	var passer := _place(ctx, team, back, pace, line_depth, dir)
	SimOffBall.reset()
	ctx.tick_index = 0
	SimOffBall.update(ctx)

	var runner := ctx.players[_RUNNER]
	var committed := SimOffBall.is_running_in_behind(ctx, runner)
	# Zeroed so the tally below reads this row alone. It is the engine's own count
	# of which gate refused a man making the run, and it is the only way a "no ball
	# was offered" row can name a cause instead of leaving one to be guessed at.
	SimDecision.behind_gate.resize(SimDecision.BEHIND_GATES.size())
	SimDecision.behind_gate.fill(0.0)
	var best := {}
	for c in SimDecision.options_for(ctx, passer):
		if int(c["action"]) != SimDecision.Action.THROUGH_BALL:
			continue
		if best.is_empty() or float(c["score"]) > float(best["score"]):
			best = c
	if best.is_empty():
		return "%-9s %7.0f m/s %9s  %s" % [
			"%.0f m" % back, pace, "committed" if committed else "projected",
			"none offered — " + _refused(committed)]

	var aim: Vector3 = best["point"]
	var length := SimConsts.horizontal_length(aim - passer.pos)
	var ahead := SimConsts.horizontal_length(aim - runner.pos)
	# The strike the touch layer will make from this candidate, solved the same
	# way it solves it: the scored pace is the pace it is hit at.
	var struck := ctx.ballistics.ground_pass_speed(length, float(best["pace"]), ctx.env)
	var flight := ctx.ballistics.ground_travel_time(length, struck, ctx.env)
	var arrives := ctx.ballistics.ground_pace_after(struck, length, ctx.env)
	var covers := SimValueField.reach_in(runner, aim - runner.pos, flight)

	var verdict := "he gets there with %.1f m to spare" % (covers - ahead)
	if ahead > covers:
		verdict = "short by %.1f m" % (ahead - covers)
		if arrives > runner.max_speed():
			verdict += ", arriving at %.1f m/s against his %.1f" % [arrives, runner.max_speed()]
	elif arrives > runner.max_speed():
		# Only a fault for a ball he has to chase; a man already on the spot
		# takes a firm ball like any pass to feet.
		verdict = "there first, met by a ball at %.1f m/s" % arrives
	return "%-9s %7.0f m/s %9s %6.1f m %6.1f m %6.1f m/s %6.2f s %7.1f m/s %8.1f m  %s" % [
		"%.0f m" % back, pace, "committed" if committed else "projected",
		length, ahead, struck, flight, arrives, covers, verdict]


## Which gate turned the ball down, in the engine's own words. More than one man
## can be in the population — the parked teammates are still teammates — so it
## names every gate that fired rather than asserting there was one.
##
## The empty case is not a missing answer, it is a fact about the instrument.
## `_open_behind_gates` opens the population on `is_running_in_behind`, so the
## tally — and `A man was running in behind` in `./run.sh diagnose`, which is the
## same tally — **only ever sees men the off-ball layer has committed to a run.**
## Every `projected` row here is invisible to it, and so is every projected ball in
## a match. That is the branch this thread found aiming a flat 12.6 m ahead.
static func _refused(committed: bool) -> String:
	var parts := PackedStringArray()
	for i in SimDecision.behind_gate.size():
		if SimDecision.behind_gate[i] > 0.0 and i != SimDecision.BEHIND_OFFERED:
			parts.append("%s x%d" % [SimDecision.BEHIND_GATES[i], int(SimDecision.behind_gate[i])])
	if not parts.is_empty():
		return ", ".join(parts)
	if committed:
		return "nobody was making a run"
	return "no committed run, so the gate tally never saw him"


## The striker, and the midfielder who plays it. Fixed ids so the drill reads the
## same man every row; the squad is generated from a seed but the roles are not.
const _RUNNER := 9
const _PASSER := 6


## Puts both sides where the row wants them and leaves everyone else out of it.
static func _place(ctx: SimContext, team: int, back: float, pace: float,
		line_depth: float, dir: float) -> SimPlayer:
	var parked := 0
	for p in ctx.players:
		p.on_pitch = true
		p.vel = Vector3.ZERO
		if p.is_keeper:
			p.pos = Vector3((ctx.pitch.half_length - 0.5) * (dir if p.team != team else -dir), 0.0, 0.0)
			continue
		if p.team != team:
			continue
		# The passing side, apart from the two who matter, out of the way. Behind
		# the ball and wide, so they are neither an option nor a body in the lane.
		p.pos = Vector3((line_depth - back - 12.0) * dir, 0.0,
			PARKED_Z * (1.0 if parked % 2 == 0 else -1.0))
		parked += 1

	# The back four across the line, and the rest of the defending side upfield of
	# it and wide. See `PARKED_Z`.
	var four := 0
	for p in ctx.players:
		if p.team == team or p.is_keeper:
			continue
		if four < BACK_FOUR_Z.size():
			p.pos = Vector3(line_depth * dir, 0.0, BACK_FOUR_Z[four])
			four += 1
			continue
		p.pos = Vector3((line_depth - back - 6.0) * dir, 0.0,
			PARKED_Z * (1.0 if four % 2 == 0 else -1.0))
		four += 1

	var runner := ctx.players[_RUNNER]
	runner.pos = Vector3((line_depth - RUNNER_ONSIDE) * dir, 0.0, 0.0)
	runner.vel = Vector3(dir * pace, 0.0, 0.0)
	runner.facing = 0.0 if dir > 0.0 else PI

	var passer := ctx.players[_PASSER]
	passer.pos = Vector3((line_depth - back) * dir, 0.0, 0.0)
	passer.vel = Vector3.ZERO
	passer.facing = 0.0 if dir > 0.0 else PI
	ctx.ball.reset(passer.pos + Vector3(dir * 0.4, 0.0, 0.0))
	ctx.ball.last_touch_player = passer.id
	ctx.ball.last_touch_team = team
	ctx.possession_team = team
	ctx.possession_player = passer.id
	ctx.in_play = true
	return passer
