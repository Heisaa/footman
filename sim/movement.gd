class_name SimMovement
extends RefCounted
## Off-ball positioning, pressing and defensive assignment (PLAN.md §4.3).
##
## A player's target position is a sum of contributions: the formation's home
## position, a response vector as the ball moves off centre, a phase-of-play
## offset, a role behaviour vector, gradient ascent on value for attackers and
## an assignment vector for defenders.
##
## The primary failure mode to watch for is ball-swarming. The guard against it
## lives here and nowhere else: only a small, explicitly chosen set of players
## per team may target the ball. Everyone else holds shape.

## How far the shape slides with the ball, longitudinally and laterally.
const BALL_PULL_X := 0.36
const BALL_PULL_Z := 0.30

## What the front line drops back by when the ball goes behind it. The one
## direction the pull is not symmetric in, and the difference between a team that
## stretches and a team that follows the ball about.
##
## Applied flat, as it was at 0.36 both ways, all ten outfielders slide back
## twelve metres when the ball goes twelve metres back: the side is a blob of
## constant length centred on wherever the ball is, and a man in his own third
## has nobody thirty metres up the pitch to find. Measured, that is what it looked
## like -- 65% of touches in the middle third, 29% of passes backwards, and an
## off-ball layer probing six metres around a station that had already dropped.
##
## Only the drop is cut. A front line pushes up with play as hard as anyone --
## that is how a team gets into the final third at all, and slowing it there costs
## exactly what it sounds like: cut both ways at 0.12, final-third touches fell
## from 19% to 16% and shots halved, because the striker no longer advanced when
## the ball did. What a front line does *not* do is trail back to the halfway line
## every time a centre-half plays it square. It holds against the opponent's last
## man and waits, which is what makes the side long when the ball is deep and is
## the whole point of the change.
const BALL_PULL_X_HOLD := 0.25

## The lateral pull, eased while this side builds in its own half. The failed
## experiments -- support as an angle problem -- pulled the
## shape *toward* the ball and halved the attack; the owner's direction is the
## reverse — in build-up the far side holds its width, so the switch of play
## has somewhere to go and the middle does not collapse onto the carrier.
## Defending, and anywhere past halfway, the full pull stands. Dialed 0.16 to
## 0.10 at the owner's direction after watching: still too much grouping.
const BALL_PULL_Z_BUILD := 0.10


## How hard this player's station slides sideways with the ball.
##
## Two eased conditions where there were two switched ones. `phase` is how much
## his side is the side in possession (`SimContext.shape_phase`). It used to be
## `possession_team == p.team and ball_x < 0.0`, a pair of booleans, and with the
## ball wide each was worth about seven metres of station: one jumped at every
## turnover and the other every time play crossed the halfway line.
##
## **The fade is short on purpose.** The first cut shared `_build_up_width`'s
## depth ramp, which reaches full strength only in the defensive third — and
## since four fifths of the football happens in the middle third, that quietly
## put the possessing side back near `BALL_PULL_Z` almost everywhere and undid
## the owner's 0.16-to-0.10 dial. Measured: the side closed 0.8 m further onto
## its own ball on all three seeds. `BALL_PULL_Z_BUILD` is meant to hold for the
## whole of the own half, so the fade is a band at the halfway line and nothing
## more.
const BUILD_UP_FADE := 12.0


static func lateral_pull(_ctx: SimContext, _p: SimPlayer, ball_x: float, phase: float = 0.0) -> float:
	var behind: float = clampf(-ball_x / BUILD_UP_FADE, 0.0, 1.0)
	return lerpf(BALL_PULL_Z, BALL_PULL_Z_BUILD, phase * behind)


## How far the station slides for a ball at `ball_x`, in the canonical attacking
## frame. Piecewise and continuous at the halfway line, where the two slopes
## meet: a striker pushes on once the ball is over it and holds his height while
## the side builds behind it.
##
## `building` is how much this player's own side has the ball
## (`SimContext.shape_phase`, 0 to 1): with it, the CM holds his height against a
## deep ball the same way the front line always has. Trailing all the way back
## onto the carrier is the midfield collapse the owner watched (DECISIONS.md,
## "Width in build-up") — the pivot still comes, because a DM dropping to offer
## for his centre-halves is build-up, but the man between the lines stays between
## the lines. Defending, everyone tracks at the full rate as before.
##
## It was a bool, and for a midfielder with the ball on his own goal line the two
## rates are six metres of station apart, arriving in one tick at the turnover.
static func ball_pull_shift(role: int, ball_x: float, building: float = 0.0) -> float:
	if ball_x >= 0.0:
		return BALL_PULL_X * ball_x
	if SimRole.is_attacking(role):
		return BALL_PULL_X_HOLD * ball_x
	if role == SimRole.CM:
		return lerpf(BALL_PULL_X, BALL_PULL_X_HOLD, building) * ball_x
	return BALL_PULL_X * ball_x


## How much wider the back line stands with the ball at its own feet in its own
## half, as a multiplier on the width the formation gives it.
##
## A back four in possession splits. The centre-halves take the width of the
## penalty area between them and the full-backs go and stand on the touchline,
## because a pitch is only as big as a side makes it and building out is the one
## moment nobody is close enough to punish the space between them. The engine had
## a single width for the whole match -- `SimTactics.width_scale`, a plan-level
## number that cannot know where the ball is -- so a side playing out of its own
## box stood exactly as narrow as it does defending a cross. Every angle out of
## the back then ran through the same crowded middle, and the ball that was on
## was the square one.
##
## Applied to the formation's own z, so the proportions of the line survive and
## only its width changes: a full-back at 23 m goes to 31, a centre-half at 8 m
## to 11. It is not a tactical switch — the plan's own `width_scale` multiplies
## on top, so a narrow side still splits less than a wide one.
const BUILD_UP_WIDTH := 1.35
## The midfield's share of the same split. Smaller, because a midfield spread
## to the touchlines is not a shape, but a midfield that keeps its formation
## width while the ball is worked out of the back is what stops the middle
## collapsing onto the carrier — the owner watched the collapse and the long
## ball that was the only way out of it (DECISIONS.md, "Width in build-up").
## Dialed 1.18 to 1.30 at the owner's direction after watching.
const BUILD_UP_WIDTH_MID := 1.30
## How deep the ball has to be for the whole of it, as a fraction of the half
## length. Full inside their own third, gone by the halfway line: splitting the
## back line is a thing a side does while it still has grass behind it, and a
## back four that stays split at halfway is one about to be played through.
const BUILD_UP_DEPTH := 0.55

## Speed a player uses to hold shape, as a fraction of their maximum, and the
## gap past which he is not holding shape but getting back into it.
##
## 0.25 of top speed is about 1.9 m/s, and the obvious reading of `diagnose`'s
## `Holding the shape` -- every errand leaving its man eight to nine metres
## behind his own target -- is that this is too slow. It was tried: a continuous
## ramp from `SHAPE_SPEED` at the station to `RECOVER_SPEED` at twelve metres.
## The gap did not move (8.5 m against 8.5) and the mean speed of an outfielder
## went from 2.49 m/s to 3.34, against football's two. It was not the pace. The
## point he was running at was moving at 4 to 7 m/s -- see `SimContext.shape_ball`
## -- and no pace closes a gap to something moving faster than you.
const SHAPE_SPEED := 0.25
const RECOVER_SPEED := 0.72
const SHAPE_SPEED_GAP := 12.0
## How far off their station a player is willing to be before bothering to move.
const SHAPE_DEADBAND := 3.9
## A probe has to be this much better than standing still before an attacker
## bothers to move. Without hysteresis they chase a flickering optimum and end
## the match having run twice as far as a footballer.
const PROBE_MARGIN := 1.25
## Gradient-ascent probe distance for attackers looking for space.
const PROBE_DISTANCE := 4.5
## The probe set, in the canonical attacking frame.
const PROBES := [
	Vector3(PROBE_DISTANCE, 0.0, 0.0),
	Vector3(-PROBE_DISTANCE * 0.6, 0.0, 0.0),
	Vector3(0.0, 0.0, PROBE_DISTANCE),
	Vector3(0.0, 0.0, -PROBE_DISTANCE),
]

## How many players per team get the full interception model. Beyond the
## nearest handful, nobody is winning a race to the ball.
const CHASE_CANDIDATES := 5
## How far ahead the cheap prefilter is willing to project a player's own
## momentum when measuring him against the ball.
const PROXY_LOOKAHEAD := 1.0

## How long a player counts as beaten after the ball is taken off him, and how
## much that adds to his ranked time-to-the-ball. Roughly the time it takes to
## turn and get going again, and enough of a penalty to put a teammate a few
## metres further away ahead of him without ruling him out.
const BEATEN_TICKS := 45
const BEATEN_PENALTY := 0.9

## Scratch, reused every tick so the movement path allocates nothing.
static var _rank_ids := PackedInt32Array()
static var _rank_times := PackedFloat32Array()
static var _near_ids := PackedInt32Array()
static var _near_scores := PackedFloat32Array()


## Chase assignment refresh interval, in ticks. Fast enough to react, slow
## enough not to cost the whole tick budget.
const CHASE_TICKS := 3


## Chase role per player id: 0 none, 1 primary, 2 support. A flat array rather
## than a dictionary of lists, because this is read for every player every tick.
enum { CHASE_NONE, CHASE_PRIMARY, CHASE_SUPPORT }

static var _chase_role := PackedInt32Array()

## Raw time-to-the-ball for every player the assignment actually weighed up,
## INF for everyone else. Kept because it is already computed: knowing that the
## man opposite can be there in the same second is what turns a chase into a
## race, and recomputing it for that would be walking the forecast twice.
static var _chase_time := PackedFloat32Array()

## Whether this player is currently in a race, latched. See `_contest_pace`.
static var _contest_latch := PackedInt32Array()

## Which side of the ball each support presser chose to close, latched for the
## length of his press and zero when he is not pressing. See
## `_support_press_point`, which is the only reader and the only writer.
static var _press_side := PackedFloat32Array()


## Read-only views of the assignment, for the debug overlay. The anti-swarm guard
## lives in `_assign_chasers` and nowhere else; these two say what it decided and
## are read by nothing in `sim/`.
static func chase_role_of(id: int) -> int:
	return _chase_role[id] if id >= 0 and id < _chase_role.size() else CHASE_NONE


static func chase_time_of(id: int) -> float:
	return _chase_time[id] if id >= 0 and id < _chase_time.size() else INF


## The arms of `_recompute_target`, in the order the ladder tries them. Each is
## stamped on `SimPlayer.errand` by the branch that takes it, so this list and
## the code cannot drift: an arm that stops firing stops appearing.
##
## `STATION` is the shape and nothing on top of it, and it is the one that has
## to be common. Everything else is a reason a man is somewhere his formation
## did not put him, and the diagnostics count them because "they all clump on
## the ball" is a claim about which of these arms is winning.
enum Errand {
	STATION,   ## the formation's own point, slid with play
	CHASE,     ## designated to go to the ball
	PRESS,     ## the second man, supporting the press
	PATTERN,   ## a named pattern is running him somewhere
	SHOULDER,  ## a forward playing on the last defender
	OFFER,     ## SimOffBall relocated him: show, space, behind, box, decoy, second
	SUPPORT,   ## came short to give the carrier a angle
	DRIFT,     ## a few metres off his station, into a pocket
	ASCENT,    ## the value field's local gradient moved him
	MARK,      ## goal-side of an opponent
	BLOCK,     ## thrown at a shot (`SimDuel.commit_blocks`)
	COVER,     ## filling the space a beaten teammate lost (`_pick_cover`)
	JOCKEY,    ## arrived at the carrier: standing off him, side-on, showing him wide
	ESCORT,    ## walking a dying ball over the line, body between it and the man
}

const ERRAND_NAMES := [
	"station", "chase", "press", "pattern", "shoulder", "offer", "support",
	"drift", "ascent", "mark", "block", "cover", "jockey", "escort",
]


