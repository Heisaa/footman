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

## Which term an option that was on the list lost on.
##
## `received` in the off-ball table says a run was not found. It cannot say
## whether the ball to it scored badly or scored perfectly well and was beaten by
## something better, and those want opposite fixes -- one is the pass model, the
## other is the rest of the list. Guessing between them is how two changes went in
## backwards in one afternoon.
##
## So: on every decision, the best-scoring candidate of each kind is compared with
## the one actually played, and the four numbers the score is made of are summed
## for both sides. The averages come out as "a through ball, when it was the best
## of its kind and lost, had a success of 0.24 against the played option's 0.58" --
## which names the term without anybody having to reason about the softmax.
##
## Counted rather than logged, and for the same reason as `SimOffBall`'s tallies:
## a decision happens several times a second, `SimTelemetry.canonical_text` is
## hashed by the golden replay test, and a diagnostic has no business moving a
## digest. Nothing in `sim/` reads it back and it never touches `ctx.rng`.
const LOST_N := 0
const LOST_SUCCESS := 1
const LOST_GAIN := 2
const LOST_LOSS := 3
const LOST_BIAS := 4
const LOST_SCORE := 5
const WON_SUCCESS := 6
const WON_GAIN := 7
const WON_LOSS := 8
const WON_BIAS := 9
const WON_SCORE := 10
## And the five factors the losing candidate's `success` is a product of, for the
## pass kinds. A success of 0.05 can be one factor at 0.05 or three at 0.4, and
## those are unrelated faults in unrelated code, so the product on its own sends
## you looking in the wrong place.
const LOST_SPACE := 11
const LOST_IN_TIME := 12
const LOST_LANE := 13
const LOST_CONTROL := 14
const LOST_STRUCK := 15
const LOST_STRIDE := 16

## Slots of `_parts`, which is what a success model leaves behind for the tally.
##
## Named for what they mean rather than for either model's internals, so the two
## can share a table. A ball in the air has no `IN_TIME` and no `LANE` -- it
## cannot be cut out along the ground, which is the whole difference between it
## and a pass -- and both come back as 1.0 for it rather than as a gap.
const PART_SPACE := 0
const PART_IN_TIME := 1
const PART_LANE := 2
const PART_CONTROL := 3
const PART_STRUCK := 4
const PARTS := 5

## What the last success model computed, and the same per candidate, written as
## each one is appended so index i means candidate i. Both are scratch, reused
## every decision.
static var _parts := PackedFloat32Array()
static var _cand_parts := PackedFloat32Array()


## Files the factors of the success just computed. Called by the two success
## models; picked up by `_keep_parts` when the candidate they belong to is
## appended.
static func _note_parts(space: float, in_time: float, lane: float, control: float, struck: float) -> void:
	if _parts.size() != PARTS:
		_parts.resize(PARTS)
	_parts[PART_SPACE] = space
	_parts[PART_IN_TIME] = in_time
	_parts[PART_LANE] = lane
	_parts[PART_CONTROL] = control
	_parts[PART_STRUCK] = struck


## Attaches them to the candidate that has just gone on the list.
static func _keep_parts() -> void:
	var at := (_candidates.size() - 1) * PARTS
	if _cand_parts.size() < at + PARTS:
		_cand_parts.resize(at + PARTS)
	for k in PARTS:
		_cand_parts[at + k] = _parts[k] if _parts.size() == PARTS else 1.0

static var lost := PackedFloat32Array()

## Scratch for the tally: the best-scoring candidate of each kind this decision.
static var _best_of_kind := PackedInt32Array()


## Clears the rejection tally. Called from `SimMatch.setup` with the rest of the
## static state, because a static outlives the match that filled it.
static func reset() -> void:
	lost.resize(Action.size() * LOST_STRIDE)
	for i in lost.size():
		lost[i] = 0.0
	_exposure_tick = -1
	exposure_sum = 0.0
	exposure_line = 0.0
	exposure_n = 0.0


## One slot of the tally, for the diagnostics to read.
static func lost_at(kind: int, slot: int) -> float:
	var i := kind * LOST_STRIDE + slot
	return lost[i] if i >= 0 and i < lost.size() else 0.0


## Files every kind that was on the list and did not get played, against the one
## that did.
static func _note_rejections(chosen: int) -> void:
	if lost.size() != Action.size() * LOST_STRIDE:
		reset()
	if _best_of_kind.size() != Action.size():
		_best_of_kind.resize(Action.size())
	for k in Action.size():
		_best_of_kind[k] = -1
	for i in _candidates.size():
		var kind := int(_candidates[i]["action"])
		var at: int = _best_of_kind[kind]
		if at < 0 or float(_candidates[i]["score"]) > float(_candidates[at]["score"]):
			_best_of_kind[kind] = i
	var won: Dictionary = _candidates[chosen]
	for k in Action.size():
		var i: int = _best_of_kind[k]
		if i < 0 or i == chosen:
			continue
		var c: Dictionary = _candidates[i]
		var base := k * LOST_STRIDE
		lost[base + LOST_N] += 1.0
		lost[base + LOST_SUCCESS] += float(c.get("success", 0.0))
		lost[base + LOST_GAIN] += float(c.get("gain", 0.0))
		lost[base + LOST_LOSS] += float(c.get("loss", 0.0))
		lost[base + LOST_BIAS] += float(c.get("bias", 1.0))
		lost[base + LOST_SCORE] += float(c.get("score", 0.0))
		lost[base + WON_SUCCESS] += float(won.get("success", 0.0))
		lost[base + WON_GAIN] += float(won.get("gain", 0.0))
		lost[base + WON_LOSS] += float(won.get("loss", 0.0))
		lost[base + WON_BIAS] += float(won.get("bias", 1.0))
		lost[base + WON_SCORE] += float(won.get("score", 0.0))
		if is_pass(k):
			var at := i * PARTS
			if at + PARTS <= _cand_parts.size():
				lost[base + LOST_SPACE] += _cand_parts[at + PART_SPACE]
				lost[base + LOST_IN_TIME] += _cand_parts[at + PART_IN_TIME]
				lost[base + LOST_LANE] += _cand_parts[at + PART_LANE]
				lost[base + LOST_CONTROL] += _cand_parts[at + PART_CONTROL]
				lost[base + LOST_STRUCK] += _cand_parts[at + PART_STRUCK]


