class_name SimDuel
extends RefCounted
## Resolves who actually touches the ball on a given tick.
##
## Tackling is not a special case (PLAN.md §3.3). A defender within control
## range may attempt a poke or a block like any other touch. When two players
## are in range on the same tick, the contest is a weighted random on tackling
## versus dribbling and closing speed, followed by a roll for a foul --
## probability rising with closing speed and with the tackler being the loser.

## Contest weights.
const CLOSING_SPEED_WEIGHT := 0.09
## What a carrier who invites the contact multiplies the foul roll by, at full
## composure. See where it is applied.
const INVITE_CONTACT := 1.6
## How far from their goal it is worth doing: a free kick out here is worth less
## than the ball, and a footballer who goes down on halfway has given it away.
const INVITE_RANGE := 30.0


## How much of the carrier's body is between the challenger and the ball: 1 with
## the man square at his back, 0 with the man in his face. The shield is the
## carrier's choice (`SimPlayer.shielding`, set by `SimDecision._play_hold`) and
## this is how well it was made -- the hips turn at `turn_rate`, so a shield
## called with the man in front of him is not yet one.
static func shielded(carrier: SimPlayer, challenger: SimPlayer) -> float:
	var to := SimConsts.horizontal(challenger.pos - carrier.pos)
	var d := to.length()
	if d < 1e-4:
		return 0.5
	var frontness: float = 0.5 * (clampf((to / d).dot(carrier.heading_dir()), -1.0, 1.0) + 1.0)
	return 1.0 - frontness


## Is this a moment worth inviting contact in? Their half, inside range of goal,
## and with the ball actually at his feet.
static func _invites_contact(ctx: SimContext, carrier: SimPlayer) -> bool:
	var goal := ctx.pitch.target_goal(carrier.team)
	return SimConsts.horizontal_length(goal - carrier.pos) <= INVITE_RANGE


## Base foul probability for a lost tackle, before closing speed.
const FOUL_BASE := 0.022
const FOUL_PER_CLOSING_SPEED := 0.010

## How close a defender must be to the *carrier* to challenge him, even though
## the ball itself is beyond his reach (PLAN.md §3.3). Without this a carry can
## only be ended by the carrier's own choice or his own mistake: he pushes the
## ball two to four metres ahead, so a defender a metre behind him is three to
## five metres from the ball and can never contest anything.
## Measured, not guessed: at twice control range defenders were inside it for
## eleven seconds of a thirty-minute match, so the mechanic had almost no
## opportunities to fire. A defender who reads as "on the carrier's back" from
## the match camera is nearer three metres away than two.
const CHALLENGE_RADIUS := 3.0
## Contesting a man in possession is harder than arriving at a ball nobody owns,
## and coming from behind him is harder still — and far more likely to be a foul.
const CHALLENGE_WEIGHT_FRONT := 0.6
const CHALLENGE_WEIGHT_BEHIND := 0.32
const CHALLENGE_FOUL_FRONT := 1.0
const CHALLENGE_FOUL_BEHIND := 2.4
## Being close enough to challenge is not the same as committing to one, and the
## difference is most of what a defender does. Containing the carrier is the
## default; going in is an occasional decision, scaled by aggression. Without
## this a trailing defender lunges on every tick he is in range — which produced
## a challenge every 2.7 seconds and roughly eighty fouls a side.
const CHALLENGE_COMMIT_PER_SECOND := 0.5

static var _contenders: Array[SimPlayer] = []
static var _weights := PackedFloat32Array()
## Per-contender modifiers, parallel to `_contenders`. 1.0 for anyone contesting
## the ball itself; less for a defender challenging the man.
static var _challenge_win := PackedFloat32Array()
static var _challenge_foul := PackedFloat32Array()
## And how much of the challenge was the deliberate one, 0 to 1.
static var _challenge_cynical := PackedFloat32Array()

## The deliberate foul. The cynical foul that stops a break already fell out
## of the challenge from behind (`CHALLENGE_FOUL_BEHIND`) by accident; this is
## the choice. A defender who is behind or beside a carrier running at his
## goal, with no more of his own men goal-side than they have attackers, and
## outside his own area, goes in when he otherwise would not and goes through
## the man when he does. Priced by aggression, because that is the attribute.
## The card is the referee's, as for any foul.
const PRO_FOUL_COMMIT := 5.0
const PRO_FOUL := 2.5
const PRO_FOUL_RANGE := 55.0
const PRO_FOUL_RUNNING := 2.0
const PRO_FOUL_FRONTNESS := 0.65
## With the numbers not short, how far the nearest cover has to be from the
## carrier before the foul is worth it, and where it is fully worth it.
const PRO_FOUL_COVER_NEAR := 6.0
const PRO_FOUL_COVER_FAR := 14.0
## Tallies, whole match. Read by `diagnose`: the ticks a challenger had the
## moment, the challenges it produced, the fouls from those.
static var cynical_moments := 0
static var cynical_challenges := 0
static var cynical_fouls := 0


