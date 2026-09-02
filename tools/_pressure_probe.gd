extends SceneTree
## What the man on the ball is pressed by, and what he does about it.
##
## `pressure_on` sums every opponent inside 6 m by proximity alone. A jockey
## standing off, a marker walking away and a man charging in all read the same
## at the same distance. This splits the field at each on-ball decision by
## the opponent's closing speed, and reads the pick against it: what won, and
## what the best carry lost on when it lost.
##     godot --headless --script res://tools/_pressure_probe.gd -- --seed N --minutes M

const CLOSING := 1.5   # m/s toward the carrier: closing above, retreating below -CLOSING
const BANDS := [0.25, 0.8, 1e9]
const LABELS := ["free", "closed down", "challenged"]
const KINDS := ["hold", "carry", "pass", "lofted", "through", "cross", "shot", "clear", "set", "dummy", "feint"]

var seeds := [7, 3, 11]
var minutes := 10.0
var force_push := false
# forced knocks: [due, team, said, beat_id, dir, ball_at_strike]
var forced := []
var forced_n := 0
var forced_said := 0.0
var forced_kept2 := 0
var forced_kept4 := 0
var forced_past := 0

# per band: n, pressure sum, share closing, standing, retreating, nearest d, nearest closing
var band_n := [0, 0, 0]
var band_press := [0.0, 0.0, 0.0]
var band_from := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
var band_pick := [{}, {}, {}]
# free men with open grass ahead (>= 9 m in the forward lane)
var open_n := 0
var open_pick := {}
var open_carry_lost := {"success": 0, "gain": 0, "n": 0}
var open_carry_terms := {"succ": 0.0, "gain": 0.0, "wsucc": 0.0, "wgain": 0.0, "n": 0}
var open_parts := {"ctrl": 0.0, "escape": 0.0, "skill_press": 0.0, "face": 0.0, "in_play": 0.0, "lane": 0.0, "n": 0}
var open_look := 0.0   # how far ahead the best carry's target sat
# pressure reading for a lone standing-off man, by distance
var lone_stand := {}
# carries played: said success against kept two seconds later, by lane
var pending := []   # [due_tick, team, said, open_lane]
var calib := {"open": [0, 0.0, 0], "traffic": [0, 0.0, 0]}   # n, said sum, kept
# a challenger in sight: was the knock past him on the list, and what did it read
var chal_n := 0
var chal_burst := {"listed": 0, "played": 0, "succ": 0.0, "gain": 0.0, "wsucc": 0.0, "wgain": 0.0}
var chal_feint := {"listed": 0, "played": 0}
var chal_pick := {}
var burst_parts := {"ctrl": 0.0, "escape": 0.0, "skill_press": 0.0, "in_play": 0.0, "lane": 0.0, "seconds": 0.0, "travel": 0.0, "push": 0.0, "n": 0}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			seeds = [int(args[i + 1])]
		if args[i] == "--minutes" and i + 1 < args.size():
			minutes = float(args[i + 1])
		if args[i] == "--force-push":
			force_push = true
	for s in seeds:
		_run(s)
	_report()
	quit()


func _run(seed_value: int) -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = minutes
	opts.events = false
	var m := SimRunner.build(opts)
	var ctx := m.ctx
	SimDebug.enabled = true
	SimDecision.debug_parts = true
	SimDecision.debug_force_push = force_push
	var seen := -1
	while not m.finished:
		m.tick()
		_settle_pending(ctx)
		var rec := SimDebug.newest()
		if rec.is_empty() or int(rec["tick"]) == seen:
			continue
		seen = int(rec["tick"])
		if int(rec["chosen"]) < 0:
			continue
		var p: SimPlayer = ctx.players[int(rec["id"])]
		if p.is_keeper:
			continue
		_sample(ctx, p, rec)
	SimDebug.enabled = false
	SimDecision.debug_parts = false
	SimDecision.debug_force_push = false


