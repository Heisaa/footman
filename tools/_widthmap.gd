extends SceneTree
## Throwaway probe: where each role actually stands, off the trace.
##
##   godot --headless --script res://tools/_widthmap.gd -- --seed N --minutes M
##
## Per role: mean |z| (metres from the centre line), the share of samples in the
## wide fifth (|z| > 20.4 m), split by whether his own side has the ball.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var flags := {}
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var value := "1"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				value = args[i + 1]
				i += 1
			flags[key] = value
		i += 1
	var opts := SimRunner.Options.new()
	opts.seed_value = int(flags.get("seed", "1"))
	opts.home_quality = 0.6
	opts.away_quality = 0.6
	opts.minutes = float(flags.get("minutes", "10"))
	opts.clock_rate = float(flags.get("clock-rate", "10"))
	opts.trace = true
	var m := SimRunner.build(opts)
	m.run_to_completion()
	_dump(m)
	quit()


func _dump(m: SimMatch) -> void:
	var ctx := m.ctx
	var trace := ctx.telemetry.trace
	var roles := SimRole.NAMES.size()
	var n := [PackedInt32Array(), PackedInt32Array()]
	var z_sum := [PackedFloat32Array(), PackedFloat32Array()]
	var wide := [PackedInt32Array(), PackedInt32Array()]
	var station_z := [PackedFloat32Array(), PackedFloat32Array()]
	for w in 2:
		n[w].resize(roles)
		z_sum[w].resize(roles)
		wide[w].resize(roles)
		station_z[w].resize(roles)
	for s in trace:
		if s.size() != ctx.players.size() + 1:
			continue
		var ball: Vector3 = s[0]
		var carrier := -1
		var best := 2.5
		for pid in ctx.players.size():
			var d := SimConsts.horizontal_length(s[pid + 1] - ball)
			if d < best:
				best = d
				carrier = pid
		if carrier < 0:
			continue
		var team: int = ctx.players[carrier].team
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper:
				continue
			var w := 1 if p.team == team else 0
			var z: float = absf(s[pid + 1].z)
			n[w][p.role] += 1
			z_sum[w][p.role] += z
			if z > 20.4:
				wide[w][p.role] += 1
			var home: Vector3 = ctx.teams[p.team].formation.homes[p.slot]
			station_z[w][p.role] += absf(home.z)
	print("role   station|z|   in possession: mean|z|  wide%     defending: mean|z|  wide%")
	for r in roles:
		if n[1][r] == 0:
			continue
		print("%-5s %8.1f %22.1f %6.0f%% %22.1f %6.0f%%" % [
			SimRole.NAMES[r], station_z[1][r] / float(n[1][r]),
			z_sum[1][r] / float(n[1][r]), 100.0 * float(wide[1][r]) / float(n[1][r]),
			z_sum[0][r] / float(n[0][r]), 100.0 * float(wide[0][r]) / float(n[0][r])])
