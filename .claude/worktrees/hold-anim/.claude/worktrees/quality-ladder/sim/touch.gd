class_name SimTouch
extends RefCounted
## All ball contact (PLAN.md §3.3).
##
## There is no possession flag and the ball is never glued to a foot. Every
## action below is the same primitive -- an impulse plus a spin -- with
## different parameters and different error distributions. A bad first touch
## leaving the ball loose is a feature: 50/50 balls, deflections and scrambles
## come out of it for free.

# How fast a dribbled ball pulls away from the man running alongside it is
# `SimEnv.roll_decel` and nothing else, which is why there is no constant for it
# here any more.
#
# There was one, at 1.25, and it was the same physics carrying a different
# number. A carrier holding his pace *is* a stationary frame for the ball, so the
# rate the gap closes at is the rate the ball slows at -- the rolling resistance
# of the grass, which the engine already knows. Two numbers for one quantity is a
# thing that drifts, and this one had:
#
#   - The touch never opened the gap it was struck to open. `dribble` picks the
#     strike speed from the constant and the grass then does the arithmetic, so
#     at 1.25 against a real 1.6 a touch played to sit 4.5 m in front actually
#     sat 3.5 m in front -- 78% of it, and the same 78% at every size. Every term
#     the decision layer read off `ahead` was describing a touch that did not
#     happen.
#   - Pitch conditions never reached the carry at all. `roll_decel` is set by
#     grass length and wetness; a constant is set by nothing. On long grass the
#     ball was known to be slow everywhere in the engine except at the feet of
#     the man carrying it, where the same touch opened barely half the gap.
#
# Sharing the one value fixes both, and makes `SimDecision.carry_room` and
# `carry_travel` exact inverses of each other rather than nearly so.


## Base aim error for a dribble touch, in radians before skill, pressure and
## the rest are applied. Named because the decision layer has to ask the same
## question the execution will answer.
const DRIBBLE_AIM_BASE := 0.085

## Base aim error for a shot, in radians before skill, pressure and the rest.
##
## It was 0.28, which is five times the ground pass's 0.055 and made a shot the
## least accurate act in the game — in an engine where the same function also
## covers a clearance and a diving header. Shooting is the most rehearsed thing
## a footballer does; it belongs beside the pass, a little wider for the power.
##
## What 0.28 actually meant: an average player standing unpressured eleven
## metres out struck with a yaw sigma of about 0.35 rad, twenty degrees. One
## standard deviation put the ball 4.1 m off centre against a post at 3.66 m,
## and the 1.6 elevation weighting in `shot` made the vertical miss five metres
## against a 2.44 m bar. Measured over three seeds, twelve shots from the
## penalty spot produced two on target, against a real two-thirds.
##
## The damage was not confined to the finishing. `SimDecision.expected_goals` is
## calibrated against real shot data — 0.26 from the penalty spot, and it says so
## — and never reads this number, so the decision layer priced every shot as a
## footballer's while the execution layer struck it like nobody's. That is the
## whole of the gap between the engine's expected goals and its actual ones:
## summed xG ran at three times the goals scored. Two models of the same event
## disagreeing, which is the failure `CLAUDE.md` calls pricing every path to the
## same outcome.
const SHOT_AIM_BASE := 0.08
## How far ahead a dribble touch places the ball, in metres.
##
## The minimum has to clear `SimConsts.CONTROL_RANGE`, or the ball never leaves
## the dribbler's own reach: they stay a contender in `SimDuel.resolve_contacts`
## and the next touch fires the moment the cooldown expires, re-aiming the ball
## four to six times
## a second. That is not gluing in mechanism — every touch is a real impulse —
## but it is gluing in effect, and it is what makes the ball appear to swing
## round with a turning player. It also makes PLAN.md §10's Phase 1 exit
## criterion, "touches sometimes get away from them", impossible by
## construction. A touch has to be something the player then has to run onto.
const DRIBBLE_AHEAD_MIN := 1.8
const DRIBBLE_AHEAD_MAX := 4.2
## However hard a dribbler is pressed, the touch still has to clear their reach.
const DRIBBLE_AHEAD_FLOOR := SimConsts.CONTROL_RANGE * 1.2
## How far round a first touch can turn the ball from the line it arrived on, in
## radians, from a player with no touch to speak of to one who can take anything
## down facing anywhere. Beyond this he takes what he can now and turns with his
## second touch, which is what taking it on the half-turn means.
const TURN_MIN := 1.15
const TURN_MAX := 2.55
## The most pace a first touch can leave on the ball however hard it arrived, in
## m/s, from a player who cannot control it at all to one who can take anything
## down dead. See `first_touch`: this is what makes killing a driven ball
## possible, which a purely proportional residual cannot express at any setting.
##
## The best figure is deliberately not zero. A ball stopped stone dead under the
## sole is a thing footballers do and mostly do not want -- the touch that gets
## used is the one that leaves it rolling into the next stride, and `settle`
## above pushes it there. This is the ceiling on what survives, not the target.
const CUSHION_WORST := 6.0
const CUSHION_BEST := 0.8
## The hardest a ball can be to take down: struck as firmly as anyone strikes
## one, dropping out of the air, arriving with a man on you, and needing to be
## turned back the way it came. Everything in `first_touch` is measured as a
## fraction of this, so it is a scale rather than a threshold -- nothing is
## clamped by it except a ball that is worse than all four at once.
const DIFFICULTY_MAX := 1.6
## Backspin on a firmly struck ground pass, as a fraction of the rolling rate.
const PASS_BACKSPIN_FRACTION := 0.55
## A lofted ball carries sidespin and nothing else, and that is deliberate.
##
## Backspin was tried here, because a ball struck underneath really does come off
## the boot turning backwards. It was measured out again: backspin on a ball in
## the air is lift, and lift is hang. At a fifth of the rolling rate — 50 rad/s
## on a firmly struck ball, which is ordinary — the Magnus force very nearly
## cancels gravity and a long pass floats like a balloon. Correct, and the exact
## opposite of what a long ball needs to look like. It also stops the flight
## solver converging, since a floating flat trajectory and a proper arc can share
## a flight time.
const LOFT_BACKSPIN := false
## How much having to play the ball away from the way the body is pointing
## multiplies aim error, at its worst — square across the body costs a quarter of
## this, straight back the whole of it.
##
## `PLAN.md` §3.3 lists body orientation as an error source on the pass and this
## is it. What it buys is that the *direction a player is facing becomes a fact
## about the game*: a midfielder turned upfield has a different set of options
## from the same midfielder with his back to play, and the difference is paid for
## rather than announced. Because the decision layer prices its passes through
## `execution_accuracy`, which shares this function, the blind ball back is not
## forbidden — it is simply worth less, so it gets played less often and by the
## players who can actually hit it.
const FACING_COST := 3.6
## The share of that cost a player standing still still pays.
##
## On the spot he can plant and turn his hips; at a sprint he cannot, and the
## ball has to be dug out from under him. He is not charged nothing, and that is
## deliberate: the engine has no notion of *taking a moment* to turn, so a
## stationary player would otherwise get the turn for free and the whole mechanic
## would disappear the instant a carrier slowed down. This fraction is the price
## of the second he does not spend.
const FACING_STATIC_SHARE := 0.5


