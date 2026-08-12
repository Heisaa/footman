class_name SimDecision
extends RefCounted
## On-ball decision making (PLAN.md §4.2).
##
## Candidates are generated, each is scored as
##   success x gain - (1 - success) x risk_weight x loss
## and one is chosen by softmax, never by argmax. Deterministic argmax selection
## is the most common way this kind of engine ends up feeling robotic; the
## temperature falls with the decisions attribute, so better decision-makers
## more often pick the genuinely best option and weaker ones make
## plausible-but-wrong choices.
##
## All values are in goal-probability units, so expected threat, expected goals
## and the counter-attacking threat conceded on a turnover are directly
## comparable.

enum Action { HOLD, DRIBBLE, GROUND_PASS, LOFTED_PASS, THROUGH_BALL, CROSS, SHOOT, CLEAR }

## Softmax temperature bounds, as a fraction of the spread of candidate scores.
## Low temperature means near-optimal play.
const TEMP_POOR := 0.55
const TEMP_GOOD := 0.11
## Dribble probe directions, in the canonical attacking frame.
const DRIBBLE_DIRS := 8
const DRIBBLE_DISTANCE := 4.5
## How far a dribbler knocks it when he is running away from a challenge rather
## than carrying it. Long enough that the man on his back has to win a foot race
## for it instead of reaching round him for it.
const BURST_DISTANCE := 9.0
## How far in front of himself a carrier puts the ball, in seconds of his own
## running. `SimTouch.dribble` has claimed since it was written that the touch is
## "matched to stride", and nothing in it ever was: the size came off the room and
## the score and never once off the speed of the man playing it.
##
## Measured on seed 7, that is the whole of the complaint that the ball gets away
## from them. A carry pushed it 2.3 m in front while the carrier was travelling at
## about 2.9 m/s -- the ball leaves his foot at 5.3 -- so a jogging player struck
## every touch as though he were sprinting onto it, and then had to sprint onto
## it. A footballer's touch is about half a second of his own running ahead, and
## that is a *rate*: it is what makes a man at full pace push it four metres and
## the same man shifting it inside his own body length keep it under his sole,
## from one rule rather than two.
##
## It bootstraps rather than locking, which is the thing to watch. A standing
## player gets the floor, the floor is enough of a gap for `SimMovement` to pace
## him at it, and the touch after that is bigger because he is quicker. That is
## also how a footballer starts a run.
const TOUCH_SECONDS := 0.55
## The same measure for the knock past a man, which is deliberately further than
## his stride -- that is what makes it a foot race rather than a carry -- and the
## pace below which it is not a foot race at all. A jogger who launches it nine
## metres has not beaten anybody, he has given it away.
const BURST_SECONDS := 1.2
const BURST_PACE := 3.5
## How far in front of himself a man puts the ball when he is not trying to go
## anywhere with it. The smallest touch the engine has: `SimTouch.dribble`'s own
## floor, a ball kept inside the width of his own stride.
##
## It is the size that makes the hold the option it was scored as. See
## `_play_hold` -- and note that it is a *rate* only for the carry, deliberately
## not here. A hold does not grow with his pace, because a man who wants the ball
## to stay where it is does not push it further for running faster.
const HOLD_AHEAD := SimTouch.DRIBBLE_AHEAD_FLOOR
## Where a touch stops being a way of covering ground and starts being a way of
## setting yourself: the distance from the goal at which touches begin to shorten,
## and the size they shorten to on top of it.
const CLOSE_CONTROL_FAR := 22.0
const CLOSE_CONTROL_NEAR := 6.0
const CLOSE_CONTROL_TOUCH := 1.6
## Logistic width, in seconds, on the race between carrier and challenger for a
## dribble's landing point. Tighter than the pitch-control equivalent because
## this is one race between two known men, not a field-wide average.
const ESCAPE_TAU := 0.30
## How long after winning the ball back the priority is still to secure it
## rather than to advance it, in seconds.
const REGAIN_WINDOW := 2.0
## Where a pass stops being a thing you can play along the grass.
##
## These two numbers, and the lofted pass's own threshold, are the whole of the
## rule that a longer ball is a higher ball. Below the lofted threshold the only
## pass on offer is along the ground; between it and the ground limit both are
## generated and the softmax chooses; past the ground limit the ball in the air
## is the only pass there is. Nothing weights one against the other by distance —
## the share of passes that are lofted rises with length because that is which
## options exist, which is also how it works on a pitch.
##
## Thirty-two metres is already a driven ball rather than a pass, and the ground
## limit sat at thirty-eight, which is a ball nobody hits along the floor. Past
## the lofted limit it is not a pass at all, it is a clearance, and `_add_clear`
## is where those live.
const LOFTED_FROM := 24.0
const MAX_GROUND_PASS := 32.0
const MAX_LOFTED_PASS := 45.0
## How much grass a touch has to leave between the ball and the line. A ball
## that stops exactly on the paint is a ball nobody can do anything with.
const LINE_MARGIN := 1.2
## Standing penalties on the two passes that flatter themselves: they look
## valuable because they end up further forward, and they are much harder than
## the value function alone admits.
const THROUGH_BALL_BIAS := 0.55
const LOFTED_BIAS := 0.30
## How many teammates get fully scored as pass targets.
##
## Scoring a pass properly costs a pitch-control evaluation, an interception
## sweep and an execution-accuracy estimate, so doing it for all ten teammates
## times three pass kinds is most of the cost of the whole engine. A cheap
## pre-filter over values already computed this tick throws away the options
## nobody was ever going to take, and the softmax cannot tell the difference.
const MAX_PASS_TARGETS := 6
## The nearest teammates are always considered whatever the filter thinks, so a
## player under pressure never loses their safe ball.
const ALWAYS_KEEP_NEAREST := 2

## Scratch candidate list, reused so the decision path allocates as little as
## possible. Candidates are dictionaries; there are rarely more than 30.
static var _candidates: Array[Dictionary] = []
static var _weights := PackedFloat32Array()
static var _aim_weights := PackedFloat32Array()

## What the last softmax did, for the debug sink alone. Three stores per
## decision, read by nothing in the simulation: `SimDebug` is a one-way tap and
## the pick itself has already happened by the time these are looked at.
static var _last_pick := -1
static var _last_temp := 0.0
static var _last_spread := 0.0


## Called when `player` is in contact with the ball and may act.
static func choose_and_execute(ctx: SimContext, player: SimPlayer) -> void:
	if player.is_keeper:
		SimKeeper.decide_with_ball(ctx, player)
		return

	_candidates.clear()
	var incoming := ctx.ball.vel.length()
	var uncontrolled := incoming > 5.0 and ctx.ball.last_touch_player != player.id
	# Both are situational facts about this moment rather than about any one
	# candidate, so they are established once and handed down: who is coming to
	# take the ball off him, and whether he has only just won it.
	var challenger := ctx.nearest_challenger(player)
	var regain := regain_urgency(ctx, player)

	_add_shot(ctx, player, uncontrolled)
	_add_passes(ctx, player, uncontrolled, regain)
	_add_dribbles(ctx, player, uncontrolled, challenger, regain)
	_add_hold(ctx, player, uncontrolled, regain)
	_add_clear(ctx, player)

	if _candidates.is_empty():
		SimTouch.first_touch(ctx, player, ctx.pitch.target_goal(player.team) - player.pos)
		return

	var chosen := _softmax_pick(ctx, player)
	if SimDebug.enabled:
		SimDebug.capture_decision(
			ctx, player, _candidates, _last_pick, _weights, _last_temp, _last_spread, regain
		)
	_execute(ctx, player, chosen, uncontrolled)


# --- Candidate generation ---------------------------------------------------


static func _add_shot(ctx: SimContext, player: SimPlayer, first_time: bool) -> void:
	var goal := ctx.pitch.target_goal(player.team)
	var from := ctx.ball.pos
	var distance := SimConsts.horizontal_length(goal - from)
	if distance > 38.0:
		return
	var aim := _pick_shot_aim(ctx, player, goal)
	var quality := expected_goals(ctx, player, from, aim)
	# Not every sight of goal is a shot, and the floor is here to keep a hopeless
	# attempt out of the softmax rather than to decide anything: a candidate
	# nobody would ever take still widens the spread of scores, and the spread is
	# what the temperature is measured against.
	#
	# At 0.075 it was doing a quite different job. The calibration in
	# `expected_goals` puts the edge of the box at about 0.09 before pressure and
	# bodies in the way are counted, so a shot from beyond eighteen yards -- or
	# from the edge of it with a man closing -- was not scored badly, it was never
	# generated at all. Whether a shot from twenty-two metres is worth taking is a
	# question the score answers on its own, against a turnover priced at
	# POSSESSION_VALUE plus the threat conceded, and answering it a second time
	# with a gate is how a team ends up with no long shots in it. 0.025 is roughly
	# twenty-five metres for an ordinary player with a clear sight of goal, and
	# less than that for one who has neither.
	if quality < 0.025:
		return
	var tactics := ctx.tactics(player.team)
	# Losing the ball with a shot costs little: the ball ends up deep in the
	# opponent's half either way.
	var loss := ctx.value.xt_at(SimConsts.other_team(player.team), Vector3(goal.x * 0.75, 0.0, 0.0), ctx.pitch)
	_candidates.append({
		"action": Action.SHOOT,
		"aim": aim,
		"success": quality,
		"gain": 1.0,
		"loss": loss,
		"first_time": first_time,
		# A shot is already scored in the same currency as everything else --
		# success times gain, where the success is the chance of scoring and the
		# gain is the goal -- so this multiplier is not the knob for how often the
		# engine shoots. It is what a shot is worth *over and above* the goal it
		# might be: the corner, the rebound, the ball that stays in their half.
		# Somewhere around one, in other words.
		#
		# At a third to two thirds, which is where it was, it was instead a
		# standing tax, and the tax decided the whole of the engine's behaviour in
		# the penalty area. Expected threat peaks at 0.38 near the penalty spot,
		# and a shot from there with a man closing and two bodies in the way is
		# worth about 0.12 once `expected_goals` has counted them -- so carrying
		# the ball in the six-yard box scored better than striking it, every time,
		# and the carry is what got played.
		"bias": lerpf(0.75, 1.25, tactics.directness) * (0.6 if first_time else 1.0),
		"power": clampf(0.5 + distance / 40.0, 0.45, 1.0),
	})