func _sample(ctx: SimContext, p: SimPlayer, rec: Dictionary) -> void:
	var press: float = rec["pressure"]
	var band := 0
	while press > BANDS[band]:
		band += 1
	# Decompose: the same sum `update_pressure` makes, tagged by closing speed.
	var from := [0.0, 0.0, 0.0]
	var near_d := INF
	var near_closing := 0.0
	var count := 0
	for j in ctx.opponent_ids(p.team):
		var o := ctx.players[j]
		if not o.on_pitch:
			continue
		var d := p.dist_to(o.pos)
		if d > 6.0 or d < 0.1:
			continue
		var to_opp := (o.pos - p.pos) / d
		var facing := 0.65 + 0.35 * to_opp.dot(p.heading_dir())
		var term := facing * (1.0 - d / 6.0) * (1.0 - d / 6.0)
		var closing := (o.vel - p.vel).dot(-to_opp)
		var k := 1
		if closing > CLOSING:
			k = 0
		elif closing < -CLOSING:
			k = 2
		from[k] += term
		count += 1
		if d < near_d:
			near_d = d
			near_closing = closing
	band_n[band] += 1
	band_press[band] += press
	for k in 3:
		band_from[band][k] += from[k]
	var chosen: Dictionary = rec["options"][int(rec["chosen"])]
	var kind: String = KINDS[int(chosen["action"])]
	band_pick[band][kind] = band_pick[band].get(kind, 0) + 1
	# One man, standing off: what does the field read him as.
	if count == 1 and absf(near_closing) <= CLOSING:
		var bucket := "%d-%d m" % [int(near_d), int(near_d) + 1]
		if not lone_stand.has(bucket):
			lone_stand[bucket] = [0, 0.0, 0.0]
		lone_stand[bucket][0] += 1
		lone_stand[bucket][1] += press
		lone_stand[bucket][2] += float(rec["challenge"])
	if kind == "carry":
		var opts: Array = SimDecision._candidates
		var c: Dictionary = opts[_picked_index(rec)] if _picked_index(rec) >= 0 else {}
		if not c.is_empty() and c.has("push"):
			var beat := ctx.nearest_challenger(p)
			forced.append([ctx.tick_index + 120, ctx.tick_index + 240, p.team, float(c["success"]),
				beat.id if beat != null else -1, Vector3(c["dir"]), ctx.ball.ground_pos(), false])
		if not c.is_empty() and not c.has("push") and c.has("dir"):
			var lane := _open_ahead(ctx, p, Vector3(c["dir"]).normalized()) >= 9.0
			pending.append([ctx.tick_index + 120, p.team, float(c["success"]), lane])
	if band > 0 or float(rec["challenge"]) > 0.25:
		_with_a_challenger(rec, kind)
	# Free, with grass in front of him.
	if band == 0 and _open_ahead(ctx, p) >= 9.0:
		open_n += 1
		open_pick[kind] = open_pick.get(kind, 0) + 1
		_carry_against_winner(ctx, p, rec)


func _picked_index(rec: Dictionary) -> int:
	# The record keeps the top few options; find the chosen one on the full list by score.
	var chosen: Dictionary = rec["options"][int(rec["chosen"])]
	var want: float = chosen["score"]
	for i in SimDecision._candidates.size():
		if is_equal_approx(float(SimDecision._candidates[i].get("score", NAN)), want):
			return i
	return -1


func _settle_pending(ctx: SimContext) -> void:
	var k := 0
	while k < forced.size():
		var row: Array = forced[k]
		if ctx.tick_index >= int(row[0]) and not bool(row[7]):
			row[7] = true
			forced_n += 1
			forced_said += float(row[3])
			if ctx.possession_team == int(row[2]):
				forced_kept2 += 1
			# Past him: the ball further along the knock's line than the man.
			if int(row[4]) >= 0:
				var d: Vector3 = row[5]
				var man := ctx.players[int(row[4])]
				if (ctx.ball.ground_pos() - man.pos).dot(d) > 0.0 and ctx.possession_team == int(row[2]):
					forced_past += 1
		if ctx.tick_index >= int(row[1]):
			if ctx.possession_team == int(row[2]):
				forced_kept4 += 1
			forced.remove_at(k)
			continue
		k += 1
	var i := 0
	while i < pending.size():
		var row: Array = pending[i]
		if ctx.tick_index < int(row[0]):
			i += 1
			continue
		var key := "open" if bool(row[3]) else "traffic"
		calib[key][0] += 1
		calib[key][1] += float(row[2])
		if ctx.possession_team == int(row[1]):
			calib[key][2] += 1
		pending.remove_at(i)


