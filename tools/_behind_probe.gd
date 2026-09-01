extends SceneTree
## What the through ball's success is made of, in the geometry made for it.
##
## The replay says the through ball loses the pick at succ 0.11 on the highest
## gain on the board, and cannot say which term of the success model that 0.11
## is. Same construction as `_pullback_probe.gd`: place the scenario, ask the
## decision layer for the list without ticking the clock, print the factors.
##     godot --headless --script res://tools/_behind_probe.gd

const SEEDS := 25


func _init() -> void:
	var s := SimScenarios.by_name("through-ball")
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

		var pick := -1
		for c in options.size():
			if int(options[c]["action"]) != SimDecision.Action.THROUGH_BALL:
				continue
			if pick < 0 or float(options[c]["success"]) > float(options[pick]["success"]):
				pick = c

		if i == 0:
			print("seed %d, %s on the ball at %.1f, %.1f  (%d candidates)" % [
				opts.seed_value, man.player_name, ctx.ball.pos.x, ctx.ball.pos.z, options.size()])
			print("  %-30s %6s %6s %6s %6s | %6s %6s %6s %6s %6s %6s" % [
				"", "score", "succ", "gain", "bias", "space", "inTime", "lane", "ctrl",
				"struck", "set"])
			for c in options.size():
				_row(ctx, man, options[c], parts, c, c == pick)
			if pick >= 0:
				_geometry(ctx, man, options[pick])

		if pick < 0:
			continue
		found += 1
		succ += float(options[pick]["success"])
		var b := pick * SimDecision.PARTS
		for k in SimDecision.PARTS:
			totals[k] += parts[b + k]
		damp += float(options[pick].get("set", 1.0))

	print("")
	if found == 0:
		print("the through ball was not a candidate in any of %d seeds" % SEEDS)
		quit()
		return
	print("the through ball, mean of %d seeds it was offered in (of %d)" % [found, SEEDS])
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


## Where the ball lands against the line and the keeper: the aim is the meeting
## point of run and flight now, and if it has run into the keeper's ground the
## space term is right to collapse -- the fault would be the aim, not the term.
func _geometry(ctx: SimContext, man: SimPlayer, c: Dictionary) -> void:
	var to: Vector3 = c["point"]
	var from := ctx.ball.pos
	var attack := ctx.pitch.attack_dir(man.team)
	var line := SimReferee.believed_offside_line(ctx, man) * attack
	var distance := SimConsts.horizontal_length(to - from)
	var travel := ctx.ballistics.ground_travel_time(distance,
		ctx.ballistics.ground_pass_speed(distance, float(c["pace"]), ctx.env), ctx.env)
	var goal := ctx.pitch.target_goal(man.team)
	var keeper: SimPlayer = ctx.teams[SimConsts.other_team(man.team)].keeper()
	print("")
	print("  the aim: %.1f m from the passer, %.1f m beyond the line, %.1f m from goal" % [
		distance, to.x * attack - line, SimConsts.horizontal_length(to - goal)])
	if keeper != null:
		print("  the keeper: %.1f m off the aim, there in %.2f s against the ball's %.2f s" % [
			keeper.dist_to(to),
			SimValueField.time_to_arrive(keeper, to, SimValueField.reaction_of(keeper)),
			travel])


func _row(ctx: SimContext, man: SimPlayer, c: Dictionary, parts: PackedFloat32Array,
		at: int, marked: bool) -> void:
	var kind: String = ["hold", "dribble", "pass", "lofted", "through", "cross",
		"shot", "clear", "set", "dummy"][int(c["action"])]
	var label := kind
	var target := int(c.get("target", -1))
	if target >= 0:
		var p: Vector3 = c.get("point", ctx.players[target].pos)
		label = "%s -> #%d %.0f m" % [kind, ctx.players[target].shirt,
			SimConsts.horizontal_length(p - ctx.ball.pos)]
	if marked:
		label += "  <- THE BALL"
	var b := at * SimDecision.PARTS
	var succ := float(c["success"])
	if parts.size() < b + SimDecision.PARTS:
		print("  %-30s %6.4f %6.3f %6.3f %6.2f | %s" % [
			label, SimDecision.score_of(ctx, man, c), succ, float(c["gain"]), float(c.get("bias", 1.0)),
			"no success model"])
		return
	print("  %-30s %6.4f %6.3f %6.3f %6.2f | %6.3f %6.3f %6.3f %6.3f %6.3f %6.2f" % [
		label, SimDecision.score_of(ctx, man, c), succ, float(c["gain"]), float(c.get("bias", 1.0)),
		parts[b + SimDecision.PART_SPACE], parts[b + SimDecision.PART_IN_TIME],
		parts[b + SimDecision.PART_LANE], parts[b + SimDecision.PART_CONTROL],
		parts[b + SimDecision.PART_STRUCK], float(c.get("set", 1.0))])
