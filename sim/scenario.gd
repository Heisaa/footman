class_name SimScenario
extends RefCounted
## One named football situation, set rather than waited for, run forward and
## scored.
##
## The problem this exists for is that a match is a slow and noisy way to ask a
## question about a mechanic. The situation you want to look at happens a
## handful of times an hour -- the engine reaches the box about seven times a
## match -- so a change to it is measured against a count small enough that
## nothing separates a real effect from the next seed. And watching for it is
## worse: you sit through nine minutes for four glimpses of the thing you came
## to see.
##
## A scenario puts the players on the exact grass the question is about, runs a
## few seconds of real football from there, and says how it ended. Twenty of
## them cost less than one match and answer with a rate rather than an anecdote.
##
## **The same definition is watched and counted**, which is the point of putting
## it in `sim/` rather than in a bench. `./run.sh scenario` runs it many times
## and prints the table; `./run.sh view3d --scenario NAME` puts one on screen,
## repeatedly, from the same starting position. So the numbers and the eye are
## looking at the identical situation and can disagree about it usefully.
##
## What it is not: `./run.sh box` asks the decision layer what a striker would
## *choose* in a set geometry and never ticks the clock. This asks what actually
## happens. The two answer different halves of the same question and neither
## replaces the other -- a change that alters what he picks and not how it ends
## is a real result, and only the pair of them can see it.

## How a trial ended, most decisive first. One list for every scenario on
## purpose: the value of a fixed vocabulary is that you learn to read the shape
## of a row, and a per-scenario outcome set would be a new table every time.
enum {
	GOAL,
	SAVED,
	OFF,
	BLOCKED,
	LOST,
	NONE,
}
const RESOLUTIONS := ["goal", "saved", "off", "blocked", "lost", "none"]

## Identifier, for `--only` and `--scenario`.
var name := ""
## One line a human reads before looking at it.
var title := ""
## How long the trial is given, in simulated seconds, before it is called
## unresolved. Long enough for the situation to play out and no longer: a
## scenario that runs on becomes an ordinary match with a strange kick-off.
var seconds := 6.0
## The side the scenario is about. Every outcome is written from its point of
## view.
var attacking_team := SimConsts.TEAM_HOME
## Places the bodies and the ball: `func(scenario, ctx) -> void`. Called after
## the match is built and instead of its kick-off.
var place := Callable()

## The canonical x, in the attacking direction, past which the situation has
## succeeded and is over. `INF` for every row that has no such line, which is
## most of them.
##
## It exists for the two rows that read backwards -- `build-up` and `goal-kick`,
## where `none` is the good outcome and `lost` the bad one. Without it those two
## run the full clock over the whole pitch, so a side that plays out through the
## press, six passes and sixty metres, and is then tackled on the halfway line is
## scored `lost` on the row whose entire question is whether it can play out.
## Measured: `goal-kick` trial 1 did exactly that at 10.5 s and came back `lost`.
##
## The line is the top of the defending third, because that is where playing out
## is done. Past it with the ball still ours the trial stops and the verdict is
## `NONE`, which on these two rows is what success is called.
var escape_x := INF


## How soon after a defending touch the ball has to be ours again to count as
## given back, in simulated seconds. Long enough to cover a rebound picked up,
## short enough that a defence winning it and losing it again in open play is a
## different thing.
const GIVE_BACK := 1.0

## Touch kinds that leave the ball under someone's control. Everything else --
## a pass, a shot, a clearance, a parry -- puts it in flight, and the time it
## spends there is not a gap in anybody's carry.
const CONTROL_TOUCHES := [
	SimTelemetry.Touch.DRIBBLE,
	SimTelemetry.Touch.FIRST_TOUCH,
	SimTelemetry.Touch.CHEST,
	SimTelemetry.Touch.TACKLE,
	SimTelemetry.Touch.KEEPER_CATCH,
]

## The height a dropping ball is called arrived at, for `Result.drop_gap`.
## `SimTouch.CROSS_ARRIVE` is what a cross is solved to come down on, so the
## measurement is taken where the delivery was aimed.
const DROP_HEIGHT := 2.2


