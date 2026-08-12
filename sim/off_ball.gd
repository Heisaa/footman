class_name SimOffBall
extends RefCounted
## How a player without the ball offers himself to receive it (PLAN.md §4.3).
##
## Before this, a teammate's availability was one undifferentiated thing: hold
## the formation's station, slide with the ball, and settle onto a twelve-metre
## ring if play came near. Every option a carrier had was therefore the same
## option, and the only thing telling two of them apart was distance. A team
## like that has nobody coming to meet the ball, nobody driving off a marker,
## and no runner to hit -- so the through ball is generated as a candidate and
## then never scores, because there is never anybody actually going anywhere.
##
## A footballer makes himself available in several different ways, and which one
## he picks is a decision:
##
##   show    -- come and meet the man on the ball, short and angled off the
##              nearest marker. Worth most when the carrier is under pressure,
##              which is the moment somebody has to give him an out.
##   space   -- move off into a pocket, valued by control of the space *and* by
##              whether a ball could actually get there. The plain value ascent
##              in SimMovement cannot see the second half of that: it will climb
##              happily into a pocket with two men standing in the passing lane.
##   behind  -- set off past the last defender for a ball played in front of
##              him. Timed rather than positional: he starts from onside and is
##              offside if the pass comes late, which is what makes the timing
##              of the release matter to both players.
##
## The three are scored in the same units as everything else in the engine --
## pitch control times expected threat -- picked by softmax rather than argmax,
## held for a commitment window so nobody flickers between two ideas, and
## rationed by a quota per team so that ten men do not all come short at once.
##
## That quota is the same anti-swarm reasoning as SimMovement._assign_chasers,
## applied to the attacking half of the problem. It is *not* a second chase
## mechanism and it does not touch that one: no intent here ever targets the
## ball, and the shortest of them stops a good ten metres off it.
##
## Every option is measured against the player's *station* rather than against
## where he happens to be standing, and the movement layer applies the result on
## top of the shape rather than instead of it. That is not a detail. The first
## cut of this module handed back an absolute point and returned early, so a man
## with an idea stopped sliding up the pitch with play and stopped taking the
## shoulder of the last defender -- five of the ten simply fell out of the
## shape. Measured on one seed it moved touches in the final third from 26% to
## 15%, the ball in the box from 55 to 19, and distance covered *down* by four
## hundred metres a man: the whole team standing around midfield offering for a
## ball nobody could do anything with. Contributions, per PLAN.md §4.3, not
## replacements.

enum { NONE, SHOW, SPACE, BEHIND }

const KIND_NAMES := ["none", "show", "space", "behind"]

## Assignment cadence, in ticks. This is built out of the value field, which is
## a 5 Hz quantity (PLAN.md §2.5), so it is refreshed at the same rate.
const ASSIGN_TICKS := 12

## How many of each kind a team may have running at once. Six of the ten
## outfielders at the very most, and in practice fewer, because a run has to
## beat standing still by a margin before it is taken at all.
##
## Space was two, and two is not a team moving. With one man allowed to come
## short and two to go past the last defender, a side in possession had at most
## three of its ten offering anything and the other seven stood on their
## stations -- which is what a carrier with nothing on is looking at, whatever
## the scoring says. It is raised here and not in the quota for showing, because
## moving into space is the one kind that cannot swarm: no intent in this file
## ever targets the ball and the nearest of them stops ten metres off it, so the
## guard in `SimMovement._assign_chasers` has nothing to say about it.
const QUOTA := [0, 1, 3, 2]

## Nobody further than this from the ball is offering to receive it. He is
## holding shape, which at that distance is the right thing to be doing.
const RANGE := 40.0
## Radius of the shared local set used for every control evaluation in one
## assignment pass. Everyone outside it is too far away to win a race for any
## point being considered.
const LOCAL_RADIUS := 45.0

## Where a man showing for it stops.
##
## Deliberately outside ten metres: the swarm invariant counts bodies inside
## that radius, and a support run that reads as football must not be the thing
## that makes a team look like it is collapsing on the ball. What makes this
## read as coming to meet it is the movement -- brisk, on a tight deadband --
## and not the last metre and a half of the distance.
const SHOW_DISTANCE := 10.5
## He has to be far enough out for coming short to mean anything, and near
## enough that he is a candidate to be found at all.
const SHOW_MIN := 13.0
const SHOW_MAX := 22.0
## How far he steps off a defender sitting on the spot he is coming to. Across
## the line to the ball rather than along it, so he opens the angle without
## giving up the distance.
const SHOW_STEP := 3.2
## How close a marker has to be to that spot before it is worth stepping off him.
const SHOW_MARKED := 5.0

