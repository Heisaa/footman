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
##   box     -- attack the cross. The three targets are the three points
##              `SimDecision._add_crosses` aims at, and the trigger is that
##              function's own test on the ball, because a run to meet a ball
##              nobody is going to play is worse than holding shape.
##
## The four are scored in the same units as everything else in the engine --
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

enum { NONE, SHOW, SPACE, BEHIND, BOX, DECOY, SECOND }

const KIND_NAMES := ["none", "show", "space", "behind", "box", "decoy", "second"]

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
##
## Box was two and is three, because `_box_point` authors exactly three targets --
## near post, the penalty spot, far post -- and rationing them to two men is an
## inconsistency inside one mechanic rather than a judgement about eagerness. It
## only started to bite once the box run had a trigger that fired: with the old
## one it was a candidate on 0.1% of decisions and the ration never came up, and
## `and which idea he was allowed to have` now reads 18 blocked against 34 won.
## **Both rations are now measured** (2026-08-15, twenty seeds each), which they
## never had been -- `and which idea he was allowed to have` showed 88% of space
## picks and 86% of show picks winning their softmax and being dropped here, and
## nobody had asked whether that was right.
##
##   show 1 -> 2:   goals 4.45 to 3.52. **One is right.** A second man coming short
##                  is the midfield collapse the owner watched, arriving by quota
##                  instead of by score, and it agrees with his own words: one
##                  midfielder dropping to meet the defenders is fine.
##   space 3 -> 4:  shots 5.28 to 5.84, goals unchanged. Kept, on the same argument
##                  the constant was raised from two on -- more of the side moving
##                  is more of the side available -- and because the cost of being
##                  wrong is a man drifting rather than a man abandoning his post.
const QUOTA := [0, 1, 4, 2, 3, 1, 1]

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
const HOLD_SECONDS := [0.0, 3.0, 4.5, 4.0, 3.5, 3.0, 2.5]
## And the rest afterwards, before the same player will do it again. The sprint
## in behind is the expensive one and carries much the longest cooldown; without
## it a front three covers eighteen kilometres between them.
const REST_SECONDS := [0.0, 4.5, 4.0, 10.0, 7.0, 6.0, 3.0]

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
const PACE := [0.0, 0.62, 0.75, 0.97, 0.95, 0.9, 0.85]
const DEADBAND := [0.0, 1.5, 1.8, 1.0, 1.2, 1.5, 1.6]

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

## Check away and come back: how close a marker has to be for the check to be
## worth making, how far the wrong way it goes, how long it lasts, and the pace
## it is made at -- a walk-and-a-half, so the burst back reads as one.
const CHECK_MARKED := 4.5
const CHECK_AWAY := 3.0
const CHECK_SECONDS := 0.8
const CHECK_PACE := 0.5

## Timing the arrival at a cross: how far short of the spot a box runner holds
## until the ball is up, and the pace he holds there at.
const BOX_EASE := 6.0
## And how far short he holds once a man is wide on the ball with his head up.
## Near enough that the flight of the cross is the rest of his run.
const BOX_EASE_CROSS := 2.0
const BOX_EASE_PACE := 0.8
## How near the ball a man has to be for it to be his, for the release below.
##
## The same three metres `SimContext.update_possession` calls the ball leaving
## him, and asked here rather than reading `ctx.possession_player` because that
## field is -1 the moment an opponent is within 2.2 m of the ball. A full-back
## closing the man about to cross is the situation, not the absence of one, and
## it was reading as nobody being on the ball at all.
const CROSS_CARRIER_REACH := 3.0
## How long "a cross is coming" outlives the tick that said so.
##
## The run is committed seconds before the ball is struck and this was recomputed
## from nothing every tick, so a carrier a stride off the wide line -- or the
## strike itself, which takes the ball off him -- put the runner straight back to
## holding six metres short, including as the ball came down. Measured before it:
## the release fired on 2, 4 and 31 ticks of a match against 392, 702 and 508
## held.
const CROSS_COMING_HOLD := 1.0

## Live intent per player id, and where it is going. Flat arrays rather than
## dictionaries because the movement layer reads them for every player, every
## tick.
static var _intent := PackedInt32Array()
static var _point := PackedVector3Array()
static var _until := PackedInt32Array()
static var _ready := PackedInt32Array()
static var _since := PackedInt32Array()
## The check phase of a show: the point it goes to, and the tick it runs until.
static var _check_point := PackedVector3Array()
static var _check_until := PackedInt32Array()

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

## Which of the six ideas a man off the ball actually gets to have.
##
## Everything above counts runs that were *taken*: 35 in behind and 6 into the box
## in a match against 487 into space. That number cannot say which of three
## different things went wrong, and they want three different fixes — the option
## was never a candidate on the grass he was standing on, or it was a candidate
## and lost the softmax, or it won the softmax and was then refused by `QUOTA`
## because two men were already running. The last of those is silent: `_consider`
## files a pick and `_assign` drops it without anything being recorded.
##
## So, per kind, over every man considered on every assignment tick: how often the
## option existed at all, the share of the softmax it held while it did, how often
## it won, and how often winning was not enough.
##
## The same one-way contract as every other tally here — written as the engine
## picks, never read back, and it never touches `ctx.rng`.
static var chose_seen := PackedInt32Array()
static var chose_share := PackedFloat32Array()
static var chose_won := PackedInt32Array()
static var chose_blocked := PackedInt32Array()
static var chose_men := 0


## And, for the two kinds that are almost never on the list, which test refused
## them. Measured because `on the list 6%` names no line of code, and a gate
## upstream of every value knob is what this project has been caught by four
## times. Each man is filed under the first test he fails, in the order they are
## applied, so the rows read down like the function does.
const BEHIND_WHY := [
	"not his job", "under pressure", "too far from the ball", "ball too deep",
	"behind the ball", "already offside", "no run to make", "on the list",
]
const BOX_WHY := [
	"not his job", "too far from the ball", "not in their half", "already offside",
	"no point free for him", "on the list",
]
static var behind_why := PackedInt32Array()
static var box_why := PackedInt32Array()
## And which of the three he went to, when he went. Three points authored as the
## near post, the penalty spot and the far post are only three positions if the
## men actually spread across them; scored on his own race, every man can pick the
## same one and the box is one body deep.
const BOX_TARGETS := ["near post", "penalty spot", "far post"]
static var box_target := PackedInt32Array()
## And whether he is holding short of it or attacking it, which is `BOX_EASE`
## against `BOX_EASE_CROSS`. Counted because both halves of this timing have now
## been dead once each -- the ease unreachable behind the onside return, the
## trigger a float read as a truth value -- and a run to a point looks the same
## from outside either way.
const BOX_EASE_NAMES := ["holding", "attacking the cross"]
static var box_ease := PackedInt32Array()

## Drifts abandoned for a run, by the kind that was given up. A man mid-drift can
## change his mind and nothing else can, so this is the whole population of it --
## and zero here means the mechanic is dead rather than quiet.
static var switched := PackedInt32Array()


static func _note_choice(kind: int, total: float) -> void:
	chose_men += 1
	for i in KIND_NAMES.size():
		if _weights[i] <= 0.0:
			continue
		chose_seen[i] += 1
		chose_share[i] += _weights[i] / total
	if kind >= 0:
		chose_won[kind] += 1