## The kinds whose `success` is a product of the five factors above.
static func is_pass(action: int) -> bool:
	return action == Action.GROUND_PASS or action == Action.THROUGH_BALL \
		or action == Action.LOFTED_PASS or action == Action.CROSS

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
##
## The constant never did grow with his pace. The strike did, for as long as the
## hold went out through `SimTouch.dribble`, which adds the carrier's own speed
## to every touch because a carry is a distance measured against a moving man.
## `SimTouch.settle` is the same distance measured against the grass, which is
## the frame `_add_hold` scores in.
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

	# Cleared on every decision and set again by `_play_hold`, so it describes the
	# touch just played rather than any earlier one.
	player.settling = false

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
	# opponent's half either way. That restart is also where the possession
	# stands afterwards, so it is the point `score_of` prices the turnover at.
	var restart := Vector3(goal.x * 0.75, 0.0, 0.0)
	var loss := ctx.value.xt_at(SimConsts.other_team(player.team), restart, ctx.pitch)
	_candidates.append({
		"action": Action.SHOOT,
		"aim": aim,
		# Not `point`: the debug overlay draws the arrow at that key, and a shot's
		# arrow is its aim.
		"end": restart,
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
		# `shot_appetite` is 1.0 at real time and only leaves it under compression:
		# see `SimMatchConfig`, "the compressed match's scoring fit".
		"bias": lerpf(0.75, 1.25, tactics.directness) * (0.6 if first_time else 1.0)
			* ctx.config.shot_appetite(),
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
	# And whether there is a shot there at all from where his body is pointing.
	# `SimTouch.shot` scales the strike by the same number, so the chance the
	# engine prices and the ball it then hits are the same event: a man with the
	# goal over his shoulder gets a scuffed poke, and the way to a real shot is to
	# turn first.
	base *= SimTouch.strike_scale(player, aim - from)
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
		# How long a ball he can hit this way at all. A pass played across or
		# behind the body is not a shorter version of the same pass, it is a
		# different act with a fraction of the range -- see `SimTouch.strike_scale`,
		# which `ground_pass` and `lofted_pass` clamp the struck ball to. Gating the
		# candidate on the same number is what stops the engine scoring a
		# forty-metre diagonal off a man's back foot, choosing it, and then playing
		# a fifteen-metre one. The way to the long ball is to turn and hit it.
		var ground_reach := SimTouch.strike_range(player, believed - from, MAX_GROUND_PASS)
		var air_reach := SimTouch.strike_range(player, believed - from, MAX_LOFTED_PASS)

		# --- Ground pass to feet -------------------------------------------
		if raw_distance <= ground_reach:
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
				"end": lead,
				"success": success * off_balance,
				# Read where the ball is going and nowhere else. The floor that
				# used to be here -- worth at least 85% of the grass it left --
				# handed the ball played backwards the value of the position it
				# was giving up, which is the option this whole section exists to
				# price honestly.
				"gain": gain,
				"loss": ctx.value.xt_at(SimConsts.other_team(player.team), lead, ctx.pitch),
				"pace": pace,
				# Football's pass-length distribution is heavily short. Without
				# this the engine plays a Hollywood ball every time.
				"bias": tactics.retention_bias() * (1.0 / (1.0 + raw_distance * 0.21)) * secure
					* _call_bias(ctx, mate) * _give_and_go_bias(ctx, player, mate_id),
			})
			_keep_parts()

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
				# As far along it as he can get while the ball is travelling, and
				# no further. The ground pass has always been aimed this way --
				# `_lead_point` clamps to what the receiver can reach -- and this
				# branch went straight to the end of the run without asking, which
				# is a ball aimed past a man by whatever was left of it. It is the
				# reason a through ball kept arriving with the runner a stride
				# short: not unlucky, aimed wrong.
				#
				# One correction, the same as the ground pass makes. The flight is
				# measured to the far end, the aim is cut back to what that flight
				# buys, and the terms below are then recomputed off the aim that
				# came out -- so the ball that is scored is the ball that is struck.
				var to_run := SimConsts.horizontal(committed - believed)
				var span := to_run.length()
				if span < 0.5:
					target = _keep_in_play(ctx, committed)
				else:
					var far := SimConsts.horizontal_length(committed - from)
					var far_travel := ctx.ballistics.ground_travel_time(far,
						ctx.ballistics.ground_pass_speed(far, arrival_pace(far, tactics) * 1.15, ctx.env),
						ctx.env)
					target = _keep_in_play(ctx, believed + to_run / span
						* minf(span, _run_reach(ctx, mate, to_run, far_travel)))
			var t_distance := SimConsts.horizontal_length(target - from)
			if t_distance > 4.0 and t_distance <= SimTouch.strike_range(player, target - from, MAX_GROUND_PASS + 6.0):
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
					"end": target,
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
				_keep_parts()

		# --- Lofted pass or cross ------------------------------------------
		# A ball in the air is a choice, not a default: only over a distance
		# that a ground pass cannot cover, or into the box.
		var box_target := ctx.pitch.in_opponent_penalty_area(player.team, believed)
		if raw_distance <= air_reach and (raw_distance > LOFTED_FROM or (box_target and raw_distance > 12.0)):
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
				"end": lofted_target,
				"success": lofted_success * off_balance,
				"gain": ctx.value.xt_at(player.team, lofted_target, ctx.pitch) * tactics.focus_at(lofted_target.z, ctx.pitch) * (1.15 if is_cross else 1.0),
				"loss": ctx.value.xt_at(SimConsts.other_team(player.team), lofted_target, ctx.pitch),
				"flight": flight,
				"bias": tactics.direct_bias() * LOFTED_BIAS * (1.0 / (1.0 + raw_distance * 0.055))
					* SimPatterns.pass_bias(ctx, player, mate_id, lofted_target) * _call_bias(ctx, mate),
			})
			_keep_parts()


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
		# Ranked on where he is going, if he has committed to going anywhere.
		#
		# `player_threat` is the expected threat of the grass a man is standing on,
		# and for a man mid-run that is the grass he is trying to leave -- so the
		# run that is worth passing to was competing for a place on the list on the
		# strength of the position it was made *from*. Measured: 55% of moves into
		# space and 38% of runs past the last defender were never a scored candidate
		# at all. Not rejected -- never asked about.
		var offer := SimOffBall.destination_for(ctx, mate)
		if not is_inf(offer.x):
			threat = maxf(threat, ctx.value.xt_at(player.team, offer, ctx.pitch))
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
	# Nor the man going past the last defender. Ranking him at his destination
	# above gets him onto most lists; this is the guarantee, and it is worth
	# spending a slot on because the alternative is the best ball in football
	# being invisible. Bounded by the quota in `SimOffBall`, which allows two.
	for mate_id in _short_ids:
		if SimOffBall.intent_of(ctx, ctx.players[mate_id]) == SimOffBall.BEHIND \
				and not kept.has(mate_id):
			kept.append(mate_id)
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
	return believed + to_dest / span * minf(span, _run_reach(ctx, mate, to_dest, travel))