## Probe distances and directions for a move into space, in the canonical
## attacking frame.
##
## Two rings, and the far one is the point. At one ring of six metres the most
## ambitious thing this layer could express was a shuffle, and it measured as one:
## 545 moves into space in ten minutes, averaging *plus one point eight metres up
## the pitch*, found by the ball 3% of the time. That is not a man moving into
## space to give somebody an option, it is a man adjusting his footing, and it is
## the whole of why a side with the ball in its own half has nothing on but a
## square pass.
##
## The far ring only goes forward. Sideways at fourteen metres is a man leaving
## his station for no reason, and backwards at any distance is what the station
## already is -- holding it is scored as `NONE` from the same function, so a
## backward probe could only ever be a worse version of standing still. That is
## also why the near ring lost the one it had.
const SPACE_PROBE := 6.0
const SPACE_PROBE_FAR := 14.0
const SPACE_PROBES := [
	Vector3(SPACE_PROBE, 0.0, 0.0),
	Vector3(SPACE_PROBE * 0.7, 0.0, SPACE_PROBE * 0.7),
	Vector3(SPACE_PROBE * 0.7, 0.0, -SPACE_PROBE * 0.7),
	Vector3(0.0, 0.0, SPACE_PROBE),
	Vector3(0.0, 0.0, -SPACE_PROBE),
	Vector3(SPACE_PROBE_FAR, 0.0, 0.0),
	Vector3(SPACE_PROBE_FAR * 0.75, 0.0, SPACE_PROBE_FAR * 0.66),
	Vector3(SPACE_PROBE_FAR * 0.75, 0.0, -SPACE_PROBE_FAR * 0.66),
]

## How fast the value of a point decays with how long it takes to get to it. See
## `_value_of`.
const PROMPTNESS_DECAY := 0.22

## How far past the last defender the run in behind is aimed.
const BEHIND_DEPTH := 9.0
const BEHIND_RANGE := 34.0
## A runner only goes when the man on the ball can see him go. Above this the
## carrier has his head down and the run is wasted, which is exactly the
## complaint about engines where strikers sprint in behind on a metronome.
const BEHIND_MAX_PRESSURE := 1.05
## How far beyond the line he may already be and still start a run. Past this he
## is not making a run, he is standing offside.
const BEHIND_ONSIDE_SLACK := 1.0
## Assumed pace of the ball that would be played, for judging the race.
const BEHIND_PASS_SPEED := 16.0
## The longest run in behind worth setting off on: a sprinter covers about this
## in the window below, and a run that outlasts its own commitment is a man
## chasing a ball that went somewhere else two seconds ago.
const BEHIND_MAX_RUN := 18.0

## Commitment window per kind, in seconds. Long enough that a run is a run --
## and for a move into space that now means long enough to finish the far probe,
## which at the pace below is a little over three seconds. A window that expires
## as he arrives is a man who never arrives.
const HOLD_SECONDS := [0.0, 3.0, 4.5, 4.0]
## And the rest afterwards, before the same player will do it again. The sprint
## in behind is the expensive one and carries much the longest cooldown; without
## it a front three covers eighteen kilometres between them.
const REST_SECONDS := [0.0, 4.5, 4.0, 10.0]

## Pace of each kind as a fraction of the player's maximum, and how close counts
## as arrived. A run in behind has to be made to the metre; drifting into space
## does not.
##
## Space was 0.45 of maximum, and that was the option scored one way and played
## another. `promptness` prices the point off `time_to_arrive`, which knows only
## the player's real acceleration and top speed -- so the layer scored a man
## arriving in two seconds and then sent him at a stroll that took four and a
## half. The far probe cannot survive that and neither could the near one: three
## per cent of moves into space ever had the ball played to them. He goes at the
## pace he was scored at, near enough, and what is left of the gap is the
## difference between a footballer's cruise and his sprint.
const PACE := [0.0, 0.62, 0.75, 0.97]
const DEADBAND := [0.0, 1.5, 1.8, 1.0]

## How much better than standing still an idea has to look before it is worth
## the legs. The same hysteresis as SimMovement.PROBE_MARGIN and for the same
## reason: without it players chase a flickering optimum all match.
const HOLD_MARGIN := 1.35

## Softmax temperature bounds, as a fraction of the spread of the option scores.
## Same construction as SimDecision: a fixed temperature over scores that often
## span less than a hundredth is either argmax or noise.
const TEMP_POOR := 0.35
const TEMP_GOOD := 0.10

## Width of the corridor an opponent has to be inside before he counts as
## standing in the passing lane.
const LANE_WIDTH := 3.0
## How hard an open lane counts when the player is choosing a pocket rather than
## coming to meet the ball. See `_value_of`.
const SPACE_LANE_POWER := 0.5

## Live intent per player id, and where it is going. Flat arrays rather than
## dictionaries because the movement layer reads them for every player, every
## tick.
static var _intent := PackedInt32Array()
static var _point := PackedVector3Array()
static var _until := PackedInt32Array()
static var _ready := PackedInt32Array()
static var _since := PackedInt32Array()

