extends SceneTree
## The headless entry point (PLAN.md §2.1).
##
## It is both the tuning tool and the architectural enforcement mechanism: the
## simulation must be runnable with rendering entirely absent, so if this stops
## working, the sim/presentation separation has been violated.
##
##   godot --headless --script res://tools/headless_main.gd -- <command> [args]
##
## Commands:
##   match       one match, printed as a summary
##   diagnose    one match, broken down by touch, pass and third
##   batch       N matches, aggregated against the §11 validation bands
##   aggregate   judge a directory of shard JSON without re-simulating
##   compare     judge two shard directories against each other
##   determinism one seed run twice, event logs compared
##   perf        timing of a full-fidelity match
##   tactics     two contrasting plans compared (the §10 Phase 5 exit criterion)
##   replay      every decision around one tick of one seed, in words
##   behind      the ball in behind, struck in a geometry set rather than sampled
##
## Flags worth knowing: --minutes M (counts are normalised per 90, so a short
## batch is a legitimate measurement of a rate), --clock-rate R (match-clock
## seconds per simulated second: a full match on a compressed clock, rather than
## a fraction of one), --reduced (the §2.5 tier-2 cadence), --strict (promote the
## tuning bands to pass/fail), --plan press|block and --away-plan, which is how
## the two arms of the Phase 5 test shard.
##
## --minutes and --clock-rate are not the same measurement and are easy to
## confuse. `--minutes 10` plays the first ten minutes of a match and stops;
## `--clock-rate 10` plays all ninety, kick-off to full time, in nine minutes
## of football. The first samples a rate, the second changes what a match is.
##
## **--clock-rate defaults to 10 and should be left there.** The nine-minute
## match is the match that ships and the one every number is tuned to, so every
## command here measures it by default. `--clock-rate 1` measures a match nobody
## plays; `--urgency U` is the way to ask about the scoring fit on its own.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var command := args[0] if args.size() > 0 else "match"
	var flags := _parse_flags(args)

	match command:
		"match":
			_cmd_match(flags)
		"batch":
			_cmd_batch(flags)
		"determinism":
			_cmd_determinism(flags)
		"perf":
			_cmd_perf(flags)
		"tactics":
			_cmd_tactics(flags)
		"diagnose":
			_cmd_diagnose(flags)
		"chains":
			_cmd_chains(flags)
		"aggregate":
			_cmd_aggregate(flags)
		"compare":
			_cmd_compare(flags)
		"replay":
			_cmd_replay(flags)
		"behind":
			BehindBench.run(flags)
		"box":
			BoxBench.run(flags)
		"strike":
			StrikeBench.run(flags)
		_:
			printerr("unknown command: %s" % command)
			quit(2)
			return
	quit(0)