## How much this is the moment for the deliberate foul, 0 to 1.
static func _cynical(ctx: SimContext, p: SimPlayer, carrier: SimPlayer, frontness: float) -> float:
	# Behind him or level with him: the man losing the race pulls him back.
	if frontness > PRO_FOUL_FRONTNESS:
		return 0.0
	var own_goal := ctx.pitch.own_goal(p.team)
	var to_goal := SimConsts.horizontal(own_goal - carrier.pos)
	var range_to_goal := to_goal.length()
	if range_to_goal > PRO_FOUL_RANGE or range_to_goal < 1.0:
		return 0.0
	if ctx.pitch.in_own_penalty_area(p.team, carrier.pos):
		return 0.0
	if carrier.vel.dot(to_goal / range_to_goal) < PRO_FOUL_RUNNING:
		return 0.0
	# The numbers: ours goal-side of him, bar the challenger, against theirs
	# -- and, short of that, whether the nearest of ours goal-side is near
	# enough to cover. A man beaten with the cover twelve metres off has the
	# same choice to make as a man beaten on a two-on-two.
	var dir := ctx.pitch.attack_dir(p.team)
	var ours := 0
	var theirs := 0
	var cover_gap := INF
	for q in ctx.players:
		if not q.on_pitch or q.is_keeper or q.id == p.id or q.id == carrier.id:
			continue
		if (q.pos.x - carrier.pos.x) * dir < 0.0:
			if q.team == p.team:
				ours += 1
				cover_gap = minf(cover_gap, q.dist_to(carrier.pos))
			else:
				theirs += 1
	var moment: float
	if theirs >= ours:
		moment = 1.0
	else:
		moment = clampf((cover_gap - PRO_FOUL_COVER_NEAR) / (PRO_FOUL_COVER_FAR - PRO_FOUL_COVER_NEAR), 0.0, 1.0)
	if moment > 0.0:
		cynical_moments += 1
	return moment * lerpf(0.5, 1.2, p.attrs.aggression)




## How far round a man's leg reaches: a ball in front of his hips or beside
## him is his, a ball behind him is not until he has turned. About 110 degrees
## either side of where he faces.
##
## The contact rule took any ball inside `CONTROL_RANGE` whichever way the man
## was pointing, so a back line facing its own goal cut out the ball played
## behind it, and the lane model, pricing that ball by the turn he would need,
## had nothing to agree with (`docs/INVARIANTS.md`, two models of one event).
## The same arc is what `SimDecision._facing_cost` charges the turn beyond.
const REACH_ARC := 1.92


## Whether he can see the ball: inside the arc `SimPerception` gives his eyes.
static func sees_ball(p: SimPlayer, ball_pos: Vector3) -> bool:
	var to_ball := SimConsts.horizontal(ball_pos - p.pos)
	if to_ball.length_squared() < 0.04:
		return true
	var face := SimConsts.horizontal(p.heading_dir())
	if face.length_squared() < 1e-6:
		return true
	return face.normalized().dot(to_ball.normalized()) >= cos(SimPerception.view_half(p, 0.5))


## A ball struck at his feet is his to play; a ball passing a leg's length off
## them is not, until he has reacted and reached for it.
const AT_FEET := 0.35


## Whether he has had time to get a leg to a ball that is not at his feet.
##
## Reach was instant: any ball inside `CONTROL_RANGE` was played the tick it
## got there, whichever way the man was pointing and whether or not he had seen
## it struck. A footballer reacts and then reaches (owner, 2026-08-29), and the
## clock starts when the ball became news to him -- the strike, if he had the
## striker in his eyes (`SimPerception.saw_recently`, arc plus memory; his own
## side always did, it is their ball), otherwise the tick it came into his view.
## The lane model charges the same reaction in `SimDecision._cut_chance` and
## `_facing_cost`, so the two say one thing about one ball.
##
## Not for the man whose ball it is, and not for anyone while it is at a
## carrier's feet: that contest is `_add_challengers`' and the duel's.
static func _ready_for(ctx: SimContext, p: SimPlayer) -> bool:
	var ball := ctx.ball
	if ball.last_touch_player == p.id or ball.last_touch_player < 0:
		return true
	if p.dist_to(ball.pos) <= AT_FEET:
		return true
	var striker := ctx.players[ball.last_touch_player]
	if striker.on_pitch and striker.dist_to(ball.pos) <= SimConsts.CONTROL_RANGE:
		return true
	return ball_news_age(ctx, p) >= p.reaction


