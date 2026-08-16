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


static func resolve_contacts(ctx: SimContext) -> void:
	_contenders.clear()
	_challenge_win.clear()
	_challenge_foul.clear()
	var ball := ctx.ball
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
		if overhead and SimAerial.lets_it_drop(ctx, p):
			continue
		_contenders.append(p)
		_challenge_win.append(1.0)
		_challenge_foul.append(1.0)

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
		if not ctx.rng.chance(commit):
			continue
		# 0 is directly behind the carrier, 1 is square in front of him.
		var frontness: float = 0.5 * (clampf((to / d).dot(heading), -1.0, 1.0) + 1.0)
		_contenders.append(p)
		_challenge_win.append(lerpf(CHALLENGE_WEIGHT_BEHIND, CHALLENGE_WEIGHT_FRONT, frontness))
		_challenge_foul.append(lerpf(CHALLENGE_FOUL_BEHIND, CHALLENGE_FOUL_FRONT, frontness))


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
			w *= lerpf(1.05, 1.5, p.attrs.strength)
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
				p_foul *= 1.35
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
				p_foul *= lerpf(1.0, INVITE_CONTACT, winner.attrs.composure)
		if ctx.rng.chance(clampf(p_foul, 0.0, 0.6)):
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
			SimTouch.poke(ctx, player, SimTelemetry.Touch.TACKLE if from_contest else SimTelemetry.Touch.BLOCK)
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