## Clears the chase assignment, for the same reason `SimOffBall.reset` exists: it
## is static, it outlives the context that made it, and the first ticks of a new
## match read it before the first assignment has run.
static func reset() -> void:
	_chase_role = PackedInt32Array()
	_chase_time = PackedFloat32Array()
	_press_side = PackedFloat32Array()
	_contest_latch = PackedInt32Array()
	_cover = PackedInt32Array([-1, -1])
	covers_taken = 0
	escorts = 0
	_trap_tick = PackedInt32Array([-100000, -100000])
	traps_sprung = 0
	trap_triggers = 0
	link_asked = 0
	link_no_gap = 0
	link_no_ahead = 0
	link_applied = 0
	link_moved = 0.0
	link_stood = 0.0


static func update(ctx: SimContext) -> void:
	var stride := ctx.config.decision_stride()
	# The first tick after `reset`, before anybody has decided anything. The
	# stagger below is a refresh cadence and must never delay a man's *first*
	# decision: `SimPlayer.move_target` starts at the world origin with no speed
	# cap, so until he has decided once he is steering at the centre spot flat
	# out. At a kick-off that is a few harmless centimetres with everyone
	# standing still. In a situation that starts men at speed it is decisive --
	# measured on `race`, a foot race set dead level, the man whose stagger came
	# up later spent three ticks braking toward the middle of the pitch, lost
	# half a metre a second, and never got it back: the quicker of the two won
	# 10 races out of 18, and 18 out of 18 once he decided on the first tick.
	var first := _chase_role.size() != ctx.players.size()
	if first or ctx.tick_index % (CHASE_TICKS * stride) == 0:
		_assign_chasers(ctx)
	# Who is offering himself for a pass, and in which of the several ways there
	# are of doing it. Runs on its own cadence and only writes intents; the
	# targets it produces are read below like any other contribution.
	SimOffBall.update(ctx)
	for p in ctx.players:
		if not p.on_pitch or p.is_keeper:
			continue
		if first or ctx.tick_index >= p.next_decision_tick:
			p.next_decision_tick = ctx.tick_index + SimConsts.OFF_BALL_DECISION_TICKS * stride
			_recompute_target(ctx, p)
		p.steer_to(p.move_target, p.move_speed_cap, p.move_deadband)
		_orient_receiver(ctx, p)


## Receive on the half-turn: the hips are chosen before
## the ball arrives, not discovered when it does.
##
## A man waiting for a pass with his body slaved to his last run stands square
## to the ball he came to meet, and every act after his first touch then pays
## `facing_penalty` and `strike_scale` for it. A footballer opens his body
## while the ball travels: half-way between the line it is coming on and the
## way he wants to play, which is what lets the first touch go forward and the
## next ball be on. Written as a look, and `SimPlayer.locomote` decides whether
## the run allows it: a man sprinting onto the ball keeps his hips on the run,
## a man walking onto it or waiting for it opens up. Only for the man the pass
## is for, and not with a man tight on him -- opening up with a challenger on
## your back is how the ball is nicked off it, so the tight receiver keeps his
## body closed and shields instead.
static func _orient_receiver(ctx: SimContext, p: SimPlayer) -> void:
	if ctx.ball.intended_target != p.id or ctx.ball.last_touch_team != p.team:
		return
	# The look is for receiving, and ends at the touch: `intended_target`
	# outlives it, and a carrier still held on his receiving look was capped
	# to a shuffle -- standing went from 20% to 31% of a match.
	if ctx.ball.last_touch_player == p.id:
		return
	var to_ball := SimConsts.horizontal(ctx.ball.pos - p.pos)
	if ctx.challenge_on(p) > 0.5:
		# Closed: facing the ball, marker behind, the ball on the far foot.
		if to_ball.length() > 0.5:
			p.look_target = p.pos + to_ball.normalized() * 4.0
		return
	var to_goal := SimConsts.horizontal(ctx.pitch.target_goal(p.team) - p.pos)
	if to_ball.length() < 0.5 or to_goal.length() < 0.5:
		return
	var open := to_ball.normalized() + to_goal.normalized()
	if open.length() < 0.2:
		return
	p.look_target = p.pos + open.normalized() * 4.0


# --- Chase assignment -------------------------------------------------------


## Decides, per team, who goes to the ball, and writes it into `_chase_role`.
##
## This is the anti-swarm mechanism. The number of players allowed to leave
## shape comes from the pressing intensity, so a low block sends one and a high
## press sends three -- and nobody else moves toward the ball at all.
static func _assign_chasers(ctx: SimContext) -> void:
	var n := ctx.players.size()
	if _chase_role.size() != n:
		_chase_role.resize(n)
		_chase_time.resize(n)
		_press_side.resize(n)
		_contest_latch.resize(n)
		for i in n:
			_contest_latch[i] = 0
	for i in n:
		_chase_role[i] = CHASE_NONE
		_chase_time[i] = INF

	var ball_ground := ctx.ball.ground_pos()
	var carrier := ctx.possession_player
	var receiver := ctx.ball.intended_target
	# Rank against where the ball is going rather than where it is.
	_gather_forecast(ctx)
	# A ball nobody has is there to be won, and who is closest to it is a
	# different question from who should leave his station to press a man.
	var loose := _ball_is_loose(ctx)
	# A ball over everyone's heads is contested by more than one man a side, and
	# it is contested at the ball rather than in the lane behind it.
	var aerial := not ctx.ball.grounded and SimAerial.is_aerial(ctx)
	for team in 2:
		var tactics := ctx.tactics(team)
		var allowed := tactics.press_commitment()
		if SimPatterns.pressing_restart(ctx, team):
			allowed += 2
		if ctx.possession_team == team:
			# In possession, only the player nearest the ball goes to it.
			allowed = 1
		if aerial:
			allowed = maxi(allowed, AERIAL_CHASERS)
		# Two passes. A squared distance to where the ball is heading is enough
		# to rule out most of the team, and the real interception model -- which
		# walks the forecast for every candidate -- then runs only for the few
		# who could plausibly get there. Running it for all eleven was the single
		# most expensive thing in the engine.
		_near_ids.clear()
		_near_scores.clear()
		for pid in ctx.team_players[team]:
			var p := ctx.players[pid]
			if not p.on_pitch or p.is_keeper:
				continue
			var proxy := _proxy_distance(p)
			if pid == receiver:
				proxy *= 0.4
			_insert_near(pid, proxy)

		_rank_ids.clear()
		_rank_times.clear()
		var considered: int = mini(CHASE_CANDIDATES, _near_ids.size())
		for i in considered:
			var pid: int = _near_ids[i]
			var p := ctx.players[pid]
			var t := intercept_time(ctx, p)
			# Kept before the adjustments below, which are preferences about who
			# ought to go rather than statements about who can get there. Only
			# the physical time means anything to a race.
			_chase_time[pid] = t
			# Players who should be holding a defensive station are reluctant to
			# leave it, so the nearest body is not automatically the presser.
			#
			# Only against a man in possession. Getting in front of a ball that
			# belongs to nobody is the most valuable thing a defender does, and
			# charging him three-quarters of a second for it meant the quickest
			# man to a loose ball stood and watched a midfielder arrive from
			# further away. Measured, that was 41% of every occasion the slower
			# man was sent.
			if SimRole.is_defensive(p.role) and ctx.possession_team != team and not loose:
				t += 0.7
			# The player a pass was aimed at goes to meet it. Without this, the
			# passer is still the closest body to the ball and ends up chasing
			# his own pass while the intended receiver holds shape.
			if pid == receiver:
				t -= 1.2
			# A man who has just had it taken off him is beaten, and the nearest
			# body is the wrong way to pick a presser at that moment. He is standing
			# next to the ball by definition, so without this he always leads the
			# press, wins it straight back off the man who has just turned away from
			# him, and the turnover simply reverses: the same two players trade the
			# ball in one square metre and the passage of play goes nowhere. He
			# still goes if nobody else is near -- this changes who is picked, not
			# whether anyone presses.
			if ctx.tick_index - p.dispossessed_tick < BEATEN_TICKS:
				t += BEATEN_PENALTY
			_insert_ranked(pid, t)
		var limit: int = mini(allowed, _rank_ids.size())
		for i in limit:
			# The nearest player always goes. Anyone beyond the first only joins
			# if the ball is inside the plan's engagement distance -- this is
			# what stops a whole team converging on it.
			if i == 0:
				_chase_role[_rank_ids[i]] = CHASE_PRIMARY
				continue
			# A ball in the air has no lane behind it to close, so the second and
			# third men go at the ball as well. This is what makes a near post, a
			# far post and a second ball exist at all.
			if aerial:
				_chase_role[_rank_ids[i]] = CHASE_PRIMARY
				continue
			var p := ctx.players[_rank_ids[i]]
			if p.dist_to(ball_ground) <= tactics.engage_distance():
				_chase_role[_rank_ids[i]] = CHASE_SUPPORT
		# The man on the ball goes to the ball whatever the ranking said, because
		# he is chasing his own touch. Not the man who has just passed it: his
		# touch was played to somebody else, and it is that man's to go and get.
		#
		# `possession_player` is derived from the last touch and stays with the
		# passer while the ball is within three metres of him and uncontested --
		# most of the flight of a short pass, and almost none of a long one. So
		# this line used to hand the passer a second CHASE_PRIMARY in a phase
		# whose cap is one, and he set off after the ball he had just played.
		# Measured on seed 7: on passes under twelve metres the passer was a
		# designated chaser for 42% of the flight, and his side had two primary
		# chasers for 35% of it, against 12% and 11% for a pass of 12 to 25 m.
		var passed_it_on := ctx.ball.intended_target >= 0 \
			and ctx.ball.intended_target != carrier
		if carrier >= 0 and ctx.players[carrier].team == team \
				and _chase_role[carrier] == CHASE_NONE and not passed_it_on:
			_chase_role[carrier] = CHASE_PRIMARY
		if loose:
			_add_nearby_chaser(ctx, team, receiver, ball_ground)
		_pick_cover(ctx, team)
		_consider_trap(ctx, team)
	# A man who is not a support presser has no side to close. Cleared here so
	# that the next press he is given picks one afresh, rather than inheriting
	# whichever side he happened to be on in some earlier phase.
	for i in n:
		if _chase_role[i] != CHASE_SUPPORT:
			_press_side[i] = 0.0


## How many men a side sends at a ball in the air.
##
## In possession the cap is one, and one is right for a ball at somebody's feet.
## It is also the whole reason a cross used to arrive at nobody: the man it was
## aimed at went for it, and the near post, the far post and the second ball were
## covered by players holding a shape. A ball hung up in the air is the moment a
## side stops keeping the ball and attacks a space, and the side defending it
## does the same -- so both get the floor, whatever the plan says about pressing.
##
## Two. Two men going up for a cross is a contest; four is the swarm the guard
## exists to prevent, and the box would empty out behind them.
const AERIAL_CHASERS := 2

## A loose ball this close in time, and this close in metres, is a man's to go
## and get whatever the press cap says.
const NEARBY_SECONDS := 1.1
const NEARBY_RANGE := 9.0
## And this is the fastest it may be moving. Past it, the ball is not rolling
## past him, it is flying past him, and the man it goes by is not the man who
## wins it — he is the man who gets pulled out of shape by every driven pass in
## the match.
const NEARBY_SPEED := 8.0
## How many men it may add per side. One. And he takes the chase over rather
## than joining it: two teammates converging on the same loose ball run into
## each other, and the collision is how it gets lost. Opponents settle a close
## race by running (`_contest_pace`); teammates settle it by the call, and the
## call goes to the man already going unless the other is clearly quicker.
const NEARBY_EXTRA := 1


