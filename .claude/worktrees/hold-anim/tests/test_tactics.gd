class_name TestTactics
extends SimTestCase
## The Phase 5 exit criterion, in miniature (PLAN.md §10).
##
## Two contrasting plans must produce statistically distinguishable match
## traces. If they do not, the tactical layer is a lie -- so this runs on every
## test pass rather than only when someone remembers to check.
##
## The real version is `./run.sh tactics`, which shards both arms across cores
## and can afford full-length matches; this is the cheap directional check that
## belongs in the ordinary suite.
##
## Sixteen matches at eighteen minutes was six hundred seconds, most of the
## suite's wall clock on its own. The metrics compared here -- possession share,
## mean pass length, passes, distance, shot distance -- are all *rates*, and a
## rate is well estimated from a short match, so shortening the matches costs
## almost no discrimination while the sample size, which is what sets the
## degrees of freedom, is barely touched.
const SAMPLE := 7
const MINUTES := 8.0


func run() -> void:
	_modifiers_move_in_the_right_direction()
	_plans_are_distinguishable()
	_every_tactical_axis_is_a_modifier()


func _modifiers_move_in_the_right_direction() -> void:
	var press := SimTactics.high_press_direct()
	var block := SimTactics.deep_block_patient()
	var pitch := SimPitch.regulation()
	check_greater(press.engage_distance(), block.engage_distance(), "a high press engages further from goal")
	check_greater(press.line_x(pitch), block.line_x(pitch), "a high press defends higher up the pitch")
	check_greater(press.press_commitment(), block.press_commitment(), "and sends more players at the ball")
	check_greater(press.direct_bias(), block.direct_bias(), "a direct plan values the forward ball more")
	check_greater(block.retention_bias(), press.retention_bias(), "a patient plan values keeping the ball more")
	check_less(press.future_discount(), block.future_discount(), "a high-tempo plan discounts the future harder")
	check_less(press.risk_weight(), block.risk_weight(), "and is less afraid of losing the ball")


func _plans_are_distinguishable() -> void:
	var press := _sample(SimTactics.high_press_direct(), 500)
	var block := _sample(SimTactics.deep_block_patient(), 500)

	var separated := 0
	for key in ["possession", "pass_length", "passes", "distance", "shot_distance"]:
		var a := _extract(press, key)
		var b := _extract(block, key)
		var t: float = absf(SimValidation.welch_t(a, b))
		checks += 1
		if t > 2.0:
			separated += 1
	check_greater(float(separated), 1.5, "two contrasting plans must separate on several measures")

	# And in the direction a manager would expect.
	check_greater(
		SimValidation.mean_of(_extract(block, "pass_length")) * 0.0 + SimValidation.mean_of(_extract(press, "pass_length")),
		SimValidation.mean_of(_extract(block, "pass_length")),
		"a direct plan plays longer passes than a patient one"
	)


func _every_tactical_axis_is_a_modifier() -> void:
	# PLAN.md §5.1: any tactical feature that cannot be expressed as a modifier
	# on the shared value function should be rejected. Neutral tactics must
	# therefore leave every derived modifier at a neutral value.
	var t := SimTactics.balanced()
	var pitch := SimPitch.regulation()
	check_between(t.risk_weight(), 0.8, 1.2, "balanced risk is neutral")
	check_between(t.direct_bias(), 0.9, 1.2, "balanced directness is neutral")
	check_between(t.retention_bias(), 0.9, 1.2, "balanced retention is neutral")
	check_between(t.width_scale(), 0.9, 1.1, "balanced width is neutral")
	check_near(t.focus_at(0.0, pitch), 1.0, 0.01, "balanced focus is neutral")
	var clone := t.clone()
	clone.press_intensity = 0.9
	check_near(t.press_intensity, 0.5, 0.01, "cloning a plan must not alias it")


static func _sample(plan: SimTactics, base_seed: int) -> Array[SimMatchStats]:
	var opts := SimRunner.Options.new()
	opts.seed_value = base_seed
	opts.minutes = MINUTES
	opts.home_tactics = plan
	opts.away_tactics = SimTactics.balanced()
	return SimRunner.run_batch(opts, SAMPLE)


static func _extract(stats: Array[SimMatchStats], key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for s in stats:
		match key:
			"possession":
				out.append(s.possession[0])
			"pass_length":
				out.append(s.mean_pass_length[0])
			"passes":
				out.append(float(s.passes[0]))
			"distance":
				out.append(s.distance[0] / 1000.0)
			"shot_distance":
				out.append(s.mean_shot_distance[0])
	return out
