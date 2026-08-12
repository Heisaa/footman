class_name TestMatch
extends SimTestCase
## Whole-match invariants, including the Phase 2 exit criterion.
##
## PLAN.md §10 Phase 2: the debug view must read as football, and specifically
## there must be no ball-swarming -- players hold shape when the ball is
## elsewhere. That is measurable, so it is measured here rather than eyeballed.


## Long enough to play both halves and settle a rate, and no longer. It was
## twelve, and every check below is either a ratio -- which converges in the
## first minute or two -- or a floor on a count with a wide margin. See
## `MIN_EVENTS`.
const MINUTES := 6.0

## The floor under the event count, and it is a "did a match happen at all" test
## rather than a rate. Six minutes of football produces several hundred events --
## touches alone run to about sixty a minute -- so this sits far below the
## measurement on purpose. It was 200 against a twelve-minute match; halving the
## match without halving the floor would have turned a sanity check into a band.
const MIN_EVENTS := 150.0


func run() -> void:
	_whole_match_invariants()
	_offside_line_is_the_second_last_defender()
	_sent_off_players_stop_playing()


## Six whole-match invariants over one stepped match rather than six.
##
## They all want the same thing -- a match played tick by tick with something
## sampled along the way -- and simulating it once instead of six times is most
## of this suite's wall clock. The suite is the check that has to be cheap enough
## to run on every change (PLAN.md §11.1); breadth across seeds comes from the
## smoke and gate runs, which sample many.
##
## The half-time flip used to be its own eight-minute match, run to the interval
## and then thrown away. This match already crosses the interval, so it is
## watched here instead, and the second match is gone.
func _whole_match_invariants() -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = 8
	opts.minutes = MINUTES
	var m := SimRunner.build(opts)

	var first_half_dir := m.ctx.pitch.attack_dir(0)
	var second_half_dir := first_half_dir
	var stray_ticks := 0
	var players_off := 0
	var near_samples := 0
	var near_total := 0
	var worst_near := 0
	var spread_samples := 0
	var spread_total := 0.0

	while not m.finished:
		m.tick()
		var ctx := m.ctx
		if ctx.period == SimConsts.Period.SECOND_HALF:
			second_half_dir = ctx.pitch.attack_dir(0)
		var b := ctx.ball
		if absf(b.pos.x) > ctx.pitch.half_length + 6.0 or absf(b.pos.z) > ctx.pitch.half_width + 6.0:
			stray_ticks += 1
		for p in ctx.players:
			if absf(p.pos.x) > ctx.pitch.half_length + 4.0 or absf(p.pos.z) > ctx.pitch.half_width + 4.0:
				players_off += 1
		if not ctx.in_play:
			continue

		# The failure mode to watch for. If players collapse onto the ball, the
		# mean number within ten metres of it climbs and the shape disappears.
		if ctx.tick_index % 30 == 0:
			var ball := b.ground_pos()
			var near := 0
			for p in ctx.players:
				if not p.is_keeper and p.dist_to(ball) < 10.0:
					near += 1
			near_total += near
			worst_near = maxi(worst_near, near)
			near_samples += 1

		# Standard deviation of team positions: a team holding shape is spread
		# out, a swarming team is not.
		if ctx.tick_index % 60 == 0:
			for team in 2:
				var mean := Vector3.ZERO
				var n := 0
				for pid in ctx.team_players[team]:
					var p := ctx.players[pid]
					if p.is_keeper:
						continue
					mean += p.pos
					n += 1
				mean /= maxf(float(n), 1.0)
				var acc := 0.0
				for pid in ctx.team_players[team]:
					var p := ctx.players[pid]
					if p.is_keeper:
						continue
					acc += p.pos.distance_squared_to(mean)
				spread_total += sqrt(acc / maxf(float(n), 1.0))
				spread_samples += 1

	check(m.finished, "a match must reach full time")
	check_greater(float(m.ctx.telemetry.events.size()), MIN_EVENTS, "and produce a substantial event log")
	check_equal(m.ctx.period, SimConsts.Period.FULL_TIME, "and end in the full-time period")
	check_greater(float(m.ctx.telemetry.count_of(SimTelemetry.Ev.KICKOFF)), 1.0, "both halves must kick off")
	check_near(second_half_dir, -first_half_dir, 0.01, "sides must change ends at half time")

	check_less(float(stray_ticks) / float(maxi(m.ctx.tick_index, 1)), 0.06, "the ball must not spend long off the pitch")
	check_equal(players_off, 0, "players must stay on or near the field of play")

	var mean_near := float(near_total) / maxf(float(near_samples), 1.0)
	check_less(mean_near, 6.5, "on average only a few players should be near the ball")
	check_less(float(worst_near), 15.0, "and never anything like the whole pitch")

	var mean_spread := spread_total / maxf(float(spread_samples), 1.0)
	check_greater(mean_spread, 14.0, "a team must stay spread across the pitch")
	check_less(mean_spread, 40.0, "but not be strung out end to end")

	var total: float = float(m.ctx.possession_count[0] + m.ctx.possession_count[1])
	check_greater(total, 1000.0, "possession must be tracked")
	var share: float = float(m.ctx.possession_count[0]) / total
	check_between(share, 0.2, 0.8, "neither side should own the whole match")


func _offside_line_is_the_second_last_defender() -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = 22
	opts.minutes = 2.0
	var m := SimRunner.build(opts)
	var ctx := m.ctx
	# Lay the away side out along the pitch, every player at a distinct depth,
	# and check where the line falls.
	var i := 0
	for pid in ctx.team_players[1]:
		var p := ctx.players[pid]
		p.pos = Vector3(-(48.0 - float(i) * 4.0), 0.0, float(i) * 2.0 - 8.0)
		i += 1
	# Home attacks +X, so the away side is at negative X here -- entirely inside
	# the home half. You cannot be offside in your own half, so the line is the
	# halfway line.
	var line := SimReferee.offside_line(ctx, 0)
	check_near(line, 0.0, 0.01, "with everyone in their own half the line is the halfway line")

	# Now put them in their own half, deepest at 48 m and next at 44 m. The
	# offside line is the second-last defender: 44.
	i = 0
	for pid in ctx.team_players[1]:
		var p := ctx.players[pid]
		p.pos = Vector3(48.0 - float(i) * 4.0, 0.0, float(i) * 2.0 - 8.0)
		i += 1
	var line2 := SimReferee.offside_line(ctx, 0)
	check_near(line2, 44.0, 0.01, "otherwise it is the second-last defender")
	ctx.ball.pos = Vector3(10.0, SimConsts.BALL_RADIUS, 0.0)
	check(SimReferee.would_be_offside(ctx, 0, Vector3(46.0, 0.0, 0.0)), "beyond the line and the ball is offside")
	check(not SimReferee.would_be_offside(ctx, 0, Vector3(20.0, 0.0, 0.0)), "short of the line is not")
	check(not SimReferee.would_be_offside(ctx, 0, Vector3(-20.0, 0.0, 0.0)), "you cannot be offside in your own half")


func _sent_off_players_stop_playing() -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = 44
	opts.minutes = 3.0
	var m := SimRunner.build(opts)
	var victim := m.ctx.players[5]
	victim.on_pitch = false
	victim.sent_off = true
	var start := victim.pos
	for i in 600:
		m.tick()
	check_near(victim.distance_run, 0.0, 0.01, "a dismissed player does not keep running")
	check_near(victim.pos.distance_to(start), 0.0, 0.5, "and does not keep moving")