## The one exception to the press cap: a ball nobody owns, dying within a stride
## or two of a man who can reach it.
##
## The cap in `_assign_chasers` is right about pressing -- a side does not send
## five men at a carrier -- and wrong about this, because going to a loose ball
## at your feet is not a decision to leave a station. Measured against the
## complaint that players ignore balls rolling slowly beside them, the reason was
## always the same: the man was the second-ranked chaser and `allowed` was one,
## which in possession it always is.
##
## All four conditions carry weight. Loose, or a marker abandons the press to
## stand over a ball the carrier has under his foot; slow and near, or a driven
## pass drags whoever it passes out of shape; in time, or this is just a bigger
## cap by another name. And not for the side a pass is already travelling to,
## whose man is on his way to meet it -- a second body converging on the same
## ball is the swarm, not an interception.
##
## The same reasoning applies inside the team, and that is the call. A teammate
## is only added over the head of the primary already going if he is clearly
## quicker -- quicker by more than the dead-heat window -- and then the primary
## stands down to support instead of arriving second into the back of him. Two
## teammates never race each other to a ball: one of them owns it the moment
## the assignment is made, which is what the shout does on a real pitch.
static func _add_nearby_chaser(ctx: SimContext, team: int, receiver: int, ball_ground: Vector3) -> void:
	if ctx.ball.ground_speed() > NEARBY_SPEED:
		return
	if receiver >= 0 and receiver < ctx.players.size() and ctx.players[receiver].team == team:
		return
	# The man already called for it, and how quick he is. Raw time: the call is
	# about who gets there, not who ought to.
	var going := -1
	var going_t := INF
	for pid in _rank_ids:
		if _chase_role[pid] == CHASE_PRIMARY and _chase_time[pid] < going_t:
			going = pid
			going_t = _chase_time[pid]
	var added := 0
	for pid in _rank_ids:
		if added >= NEARBY_EXTRA:
			return
		if _chase_role[pid] != CHASE_NONE:
			continue
		if _chase_time[pid] > NEARBY_SECONDS:
			continue
		if ctx.players[pid].dist_to(ball_ground) > NEARBY_RANGE:
			continue
		if _chase_time[pid] + CONTEST_DEAD_HEAT >= going_t:
			continue
		if going >= 0:
			_chase_role[going] = CHASE_SUPPORT
		_chase_role[pid] = CHASE_PRIMARY
		added += 1


## Points along the forecast the prefilter measures players against, with the
## time each is reached. Gathered once per assignment and shared by both teams.
static var _forecast_pts := PackedVector3Array()
static var _forecast_ts := PackedFloat32Array()


## Collects the reachable part of the ball's forecast.
##
## The prefilter used to measure everybody against a single point -- where the
## ball would be in six tenths of a second -- and that is not where a chase is
## decided. A cleared ball or a long pass is caught up with at its landing spot,
## twenty or thirty metres from that instant, so the men actually in the race
## were ranked as though they were nowhere near it and the five who got the real
## interception model were the wrong five. The nearest point of the whole
## forecast is the question the real model answers, so it is the question the
## prefilter should approximate.
static func _gather_forecast(ctx: SimContext) -> void:
	_forecast_pts.clear()
	_forecast_ts.clear()
	var traj := ctx.trajectory_now()
	for i in range(0, traj.count, PROXY_STEP):
		var sample := traj.points[i]
		if sample.y > SimConsts.HEAD_REACH_HEIGHT:
			continue
		_forecast_pts.append(sample)
		_forecast_ts.append(traj.time_of_index(i))
	if _forecast_pts.is_empty() and traj.count > 0:
		# Every sample is above head height: the ball is in the air throughout
		# the forecast, and the place to be is wherever it comes down.
		_forecast_pts.append(traj.points[traj.count - 1])
		_forecast_ts.append(traj.time_of_index(traj.count - 1))


## Squared distance from where this player can be to the nearest point of the
## forecast -- his own momentum counted, because a committed runner judged as
## though he were standing still is exactly who this filter used to drop.
static func _proxy_distance(p: SimPlayer) -> float:
	var best := INF
	for i in _forecast_pts.size():
		var lead: float = minf(_forecast_ts[i], PROXY_LOOKAHEAD)
		var dx := p.pos.x + p.vel.x * lead - _forecast_pts[i].x
		var dz := p.pos.z + p.vel.z * lead - _forecast_pts[i].z
		best = minf(best, dx * dx + dz * dz)
	return best


## Stride through the forecast when gathering the prefilter's points. Coarse:
## consecutive samples are a sixtieth of a second apart and the answer wanted is
## "roughly how near does this ball ever come to him".
const PROXY_STEP := 6


## Sample times along the forecast at which interception is tested. Coarse on
## purpose: the point is to rank players, not to solve the meeting exactly.
const INTERCEPT_SAMPLES := [2, 8, 17, 29, 44, 62]


## Earliest time at which `p` could meet the ball, given where the ball is
## actually going. Ranking on the ball's *current* position instead is the
## classic way to end up with nobody running onto a pass.
static func intercept_time(ctx: SimContext, p: SimPlayer) -> float:
	var traj := ctx.trajectory_now()
	for i in INTERCEPT_SAMPLES:
		if i >= traj.count:
			break
		var sample := traj.points[i]
		if sample.y > SimConsts.HEAD_REACH_HEIGHT:
			continue
		var t := traj.time_of_index(i)
		if SimValueField.time_to_arrive(p, sample, p.reaction) <= t:
			return t
	var last := traj.points[traj.count - 1]
	return SimValueField.time_to_arrive(p, last, p.reaction)


static func _insert_near(pid: int, score: float) -> void:
	var i := 0
	while i < _near_scores.size() and _near_scores[i] <= score:
		i += 1
	_near_ids.insert(i, pid)
	_near_scores.insert(i, score)


static func _insert_ranked(pid: int, t: float) -> void:
	var i := 0
	while i < _rank_times.size() and _rank_times[i] <= t:
		i += 1
	_rank_ids.insert(i, pid)
	_rank_times.insert(i, t)


# --- Target selection -------------------------------------------------------


## The pace of a chaser who has not yet reacted to the strike: legs that have
## had no news do not sprint. See the gate below.
const UNSEEN_PACE := 0.35

## How far past the intercept the man a ball in behind was struck to carries his
## target: he meets the ball through it, still moving, instead of arriving on
## it, stopping, and being turned back toward the passer by `_orient_receiver`.
const RUN_ON_THROUGH := 3.0
## How far ahead of him, along the run, the intercept has to be before the ball
## is one he meets through rather than a ball to his feet.
const RUN_ON_AHEAD := 2.0


## Defenders read the body. With the ball at a carrier's feet, the chaser
## closes half-way between the ball and where the carrier's hips say the next
## touch goes -- `READ_AHEAD`, the next touch's length at a walk -- inside
## `READ_RANGE`. It is what a feint sells to.
const READ_AHEAD := 1.5
const READ_RANGE := 4.5


static func _recompute_target(ctx: SimContext, p: SimPlayer) -> void:
	# An arm that wants the body held sets a look; every other arm faces the run.
	p.look_target = Vector3.INF
	p.escorting = false
	var role: int = _chase_role[p.id]
	var is_primary := role == CHASE_PRIMARY
	var is_support := role == CHASE_SUPPORT

	# A body thrown at a shot is committed (`SimPlayer.commit_move`); nothing
	# here steers it. Named for the instruments.
	if ctx.tick_index < p.block_until:
		p.errand = Errand.BLOCK
		return

	if is_primary:
		p.errand = Errand.CHASE
		var point := _intercept_point(ctx, p)
		# The struck ball makes its man the designated chaser, which converts a
		# runner in behind into a man running *at* the ball: he arrives at the
		# intercept, stops, and `_orient_receiver` turns him back toward the
		# passer -- watched and named by the owner. Carry his target past the
		# intercept along his own committed run instead.
		if ctx.ball.intended_target == p.id and ctx.ball.last_touch_team == p.team \
				and SimOffBall.is_running_in_behind(ctx, p):
			var dest := SimOffBall.destination_for(ctx, p)
			# Only for a ball actually rolled past him -- the intercept ahead
			# of him along his own run. The first cut ran him through *every*
			# ball while committed, a pass to feet included, and he overran
			# those on purpose: the scenario read 90% lost with two touches a
			# trial, every trial ending on the first ball.
			if not is_inf(dest.x):
				var run_dir := SimConsts.horizontal(dest - p.pos)
				var to_point := SimConsts.horizontal(point - p.pos)
				if run_dir.length() > 1.0 \
						and to_point.dot(run_dir.normalized()) > RUN_ON_AHEAD:
					var on := SimConsts.horizontal(dest - point)
					if on.length() > 1.0:
						point += on / on.length() * RUN_ON_THROUGH
		# Their man on the ball: read his body.
		var holder_id := ctx.ball.last_touch_player
		if holder_id >= 0 and holder_id != p.id and ctx.players[holder_id].team != p.team:
			var holder: SimPlayer = ctx.players[holder_id]
			var at := ctx.ball.ground_pos()
			if holder.on_pitch and holder.dist_to(at) < SimConsts.CONTROL_RANGE \
					and p.dist_to(at) < READ_RANGE:
				point = point.lerp(at + holder.heading_dir() * READ_AHEAD, 0.5)
			# And in front of our own goal, he is closed from goal-side: the
			# body between the ball and the net, which is what a block is
			# thrown from and what a defender in the box is for. Open play
			# stays as it was -- a chaser who cuts in front of every carry is
			# the wrong act (`_recovery_point`); this is the one place the
			# football says otherwise.
			# Not from behind him: a chaser in the slipstream aimed at a point
			# in front of the carrier is the tailgate INVARIANTS names, and it
			# undid the recovery run -- `1v1-clear` read 35% to 44% goals at
			# n=160 until this line. He runs round first; the lane is for the
			# man who is level or in front.
			if holder.on_pitch and holder.dist_to(at) < SimTouch.DRIBBLE_AHEAD_MAX \
					and _recovery_weight(ctx, p) <= 0.0:
				var lane := _box_lane_weight(ctx, p.team, at)
				if lane > 0.0:
					var own_goal := ctx.pitch.own_goal(p.team)
					var to_goal := SimConsts.horizontal(own_goal - at)
					var gd := to_goal.length()
					if gd > LANE_STANDOFF + 0.5:
						point = point.lerp(at + to_goal / gd * LANE_STANDOFF, lane)
				# And having got there, he does not run through him. The
				# jockey: stand off, face him, shuffle with him, show him the
				# touchline. The challenge is still `SimDuel`'s commit roll;
				# this is what he does between rolls, which is most of
				# defending.
				var jockey := _jockey_weight(ctx, p, holder, at)
				if jockey > 0.0:
					p.errand = Errand.JOCKEY
					point = point.lerp(_jockey_point(ctx, p, holder.pos), jockey)
					p.look_target = at
		# A ball dying over the line for our restart is walked out, not played:
		# shielding's cheapest special case.
		if _escort_wanted(ctx, p):
			p.errand = Errand.ESCORT
			p.escorting = true
			point = _escort_point(ctx, p)
			p.look_target = ctx.ball.ground_pos()
			escorts += 1
		# A chaser coming from behind a man in possession runs round him rather
		# than into the back of him.
		var recovery := _recovery_weight(ctx, p)
		if recovery > 0.0:
			point = point.lerp(_recovery_point(ctx, p, point), recovery)
		p.move_target = point
		# Pace it. A player does not sprint at a ball rolling gently toward
		# them, and making every chaser sprint is worth several kilometres a
		# match of running that no footballer does. Getting round a carrier is the
		# exception: he is already at full speed and the way round is longer than
		# the way through.
		var gap_to_ball := p.dist_to(p.move_target)
		var when := maxf(intercept_time(ctx, p), 0.35)
		p.move_speed_cap = clampf(gap_to_ball / when * 1.15, p.max_speed() * 0.35, p.max_speed())
		if recovery > 0.0:
			p.move_speed_cap = lerpf(p.move_speed_cap, p.max_speed() * RECOVERY_PACE, recovery)
		# A carrier is a chaser of his own touch, and pacing him like one is why
		# he was seen to walk the ball around with a man on his back. "Fast
		# enough to arrive" is the right rule for running onto a loose ball and
		# the wrong one for running away from a challenge: it caps him at the
		# speed that just reaches his own next touch, so the man behind him has
		# only to match a jog. Being challenged is the one case where the point
		# is not to arrive but to arrive first.
		#
		# The floors below ask a man on the ball for more than the pace that just
		# reaches it, and each is about a man going somewhere: away from a
		# challenge, or down the pitch. A man who has just settled the ball is
		# going nowhere by his own decision, and floored at 60-100% of his top
		# speed he sprints straight past a ball sitting a metre in front of him.
		# The race floor between the two needs no such gate: it is only ever
		# non-zero for a ball nobody owns.
		var settling := p.settling and ctx.ball.last_touch_player == p.id
		var escaping := 0.0 if settling else _escape_pace(ctx, p)
		if escaping > 0.0:
			p.move_speed_cap = maxf(p.move_speed_cap, p.max_speed() * lerpf(0.6, 1.0, escaping))
		# And the same rule again, for the other way a chase stops being about
		# arriving: somebody else is going for the same ball. Two men racing
		# shoulder to shoulder for a loose one do not each pace themselves to
		# turn up -- it belongs to whichever of them is a stride quicker, and
		# neither of them knows which that is until they have run.
		var contest := _contest_pace(ctx, p)
		if contest > 0.0:
			p.move_speed_cap = maxf(p.move_speed_cap, p.max_speed() * contest)
		# And once more, for the man in possession with nobody in front of him.
		# He is not trying to catch his own touch, he is trying to get down the
		# pitch, and the touch he takes next is sized off the pace he is at.
		var driving := 0.0 if settling else _carry_pace(ctx, p)
		if driving > 0.0:
			p.move_speed_cap = maxf(p.move_speed_cap, p.max_speed() * driving)
		# A ball struck where he could not see it is not yet his errand: he
		# reacts, then runs. The contact rule already waits
		# (`SimDuel._ready_for`); the legs did not, so a back line turned and
		# sprinted the tick a ball was played over it from a striker at its
		# back. Same clock, one answer -- and his own side's ball is exempt in
		# the clock itself, it is their ball.
		if ctx.ball.last_touch_team != p.team \
				and SimDuel.ball_news_age(ctx, p) < p.reaction:
			p.move_speed_cap = minf(p.move_speed_cap, p.max_speed() * UNSEEN_PACE)
		# A shield is a body between the man and the ball. `_play_hold` chose
		# it; this is where it is made: the hips turned away from the
		# challenger, and the pace held under the strafe cap so they stay
		# there. `SimDuel.shielded` reads the body it actually got.
		if p.shielding and ctx.ball.last_touch_player == p.id:
			var challenger := ctx.nearest_challenger(p)
			if challenger != null:
				var away := SimConsts.horizontal(p.pos - challenger.pos)
				if away.length() > 0.1:
					p.look_target = p.pos + away.normalized() * 4.0
					p.move_speed_cap = minf(p.move_speed_cap,
						p.max_speed() * SimPlayer.STRAFE_SHARE * SimPlayer.STRAFE_RELEASE)
		# The release half of `SimOffBall.MEET_EASE`'s timing, counted here
		# because the struck ball makes its man the designated chaser: the
		# station errand -- and `point_for` with it -- stops running for him.
		if ctx.ball.intended_target == p.id:
			var meet_kind := SimOffBall.intent_of(ctx, p)
			if meet_kind == SimOffBall.SHOW or meet_kind == SimOffBall.SPACE:
				SimOffBall.meet_ease[1] += 1
		p.move_deadband = 0.25
		return
	if _cover.size() == 2 and _cover[p.team] == p.id:
		p.errand = Errand.COVER
		p.move_target = cover_point(ctx, p.team)
		p.move_speed_cap = p.max_speed() * 0.92
		p.move_deadband = 0.8
		return
	if is_support:
		p.errand = Errand.PRESS
		p.move_target = _support_press_point(ctx, p)
		p.move_speed_cap = p.max_speed() * 0.68
		p.move_deadband = 2.0
		return

	# A live pattern has this player making a specific run. It is still just a
	# target the ordinary locomotion has to reach, not a special mode.
	var scripted := SimPatterns.movement_override(ctx, p)
	if scripted != Vector3.INF:
		p.errand = Errand.PATTERN
		p.move_target = scripted
		p.move_speed_cap = p.max_speed() * 0.95
		p.move_deadband = 1.2
		p.making_run = true
		return

	var shape := shape_position(ctx, p)
	p.errand = Errand.STATION
	if ctx.possession_team == p.team:
		shape = _attacking_adjust(ctx, p, shape)
	else:
		shape = _defensive_adjust(ctx, p, shape)
	p.move_target = ctx.pitch.clamp_to_pitch(shape, 0.5)
	# Holding shape is a jog; recovering a long way out of position is not.
	var gap := p.dist_to(p.move_target)
	p.move_speed_cap = p.max_speed() * (SHAPE_SPEED * lerpf(0.85, 1.2, p.attrs.work_rate) if gap < SHAPE_SPEED_GAP else RECOVER_SPEED)
	# A line springing a trap steps up at a run, not at shape-holding pace.
	if (p.role == SimRole.CB or p.role == SimRole.FB) and trap_lift(ctx, p.team) > 0.0:
		p.move_speed_cap = maxf(p.move_speed_cap, p.max_speed() * TRAP_PACE)
	# A footballer holding a station does not sprint to be exactly on it. This
	# tolerance is what keeps a match inside 9-12 km per player. A timed run in
	# behind is the exception: it has to be made to the metre.
	if SimOffBall.intent_of(ctx, p) != SimOffBall.NONE:
		# He is not holding a station, he is making himself available, and the
		# pace and the tolerance come from which way he chose to do it: a man
		# coming to feet and a man going in behind are not the same errand.
		p.move_speed_cap = p.max_speed() * SimOffBall.pace_for(ctx, p)
		p.move_deadband = SimOffBall.deadband_for(ctx, p)
	elif not p.making_run:
		p.move_deadband = SHAPE_DEADBAND
	if p.making_run:
		# Taking the shoulder of the last defender outranks whatever else he had
		# decided to do with himself: it is the one position that has to be held
		# to the metre, and a striker drifting toward it at a drifter's pace is
		# not on it. Left the other way round, a front line that chose to move
		# into a pocket stopped playing on the last man for three seconds at a
		# time and the whole team spent the match a few metres too deep.
		p.move_deadband = minf(p.move_deadband, 2.0)
		p.move_speed_cap = maxf(p.move_speed_cap, p.max_speed() * 0.8)


