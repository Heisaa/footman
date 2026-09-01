class_name SimMatchView3D
extends Node3D
## The watchable match view (PLAN.md §9).
##
## Reads snapshots and draws them. It never writes to the simulation, never
## consumes from its generator, and could be deleted without the sim noticing.
##
## The look is a toy football set, not a broadcast: flat colour, a single soft
## light, a low field of view from a fixed high angle.
##
## Animation used to be quantised to ten frames a second for a stop-motion
## register (`PLAN.md` §10, Phase 6). The owner asked for smooth motion instead,
## so the pose layer now runs continuously, at the display's frame rate, and
## `--step-fps 10` puts the stepping back for a side-by-side look. Everything the
## pose layer measures over time — the gait's cadence, the turn rate — is stated
## in seconds rather than in stepped frames, so one set of code drives both.

## Three cameras, and they pan (§9.2).
##
## An earlier version had twenty-one authored positions — seven along the pitch
## by three across it — and cut to whichever was nearest the ball. It cut far too
## often: a ball played twenty metres sideways changed the shot, and the viewer
## spent the match re-finding play instead of watching it. Cutting is the most
## violent thing a camera can do and it was being spent on nothing.
##
## What replaces it is the rig a television match is actually shot on. Three
## fixed positions, all on the *same* touchline — reversing the side would
## reverse the direction of play, which is the one thing a football viewer cannot
## be asked to re-learn mid-match — and each of them pans and tilts to hold the
## ball. The one on the halfway line takes almost the whole match; the two level
## with the penalty areas take over when play arrives there, where the halfway
## camera's angle into the box has gone too oblique to read.
##
## Motion inside a shot is free, and it is what the eye follows. Cuts are then
## rare enough to mean something.

## Where each camera stands, stated as an angle and a distance from the point it
## is aimed at when that point is on the halfway line.
##
## Elevation is what makes this a toy set rather than a broadcast: shallower than
## about twenty-five degrees and the pitch foreshortens to nothing, so positions
## stop reading as positions. It is now the elevation *at the middle* of the
## pitch rather than a fixed one, because a panning camera has a different angle
## on every point it can look at — thirty-five here swings from about
## twenty-five degrees on the far touchline to fifty-five on the near one, which
## is the widest band that still reads as one stadium.
const CAMERA_ELEVATION_DEG := 35.0
const CAMERA_RANGE := 80.0
## How far along the pitch the two penalty-area cameras stand. The box edge is at
## 36, so this is level with the spot and looking slightly in at the goal.
const CAMERA_SIDE_X := 40.0

## Frame width decides how big a player is on screen, and a player who is forty
## pixels tall has no body language: the expressions, the arm swing and the
## squash of a kick are all below the resolution of the shot, and the whole
## character system may as well not exist. Fifty metres across the frame put a
## player at roughly sixty pixels in 720p, which is enough to read a face, while
## still holding the ball carrier and the players around him. Fifty-eight is the
## owner's call after the world clubs went on: a bit more of the shape of play
## around the carrier, and a face still reads.
##
## Holding it fixed is what makes the lens a zoom. A camera bolted to one spot is
## three times further from the far touchline than from the near one, so at a
## fixed field of view a player's size on screen would swing by that factor as
## play crossed the pitch. `_apply_camera` solves the field of view for this
## width at whatever the range to the ball currently is, which is what a camera
## operator does with the zoom rocker and for the same reason.
const CAMERA_FRAME_WIDTH := 58.0
const CAMERA_FOV_MIN := 8.0
const CAMERA_FOV_MAX := 50.0

## When play is this far up the pitch, the penalty-area camera has the better
## angle. The hysteresis is deliberately large: coming back to the halfway camera
## needs the ball eight metres inside the line that sent us away, so a ball
## cleared to the edge of the box and headed back does not cost two cuts.
##
## Thirty is a good way short of the box, which is deliberate — waiting for the
## ball to reach the edge of it meant the cut landed after the attack had already
## arrived, and the box camera kept showing up late to its own shot.
const CAMERA_SWITCH_X := 30.0
const CAMERA_SWITCH_HYSTERESIS := 8.0
## Three timers, all in *simulated* seconds so the same match is shot the same
## way at 1x and at 8x: a wall-clock pan would trail hopelessly behind a
## fast-forwarded ball, and wall-clock delays would silently cut less often the
## faster you watched.
##
## The minimum is a floor on how long a shot lasts, and it is a backstop rather
## than the mechanism — with the commitment doing the real work it hardly ever
## binds. Kept short so play that sweeps end to end can be followed up the pitch,
## halfway camera and all, instead of the halfway shot being skipped because it
## would have been too brief to allow.
##
## The commitment is the useful one: play has to stay in the new camera's
## territory for this long before the cut is taken, so a ball that arrives in the
## final third and is cleared straight back out is covered by the pan and costs
## no cut at all. Without it the camera sat out its minimum and then cut
## immediately, which is the same twitchiness one step slower.
##
## A second of it was too much to sit through, though: an attack develops fast
## enough that the cut has to be part of it rather than a reaction to it. What is
## left is long enough to swallow a ball passing through, short enough that the
## box camera is live before the cross comes in.
const CAMERA_MIN_SHOT := 3.0
const CAMERA_COMMIT := 1.0
const CAMERA_PAN_TAU := 0.35

## The ball is drawn larger than it is simulated, and only drawn.
##
## A regulation ball is 22 cm across, which in a 42-metre frame is about seven
## pixels: too small to read as a ball, too small to show which way it is
## turning, and too small to follow when it is moving quickly. The sim keeps the
## real radius, because that number is in the contact and interception geometry
## everywhere; the view inflates the sphere it draws so the object the whole
## match is about is actually visible.
##
## At 2.0 the ball is 44 cm across and about a fifth of a player's height, which
## is nowhere near life size and is the point: this is a toy football set, and a
## toy set's ball is the size the hand that plays with it needs, not the size the
## rules say.
##
## It was 2.4, and came down because of what an inflated ball does to how fast
## the match reads. Speed is judged against the size of the thing moving, so a
## ball drawn 2.4 times too big crosses its own diameter in 2.4 times the time
## and the whole match looks like slow motion — whatever the physics underneath
## is doing. There is a floor: below about 1.8 the ball stops reading as a ball
## in a wide frame and you lose which way it is spinning.
const BALL_VISUAL_SCALE := 2.0
const BALL_DRAW_RADIUS := SimConsts.BALL_RADIUS * BALL_VISUAL_SCALE

## Spacing of the ground mesh's vertices, metres. The shortest wavelength in the
## surface is about three metres, so a metre resolves it; the whole pitch at this
## step is under twenty thousand triangles, built once.
const TURF_MESH_STEP := 1.0


## The defaults below are the compressed match, because this scene exists to be
## watched and a ninety-minute one is not. The sim, the headless runner and
## every batch now default to the same clock (DECISIONS.md, sixth amendment),
## so the view and the instruments describe one match. `--clock-rate 1
## --pitch-scale 1` puts this back to real time.
@export var match_seed := 1
## A world seed puts two generated clubs on the pitch instead of `SimSquadGen`
## squads: `world_match.tscn` sets it, `--world N` on the command line does too.
## `home_club` and `away_club` are their places in the league at that seed.
@export var world_seed := -1
@export var home_club := 0
@export var away_club := 1
@export var minutes := 90.0
## Match-clock seconds per simulated second. At 10 a full ninety is played out
## in nine minutes of football, with the scoreboard still reading 0-90.
@export var clock_rate := 10.0
## Six a side on a reduced pitch. Everything geometric in the world is built
## from `_pitch`, so this changes the markings, the goals and the stands with it.
@export var small_sided := false
## Shrinks the pitch while keeping eleven a side. Regulation by the owner's
## call after looking at a shrunk one. The knob stays because the compressed
## match still needs the football per second from somewhere, and a smaller pitch
## was one of the two places it could come from; the other is chance quality,
## which is where the work goes instead.
@export var pitch_scale := 1.0

## The squad quality each match in a session is played at, home then away, walked
## one step by N. Three matches: two even sides at 0.6, two even sides at 1.0,
## then a mismatch. Watching them back to back is the only way to see whether
## quality reads on the grass — whether the good side keeps it better, and
## whether the mismatch looks like one. The list wraps, so a fourth N is the
## first match again on a new seed.
##
## Overridden for the whole session by `--home` and `--away`, which pin one pair
## and turn the walk off.
const QUALITY_LADDER := [Vector2(0.6, 0.6), Vector2(1.0, 1.0), Vector2(1.0, 0.6)]
## Which rung this match is on. Advanced by N, kept by R: R is this match again,
## and the same seed at a different quality is a different match.
var _quality_step := 0
## The pair pinned by `--home`/`--away`, or a negative x if the ladder is live.
var _quality_pinned := Vector2(-1.0, -1.0)

var _match: SimMatch
## The pitch's surface. Held separately from the match because the world — the
## ground mesh above all — is built before the match is started, and it is the
## same object either way.
var _env: SimEnv
## The dimensions the world is built to. Held for the same reason as `_env`: the
## markings are painted, the goals planted and the stands seated before there is
## a match to ask, so both come from `SimRunner` rather than from `_match`.
var _pitch: SimPitch = SimPitch.regulation()
var _prev := SimSnapshot.new()
var _curr := SimSnapshot.new()
var _accumulator := 0.0
## The set situation being watched, and the tick it is played out to. A scenario
## repeats on the next seed rather than running on into an ordinary match: the
## point of watching one is seeing the same moment many times, and five seconds
## of football followed by eighty-nine minutes of something else is not that.
var _scenario: SimScenario = null
## The tour: `--scenario all` starts at the first scenario and repeats it on a
## new seed each play-out, like the single-scenario watch; N steps to the next
## scenario in table order, wrapping, and R replays the same seed.
var _scenario_cycle := false
var _scenario_index := 0
var _scenario_end_tick := -1
## The tick the hold after the situation resolved runs to, once it has. Held
## separately so the resolution is only noticed once: `live` goes false the
## instant the keeper has it and stays false while the hold plays out.
var _scenario_hold_end := -1
## Whether the ball has been in play yet, for `SimScenario.live`. A set piece
## starts dead and the watch would end on its first frame without it.
var _scenario_started := false
var _speed_given := false
## What a scenario runs at when nobody said. Real time: the situations start
## twenty-five to thirty metres out and the running is part of what is being
## judged, so half speed -- which was right when the striker started on the edge
## of the box and it was over in a second -- is now eight wall seconds of a man
## jogging before anything happens (owner, 2026-08-23).
const SCENARIO_SPEED := 1.0
## Seconds the ball is left alone after the situation's own clock runs out, so
## the shot arrives, the keeper saves it and the eye sees how it ended.
const SCENARIO_HOLD := 2.5
var _speed := 1.0
var _paused := false
var _players: Array[Node3D] = []
## The two kit palettes actually worn, home first. Derived here rather than taken
## from the team, because the away colour is chosen against the home one so the
## two sides can be told apart, and the scoreboard has to name the sides in the
## colours the viewer can see on the grass.
var _kits: Array = []
var _ball: Node3D
## The ball's orientation, carried as a quaternion because it is integrated a
## frame at a time and a basis multiplied by itself for ninety minutes stops
## being a rotation.
var _ball_roll := Quaternion.IDENTITY
var _camera: Camera3D
## Which of the three cameras is live: 0 and 2 are the penalty-area pair, 1 the
## halfway line, which is where a match starts and where it mostly stays.
var _camera_shot := 1
## The point on the grass the live camera is pointed at, chased toward the ball
## rather than snapped to it. This is the pan and the tilt: the camera body never
## moves, only what it is looking at.
var _camera_aim := Vector3.ZERO
## Simulated seconds the live camera has held the shot, against CAMERA_MIN_SHOT.
var _camera_held := 0.0
## The camera play has been asking for, and for how long, against CAMERA_COMMIT.
var _camera_wanted := 1
var _camera_wanted_for := 0.0
## The tick the last frame was drawn at, which is what the camerawork is stepped
## by. Not the same as the tick the match has reached: the picture can be
## standing still, stepping a tick at a time, or somewhere in the recording.
var _drawn_tick := 0
## The most simulated time one frame of camerawork is worth. A fast-forward
## covers minutes a frame, and a pan given minutes is a cut with extra steps.
const CAMERA_DT_MAX := 1.0
var _crowd: MultiMeshInstance3D
## The grass, the paint and the goals. Everything else in the stadium stands
## still between matches; these are cut from the seed's own surface, so they are
## held together and rebuilt at every kick-off.
var _ground: Node3D
## Whether full time has been reached and said so. The match stops ticking of its
## own accord; this is only what the board is told.
var _full_time := false
## The clock and the scoreline, over the top of everything (PLAN.md §9.6).
var _scoreboard: MatchScoreboard
var _elapsed := 0.0
var _frame_width := CAMERA_FRAME_WIDTH
var _elevation_deg := CAMERA_ELEVATION_DEG
var _range := CAMERA_RANGE
var _pose_sheet := false
## Where in each one-shot arc the pose sheet freezes, 0 to 1.
var _pose_u := 0.55
## Frames a second the pose layer is quantised to; zero, the default, leaves it
## continuous. Set with `-- --step-fps 10` for the old stop-motion look.
var _step_fps := 0.0
## How far this frame sits between the two most recent snapshots. Held on the
## instance because every pose that reads a per-player quantity wants it, and
## threading it through eleven pose functions would say nothing.
var _alpha := 1.0


## Seconds to run before saving a screenshot and quitting. Set with
## `-- --shot 20 --shot-path /tmp/frame.png`, so the look can be checked from a
## virtual display without anyone having to sit and watch it.
var _shot_after := -1.0
var _shot_path := "user://frame.png"


## Everything below is the debug overlay, off unless `--debug` was passed. It
## costs nothing when it is off: the sink in the sim is one boolean test per
## decision and neither node is built.
var _debug := false
## Whether the command line asked for a clock rate. A minute of football a second
## is the view's default and is unreadable, so `--debug` drops it to real time
## unless the owner said otherwise.
var _clock_rate_given := false
var _overlay: MatchDebugOverlay
var _debug_world: MatchDebugWorld
## Annotation layers asked for on the command line, as the digits that key them.
var _layer_arg := ""

## Half a minute of snapshots, for the trails layer and for stepping back through
## what just happened. Display only, and it has to be: the sim runs forward from
## a seed and cannot be rewound, so this is a recording of what was drawn.
##
## A sample every three ticks, which is a twentieth of a second — fine enough
## that a touch is several samples, coarse enough that half a minute of football
## is six hundred of them.
const HISTORY_EVERY := 3
const HISTORY_MAX := 600
## Samples the trail layer draws, counting back from the moment on screen. The
## whole buffer is thirty seconds and would be spaghetti; ten is a move.
const TRAIL_SAMPLES := 200
## Samples one press of `,` or `.` moves, and how far the shifted keys jump.
## Half a second is roughly a pass, which is the unit of "back a bit".
const STEP_SAMPLES := 1
const STEP_BIG_SAMPLES := 10
## The keys that scrub, which are the only ones a held press repeats on.
const STEP_KEYS := [KEY_COMMA, KEY_PERIOD, KEY_LESS, KEY_GREATER]
var _history: Array[SimSnapshot] = []
## What the panels and the annotation layers said at each of those samples,
## captured alongside. Same length as `_history` and the same indices.
var _frames: Array[MatchDebugFrame] = []
var _live_frame := MatchDebugFrame.new()
var _history_countdown := 0
## How many samples back the display is sitting, and the live pair to put back
## when it returns to now.
var _scrub := 0
var _scrubbing := false
var _live_prev := SimSnapshot.new()
var _live_curr := SimSnapshot.new()
var _bookmark_pending := false
## Seconds to run before marking the moment without anyone pressing `M`. For
## checking the file the key writes, and for marking a moment from a script.
var _bookmark_after := -1.0

## Watching a marked moment again. The tick that was marked, the tick the seek is
## running to, and the tick it stopped at once it got there.
var _mark_tick := -1
var _seek_target := -1
var _marked_at := -1
## Whether the seek in progress is a rewind — the same match rebuilt to play on
## from a moment already watched — rather than a run-up to a mark. The two end
## differently: a mark is walked into at quarter speed, a rewind carries on at
## whatever speed the owner was watching at.
var _seek_is_rewind := false
## The pinned player, held across a rewind. The overlay drops the pin whenever it
## is handed a new context, which is right for a new match and wrong for the same
## match rebuilt: it is the same eleven, and the man being watched is the reason
## the moment was worth going back to.
var _pin_held := -1
## How much of the run-up to the marked moment is played rather than skipped.
const MARK_PRELUDE := SimConsts.TICK_HZ * 5
## Milliseconds a frame may spend fast-forwarding. The seek runs across frames so
## the window stays alive and can say how far it has got: a mark late in a match
## is a hundred thousand ticks away, and the sim has no way to jump to one.
const SEEK_BUDGET_MS := 12

