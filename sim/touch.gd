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
## Sidespin on a driven pass, in rad/s of yaw, scaled by technique. Zero-mean:
## one man wraps it round with the inside, the next steers it with the outside,
## and the bend is a property of the strike rather than an aim the model owes.
## Sized against the bench's sideways column, which has to stay inside `said`.
const PASS_CURL_SIGMA := 1.6
const PASS_CURL_CLAMP := 1.4
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
	# The pass has arrived. Read here, before the ball's own memory below is
	# overwritten, because "it came straight from the passer" is the whole test:
	# the man it was played to is touching it and nobody has touched it since it
	# left. A deflection, an interception or a scramble fails that and leaves the
	# arrival unstamped, so a ball won back three seconds later is not a one-two.
	if player.id == ctx.last_pass_to and ctx.ball.last_touch_player == ctx.last_pass_from \
			and ctx.last_pass_arrival_tick < ctx.last_pass_tick:
		ctx.last_pass_arrival_tick = ctx.tick_index
	# The first touch of a spell starts his orientation clock, and the flight he
	# watched before it counts toward it. Read before the ball's memory is
	# overwritten; `SimDecision.readiness` is the consumer.
	if ctx.ball.last_touch_player != player.id:
		player.spell_start_tick = ctx.tick_index
		player.spell_prep_seconds = 0.0
		if ctx.ball.last_touch_tick >= 0:
			player.spell_prep_seconds = float(ctx.tick_index - ctx.ball.last_touch_tick) * SimConsts.DT
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
	# The other two that outlast their own contact. A header is a man in the air
	# and he is still coming down; a chest is a ball still dropping to his feet.
	# Cut to two tenths, both of them snap back to a run mid-act -- which for the
	# header is a figure that rises off the grass and is put back on it before it
	# has landed, and no viewer reads that as a leap.
	var thrown: bool = kind == SimTelemetry.Touch.THROW_IN or kind == SimTelemetry.Touch.KEEPER_THROW
	var slow: bool = thrown or kind == SimTelemetry.Touch.CHEST \
		or kind == SimTelemetry.Touch.HEADER
	player.play_anim(_anim_for(kind, vel.length()), 0.45 if slow else 0.2)

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
		SimTelemetry.Touch.CHEST:
			return SimConsts.Anim.CHEST
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
	# Squared, so playing it square across the body costs a quarter of turning it
	# all the way round rather than half: opening up to play the ball sideways is
	# ordinary football, and hitting one you cannot see is not.
	var off := off_axis(player, dir)
	return 1.0 + FACING_COST * off * off * lerpf(1.0, 0.28, deftness_of(player)) * momentum_of(player)


## How far off the way the body is pointing the ball is being played: 0 straight
## ahead, 0.5 square across him, 1 straight back.
##
## One measure, read by everything that prices the body -- the aim error above,
## the reach below, and through them the decision layer's own estimate of both.
## Two of anything here is two things that drift apart.
static func off_axis(player: SimPlayer, dir: Vector3) -> float:
	var d := SimConsts.horizontal(dir)
	var length := d.length()
	if length < 1e-6:
		return 0.0
	var ahead: float = player.heading_dir().dot(d / length)
	return (1.0 - clampf(ahead, -1.0, 1.0)) * 0.5


## Opening the hips and striking a ball you are not looking at: technique and
## agility, not the skill of whatever action it is.
static func deftness_of(player: SimPlayer) -> float:
	return clampf(player.attrs.technique * 0.6 + player.attrs.agility * 0.4, 0.0, 1.0)


## The share of the facing cost a running player pays over a standing one. See
## `FACING_STATIC_SHARE`.
static func momentum_of(player: SimPlayer) -> float:
	var speed_ratio: float = clampf(player.speed() / maxf(player.nominal_max_speed(), 1e-3), 0.0, 1.0)
	return lerpf(FACING_STATIC_SHARE, 1.0, speed_ratio)


