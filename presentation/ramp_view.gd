extends Node3D
## The FIFA ramp test, run on the match ball.
##
## A ball is released at the top of a one-metre ramp set at 45 degrees and the
## distance it rolls from the foot is measured. FIFA's Quality Programme wants
## 4 to 10 m (Quality) or 4 to 8 m (Quality Pro). Four balls run at once, one
## per surface the engine has -- dry, wet, long grass, wet long grass -- each
## on its own `SimEnv` and integrated by `SimBall` from the foot of the ramp,
## which is the part the test measures. The descent is the textbook roll
## without slip, `a = 5/7 g sin 45`: a 45-degree slope is outside the
## integrator's small-slope surface model, and the test only asks what the
## grass does with the ball the ramp delivers.
##
## Presentation only. Nothing here changes a match.
##
##     ./run.sh ramp [--flat] [--speed S] [--shot PATH --at T]
##
## `--flat` runs on a plane instead of the match turf. Keys: R replays, space
## pauses, 1 2 3 cut the camera, + and - change the playback speed.

const RAMP_HEIGHT := 1.0
const RAMP_LENGTH := RAMP_HEIGHT * sqrt(2.0)
## Rolling without slip down the incline.
const RAMP_ACCEL := 5.0 / 7.0 * SimConsts.GRAVITY * sqrt(0.5)
const FIFA_LOW := 4.0
const FIFA_PRO := 8.0
const FIFA_HIGH := 10.0
const STRIP_X0 := -2.5
const STRIP_X1 := 14.0
const LANE_WIDTH := 2.0
const LANES := [
	["dry", false, false],
	["wet", true, false],
	["long grass", false, true],
	["wet, long grass", true, true],
]

var _flat := false
var _speed := 0.5
var _shot_path := ""
var _shot_at := 4.0
var _paused := false
var _sim_time := 0.0
var _accum := 0.0
var _elapsed := 0.0
var _cut := 1

var _envs: Array[SimEnv] = []
var _balls: Array[SimBall] = []
var _on_ramp: Array[bool] = []
var _stopped: Array[float] = []
var _rolls: Array[Quaternion] = []
var _ball_nodes: Array[Node3D] = []
var _lane_labels: Array[Label3D] = []
var _camera: Camera3D
var _hud: Label
var _panels: ImageTexture


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--flat":
			_flat = true
		elif args[i] == "--speed" and i + 1 < args.size():
			_speed = float(args[i + 1])
		elif args[i] == "--shot" and i + 1 < args.size():
			_shot_path = args[i + 1]
		elif args[i] == "--at" and i + 1 < args.size():
			_shot_at = float(args[i + 1])
	SimMatchView3D._apply_render_size(get_window())
	var windowed := SimMatchView3D._requested_size("--windowed")
	if _shot_path != "" or windowed != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if windowed != Vector2i.ZERO:
			DisplayServer.window_set_size(windowed)
	_build_world()
	_build_lanes()
	_build_hud()
	_reset()
	if _shot_path != "":
		_advance(_shot_at)