## The link players (`docs/THE_FOOTBALL.md` 30). The formation's midfield
## stations sit where the formation put them, slid with play, and the pocket
## between the opponents' midfield and their back line was only ever an
## *offer* (`SimOffBall._pocket_point`, a lift on a space probe) -- taken or
## not by the softmax, and mostly not: 73% of touches in the middle third.
## This is the station itself. In possession, the link roles stand between
## their lines: the playmaker fully, the central midfielders by half, so one
## of them is always level with the ball and one is ahead of it. The pocket
## is read off where their men are, which moves at the pace of a line rather
## than a pass, and blended on the possession phase so it never teleports.
## Width is the formation's own: keep structure and width, said the owner,
## and make the midfield a link.
const LINK_AM := 1.0
const LINK_CM := 0.5
## The pocket has to be this far ahead of the shape's ball to be a link and
## not a striker, and no further than this from it to be a pass.
const LINK_AHEAD_MIN := 3.0
const LINK_AHEAD_MAX := 26.0
## And a stride onside of their line.
const LINK_ONSIDE := 2.5


static func _link_station(ctx: SimContext, p: SimPlayer, shape: Vector3) -> Vector3:
	var weight: float
	if p.role == SimRole.AM:
		weight = LINK_AM
	elif p.role == SimRole.CM:
		weight = LINK_CM
	else:
		return shape
	weight *= ctx.shape_phase_of(p.team)
	if weight <= 0.0:
		return shape
	var dir := ctx.pitch.attack_dir(p.team)
	var line: float = SimReferee.offside_line(ctx, p.team) * dir
	var mid_sum := 0.0
	var n := 0
	for oid in ctx.opponent_ids(p.team):
		var o := ctx.players[oid]
		if not o.on_pitch or o.is_keeper:
			continue
		if o.role == SimRole.DM or o.role == SimRole.CM or o.role == SimRole.AM:
			mid_sum += o.pos.x * dir
			n += 1
	if n == 0:
		return shape
	var mid_line := mid_sum / float(n)
	link_asked += 1
	if line - mid_line < SimOffBall.POCKET_GAP:
		link_no_gap += 1
		return shape
	var pocket: float = minf((line + mid_line) * 0.5, line - LINK_ONSIDE)
	var ball_x: float = ctx.shape_ball.x * dir
	var ahead := pocket - ball_x
	if ahead < LINK_AHEAD_MIN or ahead > LINK_AHEAD_MAX:
		link_no_ahead += 1
		return shape
	var x: float = lerpf(shape.x * dir, pocket, weight)
	link_moved += absf(x - shape.x * dir)
	link_stood += p.pos.x * dir - ball_x
	link_applied += 1
	return Vector3(x * dir, shape.y, shape.z)


## Tallies for `diagnose`: how often the link station was asked for by a
## link role in possession, refused for no gap between their lines, refused
## for the pocket being behind the ball or too far ahead, applied, and the
## metres it moved the station when it was.
static var link_asked := 0
static var link_no_gap := 0
static var link_no_ahead := 0
static var link_applied := 0
static var link_moved := 0.0
static var link_stood := 0.0


## Sentinel for `shape_position`: build the shape around wherever the ball
## actually is. A real ball position always has y at or above zero.
const SHAPE_BALL_LIVE := Vector3(0.0, -1.0, 0.0)


## The formation's home position, slid with play and shifted by the tactical
## plan. Expressed in world coordinates.
##
## `ball_at` overrides where the shape thinks the ball is. Only the restart code
## passes it, and only to say "build the shape around the ball we are about to
## play, not the dead one on the goal line" -- see `SimSetPiece._restart_shape`.
static func shape_position(ctx: SimContext, p: SimPlayer, ball_at: Vector3 = SHAPE_BALL_LIVE) -> Vector3:
	var team: SimTeam = ctx.teams[p.team]
	var slot: int = clampi(p.slot, 0, team.formation.size() - 1)
	var tactics := team.ensure_tactics()
	var pitch := ctx.pitch

	# Work in the canonical frame where this team attacks +X.
	var home := pitch.scale_point(team.formation.homes[slot])
	# `ctx.shape_ball`, not the live ball: the shape follows play rather than the
	# pass. A restart overrides it outright, because a side lining up for a free
	# kick is standing where that ball is going to be struck from and nowhere else.
	var ball_c := pitch.orient(p.team, ctx.shape_ball if ball_at.y < 0.0 else ball_at)

	# How much this side is the side in possession, eased over a couple of seconds
	# rather than switched in a tick. Four things below read it and they are worth
	# fifteen metres of station between them; see `SimContext.shape_phase`.
	var phase := ctx.shape_phase_of(p.team)

	# The shape slides with play rather than being pinned to the formation, and
	# the front of it does not trail back with a ball played behind it.
	var x := home.x + ball_pull_shift(p.role, ball_c.x, phase)
	var z := home.z * tactics.width_scale() * _build_up_width(ctx, p, ball_c.x, phase) \
		+ ball_c.z * lateral_pull(ctx, p, ball_c.x, phase)

	# Defensive line height. Only the back line and the pivot are anchored to
	# it; the front line hangs off the shape ahead of them.
	var line_shift := tactics.line_x(pitch) - _default_line_x(team, pitch)
	var anchor: float = 1.0 if SimRole.is_defensive(p.role) else lerpf(0.65, 0.2, float(SimRole.is_attacking(p.role)))
	x += line_shift * anchor

	# Phase of play: push up in possession, drop off out of it.
	#
	# In possession a side squeezes, and it squeezes from the back. The push is
	# largest for the line that has grass behind it to give up and smallest for
	# the man already standing on the last defender, who has nowhere to go.
	#
	# It used to be the other way round -- 1.4 for the attackers and 1.0 for
	# everyone else -- so the engine *stretched* at the moment it should have been
	# closing up. Measured off the trace, the side was 46 to 53 m from its own back
	# line to its furthest man against a real team's 30 to 40, and worst with the
	# ball in its own third: a defensive line on 19 m and the highest man on 68,
	# forty-nine metres of pitch with ten players spread over it. That is a team
	# with no bands, and it is the shape behind a carrier who has nothing on but a
	# square pass -- every option is a long way away, so every lane is long.
	#
	# Both halves are computed and crossfaded on `phase`. Branched, this was the
	# largest jump of the four -- a centre-half's push is +11 m with the ball and
	# -2.5 without it, so his station crossed thirteen metres of pitch in one
	# sixtieth of a second at every change of hands, and did it again on the way
	# back. The magnitudes are unchanged; only the arrival is.
	var squeeze: float = 0.7
	if SimRole.is_defensive(p.role):
		squeeze = 1.6
	elif not SimRole.is_attacking(p.role):
		squeeze = 1.0
	var phase_shift := lerpf(
		-lerpf(4.5, 0.5, tactics.press_intensity),
		lerpf(3.0, 9.0, tactics.tempo) * squeeze,
		phase)
	x += phase_shift

	# A defender never positions behind their own goal line.
	x = clampf(x, -pitch.half_length + 4.0, pitch.half_length - 1.0)
	return pitch.orient(p.team, Vector3(x, 0.0, z))