## Picks where in the goal to aim.
##
## Chosen by softmax over the available corners, not by always taking the one
## furthest from the keeper. Always picking the best corner means every shot
## that stays on target is an unsaveable one, and the conversion rate ends up
## three times what football produces. Composure and finishing sharpen the
## choice; a hurried player often just hits it down the middle.
static func _pick_shot_aim(ctx: SimContext, player: SimPlayer, goal: Vector3) -> Vector3:
	var keeper := ctx.teams[SimConsts.other_team(player.team)].keeper()
	var half := ctx.pitch.goal_half_width - 0.5
	var options := [
		Vector3(goal.x, 0.5, -half),
		Vector3(goal.x, 0.5, half),
		Vector3(goal.x, 1.7, -half * 0.8),
		Vector3(goal.x, 1.7, half * 0.8),
		Vector3(goal.x, 0.6, -half * 0.35),
		Vector3(goal.x, 0.6, half * 0.35),
		Vector3(goal.x, 0.5, 0.0),
	]
	if _aim_weights.size() != options.size():
		_aim_weights.resize(options.size())
	var scores := PackedFloat32Array()
	scores.resize(options.size())
	var best := -INF
	for i in options.size():
		var o: Vector3 = options[i]
		var score := 0.0
		if keeper != null:
			score += minf(keeper.dist_to(o), 8.0)
		score += (2.0 - o.y) * 0.6
		scores[i] = score
		best = maxf(best, score)
	# Placement is a skill: a composed finisher discriminates between corners,
	# a panicked one barely does.
	var temperature: float = lerpf(4.0, 0.7, (player.attrs.composure + player.attrs.finishing) * 0.5)
	temperature /= maxf(1.0 + ctx.pressure_on(player) * 0.6, 1.0)
	for i in options.size():
		_aim_weights[i] = exp((scores[i] - best) / maxf(temperature, 0.05))
	var idx: int = ctx.rng.weighted_index(_aim_weights)
	return options[maxi(idx, 0)]


## The engine's own estimate of shot quality. It informs the choice; the actual
## outcome is resolved physically by the flight of the ball and the keeper.
static func expected_goals(ctx: SimContext, player: SimPlayer, from: Vector3, aim: Vector3) -> float:
	var goal := ctx.pitch.target_goal(player.team)
	var dx := absf(goal.x - from.x)
	var dz := absf(from.z)
	var d: float = maxf(sqrt(dx * dx + dz * dz), 1.0)
	var half := ctx.pitch.goal_half_width
	var theta := absf(atan2(half - from.z, maxf(dx, 0.4)) - atan2(-half - from.z, maxf(dx, 0.4)))
	var angle_factor: float = pow(clampf(theta / 1.047, 0.0, 1.0), 0.7)
	# Calibrated against real shot data: about 0.26 from the penalty spot, 0.09
	# from the edge of the box, 0.03 from 25 m. Expected goals and expected
	# threat are compared directly when a player decides whether to shoot, so
	# getting their relative scale wrong means a team that walks it in or a team
	# that shoots from the halfway line.
	var base := 1.35 * exp(-0.11 * d) * angle_factor
	base *= lerpf(0.55, 1.35, player.attrs.finishing)
	base *= lerpf(1.0, 0.35, clampf(ctx.pressure_on(player), 0.0, 1.5) / 1.5)
	base *= lerpf(0.8, 1.05, player.attrs.composure)
	# Bodies in the way.
	var blockers := 0
	for oid in ctx.opponent_ids(player.team):
		var o := ctx.players[oid]
		if o.on_pitch and _near_segment(o.pos, from, aim, 1.1) and o.dist_to(from) > 0.8:
			blockers += 1
	base *= pow(0.72, float(blockers))
	return clampf(base, 0.002, 0.92)


static func _add_passes(ctx: SimContext, player: SimPlayer, uncontrolled: bool, regain: float) -> void:
	var tactics := ctx.tactics(player.team)
	# Straight after a regain the simple ball is worth more than it looks. Only
	# the ground pass is lifted: securing possession means finding a man, not
	# hitting the same forty-metre ball you would have looked for in settled
	# play, so the through ball and the lofted pass keep their standing prices.
	var secure: float = lerpf(1.0, 1.7, regain)
	var from := ctx.ball.pos
	var current_threat := ctx.value.xt_at(player.team, from, ctx.pitch)
	var attack_dir := ctx.pitch.attack_dir(player.team)
	# Nobody plays a measured pass off a ball that is still bouncing. This is
	# what makes a first touch the usual answer to a ball arriving at pace.
	var off_balance: float = 1.0
	if uncontrolled:
		off_balance = lerpf(0.3, 0.7, player.attrs.first_touch * player.attrs.technique)

	for mate_id in _shortlist(ctx, player, from):
		var mate := ctx.players[mate_id]
		var believed := SimPerception.believed_pos(ctx, player, mate)
		var raw_distance := SimConsts.horizontal_length(believed - from)

		# --- Ground pass to feet -------------------------------------------
		if raw_distance <= MAX_GROUND_PASS:
			var pace := arrival_pace(raw_distance, tactics)
			var travel := ctx.ballistics.ground_travel_time(
				raw_distance, ctx.ballistics.ground_pass_speed(raw_distance, pace, ctx.env), ctx.env)
			var lead := _keep_in_play(ctx, _lead_point(ctx, mate, believed, travel))
			# Aiming ahead of a man lengthens the pass, so the flight time it was
			# aimed with is not the flight time it has. One correction is enough,
			# and without it a ball played into a run is judged against a shorter
			# journey than it makes -- which makes the runner look late for a ball
			# that would have reached him.
			var lead_distance := SimConsts.horizontal_length(lead - from)
			travel = ctx.ballistics.ground_travel_time(
				lead_distance, ctx.ballistics.ground_pass_speed(lead_distance, pace, ctx.env), ctx.env)
			# A ball put where a man is going is a ball into space, and arrival
			# there is a race rather than a delivery to a stationary target.
			var into_space := SimConsts.horizontal_length(lead - believed) > 2.0
			var success := _pass_success(ctx, player, from, lead, travel, mate, into_space)
			var gain := ctx.value.xt_at(player.team, lead, ctx.pitch) * tactics.focus_at(lead.z, ctx.pitch)
			gain += _arrival_gain(ctx, player.team, lead, believed, mate, travel)
			_candidates.append({
				"action": Action.GROUND_PASS,
				"target": mate_id,
				"point": lead,
				"success": success * off_balance,
				"gain": maxf(gain, current_threat * 0.85),
				"loss": ctx.value.xt_at(SimConsts.other_team(player.team), lead, ctx.pitch),
				"pace": pace,
				# Football's pass-length distribution is heavily short. Without
				# this the engine plays a Hollywood ball every time.
				"bias": tactics.retention_bias() * (1.0 / (1.0 + raw_distance * 0.21)) * secure
					* _call_bias(ctx, mate) * _give_and_go_bias(ctx, player, mate_id),
			})

		# --- Through ball in behind ----------------------------------------
		# Only worth considering for someone actually running in behind. A
		# through ball to a stationary midfielder is just a bad pass.
		var running_on: float = mate.vel.x * attack_dir
		# Role is the wrong test on its own, and it was the reason a through ball
		# was generated and then never chosen: it asks who is *usually* the man in
		# behind rather than who is going right now. A midfielder timing a run
		# past the last defender is exactly the pass this candidate is for, and
		# `making_run` is the movement layer saying so.
		var runner := SimRole.is_attacking(mate.role) or mate.making_run
		if not mate.is_keeper and raw_distance < 45.0 and running_on > 1.2 and runner:
			var run := Vector3(attack_dir, 0.0, 0.0) * lerpf(7.0, 16.0, tactics.directness)
			var target := _keep_in_play(ctx, believed + run + mate.vel * 0.4)
			# If he has actually committed to going somewhere, that is the ball,
			# and a projection down the pitch is only the guess made in its
			# absence. Aiming at the guess is how a through ball gets played to
			# a yard the runner was never heading for.
			var committed := SimOffBall.destination_for(ctx, mate)
			if SimOffBall.is_running_in_behind(ctx, mate) and not is_inf(committed.x):
				target = _keep_in_play(ctx, committed)
			var t_distance := SimConsts.horizontal_length(target - from)
			if t_distance > 4.0 and t_distance <= MAX_GROUND_PASS + 6.0:
				var t_pace := arrival_pace(t_distance, tactics) * 1.15
				var t_speed := ctx.ballistics.ground_pass_speed(t_distance, t_pace, ctx.env)
				var t_travel := ctx.ballistics.ground_travel_time(t_distance, t_speed, ctx.env)
				# The runner beating everyone there is the whole question, and it
				# is asked once. Asking it twice -- once statically and once in
				# time -- squared a term that is small for every ball worth
				# playing in behind, and no through ball was ever chosen in a
				# match: 274 of them generated on one ten-minute seed, the best
				# at a 0.39 chance of arriving, and not one selected.
				var t_success := _pass_success(ctx, player, from, target, t_travel, mate, true)
				# Offside is judged where the *receiver* stands when the ball is
				# struck, not where it is going -- that is the entire point of a
				# through ball, and testing the target instead flagged every one
				# of them, because a ball played in behind lands in behind by
				# definition. Judged off the passer's belief, so a ball played to
				# a man who has already gone is a mistake he can make.
				if SimReferee.would_be_offside(ctx, player.team, believed):
					t_success *= 0.12
				_candidates.append({
					"action": Action.THROUGH_BALL,
					"target": mate_id,
					"point": target,
					"success": t_success * off_balance,
					"gain": ctx.value.xt_at(player.team, target, ctx.pitch) * tactics.focus_at(target.z, ctx.pitch)
						+ _arrival_gain(ctx, player.team, target, believed, mate, t_travel),
					"loss": ctx.value.xt_at(SimConsts.other_team(player.team), target, ctx.pitch),
					# The pace it was scored at. This was a flat 6.0 while
					# `t_travel` -- and through it `t_success` and the arrival
					# gain -- were computed from `t_pace`, so the ball that got
					# struck was not the ball the race had been judged on. The
					# same mismatch the carry had between its scored touch and
					# its played one, in the other half of the decision layer.
					"pace": t_pace,
					"bias": tactics.direct_bias() * _call_bias(ctx, mate),
				})

		# --- Lofted pass or cross ------------------------------------------
		# A ball in the air is a choice, not a default: only over a distance
		# that a ground pass cannot cover, or into the box.
		var box_target := ctx.pitch.in_opponent_penalty_area(player.team, believed)
		if raw_distance <= MAX_LOFTED_PASS and (raw_distance > LOFTED_FROM or (box_target and raw_distance > 12.0)):
			# Flight time, which is the whole character of a ball in the air: ask
			# for a long one and the solver lobs it, ask for a short one and it
			# drives it.
			#
			# There is a floor under this and it is not a taste question. Below a
			# certain flight time the only way to cover the distance is to strike
			# the ball harder than a person can, and the solver will do it — a
			# 45 m pass asked for in 1.8 s comes out at 37 m/s. Measured against
			# the integrator, the knee where launch speed starts to run away sits
			# at about 0.2 + 0.045 d, and that is what this is. It used to be
			# 0.75 + 0.032 d, a quarter of a second of hang above the knee at
			# every distance a lofted pass is actually played over.
			var flight: float = clampf(0.2 + raw_distance * 0.045, 0.7, 2.25)
			var lofted_target := _keep_in_play(ctx, believed + mate.vel * flight * 0.55)
			lofted_target.y = 0.0
			var lofted_success := _lofted_success(ctx, player, lofted_target, flight, mate)
			var is_cross := ctx.pitch.in_opponent_penalty_area(player.team, lofted_target) and absf(from.z) > ctx.pitch.half_width * 0.45
			_candidates.append({
				"action": Action.CROSS if is_cross else Action.LOFTED_PASS,
				"target": mate_id,
				"point": lofted_target,
				"success": lofted_success * off_balance,
				"gain": ctx.value.xt_at(player.team, lofted_target, ctx.pitch) * tactics.focus_at(lofted_target.z, ctx.pitch) * (1.15 if is_cross else 1.0),
				"loss": ctx.value.xt_at(SimConsts.other_team(player.team), lofted_target, ctx.pitch),
				"flight": flight,
				"bias": tactics.direct_bias() * LOFTED_BIAS * (1.0 / (1.0 + raw_distance * 0.055))
					* SimPatterns.pass_bias(ctx, player, mate_id, lofted_target) * _call_bias(ctx, mate),
			})