## What one trial produced.
class Result extends RefCounted:
	var resolution := NONE
	## Simulated seconds from the start to the first shot, or -1 for no shot.
	var to_shot := -1.0
	## Where the shot was struck from, in metres from goal. -1 for no shot.
	var shot_from := -1.0
	## Simulated seconds the attacking side held the ball inside the box before
	## it resolved. Seconds and not touches: it is sampled every tick, and
	## calling that a touch count would be a name that lies about its unit.
	var box_seconds := 0.0
	## Passes the attacking side attempted before it resolved.
	var passes := 0
	## Crosses the attacking side struck, and how far the nearest of ours was
	## from the ball when the first of them came down through heading height
	## (-1 if none did).
	##
	## Two columns rather than one because they separate the two ways a cross
	## fails, and `docs/THE_FOOTBALL.md` 29 is the second of them: a scenario
	## that ends with no shot is either a ball nobody put in, or a ball nobody
	## attacked, and those are fixed in different files.
	var crosses := 0
	var drop_gap := -1.0
	## Touches by the attacking side before it resolved, of any kind.
	var touches := 0
	## The longest stretch, in simulated seconds, that the ball went untouched by
	## anybody while nobody had struck it -- a ball rolling on with no pass and
	## no shot in it, which is a ball that has got away from the man who was
	## meant to have it.
	##
	## The "nobody had struck it" half is what keeps it honest: a cross hanging
	## for a second and a half is untouched too, and is football. Only the gaps
	## in a carry are counted.
	var carry_gap := 0.0
	## And how far the ball got from the man whose it was while that ran, in
	## metres.
	##
	## `carry_gap` counts seconds and cannot tell the two apart: a man running
	## alongside his own ball for half a second without touching it is football,
	## and a man standing still while it rolls two metres off him is the thing
	## the owner keeps seeing. Same seconds, different pictures, and only the
	## distance separates them -- which is what the eye is reading from the
	## stand.
	var carry_drift := 0.0
	## The defending side touched the ball and the attacking side had it again
	## within `GIVE_BACK`.
	##
	## A blocked shot rebounding to the striker is one of these and is real
	## football; a keeper catching it and the ball being back at the striker's
	## feet is one too and is not. The column does not tell them apart and is not
	## meant to -- it says how much of what this scenario produced came *through*
	## the defence rather than past it, and a row where that is a third of the
	## goals is a row to go and watch.
	var given_back := false
	## Touches by the attacking side before it resolved, counted by kind, and the
	## duels, offsides and fouls in the trial.
	##
	## The outcome columns say how it ended and the columns beside them say
	## whether the football was real; this says *what was played*, which is the
	## only one of the three that can tell an act that is never chosen from an
	## act that is chosen and fails. `--acts` prints it.
	var acts := PackedInt32Array()
	var duels := 0
	var offsides := 0
	var fouls := 0
	## Filled only when the scenario is `traced`.
	var log: Array = []

	func _init() -> void:
		acts.resize(SimTelemetry.TOUCH_NAMES.size())


## Puts every player on the station his own shape gives him for a ball at
## `ball_at`, and hands the ball to `holder`.
##
## The shape is asked rather than authored because a scenario with nine men
## parked on the touchline is not the situation it claims to be -- the value
## field reads the whole pitch, so the grass behind the play is part of what the
## striker is deciding about. `SimMovement.shape_position` is the engine's own
## answer to "where does this side stand when the ball is there", so a scenario
## only has to say what is *different* about the moment.
## **Whose ball it is is settled before anybody is placed**, because
## `shape_position` reads `SimContext.shape_phase` and a side in possession
## stands fifteen metres up the pitch from the same side out of it. Placing first
## laid every scenario out in the phase the kick-off it replaced had left behind
## -- the attacking side dropped off, in its own shape, on a row about its own
## attack. Measured on `fk-shot`, a free kick twenty-one metres from goal: when
## the ball was delivered the nearest of ours was **35.8 m from that goal**,
## fifteen metres *behind* the ball, and `drop m` read 20.8 in a box with nobody
## in it.
func settle(ctx: SimContext, ball_at: Vector3, holder: SimPlayer) -> void:
	for p in ctx.players:
		p.on_pitch = true
		p.vel = Vector3.ZERO
		p.recovery_ticks = 0
		p.touch_cooldown = 0.0
		p.marking_target = -1
		# The orientation clock, cleared rather than inherited from the kick-off
		# this scenario replaced. `SimDecision.readiness` reads it to decide
		# whether a man is set over the ball, so a leftover value is a striker
		# who has been standing on it for a minute and can strike it at once.
		p.spell_start_tick = -1
		p.spell_prep_seconds = 0.0

	ctx.ball.reset(Vector3(ball_at.x, SimConsts.BALL_RADIUS, ball_at.z))
	ctx.ball.last_touch_player = holder.id
	ctx.ball.last_touch_team = holder.team
	ctx.ball.last_touch_tick = ctx.tick_index
	# He has this instant come by the ball, which is the state a man in a set
	# situation is actually in -- not a man who has had it and looked up.
	holder.spell_start_tick = ctx.tick_index
	holder.spell_prep_seconds = 0.0
	ctx.in_play = true
	ctx.phase = SimConsts.Phase.ATTACK
	# The shape's ball starts on the real one rather than walking out to it over
	# the first seconds, which is `SimMatch.setup`'s own reasoning at kick-off.
	ctx.shape_ball = ctx.ball.ground_pos()
	ctx.shape_phase = PackedFloat32Array([
		1.0 if holder.team == SimConsts.TEAM_HOME else 0.0,
		1.0 if holder.team == SimConsts.TEAM_AWAY else 0.0,
	])
	ctx.update_possession()

	# And only now the bodies, on a shape that knows all of it.
	for p in ctx.players:
		p.pos = SimMovement.shape_position(ctx, p, ball_at)
		var toward := SimConsts.horizontal(ctx.pitch.target_goal(p.team) - p.pos)
		if toward.length() > 1e-3:
			p.facing = atan2(toward.z, toward.x)