## Slow motion is worth more than any panel here: most of what looks wrong is two
## seconds long at 1x. Stepped through with `[` and `]`.
const SPEED_LADDER := [0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
var _speed_step := 3


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			_shot_after = float(args[i + 1])
		elif args[i] == "--shot-path" and i + 1 < args.size():
			_shot_path = args[i + 1]
		elif args[i] == "--seed" and i + 1 < args.size():
			match_seed = int(args[i + 1])
		elif args[i] == "--world" and i + 1 < args.size():
			world_seed = int(args[i + 1])
		elif args[i] == "--home-club" and i + 1 < args.size():
			home_club = int(args[i + 1])
		elif args[i] == "--away-club" and i + 1 < args.size():
			away_club = int(args[i + 1])
		elif args[i] == "--speed" and i + 1 < args.size():
			_speed = float(args[i + 1])
			_speed_given = true
		# Framing overrides, so the three numbers that decide the composition can
		# be compared from screenshots without an edit-and-rerun cycle.
		elif args[i] == "--frame-width" and i + 1 < args.size():
			_frame_width = float(args[i + 1])
		elif args[i] == "--elevation" and i + 1 < args.size():
			_elevation_deg = float(args[i + 1])
		elif args[i] == "--range" and i + 1 < args.size():
			_range = float(args[i + 1])
		elif args[i] == "--poses":
			_pose_sheet = true
		elif args[i] == "--pose-u" and i + 1 < args.size():
			_pose_u = float(args[i + 1])
		elif args[i] == "--step-fps" and i + 1 < args.size():
			_step_fps = float(args[i + 1])
		elif args[i] == "--clock-rate" and i + 1 < args.size():
			clock_rate = float(args[i + 1])
			_clock_rate_given = true
		# Either one pins both: a session watching one mismatch wants that
		# mismatch on every N, not the ladder walking away from it.
		elif args[i] == "--home" and i + 1 < args.size():
			_pin_quality(float(args[i + 1]), -1.0)
		elif args[i] == "--away" and i + 1 < args.size():
			_pin_quality(-1.0, float(args[i + 1]))
		elif args[i] == "--debug":
			_debug = true
		# The annotation layers are keyed, and a screenshot cannot press a key.
		# `--layers 1,3,4` turns them on from the command line instead, which is
		# how one gets into a report.
		elif args[i] == "--layers" and i + 1 < args.size():
			_debug = true
			_layer_arg = args[i + 1]
		elif args[i] == "--bookmark" and i + 1 < args.size():
			_debug = true
			_bookmark_after = float(args[i + 1])
		elif args[i] == "--from-bookmark" and i + 1 < args.size():
			_load_bookmark(args[i + 1])
		# A set situation instead of a match. The same `SimScenario` the table in
		# `./run.sh scenario` counts, so what is on screen and what is in the
		# row are the identical starting position -- which is the only reason
		# the eye and the numbers can usefully disagree.
		elif args[i] == "--scenario" and i + 1 < args.size():
			if args[i + 1] == "all":
				_scenario_cycle = true
				_scenario = SimScenarios.all()[0]
			else:
				_scenario = SimScenarios.by_name(args[i + 1])
				if _scenario == null:
					push_error("no scenario named '%s'; known: all, %s" % [
						args[i + 1], ", ".join(SimScenarios.names())])
		elif args[i] == "--small":
			small_sided = true
		elif args[i] == "--pitch-scale" and i + 1 < args.size():
			pitch_scale = float(args[i + 1])
	# The game runs full screen, which `display/window/size/mode` in project.godot
	# asks for at window creation. That setting beats the engine's own
	# `--windowed` flag, so the two screenshot paths cannot ask for a window on
	# the command line and have to put themselves back into one here: a
	# fullscreen window is the display's size, and a different aspect ratio is a
	# different shot from the one `--resolution` asked for.
	# `--windowed WxH` does the same for a live look at another resolution --
	# where the compositor lets a window pick its size. A tiling one does not,
	# so `--render WxH` is the one that always works: the whole frame is drawn
	# at that many pixels and stretched to whatever the window is.
	_apply_render_size(get_window())
	var windowed := _requested_size("--windowed")
	if _shot_after > 0.0 or _pose_sheet or windowed != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var wanted := _requested_resolution() if windowed == Vector2i.ZERO else windowed
		if wanted != Vector2i.ZERO:
			DisplayServer.window_set_size(wanted)
	if _pose_sheet:
		_build_pose_sheet()
		return
	# A minute of football a second is the compressed clock, and nothing on the
	# overlay can be read at that rate. Debug is real time unless told otherwise.
	if _debug and not _clock_rate_given:
		clock_rate = 1.0
	if _scenario != null and not _speed_given:
		_speed = SCENARIO_SPEED
	# `--speed` sets a rate the ladder has to start from, or the first press of
	# `[` jumps somewhere unrelated to what is on screen.
	for i in SPEED_LADDER.size():
		if absf(SPEED_LADDER[i] - _speed) < absf(SPEED_LADDER[_speed_step] - _speed):
			_speed_step = i
	# The world is built to these dimensions and the match is then played on the
	# pitch the same options produce, so the two cannot drift apart.
	_pitch = SimRunner.pitch_for(_match_options(match_seed))
	_build_world()
	_start_match(match_seed)
	if _debug:
		_build_debug()
	if _mark_tick >= 0:
		_seek_target = maxi(_mark_tick - MARK_PRELUDE, 0)


## The `--resolution WxH` the process was launched with, or zero if there was
## none. Godot applies it when it creates the window; it has to be applied again
## by hand, because that window is created full screen and the requested size
## only means anything once it is a window again.
func _requested_resolution() -> Vector2i:
	return _requested_size("--resolution")


static func _apply_render_size(window: Window) -> void:
	var size := _requested_size("--render")
	if size == Vector2i.ZERO:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = size


## A layer for the overlay, and the node to put it under. Under `--render` the
## overlay, laid out for 1080 rows, shrinks as a display that size would draw
## it. Done on the layer, not with `content_scale_factor`, which in viewport
## mode divides the render size and undoes the point.
static func _overlay_layer(layer_index: int) -> Array:
	var size := _requested_size("--render")
	var layer := CanvasLayer.new()
	layer.layer = layer_index
	if size == Vector2i.ZERO:
		return [layer, layer]
	# Shrunk by the layer, and anchored against a control the design's size:
	# anchored to the viewport, a scoreboard centres on a 640-wide frame and is
	# then scaled towards the corner.
	var scale := float(size.y) / 1080.0
	layer.scale = Vector2.ONE * scale
	var root := Control.new()
	root.size = Vector2(size) / scale
	layer.add_child(root)
	return [layer, root]


static func _requested_size(flag: String) -> Vector2i:
	# `--resolution` is an engine flag and comes before the `--`; the game's own
	# flags come after it, and the two are different lists.
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] != flag or i + 1 >= args.size():
			continue
		var parts := args[i + 1].split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


## The one description of the match this view is showing. Both the world build
## and the match itself go through it, so the pitch painted on the ground is the
## pitch the ball is played on.
func _match_options(seed_value: int) -> SimRunner.Options:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.world_seed = world_seed
	opts.home_club = home_club
	opts.away_club = away_club
	opts.minutes = minutes
	opts.clock_rate = clock_rate
	opts.small_sided = small_sided
	opts.pitch_scale = pitch_scale
	var quality := _quality()
	opts.home_quality = quality.x
	opts.away_quality = quality.y
	opts.scenario = _scenario
	return opts


## This match's squad quality, home then away.
func _quality() -> Vector2:
	if _quality_pinned.x >= 0.0:
		return _quality_pinned
	return QUALITY_LADDER[_quality_step % QUALITY_LADDER.size()]


## Pins one pair for the session. A negative side is the one that was not given
## on the command line, and keeps whatever the first rung has for it.
func _pin_quality(home: float, away: float) -> void:
	var current: Vector2 = _quality_pinned if _quality_pinned.x >= 0.0 else QUALITY_LADDER[0]
	_quality_pinned = Vector2(
		home if home >= 0.0 else current.x,
		away if away >= 0.0 else current.y,
	)


func _quality_text() -> String:
	var quality := _quality()
	return "quality %.2f v %.2f" % [quality.x, quality.y]


## What N is about to play, for the full-time board.
func _next_quality_text() -> String:
	if _quality_pinned.x >= 0.0:
		return ""
	var next: Vector2 = QUALITY_LADDER[(_quality_step + 1) % QUALITY_LADDER.size()]
	return "%.2f v %.2f" % [next.x, next.y]


## The tour's step: the next scenario in table order, wrapping.
func _advance_scenario() -> void:
	var list := SimScenarios.all()
	_scenario_index = (_scenario_index + 1) % list.size()
	_scenario = list[_scenario_index]


## Kicks off a match, and clears everything the last one left behind.
##
## Everything below the match itself is state carried on this node or on a tool
## that outlives the match: the recorded snapshots the trails and the step-back
## read, the scoreboard's running score, the decision sink. A new match that
## inherits any of them shows the previous one's football, which is worse than
## showing none.
##
## The ground is rebuilt too. The turf is cut from `SimEnv.surface_height` and
## the seed picks the phase of its undulations, so grass built for the last seed
## is grass the new match's ball does not roll on: a ball buried in one hollow
## and floating over the next.
func _start_match(seed_value: int) -> void:
	match_seed = seed_value
	var opts := _match_options(seed_value)
	_match = SimRunner.build(opts)
	_env = _match.ctx.env
	_match.write_snapshot(_curr)
	_prev.copy_from(_curr)
	_drawn_tick = _curr.tick
	_ball_roll = Quaternion.IDENTITY
	_accumulator = 0.0
	_paused = false
	_full_time = false
	_scenario_end_tick = -1
	_scenario_hold_end = -1
	_scenario_started = false
	if _scenario != null:
		_scenario_end_tick = int((_scenario.seconds + SCENARIO_HOLD) / SimConsts.DT)
		var tour := (" (%d/%d, N next, R again)" % [_scenario_index + 1,
			SimScenarios.all().size()]) if _scenario_cycle else ""
		print("scenario %s%s, seed %d: %s" % [_scenario.name, tour, seed_value, _scenario.title])
		if _scoreboard != null:
			_scoreboard.subtitle = _scenario.name.to_upper() + (
				"  %d/%d" % [_scenario_index + 1, SimScenarios.all().size()]
				if _scenario_cycle else "")
	_build_ground()
	_build_players()
	if _scoreboard != null:
		var home: SimTeam = _match.ctx.teams[0]
		var away: SimTeam = _match.ctx.teams[1]
		_scoreboard.reset()
		_scoreboard.home_name = home.short_name
		_scoreboard.away_name = away.short_name
		_scoreboard.home_kit = _kits[0][0]
		_scoreboard.away_kit = _kits[1][0]
	# A new match kicks off from the centre spot, so the halfway camera takes it.
	if _camera != null:
		_cut_to(1)
	_history.clear()
	_frames.clear()
	_scrubbing = false
	_scrub = 0
	# The sink is static, so it outlives the match that filled it. Cleared here
	# rather than left to its own roll-over, which only fires on the new match's
	# first decision — until then the panel would be latched on a man who is no
	# longer on the pitch.
	if _debug:
		SimDebug.reset()
	if _debug_world != null:
		_debug_world.env = _env
	_debug_kits()
	print("kick-off: seed %d, %s" % [seed_value, _quality_text()])


## The next match: the seed after this one, so the sequence is still reproducible
## and every bookmark, replay command and printed line names a match that can be
## opened again with `--seed`.
##
## The mark state goes with the old match. A bookmark is a tick of one seed, and
## seeking to it in a different one lands somewhere unrelated.
##
## `quality_step` walks the quality ladder with it. N takes the next rung, R
## stays on this one: the point of R is the same football again.
func _go_to_match(seed_value: int, quality_step: int = -1) -> void:
	if quality_step >= 0:
		_quality_step = quality_step
	_mark_tick = -1
	_seek_target = -1
	_seek_is_rewind = false
	_marked_at = -1
	_bookmark_pending = false
	_start_match(seed_value)


# --- World ------------------------------------------------------------------


## Everything that outlives a match: the light, the camera, the stands, the crowd
## and the ball. The grass and the goals are not here — they are cut from the
## seed's own surface, so `_start_match` builds them.
func _build_world() -> void:
	var backdrop := SimPalette.BACKDROPS[0]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = backdrop
	# Flat ambient, no bloom and no screen-space reflections -- those do fight the
	# hand-made register. Crease shading is the exception and this comment used to
	# rule it out with the rest: the owner's vinyl reference is full of it, and
	# without it a flat-coloured figure is a set of shapes rather than an object.
	# `SimCharacterBuilder.add_crease_shading` has the reasoning and the cost.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	# Down from 0.55, and the fill light below is what it paid for. Flat ambient
	# is the thing that flattens: it lights the shadow side evenly and a figure
	# stops being round.
	env.ambient_light_energy = 0.30
	SimCharacterBuilder.add_crease_shading(env)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	# Past the point the camera looks at, with the fade band left over. The
	# camera stands `CAMERA_RANGE` from that point and Godot fades a directional
	# shadow out over the last fifth of this range, so at 70 the man in the
	# middle of the frame was 10 m beyond his own shadow's end and the ones
	# nearer the touchline stood in the fade. `soften_shadow` scales the bias
	# with the range, which is what let it go this far without the crosshatch.
	SimCharacterBuilder.soften_shadow(sun, 110.0)
	add_child(sun)
	SimCharacterBuilder.add_fill_light(self, -35.0)

	_camera = Camera3D.new()
	add_child(_camera)
	_cut_to(1)

	_build_stands()
	_build_crowd()

	_ball = _build_ball()
	add_child(_ball)

	_build_scoreboard()


## The grass, the paint and the goals, all cut from this seed's surface. Held
## under one node so a new match can throw the last one's away in a line.
func _build_ground() -> void:
	if _ground != null:
		_ground.queue_free()
	_ground = Node3D.new()
	add_child(_ground)
	_build_pitch()
	_build_goals()


## The interface sits on a CanvasLayer of its own so it is drawn over the match
## at a fixed size, whatever the camera is doing underneath it.
func _build_scoreboard() -> void:
	var made := _overlay_layer(10)
	add_child(made[0])
	_scoreboard = MatchScoreboard.new()
	made[1].add_child(_scoreboard)


## The debug overlay: panels on their own canvas layer above the scoreboard, and
## the annotation layers in the world. Both read the context and neither writes
## to it. Nothing here is built unless `--debug` was passed.
func _build_debug() -> void:
	var made := _overlay_layer(11)
	add_child(made[0])
	_overlay = MatchDebugOverlay.new()
	made[1].add_child(_overlay)
	_debug_world = MatchDebugWorld.new()
	add_child(_debug_world)
	_debug_world.env = _env
	# On by default, alone among the layers. Everything else answers a question;
	# this one is what makes the answers usable, because every panel names men by
	# a number the pitch does not otherwise carry.
	_debug_world.toggle(MatchDebugWorld.L_NAMES)
	for digit in _layer_arg.split(",", false):
		var index := int(digit) - 1
		if index >= 0 and index < MatchDebugWorld.LAYER_KEYS.size():
			_debug_world.toggle(MatchDebugWorld.LAYER_KEYS[index])
	_debug_kits()
	# The sink is enabled after the match is built and before it is stepped, so
	# the first decision of the match is already in it.
	SimDebug.enabled = true
	SimDebug.reset()


func _debug_kits() -> void:
	if _overlay == null or _kits.size() < 2:
		return
	_overlay.home_kit = _kits[0][0]
	_overlay.away_kit = _kits[1][0]
	_debug_world.set_kits(_kits[0][0], _kits[1][0])
	_build_name_tags()


## Shirt numbers over the players' heads.
##
## Every panel, every bookmark and every replay line names a player by his shirt,
## and until this there was no way to tell which body that was: the 3D players
## carry kits and faces and no numbers. It is the difference between "the one on
## the left" and "#4 again", which is the difference between a complaint that can
## be investigated and one that cannot.
##
## The tag is a child of the player node rather than a thing drawn at a snapshot
## position, so it inherits the interpolated body and never lags it.
const NAME_TAG_HEIGHT := 2.2
const NAME_TAG_FONT := 44
const NAME_TAG_OUTLINE := 12
## With `fixed_size` on, this is what decides how big the number is on screen. It
## wants to be readable and no larger: a tag the size of the player is a tag that
## hides the football.
const NAME_TAG_PIXELS := 0.00022