## The teammates worth scoring as pass targets, cheaply chosen.
##
## The proxy uses only things already computed this tick -- the cached per-player
## expected threat and a squared distance -- so the filter itself is free.
static var _short_ids := PackedInt32Array()
static var _short_scores := PackedFloat32Array()


static func _shortlist(ctx: SimContext, player: SimPlayer, from: Vector3) -> PackedInt32Array:
	_short_ids.clear()
	_short_scores.clear()
	for mate_id in ctx.teammate_ids(player.team):
		if mate_id == player.id:
			continue
		var mate := ctx.players[mate_id]
		if not mate.on_pitch:
			continue
		var dx := mate.pos.x - from.x
		var dz := mate.pos.z - from.z
		var d2 := dx * dx + dz * dz
		if d2 < 4.0 or d2 > 3600.0:
			continue
		var threat: float = ctx.player_threat[mate_id] if mate_id < ctx.player_threat.size() else 0.0
		# Forward and dangerous, or simply close. Both kinds of option matter.
		var score: float = threat * 3.0 + 1.0 / (1.0 + sqrt(d2) * 0.06)
		var i := 0
		while i < _short_scores.size() and _short_scores[i] >= score:
			i += 1
		_short_ids.insert(i, mate_id)
		_short_scores.insert(i, score)

	if _short_ids.size() <= MAX_PASS_TARGETS:
		return _short_ids
	# Keep the best few, but never drop the nearest couple: the safe ball has to
	# stay on the table even when it looks worthless.
	var kept := _short_ids.slice(0, MAX_PASS_TARGETS)
	var nearest := PackedInt32Array()
	var nearest_d := PackedFloat32Array()
	for mate_id in _short_ids:
		var mate := ctx.players[mate_id]
		var d := mate.dist_to(from)
		var i := 0
		while i < nearest_d.size() and nearest_d[i] <= d:
			i += 1
		nearest.insert(i, mate_id)
		nearest_d.insert(i, d)
	for i in mini(ALWAYS_KEEP_NEAREST, nearest.size()):
		if not kept.has(nearest[i]):
			kept.append(nearest[i])
	return kept


## Pace a ground pass should arrive at, in m/s. A short ball is rolled in; a
## long one has to be driven or the defence gets there first.
##
## The slope was 0.35 off a floor of 3.5, which puts an ordinary fourteen-metre
## ball into a man's feet at 9.2 m/s. That is not a pass, it is a drive, and it
## was the single biggest reason the ball read as running away from people:
## measured over two seeds, every ground pass in the match arrived at 8.7 m/s,
## and the `Taking it down` block then showed the ball arriving at 9.5 and
## leaving at 4.2 -- a first touch failing at a ball nobody should have hit that
## hard.
##
## It is also the one thing rolling resistance cannot reach.
## `SimBallistics.ground_pass_speed` solves the launch speed *against*
## `roll_decel` to hit the pace asked for here, so a grabbier pitch strikes the
## ball harder and it still arrives at 8.7. Arrival pace is invariant to friction
## by construction, and this function is the only place it is decided.
##
## The new curve is a footballer's: about 3.5 m/s at five metres, 4.7 at ten,
## 5.6 at fourteen, 7 at twenty, and just under 10 at the length where a ground
## pass stops being offered at all. The docstring's original point survives in
## the slope -- a long ball is still driven -- it is the intercept that was
## wrong.
##
## What it costs is on the books rather than hidden: a slower ball is longer in
## flight, `_pass_success` prices interception off exactly that, and the softmax
## will stop choosing the long ground passes that can now be cut out. A slow pass
## being easier both to control and to intercept is the trade football makes.
static func arrival_pace(distance: float, tactics: SimTactics) -> float:
	return clampf(2.2 + distance * 0.21, 2.5, 12.0) * lerpf(0.9, 1.2, tactics.tempo)


## Pulls a target point far enough inside the pitch that a ball played to it has
## somewhere to be received. Passes aimed at the touchline are how a match ends
## up with twenty corners and forty throw-ins.
static func _keep_in_play(ctx: SimContext, point: Vector3) -> Vector3:
	return ctx.pitch.clamp_to_pitch(point, 3.0)


## Where to aim a ball that will take `travel` seconds to reach a teammate.
##
## The old answer was `believed + vel * travel * 0.6`, dead reckoning on the
## velocity he happens to have right now, and it fails in the one case that
## matters. A player who has just committed to a run has not accelerated into it
## yet, so his velocity is small and the ball is played to his feet -- which
## means the through ball is mispriced precisely when it is worth playing,
## because the runner is still turning at the moment it should be struck. The
## `0.6` then under-leads even the runs it can see, so the ball arrives behind a
## man who is still going.
##
## Both are fixed by asking the receiver where he is going instead of guessing
## from where he is pointing. He is aimed at as far along his own committed run
## as he can physically get in the time the ball is in flight, and no further --
## `_pass_success` still has to be convinced he beats everyone else there, so an
## optimistic lead is priced rather than believed.
static func _lead_point(ctx: SimContext, mate: SimPlayer, believed: Vector3, travel: float) -> Vector3:
	var dest := SimOffBall.destination_for(ctx, mate)
	if is_inf(dest.x):
		return believed + mate.vel * travel * 0.6
	var to_dest := SimConsts.horizontal(dest - believed)
	var span := to_dest.length()
	if span < 0.5:
		return believed + mate.vel * travel * 0.6
	var pace: float = maxf(mate.max_speed() * SimOffBall.pace_for(ctx, mate), 1.0)
	return believed + to_dest / span * minf(span, pace * travel)


## What a teammate's committed offer is worth as a claim on the ball.
static func _call_bias(ctx: SimContext, mate: SimPlayer) -> float:
	var kind := SimOffBall.intent_of(ctx, mate)
	if kind == SimOffBall.BEHIND:
		return CALL_BEHIND
	if kind == SimOffBall.SHOW:
		return CALL_SHOW
	if kind == SimOffBall.SPACE:
		return CALL_SPACE
	return 1.0