## Seconds since the ball became news to this player: the strike, if he had the
## striker in his eyes, otherwise the tick the ball came into his view --
## negative while it still has not. His own side's ball is always news he had.
## The clock `_ready_for` runs reach on, public so the chase can run its legs on
## it too (`SimMovement._recompute_target`): one answer to one question.
static func ball_news_age(ctx: SimContext, p: SimPlayer) -> float:
	var ball := ctx.ball
	if ball.last_touch_player < 0:
		return INF
	# A ball at a carrier's feet is not a strike, and the clock is for balls in
	# flight. Without this the dribble stamped `last_touch_tick` every 0.17 to
	# 0.27 s -- faster than a 0.16 to 0.36 s reaction -- so the clock reset
	# before it ever elapsed and every presser behind a dribbling carrier was
	# capped at a walk (owner's bookmark seed3-t410, 2026-08-31: pressure 0.0
	# to 0.4 around the ball and a 32 m diagonal picked at 100%). The same
	# exemption `_ready_for` applies before asking, made shared.
	var striker := ctx.players[ball.last_touch_player]
	if striker.on_pitch and striker.dist_to(ball.pos) <= SimConsts.CONTROL_RANGE:
		return INF
	var news := ball.last_touch_tick
	if ball.last_touch_team != p.team \
			and not SimPerception.saw_recently(ctx, p, ctx.players[ball.last_touch_player]):
		if not sees_ball(p, ball.pos):
			p.ball_seen_tick = -1
			return -1.0
		if p.ball_seen_tick < 0:
			p.ball_seen_tick = ctx.tick_index
		news = p.ball_seen_tick
	return float(ctx.tick_index - news) * SimConsts.DT


## Whether the ball is within the arc his leg can reach without turning.
static func in_reach_arc(p: SimPlayer, ball_pos: Vector3) -> bool:
	var to_ball := SimConsts.horizontal(ball_pos - p.pos)
	if to_ball.length_squared() < 0.04:
		return true
	var face := SimConsts.horizontal(p.heading_dir())
	if face.length_squared() < 1e-6:
		return true
	return face.normalized().dot(to_ball.normalized()) >= cos(REACH_ARC)


# --- The block --------------------------------------------------------------


## How far in front of the striker a body can throw itself at the ball. Past
## this the ordinary contact rule has him: the ball arrives after his reaction
## has run (`_ready_for`), and he sticks a leg out like at any pass.
const BLOCK_RANGE := 6.0
## The anticipation, in seconds: a defender in the striker's face moves on the
## backlift, not on the strike. A shot at 25 m/s is past a man four metres away
## in 0.16 s and no reaction reaches it; the read is the whole mechanic.
const BLOCK_READ := 0.25
## What a body thrown sideways covers from where he stands, in metres -- a leg
## flung out, a torso turned across the ball -- and what the lunge adds per
## second of window.
const BLOCK_REACH := 1.4
const BLOCK_CLOSE := 3.5
## The ball above this at his station goes over the block.
const BLOCK_HEIGHT := 1.6
## What a man dead on the line gets, and how the chance falls off toward the
## edge of his cover.
const BLOCK_COMMIT := 0.85
const BLOCK_FALLOFF := 0.7
## How long he is on the floor for after throwing himself, whether or not he
## got there. In seconds; his own `recovery_ticks` brake.
const BLOCK_DOWN_MIN := 0.3
const BLOCK_DOWN_MAX := 0.5
## The wall. How far in front of the ball a wall man still counts as one, the
## half-width of the body he puts in the way, how high he gets, and what a ball
## into that gets stopped by.
const WALL_ALONG := 12.0
const WALL_BODY := 0.5
const WALL_JUMP := 2.3
const WALL_STOPS := 0.9


