class_name MatchDebugWorld
extends Node3D
## The pitch-space half of the debug overlay: what the engine was thinking,
## drawn on the grass rather than written in a panel.
##
## A pass option is a line from the carrier to the target. Everything here is
## something whose *shape* is the answer — where the options went, who is
## chasing, who has run where — because a table of coordinates says none of it.
##
## Every layer is off until a key turns it on. Layer 1 is the one that earns the
## overlay: "he never passes to the winger" resolves to either "the winger was
## not a candidate" or "he was, and he scored 0.02 lower", and those are two
## completely different jobs.
##
## Presentation. It draws a `MatchDebugFrame` — the context copied out at one
## tick — and never writes anything back.

const L_OPTIONS := 1 << 0
const L_PRESSURE := 1 << 1
const L_INTENT := 1 << 2
const L_CHASE := 1 << 3
const L_VALUE := 1 << 4
const L_BELIEF := 1 << 5
const L_TRAIL := 1 << 6
## Shirt numbers over the players. Not drawn here — the tags hang off the view's
## own player nodes so they inherit the interpolated position — but keyed and
## named with the rest, because to the eye it is one more layer.
const L_NAMES := 1 << 7

const LAYER_KEYS := [
	L_OPTIONS, L_PRESSURE, L_INTENT, L_CHASE, L_VALUE, L_BELIEF, L_TRAIL, L_NAMES,
]
const LAYER_NAMES := [
	"options", "pressure", "runs", "chasing", "value", "belief", "trails", "names",
]

## How far above the grass the annotations float. The pitch is cambered by 0.2 m
## from the middle to the touchline, so this is measured from the surface itself
## rather than from y = 0.
const LIFT := 0.14
const FILL_LIFT := 0.06
const RING_SEGMENTS := 20
## Half the width of a line drawn as three: the renderer gives every line one
## pixel whatever it is told, so a line that has to read as heavier is drawn
## more than once.
const THICKEN := 0.11
## Radius of the cross marking where a carrier meets the ball again. Smaller than
## the option rings it sits among, because it is a point rather than an area.
const CATCH_MARK := 0.75

var env: SimEnv = null
var layers := 0

var _mesh: ImmediateMesh
var _line_material: StandardMaterial3D
var _fill_material: StandardMaterial3D
var _lines := PackedVector3Array()
var _line_colours := PackedColorArray()
var _tris := PackedVector3Array()
var _tri_colours := PackedColorArray()
var _home_kit := SimPalette.RED
var _away_kit := SimPalette.SKY


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Always visible: an annotation hidden behind a player is an annotation that
	# is missing exactly when the thing it explains is happening.
	_line_material.no_depth_test = true
	_line_material.render_priority = 2
	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.vertex_color_use_as_albedo = true
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.mesh = _mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func set_kits(home: Color, away: Color) -> void:
	_home_kit = home
	_away_kit = away


func toggle(bit: int) -> void:
	layers ^= bit


func layer_on(bit: int) -> bool:
	return (layers & bit) != 0


## The help line: which layer each key holds, and which are on.
func layer_help() -> String:
	var parts := PackedStringArray()
	for i in LAYER_KEYS.size():
		var label := "%d %s" % [i + 1, LAYER_NAMES[i]]
		parts.append("[%s]" % label if layer_on(LAYER_KEYS[i]) else label)
	return "  ".join(parts)


## Rebuilt from scratch each frame. Everything here is a few hundred vertices
## and only when a layer is on, so there is nothing to be gained by caching it
## and a stale annotation would be worse than none.
##
## Every layer is drawn from the frame, which is the tick on screen rather than
## the tick the sim has reached. Stepped back, these used to be blanked: the
## context only knows about now, and drawing this instant's pressure over a
## picture of three seconds ago is a lie with a ring around it. The frame carries
## that moment's, so the rings, the runs and the option lines are the ones that
## belonged to the picture.
##
## `trail` is the run of samples ending at the moment shown, oldest first.
func show_state(frame: MatchDebugFrame, snap: SimSnapshot, trail: Array[SimSnapshot], focus: int,
		decision: Dictionary) -> void:
	_lines.clear()
	_line_colours.clear()
	_tris.clear()
	_tri_colours.clear()
	if frame != null and frame.captured() and layers != 0:
		if layer_on(L_VALUE):
			_draw_value(frame, snap)
		if layer_on(L_TRAIL):
			_draw_trails(trail)
		if layer_on(L_PRESSURE):
			_draw_pressure(frame)
		if layer_on(L_CHASE):
			_draw_chase(frame, snap)
		if layer_on(L_INTENT):
			_draw_intents(frame)
		if layer_on(L_BELIEF):
			_draw_beliefs(frame, focus)
		if layer_on(L_OPTIONS):
			_draw_options(decision)
	_flush()


# --- The layers -------------------------------------------------------------