func _build_name_tags() -> void:
	for i in _players.size():
		if _players[i].has_node("name_tag"):
			continue
		var tag := Label3D.new()
		tag.name = "name_tag"
		tag.text = "%d" % _match.ctx.players[i].shirt
		tag.position = Vector3(0.0, NAME_TAG_HEIGHT, 0.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Fixed size, so a number is as readable at the far touchline as at the
		# near one — which is where the men you cannot identify tend to be.
		tag.fixed_size = true
		tag.pixel_size = NAME_TAG_PIXELS
		tag.no_depth_test = true
		tag.font_size = NAME_TAG_FONT
		tag.outline_size = NAME_TAG_OUTLINE
		tag.modulate = SimPalette.PAPER
		tag.outline_modulate = SimPalette.INK
		tag.render_priority = 3
		tag.outline_render_priority = 2
		_players[i].add_child(tag)
	_show_name_tags(_debug and _debug_world.layer_on(MatchDebugWorld.L_NAMES))


func _show_name_tags(shown: bool) -> void:
	for node in _players:
		var tag := node.get_node_or_null("name_tag")
		if tag != null:
			(tag as Label3D).visible = shown


func _build_pitch() -> void:
	var hl := _pitch.half_length
	var hw := _pitch.half_width
	# The ground the whole stadium stands on. Without it the grass runs out from
	# under the stands and the crowd floats over the backdrop. Not green: in the
	# pitch colours it reads as more pitch beyond the stand, which is worse than
	# no apron at all. Follows the turf like everything else, or the twenty
	# centimetres the pitch falls by the touchline would leave it standing proud
	# of the grass it is supposed to sit under.
	var ground := MeshInstance3D.new()
	ground.mesh = _turf_mesh(Vector2(hl * 2.0 + 60.0, hw * 2.0 + 50.0), 0.0, -0.03, 3.0)
	ground.material_override = SimCharacterBuilder.flat_material(SimPalette.SLATE)
	_ground.add_child(ground)

	# Mowing stripes as flat colour bands, which is all they ever are.
	var bands := 12
	for i in bands:
		var x0: float = lerpf(-hl, hl, float(i) / float(bands))
		var x1: float = lerpf(-hl, hl, float(i + 1) / float(bands))
		var strip := MeshInstance3D.new()
		strip.mesh = _turf_mesh(Vector2(x1 - x0, hw * 2.0 + 14.0), (x0 + x1) * 0.5, 0.0, TURF_MESH_STEP)
		strip.material_override = SimCharacterBuilder.flat_material(
			SimPalette.GRASS if i % 2 == 0 else SimPalette.PINE
		)
		_ground.add_child(strip)

	# Painted lines: one of the two places a texture is allowed.
	var lines := MeshInstance3D.new()
	lines.mesh = _turf_mesh(Vector2(hl * 2.0, hw * 2.0), 0.0, 0.02, TURF_MESH_STEP)
	var line_mat := SimCharacterBuilder.flat_material(Color.WHITE)
	line_mat.albedo_texture = _pitch_line_texture()
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A painted line seen down a shallow ground plane is the worst case there is
	# for point sampling: without mipmaps and anisotropy the far lines break into
	# dots and the centre circle crawls as the camera cuts.
	line_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	lines.material_override = line_mat
	_ground.add_child(lines)


## The turf as geometry, following the same surface the simulation integrates the
## ball over (SimEnv.surface_height).
##
## The pitch was three flat planes, which was right while the ground under the
## ball was a plane. It is not any more: there is a camber, and the ball rides it.
## A flat mesh under a ball that follows the grass is a ball buried to the waist
## by the touchline and floating over the middle, and the bob over the small
## undulations cannot show at all, because there is nothing for it to be relative
## to.
##
## Normals come from the analytic gradient rather than from the triangles, so the
## light reads the surface as the smooth thing it is instead of faceting it.
func _turf_mesh(size: Vector2, centre_x: float, y_offset: float, step: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := centre_x - size.x * 0.5
	var z0 := -size.y * 0.5
	var nx: int = maxi(1, int(ceil(size.x / step)))
	var nz: int = maxi(1, int(ceil(size.y / step)))
	for ix in nx:
		for iz in nz:
			var xa := x0 + size.x * float(ix) / float(nx)
			var xb := x0 + size.x * float(ix + 1) / float(nx)
			var za := z0 + size.y * float(iz) / float(nz)
			var zb := z0 + size.y * float(iz + 1) / float(nz)
			# Wound so the face looks up. The other way round the whole pitch
			# renders as a hole with the players floating over the backdrop.
			_turf_vertex(st, xb, zb, y_offset, x0, z0, size)
			_turf_vertex(st, xa, zb, y_offset, x0, z0, size)
			_turf_vertex(st, xa, za, y_offset, x0, z0, size)
			_turf_vertex(st, xb, za, y_offset, x0, z0, size)
			_turf_vertex(st, xb, zb, y_offset, x0, z0, size)
			_turf_vertex(st, xa, za, y_offset, x0, z0, size)
	return st.commit()


func _turf_vertex(st: SurfaceTool, x: float, z: float, y_offset: float, x0: float, z0: float, size: Vector2) -> void:
	st.set_uv(Vector2((x - x0) / size.x, (z - z0) / size.y))
	if _env != null:
		var slope := _env.surface_slope(x, z)
		st.set_normal(Vector3(-slope.x, 1.0, -slope.z).normalized())
	else:
		st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(x, _turf(x, z) + y_offset, z))


## Height of the grass at a point. Zero before there is a match to ask.
func _turf(x: float, z: float) -> float:
	return _env.surface_height(x, z) if _env != null else 0.0


## Draws the markings once into a texture rather than as geometry.
##
## Twenty pixels to the metre. At ten the lines were thinner than a texel by the
## time they reached the far end of the frame and broke into dots, and the
## centre circle — plotted as a ring of points rather than filled — was gappy
## even close up.
const LINE_PX_PER_M := 20.0
const LINE_WIDTH_M := 0.24


func _pitch_line_texture() -> Texture2D:
	var w := int(_pitch.half_length * 2.0 * LINE_PX_PER_M)
	var h := int(_pitch.half_width * 2.0 * LINE_PX_PER_M)
	var image := Image.create(w, h, true, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var white := Color(1, 1, 1, 0.9)
	var thickness := maxi(int(LINE_WIDTH_M * LINE_PX_PER_M), 1)
	var to_px := func(x: float, z: float) -> Vector2i:
		return Vector2i(
			int((x + _pitch.half_length) * LINE_PX_PER_M),
			int((z + _pitch.half_width) * LINE_PX_PER_M)
		)
	var rect := func(x0: float, z0: float, x1: float, z1: float) -> void:
		var a: Vector2i = to_px.call(x0, z0)
		var b: Vector2i = to_px.call(x1, z1)
		for t in thickness:
			_hline(image, a.x, b.x, a.y + t, white)
			_hline(image, a.x, b.x, b.y - t, white)
			_vline(image, a.y, b.y, a.x + t, white)
			_vline(image, a.y, b.y, b.x - t, white)
	rect.call(-_pitch.half_length, -_pitch.half_width, _pitch.half_length, _pitch.half_width)
	for t in thickness:
		_vline(image, 0, h - 1, w / 2 + t, white)
	_ring(image, w / 2, h / 2, _pitch.centre_circle * LINE_PX_PER_M, float(thickness), white)
	# Spots. Small, but they are what makes the markings read as a real pitch
	# rather than a diagram of one.
	_disc(image, w / 2, h / 2, LINE_WIDTH_M * LINE_PX_PER_M * 1.6, white)
	for side in [-1.0, 1.0]:
		var edge: float = side * _pitch.half_length
		var inner: float = side * (_pitch.half_length - _pitch.penalty_depth)
		rect.call(minf(edge, inner), -_pitch.penalty_half_width, maxf(edge, inner), _pitch.penalty_half_width)
		var six: float = side * (_pitch.half_length - _pitch.goal_area_depth)
		rect.call(minf(edge, six), -_pitch.goal_area_half_width, maxf(edge, six), _pitch.goal_area_half_width)
		var spot: Vector2i = to_px.call(side * (_pitch.half_length - _pitch.penalty_spot_dist), 0.0)
		_disc(image, spot.x, spot.y, LINE_WIDTH_M * LINE_PX_PER_M * 1.6, white)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _hline(image: Image, x0: int, x1: int, y: int, colour: Color) -> void:
	if y < 0 or y >= image.get_height():
		return
	for x in range(maxi(mini(x0, x1), 0), mini(maxi(x0, x1), image.get_width() - 1) + 1):
		image.set_pixel(x, y, colour)


func _vline(image: Image, y0: int, y1: int, x: int, colour: Color) -> void:
	if x < 0 or x >= image.get_width():
		return
	for y in range(maxi(mini(y0, y1), 0), mini(maxi(y0, y1), image.get_height() - 1) + 1):
		image.set_pixel(x, y, colour)


## An annulus tested per pixel, not a ring of plotted points. Plotting points
## around a circumference leaves gaps wherever the step is longer than a pixel,
## which is what made the centre circle dotted.
func _ring(image: Image, cx: int, cy: int, radius: float, thickness: float, colour: Color) -> void:
	_fill(image, cx, cy, radius + thickness, colour, func(d: float) -> bool:
		return d >= radius and d <= radius + thickness)


func _disc(image: Image, cx: int, cy: int, radius: float, colour: Color) -> void:
	_fill(image, cx, cy, radius, colour, func(d: float) -> bool: return d <= radius)


func _fill(image: Image, cx: int, cy: int, extent: float, colour: Color, inside: Callable) -> void:
	var r := int(ceil(extent)) + 1
	for y in range(maxi(cy - r, 0), mini(cy + r, image.get_height() - 1) + 1):
		for x in range(maxi(cx - r, 0), mini(cx + r, image.get_width() - 1) + 1):
			var dx := float(x - cx)
			var dy := float(y - cy)
			if inside.call(sqrt(dx * dx + dy * dy)):
				image.set_pixel(x, y, colour)


## Thick rounded tubes in a bright accent colour: they should read as pool
## noodles, not steel.
func _build_goals() -> void:
	var accent := SimCharacterBuilder.flat_material(SimPalette.AMBER)
	for side in [-1.0, 1.0]:
		var x: float = side * _pitch.half_length
		# Each post is set into the grass at its own foot rather than at y = 0.
		# The camber is nothing this close to the middle, but the undulation is
		# a couple of centimetres either way, and a post standing that far clear
		# of its own shadow is worse than one sunk the same amount.
		var base := _turf(x, 0.0) - 0.02
		for post in [-1.0, 1.0]:
			var p := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.16
			mesh.bottom_radius = 0.16
			mesh.height = _pitch.goal_height
			mesh.radial_segments = 8
			p.mesh = mesh
			p.material_override = accent
			p.position = Vector3(x, base + _pitch.goal_height * 0.5, post * _pitch.goal_half_width)
			_ground.add_child(p)
		var bar := MeshInstance3D.new()
		var bar_mesh := CylinderMesh.new()
		bar_mesh.top_radius = 0.16
		bar_mesh.bottom_radius = 0.16
		bar_mesh.height = (_pitch.goal_half_width * 2.0)
		bar_mesh.radial_segments = 8
		bar.mesh = bar_mesh
		bar.material_override = accent
		bar.position = Vector3(x, base + _pitch.goal_height, 0.0)
		bar.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_ground.add_child(bar)

		_build_net(side, base)


## How wide a mesh of the net is, in metres, and how thick its cord.
##
## Both are toys rather than measurements. A real net is a 10 cm mesh of 3 mm
## cord, which at the distance this camera watches from is a cord a fiftieth of
## a pixel wide: it mips away to nothing and the goal is empty again. A chunky
## mesh of visible cord is the same object drawn the way the rest of this is
## drawn, and it survives being looked at from the halfway line.
const NET_CELL_M := 0.22
const NET_CORD_M := 0.02
const NET_TEXTURE_PX := 64


## Nets, as four panels of a generated grid: the sloping roof off the crossbar,
## the back, and a side down each post.
##
## The one place the ball is watched most closely is the one place the goal had
## nothing in it. It is also the only structure here that has to be see-through
## and still be an object, so it is drawn the way the pitch markings are — a
## generated texture with an alpha grid in it, no image file — rather than as
## geometry per thread, which would be some thousands of tubes per goal.
##
## Depth and slope come from `SimConsts`, not from a constant here: the ball is
## left running for two seconds after it crosses the line now, and the
## simulation stops a scored one in the same netting this draws.
func _build_net(side: float, base: float) -> void:
	var hl := _pitch.half_length
	var w := _pitch.goal_half_width
	var h := _pitch.goal_height
	var x_line := side * hl
	var x_top := side * (hl + SimConsts.NET_DEPTH_TOP)
	var x_foot := side * (hl + SimConsts.NET_DEPTH_FOOT)

	# Foot vertices sit on the grass rather than at a flat zero, for the same
	# reason the posts are sunk into it: the camber is a couple of centimetres
	# here and a net hovering over its own shadow is worse than no net.
	var crossbar := func(z: float) -> Vector3: return Vector3(x_line, base + h, z)
	var back_top := func(z: float) -> Vector3: return Vector3(x_top, base + SimConsts.NET_BACK_HEIGHT, z)
	var back_foot := func(z: float) -> Vector3: return Vector3(x_foot, _turf(x_foot, z), z)
	var post_foot := func(z: float) -> Vector3: return Vector3(x_line, _turf(x_line, z), z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_net_panel(st, crossbar.call(-w), crossbar.call(w), back_top.call(w), back_top.call(-w))
	_net_panel(st, back_top.call(-w), back_top.call(w), back_foot.call(w), back_foot.call(-w))
	for z in [-w, w]:
		_net_panel(st, post_foot.call(z), crossbar.call(z), back_top.call(z), back_foot.call(z))
	st.generate_normals()

	var net := MeshInstance3D.new()
	net.mesh = st.commit()
	net.material_override = _net_material()
	# A net is a hole in the light, not a caster: shadowing every thread of it
	# stipples the six-yard box with a grid that is not there in life.
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.add_child(net)


## One panel, wound as two triangles and UV'd off its own edge lengths so the
## mesh stays roughly square whatever shape the panel is. The sides are
## trapezoids, so their UVs are taken from the pair of edges that bound each
## axis rather than assumed equal.
func _net_panel(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var uv := [
		Vector2(0.0, 0.0),
		Vector2(p1.distance_to(p0) / NET_CELL_M, 0.0),
		Vector2(p2.distance_to(p3) / NET_CELL_M, p2.distance_to(p1) / NET_CELL_M),
		Vector2(0.0, p3.distance_to(p0) / NET_CELL_M),
	]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for i in tri:
			st.set_uv(uv[i])
			st.add_vertex([p0, p1, p2, p3][i])


var _net_mat: StandardMaterial3D = null


func _net_material() -> StandardMaterial3D:
	if _net_mat != null:
		return _net_mat
	_net_mat = SimCharacterBuilder.flat_material(SimPalette.CHALK)
	_net_mat.albedo_texture = _net_texture()
	_net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_net_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Both faces: the camera watches the goal from in front, from behind the
	# byline and from the side, and a one-sided net disappears from two of them.
	_net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The same worst case as the painted lines, and worse: a grid seen nearly
	# edge-on aliases into moire without mipmaps, and the far net crawls on every
	# camera move. Mipped, it settles into the haze a net is at that distance.
	_net_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _net_mat


## One cell of the mesh, tiled. The cord is drawn on two edges only — the left
## column and the top row — so that tiling it lays exactly one cord between
## neighbouring cells instead of two side by side.
func _net_texture() -> ImageTexture:
	var px := NET_TEXTURE_PX
	var cord: int = maxi(2, int(round(float(px) * NET_CORD_M / NET_CELL_M)))
	# Flat, then mipped afterwards -- the same trap the ball's panel texture
	# documents: allocating the levels up front leaves them unwritten.
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	for y in px:
		for x in px:
			if x < cord or y < cord:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## The terracing the crowd sits on.
##
## The heads alone read as heads floating over a backdrop. A raked block under
## each row, plus a back wall so the stand is not see-through, is what turns
## them into a ground — and it costs thirty-four boxes.
const STAND_ROW_RISE := 0.62
const STAND_ROW_DEPTH := 0.85
const CROWD_HEAD_RADIUS := 0.34


func _build_stands() -> void:
	var tier := SimCharacterBuilder.flat_material(SimPalette.SLATE)
	var wall := SimCharacterBuilder.flat_material(SimPalette.INK)
	var side_rows := 9
	var end_rows := 8
	var side_length := _pitch.half_length * 2.0 + 22.0
	var end_length := _pitch.half_width * 2.0 + 18.0

	for side in [-1.0, 1.0]:
		for row in side_rows:
			var z: float = side * (_pitch.half_width + 4.0 + float(row) * STAND_ROW_DEPTH)
			var top: float = 1.0 + float(row) * STAND_ROW_RISE - CROWD_HEAD_RADIUS
			_stand_block(Vector3(side_length, top, STAND_ROW_DEPTH), Vector3(0.0, top * 0.5, z), tier)
		var back_z: float = side * (_pitch.half_width + 4.0 + float(side_rows) * STAND_ROW_DEPTH)
		var back_h: float = 1.0 + float(side_rows) * STAND_ROW_RISE
		_stand_block(Vector3(side_length, back_h, 0.7), Vector3(0.0, back_h * 0.5, back_z), wall)

	for end in [-1.0, 1.0]:
		for row in end_rows:
			var x: float = end * (_pitch.half_length + 5.0 + float(row) * STAND_ROW_DEPTH)
			var top2: float = 1.0 + float(row) * STAND_ROW_RISE - CROWD_HEAD_RADIUS
			_stand_block(Vector3(STAND_ROW_DEPTH, top2, end_length), Vector3(x, top2 * 0.5, 0.0), tier)
		var back_x: float = end * (_pitch.half_length + 5.0 + float(end_rows) * STAND_ROW_DEPTH)
		var back_h2: float = 1.0 + float(end_rows) * STAND_ROW_RISE
		_stand_block(Vector3(0.7, back_h2, end_length), Vector3(back_x, back_h2 * 0.5, 0.0), wall)


## Blocks are given as a size and a centre that puts their base on y = 0. They
## are built reaching further down than that, because y = 0 is no longer the
## ground out here: the camber puts the apron twenty centimetres lower at the
## touchline than at the centre spot, and a stand that stops at zero stands on
## nothing with daylight under the front row. The tops do not move.
func _stand_block(size: Vector3, at: Vector3, material: Material) -> void:
	var sink := SimConsts.SURFACE_CAMBER + 0.1
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y + sink, size.z)
	block.mesh = mesh
	block.material_override = material
	block.position = at - Vector3(0.0, sink * 0.5, 0.0)
	add_child(block)


## Instanced low-poly heads bobbing on a sine with per-instance phase offsets.
## Cheap, and the collective motion is what sells the stadium.
func _build_crowd() -> void:
	var rng := SimRng.new(99)
	var mesh := SphereMesh.new()
	mesh.radius = CROWD_HEAD_RADIUS
	mesh.height = CROWD_HEAD_RADIUS * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh

	var positions: Array[Vector3] = []
	var colours: Array[Color] = []
	# Side stands.
	for side in [-1.0, 1.0]:
		for row in 9:
			var z: float = side * (_pitch.half_width + 4.0 + float(row) * STAND_ROW_DEPTH)
			var y: float = 1.0 + float(row) * STAND_ROW_RISE
			var count := 132
			for i in count:
				var x: float = lerpf(-_pitch.half_length - 8.0, _pitch.half_length + 8.0, float(i) / float(count - 1))
				positions.append(Vector3(x + rng.range_float(-0.25, 0.25), y, z + rng.range_float(-0.2, 0.2)))
				colours.append(SimPalette.KIT_COLOURS[rng.range_int(0, SimPalette.KIT_COLOURS.size() - 1)])
	# Ends, so the ground closes rather than trailing off into the backdrop.
	for end in [-1.0, 1.0]:
		for row in 8:
			var x2: float = end * (_pitch.half_length + 5.0 + float(row) * STAND_ROW_DEPTH)
			var y2: float = 1.0 + float(row) * STAND_ROW_RISE
			var count2 := 72
			for i in count2:
				var z2: float = lerpf(-_pitch.half_width - 6.0, _pitch.half_width + 6.0, float(i) / float(count2 - 1))
				positions.append(Vector3(x2 + rng.range_float(-0.2, 0.2), y2, z2 + rng.range_float(-0.25, 0.25)))
				colours.append(SimPalette.KIT_COLOURS[rng.range_int(0, SimPalette.KIT_COLOURS.size() - 1)])
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		mm.set_instance_color(i, colours[i])

	_crowd = MultiMeshInstance3D.new()
	_crowd.multimesh = mm
	var mat := SimCharacterBuilder.flat_material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	_crowd.material_override = mat
	_crowd.set_meta("home", positions)
	_crowd.set_meta("phases", _phases(positions.size()))
	add_child(_crowd)


func _phases(count: int) -> PackedFloat32Array:
	var rng := SimRng.new(1234)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = rng.unit_float() * TAU
	return out


## The ball: one sphere, with the panels painted on rather than built.
##
## They used to be six small dark spheres poking through the surface at random
## points. Two things were wrong with that. Bumps are not a pattern — a rolling
## ball wobbled rather than turned, because the silhouette changed as it went —
## and a random scatter has no symmetry, so the eye cannot tell a quarter turn
## from a half one. A painted truncated icosahedron has both: it is the same
## everywhere, so any rotation reads as rotation and nothing else.
func _build_ball() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = BALL_DRAW_RADIUS
	mesh.height = BALL_DRAW_RADIUS * 2.0
	# Faceting reads as a shape change while the ball turns, which is exactly the
	# cue the roll is being judged on, so the sphere is round enough to not lie.
	# It is one object in the scene; the triangles are free.
	mesh.radial_segments = 28
	mesh.rings = 14
	body.mesh = mesh
	var mat := SimCharacterBuilder.flat_material(SimPalette.CHALK)
	mat.albedo_texture = _ball_panel_texture()
	# A ball ten pixels across is the worst case for point sampling: without
	# mipmaps the panels flicker on and off as it rolls.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body.material_override = mat
	root.add_child(body)
	return root


## The classic thirty-two-panel ball, drawn once into a texture.
##
## Twelve dark pentagons sit at the vertices of an icosahedron and the white
## hexagons are simply everything else, which is what a truncated icosahedron
## is. Each pentagon is the region cut by the five planes through its corners,
## so the edges come out straight and the five points are sharp; a distance test
## against the vertex would give a circle, and circles do not read as panels.
const BALL_TEXTURE_WIDTH := 256
const BALL_TEXTURE_HEIGHT := 128
## Half-width of the blend across a panel edge, in units of the plane test. Wide
## enough to stop the edges crawling, narrow enough that they still look cut.
const BALL_EDGE_SOFTNESS := 0.02


func _ball_panel_texture() -> ImageTexture:
	var vertices := _icosahedron_vertices()
	var planes := _pentagon_planes(vertices)
	# Created flat and mipped afterwards: `Image.create` with mipmaps on allocates
	# the smaller levels but does not fill them, and `set_pixel` only ever writes
	# the top one. The ball is small enough on screen to be sampling mip 2, so
	# what shows is not the pattern but whatever was in that memory.
	var image := Image.create(BALL_TEXTURE_WIDTH, BALL_TEXTURE_HEIGHT, false, Image.FORMAT_RGB8)
	for j in BALL_TEXTURE_HEIGHT:
		# v runs from the north pole down, the way SphereMesh lays its UVs out.
		var theta: float = (float(j) + 0.5) / float(BALL_TEXTURE_HEIGHT) * PI
		var sin_t := sin(theta)
		var cos_t := cos(theta)
		for i in BALL_TEXTURE_WIDTH:
			var phi: float = (float(i) + 0.5) / float(BALL_TEXTURE_WIDTH) * TAU
			var dir := Vector3(sin_t * cos(phi), cos_t, sin_t * sin(phi))
			image.set_pixel(i, j, SimPalette.CHALK.lerp(SimPalette.INK, _panel_ink(dir, vertices, planes)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## How dark this direction is: 1 inside a pentagon, 0 on the hexagons, blended
## across the width of an edge.
func _panel_ink(dir: Vector3, vertices: Array, planes: Array) -> float:
	var nearest := 0
	var best := -2.0
	for i in vertices.size():
		var d: float = dir.dot(vertices[i])
		if d > best:
			best = d
			nearest = i
	# A pentagon reaches 20 degrees from its centre, so anything further out than
	# that is hexagon and the five plane tests can be skipped.
	if best < 0.92:
		return 0.0
	var outside := -2.0
	for plane in planes[nearest]:
		outside = maxf(outside, dir.dot(plane as Vector3))
	return 1.0 - smoothstep(-BALL_EDGE_SOFTNESS, BALL_EDGE_SOFTNESS, outside)


func _icosahedron_vertices() -> Array:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var out := []
	for a in [-1.0, 1.0]:
		for b in [-phi, phi]:
			out.append(Vector3(0.0, a, b).normalized())
			out.append(Vector3(a, b, 0.0).normalized())
			out.append(Vector3(b, 0.0, a).normalized())
	return out


## For each vertex, the five planes that bound its pentagon.
##
## A pentagon corner sits a third of the way along an icosahedron edge, so it is
## `2v + n` for each neighbour `n`. Two corners on the same icosahedron face
## share an edge of the pentagon, and the plane through the centre containing
## both is that edge. Normals point away from the vertex, so a direction is
## inside the pentagon when it is on the negative side of all five.
func _pentagon_planes(vertices: Array) -> Array:
	var out := []
	for i in vertices.size():
		var v: Vector3 = vertices[i]
		var neighbours: Array[Vector3] = []
		for other in vertices:
			# Adjacent vertices of an icosahedron sit at a dot product of 1/sqrt(5);
			# everything else is at 0 or below.
			if v.dot(other) > 0.3 and v.dot(other) < 0.99:
				neighbours.append(other)
		var edges: Array[Vector3] = []
		for a in neighbours.size():
			for b in range(a + 1, neighbours.size()):
				if neighbours[a].dot(neighbours[b]) < 0.3:
					continue  # Not two corners of one face.
				var ca := (v * 2.0 + neighbours[a]).normalized()
				var cb := (v * 2.0 + neighbours[b]).normalized()
				var normal := ca.cross(cb).normalized()
				if normal.dot(v) > 0.0:
					normal = -normal
				edges.append(normal)
		out.append(edges)
	return out


func _build_players() -> void:
	for node in _players:
		node.queue_free()
	_players.clear()
	# A kit clash is the one visual bug that makes a match unwatchable, so the
	# away side is chosen against the home colour rather than independently.
	var home_colour: Color = _match.ctx.teams[0].kit[0]
	_kits = [
		SimAppearance.kit_for(home_colour),
		SimAppearance.away_kit(home_colour, _match.ctx.config.seed_value),
	]
	var kits := _kits
	for p in _match.ctx.players:
		var appearance := SimCharacterModel.appearance_for(p.appearance_seed)
		var node := SimCharacterModel.build(p.appearance_seed, appearance, kits[p.team], p.shirt)
		node.set_meta("appearance", appearance)
		add_child(node)
		_players.append(node)


# --- Pose sheet ---------------------------------------------------------------


## Every anim state at once, on a stand, labelled.
##
## A dive, a slide and a fall happen a handful of times in ninety minutes and
## last under a second each, so watching a match is a hopeless way to check that
## their poses are right. This lays all seventeen out side by side and holds them
## at a chosen point in their arc, which turns "is the keeper's dive the right
## way round" into something a screenshot can answer.
## Two long rows seen almost side-on. A pose is a silhouette, and a silhouette
## is exactly what a steep camera destroys: from above, a leg swung forward and
## a leg swung back look the same. The rows are spaced far further apart in
## depth than across, so the back one clears the front one at a low angle.
## Rows the sheet is laid out in. Two, always: the framing below is a camera
## pulled back far enough to hold one row's width, and a third row lands nearer
## the lens than the point it is aimed at and falls out of the bottom of the
## frame. The column count follows from the number of anims instead, so adding
## one widens the sheet rather than starting a row nobody can see.
const POSE_SHEET_ROWS := 2
const POSE_SHEET_SPACING := 3.0
const POSE_SHEET_ROW_DEPTH := 7.0
const POSE_SHEET_ELEVATION := 24.0
## The sheet is a still of a fixed rank of figures, so it keeps a fixed lens
## rather than the match camera's zoom.
const POSE_SHEET_FOV := 30.0
## Speed each locomotion state is posed at, so the run cycle is not frozen flat.
const POSE_SHEET_SPEEDS := {
	SimConsts.Anim.IDLE: 0.0,
	SimConsts.Anim.JOG: 3.0,
	SimConsts.Anim.RUN: 5.5,
	SimConsts.Anim.SPRINT: 7.5,
	SimConsts.Anim.TURN: 4.0,
}


func _build_pose_sheet() -> void:
	var backdrop := SimPalette.BACKDROPS[0]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = backdrop
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	# Down from 0.55, and the fill light below is what it paid for. Flat ambient
	# is the thing that flattens: it lights the shadow side evenly and a figure
	# stops being round.
	env.ambient_light_energy = 0.30
	SimCharacterBuilder.add_crease_shading(env)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	SimCharacterBuilder.soften_shadow(sun)
	add_child(sun)

	var names := SimConsts.Anim.keys()
	var columns: int = int(ceil(float(names.size()) / float(POSE_SHEET_ROWS)))
	var rows: int = int(ceil(float(names.size()) / float(columns)))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(columns * POSE_SHEET_SPACING + 8.0, rows * POSE_SHEET_ROW_DEPTH + 12.0)
	plane.orientation = PlaneMesh.FACE_Y
	ground.mesh = plane
	ground.material_override = SimCharacterBuilder.flat_material(SimPalette.GRASS)
	add_child(ground)

	_curr.resize(names.size())
	var kit := SimAppearance.kit_for(SimPalette.BLUE)
	for i in names.size():
		var col := i % columns
		var row := i / columns
		var at := Vector3(
			(float(col) - float(columns - 1) * 0.5) * POSE_SHEET_SPACING,
			0.0,
			(float(row) - float(rows - 1) * 0.5) * POSE_SHEET_ROW_DEPTH
		)
		var anim: int = SimConsts.Anim[names[i]]
		_curr.player_pos[i] = at
		_curr.player_facing[i] = 0.0
		_curr.player_vel[i] = Vector3(POSE_SHEET_SPEEDS.get(anim, 0.0), 0.0, 0.0)
		_curr.player_stamina[i] = 1.0
		_curr.player_anim[i] = anim
		_curr.player_on_pitch[i] = 1
		# **Through the model seam, like the match.** Built straight off
		# `SimCharacterBuilder`, this sheet renders the primitives whatever is on
		# disk -- so the one tool that shows every animation state was the one
		# tool that could not show them on the figure the game actually draws,
		# and a built model with its torso planted on its hips passed it.
		var node := SimCharacterModel.build(
			i + 11, SimCharacterModel.appearance_for(i + 11), kit)
		add_child(node)
		_players.append(node)

		var label := Label3D.new()
		label.text = String(names[i])
		label.font_size = 96
		label.pixel_size = 0.0019
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = SimPalette.INK
		label.no_depth_test = true
		# At the feet and toward the camera, not overhead: a label floating above
		# a head sits level with the row behind and captions the wrong player.
		label.position = at + Vector3(0.0, 0.1, 1.9)
		add_child(label)
	_prev.copy_from(_curr)

	_camera = Camera3D.new()
	_camera.fov = POSE_SHEET_FOV
	add_child(_camera)
	# Sized for the near row, which is closer than the point the camera is aimed
	# at and so spills off both edges if the span is measured at the centre.
	var span: float = columns * POSE_SHEET_SPACING + 4.0
	# The aspect has to be the one actually being rendered, not 16:9 assumed. A
	# virtual display hands out whatever screen it was started with -- 1280x1024
	# here, which is 1.25 -- and the camera pulled back for a 1.78 frame cuts the
	# outer column off both ends of every row. The whole point of this sheet is
	# that every pose is on it.
	var view := get_viewport().get_visible_rect().size
	var aspect: float = view.x / view.y if view.y > 0.0 else 16.0 / 9.0
	var d := (span / aspect * 0.5) / tan(deg_to_rad(POSE_SHEET_FOV) * 0.5)
	var elevation := deg_to_rad(POSE_SHEET_ELEVATION)
	var centre := Vector3(0.0, 0.9, POSE_SHEET_ROW_DEPTH * 0.25)
	_camera.position = centre + Vector3(0.0, d * sin(elevation), d * cos(elevation))
	_camera.look_at(centre, Vector3.UP)


func _draw_pose_sheet() -> void:
	var clock := _anim_clock()
	_alpha = 1.0
	for i in _players.size():
		var node: Node3D = _players[i]
		node.position = _curr.player_pos[i]
		# Hold each one-shot at the requested point in its arc rather than
		# letting it play out and freeze on the last frame.
		var anim: int = _curr.player_anim[i]
		var span: float = ANIM_SECONDS.get(anim, 1.0)
		node.set_meta("anim", anim)
		node.set_meta("anim_started", _elapsed - _pose_u * span)
		_pose(node, i, clock)


# --- Frame ------------------------------------------------------------------


func _process(delta: float) -> void:
	_elapsed += delta
	if _pose_sheet:
		_draw_pose_sheet()
		_maybe_shoot()
		return
	if _match == null:
		return
	if _seek_target >= 0:
		_run_seek()
		_draw_frame(1.0, 0.0)
		_update_debug(delta)
		return
	var stepped := 0
	if not _paused and not _match.finished:
		_accumulator += delta * _speed
		var budget := 0
		while _accumulator >= SimConsts.DT and budget < 2000:
			_prev.copy_from(_curr)
			_match.tick()
			_match.write_snapshot(_curr)
			_accumulator -= SimConsts.DT
			budget += 1
			_record_history()
		stepped = budget
	# Stop on the marked tick rather than sail past it. The five seconds before it
	# have just been played; from here it is `.` and `,`.
	if _mark_tick >= 0 and _curr.tick >= _mark_tick:
		_marked_at = _mark_tick
		_mark_tick = -1
		_paused = true
	# A scenario plays itself out and starts again on the next seed. The quality
	# ladder is deliberately not walked: the situation is the variable being
	# watched, and changing the squads under it every repeat would be a second.
	# The situation ending is what ends the watch, and the clock is only the
	# backstop. `SimScenario.live` is the rule the table scores by, so the last
	# thing on screen is the thing the row counted.
	if _scenario != null and not _scenario_started:
		_scenario_started = _match.ctx.in_play
	if _scenario != null and _scenario_end_tick > _scenario_hold_end \
			and not _scenario.live(_match.ctx, _scenario_started):
		_scenario_hold_end = _curr.tick + int(SCENARIO_HOLD / SimConsts.DT)
		_scenario_end_tick = mini(_scenario_end_tick, _scenario_hold_end)
	if _scenario_end_tick >= 0 and _curr.tick >= _scenario_end_tick and not _paused:
		# On the tour the repeat stays on this scenario, a new seed each time,
		# like the single-scenario watch; only N steps to the next one.
		_go_to_match(match_seed + 1)
		return
	_check_full_time()
	if _debug:
		_refresh_value_grid()
	# How much simulated time this frame covered, which is what the ball's roll
	# is integrated over. Not the frame delta: at 2x or 8x the sim advances
	# several ticks per frame, and a ball rolling at wall-clock speed under a
	# match running at eight times that skids across the grass.
	# Stepped back through the history there is no next snapshot to interpolate
	# toward, so the frame is drawn on the sample itself.
	var alpha := 1.0 if _scrubbing else clampf(_accumulator / SimConsts.DT, 0.0, 1.0)
	_draw_frame(alpha, float(stepped) * SimConsts.DT)
	_update_debug(delta)
	_maybe_shoot()
	_maybe_bookmark()


## Full time. The match stops of its own accord and the board already says so;
## what was missing was any way out of it. Without this the view sat on a still
## pitch until it was killed, and watching a second match meant relaunching.
##
## It waits to be asked rather than rolling on by itself: the last thing that
## happens in a match is usually the thing worth looking at, and a view that cut
## to a fresh kick-off after a few seconds would take it away.
func _check_full_time() -> void:
	if not _match.finished or _full_time:
		return
	_full_time = true
	print("full time: seed %d, %s %d - %d %s, %s" % [
		match_seed, _match.ctx.teams[0].short_name,
		_curr.score[0], _curr.score[1], _match.ctx.teams[1].short_name,
		_quality_text(),
	])
	if _scoreboard != null:
		# The board names what N is about to show, because the next match is a
		# different pair of squads and that is the reason to press it. Pinned,
		# there is nothing to name: every match is the pair on the command line.
		var next := _next_quality_text()
		_scoreboard.prompt = "N  NEXT MATCH%s   R  AGAIN" % ("  " + next if next != "" else "")


func _maybe_shoot() -> void:
	if _shot_after <= 0.0 or _elapsed < _shot_after:
		return
	_shot_after = -1.0
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_shot_path)
	print("saved %s at %d-%d, minute %.1f" % [
		_shot_path, _curr.score[0], _curr.score[1], _curr.clock / 60.0,
	])
	get_tree().quit()


# --- The debug overlay ------------------------------------------------------


func _update_debug(delta: float) -> void:
	if _overlay == null or not _debug:
		return
	var ctx := _match.ctx
	_overlay.status_line = _status_text()
	_overlay.layer_line = _debug_world.layer_help()
	_show_name_tags(_debug_world.layer_on(MatchDebugWorld.L_NAMES))
	# Everything the panels and the annotations say is about the moment on screen,
	# which is a recorded one while the picture is stepped back. The overlay is
	# handed the live snapshot as well, because the ticker goes on reading the
	# event log forward however far back the picture has been wound.
	var frame := _shown_frame()
	_overlay.show_state(ctx, _live_curr if _scrubbing else _curr, frame, delta)
	_debug_world.show_state(frame, _curr, _trail(), _focus_player(frame), _overlay.latched())


## The moment being shown: a recorded frame while stepped back, otherwise this
## tick's, captured now. Captured rather than recorded so the annotations move
## with the match at every frame rate rather than at the sample rate.
func _shown_frame() -> MatchDebugFrame:
	if _scrubbing and not _frames.is_empty():
		return _frames[maxi(_frames.size() - 1 - _scrub, 0)]
	_live_frame.capture(_match.ctx)
	return _live_frame


## The trail samples, ending at the moment on screen. Drawing the whole buffer
## would draw the future over a picture that has been stepped back.
func _trail() -> Array[SimSnapshot]:
	var end := _history.size() - _scrub
	return _history.slice(maxi(end - TRAIL_SAMPLES, 0), maxi(end, 0))


## Whose head the overlay is inside: the pinned man if there is one, otherwise
## whoever had the ball at the moment on screen.
func _focus_player(frame: MatchDebugFrame) -> int:
	if _overlay != null and _overlay.pinned >= 0:
		return _overlay.pinned
	return frame.possession_player if frame.possession_player >= 0 else frame.last_touch


## Debug only, and never on the decision path — the grid is a couple of hundred
## pitch-control evaluations and the sim never asks for one.
func _refresh_value_grid() -> void:
	if not _debug_world.layer_on(MatchDebugWorld.L_VALUE):
		return
	if _match.ctx.tick_index % 30 == 0:
		_match.ctx.value.refresh_debug_grid(_match.ctx)


func _record_history() -> void:
	if not _debug:
		return
	# A seek runs through the whole match to get where it is going, and only its
	# last thirty seconds can ever be stepped back through. Capturing a frame for
	# every sample of the hour before that is an hour of copying nobody reads.
	if _seek_target >= 0 and _match.ctx.tick_index < _seek_target - HISTORY_MAX * HISTORY_EVERY:
		return
	_history_countdown -= 1
	if _history_countdown > 0:
		return
	_history_countdown = HISTORY_EVERY
	var snap := SimSnapshot.new()
	snap.copy_from(_curr)
	_history.append(snap)
	var frame := MatchDebugFrame.new()
	frame.capture(_match.ctx)
	_frames.append(frame)
	if _history.size() > HISTORY_MAX:
		_history.remove_at(0)
		_frames.remove_at(0)


func _status_text() -> String:
	if _seek_target > 0:
		var percent := 100 * _curr.tick / maxi(_seek_target, 1)
		if _seek_is_rewind:
			return "re-simulating to t%d — %d%%" % [_seek_target, percent]
		return "seeking to the marked tick %d — %d%%" % [_mark_tick, percent]
	if _mark_tick >= 0:
		return "the mark is %.1f s away" % (float(_mark_tick - _curr.tick) * SimConsts.DT)
	if _scrubbing:
		var oldest := " (earliest recorded)" if _scrub >= _history.size() - 1 else ""
		return ("STEPPED BACK %.1f s%s   , . a sample   < > half a second"
			+ "   enter play on from here   space live") % [
			float(_scrub * HISTORY_EVERY) * SimConsts.DT, oldest,
		]
	# The compressed clock cannot be changed once the match is built, so a match
	# opened with F1 rather than started with --debug is being read at 30x. Saying
	# so is the whole of the fix available from here.
	var compressed := ""
	if clock_rate > 4.0:
		compressed = "   clock %.0fx — restart with --debug to read this properly" % clock_rate
	var mark := "   AT THE MARK t%d" % _marked_at if _marked_at >= 0 else ""
	# The seed belongs on the line the moment there is more than one match in a
	# session: every bookmark and replay command names one, and by the third match
	# nobody remembers which they are watching.
	# The quality is on the line for the same reason the seed is: three matches
	# into a session the sides have changed twice and nothing else on screen says
	# which pair is playing.
	return ("seed %d   %s   %sx%.2f   space pause   [ ] speed   . step   , back   < > jump"
		+ "   M mark   N next   R again   click pin   F1 off%s%s") % [
		match_seed, _quality_text(), "PAUSED  " if _paused else "",
		_speed, mark, compressed,
	]


func _set_speed(step: int) -> void:
	_leave_scrub()
	_speed_step = clampi(step, 0, SPEED_LADDER.size() - 1)
	_speed = SPEED_LADDER[_speed_step]


## One tick, paused. The other half of slow motion: at 0.1x a touch still takes
## six frames, and some of what looks wrong happens inside one.
##
## Stepped back, it walks forward through the recording instead, `samples` at a
## time — the same jump `,` made, so a big step back is undone by a big step
## forward and the moment can be crossed and re-crossed.
func _step_forward(samples := STEP_SAMPLES) -> void:
	if _scrubbing:
		_scrub -= samples
		if _scrub <= 0:
			_leave_scrub()
		else:
			_show_scrub()
		return
	_paused = true
	if _match.finished:
		return
	_prev.copy_from(_curr)
	_match.tick()
	_match.write_snapshot(_curr)
	_record_history()


## Back through the recording, one sample or ten. The simulation is not rewound
## — it cannot be — so this moves the picture, and the panels move with it.
func _step_back(samples := STEP_SAMPLES) -> void:
	if _history.size() < 2:
		return
	if not _scrubbing:
		_live_prev.copy_from(_prev)
		_live_curr.copy_from(_curr)
		_scrubbing = true
		_paused = true
		_scrub = 0
	_scrub = mini(_scrub + samples, _history.size() - 1)
	_show_scrub()


func _show_scrub() -> void:
	var i := _history.size() - 1 - _scrub
	_curr.copy_from(_history[i])
	_prev.copy_from(_history[maxi(i - 1, 0)])


func _leave_scrub() -> void:
	if not _scrubbing:
		return
	_scrubbing = false
	_scrub = 0
	_prev.copy_from(_live_prev)
	_curr.copy_from(_live_curr)


## Play on from the moment on screen, rather than from where the match has got
## to. What the step-back is for half the time: the thing that looked wrong went
## past, and the question is what happens next if it is watched properly.
##
## The simulation cannot be rewound. Nothing in `sim/` runs backwards, and a good
## deal of what a tick reads is static — the off-ball intents, the chase
## assignment, the duel scratch — so there is no one object to put back. What
## there is instead is determinism: the same seed re-simulates the same match,
## tick for tick, which is what `./run.sh determinism` exists to check. So the
## match is built again from the seed and fast-forwarded to the tick on screen,
## and from there the football is live again — the next pass goes where the
## decision takes it, not where the recording said it went.
##
## It costs what those minutes cost the first time. The seek runs across frames
## with a percentage on the status line, so a rewind an hour into a match is a
## wait rather than a freeze. Stepping back and playing on twice in the same
## minute pays it twice; there is nothing cheaper while the sim keeps state in
## statics.
func _play_from_here() -> void:
	if not _scrubbing:
		return
	var target := _curr.tick
	_scrubbing = false
	_scrub = 0
	_marked_at = -1
	_pin_held = _overlay.pinned if _overlay != null else -1
	# Everything the recording holds is about to be simulated again, and the sink
	# with it. `_start_match` clears both.
	_start_match(match_seed)
	if target <= 0:
		return
	_seek_target = target
	_seek_is_rewind = true
	print("playing on from t%d: re-simulating seed %d from kick-off" % [target, match_seed])


## Pins the player nearest the click. The ray is dropped onto the plane the
## players stand on, which is close enough at this camera height.
func _pin_at(at: Vector2) -> void:
	if _camera == null or _overlay == null:
		return
	var origin := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	if absf(dir.y) < 0.0001:
		return
	var travel := -origin.y / dir.y
	if travel <= 0.0:
		return
	var point := origin + dir * travel
	var best := -1
	var best_distance := 3.0
	for i in _curr.player_count:
		if _curr.player_on_pitch[i] == 0:
			continue
		var d := SimConsts.horizontal_length(_curr.player_pos[i] - point)
		if d < best_distance:
			best_distance = d
			best = _curr.player_id[i]
	_overlay.pinned = best


# --- Bookmarks --------------------------------------------------------------


## Writes the moment to a file, with the frame beside it.
##
## This is the point of the whole overlay. "It looked like he ignored an obvious
## pass" becomes a seed, a tick and a candidate list, which re-runs identically
## and can be read by somebody who was not watching.
func _maybe_bookmark() -> void:
	if _bookmark_after > 0.0 and _elapsed >= _bookmark_after:
		_bookmark_after = -1.0
		_bookmark_pending = true
	if not _bookmark_pending:
		return
	_bookmark_pending = false
	var folder := "res://bookmarks"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var stem := "seed%d-t%d" % [match_seed, _curr.tick]
	var file := FileAccess.open("%s/%s.md" % [folder, stem], FileAccess.WRITE)
	if file == null:
		printerr("could not write a bookmark into %s" % ProjectSettings.globalize_path(folder))
		return
	file.store_string(_bookmark_text(_shown_frame()))
	file.close()
	print("bookmark: %s" % ProjectSettings.globalize_path("%s/%s.md" % [folder, stem]))
	print("  %s" % _replay_command(_curr.tick))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, stem])


## The marked moment as words. Written from the frame rather than the context,
## so a moment marked after stepping back describes the picture that was marked
## and not the one the sim has since reached.
func _bookmark_text(frame: MatchDebugFrame) -> String:
	var ctx := _match.ctx
	var tick := frame.tick
	var window := SimConsts.TICK_HZ * 8
	var out := PackedStringArray()
	out.append("# seed %d, tick %d (%s), %s %d - %d %s" % [
		match_seed, tick, SimDebug.clock_text(_curr.clock),
		ctx.teams[0].short_name, _curr.score[0], _curr.score[1], ctx.teams[1].short_name,
	])
	out.append("")
	out.append("    %s" % _replay_command(tick))
	out.append("")
	out.append("%s, phase %s, ball %.1f m/s at (%.1f, %.1f)" % [
		"in play" if frame.in_play else "dead ball",
		MatchDebugOverlay.PHASE_NAMES[frame.phase], _curr.ball_vel.length(),
		_curr.ball_pos.x, _curr.ball_pos.z,
	])

	out.append("\n## Around the ball\n")
	var ball := Vector3(_curr.ball_pos.x, 0.0, _curr.ball_pos.z)
	for i in frame.count:
		if frame.on_pitch[i] == 0:
			continue
		var distance := SimConsts.horizontal_length(frame.pos[i] - ball)
		if distance > 20.0:
			continue
		var p := ctx.players[i]
		out.append("- #%d %s %s (%s), %.0f m from the ball, pressure %.1f, offering %s, chase %s" % [
			p.shirt, SimRole.name_of(p.role), p.player_name, ctx.teams[p.team].short_name,
			distance, frame.pressure[i],
			SimOffBall.KIND_NAMES[frame.intent[i]],
			["none", "primary", "support"][frame.chase[i]],
		])

	out.append("\n## Decisions\n")
	out.append("```")
	for rec in SimDebug.between(tick - window, tick):
		for line in SimDebug.describe(rec):
			out.append(line)
	out.append("```")

	out.append("\n## Events\n")
	out.append("```")
	for e in ctx.telemetry.events:
		var t := int(e["t"])
		if t < tick - window or t > tick:
			continue
		var text := SimDebug.event_text(ctx, e)
		if text != "":
			out.append("t%-7d %s" % [t, text])
	out.append("```")
	return "\n".join(out) + "\n"


## Opens a marked moment: the same seed, fast-forwarded to five seconds before
## the tick, played at quarter speed, and paused on the tick itself.
##
## `./run.sh replay` reads a bookmark back as words. This watches it again, as
## many times as it takes, which is the half a description of a moment cannot
## replace. Takes `seed7-t34210`, the file name, or a path to it.
##
## The flags are read out of the file rather than assumed, because the seed alone
## does not identify the match: a compressed clock and a scaled pitch are
## different matches from the same seed, and the tick would land somewhere else.
func _load_bookmark(arg: String) -> void:
	var path := arg if arg.ends_with(".md") else arg + ".md"
	if not path.contains("/"):
		path = "res://bookmarks/".path_join(path)
	var found := RegEx.create_from_string("seed(\\d+)-t(\\d+)").search(path.get_file())
	if found == null:
		printerr("--from-bookmark wants a bookmark named seedN-tT, not %s" % arg)
		return
	match_seed = int(found.get_string(1))
	_mark_tick = int(found.get_string(2))
	_debug = true

	if not FileAccess.file_exists(path):
		printerr("no bookmark at %s — replaying the seed with this view's own settings, "
			% ProjectSettings.globalize_path(path)
			+ "so the tick will only line up if they match the ones it was marked under")
		return
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.contains("run.sh replay"):
			continue
		var words := line.split(" ", false)
		for i in words.size():
			if words[i] == "--clock-rate" and i + 1 < words.size():
				clock_rate = float(words[i + 1])
				_clock_rate_given = true
			elif words[i] == "--pitch-scale" and i + 1 < words.size():
				pitch_scale = float(words[i + 1])
			elif words[i] == "--home" and i + 1 < words.size():
				_pin_quality(float(words[i + 1]), -1.0)
			elif words[i] == "--away" and i + 1 < words.size():
				_pin_quality(-1.0, float(words[i + 1]))
			elif words[i] == "--small":
				small_sided = true
		break


## Fast-forwards toward the mark, a frame's worth at a time.
func _run_seek() -> void:
	var deadline := Time.get_ticks_msec() + SEEK_BUDGET_MS
	while _match.ctx.tick_index < _seek_target and not _match.finished:
		_prev.copy_from(_curr)
		_match.tick()
		_match.write_snapshot(_curr)
		_record_history()
		if Time.get_ticks_msec() >= deadline:
			return
	_seek_target = -1
	# Quarter speed for the run-up to a mark. A rewind is not a run-up: the owner
	# has just been watching at some speed and wants the same football back.
	if not _seek_is_rewind:
		_set_speed(1)
	elif _overlay != null and _pin_held >= 0:
		_overlay.pinned = _pin_held
	_seek_is_rewind = false
	_pin_held = -1
	# The camera put where the ball is rather than left chasing it across the
	# ninety seconds it has just skipped.
	_cut_to(_camera_shot)


## The command that re-simulates this moment. The flags matter: the compressed
## clock and a scaled pitch are different matches from the same seed.
func _replay_command(tick: int) -> String:
	# Always, because the replay's own default is the compressed clock and the
	# debug overlay's is real time: leaving it off is a different match.
	var extra := " --clock-rate %s" % clock_rate
	if _scenario != null:
		extra += " --scenario %s" % _scenario.name
	if pitch_scale != 1.0:
		extra += " --pitch-scale %s" % pitch_scale
	if small_sided:
		extra += " --small"
	# The squads are part of the match too: the same seed at another quality is
	# eleven other men, and the tick lands somewhere unrelated.
	var quality := _quality()
	if quality.x != 0.6 or quality.y != 0.6:
		extra += " --home %s --away %s" % [quality.x, quality.y]
	# And the world's clubs, when the match is one of the world's: the seed
	# alone gives a generated squad with other men in it.
	if world_seed >= 0:
		extra += " --world %d --home-club %d --away-club %d" % [world_seed, home_club, away_club]
	if minutes != 90.0:
		extra += " --minutes %s" % minutes
	return "./run.sh replay --seed %d --tick %d --around 6%s" % [match_seed, tick, extra]


func _draw_frame(alpha: float, sim_dt: float) -> void:
	_alpha = alpha
	var ball_pos := _prev.ball_pos.lerp(_curr.ball_pos, alpha)
	# The drawn ball is bigger than the simulated one, so on the ground its centre
	# has to sit at the drawn radius or it is buried to the waist in the grass --
	# above the grass at that point, which is not a constant. The floor used to be
	# BALL_DRAW_RADIUS flat, and it swallowed the whole of the ball's movement over
	# the bumps, since the undulation is smaller than the difference between the
	# drawn radius and the real one.
	ball_pos.y = maxf(ball_pos.y, _turf(ball_pos.x, ball_pos.z) + BALL_DRAW_RADIUS)
	ball_pos = _ball_in_hands(ball_pos)
	_spin_ball(sim_dt)
	_ball.transform = Transform3D(Basis(_ball_roll), ball_pos)

	var clock := _anim_clock()
	for i in mini(_players.size(), _curr.player_count):
		var node: Node3D = _players[i]
		if _curr.player_on_pitch[i] == 0:
			node.visible = false
			continue
		node.visible = true
		var pos := _prev.player_pos[i].lerp(_curr.player_pos[i], alpha)
		# Players stand on the grass too. The simulation has them on a plane,
		# because a player's height over the turf is not a thing it models, so the
		# view is where they meet the ground they are actually standing on.
		pos.y += _turf(pos.x, pos.z)
		node.position = pos
		# Orientation, yaw included, is `_pose`'s: it writes the whole rotation
		# in one go so a tilted pose cannot be built on a decomposed Euler.
		_pose(node, i, clock)

	_bob_crowd()
	_work_camera(ball_pos, _camera_dt())
	_drawn_tick = _curr.tick
	if _scoreboard != null:
		_scoreboard.show_snapshot(_curr)


## Simulated seconds between the frame drawn last and this one, however the
## picture got there: played, stepped a tick at a time, or stepped back through
## the recording.
##
## The camerawork is integrated over this — the pan is a decay toward the ball
## and the cut is on a timer — so it has to be the time the *picture* moved, not
## the time the match advanced. Given the played time alone the camera sat dead
## still while the ball jumped five seconds up the pitch, and stepping back
## through a move meant watching it from wherever the camera happened to be
## pointing when the picture stopped.
##
## Unsigned, because a camera catching up does not care which way through the
## recording the picture went, and capped, because a fast-forward hands this
## whole minutes at a time and a pan is only ever worth a second of decay.
func _camera_dt() -> float:
	return minf(float(absi(_curr.tick - _drawn_tick)) * SimConsts.DT, CAMERA_DT_MAX)


## Puts the ball in a thrower's hands while he is winding up.
##
## The simulation has no notion of a ball being held: it leaves it on the grass
## at the touchline and launches it from over the thrower's head at the moment of
## release (`SimSetPiece.THROW_HEIGHT`). That is the right model — a held ball is
## not a physical object the engine has to integrate — but drawn literally it is
## a man miming a throw over a ball lying at his feet.
##
## So the view carries it for him, over the half second the pose is winding up,
## and hands it back the instant it is moving. The two positions agree at the
## release, because the release height here and the one the sim launches from are
## the same number, so there is no jump to hide.
func _ball_in_hands(ball_pos: Vector3) -> Vector3:
	# Once it is moving it is the simulation's again, and this must not touch it.
	if _curr.ball_vel.length_squared() > 0.25:
		return ball_pos
	for i in mini(_players.size(), _curr.player_count):
		if _curr.player_anim[i] != SimConsts.Anim.THROW or _curr.player_on_pitch[i] == 0:
			continue
		var at := _prev.player_pos[i].lerp(_curr.player_pos[i], _alpha)
		if SimConsts.horizontal_length(at - ball_pos) > 3.0:
			continue
		var u: float = clampf(
			_anim_phase(_players[i], SimConsts.Anim.THROW) / float(ANIM_SECONDS[SimConsts.Anim.THROW]),
			0.0, 1.0
		)
		# The same two ramps the pose swings the arms on, so the ball travels with
		# the hands rather than on its own schedule.
		var back := smoothstep(0.0, THROW_RELEASE, u)
		var whip := smoothstep(THROW_RELEASE, minf(THROW_RELEASE + 0.2, 1.0), u)
		var facing := _facing(i)
		var forward := Vector3(cos(facing), 0.0, sin(facing))
		return at \
			+ Vector3(0.0, _turf(at.x, at.z) + lerpf(1.5, 2.1, back), 0.0) \
			+ forward * (lerpf(0.0, -0.35, back) + lerpf(0.0, 0.75, whip))
	return ball_pos


## Turns the ball by the simulation's own angular velocity.
##
## `SimBall` already keeps spin as a proper angular velocity vector and already
## snaps it to rolling without slipping whenever the ball is on the grass — a
## ball running along +X carries spin (0, 0, -v/r). So the roll matching the
## movement is not something the view has to derive or fake: it is what the sim
## says, integrated over the time the sim actually advanced.
##
## What the view used to do was apply two of the three components, at half rate,
## against a fixed step. That is a ball turning at half the speed it travels,
## never turning at all when it moves along Z, and running to its own clock
## rather than the match's. All three are visible as skid.
##
## The one correction the drawn ball does need is for its own size. Rolling
## without slipping is a statement about the surface at the contact point, and
## the surface being watched is the drawn one: a sphere 1.7 times too big,
## turning at the real ball's rate, has its underside going backwards over the
## grass. So the rate comes down by the same factor it was inflated by.
func _spin_ball(sim_dt: float) -> void:
	if sim_dt <= 0.0:
		return
	var spin := _curr.ball_spin / BALL_VISUAL_SCALE
	var rate := spin.length()
	if rate < 1e-4:
		return
	# Pre-multiplied: the spin is an angular velocity in world axes, not in the
	# ball's own.
	_ball_roll = (Quaternion(spin / rate, rate * sim_dt) * _ball_roll).normalized()


## How long each one-shot pose runs on screen.
##
## The simulation holds its own anim for a comparable time (`SimPlayer.play_anim`)
## but the snapshot carries only *which* anim is current, never how far through
## it is. The view times it instead, the same way it derives turn rate — so the
## sim is not asked for anything it does not already need for itself.
const ANIM_SECONDS := {
	SimConsts.Anim.KICK_LIGHT: 0.28,
	SimConsts.Anim.KICK_HARD: 0.36,
	SimConsts.Anim.HEADER: 0.5,
	# As long as the ball takes to drop from his chest to his feet, near enough:
	# the pose is the whole of that, not the instant of the contact.
	SimConsts.Anim.CHEST: 0.5,
	SimConsts.Anim.SLIDE: 0.7,
	SimConsts.Anim.FALL: 0.7,
	SimConsts.Anim.GET_UP: 0.6,
	SimConsts.Anim.DIVE_LEFT: 0.9,
	SimConsts.Anim.DIVE_RIGHT: 0.9,
	SimConsts.Anim.KEEPER_CATCH: 0.6,
	# The only one of these that spans two events rather than one. The wind-up
	# starts when the thrower picks the ball up and the release comes half a
	# second later (`SimSetPiece.THROW_WINDUP`), so the arc has to be long enough
	# to hold both and still have a follow-through left over.
	SimConsts.Anim.THROW: 0.9,
}
## Where in that arc the ball actually leaves his hands, matching the sim's
## wind-up. Everything before it is holding the ball up; everything after is the
## whip and the follow-through.
const THROW_RELEASE := 0.55


## No root motion: the pose is driven entirely by simulated velocity and by the
## anim state the sim has already published.
##
## The locomotion cycle is the base — six joints move rather than two, because a
## figure this simple only reads as alive if the arms swing against the legs —
## and a named anim then overwrites whatever it needs on top. Everything the sim
## can say (`SimConsts.Anim`) has a pose here: without them a keeper never
## dives, a fouled player never falls over, and a goal is celebrated by twenty-two
## people continuing to jog, which is the opposite of §9.5's "big, readable body
## language is how the player reads the match without reading numbers".
func _pose(node: Node3D, index: int, clock: float) -> void:
	var anim: int = _curr.player_anim[index]
	var t: float = _quantise(_anim_phase(node, anim))
	var span: float = ANIM_SECONDS.get(anim, 1.0)
	var u: float = clampf(t / span, 0.0, 1.0)

	_root(node, index, 0.0, 0.0)
	node.scale = Vector3.ONE
	_pose_run(node, index, clock)

	if not pose_anim(node, anim, u, t):
		match anim:
			SimConsts.Anim.SLIDE:
				_pose_slide(node, index, u)
			SimConsts.Anim.FALL:
				_pose_fall(node, index, u)
			SimConsts.Anim.GET_UP:
				_pose_fall(node, index, 1.0 - u)
			SimConsts.Anim.DIVE_LEFT:
				_pose_dive(node, index, u, -1.0)
			SimConsts.Anim.DIVE_RIGHT:
				_pose_dive(node, index, u, 1.0)
			_:
				pass

	SimCharacterModel.set_expression(
		node, SimAppearance.face_for_anim(anim, _curr.player_stamina[index])
	)


## The half of the anim table whose shape is a function of the figure and the
## phase alone, and nothing else. Returns whether it handled the state.
##
## Split out so `parade` can play the **same** poses rather than a second set
## written to look like them: a figure judged standing still is half judged, and
## two tables would drift the first time one of them was tuned.
##
## What stays behind is what genuinely needs the match. A slide, a fall and a
## keeper's dive are posed off the player's own heading, and a parade has none.
static func pose_anim(node: Node3D, anim: int, u: float, t: float) -> bool:
	match anim:
		SimConsts.Anim.KICK_LIGHT:
			_pose_kick(node, u, 1.0)
		SimConsts.Anim.KICK_HARD:
			_pose_kick(node, u, 1.45)
		SimConsts.Anim.HEADER:
			_pose_header(node, u)
		SimConsts.Anim.CELEBRATE:
			_pose_celebrate(node, t)
		SimConsts.Anim.DEJECTED:
			_pose_dejected(node, t)
		SimConsts.Anim.EXHAUSTED:
			_pose_exhausted(node, t)
		SimConsts.Anim.KEEPER_CATCH:
			_pose_catch(node, u)
		SimConsts.Anim.THROW:
			_pose_throw(node, u)
		SimConsts.Anim.KEEPER_HOLD:
			_pose_keeper_hold(node, t)
		SimConsts.Anim.HOLD:
			_pose_hold(node, t)
		SimConsts.Anim.CHEST:
			_pose_chest(node, u)
		_:
			return false
	return true


## The gait is geared to the ground, not to the clock.
##
## The run cycle used to advance by a fixed amount every stepped frame, so every
## player took 3.3 steps a second whatever their speed and only the size of the
## swing changed. Two things follow from that, and both are why a match read as
## twenty-two people walking.
##
## The first is that the legs never keep up with the pitch. Foot travel per step
## is about `2 * leg * sin(hip swing)`, so at the old amplitudes the gait was
## worth 1.4 m/s at a jog and 4.5 m/s at a sprint, against ground speeds of 2 and
## 7.5. Everyone skated forward, hardest exactly when they were running hardest.
##
## The second is that cadence is most of what says *how fast* — a sprint is
## visibly quicker feet, not just a longer stride. With one cadence for every
## speed, the only thing separating a shape-holding jog from a counter-attack was
## limb amplitude, which at match framing is a few pixels.
##
## So the phase advances by the distance actually covered, divided by the step
## length the current swing implies. Amplitude saturates and distance does not,
## which makes the cadence climb on its own: about 1.0 Hz at walking pace and
## 3.1 Hz flat out. Standing still, amplitude is zero and the cycle stops rather
## than freezing mid-stride.
const GAIT_SATURATION_SPEED := 7.0
const GAIT_SWING_MAX := 0.95
## Below 1 the swing fills out quickly and then saturates, so the low end of the
## speed range is spent lengthening the stride and the top end quickening it.
const GAIT_SWING_CURVE := 0.55
## Ceiling on the cycle, in Hz. It exists because a drawn frame rate cannot show
## a cycle faster than a few times it without the legs aliasing into a blur or a
## reversal; at 3.1 a sprinter's feet are quick and still legible, and the
## stepped mode drops it to the quarter of its frame rate the old value was.
const GAIT_MAX_CYCLE_HZ := 3.1


func _max_cycle_hz() -> float:
	if _step_fps <= 0.0:
		return GAIT_MAX_CYCLE_HZ
	return minf(GAIT_MAX_CYCLE_HZ, _step_fps * 0.24)


## Advances this player's gait phase over however much animation time has passed.
##
## Kept per node rather than derived from the clock, because a phase computed
## from `elapsed * frequency` jumps the moment the frequency changes, and here
## the frequency changes every time the player speeds up or slows down.
func _gait_phase(node: Node3D, index: int, clock: float, speed: float, amplitude: float) -> float:
	var phase: float = node.get_meta("gait_phase", -1.0)
	if phase < 0.0:
		# Staggered, so a team does not march in lockstep.
		phase = fmod(float(index) * 1.29, TAU)
		node.set_meta("gait_clock", clock)
		node.set_meta("gait_phase", phase)
		return phase
	var dt: float = clock - float(node.get_meta("gait_clock", clock))
	if dt <= 0.0:
		return phase
	node.set_meta("gait_clock", clock)
	var step_length: float = 2.0 * _leg_length(node) * sin(amplitude)
	if step_length > 0.01:
		# Two steps to the cycle, so a cycle covers twice the step length.
		var cycle_hz: float = minf(speed / (2.0 * step_length), _max_cycle_hz())
		phase = fposmod(phase + TAU * cycle_hz * dt, TAU)
		node.set_meta("gait_phase", phase)
	return phase


## Hip height, which is the length of the leg the gait is geared to. Cached off
## the node: it is fixed at build time and varies per player with their height.
static func _leg_length(node: Node3D) -> float:
	if not node.has_meta("leg_length"):
		var hip := _joint(node, "HipL")
		node.set_meta("leg_length", hip.position.y if hip != null else 0.83)
	return node.get_meta("leg_length")


## What each leg does over one cycle, and why the shape of it is what it is.
##
## The hip is a pendulum: `sin(phase)`, positive swinging the leg *back*. So
## phase 0 is mid-stance with the leg underneath, phase π/2 is toe-off with it
## fully trailing, phase π is mid-swing with it passing under the body again on
## the way through, and phase 3π/2 is touchdown with it reaching forward.
##
## Everything else hangs off that timing. The old cycle had the hips and nothing
## else — the knee bent a little, but on the wrong half, and the boot was welded
## flat to the shin — so each leg swung through as a straight rod with the foot
## grazing the turf the whole way. That is the shuffle: no part of the figure
## ever leaves the ground, so the legs read as pushed along it rather than
## carrying the body over it.
##
## A run is the knee, not the hip. The knee folds hard just *after* toe-off,
## while the thigh is still trailing — heel toward the backside, foot lifted
## clear — and then extends again as the leg reaches forward, so it is nearly
## straight by the time it plants. Hence the lead: the flexion peak sits a little
## before mid-swing rather than on it. A second, much smaller bend at mid-stance
## is the leg taking the body's weight, which is what stops the stride looking
## stilted.
##
## The ankle is the other half of leaving the ground. It points hard at toe-off,
## which is the push, and comes up through the swing so the boot clears the grass
## and lands toes-first-ish rather than dragging.
const GAIT_KNEE_SWING := 2.1
const GAIT_KNEE_LEAD := 0.45
const GAIT_KNEE_STANCE := 0.5
const GAIT_ANKLE_PUSH := 0.75
const GAIT_ANKLE_LIFT := 0.45
## How far the whole figure rides up between footfalls. Higher at mid-swing on
## each side and lowest at mid-stance, so it is twice a cycle — the second thing
## after the knees that separates running from gliding.
const GAIT_BOB := 0.075
## And how far it sinks over the planted foot. This is not decoration: bending
## the stance knee lifts that foot off the grass by about the same three
## centimetres, so without the dip the figure runs on tiptoe at exactly the
## moment it should be carrying its own weight.
const GAIT_DIP := 0.035


## One leg, `tag` being "L" or "R" and `phase` already offset for the side.
static func _pose_leg(node: Node3D, tag: String, phase: float, amplitude: float) -> void:
	var lift: float = maxf(-cos(phase + GAIT_KNEE_LEAD), 0.0)
	var planted: float = maxf(cos(phase), 0.0)
	var knee: float = amplitude * (
		GAIT_KNEE_SWING * pow(lift, 0.75) + GAIT_KNEE_STANCE * planted * planted
	)
	# Positive points the toe down, negative lifts it.
	var ankle: float = amplitude * (
		GAIT_ANKLE_PUSH * pow(maxf(sin(phase), 0.0), 2.0)
		- GAIT_ANKLE_LIFT * maxf(-sin(phase), 0.0)
	)
	_rotate(node, "Hip" + tag, sin(phase) * amplitude)
	_rotate(node, "Knee" + tag, knee)
	_rotate(node, "Ankle" + tag, ankle)


func _pose_run(node: Node3D, index: int, clock: float) -> void:
	var speed: float = _velocity(index).length()
	var amplitude: float = gait_amplitude(speed)
	var phase := _gait_phase(node, index, clock, speed, amplitude)
	pose_gait(node, speed, phase, clampf(_turn_rate(node, index, clock), -1.0, 1.0))


## How far the hips swing at this speed, and therefore how long a step is. Grows
## fast at walking pace and saturates, which is what makes the cadence climb.
static func gait_amplitude(speed: float) -> float:
	return GAIT_SWING_MAX * pow(
		clampf(speed / GAIT_SATURATION_SPEED, 0.0, 1.0), GAIT_SWING_CURVE)


## The run, as a shape: everything about it that is a function of the figure and
## the phase, and nothing that is a function of the match.
##
## Split out so the parade can run the **same** gait rather than a second one
## written to look like it. What the match keeps is where the phase comes from
## -- a real speed over a real leg length, quantised to the sim's step -- and
## that is a clock, not a pose.
static func pose_gait(node: Node3D, speed: float, phase: float, turn: float) -> void:
	var effort: float = clampf(speed / GAIT_SATURATION_SPEED, 0.0, 1.0)
	var amplitude: float = gait_amplitude(speed)
	var swing := sin(phase) * amplitude
	var opposite := -swing

	_pose_leg(node, "L", phase, amplitude)
	_pose_leg(node, "R", phase + PI, amplitude)
	# Arms swing against the legs — left arm forward with the right leg — and
	# drive harder the faster the player runs. The elbow closes up with effort:
	# a sprinter carries his hands high and his arms folded, a jogger does not.
	_rotate(node, "ShoulderL", opposite * 0.78)
	_rotate(node, "ShoulderR", swing * 0.78)
	# Both elbows carry the same bend: the two arms are half a cycle apart, so
	# the size of the swing is the same on each side however it is measured.
	var elbow: float = -0.3 - effort * 0.5 - absf(swing) * 0.35
	_rotate(node, "ElbowL", elbow)
	_rotate(node, "ElbowR", elbow)

	# Lean into the run, and bank into a turn. Positive x pitches the torso
	# forward: this was negative, so runners leaned back as they accelerated.
	_lean(node, effort * 0.22, turn * 0.25)
	var spine := _joint(node, "Spine")
	if spine != null:
		spine.position.y = _spine_base(node) + absf(swing) * 0.02
	var neck := _joint(node, "Neck")
	if neck != null:
		# The head stays up while the torso pitches, so the face keeps facing
		# where the player is going.
		neck.rotation = Vector3(-effort * 0.1, 0.0, 0.0)
	# The whole figure rides up and down as it runs: up between footfalls, down
	# over the planted foot, twice a cycle.
	var planted := cos(phase)
	node.position.y = absf(swing) * GAIT_BOB - amplitude * planted * planted * GAIT_DIP


## The follow-through, not the strike: the sim plays this *after* the ball has
## gone, so the leg starts extended and relaxes out of it.
static func _pose_kick(node: Node3D, u: float, force: float) -> void:
	var swing: float = lerpf(1.0, 0.2, u) * force
	_rotate(node, "HipR", -1.15 * swing)
	_rotate(node, "KneeR", 0.12)
	_rotate(node, "HipL", 0.3 * swing)
	_rotate(node, "KneeL", 0.35 * swing)
	_rotate(node, "ShoulderL", -0.8 * swing)
	_rotate(node, "ShoulderR", 0.55 * swing)
	_rotate(node, "ElbowL", -0.3)
	_rotate(node, "ElbowR", -0.3)
	_lean(node, -0.32 * swing)
	# Stretched through the strike, settling back. §9.5 asks for heavy squash and
	# stretch on kicks, and at ten frames a second it needs to be heavy to read
	# at all — it is on screen for three frames.
	_squash(node, -0.16 * swing)


## Where in the header's arc his feet are back on the grass. The rest of the span
## is the landing: knees still folded, arms still out, coming upright.
const HEADER_LAND := 0.7
## The most a footballer leaves the ground by. Half a metre is a good leap at a
## cross, and the figure's own head is already 1.7 m up, so this is a ball at 2.2
## — about as high as anything gets headed.
const HEADER_LIFT_MAX := 0.5


## Airborne, arched, arms wide. What sells a header is not the head — it is the
## legs leaving the ground and tucking, so the figure is unmistakably not
## standing.
##
## The contact is the *first* frame of this pose, not the middle of it: the sim
## plays the anim after the ball has already gone, the same as it does for a
## kick. So the leap is at its apex when the pose starts and falls away from
## there. It used to be `sin(u * PI)` — the man stood flat on the grass while the
## ball changed direction over his head, then jumped a fifth of a second later
## under a ball that had already left, and was set back down before he landed.
## That is the header that looks like it bounces above the head.
##
## And how far he leaves the ground is the ball's business, not a constant. A
## fixed 0.55 m is a full leap at a ball on his forehead and half a leap at one
## over it; both read as the head missing.
static func _pose_header(node: Node3D, u: float) -> void:
	var fall: float = clampf(u / HEADER_LAND, 0.0, 1.0)
	# A body comes down like a body: slowly at first, then all at once.
	var arc := 1.0 - fall * fall
	node.position.y += arc * _header_lift(node)
	_lean(node, -0.3 * arc)
	_rotate(node, "Neck", 0.4 * arc)
	# Arms thrown wide and back, mirrored.
	_rotate(node, "ShoulderL", 0.9 * arc, -1.35 * arc)
	_rotate(node, "ShoulderR", 0.9 * arc, 1.35 * arc)
	_rotate(node, "ElbowL", -0.4)
	_rotate(node, "ElbowR", -0.4)
	# One leg tucked under, the other trailing.
	_rotate(node, "HipL", 0.75 * arc)
	_rotate(node, "HipR", -0.3 * arc)
	_rotate(node, "KneeL", 1.3 * arc)
	_rotate(node, "KneeR", 0.35 * arc)
	# Squashes on landing rather than in the air.
	_squash(node, 0.3 * maxf(u - HEADER_LAND, 0.0) / maxf(1.0 - HEADER_LAND, 0.01))


## How high he has to get to meet this particular ball: the gap between it and
## the top of his own head, capped at a leap a footballer can actually produce.
static func _header_lift(node: Node3D) -> float:
	var contact: float = float(node.get_meta("contact_y", 0.0))
	if contact < 0.01:
		# No ball in the scene — the pose sheet. Show the leap it was drawn for.
		return HEADER_LIFT_MAX * 0.6
	return clampf(contact - _head_height(node), 0.0, HEADER_LIFT_MAX)


## Where this figure's head sits when it is standing — its centre, which is where
## a ball meets a forehead. Read off the joints it was built from, and cached: it
## never changes, and it varies with height the way the leg length does.
static func _head_height(node: Node3D) -> float:
	if not node.has_meta("head_height"):
		var neck := _joint(node, "Neck")
		var head := _joint(node, "Head")
		var y := 1.7
		if neck != null and head != null:
			y = _spine_base(node) + neck.position.y + head.position.y
		node.set_meta("head_height", y)
	return node.get_meta("head_height")


## Taking it down: chest thrown out and leaning away from the ball, arms wide of
## it, then upright with the eyes following it to the floor.
##
## The lean is the whole pose, and it is what tells a viewer this is not a
## header. A man cushioning a ball on his chest arches *back* — he gives with it,
## because a chest held square bounces it straight off — and his arms go out wide
## to keep them out of the way, which is also the shape that keeps him onside of
## a handball. Nothing leaves the ground: that is the other half of the read.
##
## Like the header and the kick, contact is the first frame. What follows is the
## half-second the ball spends dropping to his feet, and he spends it coming
## upright and looking down at it.
static func _pose_chest(node: Node3D, u: float) -> void:
	var give := 1.0 - smoothstep(0.0, 0.85, u)
	_lean(node, -0.42 * give)
	# Chin up at the ball on contact, down at it by the time it lands.
	_rotate(node, "Neck", lerpf(-0.3, 0.45, smoothstep(0.0, 1.0, u)))
	# Arms out and back, low: away from the ball rather than up at it.
	_rotate(node, "ShoulderL", -0.35 * give, -0.95 * give)
	_rotate(node, "ShoulderR", -0.35 * give, 0.95 * give)
	_rotate(node, "ElbowL", -0.45 * give)
	_rotate(node, "ElbowR", -0.45 * give)
	# Knees soft, weight settling back onto the standing leg. He absorbs the ball
	# with the whole body, so the whole body dips a little.
	_rotate(node, "HipL", 0.28 * give)
	_rotate(node, "KneeL", 0.4 * give)
	_rotate(node, "KneeR", 0.3 * give)
	node.position.y -= 0.04 * give


## Feet first, body reclined behind them. The root pivot is at the feet, so a
## backward rotation drops the whole figure to the turf with the legs leading.
func _pose_slide(node: Node3D, index: int, u: float) -> void:
	var down: float = minf(u * 3.0, 1.0)
	_root(node, index, -0.95 * down, 0.0)
	_rotate(node, "HipL", -0.85 * down)
	_rotate(node, "HipR", -0.35 * down)
	_rotate(node, "KneeL", 0.1)
	_rotate(node, "KneeR", 0.55 * down)
	_rotate(node, "ShoulderL", 0.9 * down)
	_rotate(node, "ShoulderR", 0.7 * down)
	_rotate(node, "ElbowL", -0.2)
	_rotate(node, "ElbowR", -0.2)
	_lean(node, 0.25 * down)


## Topples forward about the feet, accelerating the way a falling body does. A
## linear ramp reads as lying down on purpose.
func _pose_fall(node: Node3D, index: int, u: float) -> void:
	_root(node, index, 1.5 * u * u, 0.0)
	# Arms go out to break the fall, then flail.
	_rotate(node, "ShoulderL", -1.3 * u, -0.7 * u)
	_rotate(node, "ShoulderR", -1.1 * u, 0.7 * u)
	_rotate(node, "ElbowL", -0.15)
	_rotate(node, "ElbowR", -0.15)
	_rotate(node, "HipL", 0.4 * u)
	_rotate(node, "HipR", 0.25 * u)
	_rotate(node, "KneeL", 0.7 * u)
	_rotate(node, "KneeR", 0.5 * u)
	_squash(node, 0.35 * maxf(u - 0.8, 0.0) * 5.0)


## Both hands over the head, arched back, then whipped forward over the top.
##
## The reason a throw-in needs its own pose rather than borrowing the kick is
## that the whole act happens above the shoulders, and it is the only thing in
## the match that does. Two hands and a symmetrical arch is what a viewer reads
## as "throw-in" from forty metres away, before they have registered that the
## ball is at the touchline.
##
## Same lesson as the celebration: arms are about as long as
## the head is wide, so straight up is inside the head's silhouette and reads as
## nothing. The wind-up leans them back past vertical and the release carries
## them through to horizontal, which puts the hands outside the head at both ends
## of the arc and gives the whip something to travel across.
static func _pose_throw(node: Node3D, u: float) -> void:
	# Wind-up on a slow ease, release on a fast one: the arms go back over about
	# half a second and come through in a fifth of it.
	var back := smoothstep(0.0, THROW_RELEASE, u)
	var whip := smoothstep(THROW_RELEASE, minf(THROW_RELEASE + 0.2, 1.0), u)
	# Straight up and behind at the top of the wind-up (a shade under PI), through
	# vertical and out to shoulder height in front.
	# 2.5 rad is about fifty degrees back from vertical, which is what puts the
	# hands outside the head rather than inside its silhouette -- the same
	# constraint the celebration ran into, and the reason straight up is wrong for
	# a figure whose head is wider than its arms are long.
	var arms: float = lerpf(0.0, 2.5, back) + lerpf(0.0, 1.95, whip)
	_rotate(node, "ShoulderL", arms, -0.22)
	_rotate(node, "ShoulderR", arms, 0.22)
	# Elbows cocked at the top, straightening through the release. A throw with
	# straight arms all the way is a man surrendering.
	var cocked: float = lerpf(0.0, -0.85, back) * (1.0 - whip)
	_rotate(node, "ElbowL", cocked)
	_rotate(node, "ElbowR", cocked)
	_rotate(node, "Neck", -0.25 * back + 0.3 * whip)
	# Arched back, then folded over the line. This is where most of the power
	# reads from -- the arms are a small part of the silhouette and the torso is
	# most of it.
	_lean(node, -0.34 * back + 0.85 * whip)
	# Both feet stay on the ground, one dragging behind, which is the rule and
	# also what stops it reading as a goal celebration.
	_rotate(node, "HipL", -0.3 * back - 0.1 * whip)
	_rotate(node, "HipR", 0.22 * back + 0.3 * whip)
	_rotate(node, "KneeL", 0.25 * back)
	_rotate(node, "KneeR", 0.4 * back + 0.3 * whip)
	_squash(node, -0.1 * back + 0.16 * whip)


static func _pose_celebrate(node: Node3D, t: float) -> void:
	# Up and *forward*, in a slight V. Two things rule out the obvious pose. The
	# arms reach about 1.7 m and the head tops out at 1.95 m, so straight
	# overhead puts them inside the head's silhouette; and a sideways spread
	# happens across the viewing axis, so from a camera watching play in profile
	# it foreshortens to a stub at the chest. Forward and up is the one direction
	# that clears the head and still reads from the touchline.
	_rotate(node, "ShoulderL", 3.55, -0.4)
	_rotate(node, "ShoulderR", 3.55, 0.4)
	_rotate(node, "ElbowL", 0.15)
	_rotate(node, "ElbowR", 0.15)
	var hop := absf(sin(t * 7.0))
	node.position.y = hop * 0.26
	_rotate(node, "HipL", -0.15 * hop)
	_rotate(node, "HipR", -0.15 * hop)
	_rotate(node, "KneeL", 0.5 * (1.0 - hop))
	_rotate(node, "KneeR", 0.5 * (1.0 - hop))
	_lean(node, -0.18)
	_squash(node, 0.22 * (1.0 - hop))


static func _pose_dejected(node: Node3D, t: float) -> void:
	_lean(node, 0.42)
	_rotate(node, "Neck", 0.4)
	# Arms hang. Nothing swings, which is the whole point of the pose.
	_rotate(node, "ShoulderL", -0.05 + sin(t * 1.4) * 0.05)
	_rotate(node, "ShoulderR", -0.05 - sin(t * 1.4) * 0.05)
	_rotate(node, "ElbowL", -0.12)
	_rotate(node, "ElbowR", -0.12)
	_rotate(node, "HipL", 0.0)
	_rotate(node, "HipR", 0.0)
	_rotate(node, "KneeL", 0.08)
	_rotate(node, "KneeR", 0.08)
	# Feet flat. The gait runs underneath every pose, so a state that means
	# "stopped" has to put the ankles back or it trudges on its toes.
	_rotate(node, "AnkleL", 0.0)
	_rotate(node, "AnkleR", 0.0)
	node.position.y = 0.0


## Hands on knees, heaving. §9.5 wants exhaustion visible in the body before it
## is visible anywhere else, and this is the pose that does it.
static func _pose_exhausted(node: Node3D, t: float) -> void:
	var heave := sin(t * 3.2) * 0.07
	_lean(node, 0.85 + heave)
	_rotate(node, "Neck", -0.45)
	_rotate(node, "ShoulderL", -0.85)
	_rotate(node, "ShoulderR", -0.85)
	_rotate(node, "ElbowL", -0.25)
	_rotate(node, "ElbowR", -0.25)
	_rotate(node, "HipL", -0.2)
	_rotate(node, "HipR", -0.2)
	_rotate(node, "KneeL", 0.4)
	_rotate(node, "KneeR", 0.4)
	_rotate(node, "AnkleL", 0.0)
	_rotate(node, "AnkleR", 0.0)
	node.position.y = -0.02
	_squash(node, 0.05 + heave)


## The keeper dives to a *world* side — `SimKeeper` picks LEFT or RIGHT from the
## ball's z against his own — so which way the body rolls depends on which way he
## is facing. Resolving it against the facing is what stops the away keeper
## diving over the wrong shoulder.
func _pose_dive(node: Node3D, index: int, u: float, dir_z: float) -> void:
	var roll: float = dir_z * cos(_facing(index))
	var angle: float = minf(u * 3.5, 1.0) * 1.35
	_root(node, index, 0.0, roll * angle)
	node.position.y += sin(u * PI) * 0.5
	# Both arms reach past the head, along the line of the dive, fanned enough to
	# clear its silhouette.
	_rotate(node, "ShoulderL", 2.6, -0.5)
	_rotate(node, "ShoulderR", 2.6, 0.5)
	_rotate(node, "ElbowL", 0.05)
	_rotate(node, "ElbowR", 0.05)
	_rotate(node, "HipL", -0.1)
	_rotate(node, "HipR", 0.1)
	_rotate(node, "KneeL", 0.25)
	_rotate(node, "KneeR", 0.15)
	_lean(node, -0.1)
	_squash(node, -0.12 * sin(u * PI))


## The ball is his. Two hands cupped at the chest, walking out with it, head up
## looking for someone.
##
## Held on a clock rather than an arc, because unlike every other keeper pose
## this one lasts seconds rather than tenths, and a frozen figure over that long
## reads as the game having stopped. The sim puts the ball at
## `SimKeeper.HOLD_HEIGHT`, `SimKeeper.HOLD_REACH` in front of him, and these
## angles are solved to put the hands there: upper arms hanging forward and down
## to an elbow tucked at the ribs, forearms up and out to hands that meet at the
## front of the chest. The previous pair (-1.35 / -1.15) reached a hand about
## 0.24 m too high, which with the ball on his own centre line meant hands
## cupping nothing above a ball inside his chest.
static func _pose_keeper_hold(node: Node3D, t: float) -> void:
	_rotate(node, "ShoulderL", -0.63, 0.34)
	_rotate(node, "ShoulderR", -0.63, -0.34)
	_rotate(node, "ElbowL", -1.3)
	_rotate(node, "ElbowR", -1.3)
	# Scanning: the head turns one way and back while he looks for an option. The
	# only moving part, and it is what says he is thinking rather than frozen.
	_rotate(node, "Neck", -0.12, sin(t * 1.6) * 0.35)
	_lean(node, 0.1)


## Seconds the foot takes to come down on the ball. Short: the sim plays this
## after the touch, so the shape wants to be there almost at once, and anything
## slower reads as him lifting his foot for no reason and finding the ball later.
const HOLD_PLANT_SECONDS := 0.12
## Where the sole ends up, and the angles are solved for it rather than picked.
## The rig's leg is two 0.41 m segments from a hip at `_leg_length`, and the
## joint chain sums: the shin's angle off vertical is hip + knee, the boot's is
## hip + knee + ankle. Putting the ankle 0.5 m in front of the standing foot and
## 0.22 m up — a ball's height, an easy stride ahead — needs a 0.55 rad knee and
## a thigh 0.96 rad forward. The ankle then takes 0.32: 0.41 lays the sole flat,
## and a little under that rides the toe up over the ball instead of into it.
const HOLD_HIP := -0.96
const HOLD_KNEE := 0.55
const HOLD_ANKLE := 0.32


## The foot on the ball. He has it, he is not going anywhere with it, and he is
## looking for someone to give it to.
##
## Driven by the clock rather than an arc, like the keeper's hold and unlike
## every other outfield pose. A hold is a shape held for as long as the sim says
## so, not a strike with a follow-through: `SimTouch.settle` renews the anim on
## every touch, so back-to-back holds keep one continuous pose rather than
## restarting an arc that would never finish. The only wind-up is the foot coming
## down.
##
## The standing leg does the work — knee bent, weight on it, hips back over it,
## chest up. Both arms come out to balance against a foot that is off the ground.
## The one thing that keeps moving is the head: he is scanning, and a figure
## standing on a ball with nothing moving reads as the match having paused.
static func _pose_hold(node: Node3D, t: float) -> void:
	var plant: float = smoothstep(0.0, HOLD_PLANT_SECONDS, t)
	# The ball rolls a little back and forth under the sole. Small, slow, and the
	# reason the foot does not look welded to it.
	var roll: float = sin(t * 2.2) * 0.05 * plant

	_rotate(node, "HipR", (HOLD_HIP - roll) * plant)
	_rotate(node, "KneeR", (HOLD_KNEE + roll) * plant)
	_rotate(node, "AnkleR", HOLD_ANKLE * plant)
	# Standing leg: bent under the weight, and the whole figure drops with it.
	_rotate(node, "HipL", 0.1 * plant)
	_rotate(node, "KneeL", 0.22 * plant)
	_rotate(node, "AnkleL", 0.0)
	node.position.y -= 0.03 * plant

	_rotate(node, "ShoulderL", -0.2 * plant, -0.6 * plant)
	_rotate(node, "ShoulderR", 0.3 * plant, 0.45 * plant)
	_rotate(node, "ElbowL", -0.35 * plant)
	_rotate(node, "ElbowR", -0.35 * plant)
	# Sat back over the standing foot, head up over the top of it.
	_lean(node, -0.1 * plant)
	_rotate(node, "Neck", -0.12 * plant, sin(t * 1.4) * 0.3 * plant)


static func _pose_catch(node: Node3D, u: float) -> void:
	var arc := sin(u * PI)
	node.position.y += arc * 0.12
	# Arms forward and folded, gathering the ball in.
	_rotate(node, "ShoulderL", -1.75, 0.3)
	_rotate(node, "ShoulderR", -1.75, -0.3)
	_rotate(node, "ElbowL", -0.85)
	_rotate(node, "ElbowR", -0.85)
	_lean(node, 0.25)
	_rotate(node, "KneeL", 0.3 * arc)
	_rotate(node, "KneeR", 0.3 * arc)


# --- Pose primitives ---------------------------------------------------------


## The clock the pose layer runs on, in seconds. Continuous unless `--step-fps`
## asked for stepping, in which case it advances in jumps and every pose that
## reads it steps with it.
func _anim_clock() -> float:
	return _quantise(_elapsed)


func _quantise(t: float) -> float:
	if _step_fps <= 0.0:
		return t
	return floorf(t * _step_fps) / _step_fps


## A player's facing, interpolated between the two most recent snapshots.
##
## The sim publishes it once a tick and the view draws several times a tick, so
## reading the newest snapshot directly makes the yaw of every figure — and with
## it the direction its legs swing in — advance in sixtieths while its position
## slides smoothly between them. It is the same interpolation the position gets,
## on the shortest way round the circle.
func _facing(index: int) -> float:
	return lerp_angle(_prev.player_facing[index], _curr.player_facing[index], _alpha)


## Likewise velocity, which sets how hard the gait works. Interpolated for the
## same reason: it is read every frame and written every tick.
func _velocity(index: int) -> Vector3:
	return _prev.player_vel[index].lerp(_curr.player_vel[index], _alpha)


## Seconds since this player's current anim began. Presentation times it; the
## snapshot carries the state, not the clock.
func _anim_phase(node: Node3D, anim: int) -> float:
	if int(node.get_meta("anim", -1)) != anim:
		node.set_meta("anim", anim)
		node.set_meta("anim_started", _elapsed)
		# Where the ball was when the act began, which for a one-shot is where it
		# was struck. The header is the pose that needs it: how far a man has to
		# leave the ground is the difference between the ball's height and his own
		# head's, and it is the difference between a leap at a cross and a nod at
		# one that was already on his forehead.
		node.set_meta("contact_y", _curr.ball_pos.y)
	return _elapsed - float(node.get_meta("anim_started", _elapsed))


## Swings a joint: `angle` about its own pitch axis, `lateral` away from the body.
##
## Always writes the whole rotation, never one component. `rotation.x = a` is a
## read-modify-write, and Godot returns Euler angles decomposed back out of the
## basis with the pitch folded into [-90°, 90°]. Any angle past that comes back
## as a different triple — arms raised overhead read back as (0.29, π, π) — so
## the *next* component write builds a wholly different orientation from it. The
## symptom was a goal celebrated with the arms hanging down.
static func _rotate(node: Node3D, joint: String, angle: float, lateral := 0.0) -> void:
	var j := _joint(node, joint)
	if j != null:
		j.rotation = Vector3(angle, 0.0, lateral)


## Pitches the torso. Positive is forward, over the ball.
static func _lean(node: Node3D, angle: float, bank := 0.0) -> void:
	var spine := _joint(node, "Spine")
	if spine != null:
		spine.rotation = Vector3(angle, 0.0, bank)


## The whole figure's orientation, yaw included, for the same reason.
func _root(node: Node3D, index: int, pitch: float, roll: float) -> void:
	node.rotation = Vector3(pitch, -_facing(index) + PI * 0.5, roll)


## Positive squashes, negative stretches, volume roughly held.
static func _squash(node: Node3D, amount: float) -> void:
	var a: float = clampf(amount, -0.4, 0.4)
	node.scale = Vector3(1.0 + a * 0.45, 1.0 - a, 1.0 + a * 0.45)


## Joint lookups are cached per player. `find_child` walks the subtree, and at
## twenty-two players and a dozen joints a frame that is a search per joint per
## frame for a hierarchy that never changes.
static func _joint(node: Node3D, joint: String) -> Node3D:
	var cache: Dictionary = node.get_meta("joints", {})
	if cache.is_empty():
		node.set_meta("joints", cache)
	if not cache.has(joint):
		cache[joint] = node.find_child(joint, true, false) as Node3D
	return cache[joint]


## Where a player's spine sits when standing, cached off the node so the bob
## does not accumulate.
static func _spine_base(node: Node3D) -> float:
	if not node.has_meta("spine_y"):
		# **`_joint`, not `get_node_or_null`.** A direct-child lookup finds the
		# procedural figure's spine and misses a built model's, and the miss is
		# silent: it falls back to zero, which is a plausible height for a node
		# to sit at. Every man in the match then had his torso planted on his
		# hips and no legs to speak of, while the parade -- which caches this
		# meta from its own stand pose first -- looked perfectly correct.
		var spine := _joint(node, "Spine")
		node.set_meta("spine_y", spine.position.y if spine != null else 0.0)
	return node.get_meta("spine_y")


## How sharply this player is turning, measured over a stepped frame and
## smoothed. Presentation derives it; the sim is not asked.
##
## This was the change in facing between the two most recent snapshots, times
## twelve. One tick is a sixtieth of a second, and over that window facing is
## almost all noise: a player holding shape drifts at a couple of centimetres a
## second and his heading is whatever the separation forces last nudged his
## velocity to. Measured, the direction of that per-tick change reversed about
## twenty-five times a second and the twelvefold gain drove it into its own
## clamp, so the torso banked its full fourteen degrees back and forth at 25 Hz.
##
## The head sits nearly a metre above the spine pivot and the legs sit at it, so
## a bank is almost entirely a sideways swing of the head: that vibration is why
## the heads twitched. It was also the one part of the pose still running at
## frame rate while everything around it stepped at ten.
##
## Two changes. The baseline is a tenth of a second rather than a tick, which is
## six times the window and averages the noise out instead of amplifying it, and
## what is left is smoothed toward over the following frames. A real turn is
## sustained for a good fraction of a second and survives both.
##
## Both of those used to be counted in stepped frames, which is exactly the trap
## the smooth clock sets: at sixty frames a second the same code would measure
## facing over a sixtieth again — the original bug — and smooth six times as
## fast. So the window is a duration, held open across as many frames as it
## takes, and the smoothing is a time constant rather than a per-frame fraction.
## At a tenth of a second the two are what they always were.
const TURN_SATURATION := 5.0
const TURN_WINDOW := 0.1
const TURN_SMOOTHING_TAU := 0.2


func _turn_rate(node: Node3D, index: int, clock: float) -> float:
	var facing: float = _curr.player_facing[index]
	if not node.has_meta("turn_facing"):
		node.set_meta("turn_facing", facing)
		node.set_meta("turn_clock", clock)
		node.set_meta("turn_smooth_clock", clock)
		node.set_meta("turn_measured", 0.0)
		node.set_meta("turn_rate", 0.0)
		return 0.0
	var window: float = clock - float(node.get_meta("turn_clock"))
	if window >= TURN_WINDOW:
		var rate: float = wrapf(facing - float(node.get_meta("turn_facing")), -PI, PI) / window
		node.set_meta("turn_measured", rate / TURN_SATURATION)
		node.set_meta("turn_facing", facing)
		node.set_meta("turn_clock", clock)
	var smoothed: float = node.get_meta("turn_rate")
	var dt: float = clock - float(node.get_meta("turn_smooth_clock"))
	if dt > 0.0:
		node.set_meta("turn_smooth_clock", clock)
		var toward: float = node.get_meta("turn_measured")
		smoothed = lerpf(smoothed, toward, 1.0 - exp(-dt / TURN_SMOOTHING_TAU))
		node.set_meta("turn_rate", smoothed)
	return smoothed


func _bob_crowd() -> void:
	if _crowd == null:
		return
	var home: Array = _crowd.get_meta("home") as Array
	var phases := _crowd.get_meta("phases") as PackedFloat32Array
	var mm: MultiMesh = _crowd.multimesh
	for i in mm.instance_count:
		var bob := sin(_elapsed * 2.4 + phases[i]) * 0.16
		mm.set_instance_transform(i, Transform3D(Basis(), home[i] + Vector3(0.0, bob, 0.0)))


## One frame of camerawork: decide whether the shot still holds, then pan.
func _work_camera(ball_pos: Vector3, sim_dt: float) -> void:
	_camera_held += sim_dt
	var wanted := _shot_for(ball_pos.x)
	if wanted == _camera_wanted:
		_camera_wanted_for += sim_dt
	else:
		_camera_wanted = wanted
		_camera_wanted_for = 0.0
	# Play at the far end is the one case worth cutting on sight. The live camera
	# is then behind play by the length of the pitch, and every second it holds is
	# a second of watching an attack side-on from eighty metres away.
	var far_end := absi(wanted - _camera_shot) == 2
	var settled := _camera_held >= CAMERA_MIN_SHOT and _camera_wanted_for >= CAMERA_COMMIT
	if wanted != _camera_shot and (settled or far_end):
		_cut_to(wanted)
	else:
		_pan_to(ball_pos, sim_dt)
	_apply_camera()


## Which camera has the angle, given where play is.
##
## The hysteresis widens the live camera's own territory and nothing else. Doing
## it the obvious way — one threshold, moved in when a penalty-area camera is
## live — also moves the boundary of the camera at the *other* end, so a left-box
## camera would hand straight over to the right-box one with play still in
## midfield.
func _shot_for(ball_x: float) -> int:
	var right := CAMERA_SWITCH_X - (CAMERA_SWITCH_HYSTERESIS if _camera_shot == 2 else 0.0)
	var left := -CAMERA_SWITCH_X + (CAMERA_SWITCH_HYSTERESIS if _camera_shot == 0 else 0.0)
	if ball_x > right:
		return 2
	if ball_x < left:
		return 0
	return 1


## Takes the shot, and starts it already framed on the ball. Panning in from
## wherever the last camera happened to be pointed would spend the first second
## of every cut looking at the wrong part of the pitch.
func _cut_to(shot: int) -> void:
	_camera_shot = shot
	_camera_held = 0.0
	_camera_wanted = shot
	_camera_wanted_for = 0.0
	_camera_aim = _aim_for(_curr.ball_pos)
	var x := 0.0
	if shot == 0:
		x = -CAMERA_SIDE_X
	elif shot == 2:
		x = CAMERA_SIDE_X
	# All three stand off the same touchline, at the same height and the same
	# distance back, so a cut moves along the stand and never across the pitch.
	var elevation := deg_to_rad(_elevation_deg)
	_camera.position = Vector3(x, _range * sin(elevation), _range * cos(elevation))


## Chases the aim point toward the ball with a time constant rather than
## following it exactly, which is the whole difference between a camera and a
## cursor: the shot trails a fast ball and settles behind it. Framed as a decay
## over the elapsed time, so the lag is the same however many frames a second the
## view is drawing at.
func _pan_to(ball_pos: Vector3, sim_dt: float) -> void:
	_camera_aim = _camera_aim.lerp(_aim_for(ball_pos), 1.0 - exp(-sim_dt / CAMERA_PAN_TAU))


## How far up the far half of the pitch the tilt will follow the ball before it
## stops and lets play climb the frame instead.
##
## The two directions of tilt are not symmetric, because the stadium is not.
## Tilting *towards* the viewer only ever brings in more grass and then the top
## rows of the near stand, which frame the shot; tilting away runs out of pitch,
## then out of crowd, and puts a band of empty backdrop across the top of the
## frame. Seventeen metres is where the top edge of the frame still lands inside
## the far stand at this elevation and range, so the sky never gets in.
##
## Stopping the tilt is also what an operator does with a ball played into the
## far corner: the camera holds and lets it run into the top of frame rather than
## chasing it up and losing the horizon.
const CAMERA_TILT_LIMIT := 17.0
## The same idea along the pitch. Centring the aim on a ball in the six-yard box
## puts the goal line a third of the way across the frame and gives the other
## third to the stand behind it. Stopping the pan short holds the goal near the
## edge of frame, which is where a television camera keeps it and how a viewer
## reads the width of the box.
const CAMERA_PAN_LIMIT := 38.0


## The point on the grass a camera tries to hold, which is the ball flattened
## onto the pitch and kept inside the part of it worth looking at. Flattened,
## because tracking a lofted ball in three dimensions tips the camera up into the
## empty sky above the far stand every time one is cleared. Kept inside, because
## a throw-in is taken from off the pitch and a corner from the very corner of
## it, and neither is a reason to swing the shot out over the crowd.
func _aim_for(ball_pos: Vector3) -> Vector3:
	return Vector3(
		clampf(ball_pos.x, -CAMERA_PAN_LIMIT, CAMERA_PAN_LIMIT),
		0.0,
		clampf(ball_pos.z, -CAMERA_TILT_LIMIT, _pitch.half_width),
	)


## Points the live camera at the aim point and zooms it so that CAMERA_FRAME_WIDTH
## metres span the frame *there*. Godot's `fov` is vertical, so the aspect ratio
## comes into it — and because the fit is redone every frame, a resize or a jump
## to full screen is already handled.
func _apply_camera() -> void:
	_camera.look_at(_camera_aim, Vector3.UP)
	var size := get_viewport().get_visible_rect().size
	var aspect: float = size.x / size.y if size.y > 0.0 else 16.0 / 9.0
	var vertical := _frame_width / aspect
	var range_to_aim := maxf(_camera.position.distance_to(_camera_aim), 1.0)
	var fov := rad_to_deg(2.0 * atan(vertical * 0.5 / range_to_aim))
	_camera.fov = clampf(fov, CAMERA_FOV_MIN, CAMERA_FOV_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if _debug and event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_pin_at(click.position)
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	# A held key repeats for the transport alone. Scrubbing back through a move a
	# sample at a time is otherwise a press per twentieth of a second, and every
	# other key here does something that should happen once.
	if event.echo and not (_debug and (event as InputEventKey).keycode in STEP_KEYS):
		return
	if _debug and _debug_key(event as InputEventKey):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_paused = not _paused
		KEY_1:
			_speed = 1.0
		KEY_2:
			_speed = 2.0
		KEY_3:
			_speed = 8.0
		# The next match and this one again. Both work at any point, but full time
		# is where they are wanted: the board asks for them there.
		KEY_N:
			if _scenario_cycle:
				_advance_scenario()
				_go_to_match(match_seed + 1)
			else:
				_go_to_match(match_seed + 1, _quality_step + 1)
		KEY_R:
			_go_to_match(match_seed)
		KEY_F11, KEY_F:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN
			)
		KEY_F1:
			_toggle_debug()
		KEY_ESCAPE:
			get_tree().quit()


## Brings the overlay up in a match that was not started with `--debug`, which is
## every match anybody actually watches: the main scene is this one.
##
## It is built the first time it is asked for rather than at start-up, so a
## normal match pays nothing for it — no nodes, and the sink in the sim off. What
## it cannot do is un-compress the clock: `clock_rate` is baked into the match
## when it is built, so a main-scene match opened this way is being read at 30x
## and says so.
func _toggle_debug() -> void:
	if _overlay == null:
		_debug = true
		_build_debug()
		return
	_debug = not _debug
	_leave_scrub()
	_overlay.visible = _debug
	_debug_world.visible = _debug
	_show_name_tags(_debug and _debug_world.layer_on(MatchDebugWorld.L_NAMES))
	SimDebug.enabled = _debug
	if not _debug:
		SimDebug.reset()


## The debug keys, which take precedence over the ordinary ones while `--debug`
## is on: the digits are the seven annotation layers there, and speed moves to
## the bracket keys and a ladder that reaches 0.1x.
func _debug_key(key: InputEventKey) -> bool:
	match key.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			_debug_world.toggle(MatchDebugWorld.LAYER_KEYS[key.keycode - KEY_1])
		KEY_BRACKETLEFT:
			_set_speed(_speed_step - 1)
		KEY_BRACKETRIGHT:
			_set_speed(_speed_step + 1)
		# `.` and `,` move a sample; shifted — `>` and `<` on the same two keys —
		# they move ten, which is half a second. The keycode is the key's own
		# label whatever the shift does to it, so both are read off `shift_pressed`
		# rather than off a second keycode.
		KEY_PERIOD, KEY_GREATER:
			_step_forward(STEP_BIG_SAMPLES if key.shift_pressed else STEP_SAMPLES)
		KEY_COMMA, KEY_LESS:
			_step_back(STEP_BIG_SAMPLES if key.shift_pressed else STEP_SAMPLES)
		# Only ever pressed with the picture stepped back, and it does nothing
		# otherwise: this is the way out of the recording that is not "give up and
		# go back to now".
		KEY_ENTER, KEY_KP_ENTER:
			_play_from_here()
		KEY_M:
			_bookmark_pending = true
		KEY_TAB:
			_overlay.visible = not _overlay.visible
		KEY_SPACE:
			_leave_scrub()
			_paused = not _paused
		_:
			return false
	return true