## As far along a run as the receiver can actually be when the ball arrives.
##
## Two things, and the engine had neither. `reach_in` starts him from the pace he
## is going rather than from his top speed, which is what a lead of `pace x
## travel` assumed; and the pace he is aiming for is the one his intent is being
## run at, which for a drift into a pocket is well under a sprint.
static func _run_reach(ctx: SimContext, mate: SimPlayer, dir: Vector3, travel: float) -> float:
	var capped: float = mate.max_speed() * maxf(SimOffBall.pace_for(ctx, mate), 0.2) * travel
	return minf(SimValueField.reach_in(mate, dir, travel), capped)


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
	# Whether the receiver is there when it is -- and only for a ball to feet.
	#
	# For a ball into space the two lines above and this one are the same question
	# asked twice about the same man. `control_at_time` floors every arrival at the
	# ball's journey and then weighs everyone who could be there against everyone
	# else; the receiver is on the passing side, so his own race is already inside
	# it, and a receiver who cannot get there is weighed at `exp(-(his time - the
	# ball's) / 0.42)`, which is nothing. Multiplying `in_time` on top squares a
	# term that is well under one for every ball worth playing in behind.
	#
	# It is the same mistake the through-ball branch found once before and fixed by
	# deleting the *other* copy of it -- the note is still up there in
	# `_add_passes` -- and this is the half that survived. Measured on the losing
	# candidates: a through ball came back at 0.05 with `space` 0.47 and `in_time`
	# 0.59, while the ones the engine did play completed two times in three.
	#
	# A ball to feet is a different question and keeps it: `space` is a snapshot
	# there, with no notion of when the ball turns up, so nothing else asks whether
	# the man is standing where it is going.
	var in_time := 1.0
	if not into_space:
		var receiver_time := SimValueField.time_to_arrive(receiver, to, receiver.reaction)
		in_time = 1.0 / (1.0 + exp(-(travel + 0.3 - receiver_time) / 0.45))
	var lane := _lane_survival(ctx, player, from, to, travel, LANE_TAIL if into_space else 0.0)
	var control: float = lerpf(0.72, 0.99, receiver.attrs.first_touch)
	var distance := SimConsts.horizontal_length(to - from)
	# The line is handed to the accuracy estimate, not just its length, so the ball
	# the passer would have to hit blind off his back foot is priced as the harder
	# ball it is. Without it the engine happily selects a pass it then scuffs, and
	# the facing model shows up only as passes going astray -- never as a player
	# choosing to turn, or to give it to the man he can see instead.
	var struck := SimTouch.execution_accuracy(ctx, player, player.attrs.passing, distance, 0.055, pass_tolerance(distance), to - from)
	_note_parts(space, in_time, lane, control, struck)
	return clampf(space * in_time * lane * control * struck, 0.0, 0.99)


## How far off a pass can land and still be a pass. A longer ball gives the
## receiver more time to adjust to a poor one.
static func pass_tolerance(distance: float) -> float:
	return 2.0 + distance * 0.06


## How much more room a ball in the air has to land in than one along the floor.
##
## `execution_accuracy` asks whether the ball lands inside a tolerance, and the
## tolerance was a rolled ball's for both. It is not the same question. A ball
## rolled at a man's feet either arrives at his feet or runs past him; a ball
## dropped near him hangs long enough to be walked onto, and he can attack it from
## a good deal further away than he can reach with a foot. Nobody heads a ball
## from exactly where they were standing when it was struck.
##
## Measured, the model was pricing the difference the wrong way round. The `struck`
## term for a lofted ball came back at 0.35 and for a cross at 0.34, against 0.82
## for a ground pass -- and lofted balls were the best rejected option 403 times in
## ten minutes while the ones that got played completed at 50 to 59%. The larger
## aim error a lofted ball is struck with is real and stays; what was wrong was
## measuring it against a target the size of a man's boot.
const AERIAL_TOLERANCE := 1.8


static func _lofted_success(ctx: SimContext, player: SimPlayer, to: Vector3, flight: float, receiver: SimPlayer) -> float:
	# A ball in the air cannot be cut out along the ground, but it is harder to
	# control and easier to attack in the air.
	var arrival := ctx.value.control_at_time(ctx, to, player.team, flight, player.id)
	var aerial: float = lerpf(0.55, 0.95, (receiver.attrs.heading + receiver.attrs.jumping) * 0.5)
	var distance := SimConsts.horizontal_length(to - ctx.ball.pos)
	var struck := SimTouch.execution_accuracy(ctx, player, player.attrs.passing, distance, 0.085, pass_tolerance(distance) * AERIAL_TOLERANCE, to - ctx.ball.pos)
	# `struck` carries the passer's own skill as well here, and the two terms a
	# ground ball has and this one does not come back as 1.0 rather than as a gap.
	_note_parts(arrival, 1.0, 1.0, aerial, struck * lerpf(0.7, 0.95, player.attrs.passing))
	return clampf(arrival * aerial * struck * lerpf(0.7, 0.95, player.attrs.passing), 0.0, 0.97)


## How much of the far end of a lane belongs to the destination rather than to
## the journey, for a ball played into space.
##
## The two halves of a pass model divide at the target: `control_at_time` prices
## who owns the place it is going, `_lane_survival` prices getting there. Drawing
## that line exactly at the target charges the last defender twice -- he is stood
## by the target, so he counts in the first, and the last stride of the lane runs
## past him, so he counts again in the second. Six metres is about what
## `CONTROL_TAU` is already weighing at the far end.
const LANE_TAIL := 6.0