## True if `player` can physically contact the ball this tick with `kind`.
## Height band a player can play the ball at without jumping.
static func playable_height(player: SimPlayer, ball_y: float) -> bool:
	return ball_y <= SimConsts.HEAD_REACH_HEIGHT + player.attrs.jumping * 0.55


# --- The primitive ----------------------------------------------------------


## Applies an impulse and a spin, stamps provenance, and logs the touch. Every
## action funnels through here.
static func apply(ctx: SimContext, player: SimPlayer, kind: int, vel: Vector3, spin: Vector3, target_id: int = -1, extra: Dictionary = {}) -> void:
	var before := ctx.ball.pos
	ctx.ball.launch(vel, spin)
	ctx.ball.last_touch_player = player.id
	ctx.ball.last_touch_team = player.team
	ctx.ball.last_touch_tick = ctx.tick_index
	ctx.ball.last_touch_kind = kind
	ctx.ball.intended_target = target_id
	player.touch_cooldown = player.touch_cooldown_length()
	player.touches += 1
	player.spend_action(1.0 if kind == SimTelemetry.Touch.DRIBBLE else 2.0)
	# A throw-in's pose is already half over by the time the ball leaves -- the
	# wind-up ran while he stood there holding it -- so it needs longer on the
	# clock than a kick or the follow-through is cut off at the release.
	var thrown: bool = kind == SimTelemetry.Touch.THROW_IN or kind == SimTelemetry.Touch.KEEPER_THROW
	player.play_anim(_anim_for(kind, vel.length()), 0.45 if thrown else 0.2)

	var data := {
		"p": player.id,
		"team": player.team,
		"kind": kind,
		"from": before,
		# Where the player was standing when they made contact. Without it the
		# log cannot answer how far away a player was when they played the ball,
		# which is the only way to tell a plausible touch from a magnetic one.
		"at": player.pos,
		"vel": vel,
		"spin": spin,
		"press": ctx.pressure_on(player),
		# What the carrier was being asked to deal with when he chose this. The
		# only way to answer "does he still stay in the challenge every time" is
		# to bucket his touches by how imminent the challenge was, and pressure
		# cannot stand in for it -- it rates the man on his back at nearly zero.
		"chal": ctx.challenge_on(player),
	}
	if target_id >= 0:
		data["target"] = target_id
	for key in extra:
		data[key] = extra[key]
	ctx.log_event(SimTelemetry.Ev.TOUCH, data)


