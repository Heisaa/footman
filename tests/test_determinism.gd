class_name TestDeterminism
extends SimTestCase
## PLAN.md §2.4: identical results for a given seed within a given build.
##
## This is the test the architecture rests on. If it fails, something in the
## simulation is reading the frame counter, the system clock, a global RNG, or
## iterating a collection in an undefined order.


func run() -> void:
	_same_seed_same_events()
	_different_seeds_differ()
	_snapshots_do_not_perturb_the_sim()
	_reading_the_value_field_does_not_consume_randomness()


## Every match here is run twice, so its length is paid for twice. Divergence
## is compared over the whole event log, and a log from four minutes of match
## already contains set pieces, fouls, shots and a keeper -- the paths where an
## undefined iteration order or a stray global RNG call actually hides. Length
## beyond that buys repetition, not coverage, and the golden replay test covers
## a full match against a recorded hash.
static func _run_match(seed_value: int, minutes: float = 4.0) -> SimMatch:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = minutes
	var m := SimRunner.build(opts)
	m.run_to_completion()
	return m


func _same_seed_same_events() -> void:
	var a := _run_match(4242)
	var b := _run_match(4242)
	check_equal(a.ctx.telemetry.events.size(), b.ctx.telemetry.events.size(), "same seed, same number of events")
	check_equal(a.ctx.telemetry.digest(), b.ctx.telemetry.digest(), "same seed, identical event log")
	check_equal(a.ctx.score, b.ctx.score, "same seed, same score")
	check_greater(float(a.ctx.telemetry.events.size()), 100.0, "the match must actually have happened")


func _different_seeds_differ() -> void:
	var a := _run_match(1, 2.0)
	var b := _run_match(2, 2.0)
	check(a.ctx.telemetry.digest() != b.ctx.telemetry.digest(), "different seeds must produce different matches")


func _snapshots_do_not_perturb_the_sim() -> void:
	# Presentation reads snapshots every frame. Doing so must not touch sim
	# state or consume a single random draw.
	var opts := SimRunner.Options.new()
	opts.seed_value = 77
	opts.minutes = 3.0

	var plain := SimRunner.build(opts)
	plain.run_to_completion()

	var watched := SimRunner.build(opts)
	var snap := SimSnapshot.new()
	while not watched.finished:
		watched.tick()
		watched.write_snapshot(snap)
	check_equal(plain.ctx.telemetry.digest(), watched.ctx.telemetry.digest(), "taking snapshots must not change the match")


func _reading_the_value_field_does_not_consume_randomness() -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = 909
	opts.minutes = 2.0

	var plain := SimRunner.build(opts)
	plain.run_to_completion()

	var probed := SimRunner.build(opts)
	while not probed.finished:
		probed.tick()
		if probed.ctx.tick_index % 120 == 0:
			# What the debug view and the heat maps do.
			probed.ctx.value.refresh_debug_grid(probed.ctx)
			probed.ctx.value.xt_at(0, probed.ctx.ball.pos, probed.ctx.pitch)
	check_equal(plain.ctx.telemetry.digest(), probed.ctx.telemetry.digest(), "the debug grid must never be on the decision path")