## The same question asked of the two seconds after a regain, which is the only
## window three separate mechanics fire in.
##
## Everything above answers over a match, and a match is the wrong population for
## this. `break_bias`, `BREAK_RUN` and `secure` all live inside
## `SimDecision.REGAIN_WINDOW`, and "the counter is not on" has three causes that
## produce one number between them: nobody on the winning side is *eligible* to
## run, or they are eligible and the run scores badly, or they run and the man on
## the ball never picks them. They are fixed in three different files.
##
## So this is the eligibility gate in `_assign`, counted rather than reasoned
## about: for every man on the side in possession, the first of the gate's own
## tests he fails. `resting` is the one to read first, and it is indexed by the
## kind he is resting *from*, because `REST_SECONDS` charges 10 s for a run in
## behind and possession here changes every few seconds.
##
## Every count is a pair: `[0]` is the rest of the match and `[1]` is the window.
## A row on its own says nothing — two men of nine resting is only a tax on the
## counter if the same row reads lower when the counter is not on.
static var regain_passes := PackedInt32Array()
static var regain_men := PackedInt32Array()
static var regain_live := PackedInt32Array()
static var regain_resting := PackedInt32Array()
static var regain_rest_left := PackedFloat32Array()
static var regain_far := PackedInt32Array()
static var regain_held := PackedInt32Array()
static var regain_considered := PackedInt32Array()

## How much of its window a run had served when a turnover ended it, by kind, and
## how many of them there were.
##
## The quantity the fix in `_expire` would scale the rest by, measured before it
## is applied: a man charged 10 s for a run he made a fifth of is a man the engine
## has taken off the pitch for the next ten seconds on the strength of half a
## stride.
static var cut_served := PackedFloat32Array()
static var cut_n := PackedInt32Array()

## And what became of the runs that did begin inside the window: the same
## offered / best w / received split, over the offers that were made when the
## counter was on rather than over all of them.
static var born := PackedInt32Array()
static var born_offered := PackedInt32Array()
static var born_weight := PackedFloat32Array()
static var born_received := PackedInt32Array()

## The live half of those two, per player, reset at `_commit` and folded in at
## `_expire`.
static var _offered := PackedInt32Array()
static var _best_weight := PackedFloat32Array()

## Which kind each man is serving his rest for, and whether the run he is on now
## was begun inside a regain window. Both are for the tallies above and nothing
## in the football reads them.
static var _rest_kind := PackedInt32Array()
static var _born := PackedInt32Array()

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
## and diverged from the same seed run on its own. `docs/INVARIANTS.md` has it.
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
	# Check away and come back: for the first beat of a marked show, the point
	# is the check -- a few metres the wrong way, taking the marker with it --
	# and only then the ball. See `_commit`.
	if kind == SHOW and ctx.tick_index < _check_until[p.id]:
		return _check_point[p.id]
	# Timing the run in behind: the run itself goes at full depth -- a pass is
	# priced off a man already moving, and holding him at the line until the
	# ball was struck deadlocked the pair completely (measured: through balls
	# offered in 59% of runner decisions and played in none). What changes is
	# what he does when the ball has *not* come by the time he is over the
	# line: he checks back onside instead of standing beyond it waiting to be
	# flagged, and the next query sends him again. That is the arrival timed,
	# and it is also fewer offsides.
	# The same rule for the man attacking the box. `BOX_EASE` below already times
	# his *arrival*, and that is a different question from whether he is onside:
	# he can ease short of the six-yard box and still be a stride beyond the last
	# defender, which is the flag. Measured at n=20, offsides were running at 13.3
	# a team per football-90 against a §11 ceiling of 12, and the two runs that
	# were given triggers this week are the two that go past the line.
	#
	# The two are applied in that order and not as alternatives. Written as an
	# early return for the onside case, this branch answered for every box runner
	# who was not the man the ball in flight was for -- which is all of them, most
	# ticks -- and `BOX_EASE` below was never reached at all. Probed: nought ticks
	# of either arm over three matches. A dead mechanic reads as a live one in
	# every diagnostic, because a run to a point is a run to a point.
	var point := _point[p.id]
	# Timing the arrival at a cross: until the ball is up, he holds short of the
	# spot -- arriving as the ball does, not standing on the six-yard line
	# waiting for it.
	if kind == BOX and ctx.ball.grounded:
		var d2 := ctx.pitch.attack_dir(p.team)
		# Unless the man wide has the ball and is about to hit it, in which case
		# the run is already late: measured, the man a cross was aimed at was 8 to
		# 16 m off it when it came down, and six of those metres were this line.
		var coming := _cross_coming(ctx, p.team)
		box_ease[1 if coming else 0] += 1
		var ease: float = BOX_EASE_CROSS if coming else BOX_EASE
		point -= Vector3(d2 * ease, 0.0, 0.0)
	if (kind == BEHIND or kind == BOX) and ctx.ball.intended_target != p.id:
		var dir := ctx.pitch.attack_dir(p.team)
		var line: float = SimReferee.believed_offside_line(ctx, p) * dir
		if p.pos.x * dir > line - ONSIDE_MARGIN:
			return Vector3((line - ONSIDE_MARGIN) * dir, 0.0, point.z)
	return point


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
	# A man a pattern is running is a man with a destination, and this did not
	# know it. `_assign` skips anyone `SimPatterns.movement_override` has an
	# opinion about, so his intent stays `NONE`, so this returned `INF`, so
	# `_shortlist` ranked him on the grass he was leaving and `_lead_point` aimed
	# at dead reckoning off the velocity he happened to have. The pattern sent him
	# somewhere and then hid where from the only man who could find him.
	#
	# Measured on the third man, which is the pattern that shows it worst: 71
	# firings across both sides in a match, the ball it wants on the list 29.8% of
	# the time — a better rate than the run in behind manages — and **not one
	# success**. The move is generated, offered and aimed at the wrong yard.
	#
	# It goes first because it outranks the off-ball layer by construction: the
	# override is why he has no intent to read.
	var override := SimPatterns.movement_override(ctx, p)
	if not is_inf(override.x):
		return override
	match intent_of(ctx, p):
		SHOW, BEHIND, BOX, SECOND:
			return _point[p.id]
		SPACE:
			return SimMovement.shape_position(ctx, p) + _point[p.id]
		_:
			# A decoy is the one run not made to receive, so it is not a
			# destination the passer is offered.
			return Vector3.INF


static func pace_for(ctx: SimContext, p: SimPlayer) -> float:
	var kind := intent_of(ctx, p)
	# The check is made at a walk-and-a-half; the come-back is the sprint. A
	# box runner eases until the ball is up, then attacks it.
	if kind == SHOW and ctx.tick_index < _check_until[p.id]:
		return CHECK_PACE
	if kind == BOX and ctx.ball.grounded and not _cross_coming(ctx, p.team):
		return BOX_EASE_PACE
	return PACE[kind]


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

## The same idea for the break, and stronger, because it is the whole side
## rather than one man and because it lasts two seconds rather than a window.
## `SimDecision.break_bias` is the pass half; this is the run half, and neither
## does anything without the other -- lifting the pass alone moved through balls
## from 39 to 40 on seed 7, because a through ball is only generated for a mate
## already moving in behind and two seconds after a regain nobody was.
##
## Since measured, in `The two seconds after a regain`: a man in the window takes a
## run three times as often per assignment pass as he does in settled play, so this
## lift is reaching the pick. It cannot change *which* run he takes, because it
## multiplies BEHIND and SPACE by the same number, and space is what he mostly
## takes -- 385 to 15 on seed 7.
const BREAK_RUN := 3.0
## And what the pressure gate below relaxes to while it is on. A regain happens
## in the most crowded pocket on the pitch, so `BEHIND_MAX_PRESSURE` refuses the
## run at exactly the moment football makes it. The gate is right in settled
## play -- a striker peeling off under pressure with no way of reaching him is a
## man lost -- and the counter is the case it was not written for.
const BEHIND_MAX_PRESSURE_BREAK := 2.2