## The chance this defender blocks a ball struck from `from` along `dir` at
## `speed`, with the striker `shooter` in front of him. Zero for anyone the
## lunge model does not cover; `_shot_blockers` in `SimDecision` prices those
## as bodies in the corridor. One function for the price and the act
## (`docs/INVARIANTS.md`, the contact rule and the lane model read the same
## body).
static func block_chance(ctx: SimContext, o: SimPlayer, shooter: SimPlayer, from: Vector3,
		dir: Vector3, speed: float, launch_y: float = 0.0, climb: float = 0.0) -> float:
	if not o.on_pitch or o.is_keeper or o.recovery_ticks > 0 or o.team == shooter.team:
		return 0.0
	var rel := SimConsts.horizontal(o.pos - from)
	var along: float = rel.dot(dir)
	var lateral: float = absf(rel.x * dir.z - rel.z * dir.x)
	var t: float = along / maxf(speed, 1.0)
	# Where the ball is when it gets to him: a rising drive clears a body.
	var y: float = launch_y + climb * t - 0.5 * SimConsts.GRAVITY * t * t
	# A man in a wall: a standing body that jumps, at the wall's distance. No
	# read, no lunge; the ball goes through his metre or it does not.
	if o.in_wall:
		if along < 0.8 or along > WALL_ALONG or lateral > WALL_BODY or y > WALL_JUMP:
			return 0.0
		return WALL_STOPS
	if along < 0.8 or along > BLOCK_RANGE:
		return 0.0
	if y > BLOCK_HEIGHT:
		return 0.0
	# He has to have the striker in his eyes to read the backlift.
	if not SimPerception.saw_recently(ctx, o, shooter):
		return 0.0
	var window: float = t + BLOCK_READ
	# The way he is already moving, toward or away from the line.
	var toward := Vector3(-dir.z, 0.0, dir.x)
	if rel.dot(toward) > 0.0:
		toward = -toward
	var drift: float = maxf(o.vel.dot(toward), 0.0) * t
	var cover: float = BLOCK_REACH + BLOCK_CLOSE * window + drift
	if lateral >= cover:
		return 0.0
	var chance: float = BLOCK_COMMIT * pow(1.0 - lateral / cover, BLOCK_FALLOFF)
	chance *= lerpf(0.8, 1.15, o.attrs.positioning)
	chance *= lerpf(0.9, 1.1, o.attrs.aggression)
	return clampf(chance, 0.0, 0.95)


## The share of a shot from `from` at `aim` that gets past every body in lunge
## range. What `SimDecision.expected_goals` charges for the near bodies.
static func block_survival(ctx: SimContext, shooter: SimPlayer, from: Vector3, aim: Vector3,
		speed: float) -> float:
	var dir := SimConsts.horizontal(aim - from)
	var d := dir.length()
	if d < 1e-3:
		return 1.0
	dir /= d
	var survival := 1.0
	for oid in ctx.opponent_ids(shooter.team):
		var chance := block_chance(ctx, ctx.players[oid], shooter, from, dir, speed)
		if chance > 0.0:
			survival *= 1.0 - chance
	return survival


## The strike has been made: every defender in lunge range throws himself at
## it, and one roll each says whether he gets there. Decided here and taken
## when the ball arrives, the keeper's own pattern -- a per-tick roll is a roll
## until it succeeds (`docs/INVARIANTS.md`).
static func commit_blocks(ctx: SimContext, shooter: SimPlayer) -> void:
	var ball := ctx.ball
	var dir := SimConsts.horizontal(ball.vel)
	var speed := dir.length()
	if speed < 1.0:
		return
	dir /= speed
	var from := ball.pos
	# The nearest body in front of the strike, on the shot's own record, so the
	# instruments can say whether a block share is geometry or the model.
	var near_along := INF
	var near_lat := 0.0
	var near_saw := false
	var near_d2 := INF
	for oid in ctx.opponent_ids(shooter.team):
		var o := ctx.players[oid]
		if o.on_pitch and not o.is_keeper:
			var rel := SimConsts.horizontal(o.pos - from)
			var along: float = rel.dot(dir)
			if along > 0.8 and rel.length_squared() < near_d2:
				near_d2 = rel.length_squared()
				near_along = along
				near_lat = absf(rel.x * dir.z - rel.z * dir.x)
				near_saw = SimPerception.saw_recently(ctx, o, shooter)
	if not ctx.active_shot.is_empty() and not is_inf(near_along):
		ctx.active_shot["near_along"] = near_along
		ctx.active_shot["near_lat"] = near_lat
		ctx.active_shot["near_saw"] = near_saw
	for oid in ctx.opponent_ids(shooter.team):
		var o := ctx.players[oid]
		var chance := block_chance(ctx, o, shooter, from, dir, speed, ball.pos.y, ball.vel.y)
		if chance <= 0.0:
			continue
		var rel := SimConsts.horizontal(o.pos - from)
		var along: float = rel.dot(dir)
		var t: float = along / speed
		var arrive := ctx.tick_index + int(ceil(t * float(SimConsts.TICK_HZ)))
		o.block_shot = ball.last_touch_tick
		o.block_tick = arrive
		o.block_until = arrive + int(round(0.15 * float(SimConsts.TICK_HZ)))
		o.block_point = Vector3(from.x + dir.x * along, 0.0, from.z + dir.z * along)
		o.block_hit = ctx.rng.chance(chance)
		# He goes now, not on the movement cadence: the whole act is shorter
		# than one.
		o.move_target = o.block_point
		o.move_speed_cap = o.max_speed()
		o.move_deadband = 0.15
		o.look_target = Vector3.INF
		o.play_anim(SimConsts.Anim.SLIDE, t + BLOCK_READ + 0.3)
		ctx.log_event(SimTelemetry.Ev.BLOCK_LUNGE, {
			"p": o.id,
			"team": o.team,
			"chance": chance,
			"hit": o.block_hit,
		})