static func _anim_for(kind: int, speed: float) -> int:
	match kind:
		SimTelemetry.Touch.HEADER:
			return SimConsts.Anim.HEADER
		SimTelemetry.Touch.TACKLE:
			return SimConsts.Anim.SLIDE
		SimTelemetry.Touch.KEEPER_CATCH:
			return SimConsts.Anim.KEEPER_CATCH
		SimTelemetry.Touch.THROW_IN, SimTelemetry.Touch.KEEPER_THROW:
			# The wind-up is already running -- `SimSetPiece.update` starts it when
			# the thrower picks the ball up -- and naming the same anim again here
			# leaves its phase alone, so the release lands in the middle of the
			# arc rather than restarting it.
			return SimConsts.Anim.THROW
		_:
			return SimConsts.Anim.KICK_HARD if speed > 14.0 else SimConsts.Anim.KICK_LIGHT


# --- Error model ------------------------------------------------------------


## Angular error, in radians, for an action. Every source of difficulty in the
## game funnels through this function.
##
## `dir` is the line the ball is being played along, and passing it in is what
## charges the action for the body being turned away from it. Left out, the
## action is treated as one the body is set for -- which is right for a header, a
## hack clear or anything else struck wherever the player happens to be pointing.
static func aim_sigma(ctx: SimContext, player: SimPlayer, skill: float, distance: float, base: float, dir: Vector3 = Vector3.ZERO) -> float:
	var press := ctx.pressure_on(player)
	var speed_ratio: float = player.speed() / maxf(player.nominal_max_speed(), 1e-3)
	var sigma := base
	sigma *= lerpf(1.9, 0.45, clampf(skill, 0.0, 1.0))
	sigma *= 1.0 + 0.16 * press
	sigma *= 1.0 + 0.35 * speed_ratio * speed_ratio
	sigma *= 1.0 + 0.012 * maxf(distance - 12.0, 0.0)
	sigma *= lerpf(1.25, 0.9, player.attrs.composure)
	sigma *= facing_penalty(player, dir)
	sigma /= maxf(player.fatigue_factor(), 0.5)
	return sigma


## Multiplier on aim error for playing the ball along `dir` rather than straight
## ahead of the body: 1.0 straight ahead, rising as the ball has to be worked
## across the body, and worst of all straight back.
##
## The skill it reads is deliberately not the skill of the action. Technique and
## agility are what let a player open his hips and strike a ball he is not
## looking at, so a gifted midfielder can clip one back off the outside of his
## foot at pace and a merely accurate passer has to take the extra touch first.
## Nothing here forbids the pass behind; it makes it a thing only some players
## can do well, which is the point.
static func facing_penalty(player: SimPlayer, dir: Vector3) -> float:
	var d := SimConsts.horizontal(dir)
	var length := d.length()
	if length < 1e-6:
		return 1.0
	var ahead: float = player.heading_dir().dot(d / length)
	# 0 straight ahead, 0.5 square, 1 straight back. Squared, so playing it square
	# across the body costs a quarter of turning it all the way round rather than
	# half: opening up to play the ball sideways is ordinary football, and hitting
	# one you cannot see is not.
	var off: float = (1.0 - clampf(ahead, -1.0, 1.0)) * 0.5
	var deftness: float = clampf(player.attrs.technique * 0.6 + player.attrs.agility * 0.4, 0.0, 1.0)
	var speed_ratio: float = clampf(player.speed() / maxf(player.nominal_max_speed(), 1e-3), 0.0, 1.0)
	var momentum: float = lerpf(FACING_STATIC_SHARE, 1.0, speed_ratio)
	return 1.0 + FACING_COST * off * off * lerpf(1.0, 0.28, deftness) * momentum


## The share of a touch's control that survives being played along `dir`: 1.0
## straight ahead, falling away behind.
##
## The reciprocal of `facing_penalty`, and it exists so that a candidate priced
## with this and a touch struck with `aim_sigma` are talking about the same
## thing. A decision layer that scores a turn it cannot execute is the same bug
## as one that scores a nine-metre knock and then plays a four-metre touch.
static func facing_control(player: SimPlayer, dir: Vector3) -> float:
	return 1.0 / facing_penalty(player, dir)


## Multiplicative weight error on a struck ball.
static func weight_sigma(player: SimPlayer, skill: float) -> float:
	return lerpf(0.19, 0.055, clampf((skill + player.attrs.technique) * 0.5, 0.0, 1.0))


## Probability that a struck ball actually lands within `tolerance` of where it
## was aimed, given the same error model the execution uses.
##
## The decision layer needs this: without it, a value function happily picks a
## forty-metre ball because the target square looks good, having no idea the
## player cannot hit it. Sharing `aim_sigma` means tuning the error model
## automatically retunes what the engine is willing to attempt.
static func execution_accuracy(ctx: SimContext, player: SimPlayer, skill: float, distance: float, base_sigma: float, tolerance: float, dir: Vector3 = Vector3.ZERO) -> float:
	var sigma := aim_sigma(ctx, player, skill, distance, base_sigma, dir)
	var lateral := sigma * distance
	var longitudinal := weight_sigma(player, skill) * distance
	return _within(tolerance, lateral) * _within(tolerance, longitudinal)


