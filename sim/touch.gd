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
## disagreeing, which is the failure `docs/INVARIANTS.md` calls pricing every
## path to the same outcome.
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
## The smallest touch there is: the ball kept at the edge of his own reach.
##
## It was `CONTROL_RANGE * 1.2` -- deliberately *past* his reach, so that a touch
## is always something he has to run onto and the ball is never glued to him
## (`PLAN.md` §10). That reasoning holds; the twenty per cent did not, because a
## gap is not a distance over the grass. A ball a fifth of a metre beyond his
## reach is a ball he cannot play again until friction has brought the whole gap
## back inside, and at nine metres a second that is **seven metres of pitch**.
##
## So the engine's *smallest* forward touch was a seven-metre ball, and a striker
## bearing down on a goalkeeper had no way to keep it close: his choices were a
## knock the keeper collected or a shot from twenty-five metres, which is both of
## the things the owner watched. At the edge of his reach instead, the same man
## plays it again a third of a second later having covered three metres -- close
## control at a sprint, which is the act that was missing.
##
## It is still not glued. He has to run onto every touch; what has changed is
## that the run is a stride rather than a chase.
const DRIBBLE_AHEAD_FLOOR := SimConsts.CONTROL_RANGE
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
## The bend on a driven pass, in rad/s of yaw before technique scales it --
## the cross's own whip, because it is the same act of the boot. Every driven
## ball carries it as shape, signed by the foot (`pass_shape_curl`): about
## 0.2 m of bow over twenty metres, because a skimming drive is only in the
## air for half its journey. When the decision layer prices a bent lane worth
## having (`SimDecision`, the curled driven ball) the same spin is *meant*,
## and a meant bend is also a *lifted* ball (`BEND_LIFT`): the
## first cut of this mechanic set 25 rad/s on an ordinary drive and measured
## 0.18 m of bow against a defender's 0.9 m of free reach, so the bent lane
## never opened -- the spin was saturating (`MAGNUS_S_HALF`) and the ball was
## on the grass for half its journey. Clipped up at the cross's spin, the bow
## comes out near half a metre over twenty. Starting value, unturned.
const PASS_CURL := 40.0


## The bend every driven pass along `dir` carries as shape: `PASS_CURL` signed
## by the striking foot and scaled by technique. The decision layer prices the
## driven lane with the bow this gives, so the ball the model sees is the ball
## that is struck.
static func pass_shape_curl(player: SimPlayer, dir: Vector3) -> float:
	var sign: float = 1.0 if striking_foot(player, dir) == SimAttributes.FOOT_RIGHT else -1.0
	return sign * PASS_CURL * clampf(player.attrs.technique, 0.0, 1.0)
## The outside of the boot. A trivela bends the ball the *other* way -- the way
## the striking foot cannot -- and costs control: this multiplies the aim error
## at the strike, and `SimDecision.TRIVELA_CONTROL` taxes the success it was
## priced at. Deliberately no attribute gate: technique already scales the curl
## and the two taxes price the rest. The owner's claim that the outside of the
## boot is *power* is recorded as an open question in `docs/THE_FOOTBALL.md` --
## no inside-curl pace cost exists yet for the trivela to be exempt from, so
## there is nothing to refund without asserting a direction nobody has decided.
const TRIVELA_SIGMA := 1.35
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

## The same statement about the other axis of the body: which foot the ball is
## on.
##
## `FACING_COST` prices playing the ball somewhere the body is not pointing.
## This prices playing it to the side the body cannot open onto, and it is the
## half of a footballer's shape that was missing entirely: before this every man
## in the game struck the ball equally well in every direction, so no winger ever
## cut inside, nobody was ever shown onto a foot he could not use, and a full-back
## overlapped for reasons that had nothing to do with which foot he crossed with.
##
## The geometry is the inside of the boot. A right-footer's natural ball goes to
## his *left*, across his body -- which is why a right-footed corner from the left
## flag swings in, and why the inverted winger cutting onto his stronger foot is
## a shape and not a quirk. So the cost rises as the ball is played to the same
## side as the striking foot, and squared, for the reason `facing_penalty` squares
## its own: opening up a little is ordinary football and reaching right across
## yourself is not.
const FOOT_COST := 0.85
## What is left of a full-blooded strike played off the weaker foot, as a
## fraction of range -- the same currency `STRIKE_BEHIND` is in, and for the same
## reason. Nobody hits a forty-metre diagonal with his wrong foot; he hits a
## fifteen-metre one and looks for someone closer.
const FOOT_STRIKE := 0.62
## How far behind his good foot a one-footed player's other foot is, in the units
## `foot_cost` is measured in.
##
## Above 1.0 on purpose. At exactly 1.0 the worst angle for the strong foot and
## the best angle for a useless weak foot cost the same, so the man would swap
## feet rather than contort -- and the thing everyone has watched a one-footed
## player do is contort. Over 1.0, he wraps his good foot round it and pays for
## that instead, and only a player with a genuine other foot switches.
const WEAK_FOOT_GAP := 1.3

## What striking a moving ball first-time costs in aim error, from the easiest
## first-time ball there is to the hardest.
##
## The two ends are different acts. A ball helped back the way it came -- the
## layoff -- is played with the ball's own pace: the foot is a wall angled at the
## man it returns to, and there is almost nothing to get wrong. A ball forced
## square or on, off a ball still moving across the body, is the hardest strike
## in the game. `redirect_share` says where between those a given line sits, and
## the decision layer reads the same function so the ball it prices is the ball
## that gets hit.
const FIRST_TIME_EASY := 1.08
const FIRST_TIME_HARD := 1.65
## The redirect angle past which a first-time ball keeps the whole penalty, in
## radians off straight-back-where-it-came-from. About a hundred degrees: within
## the cone the incoming pace is doing the work, beyond it the foot is.
const REDIRECT_ARC := 1.75

## First-time balls actually struck, and how many of them were layoffs -- helped
## back inside the easy half of the cone. Counted rather than logged per the
## usual contract; `reset_tallies` is called from `SimMatch.setup`.
static var ft_played := 0
static var ft_layoff := 0

## Whether the foot reaches the strike at all.
##
## The first thing to know about a body term added after the fact, and the one
## this project keeps being caught not asking: a factor that never varies cannot
## be the cause of anything, whatever it is worth. `lateral_of` is zero for a man
## playing the ball straight down the line he is facing, and if a carrier always
## faces where he is about to play it then the whole of `foot_cost` is dead code
## with a comment on it. These say otherwise or they do not.
##
## Boots only -- headers, chests and the keeper's hands are struck with things
## that have no handedness here.
static var foot_strikes := 0
static var foot_off_foot := 0
static var foot_cost_sum := 0.0
static var foot_across_sum := 0.0


## Kinds struck with a foot, which are the only ones a foot model applies to.
static func is_footed(kind: int) -> bool:
	return not is_thrown(kind) \
		and kind != SimTelemetry.Touch.HEADER \
		and kind != SimTelemetry.Touch.CHEST \
		and kind != SimTelemetry.Touch.KEEPER_CATCH \
		and kind != SimTelemetry.Touch.KEEPER_PARRY


static func reset_tallies() -> void:
	ft_played = 0
	driven_played = 0
	ft_layoff = 0
	chips_played = 0
	volleys_struck = 0
	foot_strikes = 0
	foot_off_foot = 0
	foot_cost_sum = 0.0
	foot_across_sum = 0.0


