extends SceneTree
## Link 0 for the bent lane, in the geometry made for it: does `curl-blocked`
## actually offer the curled driven ball, what did the gate see, and how many
## centimetres of bend does the chosen ball carry.
##     godot --headless --script res://tools/_curl_probe.gd

const SEEDS := 25


func _init() -> void:
	var s := SimScenarios.by_name("curl-blocked")
	var with_curl := 0
	var lane_s_sum := 0.0
	var lane_b_sum := 0.0
	var bow_sum := 0.0
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
		var recv: SimPlayer = ctx.players[9]
		var options := SimDecision.options_for(ctx, man)
		var any_curl := false
		var best_pace := -1.0
		var best: Dictionary = {}
		for c in options.size():
			var cand: Dictionary = options[c]
			if int(cand["action"]) != SimDecision.Action.GROUND_PASS \
					or int(cand.get("target", -1)) != recv.id:
				continue
			if cand.has("curl"):
				any_curl = true
			if float(cand.get("pace", 0.0)) > best_pace:
				best_pace = float(cand["pace"])
				best = cand
		if any_curl:
			with_curl += 1
		if best.is_empty():
			continue
		found += 1
		# Recompute what the gate saw for the fastest ball to the receiver.
		var from := ctx.ball.pos
		var lead: Vector3 = best["point"]
		var dist := SimConsts.horizontal_length(lead - from)
		var d_speed := ctx.ballistics.ground_pass_speed(dist, best_pace, ctx.env)
		var travel := ctx.ballistics.ground_travel_time(dist, d_speed, ctx.env)
		var meant := SimTouch.PASS_CURL * clampf(man.attrs.technique, 0.0, 1.0)
		var bow := SimBallistics.curl_bow(meant, d_speed, dist, SimBallistics.BEND_BOW_SHARE)
		# The plain driven ball is priced on its shape bend now, not the chord.
		var shape := SimBallistics.curl_bow(meant, d_speed, dist, SimBallistics.DRIVEN_BOW_SHARE)
		var ls := SimDecision._lane_survival(ctx, man, from, lead, travel, SimDecision.FEET_TAIL, -1, shape)
		var lb := SimDecision._lane_survival(ctx, man, from, lead, travel, SimDecision.FEET_TAIL, -1, bow)
		lane_s_sum += ls
		lane_b_sum += lb
		bow_sum += bow
		if i < 3:
			# Every ball to the receiver, and the top of the list it lost to.
			var by_score := options.duplicate()
			by_score.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
			for r in mini(by_score.size(), 4):
				var t: Dictionary = by_score[r]
				print("    top %d: action %d target %d score %.4f succ %.2f bias %.2f" % [r, int(t["action"]),
					int(t.get("target", -1)), float(t.get("score", 0.0)), float(t.get("success", 0.0)), float(t.get("bias", 0.0))])
			for t in options:
				if int(t.get("target", -1)) == recv.id:
					print("    to recv: action %d pace %.1f score %.4f succ %.2f bias %.2f curl %s trivela %s" % [
						int(t["action"]), float(t.get("pace", 0.0)), float(t.get("score", 0.0)),
						float(t.get("success", 0.0)), float(t.get("bias", 0.0)),
						str(t.get("curl", "-")), str(t.get("trivela", false))])
			print("seed %d: to recv dist %.1f  d_speed %.1f  succ %.3f  curl? %s  bow %.2f m  lane shape %.3f lifted %.3f  (need +%.2f)" % [
				opts.seed_value, dist, d_speed, float(best["success"]),
				str(best.has("curl")), bow, ls, lb, SimDecision.CURL_MIN])
	print("")
	print("curled candidate offered in %d/%d seeds (fast ball to receiver found in %d)" % [with_curl, SEEDS, found])
	if found > 0:
		print("means: lane shape %.3f  lifted(left) %.3f  bow %.2f m" % [
			lane_s_sum / found, lane_b_sum / found, bow_sum / found])
	print("")
	print("bow reference (curl_bow):")
	print("  lifted bend, tech 0.9: 20 m %.2f m   28 m %.2f m" % [
		SimBallistics.curl_bow(36.0, 15.5, 20.0, SimBallistics.BEND_BOW_SHARE),
		SimBallistics.curl_bow(36.0, 17.5, 28.0, SimBallistics.BEND_BOW_SHARE)])
	print("  bent shot, tech 0.9:  16 m %.2f m   22 m %.2f m" % [
		SimBallistics.curl_bow(40.5, 26.0, 16.0),
		SimBallistics.curl_bow(40.5, 27.0, 22.0)])
	print("  the cross, for scale (40 rad/s, 20 m/s, 25 m): %.2f m" % [
		SimBallistics.curl_bow(40.0, 20.0, 25.0)])
	quit()