# --- The scene --------------------------------------------------------------


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SimPalette.SKY.lightened(0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	SimCharacterBuilder.soften_shadow(sun, 30.0)
	add_child(sun)
	SimCharacterBuilder.add_fill_light(self, -35.0)
	_camera = Camera3D.new()
	_camera.fov = 46.0
	add_child(_camera)
	_cut_to(1)


func _lane_z(i: int) -> float:
	return (float(i) - 1.5) * LANE_WIDTH


func _build_lanes() -> void:
	# The match's own painted panels, so a turn reads as a turn.
	var painter := SimMatchView3D.new()
	_panels = painter._ball_panel_texture()
	painter.free()
	for i in LANES.size():
		var lane: Array = LANES[i]
		var env := SimEnv.new(lane[1], lane[2], 0.0)
		if _flat:
			env.surface_amplitude = 0.0
			env.camber = 0.0
		_envs.append(env)
		var z := _lane_z(i)
		var zl := z - LANE_WIDTH * 0.5
		var zr := z + LANE_WIDTH * 0.5
		# The turf, cut from the surface this lane's ball rides.
		_add_strip(env, STRIP_X0, STRIP_X1, zl, zr, 0.0,
			SimPalette.GRASS if i % 2 == 0 else SimPalette.PINE)
		# The FIFA band, and the Pro half of it a shade stronger.
		_add_strip(env, FIFA_LOW, FIFA_HIGH, zl + 0.05, zr - 0.05, 0.006, SimPalette.LIME.lerp(Color.WHITE, 0.3))
		_add_strip(env, FIFA_LOW, FIFA_PRO, zl + 0.05, zr - 0.05, 0.009, SimPalette.LIME.lerp(Color.WHITE, 0.15))
		# Metre lines from the foot of the ramp.
		for m in range(0, 13):
			_add_strip(env, float(m) - 0.02, float(m) + 0.02, zl, zr, 0.012, SimPalette.CHALK)
		# The ball, at its true size.
		var node := Node3D.new()
		var body := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = SimConsts.BALL_RADIUS
		mesh.height = SimConsts.BALL_RADIUS * 2.0
		mesh.radial_segments = 28
		mesh.rings = 14
		body.mesh = mesh
		var mat := SimCharacterBuilder.flat_material(SimPalette.CHALK)
		mat.albedo_texture = _panels
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		body.material_override = mat
		node.add_child(body)
		add_child(node)
		_ball_nodes.append(node)
		# The lane's caption, behind the ramp.
		var label := Label3D.new()
		label.font_size = 44
		# The same size on screen whichever lane it captions.
		label.fixed_size = true
		label.pixel_size = 0.00035
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = SimPalette.INK
		label.outline_modulate = SimPalette.CHALK
		label.outline_size = 10
		label.position = Vector3(-1.2, 1.3, z)  # follows the ball once it runs
		add_child(label)
		_lane_labels.append(label)
		_balls.append(SimBall.new())
		_on_ramp.append(true)
		_stopped.append(-1.0)
		_rolls.append(Quaternion.IDENTITY)
	_build_ramp()
	# Metre numbers along the far edge.
	for m in range(1, 13):
		var label := Label3D.new()
		label.text = "%d m" % m
		label.font_size = 48
		label.pixel_size = 0.008
		label.modulate = SimPalette.INK
		label.outline_modulate = SimPalette.CHALK
		label.outline_size = 8
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		label.position = Vector3(float(m), 0.05, _lane_z(0) - LANE_WIDTH * 0.5 - 0.45)
		add_child(label)
	var band := Label3D.new()
	band.text = "FIFA ball roll: 4-10 m Quality, 4-8 m Quality Pro"
	band.font_size = 48
	band.pixel_size = 0.0025
	band.modulate = SimPalette.INK
	band.outline_modulate = SimPalette.CHALK
	band.outline_size = 8
	band.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	band.position = Vector3(7.0, 0.05, _lane_z(LANES.size() - 1) + LANE_WIDTH * 0.5 + 0.5)
	add_child(band)


## A strip of ground following `env`'s surface, `y_off` above it.
func _add_strip(env: SimEnv, x0: float, x1: float, z0: float, z1: float, y_off: float, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.25
	var nx: int = maxi(1, int(ceil((x1 - x0) / step)))
	var nz: int = maxi(1, int(ceil((z1 - z0) / step)))
	for ix in nx:
		for iz in nz:
			var xa := lerpf(x0, x1, float(ix) / float(nx))
			var xb := lerpf(x0, x1, float(ix + 1) / float(nx))
			var za := lerpf(z0, z1, float(iz) / float(nz))
			var zb := lerpf(z0, z1, float(iz + 1) / float(nz))
			for v in [[xb, zb], [xa, zb], [xa, za], [xb, za], [xb, zb], [xa, za]]:
				var slope := env.surface_slope(v[0], v[1])
				st.set_normal(Vector3(-slope.x, 1.0, -slope.z).normalized())
				st.add_vertex(Vector3(v[0], env.surface_height(v[0], v[1]) + y_off, v[1]))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = SimCharacterBuilder.flat_material(colour)
	add_child(mi)


## One wedge across every lane: top at x = -1, foot at x = 0.
func _build_ramp() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := _lane_z(0) - LANE_WIDTH * 0.5
	var z1 := _lane_z(LANES.size() - 1) + LANE_WIDTH * 0.5
	var top_back := Vector3(-RAMP_HEIGHT - 0.4, RAMP_HEIGHT, 0.0)
	var top := Vector3(-RAMP_HEIGHT, RAMP_HEIGHT, 0.0)
	var foot := Vector3(0.0, 0.0, 0.0)
	var back := Vector3(-RAMP_HEIGHT - 0.4, 0.0, 0.0)
	# The slope.
	_quad(st, Vector3(top.x, top.y, z0), Vector3(top.x, top.y, z1), Vector3(foot.x, foot.y, z1), Vector3(foot.x, foot.y, z0), Vector3(1, 1, 0).normalized())
	# The platform at the top.
	_quad(st, Vector3(top_back.x, top_back.y, z0), Vector3(top_back.x, top_back.y, z1), Vector3(top.x, top.y, z1), Vector3(top.x, top.y, z0), Vector3.UP)
	# The back.
	_quad(st, Vector3(back.x, back.y, z1), Vector3(back.x, back.y, z0), Vector3(top_back.x, top_back.y, z0), Vector3(top_back.x, top_back.y, z1), Vector3.LEFT)
	# The two ends.
	_tri(st, Vector3(back.x, 0.0, z0), Vector3(top_back.x, RAMP_HEIGHT, z0), Vector3(top.x, RAMP_HEIGHT, z0), Vector3.FORWARD)
	_tri(st, Vector3(back.x, 0.0, z0), Vector3(top.x, RAMP_HEIGHT, z0), Vector3(foot.x, 0.0, z0), Vector3.FORWARD)
	_tri(st, Vector3(back.x, 0.0, z1), Vector3(top.x, RAMP_HEIGHT, z1), Vector3(top_back.x, RAMP_HEIGHT, z1), Vector3.BACK)
	_tri(st, Vector3(back.x, 0.0, z1), Vector3(foot.x, 0.0, z1), Vector3(top.x, RAMP_HEIGHT, z1), Vector3.BACK)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = SimCharacterBuilder.flat_material(SimPalette.SAND)
	add_child(mi)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	# Wound to face `n`.
	if (b - a).cross(c - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


func _build_hud() -> void:
	_hud = Label.new()
	_hud.position = Vector2(18.0, 14.0)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_color", SimPalette.INK)
	_hud.add_theme_color_override("font_outline_color", SimPalette.CHALK)
	_hud.add_theme_constant_override("outline_size", 6)
	add_child(_hud)


func _cut_to(n: int) -> void:
	_cut = n
	match n:
		1:
			# Three-quarter, from the near side: the ramp at the left, the
			# lanes running right, the band in the middle of the frame.
			# In front of the ramp, so its face and the balls on it are seen.
			_camera.position = Vector3(6.5, 3.4, 9.5)
			_camera.look_at(Vector3(3.2, 0.2, 0.3))
		2:
			_camera.position = Vector3(5.0, 2.2, 11.0)
			_camera.look_at(Vector3(5.0, 0.2, 0.0))
		_:
			_camera.position = Vector3(5.0, 12.0, 4.0)
			_camera.look_at(Vector3(5.0, 0.0, 0.0))


# --- The test ---------------------------------------------------------------


func _reset() -> void:
	_sim_time = 0.0
	_accum = 0.0
	for i in LANES.size():
		_on_ramp[i] = true
		_stopped[i] = -1.0
		_rolls[i] = Quaternion.IDENTITY
	_place_all()


## The ball leaves the foot of the ramp rolling at `sqrt(2 g h * 5/7)`.
static func ramp_exit_speed() -> float:
	return sqrt(2.0 * SimConsts.GRAVITY * RAMP_HEIGHT * 5.0 / 7.0)


static func ramp_time() -> float:
	return sqrt(2.0 * RAMP_LENGTH / RAMP_ACCEL)


## One fixed simulation step for every lane.
func _step(dt: float) -> void:
	_sim_time += dt
	for i in LANES.size():
		var ball := _balls[i]
		var z := _lane_z(i)
		if _on_ramp[i]:
			if _sim_time < ramp_time():
				# Down the incline: position and spin are kinematic, and the
				# visual roll turns at the rolling rate.
				var v := RAMP_ACCEL * _sim_time
				_turn(i, Vector3(0.0, 0.0, -v / SimConsts.BALL_RADIUS), dt)
				continue
			_on_ramp[i] = false
			var v0 := ramp_exit_speed()
			ball.reset(Vector3(0.0, SimConsts.BALL_RADIUS + _envs[i].surface_height(0.0, z), z))
			ball.vel = Vector3(v0, 0.0, 0.0)
			ball.spin = Vector3(0.0, 0.0, -v0 / SimConsts.BALL_RADIUS)
			ball.grounded = true
		if _stopped[i] >= 0.0:
			continue
		ball.integrate(dt, _envs[i])
		_turn(i, ball.spin, dt)
		if ball.grounded and ball.ground_speed() < 1e-3:
			_stopped[i] = _sim_time


func _turn(i: int, spin: Vector3, dt: float) -> void:
	var rate := spin.length()
	if rate < 1e-4:
		return
	_rolls[i] = (Quaternion(spin / rate, rate * dt) * _rolls[i]).normalized()


func _advance(seconds: float) -> void:
	var steps := int(round(seconds / SimConsts.DT))
	for s in steps:
		_step(SimConsts.DT)
	_place_all()


func _place_all() -> void:
	for i in LANES.size():
		var z := _lane_z(i)
		var pos: Vector3
		if _on_ramp[i]:
			var s: float = minf(0.5 * RAMP_ACCEL * _sim_time * _sim_time, RAMP_LENGTH)
			var along := Vector3(-RAMP_HEIGHT, RAMP_HEIGHT, z) + Vector3(1.0, -1.0, 0.0) * (s * sqrt(0.5))
			pos = along + Vector3(1.0, 1.0, 0.0).normalized() * SimConsts.BALL_RADIUS
		else:
			pos = _balls[i].pos
		_ball_nodes[i].transform = Transform3D(Basis(_rolls[i]), pos)
		_lane_labels[i].position = pos + Vector3(0.0, 0.42, 0.0)
		var lane: Array = LANES[i]
		var text: String = lane[0]
		if _stopped[i] >= 0.0:
			text += "\n%.2f m" % _balls[i].pos.x
		elif not _on_ramp[i]:
			text += "\n%.2f m  %.1f m/s" % [_balls[i].pos.x, _balls[i].ground_speed()]
		_lane_labels[i].text = text
	var hud := "FIFA ramp test on the match ball: 1 m ramp at 45 deg, off the foot at %.2f m/s rolling%s\n" % [
		ramp_exit_speed(), "  (flat plane)" if _flat else "  (match turf)"] \
		+ "Down the ramp: rolling without slip. From the foot: SimBall, the integrator every match uses.\n" \
		+ "FIFA wants 4-10 m (Quality), 4-8 m (Quality Pro).\n" \
		+ "t %.2f s   x%.2f%s      R replay   space pause   1 2 3 camera   + - speed\n" % [
		_sim_time, _speed, "  paused" if _paused else ""]
	for i in LANES.size():
		hud += "\n%-16s roll decel %.2f m/s^2" % [LANES[i][0], _envs[i].roll_decel]
		if _stopped[i] >= 0.0:
			var run: float = _balls[i].pos.x
			var verdict := "short of FIFA's 4 m" if run < FIFA_LOW else ("FIFA Pro" if run <= FIFA_PRO else ("FIFA Quality" if run <= FIFA_HIGH else "past 10 m"))
			hud += "   %.2f m in %.2f s   %s" % [run, _stopped[i] - ramp_time(), verdict]
	_hud.text = hud


func _process(delta: float) -> void:
	_elapsed += delta
	if not _paused:
		_accum += delta * _speed
		while _accum >= SimConsts.DT:
			_accum -= SimConsts.DT
			_step(SimConsts.DT)
	_place_all()
	_maybe_shoot()


func _maybe_shoot() -> void:
	if _shot_path == "" or _elapsed < 0.4:
		return
	var path := _shot_path
	_shot_path = ""
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	for i in LANES.size():
		var lane: Array = LANES[i]
		print("%-16s %.2f m in %.2f s" % [lane[0], _balls[i].pos.x, _stopped[i] - ramp_time()])
	print("saved %s at t=%.1f" % [path, _sim_time])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			_reset()
		KEY_SPACE:
			_paused = not _paused
		KEY_1:
			_cut_to(1)
		KEY_2:
			_cut_to(2)
		KEY_3:
			_cut_to(3)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_speed = minf(_speed * 1.5, 4.0)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_speed = maxf(_speed / 1.5, 0.05)
		KEY_ESCAPE, KEY_Q:
			get_tree().quit()