## How much of the first-time penalty a ball played along `dir` keeps, given the
## ball arriving with `ball_vel`: 0 for one eased straight back up its own line,
## 1 for one forced square or beyond.
static func redirect_share(ball_vel: Vector3, dir: Vector3) -> float:
	var line := SimConsts.horizontal(ball_vel)
	var d := SimConsts.horizontal(dir)
	if line.length() < 1.0 or d.length() < 1e-4:
		return 1.0
	var back: float = clampf((-line.normalized()).dot(d.normalized()), -1.0, 1.0)
	return clampf(acos(back) / REDIRECT_ARC, 0.0, 1.0)


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
			# Capped: the flight pays for the scan, not for the body over the
			# next strike. See `SimDecision.FLIGHT_PREP_CAP`.
			player.spell_prep_seconds = minf(
				float(ctx.tick_index - ctx.ball.last_touch_tick) * SimConsts.DT,
				SimDecision.FLIGHT_PREP_CAP)
	# Counted before the launch, because it is a fact about the man striking it.
	if is_footed(kind):
		var line := SimConsts.horizontal(vel)
		# The strike's tick and the wind-up he swung before it, for the view's
		# kick phase and the keeper. `SimDecision.fire` leaves `strike_act` set
		# through the strike so the swing can be read here; an instant strike
		# has none.
		player.struck_tick = ctx.tick_index
		player.struck_windup = 0.0
		if player.strike_at >= 0:
			player.struck_windup = float(player.strike_act.get("seconds", 0.0)) * (1.0 - player.rushed)
		foot_strikes += 1
		foot_cost_sum += foot_cost(player, line)
		foot_across_sum += absf(lateral_of(player, line))
		player.anim_foot = striking_foot(player, line)
		if player.anim_foot != player.attrs.foot:
			foot_off_foot += 1
	ctx.ball.launch(vel, spin)
	ctx.ball.last_touch_player = player.id
	ctx.ball.last_touch_team = player.team
	ctx.ball.last_touch_tick = ctx.tick_index
	ctx.ball.last_touch_kind = kind
	ctx.ball.last_touch_pos = before
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
	# A tackle too: a lunge or a slide is a shape held, not a follow-through.
	var thrown: bool = kind == SimTelemetry.Touch.THROW_IN or kind == SimTelemetry.Touch.KEEPER_THROW
	var slow: bool = thrown or kind == SimTelemetry.Touch.CHEST \
		or kind == SimTelemetry.Touch.HEADER or kind == SimTelemetry.Touch.TACKLE
	var anim := _anim_for(player, kind, vel.length(), before.y)
	if anim >= 0:
		var hold := 0.2
		if slow:
			hold = 0.45
		elif kind == SimTelemetry.Touch.FIRST_TOUCH:
			# A cushion is the foot set down, not a follow-through.
			hold = 0.35
		player.play_anim(anim, hold)

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
	if player.rushed > 0.0:
		data["rushed"] = player.rushed
	for key in extra:
		data[key] = extra[key]
	ctx.log_event(SimTelemetry.Ev.TOUCH, data)


## Above this pace a tackle is a slide; below it the man is standing and lunges.
## The sim does not model the difference, so the view is told by the speed he
## arrived at: a jog is a stretch of the leg, a run is a body on the grass.
const SLIDE_SPEED := 4.5
## A ball struck above this off the grass is a volley: the leg comes up to it.
const VOLLEY_HEIGHT := 0.45


## The pose for a touch, or -1 to leave the one already playing. `height` is
## the ball's when it was struck.
static func _anim_for(player: SimPlayer, kind: int, speed: float, height: float) -> int:
	match kind:
		SimTelemetry.Touch.HEADER:
			return SimConsts.Anim.HEADER
		SimTelemetry.Touch.CHEST:
			return SimConsts.Anim.CHEST
		SimTelemetry.Touch.FIRST_TOUCH:
			return SimConsts.Anim.TRAP
		SimTelemetry.Touch.TACKLE:
			return SimConsts.Anim.SLIDE if player.speed() > SLIDE_SPEED else SimConsts.Anim.TACKLE
		SimTelemetry.Touch.KEEPER_CATCH:
			return SimConsts.Anim.KEEPER_CATCH
		SimTelemetry.Touch.KEEPER_PARRY:
			# He is mid-dive: `SimKeeper` played it before the ball reached him,
			# and a pose named here would cut it off in the air.
			return -1
		SimTelemetry.Touch.THROW_IN, SimTelemetry.Touch.KEEPER_THROW:
			# The wind-up is already running -- `SimSetPiece.update` starts it when
			# the thrower picks the ball up -- and naming the same anim again here
			# leaves its phase alone, so the release lands in the middle of the
			# arc rather than restarting it.
			return SimConsts.Anim.THROW
		_:
			if height > VOLLEY_HEIGHT and kind != SimTelemetry.Touch.DRIBBLE:
				return SimConsts.Anim.VOLLEY
			return SimConsts.Anim.KICK_HARD if speed > 14.0 else SimConsts.Anim.KICK_LIGHT


# --- The planted foot -------------------------------------------------------


## How long the wind-up before a strike is, in seconds, by act and power
## (`docs/THE_FOOTBALL.md` 53). A plant and a leg drawn back: about half a
## second for a long ball or a hard shot, a sixth for a ball rolled to feet.
## None for a first-time strike -- its backlift was the flight he watched,
## and `SimDecision.readiness` already counts it. The price
## (`SimDecision._add_passes`, `expected_goals`) and the act
## (`SimDecision.wind_up`) read this one function.
const WINDUP_ROLLED := 0.15
const WINDUP_DRIVEN := 0.3
const WINDUP_LONG := 0.45
const WINDUP_SHOT_SOFT := 0.25
const WINDUP_SHOT_HARD := 0.45
## A ground pass is rolled under this and driven beyond twice it.
const WINDUP_GROUND_FROM := 8.0
const WINDUP_GROUND_TO := 32.0
## A lofted ball is a clip under this and a long ball beyond it.
const WINDUP_AIR_FROM := 15.0
const WINDUP_AIR_TO := 45.0


## `power` is the shot's 0..1, or 1.0 for a driven ground pass and 0 otherwise.
static func windup_for(kind: int, distance: float, power: float, first_time: bool) -> float:
	if first_time:
		return 0.0
	match kind:
		SimTelemetry.Touch.SHOT:
			return lerpf(WINDUP_SHOT_SOFT, WINDUP_SHOT_HARD, clampf(power, 0.0, 1.0))
		SimTelemetry.Touch.LOFTED_PASS, SimTelemetry.Touch.CROSS:
			return lerpf(WINDUP_DRIVEN, WINDUP_LONG,
				clampf((distance - WINDUP_AIR_FROM) / (WINDUP_AIR_TO - WINDUP_AIR_FROM), 0.0, 1.0))
		SimTelemetry.Touch.GROUND_PASS, SimTelemetry.Touch.THROUGH_BALL:
			var hard: float = maxf(clampf((distance - WINDUP_GROUND_FROM)
				/ (WINDUP_GROUND_TO - WINDUP_GROUND_FROM), 0.0, 1.0), clampf(power, 0.0, 1.0))
			return lerpf(WINDUP_ROLLED, WINDUP_DRIVEN, hard)
	return 0.0


