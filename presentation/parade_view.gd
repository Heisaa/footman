extends Node3D
## The parade: a rank of generated players, close up, numbered, turning slowly.
##
## A match is the wrong place to judge a figure. Everyone is thirty metres away,
## half of them are behind the ball, and the one with the odd hairline has gone
## before anyone can point at him. This stands four of them in a row at reading
## distance, spins them so the back of the shirt comes round, and captions each
## one with his number, his name and his appearance seed — which is the whole
## point: a note that says "seed 7, number 9, the head is still too big" names a
## man the owner can be shown again with one command.
##
## The squad is the *match* squad. It is built through `SimRunner.build`, the
## same call `view3d` makes, so `parade --seed 7` and `view3d --seed 7` are the
## same twenty-two men and a note taken here holds there.
##
## Presentation only. It builds a match to read the squad list off it and never
## ticks one.

## How many stand in the rank at once. Four, because the camera has to be close
## enough that a face is a face and a drawn line is a line: six across a 16:9
## frame puts the eye eleven metres back, which is match distance again and the
## whole reason this view exists.
const PER_PAGE := 4
const SPACING := 1.1
## The frame is at least this tall in metres, so a short rank fills the shot
## rather than sitting in the middle of it.
const FRAME_HEIGHT_MIN := 2.6
## The rank is seen almost level. A figure is a silhouette and the camera that
## destroys a silhouette is the steep one.
const ELEVATION_DEG := 7.0
const FOV := 32.0
## Degrees a second on the turntable. Slow enough to look at, fast enough that
## nobody waits for the back of the shirt.
const SPIN_RATE := 24.0
const BREATH_RATE := 1.3
const BREATH_DEPTH := 0.006
## Arms hang inside the torso on a figure that is not running, so the stand pose
## pushes them out and puts a bend in the elbow.
const ARM_OUT := 0.16
const ELBOW_BEND := -0.22

var _seed := 7
var _page := 0
var _spin := true
var _turn := 0.0
var _outline := true
var _face := SimAppearance.Face.NEUTRAL
var _shot_path := ""
var _elapsed := 0.0

var _pool: Array = []
var _kits: Array[PackedColorArray] = []
var _nodes: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _camera: Camera3D = null
var _caption: Label = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1])
		elif args[i] == "--page" and i + 1 < args.size():
			_page = int(args[i + 1])
		elif args[i] == "--no-outline":
			_outline = false
		elif args[i] == "--still":
			_spin = false
		elif args[i] == "--turn" and i + 1 < args.size():
			# Which way the rank faces at the start. `--turn 180 --still` is the
			# shot of the backs of the shirts.
			_turn = float(args[i + 1])
		elif args[i] == "--face" and i + 1 < args.size():
			_face = int(args[i + 1])
		elif args[i] == "--shot" and i + 1 < args.size():
			_shot_path = args[i + 1]
	# The window is fullscreen by project setting, which is not the frame
	# `--resolution` asked for. A screenshot has to put itself back in a window.
	if _shot_path != "":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_build_world()
	_load_squad()
	_build_row()


# --- The stand --------------------------------------------------------------


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Paper, not a pitch colour: the kits are being judged and they have to read
	# against something that is not competing with them.
	env.background_color = SimPalette.PAPER
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 24.0)
	plane.orientation = PlaneMesh.FACE_Y
	ground.mesh = plane
	ground.material_override = SimCharacterBuilder.flat_material(SimPalette.GRASS)
	add_child(ground)

	_camera = Camera3D.new()
	_camera.fov = FOV
	add_child(_camera)

	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24.0, 18.0)
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.add_theme_color_override("font_color", SimPalette.INK)
	_caption.add_theme_color_override("font_outline_color", SimPalette.CHALK)
	_caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(_caption)


## The squad a seed produces, read off a match rather than invented here, so the
## rank is the eleven the view and the batch runner would show for that seed.
func _load_squad() -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = _seed
	opts.events = false
	var m := SimRunner.build(opts)
	_pool = []
	for p in m.ctx.players:
		_pool.append(p)
	var home_colour: Color = m.ctx.teams[0].kit[0]
	_kits = [
		SimAppearance.kit_for(home_colour),
		SimAppearance.away_kit(home_colour, _seed),
	]
	_page = clampi(_page, 0, maxi(_pages() - 1, 0))


func _pages() -> int:
	return int(ceil(float(_pool.size()) / float(PER_PAGE)))


func _build_row() -> void:
	for node in _nodes:
		node.queue_free()
	for label in _labels:
		label.queue_free()
	_nodes.clear()
	_labels.clear()

	var first := _page * PER_PAGE
	var count: int = mini(PER_PAGE, _pool.size() - first)
	for i in count:
		var p = _pool[first + i]
		var appearance := SimAppearance.from_seed(p.appearance_seed)
		var at := Vector3((float(i) - float(count - 1) * 0.5) * SPACING, 0.0, 0.0)
		var node := SimCharacterBuilder.build(
			appearance, _kits[p.team], p.shirt, _outline)
		node.position = at
		node.rotation.y = deg_to_rad(_turn)
		add_child(node)
		_nodes.append(node)
		_stand(node)
		SimCharacterBuilder.set_expression(node, _face)

		var label := Label3D.new()
		# The seed is on the caption because it is the handle for feedback: it is
		# what puts this exact man back on screen tomorrow.
		label.text = "#%d  %s\n%.2f m\nseed %d" % [
			p.shirt, p.player_name, appearance.height, p.appearance_seed,
		]
		label.font_size = 64
		label.pixel_size = 0.0011
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = SimPalette.INK
		label.outline_modulate = SimPalette.CHALK
		label.outline_size = 12
		label.no_depth_test = true
		label.position = at + Vector3(0.0, -0.02, 0.72)
		add_child(label)
		_labels.append(label)

	_frame_row(count)
	_write_caption()