## P(|X| < r) for a zero-mean normal, via the usual logistic approximation to
## the normal CDF. Accurate to about one part in a hundred, and far cheaper.
static func _within(r: float, sigma: float) -> float:
	if sigma < 1e-4:
		return 1.0
	return clampf(2.0 / (1.0 + exp(-1.702 * r / sigma)) - 1.0, 0.0, 1.0)


static func _perturb(ctx: SimContext, vel: Vector3, sigma_rad: float, weight_sigma_v: float, elevation_scale: float = 1.0) -> Vector3:
	var yaw: float = ctx.rng.gauss_clamped(0.0, sigma_rad, 2.8)
	var out := vel.rotated(Vector3.UP, yaw)
	if elevation_scale > 0.0:
		# Elevation error tilts the launch in the vertical plane containing the
		# shot. Flat balls are far less sensitive to it than lofted ones.
		var horiz := SimConsts.horizontal(out)
		var hl := horiz.length()
		if hl > 1e-4:
			var axis := horiz.cross(Vector3.UP) / hl
			var pitch_err: float = ctx.rng.gauss_clamped(0.0, sigma_rad * 0.75 * elevation_scale, 2.8)
			out = out.rotated(axis, pitch_err)
	var weight: float = 1.0 + ctx.rng.gauss_clamped(0.0, weight_sigma_v, 2.5)
	return out * clampf(weight, 0.45, 1.7)


# --- Actions ----------------------------------------------------------------


## Pushes the ball ahead, matched to stride. `space` is 0..1: how much clear
## room the dribbler has, which decides how big a touch they take.
##
## `push` overrides that distance outright, for the one touch that is not a
## carry: the knock past a challenger that turns the situation into a foot race.
## It is deliberately allowed past DRIBBLE_AHEAD_MAX -- the whole point of it is
## that the ball goes further than the man on your back can reach -- and it does
## not shrink under pressure, because it is chosen *because of* the pressure.
## The pressure shrink here survived an attempt to replace it with something
## better, and the attempt is worth recording because it is the obvious one. A
## scalar of how pressed a man is cannot tell the direction he is turning away
## from his marker into from the one he is knocking it into, so the replacement
## asked the question properly, in the decision layer where the direction is
## known: the touch puts the ball on a spot `s` in front of him, so try the sizes
## from the top and take the largest he beats every opponent to.
##
## It changed nothing. Measured on two seeds at ten minutes, the mean carry under
## challenge moved 2.09 m to 1.98 m on one and 1.96 m to 2.17 m on the other,
## against interceptions and balls out of play flat -- noise, twice. The reason
## is selection: a direction with a defender standing in it is a direction the
## softmax was never going to pick, because `_escape_value` and `control_at` have
## already priced him, so the race test only ever pruned touches nobody was going
## to play. The blunt instrument keeps working because it is measuring something
## the sharp one was not -- not whether this touch beats that man, but that a man
## with company does not let the ball leave his feet at all.
##
## `away` is which way this touch is played relative to the man closing on the
## carrier: 1 straight away from him, 0 across him, -1 into him, and 0 when
## nobody is challenging. It changes nothing about the touch and is carried only
## so the log can tell turning away from a challenger apart from taking another
## touch into him -- from outside, the two are the same event.
static func dribble(ctx: SimContext, player: SimPlayer, dir: Vector3, space: float, push: float = 0.0, away: float = 0.0, max_ahead: float = INF) -> void:
	var d := SimConsts.horizontal(dir)
	if d.length_squared() < 1e-6:
		d = player.heading_dir()
	d = d.normalized()
	var press := ctx.pressure_on(player)
	var ahead: float = lerpf(DRIBBLE_AHEAD_MIN, DRIBBLE_AHEAD_MAX, clampf(space, 0.0, 1.0))
	ahead = maxf(ahead * clampf(1.0 - 0.28 * press, 0.45, 1.0), DRIBBLE_AHEAD_FLOOR)
	if push > 0.0:
		ahead = push
	# The decision layer scored this touch on the room it found for it, and a
	# touch played bigger than the one that was scored is the engine lying to
	# itself about its own option.
	ahead = minf(ahead, max_ahead)
	# Relative speed that puts the ball `ahead` metres in front before friction
	# hands it back to the runner.
	var delta := sqrt(2.0 * maxf(ctx.env.roll_decel, 0.1) * ahead)
	var along: float = maxf(player.vel.dot(d), 0.0)
	var speed: float = clampf(along + delta, 1.2, 16.0)

	var sigma := aim_sigma(ctx, player, player.attrs.dribbling, ahead, DRIBBLE_AIM_BASE, d)
	var vel := _perturb(ctx, d * speed, sigma, weight_sigma(player, player.attrs.dribbling) * 1.25, 0.0)
	vel.y = 0.0
	# Slight topspin so the touch runs on rather than sitting up. Positive
	# up-cross-direction is topspin; negative is backspin.
	var spin := Vector3.UP.cross(vel.normalized()) * (vel.length() / SimConsts.BALL_RADIUS * 1.15)
	apply(ctx, player, SimTelemetry.Touch.DRIBBLE, vel, spin, -1, {"ahead": ahead, "away": away})