## The kick the wind-up is posed as, chosen before the ball's speed is known:
## the same split `_anim_for` makes after it, read off the act instead.
static func windup_anim(kind: int, distance: float, power: float) -> int:
	match kind:
		SimTelemetry.Touch.GROUND_PASS, SimTelemetry.Touch.THROUGH_BALL:
			return SimConsts.Anim.KICK_HARD if distance > 18.0 or power > 0.5 else SimConsts.Anim.KICK_LIGHT
	return SimConsts.Anim.KICK_HARD


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
	# The floor came down 0.45 -> 0.38 (owner, 2026-08-31): a 1.0-quality
	# side sprayed its passes more than its class should.
	sigma *= lerpf(1.9, 0.38, clampf(skill, 0.0, 1.0))
	sigma *= 1.0 + 0.16 * press
	# The tackle arriving is not the man standing near: pressure rates a
	# challenger at the carrier's back at nearly zero (`apply`'s own note), so a
	# man being tackled paid ~6% on his strike while the hold and the set touch
	# paid challenge at full rate -- and the 31 m diagonal priced within a
	# coin-flip of the safe touch exactly when a challenger arrived (owner's
	# bookmark seed3-t75, 2026-08-31). Charged here so the priced ball and the
	# struck ball stay one model.
	sigma *= 1.0 + CHALLENGE_AIM * ctx.challenge_on(player)
	# The strike a challenge rushed (`SimPlayer.rushed`): the share of the
	# swing he did not get is priced as the hardest first-time ball.
	sigma *= lerpf(1.0, FIRST_TIME_HARD, player.rushed)
	sigma *= 1.0 + 0.35 * speed_ratio * speed_ratio
	sigma *= 1.0 + 0.012 * maxf(distance - 12.0, 0.0)
	sigma *= lerpf(1.25, 0.9, player.attrs.composure)
	sigma *= body_penalty(player, dir)
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


## The pace a player carries *along his body*, as a share of his top speed:
## the run-up behind the strike. The body is its own state
## (`SimPlayer.look_target`), so a man shuffling across his hips at four metres
## a second has none of it and a man sprinting has all of it. One helper for
## `momentum_of` and `strike_scale`, so the two cannot drift apart.
static func drive_of(player: SimPlayer) -> float:
	var along: float = player.vel.x * cos(player.facing) + player.vel.z * sin(player.facing)
	return clampf(along / maxf(player.nominal_max_speed(), 1e-3), 0.0, 1.0)


## The share of the facing cost a running player pays over a standing one. See
## `FACING_STATIC_SHARE`.
static func momentum_of(player: SimPlayer) -> float:
	return lerpf(FACING_STATIC_SHARE, 1.0, drive_of(player))


## Which side of the body the ball is being played to: -1 hard to his left, 0
## straight ahead or straight behind, +1 hard to his right.
##
## The companion of `off_axis`, which measures the same line in the other plane,
## and it is one function for the same reason that one is: the aim error, the
## range, the decision layer's estimate of both and the direction the ball bends
## all have to be reading the same angle.
##
## `heading_dir` is `(cos, 0, sin)`, so a man facing +X has +Z on his right.
static func lateral_of(player: SimPlayer, dir: Vector3) -> float:
	var d := SimConsts.horizontal(dir)
	var length := d.length()
	if length < 1e-6:
		return 0.0
	return clampf(player.heading_dir().cross(Vector3.UP).dot(d / length), -1.0, 1.0)


## How awkward this foot finds a ball played along `dir`: 0 natural, 1 at full
## stretch across himself.
##
## Zero on the whole of the side the boot opens onto, because the inside of the
## foot plays that ball and there is no cost to it, and rising into the side the
## foot is on, where he has to use the outside of it or reach across.
static func foot_awkwardness(player: SimPlayer, dir: Vector3, foot: int) -> float:
	var lateral := lateral_of(player, dir)
	var across: float = maxf(lateral if foot == SimAttributes.FOOT_RIGHT else -lateral, 0.0)
	return across * across


## Which foot he strikes this ball with and what it costs him, as
## `(foot, cost)` -- the cheaper of his two, once the weak one is charged for
## being the weak one.
##
## The two answers come out of one comparison on purpose. The foot the ball bends
## off has to be the foot he was charged for using, and computing them apart is
## the way that stops being true after the next edit to either.
##
## Note what is *not* here. `facing_penalty` lets technique buy back some of its
## cost, and this does not, because `weak_foot` is already the per-player dial and
## charging technique on top of it would be two attributes answering one
## question. A gifted one-footed player is a real thing and the engine should be
## able to produce him.
static func foot_choice(player: SimPlayer, dir: Vector3) -> Vector2:
	var strong := foot_awkwardness(player, dir, player.attrs.foot)
	var other := SimAttributes.other_foot(player.attrs.foot)
	var weak := foot_awkwardness(player, dir, other) \
		+ WEAK_FOOT_GAP * (1.0 - clampf(player.attrs.weak_foot, 0.0, 1.0))
	if strong <= weak:
		return Vector2(float(player.attrs.foot), clampf(strong, 0.0, 1.0))
	return Vector2(float(other), clampf(weak, 0.0, 1.0))


## What the ball being on the wrong side costs this player, 0 to 1.
static func foot_cost(player: SimPlayer, dir: Vector3) -> float:
	return foot_choice(player, dir).y


## Which foot actually strikes this ball.
static func striking_foot(player: SimPlayer, dir: Vector3) -> int:
	return int(foot_choice(player, dir).x)


## Multiplier on aim error for the ball being on the wrong foot.
static func foot_penalty(player: SimPlayer, dir: Vector3) -> float:
	return 1.0 + FOOT_COST * foot_cost(player, dir)


## Everything the body costs an action played along `dir`: which way he is
## pointing, and which foot it is on.
##
## One function, because `aim_sigma` charges it and `facing_control` refunds it,
## and a strike priced by one and executed under the other is the bug the
## reciprocal exists to prevent.
static func body_penalty(player: SimPlayer, dir: Vector3) -> float:
	return facing_penalty(player, dir) * foot_penalty(player, dir)


## The sidespin a strike is *meant* to have, in rad/s of yaw.
##
## The engine has always been able to bend a ball -- `SimBall` carries a
## three-axis spin and a Magnus term that is `spin.cross(vel)` -- and no strike
## in open play has ever meant to. Every curl was zero-mean noise scaled by
## technique, so the better a player was the harder he bent it in a direction
## `ctx.rng` chose, and half of every cross in the game curled into the keeper's
## hands. The physics was free and the intention was missing.
##
## The intention is the foot. The inside of the boot turns the ball away from the
## foot that struck it: right-footed it bends to his left, left-footed to his
## right. That single sign is the inswinging corner, the whipped cross from the
## wrong flank and the finish bent round the far post, and it is why an inverted
## winger is a shape somebody chose rather than a player standing on the wrong
## side.
##
## `mean` is the intended bend and `sigma` the part he does not control, so a man
## still occasionally steers one the other way with the outside of the foot --
## which is what the old comment here described and the old code could not tell
## apart from the ball he meant to whip.
##
## `spin` along +UP deflects the ball toward `UP.cross(vel)`, which is the
## striker's left when he is facing down the line of the ball. Only worth putting
## on a ball whose launch is *solved* with the spin in hand: the shot, the lofted
## pass and the cross all are, and the driven ground pass is not -- see
## `ground_pass`.
static func curl_for(ctx: SimContext, player: SimPlayer, dir: Vector3, mean: float, sigma: float) -> float:
	var sign: float = 1.0 if striking_foot(player, dir) == SimAttributes.FOOT_RIGHT else -1.0
	return (sign * mean + ctx.rng.gauss_clamped(0.0, sigma, 2.0)) \
		* clampf(player.attrs.technique, 0.0, 1.0)