## The back line's extra width while this side builds out of its own half, as a
## multiplier on the formation's z. One for everybody else, and one for anybody
## at any time the ball is not his own team's and in his own half.
##
## `ball_x` is the ball in this player's canonical frame, so "his own half" is
## simply a negative number and the same expression works at either end.
static func _build_up_width(ctx: SimContext, p: SimPlayer, ball_x: float, phase: float = 0.0) -> float:
	if phase <= 0.0:
		return 1.0
	# `phase` multiplies the depth rather than gating on it. Gated, a full-back
	# standing 23 m off centre went to 31 and back in one tick at every change of
	# hands -- eight metres of station, which is the single largest of the four.
	var depth: float = clampf(-ball_x / maxf(ctx.pitch.half_length * BUILD_UP_DEPTH, 1.0), 0.0, 1.0) * phase
	if p.role == SimRole.CB or p.role == SimRole.FB:
		return lerpf(1.0, BUILD_UP_WIDTH, depth)
	if p.role == SimRole.DM or p.role == SimRole.CM or p.role == SimRole.AM:
		return lerpf(1.0, BUILD_UP_WIDTH_MID, depth)
	return 1.0


## Canonical X of the formation's own back line, used as the reference the
## tactical line height shifts away from. Constant for a match, so cached.
static var _line_x_cache := {}


static func _default_line_x(team: SimTeam, pitch: SimPitch) -> float:
	var key := team.formation.display_name + "|" + str(pitch.half_length)
	if _line_x_cache.has(key):
		return _line_x_cache[key]
	var deepest := 0.0
	var n := 0
	for i in team.formation.roles.size():
		var role := team.formation.roles[i]
		if role == SimRole.CB or role == SimRole.FB:
			deepest += pitch.scale_point(team.formation.homes[i]).x
			n += 1
	var value: float = deepest / maxf(float(n), 1.0) if n > 0 else -pitch.half_length * 0.61
	_line_x_cache[key] = value
	return value


## Where the primary presser goes: the earliest point on the shared forecast
## they can actually get to.
static func _intercept_point(ctx: SimContext, p: SimPlayer) -> Vector3:
	var traj := ctx.trajectory_now()
	for i in range(0, traj.count, 3):
		var sample := traj.points[i]
		if sample.y > SimConsts.HEAD_REACH_HEIGHT:
			continue
		var t := traj.time_of_index(i)
		if SimValueField.time_to_arrive(p, sample, 0.0) <= t + 0.12:
			return Vector3(sample.x, 0.0, sample.z)
	var last := traj.points[traj.count - 1]
	return Vector3(last.x, 0.0, last.z)


## How far behind a carrier the approach angle is worth thinking about. Beyond
## this the chaser is not in anybody's slipstream and a straight line is right.
const RECOVERY_RADIUS := 5.0
## Frontness at which a chaser is level with the carrier and stops going round:
## 0 is directly behind him, 1 is square in front. The weight fades to nothing
## here, so the target moves continuously back onto the ball rather than
## flicking between two points.
const RECOVERY_LEVEL := 0.5
## How far to the side of the ball's line the recovery run is made. Wide enough
## to come round a body instead of into it, and it closes again as he arrives,
## so the run ends on the ball rather than beside it.
const RECOVERY_OFFSET := 2.4
## Distance from the ball over which the offset closes.
const RECOVERY_CLOSE := 4.0
## The carrier has to be going somewhere for there to be a way round him.
const RECOVERY_MIN_CARRIER_SPEED := 2.0
## How close two men's arrival times have to be for the ball to be a race worth
## sprinting for, and inside what margin it is a dead heat and they both go flat
## out. In seconds.
const CONTEST_DEAD_HEAT := 0.3
const CONTEST_WINDOW := 1.1


## Pace of a recovery run, as a fraction of the chaser's maximum. A defender
## going round a man is running, not jogging in his wake -- and the line round
## is longer than the line through, so without this he never completes it: the
## measured trails go straight back to two seconds and beyond.
##
## This and RECOVERY_RADIUS are the two knobs to turn while watching a match. If
## the chaser looks half-hearted, or gives up on carries he should be getting
## across, raise them; 0.92 and 7.0 were the first values and read the same on
## the diagnostic. They were trimmed to hold a shot count up, which is not a
## reason -- see "What this is judged by" in CLAUDE.md.
const RECOVERY_PACE := 0.85


## The opponent carrying the ball, or null. "Carrying" means he touched it last
## and it is still within a dribbler's reach of him -- the same condition the
## challenge model uses, because it is the same situation seen from further out.
static func _carrier_ahead(ctx: SimContext, p: SimPlayer) -> SimPlayer:
	var holder := ctx.ball.last_touch_player
	if holder < 0 or holder >= ctx.players.size():
		return null
	var c := ctx.players[holder]
	if c.team == p.team or c.is_keeper or not c.on_pitch:
		return null
	if c.dist_to(ctx.ball.ground_pos()) > SimTouch.DRIBBLE_AHEAD_MAX:
		return null
	return c


## How much of the chaser's target is the way round the carrier rather than the
## straight line to the ball.
##
## Zero unless he is genuinely behind a running carrier. A defender who tracks a
## carrier from directly behind can never reach the ball: it is pushed two to
## four metres in front of the man, so the straight line to it runs through him,
## soft separation holds the defender a body's width off, and he settles into the
## slipstream for the length of the carry. Measured before this existed, the
## nearest defender to a running carrier was behind him 87% of the time, at 1.1 m,
## in trails averaging 3.3 seconds. `./run.sh diagnose` prints that split.
static func _recovery_weight(ctx: SimContext, p: SimPlayer) -> float:
	var carrier := _carrier_ahead(ctx, p)
	if carrier == null:
		return 0.0
	var to := SimConsts.horizontal(p.pos - carrier.pos)
	var d := to.length()
	if d > RECOVERY_RADIUS or d < 1e-3:
		return 0.0
	var heading := SimConsts.horizontal(carrier.vel)
	if heading.length() < RECOVERY_MIN_CARRIER_SPEED:
		return 0.0
	var frontness: float = 0.5 * (clampf(to.dot(heading.normalized()) / d, -1.0, 1.0) + 1.0)
	return clampf(1.0 - frontness / RECOVERY_LEVEL, 0.0, 1.0)


## The same interception point, approached from beside the carrier instead of
## through him: the ball's line, stepped sideways by enough to run past a body.
##
## Deliberately *not* a point in front of the carrier. Standing in his path is a
## stronger defensive act than getting round him -- the pressure model rates an
## opponent in front at three times one behind -- and a chaser who cuts in front
## of every carry halves the shots in a match. The offset closes with the last
## few metres, so the run finishes on the ball and he can take it or hack it
## clear like anyone else arriving.
static func _recovery_point(ctx: SimContext, p: SimPlayer, intercept: Vector3) -> Vector3:
	var carrier := _carrier_ahead(ctx, p)
	if carrier == null:
		return intercept
	var heading := SimConsts.horizontal(carrier.vel).normalized()
	var to := SimConsts.horizontal(p.pos - carrier.pos)
	var lateral := Vector3(-heading.z, 0.0, heading.x)
	# Which way round. Crossing behind a sprinting man to come up the other side
	# loses the race, so a chaser already committed to one side stays there. From
	# square behind there is nothing to lose by choosing, and the side worth
	# choosing is the inside: it shepherds the carrier toward the touchline
	# instead of following him toward goal.
	var offset := lateral.dot(to)
	var side: float = signf(offset) if absf(offset) > 0.8 else signf(-carrier.pos.z)
	if is_zero_approx(side):
		side = 1.0
	var closing: float = clampf(SimConsts.horizontal_length(intercept - p.pos) / RECOVERY_CLOSE, 0.0, 1.0)
	var point := intercept + lateral * side * RECOVERY_OFFSET * closing
	return ctx.pitch.clamp_to_pitch(Vector3(point.x, 0.0, point.z), 0.5)


## How hard the man in possession is running, 0 to 1, when he is the one being
## chased rather than the one chasing.
##
## Zero for everybody except the player who last touched the ball, so an
## ordinary chase is paced exactly as before. For him it rises with how imminent
## the challenge is, and it is the other half of the decision layer's knock past
## a man: `SimDecision` scores that touch on winning a race to the ball, and a
## carrier still capped at "fast enough to arrive" would lose every race he
## chose to start.
static func _escape_pace(ctx: SimContext, p: SimPlayer) -> float:
	if ctx.ball.last_touch_player != p.id:
		return 0.0
	return clampf(ctx.challenge_on(p) / 0.8, 0.0, 1.0)


## Half the width of the lane a carrier is running down: an opponent further off
## it than this is beside him rather than in front of him.
const CARRY_LANE := 3.5
## Clear grass down that lane before there is anything to run into: below this he
## is paced by his own touch like anybody else.
const CARRY_CLEAR := 9.0
## Clear grass down that lane, in metres, at which he is running as hard as he
## can. A third of the pitch in front of nobody is a man who has gone.
const CARRY_OPEN := 18.0
## What a carrier with grass in front of him is asked for, from the moment the
## lane opens at all to the moment it is wide open.
const CARRY_PACE_MIN := 0.62
const CARRY_PACE_MAX := 1.0


## How hard the man in possession runs at the space in front of him, 0 to 1.
##
## The third instance of the rule that "fast enough to arrive" is the wrong pace
## whenever arriving is not the point, after `_escape_pace` and `_contest_pace`.
## Finding it three times says the rule is what wanted the exception, not any of
## the cases.
##
## Here it is a loop rather than a single mistake, and the loop is what made a
## carrier look like he was walking the ball about. He is chase-primary for his
## own touch, so he is paced at the speed that just reaches it; the decision
## layer sizes his next touch off the pace he is going; a jogger therefore takes
## a jogger's touch, which keeps him jogging. Nothing in it is wrong locally and
## between them they pin a man with the whole half in front of him to about three
## metres a second. Breaking it needs the pace to come from somewhere that is not
## the ball, and the honest somewhere is the grass: a footballer with twenty
## metres of it in front of him runs, and *then* pushes the ball into it.
##
## Zero for everybody but the man on the ball, and zero for him the moment there
## is a body in his lane -- at which point he is back to being paced by his own
## touch, which for a man with somebody in front of him is the right rule again.
static func _carry_pace(ctx: SimContext, p: SimPlayer) -> float:
	if ctx.possession_team != p.team or ctx.ball.last_touch_player != p.id:
		return 0.0
	if p.dist_to(ctx.ball.ground_pos()) > SimTouch.DRIBBLE_AHEAD_MAX:
		return 0.0  # Not carrying it -- he has knocked it away or lost it.
	var heading := SimConsts.horizontal(p.vel)
	if heading.length() < 1.0:
		return 0.0  # Standing over it. There is no run to pace.
	return carry_pace_for(ctx, p, heading.normalized())