## 1 while the ball is on its way to the man he gave it to, then decaying to 0
## across the window.
##
## The run half of the one-two, and it holds rather than decaying during the
## flight for the same reason the pass half now starts at the arrival: a window
## measured from the strike is mostly spent by the time there is anybody to give
## it back to, and both halves were reaching that moment at nothing. He plays it
## and he goes; the clock on the pair starts when the ball gets there.
static func _just_passed(ctx: SimContext, p: SimPlayer) -> float:
	if ctx.last_pass_from != p.id:
		return 0.0
	if ctx.last_pass_arrival_tick < ctx.last_pass_tick:
		# Still travelling. Worth the full run until somebody other than the man
		# it was played to touches it, which is the ball being cut out.
		return 1.0 if ctx.ball.last_touch_player == p.id else 0.0
	var elapsed := float(ctx.tick_index - ctx.last_pass_arrival_tick) / float(SimConsts.TICK_HZ)
	if elapsed < 0.0 or elapsed > SimDecision.GIVE_AND_GO_WINDOW:
		return 0.0
	return 1.0 - elapsed / SimDecision.GIVE_AND_GO_WINDOW


# --- Assignment -------------------------------------------------------------


static func _assign(ctx: SimContext, team: int, carrier: int) -> void:
	var ball := ctx.ball.ground_pos()
	var urgency := ctx.pressure_on(ctx.players[carrier])
	# The same window the pass half of the counter is priced in, read off the same
	# function, so the two halves cannot disagree about when it is open.
	var in_window := SimDecision.regain_urgency(ctx, ctx.players[carrier]) > 0.0
	_sample_regain(ctx, team, carrier, ball, 1 if in_window else 0)
	# One gather for the whole pass: every point considered below is within a
	# few metres of somebody in this set, so the same handful of players decides
	# all of them.
	ctx.value.begin_local(ctx, ball, LOCAL_RADIUS)

	# Runs already under way consume the quota before anyone new is considered.
	# Sized from the kinds rather than by hand: written out as four zeroes, adding
	# a fifth intent left this one behind and every assignment pass threw an
	# out-of-bounds error to stderr, so the new run was scored, won its softmax
	# six times over, and was never once committed.
	var used := PackedInt32Array()
	used.resize(KIND_NAMES.size())
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
		# **A commitment is not a blindfold, and it was.** A man already offering
		# something was never reconsidered until his window ran out, so a drift
		# into space -- 4.5 s of it -- blindfolded him to everything that
		# happened in between. Measured over ten match-minutes: at the 104 ticks
		# where a man of ours was wide on the ball with a cross on, the box run
		# was offered to **nobody at all**, and `_box_point` was reached five
		# times in the whole window because eight of ten men were mid-drift. The
		# run into the box is offered four to six times a *match* for the same
		# reason.
		#
		# So a drift can be abandoned and a run cannot: `SPACE` is a few metres
		# off a station he is still holding, and the two things worth abandoning
		# it for are the two runs that are about a moment rather than a position.
		# `_consider` enforces which, and the rest below is untouched -- a man
		# recovering from a sprint stays recovering.
		var live: int = _intent[pid]
		if live != NONE and live != SPACE:
			continue
		if ctx.tick_index < _ready[pid]:
			continue
		if p.dist_to(ball) > RANGE:
			continue
		# A pattern already has this man running somewhere specific. Two ideas
		# about where one player should be is one too many.
		if SimPatterns.movement_override(ctx, p) != Vector3.INF:
			continue
		_consider(ctx, p, team, carrier, ball, urgency, live)

	# The quota goes to whoever gains most by running, not to whoever the loop
	# reached first.
	for i in _pick_ids.size():
		var kind: int = _pick_kinds[i]
		if used[kind] >= int(QUOTA[kind]):
			chose_blocked[kind] += 1
			continue
		var pid: int = _pick_ids[i]
		# He was drifting and is now running. The drift is retired properly so
		# every tally it feeds is closed the way a lapsed one is, and without the
		# rest a finished run earns: he is not stopping, he is going somewhere
		# better.
		if _intent[pid] != NONE:
			switched[_intent[pid]] += 1
			_retire(ctx, pid, false)
			used[SPACE] = maxi(used[SPACE] - 1, 0)
		used[kind] += 1
		_commit(ctx, pid, kind, _pick_points[i], in_window)


## Who on the winning side could have offered anything, in the seconds after the
## regain. See `regain_passes`.
##
## The tests are the eligibility gate of the loop below, in the gate's own order,
## and each man is counted against the first one he fails. Reading the raw
## `_intent` rather than `intent_of` is deliberate: `_expire` has just run on this
## tick, so the raw array is what the gate itself sees.
static func _sample_regain(ctx: SimContext, team: int, carrier: int, ball: Vector3, w: int) -> void:
	var kinds := KIND_NAMES.size()
	regain_passes[w] += 1
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if pid == carrier or p.is_keeper or not p.on_pitch:
			continue
		regain_men[w] += 1
		if _intent[pid] != NONE:
			regain_live[w * kinds + _intent[pid]] += 1
		elif ctx.tick_index < _ready[pid]:
			regain_resting[w * kinds + _rest_kind[pid]] += 1
			regain_rest_left[w] += float(_ready[pid] - ctx.tick_index) / float(SimConsts.TICK_HZ)
		elif p.dist_to(ball) > RANGE:
			regain_far[w] += 1
		elif SimPatterns.movement_override(ctx, p) != Vector3.INF:
			regain_held[w] += 1
		else:
			regain_considered[w] += 1