## Whether the situation is still live: the ball in play, and nobody else's.
##
## Its own function because both halves have to stop at the same moment.
## `view3d` played on to a fixed clock, so a keeper collecting the ball at three
## seconds was scored `lost` by the table while the screen carried on and showed
## a goal a second later -- the eye and the row disagreeing about nothing, which
## is the one thing this pair exists not to do (owner, 2026-08-23).
## `started` is whether the ball has ever been in play in this trial. A set piece
## begins dead, and without that flag every corner and every free kick would be
## scored as over before the taker had reached the ball.
func live(ctx: SimContext, started: bool) -> bool:
	if not ctx.in_play:
		return not started
	return ctx.possession_team < 0 or ctx.possession_team == attacking_team


## Every event of one trial, as `[seconds, event]`, when `traced` is on.
##
## The table says how often; this says what happened, in order, in one of them.
## Kept on the result rather than printed from inside the loop so the caller
## decides what is worth reading.
var traced := false

## Whether the ball is already in the air when the trial starts, struck as a
## cross by somebody the situation does not bother to animate.
##
## `run` needs telling, because everything it measures about a cross hangs off
## seeing the touch that struck one -- the `cross` count, and `drop m`, which is
## the answer to "was anybody there". A ball placed in flight logs no touch.
var starts_in_flight := false


