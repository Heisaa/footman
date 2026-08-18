class_name ControlBench
extends RefCounted
## `./run.sh control` — what the pass model says about a contest, against what
## the engine then does with it.
##
## `control_at_pass` is the `space` factor, and it is the largest single term in
## `_pass_success`. A match cannot calibrate it: which balls get played is chosen
## by the softmax on the strength of this very number, so the completion rate
## beside it is as much a fact about selection as about the model. `diagnose`'s
## `is it ordered?` has that problem and says so.
##
## So this sets the geometry instead of sampling it. A passer, a receiver
## standing still 12 m away, one defender at a chosen distance from him, and
## everybody else parked off the map. The model is asked what it thinks; then the
## ball is actually struck and the match ticked until somebody touches it.
## **Every ball on the list is played**, so nothing about which balls get chosen
## can confound the two columns.
##
## Read `said` against `arrived`:
##
##   `said` is `control_at_pass` at the moment of the strike.
##   `arrived` is the share the receiver got, over `--trials` strikes, each from
##   its own match and its own rng stream.
##   `cut out` is the defender taking it, which is the only thing `said` is about.
##   `never controlled` is nobody touching it inside `SETTLE_TICKS` — a receiver
##   losing his own uncontested ball, which `said` does not model and should not.
##
## The two columns are a calibration only where `cut out` is non-zero. Past that
## the gap between them is the receiver's first touch, and reading it as model
## error would be charging `space` for something `receiver_touch` owns.
##
## It does not assert an answer. It prints the pair; the owner says whether that
## curve is football.
##
## **Re-read it when the defensive pass lands.** The cliff this measures is where
## *this* engine's interceptions happen, and a defence that steps into lanes will
## move it. The whole point of the bench is that re-measuring is minutes.
##
## Unlike `behind`, `box` and `strike`, this one simulates: `--trials` matches per
## row, a few seconds each. The default is sized to stay inside a coffee cup.

## The ball on the table. A 12 m ball to feet is the commonest pass in the match
## and the one the pass model is least able to see.
const PASS_LEN := 12.0
## Block A: how far the defender stands from the man the ball is for, square to
## the pass. Dense where the engine's interceptions actually are, sparse past.
const MARKER_AT := [1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 20.0]
## Block B: how far off the line he stands, at the midpoint of it. The two blocks
## split the model along its own seam — the contest at the end of the ball is
## `space`, the one along it is `lane`, and a geometry that moves both at once
## cannot say which is wrong.
const LANE_AT := [0.5, 1.0, 1.5, 2.0, 3.0, 4.5, 6.0]
## Block C: the same lane, with the man it is for sprinting onto the ball instead
## of standing waiting for it. `into_space` is a different branch of the pass
## model — a longer tail left to the destination, a wider tolerance — and block B
## cannot speak for it: a ball to feet is aimed at a boot and this one is aimed at
## grass. The defender stands in the space the runner is going into.
const RUN_LANE_AT := [1.0, 2.0, 3.0, 4.5, 6.0, 9.0]
## How fast he is already going when it is struck, and where he starts. A man at
## a sprint with the ball played in front of him is the case the tail was written
## for.
const RUN_PACE := 6.0
const RUN_FROM := 10.0
## Where the defender stands, up the pitch. Ahead of the runner's start and short
## of where the ball is aimed, which is the ground a ball in behind is threaded
## across.
const RUN_MARKER_AT := 15.0
## Block D: a defender beside the *receiver* rather than out on the line, on a
## ball played into the space ahead of him. This is the seam. `_pass_success`
## splits at the target — `_lane_survival` prices the journey and
## `control_at_pass` the arrival — and `LANE_TAIL` hands the last six metres of
## the journey to the arrival so the last defender is not charged twice. A body
## inside that six metres who is *not* contesting the arrival is charged by
## neither, and this block is what says whether that is a real hole or a
## double-count correctly avoided.
##
## Swept twice, because standing still and crossing are the two cases the tail's
## argument treats alike: a marker planted beside the receiver is the man the
## tail was written for, and one moving across the line at pace is not.
const TAIL_AT := [1.0, 2.0, 3.0, 4.5, 6.0]
## How fast the crossing defender is already travelling, toward the line. Read
## off the case that raised this: seed 2 tick 217, a winger 2.9 m off the line at
## 9.9 m/s, on a ball the model scored 0.68 and the engine cut out.
const TAIL_CROSS_PACE := 8.0
## How long a strike is followed before the ball is called dead. Seven seconds
## against a flight of under two, so a receiver who has to turn and fetch a
## mis-hit one still counts as having got it.
const SETTLE_TICKS := 420


static var _ctx: SimContext
static var _match: SimMatch
static var _passer: SimPlayer
static var _receiver: SimPlayer
static var _marker: SimPlayer
static var _aim := Vector3.ZERO

enum { MODE_FEET, MODE_LANE, MODE_RUN, MODE_TAIL, MODE_TAIL_CROSS }


