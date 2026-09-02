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
## `--world N` stands a generated club's squad instead: `WorldGen.club` at that
## seed, the men the game will actually field, with the record on the caption --
## age, country, archetype -- next to the face it was packed into. That is the
## view for judging whether a thirty-six-year-old looks thirty-six.
##
## **It moves.** A figure judged standing still is half judged: a shoulder that
## reads at rest can tear open the moment an arm lifts, and a gait is the thing
## a man spends a match doing. `[` and `]` step through the animation states,
## `A` rolls through them on its own, `0` goes back to standing, and `--anim RUN`
## opens on one. The poses are `SimMatchView3D`'s own -- the same table the match
## plays, not a second one written to look like it.
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
## The states the parade cycles, in the order they are worth looking at: the
## gait first, because it is what a figure spends a match doing, then the ones
## that bend it hardest.
##
## `SimMatchView3D` owns both the poses and the speeds -- a figure judged here
## has to be posed by the code the match plays, or this view is judging a
## different man.
##
## Every state in `SimConsts.Anim` is here, and `_ready` checks it: a state the
## parade cannot show is a state nobody judges up close.
const REEL := [
	SimConsts.Anim.IDLE, SimConsts.Anim.JOG, SimConsts.Anim.RUN,
	SimConsts.Anim.SPRINT, SimConsts.Anim.TURN, SimConsts.Anim.SHUFFLE,
	SimConsts.Anim.KICK_LIGHT, SimConsts.Anim.KICK_HARD, SimConsts.Anim.VOLLEY,
	SimConsts.Anim.TRAP, SimConsts.Anim.HEADER, SimConsts.Anim.JUMP,
	SimConsts.Anim.CHEST, SimConsts.Anim.THROW,
	SimConsts.Anim.TACKLE, SimConsts.Anim.SLIDE, SimConsts.Anim.STUMBLE,
	SimConsts.Anim.FALL, SimConsts.Anim.GET_UP, SimConsts.Anim.PROTEST,
	SimConsts.Anim.CELEBRATE, SimConsts.Anim.DEJECTED, SimConsts.Anim.EXHAUSTED,
	SimConsts.Anim.DIVE_LEFT, SimConsts.Anim.DIVE_RIGHT,
	SimConsts.Anim.KEEPER_CATCH, SimConsts.Anim.PUNCH, SimConsts.Anim.KEEPER_HOLD,
	SimConsts.Anim.HOLD,
]
## Seconds a one-shot state is held before the reel moves on. Long enough to
## watch the arc twice, which is what makes a follow-through readable.
const REEL_DWELL := 2.4
## Cadence ceiling, in cycles a second. The match takes this off the simulation
## step; nothing here is stepped, so it is stated.
const REEL_MAX_HZ := 3.4

const BREATH_RATE := 1.3
const BREATH_DEPTH := 0.006
## Arms hang inside the torso on a figure that is not running, so the stand pose
## pushes them out and puts a bend in the elbow.
const ARM_OUT := 0.10
const ELBOW_BEND := -0.22

## Set on the scene so it runs from the editor without arguments:
## `world_parade.tscn` sets `world_seed`. A `--world` on the command line wins.
@export var world_seed := -1
@export var club_index := 0
@export var reputation := 0.45

var _seed := 7
## A world seed, or -1 for the match squad. `_club` is which club of the
## league at that seed, and `_rep` the reputation a lone club is built at.
var _world := -1
var _club := 0
var _rep := 0.45
## The record behind each man in `_pool`, when the pool came from the world.
var _records: Array = []
var _page := 0
var _spin := true
var _turn := 0.0
## Degrees the camera sits above level. `ELEVATION_DEG` by default; `--elevation
## 40 --turn 60` is the man seen as the match sees him.
var _elevation := ELEVATION_DEG
## The stops `E` walks: level, the match camera, the steepest it gets.
const ELEVATION_STOPS := [7.0, 40.0, 60.0]
## Camera distance multiplier. 1 holds the rank; 0.5 is the head and shoulders
## of the middle two. `+` and `-` step it.
var _zoom := 1.0
var _face := SimAppearance.Face.NEUTRAL
## Which of `REEL` is playing, or -1 for the stand pose the parade opened with.
var _reel := -1
## True while the reel advances on its own; false holds one state to look at.
var _rolling := false
var _anim_clock := 0.0
## Which cut to put on the rank, overriding what the men were born with. The four
## on screen take this one and the next three, so five pages walk the library.
## Negative leaves every man his own hair.
var _hair := -1
## The same for the nose library, over `NOSE_LIBRARY`.
var _nose := -1
## Moustache and beard: N puts style N on the first man and walks on; -2 is
## none on every man; -1 leaves each man his own.
var _tache := -1
var _beard := -1
## Chin on the first man, 0-1, with the next three stepping up by a quarter
## each: `--chin 0` walks none, a quarter, a half, three quarters. Negative
## leaves each man his own.
var _chin := -1.0
## The same for the brow ridge.
var _brow := -1.0
## One man for every column, by his place in the squad (1-based), so a sheet
## of cuts is a sheet of cuts and not of men. Zero is the squad as it comes.
var _man := 0
## Nobody wears an accessory, for a look at the hair alone.
var _plain := false
var _shot_path := ""
var _elapsed := 0.0

