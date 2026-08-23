class_name SimAerial
extends RefCounted
## The ball above the grass: who can play it, and what heading it is worth
## (PLAN.md §3.3, `docs/THE_FOOTBALL.md` "In the air").
##
## Nothing here is a new kind of contact. A high ball is resolved by the same
## `SimDuel` contest as a low one, with different weights, and the winner plays
## `SimTouch.header` instead of choosing from `SimDecision`'s candidate list.
## That is the whole shape of the layer, and it is deliberate: a header is a
## reflex and not a deliberation. A man does not price six options while the ball
## is dropping on him -- he heads it at goal if there is a goal to head it at,
## clears it if it is dangerous, and finds a shirt if it is neither.
##
## The gap this fills was the largest single hole in the engine.
## `SimTouch.header` was written and nothing called it; heading and jumping were
## generated, priced into squad quality and read by nothing in a match; and a
## cross was met on the floor or not at all, so every ball in the air ended as a
## bounce nobody contested.

## What a header was for, carried on the touch so the log can tell four quite
## different acts apart. `docs/DIAGNOSTICS.md` reads them back.
enum { CLEAR, AT_GOAL, TO_A_MAN, DOWN_FOR_HIMSELF }

const INTENT_NAMES := ["cleared", "at goal", "to a man", "down for himself"]

## Where the body stops and the head begins.
##
## Above the shoulders, and measured off the drawn figure: the head sits at about
## 1.7 m, so a ball at 1.75 is one he has to get his forehead to. Below it he has
## a chest, a thigh and a shoulder, and `SimTouch.chest` is what he does with
## them.
##
## It was 1.45 — chest height — and every ball above that was headed, which is
## how a match ended up with a header in it every time the ball left the grass. A
## ball dropping onto a man's chest is not a header in football and it should not
## be one here. The band between this and `CHEST_FROM` is the commonest ball in
## the air, and it is now the commonest thing done with one: taken down.
const HEADER_FROM := 1.75

## Where a foot stops. Above this the ball is played with the body -- taken down
## off the chest, or headed if it is higher still -- and below it the ordinary
## decision has it, because it is a ball on the floor.
const CHEST_FROM := SimConsts.FOOT_REACH_HEIGHT
## How much grass a chest-down needs in front of him. Shorter than a hold: the
## ball drops about a metre away and he is standing over it when it lands, so the
## only thing this rules out is taking one down into a defender or over a line.
const CHEST_AHEAD := 1.2

## How far a man can get to a ball in the air, horizontally.
##
## Wider than `CONTROL_RANGE`, which is the reach of a boot from a standing
## body. Meeting a ball at head height is a leap into it: he comes off one foot,
## his head arrives ahead of his centre, and the contact happens further from
## where he was standing than any touch on the floor.
const AERIAL_RANGE := 1.4

## How near the goal a man will head one at it, in metres.
const HEADER_SHOT_RANGE := 18.0
## What a header is worth against the same chance struck with a foot, from a
## player who cannot head a ball to one who can. `SimDecision.expected_goals` is
## calibrated on shots, and a header is a worse way of hitting the target than a
## shot is -- less pace, less placement, and no second look.
const HEADER_XG_WORST := 0.25
const HEADER_XG_BEST := 0.75
## Below this there is no attempt worth making and he plays it as a ball rather
## than as a chance. Lower than the shot floor in `SimDecision._add_shot`,
## because a header at goal costs nothing and keeps the ball in a dangerous
## place even when it misses.
const HEADER_SHOT_FLOOR := 0.015

## How far a headed ball can be aimed at a teammate. A neck and a set of
## shoulders is fifteen metres of pass at the outside, and that is a good one.
const HEADER_REACH := 16.0
## Nobody gets a head on a ball that is on top of him.
const HEADER_MIN := 4.0

## How much grass the direction is tested for, which is not how far the ball
## goes -- `SimTouch.header` has no solver, so nothing here names a distance and
## this is a room test like the chest-down's `CHEST_AHEAD`. Measured off the
## trace, the ball lands one to two metres away and is still moving; what this
## rules out is nodding it down into a man or over a line.
const KNOCK_AHEAD := 4.0
## How much of his neck goes into it -- see `SimTouch.header`'s `power_scale`.
## What is left of a man's neck when he is not heading at goal.
##
## `SimTouch.header`'s band was raised for the one header the owner watched --
## the attempt on goal, which was leaving the forehead too slowly to beat a
## goalkeeper (2026-08-23). Nothing else about heading was wrong, and the ball a
## defender puts into the stand and the ball nodded to a teammate both hold where
## they were measured: 0.72 is the old band over the new one. Left at 1.0 the
## clearing header carried a mean of **29 m** against `tests/test_distances`'s
## football band of 4 to 26.
const NOT_AT_GOAL_POWER := 0.72
## Down from 0.45 when the header's own band went up: the cushion is a fraction
## of his neck, so it moves whenever the neck does, and what 42 measured -- the
## ball landing one to two metres away and still moving -- is the thing to hold.
const KNOCK_POWER := 0.32
## And down, which is what makes it drop in front of him rather than fly.
const KNOCK_ANGLE := -0.25