## The return ball, decaying across `GIVE_AND_GO_WINDOW`.
static func _give_and_go_bias(ctx: SimContext, player: SimPlayer, mate_id: int) -> float:
	if ctx.last_pass_to != player.id or ctx.last_pass_from != mate_id:
		return 1.0
	var elapsed := float(ctx.tick_index - ctx.last_pass_tick) / float(SimConsts.TICK_HZ)
	if elapsed < 0.0 or elapsed > GIVE_AND_GO_WINDOW:
		return 1.0
	return lerpf(GIVE_AND_GO_BIAS, 1.0, elapsed / GIVE_AND_GO_WINDOW)


## What the receiver does with the ball once it reaches him, as threat over and
## above the grass it stops on. See `RECEIVER_CARRY_SECONDS`.
##
## Only a man arriving *towards* goal earns any of it, which is the distinction
## expected threat cannot draw: the same ball to the same spot is worth one
## thing to a striker running onto it and another to one checking back to feet
## with his back to the play. Discounted by whether his side still holds the
## ball where the carry ends, so a run into a crowd earns nothing.
static func _arrival_gain(ctx: SimContext, team: int, point: Vector3, believed: Vector3,
		receiver: SimPlayer, travel: float) -> float:
	var goal := ctx.pitch.target_goal(team)
	var to_goal := SimConsts.horizontal(goal - point)
	var gl := to_goal.length()
	if gl < 2.0:
		return 0.0
	to_goal /= gl
	var run := SimConsts.horizontal(point - believed)
	var onto := 0.0
	if run.length() > 0.5:
		onto = clampf(run.normalized().dot(to_goal), 0.0, 1.0)
	else:
		onto = clampf(receiver.heading_dir().dot(to_goal), 0.0, 1.0)
	if onto <= 0.01:
		return 0.0
	var carry: float = minf(receiver.max_speed() * RECEIVER_CARRY_SECONDS * onto, gl - 1.0)
	if carry <= 0.5:
		return 0.0
	var ahead := _keep_in_play(ctx, point + to_goal * carry)
	var step := ctx.value.xt_at(team, ahead, ctx.pitch) - ctx.value.xt_at(team, point, ctx.pitch)
	if step <= 0.0:
		return 0.0
	return step * ctx.value.control_at_time(ctx, ahead, team, travel + RECEIVER_CARRY_SECONDS)


## Probability a ground pass reaches its target: the receiving side must win the
## arrival point, and nobody may cut the line off on the way.
static func _pass_success(ctx: SimContext, player: SimPlayer, from: Vector3, to: Vector3, travel: float, receiver: SimPlayer, into_space: bool = false) -> float:
	# Three separate questions, and conflating them is how an engine talks
	# itself into forty-metre passes: who owns that space, can this particular
	# receiver be there when the ball is, and does the ball survive the journey.
	#
	# A ball played into space asks the first question differently. Nobody owns
	# the grass behind a defensive line at the moment it is played -- that is
	# what makes it space -- so the static form answers "the defence, always"
	# and prices every through ball as a giveaway. What matters is who owns it
	# when the ball gets there, which is the form that charges everyone for
	# waiting on it.
	var space := ctx.value.control_at_time(ctx, to, player.team, travel, player.id) if into_space \
		else ctx.value.control_at(ctx, to, player.team, player.id)
	var receiver_time := SimValueField.time_to_arrive(receiver, to, receiver.reaction)
	var in_time: float = 1.0 / (1.0 + exp(-(travel + 0.3 - receiver_time) / 0.45))
	var lane := _lane_survival(ctx, player, from, to, travel)
	var control: float = lerpf(0.72, 0.99, receiver.attrs.first_touch)
	var distance := SimConsts.horizontal_length(to - from)
	# The line is handed to the accuracy estimate, not just its length, so the ball
	# the passer would have to hit blind off his back foot is priced as the harder
	# ball it is. Without it the engine happily selects a pass it then scuffs, and
	# the facing model shows up only as passes going astray -- never as a player
	# choosing to turn, or to give it to the man he can see instead.
	var struck := SimTouch.execution_accuracy(ctx, player, player.attrs.passing, distance, 0.055, pass_tolerance(distance), to - from)
	return clampf(space * in_time * lane * control * struck, 0.0, 0.99)


## How far off a pass can land and still be a pass. A longer ball gives the
## receiver more time to adjust to a poor one.
static func pass_tolerance(distance: float) -> float:
	return 2.0 + distance * 0.06


static func _lofted_success(ctx: SimContext, player: SimPlayer, to: Vector3, flight: float, receiver: SimPlayer) -> float:
	# A ball in the air cannot be cut out along the ground, but it is harder to
	# control and easier to attack in the air.
	var arrival := ctx.value.control_at_time(ctx, to, player.team, flight, player.id)
	var aerial: float = lerpf(0.55, 0.95, (receiver.attrs.heading + receiver.attrs.jumping) * 0.5)
	var distance := SimConsts.horizontal_length(to - ctx.ball.pos)
	var struck := SimTouch.execution_accuracy(ctx, player, player.attrs.passing, distance, 0.085, pass_tolerance(distance), to - ctx.ball.pos)
	return clampf(arrival * aerial * struck * lerpf(0.7, 0.95, player.attrs.passing), 0.0, 0.97)


## Probability no opponent intercepts along the line. Only opponents actually
## near the line are considered, which keeps this cheap.
static func _lane_survival(ctx: SimContext, player: SimPlayer, from: Vector3, to: Vector3, travel: float) -> float:
	var survival := 1.0
	var seg := SimConsts.horizontal(to - from)
	var length: float = maxf(seg.length(), 0.1)
	var dir := seg / length
	for oid in ctx.opponent_ids(player.team):
		var o := ctx.players[oid]
		if not o.on_pitch:
			continue
		var rel := SimConsts.horizontal(o.pos - from)
		var along: float = rel.dot(dir)
		if along <= 0.5 or along >= length:
			continue
		var lateral: float = absf(rel.x * -dir.z + rel.z * dir.x)
		if lateral > 12.0:
			continue
		var point := from + dir * along
		var ball_time := travel * (along / length)
		# When does the ball get there, and when could they?
		#
		# "Could they" is not "could they stand on that spot". A defender a metre
		# off the line does not run to it, he sticks a leg out, and the first
		# CONTROL_RANGE of the gap between him and the ball's path costs him
		# nothing but his reaction. Charging him the full locomotion cost for it
		# is what made this model kind to a pass threaded straight past somebody:
		# measured across three ten-minute seeds, a quarter of all passes were
		# played with an opponent inside a metre and a half of the line, and they
		# completed at about 40% -- the engine was choosing them, watching them
		# get cut out, and choosing them again.
		var toward := SimConsts.horizontal(o.pos - point)
		var gap := toward.length()
		var meet := point
		if gap > 1e-3:
			meet = point + toward / gap * minf(SimConsts.CONTROL_RANGE, gap)
		var opp_time := SimValueField.time_to_arrive(o, meet, SimValueField.reaction_of(o))
		var margin := ball_time - opp_time
		if margin <= -0.9:
			continue
		var p_cut: float = clampf(1.0 / (1.0 + exp(-(margin) / 0.28)), 0.0, 0.97)
		p_cut *= lerpf(0.75, 1.0, o.attrs.positioning)
		survival *= 1.0 - p_cut
	return clampf(survival, 0.0, 1.0)


## The race for a dribble's landing point, between the carrier and the man
## closing on him.
##
## This is what makes a change of direction a real option. Pitch control cannot
## express it: `control_at` counts the carrier on his own side, and he is the
## nearest man to every one of his own probes, so every direction comes back at
## roughly the same value and the eight candidates are told apart by nothing but
## expected threat -- which is why the carrier only ever dribbled forward, into
## the man.
##
## Asked as one race between two known players it discriminates sharply, because
## `SimValueField.time_to_arrive` charges each of them for the momentum he has
## to shed before he can travel across his own line. A touch played square
## across a committed challenger beats him; the same touch played down the pitch
## in front of him does not. Neither case is authored -- both fall out of the
## locomotion model.
##
## Returns 1.0 when nobody is challenging, so an uncontested carry is unchanged.
static func _escape_value(challenger: SimPlayer, player: SimPlayer, target: Vector3) -> float:
	if challenger == null:
		return 1.0
	# The carrier is not reacting to anything: he has just chosen this himself.
	var mine := SimValueField.time_to_arrive(player, target, 0.0)
	var theirs := SimValueField.time_to_arrive(challenger, target, challenger.reaction)
	return clampf(1.0 / (1.0 + exp(-(theirs - mine) / ESCAPE_TAU)), 0.02, 1.0)


