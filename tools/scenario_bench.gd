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
## **`touch`, `gap s` and `back` are the three that say whether the football was
## real**, which the outcome columns cannot: a goal scored off a keeper who
## handed the ball back is a goal in the `goal` column and nowhere else
## (owner, 2026-08-23, watching `1v1-clear`).
##
## - `touch` is touches by the attacking side per trial. A man carrying the ball
##   takes one about every three tenths of a second, so a one-on-one that runs
##   four seconds and shows two touches is a ball travelling on its own.
## - `gap s` is the longest stretch in a trial that the ball went untouched by
##   anybody with nothing struck -- so a hanging cross does not count, and a ball
##   rolling away from the man meant to have it does. It is the same failure as a
##   low `touch` seen from the other side, and the pair is worth having because a
##   single long gap and a carry that is generally loose read alike in one and
##   not in the other.
## - `back` is the share of trials where the defence touched the ball and the
##   attacking side had it again within a second. Some of that is a rebound off a
##   block and is football. A third of a row is not.
##
## `cross` is crosses struck per trial and `drop m` how far the nearest of ours
## was from the ball when the first of them came down through heading height.
## The pair separates the two ways a cross fails, which are fixed in different
## files: a ball nobody put in, and a ball nobody attacked
## (`docs/THE_FOOTBALL.md` 29). A dash means no cross came down in any trial.
##
## **What a difference is worth.** Each row is n trials of a binomial, so the
## standard error on a share near a half is about `50/sqrt(n)` points: at the
## default 40 trials that is 8 points, and a row that moves by five has not
## moved. Raise `--trials` before believing a small change, and remember that
## the four variants are four different questions rather than four samples of
## one.
##
## **Three instruments, and they are meant to be used in order.** The table says
## how often; `--acts` says what was played, which is the only way to tell an act
## that is never generated from one that is chosen and fails; `--trace N` prints
## one trial's event log in order, which is where a row that reads wrong is
## finally explained.
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

	print("Set situations, run forward  (%d trials each, quality %.2f, standard clock)" % [
		trials, quality])
	print("  shares of how the situation ended, and they sum to 100")
	print("  %-16s %6s %6s %6s %6s %6s %6s | %6s %6s %5s %6s %6s | %5s %5s %5s %5s" % [
		"", "goal", "saved", "off", "block", "lost", "none",
		"shot s", "shot m", "box s", "cross", "drop m",
		"touch", "gap s", "away", "back"])
	for s in list:
		print("  " + _row(s, trials, quality))
	print("  a share near a half carries about %.0f points of standard error at n=%d;" % [
		50.0 / sqrt(float(trials)), trials])
	print("  a row that moved by less than that has not moved. --trials N for more.")
	for s in list:
		print("  %-16s %.0f s  %s" % [s.name, s.seconds, s.title])
		print("  %-16s       expect: %s" % ["", s.expect])
	if flags.has("acts"):
		_acts(list, trials, quality)
	if flags.has("trace"):
		_trace(list, int(flags.get("trace", 0)), quality)


## `--trace N`: every event of trial N of each selected scenario, in order.
##
## The third instrument, and the one the other two send you to. A share says a
## situation ends badly and the act histogram says which act was played; only
## the order of events says a keeper caught it at 2.6 s and the striker had it
## back at 3.3.
static func _trace(list: Array[SimScenario], index: int, quality: float) -> void:
	for s in list:
		var opts := SimRunner.Options.new()
		opts.seed_value = SEED_BASE + index
		opts.home_quality = quality
		opts.away_quality = quality
		opts.minutes = 90.0
		opts.scenario = s
		var m := SimRunner.build(opts)
		s.traced = true
		var r := s.run(m)
		s.traced = false
		print("")
		print("%s, trial %d (seed %d): %s -> %s" % [
			s.name, index, SEED_BASE + index, s.title,
			SimScenario.RESOLUTIONS[r.resolution]])
		for entry in r.log:
			var e: Dictionary = entry[1]
			var kind: int = e["ev"]
			var ev_name: String = SimTelemetry.EV_NAMES[kind]
			var who := ""
			var team: int = int(e.get("team", -1))
			if team >= 0:
				who = "us" if team == s.attacking_team else "them"
			var extra := PackedStringArray()
			if kind == SimTelemetry.Ev.TOUCH:
				extra.append(SimTelemetry.TOUCH_NAMES[int(e.get("kind", 0))])
			for key in ["player", "target", "on_target", "goal", "blocked", "outcome", "reason", "ahead", "head", "chance", "hit"]:
				if e.has(key):
					extra.append("%s=%s" % [key, e[key]])
			if e.get("from") is Vector3:
				var at: Vector3 = e["from"]
				extra.append("from=(%.0f,%.0f)" % [at.x, at.z])
			elif e.has("from"):
				extra.append("from=%s" % e["from"])
			print("  %5.2f  %-14s %-4s %s" % [entry[0], ev_name, who, " ".join(extra)])