## How much bend each struck ball is meant to have, and how much of it is noise.
##
## The cross is the biggest because whipping one is the whole act; the shot bends
## less because it is hit harder and travels less far; the lofted pass least,
## because a ball clipped over a line into space is not trying to curve round
## anything.
## **The cross was barely spinning and it is the reason nothing bent.** 3.4 rad/s
## is half a turn a second, where a footballer whips one at five to ten, and the
## flight bowed **0.28 m** over twenty-five metres -- a straight ball with a
## number on it. It was not raised before because the solver could not put it
## back: sidespin pushed the ball off its target and nothing corrected for it
## (`SimBallistics.solve_lofted`, now fixed). Measured with that in hand, the same
## cross bows **1.3 to 1.8 m** and still lands where it was aimed.
const CROSS_CURL := 40.0
const CROSS_CURL_SIGMA := 9.0
const SHOT_CURL := 1.9
const SHOT_CURL_SIGMA := 1.3
## And the bend a shot *means*, when the decision layer has found a blocker the
## curl takes out of the corridor (`SimDecision._add_shot`). `SHOT_CURL` is
## shape -- the small bend every strike carries; this is intent, a footballer's
## whip, and it bows a 20 m shot about half a metre (`SimBallistics.curl_bow`)
## -- a ball around a body. Technique scales it before it gets here. Starting
## value, unturned (`PLAN.md` 11.1.1).
const SHOT_CURL_BENT := 45.0
const LOFT_CURL := 1.2
const LOFT_CURL_SIGMA := 1.2


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


## The two costs are separate factors rather than one blended one, because they
## are different sentences about the strike. Behind him there is no backlift;
## on the wrong foot there is a backlift and no boot worth swinging. A man
## turning to hit one off his weaker foot is charged both, and should be.
## A strike a challenge rushed (`SimPlayer.rushed`) has that share of its
## backlift missing, and no backlift is `STRIKE_BEHIND`: the same number for
## the same fact.
static func strike_scale(player: SimPlayer, dir: Vector3) -> float:
	var off := off_axis(player, dir)
	var momentum: float = lerpf(STRIKE_STATIC_SHARE, 1.0, drive_of(player))
	var cost: float = clampf(off * off * lerpf(1.0, 0.75, deftness_of(player)) * momentum, 0.0, 1.0)
	return lerpf(1.0, STRIKE_BEHIND, cost) * lerpf(1.0, FOOT_STRIKE, foot_cost(player, dir)) \
		* lerpf(1.0, STRIKE_BEHIND, player.rushed)


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
## The reciprocal of `body_penalty`, and it exists so that a candidate priced
## with this and a touch struck with `aim_sigma` are talking about the same
## thing. A decision layer that scores a turn it cannot execute is the same bug
## as one that scores a nine-metre knock and then plays a four-metre touch.
##
## The name is still the facing's because that is what its one caller is asking
## about; what it refunds is everything the body costs, the foot included, which
## is what `aim_sigma` charges.
static func facing_control(player: SimPlayer, dir: Vector3) -> float:
	return 1.0 / body_penalty(player, dir)


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
##
## **And it came down anyway, 2026-08-23, because the ball changed under it.**
## `SimBallistics.solve_lofted` now corrects the launch heading for the spin on
## the ball, so the sideways spread a curled ball used to inherit is gone: the
## same bench rows that read 4.19 said against 4.52 rolled now read 5.05 against
## **3.83**, and the model was overstating by about a quarter at every distance on
## both air kinds. 0.085 to 0.066 is that quarter. The lesson is the one in the
## sentence above -- the bench is what keeps it honest -- and it caught this the
## first time it was asked.
const GROUND_AIM_BASE := 0.055
const AIR_AIM_BASE := 0.07
const AIR_MODEL_AIM_BASE := 0.066

## How much harder a ball in the air is to weight than one on the floor, and how
## much of the aim error goes into the launch angle rather than across it. Both
## were literals inside the two strikes; they are read by the model now, so they
## cannot drift from it.
const LOFT_WEIGHT_SCALE := 1.15
## And how much of the elevation error a cross carries, against the same man's
## lofted pass.
##
## **Because the range error it turns into is enormous.** Measured on
## `cross-loaded`, a ten per cent error in the weight of the strike came out as
## **nine metres** of range: trial after trial the ball either dropped nine metres
## short of the aim or sailed nine past it onto the goalkeeper, which is what the
## owner watched -- *the crosses are almost always hit too far or far forward,
## close to the goal, so the attacking players do not really have a chance*
## (2026-08-23). The amplification is physical and stays: a fast, flat ball
## overhit by a tenth crosses heading height a long way later.
##
## What is not physical is charging a winger a generic lofted ball's error on the
## one strike he hits fifty times a day at the same three targets. **And it is
## the elevation and not the weight**: halving the weight error moved the rolled
## range scatter 8.1 m to 6.9 and no further, because a five-degree error in the
## angle a flat ball leaves at is worth more range than a tenth of its speed.
## `_perturb` has carried the scale for exactly this since it was written --
## "flat balls are far less sensitive to it than lofted ones" -- and the cross is
## the flattest ball the engine strikes.
const CROSS_ELEVATION_SCALE := 0.5
const ELEVATION_SHARE := 0.75


## The flight time a lofted ball is asked for. A function of the distance alone,
## which is what lets the model work out the angle it leaves the boot at.
##
## There is a floor under it and it is not a taste question: below a certain
## flight time the only way to cover the ground is to strike the ball harder than
## a person can, and the solver will do it. Measured against the integrator, the
## knee where launch speed runs away sits at about 0.2 + 0.045 d.
static func lofted_flight(distance: float) -> float:
	return clampf(0.35 + distance * 0.055, 0.8, 2.4)


## And the flight a *cross* is asked for, which is a shorter one.
##
## A cross is whipped and a lofted pass is clipped: they are the same primitive
## and they are not the same ball. Asked for the lofted flight, a twenty-five
## metre cross hung for **1.73 s** and came down through heading height at 11.8
## m/s, which is a floated ball -- long enough for the goalkeeper to leave his
## line and take it, which is what the owner watched (2026-08-23). Football's is
## about 1.2 s over that distance and it arrives before he gets there.
##
## The floor is the same statement `lofted_flight`'s is: below it the only way to
## cover the ground is to strike the ball harder than a person can. Measured
## against the integrator at the arrival height a cross is solved for, a 25 m ball
## at 1.25 s leaves the boot at 24 m/s and a 40 m one at 1.7 s at 31 -- a
## full-blooded strike and no more, which is what this ball is.
static func cross_flight(distance: float) -> float:
	return clampf(0.30 + distance * 0.038, 0.7, 1.7)


## And the other end of it: the ball hung up rather than whipped in.
##
## A cross has two flights and the engine had one. The whipped one above beats
## the goalkeeper to the spot; this one buys a man time to get there, and it is
## the ball that goes over a defender's head onto somebody arriving at the far
## post. Which of them is struck is not a taste -- `SimDecision._add_crosses`
## fits the flight to how long the man it is for actually needs, so the ball is
## aimed at where he is going to be in time as well as in space (owner,
## 2026-08-23: *they should be aimed at where team mates are going to end up*).
##
## Higher, because the solver has to keep it in the air longer over the same
## ground. That is where the high cross went and where it comes back from.
static func cross_hang(distance: float) -> float:
	return clampf(0.45 + distance * 0.060, 1.0, 2.5)


## Where a cross of this length sits between the two: 1 whipped, 0 hung.
static func cross_whip_share(distance: float, flight: float) -> float:
	var whipped := cross_flight(distance)
	var hung := cross_hang(distance)
	if hung - whipped < 1e-3:
		return 1.0
	return clampf((hung - flight) / (hung - whipped), 0.0, 1.0)