## Pressure at which a man in his own half stops looking for a shirt and heads it
## away. `CHALLENGE_SIGHT` is 5.5 m, so this is somebody genuinely on him.
const CLEAR_PRESSURE := 0.8

# --- Letting it drop --------------------------------------------------------
#
# The behaviour that decides how much of a match is played in the air, and the
# one the engine was missing. Everything above head height was headed, so a ball
# floating down to an unmarked centre-half in acres of space was nodded twenty
# metres to nobody -- and it happened every time the ball left the grass, which is
# most of a match. A footballer heads a ball when he has to. Given a free ball
# dropping on him and nobody near, he watches it down and takes it on his chest,
# because the ball is then his and not a coin toss.
#
# So heading is what is left when he cannot wait: a man on him, his own box, a
# chance at goal, or somebody else about to get there first.

## Pressure at which he stops watching it down and attacks it. Well below
## `CLEAR_PRESSURE`: this is anybody in the neighbourhood at all, not a man on
## his back, because waiting under a dropping ball is the one thing you cannot do
## with company.
const DROP_PRESSURE := 0.45
## How near an opponent can be to the ball before it is a contest rather than a
## free ball. Wider than the reach either of them has, because the man arriving
## is still running and this is judged a second before the contact.
const DROP_CONTEST_RANGE := 4.5
## The longest he will stand under it, and how far off him it may land. A stride
## and a half: he can shuffle under a ball, he cannot follow one downfield.
const DROP_SECONDS := 1.1
const DROP_RANGE := 2.2


## True while the ball is one that has to be headed. Asked of the ball, not of a
## player: the ball is either over his head or it is not.
static func is_aerial(ctx: SimContext) -> bool:
	return ctx.ball.pos.y > HEADER_FROM


## True while the ball is off the grass far enough that a foot is not the thing
## that plays it. Everything above this line comes through `play`.
static func above_boot(ctx: SimContext) -> bool:
	return ctx.ball.pos.y > CHEST_FROM


## How far from a player the ball can be and still be contested this tick.
static func contact_range(ball_y: float) -> float:
	return AERIAL_RANGE if ball_y > HEADER_FROM else SimConsts.CONTROL_RANGE


## Whether this man lets the ball come down to him instead of heading it.
##
## Asked by `SimDuel` before he is a contender at all, and that is deliberate:
## declining a header has to happen before the bookkeeping, or the log records a
## recovery and a completed pass for a touch that never happened.
##
## Read the conditions as the four reasons a footballer does not wait. Somebody
## is on him. He is in front of their goal, where the header *is* the chance.
## He is in his own box, where waiting is how goals are conceded. Or somebody
## else is close enough to get there first, and a ball you let drop with a man
## arriving is a ball you have given away.
static func lets_it_drop(ctx: SimContext, player: SimPlayer) -> bool:
	var ball := ctx.ball
	# Still going up, or going past him: it is not a ball that is coming to him.
	if ball.vel.y > 0.0:
		return false
	if ctx.pressure_on(player) > DROP_PRESSURE:
		return false
	if player.dist_to(ctx.pitch.target_goal(player.team)) <= HEADER_SHOT_RANGE:
		return false
	if _in_danger(ctx, player):
		return false
	var opponent := SimConsts.other_team(player.team)
	for pid in ctx.team_players[opponent]:
		var p := ctx.players[pid]
		if not p.on_pitch:
			continue
		if p.dist_to(ball.pos) <= DROP_CONTEST_RANGE:
			return false
	# And it has to actually come down where he is standing, soon. The shared
	# forecast already knows: the first sample below head height within a stride
	# of him is the moment he would take it on his chest.
	var traj := ctx.trajectory_now()
	var i := traj.first_reachable_index(player.pos, DROP_RANGE, HEADER_FROM)
	return i >= 0 and traj.time_of_index(i) <= DROP_SECONDS


## What decides a ball in the air, in place of dribbling and tackling.
##
## Nobody is carrying a ball over his own head, so the contest is not the
## holder's to defend: both men are arriving at it, and what settles it is who
## gets up to it. Strength is counted by `SimDuel` on top of this, as it is for a
## contest on the floor, and it belongs in both.
static func duel_skill(p: SimPlayer) -> float:
	return p.attrs.heading * 0.55 + p.attrs.jumping * 0.45