## Ground pass toward a point, arriving at roughly `arrive_pace` m/s.
static func ground_pass(ctx: SimContext, player: SimPlayer, target: Vector3, arrive_pace: float, target_id: int, kind: int = SimTelemetry.Touch.GROUND_PASS, expected_value: float = 0.0) -> void:
	var delta := SimConsts.horizontal(target - ctx.ball.pos)
	var distance: float = maxf(delta.length(), 0.6)
	var dir := delta / distance
	var speed := ctx.ballistics.ground_pass_speed(distance, arrive_pace, ctx.env)

	var sigma := aim_sigma(ctx, player, player.attrs.passing, distance, 0.055, dir)
	var vel := _perturb(ctx, dir * speed, sigma, weight_sigma(player, player.attrs.passing), 0.0)
	vel.y = 0.0
	var roll_rate := vel.length() / SimConsts.BALL_RADIUS
	# Backspin proportional to how firmly the ball is struck.
	var spin := -Vector3.UP.cross(vel.normalized()) * (roll_rate * PASS_BACKSPIN_FRACTION)

	apply(ctx, player, kind, vel, spin, target_id, {"dist": distance})
	_log_pass_attempt(ctx, player, kind, target, target_id, expected_value, distance)


## Lofted pass or cross. `curl` is sidespin in rad/s, signed.
static func lofted_pass(ctx: SimContext, player: SimPlayer, target: Vector3, flight_time: float, target_id: int, kind: int = SimTelemetry.Touch.LOFTED_PASS, curl: float = 0.0, expected_value: float = 0.0) -> void:
	var aim := target
	aim.y = maxf(aim.y, SimConsts.BALL_RADIUS)
	var skill: float = player.attrs.crossing if kind == SimTelemetry.Touch.CROSS else player.attrs.passing
	var spin := Vector3.UP * curl
	var vel := ctx.ballistics.solve_lofted(ctx.ball.pos, aim, flight_time, ctx.env, spin)
	var line := SimConsts.horizontal(aim - ctx.ball.pos)
	var distance := line.length()

	var sigma := aim_sigma(ctx, player, skill, distance, 0.07, line)
	vel = _perturb(ctx, vel, sigma, weight_sigma(player, skill) * 1.15, 1.0)
	vel.y = maxf(vel.y, 1.0)

	apply(ctx, player, kind, vel, spin, target_id, {"dist": distance})
	_log_pass_attempt(ctx, player, kind, aim, target_id, expected_value, distance)


## Shot at a point in the goal mouth. `power` is 0..1 over the shot speed range.
static func shot(ctx: SimContext, player: SimPlayer, aim_point: Vector3, power: float, first_time: bool, chance_quality: float) -> void:
	var speed: float = lerpf(SimConsts.SHOT_SPEED_MIN, SimConsts.SHOT_SPEED_MAX, clampf(power * lerpf(0.65, 1.0, player.attrs.power), 0.0, 1.0))
	var distance := SimConsts.horizontal_length(aim_point - ctx.ball.pos)
	var curl: float = ctx.rng.gauss_clamped(0.0, 2.2, 2.0) * player.attrs.technique
	var spin := Vector3.UP * curl
	var vel := ctx.ballistics.solve_direct(ctx.ball.pos, aim_point, speed, ctx.env, spin)

	var sigma := aim_sigma(ctx, player, player.attrs.finishing, distance, SHOT_AIM_BASE)
	if first_time:
		sigma *= 1.45
	# Elevation is the harder axis: the goal is 7.32 m wide and 2.44 m high, and
	# most missed shots miss over the bar rather than round the post.
	vel = _perturb(ctx, vel, sigma, weight_sigma(player, player.attrs.finishing), 1.6)

	player.shots += 1
	var from := ctx.ball.pos
	apply(ctx, player, SimTelemetry.Touch.SHOT, vel, spin, -1, {"first_time": first_time})
	# Held by reference: the referee fills in on_target and goal as the ball
	# resolves, so the log carries the outcome alongside the intent.
	var record := {
		"p": player.id,
		"team": player.team,
		"from": from,
		"aim": aim_point,
		"quality": chance_quality,
		"first_time": first_time,
		"dist": distance,
		"on_target": false,
		"goal": false,
		"blocked": false,
	}
	ctx.log_event(SimTelemetry.Ev.SHOT, record)
	ctx.active_shot = record
	ctx.active_shot_tick = ctx.tick_index