## The knock a carrier could get away with here, in metres of relative gap,
## given where the touchline is.
##
## The conversion is the point. A dribble touch is struck to leave the ball
## `push` metres clear of a player who keeps running, so the ball's own travel
## over the ground is far greater than `push` -- it has to outrun him first and
## then wait for him. Asking whether there is room for the *gap* rather than for
## the ball is how a carrier ends up knocking it into touch and calling it a
## run in behind.
static func _room_ahead(ctx: SimContext, player: SimPlayer, dir: Vector3) -> float:
	var room := ctx.pitch.run_room(player.pos, dir, 1.0)
	if is_inf(room):
		return BURST_DISTANCE
	# Undo the overshoot: ball travel is roughly its launch speed squared over
	# twice the rolling deceleration, and the launch speed is the carrier's own
	# pace plus whatever opens the gap.
	#
	# Inverted properly, which it was not. It used to check the full nine-metre
	# knock against the room and, when it did not fit, scale the knock by the
	# ratio `room / travel` -- but travel goes as the *square* of the launch speed
	# and the launch speed has the carrier's own pace already in it, so scaling
	# the gap by that ratio does not make the ball fit the room, it merely makes
	# it a bit less wrong. Worked through: a man running at 6 m/s with 20 m of
	# grass was allowed a 5 m knock, which leaves the ball travelling at 9.5 m/s
	# and rolling 28 m -- eight metres out of play, from a test whose entire job
	# was to stop that.
	#
	# It is the only thing in the engine that puts a carried ball out from the
	# middle of the pitch, and it is why. Measured, the dribble touches that ended
	# in a throw-in or a goal kick were played on average 16.6 m inside the
	# nearest line, at 10.7 m/s -- nowhere near the paint, and far too hard to be
	# an ordinary carry.
	#
	# The launch speed the ball can afford is the one that brings it to rest on
	# the line, `sqrt(2 * decel * room)`; what the knock is worth is whatever is
	# left of that after his own pace, converted back through the relative
	# deceleration the way `carry_room` does it.
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	var delta: float = sqrt(2.0 * decel * maxf(room, 0.0)) - along
	if delta <= 0.0:
		return 0.0  # Running this fast, the ball is out of play before he is.
	return minf(BURST_DISTANCE, delta * delta / (2.0 * decel))


## How big a touch this direction has room for, capped at `wanted`.
##
## Nothing else in the engine can see this. Every candidate point is clamped back
## inside the touchline before it is scored, so a touch played *along* the line
## and one played *over* it come back with the same expected threat, the same
## pitch control and the same everything else -- and the ball goes out. Measured
## on one seed, 19 of the 24 balls that went out of play in ten minutes were put
## there by a dribble, 11 of them carried over the goal line the carrier was
## running at.
##
## The distance to price it against is neither of the two obvious ones. It is not
## where the touch puts the ball relative to the carrier -- the ball is struck to
## be `ahead` metres clear of a man who keeps running, so in the world frame it
## travels much further than that. Nor is it where the ball would stop rolling,
## which is what `_room_ahead` above charges the burst: the carrier catches this
## one, so the ball never gets to stop. It is the ground the ball covers until it
## has slowed to his pace, which is the moment he starts closing on it:
##
##     travel = (2 * along * delta + delta * delta) / (2 * decel)
##
## for a carrier running at `along` and a launch that beats him by `delta`. That
## is the free-roll figure without its `along * along` term, and the difference
## is not academic -- at a sprint it is 15 metres against 27, and charging a
## carry the larger of the two took nearly every forward touch in the attacking
## half off the table and cost half the shots in a match.
##
## Inverted for `ahead`, which is what the caller needs.
static func carry_room(ctx: SimContext, player: SimPlayer, dir: Vector3, wanted: float) -> float:
	var room := ctx.pitch.run_room(ctx.ball.ground_pos(), dir, LINE_MARGIN)
	if is_inf(room):
		return wanted
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	var delta: float = sqrt(along * along + 2.0 * decel * maxf(room, 0.0)) - along
	if delta <= 0.0:
		return 0.0
	return minf(wanted, delta * delta / (2.0 * decel))


## How big a touch this direction is worth at the pace he is going.
##
## His speed *along the touch*, not his speed: a man running at eight metres a
## second who shifts it square across himself has none of that pace going where
## the ball is going, and the touch that comes back is the short one it should
## be. Turning and carrying on are told apart by the geometry, with nothing
## authored about either.
static func stride_room(player: SimPlayer, dir: Vector3, seconds: float = TOUCH_SECONDS) -> float:
	var along: float = maxf(player.vel.x * dir.x + player.vel.z * dir.z, 0.0)
	return maxf(along * seconds, SimTouch.DRIBBLE_AHEAD_FLOOR)


## Shrinks an intended touch by how close to goal it is being played.
##
## A knock four metres in front of you is a way of covering ground, and inside
## the penalty area there is no ground left to cover -- the ball has to stay
## somewhere it can be struck. A carrier who arrives in the box and pushes it
## another four metres has given the keeper the ball and himself no shot, which
## is the shape of every attack that gets that far and produces nothing.
##
## Nothing else in the engine shortens it. `carry_room` charges the touch for the
## grass it needs, and a man running *across* the six-yard box has all the grass
## in the world by that test while knocking the ball past the near post; the
## value function scores the point the ball ends up at, and four metres closer to
## goal always scores better. Neither can see that the act itself is the wrong
## one this close in.
##
## Applied to the long knock past a challenger as well, where it has a second
## effect worth naming: shortened below the size that made it a foot race, the
## burst fails its own gate in `_add_dribbles` and is not offered at all. That is
## the intention. Knocking it nine metres past a man and running is football at
## twenty metres from goal and is a ball given to the keeper at eight.
static func close_control(ctx: SimContext, player: SimPlayer, wanted: float) -> float:
	var goal := ctx.pitch.target_goal(player.team)
	var d := SimConsts.horizontal_length(goal - ctx.ball.pos)
	var t: float = clampf((d - CLOSE_CONTROL_NEAR) / (CLOSE_CONTROL_FAR - CLOSE_CONTROL_NEAR), 0.0, 1.0)
	return minf(wanted, lerpf(CLOSE_CONTROL_TOUCH, wanted, t))