## `--acts`: what was actually played, per trial, in each situation.
##
## The outcome table says how a situation ended and cannot say why. This says
## which acts the attacking side chose, and it is the only one of the two that
## separates **an act that is never a candidate from an act that is chosen and
## fails** -- the distinction `docs/THE_FOOTBALL.md` says this project has been
## caught by three times. A column of zeroes under `header` in a corner is not a
## heading problem.
static func _acts(list: Array[SimScenario], trials: int, quality: float) -> void:
	var shown := PackedInt32Array()
	var rows := {}
	for s in list:
		var totals := PackedInt32Array()
		totals.resize(SimTelemetry.TOUCH_NAMES.size() + 4)
		for i in trials:
			var opts := SimRunner.Options.new()
			opts.seed_value = SEED_BASE + i
			opts.home_quality = quality
			opts.away_quality = quality
			opts.minutes = 90.0
			opts.scenario = s
			var r := s.run(SimRunner.build(opts))
			for k in r.acts.size():
				totals[k] += r.acts[k]
			totals[totals.size() - 4] += r.duels
			totals[totals.size() - 3] += r.offsides
			totals[totals.size() - 2] += r.fouls
			totals[totals.size() - 1] += r.feints
		rows[s.name] = totals
		for k in totals.size():
			if totals[k] > 0 and not shown.has(k):
				shown.append(k)
	shown.sort()

	var names := PackedStringArray()
	for k in shown:
		if k < SimTelemetry.TOUCH_NAMES.size():
			names.append(SimTelemetry.TOUCH_NAMES[k].substr(0, 5))
		else:
			names.append(["duel", "ofsd", "foul", "feint"][k - SimTelemetry.TOUCH_NAMES.size()])
	print("")
	print("What the attacking side played, per trial  (touch kinds, then duels, offsides, fouls, feints)")
	print("  a kind nothing ever played is not a column: the act was never chosen anywhere")
	var head := "  %-16s" % ""
	for n in names:
		head += " %5s" % n
	print(head)
	for s in list:
		var line := "  %-16s" % s.name
		for k in shown:
			var v: float = float(rows[s.name][k]) / float(trials)
			line += " %5s" % ("    ." if v == 0.0 else "%5.1f" % v)
		print(line)


static func _row(s: SimScenario, trials: int, quality: float) -> String:
	var counts := PackedInt32Array()
	counts.resize(SimScenario.RESOLUTIONS.size())
	var shot_seconds := 0.0
	var shot_metres := 0.0
	var shots := 0
	var box_seconds := 0.0
	var crosses := 0
	var drop_total := 0.0
	var drops := 0
	var touches := 0
	var gap_total := 0.0
	var drift_total := 0.0
	var given_back := 0

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
		crosses += r.crosses
		touches += r.touches
		gap_total += r.carry_gap
		drift_total += r.carry_drift
		if r.given_back:
			given_back += 1
		if r.drop_gap >= 0.0:
			drops += 1
			drop_total += r.drop_gap
		if r.to_shot >= 0.0:
			shots += 1
			shot_seconds += r.to_shot
			shot_metres += r.shot_from

	var n := float(trials)
	var parts := PackedStringArray()
	for c in counts:
		parts.append("%5.0f%%" % (100.0 * float(c) / n))
	var shot_n := maxf(float(shots), 1.0)
	return "%-16s %s | %6s %6s %5.2f %6.2f %6s | %5.1f %5.2f %5.2f %4.0f%%" % [
		s.name, " ".join(parts),
		"%.2f" % (shot_seconds / shot_n) if shots > 0 else "-",
		"%.1f" % (shot_metres / shot_n) if shots > 0 else "-",
		box_seconds / n,
		float(crosses) / n,
		"%.1f" % (drop_total / float(drops)) if drops > 0 else "-",
		float(touches) / n,
		gap_total / n,
		drift_total / n,
		100.0 * float(given_back) / n,
	]
