extends Node2D
## The top-down debug view (PLAN.md §10, Phase 0).
##
## This is presentation: it reads snapshots and draws them, and never writes
## back into the simulation. The sim runs on its own fixed clock; this node
## advances it the right number of steps for the elapsed frame time and
## interpolates between the last two snapshots for smooth display.
##
## It is a debug tool, not the game. Phase 6 builds the real thing.

const PITCH_MARGIN := 40.0
const PLAYER_RADIUS_PX := 9.0

@export var match_seed := 1
@export var minutes := 90.0
@export var small_sided := false

var _match: SimMatch
var _prev := SimSnapshot.new()
var _curr := SimSnapshot.new()
var _accumulator := 0.0
var _speed := 1.0
var _paused := false
var _show_value_grid := false
var _show_trails := false
var _scale := 8.0
var _origin := Vector2.ZERO
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_start_match(match_seed)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _start_match(seed_value: int) -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = minutes
	opts.small_sided = small_sided
	opts.trace = false
	_match = SimRunner.build(opts)
	_match.write_snapshot(_curr)
	_prev.copy_from(_curr)
	_accumulator = 0.0


func _layout() -> void:
	var view := get_viewport_rect().size
	var pitch_w := _curr.half_length * 2.0 + 8.0
	var pitch_h := _curr.half_width * 2.0 + 8.0
	_scale = minf((view.x - PITCH_MARGIN * 2.0) / pitch_w, (view.y - PITCH_MARGIN * 2.0 - 40.0) / pitch_h)
	_origin = Vector2(view.x * 0.5, view.y * 0.5 + 20.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _match == null:
		return
	if not _paused and not _match.finished:
		# Fixed timestep. The simulation never sees `delta`; it only sees how
		# many whole steps to take.
		_accumulator += delta * _speed
		var step := SimConsts.DT
		var budget := 0
		while _accumulator >= step and budget < 4000:
			_prev.copy_from(_curr)
			_match.tick()
			_match.write_snapshot(_curr)
			_accumulator -= step
			budget += 1
		if _show_value_grid and _match.ctx.tick_index % 30 == 0:
			# Debug only, and never on the decision path.
			_match.ctx.value.refresh_debug_grid(_match.ctx)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_paused = not _paused
		KEY_1:
			_speed = 1.0
		KEY_2:
			_speed = 2.0
		KEY_3:
			_speed = 4.0
		KEY_4:
			_speed = 16.0
		KEY_V:
			_show_value_grid = not _show_value_grid
		KEY_T:
			_show_trails = not _show_trails
		KEY_R:
			match_seed += 1
			_start_match(match_seed)
			_layout()
		KEY_ESCAPE:
			get_tree().quit()


func _to_screen(p: Vector3) -> Vector2:
	return _origin + Vector2(p.x, p.z) * _scale


func _draw() -> void:
	if _match == null:
		return
	# Interpolate between the last two snapshots so the display is smooth even
	# though the sim is stepped in discrete ticks.
	var alpha: float = clampf(_accumulator / SimConsts.DT, 0.0, 1.0)
	_draw_pitch()
	if _show_value_grid:
		_draw_value_grid()
	_draw_ball(alpha)
	_draw_players(alpha)
	_draw_hud()


func _draw_pitch() -> void:
	var hl := _curr.half_length
	var hw := _curr.half_width
	draw_rect(Rect2(_to_screen(Vector3(-hl, 0, -hw)), Vector2(hl * 2.0, hw * 2.0) * _scale), SimPalette.PINE)
	# Mowing stripes, as flat bands.
	var bands := 10
	for i in bands:
		if i % 2 == 1:
			continue
		var x0: float = lerpf(-hl, hl, float(i) / float(bands))
		var x1: float = lerpf(-hl, hl, float(i + 1) / float(bands))
		draw_rect(Rect2(_to_screen(Vector3(x0, 0, -hw)), Vector2(x1 - x0, hw * 2.0) * _scale), SimPalette.GRASS)

	var line := SimPalette.CHALK
	var w := 2.0
	_line_rect(Vector3(-hl, 0, -hw), Vector3(hl, 0, hw), line, w)
	draw_line(_to_screen(Vector3(0, 0, -hw)), _to_screen(Vector3(0, 0, hw)), line, w)
	draw_arc(_to_screen(Vector3.ZERO), SimConsts.CENTRE_CIRCLE_RADIUS * _scale, 0.0, TAU, 48, line, w)
	for side in [-1.0, 1.0]:
		var pd := SimConsts.PENALTY_AREA_DEPTH
		var pw := SimConsts.PENALTY_AREA_HALF_WIDTH
		_line_rect(Vector3(side * hl, 0, -pw), Vector3(side * (hl - pd), 0, pw), line, w)
		var gd := SimConsts.GOAL_AREA_DEPTH
		var gw := SimConsts.GOAL_AREA_HALF_WIDTH
		_line_rect(Vector3(side * hl, 0, -gw), Vector3(side * (hl - gd), 0, gw), line, w)
		# Goals, as thick rounded tubes in an accent colour.
		var gh := SimConsts.GOAL_HALF_WIDTH
		draw_line(
			_to_screen(Vector3(side * hl, 0, -gh)),
			_to_screen(Vector3(side * hl, 0, gh)),
			SimPalette.AMBER, 7.0
		)


func _line_rect(a: Vector3, b: Vector3, colour: Color, width: float) -> void:
	var p0 := _to_screen(a)
	var p1 := _to_screen(b)
	draw_line(p0, Vector2(p1.x, p0.y), colour, width)
	draw_line(Vector2(p1.x, p0.y), p1, colour, width)
	draw_line(p1, Vector2(p0.x, p1.y), colour, width)
	draw_line(Vector2(p0.x, p1.y), p0, colour, width)


func _draw_value_grid() -> void:
	var grid := _match.ctx.value.debug_grid
	if grid.size() != SimValueField.GRID_X * SimValueField.GRID_Z:
		return
	var hl := _curr.half_length
	var hw := _curr.half_width
	var cell_w := hl * 2.0 / float(SimValueField.GRID_X)
	var cell_h := hw * 2.0 / float(SimValueField.GRID_Z)
	for ix in SimValueField.GRID_X:
		for iz in SimValueField.GRID_Z:
			var v := grid[iz * SimValueField.GRID_X + ix]
			var colour := SimPalette.SKY if v > 0.5 else SimPalette.RED
			colour.a = absf(v - 0.5) * 0.6
			var top_left := Vector3(-hl + float(ix) * cell_w, 0.0, -hw + float(iz) * cell_h)
			draw_rect(Rect2(_to_screen(top_left), Vector2(cell_w, cell_h) * _scale), colour)


func _draw_ball(alpha: float) -> void:
	var pos := _prev.ball_pos.lerp(_curr.ball_pos, alpha)
	# Height reads as a shadow offset plus a slightly larger ball.
	var shadow := _to_screen(Vector3(pos.x, 0.0, pos.z))
	draw_circle(shadow, 4.0, Color(0, 0, 0, 0.25))
	var lift := minf(pos.y, 12.0) * 1.6
	draw_circle(shadow - Vector2(0.0, lift), 4.5 + minf(pos.y, 6.0) * 0.35, SimPalette.CHALK)
	draw_arc(shadow - Vector2(0.0, lift), 4.5 + minf(pos.y, 6.0) * 0.35, 0.0, TAU, 12, SimPalette.INK, 1.0)


func _draw_players(alpha: float) -> void:
	for i in _curr.player_count:
		if _curr.player_on_pitch[i] == 0:
			continue
		var pos := _prev.player_pos[i].lerp(_curr.player_pos[i], alpha) if _prev.player_count == _curr.player_count else _curr.player_pos[i]
		var screen := _to_screen(pos)
		var team := _curr.player_team[i]
		var base: Color = SimPalette.RED if team == 0 else SimPalette.SKY
		# Fatigue is visible: a tired player drains toward grey.
		var stamina := _curr.player_stamina[i]
		base = base.lerp(SimPalette.SLATE, clampf(1.0 - stamina, 0.0, 1.0) * 0.55)
		draw_circle(screen, PLAYER_RADIUS_PX, base)
		draw_arc(screen, PLAYER_RADIUS_PX, 0.0, TAU, 16, SimPalette.INK, 1.5)
		# Facing, as a stubby nose.
		var facing := _curr.player_facing[i]
		draw_line(screen, screen + Vector2(cos(facing), sin(facing)) * PLAYER_RADIUS_PX * 1.6, SimPalette.INK, 2.0)
		if _font != null:
			draw_string(_font, screen + Vector2(-4.0, 4.0), str(_curr.player_shirt[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, SimPalette.PAPER)


func _draw_hud() -> void:
	if _font == null:
		return
	var minute := int(_curr.clock / 60.0)
	var second := int(_curr.clock) % 60
	# Explicitly typed: indexing an untyped Array yields a Variant, which `:=`
	# cannot infer from, and the parse error takes the whole scene down with it.
	var period: String = ["1st", "HT", "2nd", "FT"][_curr.period]
	var header := "%s  %d - %d   %02d:%02d  %s   x%.0f%s" % [
		"MATCH", _curr.score[0], _curr.score[1], minute, second, period, _speed,
		"  PAUSED" if _paused else "",
	]
	draw_string(_font, Vector2(20.0, 28.0), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, SimPalette.PAPER)
	draw_string(
		_font, Vector2(20.0, get_viewport_rect().size.y - 14.0),
		"space pause   1/2/3/4 speed   V value grid   R next seed   Esc quit",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SimPalette.PAPER
	)
