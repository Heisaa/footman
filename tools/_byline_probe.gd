extends SceneTree
## Does the engine know the cross gets better nearer the byline?
##
## `cross-loaded` t31: a hopeful cross at succ 0.13 takes 97% of the softmax over
## the carry down the line. 51's question is whether the approach is mispriced
## or merely never picked: put the same winger at graded depths on the same
## flank and print what he is offered. If the cross's succ and score climb with
## depth, the engine knows and the fault is the pick's horizon; if they are
## flat, the fault is the pricing.
##     godot --headless --script res://tools/_byline_probe.gd

const DEPTHS := [24.0, 32.0, 38.0, 44.0, 48.0]


func _init() -> void:
	for d in DEPTHS:
		var opts := SimRunner.Options.new()
		opts.seed_value = 1
		opts.home_quality = 0.6
		opts.away_quality = 0.6
		opts.minutes = 90.0
		opts.scenario = SimScenarios.by_name("cross-loaded")
		var m := SimRunner.build(opts)
		var ctx := m.ctx
		var man: SimPlayer = ctx.players[ctx.ball.last_touch_player]
		var dir := ctx.pitch.attack_dir(man.team)
		man.pos = Vector3(float(d) * dir, 0.0, 26.0)
		man.vel = Vector3(dir * 3.0, 0.0, 0.0)
		ctx.ball.pos = man.pos + Vector3(dir * 0.6, 0.0, 0.0)
		ctx.ball.vel = Vector3.ZERO
		var up := SimConsts.horizontal(ctx.pitch.target_goal(man.team) - man.pos)
		man.facing = atan2(up.z, up.x)
		ctx.update_possession()
		SimDecision.debug_parts = true
		var options := SimDecision.options_for(ctx, man)
		var order := []
		for c in options.size():
			order.append([SimDecision.score_of(ctx, man, options[c]), c])
		order.sort_custom(func(a, b): return a[0] > b[0])
		print("")
		print("%.0f m up, %.1f m from the byline  (%d candidates)" % [
			d, ctx.pitch.half_length - d, options.size()])
		for i in mini(6, order.size()):
			_row(ctx, man, options[order[i][1]], float(order[i][0]))
	quit()


func _row(ctx: SimContext, man: SimPlayer, c: Dictionary, score: float) -> void:
	var kind: String = ["hold", "dribble", "pass", "lofted", "through", "cross",
		"shot", "clear", "set", "dummy"][int(c["action"])]
	var label := kind
	var target := int(c.get("target", -1))
	var p: Vector3 = c.get("point", man.pos)
	if kind == "dribble":
		var dir := ctx.pitch.attack_dir(man.team)
		label = "carry %+.1f on, %+.1f in" % [
			(p.x - man.pos.x) * dir, (26.0 - absf(p.z)) - (26.0 - absf(man.pos.z))]
	elif target >= 0:
		label = "%s -> #%d %.0f m" % [kind, ctx.players[target].shirt,
			SimConsts.horizontal_length(p - ctx.ball.pos)]
	var near := INF
	for oid in ctx.opponent_ids(man.team):
		var o := ctx.players[oid]
		if o.on_pitch and not o.is_keeper:
			near = minf(near, o.dist_to(p))
	var split := ""
	if c.has("parts"):
		var q: Dictionary = c["parts"]
		split = "  ctrl %.2f esc %.2f sp %.2f face %.2f play %.2f lane %.2f" % [
			q["ctrl"], q["escape"], q["skill_press"], q["face"], q["in_play"], q["lane"]]
	print("  %-28s %7.4f  succ %.2f  gain %.3f  bias %.2f  near %4.1f m%s" % [
		label, score, float(c["success"]), float(c["gain"]), float(c.get("bias", 1.0)), near, split])