## Per-match tallies by kind: how many of each were made, how many ended with
## the ball at that player's feet, and how far he ran to offer.
##
## Counted rather than logged. An intent is taken several times a second across
## a team, so putting each one in the event log would bury everything else in
## it -- but a run nobody ever judges is a run nobody can learn anything from
## (PLAN.md §5.3 makes the same argument about patterns), and "space: 88 taken,
## 11% found" is the whole answer to whether this layer is doing its job.
static var made := PackedInt32Array()
static var received := PackedInt32Array()
static var cut_short := PackedInt32Array()
static var travel := PackedFloat32Array()
## Net ground gained up the pitch by every offer of each kind. A layer meant to
## make a team available that quietly walks it backwards would show up here and
## nowhere else.
static var forward := PackedFloat32Array()

## The receiver's half of the decision, which `received` cannot see.
##
## "Space: 374 taken, 2% received" is two completely different faults wearing the
## same number, and they want opposite fixes. Either the man on the ball never had
## this run on his list at all -- `_shortlist` keeps six of ten teammates and ranks
## them by the expected threat of the grass each is standing on, which for a man
## mid-run is the grass he is leaving -- or it was on the list every time and lost,
## in which case the run is fine and what is wrong is what the pass is worth.
##
## `offered` counts the runs that were a scored pass candidate at least once
## before they expired. `weight` sums the largest share of the softmax the run's
## own ball ever held, so `weight / made` is what an average offer was actually
## worth to the man who could have played it.
static var offered := PackedInt32Array()
static var weight := PackedFloat32Array()

## Runs that ended because the possession ended in a shot. Split out of
## `cut_short`, which was counting them as failures. See `_expire`.
static var shot := PackedInt32Array()

## The live half of those two, per player, reset at `_commit` and folded in at
## `_expire`.
static var _offered := PackedInt32Array()
static var _best_weight := PackedFloat32Array()

## Scratch for one assignment pass, reused so the path allocates nothing.
static var _pick_ids := PackedInt32Array()
static var _pick_kinds := PackedInt32Array()
static var _pick_gains := PackedFloat32Array()
static var _pick_points := PackedVector3Array()
static var _scores := PackedFloat32Array()
static var _points := PackedVector3Array()
static var _weights := PackedFloat32Array()


# --- The layer --------------------------------------------------------------


## Clears everything this layer keeps outside the context. `SimMatch.setup` calls
## it, because a second match in the same process must not inherit the first
## one's runs.
##
## This used to be done inside `update`, on `ctx.tick_index == 0`, and it never
## fired once: tick 0 is the kick-off, the ball is dead, and the movement layer —
## which is what calls `update` — only runs while the ball is in play. So every
## match after the first in a process started with the previous match's intents
## and diverged from the same seed run on its own. `docs/PITFALLS.md` has it.
static func reset() -> void:
	_resize(0)


## Called once per tick from the movement layer, before anyone's target is
## recomputed.
static func update(ctx: SimContext) -> void:
	var n := ctx.players.size()
	if _intent.size() != n:
		_resize(n)
	var stride := ctx.config.decision_stride()
	if ctx.tick_index % (ASSIGN_TICKS * stride) != 0:
		return
	_expire(ctx)

	var team := ctx.possession_team
	if team < 0:
		return
	# Somebody has to be about to play the pass. A contested ball has no carrier
	# to show for, but the man who last touched it is still the one everyone is
	# arranging themselves around.
	var carrier := ctx.possession_player
	if carrier < 0:
		carrier = ctx.ball.last_touch_player
	if carrier < 0 or carrier >= n or ctx.players[carrier].team != team:
		return
	_assign(ctx, team, carrier)


## Which way this player is currently offering himself, or NONE.
##
## Intents are retired on the assignment cadence, so the window and the state of
## possession are re-tested here rather than trusted: a run that ends the instant
## the ball is lost must end on that tick and not up to a fifth of a second
## later.
static func intent_of(ctx: SimContext, p: SimPlayer) -> int:
	if p.id >= _intent.size() or _intent[p.id] == NONE:
		return NONE
	if ctx.possession_team != p.team or ctx.tick_index >= _until[p.id]:
		return NONE
	return _intent[p.id]


## Where a man who has gone somewhere specific is going, or Vector3.INF.
##
## Only the two intents that genuinely relocate him: coming to meet the ball,
## and going past the last defender. Moving into space is not one of those -- it
## is a few metres off a station he is still holding -- and it comes back as an
## offset instead, from `drift_for`.
##
## The distinction is not cosmetic. Handed back as an absolute point, a drift
## took the front line off the shoulder of the last defender for three seconds
## at a time -- it was the shape for the duration, rather than a nudge to it, so
## everything the shape was doing for those three seconds simply stopped.
static func point_for(ctx: SimContext, p: SimPlayer) -> Vector3:
	var kind := intent_of(ctx, p)
	if kind == NONE or kind == SPACE:
		return Vector3.INF
	return _point[p.id]