## What share of a lofted pass's distance the ball covers *after* touchdown.
##
## The flight the solver lands wherever it is asked — verified to inside 2% —
## but it arrives with twelve to fifteen metres a second of horizontal pace and
## no backspin (backspin floats; see `LOFT_BACKSPIN`), so it skips on in hops
## for about two-fifths of the distance it flew. Measured on the bench with the
## noise off: +8.3, +12.3 and +16.2 m of deterministic run-on at 20, 30 and
## 40 m, a constant share. The owner watched it: "lofted balls go way too far."
##
## So the lofted pass is aimed to *finish* at the target rather than to land on
## it: touchdown is pulled short by this share, the hops carry the rest, and
## the man it was played to meets a ball that has sat down — which is also what
## `docs/THE_FOOTBALL.md` 23 asks of the ball over the top. A cross is exempt: it is
## attacked in the air at the point it drops, so it keeps landing on its aim.
const LOFT_RUNON_SHARE := 0.28

## The height a cross is aimed to arrive at, and the other half of the exemption
## above.
##
## "It is attacked in the air at the point it drops" was the argument, and the
## ball was still solved to arrive at **grass level** on the aim point, which is
## not the same thing: it comes down through a forehead's height several metres
## before it gets there. Measured on the bench once the bench was reading the
## right point — a cross aimed 20, 30 and 40 m is headable **5.3, 4.2 and 3.6 m
## short** of where it was aimed, every time, which puts it behind a man attacking
## the near post rather than on him. That is `docs/THE_FOOTBALL.md` 29 in one
## number, and it is why a headed attempt is struck from a median of 13 m.
##
## Solved rather than fudged: the aim keeps its point and gains a height, and
## `SimBallistics.solve_lofted` already takes the target height and already
## insists the ball be falling when it reaches it. `SimAerial.HEADER_FROM` is 1.75
## m, so a ball arriving here is one a man can actually head.
const CROSS_ARRIVE := 1.9


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
static func long_sigma(player: SimPlayer, skill: float, distance: float, axis: int,
		whip := 1.0) -> float:
	# The floor's spread is measured, not the square law's 2.0 it used to be.
	# The square law prices the ball's roll to rest, and a pass is not measured
	# there: it finishes where it has decayed to its arrival pace, and the
	# excess of an overhit ball is shed in the slowest part of the decay -- on a
	# driven ball, in the skim, where there is almost no friction to shed it
	# with. `DRIVE_BACKSPIN` going 0.2 to 0.5 gave the skim its bite back and
	# tightened the ball itself (22 m: 8.0 m long down to 6.5); re-rolled at 8,
	# 14, 22 and 30 m the implied scale is 3.1, 2.3, 2.6 and 2.1 times the
	# weight error, and a flat number in the middle is again closer than any
	# shape. Before the pair of fixes the decision layer was told a 25 m ball
	# in behind lands inside tolerance at nearly three times its real rate,
	# which is the giveaway the owner watched.
	var scale := GROUND_RANGE_SPREAD
	# And in the air it does not grow with the length of the ball the way a
	# straight line says. Measured on `./run.sh strike`, the lofted pass rolls
	# **6.1, 8.5 and 9.0 m** long at 20, 30 and 40 m, where a line through the
	# first of those puts 12 at forty: drag limits how far an overhit long ball
	# actually travels, and the model was charging a 42 m switch a quarter more
	# scatter than the ball has. It then told the decision layer the ball lands
	# inside its tolerance 39% of the time while the ball managed 52%, which is
	# the difference between a switch being on the list and being on it at zero.
	#
	# One knee for both air axes and a scale each, fitted to the six bench rows.
	var reach := distance / (1.0 + distance / AIR_RANGE_KNEE) if axis != LONG_GROUND else distance
	match axis:
		LONG_AIR:
			scale = AIR_RANGE_SPREAD
		LONG_AIR_CROSS:
			# And a cross is charged by how flat it is. The whipped ball's spread
			# is the one the bench measured after `cross_flight` landed; a hung
			# one is the ball that was there before it and scatters like the
			# lofted pass it flies like. Flat by default, so every caller that
			# does not know the flight asks about the ball the bench rolls.
			scale = lerpf(CROSS_HANG_SPREAD, CROSS_RANGE_SPREAD, clampf(whip, 0.0, 1.0))
	return scale * weight_sigma(player, skill) * reach


## How many times his weight error a ball in the air finishes off its mark by.
##
## Two numbers since `LOFT_RUNON_SHARE`, because the two balls finish
## differently. The lofted pass is aimed to sit down at its man, so the hops
## that used to amplify a weight error into rest-position scatter are spent
## short of him: re-rolled on the bench after the change, 2.6, 2.9 and 1.9
## times the weight error at twenty, thirty and forty metres, and a flat
## number in the middle is again closer than any shape.
##
## **The cross was 4.4 and is 2.3, because the bench was reading the wrong point
## of its flight.** `tools/strike_bench.gd` took an air ball's finish to be where
## it stops, which is right for the lofted pass and wrong for the one ball that is
## attacked before it ever gets there: it was charging the cross with 10.4, 13.0
## and 16.0 m of scatter measured at rest, tens of metres past the far post. Read
## where a cross is actually met -- coming down through heading height, which is
## what `CROSS_ARRIVE` now solves for -- the same strike rolls **5.8, 6.5 and
## 7.7 m**, or 2.8, 2.1 and 1.9 times the weight error, and a flat 2.3 is again
## closer than any shape.
##
## This is the two models being made to share one again rather than a softening:
## at 4.4 the decision layer was told a thirty-metre cross lands inside its
## tolerance 36% of the time when the ball manages 69%, so it turned down crosses
## it could hit. `docs/THE_FOOTBALL.md` 29.
## Where the air's range error stops growing with the length of the ball, in
## metres. See `long_sigma`: the three scales below are all measured against it,
## so moving it means re-reading the bench.
const AIR_RANGE_KNEE := 30.0
const AIR_RANGE_SPREAD := 4.8
## The floor's own, fitted to the same bench. See the note in `long_sigma`.
const GROUND_RANGE_SPREAD := 2.5
## **And the cross's own went 2.3 to 3.2 when the ball was whipped rather than
## floated** (`cross_flight`, 2026-08-23). A flatter, faster ball overhit by the
## same fraction of its weight sails much further before it drops back through
## heading height, and the bench says so: at 20, 30 and 40 m the same strike
## rolled 8.1, 9.5 and 12.2 m against a model still claiming 4.7, 7.0 and 9.3.
## The two models have to share one number or the decision layer is pricing a
## ball nobody hits -- which is the whole reason `./run.sh strike` exists.
const CROSS_RANGE_SPREAD := 4.7
## And what the same ball hung up rather than whipped scatters by, which is what
## the cross measured before it was given a flight of its own.
const CROSS_HANG_SPREAD := 3.4



## Probability that a struck ball actually lands within `tolerance` of where it
## was aimed, given the same error model the execution uses.
##
## The decision layer needs this: without it, a value function happily picks a
## forty-metre ball because the target square looks good, having no idea the
## player cannot hit it. Sharing `aim_sigma` means tuning the error model
## automatically retunes what the engine is willing to attempt.
static func execution_accuracy(ctx: SimContext, player: SimPlayer, skill: float, distance: float, base_sigma: float, tolerance: float, dir: Vector3 = Vector3.ZERO, long_axis: int = LONG_NONE, whip := 1.0) -> float:
	var sigma := aim_sigma(ctx, player, skill, distance, base_sigma, dir)
	var lateral := _within(tolerance, sigma * distance)
	if long_axis == LONG_NONE:
		return lateral
	return lateral * _within(tolerance,
		long_sigma(player, skill, distance, long_axis, whip))


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
## `LONG_GROUND` is the rolling law, `LONG_AIR` the flying ball that finishes
## at its man, and `LONG_AIR_CROSS` the cross, which lands hot on its spot and
## scatters accordingly; `long_sigma` has all three.
const LONG_NONE := 0
const LONG_GROUND := 1
const LONG_AIR := 2
const LONG_AIR_CROSS := 3