## Probability no opponent intercepts along the line. Only opponents actually
## near the line are considered, which keeps this cheap.
##
## `tail` is how much of the far end to leave to the destination model. Zero for
## a ball to feet, where nothing else has priced the man marking him.
static func _lane_survival(ctx: SimContext, player: SimPlayer, from: Vector3, to: Vector3, travel: float, tail: float = 0.0) -> float:
	var survival := 1.0
	var seg := SimConsts.horizontal(to - from)
	var length: float = maxf(seg.length(), 0.1)
	var dir := seg / length
	var journey: float = maxf(length - tail, length * 0.5)
	for oid in ctx.opponent_ids(player.team):
		var o := ctx.players[oid]
		if not o.on_pitch:
			continue
		var rel := SimConsts.horizontal(o.pos - from)
		var along: float = rel.dot(dir)
		if along <= 0.5 or along >= journey:
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
## The distance to price it against is not where the touch puts the ball relative
## to the carrier: the ball is struck to be `ahead` metres clear of a man who
## keeps running, so in the world frame it travels much further. `carry_travel`
## is the figure, and this is that inversion.
##
## It used to charge the ball only as far as the point where it has slowed to his
## pace, on the reasoning that the carrier catches it there so it never gets to
## stop. He does not catch it there. That is the moment he *starts* closing, with
## the gap still open and the ball still doing his own speed; he reaches it most
## of the way to where it would have stopped anyway. At a sprint the two figures
## are 16 metres and 25, and the ten metres in between is where the ball crosses
## the line -- measured before this, carries that went out were struck 16.8 m
## inside the nearest line at 11.2 m/s, which passes a 16 m test and rolls 26.
##
## Nothing in between could have caught it either. The ball is beyond his reach
## for that whole stretch, so there is no second touch to shorten it with: the
## decision that put it there is the only one that could have known.
static func carry_room(ctx: SimContext, player: SimPlayer, dir: Vector3, wanted: float) -> float:
	var room := ctx.pitch.run_room(ctx.ball.ground_pos(), dir, LINE_MARGIN)
	if is_inf(room):
		return wanted
	room = maxf(room, 0.0)
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	# `travel = 2 * along * sqrt(2 * decel * ahead) / decel`, solved for `ahead`.
	# The standing case is the other branch: the ball simply goes `ahead`.
	var allowed := room
	if along > 0.01:
		allowed = minf(allowed, room * room * decel / (8.0 * along * along))
	return minf(wanted, allowed)


## The same question for a settling touch, which does not carry his pace at all:
## `SimTouch.settle` strikes it to travel `ahead` over the grass, so the room test
## is the plain one. Asking `carry_room` -- which assumes a moving frame -- refused
## a sprinting player a forward settle he could comfortably make.
static func settle_room(ctx: SimContext, player: SimPlayer, dir: Vector3, wanted: float) -> float:
	var room := ctx.pitch.run_room(ctx.ball.ground_pos(), dir, LINE_MARGIN)
	return wanted if is_inf(room) else minf(wanted, maxf(room, 0.0))


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


