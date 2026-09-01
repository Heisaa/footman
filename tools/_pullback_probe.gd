extends SceneTree
## What the pull-back's success is made of, in the geometry made for it.
##
## `cross-pullback` ends 78% lost and the acts table shows no cross and no
## pull-back ever played. The replay says why it is not chosen -- succ 0.05 on
## the highest gain on the board -- and cannot say which term of the success
## model that 0.05 is. `_pass_success` files its factors in
## `SimDecision._cand_parts` and nothing prints them per candidate.
##
## So: place the scenario, ask the decision layer for the list without ticking
## the clock, and print the factors beside each option.
##     godot --headless --script res://tools/_pullback_probe.gd
##
## The pull-back is picked out by its point, which is the only exact handle:
## `_add_pullback` aims at `goal.x - dir * PULLBACK_BACK` and nothing else does.
##
## Measured 2026-08-28, 25 seeds, offered in all of them:
##     succ 0.051 = space 0.757 x lane 0.200 x struck 0.667 x set 0.500
## `lane` is the answer. `space` says he wins the grass and `struck` says the
## ball is hittable; `_lane_survival` prices the defence between the byline and
## the D as interceptors, and a cut-back goes behind a back line that is facing
## its own goal. Every ball on the floor from there comes back at 0.15-0.21 and
## every ball in the air at 1.000, which is the shape of a term reading bodies
## and not which way they are pointing. The `set` 0.500 is `settle()` putting
## him on the ball this instant and decays within a second; it is not the cause.
##
## Then, per defender: the 0.190 is **one man**, not a crowd. #3 stands 0.8 m off
## the line of the pass, 5 m from the ball, and is charged p_cut 0.797 -- which
## is the lane term working, not failing.
##
## The fault is a point above it. `_add_pullback` weighs its two target points on
## `worth` alone, never on whether the ball can get there, and appends only the
## winner. On seed 1:
##     z  +0.0   21.4 m  lane 0.190   <- the one offered
##     z  +9.1   14.6 m  lane 0.967
## The open cut-back is shorter, clear, and never a candidate.

const SEEDS := 25


func _init() -> void:
	var s := SimScenarios.by_name("cross-pullback")
	var totals := PackedFloat32Array()
	totals.resize(SimDecision.PARTS)
	var succ := 0.0
	var damp := 0.0
	var found := 0

	for i in SEEDS:
		var opts := SimRunner.Options.new()
		opts.seed_value = 1 + i
		opts.home_quality = 0.6
		opts.away_quality = 0.6
		opts.minutes = 90.0
		opts.scenario = s
		var m := SimRunner.build(opts)
		var ctx := m.ctx
		var man: SimPlayer = ctx.players[ctx.ball.last_touch_player]
		var options := SimDecision.options_for(ctx, man)
		var parts := SimDecision._cand_parts
		var mark := _pullback_point(ctx, man)

		if i == 0:
			print("seed %d, %s on the ball at %.1f, %.1f  (%d candidates)" % [
				opts.seed_value, man.player_name, ctx.ball.pos.x, ctx.ball.pos.z, options.size()])
			print("  %-30s %6s %6s %6s | %6s %6s %6s %6s %6s %6s" % [
				"", "succ", "gain", "bias", "space", "inTime", "lane", "ctrl",
				"struck", "set"])
			for c in options.size():
				_row(ctx, man, options[c], parts, c, mark)

		if i == 0:
			_lane_breakdown(ctx, man, options, mark)

		for c in options.size():
			if not _is_pullback(options[c], mark):
				continue
			found += 1
			succ += float(options[c]["success"])
			var b := c * SimDecision.PARTS
			for k in SimDecision.PARTS:
				totals[k] += parts[b + k]
			damp += float(options[c].get("set", 1.0))
			break

	print("")
	if found == 0:
		print("the pull-back was not a candidate in any of %d seeds" % SEEDS)
		quit()
		return
	print("the pull-back, mean of %d seeds it was offered in (of %d)" % [found, SEEDS])
	print("  succ %.3f = space %.3f x inTime %.3f x lane %.3f x ctrl %.3f x struck %.3f x set %.3f" % [
		succ / found,
		totals[SimDecision.PART_SPACE] / found,
		totals[SimDecision.PART_IN_TIME] / found,
		totals[SimDecision.PART_LANE] / found,
		totals[SimDecision.PART_CONTROL] / found,
		totals[SimDecision.PART_STRUCK] / found,
		damp / found,
	])
	quit()


## Where `_add_pullback` aims, which is the handle that tells its candidate from
## an ordinary pass to the same man.
func _pullback_point(ctx: SimContext, man: SimPlayer) -> float:
	var goal := ctx.pitch.target_goal(man.team)
	return goal.x - ctx.pitch.attack_dir(man.team) * SimDecision.PULLBACK_BACK


func _is_pullback(c: Dictionary, mark: float) -> bool:
	if int(c["action"]) != SimDecision.Action.GROUND_PASS:
		return false
	var p: Vector3 = c.get("point", Vector3(1e9, 0.0, 0.0))
	return absf(p.x - mark) < 0.01