## The ground a carry of this size covers before the carrier catches it up.
static func carry_travel(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	var delta: float = sqrt(2.0 * decel * maxf(ahead, 0.0))
	return (2.0 * along * delta + delta * delta) / (2.0 * decel)


## Probability this carry leaves the ball on the field of play.
##
## The room test above is a hard floor -- it stops a carrier walking the ball
## over a line he is running straight at -- and a hard floor is the wrong shape
## for the rest of the problem. A winger carrying it up the touchline has all
## the grass in the world along his direction and none at all beside it, so no
## test of the direction can fault the touch; what puts it out is the aim error,
## and the only honest answer is that his touch up the line is a riskier act than
## the same touch played infield. Priced, not forbidden: the softmax then turns
## him inside on its own, which is the behaviour that was wanted.
##
## Shortening the touch instead, which was the first attempt, does not help and
## may well hurt: he stays beside the line for longer and takes more touches
## there, each with its own chance of the same mistake. The measurement that
## rejected it was a single seed and too noisy to put a number on, but the
## mechanism is plain enough, and pricing the option is the engine's idiom
## anyway.
##
## Both channels of the execution model count. The yaw error opens sideways with
## distance; the weight error stretches or shortens the travel, which only
## matters for a line the touch is heading at. Sharing them with `SimTouch`
## means tuning the error model retunes what the engine is willing to try.
static func _in_play_odds(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var travel := carry_travel(ctx, player, dir, ahead)
	if travel < 0.1:
		return 1.0
	var yaw := SimTouch.aim_sigma(ctx, player, player.attrs.dribbling, ahead, SimTouch.DRIBBLE_AIM_BASE, dir)
	# Travel goes as the square of the launch speed, so a relative error in how
	# firmly it is struck arrives roughly doubled in how far it runs.
	var stretch: float = 2.0 * SimTouch.weight_sigma(player, player.attrs.dribbling) * 1.25
	var ball := ctx.ball.ground_pos()
	var pitch := ctx.pitch
	var odds := 1.0
	odds *= _line_odds(pitch.half_length - LINE_MARGIN - ball.x, -dir.x, travel, yaw, stretch)
	odds *= _line_odds(ball.x + pitch.half_length - LINE_MARGIN, dir.x, travel, yaw, stretch)
	odds *= _line_odds(pitch.half_width - LINE_MARGIN - ball.z, -dir.z, travel, yaw, stretch)
	odds *= _line_odds(ball.z + pitch.half_width - LINE_MARGIN, dir.z, travel, yaw, stretch)
	return clampf(odds, 0.02, 1.0)


## One line's share of that: how much grass is left between the touch's landing
## point and the line, against how far the two errors can move it that way.
##
## `closing` is the component of the direction moving *away* from the line, so
## it is negative for a touch played at it -- which is also the only case where
## striking it too firmly matters.
static func _line_odds(clearance: float, closing: float, travel: float, yaw: float, stretch: float) -> float:
	var margin := clearance + travel * closing
	var sideways := yaw * travel
	var lengthways: float = stretch * travel * maxf(-closing, 0.0)
	var spread := sqrt(sideways * sideways + lengthways * lengthways)
	if spread < 1e-4:
		return 1.0 if margin >= 0.0 else 0.0
	# The same logistic approximation to a normal tail that the execution model
	# uses, one-sided.
	return clampf(1.0 / (1.0 + exp(-1.702 * margin / spread)), 0.0, 1.0)


## Which way a touch is played relative to the man closing: 1 straight away from
## him, 0 square across him, -1 straight into him.
##
## Carried on the touch for the log only. The escape value cannot stand in for
## it: that is a probability, and it comes back high for almost every direction
## the softmax would ever pick, so bucketing on it says nothing. Whether the
## carrier turned away from his man is a fact about the geometry, and it is the
## fact the complaint was about.
static func _awayness(challenger: SimPlayer, player: SimPlayer, dir: Vector3) -> float:
	if challenger == null:
		return 0.0
	var from_him := SimConsts.horizontal(player.pos - challenger.pos)
	if from_him.length() < 1e-3:
		return 0.0
	return SimConsts.horizontal(dir).normalized().dot(from_him.normalized())


static func _add_dribbles(ctx: SimContext, player: SimPlayer, uncontrolled: bool, challenger: SimPlayer, regain: float) -> void:
	if uncontrolled:
		return
	var tactics := ctx.tactics(player.team)
	var attack := ctx.pitch.attack_dir(player.team)
	var press: float = lerpf(1.0, 0.55, clampf(ctx.pressure_on(player), 0.0, 1.6) / 1.6)
	var skill: float = lerpf(0.62, 1.0, player.attrs.dribbling)
	# Having just won the ball is the worst moment to try to beat a man: the one
	# you took it from is turning back onto you and his nearest support is still
	# in the pocket. Play it, do not carry it.
	var settle: float = lerpf(1.0, 0.45, regain)
	for i in DRIBBLE_DIRS:
		var angle := TAU * float(i) / float(DRIBBLE_DIRS)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		# How big a touch there is room for this way. A direction with no room
		# for even the smallest touch is not a direction he can carry the ball
		# in, and leaving it on the list was how an unpressured carrier walked
		# the ball over the line: clamped back inside the pitch, the probe
		# looked exactly like one played along it.
		var wanted := close_control(ctx, player, DRIBBLE_DISTANCE)
		var horizon := carry_room(ctx, player, dir, wanted)
		if horizon < SimTouch.DRIBBLE_AHEAD_FLOOR:
			continue
		# And only as big a touch as his own pace this way is worth.
		#
		# The distance he *looks* and the distance he *knocks it* are two numbers
		# and have to stay two numbers, which they briefly were not, with results
		# worth recording. Every term below is read at `pos + dir * <distance>`:
		# who owns the ground, whether the challenger beats him to it, what it is
		# worth, whether the ball stays on the field -- and, through `point`, where
		# he then runs. Sizing that off the touch made the whole risk model as
		# short-sighted as the touch was: a jogging carrier takes a 1.5 m touch, so
		# he was asking about the grass 1.5 m in front of his feet, where there is
		# never a defender and never a touchline. He ran into people and off the
		# side of the pitch, and every probe told him it was fine.
		#
		# A carry is not one touch, it is a direction he will still be going in
		# several touches from now, and `carry_room` and `close_control` already
		# say how far that direction can be pursued at all. That is the horizon to
		# price it over. The touch is the step he takes along it.
		var reach: float = minf(horizon, stride_room(player, dir))
		# Bias the probe set toward the way this team attacks, so a right-back
		# does not consider dribbling into their own net as often as forward.
		var target := ctx.pitch.clamp_to_pitch(player.pos + dir * horizon, 1.0)
		var forwardness: float = dir.x * attack
		var escape := _escape_value(challenger, player, target)
		var success := ctx.value.control_at(ctx, target, player.team)
		# Working the ball back across himself is a touch he is far less likely to
		# get right, and the probe set is the only place the engine can express
		# that as a *choice*. The race in `_escape_value` already charges him for
		# the momentum he has to shed to get there; this is the separate question
		# of whether the ball goes where he meant it to.
		success *= skill * press * escape * SimTouch.facing_control(player, dir)
		# And it is only a carry if the ball is still on the field afterwards.
		#
		# Priced on what he *wanted* to do, not on what the touchline has already
		# cut it down to, and the difference is the whole of whether this term
		# does anything. `carry_room` shortens the touch to fit the grass, so by
		# the time `horizon` comes back it is a touch that fits by construction --
		# feed that in and the lateral spread, which is the yaw error times the
		# travel, is small because the travel is small, and the odds come back
		# near one for a man running along the paint. The protection then collapses
		# to the shortening alone, which is the failure this function was written
		# to replace: he stays beside the line longer and takes more touches there,
		# each with its own chance of the same mistake.
		#
		# Asked of the full-sized carry he would like to play, the direction beside
		# the line is priced as the riskier act it is even though the touch he gets
		# is short, and the softmax turns him infield on its own.
		success *= _in_play_odds(ctx, player, dir, wanted)
		_candidates.append({
			"action": Action.DRIBBLE,
			"point": target,
			"dir": dir,
			"escape": escape,
			"away": _awayness(challenger, player, dir),
			"success": clampf(success, 0.0, 0.98),
			"gain": ctx.value.xt_at(player.team, target, ctx.pitch) * tactics.focus_at(target.z, ctx.pitch),
			# Charged where the ball would be lost, which is where the touch was
			# going -- the convention every other candidate in the engine follows,
			# the knock past the man twenty lines below included. Read at the
			# carrier's own feet instead, as this was, it is the *same number for
			# all eight probes*, so the risk term cannot tell dribbling toward his
			# own goal from dribbling toward the other one.
			#
			# It is the only term that could, in one's own half. Expected threat
			# for the team in possession is flat back there -- of the order of
			# 0.0002 against the 0.013 the engine adds for merely having the ball
			# -- while the threat conceded on a turnover climbs steeply toward
			# one's own box, which is the whole reason a defender plays it long.
			"loss": ctx.value.xt_at(SimConsts.other_team(player.team), target, ctx.pitch),
			# The size of the touch follows the room the direction actually buys,
			# so getting away from a man is a knock into space and being hemmed in
			# is a short one under the sole.
			#
			# Read off `reach` and not off `success`, which is what it used to be.
			# The score is a composite -- pitch control, the escape race, the body
			# angle, the touchline odds -- and every one of those terms is high
			# for the direction the softmax is about to pick, so taking the size
			# from it meant the chosen touch was the long one whatever the traffic
			# in front of him. This is the room, in metres, and nothing else.
			"space": clampf((reach - SimTouch.DRIBBLE_AHEAD_FLOOR) / maxf(DRIBBLE_DISTANCE - SimTouch.DRIBBLE_AHEAD_FLOOR, 0.1), 0.0, 1.0),
			# And the touch that gets played has to be the touch that was scored.
			"max_ahead": reach,
			"bias": tactics.retention_bias() * lerpf(0.85, 1.1, 0.5 + forwardness * 0.5) * settle,
		})

	# --- Knock it past him and run -------------------------------------------
	# A carrier with a man on his shoulder and grass ahead does not take another
	# short touch under his sole. He pushes it a long way in front and turns it
	# into a foot race, which is a different option from the carry and has to be
	# on the list as one: the short probes can never express it, because at four
	# metres the challenger is still within reach of every one of them.
	#
	# It used to require a challenger, and that left a hole exactly where the
	# behaviour is most obvious to watch: a man running into an empty half has
	# nobody near enough to be `nearest_challenger`, so the only touch on offer
	# to him was a four-metre carry, and the way `SimMovement` paces a carrier --
	# off the gap between him and his own next touch -- meant he then jogged
	# after it. Knocking it into space and going is the same act whether or not
	# somebody is chasing; when nobody is, `_escape_value` returns 1.0 and
	# `control_at` ignores nobody, so the knock is priced on the grass alone.
	var running := SimConsts.horizontal(player.vel)
	if running.length() < BURST_PACE:
		return
	var burst_dir := running.normalized()
	# Only as far as there is pitch to run into. The ball goes a long way further
	# than the gap it opens up -- it is struck to be `push` metres clear of a man
	# still running, so in the world frame it rolls two or three times that before
	# he catches it -- and none of that is visible to the value function, which
	# scores a point clamped back inside the touchline. Knocking it into space you
	# do not have is a throw-in, and unchecked it produced them by the dozen.
	var push := minf(close_control(ctx, player, BURST_DISTANCE), _room_ahead(ctx, player, burst_dir))
	# Beyond his stride, but still off it: the knock a man at full pace can run
	# onto is not the one a man who has just got going can.
	push = minf(push, stride_room(player, burst_dir, BURST_SECONDS))
	if push < BURST_DISTANCE * 0.55:
		return  # Not enough grass for this to be the knock it was scored as.
	var burst := ctx.pitch.clamp_to_pitch(player.pos + burst_dir * push, 1.0)
	var burst_escape := _escape_value(challenger, player, burst)
	var burst_success := ctx.value.control_at(ctx, burst, player.team, challenger.id if challenger != null else -1)
	burst_success *= skill * burst_escape
	# The same question the carry above is asked. `_room_ahead` shortens the knock
	# to fit the grass, which stops him aiming it off the pitch, and says nothing
	# about his aiming it *near* the line and mishitting it -- and this is the
	# touch with the longest travel in the game, so the aim error has the furthest
	# to spread. Left unpriced while the carry was priced, the softmax simply
	# moved the problem: carries out of play fell by a fifth and bursts out of
	# play rose by a fifth.
	burst_success *= _in_play_odds(ctx, player, burst_dir, push)
	# Pace, acceleration and the room already won decide whether it comes off,
	# and all three are in the race above.
	#
	# What the score does not carry is that the knock commits him past the ball:
	# lose this one and the opponent has possession *and* a man behind it, where
	# losing a short touch leaves the carrier still in the contest. That is a
	# cost to the shape rather than to the ball's position, and a single-step
	# model has no vocabulary for it -- the same limit POSSESSION_VALUE exists to
	# patch. Left unmodelled rather than papered over with a coefficient.
	_candidates.append({
		"action": Action.DRIBBLE,
		"point": burst,
		"dir": burst_dir,
		"escape": burst_escape,
		"away": _awayness(challenger, player, burst_dir),
		"success": clampf(burst_success, 0.0, 0.98),
		"gain": ctx.value.xt_at(player.team, burst, ctx.pitch) * tactics.focus_at(burst.z, ctx.pitch),
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), burst, ctx.pitch),
		"space": 1.0,
		# The execution has to push it as far as the score assumed it would. A
		# candidate scored on a nine-metre knock and then played as a four-metre
		# touch is the decision layer lying to itself about its own option.
		"push": push,
		"bias": tactics.retention_bias() * lerpf(0.9, 1.25, player.attrs.pace) * settle,
	})