## What is left of a full-blooded strike when the ball has to be played along
## `dir` rather than out in front of the body, as a fraction.
##
## Aim error used to be the whole of the body-facing model, and error alone
## cannot say the thing anyone watching sees. A man with his back to play does
## not hit a forty-metre diagonal *wide of the mark* -- he does not hit it at
## all. There is no backlift behind him and no hips to swing through the ball, so
## what comes off his boot is a flick or a scoop that travels a fraction of the
## distance. The option is not a worse pass; it is not that pass, and the answer
## a footballer uses is to turn first and hit it properly a moment later.
##
## Read as a fraction of *range* rather than of speed, which is what makes it
## legible: a man who can find somebody forty-five metres away in front of him
## can find somebody ten metres behind him. Squared in the off-axis measure, the
## same shape `facing_penalty` uses -- square across the body is ordinary and
## costs a quarter of what turning it all the way round costs. Technique buys
## some of it back, and standing still buys the rest, which is the same statement
## `FACING_STATIC_SHARE` makes about the second he does not spend turning.
##
## `SimDecision` gates its pass candidates on this and the touch primitives clamp
## to it, so the ball the engine scores is the ball it can actually strike.
const STRIKE_BEHIND := 0.22
## The share of that cost a player standing still pays.
##
## Deliberately higher than `FACING_STATIC_SHARE`, which is the same idea about
## aim. A man on the spot can plant, look and get most of his *accuracy* back;
## what he cannot get back is the swing, because there is no run-up behind a ball
## played past his own heel whether he is moving or not. Standing still is worth
## something here and it is not worth half.
const STRIKE_STATIC_SHARE := 0.75


static func strike_scale(player: SimPlayer, dir: Vector3) -> float:
	var off := off_axis(player, dir)
	var speed_ratio: float = clampf(player.speed() / maxf(player.nominal_max_speed(), 1e-3), 0.0, 1.0)
	var momentum: float = lerpf(STRIKE_STATIC_SHARE, 1.0, speed_ratio)
	var cost: float = clampf(off * off * lerpf(1.0, 0.75, deftness_of(player)) * momentum, 0.0, 1.0)
	return lerpf(1.0, STRIKE_BEHIND, cost)


## The longest ball this player can strike along `dir`, given that he could hit
## it `full_range` metres out in front of himself.
static func strike_range(player: SimPlayer, dir: Vector3, full_range: float) -> float:
	return full_range * strike_scale(player, dir)


## Pulls an aim point back to a distance the striker can actually reach. What
## comes out is the ball falling short, which is what a hooked clearance off the
## back foot does.
static func clamp_to_reach(player: SimPlayer, from: Vector3, target: Vector3, full_range: float) -> Vector3:
	var line := SimConsts.horizontal(target - from)
	var distance := line.length()
	var reach := strike_range(player, line, full_range)
	if distance <= reach or distance < 1e-3:
		return target
	var pulled := from + line / distance * reach
	return Vector3(pulled.x, target.y, pulled.z)


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


## The base aim error of each strike, in one place, because the model and the
## strike have to read the same number or `execution_accuracy` is describing a
## ball nobody hits. They did not: the lofted model used 0.085 and the lofted
## strike 0.07, and nothing could see it.
##
## The two air numbers still differ, and now on purpose. `./run.sh strike` rolls
## the real ball against the integrator and says the *model* is right on the
## sideways axis — 4.19 m said against 4.52 m at thirty metres — because a ball in
## the air lands further out than the yaw at the boot implies: it inherits the
## spread of its own range. `AIR_MODEL_AIM_BASE` is that, and the bench is what
## keeps it honest. If it were pulled down to `AIR_AIM_BASE` for tidiness the one
## axis that works would stop working.
const GROUND_AIM_BASE := 0.055
const AIR_AIM_BASE := 0.07
const AIR_MODEL_AIM_BASE := 0.085

## How much harder a ball in the air is to weight than one on the floor, and how
## much of the aim error goes into the launch angle rather than across it. Both
## were literals inside the two strikes; they are read by the model now, so they
## cannot drift from it.
const LOFT_WEIGHT_SCALE := 1.15
const ELEVATION_SHARE := 0.75


## The flight time a lofted ball is asked for. A function of the distance alone,
## which is what lets the model work out the angle it leaves the boot at.
##
## There is a floor under it and it is not a taste question: below a certain
## flight time the only way to cover the ground is to strike the ball harder than
## a person can, and the solver will do it. Measured against the integrator, the
## knee where launch speed runs away sits at about 0.2 + 0.045 d.
static func lofted_flight(distance: float) -> float:
	return clampf(0.2 + distance * 0.045, 0.7, 2.25)