## Takes the blocks committed at the strike, on the tick the ball reaches each
## man. The ball must still be the shot he threw himself at.
static func _resolve_blocks(ctx: SimContext) -> void:
	var ball := ctx.ball
	for o in ctx.players:
		if o.block_shot < 0:
			continue
		if o.block_shot != ball.last_touch_tick or not o.on_pitch:
			o.block_shot = -1
			continue
		if ctx.tick_index < o.block_tick:
			continue
		o.block_shot = -1
		# On the floor either way.
		o.recovery_ticks = maxi(o.recovery_ticks,
			int(ctx.rng.range_float(BLOCK_DOWN_MIN, BLOCK_DOWN_MAX) * float(SimConsts.TICK_HZ)))
		if not o.block_hit:
			continue
		SimTouch.block(ctx, o)
		# One block per shot: the ball is a different ball now.
		for other in ctx.players:
			other.block_shot = -1
		return


static func resolve_contacts(ctx: SimContext) -> void:
	_contenders.clear()
	_challenge_win.clear()
	_challenge_foul.clear()
	_challenge_cynical.clear()
	var ball := ctx.ball
	# A ball in a goalkeeper's hands is not a loose ball, and this is the only
	# place that could have said so. See `SimKeeper.ball_in_hands`.
	if SimKeeper.ball_in_hands(ctx):
		return
	_resolve_blocks(ctx)
	var overhead := SimAerial.is_aerial(ctx)
	for p in ctx.players:
		# Note the cooldown is deliberately *not* checked here. A player who has
		# just touched the ball is still standing over it, shielding it and being
		# challenged for it. Requiring a ready cooldown to be a contender means
		# duels essentially never happen, because the carrier is always on one.
		if not p.on_pitch or p.recovery_ticks > 0:
			continue
		if p.is_keeper:
			continue  # The keeper module owns its own contact rules.
		if p.block_shot >= 0:
			continue  # Thrown at the shot; `_resolve_blocks` has him.
		if p.escorting:
			continue  # Walking it out; the whole point is not to touch it.
		# A ball over head height is met with a leap, which arrives further from
		# where he was standing than a boot does. `SimAerial.contact_range` is the
		# one place that difference is stated.
		var reach := SimAerial.contact_range(ball.pos.y)
		if p.dist_sq_to(ball.pos) > reach * reach:
			continue
		if not SimTouch.playable_height(p, ball.pos.y):
			continue
		# A ball over his head that he would rather take on his chest a moment
		# from now. He is not a contender for it, which is the whole of the
		# mechanic: nobody touches it, and it comes down.
		# A ball behind him is not his to play until he has turned. His own
		# ball is left out: a carrier's knock is in front of him by construction
		# and the touch model owns how he gets to it.
		if not overhead and ball.last_touch_player != p.id and not in_reach_arc(p, ball.pos):
			continue
		if not overhead and not _ready_for(ctx, p):
			continue
		if overhead and SimAerial.lets_it_drop(ctx, p):
			continue
		# And the same man a band lower, on his own ball, between the chest-down
		# he has just played and the feet it is dropping to. See
		# `SimAerial.settling_a_chest`.
		if SimAerial.settling_a_chest(ctx, p):
			continue
		_contenders.append(p)
		_challenge_win.append(1.0)
		_challenge_foul.append(1.0)
		_challenge_cynical.append(0.0)

	_add_challengers(ctx)

	if _contenders.is_empty():
		return
	if _contenders.size() == 1:
		if _contenders[0].can_touch():
			_act(ctx, _contenders[0], false)
		return

	# Are the contenders from both sides?
	var first_team: int = _contenders[0].team
	var contested := false
	for p in _contenders:
		if p.team != first_team:
			contested = true
			break

	if not contested:
		# Same side: the best placed player who can actually play it takes it,
		# and nobody else does.
		var best: SimPlayer = null
		for p in _contenders:
			if not p.can_touch():
				continue
			if best == null or p.dist_sq_to(ball.pos) < best.dist_sq_to(ball.pos):
				best = p
		if best != null:
			_act(ctx, best, false)
		return

	_resolve_contest(ctx)


