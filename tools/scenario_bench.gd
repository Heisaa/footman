class_name ScenarioBench
extends RefCounted
## `./run.sh scenario` — every named situation, run many times, as a table.
##
## The half of `SimScenario` that produces numbers. The other half is
## `./run.sh view3d --scenario NAME`, which puts the identical starting position
## on screen; read that file first for why the pair exists.
##
## **How to read a row.** The six outcome columns are shares of the trials and
## sum to 100%. `goal` and `saved` together are the shots that were worth
## taking, `off` is the finish, `blocked` belongs to the defence, `lost` is the
## situation ending before a shot at all, and `none` is the clock running out
## with the ball still ours and nothing struck -- which on a five-second
## one-on-one means he did not go for goal.
##
## **What a difference is worth.** Each row is n trials of a binomial, so the
## standard error on a share near a half is about `50/sqrt(n)` points: at the
## default 40 trials that is 8 points, and a row that moves by five has not
## moved. Raise `--trials` before believing a small change, and remember that
## the four variants are four different questions rather than four samples of
## one.
##
## Every trial is a different seed, so the squads differ between them: the
## situation is fixed and the players in it are not, which is the same choice
## every batch in this project makes. A scenario is a property of the rules, not
## of one striker.

## Trials per scenario. Forty is a couple of seconds a scenario and enough to
## see a big move; it is not enough to see a small one, and the header says so.
const TRIALS := 40
## Seeds start here so a scenario run is reproducible and does not collide with
## the golden replays' seeds.
const SEED_BASE := 4000


static func run(flags: Dictionary) -> void:
	var only := String(flags.get("only", ""))
	var trials := int(flags.get("trials", TRIALS))
	var quality := float(flags.get("quality", 0.6))
	var list: Array[SimScenario] = []
	for s in SimScenarios.all():
		if only == "" or s.name == only:
			list.append(s)
	if list.is_empty():
		print("no scenario named '%s'. known: %s" % [only, ", ".join(SimScenarios.names())])
		return

	print("Set situations, run forward  (%d trials each, %.1f s a trial, quality %.2f, standard clock)" % [
		trials, list[0].seconds, quality])
	print("  shares of how the situation ended, and they sum to 100")
	print("  %-16s %6s %6s %6s %6s %6s %6s | %7s %7s %7s" % [
		"", "goal", "saved", "off", "block", "lost", "none", "shot s", "shot m", "box s"])
	for s in list:
		print("  " + _row(s, trials, quality))
	print("  a share near a half carries about %.0f points of standard error at n=%d;" % [
		50.0 / sqrt(float(trials)), trials])
	print("  a row that moved by less than that has not moved. --trials N for more.")
	for s in list:
		print("  %-16s %s" % [s.name, s.title])


static func _row(s: SimScenario, trials: int, quality: float) -> String:
	var counts := PackedInt32Array()
	counts.resize(SimScenario.RESOLUTIONS.size())
	var shot_seconds := 0.0
	var shot_metres := 0.0
	var shots := 0
	var box_seconds := 0.0

	for i in trials:
		var opts := SimRunner.Options.new()
		opts.seed_value = SEED_BASE + i
		opts.home_quality = quality
		opts.away_quality = quality
		# Long enough that the match clock never runs out underneath a trial;
		# the scenario stops itself.
		opts.minutes = 90.0
		opts.scenario = s
		var m := SimRunner.build(opts)
		var r := s.run(m)
		counts[r.resolution] += 1
		box_seconds += r.box_seconds
		if r.to_shot >= 0.0:
			shots += 1
			shot_seconds += r.to_shot
			shot_metres += r.shot_from

	var n := float(trials)
	var parts := PackedStringArray()
	for c in counts:
		parts.append("%5.0f%%" % (100.0 * float(c) / n))
	var shot_n := maxf(float(shots), 1.0)
	return "%-16s %s | %7s %7s %7.2f" % [
		s.name, " ".join(parts),
		"%.2f" % (shot_seconds / shot_n) if shots > 0 else "-",
		"%.1f" % (shot_metres / shot_n) if shots > 0 else "-",
		box_seconds / n,
	]