## The committed drift off his station, or Vector3.ZERO. Added to whatever the
## shape decided, so everything the shape does -- sliding with play, hanging off
## the defensive line, taking the shoulder -- still happens underneath it.
static func drift_for(ctx: SimContext, p: SimPlayer) -> Vector3:
	if intent_of(ctx, p) != SPACE:
		return Vector3.ZERO
	return _point[p.id]


## Where this player is going, whatever kind of offer he has made, or
## Vector3.INF if he has made none.
##
## `point_for` deliberately answers only for the two intents that relocate a
## man, because the movement layer needs a drift to stay a drift. The passer
## needs a different question answered: not "has he gone somewhere" but "where
## will he be", and for that a pocket three metres off his station is as real a
## destination as a run past the last defender. This resolves all three into the
## one absolute point that a ball can be played to.
##
## This is the receiver's half of a conversation the engine was not having. The
## man on the ball was aiming at where a teammate *is*, extrapolated by his
## current velocity, which cannot see the run that has been decided on and not
## yet begun -- and that run is exactly the one worth passing to.
static func destination_for(ctx: SimContext, p: SimPlayer) -> Vector3:
	match intent_of(ctx, p):
		SHOW, BEHIND:
			return _point[p.id]
		SPACE:
			return SimMovement.shape_position(ctx, p) + _point[p.id]
		_:
			return Vector3.INF


static func pace_for(ctx: SimContext, p: SimPlayer) -> float:
	return PACE[intent_of(ctx, p)]


static func deadband_for(ctx: SimContext, p: SimPlayer) -> float:
	return DEADBAND[intent_of(ctx, p)]


## True while this player is making a timed run in behind. The decision layer
## reads it through `SimPlayer.making_run`: a through ball is only a through
## ball if somebody is running onto it, and before this the only players who
## could be were the ones whose *role* happened to be attacking.
static func is_running_in_behind(ctx: SimContext, p: SimPlayer) -> bool:
	return intent_of(ctx, p) == BEHIND


## How much a run is worth to the man who has just passed, at the instant he
## plays it, decaying to nothing across the same window the decision layer
## prices his return ball over.
const GIVE_AND_GO_RUN := 1.5


## 1 at the moment this player laid the ball off, 0 once the window has run out.
static func _just_passed(ctx: SimContext, p: SimPlayer) -> float:
	if ctx.last_pass_from != p.id:
		return 0.0
	var elapsed := float(ctx.tick_index - ctx.last_pass_tick) / float(SimConsts.TICK_HZ)
	if elapsed < 0.0 or elapsed > SimDecision.GIVE_AND_GO_WINDOW:
		return 0.0
	return 1.0 - elapsed / SimDecision.GIVE_AND_GO_WINDOW


# --- Assignment -------------------------------------------------------------


static func _assign(ctx: SimContext, team: int, carrier: int) -> void:
	var ball := ctx.ball.ground_pos()
	var urgency := ctx.pressure_on(ctx.players[carrier])
	# One gather for the whole pass: every point considered below is within a
	# few metres of somebody in this set, so the same handful of players decides
	# all of them.
	ctx.value.begin_local(ctx, ball, LOCAL_RADIUS)

	# Runs already under way consume the quota before anyone new is considered.
	var used := [0, 0, 0, 0]
	for pid in ctx.team_players[team]:
		var live: int = _intent[pid]
		if live != NONE:
			used[live] += 1

	_pick_ids.clear()
	_pick_kinds.clear()
	_pick_gains.clear()
	_pick_points.clear()
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if pid == carrier or p.is_keeper or not p.on_pitch:
			continue
		if _intent[pid] != NONE or ctx.tick_index < _ready[pid]:
			continue
		if p.dist_to(ball) > RANGE:
			continue
		# A pattern already has this man running somewhere specific. Two ideas
		# about where one player should be is one too many.
		if SimPatterns.movement_override(ctx, p) != Vector3.INF:
			continue
		_consider(ctx, p, team, carrier, ball, urgency)

	# The quota goes to whoever gains most by running, not to whoever the loop
	# reached first.
	for i in _pick_ids.size():
		var kind: int = _pick_kinds[i]
		if used[kind] >= int(QUOTA[kind]):
			continue
		used[kind] += 1
		_commit(ctx, _pick_ids[i], kind, _pick_points[i])