## Multiplier per unit of `challenge_on` (0 to 2) on every strike's aim error.
const CHALLENGE_AIM := 0.35


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


## How much of `ahead` this touch still has to open up.
##
## `ahead` is where the touch leaves the ball *relative to him* -- that is what
## `dribble_ahead` documents, what the debug overlay draws as the place he will
## meet it again, and what `SimDecision` prices the carry on. The strike below
## was sizing itself to open a further `ahead` on top of wherever the ball
## already was, and a carrier's ball is never at his feet: it lies most of a
## metre in front of him, because that is where his last touch put it.
##
## So a man asking for the ball 1.7 m in front of him got it 2.6 m in front,
## struck at 9.0 m/s while he ran at 5.3, and it stayed outside his 0.9 m reach
## for **1.15 seconds and nine metres of pitch** with his cooldown reading zero
## the whole way -- ready to play it and unable to reach it. The owner's words
## watching `1v1-clear` trials 4 and 7: *a carry forward becomes much longer than
## the player intended*.
##
## Zero when the ball is already further ahead than he wants it. There is nothing
## to open then, and the touch is the gentlest one he has.
##
## A settling touch is not in this frame at all -- `settle` measures against the
## grass -- so it does not ask.
static func dribble_opening(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var d := SimConsts.horizontal(dir)
	if d.length_squared() < 1e-6:
		return maxf(ahead, 0.0)
	var gap := SimConsts.horizontal(ctx.ball.ground_pos() - player.pos).dot(d.normalized())
	return clampf(ahead - maxf(gap, 0.0), 0.0, maxf(ahead, 0.0))


static func dribble(ctx: SimContext, player: SimPlayer, dir: Vector3, space: float, push: float = 0.0, away: float = 0.0, max_ahead: float = INF, settle: bool = false) -> void:
	var d := SimConsts.horizontal(dir)
	if d.length_squared() < 1e-6:
		d = player.heading_dir()
	d = d.normalized()
	var ahead := dribble_ahead(ctx, player, space, push, max_ahead)
	# The body goes where the ball is pushed.
	player.look_target = player.pos + d * 4.0
	# Relative speed that puts the ball `ahead` metres in front before friction
	# hands it back to the runner -- and, for a settling touch, the whole of the
	# strike, because there the runner is not going anywhere with it.
	# Only the part of `ahead` the ball has not already got. See
	# `dribble_opening`; a settling touch is measured against the grass and is
	# the whole strike either way.
	var opening: float = ahead if settle else dribble_opening(ctx, player, d, ahead)
	var delta := sqrt(2.0 * maxf(ctx.env.roll_decel, 0.1) * opening)
	var along: float = 0.0 if settle else maxf(player.vel.dot(d), 0.0)

	var sigma := aim_sigma(ctx, player, player.attrs.dribbling, ahead, DRIBBLE_AIM_BASE, d)
	# The weight error belongs to the part of the strike he is choosing, and for
	# a carry that is `delta` alone.
	#
	# `_perturb` scales the whole velocity, which everywhere else is the right
	# thing: a pass, a shot and a clearance are struck from nothing, so all of
	# the speed is his. A carry is not -- most of the ball's speed is the
	# momentum it already shares with a running man, and that is in the ball
	# whether he strikes it well or badly. Scaling it made the mis-hit bigger
	# than the intent: at 8.8 m/s the gap he wants is worth **0.93 m/s** of
	# relative speed and a twenty per cent error on the total is **1.95**, so the
	# size of a carry was decided by the draw and not by the decision. The ball
	# then ran metres past where he meant it to be -- `1v1-clear` trials 4 and 7,
	# and the owner's words: *a carry forward becomes much longer than the player
	# intended*.
	var weight: float = clampf(1.0 + ctx.rng.gauss_clamped(
		0.0, weight_sigma(player, player.attrs.dribbling) * 1.25, 2.5), 0.3, 2.0)
	var struck: float = clampf(along + delta * weight, 1.2, 16.0)
	var vel := (d * struck).rotated(Vector3.UP, ctx.rng.gauss_clamped(0.0, sigma, 2.8))
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
## `first_time` is a ball struck while it is still moving, priced by how far it
## has to be redirected -- see `FIRST_TIME_EASY`.
static func ground_pass(ctx: SimContext, player: SimPlayer, target: Vector3, arrive_pace: float, target_id: int, kind: int = SimTelemetry.Touch.GROUND_PASS, expected_value: float = 0.0, first_time: bool = false, curl_mean: float = NAN, trivela: bool = false) -> void:
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
	var curl := 0.0
	var lift := 0.0
	var launch_yaw := 0.0
	if is_thrown(kind):
		speed = ctx.ballistics.ground_pass_speed(distance, arrive_pace, ctx.env)
	else:
		# The curl on a driven ball, drawn *before* the solve so the launch is
		# solved with the spin in hand and comes back with the yaw that answers
		# it -- the ball bends and still arrives. Every driven ball carries the
		# bend its foot gives it (`curl_for`'s sign: the inside of the right boot
		# turns it left), at `PASS_CURL` and scaled by technique, as *shape*;
		# it was zero-mean noise until the solver could put a signed bend back
		# on its target, and now nothing keeps it so. A *meant* bend replaces
		# the shape with `curl_mean` -- the decision's signed, technique-scaled
		# whip, flipped for the trivela -- and lifts the ball so the same spin
		# has the air to work in. The noise is scaled here and the mean is not:
		# one charge, not two. The draw happens whether or not a bend was
		# meant, so the stream reads the same either way. Whether the ball is
		# driven is read off the closed-form speed, the same test
		# `ground_launch` opens with, so the draw happens exactly when the
		# solver can use it.
		if SimBallistics.drive_loft(
				ctx.ballistics.ground_pass_speed(distance, arrive_pace, ctx.env)) > 0.0:
			curl = ctx.rng.gauss_clamped(0.0, PASS_CURL_SIGMA, PASS_CURL_CLAMP) \
				* player.attrs.technique
			if is_nan(curl_mean):
				curl += pass_shape_curl(player, dir)
			else:
				curl += curl_mean
				# A meant bend is a lifted ball -- see `BEND_LIFT`.
				lift = SimBallistics.BEND_LIFT
		var launch := ctx.ballistics.ground_launch(distance, arrive_pace, ctx.env, curl, lift)
		speed = launch["speed"]
		launch_yaw = launch["yaw"]

	var sigma := aim_sigma(ctx, player, player.attrs.passing, distance, GROUND_AIM_BASE, dir)
	if trivela:
		sigma *= TRIVELA_SIGMA
	# Struck first-time, the error grows with how far the moving ball has to be
	# redirected. Read off the ball as it arrives, before `apply` replaces it.
	if first_time:
		sigma *= lerpf(FIRST_TIME_EASY, FIRST_TIME_HARD, redirect_share(ctx.ball.vel, dir))
		ft_played += 1
		if redirect_share(ctx.ball.vel, dir) < 0.45:
			ft_layoff += 1
	# The launch leaves the boot along the solved yaw -- off the line of the
	# aim, so the bend brings it back on -- while the aim error above was read
	# off the line he *means*, which is the ball he is charged for.
	var vel := _perturb(ctx, dir.rotated(Vector3.UP, launch_yaw) * speed, sigma,
		weight_sigma(player, player.attrs.passing), 0.0)
	vel.y = 0.0
	# The skim and the backspin are re-read off the *perturbed* speed, so an
	# overhit ball is driven a little harder and flatter, the way it came off
	# the boot, rather than wearing the intended strike's shape.
	if not is_thrown(kind):
		drive = SimBallistics.drive_loft(vel.length())
		if drive > 0.0:
			driven_played += 1
	vel.y = drive + lift
	var roll_rate := SimConsts.horizontal_length(vel) / SimConsts.BALL_RADIUS
	var spin := -Vector3.UP.cross(SimConsts.horizontal(vel).normalized()) \
		* (roll_rate * SimBallistics.drive_backspin(drive)) + Vector3.UP * curl

	apply(ctx, player, kind, vel, spin, target_id, {"dist": distance, "ft": first_time})
	_log_pass_attempt(ctx, player, kind, target, target_id, expected_value, distance, vel.length())


## Lofted pass or cross. `curl` is sidespin in rad/s, signed.
static func lofted_pass(ctx: SimContext, player: SimPlayer, target: Vector3, flight_time: float, target_id: int, kind: int = SimTelemetry.Touch.LOFTED_PASS, curl: float = 0.0, expected_value: float = 0.0, first_time: bool = false) -> void:
	var aim := target
	if not is_thrown(kind):
		aim = clamp_to_reach(player, ctx.ball.pos, aim, AIR_RANGE)
	aim.y = maxf(aim.y, SimConsts.BALL_RADIUS)
	# The touchdown is short of the aim and the run-on covers the rest; see
	# `LOFT_RUNON_SHARE`. The flight time shortens with the flight.
	if kind == SimTelemetry.Touch.LOFTED_PASS:
		var whole := SimConsts.horizontal(aim - ctx.ball.pos)
		aim = ctx.ball.pos + whole * (1.0 - LOFT_RUNON_SHARE)
		aim.y = maxf(target.y, SimConsts.BALL_RADIUS)
		flight_time = lofted_flight(SimConsts.horizontal_length(whole) * (1.0 - LOFT_RUNON_SHARE))
	elif kind == SimTelemetry.Touch.CROSS:
		# Arrive on the head, not on the grass. See `CROSS_ARRIVE`.
		aim.y = maxf(aim.y, CROSS_ARRIVE)
	var skill: float = player.attrs.crossing if kind == SimTelemetry.Touch.CROSS else player.attrs.passing
	var spin := Vector3.UP * curl
	var vel := ctx.ballistics.solve_lofted(ctx.ball.pos, aim, flight_time, ctx.env, spin)
	var line := SimConsts.horizontal(aim - ctx.ball.pos)
	var distance := line.length()

	var sigma := aim_sigma(ctx, player, skill, distance, AIR_AIM_BASE, line)
	if first_time:
		sigma *= lerpf(FIRST_TIME_EASY, FIRST_TIME_HARD, redirect_share(ctx.ball.vel, line))
		ft_played += 1
	var elevation := CROSS_ELEVATION_SCALE if kind == SimTelemetry.Touch.CROSS else 1.0
	vel = _perturb(ctx, vel, sigma, weight_sigma(player, skill) * LOFT_WEIGHT_SCALE, elevation)
	vel.y = maxf(vel.y, 1.0)

	apply(ctx, player, kind, vel, spin, target_id, {"dist": distance, "ft": first_time})
	_log_pass_attempt(ctx, player, kind, aim, target_id, expected_value, distance,
		vel.length(), flight_time)


## How long a chip hangs, by distance. Long enough to get over a keeper off his
## line, short enough that it is a finish rather than a cross to nobody.
static func chip_flight(distance: float) -> float:
	return clampf(0.55 + distance * 0.05, 0.9, 1.6)


## Chips actually struck. Counted, not logged; reset with the other tallies.
static var chips_played := 0
## Driven ground passes struck -- the ball the bent lane rides inside, so a bend
## count reads against this and not against every pass.
static var driven_played := 0


## Shot at a point in the goal mouth. `power` is 0..1 over the shot speed range.
## `chip` lifts the ball over an advanced keeper instead of driving it: the
## strike is solved as a dropping arc onto the aim point, and everything else --
## the error model, the log, the referee -- treats it as the shot it is.
## The height at which a shot is a full volley rather than a half-volley off the
## bounce, and what that costs and buys. Above the knee the ball has to be met
## with the body open, which is where both numbers come from.
const VOLLEY_FULL := 0.75
const VOLLEY_SIGMA := 1.9
const VOLLEY_POWER := 1.12
static var volleys_struck := 0


static func shot(ctx: SimContext, player: SimPlayer, aim_point: Vector3, power: float, first_time: bool, chance_quality: float, chip: bool = false, curl_mean: float = NAN, trivela: bool = false) -> void:
	var line := aim_point - ctx.ball.pos
	var speed: float = lerpf(SimConsts.SHOT_SPEED_MIN, SimConsts.SHOT_SPEED_MAX, clampf(power * lerpf(0.65, 1.0, player.attrs.power), 0.0, 1.0))
	# Nobody strikes one hard off his back foot. The same reach the passes are
	# clamped to, applied to the one number a shot is made of -- so a man with the
	# goal behind him gets a scuffed poke at it and has to turn to hit it properly.
	# `SimDecision.expected_goals` prices the same factor, so the shot the engine
	# takes is the shot it scored.
	speed *= strike_scale(player, line)
	var distance := SimConsts.horizontal_length(line)
	# The unmeant default, or the bend the decision priced. A meant mean comes
	# in technique-scaled, so only the noise is scaled here -- one charge, the
	# driven pass's contract. One draw either way; the stream cannot tell.
	var curl: float
	if is_nan(curl_mean):
		curl = curl_for(ctx, player, line, SHOT_CURL, SHOT_CURL_SIGMA)
	else:
		curl = curl_mean + ctx.rng.gauss_clamped(0.0, SHOT_CURL_SIGMA, 2.0) \
			* clampf(player.attrs.technique, 0.0, 1.0)
	var spin := Vector3.UP * curl
	var vel: Vector3
	if chip:
		chips_played += 1
		vel = ctx.ballistics.solve_lofted(ctx.ball.pos, aim_point, chip_flight(distance), ctx.env, spin)
	else:
		vel = ctx.ballistics.solve_direct(ctx.ball.pos, aim_point, speed, ctx.env, spin)

	# The scale is 1.0 at real time: `SimMatchConfig`, "the compressed match's
	# scoring fit".
	var sigma := aim_sigma(ctx, player, player.attrs.finishing, distance,
		SHOT_AIM_BASE * ctx.config.shot_sigma_scale(), line)
	if trivela:
		sigma *= TRIVELA_SIGMA
	if first_time:
		sigma *= 1.45
	# The volley, as its own act rather than an ordinary shot at a ball that
	# happens to be off the grass (`docs/THE_FOOTBALL.md` 29).
	#
	# Two things separate it and the engine had neither. A ball met in the air is
	# struck by a man who cannot plant his standing foot and set his body over it,
	# so it is far harder to keep down and to place -- and the elevation axis,
	# which `SHOT_ELEVATION_SPREAD` already says is the one that misses, is where
	# the error goes. And it comes off the boot faster than the same swing at a
	# dead ball, because the ball's own pace is added to the strike rather than
	# having to be generated.
	#
	# Scaled by height off the grass so an ankle-high half-volley is nearly the
	# ordinary shot and one at thigh height is the spectacular one, and by
	# `technique`, because that is the attribute the act is famous for needing.
	var lift: float = clampf(ctx.ball.pos.y / VOLLEY_FULL, 0.0, 1.0)
	if lift > 0.0:
		var skill: float = lerpf(1.0, 0.45, player.attrs.technique)
		sigma *= lerpf(1.0, VOLLEY_SIGMA * skill + (1.0 - skill), lift)
		speed *= lerpf(1.0, VOLLEY_POWER, lift)
		vel = ctx.ballistics.solve_direct(ctx.ball.pos, aim_point, speed, ctx.env, spin) \
			if not chip else vel
		volleys_struck += 1 if lift > 0.35 else 0
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
		"minute": ctx.minute(),
	}
	# Where the keeper stood when it was struck, off his line: the narrowing
	# (`SimKeeper._narrowed_station`) is read off this and nothing else.
	var keeper := ctx.teams[SimConsts.other_team(player.team)].keeper()
	if keeper != null and keeper.on_pitch:
		record["k_off"] = SimConsts.horizontal_length(keeper.pos - ctx.pitch.own_goal(keeper.team))
	ctx.log_event(SimTelemetry.Ev.SHOT, record)
	ctx.active_shot = record
	ctx.active_shot_tick = ctx.tick_index
	# And the bodies in front of it throw themselves at it, now, on the
	# backlift: `SimDuel.BLOCK_READ`.
	SimDuel.commit_blocks(ctx, player)