## Scores this player's options, picks one by softmax, and files it against the
## quota. Filing rather than committing, because how good the idea is decides
## who gets to act on it.
static func _consider(ctx: SimContext, p: SimPlayer, team: int, carrier: int, ball: Vector3, urgency: float, live: int = NONE) -> void:
	if _scores.size() != KIND_NAMES.size():
		_scores.resize(KIND_NAMES.size())
		_points.resize(KIND_NAMES.size())
		_weights.resize(KIND_NAMES.size())
	for i in KIND_NAMES.size():
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

	var breaking := _break_lift(ctx, team, carrier)
	var behind := _behind_point(ctx, p, team, ball, urgency, breaking)
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

	# Attacking the cross, and it is scored as neither pitch control nor a race.
	#
	# Both of those ask who beats whom to the spot, and for a point in the
	# six-yard area the answer is always the defence, because they are already
	# standing on it. Scored as a race it came back at 0.00001 and **no player
	# attacked a cross in thirty minutes of football across three seeds** -- the
	# run existed and was never once taken.
	#
	# That is the wrong question about the act. Nobody arrives at a cross first;
	# a cross is a contested ball in the air, and what decides it is being there
	# when it lands and being able to attack it when you are. Which is the same
	# pair `_lofted_success` prices from the other side -- arrival, then aerial
	# ability -- rather than a foot race nobody wins.
	var box := _box_point(ctx, p, team, ball)
	if box != Vector3.INF:
		var aerial: float = lerpf(0.35, 0.85, (p.attrs.heading + p.attrs.jumping) * 0.5)
		_scores[BOX] = ctx.value.xt_at(team, box, ctx.pitch) * _box_reach(p, box) * aerial \
			* ctx.tactics(team).direct_bias() * ctx.tactics(team).focus_at(box.z, ctx.pitch)
		_points[BOX] = box

	# The decoy: a run made where the ball will not go, worth exactly as much
	# as the marker it takes with it. Scored on how tightly he is marked --
	# an unmarked man dragging nobody is not a decoy, he is lost -- times the
	# threat of the ground he darts across, which is what makes his marker
	# follow. Not offered to the passer (`destination_for`), so it is the one
	# run in the layer that cannot be judged by `received`; `made` is its row.
	var decoy := _decoy_point(ctx, p, team, ball)
	if decoy != Vector3.INF:
		var marker := ctx.nearest_to(p.pos, SimConsts.other_team(team))
		if marker != null and not marker.is_keeper:
			var marked: float = clampf(1.0 - marker.dist_to(p.pos) / DECOY_MARKED, 0.0, 1.0)
			if marked > 0.0:
				# `teamwork` is what the attribute is for, and until now nothing on
				# the pitch read it (`docs/THE_FOOTBALL.md` 14). The decoy is the one
				# run in this file made entirely for somebody else — it is not
				# offered to the passer at all — so willingness to make it is
				# exactly the quantity the attribute names.
				var willing: float = lerpf(0.55, 1.35, p.attrs.teamwork)
				_scores[DECOY] = ctx.value.xt_at(team, decoy, ctx.pitch) * marked \
					* DECOY_WORTH * willing \
					* ctx.tactics(team).focus_at(decoy.z, ctx.pitch)
				_points[DECOY] = decoy

	# The second ball: with a long ball of ours in the air toward a contested
	# drop, somebody stands underneath the duel. Worth the ball itself -- most
	# knock-downs and half-clearances die a few metres short of the contest,
	# and the man already standing there owns them.
	var second := _second_ball_point(ctx, p, team)
	if second != Vector3.INF:
		_scores[SECOND] = _worth_at(ctx, team, second) * SECOND_WORTH
		_points[SECOND] = second

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

	# And the break, which is the same shape applied to the whole side. Both
	# options are non-negative here too, so the lift cannot turn a bad idea into
	# a good one -- it decides who gets the quota, not whether running is on.
	if breaking > 0.0:
		var blift: float = lerpf(1.0, BREAK_RUN, breaking)
		if not is_inf(_scores[BEHIND]):
			_scores[BEHIND] *= blift
		if not is_inf(_scores[SPACE]):
			_scores[SPACE] *= blift

	# Softmax, never argmax, and the temperature is relative to the spread of
	# the scores rather than absolute -- they are goal probabilities and often
	# span less than a hundredth.
	var best := -INF
	var worst := INF
	for i in KIND_NAMES.size():
		if is_inf(_scores[i]):
			continue
		best = maxf(best, _scores[i])
		worst = minf(worst, _scores[i])
	if is_inf(best):
		return
	var temperature: float = lerpf(TEMP_POOR, TEMP_GOOD, p.attrs.decisions) * maxf(best - worst, 1e-5)
	for i in KIND_NAMES.size():
		_weights[i] = 0.0 if is_inf(_scores[i]) else exp((_scores[i] - best) / temperature)
	var kind: int = maxi(ctx.rng.weighted_index(_weights), 0)
	# Counted before the NONE return, because "he held still" is one of the six
	# answers and dropping it makes every share below add up against the wrong
	# denominator.
	var total := 0.0
	for i in KIND_NAMES.size():
		total += _weights[i]
	if total > 0.0:
		_note_choice(kind, total)
	if kind == NONE:
		return
	# What a man already drifting is allowed to change his mind to. Anything else
	# -- including another drift -- would let him restart his own window every
	# fifth of a second, and every tally that counts a run from `_since` would be
	# counting one run as twenty.
	if live != NONE and kind != BOX and kind != BEHIND:
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


## A run authored from outside the assignment loop: `SimScenarios` planting a
## situation's premise. A scenario that fakes a run with a velocity gives
## `destination_for` nothing to read, so the first off-ball retarget puts the
## man back on his station and the premise dies before the ball is struck --
## and the decision layer's "is he moving on" gate dies with it. This writes
## the state `_commit` would have, so the run is committed, held for its
## window, skipped by reassignment like any live run, and judged by the same
## tallies. Scenarios only; a match never calls it.
static func plant(ctx: SimContext, p: SimPlayer, kind: int, point: Vector3, seconds: float) -> void:
	if _intent.size() != ctx.players.size():
		_resize(ctx.players.size())
	_intent[p.id] = kind
	_point[p.id] = point
	_offered[p.id] = 0
	_best_weight[p.id] = 0.0
	_born[p.id] = 0
	_check_until[p.id] = 0
	_until[p.id] = ctx.tick_index + int(seconds * float(SimConsts.TICK_HZ))
	_since[p.id] = ctx.tick_index
	made[kind] += 1


static func _commit(ctx: SimContext, pid: int, kind: int, point: Vector3, in_window: bool = false) -> void:
	_intent[pid] = kind
	_point[pid] = point
	_offered[pid] = 0
	_best_weight[pid] = 0.0
	# Check away and come back. Only a marked man has anybody to lose: the
	# check drags the marker the wrong way for a beat, and the burst back to
	# the show point is what arrives free. Unmarked, he just comes.
	_check_until[pid] = 0
	if kind == SHOW:
		var mover := ctx.players[pid]
		var marker := ctx.nearest_to(mover.pos, SimConsts.other_team(mover.team))
		if marker != null and not marker.is_keeper and marker.dist_to(mover.pos) < CHECK_MARKED:
			var away := SimConsts.horizontal(mover.pos - ctx.ball.ground_pos())
			if away.length() > 0.5:
				_check_point[pid] = ctx.pitch.clamp_to_pitch(
					mover.pos + away.normalized() * CHECK_AWAY, 1.5)
				_check_until[pid] = ctx.tick_index + int(CHECK_SECONDS * float(SimConsts.TICK_HZ))
	_born[pid] = 1 if in_window else 0
	if in_window:
		born[kind] += 1
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
##
## **A run a turnover ended is not a run he finished**, and the rest is charged in
## proportion to how much of it he made. Losing the ball retires every intent
## instantly, so before this a man whose idea was cut off after half a second paid
## the same four to ten seconds as a man who had sprinted a full window — and
## possession here changes every few seconds. Measured over ten minutes on seed 7,
## a run a turnover ended had served 52% of its window and was charged all of
## `REST_SECONDS` for it, with two men of nine sitting out any given assignment
## pass. It is the more honest physiology as well as the thing that puts bodies
## back on the pitch: a run that was run pays for itself, a run that was called
## off does not.
static func _expire(ctx: SimContext) -> void:
	for i in _intent.size():
		var kind: int = _intent[i]
		if kind == NONE:
			continue
		var p := ctx.players[i]
		if ctx.possession_team == p.team and ctx.tick_index < _until[i] and p.on_pitch:
			continue
		_retire(ctx, i)