## The ground a carry of this size covers before the carrier gets to it.
##
## Two stages, and leaving out the second is what let carries run off the pitch.
## The ball beats him by `delta` and that decays at the rolling rate, so after
## `delta / decel` seconds it is down to his pace with the gap fully open at
## `ahead` -- and he has closed nothing. Only then does he start gaining, and
## closing `ahead` metres on a ball that is still rolling takes as long again.
## The two stages come to `2 * along * delta / decel`, which at a sprint is 25 m
## against the 16 the first stage alone reports.
##
## Floored at `ahead`, which is the standing case: no pace to add, so the ball
## goes exactly as far as the touch was struck to send it.
static func carry_travel(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	var delta: float = sqrt(2.0 * decel * maxf(ahead, 0.0))
	return maxf(ahead, 2.0 * along * delta / decel)


## How long that takes -- the other half of `carry_travel`, and the half the
## engine kept implicit.
##
## A knock has a duration and it is not small. Nine metres in front of a man at
## 7.9 m/s puts the ball 43 m down the pitch and him on it five and a half
## seconds later, which is longer than most passing moves. Anything that prices
## the end of a carry -- who owns that grass, what it is worth by the time he
## gets there -- is answering a question about a board five seconds from now, and
## has to be told so.
##
## Read off the runner, not off the ball. The ball rolls further than this and
## stops later; the contest is where he meets it, and at pace that is
## `travel / along` -- the same `2 * delta / decel` the two stages above come to.
## Standing still he has no pace to run it down with, so the honest answer is the
## ball's own roll to a stop.
static func carry_time(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	var rolling: float = sqrt(2.0 * decel * maxf(ahead, 0.0)) / decel
	if along <= 0.01:
		return rolling
	return maxf(rolling, carry_travel(ctx, player, dir, ahead) / along)


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
		# The size of the touch follows the room the direction actually buys, so
		# getting away from a man is a knock into space and being hemmed in is a
		# short one under the sole.
		#
		# Read off `reach` and not off `success`, which is what it used to be. The
		# score is a composite -- pitch control, the escape race, the body angle,
		# the touchline odds -- and every one of those terms is high for the
		# direction the softmax is about to pick, so taking the size from it meant
		# the chosen touch was the long one whatever the traffic in front of him.
		# This is the room, in metres, and nothing else.
		var space: float = clampf((reach - SimTouch.DRIBBLE_AHEAD_FLOOR)
			/ maxf(DRIBBLE_DISTANCE - SimTouch.DRIBBLE_AHEAD_FLOOR, 0.1), 0.0, 1.0)
		# And where that touch puts the ball, asked of the primitive that will play
		# it rather than guessed at here.
		#
		# This is the distance the horizon was never meant to stand in for. A man
		# jogging knocks it two metres and is back on it in half a second, which is
		# the carry the horizon describes. The same touch at 7 m/s is a different
		# act: his own pace goes into the strike, the ball leaves at 11, and it runs
		# twenty-six metres before he is near it again. Scored at the horizon, that
		# is a four-metre carry into open grass; played, it is a square ball to
		# whoever is standing twenty metres away, and the panel and the pitch
		# disagreed about which had happened.
		#
		# So the probe looks as far as the ball goes, or as far as the horizon,
		# whichever is further. The horizon stays because it is what stops a walking
		# carrier probing the metre in front of his feet and finding it empty; the
		# roll is added because it is where the ball ends up.
		var ahead := SimTouch.dribble_ahead(ctx, player, space, 0.0, reach)
		var look: float = maxf(horizon, carry_travel(ctx, player, dir, ahead))
		# Bias the probe set toward the way this team attacks, so a right-back
		# does not consider dribbling into their own net as often as forward.
		var target := ctx.pitch.clamp_to_pitch(player.pos + dir * look, 1.0)
		var forwardness: float = dir.x * attack
		var escape := _escape_value(challenger, player, target)
		# When the contest at the far end happens, which is when he is there with
		# it. `control_at_time` is then the same question a ball into space is
		# priced with -- who owns that grass at the moment it matters, rather than
		# who is standing nearest to it now.
		var when := SimValueField.time_to_arrive(player, target, 0.0)
		var success := ctx.value.control_at_time(ctx, target, player.team, when)
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
		# And whether it survives the journey, which is the term a carry never had.
		#
		# A ball knocked past a man rolls through everything between here and
		# there. `control_at_time` asks who owns the far end; it cannot see the
		# defender standing eight metres along the line, because he is not near the
		# far end and never needed to be -- he sticks a leg out as it goes past. It
		# is the same question a pass is asked and the same function that answers
		# it, and a carry that outruns its own carrier *is* a pass, played to
		# whoever happens to be standing in it.
		#
		# It costs nothing on the carry that stays under his sole: the lane is two
		# metres long, and `_lane_survival` only counts opponents between the ends
		# of it.
		success *= _lane_survival(ctx, player, ctx.ball.ground_pos(), target, when)
		_candidates.append({
			"action": Action.DRIBBLE,
			"point": target,
			"end": target,
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
			# The room the direction buys, in metres, and nothing else. Worked out
			# above, where the touch it sizes is worked out.
			"space": space,
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
	# And every term below is read where the ball ends up, which is a long way
	# past where the gap opens.
	#
	# `push` is a distance between two moving things: the daylight left between
	# the ball and a man who keeps running. The ball's own journey is that plus
	# every metre he covers while it is still faster than him --
	# `travel = push + along * delta / decel`, which is `carry_travel`. At a
	# roll of 2.4 and a nine-metre knock the ball is out in front for 2.7 s, and
	# a carrier at 6 m/s runs 16 of the 25 metres it covers. Two and a half to
	# three and a half times `push`, rising with his pace.
	#
	# The ordinary carry has the same geometry and does not have the problem,
	# because he plays it again every third of a second and the gap never opens.
	# The burst is the one touch in the engine that runs to completion -- not
	# re-touching *is* the act -- so it is the only candidate whose ball really
	# travels the whole distance, and scoring it at `push` asked who owned the
	# grass, who won the race and what it was worth a third of the way there.
	# The touchline half of this was already converted, in `_room_ahead`; these
	# four terms sat four lines below it and were not.
	#
	# `carry_travel` is where the ball has slowed to his pace, which is the
	# moment he starts closing rather than the moment he arrives. The contest is
	# near there, and it is the last point on the journey the engine can name
	# without modelling the chase itself.
	var arrival := ctx.pitch.clamp_to_pitch(
		ctx.ball.ground_pos() + burst_dir * carry_travel(ctx, player, burst_dir, push), 1.0)
	# How long the ball is out there, and it is the whole of what was wrong with
	# the terms below.
	#
	# `control_at` is a snapshot: it asks who reaches a point first from where
	# everyone stands *now*, and weighs each man by how far behind the earliest
	# arrival he is. Asked about a point 43 m away that is a question with a
	# perverse answer. The carrier's own arrival is 5.5 s, the nearest defender's
	# is 2, and `CONTROL_TAU` is 0.42 -- so the man whose carry this is counts
	# `exp(-3.5 / 0.42)`, a quarter of a thousandth, and what came back as the
	# success of his burst was his *teammates'* share of grass he is the one
	# running onto. It reads about 0.28 in midfield and it is not a claim about
	# him at all. The complaint that found it was the plain one: he can never get
	# there first, and nothing in the number ever asked whether he could.
	#
	# `control_at_time` is that question asked properly. Nobody wins a ball before
	# it arrives, so every arrival is floored at the ball's journey -- which puts
	# the carrier and every defender who can cover the ground in 5.5 s on level
	# terms, and then the count of bodies decides it, which is what a ball knocked
	# into a defended third is actually decided by. It is the same function a
	# lofted pass into the box is priced with, for the same reason.
	var burst_seconds := carry_time(ctx, player, burst_dir, push)
	var burst_escape := _escape_value(challenger, player, arrival)
	var burst_success := ctx.value.control_at_time(
		ctx, arrival, player.team, burst_seconds, challenger.id if challenger != null else -1)
	burst_success *= skill * burst_escape
	# The same question the carry above is asked. `_room_ahead` shortens the knock
	# to fit the grass, which stops him aiming it off the pitch, and says nothing
	# about his aiming it *near* the line and mishitting it -- and this is the
	# touch with the longest travel in the game, so the aim error has the furthest
	# to spread. Left unpriced while the carry was priced, the softmax simply
	# moved the problem: carries out of play fell by a fifth and bursts out of
	# play rose by a fifth.
	burst_success *= _in_play_odds(ctx, player, burst_dir, push)
	# The longest lane in the game, and the one most likely to have somebody
	# standing in it. Same term as the carry above and as every pass.
	burst_success *= _lane_survival(ctx, player, ctx.ball.ground_pos(), arrival, burst_seconds)
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
		# Where he runs, too. `_execute` hands this to the movement layer, and a
		# man who has knocked it twenty-five metres past a defender should not be
		# setting off toward the nine-metre mark.
		"point": arrival,
		"end": arrival,
		"dir": burst_dir,
		"escape": burst_escape,
		"away": _awayness(challenger, player, burst_dir),
		"success": clampf(burst_success, 0.0, 0.98),
		"gain": ctx.value.xt_at(player.team, arrival, ctx.pitch) * tactics.focus_at(arrival.z, ctx.pitch),
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), arrival, ctx.pitch),
		# The longest action in the game, and until this it was discounted as
		# though it took a second like everything else. See `DISCOUNT_SECONDS`.
		"seconds": burst_seconds,
		"space": 1.0,
		# The execution has to push it as far as the score assumed it would. A
		# candidate scored on a nine-metre knock and then played as a four-metre
		# touch is the decision layer lying to itself about its own option.
		"push": push,
		"bias": tactics.retention_bias() * lerpf(0.9, 1.25, player.attrs.pace) * settle,
	})