## A damping impulse opposing the incoming ball. What is left over is the loose
## ball -- and a large share of the game's drama comes from here, so it is never
## clamped away.
static func first_touch(ctx: SimContext, player: SimPlayer, intent_dir: Vector3) -> void:
	var incoming := ctx.ball.vel
	var incoming_speed := incoming.length()
	var dir := SimConsts.horizontal(intent_dir)
	if dir.length_squared() < 1e-6:
		dir = player.heading_dir()
	dir = dir.normalized()

	# How much of the incoming pace the player kills. Difficulty rises with the
	# speed of the ball, with height, and with how far the ball has to be turned
	# from the line it arrived on.
	#
	# That last term had its sign the wrong way round, and it was worth more than
	# everything else in the function put together. `-incoming` points back up the
	# ball's path, toward whoever played it, so dotting *that* against the way the
	# receiver wants to go scores a man who lets the ball run on in its own line
	# -- the easiest touch there is, and the commonest, a ball rolled into his
	# path that he carries on with -- at the maximum penalty of 1.0, and scores
	# turning it back where it came from at nothing. Exactly inverted.
	#
	# Measured on seed 7 at ten minutes, `quality` came out at 0.02 to 0.10 for
	# every first touch in the match, in all three of the bands the report prints.
	# `first_touch` and `technique` were dead weight: every footballer in the
	# engine controlled every pass like the worst player on the pitch, took 55% of
	# the pace with it, and then had to chase it. Nothing counts that -- a touch
	# taken cleanly and one that runs away from a man are one event in the log --
	# which is why it survived this long.
	var angle_penalty := 0.0
	if incoming_speed > 0.1:
		angle_penalty = 0.5 * (1.0 - (incoming / incoming_speed).dot(dir))
	var difficulty: float = clampf(incoming_speed / 18.0 + angle_penalty + ctx.ball.pos.y * 0.22 + ctx.pressure_on(player) * 0.15, 0.0, DIFFICULTY_MAX)
	# Difficulty discounts the skill; it used to be subtracted from it. The
	# difference is not a coefficient, it is whether the attributes survive at
	# all: subtracted, a difficulty of 0.8 wiped out every player in the squad,
	# because `first_touch * technique` for an ordinary footballer is about 0.44
	# and the subtraction was 0.55 of the difficulty. An ordinary firm pass is
	# 0.55 of that scale before anybody has to turn with it, so the function
	# returned zero for nearly every touch in the match and both attributes might
	# as well not have been read.
	#
	# It is also the disagreement `CLAUDE.md` warns about, in its clearest form
	# yet: `SimDecision._shortlist` prices the same man's control of the same ball
	# at `lerpf(0.72, 0.99, first_touch)` when deciding whether to pass it to him,
	# while this graded what he then did with it at 0.02. One of the two was
	# wrong, and it was not the one calibrated against a footballer.
	var skill: float = player.attrs.first_touch * lerpf(0.75, 1.0, player.attrs.technique)
	var quality: float = clampf(skill * (1.0 - difficulty / DIFFICULTY_MAX), 0.0, 1.0)
	var wanted := dir
	# And he does not try to reverse a firm ball in one touch, because nobody
	# does. The decision layer hands down where he would *like* to be going --
	# `_safe_direction`, which is at the goal unless somebody is in the way -- and
	# asking for that literally is how a man receiving a ball played back to him
	# ends up attempting a 180 degree turn on a ball travelling at ten metres a
	# second, failing it, and chasing it back the way it came. He takes it on the
	# half-turn instead: as much of the turn as he can manage now, the rest with
	# his second touch. The same limit `locomote` puts on a body, put on the ball.
	if incoming_speed > 0.1:
		var line := SimConsts.horizontal(incoming)
		if line.length() > 0.1:
			line /= line.length()
			var swing := atan2(line.x * dir.z - line.z * dir.x, line.x * dir.x + line.z * dir.z)
			var most: float = lerpf(TURN_MIN, TURN_MAX, skill)
			var applied: float = clampf(swing, -most, most)
			var ca := cos(applied)
			var sa := sin(applied)
			dir = Vector3(line.x * ca - line.z * sa, 0.0, line.x * sa + line.z * ca)
			# The difficulty was priced against the turn he was asked for; charge
			# him for the one he is actually attempting.
			angle_penalty = 0.5 * (1.0 - cos(applied))
			difficulty = clampf(incoming_speed / 18.0 + angle_penalty + ctx.ball.pos.y * 0.22 + ctx.pressure_on(player) * 0.15, 0.0, DIFFICULTY_MAX)
			quality = clampf(skill * (1.0 - difficulty / DIFFICULTY_MAX), 0.0, 1.0)
	quality *= player.fatigue_factor()
	var residual: float = lerpf(0.55, 0.06, quality) * (1.0 + ctx.rng.gauss_clamped(0.0, 0.28, 2.5))
	residual = clampf(residual, 0.02, 0.95)

	# The ball keeps some of its own momentum and gains a small push in the
	# direction the player wanted to take it.
	#
	# A first touch is a redirection and not only a brake, and until this was
	# written it was only a brake: whatever pace survived `residual` survived
	# along the ball's own line, so a man who came to meet a pass and wanted to
	# turn with it watched it carry on past him at a couple of metres a second
	# and then had to turn round and chase it. A twelve-metre ball met square, at
	# an ordinary residual of 0.3, left him going one way at 3.6 m/s and the ball
	# going the other -- which is exactly the complaint that the ball ends up
	# behind the man receiving it, and the small circle he runs afterwards is not
	# a locomotion problem, it is this.
	#
	# How much of the surviving pace gets turned into the direction he wanted is
	# `quality`, the same number that decides how much survives. Both halves of a
	# good first touch are then the one attribute: he takes the sting out of it
	# *and* he sets it where he is going. A poor one does neither, and the ball
	# runs on along the line it arrived at, which is what it always did.
	var settle: float = lerpf(0.4, 1.9, quality)
	var kept := incoming * residual
	var horiz := SimConsts.horizontal(kept)
	# And a touch is a cushion as well as a brake.
	#
	# `residual` is purely proportional, and proportional alone cannot express
	# the act. It says a ball arriving twice as fast leaves twice as fast however
	# well it is controlled, so a driven ball taken down by the best receiver on
	# the pitch still ran away from him: at a good quality of 0.4 a 15 m/s ball
	# left his foot at 5.4, which is faster than he can run. There is no value of
	# `residual` that fixes that without also making a bad touch gentle, and a bad
	# touch on a firm ball *should* spray it -- that is where the loose balls come
	# from.
	#
	# What is missing is the other half of the physics. A footballer does not
	# scale the ball's pace down, he absorbs it: the foot, thigh or chest gives
	# way with the ball and takes the sting out, and how much sting a man can take
	# out is a fact about his technique, not about how hard it arrived. So the two
	# models are each half right, and the touch keeps the *lesser* of them --
	# proportional for an ordinary ball, absorbed for a fierce one.
	#
	# It is a cushion and not a clamp: it is keyed on `quality`, so it barely
	# exists for a poor touch, and `quality` carries the skill, the difficulty and
	# the noise on `residual` before it. Nothing is clamped away.
	var cushion: float = lerpf(CUSHION_WORST, CUSHION_BEST, quality)
	if horiz.length() > cushion:
		horiz *= cushion / horiz.length()
	var vel := horiz.lerp(dir * horiz.length(), quality)
	vel.y = kept.y
	vel += dir * settle
	vel.y = minf(vel.y * 0.35, 2.0)
	var sigma := aim_sigma(ctx, player, player.attrs.first_touch, 2.0, 0.16, dir)
	vel = _perturb(ctx, vel, sigma, 0.14, 0.0)
	var spin := -Vector3.UP.cross(vel.normalized() if vel.length() > 0.1 else dir) * (vel.length() / SimConsts.BALL_RADIUS * 0.4)

	# `set` is where the ball ended up relative to where he was trying to go: 1
	# into his stride, 0 square across him, -1 left behind him. Nothing else in
	# the log can see it -- a first touch that sets the ball up and one that
	# leaves it behind are the same event, by the same player, in the same place.
	var flat := SimConsts.horizontal(vel)
	# Against what he *wanted*, not against the half-turn he settled for, or the
	# instrument would be measuring its own compromise and always approve of it.
	var set_dot: float = flat.normalized().dot(wanted) if flat.length() > 0.05 else 1.0
	apply(ctx, player, SimTelemetry.Touch.FIRST_TOUCH, vel, spin, -1, {
		"quality": quality, "residual": residual, "set": set_dot, "pace": flat.length(),
		"in": incoming_speed,
	})