## Closes one offer and files what it was worth.
##
## Split out of `_expire` because an offer now ends two ways: its window runs out,
## or the man abandons it for a run (`_assign`). Both have to close the same
## tallies or `received` and `cut short` start describing different populations.
## `rest` is the difference between them -- a lapsed run has been made and earns
## its recovery, and a drift given up halfway has not.
static func _retire(ctx: SimContext, i: int, rest_after := true) -> void:
	var kind: int = _intent[i]
	if kind == NONE:
		return
	var p := ctx.players[i]
	if true:
		# Judged as it is retired: did the ball come to the man who went to ask
		# for it. A pass that arrives is the only thing any of these are for.
		#
		# A run the team's own turnover cut off mid-stride is counted apart from
		# one that simply was not found. They fail for opposite reasons and the
		# fix for one is no use against the other.
		var served: float = clampf(float(ctx.tick_index - _since[i])
			/ maxf(float(HOLD_SECONDS[kind]) * float(SimConsts.TICK_HZ), 1.0), 0.0, 1.0)
		var got_it := ctx.ball.last_touch_player == i and ctx.ball.last_touch_tick >= _since[i]
		if got_it:
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
			cut_served[kind] += served
			cut_n[kind] += 1
		# And what the man on the ball made of it while it lasted, which is the
		# half of the judgement `received` cannot make: a run that was never on
		# anybody's list and a run that was on every list and never chosen both
		# come back as "not found".
		offered[kind] += _offered[i]
		weight[kind] += _best_weight[i]
		if _born[i] == 1:
			born_offered[kind] += _offered[i]
			born_weight[kind] += _best_weight[i]
			born_received[kind] += 1 if got_it else 0
		_intent[i] = NONE
		_born[i] = 0
		if not rest_after:
			return
		var rest: float = float(REST_SECONDS[kind]) * served * lerpf(1.3, 0.7, p.attrs.work_rate)
		_ready[i] = ctx.tick_index + int(rest * float(SimConsts.TICK_HZ))
		_rest_kind[i] = kind


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
	# The lane, not just the marker. The filter on support measured as almost
	# entirely the lane --
	# the men were there and unmarked, and the ball could not reach them. So a
	# man showing into a blocked line takes one more lateral step, to whichever
	# side opens it. The quota is untouched: this is effort from the men
	# already coming, not more men coming.
	if _lane_open(ctx, ball, point, team) < 0.7:
		var across := Vector3(-dir.z, 0.0, dir.x) * SHOW_STEP
		var left := point + across
		var right := point - across
		point = left if _lane_open(ctx, ball, left, team) >= _lane_open(ctx, ball, right, team) \
			else right
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
	# Drop into the pocket between the lines: the one probe that is aimed at
	# the opponents' shape rather than at fixed offsets from his own.
	var pocket := _pocket_point(ctx, p, team, base)
	if pocket != Vector3.INF and SimConsts.horizontal_length(pocket - ball) <= RANGE:
		# The first man into the pocket is worth far more than the second, and the
		# value function cannot say so: it prices a patch of grass, and the grass
		# between the lines is just as good whether or not a teammate is already
		# standing in it. So a side with nobody linking and a side with two both
		# read the same, and the layer fills the pocket or leaves it empty by
		# accident.
		#
		# The owner's ask (2026-08-15) is exactly this shape: "one midfielder
		# dropping to meet the defenders is fine; there have to be link players."
		# Coming short is already rationed to one by `QUOTA`; being *between the
		# lines* was rationed by nothing and valued as ordinary space. Measured,
		# 78% of touches were in the middle third and 12% in the final third.
		#
		# Stated as a lift on the empty pocket rather than a quota, because the
		# football is that the pocket is worth occupying, not that a second man
		# there is illegal -- and because a lift keeps it a value the softmax can
		# still lose.
		var lift := POCKET_LIFT
		if not _anyone_between_the_lines(ctx, team, p.id, pocket):
			lift = POCKET_LIFT_FIRST
		var pv := _value_of(ctx, p, team, ball, pocket, 0.5, SPACE_LANE_POWER) * lift
		if pv > best_value:
			best_value = pv
			best = pocket
	if best == Vector3.INF:
		return best
	# Handed back as a displacement from the station, not as a place to stand.
	return best - base


## How much of a break is on for this side, read off the man who won the ball.
##
## `SimDecision.break_on` is the one measurement, so the pass and the run cannot
## disagree about whether the counter is available: it is the regain window
## times how far up the pitch the side that just lost it had committed. Nobody
## exposed, no break, and the whole thing is a no-op.
static func _break_lift(ctx: SimContext, team: int, carrier: int) -> float:
	if carrier < 0 or carrier >= ctx.players.size():
		return 0.0
	var c := ctx.players[carrier]
	if c.team != team:
		return 0.0
	return SimDecision.break_on(ctx, c, SimDecision.regain_urgency(ctx, c))


## Setting off past the last defender.
##
## The line is taken as this player believes it to be, not as it is, which is
## where being caught offside comes from. He must start from onside; the target
## is beyond the line, so whether he is onside when the ball is actually struck
## is a question about the release, and the referee answers it.
static func _behind_point(ctx: SimContext, p: SimPlayer, team: int, ball: Vector3, urgency: float, breaking: float = 0.0) -> Vector3:
	if not SimRole.is_attacking(p.role) and p.role != SimRole.CM:
		behind_why[0] += 1
		return Vector3.INF
	if urgency > lerpf(BEHIND_MAX_PRESSURE, BEHIND_MAX_PRESSURE_BREAK, breaking):
		behind_why[1] += 1
		return Vector3.INF
	if p.dist_to(ball) > BEHIND_RANGE:
		behind_why[2] += 1
		return Vector3.INF
	var dir := ctx.pitch.attack_dir(team)
	# Not worth it from deep in one's own half: the ball cannot be played that
	# far, and a striker who makes the run anyway has left the team a man short
	# for ninety minutes.
	if ball.x * dir < -ctx.pitch.half_length * 0.25:
		behind_why[3] += 1
		return Vector3.INF
	# Level with the ball or ahead of it. A run in behind from behind the ball is
	# a different move and one the overlap patterns already make.
	if (p.pos.x - ball.x) * dir < -8.0:
		behind_why[4] += 1
		return Vector3.INF
	var line := SimReferee.believed_offside_line(ctx, p) * dir
	if p.pos.x * dir > line + BEHIND_ONSIDE_SLACK:
		behind_why[5] += 1
		return Vector3.INF
	var depth: float = minf(line + BEHIND_DEPTH, ctx.pitch.half_length - 3.0)
	var run: float = depth - p.pos.x * dir
	# Long enough to be a run, short enough to be finished inside the window he
	# is committing to. A "run" he could never complete is a striker jogging
	# hopefully at a spot the ball has long since left.
	if run < 2.0 or run > BEHIND_MAX_RUN:
		behind_why[6] += 1
		return Vector3.INF
	# Into the channel he already occupies, drifting a little toward goal.
	behind_why[7] += 1
	var point := Vector3(depth * dir, 0.0, p.pos.z * 0.85)
	return ctx.pitch.clamp_to_pitch(point, 2.0)


## How far a man will run to attack a cross, and how far from the ball he can be
## and still be part of the move.
const BOX_MAX_RUN := 26.0
const BOX_RANGE := 42.0
## Whether he is there for it: 1 if he arrives inside the window, decaying to 0
## across `BOX_LATE`. One function, so the target he picks and the score the run
## gets are the same question asked once.
static func _box_reach(p: SimPlayer, point: Vector3) -> float:
	var arrive := SimValueField.time_to_arrive(p, point, 0.0)
	return clampf(1.0 - maxf(arrive - BOX_WINDOW, 0.0) / BOX_LATE, 0.0, 1.0)


## How long a man has to get there, from the moment he sets off.
##
## Not the flight of the cross, and that mistake cost a whole measurement: scored
## against the flight alone -- about 1.25 s -- the run was worthless to anybody
## further than a dozen metres out, and the gate opened 29 times a match while
## **no player ever attacked a cross**. A run into the box is made before the
## ball is struck. The striker goes when he sees the winger's head come up, and
## what he has is that lead plus the flight.
const BOX_WINDOW := 3.0
## And how much later than that a run is still worth making. A ball at the back
## post is often met by a man still running on to it.
const BOX_LATE := 1.2