func _row(ctx: SimContext, man: SimPlayer, c: Dictionary, parts: PackedFloat32Array,
		at: int, mark: float) -> void:
	var kind: String = ["hold", "dribble", "pass", "lofted", "through", "cross",
		"shot", "clear", "set", "dummy", "feint"][int(c["action"])]
	var label := kind
	var target := int(c.get("target", -1))
	if target >= 0:
		var p: Vector3 = c.get("point", ctx.players[target].pos)
		label = "%s -> #%d %.0f m" % [kind, ctx.players[target].shirt,
			SimConsts.horizontal_length(p - ctx.ball.pos)]
	if _is_pullback(c, mark):
		label += "  <- PULL-BACK"
	var b := at * SimDecision.PARTS
	var succ := float(c["success"])
	if parts.size() < b + SimDecision.PARTS:
		print("  %-30s %6.3f %6.3f %6.2f | %s" % [
			label, succ, float(c["gain"]), float(c.get("bias", 1.0)),
			"no success model"])
		return
	# `_apply_set_damp` runs after every candidate is built and is not one of the
	# parts, so the factors alone do not multiply out to the success. It is on the
	# candidate already, under the same name the debug overlay prints.
	print("  %-30s %6.3f %6.3f %6.2f | %6.3f %6.3f %6.3f %6.3f %6.3f %6.2f" % [
		label, succ, float(c["gain"]), float(c.get("bias", 1.0)),
		parts[b + SimDecision.PART_SPACE], parts[b + SimDecision.PART_IN_TIME],
		parts[b + SimDecision.PART_LANE], parts[b + SimDecision.PART_CONTROL],
		parts[b + SimDecision.PART_STRUCK], float(c.get("set", 1.0))])


## Who the lane term is actually charging, and how much each of them costs.
##
## `survival` is a product over every opponent in the corridor, so a 0.20 is
## either one man priced as a near-certain interception or a crowd of them each
## priced as a small one -- and those want opposite fixes. Asked by handing the
## real function an `ignore_id` rather than by reimplementing its loop, so the
## split cannot drift from what the engine did.
func _lane_breakdown(ctx: SimContext, man: SimPlayer, options: Array, mark: float) -> void:
	var pull := {}
	for c in options:
		if _is_pullback(c, mark):
			pull = c
			break
	if pull.is_empty():
		return
	var from := ctx.ball.pos
	var to: Vector3 = pull["point"]
	var distance := SimConsts.horizontal_length(to - from)
	var travel := ctx.ballistics.ground_travel_time(distance,
		ctx.ballistics.ground_pass_speed(distance, float(pull["pace"]), ctx.env), ctx.env)
	var all := SimDecision._lane_survival(ctx, man, from, to, travel, SimDecision.LANE_TAIL)
	print("")
	print("  the pull-back lane: %.1f m, ball there in %.2f s, survival %.3f" % [
		distance, travel, all])
	for oid in ctx.opponent_ids(man.team):
		var o: SimPlayer = ctx.players[oid]
		if not o.on_pitch:
			continue
		var without := SimDecision._lane_survival(
			ctx, man, from, to, travel, SimDecision.LANE_TAIL, o.id)
		if is_equal_approx(without, all):
			continue
		var rel := SimConsts.horizontal(o.pos - from)
		var seg := SimConsts.horizontal(to - from)
		var dir := seg / maxf(seg.length(), 0.1)
		print("    #%-3d %-3s  along %5.1f m  lateral %5.1f m   p_cut %.3f%s" % [
			o.shirt, "GK" if o.is_keeper else "", rel.dot(dir),
			absf(rel.x * -dir.z + rel.z * dir.x),
			1.0 - all / without if without > 0.0 else 1.0,
			"   <- keeper" if o.is_keeper else ""])
	# `_add_pullback` weighs its two target points on `worth` alone and appends
	# only the winner, so if the one it threw away has the clear lane the open
	# pull-back was never a candidate at all.
	var goal := ctx.pitch.target_goal(man.team)
	var attack_dir := ctx.pitch.attack_dir(man.team)
	var side: float = signf(from.z)
	if side == 0.0:
		side = 1.0
	var both := [
		Vector3(goal.x - attack_dir * SimDecision.PULLBACK_BACK, 0.0, 0.0),
		Vector3(goal.x - attack_dir * SimDecision.PULLBACK_BACK, 0.0,
			side * ctx.pitch.penalty_half_width * 0.45),
	]
	print("  both target points `_add_pullback` weighed:")
	for pt in both:
		var d := SimConsts.horizontal_length(pt - from)
		var t := ctx.ballistics.ground_travel_time(d,
			ctx.ballistics.ground_pass_speed(d, float(pull["pace"]), ctx.env), ctx.env)
		print("    z %+6.1f  %5.1f m  lane %.3f%s" % [
			pt.z, d,
			SimDecision._lane_survival(ctx, man, from, pt, t, SimDecision.LANE_TAIL),
			"   <- the one offered" if is_equal_approx(pt.z, to.z) else ""])