static func run(flags: Dictionary) -> void:
	var trials := int(flags.get("trials", "40"))
	var base := int(flags.get("seed", "1000"))
	print("A %.0f m ground pass to a man standing still, in a set geometry  (%d strikes a row)"
		% [PASS_LEN, trials])
	print("")
	print("A. one defender, d metres square of the receiver — the contest at the end")
	print("  %6s %7s %9s %10s %10s %18s" % [
		"d (m)", "space", "success", "arrived", "cut out", "never controlled"])
	for d in MARKER_AT:
		print("  " + _row(d, trials, base, MODE_FEET))
	print("")
	print("B. one defender on the line, halfway along it, l metres to the side")
	print("  %6s %7s %9s %10s %10s %18s" % [
		"l (m)", "space", "success", "arrived", "cut out", "never controlled"])
	for l in LANE_AT:
		print("  " + _row(l, trials, base, MODE_LANE))
	print("")
	print("C. the same, with the receiver sprinting onto it at %.0f m/s" % RUN_PACE)
	print("  %6s %7s %9s %10s %10s %18s" % [
		"l (m)", "space", "success", "arrived", "cut out", "never controlled"])
	for l in RUN_LANE_AT:
		print("  " + _row(l, trials, base, MODE_RUN))
	print("")
	print("D. a defender beside the running receiver, inside LANE_TAIL — the seam")
	print("   d1: he is standing there.  d2: he is crossing the line at %.0f m/s" % TAIL_CROSS_PACE)
	print("  %6s %7s %9s %10s %10s %18s" % [
		"d (m)", "space", "success", "arrived", "cut out", "never controlled"])
	for l in TAIL_AT:
		print("  d1" + _row(l, trials, base, MODE_TAIL))
	for l in TAIL_AT:
		print("  d2" + _row(l, trials, base, MODE_TAIL_CROSS))
	print("")
	print("  `space` is control_at_pass and `success` is the whole pass model, both")
	print("  read off the candidate the decision layer would score. The rest is what")
	print("  the engine then did with the same ball. `space` moves block A and `lane`")
	print("  moves block B, so a column that stays flat down its own block is the")
	print("  factor that cannot see the geometry it owns.")
	print("  `never controlled` is the receiver's own first touch and belongs to")
	print("  `receiver_touch`; neither of the first two columns answers for it.")


static func _row(d: float, trials: int, base: int, mode: int) -> String:
	# The model first, on a context of its own. `options_for` draws from `ctx.rng`
	# on its way through the shot aim, so asking it on the same context the ball is
	# struck from moves the strike's own error and the two halves stop describing
	# one ball.
	_fresh(base)
	_stage(d, mode)
	var c := _candidate()
	if c.is_empty():
		return "%6.1f    no ball to that man was ever generated" % d
	# The ball the model scored is the ball that gets struck, aim point and weight
	# both. For a man running onto it those are not his own feet.
	var aim: Vector3 = c["point"]
	var pace: float = c["pace"]
	var whole: float = c["success"]
	var length := SimConsts.horizontal_length(aim - _ctx.ball.pos)
	var travel := _ctx.ballistics.ground_travel_time(
		length, _ctx.ballistics.ground_pass_speed(length, pace, _ctx.env), _ctx.env)
	var said := _ctx.value.control_at_pass(
		_ctx, aim, _passer.team, travel, _receiver.id, _passer.id)

	var got := 0
	var cut := 0
	var loose := 0
	for t in trials:
		_fresh(base + t)
		_stage(d, mode)
		SimTouch.ground_pass(_ctx, _passer, aim, pace, _receiver.id)
		var first := _first_touch()
		if first == _receiver.id:
			got += 1
		elif first == _marker.id:
			cut += 1
		else:
			loose += 1
	var n := float(trials)
	return "%6.1f %7.2f %9.2f %9.0f%% %9.0f%% %17.0f%%" % [
		d, said, whole, 100.0 * got / n, 100.0 * cut / n, 100.0 * loose / n]


## The rolled ground pass to the receiver, as the decision layer would score it,
## or an empty dictionary if it was never generated. The driven twin is skipped:
## it is a different ball and `DRIVEN_LANE` prices its lane differently on
## purpose, and it is always the second of the pair.
static func _candidate() -> Dictionary:
	for c in SimDecision.options_for(_ctx, _passer):
		if int(c.get("action", -1)) != SimDecision.Action.GROUND_PASS:
			continue
		if int(c.get("target", -1)) != _receiver.id:
			continue
		return c
	return {}


## Who touches the ball next, or -1 if nobody does before it is called dead.
static func _first_touch() -> int:
	var was := _ctx.ball.last_touch_player
	for i in SETTLE_TICKS:
		_match.tick()
		if _ctx.ball.last_touch_player != was:
			return _ctx.ball.last_touch_player
	return -1