## Where a man attacks a cross.
##
## The other half of `SimDecision._add_crosses`, and neither is worth anything
## without it. The cross was built to be aimed at the grass rather than at a
## shirt, precisely so it would not need a body standing in the area first --
## but a ball into an area with nobody arriving is still a ball to the
## goalkeeper, and that is what it measured: eleven crosses over three seeds,
## one completed, no shots, with 0.12 players beyond the last defender at any
## moment in the match.
##
## So this is the run that meets it, and the geometry is deliberately the same
## geometry. The three targets are the three the cross is aimed at, and the
## situation that triggers the run is the situation that generates the ball:
## a teammate on it, wide, in the final third.
##
## **The three points are claimed, one man each, and that is the other half of
## `docs/THE_FOOTBALL.md` 29.** Each man scoring his own race was the first
## version, on the argument that the near man would win the near post and the far
## man the far one without anybody coordinating them. Measured, they do spread --
## near post 33-38%, penalty spot around half, far post 15% -- but that is a tally
## over a match and not over a moment: nothing stopped two men racing the same
## point at the same time, and nothing sent anybody to the far post when the spot
## was worth more to all of them. Half of every run went to the penalty spot,
## which is eleven metres, and a headed attempt was struck from a median of twelve.
##
## Football authors the box: one man attacks the near post, one the spot, one the
## far post, and the value of each is that the *set* is covered rather than that
## the point is worth more than the grass beside it. So the assignment is made
## once for the side, best pair first, and each man reads off his own share of it
## -- a pure function of where everybody is standing, so every man computes the
## same one and nobody needs to be told.
static func _box_point(ctx: SimContext, p: SimPlayer, team: int, ball: Vector3) -> Vector3:
	if not SimRole.is_attacking(p.role) and p.role != SimRole.CM:
		box_why[0] += 1
		return Vector3.INF
	if p.dist_to(ball) > BOX_RANGE:
		box_why[1] += 1
		return Vector3.INF
	var dir := ctx.pitch.attack_dir(team)
	# The ball in the final third, and that is the whole trigger.
	#
	# It used to be `_add_crosses`'s own test — final third *and* wide — on the
	# argument that a run to meet a ball nobody is going to play is worse than
	# holding shape. Measured, that argument was being made twice. `and which idea
	# he was allowed to have` says the box run was a candidate on 0.1% of the
	# 7824 men considered in a match and that **every man whose job it was, was
	# refused here**: 43% of all of them, against 57% taken by the role test above
	# and nothing left over. Six box runs got made in ninety-three minutes, and the
	# opposition area saw 4.6 touches a team against football's rough 25.
	#
	# And the argument it was making is already made, better, one layer down: the
	# run is scored against `none`, which is holding station and is a candidate
	# 100% of the time, and `QUOTA` allows two. Whenever the option did survive to
	# be scored it took 97.2% of the softmax and won — the value layer has never
	# disagreed that attacking the box is the right idea, it was only ever asked in
	# the one situation where the ball was already going there.
	#
	# So the width test goes and the third stays. A cross is one ball that finds a
	# man in the six-yard box; the cutback, the second ball and the through ball
	# are the others, and none of them starts wide.
	#
	# **And now the third goes too, for the same reason, one measurement later.**
	# At the third the run reached the list on 0.6% of the men considered in a full
	# match and **won 90.3% of the times it got there**: the value layer has never
	# once disagreed, and the only thing deciding whether a man attacks the box was
	# this line. The gate it was making is a timing argument -- do not set off
	# before there is a ball to attack -- and timing is what `_box_reach` prices,
	# with a window that scores a man at zero if he cannot be there inside
	# `BOX_WINDOW` plus `BOX_LATE`. A man on halfway is refused by that on his legs
	# rather than by a line on the pitch, which is the right refusal: it is his
	# distance from the six-yard box that decides, not the ball's.
	#
	# The football says the same. The striker goes when he sees the winger's head
	# come up, and the winger's head comes up before he crosses the line into the
	# final third -- a run started only once the ball is 35 m from goal is a run
	# started too late, which is `docs/THE_FOOTBALL.md` 29 and the 13 m median a
	# headed attempt is struck from.
	if ball.x * dir <= 0.0:
		box_why[2] += 1
		return Vector3.INF
	# Not from a standing start beyond the last man: that is not attacking a
	# cross, it is waiting offside for one.
	var line := SimReferee.believed_offside_line(ctx, p) * dir
	if p.pos.x * dir > line + BEHIND_ONSIDE_SLACK:
		box_why[3] += 1
		return Vector3.INF
	var claims := _box_claims(ctx, team, ball)
	if not claims.has(p.id):
		box_why[4] += 1
		return Vector3.INF
	var claim: Array = claims[p.id]
	box_why[5] += 1
	box_target[int(claim[1])] += 1
	return ctx.pitch.clamp_to_pitch(claim[0], 2.0)


## What the run into the box is worth when there is a man wide with the ball,
## about to cross it, against when there is not.
##
## This is the trigger the box run used to carry as a *gate* -- `_add_crosses`'s
## own test, a teammate on it, wide, in the final third -- and removing it was
## right: it refused every man whose job it was, and a cross is not the only ball
## that finds the six-yard box. Removing it also disconnected the two, and the
## measurement says so: box runs went from 6 a match to 44-77, and **the man a
## cross was aimed at was 6 to 16 m off it when it came down**, because the run
## and the ball were being decided in different moments.
##
## So the same fact, kept as timing rather than as worth. Priced -- the run into
## the box lifted while a man is wide -- it was measured at 6 headed attempts for
## 23 shots and 13 goals and struck; `docs/THE_FOOTBALL.md`, the knobs. What is
## left is when the striker goes: he sets off as the winger's head comes up, and
## on any other phase he holds, because where a man should be standing is not what
## a value knob answers.
## Latched per side, because the question is about a moment and the answer was
## being thrown away every tick. `reset` clears it.
static var _cross_tick := [-1, -1]
static var _cross_until := [-1, -1]


static func _cross_coming(ctx: SimContext, team: int) -> bool:
	if _cross_tick[team] != ctx.tick_index:
		_cross_tick[team] = ctx.tick_index
		if _wide_on_the_ball(ctx, team):
			_cross_until[team] = ctx.tick_index \
				+ int(CROSS_COMING_HOLD * float(SimConsts.TICK_HZ))
	return ctx.tick_index <= int(_cross_until[team])


## A man of this side on the ball, wide, in the final third.
##
## The gates are `_add_crosses`'s own and are asked of the ball rather than of
## the man, for the reason they are there: the cross is generated from where the
## ball is.
static func _wide_on_the_ball(ctx: SimContext, team: int) -> bool:
	var carrier := ctx.ball.last_touch_player
	if carrier < 0 or carrier >= ctx.players.size():
		return false
	var c: SimPlayer = ctx.players[carrier]
	if c.team != team or c.is_keeper or not c.on_pitch:
		return false
	var at := ctx.ball.ground_pos()
	if c.dist_to(at) > CROSS_CARRIER_REACH:
		return false
	if at.x * ctx.pitch.attack_dir(team) <= ctx.pitch.half_length / 3.0:
		return false
	return absf(at.z) > ctx.pitch.half_width * SimDecision.CROSS_WIDE