## The share of his top speed the grass down `heading` asks of a carrier, 0 to
## 1. The rule above with the direction as an argument, so the decision layer
## can look down each probe as far as this will run him: a station that
## priced a four-metre carry for a man stood in front of fifteen metres of
## open lane was the decision layer not knowing what the movement layer was
## about to do with it (`SimDecision._add_dribbles`).
static func carry_pace_for(ctx: SimContext, p: SimPlayer, heading: Vector3) -> float:
	var open := ctx.pitch.run_room(p.pos, heading, 1.0)
	for j in ctx.opponent_ids(p.team):
		var o: SimPlayer = ctx.players[j]
		if not o.on_pitch:
			continue
		# The goalkeeper coming out is not a body in his lane, he is the man to
		# beat, and the answer to him is to get there first.
		#
		# Counted like an outfielder he withdrew the pace floor of the one man
		# who most needs it. Measured on `1v1-clear`: a striker through on goal
		# with the ball a metre and a half in front of him was capped at 8.05
		# and then walked down to **5.06** as the keeper advanced -- decelerating
		# while the ball ran on at 6.3, so the gap grew and the keeper collected
		# it. `_contest_pace` cannot cover this: it is guarded to a ball nobody
		# has, and this one is still his.
		if o.is_keeper:
			continue
		var to := SimConsts.horizontal(o.pos - p.pos)
		var along := to.dot(heading)
		if along <= 0.0 or along >= open:
			continue
		if absf(to.x * -heading.z + to.z * heading.x) > CARRY_LANE:
			continue
		open = along
	# It has to be space he can actually do something with. Ramping from the width
	# of the lane meant a man with an opponent four metres in front of him still
	# got 62% of his top speed for it, which is not running into space, it is
	# running into somebody -- and it was reported as exactly that.
	if open <= CARRY_CLEAR:
		return 0.0
	var t: float = clampf((open - CARRY_CLEAR) / maxf(CARRY_OPEN - CARRY_CLEAR, 0.1), 0.0, 1.0)
	return lerpf(CARRY_PACE_MIN, CARRY_PACE_MAX, t)


## True when the ball belongs to nobody: in flight, running away from the last
## man to touch it, or bouncing clear. The same test `_carrier_ahead` uses,
## asked of the ball rather than of a particular opponent.
static func _ball_is_loose(ctx: SimContext) -> bool:
	var holder := ctx.ball.last_touch_player
	if holder < 0 or holder >= ctx.players.size():
		return true
	return ctx.players[holder].dist_to(ctx.ball.ground_pos()) > SimTouch.DRIBBLE_AHEAD_MAX


## How hard this chaser is racing somebody else for the same ball, 0 to 1.
##
## The companion to `_escape_pace`, and the same argument. "Fast enough to
## arrive" is the right rule for a loose ball nobody is contesting, and it is
## what keeps a match inside the distance a footballer actually covers. It is
## the wrong rule the moment an opponent is going for the same ball, because
## then arriving is not the point: arriving first is, and a man who paces
## himself to turn up loses every fifty-fifty to a man who does not.
##
## Measured before this existed, a chaser running shoulder to shoulder with a
## rival was being asked for 56% of his top speed.
##
## Zero unless the race is close. A chaser who is a second clear has won it and
## does not need to sprint; one who is a second down has lost it and cannot get
## there by trying harder. Both of those are also true of footballers, and both
## are cheaper than a squad that sprints at everything.
static func _contest_pace(ctx: SimContext, p: SimPlayer) -> float:
	# Only for a ball nobody has. A man closing on a carrier is not racing him
	# for it, he is pressing him, and the carrier's own answer to that is
	# `_escape_pace`. Without this guard the two of them are chase-primary for
	# their sides at almost every moment of the match, every press reads as a
	# dead heat, and both men arrive flat out: measured, it doubled the
	# turnovers -- 53 interceptions to 104 on one seed -- and left 56% of
	# regains lost again inside two and a half seconds. Pinball, not football.
	if not _ball_is_loose(ctx):
		_contest_latch[p.id] = 0
		return 0.0
	var mine := _chase_time[p.id]
	if is_inf(mine):
		_contest_latch[p.id] = 0
		return 0.0
	var theirs := INF
	for oid in ctx.opponent_ids(p.team):
		if _chase_role[oid] != CHASE_NONE:
			theirs = minf(theirs, _chase_time[oid])
	if is_inf(theirs):
		_contest_latch[p.id] = 0
		return 0.0
	var margin := absf(theirs - mine)
	# Latched, because this reads its own output.
	#
	# `_chase_time` is an intercept with a decelerating ball, so it is very
	# sensitive to the chaser's own speed -- and his own speed is what this
	# function sets. Recomputed clean every refresh the loop closes: the taper
	# eases him off, easing off lengthens his intercept, the margin moves, and
	# the pace comes back. Measured on `race`, a two-man foot race from a
	# standing start with both men level, the cap on each of them went 8.0, 5.0,
	# 8.0, 6.0, 8.0 over two seconds -- both men braking for a third of a sprint
	# they were four metres down on, and the race settled by whose brakes landed
	# worst rather than by who was quicker (`docs/THE_FOOTBALL.md` 44).
	#
	# `docs/INVARIANTS.md` already names the shape and the answer: latch a
	# discrete choice for the length of the act. Entering a race is the choice;
	# it holds until the race is *decided*, which is a margin outside the whole
	# window rather than outside the dead heat. Everything else is the taper as
	# it was.
	if _contest_latch[p.id] != 0:
		if margin <= CONTEST_WINDOW:
			return 1.0
		_contest_latch[p.id] = 0
	if margin <= CONTEST_DEAD_HEAT:
		_contest_latch[p.id] = 1
		return 1.0
	return clampf(1.0 - (margin - CONTEST_DEAD_HEAT) / (CONTEST_WINDOW - CONTEST_DEAD_HEAT), 0.0, 1.0)


## Support pressers close the passing lane behind the ball rather than piling in
## on it. Convergence on the ball is exactly the failure mode to avoid.
## The offside trap as an act. The line's standing height is a station
## (`_hold_the_line`, `offside_trap * 5` metres when the ball is far); this is
## the step -- the back four going up together on a trigger, for a moment, to
## leave the runner behind them. The triggers are football's: the ball played
## back or square, or the carrier closed down with his back to us, either of
## them with a runner near the line to catch. Rolled per refresh at
## `TRAP_PER_SECOND * offside_trap`, latched for `TRAP_HOLD` and eased in and
## out so the station does not teleport (INVARIANTS: a boolean is a station
## that teleports), with `TRAP_COOLDOWN` before the next. What catches the
## runner is that he believes a line that is `SEEN_MEMORY` stale.
const TRAP_STEP := 4.0
const TRAP_RISE := 0.25
const TRAP_HOLD := 1.2
const TRAP_FALL := 0.6
const TRAP_COOLDOWN := 4.0
const TRAP_PER_SECOND := 0.8
const TRAP_PACE := 0.85
## The line has to be this far off its own goal line to step up, the ball this
## far ahead of the line, and a runner within this of the line.
const TRAP_MIN_DEPTH := 18.0
const TRAP_BALL_AHEAD := 8.0
const TRAP_BAIT := 5.0

static var _trap_tick := PackedInt32Array([-100000, -100000])
## Traps sprung, whole match, and the refreshes on which the trigger held.
## Read by `diagnose`.
static var traps_sprung := 0
static var trap_triggers := 0


## Metres the line is lifted by a live trap, 0 when none is.
static func trap_lift(ctx: SimContext, team: int) -> float:
	if _trap_tick.size() != 2:
		return 0.0
	var age: float = float(ctx.tick_index - _trap_tick[team]) * SimConsts.DT
	if age < 0.0 or age > TRAP_RISE + TRAP_HOLD + TRAP_FALL:
		return 0.0
	if age < TRAP_RISE:
		return TRAP_STEP * age / TRAP_RISE
	if age < TRAP_RISE + TRAP_HOLD:
		return TRAP_STEP
	return TRAP_STEP * (1.0 - (age - TRAP_RISE - TRAP_HOLD) / TRAP_FALL)


static func _consider_trap(ctx: SimContext, team: int) -> void:
	if _trap_tick.size() != 2:
		_trap_tick = PackedInt32Array([-100000, -100000])
	# Off the last touch, not `possession_player`: that is -1 for most of a
	# pass's flight, and the pass played back is the trigger.
	var ball := ctx.ball
	if ball.last_touch_team != SimConsts.other_team(team) or ball.last_touch_player < 0 \
			or ball.last_touch_player >= ctx.players.size() or not ctx.offside_on:
		return
	if float(ctx.tick_index - _trap_tick[team]) * SimConsts.DT < TRAP_COOLDOWN:
		return
	var tactics := ctx.tactics(team)
	if tactics.offside_trap <= 0.05:
		return
	var dir := ctx.pitch.attack_dir(team)
	var own_x := ctx.pitch.own_goal(team).x
	var line_x := SimReferee.offside_line(ctx, SimConsts.other_team(team))
	var line_depth: float = (line_x - own_x) * dir
	if line_depth < TRAP_MIN_DEPTH:
		return
	var at := ball.ground_pos()
	if (at.x - line_x) * dir < TRAP_BALL_AHEAD:
		return
	# The trigger.
	var carrier := ctx.players[ball.last_touch_player]
	var played_back: bool = ball.vel.x * dir > 1.5 and carrier.dist_to(at) > SimConsts.CONTROL_RANGE
	var pressed_back: bool = carrier.dist_to(at) <= SimConsts.CONTROL_RANGE \
		and ctx.pressure_on(carrier) > 1.0 and carrier.heading_dir().x * dir > 0.3
	if not (played_back or pressed_back):
		return
	# And somebody to catch.
	var bait := false
	for oid in ctx.opponent_ids(team):
		var o := ctx.players[oid]
		if o.on_pitch and not o.is_keeper and o.id != carrier.id \
				and absf(o.pos.x - line_x) <= TRAP_BAIT:
			bait = true
			break
	if not bait:
		return
	trap_triggers += 1
	if not ctx.rng.chance(TRAP_PER_SECOND * tactics.offside_trap * float(CHASE_TICKS) * SimConsts.DT):
		return
	_trap_tick[team] = ctx.tick_index
	traps_sprung += 1
	ctx.log_event(SimTelemetry.Ev.TRAP, {"team": team, "line": line_x})


## The escort. A ball the forecast has going out of play, last touched by
## them -- so the restart is ours -- is not played, it is walked out: the
## nearest of ours puts his body between it and whoever wants it and lets it
## run. Any touch of his would be a clearance from the byline or a throw
## given away. Only while it is still going out inside `ESCORT_HORIZON`, and
## only if he can be there before it is; a ball that stops short of the line
## is a loose ball again and he plays it like anyone.
const ESCORT_HORIZON := 2.5
const ESCORT_GAP := 0.7
## How many times an escort was taken up, whole match. Read by `diagnose`.
static var escorts := 0


static func _escort_wanted(ctx: SimContext, p: SimPlayer) -> bool:
	var ball := ctx.ball
	if ball.last_touch_team < 0 or ball.last_touch_team == p.team:
		return false
	if not _ball_is_loose(ctx) or ball.pos.y > 1.0:
		return false
	var traj := ctx.trajectory_now()
	if traj.out_index < 0:
		return false
	var out_t := traj.time_of_index(traj.out_index)
	if out_t > ESCORT_HORIZON:
		return false
	# Going into our own goal is not a ball to escort.
	var out := traj.points[traj.out_index]
	var own_goal := ctx.pitch.own_goal(p.team)
	if absf(out.x - own_goal.x) < 1.0 and absf(out.z) <= ctx.pitch.goal_half_width + 1.0:
		return false
	# He has to be there before it is.
	return intercept_time(ctx, p) <= out_t


static func _escort_point(ctx: SimContext, p: SimPlayer) -> Vector3:
	var at := ctx.ball.ground_pos()
	var threat := ctx.nearest_to(at, SimConsts.other_team(p.team))
	var toward: Vector3
	if threat != null and threat.dist_to(at) < 12.0:
		toward = SimConsts.horizontal(threat.pos - at)
	else:
		toward = SimConsts.horizontal(-at)
	if toward.length() < 0.1:
		toward = SimConsts.horizontal(ctx.pitch.target_goal(p.team) - at)
	return ctx.pitch.clamp_to_pitch(at + toward.normalized() * ESCORT_GAP, 0.2)