## The chance a ball at chest height has to be worth before a man strikes it as
## it comes rather than taking it down.
##
## Twice the floor `SimDecision._add_shot` puts under a shot on the floor, and
## that gap is the whole of the rule. Hitting a dropping ball first time is the
## hardest thing on this list and a footballer only does it when the chance is
## actually there; anywhere else he kills it and shoots off the deck a moment
## later, which is the same chance taken properly.
const VOLLEY_XG_FLOOR := 0.05


## The winner of a ball off the grass plays it with his body: with his head if it
## is over his shoulders, off his chest if it is not.
static func play(ctx: SimContext, player: SimPlayer) -> void:
	if not is_aerial(ctx):
		_play_off_the_body(ctx, player)
		return
	var goal := ctx.pitch.target_goal(player.team)
	if player.dist_to(goal) <= HEADER_SHOT_RANGE:
		var aim := _goal_aim(ctx, player, goal)
		var quality := SimDecision.expected_goals(ctx, player, ctx.ball.pos, aim) \
			* lerpf(HEADER_XG_WORST, HEADER_XG_BEST, player.attrs.heading)
		if quality >= HEADER_SHOT_FLOOR:
			_note(ctx, player, "header at goal, xG %.2f" % quality)
			_head_at_goal(ctx, player, aim, quality)
			return
	if _in_danger(ctx, player):
		_note(ctx, player, "header clear")
		head_clear(ctx, player)
		return
	var mate := _header_target(ctx, player)
	if mate == null:
		_note(ctx, player, "nodded down for himself")
		_head_down(ctx, player)
		return
	_note(ctx, player, "header to #%d" % mate.shirt)
	_head_to(ctx, player, mate)


## A ball above the boot and below the head: chest, thigh or shoulder.
##
## Three things a footballer does with one, in the order he considers them.
##
## He hits it, if there is a chance there. That is the volley and the side-foot
## finish from a cross, and it is the only reason this path ever goes back to the
## decision layer -- with the ball off the grass, everything else `SimDecision`
## can offer is a pass or a carry played as though the ball were at his feet,
## which is the magnetic touch this whole module exists to remove.
##
## He hacks it away, if it is in a place where a mistake is a goal. `clearance`
## rather than `head_clear`: at chest height it is a boot through it, not a
## forehead.
##
## Otherwise he takes it down. That is the common case by a distance, and it is
## the one the engine did not have.
static func _play_off_the_body(ctx: SimContext, player: SimPlayer) -> void:
	var goal := ctx.pitch.target_goal(player.team)
	if player.dist_to(goal) <= HEADER_SHOT_RANGE:
		var chance := SimDecision.expected_goals(ctx, player, ctx.ball.pos, goal)
		if chance >= VOLLEY_XG_FLOOR:
			_note(ctx, player, "on the volley, xG %.2f" % chance)
			SimDecision.choose_and_execute(ctx, player)
			return
	if _in_danger(ctx, player):
		_note(ctx, player, "hacked clear")
		SimTouch.clearance(ctx, player)
		return
	var dir := SimDecision.safe_direction(ctx, player, CHEST_AHEAD)
	_note(ctx, player, "taken down on the chest")
	SimTouch.chest(ctx, player, dir)


## `./run.sh replay` reads these. A header does not go through the candidate list,
## so without them the one act in the match that skips `SimDecision` is also the
## one the replay cannot explain.
static func _note(ctx: SimContext, player: SimPlayer, label: String) -> void:
	if SimDebug.enabled:
		SimDebug.capture_choice(ctx, player, label, PackedStringArray())


## Whether this is a ball to get rid of rather than a ball to use: in his own
## penalty area, or in his own half with somebody on him. A defender who tries to
## find a shirt from inside his own six-yard box is the goal nobody can explain.
static func _in_danger(ctx: SimContext, player: SimPlayer) -> bool:
	if ctx.pitch.in_own_penalty_area(player.team, player.pos):
		return true
	var own_half := player.pos.x * ctx.pitch.attack_dir(player.team) < 0.0
	return own_half and ctx.pressure_on(player) > CLEAR_PRESSURE


## Where in the goal to head it. Down and across is the header that goes in, and
## it is the one a centre-forward is taught: the keeper's feet are the hardest
## place for him to get to from a set position.
static func _goal_aim(ctx: SimContext, player: SimPlayer, goal: Vector3) -> Vector3:
	var keeper := ctx.teams[SimConsts.other_team(player.team)].keeper()
	var half := ctx.pitch.goal_half_width - 0.6
	var side: float = 1.0 if ctx.rng.chance(0.5) else -1.0
	if keeper != null:
		# Away from wherever he is standing, which for a cross is usually the near
		# post -- so the ball goes back across him.
		side = -signf(keeper.pos.z) if absf(keeper.pos.z) > 0.3 else side
	return Vector3(goal.x, ctx.rng.range_float(0.2, 1.1), side * half * ctx.rng.range_float(0.4, 0.95))