## Adds opponents who are on the carrier rather than on the ball.
##
## Only fires when someone is actually carrying: a contender who last touched the
## ball and is therefore in control of it. A loose ball is contested on ball
## proximity alone, as before.
static func _add_challengers(ctx: SimContext) -> void:
	var ball := ctx.ball
	var carrier: SimPlayer = null
	for p in _contenders:
		if ball.last_touch_player == p.id:
			carrier = p
			break
	if carrier == null:
		return

	# The carrier's body, which is his own state and not his run: a man held
	# on a look is challenged from where the look leaves his back.
	var heading := carrier.heading_dir()
	for p in ctx.players:
		if p.team == carrier.team or not p.on_pitch or p.recovery_ticks > 0 or p.is_keeper:
			continue
		if _contenders.has(p):
			continue  # Already contesting the ball itself, on better terms.
		# A challenge is an action, so it costs one: unlike a contest over a
		# loose ball, the cooldown is checked.
		if not p.can_touch():
			continue
		var to := SimConsts.horizontal(p.pos - carrier.pos)
		var d := to.length()
		if d > CHALLENGE_RADIUS or d < 1e-4:
			continue
		var commit := CHALLENGE_COMMIT_PER_SECOND * SimConsts.DT * lerpf(0.5, 1.6, p.attrs.aggression)
		# 0 is directly behind the carrier, 1 is square in front of him.
		var frontness: float = 0.5 * (clampf((to / d).dot(heading), -1.0, 1.0) + 1.0)
		# The deliberate foul: he goes in when he otherwise would not.
		var cynical := _cynical(ctx, p, carrier, frontness)
		commit *= 1.0 + cynical * (PRO_FOUL_COMMIT - 1.0)
		if not ctx.rng.chance(commit):
			continue
		if cynical > 0.0:
			cynical_challenges += 1
		_contenders.append(p)
		_challenge_win.append(lerpf(CHALLENGE_WEIGHT_BEHIND, CHALLENGE_WEIGHT_FRONT, frontness))
		_challenge_foul.append(lerpf(CHALLENGE_FOUL_BEHIND, CHALLENGE_FOUL_FRONT, frontness)
			* (1.0 + cynical * (PRO_FOUL - 1.0)))
		_challenge_cynical.append(cynical)


