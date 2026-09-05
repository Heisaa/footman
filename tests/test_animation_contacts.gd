extends SceneTree
## Presentation-only regression: repeated contact solving must not grow a boot.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var figure := Node3D.new()
	root.add_child(figure)
	figure.scale = Vector3.ONE * 1.13
	var rest_scales := {}
	for tag in ["L", "R"]:
		var hip := Node3D.new()
		hip.name = "Hip" + tag
		hip.position = Vector3(-0.14 if tag == "L" else 0.14, 0.82, 0.0)
		figure.add_child(hip)
		var knee := Node3D.new()
		knee.name = "Knee" + tag
		knee.position.y = -0.4
		hip.add_child(knee)
		var ankle := Node3D.new()
		ankle.name = "Ankle" + tag
		ankle.position.y = -0.34
		if tag == "R":
			ankle.scale = Vector3(0.9, 1.05, 1.15)
		knee.add_child(ankle)
		for joint in [hip, knee, ankle]:
			rest_scales[joint.name] = joint.scale
	var worst := 0.0
	for frame in 12000:
		var t := float(frame) / 60.0
		figure.position = Vector3(30.0 + sin(t) * 4.0, 0.0, 20.0)
		figure.rotation = Vector3(0.0, t * 0.7, 0.0)
		SimMatchView3D.pose_gait(figure, 5.0, t * 12.0, 0.2)
		for tag in ["L", "R"]:
			var target := figure.to_global(Vector3(-0.14 if tag == "L" else 0.14, 0.08, sin(t * 12.0) * 0.25))
			SimMatchView3D._solve_leg(figure, tag, target, figure.global_basis, 0.8)
			for stem in ["Hip", "Knee", "Ankle"]:
				var joint := figure.find_child(stem + tag, true, false) as Node3D
				if not joint.basis.is_finite():
					printerr("FAIL: non-finite joint basis at frame ", frame)
					quit(1)
					return
				worst = maxf(worst, joint.scale.distance_to(rest_scales[joint.name]))
		if worst > 0.01:
			printerr("FAIL: local joint scale drift ", worst, " at frame ", frame)
			quit(1)
			return
	print("PASS: 12,000 frames of repeated leg contacts; maximum local scale drift ", worst)
	figure.free()
	quit(0)
