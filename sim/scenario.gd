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


## Puts every player on the station his own shape gives him for a ball at
## `ball_at`, and hands the ball to `holder`.
##
## The shape is asked rather than authored because a scenario with nine men
## parked on the touchline is not the situation it claims to be -- the value
## field reads the whole pitch, so the grass behind the play is part of what the
## striker is deciding about. `SimMovement.shape_position` is the engine's own
## answer to "where does this side stand when the ball is there", so a scenario
## only has to say what is *different* about the moment.
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
		p.pos = SimMovement.shape_position(ctx, p, ball_at)
		var toward := SimConsts.horizontal(ctx.pitch.target_goal(p.team) - p.pos)
		if toward.length() > 1e-3:
			p.facing = atan2(toward.z, toward.x)

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

	for i in limit:
		m.tick()
		# New events only. The trace is append-only, so an index is the whole of
		# the bookkeeping.
		while seen < ctx.telemetry.events.size():
			var e: Dictionary = ctx.telemetry.events[seen]
			seen += 1
			var kind: int = e["ev"]
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
			elif kind == SimTelemetry.Ev.GOAL and int(e.get("team", -1)) != attacking_team:
				conceded = true

		if ctx.possession_team == attacking_team \
				and ctx.pitch.in_opponent_penalty_area(attacking_team, ctx.ball.ground_pos()):
			r.box_seconds += SimConsts.DT

		# A struck ball is given time to arrive before its record is believed;
		# past that the situation is over however it ended.
		if not shot.is_empty():
			if not ctx.in_play or i - shot_tick > int(2.0 / SimConsts.DT):
				break
			continue
		# Before a shot, the situation ends when the ball does, or when it is
		# somebody else's.
		if not ctx.in_play or conceded:
			break
		if ctx.possession_team >= 0 and ctx.possession_team != attacking_team:
			break

	r.resolution = _verdict(ctx, shot, conceded)
	return r


func _verdict(ctx: SimContext, shot: Dictionary, conceded: bool) -> int:
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