## The spread of where a struck ball finishes, along its own line.
##
## This was `weight_sigma * distance` — a linear map from a weight error to a
## range error — and range is not linear in the strike. A ball in the air carries
## `v^2 sin(2t)/g` and a ball on the grass decays as `v^2/2a`, so a weight factor
## `w` moves the finishing point by `w^2`. It is the same square the `arrival_pace`
## note records for the pace at the far end, in the other axis, and it was missed
## in the same place twice.
##
## Rolled against the integrator by `./run.sh strike`, 300 strikes a row, the old
## term was out by three on the floor and by four in the air:
##
##     lofted 20 m   said 2.12 m   rolled 10.22 m
##     lofted 30 m   said 3.18 m   rolled 14.12 m
##     lofted 40 m   said 4.24 m   rolled 17.28 m
##
## on the axis a ball in the air fails on, while the sideways axis was right the
## whole time. That is why no aggregate ever showed it: the two errors are in
## different directions and a single `struck` is their product.
##
## **`AIR_RANGE_SPREAD` is measured, not derived, and that is deliberate.** The
## first version of this was a closed form — the square law plus the launch angle
## the ball leaves at, `dR/R = 2 dt / tan(2t)` — and it reproduced the total at
## thirty and forty metres. It was still wrong: cutting the elevation error to a
## third moved the real ball by 7% where the formula said 60%, so the split was
## wrong even though the sum was right. Drag, the solver and the `vel.y` floor all
## live in that number and no closed form survived its own check. The bench is the
## authority, and re-running it is what says whether this is still true after
## anything in `_perturb` moves.
static func long_sigma(player: SimPlayer, skill: float, distance: float, in_air: bool) -> float:
	# Twice the weight error on the floor, because the ball stops where its speed
	# runs out and that goes as the square of the strike.
	var scale := AIR_RANGE_SPREAD if in_air else 2.0
	return scale * weight_sigma(player, skill) * distance


## How many times his weight error a ball in the air finishes off its mark by.
## Off `./run.sh strike`: 4.8, 4.4 and 4.1 at twenty, thirty and forty metres, and
## a flat number in the middle of that is closer to the ball than the shape the
## closed form gave, which ran the wrong way across the range.
const AIR_RANGE_SPREAD := 4.4



## Probability that a struck ball actually lands within `tolerance` of where it
## was aimed, given the same error model the execution uses.
##
## The decision layer needs this: without it, a value function happily picks a
## forty-metre ball because the target square looks good, having no idea the
## player cannot hit it. Sharing `aim_sigma` means tuning the error model
## automatically retunes what the engine is willing to attempt.
static func execution_accuracy(ctx: SimContext, player: SimPlayer, skill: float, distance: float, base_sigma: float, tolerance: float, dir: Vector3 = Vector3.ZERO, long_axis: int = LONG_NONE) -> float:
	var sigma := aim_sigma(ctx, player, skill, distance, base_sigma, dir)
	var lateral := _within(tolerance, sigma * distance)
	if long_axis == LONG_NONE:
		return lateral
	return lateral * _within(tolerance,
		long_sigma(player, skill, distance, long_axis == LONG_AIR))


## Whether a ball misses by being the wrong length, and by which law.
##
## Not every ball does, and charging them all alike is what this used to do. A
## ball rolled at a man's feet and overhit by five metres has not missed him -- it
## runs through him on the same line and he takes it moving. What that costs is
## the pace it arrives at, which is real and is priced where it belongs, in
## `arrival_pace` and the through ball's `arriving faster than the man can run`.
##
## A ball aimed at *grass* is the opposite. Nobody is standing on the spot to
## catch a long one, so five metres past is five metres the runner has to make up,
## and the ball in behind fails exactly this way. Same for anything in the air,
## which stops where it lands.
##
## `LONG_GROUND` is the rolling law and `LONG_AIR` the flying one; `long_sigma`
## has both and the difference between them is a factor of three.
const LONG_NONE := 0
const LONG_GROUND := 1
const LONG_AIR := 2


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
			var pitch_err: float = ctx.rng.gauss_clamped(0.0, sigma_rad * ELEVATION_SHARE * elevation_scale, 2.8)
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
## `settle` is the frame `ahead` is measured in, and it is the difference between
## a carry and a hold. A carry is struck to sit `ahead` metres in front of a man
## who *keeps running*, so his own pace goes into the strike and the ball's
## journey over the grass is two or three times `ahead` -- which is right, and is
## what `carry_room` and `carry_travel` price. A settling touch is the same
## distance measured against the pitch: the ball ends up `ahead` metres from
## where it was struck, whoever struck it and however fast he was going.
##
## Without this a hold was the one and the other at once. `SimDecision._add_hold`
## reads its gain and its loss at the player's own position -- a pitch-frame
## claim, "the ball stays here" -- and the touch was then struck at his own speed
## plus the 2.3 m/s that opens a metre of daylight. Measured on seed 2 at
## 1.0 v 1.0, that closes a loop: the man is chase-primary for his own touch, so
## he runs to catch a ball he struck harder than he meant to, arrives quicker,
## and strikes the next one harder still. Four holds in a row took #7 from 1.1 to
## 7.6 m/s without a single decision to run anywhere, and the last "settling
## touch" left his foot at 10.7 m/s and ran eleven metres into nobody.
## How far in front of himself this touch puts the ball, in metres of relative
## gap. Split out of `dribble` so it can be asked *before* the touch is played.
##
## The debug overlay needs it to say where the carrier expects to meet the ball
## again, and working that out from a copy of these four lines is how the drawn
## number and the played touch drift apart -- the failure `first_touch_drift`
## exists to prevent on the other primitive. One function, asked by both.
static func dribble_ahead(ctx: SimContext, player: SimPlayer, space: float, push: float = 0.0, max_ahead: float = INF) -> float:
	var press := ctx.pressure_on(player)
	var ahead: float = lerpf(DRIBBLE_AHEAD_MIN, DRIBBLE_AHEAD_MAX, clampf(space, 0.0, 1.0))
	ahead = maxf(ahead * clampf(1.0 - 0.28 * press, 0.45, 1.0), DRIBBLE_AHEAD_FLOOR)
	if push > 0.0:
		ahead = push
	# The decision layer scored this touch on the room it found for it, and a
	# touch played bigger than the one that was scored is the engine lying to
	# itself about its own option.
	return minf(ahead, max_ahead)