## High and away from goal. Wide by nature: it is a panic action.
static func clearance(ctx: SimContext, player: SimPlayer) -> void:
	var away := ctx.pitch.target_goal(player.team) - player.pos
	away.y = 0.0
	if away.length_squared() < 1e-6:
		away = Vector3(ctx.pitch.attack_dir(player.team), 0.0, 0.0)
	away = away.normalized()
	# Bias toward the nearest touchline: clearances go long and wide.
	var side: float = signf(player.pos.z) if absf(player.pos.z) > 2.0 else (1.0 if ctx.rng.chance(0.5) else -1.0)
	var dir := (away + Vector3(0.0, 0.0, side * 0.3)).normalized()
	var speed: float = lerpf(16.0, 26.0, player.attrs.power) * ctx.rng.range_float(0.85, 1.1)
	var elevation: float = ctx.rng.range_float(0.5, 0.85)
	var vel := dir * (speed * cos(elevation)) + Vector3(0.0, speed * sin(elevation), 0.0)
	var sigma := aim_sigma(ctx, player, player.attrs.power * 0.5 + 0.25, 20.0, 0.2)
	vel = _perturb(ctx, vel, sigma, 0.2, 1.0)
	apply(ctx, player, SimTelemetry.Touch.CLEARANCE, vel, Vector3.ZERO)