func _with_a_challenger(rec: Dictionary, kind: String) -> void:
	chal_n += 1
	chal_pick[kind] = chal_pick.get(kind, 0) + 1
	var winner := {}
	var win_score := -INF
	var burst := {}
	var burst_score := -INF
	var feint := false
	for c in SimDecision._candidates:
		var sc: float = float(c.get("score", -INF))
		if sc > win_score:
			win_score = sc
			winner = c
		if c.has("push") and sc > burst_score:
			burst_score = sc
			burst = c
		if int(c["action"]) == SimDecision.Action.FEINT:
			feint = true
	if feint:
		chal_feint["listed"] += 1
		if kind == "feint":
			chal_feint["played"] += 1
	if burst.is_empty():
		return
	chal_burst["listed"] += 1
	if burst.has("parts"):
		var q: Dictionary = burst["parts"]
		for k in ["ctrl", "escape", "skill_press", "in_play", "lane", "seconds", "travel", "push"]:
			burst_parts[k] += float(q[k])
		burst_parts["n"] += 1
	if kind == "carry" and winner.has("push"):
		chal_burst["played"] += 1
	chal_burst["succ"] += float(burst["success"])
	chal_burst["gain"] += float(burst["gain"])
	chal_burst["wsucc"] += float(winner["success"])
	chal_burst["wgain"] += float(winner["gain"])


func _open_ahead(ctx: SimContext, p: SimPlayer, heading: Vector3 = Vector3.ZERO) -> float:
	if heading == Vector3.ZERO:
		heading = Vector3(ctx.pitch.attack_dir(p.team), 0.0, 0.0)
	var open := ctx.pitch.run_room(p.pos, heading, 1.0)
	for j in ctx.opponent_ids(p.team):
		var o := ctx.players[j]
		if not o.on_pitch or o.is_keeper:
			continue
		var to := SimConsts.horizontal(o.pos - p.pos)
		var along := to.dot(heading)
		if along <= 0.0 or along >= open:
			continue
		if absf(to.x * -heading.z + to.z * heading.x) > 3.5:
			continue
		open = along
	return open


func _carry_against_winner(ctx: SimContext, p: SimPlayer, rec: Dictionary) -> void:
	# The full list is still on `SimDecision._candidates` with its parts.
	var best_carry := {}
	var best_score := -INF
	var winner := {}
	var win_score := -INF
	for c in SimDecision._candidates:
		var sc: float = float(c.get("score", -INF))
		if sc > win_score:
			win_score = sc
			winner = c
		if int(c["action"]) == SimDecision.Action.DRIBBLE and not c.has("push") and sc > best_score:
			best_score = sc
			best_carry = c
	if best_carry.is_empty() or winner.is_empty():
		return
	open_look += SimConsts.horizontal_length(Vector3(best_carry["point"]) - p.pos)
	if best_carry.has("parts"):
		var q: Dictionary = best_carry["parts"]
		for k in ["ctrl", "escape", "skill_press", "face", "in_play", "lane"]:
			open_parts[k] += float(q[k])
		open_parts["n"] += 1
	if int(winner["action"]) == SimDecision.Action.DRIBBLE:
		return
	open_carry_terms["succ"] += float(best_carry["success"])
	open_carry_terms["gain"] += float(best_carry["gain"])
	open_carry_terms["wsucc"] += float(winner["success"])
	open_carry_terms["wgain"] += float(winner["gain"])
	open_carry_terms["n"] += 1
	# Which term would have flipped it: swap one at a time.
	var s_c: float = best_carry["success"]
	var g_c: float = best_carry["gain"]
	var s_w: float = winner["success"]
	var g_w: float = winner["gain"]
	open_carry_lost["n"] += 1
	if s_w * g_c >= win_score and s_c * g_w < win_score:
		open_carry_lost["success"] += 1
	elif s_c * g_w >= win_score:
		open_carry_lost["gain"] += 1