static func dribble(ctx: SimContext, player: SimPlayer, dir: Vector3, space: float, push: float = 0.0, away: float = 0.0, max_ahead: float = INF, settle: bool = false) -> void:
	var d := SimConsts.horizontal(dir)
	if d.length_squared() < 1e-6:
		d = player.heading_dir()
	d = d.normalized()
	var ahead := dribble_ahead(ctx, player, space, push, max_ahead)
	# Relative speed that puts the ball `ahead` metres in front before friction
	# hands it back to the runner -- and, for a settling touch, the whole of the
	# strike, because there the runner is not going anywhere with it.
	var delta := sqrt(2.0 * maxf(ctx.env.roll_decel, 0.1) * ahead)
	var along: float = 0.0 if settle else maxf(player.vel.dot(d), 0.0)
	var speed: float = clampf(along + delta, 1.2, 16.0)

	var sigma := aim_sigma(ctx, player, player.attrs.dribbling, ahead, DRIBBLE_AIM_BASE, d)
	var vel := _perturb(ctx, d * speed, sigma, weight_sigma(player, player.attrs.dribbling) * 1.25, 0.0)
	vel.y = 0.0
	# Slight topspin so the touch runs on rather than sitting up. Positive
	# up-cross-direction is topspin; negative is backspin.
	var spin := Vector3.UP.cross(vel.normalized()) * (vel.length() / SimConsts.BALL_RADIUS * 1.15)
	apply(ctx, player, SimTelemetry.Touch.DRIBBLE, vel, spin, -1, {"ahead": ahead, "away": away})


## How long the foot stays on the ball. A touch cooldown is 0.17 to 0.27 s, so a
## man holding it repeatedly renews this before it lapses and the shape reads as
## one continuous act rather than a stutter of them.
const HOLD_ANIM_SECONDS := 0.35


