extends SceneTree
## Throwaway probe: every attempt on goal, with where it was struck from.
##
##   godot --headless --script res://tools/_shotmap.gd -- --seed N --matches M
##
## One line per shot, tab separated, so several of these can run at once and the
## lines be summed outside. `Shots by distance` in the diagnose bins the same
## population; this prints it raw, adds the box test and the angle, and splits
## the header off by joining the shot to the touch that struck it.


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

	var base := int(flags.get("seed", "1"))
	var count := int(flags.get("matches", "1"))
	for m_i in count:
		var opts := SimRunner.Options.new()
		opts.seed_value = base + m_i
		opts.home_quality = 0.6
		opts.away_quality = 0.6
		opts.minutes = float(flags.get("minutes", "90"))
		opts.clock_rate = float(flags.get("clock-rate", "10"))
		var m := SimRunner.build(opts)
		m.run_to_completion()
		_dump(m)
	quit()


func _dump(m: SimMatch) -> void:
	var ctx := m.ctx
	# A header at goal logs the touch and the shot on the same tick, by the same
	# man, and nothing on the shot record says which strike it was.
	var headed := {}
	for e in ctx.telemetry.events:
		if int(e["ev"]) != SimTelemetry.Ev.TOUCH:
			continue
		if int(e["kind"]) != SimTelemetry.Touch.HEADER:
			continue
		headed["%d:%d" % [int(e.get("t", -1)), int(e.get("p", -1))]] = true

	for e in ctx.telemetry.events:
		if int(e["ev"]) != SimTelemetry.Ev.SHOT:
			continue
		var team := int(e["team"])
		var from: Vector3 = e["from"]
		var aim: Vector3 = e["aim"]
		# Flip-free: the aim is in the goal being attacked, whichever end that is.
		var dx: float = absf(aim.x - from.x)
		var dz: float = absf(from.z)
		var d: float = sqrt(dx * dx + dz * dz)
		var in_box := 1 if dx <= ctx.pitch.penalty_depth \
			and dz <= ctx.pitch.penalty_half_width else 0
		var in_six := 1 if dx <= ctx.pitch.goal_area_depth \
			and dz <= ctx.pitch.goal_area_half_width else 0
		var half: float = ctx.pitch.goal_half_width
		var theta: float = absf(atan2(half - from.z, maxf(dx, 0.4)) \
			- atan2(-half - from.z, maxf(dx, 0.4)))
		var key := "%d:%d" % [int(e.get("t", -1)), int(e.get("p", -1))]
		print("SHOT\t%d\t%d\t%.2f\t%.2f\t%.2f\t%d\t%d\t%.1f\t%d\t%.4f\t%d\t%d\t%d\t%d" % [
			ctx.config.seed_value, team, d, dx, dz, in_box, in_six,
			rad_to_deg(theta), 1 if headed.has(key) else 0,
			float(e.get("quality", 0.0)),
			1 if bool(e.get("on_target", false)) else 0,
			1 if bool(e.get("goal", false)) else 0,
			1 if bool(e.get("blocked", false)) else 0,
			1 if bool(e.get("first_time", false)) else 0,
		])