var _pool: Array = []
var _kits: Array[PackedColorArray] = []
var _nodes: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _camera: Camera3D = null
var _caption: Label = null
## The record lines, along the bottom of the frame where they cover nobody's hair.
var _record_label: Label = null


func _ready() -> void:
	for anim in SimConsts.Anim.values():
		assert(anim in REEL, "parade reel is missing %s" % SimConsts.Anim.keys()[anim])
	_world = world_seed
	_club = club_index
	_rep = reputation
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1])
		elif args[i] == "--world" and i + 1 < args.size():
			_world = int(args[i + 1])
		elif args[i] == "--club" and i + 1 < args.size():
			_club = int(args[i + 1])
		elif args[i] == "--rep" and i + 1 < args.size():
			_rep = float(args[i + 1])
		elif args[i] == "--page" and i + 1 < args.size():
			_page = int(args[i + 1])
		elif args[i] == "--still":
			_spin = false
		elif args[i] == "--turn" and i + 1 < args.size():
			# Which way the rank faces at the start. `--turn 180 --still` is the
			# shot of the backs of the shirts.
			_turn = float(args[i + 1])
		elif args[i] == "--elevation" and i + 1 < args.size():
			_elevation = float(args[i + 1])
		elif args[i] == "--zoom" and i + 1 < args.size():
			_zoom = float(args[i + 1])
		elif args[i] == "--face" and i + 1 < args.size():
			_face = int(args[i + 1])
		elif args[i] == "--anim" and i + 1 < args.size():
			var wanted := String(args[i + 1]).to_upper()
			for k in REEL.size():
				if SimConsts.Anim.keys()[REEL[k]] == wanted:
					_reel = k
			if wanted == "ALL":
				_reel = 0
				_rolling = true
		elif args[i] == "--hair" and i + 1 < args.size():
			_hair = int(args[i + 1])
		elif args[i] == "--nose" and i + 1 < args.size():
			_nose = int(args[i + 1])
		elif args[i] == "--tache" and i + 1 < args.size():
			_tache = int(args[i + 1])
		elif args[i] == "--beard" and i + 1 < args.size():
			_beard = int(args[i + 1])
		elif args[i] == "--chin" and i + 1 < args.size():
			_chin = float(args[i + 1])
		elif args[i] == "--brow" and i + 1 < args.size():
			_brow = float(args[i + 1])
		elif args[i] == "--man" and i + 1 < args.size():
			_man = int(args[i + 1])
		elif args[i] == "--plain":
			_plain = true
		elif args[i] == "--shot" and i + 1 < args.size():
			_shot_path = args[i + 1]
	# The window is fullscreen by project setting, which is not the frame
	# `--resolution` asked for. A screenshot has to put itself back in a window.
	SimMatchView3D._apply_render_size(get_window())
	var windowed := SimMatchView3D._requested_size("--windowed")
	if _shot_path != "" or windowed != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if windowed != Vector2i.ZERO:
			DisplayServer.window_set_size(windowed)
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
	# Sun plus ambient just over one. This view is where colour is judged, so it
	# has to be lit honestly: at 1.4 the pale end of the skin ladder clipped to
	# white and every fair man looked like a ghost.
	# Down from 0.5, with the fill light below taking up the slack. This view is
	# where colour is judged and it has to stay honest: the total is about what
	# it was, but a third of it now comes from a direction.
	env.ambient_light_energy = 0.26
	SimCharacterBuilder.add_crease_shading(env)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	# A rank of four at arm's length: the shadow never has to reach past the back
	# of the floor, and a tight range is what keeps the crosshatch off them.
	SimCharacterBuilder.soften_shadow(sun, 14.0)
	add_child(sun)
	SimCharacterBuilder.add_fill_light(self, -30.0)

	# The floor of a product photograph, not a pitch. The background above it was
	# already paper for the reason in the comment there -- a green field competes
	# with the kit being judged -- and a green floor under a paper sky was the
	# other half of that argument left unfinished. A shade under the background so
	# the figure has something to stand on and the contact shadow has somewhere to
	# land: on paper exactly the colour of the sky a man floats.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 24.0)
	plane.orientation = PlaneMesh.FACE_Y
	ground.mesh = plane
	ground.material_override = SimCharacterBuilder.flat_material(
		SimPalette.PAPER.darkened(0.06))
	add_child(ground)

	_camera = Camera3D.new()
	_camera.fov = FOV
	add_child(_camera)

	var made := SimMatchView3D._overlay_layer(1)
	add_child(made[0])
	_caption = Label.new()
	_caption.position = Vector2(24.0, 18.0)
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.add_theme_color_override("font_color", SimPalette.INK)
	_caption.add_theme_color_override("font_outline_color", SimPalette.CHALK)
	_caption.add_theme_constant_override("outline_size", 6)
	made[1].add_child(_caption)
	_record_label = Label.new()
	_record_label.anchor_top = 1.0
	_record_label.anchor_bottom = 1.0
	_record_label.offset_left = 24.0
	_record_label.offset_bottom = -18.0
	_record_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_record_label.add_theme_font_size_override("font_size", 20)
	_record_label.add_theme_color_override("font_color", SimPalette.INK)
	_record_label.add_theme_color_override("font_outline_color", SimPalette.CHALK)
	_record_label.add_theme_constant_override("outline_size", 6)
	made[1].add_child(_record_label)