static func _add_hold(ctx: SimContext, player: SimPlayer, uncontrolled: bool, regain: float) -> void:
	var tactics := ctx.tactics(player.team)
	var here := ctx.value.xt_at(player.team, player.pos, ctx.pitch)
	# Holding is safe but goes nowhere. Taking a first touch out of a moving
	# ball is the same candidate: it keeps the ball without advancing it.
	#
	# Except with a man arriving, when it is neither safe nor nowhere: standing
	# over the ball as a challenge comes in is how the ball is lost, and it is
	# the option the engine used to take almost every time, because the pressure
	# field it was reading rates the man on the carrier's back at nearly nothing.
	var success: float = lerpf(0.72, 0.97, player.attrs.first_touch)
	success -= ctx.pressure_on(player) * 0.16 + ctx.challenge_on(player) * 0.30
	_candidates.append({
		"action": Action.HOLD,
		"success": clampf(success, 0.05, 0.98),
		"gain": here * 0.92,
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), player.pos, ctx.pitch),
		"bias": tactics.retention_bias() * (1.5 if uncontrolled else 1.0) * lerpf(1.0, 0.5, regain),
	})


static func _add_clear(ctx: SimContext, player: SimPlayer) -> void:
	# Only a real option when deep and under pressure; it is a panic action.
	var own_goal := ctx.pitch.own_goal(player.team)
	var depth := absf(player.pos.x - own_goal.x)
	var chal := ctx.challenge_on(player)
	# Only a real option deep in your own territory. Anywhere else a clearance
	# is just a pass you have given away, and it puts the ball out of play.
	#
	# The exception is a man about to take it off you inside your own third.
	# Hooking it away rather than being tackled there is football; a defender who
	# never has that option has to stay in every challenge he cannot pass out of.
	#
	# Kept to the defensive third rather than the own half on purpose. Extended
	# to the halfway line it fired often enough to be the *first* answer to a
	# challenge rather than the last -- 29% of challenged touches and thirty-odd
	# clearances in ten minutes, which is a team that never plays through
	# anything. The situation is the same one; what changes with distance from
	# your own goal is whether giving the ball away is worth avoiding it.
	if depth > 26.0 and (chal < 0.8 or depth > ctx.pitch.half_length * (2.0 / 3.0)):
		return
	if depth > 18.0 and ctx.pressure_on(player) < 0.8 and chal < 0.8:
		return
	var landing := ctx.pitch.orient(player.team, Vector3(minf(player.pos.x * ctx.pitch.attack_dir(player.team) + 40.0, ctx.pitch.half_length - 5.0), 0.0, 0.0))
	_candidates.append({
		"action": Action.CLEAR,
		# A hack made with a man coming through you is not the same stroke as one
		# made in space, and if it were the clearance would be strictly the best
		# answer to a challenge: every other option's success falls as the man
		# arrives and this one used to be a flat 0.42 whatever was happening.
		"success": 0.42 * lerpf(1.0, 0.65, clampf(chal, 0.0, 1.0)),
		"gain": ctx.value.xt_at(player.team, landing, ctx.pitch) * 0.7,
		# The point of a clearance is what it avoids, so its loss term is the
		# threat it removes rather than the one it creates.
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), landing, ctx.pitch) * 0.5,
		# Deliberately not lifted by the challenge, and deliberately not lifted by
		# a regain either. The gate above already says a clearance is available
		# *because* a man is coming; paying for the same fact twice is what made it
		# the default answer to a challenge. And a clearance is the one thing a
		# player who has just won the ball should not be encouraged into -- putting
		# it back in the air is not getting it to a better place, it is giving it
		# away again, which is the very cycle the regain window exists to break.
		# With the lift on, clearances ran at three times their previous rate.
		"bias": 0.6 + clampf(ctx.pressure_on(player), 0.0, 2.0) * 0.55,
	})


# --- Scoring and selection --------------------------------------------------


## What simply having the ball is worth, in goal probability: roughly the goals
## per match divided by the possessions per match.
##
## Without this term the engine compares only the positional value of where the
## ball ends up, and a fifty-metre punt to a well-placed striker looks better
## than a fifteen-metre pass that keeps the ball. Retention has to be on the
## books or the engine plays like a team chasing a game in the 94th minute.
const POSSESSION_VALUE := 0.013

## How much a teammate's committed offer bids up the pass that serves it.
##
## The receiver's half of the decision. An off-ball run is currently a thing a
## player does *at* the ball rather than a thing he asks for: he commits, he
## runs, and the man on the ball weighs him exactly as he would weigh anybody
## standing in the same place. So a run that is ignored costs nothing and
## teaches nobody anything, which is the same complaint PLAN.md §5.3 makes about
## a pattern that fires and never resolves.
##
## Sized by how much of a claim each offer is. Coming to meet the ball is an
## invitation; drifting into a pocket is barely more than standing well; going
## past the last defender is a demand, and it is the one that expires -- he is
## either found or he is offside, back onside, or blown.
##
## These are priors on a value the decision layer was going to use anyway
## (PLAN.md §5.1), not a rule that the ball goes to whoever shouted.
const CALL_SHOW := 1.15
const CALL_SPACE := 1.08
const CALL_BEHIND := 1.5

## How long the man who laid it off stays a preferred option, in seconds, and
## what his return ball is worth over its map value while he does.
const GIVE_AND_GO_WINDOW := 1.4
const GIVE_AND_GO_BIAS := 1.45

## Seconds of the receiver's onward carry that a pass is credited with.
##
## Expected threat is a single-step model: it answers what the grass under the
## ball is worth and cannot answer what the man arriving on it is about to do
## with it. Those differ most for exactly the pass worth playing -- a ball in
## behind is priced as a patch of turf near the corner of the box when what it
## actually is is a striker running at an unset defence with the goal in front
## of him. `_arrival_gain` gives him this long to carry it before anyone gets
## near, and credits the pass with the threat he builds, discounted by whether
## his side will still own the ball when he gets there.
##
## It is a second step and not a solution: a real answer needs the defence's
## orientation, which the engine does not model. Kept short for that reason.
const RECEIVER_CARRY_SECONDS := 0.9


## How recently this player won the ball back, as 1 at the instant of the
## regain decaying to 0 across REGAIN_WINDOW.
##
## This exists alongside the challenge field rather than inside it because the
## two describe different things. The man who has just lost the ball is often
## momentarily still -- he is carrying a recovery penalty and a touch cooldown --
## so he registers as no threat at all, while the pocket the ball was won in is
## the most crowded place on the pitch and everyone in it is about to turn round.
## A regain is a fact about the situation, not about any one opponent.
##
## Without it the roles at a turnover simply swap: the winner carries the ball
## straight back into the man he took it from, gets challenged, and the pair of
## them trade it until somebody hoofs it.
static func regain_urgency(ctx: SimContext, player: SimPlayer) -> float:
	var elapsed := float(ctx.tick_index - player.regain_tick) / float(SimConsts.TICK_HZ)
	if elapsed < 0.0 or elapsed >= REGAIN_WINDOW:
		return 0.0
	return 1.0 - elapsed / REGAIN_WINDOW


static func score_of(ctx: SimContext, player: SimPlayer, c: Dictionary) -> float:
	var tactics := ctx.tactics(player.team)
	var success: float = c["success"]
	var gain: float = c["gain"]
	var loss: float = c["loss"]
	if c["action"] != Action.SHOOT:
		# Value that only arrives later is discounted; a high-tempo side
		# discounts harder and therefore releases the ball sooner.
		gain *= tactics.future_discount()
		# The bias scales the positional value of the option, never the whole
		# expression: a penalty applied to a negative score would make a bad
		# option look better.
		gain = gain * float(c.get("bias", 1.0)) + POSSESSION_VALUE
		loss += POSSESSION_VALUE
	else:
		gain *= float(c.get("bias", 1.0))
		loss += POSSESSION_VALUE
	return success * gain - (1.0 - success) * tactics.risk_weight() * loss


## Softmax over candidate scores, never argmax. Temperature falls with the
## decisions attribute, so better decision-makers more often pick the genuinely
## best option and weaker ones make plausible-but-wrong choices.
##
## The temperature is *relative* to the spread of the candidate scores. An
## absolute temperature cannot work: scores here are goal probabilities, so the
## whole candidate list often fits inside a range of 0.02, and any fixed
## temperature is either indistinguishable from random or indistinguishable
## from argmax depending on the situation.
static func _softmax_pick(ctx: SimContext, player: SimPlayer) -> Dictionary:
	var n := _candidates.size()
	if _weights.size() != n:
		_weights.resize(n)

	var best := -INF
	var total_score := 0.0
	for i in n:
		var s := score_of(ctx, player, _candidates[i])
		_candidates[i]["score"] = s
		total_score += s
		best = maxf(best, s)
	var mean := total_score / float(n)
	var variance := 0.0
	for i in n:
		var d: float = float(_candidates[i]["score"]) - mean
		variance += d * d
	var spread: float = sqrt(variance / float(n))

	var temp: float = lerpf(TEMP_POOR, TEMP_GOOD, player.attrs.decisions) * spread
	temp *= lerpf(1.3, 0.85, player.attrs.composure)
	temp /= maxf(player.fatigue_factor(), 0.6)
	temp = maxf(temp, 1e-7)

	var total := 0.0
	for i in n:
		var w: float = exp((float(_candidates[i]["score"]) - best) / temp)
		_weights[i] = w
		total += w
	var idx: int = ctx.rng.weighted_index(_weights)
	if idx < 0:
		idx = 0
	_last_pick = idx
	_last_temp = temp
	_last_spread = spread
	return _candidates[idx]