## A weighted random over the contenders, then a foul roll.
static func _resolve_contest(ctx: SimContext) -> void:
	var n := _contenders.size()
	if _weights.size() != n:
		_weights.resize(n)
	var ball := ctx.ball
	var aerial := SimAerial.is_aerial(ctx)
	for i in n:
		var p := _contenders[i]
		var holder := ball.last_touch_player == p.id
		# Whoever has just touched it is defending possession with dribbling and
		# strength; whoever is arriving is contesting it with tackling. Neither
		# applies over head height: nobody is holding a ball he cannot reach with
		# a foot, so an aerial contest is decided by who gets up to it.
		var skill: float = SimAerial.duel_skill(p) if aerial else (p.attrs.dribbling if holder else p.attrs.tackling)
		var w: float = 0.35 + skill * 1.1 + p.attrs.strength * 0.45
		w *= lerpf(0.7, 1.15, p.attrs.aggression) if not holder else 1.0
		# A shielded ball is the shielder's to lose. His body is between the man
		# and the ball -- `SimDecision._play_hold` set the flag and priced the
		# same fact into the option -- so the contest is not two men over a loose
		# ball, it is one man holding another off, and strength is what decides
		# how well.
		if holder and p.shielding and not aerial:
			var challenger := ctx.nearest_challenger(p)
			var made: float = shielded(p, challenger) if challenger != null else 0.0
			w *= lerpf(1.0, lerpf(1.05, 1.5, p.attrs.strength), made)
		w *= p.fatigue_factor()
		# Arriving at pace helps you win the ball and helps you foul.
		var closing := _closing_speed(p, ball)
		w *= 1.0 + closing * CLOSING_SPEED_WEIGHT
		# Being nearer the ball helps.
		w *= clampf(1.35 - p.dist_to(ball.pos) / SimAerial.contact_range(ball.pos.y) * 0.5, 0.5, 1.35)
		# And challenging the man rather than the ball is harder, worst from behind.
		w *= _challenge_win[i]
		_weights[i] = maxf(w, 0.01)

	var winner_index: int = ctx.rng.weighted_index(_weights)
	if winner_index < 0:
		winner_index = 0
	var winner := _contenders[winner_index]

	var loser: SimPlayer = null
	var loser_index := -1
	var worst := -1.0
	for i in n:
		if i == winner_index:
			continue
		var c := _closing_speed(_contenders[i], ball)
		if c > worst:
			worst = c
			loser = _contenders[i]
			loser_index = i

	# Losing a challenge takes a moment to recover from. Without this the two
	# players stand over the ball poking it at each other every third of a
	# second and the match turns into pinball.
	if loser != null:
		loser.touch_cooldown = maxf(loser.touch_cooldown, ctx.rng.range_float(0.55, 1.1))
		loser.recovery_ticks = maxi(loser.recovery_ticks, int(ctx.rng.range_float(0.1, 0.35) * SimConsts.TICK_HZ))
	# Logged so challenges can be counted and judged, not merely believed in.
	var had_challenger := false
	for i in n:
		if _challenge_win[i] < 1.0:
			had_challenger = true
			break
	ctx.log_event(SimTelemetry.Ev.DUEL, {
		"winner": winner.id,
		"team": winner.team,
		"loser": loser.id if loser != null else -1,
		"pos": ball.ground_pos(),
		"challenge": had_challenger,
		"challenger_won": _challenge_win[winner_index] < 1.0,
	})

	# Foul roll. The player who lost the contest is the one who is likely to
	# have caught the other, and speed makes it worse.
	if loser != null and loser.team != winner.team:
		var closing: float = maxf(_closing_speed(loser, ball), 0.0)
		var p_foul := FOUL_BASE + closing * FOUL_PER_CLOSING_SPEED
		p_foul *= lerpf(0.55, 1.6, loser.attrs.aggression)
		p_foul *= lerpf(1.35, 0.65, loser.attrs.tackling)
		p_foul *= lerpf(1.0, 1.25, 1.0 - loser.fatigue_factor())
		# A challenge that came in on the man, and especially one that came from
		# behind him, is far likelier to be a foul. This is where the cynical
		# foul that stops a break comes from — nobody authored it.
		p_foul *= _challenge_foul[loser_index]
		# Drawing the foul is the carrier's half of the same roll. A nimble man
		# who keeps the ball rides the contact and makes the challenge late; a
		# shielded ball makes it come through his body. Fouls happen *for* a
		# player now, not only to him -- docs/THE_FOOTBALL.md, "Drawing a foul".
		if winner.id == ball.last_touch_player:
			p_foul *= lerpf(0.9, 1.3, winner.attrs.dribbling * 0.5 + winner.attrs.agility * 0.5)
			if winner.shielding:
				p_foul *= lerpf(1.0, 1.35, shielded(winner, loser))
			# Inviting it, which is the deliberate half of the same act
			# (`docs/THE_FOOTBALL.md` 32). Everything above is contact that
			# *happens* to a carrier; a footballer also puts his body across a
			# committed challenger on purpose, and in the one place where winning
			# a free kick is worth more than keeping the ball.
			#
			# So it is not a general eagerness knob: it fires where the reward is
			# real -- inside shooting range of their goal, with a man already
			# committed -- and it is scaled by `composure`, because taking the
			# contact and staying up is what the attribute names. It is also the
			# only lever the engine has on a foul count running at 1.5 a team a
			# match against a target of 8-16.
			if winner.shielding and _invites_contact(ctx, winner):
				p_foul *= lerpf(1.0, lerpf(1.0, INVITE_CONTACT, winner.attrs.composure),
					shielded(winner, loser))
		if ctx.rng.chance(clampf(p_foul, 0.0, 0.6)):
			if _challenge_cynical[loser_index] > 0.0:
				cynical_fouls += 1
			SimReferee.award_foul(ctx, loser, winner, closing)
			return

	# The winner only actually plays the ball if they are free to. Otherwise
	# they have simply held the challenge off, which is a perfectly good outcome
	# and leaves the ball where it is.
	#
	# Winning a challenge on the *man* is not the same as reaching the ball. A
	# defender who has beaten the carrier from two metres behind him has knocked
	# him off it, not taken it — letting him apply an impulse from there is
	# exactly the magnetic touch that control range exists to prevent. The ball
	# is left alone and the carrier keeps the loser's recovery penalty, so it
	# runs on loose and both of them have to go and get it.
	if not winner.can_touch():
		return
	var reach := SimAerial.contact_range(ball.pos.y)
	if winner.dist_sq_to(ball.pos) > reach * reach:
		return
	_act(ctx, winner, true)


static func _closing_speed(p: SimPlayer, ball: SimBall) -> float:
	var to_ball := SimConsts.horizontal(ball.pos - p.pos)
	var d: float = to_ball.length()
	if d < 1e-3:
		return p.speed()
	return maxf(p.vel.dot(to_ball / d), 0.0)