## Where the ball ends up if he holds it, which is two different places.
##
## A settling touch leaves it a metre in front of him on the grass -- that is
## what `SimTouch.settle` is for -- so his own feet are the right place to read
## it, to within a stride.
##
## A ball arriving with pace on it is not that act at all. `_play_hold` sends it
## to `SimTouch.first_touch`, which is a cushion and not a stop: an ordinary one
## leaves 2.6 to 3.5 m/s on the ball, one to two and a half metres of it, in a
## direction the receiver only partly chooses. Scored at his feet, that was the
## settling touch's bug in miniature -- the option said the ball stays here and
## the engine then moved it. `SimTouch.first_touch_drift` is the execution's own
## model asked in advance, so the two layers cannot drift apart again.
##
## Since `_hold_score` went in this feeds the loss term alone -- where the ball
## would be handed over, which for a first touch is a metre or two from where it
## was received. The gain half of the question is no longer asked here, because a
## hold is not worth the grass it sits on. It is worth what he does next.
##
## What this deliberately does not do is grade the *option* on how well he will
## take it. `success` is the chance his side still has the ball afterwards, and
## measured it is already about right: 86-92% kept three seconds later across all
## three bands of `Taking it down`, against the 0.72-0.97 this reads off the
## attribute.
static func _hold_rest_point(ctx: SimContext, player: SimPlayer, uncontrolled: bool) -> Vector3:
	if not uncontrolled:
		return player.pos
	var dir := safe_direction(ctx, player, HOLD_AHEAD)
	var drift := SimTouch.first_touch_drift(ctx, player, dir)
	return ctx.pitch.clamp_to_pitch(ctx.ball.ground_pos() + drift, 1.0)


static func _add_hold(ctx: SimContext, player: SimPlayer, uncontrolled: bool, regain: float) -> void:
	var tactics := ctx.tactics(player.team)
	var rest := _hold_rest_point(ctx, player, uncontrolled)
	# Standing over the ball as a challenge comes in is how the ball is lost, and
	# it is the option the engine used to take almost every time, because the
	# pressure field it reads rates the man on the carrier's back at nearly
	# nothing. `success` is the only term here that says so.
	var success: float = lerpf(0.72, 0.97, player.attrs.first_touch)
	success -= ctx.pressure_on(player) * 0.16 + ctx.challenge_on(player) * 0.30
	_candidates.append({
		"action": Action.HOLD,
		# Not `point`: nothing executes a hold from a target, and the overlay
		# draws no arrow for it. It is where the ball would be handed over.
		"end": rest,
		"success": clampf(success, 0.05, 0.98),
		# Filled in by `_hold_score`, which is the only place a hold's value can
		# be worked out: it is the best of the other candidates, and they do not
		# exist yet. Written back so the debug overlay reports the number that
		# was used rather than one nothing reads.
		"gain": 0.0,
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), rest, ctx.pitch),
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
		"end": landing,
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
##
## It is an average over the pitch, and `TERRITORY` says where.
const POSSESSION_VALUE := 0.013

## How much more a possession is worth at the far end of the pitch than at your
## own goal line, as a fraction either side of the average above.
##
## This is the term that sends the ball forward, and it is not a taste knob. It
## is there because expected threat as this engine bakes it is flat at the back
## and the flatness is not football: 0.0001 on your own eighteen-yard line, 0.004
## at the halfway line, against the 0.013 the engine adds for merely having the
## ball. Thirty-five metres of ground gained -- the whole of your own half --
## moved a candidate's score by under a third of what having the ball at all is
## worth, and `_add_passes` then multiplied that positional difference by a
## length bias of about a fifth while `POSSESSION_VALUE` went in untouched.
##
## What was left deciding between a pass forward and a pass back was `success`.
## The ball rolled back to a man with nobody near him is the highest success on
## the list by construction, so that is the ball that got played -- the same
## shape as the hold's, in `_hold_score`, from the same cause.
##
## Lifting the map instead does not work, and the reason is worth keeping. The
## map is read twice, once as `gain` where the ball is going and once as `loss`
## for the opponent at the same point, and only `gain` is scaled by the bias. Add
## the same territory to both and the loss half wins: a flatter map makes the
## *forward* pass score worse. Territory has to be priced where the bias cannot
## reach it, which is here, beside `POSSESSION_VALUE` and added after it.
##
## At 0.4 a possession runs from three fifths of the average on your own goal
## line to seven fifths of it on theirs: 0.0001 of goal probability per metre up
## the pitch. An ordinary fifteen-metre ball forward is worth about a ninth of
## the ball itself, the same ball backwards costs the same again, and it is
## charged twice, because a turnover there hands the opponent a possession by the
## same measure. It stays a small correction where expected threat is steep --
## 0.018 against 0.3 inside the box -- and is the whole positional signal where
## the map is flat, which is the region the ball would not leave.
##
## The size is held down by a mechanic that does not exist. Territory is credited
## in metres, so the ball that gains most of it is the long one, and a long ball
## escapes the length bias entirely because this term is added after it. What
## should be paying for that is the cost of losing it stretched -- the same thing
## the knock past a man cannot price, three hundred lines up -- and nothing in a
## single-step model can say it. `success` carries what there is: 0.47 on a thirty
## metre ball against 0.9 on a short one.
##
## So it was measured for character rather than fitted to anything. On seed 7 at
## ten minutes, against the same engine with this at zero: passes backwards 42% ->
## 33%, forward 39% -> 56%, ground gained per possession 5.2 m -> 8.7 m, touches
## in the final third 9% -> 16%, shots 14 -> 15, and a possession still 2.4 passes
## long against 3.2. At 0.75 the ball goes further forward again and the engine
## stops being a passing side: 37% of every ball long and forward at 47%
## completion, possessions of 1.4 passes, 34 shots. One seed, ten minutes.
const TERRITORY := 0.4

## The same term for a match compressed to three minutes. See `SimMatchConfig`,
## "the compressed match's scoring fit" — this is a fourth knob in that fit and
## belongs to it, kept here only because it reads `POSSESSION_VALUE` beside it.
##
## 0.75 is the other column of the measurement above, and the objection recorded
## there — that it stops the engine being a passing side, possessions of 1.4
## passes, a third of every ball long and forward at 47% completion — is the
## right objection to a ninety-minute match and beside the point in one holding
## fifty possessions. Measured on its own it moved goals not at all (0.39 to
## 0.32 over forty compressed matches) while raising touches in the box by a
## quarter, which is the whole reason it is here: it delivers the ball to the
## area, and the three knobs beside it are what make arriving there worth
## something.
const TERRITORY_URGENT := 0.75


## How far up the pitch a possession is worth more than at the back, for the
## match being played. See `TERRITORY` and `SimMatchConfig.urgency`.
static func territory(ctx: SimContext) -> float:
	return lerpf(TERRITORY, TERRITORY_URGENT, ctx.config.urgency())


## What having the ball at a point is worth to a team, in goal probability.
static func possession_value(ctx: SimContext, team: int, point: Vector3) -> float:
	var progress: float = clampf(
		point.x * ctx.pitch.attack_dir(team) / ctx.pitch.half_length, -1.0, 1.0)
	return POSSESSION_VALUE * (1.0 + territory(ctx) * progress)