## A settling touch: the ball comes to rest `ahead` metres away *on the pitch*,
## whatever pace the man playing it is going. `dribble`'s `settle` says why that
## is a different act from a carry rather than a smaller one.
##
## It is still a `dribble` touch in the log, which `docs/GLOSSARY.md` warns about
## and nothing here changes: a hold is an action, not a touch kind.
##
## The anim is named here rather than in `_anim_for`, and for the same reason:
## `apply` picks a pose from the touch *kind*, and a settling touch and a carry
## share one. A carry is struck, so `apply` gives it a kick; a hold is a foot
## laid on the ball, and looks nothing like one. Naming it after the touch
## overwrites the kick `apply` just played, which is a tick old and has not been
## drawn. Longer on the clock than a kick because the pose is a held shape rather
## than a follow-through -- see `ANIM_SECONDS` in `presentation/match_view_3d.gd`,
## which times the arc itself.
static func settle(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> void:
	dribble(ctx, player, dir, 0.0, 0.0, 0.0, ahead, true)
	player.play_anim(SimConsts.Anim.HOLD, HOLD_ANIM_SECONDS)


## How far a footballer can play the ball with his body behind it: along the
## grass, and through the air. These are what `strike_scale` is a fraction of.
##
## Both sit a little above the longest ball `SimDecision` will offer -- 32 m and
## 45 m -- so a pass played out in front of the body is never shortened by them.
## The clamp exists for the ball played across or behind a man, and bites only
## there.
const GROUND_RANGE := 34.0
const AIR_RANGE := 48.0


## Whether this kind leaves the hands rather than the boot. A throw is made with
## the body squared to wherever it is going, so nothing about the feet's facing
## applies to it.
static func is_thrown(kind: int) -> bool:
	return kind == SimTelemetry.Touch.THROW_IN or kind == SimTelemetry.Touch.KEEPER_THROW


## Ground pass toward a point, arriving at roughly `arrive_pace` m/s.
static func ground_pass(ctx: SimContext, player: SimPlayer, target: Vector3, arrive_pace: float, target_id: int, kind: int = SimTelemetry.Touch.GROUND_PASS, expected_value: float = 0.0) -> void:
	if not is_thrown(kind):
		target = clamp_to_reach(player, ctx.ball.pos, target, GROUND_RANGE)
	var delta := SimConsts.horizontal(target - ctx.ball.pos)
	var distance: float = maxf(delta.length(), 0.6)
	var dir := delta / distance
	# The whole shape of the strike — speed, skim and the backspin that matches —
	# comes from one place, `SimBallistics.ground_launch`, so the ball that is
	# solved is the ball that is struck. A throw is always rolled out flat.
	var speed: float
	var drive := 0.0
	if is_thrown(kind):
		speed = ctx.ballistics.ground_pass_speed(distance, arrive_pace, ctx.env)
	else:
		var launch := ctx.ballistics.ground_launch(distance, arrive_pace, ctx.env)
		speed = launch["speed"]

	var sigma := aim_sigma(ctx, player, player.attrs.passing, distance, GROUND_AIM_BASE, dir)
	var vel := _perturb(ctx, dir * speed, sigma, weight_sigma(player, player.attrs.passing), 0.0)
	vel.y = 0.0
	# The skim and the backspin are re-read off the *perturbed* speed, so an
	# overhit ball is driven a little harder and flatter, the way it came off
	# the boot, rather than wearing the intended strike's shape.
	if not is_thrown(kind):
		drive = SimBallistics.drive_loft(vel.length())
	vel.y = drive
	var roll_rate := SimConsts.horizontal_length(vel) / SimConsts.BALL_RADIUS
	var spin := -Vector3.UP.cross(SimConsts.horizontal(vel).normalized()) \
		* (roll_rate * SimBallistics.drive_backspin(drive))
	# And the curl that rides on the driven ball. Zero-mean: one man wraps it
	# with the inside of the boot, the next steers it with the outside.
	if drive > 0.0:
		spin += Vector3.UP * (ctx.rng.gauss_clamped(0.0, PASS_CURL_SIGMA, PASS_CURL_CLAMP)
			* player.attrs.technique)

	apply(ctx, player, kind, vel, spin, target_id, {"dist": distance})
	_log_pass_attempt(ctx, player, kind, target, target_id, expected_value, distance, vel.length())


## Lofted pass or cross. `curl` is sidespin in rad/s, signed.
static func lofted_pass(ctx: SimContext, player: SimPlayer, target: Vector3, flight_time: float, target_id: int, kind: int = SimTelemetry.Touch.LOFTED_PASS, curl: float = 0.0, expected_value: float = 0.0) -> void:
	var aim := target
	if not is_thrown(kind):
		aim = clamp_to_reach(player, ctx.ball.pos, aim, AIR_RANGE)
	aim.y = maxf(aim.y, SimConsts.BALL_RADIUS)
	var skill: float = player.attrs.crossing if kind == SimTelemetry.Touch.CROSS else player.attrs.passing
	var spin := Vector3.UP * curl
	var vel := ctx.ballistics.solve_lofted(ctx.ball.pos, aim, flight_time, ctx.env, spin)
	var line := SimConsts.horizontal(aim - ctx.ball.pos)
	var distance := line.length()

	var sigma := aim_sigma(ctx, player, skill, distance, AIR_AIM_BASE, line)
	vel = _perturb(ctx, vel, sigma, weight_sigma(player, skill) * LOFT_WEIGHT_SCALE, 1.0)
	vel.y = maxf(vel.y, 1.0)

	apply(ctx, player, kind, vel, spin, target_id, {"dist": distance})
	_log_pass_attempt(ctx, player, kind, aim, target_id, expected_value, distance, vel.length())


## Shot at a point in the goal mouth. `power` is 0..1 over the shot speed range.
static func shot(ctx: SimContext, player: SimPlayer, aim_point: Vector3, power: float, first_time: bool, chance_quality: float) -> void:
	var line := aim_point - ctx.ball.pos
	var speed: float = lerpf(SimConsts.SHOT_SPEED_MIN, SimConsts.SHOT_SPEED_MAX, clampf(power * lerpf(0.65, 1.0, player.attrs.power), 0.0, 1.0))
	# Nobody strikes one hard off his back foot. The same reach the passes are
	# clamped to, applied to the one number a shot is made of -- so a man with the
	# goal behind him gets a scuffed poke at it and has to turn to hit it properly.
	# `SimDecision.expected_goals` prices the same factor, so the shot the engine
	# takes is the shot it scored.
	speed *= strike_scale(player, line)
	var distance := SimConsts.horizontal_length(line)
	var curl: float = ctx.rng.gauss_clamped(0.0, 2.2, 2.0) * player.attrs.technique
	var spin := Vector3.UP * curl
	var vel := ctx.ballistics.solve_direct(ctx.ball.pos, aim_point, speed, ctx.env, spin)

	# The scale is 1.0 at real time: `SimMatchConfig`, "the compressed match's
	# scoring fit".
	var sigma := aim_sigma(ctx, player, player.attrs.finishing, distance,
		SHOT_AIM_BASE * ctx.config.shot_sigma_scale(), line)
	if first_time:
		sigma *= 1.45
	# Elevation is the harder axis: the goal is 7.32 m wide and 2.44 m high, and
	# most missed shots miss over the bar rather than round the post.
	vel = _perturb(ctx, vel, sigma, weight_sigma(player, player.attrs.finishing), 1.6)

	var from := ctx.ball.pos
	apply(ctx, player, SimTelemetry.Touch.SHOT, vel, spin, -1, {"first_time": first_time})
	_log_shot(ctx, player, from, aim_point, chance_quality, first_time, distance)


## Opens an attempt on goal in the log.
##
## Split out of `shot` because a header at goal is the same event seen from
## outside -- the same shot count, the same on-target and goal fields filled in
## by the referee, the same entry on the post-match screen -- and an attempt that
## does not go through here is an attempt nothing can see. It is not the same
## *strike*, which is why `SimAerial` heads the ball rather than calling `shot`.
static func _log_shot(ctx: SimContext, player: SimPlayer, from: Vector3, aim_point: Vector3, chance_quality: float, first_time: bool, distance: float) -> void:
	player.shots += 1
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


## What a first touch is going to be, before it is played: the direction he can
## actually turn the ball in, and how well he takes it. Written into three
## statics rather than returned, so the decision layer can ask the question
## without allocating and without a second copy of the model.
##
## The decision layer has to ask it. `SimDecision._add_hold` scores a first touch
## as keeping the ball, and where the ball ends up decides what that is worth --
## so the two layers have to agree about where that is. `docs/PITFALLS.md` has
## the general case: the layer that scores an action and the layer that performs
## it holding separate opinions of it is this engine's most persistent bug, and
## the shared function is the only fix that stays fixed.
static var _ft_dir := Vector3.ZERO
static var _ft_wanted := Vector3.ZERO
static var _ft_quality := 0.0


static func _resolve_first_touch(ctx: SimContext, player: SimPlayer, intent_dir: Vector3) -> void:
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
	var quality := _touch_quality(skill, difficulty)
	var wanted := dir
	# And he does not try to reverse a firm ball in one touch, because nobody
	# does. The decision layer hands down where he would *like* to be going --
	# `safe_direction`, which is at the goal unless somebody is in the way -- and
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
			quality = _touch_quality(skill, difficulty)
	_ft_dir = dir
	_ft_wanted = wanted
	_ft_quality = quality * player.fatigue_factor()


## How much of the difficulty a good touch shrugs off.
##
## Difficulty used to be discounted from skill flat -- `skill * (1 - difficulty /
## DIFFICULTY_MAX)` -- and flat means *the same in relative terms for everybody*.
## A 1.0 receiver and a 0.5 receiver both lost the same 62% of what they had to
## the same ball, so the gap between them never widened where it should widen
## most. The two attributes were read and then made not to matter.
##
## Work through what that cost the best player you can build. A completely
## ordinary pass -- 9 m/s, met square, on the floor, nobody near him -- is
## `9/18 + 0.5`, a difficulty of 1.0 against a maximum of 1.6. So a perfect first
## touch came out at 0.375, a residual of 0.37, and the ball left his foot at
## 3.3 m/s. The finest receiver in the game could not take a normal pass cleanly,
## and the match average sat at 0.14 to 0.25 with balls arriving at 9 and leaving
## at 3.5.
##
## Difficulty is the thing skill exists to overcome. Taking a firm ball on the
## half-turn *is* what a good first touch is, so a good one is charged 0.45 of the
## difficulty and a poor one all of it. The same ordinary pass now comes back at
## 0.72 for the 1.0 receiver -- residual 0.20, the ball set in his stride at
## 1.8 m/s -- and 0.27 for the 0.5 one, which is still a scramble.
##
## This is also the passing fix. `SimDecision.arrival_pace` was deliberately
## slowed because the first touch could not handle pace, and slow balls are what
## interceptions eat.
const TOUCH_RESIST_BEST := 0.45


static func _touch_quality(skill: float, difficulty: float) -> float:
	var resist: float = lerpf(1.0, TOUCH_RESIST_BEST, clampf(skill, 0.0, 1.0))
	return clampf(skill * (1.0 - resist * difficulty / DIFFICULTY_MAX), 0.0, 1.0)


## A damping impulse opposing the incoming ball. What is left over is the loose
## ball -- and a large share of the game's drama comes from here, so it is never
## clamped away.
static func first_touch(ctx: SimContext, player: SimPlayer, intent_dir: Vector3) -> void:
	_resolve_first_touch(ctx, player, intent_dir)
	var incoming := ctx.ball.vel
	var incoming_speed := incoming.length()
	var dir := _ft_dir
	var wanted := _ft_wanted
	var quality := _ft_quality
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


## The ceiling on what a chest or a thigh leaves on the ball, in m/s.
##
## Tighter than `CUSHION_BEST` for a boot, and that is the point of the act. A
## chest is the largest, softest surface a footballer has and it is the one he
## uses when the ball is dropping on him: he leans back, gives with it, and the
## ball dies at his feet. A boot at the same height is a volley, which is a
## different thing entirely and not what he is doing here.
const CHEST_CUSHION_WORST := 4.5
const CHEST_CUSHION_BEST := 0.55
## How hard the ball is driven into the grass, worst touch to best. A chest that
## works ends with the ball on the floor in front of him; one that does not lets
## it drop where it likes and somebody else gets there.
const CHEST_DROP_WORST := 0.3
const CHEST_DROP_BEST := 2.2


## Taken down off the body: chest, thigh, whatever is in the way of a ball that
## is too high to play with a foot and too low to head.
##
## Football's other answer to a ball in the air, and the engine had only the one.
## Every ball above the boot was headed, so a cross met at chest height was nodded
## on, a ball dropping over a shoulder was nodded on, and a match had a header in
## it every time the ball left the ground -- which is not what a match looks like.
## The commonest thing a footballer does with a ball at that height is kill it and
## put it on the floor.
##
## It is the first touch with the same skill, the same difficulty and the same
## dice, held to two changes. The cushion is tighter, because the chest absorbs
## what a boot cannot; and the ball goes *down*, never up, so what it buys him is
## the ball at his feet a moment later rather than a metre of ground now.
static func chest(ctx: SimContext, player: SimPlayer, intent_dir: Vector3) -> void:
	_resolve_first_touch(ctx, player, intent_dir)
	var incoming_speed := ctx.ball.vel.length()
	var dir := _ft_dir
	var quality := _ft_quality
	var residual: float = lerpf(0.5, 0.05, quality) * (1.0 + ctx.rng.gauss_clamped(0.0, 0.28, 2.5))
	residual = clampf(residual, 0.02, 0.95)
	var horiz := SimConsts.horizontal(ctx.ball.vel) * residual
	var cushion: float = lerpf(CHEST_CUSHION_WORST, CHEST_CUSHION_BEST, quality)
	if horiz.length() > cushion:
		horiz *= cushion / horiz.length()
	# Same shape as the first touch: what survives, turned toward where he wants
	# to go by however good the touch was, plus the small push that sets it.
	var vel := horiz.lerp(dir * horiz.length(), quality) + dir * lerpf(0.3, 1.1, quality)
	vel.y = -lerpf(CHEST_DROP_WORST, CHEST_DROP_BEST, quality)
	var sigma := aim_sigma(ctx, player, player.attrs.first_touch, 2.0, 0.16, dir)
	# No elevation error: the one thing this touch decides is that the ball comes
	# down, and a tilt that sent it back up would be a header by another name.
	vel = _perturb(ctx, vel, sigma, 0.14, 0.0)
	var flat := SimConsts.horizontal(vel)
	apply(ctx, player, SimTelemetry.Touch.CHEST, vel, Vector3.ZERO, -1, {
		"quality": quality, "residual": residual, "pace": flat.length(),
		"in": incoming_speed, "height": ctx.ball.pos.y,
	})


## Where a first touch here would leave the ball, as a displacement from where it
## is struck.
##
## `first_touch` with the dice taken out: the same direction, the same quality,
## the mean residual rather than a sample of it, and no aim error. What comes
## back is the ball's own journey from his foot to where it stops rolling.
##
## Two things it is not. It is not where the ball will be when he next plays it
## -- he chases it and touches it again well before it stops -- so this is the
## far end of the range rather than the middle of it. And it is not a promise: a
## first touch is the one act in the engine whose whole point is that it
## sometimes gets away from a man, and the spread around this is wide by design.
##
## It exists because `SimDecision._add_hold` scores a first touch as *not moving
## the ball*, which was true of nothing: measured on seed 7 at ten minutes, an
## ordinary one leaves 2.6 to 3.5 m/s on it, which is one to two and a half
## metres of grass. The same frame confusion the settling touch had, a quarter
## the size, and with a real model underneath it rather than an accident.
static func first_touch_drift(ctx: SimContext, player: SimPlayer, intent_dir: Vector3) -> Vector3:
	_resolve_first_touch(ctx, player, intent_dir)
	var dir := _ft_dir
	var quality := _ft_quality
	var residual: float = lerpf(0.55, 0.06, quality)
	var horiz := SimConsts.horizontal(ctx.ball.vel) * residual
	var cushion: float = lerpf(CUSHION_WORST, CUSHION_BEST, quality)
	if horiz.length() > cushion:
		horiz *= cushion / horiz.length()
	var vel := horiz.lerp(dir * horiz.length(), quality) + dir * lerpf(0.4, 1.9, quality)
	var speed := vel.length()
	if speed < 0.05:
		return Vector3.ZERO
	return vel / speed * (speed * speed / (2.0 * maxf(ctx.env.roll_decel, 0.1)))


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
##
## Deliberately not a solved strike. Everything else in this module asks the
## ballistics for the launch that lands the ball on a point; a header is a man
## getting his forehead in the way of one and choosing a direction, and how far
## it then goes is a fact about his neck and the pace of the ball rather than
## about his intent. `aim_up` is the angle he heads it at, and the distance is
## whatever that buys.
##
## `goal_aim` marks it as an attempt on goal, which is a bookkeeping matter and
## not a physical one: the strike is the same, and `_log_shot` puts it on the
## books so a headed goal is a shot like any other.
static func header(ctx: SimContext, player: SimPlayer, dir: Vector3, aim_up: float, intent: int = -1, goal_aim: Vector3 = Vector3.INF, chance_quality: float = 0.0) -> void:
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
	var from := ctx.ball.pos
	# What he was trying to do with it. Nothing else in the log can tell a
	# clearing header from a knock-down: same player, same kind, same place.
	apply(ctx, player, SimTelemetry.Touch.HEADER, vel, Vector3.ZERO, -1, {"head": intent})
	if not is_inf(goal_aim.x):
		_log_shot(ctx, player, from, goal_aim, chance_quality, true,
			SimConsts.horizontal_length(goal_aim - from))


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


static func _log_pass_attempt(ctx: SimContext, player: SimPlayer, kind: int, target: Vector3, target_id: int, expected_value: float, distance: float, struck: float) -> void:
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
	# Counted from the arrival, like the bias that produced it: a first-time
	# return stamps its own arrival a few lines above, in `apply`.
	var window := int(SimDecision.GIVE_AND_GO_WINDOW * float(SimConsts.TICK_HZ))
	var give_and_go := target_id >= 0 and ctx.last_pass_to == player.id \
		and ctx.last_pass_from == target_id \
		and ctx.last_pass_arrival_tick >= ctx.last_pass_tick \
		and ctx.tick_index - ctx.last_pass_arrival_tick <= window
	# Which offer, if any, this ball was played to. Recorded because a pass to a
	# man standing still and a pass to the same man arriving on a run he
	# committed to are indistinguishable in every other field of this event --
	# same passer, same receiver, same length, same place.
	var call := 0
	# How far in front of the man it was aimed, and it is the only field that can
	# say a ball was played *past* him rather than to him. Every other field is
	# the same for both: same passer, same receiver, same length, same place. A
	# ball in behind is aimed ahead of the receiver on purpose, so the number is
	# only wrong against what he can cover while it travels -- which is `struck`
	# and `dist`, the two beside it.
	var lead := 0.0
	# And how fast he could run at the moment it was struck. Read here rather than
	# looked up when the log is read, because `max_speed` is fatigue-capped and
	# falls across a match: a ball hit in the first minute was being judged against
	# the legs its receiver had in the tenth, which made every early through ball
	# read as harder to catch than it was.
	var rmax := 0.0
	if target_id >= 0 and target_id < ctx.players.size():
		call = SimOffBall.intent_of(ctx, ctx.players[target_id])
		lead = SimConsts.horizontal_length(target - ctx.players[target_id].pos)
		rmax = ctx.players[target_id].max_speed()
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
		# The two halves of "how hard was it hit": what left the boot, and how far
		# ahead of the receiver it was aimed. Nothing else in the log has either --
		# `dist` is passer to aim point, which is the same for a ball rolled into
		# a man's path and one blasted through it.
		"struck": struck,
		"lead": lead,
		"rmax": rmax,
	})
