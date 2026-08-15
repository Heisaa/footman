class_name TestMatch
extends SimTestCase
## Whole-match invariants, including the Phase 2 exit criterion.
##
## PLAN.md §10 Phase 2: the debug view must read as football, and specifically
## there must be no ball-swarming -- players hold shape when the ball is
## elsewhere. That is measurable, so it is measured here rather than eyeballed.


## Long enough to play both halves and settle a rate, and no longer. Match-clock
## minutes: at the standard `clock_rate` 10 this is six minutes of football,
## which is what every threshold below was calibrated against. It was twelve
## (of football), and every check below is either a ratio -- which converges in
## the first minute or two -- or a floor on a count with a wide margin. See
## `MIN_EVENTS`.
const MINUTES := 60.0

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
	var build_samples := 0
	var build_width_total := 0.0
	var build_crowd_total := 0.0
	var third_samples := 0
	var third_final := 0
	var box_ticks := 0

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

		# The shape of the side in possession, and whether its attacks go
		# anywhere. The spread checks below cannot see either failure: a team
		# can hold a healthy spread while the men around its own ball clump
		# into the central channel (the collapse the owner watched,
		# DECISIONS.md "Width in build-up"), and it can hold every shape
		# number while the ball circulates in the middle third all match and
		# never reaches the box (the midfield stall).
		if ctx.tick_index % 30 == 0 and ctx.possession_team >= 0:
			var team := ctx.possession_team
			var dir := ctx.pitch.attack_dir(team)
			var ball_cx := b.pos.x * dir
			var third := ctx.pitch.half_length / 3.0
			third_samples += 1
			if ball_cx > third:
				third_final += 1
			if ctx.pitch.in_opponent_penalty_area(team, b.ground_pos()):
				box_ticks += 1
			if ball_cx < 0.0:
				var lo := INF
				var hi := -INF
				var crowd := 0
				for pid in ctx.team_players[team]:
					var p := ctx.players[pid]
					if p.is_keeper or not p.on_pitch:
						continue
					lo = minf(lo, p.pos.z)
					hi = maxf(hi, p.pos.z)
					if p.dist_to(b.ground_pos()) < 12.0:
						crowd += 1
				if not is_inf(lo):
					build_samples += 1
					build_width_total += hi - lo
					build_crowd_total += crowd

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

	# Width and structure in possession, and the stall. The bounds are sanity
	# ranges, not bands (CLAUDE.md): each catches a failure the owner has
	# watched and named, at a threshold far enough from the measured engine
	# that only the failure itself crosses it.
	# Measured on this seed when the bounds were set: width 43.5 m, crowd 3.9,
	# final third 11.5% of possession samples, 23 box samples. The stalled
	# engine this guards against (docs/STATUS.md, "The midfield stall") read
	# ~4% final third and 0 in the box, with the width still healthy — which
	# is why the final-third floor is the one carrying most of the weight.
	var mean_width := build_width_total / maxf(float(build_samples), 1.0)
	var mean_crowd := build_crowd_total / maxf(float(build_samples), 1.0)
	check_greater(float(build_samples), 50.0, "a match must contain own-half possession to measure")
	check_greater(mean_width, 30.0, "a side building in its own half must keep its width")
	check_less(mean_crowd, 6.0, "and must not clump around its own carrier")
	check_greater(float(third_final) / maxf(float(third_samples), 1.0), 0.05,
		"possession must reach the final third, not circulate in midfield all match")
	check_greater(float(box_ticks), 0.0, "and at least once in a match the ball must be worked into the box")

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
