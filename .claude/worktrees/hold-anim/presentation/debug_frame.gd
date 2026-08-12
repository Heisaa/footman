class_name MatchDebugFrame
extends RefCounted
## Everything the debug panels and the pitch annotations read off the context,
## copied out at one tick.
##
## It exists because the context only knows about now. Stepping back through the
## recording moved the picture and left every number where it was, so the panel
## described this instant's football over a picture of three seconds ago —
## pressure rings around men who were not yet under any, a phase that had not
## started, a decision nobody had taken. The snapshot already carries the
## picture; this carries the rest of what the overlay says about it.
##
## Presentation, and display only. Nothing in `sim/` reads it, and it is captured
## only while `--debug` is on.
##
## Decisions are not here. `SimDebug` already keeps a few hundred of them stamped
## with the tick they were taken at, so the overlay asks it for the newest one at
## or before the tick being shown rather than carrying a copy per sample.

## The tick this was taken at, or -1 for a frame that has never been captured.
var tick := -1
var clock := 0.0

var phase := 0
var in_play := true
var possession_team := -1
var possession_player := -1
var possession_ticks := 0
## Who touched the ball last, which is whose head the overlay is inside when
## nobody is in possession.
var last_touch := -1
var restart_kind := -1
var restart_taker := -1
var restart_hold := 0
var offside_pending := -1
## One entry per pattern in flight: `name`, `runner`, and `left`, the ticks the
## window still had to run.
var patterns: Array[Dictionary] = []

## Per player, indexed by id (`ctx.players[i].id == i` always).
var count := 0
var pos := PackedVector3Array()
var on_pitch := PackedInt32Array()
var team := PackedInt32Array()
var pressure := PackedFloat32Array()
var challenge := PackedFloat32Array()
var intent := PackedInt32Array()
## Where the offer was going, or `Vector3.INF` for a player offering nothing.
var intent_point := PackedVector3Array()
var chase := PackedInt32Array()
var marking := PackedInt32Array()
## Ticks until this player next decides, at the moment of capture.
var next_decision := PackedInt32Array()

## Believed positions, flat and indexed [observer * count + target], as the
## context holds them.
var beliefs := PackedVector3Array()
## The coarse pitch-control grid, which the view refreshes only while that layer
## is on. Empty otherwise, and the layer draws nothing.
var value_grid := PackedFloat32Array()


func captured() -> bool:
	return tick >= 0


## Copies the lot. Called once a frame for the live picture and once per recorded
## sample, so everything here is a read off state the tick has already computed:
## no layer of the sim is run again to fill it in.
func capture(ctx: SimContext) -> void:
	tick = ctx.tick_index
	clock = ctx.clock
	phase = int(ctx.phase)
	in_play = ctx.in_play
	possession_team = ctx.possession_team
	possession_player = ctx.possession_player
	possession_ticks = ctx.possession_ticks
	last_touch = ctx.ball.last_touch_player
	restart_kind = ctx.restart_kind
	restart_taker = ctx.restart_taker
	restart_hold = ctx.restart_hold
	offside_pending = ctx.offside_pending

	patterns.clear()
	for run in ctx.pattern_runs:
		var pattern: SimPattern = run["pattern"]
		patterns.append({
			"name": pattern.display_name,
			"runner": int(run["runner"]),
			"left": int(run["expires"]) - ctx.tick_index,
		})

	_resize(ctx.players.size())
	for i in count:
		var p := ctx.players[i]
		pos[i] = p.pos
		on_pitch[i] = 1 if p.on_pitch else 0
		team[i] = p.team
		pressure[i] = ctx.pressure_on(p)
		challenge[i] = ctx.challenge_on(p)
		intent[i] = SimOffBall.intent_of(ctx, p)
		intent_point[i] = SimOffBall.destination_for(ctx, p)
		chase[i] = SimMovement.chase_role_of(p.id)
		marking[i] = p.marking_target
		next_decision[i] = p.next_decision_tick - ctx.tick_index

	beliefs = ctx.beliefs.duplicate()
	value_grid = ctx.value.debug_grid.duplicate()


func _resize(n: int) -> void:
	if count == n:
		return
	count = n
	pos.resize(n)
	on_pitch.resize(n)
	team.resize(n)
	pressure.resize(n)
	challenge.resize(n)
	intent.resize(n)
	intent_point.resize(n)
	chase.resize(n)
	marking.resize(n)
	next_decision.resize(n)