static func _head_at_goal(ctx: SimContext, player: SimPlayer, aim: Vector3, quality: float) -> void:
	var line := SimConsts.horizontal(aim - ctx.ball.pos)
	var distance: float = maxf(line.length(), 1.0)
	# The angle he heads it at, from the geometry rather than from a solver: the
	# ball is above his eyes and the goal is below them, so a header at goal is
	# a downward one, which is why it is the one that beats a keeper.
	var up: float = clampf(atan2(aim.y - ctx.ball.pos.y, distance), -0.5, 0.35)
	SimTouch.header(ctx, player, line, up, AT_GOAL, aim, quality)


## Heading it away: high, long, and toward the nearest touchline. The same shape
## as `SimTouch.clearance`, which this is the airborne half of.
static func head_clear(ctx: SimContext, player: SimPlayer) -> void:
	var away := SimConsts.horizontal(ctx.pitch.target_goal(player.team) - player.pos)
	if away.length_squared() < 1e-6:
		away = Vector3(ctx.pitch.attack_dir(player.team), 0.0, 0.0)
	away = away.normalized()
	var side: float = signf(player.pos.z) if absf(player.pos.z) > 2.0 else (1.0 if ctx.rng.chance(0.5) else -1.0)
	var dir := (away + Vector3(0.0, 0.0, side * 0.45)).normalized()
	SimTouch.header(ctx, player, dir, ctx.rng.range_float(0.45, 0.7), CLEAR,
		Vector3.INF, 0.0, NOT_AT_GOAL_POWER)


## Nodding it down for himself, which is what a man with nobody to find does.
##
## The act the module did not have, and its absence was a giveaway by
## construction. `head_clear` is a *defender's* header -- it aims at the far
## goal and wide, which is the right ball from your own six-yard box and the
## wrong one from anywhere else -- and it was the fallback for every man who won
## a header with no teammate inside `HEADER_REACH`. Played by a striker thirty
## metres from the opposition goal it is the ball hoofed toward the corner flag
## that nobody of ours is running to.
##
## Measured, that is the whole of `aerial`: 25 trials, 25 headers won, **25
## losses**, every one of them `cleared` and every one of them landing eight to
## twenty-five metres away with an opponent nearest to it
## (`docs/THE_FOOTBALL.md` 42).
##
## `SimDecision.safe_direction` is the same function the chest-down asks, and
## the same question: not where the goal is, but where the ball is still his.
## The pace is `KNOCK_POWER` of his neck because the act is a cushion -- taking
## the pace off a dropping ball is the whole skill in it, and at full power the
## direction does not matter, it is a clearance either way.
static func _head_down(ctx: SimContext, player: SimPlayer) -> void:
	var dir := SimDecision.safe_direction(ctx, player, KNOCK_AHEAD)
	SimTouch.header(ctx, player, dir, KNOCK_ANGLE, DOWN_FOR_HIMSELF,
		Vector3.INF, 0.0, KNOCK_POWER)


## Who to head it to.
##
## Scored the way a throw-in is scored, and for the same reason: it is the same
## question. What is the team worth with the ball there, times the chance of it
## being theirs when it lands. A knock-down is a short pass made with the head,
## so it is priced as one rather than being given its own currency.
static func _header_target(ctx: SimContext, player: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_score := 0.0
	for pid in ctx.team_players[player.team]:
		var p := ctx.players[pid]
		if p.id == player.id or not p.on_pitch or p.is_keeper:
			continue
		var d := p.dist_to(ctx.ball.pos)
		if d < HEADER_MIN or d > HEADER_REACH:
			continue
		# Where he will be when it comes down, not where he is standing now: a
		# headed ball hangs, and everybody keeps moving under it.
		var arrival := p.pos + p.vel * 0.45
		if SimReferee.would_be_offside(ctx, player.team, arrival):
			continue
		var control := ctx.value.control_at(ctx, arrival, player.team, player.id)
		var threat := ctx.value.xt_at(player.team, arrival, ctx.pitch)
		var score := control * (threat + SimDecision.possession_value(ctx, player.team, arrival))
		if score > best_score:
			best_score = score
			best = p
	return best


static func _head_to(ctx: SimContext, player: SimPlayer, mate: SimPlayer) -> void:
	var arrival := mate.pos + mate.vel * 0.45
	var line := SimConsts.horizontal(arrival - ctx.ball.pos)
	var distance := line.length()
	# Cushioned into his feet from close range, looped over the man in front of
	# him from further out. There is no solver here -- see `SimTouch.header` --
	# so this is the angle and the distance is whatever his neck buys.
	var up: float = clampf(0.1 + distance * 0.022, 0.1, 0.5)
	SimTouch.header(ctx, player, line, up, TO_A_MAN, Vector3.INF, 0.0, NOT_AT_GOAL_POWER)
