class_name TestDeterminism
extends SimTestCase
## PLAN.md §2.4: identical results for a given seed within a given build.
##
## This is the test the architecture rests on. If it fails, something in the
## simulation is reading the frame counter, the system clock, a global RNG, or
## iterating a collection in an undefined order.


## The one seed everything here is compared against, and how long it runs.
##
## Every check in this file is "does this match the baseline", so they can all
## share one baseline instead of each simulating its own pair. It used to be
## four separate pairs on four seeds -- 22 match-minutes for four comparisons.
## One baseline plus three variants plus one contrast is five runs, and at three
## minutes each that is 15.
##
## Three minutes of football because divergence is compared over the whole event
## log, and a log that long already contains set pieces, fouls, shots and a
## keeper -- the paths where an undefined iteration order or a stray global RNG
## call actually hides. Length beyond that buys repetition, not coverage: a sim
## that reads the frame counter diverges immediately, not eventually. The
## constant is match-clock minutes: 30 at the standard `clock_rate` 10 is those
## same three minutes of football.
const SEED := 4242
const MINUTES := 30.0


func run() -> void:
	var baseline := _run_match(SEED)
	_same_seed_same_events(baseline)
	_different_seeds_differ(baseline)
	_snapshots_do_not_perturb_the_sim(baseline)
	_reading_the_value_field_does_not_consume_randomness(baseline)


static func _run_match(seed_value: int, minutes: float = MINUTES) -> SimMatch:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = minutes
	var m := SimRunner.build(opts)
	m.run_to_completion()
	return m


## Builds the same match as `_run_match`, but stepped, so a caller can do
## something on every tick. Whatever it does must not change the digest.
static func _stepped(seed_value: int, on_tick: Callable) -> SimMatch:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = MINUTES
	var m := SimRunner.build(opts)
	while not m.finished:
		m.tick()
		on_tick.call(m)
	return m


func _same_seed_same_events(a: SimMatch) -> void:
	var b := _run_match(SEED)
	check_equal(a.ctx.telemetry.events.size(), b.ctx.telemetry.events.size(), "same seed, same number of events")
	check_equal(a.ctx.telemetry.digest(), b.ctx.telemetry.digest(), "same seed, identical event log")
	check_equal(a.ctx.score, b.ctx.score, "same seed, same score")
	check_greater(float(a.ctx.telemetry.events.size()), 100.0, "the match must actually have happened")


func _different_seeds_differ(a: SimMatch) -> void:
	# A minute of football is plenty: two seeds pick different squads and diverge
	# at the kick-off. If they had not, no amount of extra match would separate
	# them.
	var b := _run_match(SEED + 1, 10.0)
	check(a.ctx.telemetry.digest() != b.ctx.telemetry.digest(), "different seeds must produce different matches")


func _snapshots_do_not_perturb_the_sim(plain: SimMatch) -> void:
	# Presentation reads snapshots every frame. Doing so must not touch sim
	# state or consume a single random draw.
	var snap := SimSnapshot.new()
	var watched := _stepped(SEED, func(m: SimMatch) -> void: m.write_snapshot(snap))
	check_equal(plain.ctx.telemetry.digest(), watched.ctx.telemetry.digest(), "taking snapshots must not change the match")


func _reading_the_value_field_does_not_consume_randomness(plain: SimMatch) -> void:
	# What the debug view and the heat maps do.
	var probed := _stepped(SEED, func(m: SimMatch) -> void:
		if m.ctx.tick_index % 120 != 0:
			return
		m.ctx.value.refresh_debug_grid(m.ctx)
		m.ctx.value.xt_at(0, m.ctx.ball.pos, m.ctx.pitch))
	check_equal(plain.ctx.telemetry.digest(), probed.ctx.telemetry.digest(), "the debug grid must never be on the decision path")