func _report() -> void:
	print("")
	print("Pressure at the decision, by band  (%s, %.0f min each)" % [str(seeds), minutes])
	print("  %-12s %5s %8s   %8s %8s %8s   %s" % ["", "n", "pressure", "closing", "standing", "retreat", "picked"])
	for b in 3:
		var n: int = band_n[b]
		if n == 0:
			continue
		var tot: float = maxf(band_from[b][0] + band_from[b][1] + band_from[b][2], 1e-6)
		print("  %-12s %5d %8.2f   %7.0f%% %7.0f%% %7.0f%%   %s" % [
			LABELS[b], n, band_press[b] / n,
			100.0 * band_from[b][0] / tot, 100.0 * band_from[b][1] / tot, 100.0 * band_from[b][2] / tot,
			_picks(band_pick[b], n)])
	print("")
	print("One man near, standing off (|closing| <= %.1f m/s): what the field reads" % CLOSING)
	var keys := lone_stand.keys()
	keys.sort()
	for k in keys:
		var r: Array = lone_stand[k]
		print("  %-8s n %3d   pressure %.2f   challenge %.2f" % [k, r[0], r[1] / r[0], r[2] / r[0]])
	print("")
	print("Free man with 9 m+ of grass ahead: %d decisions" % open_n)
	print("  picked: %s" % _picks(open_pick, maxi(open_n, 1)))
	var n := int(open_parts["n"])
	if n > 0:
		print("  best carry's target sat %.1f m from him, mean" % (open_look / n))
		print("  best carry's factors, mean:  ctrl %.2f  escape %.2f  skill*press %.2f  face %.2f  in_play %.2f  lane %.2f" % [
			open_parts["ctrl"] / n, open_parts["escape"] / n, open_parts["skill_press"] / n,
			open_parts["face"] / n, open_parts["in_play"] / n, open_parts["lane"] / n])
	var m := int(open_carry_terms["n"])
	if m > 0:
		print("  when the carry lost (%d): carry succ %.2f gain %.4f  v  winner succ %.2f gain %.4f" % [
			m, open_carry_terms["succ"] / m, open_carry_terms["gain"] / m,
			open_carry_terms["wsucc"] / m, open_carry_terms["wgain"] / m])
		print("  the winner's success alone would have flipped it %d times, its gain alone %d" % [
			open_carry_lost["success"], open_carry_lost["gain"]])


	print("")
	print("Carries played, said against kept 2 s later")
	for k in ["open", "traffic"]:
		var r: Array = calib[k]
		if r[0] > 0:
			print("  %-8s n %3d   said %.2f   kept %.0f%%" % [k + (" lane (9 m+)" if k == "open" else ""), r[0], r[1] / r[0], 100.0 * r[2] / r[0]])
	print("")
	print("A challenger in sight: %d decisions" % chal_n)
	print("  picked: %s" % _picks(chal_pick, maxi(chal_n, 1)))
	print("  feint on the list %d, played %d" % [chal_feint["listed"], chal_feint["played"]])
	if forced_n > 0:
		print("  forced knocks %d: said %.2f, kept at 2 s %.0f%%, past the man and kept %.0f%%, kept at 4 s %.0f%%" % [
			forced_n, forced_said / forced_n, 100.0 * forced_kept2 / forced_n,
			100.0 * forced_past / forced_n, 100.0 * forced_kept4 / forced_n])
	var bn := int(burst_parts["n"])
	if bn > 0:
		print("  the knock's factors, mean:  ctrl %.2f  escape %.2f  skill %.2f  in_play %.2f  lane %.2f   push %.1f m, travel %.1f m, %.1f s" % [
			burst_parts["ctrl"] / bn, burst_parts["escape"] / bn, burst_parts["skill_press"] / bn,
			burst_parts["in_play"] / bn, burst_parts["lane"] / bn,
			burst_parts["push"] / bn, burst_parts["travel"] / bn, burst_parts["seconds"] / bn])
	var b := int(chal_burst["listed"])
	if b > 0:
		print("  knock past him on the list %d, played %d;  it read succ %.2f gain %.4f  v  winner succ %.2f gain %.4f" % [
			b, chal_burst["played"], chal_burst["succ"] / b, chal_burst["gain"] / b,
			chal_burst["wsucc"] / b, chal_burst["wgain"] / b])


func _picks(d: Dictionary, n: int) -> String:
	var parts := []
	var keys := d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	for k in keys:
		parts.append("%s %.0f%%" % [k, 100.0 * d[k] / n])
	return ", ".join(parts)