## Where the near and far balls are put, as fractions of the six-yard box -- so
## they scale with the pitch, and so they can be named: the near one is across
## the near corner of it, the far one hangs past the far post.
##
## **They used to be the posts themselves**, 3.7 m either side of the middle and
## five and eight metres off the line, which is inside the goal frame. A ball
## nobody met came down in the goal mouth in front of the keeper, and that is
## what it looked like -- *aimed too much towards the goal, so it reads like a
## weak shot* (owner, 2026-08-23). The points are outside the frame now and the
## ball crosses the face of goal instead of arriving in it. Both halves move
## together, because this is the geometry the run uses as well as the ball.
const CROSS_NEAR_WIDE := 0.72
const CROSS_FAR_OUT := 1.7
const CROSS_FAR_WIDE := 0.82


## The three points of the box, in the frame of the side attacking it.
static func box_targets(ctx: SimContext, team: int, ball: Vector3) -> Array:
	var dir := ctx.pitch.attack_dir(team)
	var goal := ctx.pitch.target_goal(team)
	var side: float = signf(ball.z)
	if side == 0.0:
		side = 1.0
	var six := ctx.pitch.goal_area_half_width
	return [
		Vector3(goal.x - dir * ctx.pitch.goal_area_depth, 0.0, side * six * CROSS_NEAR_WIDE),
		Vector3(goal.x - dir * ctx.pitch.penalty_spot_dist, 0.0, 0.0),
		Vector3(goal.x - dir * ctx.pitch.goal_area_depth * CROSS_FAR_OUT, 0.0,
			-side * six * CROSS_FAR_WIDE),
	]


## Who takes which point, decided once for the side.
##
## Held for the tick it was computed on, because every man on the side asks the
## same question of the same positions and the answer cannot differ between them.
## A static outlives the match, so `reset` clears the tick.
static var _claim_tick := [-1, -1]
static var _claims := [{}, {}]


## Who is attacking a given one of the three points, or -1 if nobody is.
##
## The cross asks this. Before it did, `_add_crosses` picked its target on which
## teammate *could* reach each point -- a race the man had not agreed to run --
## and the man was meanwhile running to a different one of the three, so the ball
## and the run went to different places: measured over three matches, nobody was
## ever within three metres of a cross coming down and the man it was aimed at was
## 6 to 16 m off it, while making a box run.
static func box_claimant(ctx: SimContext, team: int, ball: Vector3, index: int) -> int:
	for pid in _box_claims(ctx, team, ball):
		if int(_box_claims(ctx, team, ball)[pid][1]) == index:
			return pid
	return -1