## The winner of the contact does something with the ball.
static func _act(ctx: SimContext, player: SimPlayer, from_contest: bool) -> void:
	var ball := ctx.ball
	var was_theirs := ball.last_touch_team == player.team
	# A ball above his boot is played with his body, whoever it belonged to a
	# moment ago -- headed if it is over his shoulders, taken down off the chest
	# if it is not. The bookkeeping below is the same either way -- a regain is a
	# regain and a pass is completed whether it was taken down or nodded on -- so
	# only the act at the end of it changes.
	var aerial := SimAerial.is_aerial(ctx)
	var off_the_grass := SimAerial.above_boot(ctx)
	if not was_theirs and ball.last_touch_team >= 0:
		# Winning it back. A hard-charging challenge pokes it clear; a settled
		# interception is played properly.
		# Whether the ball can be taken cleanly or only stabbed away. Getting
		# this too strict turns every turnover into a scramble and the match
		# into pinball.
		var closing := _closing_speed(player, ball)
		var ceiling: float = lerpf(11.0, 22.0, player.attrs.first_touch)
		# Height is judged against the head rather than the boot: a ball won back
		# at chest height is taken down off the chest, and calling that a failed
		# control stabbed away every interception of a bouncing ball in the match.
		var can_control := ball.vel.length() < ceiling and closing < 6.0 \
			and ctx.pressure_on(player) < 1.6 and ball.pos.y < SimAerial.HEADER_FROM
		# Stamped whether or not the ball can be controlled: a poke that wins it
		# back leaves him in the same crowded pocket a clean take does, and the
		# priority for the next couple of seconds is the same either way.
		player.regain_tick = ctx.tick_index
		# And the man it was taken off is beaten, which is a fact the chase
		# assignment needs. Without it he is still the body nearest the ball, so
		# he is picked as the presser, wins it straight back off the man who has
		# just turned away from him, and the two of them trade it in one square
		# metre until somebody hooks it clear.
		var beaten := ball.last_touch_player
		if beaten >= 0 and beaten < ctx.players.size() and ctx.players[beaten].team != player.team:
			ctx.players[beaten].dispossessed_tick = ctx.tick_index
		ctx.log_event(SimTelemetry.Ev.RECOVERY, {
			"p": player.id,
			"team": player.team,
			"pos": ball.ground_pos(),
			"clean": can_control,
		})
		_resolve_pass_outcome(ctx, player, false)
		if not can_control and not aerial:
			# What the touch is called is decided by *why* he could not take it.
			# The ball beating him -- struck harder than his first touch can
			# handle -- is a block, which is a man getting in the way of a strike.
			# Everything else here is him beating everyone else to a loose ball
			# and hooking it away at a stretch, which is not. Called a block, a
			# defender jogging onto a ball nobody hit at him was counted as one by
			# every instrument that counts blocks -- `race` read "block" where the
			# football was "he got there first" (`docs/THE_FOOTBALL.md` 45).
			var kind := SimTelemetry.Touch.TACKLE
			if not from_contest:
				kind = SimTelemetry.Touch.BLOCK if ball.vel.length() >= ceiling \
					else SimTelemetry.Touch.POKE
			SimTouch.poke(ctx, player, kind)
			return
	elif was_theirs and ball.last_touch_player != player.id:
		# A teammate has picked it up. That completes the pass whether or not
		# this was the player it was aimed at.
		_resolve_pass_outcome(ctx, player, true)
	if off_the_grass:
		SimAerial.play(ctx, player)
		return
	SimDecision.choose_and_execute(ctx, player)


## Closes out the pass the ball was carrying, so pass completion is measured
## against what the passer actually intended.
static func _resolve_pass_outcome(ctx: SimContext, receiver: SimPlayer, completed: bool) -> void:
	var ball := ctx.ball
	if not SimTelemetry.is_pass_kind(ball.last_touch_kind):
		return
	var passer_id := ball.last_touch_player
	if passer_id < 0 or passer_id >= ctx.players.size():
		return
	var passer := ctx.players[passer_id]
	var success := completed and receiver.team == passer.team
	if success:
		passer.passes_completed += 1
	# And back to the model that priced it, which is the only place its claim can
	# be set beside the ball rather than beside an average. A tally and nothing
	# else; nothing in `sim/` reads it back.
	SimDecision.note_pass_outcome(passer_id, ball.last_touch_kind, success)
	ctx.log_event(SimTelemetry.Ev.PASS_OUTCOME, {
		"p": passer_id,
		"team": passer.team,
		"kind": ball.last_touch_kind,
		"receiver": receiver.id,
		"ok": success,
	})
	ball.intended_target = -1
	ball.last_touch_kind = -1