func _parse_flags(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 1
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[key] = args[i + 1]
				i += 2
			else:
				out[key] = "true"
				i += 1
		else:
			i += 1
	return out


func _options(flags: Dictionary) -> SimRunner.Options:
	var o := SimRunner.Options.new()
	o.seed_value = int(flags.get("seed", "1"))
	o.home_quality = float(flags.get("home", "0.6"))
	o.away_quality = float(flags.get("away", "0.6"))
	o.minutes = float(flags.get("minutes", "90"))
	o.clock_rate = float(flags.get("clock-rate", "10"))
	o.pitch_scale = float(flags.get("pitch-scale", "1"))
	o.urgency = float(flags.get("urgency", "-1"))
	o.small_sided = flags.has("small")
	o.wet = flags.has("wet")
	o.trace = flags.has("trace")
	o.events = not flags.has("no-events")
	if flags.has("reduced"):
		o.fidelity = SimMatchConfig.Fidelity.REDUCED
	if flags.has("home-formation"):
		o.home_formation = flags["home-formation"]
	if flags.has("away-formation"):
		o.away_formation = flags["away-formation"]
	if flags.has("plan"):
		o.home_tactics = _plan_by_name(flags["plan"])
	if flags.has("away-plan"):
		o.away_tactics = _plan_by_name(flags["away-plan"])
	return o


## Named tactical plans, so a batch can be pointed at one arm of the Phase 5
## comparison from the command line and the two arms can then be sharded across
## processes like any other batch.
static func _plan_by_name(name: String) -> SimTactics:
	match name:
		"press", "high_press_direct":
			return SimTactics.high_press_direct()
		"block", "deep_block_patient":
			return SimTactics.deep_block_patient()
		_:
			return SimTactics.balanced()


# --- Commands ---------------------------------------------------------------


func _cmd_match(flags: Dictionary) -> void:
	var opts := _options(flags)
	var m := SimRunner.build(opts)
	var started := Time.get_ticks_usec()
	m.run_to_completion()
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	var s := SimMatchStats.collect(m)
	var squad := m.ctx.teams[0].players.size()

	print("%s %d - %d %s   (seed %d, %.0f ms, %d ticks)" % [
		m.ctx.teams[0].club_name, s.score[0], s.score[1], m.ctx.teams[1].club_name,
		opts.seed_value, elapsed, s.ticks,
	])
	print("  team rating          %.3f / %.3f" % [m.ctx.teams[0].rating(), m.ctx.teams[1].rating()])
	print("  shots                %d / %d" % [s.shots[0], s.shots[1]])
	print("  on target            %d / %d  (%.0f%% / %.0f%%)" % [s.shots_on_target[0], s.shots_on_target[1], s.on_target_share(0), s.on_target_share(1)])
	print("  possession           %.0f%% / %.0f%%" % [s.possession[0], s.possession[1]])
	print("  passes               %d / %d" % [s.passes[0], s.passes[1]])
	print("  pass completion      %.0f%% / %.0f%%" % [s.pass_completion(0), s.pass_completion(1)])
	print("  mean pass length     %.1f m / %.1f m" % [s.mean_pass_length[0], s.mean_pass_length[1]])
	print("  fouls                %d / %d" % [s.fouls[0], s.fouls[1]])
	print("  cards                %d / %d" % [s.cards[0], s.cards[1]])
	print("  offsides             %d / %d" % [s.offsides[0], s.offsides[1]])
	print("  corners              %d / %d" % [s.corners[0], s.corners[1]])
	print("  saves                %d / %d" % [s.saves[0], s.saves[1]])
	print("  duels                %d / %d" % [s.duels[0], s.duels[1]])
	print("  recoveries           %d / %d" % [s.recoveries[0], s.recoveries[1]])
	print("  touches              %d / %d" % [s.touches[0], s.touches[1]])
	print("  throw-ins            %d / %d" % [s.throw_ins[0], s.throw_ins[1]])
	print("  distance per player  %.1f km / %.1f km" % [s.km_per_player(0, squad), s.km_per_player(1, squad)])
	print("  final mean stamina   %.2f / %.2f" % [s.final_stamina[0], s.final_stamina[1]])
	print("  events logged        %d" % m.ctx.telemetry.events.size())


func _cmd_diagnose(flags: Dictionary) -> void:
	var opts := _options(flags)
	# Chase geometry is a positional question, so diagnose always pays for the
	# trace. It is 5 Hz and one match; the cost does not show up next to the sim.
	opts.trace = true
	# The near-tie experiment needs every decision in the match, and six ints a
	# decision is nothing. Always on here for the same reason as the trace, and off
	# everywhere else so a batch does not carry it.
	SimChoices.enabled = true
	# Asked for rather than always on, though not for the reason it looks like.
	# Nineteen extra scorings of the list per decision costs about 4% of a
	# diagnose run -- candidate generation is what a decision costs, and scoring
	# it again is nearly free. It is a flag because it answers a question about
	# the scoring rather than about the football, and the table is twenty lines.
	SimAblation.enabled = flags.has("ablate")
	var m := SimRunner.build(opts)
	m.run_to_completion()
	var s := SimMatchStats.collect(m)
	print("%s %d - %d %s\n" % [m.ctx.teams[0].short_name, s.score[0], s.score[1], m.ctx.teams[1].short_name])
	SimDiagnostics.report(m)


## The chains over several matches, saved or set against a saved run.
##
## The block `diagnose` prints says where an attack stops. This says what a change
## *did* to that, which is a different question and the one that keeps getting
## answered by eye across two terminal scrollbacks.
##
## Several matches rather than one, and it is not fussiness. A code change moves the
## match wholesale -- two runs of one seed become different football within seconds
## of the first different decision -- so a one-seed diff measures a different match
## and not the change. `docs/THE_FOOTBALL.md` 19 is the same trap stated in full. Five
## seeds is not a sample either; it is enough that a conversion moving ten points is
## worth looking at.
##
## Only the chain counts are kept, so a saved run is a few hundred bytes and can sit
## in the repo across a change.
func _cmd_chains(flags: Dictionary) -> void:
	# Checked before a single tick is simulated. `minutes` defaults to a full match
	# everywhere else in this file, so the bare command is five ninety-minute games
	# -- and it used to run all five before saying it had nowhere to put them.
	if not flags.has("out") and not flags.has("against"):
		printerr("nothing to do: pass --out FILE to save a run, or --against FILE to compare one")
		return
	# Two of the four chains start at a decision rather than at a spell, and the
	# first three links of each are unreachable from the log. Without this they
	# come back empty and the diff silently compares two of them instead of four.
	SimChoices.enabled = true
	var count := int(flags.get("matches", "5"))
	var opts := _options(flags)
	var base := opts.seed_value
	var run := {}
	for i in count:
		opts = _options(flags)
		opts.seed_value = base + i
		var m := SimRunner.build(opts)
		m.run_to_completion()
		SimDiagnostics.accumulate(run, SimDiagnostics.measure(m),
			SimMatchStats.collect(m).clock / 60.0)
		print("  match %d of %d (seed %d)" % [i + 1, count, opts.seed_value])
	if flags.has("out"):
		var file := FileAccess.open(flags["out"], FileAccess.WRITE)
		if file == null:
			printerr("could not write %s" % flags["out"])
			return
		file.store_string(JSON.stringify(run))
		file.close()
		print("saved %s" % flags["out"])
	if not flags.has("against"):
		return
	var before := _read_run(flags["against"])
	if before.is_empty():
		return
	print("")
	SimDiagnostics.chain_diff(before, run)


func _read_run(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("could not read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("chains"):
		printerr("%s is not a saved chains run" % path)
		return {}
	return parsed


## Everything the engine decided in a window around one tick, as sentences.
##
## The other half of the debug overlay's bookmark: the overlay marks a moment
## with a seed and a tick, and this re-simulates that seed and says what the
## players were choosing between there. Same seed, same match, no display, so a
## complaint about something seen on screen can be answered from a report.
##
## The window is deliberately small. Ten seconds of football is twenty or thirty
## decisions; a minute of it is the waterfall this tool exists to avoid.
func _cmd_replay(flags: Dictionary) -> void:
	var tick := int(flags.get("tick", "-1"))
	if tick < 0:
		printerr("replay needs --tick T (the tick a bookmark marked); --around S sets the window")
		return
	var around := float(flags.get("around", "6"))
	var half := int(around * float(SimConsts.TICK_HZ))
	var from_tick := maxi(tick - half, 0)
	var to_tick := tick + half

	var opts := _options(flags)
	SimDebug.enabled = true
	SimDebug.reset()
	var m := SimRunner.build(opts)
	# The clock at the marked tick, not at the end of the window: on a compressed
	# clock the two are minutes apart.
	var marked_clock := 0.0
	while not m.finished and m.ctx.tick_index <= to_tick:
		if m.ctx.tick_index == tick:
			marked_clock = m.ctx.clock
		m.tick()
	SimDebug.enabled = false

	var ctx := m.ctx
	print("seed %d, tick %d (%s), %s %d - %d %s" % [
		opts.seed_value, tick, SimDebug.clock_text(marked_clock),
		ctx.teams[0].short_name, ctx.score[0], ctx.score[1], ctx.teams[1].short_name,
	])
	print("window %d..%d, %.0f s either side\n" % [from_tick, to_tick, around])

	# Decisions and events interleaved, because half of reading a passage back is
	# seeing which came first.
	var rows := []
	for rec in SimDebug.between(from_tick, to_tick):
		rows.append([int(rec["tick"]), 1, rec])
	for e in ctx.telemetry.events:
		var t := int(e["t"])
		if t < from_tick or t > to_tick:
			continue
		if SimDebug.event_text(ctx, e) != "":
			rows.append([t, 0, e])
	rows.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])

	if rows.is_empty():
		print("nothing decided or logged in that window")
		return
	for row in rows:
		var at: int = row[0]
		var marker := " <-" if absi(at - tick) <= 1 else ""
		if row[1] == 0:
			print("t%-7d  %s%s" % [at, SimDebug.event_text(ctx, row[2]), marker])
			continue
		var lines := SimDebug.describe(row[2])
		for i in lines.size():
			if i == 0:
				print("t%-7d  %s%s" % [at, lines[0], marker])
			else:
				print("           %s" % lines[i])


func _cmd_batch(flags: Dictionary) -> void:
	var count := int(flags.get("matches", "40"))
	var opts := _options(flags)
	var quiet := flags.has("quiet")
	var progress_path: String = flags.get("progress", "")
	if not quiet:
		print("Running %d matches from seed %d ..." % [count, opts.seed_value])
	var started := Time.get_ticks_usec()

	# Run the matches here rather than in SimRunner.run_batch, so progress can
	# be reported after each one. A batch is minutes long; going silent for the
	# duration means a run that has obviously gone wrong is discovered at the
	# end instead of after the second match.
	var all: Array[SimMatchStats] = []
	var goals := 0
	var shots := 0
	var draws := 0
	for i in count:
		var o := SimRunner._clone(opts)
		o.seed_value = opts.seed_value + i
		var s := SimRunner.run_one(o)
		all.append(s)
		goals += s.total_goals()
		shots += s.shots[0] + s.shots[1]
		if s.is_draw():
			draws += 1
		if progress_path != "":
			_write_progress(progress_path, i + 1, count, goals, shots, draws)
		elif not quiet:
			var so_far := float(i + 1)
			print("  %d/%d   goals/match %.2f   shots/team %.1f   draws %.0f%%" % [
				i + 1, count, float(goals) / so_far, float(shots) / (so_far * 2.0),
				100.0 * float(draws) / so_far,
			])
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0

	# A shard of a parallel run writes its results out instead of judging them;
	# the aggregate command does the judging once, over every shard.
	if flags.has("json"):
		var rows := []
		for s in all:
			rows.append(s.to_dict())
		var file := FileAccess.open(flags["json"], FileAccess.WRITE)
		if file == null:
			printerr("could not write %s" % flags["json"])
			return
		file.store_string(JSON.stringify(rows))
		file.close()
	if quiet:
		return
	print("Done in %.1f s (%.0f ms per match)\n" % [elapsed / 1000.0, elapsed / float(count)])
	var squad := 6 if opts.small_sided else 11
	SimValidation.report(all, squad, flags.has("strict"))
	_print_upsets(all, opts)


## One line, rewritten after every match, for the driver to poll. Deliberately
## trivial to parse: a shard has no idea what the other shards are doing, and
## summing six small integers is the driver's whole job.
func _write_progress(path: String, done: int, total: int, goals: int, shots: int, draws: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	# The trailing newline matters: without it a shell `read` hits EOF, returns
	# non-zero, and a caller that treats that as failure discards a line it has
	# already parsed perfectly well.
	file.store_string("%d %d %d %d %d\n" % [done, total, goals, shots, draws])
	file.close()


## Reads every shard in a directory into one result set.
func _load_shards(dir_path: String) -> Array[SimMatchStats]:
	var all: Array[SimMatchStats] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("could not open %s" % dir_path)
		return all
	var names := PackedStringArray()
	for name in dir.get_files():
		if name.ends_with(".json"):
			names.append(name)
	# Fixed order, so the aggregate of a given set of shards is reproducible.
	names.sort()
	for name in names:
		var file := FileAccess.open(dir_path.path_join(name), FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if not (parsed is Array):
			printerr("shard %s is not a result array" % name)
			continue
		for row in parsed:
			all.append(SimMatchStats.from_dict(row))
	return all


## Reads every shard in a directory and judges them together.
func _cmd_aggregate(flags: Dictionary) -> void:
	var dir_path: String = flags.get("dir", "")
	if dir_path == "":
		printerr("aggregate needs --dir")
		return
	var all := _load_shards(dir_path)
	if all.is_empty():
		printerr("no results found in %s" % dir_path)
		return
	var shards := 0
	for name in DirAccess.open(dir_path).get_files():
		if name.ends_with(".json"):
			shards += 1

	var opts := _options(flags)
	var squad := 6 if opts.small_sided else 11
	print("%d shards, %d matches\n" % [shards, all.size()])
	SimValidation.report(all, squad, flags.has("strict"))
	_print_upsets(all, opts)


## PLAN.md §11: a stronger squad must beat a weaker one roughly 60-70% of the
## time. Only meaningful when the batch actually pitted unequal sides.
func _print_upsets(all: Array[SimMatchStats], opts: SimRunner.Options) -> void:
	if absf(opts.home_quality - opts.away_quality) < 0.02:
		return
	var r := SimValidation.upset_rate(all)
	var stronger := "home" if opts.home_quality > opts.away_quality else "away"
	print("\nStronger side (%s, %.2f vs %.2f): %.0f%% wins, %.0f%% draws, %.0f%% losses, %.2f points per game" % [
		stronger, opts.home_quality, opts.away_quality,
		r["win_pct"] if stronger == "home" else r["loss_pct"],
		r["draw_pct"],
		r["loss_pct"] if stronger == "home" else r["win_pct"],
		r["points_per_game"],
	])
	print("  (PLAN.md §11 wants the stronger squad winning roughly 60-70%% of the time, not 95%%%s)" % [
		"" if all.size() >= 40 else "; noisy at n=%d" % all.size(),
	])


func _cmd_determinism(flags: Dictionary) -> void:
	var opts := _options(flags)
	# `--debug` runs the first pass with the capture sink on and the second with
	# it off. Identical digests are the proof that the sink is a one-way tap:
	# nothing in the sim reads it and it never touches `ctx.rng`.
	SimDebug.enabled = flags.has("debug")
	var a := SimRunner.build(opts)
	a.run_to_completion()
	SimDebug.enabled = false
	SimDebug.reset()
	var b := SimRunner.build(opts)
	b.run_to_completion()
	var da := a.ctx.telemetry.digest()
	var db := b.ctx.telemetry.digest()
	print("seed %d" % opts.seed_value)
	print("  run A: %d events, digest %s" % [a.ctx.telemetry.events.size(), da.substr(0, 16)])
	print("  run B: %d events, digest %s" % [b.ctx.telemetry.events.size(), db.substr(0, 16)])
	if da == db:
		print("  IDENTICAL")
	else:
		printerr("  DIVERGED")
		var ea := a.ctx.telemetry.events
		var eb := b.ctx.telemetry.events
		for i in mini(ea.size(), eb.size()):
			if str(ea[i]) != str(eb[i]):
				printerr("  first difference at event %d:" % i)
				printerr("    A: %s" % str(ea[i]))
				printerr("    B: %s" % str(eb[i]))
				break


func _cmd_perf(flags: Dictionary) -> void:
	var count := int(flags.get("matches", "5"))
	var opts := _options(flags)
	opts.events = not flags.has("no-events")
	var total := 0.0
	var worst := 0.0
	var stages := {}
	for i in count:
		var o := SimRunner._clone(opts)
		o.seed_value = opts.seed_value + i
		var m := SimRunner.build(o)
		m.profile_enabled = flags.has("profile")
		var t := Time.get_ticks_usec()
		m.run_to_completion()
		var ms := float(Time.get_ticks_usec() - t) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		for key in m.profile:
			stages[key] = float(stages.get(key, 0.0)) + float(m.profile[key]) / 1000.0
		print("  match %d: %.0f ms, %d ticks, %d events" % [i + 1, ms, m.ctx.tick_index, m.ctx.telemetry.events.size()])
	if not stages.is_empty():
		var keys := stages.keys()
		keys.sort_custom(func(a, b): return float(stages[a]) > float(stages[b]))
		print("\n  stage breakdown (mean ms per match):")
		for key in keys:
			print("    %-16s %8.0f ms  %5.1f%%" % [key, float(stages[key]) / float(count), 100.0 * float(stages[key]) / maxf(total, 1.0)])
	var mean := total / float(count)
	var ticks_per_match: float = maxf(opts.minutes * 60.0 * float(SimConsts.TICK_HZ), 1.0)
	print("\nmean %.0f ms per full-fidelity match, worst %.0f ms" % [mean, worst])
	print("  real time per simulated second: %.2f ms" % (mean / (opts.minutes * 60.0)))
	print("  speed-up over real time:        %.0fx" % (opts.minutes * 60.0 * 1000.0 / mean))
	# At 1x the presentation advances the sim one tick per rendered frame, so
	# the per-tick cost is what has to fit inside the 16.7 ms frame budget.
	print("  cost of one tick:               %.3f ms  (%.1f%% of a 16.7 ms frame)" % [
		mean / ticks_per_match, 100.0 * (mean / ticks_per_match) / 16.7,
	])


## The serial path. `./run.sh tactics` shards both arms across processes and
## calls `compare` instead; this stays for a handful of matches and for anyone
## driving the tool directly.
func _cmd_tactics(flags: Dictionary) -> void:
	var count := int(flags.get("matches", "12"))
	var opts := _options(flags)
	print("Comparing two contrasting plans over %d matches each ...\n" % count)

	var press := SimRunner._clone(opts)
	press.home_tactics = SimTactics.high_press_direct()
	press.away_tactics = SimTactics.balanced()
	var press_stats := SimRunner.run_batch(press, count, maxi(count / 4, 1))

	var block := SimRunner._clone(opts)
	block.home_tactics = SimTactics.deep_block_patient()
	block.away_tactics = SimTactics.balanced()
	var block_stats := SimRunner.run_batch(block, count, maxi(count / 4, 1))

	SimValidation.compare_plans(press_stats, block_stats)


## Judges two already-simulated sets of shards against each other. This is what
## makes the distinguishability test parallel: each arm is an ordinary batch
## with `--plan`, so both shard across cores like anything else.
func _cmd_compare(flags: Dictionary) -> void:
	var dir_a: String = flags.get("dir-a", "")
	var dir_b: String = flags.get("dir-b", "")
	if dir_a == "" or dir_b == "":
		printerr("compare needs --dir-a and --dir-b")
		return
	var a := _load_shards(dir_a)
	var b := _load_shards(dir_b)
	if a.is_empty() or b.is_empty():
		printerr("compare found no results (%d in A, %d in B)" % [a.size(), b.size()])
		return
	SimValidation.compare_plans(a, b, flags.get("label-a", "high press, direct"), flags.get("label-b", "deep block, patient"))