# --- Execution --------------------------------------------------------------


static func _execute(ctx: SimContext, player: SimPlayer, c: Dictionary, uncontrolled: bool) -> void:
	var action: int = c["action"]
	var xv: float = float(c.get("score", 0.0))
	match action:
		Action.SHOOT:
			SimTouch.shot(ctx, player, c["aim"], c["power"], c["first_time"], c["success"])
		Action.GROUND_PASS:
			SimTouch.ground_pass(ctx, player, c["point"], c["pace"], c["target"], SimTelemetry.Touch.GROUND_PASS, xv)
		Action.THROUGH_BALL:
			SimTouch.ground_pass(ctx, player, c["point"], c["pace"], c["target"], SimTelemetry.Touch.THROUGH_BALL, xv)
		Action.LOFTED_PASS:
			SimTouch.lofted_pass(ctx, player, c["point"], c["flight"], c["target"], SimTelemetry.Touch.LOFTED_PASS, _curl_for(ctx, player), xv)
		Action.CROSS:
			SimTouch.lofted_pass(ctx, player, c["point"], c["flight"], c["target"], SimTelemetry.Touch.CROSS, _curl_for(ctx, player), xv)
		Action.DRIBBLE:
			SimTouch.dribble(ctx, player, c["dir"], c["space"], float(c.get("push", 0.0)), float(c.get("away", 0.0)), float(c.get("max_ahead", INF)))
			player.move_target = c["point"]
			player.move_speed_cap = INF
		Action.CLEAR:
			SimTouch.clearance(ctx, player)
		Action.HOLD:
			_play_hold(ctx, player, uncontrolled)
		_:
			_play_hold(ctx, player, uncontrolled)


## Plays the hold: a settling touch that leaves the ball where it is.
##
## The size is the whole of this function, and it used to be `space` 0.15, which
## is a 2.2 m knock. A hold is scored as the ball *not moving* -- `_add_hold`
## reads its gain and its loss at the player's own feet, and calls itself "safe
## but goes nowhere" -- and it was then executed as two metres of ground covered
## in a direction no candidate had been scored for. Measured on seed 7, three
## quarters of every carry touch in the match came out of here rather than out of
## the eight scored probes: 403 of 527, one every 0.47 s, 2.08 m at a time.
##
## Both halves of "he runs into people and off the side of the pitch" are that
## number. Nothing on this path asks what is in front of him, nothing asks where
## the touchline is, and nothing shortens the touch in the penalty area, because
## all three of those live in `_add_dribbles` and this is not `_add_dribbles`.
## Split by which path played them, the carries that went out of play near a line
## were *all* holds, and holds were three times as likely as a scored dribble to
## be knocked into a body four to fifteen metres up the lane -- which lost the
## ball inside two seconds about 45% of the time, against 15% for a clear one.
##
## So the hold is a hold: the smallest touch the engine has, which is what makes
## the scored option and the played one the same option again. Covering ground is
## `_add_dribbles`' job, it is offered on every decision, and it is priced.
## `close_control` is not consulted because it could not bite -- a hold is
## already shorter than the touch it would shorten to -- but `carry_room` is,
## because a metre played at a line the man is standing on is still a metre too
## far.
static func _play_hold(ctx: SimContext, player: SimPlayer, uncontrolled: bool) -> void:
	var dir := _safe_direction(ctx, player, HOLD_AHEAD)
	if uncontrolled:
		SimTouch.first_touch(ctx, player, dir)
		return
	SimTouch.dribble(ctx, player, dir, 0.0, 0.0, 0.0, carry_room(ctx, player, dir, HOLD_AHEAD))


## Where to take a settling touch: forward if the way is clear and there is grass
## for it, out of the way of whoever is in it otherwise.
##
## Sheltering the ball is not allowed to cost ground, and that restriction is
## the whole of this function's difficulty. A hold is scored as keeping the ball
## where it is and then *executed* as a real touch, so whatever direction comes
## back here the ball actually travels along it -- a metre now, and two before
## `_play_hold` made the touch the size the score assumed. Read literally, "away
## from the nearest man" points at one's own goal for as long as he is goal-side
## -- which, since the recovery run went in, is most of the time a carrier is
## under pressure. Ten holds in a row is then a twenty-metre retreat to one's own
## byline that no candidate was ever scored for and no decision was ever taken:
## measured on seed 1 it ran six seconds and 22 metres, with the man on his back
## the whole way.
##
## What is left once the retreating component is stripped out is the act the
## original was reaching for. The ball goes *across* the man rather than away
## from him -- side-on, out of his reach, conceding nothing behind. Dropping
## back with the ball is still available; it is available where it belongs, in
## the eight scored dribble probes and in a pass, both of which price the ground
## they give up.
static func _safe_direction(ctx: SimContext, player: SimPlayer, ahead: float) -> Vector3:
	var forward := SimConsts.horizontal(ctx.pitch.target_goal(player.team) - player.pos)
	if forward.length() < 0.1:
		return player.heading_dir()
	forward = forward.normalized()
	var blocker := _hold_obstacle(ctx, player, forward, ahead)
	if blocker == null and _hold_fits(ctx, player, forward, ahead):
		return forward
	if blocker != null:
		var away := SimConsts.horizontal(player.pos - blocker.pos)
		if away.length() >= 0.1:
			var dir := forward * 0.4 + away.normalized()
			dir -= forward * minf(dir.dot(forward), 0.0)
			if dir.length() > 0.2:
				dir = dir.normalized()
				if _hold_fits(ctx, player, dir, ahead):
					return dir
	# He is squarely between the carrier and the goal, so there is no forward
	# component of "away" left to keep -- or the way out is at a line. The ball
	# goes square, to whichever side has the pitch to take it: a hold that
	# shelters the ball into the touchline is a throw-in with extra steps.
	var square := Vector3(-forward.z, 0.0, forward.x)
	if ctx.pitch.run_room(player.pos, square, 1.0) < ctx.pitch.run_room(player.pos, -square, 1.0):
		square = -square
	return square


## Whether a settling touch this way has the grass to be played at all.
##
## The same question `_add_dribbles` asks of each of its eight probes, and the
## same gate: a direction with no room for even the smallest touch is not a
## direction the ball can go. Nothing on the hold path asked it, which is why
## every carry that went out of play beside a line was one -- the forward branch
## returned "at the goal" from two metres inside the byline and the touch was
## played with nothing to shorten it.
static func _hold_fits(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> bool:
	return carry_room(ctx, player, dir, ahead) >= SimTouch.DRIBBLE_AHEAD_FLOOR


## The man a settling touch has to be sheltered from: whoever is close enough to
## reach it, either standing over the carrier already or waiting down the line
## the ball is about to be played along.
##
## The second half is the new one. This used to be `nearest_opponent` inside four
## metres, full stop, and that is both too short and the wrong shape. Too short:
## `CHALLENGE_SIGHT` is 5.5 m, so a man the rest of the engine already considers
## an imminent challenge did not register here at all. Wrong shape: it is the
## nearest man in *any* direction, so a marker three metres behind the carrier
## moved the touch and a defender six metres dead in front of him did not.
## Measured, that is where the ball went -- 28% of holds were knocked into a body
## four to fifteen metres up the lane, and they lost it inside two seconds about
## 45% of the time.
##
## How far down the lane to look is not a constant, because the answer depends on
## how fast the man is going: the ball runs further from a moving carrier for the
## same touch, and `carry_travel` already says how much further. A standing
## player looks about five metres, a man at full pace about ten, from one rule
## rather than two. The floor is the old radius, which is the man on his back.
const HOLD_SHELTER := 4.0
## Half the width of the lane, a body and a step either side of the line the ball
## takes.
const HOLD_LANE := 3.0


static func _hold_obstacle(ctx: SimContext, player: SimPlayer, forward: Vector3, ahead: float) -> SimPlayer:
	var look := carry_travel(ctx, player, forward, ahead) + HOLD_SHELTER
	var best: SimPlayer = null
	var best_d := INF
	for j in ctx.opponent_ids(player.team):
		var o: SimPlayer = ctx.players[j]
		if not o.on_pitch:
			continue
		var to := SimConsts.horizontal(o.pos - player.pos)
		var d := to.length()
		if d >= best_d:
			continue
		if d < HOLD_SHELTER:
			best = o
			best_d = d
			continue
		var along := to.dot(forward)
		if along > 0.0 and along < look and absf(to.x * -forward.z + to.z * forward.x) < HOLD_LANE:
			best = o
			best_d = d
	return best


static func _curl_for(ctx: SimContext, player: SimPlayer) -> float:
	return ctx.rng.gauss_clamped(0.0, 3.0, 2.0) * player.attrs.technique


## True if `point` lies within `radius` of the segment from `a` to `b`.
static func _near_segment(point: Vector3, a: Vector3, b: Vector3, radius: float) -> bool:
	var ab := SimConsts.horizontal(b - a)
	var length_sq: float = ab.length_squared()
	if length_sq < 1e-6:
		return SimConsts.horizontal_length(point - a) <= radius
	var t: float = clampf(SimConsts.horizontal(point - a).dot(ab) / length_sq, 0.0, 1.0)
	return SimConsts.horizontal_length(point - (a + ab * t)) <= radius