## What a turnover costs beyond the ball, as a multiplier on every `loss`.
##
## Expected threat answers what the *ball* is worth where it was lost, and for a
## ball given away twenty metres from their goal the answer is nothing: the
## opposition have it beside their own corner flag, which is the worst place on the
## pitch to have it. Measured, the `loss` on a through ball came back at 0.0002.
## Ninety per cent of the time it is cut out and the model says that costs you
## approximately zero.
##
## Every footballer knows it does not. What it costs is not where the ball is, it
## is where *you* are: eight men committed, a back line on the halfway line, and
## fifty metres of grass behind it for them to run into. `TERRITORY` has this
## exactly backwards -- it says a possession won deep in one's own half is worth
## less than average, which is true of building through a set defence and false of
## breaking against a side that has just lost it in your box.
##
## So the turnover is priced off the shape rather than off the ball. The reference
## is the second-deepest outfielder, which is the defensive line -- the deepest is
## often a full-back who has not got back yet, and taking the minimum would let one
## slow man tell the whole team it was safe.
##
## It scales every option's loss alike and does its discriminating through
## `(1 - success)`: an option that comes off nine times in ten hardly feels it, and
## a one-in-ten ball played with the side committed is priced as what it is. That
## is the shape a risk term should have.
const EXPOSURE_MAX := 2.5
## Where the line has to get to before any of this bites, and where it saturates,
## as a fraction of the pitch's length from one's own goal.
##
## Fitted to what this engine's shapes actually do, having first been guessed at a
## quarter and two thirds -- which sounded like football and was inert, because the
## defensive line here averages 28% up the pitch and the term therefore averaged
## 1.16 and never varied. That is the failure mode of a constant chosen from a
## mental picture rather than from the engine, and it is why the mean is printed
## in `diagnose` beside the table it feeds.
const EXPOSURE_FROM := 0.22
const EXPOSURE_TO := 0.42

static var _exposure := PackedFloat32Array()
static var _exposure_tick := -1

## What the exposure multiplier actually came out at over the match, so a constant
## chosen for a range the engine never reaches shows up as one. Summed once per
## tick per team, alongside where the line was that made it.
static var exposure_sum := 0.0
static var exposure_line := 0.0
static var exposure_n := 0.0


## Cached per tick, because it is a fact about the shape rather than about any one
## candidate and `score_of` is called a dozen-odd times per decision.
static func turnover_exposure(ctx: SimContext, team: int) -> float:
	if _exposure.size() != 2:
		_exposure.resize(2)
		_exposure_tick = -1
	if _exposure_tick != ctx.tick_index:
		_exposure_tick = ctx.tick_index
		_exposure[0] = _measure_exposure(ctx, 0)
		_exposure[1] = _measure_exposure(ctx, 1)
	return _exposure[team] if team == 0 or team == 1 else 1.0


static func _measure_exposure(ctx: SimContext, team: int) -> float:
	var dir := ctx.pitch.attack_dir(team)
	var own_goal := ctx.pitch.own_goal(team)
	var deepest := INF
	var line := INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if not p.on_pitch or p.is_keeper:
			continue
		var up := (p.pos.x - own_goal.x) * dir
		if up < deepest:
			line = deepest
			deepest = up
		elif up < line:
			line = up
	if is_inf(line):
		return 1.0
	var full: float = maxf(ctx.pitch.half_length * 2.0, 1.0)
	var t: float = clampf((line / full - EXPOSURE_FROM) / maxf(EXPOSURE_TO - EXPOSURE_FROM, 0.01), 0.0, 1.0)
	var out: float = lerpf(1.0, EXPOSURE_MAX, t)
	exposure_sum += out
	exposure_line += line / full
	exposure_n += 1.0
	return out


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
## invitation; going past the last defender is a demand, and it is the one that
## expires -- he is either found or he is offside, back onside, or blown.
##
## Moving into space used to be third of the three at 1.08, on the reasoning that
## it is barely more than standing well. It was, when it was a six-metre shuffle.
## It is now a nine-metre run gaining seven up the pitch, and 1.08 against the
## length bias -- which is `1 / (1 + distance x 0.21)`, so 0.19 at twenty metres
## against 0.32 at ten -- charged him for the running. Measured, a committed offer
## of any kind held about 7% of the softmax weight, against the 6% an option
## nobody favours gets on a list of seventeen: the whole receiver's half of the
## decision was worth one percentage point.
##
## These are priors on a value the decision layer was going to use anyway
## (PLAN.md §5.1), not a rule that the ball goes to whoever shouted.
const CALL_SHOW := 1.15
const CALL_SPACE := 1.3
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


## `delay` is one further step of waiting, and only the hold passes anything but
## 1.0: it is how a deferred option is priced against the same option taken now.
## It multiplies the gain and never the loss, which is what makes waiting cost
## something at every sign -- a good option decays toward nothing while a bad one
## stays exactly as bad.
static func score_of(ctx: SimContext, player: SimPlayer, c: Dictionary, delay: float = 1.0) -> float:
	var tactics := ctx.tactics(player.team)
	var success: float = c["success"]
	var gain: float = c["gain"] * delay
	var loss: float = c["loss"]
	# Where the possession stands once the option has been played, which is what
	# decides what having it -- or handing it over -- is worth. Every candidate
	# carries it, the shot included, where it is the deep restart its `loss` is
	# already read at.
	var settles: Vector3 = c["end"]
	if c["action"] != Action.SHOOT:
		# Value that only arrives later is discounted; a high-tempo side
		# discounts harder and therefore releases the ball sooner.
		#
		# Charged per second of the action, because the actions are not the same
		# length. `future_discount` is a rate over `DISCOUNT_SECONDS`, and applying
		# it once to everything priced a five-second knock down the pitch exactly
		# as it priced a five-metre pass. A candidate that knows its own duration
		# says so; everything else is a second, which is what the flat version
		# assumed for all of them.
		gain *= pow(tactics.future_discount(),
			float(c.get("seconds", DISCOUNT_SECONDS)) / DISCOUNT_SECONDS)
		# The bias scales the positional value of the option, never the whole
		# expression: a penalty applied to a negative score would make a bad
		# option look better. Possession value is added after it for the same
		# reason it is not discounted: it is not a claim about a position the
		# plan has an opinion on, it is the ball.
		gain = gain * float(c.get("bias", 1.0)) + possession_value(ctx, player.team, settles)
	else:
		gain *= float(c.get("bias", 1.0))
	loss += possession_value(ctx, SimConsts.other_team(player.team), settles)
	loss *= turnover_exposure(ctx, player.team)
	return success * gain - (1.0 - success) * tactics.risk_weight() * loss