## Runs one trial of this scenario on an already-built match and scores it.
##
## Stops at the first resolution rather than at the whistle. A trial that ran on
## past a goal would restart at the halfway line and start producing a second
## situation, which is the one thing a scenario must not do.
func run(m: SimMatch) -> Result:
	var ctx := m.ctx
	var r := Result.new()
	var goal_at := ctx.pitch.target_goal(attacking_team)
	var seen := ctx.telemetry.events.size()
	var limit := int(seconds / SimConsts.DT)
	var shot: Dictionary = {}
	var shot_tick := -1
	var conceded := false
	# Whether the ball ended up in their net, by whichever shot. `_verdict` reads
	# the *first* shot of the trial for everything else, which is right -- the
	# row is about the chance the situation produced -- and wrong for the one
	# outcome that is not a property of a shot at all. Measured on `cross-open`:
	# a header saved off the line and a second header put in 0.07 s later scored
	# the trial `saved`, in a scenario with no goalkeeper in it.
	var scored := false
	var cross_up := starts_in_flight
	if starts_in_flight:
		r.crosses += 1
	# The carry clock: when the ball was last under somebody's control, and
	# whether it is in flight from a struck ball right now.
	var touched_at := 0.0
	var in_flight := starts_in_flight
	# Whether anybody has actually controlled the ball yet. `in_flight` cannot
	# stand in for it: a scenario that starts the ball moving does not log a
	# touch, so before the first one the ball has a nominal owner who is thirty
	# metres away and has never been near it -- measured, `aerial` read a drift
	# of 59 m, which is the placement and not a carry.
	var controlled := false
	# Whether the ball has been in play yet, for `live`.
	var started := false
	# When the defending side last had a touch, for `given_back`.
	var theirs_at := -100.0
	# How many ticks the trial actually ran. Not `limit`: the loop stops at the
	# first resolution, and the closing carry gap below is measured to the end of
	# the football rather than to the end of the clock it was given. Measured on
	# `fk-shot`, whose trial resolved on a keeper's catch at 2.3 s of a 12 s
	# trial and was scored a 9.4 s gap in a carry nobody was making.
	var ran := 0

	for i in limit:
		ran = i + 1
		m.tick()
		if not started:
			started = ctx.in_play
			# The wait over a dead ball is not a gap in anybody's carry.
			touched_at = float(i) * SimConsts.DT
		# New events only. The trace is append-only, so an index is the whole of
		# the bookkeeping.
		while seen < ctx.telemetry.events.size():
			var e: Dictionary = ctx.telemetry.events[seen]
			seen += 1
			var kind: int = e["ev"]
			if traced:
				r.log.append([float(i) * SimConsts.DT, e])
			if kind == SimTelemetry.Ev.SHOT and int(e.get("team", -1)) == attacking_team \
					and shot.is_empty():
				# Held by reference: `on_target`, `goal` and `blocked` are filled
				# in on this same dictionary when the ball gets where it is going,
				# so the verdict is read at the end and not here.
				shot = e
				shot_tick = i
				r.to_shot = float(i) * SimConsts.DT
				r.shot_from = SimConsts.horizontal_length(
					goal_at - (e.get("from", Vector3.ZERO) as Vector3))
			elif kind == SimTelemetry.Ev.PASS_ATTEMPT and int(e.get("team", -1)) == attacking_team:
				r.passes += 1
			elif kind == SimTelemetry.Ev.TOUCH:
				var now := float(i) * SimConsts.DT
				var touch: int = int(e.get("kind", -1))
				var by: int = int(e.get("team", -1))
				if not in_flight:
					r.carry_gap = maxf(r.carry_gap, now - touched_at)
				touched_at = now
				in_flight = not CONTROL_TOUCHES.has(touch)
				controlled = controlled or not in_flight
				if by == attacking_team:
					r.touches += 1
					if touch >= 0 and touch < r.acts.size():
						r.acts[touch] += 1
					if now - theirs_at <= GIVE_BACK:
						r.given_back = true
					if touch == SimTelemetry.Touch.CROSS:
						r.crosses += 1
						cross_up = true
				else:
					theirs_at = now
			elif kind == SimTelemetry.Ev.DUEL:
				r.duels += 1
			elif kind == SimTelemetry.Ev.OFFSIDE and int(e.get("team", -1)) == attacking_team:
				r.offsides += 1
			elif kind == SimTelemetry.Ev.FOUL:
				r.fouls += 1
			elif kind == SimTelemetry.Ev.GOAL:
				if int(e.get("team", -1)) == attacking_team:
					scored = true
				else:
					conceded = true

		# The ball on its way down through the height it was aimed to arrive at,
		# which is the moment the question "was anybody there" has an answer.
		if cross_up and ctx.ball.vel.y < 0.0 and ctx.ball.pos.y <= DROP_HEIGHT:
			cross_up = false
			if r.drop_gap < 0.0:
				r.drop_gap = _nearest_of_ours(ctx, ctx.ball.ground_pos())

		if ctx.possession_team == attacking_team \
				and ctx.pitch.in_opponent_penalty_area(attacking_team, ctx.ball.ground_pos()):
			r.box_seconds += SimConsts.DT

		# How far the ball has got from the man it belongs to, while nobody has
		# struck it. The distance half of `carry_gap`; see `Result.carry_drift`.
		if controlled and not in_flight and ctx.ball.last_touch_player >= 0:
			var owner: SimPlayer = ctx.players[ctx.ball.last_touch_player]
			if owner.team == attacking_team and not owner.is_keeper:
				r.carry_drift = maxf(r.carry_drift,
					SimConsts.horizontal_length(ctx.ball.ground_pos() - owner.pos))

		# A struck ball is given time to arrive before its record is believed;
		# past that the situation is over however it ended.
		if not shot.is_empty():
			if not ctx.in_play or i - shot_tick > int(2.0 / SimConsts.DT):
				break
			continue
		# Or, on a row that has one, when the ball is out: past the line with
		# possession still ours is this situation succeeding, and playing on
		# from there is an ordinary match with a strange kick-off. See
		# `escape_x`.
		if started and not is_inf(escape_x) and ctx.possession_team == attacking_team \
				and ctx.pitch.orient(attacking_team, ctx.ball.ground_pos()).x >= escape_x:
			break
		# Before a shot, the situation ends when the ball does, or when it is
		# somebody else's.
		if conceded or not live(ctx, started):
			break

	# The last stretch counts too: a striker who never touches it again and lets
	# the clock run out is the loudest version of this, and a gap only closed by
	# a touch would score him a zero.
	if not in_flight:
		r.carry_gap = maxf(r.carry_gap, float(ran) * SimConsts.DT - touched_at)

	r.resolution = _verdict(ctx, shot, conceded, scored)
	return r


## Distance from `at` to the nearest attacking outfielder who is not the man who
## struck the ball -- a crosser standing near his own delivery is not somebody
## attacking it.
func _nearest_of_ours(ctx: SimContext, at: Vector3) -> float:
	var best := INF
	for p in ctx.players:
		if p.team != attacking_team or p.is_keeper or p.id == ctx.ball.last_touch_player:
			continue
		best = minf(best, p.dist_to(at))
	return -1.0 if is_inf(best) else best


func _verdict(ctx: SimContext, shot: Dictionary, conceded: bool, scored := false) -> int:
	if scored:
		return GOAL
	if shot.is_empty():
		if conceded or (ctx.possession_team >= 0 and ctx.possession_team != attacking_team):
			return LOST
		return NONE
	if bool(shot.get("goal", false)):
		return GOAL
	if bool(shot.get("blocked", false)):
		return BLOCKED
	if bool(shot.get("on_target", false)):
		return SAVED
	return OFF