## A header: reflection of the incoming ball, with power from heading and
## jumping.
static func header(ctx: SimContext, player: SimPlayer, dir: Vector3, aim_up: float) -> void:
	var d := SimConsts.horizontal(dir)
	if d.length_squared() < 1e-6:
		d = player.heading_dir()
	d = d.normalized()
	var incoming := ctx.ball.vel.length()
	var power: float = lerpf(5.0, 13.0, player.attrs.heading) + incoming * 0.32
	power *= lerpf(0.8, 1.1, player.attrs.jumping) * player.fatigue_factor()
	var vel := d * (power * cos(aim_up)) + Vector3(0.0, power * sin(aim_up), 0.0)
	var sigma := aim_sigma(ctx, player, player.attrs.heading, 10.0, 0.13)
	vel = _perturb(ctx, vel, sigma, 0.16, 1.0)
	player.spend_action(2.5)
	apply(ctx, player, SimTelemetry.Touch.HEADER, vel, Vector3.ZERO)


## A defender's poke or block. Knocks the ball away from the carrier; where it
## ends up is deliberately not controlled.
static func poke(ctx: SimContext, player: SimPlayer, kind: int = SimTelemetry.Touch.TACKLE) -> void:
	var away := ctx.pitch.own_goal(player.team) - ctx.ball.pos
	away.y = 0.0
	var dir := (-away).normalized() if away.length_squared() > 1e-6 else player.heading_dir()
	# A tackle is a scramble; the direction is only loosely intended. Bias it
	# back toward the middle of the pitch, or a match ends up being played
	# entirely from throw-ins.
	dir = (dir + Vector3(0.0, 0.0, -signf(ctx.ball.pos.z) * 0.4)).normalized()
	dir = dir.rotated(Vector3.UP, ctx.rng.gauss_clamped(0.0, 0.45, 2.0))
	var speed: float = lerpf(4.0, 11.0, player.attrs.tackling) * ctx.rng.range_float(0.6, 1.3)
	var lift: float = ctx.rng.range_float(0.0, 0.45)
	var vel := dir * (speed * cos(lift)) + Vector3(0.0, speed * sin(lift), 0.0)
	player.spend_action(2.5)
	apply(ctx, player, kind, vel, Vector3.ZERO)


static func _log_pass_attempt(ctx: SimContext, player: SimPlayer, kind: int, target: Vector3, target_id: int, expected_value: float, distance: float) -> void:
	player.passes_attempted += 1
	# Offside is judged at the instant of the impulse, so the referee is told
	# here rather than watching for it.
	SimReferee.on_pass(ctx, player, target_id)
	# Where the body was pointing relative to the ball's line: 1 straight ahead,
	# 0 square, -1 straight back. The only way to see the facing model from
	# outside is to bucket completions by it, and no other field can stand in --
	# a pass played square and one played over the passer's shoulder are the same
	# length, from the same place, to the same kind of target.
	var line := SimConsts.horizontal(target - player.pos)
	var body := 1.0
	if line.length() > 1e-3:
		body = player.heading_dir().dot(line.normalized())
	# Read before the memory below is overwritten: this pass is a give-and-go
	# return if the man it is going to is the man it came from.
	var window := int(SimDecision.GIVE_AND_GO_WINDOW * float(SimConsts.TICK_HZ))
	var give_and_go := target_id >= 0 and ctx.last_pass_to == player.id \
		and ctx.last_pass_from == target_id and ctx.tick_index - ctx.last_pass_tick <= window
	# Which offer, if any, this ball was played to. Recorded because a pass to a
	# man standing still and a pass to the same man arriving on a run he
	# committed to are indistinguishable in every other field of this event --
	# same passer, same receiver, same length, same place.
	var call := 0
	if target_id >= 0 and target_id < ctx.players.size():
		call = SimOffBall.intent_of(ctx, ctx.players[target_id])
	# The give-and-go's whole memory. Recorded here rather than in the decision
	# layer because this is where a pass becomes a fact rather than a candidate.
	ctx.last_pass_from = player.id
	ctx.last_pass_to = target_id
	ctx.last_pass_tick = ctx.tick_index
	ctx.log_event(SimTelemetry.Ev.PASS_ATTEMPT, {
		"p": player.id,
		"team": player.team,
		"kind": kind,
		"target": target_id,
		# Without the origin the log cannot say which way a pass went, which is
		# the first thing anyone wants to know about one.
		"from": player.pos,
		"to": target,
		"call": call,
		"gng": give_and_go,
		"body": body,
		# "xv" is the engine's own expected-value estimate for this choice. The
		# post-match screen uses it to explain why a pass was played.
		"xv": expected_value,
		"dist": distance,
	})