## Standing, not running: shoulders pushed out of the torso, a bend in the elbow,
## and the base height of the spine remembered so the breath can move it.
func _stand(node: Node3D) -> void:
	for tag in ["L", "R"]:
		var shoulder := node.find_child("Shoulder" + tag, true, false) as Node3D
		if shoulder != null:
			shoulder.rotation = Vector3(0.0, 0.0, (-1.0 if tag == "L" else 1.0) * ARM_OUT)
		var elbow := node.find_child("Elbow" + tag, true, false) as Node3D
		if elbow != null:
			elbow.rotation = Vector3(ELBOW_BEND, 0.0, 0.0)
	var spine := node.find_child("Spine", true, false) as Node3D
	if spine != null:
		node.set_meta("spine_y", spine.position.y)


## Pulls the camera back far enough to hold the rank, at the aspect actually
## being rendered rather than 16:9 assumed — a virtual display hands out
## whatever screen it was started with, and the outer man falls off the edge.
func _frame_row(count: int) -> void:
	var span: float = float(count) * SPACING + 0.5
	var view := get_viewport().get_visible_rect().size
	var aspect: float = view.x / view.y if view.y > 0.0 else 16.0 / 9.0
	# Whichever is further back: the distance that holds the rank across the
	# frame, and the one that holds a man and his caption up it. Fitting only the
	# width leaves a tall frame mostly grass.
	var half_tan := tan(deg_to_rad(FOV) * 0.5)
	var d: float = maxf((span / aspect * 0.5) / half_tan, (FRAME_HEIGHT_MIN * 0.5) / half_tan)
	var centre := Vector3(0.0, 1.05, 0.0)
	var elevation := deg_to_rad(ELEVATION_DEG)
	_camera.position = centre + Vector3(0.0, d * sin(elevation), d * cos(elevation))
	_camera.look_at(centre, Vector3.UP)


func _write_caption() -> void:
	var first := _page * PER_PAGE + 1
	var last: int = mini(_page * PER_PAGE + PER_PAGE, _pool.size())
	_caption.text = "\n".join([
		"PARADE   match seed %d   men %d-%d of %d   page %d/%d" % [
			_seed, first, last, _pool.size(), _page + 1, _pages(),
		],
		"outline %s   %s" % [
			"on" if _outline else "off", "turning" if _spin else "still",
		],
		"< >  page    N / P  seed    SPACE  turn    O  outline    1-5  face    Q  quit",
	])


# --- Frame ------------------------------------------------------------------


func _process(delta: float) -> void:
	_elapsed += delta
	for i in _nodes.size():
		var node: Node3D = _nodes[i]
		if _spin:
			node.rotation.y += deg_to_rad(SPIN_RATE) * delta
		# A figure that does not move at all reads as a shop dummy, so it breathes.
		var spine := node.find_child("Spine", true, false) as Node3D
		if spine != null and node.has_meta("spine_y"):
			var base: float = node.get_meta("spine_y")
			spine.position.y = base + sin(_elapsed * BREATH_RATE + float(i)) * BREATH_DEPTH
	_maybe_shoot()


func _maybe_shoot() -> void:
	if _shot_path == "" or _elapsed < 0.4:
		return
	var path := _shot_path
	_shot_path = ""
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved %s: seed %d, men %d-%d of %d" % [
		path, _seed, _page * PER_PAGE + 1,
		mini(_page * PER_PAGE + PER_PAGE, _pool.size()), _pool.size(),
	])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_RIGHT, KEY_PERIOD:
			_page = (_page + 1) % maxi(_pages(), 1)
			_build_row()
		KEY_LEFT, KEY_COMMA:
			_page = (_page - 1 + maxi(_pages(), 1)) % maxi(_pages(), 1)
			_build_row()
		KEY_N:
			_seed += 1
			_page = 0
			_load_squad()
			_build_row()
		KEY_P:
			_seed = maxi(_seed - 1, 1)
			_page = 0
			_load_squad()
			_build_row()
		KEY_SPACE:
			_spin = not _spin
			_write_caption()
		KEY_O:
			# Rebuilt rather than toggled on the material: the ink is a second pass
			# hung off every material in the figure, and the honest comparison is
			# the figure built both ways.
			_outline = not _outline
			_build_row()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_face = key - KEY_1
			for node in _nodes:
				SimCharacterBuilder.set_expression(node, _face)
		KEY_Q, KEY_ESCAPE:
			get_tree().quit()
