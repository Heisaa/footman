class_name TestPatterns
extends SimTestCase
## Named tactical patterns (PLAN.md §5.3).
##
## The requirement is not that a pattern produces a particular outcome -- it is
## that it *fires visibly, is counted, and is judged*. A pattern that fires and
## is never resolved teaches the player nothing, which is the whole reason the
## feature exists.


func run() -> void:
	_installing_is_bounded_and_unique()
	_cloning_a_plan_does_not_share_counts()
	_patterns_fire_and_are_all_resolved()
	_a_pattern_biases_a_pass_toward_its_runner()
	_keeper_plays_short_is_honoured()
	_presets_carry_recognisable_moves()


func _installing_is_bounded_and_unique() -> void:
	var t := SimTactics.new()
	check(t.install(SimPattern.Kind.OVERLAP_LEFT), "a fresh plan accepts a pattern")
	check(not t.install(SimPattern.Kind.OVERLAP_LEFT), "the same pattern cannot be installed twice")
	var added := 1
	for kind in SimPattern.KIND_NAMES.size():
		if t.install(kind):
			added += 1
	check_less(float(t.patterns.size()), float(SimTactics.MAX_PATTERNS) + 0.5, "the slot count is bounded")
	check(t.has_pattern(SimPattern.Kind.OVERLAP_LEFT), "has_pattern finds what was installed")


func _cloning_a_plan_does_not_share_counts() -> void:
	var t := SimTactics.balanced()
	t.patterns[0].fired = 7
	var c := t.clone()
	check_equal(c.patterns[0].fired, 0, "a cloned plan starts its own count")
	c.patterns[0].fired = 3
	check_equal(t.patterns[0].fired, 7, "and does not write back into the original")


func _patterns_fire_and_are_all_resolved() -> void:
	# Over a real match, every firing must end up with an outcome. An unresolved
	# firing is one the post-match screen cannot report on.
	var opts := SimRunner.Options.new()
	opts.seed_value = 88
	# Long enough that the installed patterns fire plenty of times, short enough
	# that the suite stays cheap. What is being checked is that every firing is
	# resolved, which does not need more firings to be true.
	#
	# Cut from fourteen, and cut less far than everything else in the suite,
	# because this one is not a rate: `fired > 5` is an absolute count and
	# patterns are deliberately on long cooldowns -- a ten-minute diagnose has
	# shown a single named move firing once for a side. Ten minutes of football
	# keeps a real margin over the floor -- 100 match-clock minutes at the
	# standard `clock_rate` 10. Do not shorten it further without checking what
	# the firing count actually does; that is the check this test is made of.
	opts.minutes = 100.0
	opts.home_tactics = SimTactics.high_press_direct()
	opts.away_tactics = SimTactics.deep_block_patient()
	var m := SimRunner.build(opts)
	m.run_to_completion()

	var fired := m.ctx.telemetry.filter_where(SimTelemetry.Ev.PATTERN, {"phase": "fired"})
	var outcomes := m.ctx.telemetry.filter_where(SimTelemetry.Ev.PATTERN, {"phase": "outcome"})
	check_greater(float(fired.size()), 5.0, "installed patterns must actually fire in a match")
	# Everything except the runs still live at full time.
	check_less(float(fired.size() - outcomes.size()), 5.0, "almost every firing must be judged")

	var counted := 0
	var succeeded := 0
	for team in 2:
		for row in SimPatterns.summary(m.ctx, team):
			counted += int(row["fired"])
			succeeded += int(row["succeeded"])
			check_between(float(row["rate"]), 0.0, 1.0, "a success rate is a rate")
	check_equal(counted, fired.size(), "the per-pattern counters agree with the event log")
	check_greater(float(succeeded), 0.0, "at least some patterns must work")
	check_less(float(succeeded), float(counted) + 0.5, "and not more than fired")


func _a_pattern_biases_a_pass_toward_its_runner() -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = 5
	opts.minutes = 2.0
	var ctx := SimRunner.build(opts).ctx
	var carrier := ctx.players[7]
	var runner := ctx.players[9]

	var before := SimPatterns.pass_bias(ctx, carrier, runner.id, runner.pos)
	check_near(before, 1.0, 0.001, "with nothing live, a pattern has no opinion")

	var pattern := SimPattern.new(SimPattern.Kind.THIRD_MAN_RUN, 0.8)
	ctx.pattern_runs.append({
		"kind": pattern.kind, "team": carrier.team, "runner": runner.id, "with": carrier.id,
		"target": runner.pos, "fired": ctx.tick_index,
		"expires": ctx.tick_index + 240, "pattern": pattern,
	})
	var after := SimPatterns.pass_bias(ctx, carrier, runner.id, runner.pos)
	check_near(after, 1.8, 0.001, "a live pattern raises the value of the pass it wants")
	check_near(
		SimPatterns.pass_bias(ctx, carrier, ctx.players[8].id, ctx.players[8].pos), 1.0, 0.001,
		"and leaves every other pass alone"
	)
	# And it moves the runner.
	check(SimPatterns.movement_override(ctx, runner) != Vector3.INF, "the runner is given a target")
	check(SimPatterns.movement_override(ctx, carrier) == Vector3.INF, "nobody else is")


func _keeper_plays_short_is_honoured() -> void:
	var plan := SimTactics.new()
	var opts := SimRunner.Options.new()
	opts.seed_value = 12
	opts.minutes = 2.0
	var ctx := SimRunner.build(opts).ctx
	ctx.teams[0].tactics = plan
	check(not SimPatterns.keeper_plays_short(ctx, 0), "not installed, not honoured")
	plan.install(SimPattern.Kind.KEEPER_PLAYS_SHORT)
	check(SimPatterns.keeper_plays_short(ctx, 0), "installed, honoured")


func _presets_carry_recognisable_moves() -> void:
	# PLAN.md §5.3 asks for a handful of named, recognisable moves rather than
	# abstract axes, so the presets should read as football.
	var press := SimTactics.high_press_direct()
	var block := SimTactics.deep_block_patient()
	check(press.has_pattern(SimPattern.Kind.PRESS_THE_GOAL_KICK), "a pressing plan presses goal kicks")
	check(block.has_pattern(SimPattern.Kind.KEEPER_PLAYS_SHORT), "a patient plan builds from the back")
	check(not block.has_pattern(SimPattern.Kind.PRESS_THE_GOAL_KICK), "and does not press them")
	check_between(float(press.patterns.size()), 1.0, float(SimTactics.MAX_PATTERNS), "a plan has a handful of moves")
	for p in press.patterns:
		check(p.display_name != "", "every pattern has a name a player can recognise")