## The squad a seed produces, read off a match rather than invented here, so the
## rank is the eleven the view and the batch runner would show for that seed.
func _load_squad() -> void:
	if _world >= 0:
		_load_world_squad()
		return
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


## A generated club's squad. `--club N` takes the Nth club of a league at that
## seed so every club in a division can be looked at; without it one club is
## drawn on its own at `--rep`.
func _load_world_squad() -> void:
	var rng := SimRng.new(_world)
	var club: WorldClub
	if _club > 0:
		var league := WorldGen.league(rng, maxi(_club + 1, WorldSeason.DEFAULT_CLUBS), _rep)
		club = league[mini(_club, league.size() - 1)]
	else:
		club = WorldGen.club(rng, 0, _rep)
	_pool = []
	_records = []
	for i in club.squad.size():
		var record: WorldPlayer = club.squad[i]
		_pool.append(record.to_sim_player(i, 0))
		_records.append(record)
	_kits = [SimAppearance.kit_for(club.kit[0]), club.away_kit]
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
		if _man > 0 and _man <= _pool.size():
			p = _pool[_man - 1]
		var appearance := SimCharacterModel.appearance_for(p.appearance_seed)
		var styles := SimCharacterBuilder.HAIR_LIBRARY.size()
		if _hair >= 0:
			appearance.hair_style = (_hair + i) % styles
		var noses := SimCharacterBuilder.NOSE_LIBRARY.size()
		if _nose >= 0:
			appearance.nose_style = (_nose + i) % noses
		if _tache >= 0:
			appearance.moustache_style = (_tache + i) % 3
		elif _tache == -2:
			appearance.moustache_style = -1
		if _beard >= 0:
			appearance.beard_style = (_beard + i) % 3
		elif _beard == -2:
			appearance.beard_style = -1
		if _chin >= 0.0:
			appearance.chin = clampf(_chin + 0.25 * float(i), 0.0, 1.0)
		if _brow >= 0.0:
			appearance.brow = clampf(_brow + 0.25 * float(i), 0.0, 1.0)
		if _plain:
			appearance.accessory = "none"
		var at := Vector3((float(i) - float(count - 1) * 0.5) * SPACING, 0.0, 0.0)
		var node := SimCharacterModel.build(p.appearance_seed, appearance, _kits[p.team], p.shirt)
		node.position = at
		node.rotation.y = deg_to_rad(_turn)
		add_child(node)
		_nodes.append(node)
		_stand(node)
		SimCharacterModel.set_expression(node, _face)

		var label := Label3D.new()
		# The seed is on the caption because it is the handle for feedback: it is
		# what puts this exact man back on screen tomorrow.
		label.text = "#%d  %s\n%.2f m\nseed %d" % [
			p.shirt, p.player_name, appearance.height, p.appearance_seed,
		]
		# A world man is captioned along the bottom of the overlay instead: a
		# rank framed for a tall man clips a label under his feet.
		label.visible = _world < 0
		if _hair >= 0:
			var cut: Dictionary = SimCharacterBuilder.HAIR_LIBRARY[appearance.hair_style]
			label.text += "\nhair %d: %s" % [appearance.hair_style, cut.get("name", "")]
		if _nose >= 0:
			label.text += "\nnose %d of %d" % [appearance.nose_style, noses]
		if _tache >= 0 or _beard >= 0:
			label.text += "\ntache %d  beard %d" % [appearance.moustache_style, appearance.beard_style]
		if _chin >= 0.0:
			label.text += "\nchin %.2f" % appearance.chin
		if _brow >= 0.0:
			label.text += "\nbrow %.2f" % appearance.brow
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
	d /= clampf(_zoom, 0.2, 4.0)
	# Zooming in looks at the heads, not the boots: the aim climbs as the frame
	# shrinks, up to the eye line.
	var aim_y: float = lerpf(1.05, 1.55, clampf(1.0 - 1.0 / maxf(_zoom, 0.01), 0.0, 1.0))
	var centre := Vector3(0.0, aim_y, 0.0)
	var elevation := deg_to_rad(_elevation)
	_camera.position = centre + Vector3(0.0, d * sin(elevation), d * cos(elevation))
	_camera.look_at(centre, Vector3.UP)