## What the man on the ball was choosing between, drawn from where he stood when
## he chose. The chosen option is heavy and lemon; the rest fade with the softmax
## weight they were actually taken at.
##
## A carry gets a second mark: a cross where he expects to meet the ball again.
## The ring at the end of a carry's arrow is the *horizon* — how far that
## direction was judged over — and the ball never goes there, so without the
## cross the layer overstates every carry in the match.
## `SimDebugProbe._catch_point` has the distinction.
func _draw_options(rec: Dictionary) -> void:
	if rec.is_empty():
		return
	var from: Vector3 = rec["pos"]
	var options: Array = rec["options"]
	var chosen := int(rec["chosen"])
	for i in options.size():
		var opt: Dictionary = options[i]
		var to: Vector3 = opt["point"]
		var weight := float(opt["weight"])
		var alpha: float = 0.22 + 0.6 * (0.0 if is_nan(weight) else clampf(weight, 0.0, 1.0))
		if SimConsts.horizontal_length(to - from) < 0.4:
			# A hold and a clearance go nowhere, so there is no line to draw. The
			# ring at his feet is how the layer still says which one he took.
			if i == chosen:
				_ring(from, 1.1, SimPalette.LEMON)
			continue
		if i == chosen:
			_thick_line(from, to, SimPalette.LEMON)
			_ring(to, 1.1, SimPalette.LEMON)
			_draw_catch(opt, SimPalette.LEMON, 1.0)
			continue
		_line(from, to, Color(SimPalette.CHALK, alpha))
		_ring(to, 0.6, Color(SimPalette.CHALK, alpha * 0.8))
		_draw_catch(opt, SimPalette.CHALK, alpha)


## The next touch: where the ball will have run to by the time he gets to it.
## Drawn as a cross so it cannot be read as one of the option rings.
func _draw_catch(opt: Dictionary, colour: Color, alpha: float) -> void:
	var catch: Vector3 = opt.get("catch", Vector3.INF)
	if is_inf(catch.x):
		return
	var tint := Color(colour, alpha * 0.85)
	_cross(catch, CATCH_MARK, tint)


## A ring under every player, sized by how much of what he wants to do is being
## taken away, reddening as a challenge becomes imminent.
func _draw_pressure(frame: MatchDebugFrame) -> void:
	for i in frame.count:
		if frame.on_pitch[i] == 0:
			continue
		var press := frame.pressure[i]
		if press < 0.05:
			continue
		var challenge := clampf(frame.challenge[i], 0.0, 2.0) * 0.5
		var colour: Color = SimPalette.SKY.lerp(SimPalette.RED, challenge)
		_ring(frame.pos[i], 0.7 + minf(press, 3.0) * 0.5, Color(colour, 0.7))


## Who has offered himself, in which of the three ways, and where he is going.
func _draw_intents(frame: MatchDebugFrame) -> void:
	for i in frame.count:
		if frame.on_pitch[i] == 0:
			continue
		var kind := frame.intent[i]
		if kind == SimOffBall.NONE:
			continue
		var to := frame.intent_point[i]
		if is_inf(to.x):
			continue
		var colour: Color = [SimPalette.SLATE, SimPalette.AMBER, SimPalette.TEAL, SimPalette.LIME, SimPalette.PLUM, SimPalette.PINK, SimPalette.BROWN][kind]
		_arrow(frame.pos[i], to, Color(colour, 0.9))


## The anti-swarm assignment made visible: who is allowed to leave shape for the
## ball, who is backing him up, and who each defender has picked up.
func _draw_chase(frame: MatchDebugFrame, snap: SimSnapshot) -> void:
	var ball := Vector3(snap.ball_pos.x, 0.0, snap.ball_pos.z)
	for i in frame.count:
		if frame.on_pitch[i] == 0:
			continue
		match frame.chase[i]:
			SimMovement.CHASE_PRIMARY:
				_ring(frame.pos[i], 1.3, Color(SimPalette.CORAL, 0.95))
				_line(frame.pos[i], ball, Color(SimPalette.CORAL, 0.5))
			SimMovement.CHASE_SUPPORT:
				_ring(frame.pos[i], 1.0, Color(SimPalette.ORANGE, 0.6))
		# Sand rather than a grey, because the option lines are pale and a marking
		# web the same colour reads as one picture instead of two.
		var mark := frame.marking[i]
		if mark >= 0 and mark < frame.count:
			_line(frame.pos[i], frame.pos[mark], Color(SimPalette.SAND, 0.5))


## The coarse pitch-control grid. Debug only and never on the decision path,
## which is why it is refreshed by the view rather than by the sim.
func _draw_value(frame: MatchDebugFrame, snap: SimSnapshot) -> void:
	var grid := frame.value_grid
	if grid.size() != SimValueField.GRID_X * SimValueField.GRID_Z:
		return
	var cell_x := snap.half_length * 2.0 / float(SimValueField.GRID_X)
	var cell_z := snap.half_width * 2.0 / float(SimValueField.GRID_Z)
	for ix in SimValueField.GRID_X:
		for iz in SimValueField.GRID_Z:
			var v := grid[iz * SimValueField.GRID_X + ix]
			var colour: Color = _home_kit if v > 0.5 else _away_kit
			colour.a = absf(v - 0.5) * 0.7
			var x := -snap.half_length + float(ix) * cell_x
			var z := -snap.half_width + float(iz) * cell_z
			_cell(x, z, cell_x, cell_z, colour)


