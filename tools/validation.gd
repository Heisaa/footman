class_name SimValidation
extends RefCounted
## The validation bands of PLAN.md §11, and the Phase 5 distinguishability test.
##
## Two layers, because they answer different questions and cost different
## amounts of wall clock (PLAN.md §11.1):
##
##   sanity  -- is this still football? Wide structural ranges that a working
##              but untuned engine passes and a broken one cannot. These decide
##              pass or fail on every run.
##   tuning  -- the §11 target table. Reported always, but advisory until the
##              tuning freeze: while the engine is still changing shape, a
##              tuning number out of band is information, not a failure.
##
## Every counting statistic is normalised to ninety minutes, so a gate run of
## short matches measures the same thing as a full-length one.

class Band extends RefCounted:
	enum Kind { SANITY, TUNING }
	enum Status { OK, OUT, UNDERSAMPLED }

	var label := ""
	var value := 0.0
	var low := 0.0
	var high := 0.0
	var unit := ""
	var kind := Kind.TUNING
	## Sample size below which this metric is noise. From the "converges by"
	## column of §11: quoting a score-draw rate off six matches is worse than
	## not quoting one.
	var min_n := 1

	func _init(p_label: String, p_value: float, p_low: float, p_high: float, p_unit: String = "", p_kind: int = Kind.TUNING, p_min_n: int = 1) -> void:
		label = p_label
		value = p_value
		low = p_low
		high = p_high
		unit = p_unit
		kind = p_kind
		min_n = p_min_n

	func status(n: int) -> Status:
		if n < min_n:
			return Status.UNDERSAMPLED
		return Status.OK if (value >= low and value <= high) else Status.OUT

	func ok() -> bool:
		return value >= low and value <= high

	## The measurement is always shown, even when the sample is too small to
	## judge it on: a number with "noisy at n=8" beside it tells the reader
	## where the engine is drifting, and a dash tells them nothing. What the
	## sample size changes is whether the verdict counts, not whether the
	## figure is printed.
	func line(n: int) -> String:
		var word := "range" if kind == Kind.SANITY else "target"
		var span := "%s %6.1f - %-6.1f" % [word, low, high]
		var where := "ok" if ok() else ("below" if value < low else "above")
		if status(n) == Status.UNDERSAMPLED:
			return "    %-24s %8.2f %-3s  %s  %-5s (noisy at n=%d, wants %d)" % [label, value, unit, span, where, n, min_n]
		if status(n) == Status.OUT:
			return "    %-24s %8.2f %-3s  %s  %s" % [label, value, unit, span, where.to_upper() + " BAND"]
		return "    %-24s %8.2f %-3s  %s  ok" % [label, value, unit, span]


## The aggregate quantities every band is derived from, normalised per ninety
## minutes and per team where that is what the band means.
static func _aggregate(all: Array[SimMatchStats], squad_size: int) -> Dictionary:
	var n: float = maxf(float(all.size()), 1.0)
	var acc := {
		"goals": 0.0, "shots": 0.0, "on_target": 0.0, "shots_total": 0.0,
		"passes": 0.0, "pass_completion": 0.0, "fouls": 0.0, "offsides": 0.0,
		"corners": 0.0, "distance": 0.0, "score_draws": 0.0, "all_draws": 0.0,
		"stronger_possession": 0.0, "minutes": 0.0,
	}
	for s in all:
		acc["minutes"] += s.minutes_played()
		acc["goals"] += s.per_90(float(s.total_goals()))
		for t in 2:
			acc["shots"] += s.per_90(float(s.shots[t]))
			acc["on_target"] += float(s.shots_on_target[t])
			acc["shots_total"] += float(s.shots[t])
			acc["passes"] += s.per_90(float(s.passes[t]))
			acc["pass_completion"] += s.pass_completion(t)
			acc["fouls"] += s.per_90(float(s.fouls[t]))
			acc["offsides"] += s.per_90(float(s.offsides[t]))
			acc["corners"] += s.per_90(float(s.corners[t]))
			acc["distance"] += s.per_90(s.km_per_player(t, squad_size))
		if s.is_draw():
			acc["all_draws"] += 1.0
			if s.score[0] > 0:
				acc["score_draws"] += 1.0
		# "Stronger" here means whoever ended with more of the ball; the batch
		# runner is what decides whether the sides differ in quality.
		acc["stronger_possession"] += maxf(s.possession[0], s.possession[1])

	var per_team := n * 2.0
	return {
		"n": int(n),
		"mean_minutes": acc["minutes"] / n,
		"goals": acc["goals"] / n,
		"shots": acc["shots"] / per_team,
		"on_target_share": 100.0 * acc["on_target"] / maxf(acc["shots_total"], 1.0),
		"possession": acc["stronger_possession"] / n,
		"pass_completion": acc["pass_completion"] / per_team,
		"passes": acc["passes"] / per_team,
		"fouls": acc["fouls"] / per_team,
		"offsides": acc["offsides"] / per_team,
		"corners": acc["corners"] / per_team,
		"distance": acc["distance"] / per_team,
		"score_draws": 100.0 * acc["score_draws"] / n,
		"all_draws": 100.0 * acc["all_draws"] / n,
	}