## One line per man on screen: the facts the seed carries, so a face that
## contradicts its record is caught against the line under the header.
func _record_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var first := _page * PER_PAGE
	for i in mini(PER_PAGE, _pool.size() - first):
		var index := first + i
		if _man > 0 and _man <= _pool.size():
			index = _man - 1
		var r: WorldPlayer = _records[index]
		var seed_value := r.appearance_seed
		var line := "#%-2d %-22s %-4s %2d  %s   %.2f m %-8s %-8s %s hair   %s   seed %d" % [
			r.shirt, r.full_name(), SimRole.name_of(r.role), r.age, r.nation_code, r.height,
			WorldLook.type_name(WorldLook.body_type_of(seed_value)),
			WorldLook.COMPLEXION_NAMES[WorldLook.complexion_of(seed_value)],
			WorldLook.HAIR_NAMES[WorldLook.hair_family_of(seed_value)],
			WorldLook.AGE_NAMES[WorldLook.age_band_of(seed_value)], seed_value,
		]
		if r.archetype != WorldNickname.NONE:
			line += "   %s \"%s\"" % [r.archetype, r.epithet]
		if _hair >= 0:
			var style: int = (_hair + i) % SimCharacterBuilder.HAIR_LIBRARY.size()
			line += "   HAIR %d: %s" % [style, SimCharacterBuilder.HAIR_LIBRARY[style].get("name", "")]
		lines.append(line)
	return lines


func _write_caption() -> void:
	var first := _page * PER_PAGE + 1
	var last: int = mini(_page * PER_PAGE + PER_PAGE, _pool.size())
	var head := "PARADE   match seed %d" % _seed
	if _world >= 0:
		head = "PARADE   world seed %d   club %d" % [_world, _club]
	_caption.text = "\n".join([
		"%s   men %d-%d of %d   page %d/%d" % [
			head, first, last, _pool.size(), _page + 1, _pages(),
		],
		"%s   elevation %.0f   zoom %.2f   %s" % [
			"turning" if _spin else "still", _elevation, _zoom,
			"standing" if _reel < 0 else "%s%s" % [
				SimConsts.Anim.keys()[REEL[_reel]], "  (rolling)" if _rolling else "",
			],
		],
		"< >  page    N / P  seed    SPACE  turn    E  elevation    + -  zoom    1-5  face    [ ]  anim    A  roll    Q  quit",
	])
	if _world >= 0:
		_record_label.text = "\n".join(_record_lines())
		_record_label.offset_top = -18.0 - _record_label.get_minimum_size().y


# --- Frame ------------------------------------------------------------------