## What a first touch is going to be, before it is played: the direction he can
## actually turn the ball in, and how well he takes it. Written into three
## statics rather than returned, so the decision layer can ask the question
## without allocating and without a second copy of the model.
##
## The decision layer has to ask it. `SimDecision._add_hold` scores a first touch
## as keeping the ball, and where the ball ends up decides what that is worth --
## so the two layers have to agree about where that is. `docs/INVARIANTS.md` has
## the general case: the layer that scores an action and the layer that performs
## it holding separate opinions of it is this engine's most persistent bug, and
## the shared function is the only fix that stays fixed.
static var _ft_dir := Vector3.ZERO
static var _ft_wanted := Vector3.ZERO
static var _ft_quality := 0.0
## The angle the ball was turned through, signed; the body turns with it.
static var _ft_swing := 0.0


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
	# It is also the disagreement `docs/INVARIANTS.md` warns about, in its clearest form
	# yet: `SimDecision._shortlist` prices the same man's control of the same ball
	# at `lerpf(0.72, 0.99, first_touch)` when deciding whether to pass it to him,
	# while this graded what he then did with it at 0.02. One of the two was
	# wrong, and it was not the one calibrated against a footballer.
	var skill: float = player.attrs.first_touch * lerpf(0.75, 1.0, player.attrs.technique)
	var quality := _touch_quality(skill, difficulty)
	var wanted := dir
	_ft_swing = 0.0
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
			_ft_swing = applied
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
	# A touch turns the body. The hips swing toward where the ball is set, by
	# no more than the ball itself was turned -- the same limit, from the same
	# skill -- and the look is held there so the run out of the touch does not
	# take them back.
	var run := atan2(dir.z, dir.x)
	var most := absf(_ft_swing)
	player.facing += clampf(angle_difference(player.facing, run), -most, most)
	player.look_target = player.pos + dir * 4.0
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
## Most extra launch speed the incoming ball's pace can add to a header, m/s.
const HEADER_PACE_BONUS_MAX := 6.0