## Is this still football? Wide enough that any plausibly working engine passes
## without anyone having tuned a number, narrow enough that the failures that
## actually happen -- the ball never leaving the centre circle, passes at 30%,
## twenty goals a game, nobody ever shooting -- all trip a wire.
##
## These are the pass/fail criterion during the concept phase. They are not
## targets and nothing should ever be tuned toward them.
static func sanity_bands(all: Array[SimMatchStats], squad_size: int) -> Array[Band]:
	var a := _aggregate(all, squad_size)
	var K := Band.Kind.SANITY
	return [
		Band.new("goals per 90", a["goals"], 0.5, 8.0, "", K, 3),
		Band.new("shots per team", a["shots"], 3.0, 35.0, "", K, 3),
		Band.new("shots on target", a["on_target_share"], 15.0, 65.0, "%", K, 3),
		Band.new("possession, higher side", a["possession"], 50.0, 80.0, "%", K, 3),
		Band.new("pass completion", a["pass_completion"], 45.0, 95.0, "%", K, 2),
		Band.new("passes per team", a["passes"], 120.0, 900.0, "", K, 2),
		Band.new("fouls per team", a["fouls"], 1.0, 40.0, "", K, 5),
		Band.new("offsides per team", a["offsides"], 0.0, 12.0, "", K, 5),
		Band.new("corners per team", a["corners"], 0.5, 20.0, "", K, 5),
		Band.new("distance per player", a["distance"], 6.0, 15.0, "km", K, 2),
	]


## The §11 target table: where the engine should land once it is being tuned
## rather than being built. Every band carries the sample size it needs.
static func tuning_bands(all: Array[SimMatchStats], squad_size: int) -> Array[Band]:
	var a := _aggregate(all, squad_size)
	var K := Band.Kind.TUNING
	return [
		# Deliberately above the real 2.2-3.4: see PLAN.md §11.0.
		Band.new("goals per 90", a["goals"], 2.9, 4.1, "", K, 40),
		Band.new("shots per team", a["shots"], 8.0, 18.0, "", K, 40),
		Band.new("shots on target", a["on_target_share"], 30.0, 40.0, "%", K, 40),
		Band.new("possession, higher side", a["possession"], 52.0, 65.0, "%", K, 40),
		Band.new("pass completion", a["pass_completion"], 70.0, 87.0, "%", K, 20),
		Band.new("passes per team", a["passes"], 300.0, 600.0, "", K, 20),
		Band.new("fouls per team", a["fouls"], 8.0, 16.0, "", K, 40),
		Band.new("offsides per team", a["offsides"], 1.0, 4.0, "", K, 40),
		Band.new("corners per team", a["corners"], 3.0, 8.0, "", K, 40),
		Band.new("distance per player", a["distance"], 9.0, 12.0, "km", K, 20),
		# And deliberately below the real 20-28%.
		Band.new("score draws", a["score_draws"], 12.0, 22.0, "%", K, 200),
	]


## Prints both layers and returns the verdict.
##
## `strict` promotes the tuning table to a pass/fail criterion. That is the
## acceptance run and the tuning freeze; it is not what routine work runs
## against, because chasing a tuning number through a sim that is still
## changing shape is wasted effort (PLAN.md §11.1).
static func report(all: Array[SimMatchStats], squad_size: int, strict: bool = false) -> bool:
	var n := all.size()
	var a := _aggregate(all, squad_size)
	print("Validation over %d matches of %.0f min (%.0f match-minutes, %s)" % [
		n, a["mean_minutes"], a["mean_minutes"] * float(n),
		"strict: tuning bands count" if strict else "concept mode: tuning bands are advisory",
	])
	print("\n  sanity — is this still football? (PLAN.md §11)")
	var sane := true
	for b in sanity_bands(all, squad_size):
		print(b.line(n))
		if b.status(n) == Band.Status.OUT:
			sane = false

	print("\n  tuning — the §11 target table%s" % ("" if strict else ", advisory"))
	var tuned := true
	var in_band := 0
	var judged := 0
	for b in tuning_bands(all, squad_size):
		print(b.line(n))
		match b.status(n):
			Band.Status.OK:
				in_band += 1
				judged += 1
			Band.Status.OUT:
				judged += 1
				tuned = false

	print("\n  (all draws including 0-0: %.0f%%)" % a["all_draws"])
	var passed := sane and (tuned or not strict)
	var tuning_note := "%d of %d judgeable bands in band" % [in_band, judged]
	if judged == 0:
		tuning_note = "no tuning band has enough matches at n=%d — run the gate, then accept" % n
	print("\n%s   [sanity %s; tuning: %s]" % [
		"PASS" if passed else "FAIL",
		"ok" if sane else "BROKEN", tuning_note,
	])
	return passed