## Scores this player's options, picks one by softmax, and files it against the
## quota. Filing rather than committing, because how good the idea is decides
## who gets to act on it.
static func _consider(ctx: SimContext, p: SimPlayer, team: int, carrier: int, ball: Vector3, urgency: float) -> void:
	if _scores.size() != 4:
		_scores.resize(4)
		_points.resize(4)
		_weights.resize(4)
	for i in 4:
		_scores[i] = -INF
		_points[i] = Vector3.ZERO

	# Every option is measured against the station, not against the patch of
	# grass he is standing on. The station is where the shape is taking him
	# anyway -- it slides up the pitch with play and hangs off the defensive
	# line -- so scoring against his current position would price a run against
	# a stationary alternative that does not exist.
	var base := SimMovement.shape_position(ctx, p)
	# Doing nothing in particular is an option, and usually the right one.
	_scores[NONE] = _value_of(ctx, p, team, ball, base, 0.5, SPACE_LANE_POWER) * HOLD_MARGIN
	_points[NONE] = base

	var show := _show_point(ctx, p, team, ball)
	if show != Vector3.INF:
		var retention := ctx.tactics(team).retention_bias()
		# A carrier with a man on him needs somebody to come to him far more
		# than a carrier with time does. This is the whole reason the option
		# exists, so it is the term that decides when it is taken.
		var wanted: float = lerpf(0.85, 1.75, clampf(urgency / 1.5, 0.0, 1.0))
		# `retain` is 1.0 here against 0.5 for space and for holding shape, and it
		# has been tried at 0.5 twice. Through the middle third `possession_value`
		# is 0.013 against an expected threat of about 0.002 -- four fifths of the
		# whole score -- so equalising it very nearly halves this option, and the
		# reasoning for doing it was that too many men come to meet the ball.
		#
		# They do, and this is not why. Seed 7, ten minutes, halving it on its own:
		# shows fell from 225 to 128 and the men who stopped showing went back to
		# *standing on their stations*, because at the time the only other thing on
		# the list was a six-metre shuffle that already lost to holding shape. The
		# carrier's list got shorter without getting better -- touches in the
		# opposition box 30 to 8, passes backward 29% to 33%.
		#
		# Tried again with the far probes in and a move into space finally worth
		# something, it still loses, and by more: 21% of passes backward at 1.0
		# against 31% at 0.5, the final third 18% against 15%, the opposition box
		# 27 touches against 21. Coming short is not what makes a side play
		# backwards. Having nowhere else to be is.
		_scores[SHOW] = _value_of(ctx, p, team, ball, show, 1.0) * retention * wanted
		_points[SHOW] = show

	var space := _space_point(ctx, p, team, ball, base)
	if space != Vector3.INF:
		_scores[SPACE] = _value_of(ctx, p, team, ball, base + space, 0.5, SPACE_LANE_POWER)
		_points[SPACE] = space

	var behind := _behind_point(ctx, p, team, ball, urgency)
	if behind != Vector3.INF:
		# Not scored through _value_of: pitch control asks who owns that space
		# now, and the answer for a point nine metres beyond the last defender
		# is always the defence. The question a runner is actually asking is
		# whether *he* beats them to it if he sets off this instant.
		var race := _race(ctx, p, behind)
		var lane := _lane_open(ctx, ball, behind, team)
		_scores[BEHIND] = ctx.value.xt_at(team, behind, ctx.pitch) * race * lane \
			* ctx.tactics(team).direct_bias() * ctx.tactics(team).focus_at(behind.z, ctx.pitch)
		_points[BEHIND] = behind

	# The give-and-go, from the side that has to make the run. A man who has
	# just laid the ball off is the one player on the pitch whose marker is
	# watching something else, and nothing in a positional model knows that --
	# he has done his job, his station is where he already stands, and holding
	# it scores perfectly well. Both running options are lifted while it lasts,
	# which is a prior on a score the layer was going to compute anyway
	# (PLAN.md §5.1), and both are non-negative, so lifting them cannot make a
	# bad option look good the way a multiplier on a signed score would.
	var laid_off := _just_passed(ctx, p)
	if laid_off > 0.0:
		var lift: float = lerpf(1.0, GIVE_AND_GO_RUN, laid_off)
		if not is_inf(_scores[BEHIND]):
			_scores[BEHIND] *= lift
		if not is_inf(_scores[SPACE]):
			_scores[SPACE] *= lift

	# Softmax, never argmax, and the temperature is relative to the spread of
	# the scores rather than absolute -- they are goal probabilities and often
	# span less than a hundredth.
	var best := -INF
	var worst := INF
	for i in 4:
		if is_inf(_scores[i]):
			continue
		best = maxf(best, _scores[i])
		worst = minf(worst, _scores[i])
	if is_inf(best):
		return
	var temperature: float = lerpf(TEMP_POOR, TEMP_GOOD, p.attrs.decisions) * maxf(best - worst, 1e-5)
	for i in 4:
		_weights[i] = 0.0 if is_inf(_scores[i]) else exp((_scores[i] - best) / temperature)
	var kind: int = maxi(ctx.rng.weighted_index(_weights), 0)
	if kind == NONE:
		return

	# Ranked by what the run gains over standing still, so a striker with a
	# genuine ball in behind takes the quota off a midfielder shuffling two
	# metres sideways.
	var gain: float = _scores[kind] - _scores[NONE]
	var at := 0
	while at < _pick_gains.size() and _pick_gains[at] >= gain:
		at += 1
	_pick_ids.insert(at, p.id)
	_pick_kinds.insert(at, kind)
	_pick_gains.insert(at, gain)
	_pick_points.insert(at, _points[kind])