## `power_scale` is how much of his neck goes into it, and it is the only way
## this function can be told that a contact is a cushion rather than a nod. The
## power below is entirely about how far a man can *send* one -- `heading`,
## `jumping` and the pace already on the ball -- so a knock-down played at full
## power is a clearance whatever direction it is aimed in.
static func header(ctx: SimContext, player: SimPlayer, dir: Vector3, aim_up: float, intent: int = -1, goal_aim: Vector3 = Vector3.INF, chance_quality: float = 0.0, power_scale: float = 1.0) -> void:
	var d := SimConsts.horizontal(dir)
	if d.length_squared() < 1e-6:
		d = player.heading_dir()
	d = d.normalized()
	var incoming := ctx.ball.vel.length()
	# The incoming pace helps, and only up to a point: a neck redirects a
	# dropping cross, it does not return a driven goal kick with interest.
	# Uncapped, a 25 m/s ball came off the forehead at 21 and carried forty
	# metres -- the owner watched it, and `test_distances` now has the band.
	# **The band went 5-13 to 8-18, 2026-08-23** (owner: *the speed of the header
	# is too slow, it is going to be too easy to save the ball after one*).
	# Measured on `cross-open`, 61 headers at goal left the forehead at a mean
	# **12.8 m/s** -- from eleven metres that is nearly nine tenths of a second
	# for a goalkeeper, which is a save every time. A foot shot in this engine
	# leaves at 16 to 27 (`SimConsts.SHOT_SPEED_MIN`), and a header is slower than
	# a shot rather than half of one.
	#
	# The pace bonus went up with it. A cross now arrives through heading height
	# at 17 m/s where it used to arrive at 11.8 (`cross_flight`), and the cap was
	# fitted to the slower ball: it was throwing away most of what a man meeting a
	# whipped cross has to work with.
	var power: float = lerpf(8.0, 18.0, player.attrs.heading) \
		+ minf(incoming * 0.35, HEADER_PACE_BONUS_MAX)
	power *= lerpf(0.8, 1.1, player.attrs.jumping) * player.fatigue_factor() * power_scale
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


## What a body thrown at a shot does to it. Not `poke`: that is a boot hooking
## a ball off a carrier toward the far end, and a shot off a shin or a torso
## goes where the shin sent it. Most come back off him, out of the box at a
## fraction of the pace and off the floor; a share carry on, wrong-footing the
## keeper or running behind for the corner nobody could concede before this.
const BLOCK_ON := 0.3
const BLOCK_ON_SPREAD := 0.55
const BLOCK_BACK_SPREAD := 1.0


static func block(ctx: SimContext, player: SimPlayer) -> void:
	var v := ctx.ball.vel
	var inc := SimConsts.horizontal(v)
	var speed := inc.length()
	if speed < 1e-3:
		inc = player.heading_dir()
		speed = 1.0
	else:
		inc /= speed
	var dir: Vector3
	var keep: float
	if ctx.rng.chance(BLOCK_ON):
		dir = inc.rotated(Vector3.UP, ctx.rng.gauss_clamped(0.0, BLOCK_ON_SPREAD, 2.0))
		keep = ctx.rng.range_float(0.45, 0.8)
	else:
		dir = (-inc).rotated(Vector3.UP, ctx.rng.gauss_clamped(0.0, BLOCK_BACK_SPREAD, 2.0))
		keep = ctx.rng.range_float(0.2, 0.5)
	var out_speed: float = speed * keep
	var lift: float = ctx.rng.range_float(0.3, 2.5)
	player.spend_action(2.5)
	apply(ctx, player, SimTelemetry.Touch.BLOCK, dir * out_speed + Vector3(0.0, lift, 0.0), Vector3.ZERO)


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


static func _log_pass_attempt(ctx: SimContext, player: SimPlayer, kind: int, target: Vector3, target_id: int, expected_value: float, distance: float, struck: float, flight := 0.0) -> void:
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
		# How long it was asked to be in the air, for the one ball whose flight is
		# not a function of its length: a cross is whipped or hung, and an
		# instrument that assumes the first cannot see the second.
		"flight": flight,
		"lead": lead,
		"rmax": rmax,
	})