## The jockey. A defender who has reached the carrier used to keep running at
## the ball -- the intercept point, read half a touch ahead of the hips -- and
## soft separation held him off; so he either went for it or, at his station,
## did nothing. A footballer who has arrived stands off the ball a stride and a
## half, faces the man, shuffles with him side-on, and stands a little inside
## the line to goal so the easy way is the touchline. The body frame makes it:
## the look holds the hips on the carrier and `SimPlayer.STRAFE_SHARE` caps
## the shuffle, and when the carrier goes past at pace the target outruns the
## cap, the body slaves to the run and he turns and chases.
##
## `JOCKEY_STANDOFF` sits outside `CONTROL_RANGE` and inside
## `SimDuel.CHALLENGE_RADIUS`, so the commit roll still fires from there.
const JOCKEY_STANDOFF := 1.9
## Fully a jockey inside `JOCKEY_NEAR` of the ball, nothing beyond
## `JOCKEY_FAR`: outside that he is still arriving.
const JOCKEY_NEAR := 3.2
const JOCKEY_FAR := 5.0
## He has to be goal-side of the carrier to jockey him: the dot of his offset
## with the line to his own goal, ramped between these.
const JOCKEY_SIDE_LOW := 0.2
const JOCKEY_SIDE_HIGH := 0.6
## How far inside the line to goal he stands, as the tangent of the angle,
## and how far from the centre line the ball has to be before there is a
## wide side to show.
const SHOW_WIDE := 0.35
const SHOW_WIDE_FROM := 4.0


static func _jockey_weight(ctx: SimContext, p: SimPlayer, holder: SimPlayer, at: Vector3) -> float:
	if not holder.on_pitch or holder.dist_to(at) > SimTouch.DRIBBLE_AHEAD_MAX:
		return 0.0
	var d := p.dist_to(at)
	var near: float = clampf((JOCKEY_FAR - d) / (JOCKEY_FAR - JOCKEY_NEAR), 0.0, 1.0)
	if near <= 0.0:
		return 0.0
	var to_goal := SimConsts.horizontal(ctx.pitch.own_goal(p.team) - at)
	var gd := to_goal.length()
	if gd < 1.0:
		return 0.0
	var offset := SimConsts.horizontal(p.pos - at)
	var od: float = maxf(offset.length(), 1e-3)
	var side: float = (offset / od).dot(to_goal / gd)
	var goal_side: float = clampf((side - JOCKEY_SIDE_LOW) / (JOCKEY_SIDE_HIGH - JOCKEY_SIDE_LOW), 0.0, 1.0)
	return near * goal_side


## Off the *man*, not the ball. A point relative to the ball moves at the
## speed of the ball (INVARIANTS), and a carrier's ball leaves his foot at
## several metres a second every quarter-second: read that way the jockey's
## target moved at 8-9 m/s and he twitched after it. The man moves at the
## pace of a man.
static func _jockey_point(ctx: SimContext, p: SimPlayer, at: Vector3) -> Vector3:
	var to_goal := SimConsts.horizontal(ctx.pitch.own_goal(p.team) - at)
	var gd: float = maxf(to_goal.length(), 0.1)
	var dir := to_goal / gd
	if absf(at.z) > SHOW_WIDE_FROM:
		dir = (dir + Vector3(0.0, 0.0, -signf(at.z)) * SHOW_WIDE).normalized()
	return ctx.pitch.clamp_to_pitch(at + dir * minf(JOCKEY_STANDOFF, gd * 0.5), 0.3)


## Cover: when a man is beaten, somebody fills the space he lost. The chase
## ranking already penalises the beaten man (`BEATEN_PENALTY`); that chooses
## who presses next, and nobody stood in the lane he had been standing in. One
## man a side, latched for the length of the carry -- a cover recomputed every
## refresh from whoever is nearest is two men swapping the errand every third
## of a second. The point is `COVER_DEPTH` goal-side of the carrier, and it
## moves at his pace: this is about this pass, like the chase, and `Holding
## the shape` reads it under its own name.
const COVER_RANGE := 30.0
const COVER_DEPTH := 5.0
## A teammate this close to the carrier and this far behind him is beaten;
## 0 is directly behind, 1 square in front.
const COVER_BEATEN_RANGE := 4.5
const COVER_BEATEN_BEHIND := 0.35
## How far a man will come to cover.
const COVER_REACH := 14.0

## Who is covering, per team; -1 for nobody.
static var _cover := PackedInt32Array([-1, -1])
## How many times a cover was taken up, whole match. Read by `diagnose`.
static var covers_taken := 0


## The opponent carrying the ball with one of ours beaten on him, or null.
static func _beaten_on(ctx: SimContext, team: int) -> SimPlayer:
	var holder := ctx.ball.last_touch_player
	if holder < 0 or holder >= ctx.players.size():
		return null
	var c := ctx.players[holder]
	if c.team == team or c.is_keeper or not c.on_pitch:
		return null
	var at := ctx.ball.ground_pos()
	if c.dist_to(at) > SimTouch.DRIBBLE_AHEAD_MAX:
		return null
	if SimConsts.horizontal_length(ctx.pitch.own_goal(team) - at) > COVER_RANGE:
		return null
	var heading := SimConsts.horizontal(c.vel)
	var running := heading.length() >= RECOVERY_MIN_CARRIER_SPEED
	if running:
		heading = heading.normalized()
	for pid in ctx.team_players[team]:
		var d := ctx.players[pid]
		if not d.on_pitch or d.is_keeper:
			continue
		var to := SimConsts.horizontal(d.pos - c.pos)
		var dist := to.length()
		if dist > COVER_BEATEN_RANGE or dist < 1e-3:
			continue
		if ctx.tick_index - d.dispossessed_tick < BEATEN_TICKS:
			return c
		if running and 0.5 * ((to / dist).dot(heading) + 1.0) < COVER_BEATEN_BEHIND:
			return c
	return null


## Where the cover stands: goal-side of the carrier.
static func cover_point(ctx: SimContext, team: int) -> Vector3:
	var at := ctx.ball.ground_pos()
	var to_goal := SimConsts.horizontal(ctx.pitch.own_goal(team) - at)
	var d: float = maxf(to_goal.length(), 0.1)
	return ctx.pitch.clamp_to_pitch(at + to_goal / d * minf(COVER_DEPTH, d * 0.6), 0.5)


## Chooses or keeps the cover man for `team`. Latched: the man already
## covering keeps it while the carrier is still beating somebody and he is
## still eligible.
static func _pick_cover(ctx: SimContext, team: int) -> void:
	if _cover.size() != 2:
		_cover = PackedInt32Array([-1, -1])
	var carrier := _beaten_on(ctx, team)
	if carrier == null:
		_cover[team] = -1
		return
	var point := cover_point(ctx, team)
	var current: int = _cover[team]
	if current >= 0 and _cover_eligible(ctx, ctx.players[current], carrier, point):
		return
	var best := -1
	var best_d2 := COVER_REACH * COVER_REACH
	for pid in ctx.team_players[team]:
		var d := ctx.players[pid]
		if not _cover_eligible(ctx, d, carrier, point):
			continue
		var d2 := d.dist_sq_to(point)
		if d2 < best_d2:
			best_d2 = d2
			best = pid
	if best >= 0 and best != current:
		covers_taken += 1
	_cover[team] = best


static func _cover_eligible(ctx: SimContext, d: SimPlayer, carrier: SimPlayer, point: Vector3) -> bool:
	if not d.on_pitch or d.is_keeper or d.recovery_ticks > 0:
		return false
	if d.id < _chase_role.size() and _chase_role[d.id] == CHASE_PRIMARY:
		return false
	# Not the beaten man himself: he is behind the play.
	if ctx.tick_index - d.dispossessed_tick < BEATEN_TICKS:
		return false
	if d.dist_to(carrier.pos) <= COVER_BEATEN_RANGE:
		var heading := SimConsts.horizontal(carrier.vel)
		if heading.length() >= RECOVERY_MIN_CARRIER_SPEED:
			var to := SimConsts.horizontal(d.pos - carrier.pos)
			var dist: float = maxf(to.length(), 1e-3)
			if 0.5 * ((to / dist).dot(heading.normalized()) + 1.0) < COVER_BEATEN_BEHIND:
				return false
	return d.dist_to(point) <= COVER_REACH


## Defending the penalty area. Inside `BOX_DEFEND_RANGE` of his own goal the
## man closing the ball does it from goal-side, `LANE_STANDOFF` in front of
## it, and the second man drops onto the line of the shot instead of five
## metres to the side of it. The ramp is what stops it being a mode: at
## `BOX_DEFEND_FADE` and beyond it is worth nothing.
const BOX_DEFEND_RANGE := 20.0
const BOX_DEFEND_FADE := 30.0
const LANE_STANDOFF := 1.3
## What is left of the support presser's sideways fan-out in front of goal:
## two men on the line of the shot stand shoulder to shoulder, not on each
## other.
const PRESS_FAN_NEAR := 1.6
const PRESS_FAN_FAR := 5.0


## How much the box defence applies to a ball at `at`, 0 to 1.
static func _box_lane_weight(ctx: SimContext, team: int, at: Vector3) -> float:
	var own_goal := ctx.pitch.own_goal(team)
	var d := SimConsts.horizontal_length(own_goal - at)
	return clampf((BOX_DEFEND_FADE - d) / (BOX_DEFEND_FADE - BOX_DEFEND_RANGE), 0.0, 1.0)


static func _support_press_point(ctx: SimContext, p: SimPlayer) -> Vector3:
	var ball := ctx.ball.ground_pos()
	var own_goal := ctx.pitch.own_goal(p.team)
	var toward_goal := (own_goal - ball)
	toward_goal.y = 0.0
	var d: float = maxf(toward_goal.length(), 0.1)
	var base := ball + toward_goal / d * 7.0
	# Fan out to the side of the ball this player already occupies, so two
	# support pressers do not stand on each other.
	#
	# Latched for the length of the press. Recomputed from his position every
	# tick, the sign flips whenever he is anywhere near the line through the ball
	# -- and the two points are ten metres apart, so his target crossed the pitch
	# and came back. It was the last errand naming a point nobody could stand on:
	# `Holding the shape` measured `press` at 4 to 9 m/s and changing its mind on
	# 34-40% of consecutive samples, where every other arm had come under 3.5.
	# The same fix, and the same reason, as the chase assignment's own stagger.
	var lateral := Vector3(-toward_goal.z, 0.0, toward_goal.x) / d
	var side: float = _press_side[p.id] if p.id < _press_side.size() else 0.0
	if is_zero_approx(side):
		side = signf(lateral.dot(p.pos - ball))
		if is_zero_approx(side):
			side = 1.0
		if p.id < _press_side.size():
			_press_side[p.id] = side
	var fan: float = lerpf(PRESS_FAN_FAR, PRESS_FAN_NEAR, _box_lane_weight(ctx, p.team, ball))
	return ctx.pitch.clamp_to_pitch(base + lateral * side * fan, 1.0)


## How far past the last defender a forward is willing to position. Positive is
## offside; they mostly stay just short of it, and sometimes do not.
const BEHIND_MARGIN := -0.4


## Forwards play on the shoulder of the last defender.
##
## Without this the front line simply sits where the formation puts it, no
## attacker is ever beyond the defensive line, and the match records no offsides
## at all -- which is both wrong and a sign that nobody is threatening in behind.
static func _run_in_behind(ctx: SimContext, p: SimPlayer, shape: Vector3) -> Vector3:
	p.making_run = false
	if p.role != SimRole.ST and p.role != SimRole.WIDE:
		return shape
	var dir := ctx.pitch.attack_dir(p.team)
	# Only worth doing when the ball is somewhere it could actually be played
	# forward from, and near enough that this player is a candidate to receive
	# it. A forward who tracks the offside line for ninety minutes regardless
	# covers eighteen kilometres and offers nothing.
	if ctx.ball.pos.x * dir < -ctx.pitch.half_length * 0.1:
		return shape
	if p.dist_to(ctx.ball.ground_pos()) > 38.0:
		return shape
	# The line as this player believes it to be, not as it is. That difference
	# is the whole reason anyone is ever caught offside.
	var line := SimReferee.believed_offside_line(ctx, p) * dir
	# Sit on the shoulder. A good reader of the game leaves themselves a margin;
	# a poor one plays right on it and gets caught.
	var judgement: float = lerpf(BEHIND_MARGIN, -4.0, p.attrs.positioning)
	var target_depth: float = line + judgement
	var current := shape.x * dir
	if current >= target_depth:
		return shape
	# Never further forward than the shape would allow by more than a stride or
	# two: a striker glued to the offside line stops offering anything else.
	var depth: float = minf(target_depth, current + 9.0)
	p.making_run = true
	p.errand = Errand.SHOULDER
	return Vector3(depth * dir, shape.y, shape.z)