## What the man on the ball made of this offer, written from `SimDecision` as it
## weighs its candidates: `share` is this ball's share of the softmax.
##
## One-way, like the rest of the tallies. Nothing in `sim/` reads it back and it
## never touches `ctx.rng`, so a match runs identically whether or not anyone is
## looking at it.
static func note_offer(mate_id: int, share: float) -> void:
	if mate_id < 0 or mate_id >= _intent.size() or _intent[mate_id] == NONE:
		return
	_offered[mate_id] = 1
	_best_weight[mate_id] = maxf(_best_weight[mate_id], share)


static func _commit(ctx: SimContext, pid: int, kind: int, point: Vector3) -> void:
	_intent[pid] = kind
	_point[pid] = point
	_offered[pid] = 0
	_best_weight[pid] = 0.0
	_until[pid] = ctx.tick_index + int(float(HOLD_SECONDS[kind]) * float(SimConsts.TICK_HZ))
	_since[pid] = ctx.tick_index
	made[kind] += 1
	# A drift is stored as a displacement, so how far he is going to run is the
	# length of it rather than the distance to a point on the pitch.
	var dir := ctx.pitch.attack_dir(ctx.players[pid].team)
	if kind == SPACE:
		travel[kind] += point.length()
		forward[kind] += point.x * dir
	else:
		travel[kind] += ctx.players[pid].dist_to(point)
		forward[kind] += (point.x - ctx.players[pid].pos.x) * dir


## Retires every intent whose window has closed, and charges the player the rest
## that follows it. Losing the ball retires the lot: the question they were all
## answers to has gone away.
static func _expire(ctx: SimContext) -> void:
	for i in _intent.size():
		var kind: int = _intent[i]
		if kind == NONE:
			continue
		var p := ctx.players[i]
		if ctx.possession_team == p.team and ctx.tick_index < _until[i] and p.on_pitch:
			continue
		# Judged as it is retired: did the ball come to the man who went to ask
		# for it. A pass that arrives is the only thing any of these are for.
		#
		# A run the team's own turnover cut off mid-stride is counted apart from
		# one that simply was not found. They fail for opposite reasons and the
		# fix for one is no use against the other.
		if ctx.ball.last_touch_player == i and ctx.ball.last_touch_tick >= _since[i]:
			received[kind] += 1
		elif ctx.active_shot_tick >= _since[i]:
			# The possession ended in a shot while he was running. Whoever has the
			# ball now is a keeper who caught it or a defender who blocked it, and
			# counting that as the run being cut short is counting the attack
			# working as the attack failing.
			#
			# It is most of the number. `cut short` for a run past the last defender
			# read 81% and rose every time the engine got better at getting into the
			# box, which is the signature of an instrument measuring its own success.
			shot[kind] += 1
		elif ctx.possession_team != p.team:
			cut_short[kind] += 1
		# And what the man on the ball made of it while it lasted, which is the
		# half of the judgement `received` cannot make: a run that was never on
		# anybody's list and a run that was on every list and never chosen both
		# come back as "not found".
		offered[kind] += _offered[i]
		weight[kind] += _best_weight[i]
		_intent[i] = NONE
		var rest: float = float(REST_SECONDS[kind]) * lerpf(1.3, 0.7, p.attrs.work_rate)
		_ready[i] = ctx.tick_index + int(rest * float(SimConsts.TICK_HZ))


# --- The three ways of offering ---------------------------------------------


## Coming to meet the man on the ball: a point on the line between them, a
## supporting distance out, stepped off whoever is sitting on it.
static func _show_point(ctx: SimContext, p: SimPlayer, team: int, ball: Vector3) -> Vector3:
	var away := SimConsts.horizontal(p.pos - ball)
	var d := away.length()
	if d < SHOW_MIN or d > SHOW_MAX:
		return Vector3.INF
	var dir := away / d
	var point := ball + dir * SHOW_DISTANCE
	# Step across the line rather than along it: the angle opens, the distance
	# does not change, and he does not end up receiving it on the marker's toes.
	var marker := ctx.nearest_to(point, SimConsts.other_team(team))
	if marker != null and not marker.is_keeper and marker.dist_to(point) < SHOW_MARKED:
		var lateral := Vector3(-dir.z, 0.0, dir.x)
		var side: float = signf(lateral.dot(SimConsts.horizontal(point - marker.pos)))
		if is_zero_approx(side):
			side = 1.0
		point += lateral * side * SHOW_STEP
	return ctx.pitch.clamp_to_pitch(Vector3(point.x, 0.0, point.z), 1.5)