## The delay one application of `tactics.future_discount()` stands for, in
## seconds, and so the duration assumed for any candidate that does not carry a
## `seconds` of its own.
##
## Implicit until a hold needed to be priced against the same option taken now,
## and wrong the moment it was left implicit. `future_discount` is a discount on
## an *action* -- a pass in flight, a carry into space, something on the order of
## a second. A hold defers by one touch cooldown, 0.17 to 0.27 s, and charging it
## a whole action's discount for a fifth of a second's wait is a units error.
##
## Measured, it is not a small one. Charged in full, the hold stops being chosen
## at all and the engine plays one-touch football: on seeds 7 and 3 at ten
## minutes, ground passes 218 and 314 against a real match's hundred-odd, carries
## down to 31 and 55, and 27 first touches in a whole match because every ball is
## played away before it is controlled. Charged per second of actual delay, one
## hold costs about four per cent and eleven in a row cost a third, which is the
## shape that was wanted.
const DISCOUNT_SECONDS := 1.0


## What waiting one more touch costs, as a multiplier on the deferred option.
static func _wait_discount(ctx: SimContext, player: SimPlayer) -> float:
	var steps: float = player.touch_cooldown_length() / DISCOUNT_SECONDS
	return pow(ctx.tactics(player.team).future_discount(), steps)


## What a hold is worth: the decision it defers, not the ball it keeps.
##
## Every other candidate resolves the possession. A pass ends with the ball at
## the target and a new situation on the pitch; a shot ends the possession
## outright. `score_of` states what the possession is worth afterwards, and for
## those that is a complete statement.
##
## A hold states nothing. The ball is where it was, he still has it, and he still
## has to decide -- so scoring it as `POSSESSION_VALUE` plus the grass under his
## feet credited him for retaining what was never at stake, and did it again
## every touch cooldown. Since expected threat is flat through the middle third,
## `POSSESSION_VALUE` was thirteen times the whole positional signal there and
## every candidate's gain collapsed to roughly the same number. What was left
## discriminating between them was `success` -- and the hold is the highest
## success by construction, because it is the option defined as not attempting
## anything. Measured on seed 2, one midfielder held eleven times in a row at
## 95-100% of the softmax weight, with a through ball on the list whose
## positional gain was twelve times the hold's scoring negative.
##
## So a hold is priced as one step of waiting: with `success` he still has the
## ball and faces the board he faces now, one touch later; otherwise he has lost
## it here. The continuation is the best of his other options put through
## `score_of` again with an extra `future_discount`, which is what makes deferring
## cost something -- a good option decays toward nothing while a bad one stays as
## bad, so the hold can beat a list of losing options and cannot beat a winning
## one. That is the shape that was wanted: hold because there is nothing on, never
## because holding is safe.
##
## Two things it is not. It is not a lookahead -- the board it assumes he will
## face is this one, which is exactly wrong in the case that matters most, a man
## about to be closed down. `success` carries some of that and the extra discount
## carries the rest, crudely. And it is a per-*decision* fix to what is really a
## per-*possession* problem: nothing here counts how long he has already held it,
## because the engine has no representation of a possession as a thing with a
## history. `docs/BACKLOG.md` is where that belongs.
static func _hold_score(ctx: SimContext, player: SimPlayer, c: Dictionary, best_index: int) -> float:
	var tactics := ctx.tactics(player.team)
	var success: float = c["success"]
	var loss: float = (float(c["loss"]) + possession_value(
		ctx, SimConsts.other_team(player.team), c["end"])) * turnover_exposure(ctx, player.team)
	var continuation := 0.0
	if best_index >= 0:
		continuation = score_of(ctx, player, _candidates[best_index], _wait_discount(ctx, player))
	# A prior has to move the option the same way whatever the sign of what it is
	# applied to, and multiplying does not: a bias of 1.5 on a negative
	# continuation makes waiting look *worse*, and `score_of`'s own guard --
	# ignore the bias when the value is negative -- silently drops the prior
	# instead. Both are wrong here, and the second is worse than it sounds: the
	# 1.5 on `uncontrolled` is the whole of "take a touch rather than play a ball
	# that is still moving", and in the middle third the continuation is usually
	# negative, so it was being dropped exactly where it does its work. Measured,
	# first touches fell from 142 in a match to 27. Scaling toward zero for a
	# prior above one, and away from it for one below, keeps a prior a prior.
	var bias: float = maxf(float(c.get("bias", 1.0)), 0.01)
	continuation = continuation * bias if continuation > 0.0 else continuation / bias
	c["gain"] = continuation
	return success * continuation - (1.0 - success) * tactics.risk_weight() * loss


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

	# Two passes, because a hold is not an action in the sense the others are and
	# cannot be scored beside them. See `_hold_score`.
	var best_other := -INF
	var best_index := -1
	for i in n:
		if int(_candidates[i]["action"]) == Action.HOLD:
			continue
		var s := score_of(ctx, player, _candidates[i])
		_candidates[i]["score"] = s
		if s > best_other:
			best_other = s
			best_index = i

	var best := -INF
	var total_score := 0.0
	for i in n:
		if int(_candidates[i]["action"]) == Action.HOLD:
			_candidates[i]["score"] = _hold_score(ctx, player, _candidates[i], best_index)
		var s: float = _candidates[i]["score"]
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
	# What each man offering for it was worth, back to the layer that sent him.
	# A tally and nothing else -- see `SimOffBall.note_offer`.
	if total > 0.0:
		for i in n:
			var offer := int(_candidates[i].get("target", -1))
			if offer >= 0:
				SimOffBall.note_offer(offer, _weights[i] / total)
	var idx: int = ctx.rng.weighted_index(_weights)
	if idx < 0:
		idx = 0
	_note_rejections(idx)
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
	var dir := safe_direction(ctx, player, HOLD_AHEAD)
	if uncontrolled:
		SimTouch.first_touch(ctx, player, dir)
		return
	player.settling = true
	SimTouch.settle(ctx, player, dir, settle_room(ctx, player, dir, HOLD_AHEAD))


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
## Public because `SimAerial` asks the same question of a ball taken down off the
## chest: he is not choosing between candidates, he is putting the ball somewhere
## he can still play it.
static func safe_direction(ctx: SimContext, player: SimPlayer, ahead: float) -> Vector3:
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
	return settle_room(ctx, player, dir, ahead) >= SimTouch.DRIBBLE_AHEAD_FLOOR


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