## Distance at which a teammate offers a genuine short option to the carrier.
const SUPPORT_RADIUS := 12.0
## Nobody further than this from the ball bothers to come and support it.
const SUPPORT_REACH := 34.0
## How far a man will travel to do it.
##
## Support is a few steps from where he stands, not a place on a circle. It used
## to return the ring outright: every man level with or behind the ball whose
## station was between 12 and 34 m from it was put on one 12 m circle round the
## ball, which is a relocation of up to 22 m and, for a 4-3-3, four or five men
## at once. `The clump` and `Holding the shape` between them are that stated
## twice -- the ten outfielders standing on six cells of a fifteen-cell grid, and
## a `support` target moving at 5.3 m/s with its man 13.7 m behind it, because a
## circle round the ball travels at the speed of the ball.
##
## Stepped instead, the ring becomes a gradient: the man at 15 m arrives at
## supporting distance, the man at 30 m comes to 23 and stays in his band, and
## nobody is asked for a journey he cannot finish before the ball has gone.
const SUPPORT_STEP := 7.0


## Players near the ball come and offer a short option.
##
## Without this the formation holds its spacing, the nearest teammate is
## twenty-five metres away, and every pass in the match is a long one -- which
## then completes half the time and the whole game reads as pinball. Support
## movement is what makes a short passing game possible at all.
static func _support_adjust(ctx: SimContext, p: SimPlayer, shape: Vector3) -> Vector3:
	if ctx.possession_player == p.id:
		return shape
	# The shape's ball, like every other station rule: coming short is about where
	# play is, not about a ball that is in the air. Read live, the whole ring flew
	# with every pass and no one on it was ever standing still.
	var ball := ctx.shape_ball
	var away := shape - ball
	away.y = 0.0
	var d := away.length()
	if d <= SUPPORT_RADIUS or d > SUPPORT_REACH:
		return shape
	# Only players level with or behind the ball come short. The front line runs
	# beyond it -- pulling everyone back to the ball would give the carrier lots
	# of options and no way through.
	var dir := ctx.pitch.attack_dir(p.team)
	if (shape.x - ball.x) * dir > 6.0:
		return shape
	# Come along the line they already occupy, so the shape keeps its angles
	# instead of everyone converging on the same spot, and come only a few steps.
	p.errand = Errand.SUPPORT
	return shape - away / d * minf(SUPPORT_STEP, d - SUPPORT_RADIUS)


## In possession: attackers climb the local gradient of control x threat, and
## everyone offers a passing angle rather than standing in the carrier's shadow.
static func _attacking_adjust(ctx: SimContext, p: SimPlayer, shape: Vector3) -> Vector3:
	shape = _run_in_behind(ctx, p, shape)
	shape = _link_station(ctx, p, shape)
	# He has decided to go and meet the ball, or to go past the last defender.
	# Both genuinely relocate him, so both stand in for the generic support and
	# ascent below -- which are the same ideas arrived at without a decision.
	var offer := SimOffBall.point_for(ctx, p)
	if offer != Vector3.INF:
		p.making_run = SimOffBall.is_running_in_behind(ctx, p)
		p.errand = Errand.OFFER
		return offer
	shape = _support_adjust(ctx, p, shape)
	# Drifting into a pocket is not a relocation, it is a few metres off a
	# station he is still holding, so it arrives as an offset and everything the
	# shape did survives underneath it. It replaces the ascent below because it
	# is the ascent, made deliberately and then committed to.
	var drift := SimOffBall.drift_for(ctx, p)
	if drift != Vector3.ZERO:
		p.errand = Errand.DRIFT
		return ctx.pitch.clamp_to_pitch(shape + drift, 1.0)
	if not SimRole.is_attacking(p.role) and p.role != SimRole.CM and p.role != SimRole.FB:
		return shape
	# The value field is refreshed at about 5 Hz, so the ascent is too; between
	# refreshes the player keeps the offset they last found. Recomputing it on
	# the 10 Hz movement cadence doubled the cost of the most expensive thing in
	# the module for no change in behaviour.
	if ctx.tick_index - p.value_offset_tick < SimConsts.VALUE_FIELD_TICKS * ctx.config.decision_stride():
		if p.value_offset != Vector3.ZERO:
			p.errand = Errand.ASCENT
		return shape + p.value_offset

	# The probes are a few metres apart, so the players who could contest any of
	# them are the same set. Gather it once rather than per probe.
	ctx.value.begin_local(ctx, shape, PROBE_DISTANCE + 15.0)
	# **Built, measured and reverted: the incumbent may not be the point he is
	# already going to.** `PROBE_MARGIN` defends the station, and the obvious
	# reading is that it is defending a point he has already left -- a man with a
	# probe either side of him flips between the two, and `Holding the shape`
	# measured the point an `ascent` man was running at moving at 7.7 m/s, faster
	# than he can run, leaving him eleven metres off it. Starting `best` at
	# `shape + p.value_offset` instead fixed exactly that: the target came down to
	# 4.7-6.2 m/s and the gap to 7.8-9.4 m over three seeds.
	#
	# It also stopped the attack. Touches in the final third went to 0%, 12%, 2%
	# against 28%, 9%, 13%, and touches in the opposition box to 0, 0, 0 against
	# 6, 3, 1. The ascent is what climbs a man toward goal; made sticky, it holds
	# him wherever he first found value and the side never arrives. Whatever damps
	# it has to leave the climb intact, which a margin on the incumbent does not.
	var best := shape
	var best_value := ctx.value.value_at_local(ctx, shape, p.team) * PROBE_MARGIN
	# Four probes, clamped: a local ascent, not a search. Attackers drifting to
	# the single best point on the pitch would collapse the shape.
	for i in PROBES.size():
		var point := ctx.pitch.clamp_to_pitch(shape + ctx.pitch.orient(p.team, PROBES[i]), 1.0)
		var v := ctx.value.value_at_local(ctx, point, p.team)
		if v > best_value:
			best_value = v
			best = point
	p.value_offset = best - shape
	p.value_offset_tick = ctx.tick_index
	if best != shape:
		p.errand = Errand.ASCENT
	return best


## Out of possession the back line holds a line together and, if the plan says
## so, steps up to spring the trap.
##
## Aligning the line is what turns a forward's misjudgement into an offside: an
## attacker sitting on where they *believe* the line is gets caught when the
## real line moves as a unit.
static func _hold_the_line(ctx: SimContext, p: SimPlayer, shape: Vector3) -> Vector3:
	if p.role != SimRole.CB and p.role != SimRole.FB:
		return shape
	var dir := ctx.pitch.attack_dir(p.team)
	var team: SimTeam = ctx.teams[p.team]
	# Where the back line as a whole should be, from the formation rather than
	# from wherever these players happen to have ended up. Constant for the
	# match, so it reuses the same cache as the line-height reference.
	var formation_depth := _default_line_x(team, ctx.pitch)
	var tactics := team.ensure_tactics()
	var line_depth := shape.x * dir
	# Pull each defender toward the shared line, then step it up by the trap.
	var own_depth := ctx.pitch.scale_point(team.formation.homes[clampi(p.slot, 0, team.formation.size() - 1)]).x
	var aligned: float = line_depth + (formation_depth - own_depth) * 0.6
	# The shape's ball. Where a back line holds its trap is a station like any
	# other, and read live it was the last thing in this function driven at the
	# speed of a pass -- worth up to `offside_trap * 5` metres of line height,
	# arriving as fast as the ball crossed the eighteen-metre band.
	var ball_far: float = clampf((SimConsts.horizontal_length(p.pos - ctx.shape_ball) - 18.0) / 22.0, 0.0, 1.0)
	aligned += tactics.offside_trap * 5.0 * ball_far
	return Vector3(aligned * dir, shape.y, shape.z)


## Out of possession: position between the assigned opponent and goal, biased
## toward the ball side.
static func _defensive_adjust(ctx: SimContext, p: SimPlayer, shape: Vector3) -> Vector3:
	shape = _hold_the_line(ctx, p, shape)
	# The trap as an act: the whole line steps up together for a moment. Added
	# after the marking blend below, or the blend eats most of the step --
	# `pull` runs to 0.9 with the ball near.
	var lift := 0.0
	if p.role == SimRole.CB or p.role == SimRole.FB:
		lift = trap_lift(ctx, p.team)
	var step := Vector3(ctx.pitch.attack_dir(p.team) * lift, 0.0, 0.0)
	var mark := _assign_mark(ctx, p)
	if mark < 0:
		return shape + step
	p.errand = Errand.MARK
	p.marking_target = mark
	var opponent := ctx.players[mark]
	var opp_pos := SimPerception.believed_pos(ctx, p, opponent)
	var own_goal := ctx.pitch.own_goal(p.team)
	var to_goal := own_goal - opp_pos
	to_goal.y = 0.0
	var d: float = maxf(to_goal.length(), 0.1)
	# Goal-side, but not on top of them. Marking this tight means the marker is
	# inside contest range of every ball played to their man, and no pass in the
	# match is ever completed cleanly.
	var goal_side := opp_pos + to_goal / d * lerpf(4.5, 2.4, ctx.tactics(p.team).press_intensity)
	# Bias toward the ball so a marker can still intercept the pass.
	var to_ball := ctx.ball.ground_pos() - goal_side
	to_ball.y = 0.0
	var station := goal_side
	if to_ball.length() > 0.1:
		station = goal_side + to_ball.normalized() * 1.1
	# Blend with the shape so marking never drags the block apart, and go with a
	# man only as far as the ball makes him a threat. Away from the ball a
	# defender holds his zone and keeps half an eye on whoever is in it.
	var pull: float = clampf(ctx.tactics(p.team).press_intensity * 0.5 + 0.35, 0.0, 0.9)
	pull *= mark_tightness(SimConsts.horizontal_length(opp_pos - ctx.ball.ground_pos()))
	return shape.lerp(station, pull) + step


## How near the ball a man has to be before his marker goes with him.
##
## Inside `MARK_TIGHT_BALL` the ball can reach him at once, and that is the
## moment marking is for. Beyond `MARK_LOOSE_BALL` he is not receiving the next
## pass and following him is how a block comes apart.
##
## This was the largest single force taking the side out of its shape, and the
## instrument that found it is `diagnose`'s `Holding the shape`: marking was 40%
## of every outfielder-sample, the marker's own station stood 31.6 m from the
## ball and the marker stood 25.4 m from it, which is ten defenders each drawn a
## net six metres toward the ball for no reason but that somebody was standing
## there. Flat man-marking at any distance also has no answer to a side that
## simply moves: the block goes with it and the shape is whatever the opposition
## drew.
const MARK_TIGHT_BALL := 16.0
const MARK_LOOSE_BALL := 40.0
## What is left of the pull out there. Not nothing -- a defender still leans
## toward the man in his zone, he just does not travel with him.
const MARK_ZONAL := 0.3


static func mark_tightness(opponent_to_ball: float) -> float:
	var t: float = clampf((opponent_to_ball - MARK_TIGHT_BALL) / (MARK_LOOSE_BALL - MARK_TIGHT_BALL), 0.0, 1.0)
	return lerpf(1.0, MARK_ZONAL, t)


## Nearest unclaimed opponent in this player's zone. Deliberately simple: a
## strict assignment problem would be both slower and less football-like.
static func _assign_mark(ctx: SimContext, p: SimPlayer) -> int:
	var best := -1
	var best_score := INF
	var shape := p.move_target if p.move_target != Vector3.ZERO else p.pos
	for oid in ctx.opponent_ids(p.team):
		var o := ctx.players[oid]
		if not o.on_pitch or o.is_keeper:
			continue
		# Prefer opponents in front of goal and near this player's station.
		var dx := o.pos.x - shape.x
		var dz := o.pos.z - shape.z
		var d2 := dx * dx + dz * dz
		if d2 > 484.0:
			continue
		var score := sqrt(d2) - ctx.player_threat[oid] * 30.0
		# Stick with whoever you were already marking unless someone else is
		# clearly more dangerous. Reassigning every tenth of a second makes
		# defenders shuttle between two attackers and run twice as far as they
		# should.
		if oid == p.marking_target:
			score -= 4.0
		if score < best_score:
			best_score = score
			best = oid
	return best