## A stronger squad must beat a weaker one roughly 60-70% of the time, not 95%.
## Football's low scoring means upsets are frequent; if attribute differences
## dominate outcomes, the noise in the system is tuned too tight.
static func upset_rate(all: Array[SimMatchStats]) -> Dictionary:
	var wins := 0
	var draws := 0
	var losses := 0
	for s in all:
		if s.score[0] > s.score[1]:
			wins += 1
		elif s.score[0] == s.score[1]:
			draws += 1
		else:
			losses += 1
	var n: float = maxf(float(all.size()), 1.0)
	return {
		"win_pct": 100.0 * float(wins) / n,
		"draw_pct": 100.0 * float(draws) / n,
		"loss_pct": 100.0 * float(losses) / n,
		"points_per_game": (3.0 * float(wins) + float(draws)) / n,
	}


# --- Phase 5: are two plans statistically distinguishable? -------------------


static func mean_of(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


static func sd_of(values: PackedFloat32Array) -> float:
	var n := values.size()
	if n < 2:
		return 0.0
	var m := mean_of(values)
	var acc := 0.0
	for v in values:
		acc += (v - m) * (v - m)
	return sqrt(acc / float(n - 1))


## Welch's t statistic for two independent samples.
static func welch_t(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var na: float = maxf(float(a.size()), 1.0)
	var nb: float = maxf(float(b.size()), 1.0)
	var va := sd_of(a) * sd_of(a) / na
	var vb := sd_of(b) * sd_of(b) / nb
	var denom := sqrt(va + vb)
	if denom < 1e-9:
		return 0.0
	return (mean_of(a) - mean_of(b)) / denom


static func _extract(all: Array[SimMatchStats], key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(all.size())
	for i in all.size():
		var s := all[i]
		match key:
			"possession":
				out[i] = s.possession[0]
			"pass_length":
				out[i] = s.mean_pass_length[0]
			"passes":
				out[i] = float(s.passes[0])
			"shots":
				out[i] = float(s.shots[0])
			"shot_distance":
				out[i] = s.mean_shot_distance[0]
			"recoveries":
				out[i] = float(s.recoveries[0])
			"duels":
				out[i] = float(s.duels[0])
			"distance":
				out[i] = s.distance[0] / 1000.0
			"fouls":
				out[i] = float(s.fouls[0])
			"goals_for":
				out[i] = float(s.score[0])
			"goals_against":
				out[i] = float(s.score[1])
			_:
				out[i] = 0.0
	return out


## Prints the Phase 5 exit criterion: two contrasting plans must produce
## statistically distinguishable match traces. If they do not, the tactical
## layer is a lie.
static func compare_plans(a: Array[SimMatchStats], b: Array[SimMatchStats], label_a: String = "high press, direct", label_b: String = "deep block, patient") -> bool:
	var metrics := ["possession", "pass_length", "passes", "shots", "shot_distance", "recoveries", "duels", "distance", "fouls", "goals_for", "goals_against"]
	print("Plan comparison: %s (n=%d) vs %s (n=%d)\n" % [label_a, a.size(), label_b, b.size()])
	print("  %-16s %10s %10s %9s  %s" % ["metric", "A", "B", "t", "verdict"])
	var distinguishable := 0
	for key in metrics:
		var va := _extract(a, key)
		var vb := _extract(b, key)
		var t := welch_t(va, vb)
		# |t| > 3 over samples this size is comfortably beyond noise.
		var significant: bool = absf(t) > 3.0
		if significant:
			distinguishable += 1
		print("  %-16s %10.2f %10.2f %9.1f  %s" % [key, mean_of(va), mean_of(vb), t, "distinct" if significant else "-"])
	var verdict := distinguishable >= 4
	print("\n%d of %d metrics separate the two plans. %s" % [
		distinguishable, metrics.size(),
		"TACTICS ARE REAL" if verdict else "TACTICAL LAYER IS COSMETIC - fix before proceeding",
	])
	# A small sample makes |t| > 3 harder to clear, not easier, so a pass here
	# is a real result at any size. A fail at a small size is a reason to look
	# again with more matches, not a conclusion (PLAN.md §10 Phase 5).
	if not verdict and mini(a.size(), b.size()) < 40:
		print("  (only %d and %d matches: rerun with --matches 40 before believing this)" % [a.size(), b.size()])
	return verdict
