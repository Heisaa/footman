extends SceneTree
## Which test the feint fails, per scenario.
##
## The feint (`SimDecision._add_feint`) is a candidate only when the carrier
## stands, a man is inside `FEINT_RANGE`, that man is closing at 1.5 m/s, and
## there is a scored probe across him. A zero in the acts table cannot say
## which of those it was, so this runs the situations built for it and reads
## `SimDecision.feint_gate` after each trial.
##     godot --headless --script res://tools/_feint_probe.gd

const SEEDS := 25
const ROWS := ["take-on", "hold-up", "1v1-chased", "pocket"]
const LOST_SLOTS := [SimDecision.LOST_N, SimDecision.LOST_SUCCESS, SimDecision.WON_SUCCESS,
	SimDecision.LOST_GAIN, SimDecision.WON_GAIN, SimDecision.LOST_LOSS, SimDecision.WON_LOSS,
	SimDecision.LOST_SCORE, SimDecision.WON_SCORE]


func _init() -> void:
	for name in ROWS:
		var s := SimScenarios.by_name(name)
		var gates := PackedInt32Array()
		gates.resize(SimDecision.FEINT_GATES.size())
		var offered := 0
		var played := 0
		var feints := 0
		var lost := {}
		for slot in LOST_SLOTS:
			lost[slot] = 0.0
		for i in SEEDS:
			var opts := SimRunner.Options.new()
			opts.seed_value = 1 + i
			opts.home_quality = 0.6
			opts.away_quality = 0.6
			opts.minutes = 90.0
			opts.scenario = s
			var m := SimRunner.build(opts)
			SimDecision.reset_rare()
			SimDecision.reset()
			var r := s.run(m)
			for slot in LOST_SLOTS:
				lost[slot] += SimDecision.lost_at(SimDecision.Action.FEINT, slot)
			feints += r.feints
			for g in SimDecision.FEINT_GATES.size():
				gates[g] += SimDecision.feint_gate[g]
			offered += SimDecision.rare_offered[SimDecision.RARE_FEINT]
			played += SimDecision.rare_played[SimDecision.RARE_FEINT]
		var parts := PackedStringArray()
		for g in SimDecision.FEINT_GATES.size():
			parts.append("%s %d" % [SimDecision.FEINT_GATES[g], gates[g]])
		print("%-12s %s | offered %d, played %d, feints logged %d" % [
			name, ",  ".join(parts), offered, played, feints])
		var n: float = lost[SimDecision.LOST_N]
		if n > 0.0:
			print("             lost %d times: success %.2f v %.2f  gain %.4f v %.4f  loss %.4f v %.4f  score gap %+.4f" % [
				int(n),
				lost[SimDecision.LOST_SUCCESS] / n, lost[SimDecision.WON_SUCCESS] / n,
				lost[SimDecision.LOST_GAIN] / n, lost[SimDecision.WON_GAIN] / n,
				lost[SimDecision.LOST_LOSS] / n, lost[SimDecision.WON_LOSS] / n,
				(lost[SimDecision.LOST_SCORE] - lost[SimDecision.WON_SCORE]) / n])
	quit()
