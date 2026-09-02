extends SceneTree
## Why `shot-edge` carries into two centre-backs: the shot's own numbers at
## each decision tick, and the shot every carry direction is credited with.
##     godot --headless --script res://tools/_shot_edge_probe.gd
##
## Measured 2026-09-02, seeds 4001-4003, asked whether pricing the sideways
## carry by the shot it opens would move the pick. It already is priced that
## way -- `_carry_shot_gain` reads `expected_goals` at the horizon, lunge model
## included -- and the answer is no:
## - The shot from the spot is 0.031 at t0 and never on the list: gated by the
##   orientation beat (`ready` 0.00 < 0.25), and by t14 the near centre-back has
##   stepped onto the line (`surv` 0.65 to 0.37) and it is under the 0.025 floor
##   for the rest of the trial (0.013-0.020).
## - A yard sideways opens nothing: 0.012-0.028. Two men 4 m off and 5 m apart
##   each cover 2.9 m either side of the line (`BLOCK_REACH` + `BLOCK_CLOSE` x
##   the window), so the gap he already stands in is the best there is.
## - Three metres forward is credited 0.07-0.11, a gain of 0.22-0.36, because
##   the horizon is level with the centre-backs and past their lunge. The carry
##   scores that at `success` 0.29, and the row's own shares say 0.29 is about
##   right: 46% of trials get a shot off. He carries into them because they let
##   him. The missing piece is the defender who engages a man running at him
##   (the jockey stands off), not the attacker's price.

func _init() -> void:
	for seed_value in [4001, 4002, 4003]:
		var s := SimScenarios.by_name("shot-edge")
		var opts := SimRunner.Options.new()
		opts.seed_value = seed_value
		opts.home_quality = 0.6
		opts.away_quality = 0.6
		opts.minutes = 90.0
		opts.scenario = s
		var m := SimRunner.build(opts)
		var ctx := m.ctx
		print("seed %d" % seed_value)
		for t in [0, 14, 28, 42]:
			while ctx.tick_index < t:
				m.tick()
			var p := ctx.players[ctx.ball.last_touch_player]
			if p.team != s.attacking_team:
				print("  t%d ball lost" % t)
				break
			var goal := ctx.pitch.target_goal(p.team)
			var from := ctx.ball.pos
			var aim := SimDecision._pick_shot_aim(ctx, p, goal)
			var xg := SimDecision.expected_goals(ctx, p, from, aim)
			var surv := SimDuel.block_survival(ctx, p, from, aim, SimDecision.SHOT_PRICED_SPEED)
			var nb := SimDecision._shot_blockers(ctx, p, from, aim)
			print("  t%d #%d at (%.1f, %.1f) vel %.1f  ready %.2f  press %.2f  xg %.4f  surv %.2f  blockers %d  dist %.1f" % [
				t, p.id, from.x, from.z, SimConsts.horizontal_length(p.vel),
				SimDecision.readiness(ctx, p), ctx.pressure_on(p), xg, surv, nb,
				SimConsts.horizontal_length(goal - from)])
			for oid in ctx.opponent_ids(p.team):
				var o := ctx.players[oid]
				if o.dist_to(from) < 8.0:
					print("     opp #%d at (%.1f, %.1f) d %.1f  chance %.2f" % [o.id, o.pos.x, o.pos.z, o.dist_to(from),
						SimDuel.block_chance(ctx, o, p, from, SimConsts.horizontal(aim - from).normalized(), SimDecision.SHOT_PRICED_SPEED)])
			var attack := ctx.pitch.attack_dir(p.team)
			for i in 8:
				var angle := TAU * float(i) / 8.0
				var dir := Vector3(cos(angle), 0.0, sin(angle))
				for dist in [1.0, 3.0]:
					var target: Vector3 = from + dir * dist
					var xg_t := SimDecision.expected_goals(ctx, p, target, aim)
					print("     dir %d (fwd %.1f side %.1f) +%.0fm: xg %.4f  carry_shot_gain %.4f" % [i, dir.x * attack, dir.z, dist, xg_t,
						SimDecision._carry_shot_gain(ctx, p, target)])
			var cands := SimDecision.options_for(ctx, p)
			var kinds := {}
			for c in cands:
				var k: int = int(c["action"])
				kinds[k] = int(kinds.get(k, 0)) + 1
			print("     candidates %s" % [kinds])
	quit()