static func _box_claims(ctx: SimContext, team: int, ball: Vector3) -> Dictionary:
	if _claim_tick[team] == ctx.tick_index:
		return _claims[team]
	var targets := box_targets(ctx, team, ball)
	# Every pair of a man who could go and a point he could take, worth first.
	# The worth is the point's, the race is his, and both belong in the ranking:
	# a man who can only just reach the far post still takes it if nobody better
	# is going, and does not take it off a man who is arriving on time.
	var pairs: Array = []
	for pid in ctx.team_players[team]:
		var m: SimPlayer = ctx.players[pid]
		if m.is_keeper or not m.on_pitch:
			continue
		if not SimRole.is_attacking(m.role) and m.role != SimRole.CM:
			continue
		if m.dist_to(ball) > BOX_RANGE:
			continue
		# The same offside test the caller applies to himself, so a man who would
		# be refused it cannot stand on a point and keep somebody else off it.
		var dir := ctx.pitch.attack_dir(team)
		var line := SimReferee.believed_offside_line(ctx, m) * dir
		if m.pos.x * dir > line + BEHIND_ONSIDE_SLACK:
			continue
		for i in targets.size():
			var point: Vector3 = targets[i]
			var run := m.dist_to(point)
			# Long enough to be a run and short enough to be finished while the
			# ball is still worth arriving for, as `BEHIND_MAX_RUN`.
			if run < 2.0 or run > BOX_MAX_RUN:
				continue
			var worth := ctx.value.xt_at(team, point, ctx.pitch) * _box_reach(m, point)
			if worth <= 0.0:
				continue
			pairs.append([worth, i, pid, point])
	# Best pair first, and ties broken on the point and then the man so that the
	# order is a fact about the positions rather than about the array.
	pairs.sort_custom(func(a, b):
		if not is_equal_approx(a[0], b[0]):
			return a[0] > b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	var claims := {}
	var taken := {}
	for pair in pairs:
		var i: int = pair[1]
		var pid: int = pair[2]
		if taken.has(i) or claims.has(pid):
			continue
		taken[i] = true
		claims[pid] = [pair[3], i]
	_claim_tick[team] = ctx.tick_index
	_claims[team] = claims
	return claims


## The decoy run. How close the marker must be for there to be anybody to
## drag, and what dragging him is worth against the runs made to receive.
const DECOY_MARKED := 3.5
const DECOY_WORTH := 0.6
## The second ball: how far under the duel the man stands, how far away he can
## be and still get there, and what winning the loose ball is worth.
const SECOND_SHORT := 8.0
const SECOND_RANGE := 28.0
const SECOND_WORTH := 1.3
## The pocket between the lines: the least gap between the opponents' back
## line and their midfield line worth dropping into, and the lift the pocket
## carries over an ordinary probe -- the map cannot see "between the lines",
## and the lift is the football statement that a man there is playable and
## facing their goal while nobody's job is to press him.
const POCKET_GAP := 8.0
## How far onside a runner checks back to, and it is not a tuning number.
##
## It was 0.4 m. The line he is checking against is
## `SimReferee.believed_offside_line` -- his *belief*, carrying `SimPerception`'s
## positional noise of 0.35 m for a defender in view and 1.5 m for one behind him
## -- and the flag is thrown against the truth. Holding forty centimetres off a
## line he knows to within a metre and a half is not timing a run finely, it is
## being flagged by arithmetic: about half of those checks put him level or beyond
## the real line.
##
## A metre and a quarter is the noise, near enough, and it is what a striker
## actually does -- he starts from a stride onside, not from the same blade of
## grass. Measured, offsides ran at 12.8 to 13.3 a team per football-90 against a
## §11 ceiling of 12 once the runs this week were given triggers, and the owner had
## already asked for fewer of them by eye.
const ONSIDE_MARGIN := 1.25
const POCKET_LIFT := 1.15
## And what the *first* man in is worth, when nobody is linking yet. See the note
## where it is applied.
const POCKET_LIFT_FIRST := 1.9
## How near the pocket a man has to be to count as already occupying it.
const POCKET_HELD := 9.0


## Where a decoy goes: forward and across the front of the defence, up to the
## line, away from the channel the ball is in -- the dart that drags a marker
## out of the middle without asking for the ball.
static func _decoy_point(ctx: SimContext, p: SimPlayer, team: int, ball: Vector3) -> Vector3:
	if not SimRole.is_attacking(p.role):
		return Vector3.INF
	var dir := ctx.pitch.attack_dir(team)
	if ball.x * dir < ctx.pitch.half_length * 0.2:
		return Vector3.INF
	if p.dist_to(ball) > 30.0:
		return Vector3.INF
	var line: float = SimReferee.believed_offside_line(ctx, p) * dir
	if p.pos.x * dir > line + BEHIND_ONSIDE_SLACK:
		return Vector3.INF
	var across: float = -signf(p.pos.z - ball.z)
	if is_zero_approx(across):
		across = 1.0
	var pt := Vector3(minf(p.pos.x * dir + 7.0, line + 2.0) * dir, 0.0, p.pos.z + across * 6.0)
	return ctx.pitch.clamp_to_pitch(pt, 2.0)


## Where the second-ball man stands: under the drop of our own high ball,
## goal-side of the contest, when the drop is actually contested. Nobody's
## errand when the ball is on the grass, aimed at nobody's duel, or already
## his own to meet.
static func _second_ball_point(ctx: SimContext, p: SimPlayer, team: int) -> Vector3:
	if ctx.ball.grounded or ctx.ball.last_touch_team != team:
		return Vector3.INF
	if ctx.ball.pos.y < 1.5:
		return Vector3.INF
	if ctx.ball.intended_target == p.id:
		return Vector3.INF
	var traj := ctx.trajectory_now()
	if traj.count == 0:
		return Vector3.INF
	var land := traj.points[traj.count - 1]
	if p.dist_to(land) > SECOND_RANGE:
		return Vector3.INF
	# Contested, or the man it is for simply takes it and this run is a body
	# in his way.
	var rival := ctx.nearest_to(land, SimConsts.other_team(team))
	if rival == null or rival.dist_to(land) > 7.0:
		return Vector3.INF
	var dir := ctx.pitch.attack_dir(team)
	var pt := Vector3(land.x - dir * SECOND_SHORT, 0.0, lerpf(p.pos.z, land.z, 0.7))
	return ctx.pitch.clamp_to_pitch(pt, 1.5)


## The pocket between the opponents' lines, as a point in this player's own
## channel, or INF when the lines are too close to hold one.
## Is anybody already linking? Counted off where men actually are rather than off
## their intents, because a man holding station between the lines is linking just
## as much as one who has decided to move there.
static func _anyone_between_the_lines(ctx: SimContext, team: int, exclude: int, pocket: Vector3) -> bool:
	for pid in ctx.team_players[team]:
		if pid == exclude:
			continue
		var m: SimPlayer = ctx.players[pid]
		if m.is_keeper or not m.on_pitch:
			continue
		if m.dist_to(pocket) <= POCKET_HELD:
			return true
	return false


static func _pocket_point(ctx: SimContext, p: SimPlayer, team: int, base: Vector3) -> Vector3:
	if not SimRole.is_attacking(p.role) and p.role != SimRole.CM:
		return Vector3.INF
	var dir := ctx.pitch.attack_dir(team)
	var line: float = SimReferee.believed_offside_line(ctx, p) * dir
	var mid_sum := 0.0
	var n := 0
	for oid in ctx.opponent_ids(team):
		var o := ctx.players[oid]
		if not o.on_pitch or o.is_keeper:
			continue
		if o.role == SimRole.DM or o.role == SimRole.CM or o.role == SimRole.AM:
			mid_sum += o.pos.x * dir
			n += 1
	if n == 0:
		return Vector3.INF
	var mid_line := mid_sum / float(n)
	if line - mid_line < POCKET_GAP:
		return Vector3.INF
	var pt := Vector3((line + mid_line) * 0.5 * dir, 0.0, base.z)
	if (pt.x - base.x) * dir < 2.0:
		return Vector3.INF
	if SimConsts.horizontal_length(pt - base) > 16.0:
		return Vector3.INF
	return ctx.pitch.clamp_to_pitch(pt, 1.5)


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
## What arriving on a patch of grass with the ball is worth, for the one run that
## is not scored through `_value_of`.
##
## **The asymmetry this documents is real and closing it made the engine worse.**
## `_value_of` returns `control * lane * (threat + possession_value * retain) *
## promptness`, and in the middle third `possession_value` is about 0.013 against
## an expected threat of 0.002 — so four fifths of the value of any position is
## the possession, not the map. Holding station is scored with it. Three runs are
## scored outside that function because pitch control is the wrong question for a
## patch nobody is standing in yet, and only the second ball carried the
## possession half: the run in behind and the run into the box were competing
## against standing still on a fifth of the units.
##
## Priced the same way, the run in behind roughly doubled — its share of the
## softmax went 8.1% to 19.5% — and across twenty seeds **goals fell 3.46 to 2.33,
## shots 4.70 to 3.55 and touches in the opposition box 4.5 to 2.9**. Reverting it
## alone put all three back. The men who go beyond are the men who were linking:
## price the run past the last defender like a position and the side has nobody
## left in the middle third to give it to, which is the owner's "there have to be
## link players" arriving from the other side (`docs/THE_FOOTBALL.md` 30).
##
## So the two runs keep `xt` alone, and this is left holding the second ball and
## the argument. **The units are still inconsistent** — that part was not wrong —
## and whatever fixes it has to pay for the link players it takes away, which is
## 30's job and not a scoring knob's.
static func _worth_at(ctx: SimContext, team: int, point: Vector3) -> float:
	return ctx.value.xt_at(team, point, ctx.pitch) + SimDecision.possession_value(ctx, team, point)


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
	_rest_kind.resize(n)
	_born.resize(n)
	_check_point.resize(n)
	_check_until.resize(n)
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
		_rest_kind[i] = NONE
		_born[i] = 0
		_check_point[i] = Vector3.ZERO
		_check_until[i] = 0
	regain_passes.resize(2)
	regain_men.resize(2)
	regain_rest_left.resize(2)
	regain_far.resize(2)
	regain_held.resize(2)
	regain_considered.resize(2)
	for w in 2:
		regain_passes[w] = 0
		regain_men[w] = 0
		regain_rest_left[w] = 0.0
		regain_far[w] = 0
		regain_held[w] = 0
		regain_considered[w] = 0
	regain_live.resize(KIND_NAMES.size() * 2)
	regain_resting.resize(KIND_NAMES.size() * 2)
	for i in regain_live.size():
		regain_live[i] = 0
		regain_resting[i] = 0
	born.resize(KIND_NAMES.size())
	born_offered.resize(KIND_NAMES.size())
	born_weight.resize(KIND_NAMES.size())
	born_received.resize(KIND_NAMES.size())
	cut_served.resize(KIND_NAMES.size())
	cut_n.resize(KIND_NAMES.size())
	for i in KIND_NAMES.size():
		born[i] = 0
		born_offered[i] = 0
		born_weight[i] = 0.0
		born_received[i] = 0
		cut_served[i] = 0.0
		cut_n[i] = 0
	made.resize(KIND_NAMES.size())
	received.resize(KIND_NAMES.size())
	cut_short.resize(KIND_NAMES.size())
	travel.resize(KIND_NAMES.size())
	forward.resize(KIND_NAMES.size())
	offered.resize(KIND_NAMES.size())
	weight.resize(KIND_NAMES.size())
	shot.resize(KIND_NAMES.size())
	behind_why.resize(BEHIND_WHY.size())
	box_why.resize(BOX_WHY.size())
	for i in behind_why.size():
		behind_why[i] = 0
	for i in box_why.size():
		box_why[i] = 0
	box_target.resize(BOX_TARGETS.size())
	for i in box_target.size():
		box_target[i] = 0
	box_ease.resize(BOX_EASE_NAMES.size())
	for i in box_ease.size():
		box_ease[i] = 0
	switched.resize(KIND_NAMES.size())
	for i in switched.size():
		switched[i] = 0
	_claim_tick = [-1, -1]
	_claims = [{}, {}]
	_cross_tick = [-1, -1]
	_cross_until = [-1, -1]
	chose_seen.resize(KIND_NAMES.size())
	chose_share.resize(KIND_NAMES.size())
	chose_won.resize(KIND_NAMES.size())
	chose_blocked.resize(KIND_NAMES.size())
	chose_men = 0
	for i in KIND_NAMES.size():
		made[i] = 0
		received[i] = 0
		cut_short[i] = 0
		travel[i] = 0.0
		forward[i] = 0.0
		offered[i] = 0
		weight[i] = 0.0
		shot[i] = 0
		chose_seen[i] = 0
		chose_share[i] = 0.0
		chose_won[i] = 0
		chose_blocked[i] = 0