## Where each player has been, so a run that has already happened can still be
## looked at. Visual only: the samples come from the view's own history, and end
## at the moment on screen rather than at the tick the sim has reached.
func _draw_trails(trail: Array[SimSnapshot]) -> void:
	if trail.size() < 2:
		return
	for i in range(1, trail.size()):
		var a := trail[i - 1]
		var b := trail[i]
		var fade := float(i) / float(trail.size())
		_line(a.ball_pos, b.ball_pos, Color(SimPalette.CHALK, fade * 0.8))
		if a.player_count != b.player_count:
			continue
		for j in b.player_count:
			if b.player_on_pitch[j] == 0:
				continue
			var kit: Color = _home_kit if b.player_team[j] == SimConsts.TEAM_HOME else _away_kit
			_line(a.player_pos[j], b.player_pos[j], Color(kit, fade * 0.55))


## What one player believes, against what is true. The layer for "why did he not
## see that" — an option he cannot perceive is one he can never be scored for.
func _draw_beliefs(frame: MatchDebugFrame, focus: int) -> void:
	if focus < 0 or focus >= frame.count:
		return
	var n := frame.count
	if frame.beliefs.size() < n * n:
		return
	for target in n:
		if target == focus or frame.on_pitch[target] == 0:
			continue
		var believed := frame.beliefs[focus * n + target]
		var truth := frame.pos[target]
		if SimConsts.horizontal_length(believed - truth) < 1.5:
			continue
		_ring(believed, 0.5, Color(SimPalette.VIOLET, 0.8))
		_line(believed, truth, Color(SimPalette.VIOLET, 0.35))


# --- Primitives -------------------------------------------------------------


func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	_lines.append(_on_grass(a))
	_line_colours.append(colour)
	_lines.append(_on_grass(b))
	_line_colours.append(colour)


## A line drawn three times, side by side, because the renderer gives every line
## exactly one pixel however wide it is asked for.
func _thick_line(a: Vector3, b: Vector3, colour: Color) -> void:
	var side := (b - a)
	side.y = 0.0
	if side.length() < 0.001:
		return
	side = Vector3(-side.z, 0.0, side.x).normalized() * THICKEN
	_line(a, b, colour)
	_line(a + side, b + side, colour)
	_line(a - side, b - side, colour)


## An X on the grass. Deliberately not a ring: the options layer is already full
## of rings and this mark means something else.
func _cross(centre: Vector3, radius: float, colour: Color) -> void:
	var d := radius * 0.7071
	_line(Vector3(centre.x - d, 0.0, centre.z - d), Vector3(centre.x + d, 0.0, centre.z + d), colour)
	_line(Vector3(centre.x - d, 0.0, centre.z + d), Vector3(centre.x + d, 0.0, centre.z - d), colour)


func _ring(centre: Vector3, radius: float, colour: Color) -> void:
	var step := TAU / float(RING_SEGMENTS)
	for i in RING_SEGMENTS:
		var a := Vector3(centre.x + cos(step * i) * radius, 0.0, centre.z + sin(step * i) * radius)
		var b := Vector3(
			centre.x + cos(step * (i + 1)) * radius, 0.0, centre.z + sin(step * (i + 1)) * radius
		)
		_line(a, b, colour)


func _arrow(a: Vector3, b: Vector3, colour: Color) -> void:
	_line(a, b, colour)
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.5:
		return
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	_line(b, b - dir * 1.0 + side * 0.55, colour)
	_line(b, b - dir * 1.0 - side * 0.55, colour)


func _cell(x: float, z: float, w: float, h: float, colour: Color) -> void:
	var p0 := _on_fill(Vector3(x, 0.0, z))
	var p1 := _on_fill(Vector3(x + w, 0.0, z))
	var p2 := _on_fill(Vector3(x + w, 0.0, z + h))
	var p3 := _on_fill(Vector3(x, 0.0, z + h))
	for p in [p0, p1, p2, p0, p2, p3]:
		_tris.append(p)
		_tri_colours.append(colour)


func _on_grass(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground(p.x, p.z) + LIFT, p.z)


func _on_fill(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground(p.x, p.z) + FILL_LIFT, p.z)


func _ground(x: float, z: float) -> float:
	return env.surface_height(x, z) if env != null else 0.0


func _flush() -> void:
	_mesh.clear_surfaces()
	if not _tris.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_material)
		for i in _tris.size():
			_mesh.surface_set_color(_tri_colours[i])
			_mesh.surface_add_vertex(_tris[i])
		_mesh.surface_end()
	if not _lines.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
		for i in _lines.size():
			_mesh.surface_set_color(_line_colours[i])
			_mesh.surface_add_vertex(_lines[i])
		_mesh.surface_end()