## Moving off into a pocket. A local ascent like the one in SimMovement, but
## over a value that includes whether the ball could be played there at all --
## which is the difference between finding space and standing in it.
##
## Probed around the station, so the pocket he finds is an offset from the shape
## and travels with it rather than a place he wanders off to and stays.
static func _space_point(ctx: SimContext, p: SimPlayer, team: int, ball: Vector3, base: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_value := -INF
	for i in SPACE_PROBES.size():
		var probe := ctx.pitch.clamp_to_pitch(base + ctx.pitch.orient(team, SPACE_PROBES[i]), 1.5)
		if SimConsts.horizontal_length(probe - ball) > RANGE:
			continue
		var v := _value_of(ctx, p, team, ball, probe, 0.5, SPACE_LANE_POWER)
		if v > best_value:
			best_value = v
			best = probe
	if best == Vector3.INF:
		return best
	# Handed back as a displacement from the station, not as a place to stand.
	return best - base


## Setting off past the last defender.
##
## The line is taken as this player believes it to be, not as it is, which is
## where being caught offside comes from. He must start from onside; the target
## is beyond the line, so whether he is onside when the ball is actually struck
## is a question about the release, and the referee answers it.
static func _behind_point(ctx: SimContext, p: SimPlayer, team: int, ball: Vector3, urgency: float) -> Vector3:
	if not SimRole.is_attacking(p.role) and p.role != SimRole.CM:
		return Vector3.INF
	if urgency > BEHIND_MAX_PRESSURE:
		return Vector3.INF
	if p.dist_to(ball) > BEHIND_RANGE:
		return Vector3.INF
	var dir := ctx.pitch.attack_dir(team)
	# Not worth it from deep in one's own half: the ball cannot be played that
	# far, and a striker who makes the run anyway has left the team a man short
	# for ninety minutes.
	if ball.x * dir < -ctx.pitch.half_length * 0.25:
		return Vector3.INF
	# Level with the ball or ahead of it. A run in behind from behind the ball is
	# a different move and one the overlap patterns already make.
	if (p.pos.x - ball.x) * dir < -8.0:
		return Vector3.INF
	var line := SimReferee.believed_offside_line(ctx, p) * dir
	if p.pos.x * dir > line + BEHIND_ONSIDE_SLACK:
		return Vector3.INF
	var depth: float = minf(line + BEHIND_DEPTH, ctx.pitch.half_length - 3.0)
	var run: float = depth - p.pos.x * dir
	# Long enough to be a run, short enough to be finished inside the window he
	# is committing to. A "run" he could never complete is a striker jogging
	# hopefully at a spot the ball has long since left.
	if run < 2.0 or run > BEHIND_MAX_RUN:
		return Vector3.INF
	# Into the channel he already occupies, drifting a little toward goal.
	var point := Vector3(depth * dir, 0.0, p.pos.z * 0.85)
	return ctx.pitch.clamp_to_pitch(point, 2.0)


# --- Shared valuation -------------------------------------------------------


## What it is worth to this team to have a man on the ball at `point`.
##
## Three things multiplied: whether the team wins that space, what the space is
## worth, and whether the ball could be got there. The third is what separates
## this from the plain value field -- a pocket with two opponents standing in
## the line to it is not an option, however much space is in it.
##
## `retain` scales the value of simply keeping the ball, which is what stops
## every short option scoring zero next to anything played forward. It is the
## same term, and the same reasoning, as `SimDecision.possession_value` -- and
## since that stopped being flat it also says that a man offering ahead of the
## ball is worth more than the same man offering behind it. That is the receiver's
## half of the same complaint the decision layer had: expected threat is flat in
## one's own half, so the only thing separating the pocket in front from the
## pocket behind was the open lane, and the lane behind the ball is always open.
static func _value_of(ctx: SimContext, p: SimPlayer, team: int, ball: Vector3, point: Vector3, retain: float, lane_power: float = 1.0) -> float:
	# A man who has to turn and travel is a later option than one already there.
	var arrival: float = SimValueField.time_to_arrive(p, point, 0.0)
	# Asked at the moment he would be standing there, not at this one.
	#
	# This is the argument `_behind_point` already makes and the reason it is
	# scored outside this function: pitch control asks who owns a patch of grass
	# *now*, and the answer for any patch worth running into is the opposition,
	# because space is the stuff nobody is standing in yet. Asked as a snapshot,
	# every probe that goes anywhere came back worse than the station -- a pocket
	# ten metres up the pitch is grass he does not own, and grass he does own is
	# the grass he is standing on. Multiply that by a lane term that is always
	# open behind the ball and a promptness term that always favours the nearer
	# point, and the layer was choosing where a man is *safest* rather than where
	# he is any use, three times over.
	#
	# Floored at his own arrival, everyone who can be there by then counts and so
	# does he, which is the question a run actually asks. It is the same
	# correction the carry and the knock past a man got in `SimDecision`.
	var control := ctx.value.control_at_local(ctx, point, team, arrival)
	var threat := ctx.value.xt_at(team, point, ctx.pitch) * ctx.tactics(team).focus_at(point.z, ctx.pitch)
	# `lane_power` is what stops availability eating danger. A clear line to the
	# ball is the whole point of coming short, so there it counts at full weight;
	# for a man drifting off his station it is a tiebreak between pockets, and at
	# full weight it walks him back into the safe empty grass behind the ball
	# every time, because that is where the lanes are always open.
	var lane := pow(_lane_open(ctx, ball, point, team), lane_power)
	# And a later option is still worth less to the man on the ball now.
	#
	# Softened from 0.35 once `control` started asking its question at `arrival`
	# too. The two were saying the same thing twice: a distant pocket was charged
	# for being distant in the control term -- where the defence had all that time
	# to get across -- and charged again here. Between them a fourteen-metre run
	# needed to be worth twice a two-metre shuffle before it was ever considered,
	# which no patch of midfield grass is.
	var promptness: float = 1.0 / (1.0 + arrival * PROMPTNESS_DECAY)
	return control * lane * (threat + SimDecision.possession_value(ctx, team, point) * retain) * promptness


## How open the line from the ball to a point is, as a fraction. Geometric and
## deliberately cheap: this runs over every probe of every candidate, and the
## interception model proper belongs to the pass that actually gets played.
static func _lane_open(ctx: SimContext, from: Vector3, to: Vector3, team: int) -> float:
	var seg := SimConsts.horizontal(to - from)
	var length: float = maxf(seg.length(), 0.1)
	var dir := seg / length
	var open := 1.0
	for oid in ctx.opponent_ids(team):
		var o := ctx.players[oid]
		if not o.on_pitch or o.is_keeper:
			continue
		var rel := SimConsts.horizontal(o.pos - from)
		var along: float = rel.dot(dir)
		if along <= 1.0 or along >= length:
			continue
		var lateral: float = absf(rel.x * -dir.z + rel.z * dir.x)
		if lateral >= LANE_WIDTH:
			continue
		open *= clampf(lateral / LANE_WIDTH, 0.15, 1.0)
	return open


## The runner's own race to a point: does he get there before the defence, given
## he sets off now and they react. The ball has to arrive too, so the defence is
## charged only with beating the later of the two.
static func _race(ctx: SimContext, p: SimPlayer, point: Vector3) -> float:
	var mine := SimValueField.time_to_arrive(p, point, 0.0)
	var ball_time: float = SimConsts.horizontal_length(point - ctx.ball.ground_pos()) / BEHIND_PASS_SPEED + 0.3
	mine = maxf(mine, ball_time)
	var theirs := INF
	for oid in ctx.opponent_ids(p.team):
		var o := ctx.players[oid]
		if not o.on_pitch:
			continue
		# The keeper counts. A ball rolled through to a runner the keeper reaches
		# first is a ball rolled through to the keeper.
		theirs = minf(theirs, SimValueField.time_to_arrive(o, point, SimValueField.reaction_of(o)))
	if is_inf(theirs):
		return 1.0
	return clampf(1.0 / (1.0 + exp(-(theirs - mine) / SimValueField.CONTROL_TAU)), 0.0, 1.0)


# --- State ------------------------------------------------------------------


static func _resize(n: int) -> void:
	_intent.resize(n)
	_point.resize(n)
	_until.resize(n)
	_ready.resize(n)
	_since.resize(n)
	_offered.resize(n)
	_best_weight.resize(n)
	_clear()


static func _clear() -> void:
	for i in _intent.size():
		_intent[i] = NONE
		_point[i] = Vector3.ZERO
		_until[i] = 0
		_ready[i] = 0
		_since[i] = 0
		_offered[i] = 0
		_best_weight[i] = 0.0
	made.resize(4)
	received.resize(4)
	cut_short.resize(4)
	travel.resize(4)
	forward.resize(4)
	offered.resize(4)
	weight.resize(4)
	shot.resize(4)
	for i in 4:
		made[i] = 0
		received[i] = 0
		cut_short[i] = 0
		travel[i] = 0.0
		forward[i] = 0.0
		offered[i] = 0
		weight[i] = 0.0
		shot[i] = 0