## A fresh match per strike, so a row is a rate over rng streams rather than one
## roll repeated. The static movement and off-ball state outlives a context, so
## both are cleared with it.
static func _fresh(seed_value: int) -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = 1.0
	opts.events = false
	_match = SimRunner.build(opts)
	_ctx = _match.ctx
	SimMovement.reset()
	SimOffBall.reset()
	# Into open play without playing the kick-off. Ticked out of the restart
	# instead, the number of ticks it takes depends on what the taker decides, so
	# every trial started from a slightly different tick index and a slightly
	# different set of tired legs -- and a change to the decision layer that
	# cannot touch this geometry moved the rows anyway. Block A's 1 m row swung
	# from 48% cut out to 5% on a change to the *into-space* branch, which is not
	# a thing that can happen. Forced flat, every row is a property of the
	# geometry again.
	_ctx.restart_kind = -1
	_ctx.restart_team = -1
	_ctx.restart_taker = -1
	_ctx.restart_ticks = 0
	_ctx.restart_hold = 0
	_ctx.restart_spots.clear()
	_ctx.in_play = true
	_match._pending_restart = {}
	_match._dead_ball_ticks = 0
	for p in _ctx.players:
		p.vel = Vector3.ZERO
		p.facing = 0.0
	_passer = _ctx.players[1]
	_receiver = _ctx.players[2]
	for p in _ctx.players:
		if p.team != _passer.team and not p.is_keeper:
			_marker = p
			break


## Everybody placed by hand. The spares go 40 m back and 55 m wide — off the
## field rather than on the far side of it, because a body inside `PRUNE_SLACK`
## of the aim point would join the contest this bench exists to isolate.
static func _stage(d: float, mode: int = MODE_FEET) -> void:
	_passer.pos = Vector3.ZERO
	_aim = Vector3(PASS_LEN, 0.0, 0.0)
	_receiver.pos = _aim
	_receiver.vel = Vector3.ZERO
	_receiver.facing = PI
	match mode:
		MODE_FEET:
			_marker.pos = _aim + Vector3(0.0, 0.0, d)
		MODE_LANE:
			_marker.pos = Vector3(PASS_LEN * 0.5, 0.0, d)
		MODE_RUN:
			# Already at a sprint when it is struck, and facing the way he is
			# going: `_lead_point` reads his velocity and `time_to_arrive`
			# charges him for any of it he has to shed.
			_receiver.pos = Vector3(RUN_FROM, 0.0, 0.0)
			_receiver.vel = Vector3(RUN_PACE, 0.0, 0.0)
			_receiver.facing = 0.0
			_marker.pos = Vector3(RUN_MARKER_AT, 0.0, d)
		MODE_TAIL, MODE_TAIL_CROSS:
			_receiver.pos = Vector3(RUN_FROM, 0.0, 0.0)
			_receiver.vel = Vector3(RUN_PACE, 0.0, 0.0)
			_receiver.facing = 0.0
			# Beside the man it is for, which for a ball played ahead of him is
			# inside the stretch of lane the tail hands to the arrival.
			_marker.pos = _receiver.pos + Vector3(0.0, 0.0, d)
			if mode == MODE_TAIL_CROSS:
				_marker.vel = Vector3(0.0, 0.0, -signf(d) * TAIL_CROSS_PACE)
				_marker.facing = -signf(d) * PI * 0.5
	# The passer faces the ball he is about to play, so the body angle is not
	# quietly a different number from row to row.
	_passer.facing = 0.0
	# The spares are parked wide, and the opposition's are parked *upfield of the
	# receiver*. Parked behind him they become the offside line, every ball on
	# the list is flagged, and `success` comes back at a tenth of itself for a
	# reason that has nothing to do with the geometry being measured.
	var parked := 0
	for p in _ctx.players:
		if p == _passer or p == _receiver or p == _marker:
			continue
		parked += 1
		var side: float = 52.0 * (1.0 if parked % 2 == 0 else -1.0)
		if p.is_keeper:
			p.pos = Vector3((_ctx.pitch.half_length - 0.5)
				* (1.0 if p.team == _passer.team else -1.0), 0.0, 0.0)
			continue
		p.pos = Vector3(PASS_LEN + 30.0 + float(parked), 0.0, side) if p.team != _passer.team \
			else Vector3(-30.0 - float(parked), 0.0, side)
	# And the man on the ball is set over it. `readiness` runs from his own spell,
	# and a passer who has only just been handed the ball is charged
	# `SET_SUCCESS_FLOOR` on every candidate he has.
	# Clamped: the kick-off loop leaves `tick_index` in the tens, and a negative
	# `spell_start_tick` sends `readiness` down its other branch and back to zero.
	_passer.spell_start_tick = maxi(_ctx.tick_index - 120, 0)
	_passer.spell_prep_seconds = 2.0
	_ctx.ball.reset(_passer.pos + Vector3(0.4, 0.0, 0.0))
	_ctx.ball.last_touch_player = _passer.id
	_ctx.ball.last_touch_team = _passer.team
	_ctx.ball.last_touch_tick = maxi(_ctx.tick_index - 120, 0)
	_ctx.update_possession()