func _process(delta: float) -> void:
	_elapsed += delta
	if _reel >= 0:
		_anim_clock += delta
		if _rolling and _anim_clock >= REEL_DWELL:
			_anim_clock = 0.0
			_reel = (_reel + 1) % REEL.size()
			_write_caption()
	for i in _nodes.size():
		var node: Node3D = _nodes[i]
		if _spin:
			node.rotation.y += deg_to_rad(SPIN_RATE) * delta
		if _reel >= 0:
			_play(node, i, delta)
			continue
		# A figure that does not move at all reads as a shop dummy, so it breathes.
		var spine := node.find_child("Spine", true, false) as Node3D
		if spine != null and node.has_meta("spine_y"):
			var base: float = node.get_meta("spine_y")
			spine.position.y = base + sin(_elapsed * BREATH_RATE + float(i)) * BREATH_DEPTH
	_maybe_shoot()


## One figure, one frame of whatever the reel is on.
##
## The gait runs underneath every state, exactly as it does in a match: a kick
## is a leg swung out of a run, not a pose struck from standing. Each man is
## started a little way round the cycle so a rank of four is not a chorus line.
func _play(node: Node3D, index: int, delta: float) -> void:
	var anim: int = REEL[_reel]
	var speed: float = float(SimMatchView3D.POSE_SHEET_SPEEDS.get(anim, 0.0))
	var amplitude := SimMatchView3D.gait_amplitude(speed)
	var phase: float = node.get_meta("reel_phase", fmod(float(index) * 1.29, TAU))
	var leg := SimMatchView3D._leg_length(node)
	var step := 2.0 * leg * sin(amplitude)
	if step > 0.01:
		var hz: float = minf(speed / (2.0 * step), REEL_MAX_HZ)
		phase = fposmod(phase + TAU * hz * delta, TAU)
	node.set_meta("reel_phase", phase)

	# The turntable owns the yaw; a fall or a dive owns the rest, so the rest
	# is put back every frame the way the match does.
	var yaw: float = node.rotation.y
	node.rotation = Vector3(0.0, yaw, 0.0)
	node.position.y = 0.0
	# A turn is the gait banked into it; a shuffle is the gait across the hips.
	var turn: float = 1.0 if anim == SimConsts.Anim.TURN else 0.0
	var across: float = 1.0 if anim == SimConsts.Anim.SHUFFLE else 0.0
	SimMatchView3D.pose_gait(node, speed, phase, turn, across)
	var span: float = float(SimMatchView3D.ANIM_SECONDS.get(anim, REEL_DWELL))
	var t: float = fposmod(_anim_clock + float(index) * 0.21, maxf(span, 0.001))
	# A dive rolls to the man's own right, whichever way the turntable has him.
	SimMatchView3D.pose_state(node, anim, t / maxf(span, 0.001), _anim_clock, yaw, 1.0)


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
			# N and P walk whichever seed the rank came from.
			if _world >= 0:
				_world += 1
			else:
				_seed += 1
			_page = 0
			_load_squad()
			_build_row()
		KEY_P:
			if _world >= 0:
				_world = maxi(_world - 1, 0)
			else:
				_seed = maxi(_seed - 1, 1)
			_page = 0
			_load_squad()
			_build_row()
		KEY_SPACE:
			_spin = not _spin
			_write_caption()
		KEY_E:
			# The next stop above the current elevation, wrapping to level.
			var next: float = ELEVATION_STOPS[0]
			for stop in ELEVATION_STOPS:
				if float(stop) > _elevation + 0.5:
					next = float(stop)
					break
			_elevation = next
			_frame_row(_nodes.size())
			_write_caption()
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			_zoom = minf(_zoom * 1.25, 4.0)
			_frame_row(_nodes.size())
			_write_caption()
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom = maxf(_zoom / 1.25, 0.2)
			_frame_row(_nodes.size())
			_write_caption()
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			# Stepping off the stand pose starts at the top of the reel rather
			# than wherever it was, so `]` from standing is always the gait.
			if _reel < 0:
				_reel = 0
			else:
				_reel = posmod(_reel + (1 if key == KEY_BRACKETRIGHT else -1), REEL.size())
			_rolling = false
			_anim_clock = 0.0
			_write_caption()
		KEY_0:
			_reel = -1
			for node in _nodes:
				_stand(node)
			_write_caption()
		KEY_A:
			if _reel < 0:
				_reel = 0
			_rolling = not _rolling
			_anim_clock = 0.0
			_write_caption()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_face = key - KEY_1
			for node in _nodes:
				SimCharacterModel.set_expression(node, _face)
		KEY_Q, KEY_ESCAPE:
			get_tree().quit()
