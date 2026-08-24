class_name SimCharacterModel
extends RefCounted
## Where a figure comes from: a built model if there is one for his body, and
## the procedural figure if there is not (PLAN.md §9.1).
##
## This is the seam between the identity layer and the art. `WorldGen` writes a
## man's body type, height and build into the low bits of his `appearance_seed`
## (`WorldLook` says why); this reads them back, and either hands the seed to
## `SimCharacterBuilder` -- the primitives that have always drawn the game -- or
## instantiates the Blender model for that body type.
##
## **It falls back silently and always works.** With no models on disk every
## figure is the procedural one, exactly as before, so the two can be built in
## either order and a half-finished model library breaks nothing. Drop a
## `body_giant.glb` into `res://presentation/models/` and the giants use it while
## everybody else carries on as they were.
##
## The call sites use `appearance_for` where they used `SimAppearance.from_seed`
## and `build` where they used `SimCharacterBuilder.build`, and nothing else in
## the view changes.

const MODEL_DIR := "res://presentation/models"

## Height the models are authored at, in metres. A figure is scaled by his own
## height over this, so the rig is built once at an ordinary size.
const REFERENCE_HEIGHT := 1.78

## The radius the model's face is drawn on, in the model's own space.
##
## `SimCharacterBuilder` lays the atlas and poses the brows on a sphere of
## `head_r * FACE_SHELL`, and a built model has no way to say what its own is --
## so this is the number `art/toy/figure.py` builds to, and that script prints it
## on every export. If the two ever drift the brows drift off the face with them.
const MODEL_HEAD_R := 0.2869

## What fraction of its height the model's own bare skull is, chin to crown.
## `art/toy/figure.py:SKULL` is where it comes from: 0.630 to 0.950.
const MODEL_HEAD_FRACTION := 0.32

## Where the shirt number goes, in the model's own fractions of height.
## `art/figure/rig.py` puts the `Spine` pivot at 0.335 and `art/toy/figure.py`
## runs the shirt from a hem at 0.380 to a collar at 0.626, so this is between
## the shoulder blades with the collar clear above it.
const SPINE_AT := 0.335
const NUMBER_AT := 0.478
## The shirt's own half-depth there is 0.086 of height; a few millimetres more
## and the label never sinks into the weave as the man turns.
const NUMBER_BACK := 0.086 * REFERENCE_HEIGHT + 0.006
## 128 px of font at this many metres a pixel is a digit about 14 cm tall, which
## is what the references wear.
const NUMBER_PIXEL_SIZE := 0.0016

## Material slots, in the order the Blender file has to declare them. Index is
## the slot; a model with fewer slots keeps its authored colours for the rest.
const SLOT_SHIRT := 0
const SLOT_SHORTS := 1
const SLOT_TRIM := 2
const SLOT_SKIN := 3
const SLOT_HAIR := 4
const SLOT_BOOT := 5

## The slot each material name maps to. **Name, not index.** The index order in
## `docs/THE_MODELS.md` cannot survive the trip: a part is one moulding and one
## colour, so it carries one material, and glTF drops the slots a mesh does not
## use -- every part would arrive with its single surface at index 0 and be
## painted shirt-coloured. A name survives, and it is what `art/export.py`
## writes. Index is still the fallback for a model that uses no known name.
##
## A name that is not here keeps the colour it was authored in, which is what
## the eyes want: `ink` is black in every kit.
const SLOT_NAMES := {
	"shirt": SLOT_SHIRT, "shorts": SLOT_SHORTS, "trim": SLOT_TRIM,
	"skin": SLOT_SKIN, "hair": SLOT_HAIR, "boot": SLOT_BOOT,
}

## Which `AccessoryN` mesh each accessory is. `SimAppearance.ACCESSORIES` holds
## repeats of "none" to weight the draw, so the list itself is not the index.
const ACCESSORY_INDEX := {"none": -1, "headband": 0}

## Set false to draw every figure procedurally whatever is on disk -- the
## comparison you want while a model is being judged against the primitives.
static var models_enabled := true

## Whether a body type's model has already been looked for, so a missing file
## costs one `ResourceLoader.exists` per run rather than one per player.
static var _model_cache := {}


static func model_path(body_type: int) -> String:
	return "%s/body_%s.glb" % [MODEL_DIR, WorldLook.type_name(body_type)]


## Is there a model for this body? Cached, because it is asked 22 times a match
## and the answer cannot change while the game is running.
static func has_model(body_type: int) -> bool:
	if not models_enabled:
		return false
	if not _model_cache.has(body_type):
		var found := ResourceLoader.exists(model_path(body_type))
		_model_cache[body_type] = found
		if not found:
			# **Said once, out loud.** The fallback is the right behaviour and it
			# is completely silent, which is how an afternoon goes on a figure
			# nobody is actually looking at: a `.glb` that failed to export, or
			# one Godot has not imported yet, and the game draws the primitives
			# and says nothing. `godot --headless --import` is usually the answer.
			print("no model for %s at %s -- drawing the primitives" % [
				WorldLook.type_name(body_type), model_path(body_type)])
	return bool(_model_cache[body_type])


## The appearance for a seed, with the record's body applied.
##
## A drop-in for `SimAppearance.from_seed`. The seed's free bits still decide
## the face, the hair and the skin; the packed bits overrule the height and the
## build, which is how a man the record says is 2.04 m stops being drawn as an
## ordinary one. An unpacked seed is returned untouched.
static func appearance_for(seed_value: int) -> SimAppearance:
	var appearance := SimAppearance.from_seed(seed_value)
	if not WorldLook.is_packed(seed_value):
		return appearance
	appearance.height = WorldLook.height_of(seed_value)
	appearance.build = WorldLook.build_of(seed_value)
	return appearance


## The figure. A drop-in for `SimCharacterBuilder.build` that takes the seed as
## well, because the body type rides in it.
static func build(seed_value: int, appearance: SimAppearance, kit: PackedColorArray, shirt_number := 0) -> Node3D:
	var body_type := body_type_of(seed_value, appearance)
	if not has_model(body_type):
		return SimCharacterBuilder.build(appearance, kit, shirt_number)

	var scene: PackedScene = load(model_path(body_type))
	var root := scene.instantiate() as Node3D
	if root == null:
		# A model that will not instantiate is a broken asset, not a reason to
		# put nobody on the pitch.
		push_warning("model for %s did not instantiate; drawing the primitives" % WorldLook.type_name(body_type))
		return SimCharacterBuilder.build(appearance, kit, shirt_number)
	root = _unwrap(root)
	root.name = "Player"
	root.scale = Vector3.ONE * (appearance.height / REFERENCE_HEIGHT)
	_paint(root, appearance, kit)
	_choose_variant(root, "Hair", appearance.hair_style)
	_choose_variant(root, "Accessory", int(ACCESSORY_INDEX.get(appearance.accessory, -1)))
	# One mesh, shown or hidden -- there is only ever one moustache, so it is not
	# a variant set and `_choose_variant` would want it numbered.
	var tache := root.find_child("Moustache", true, false) as Node3D
	if tache != null:
		tache.visible = appearance.moustache
	# The face and the brows are the whole of a man's identity at this size, and
	# they are the same code for a model as for the primitives: the metas below
	# are what `SimCharacterBuilder.set_expression` and `_pose_brows` read.
	root.set_meta("brow_style", appearance.brow_style)
	root.set_meta("eye_style", appearance.eye_style)
	root.set_meta("mouth_style", appearance.mouth_style)
	root.set_meta("head_r", MODEL_HEAD_R)
	_shape_head(root, appearance)
	_dress_face(root, appearance)
	_dress_eyes(root)
	set_expression(root, appearance.face)
	_number(root, kit, shirt_number)
	return root


## The number on the back, the same Label3D the primitives get.
##
## `build` has taken `shirt_number` since it was written and a model threw it
## away, so half a squad could be told apart and the other half could not. Three
## of the four reference figures wear one and a crowd names a man by it.
##
## Geometry was the other option and it is the wrong one here: a digit moulded
## in relief has to be moulded per digit, per body, in Blender, and it is unread
## at match distance anyway. A label is one node and it is legible at both.
static func _number(root: Node3D, kit: PackedColorArray, shirt_number: int) -> void:
	if shirt_number <= 0:
		return
	var spine := root.find_child("Spine", true, false) as Node3D
	if spine == null:
		return
	var digits := Label3D.new()
	digits.name = "ShirtNumber"
	digits.text = str(shirt_number)
	digits.font_size = 128
	digits.pixel_size = NUMBER_PIXEL_SIZE
	digits.modulate = SimPalette.INK if kit.size() < 2 else kit[1]
	digits.outline_size = 24
	digits.outline_modulate = SimPalette.INK
	# Facing out of the man's back, which is -Z: the figure looks down +Z.
	digits.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	# Cut rather than blended: a blended quad this close to the shirt sorts
	# against it and flickers as the figure turns.
	digits.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	digits.position = Vector3(
		0.0, (NUMBER_AT - SPINE_AT) * REFERENCE_HEIGHT, -NUMBER_BACK)
	spine.add_child(digits)


## The head a man was born with, on a model that only has one.
##
## `head_width`, `head_height` and `head_fraction` are drawn per player and the
## model was ignoring all three, so five hundred men shared a head. It is the
## largest single thing making a squad look like a squad of one: hair and a
## drawn face vary, and a face is mostly its outline.
##
## The `Head` node's pivot is the chin, so this grows a head **upwards** and the
## jaw stays where the neck is. Everything hanging off it -- hair, ears, nose,
## the atlas patch and the brows -- stretches with it, which is the point: a long
## face wants long features, and features that keep their own proportions on a
## stretched skull are a mask.
static func _shape_head(root: Node3D, appearance: SimAppearance) -> void:
	var head := root.find_child("Head", true, false) as Node3D
	if head == null:
		return
	# Clamped, and the clamp is not cosmetic: the model's own head is 0.32 of
	# its height and `head_fraction` is drawn round 0.37, so an unclamped ratio
	# would grow every head by a sixth before it varied any of them.
	var size := clampf(appearance.head_fraction / MODEL_HEAD_FRACTION, 0.90, 1.14)
	head.scale = Vector3(
		appearance.head_width * size,
		appearance.head_height * size,
		appearance.head_width * size)


## Gives the model's face surface a material the atlas can be swapped into.
##
## A built face carries no art -- it is a blank patch on the front of the skull
## -- and the atlas is drawn per player and again per expression. The material
## has to be an override rather than the file's own, or every man in the match
## shares one face; and it has to be alpha, because the atlas is features on
## nothing. `SimCharacterBuilder.face_material` is the rest of the argument.
static func _dress_face(root: Node3D, appearance: SimAppearance) -> void:
	var quad := root.find_child("Face", true, false) as MeshInstance3D
	if quad == null:
		return
	var material := SimCharacterBuilder.face_material()
	SimCharacterBuilder.dress_face(
		material, appearance.face, appearance.eye_style, appearance.mouth_style)
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The eye beads get their own material, not the palette's.
##
## `_paint` cannot do it: the beads are named `eye` in the file precisely so they
## fall outside `SLOT_NAMES` and keep a colour no kit can change -- but what the
## exporter authors is a plain matte black, and the whole point of a moulded eye
## is the gloss on it. `SimCharacterBuilder.eye_material` is the same material
## the procedural figure's beads get.
static func _dress_eyes(root: Node3D) -> void:
	var eyes := root.find_child("Eyes", true, false)
	if eyes == null:
		return
	var material := SimCharacterBuilder.eye_material()
	for child in eyes.get_children():
		var bead := child as MeshInstance3D
		if bead == null:
			continue
		for slot in bead.get_surface_override_material_count():
			bead.set_surface_override_material(slot, material)


## Takes a built model out of the wrapper glTF import puts it in.
##
## The file's own root is `Player`, and Godot hands back a scene root with that
## node hanging under it -- so a model arrives one level deeper than the
## procedural figure, and anything reaching for a direct child of the figure
## finds nothing. That is not hypothetical: `_spine_base` did exactly that and
## quietly answered zero, which put every man's torso on his hips.
##
## Only an empty, untransformed wrapper round a single node is removed, which is
## the shape glTF import makes and nothing else.
static func _unwrap(root: Node3D) -> Node3D:
	if root.get_child_count() != 1 or root.transform != Transform3D.IDENTITY:
		return root
	var inner := root.get_child(0) as Node3D
	if inner == null or root is MeshInstance3D:
		return root
	root.remove_child(inner)
	root.free()
	return inner


## The body type for a seed. Falls back to reading the appearance itself for an
## unpacked seed, so a `SimSquadGen` player still gets a sensible shape.
static func body_type_of(seed_value: int, appearance: SimAppearance) -> int:
	if WorldLook.is_packed(seed_value):
		return WorldLook.body_type_of(seed_value)
	return WorldLook.body_type_for("", appearance.height, appearance.build)


## Sets the expression, whichever kind of figure this is.
static func set_expression(player_root: Node3D, face: int) -> void:
	var quad := player_root.find_child("Face", true, false) as MeshInstance3D
	if quad == null:
		return
	if quad.get_surface_override_material_count() > 0 or quad.material_override != null:
		SimCharacterBuilder.set_expression(player_root, face)
		return
	var material := quad.get_active_material(0) as StandardMaterial3D
	if material != null:
		var own := material.duplicate() as StandardMaterial3D
		SimCharacterBuilder.dress_face(own, face, 0, 0)
		quad.set_surface_override_material(0, own)


## Paints the model from the palette. Colour lives in material overrides rather
## than in the file, so one model serves both sides and every club in the game.
static func _paint(root: Node3D, appearance: SimAppearance, kit: PackedColorArray) -> void:
	var second: Color = SimPalette.INK if kit.size() < 2 else kit[1]
	var shorts: Color = second if kit.size() < 3 else kit[2]
	var colours := {
		SLOT_SHIRT: kit[0],
		SLOT_SHORTS: shorts,
		SLOT_TRIM: second,
		SLOT_SKIN: appearance.skin,
		SLOT_HAIR: appearance.hair_colour,
		SLOT_BOOT: SimPalette.INK,
	}
	var meshes := _meshes(root)
	if _named(meshes):
		for node in meshes:
			for slot in node.get_surface_override_material_count():
				var name := _material_name(node, slot)
				if SLOT_NAMES.has(name):
					node.set_surface_override_material(
						slot, _material_for(SLOT_NAMES[name], colours))
		return
	for node in meshes:
		for slot in mini(node.get_surface_override_material_count(), colours.size()):
			node.set_surface_override_material(slot, _material_for(slot, colours))


## Vinyl for the kit and the skin; matte for the hair and the boots, which are
## not painted plastic. `SimCharacterBuilder.MATTE_ROUGHNESS` has the argument,
## and the procedural figure makes the same distinction.
static func _material_for(slot: int, colours: Dictionary) -> StandardMaterial3D:
	if slot == SLOT_HAIR or slot == SLOT_BOOT:
		return SimCharacterBuilder.matte_material(colours[slot])
	return SimCharacterBuilder.toy_material(colours[slot])


## Does this model name its materials, or does it want the slot order?
static func _named(meshes: Array[MeshInstance3D]) -> bool:
	for node in meshes:
		for slot in node.get_surface_override_material_count():
			if SLOT_NAMES.has(_material_name(node, slot)):
				return true
	return false


static func _material_name(node: MeshInstance3D, slot: int) -> String:
	var material := node.get_active_material(slot)
	return "" if material == null else material.resource_name


## Shows one of a set of variant meshes named `Prefix0`, `Prefix1`, ... and
## hides the rest. How hair and accessories are chosen: the Blender file carries
## every cut, and the seed picks which one is visible.
## Shows one of a set of variant meshes named `Prefix0`, `Prefix1`, ... and
## hides the rest. How hair and accessories are chosen: the model carries every
## cut and the seed picks which one is visible.
##
## **The number in the name is the index**, not the node's place in the sorted
## list, and the difference is not academic. Sorted as text `Hair10` lands
## between `Hair1` and `Hair2`, so eighteen cuts mean eight men in the wrong
## one; and bald has no mesh at all, so counting the nodes is one short and
## every index after it is off by one. Position is the fallback for a model
## whose variants are not numbered.
static func _choose_variant(root: Node3D, prefix: String, index: int) -> void:
	var variants: Array[Node3D] = []
	for node in root.find_children("%s*" % prefix, "Node3D", true, false):
		variants.append(node)
	if variants.is_empty():
		return
	var numbered := {}
	var highest := -1
	for node in variants:
		var tail := String(node.name).substr(prefix.length())
		if tail.is_valid_int():
			numbered[node] = tail.to_int()
			highest = maxi(highest, tail.to_int())
	if numbered.size() == variants.size():
		# `highest + 1` and not the node count: the gaps are real. Bald is hair
		# zero and has nothing to show, and wrapping on the count would show the
		# next man's cut instead of no cut at all.
		var wanted := -1 if index < 0 else posmod(index, highest + 1)
		for node in variants:
			node.visible = numbered[node] == wanted
		return
	variants.sort_custom(func(a, b): return a.name < b.name)
	for i in variants.size():
		variants[i].visible = index >= 0 and i == posmod(index, variants.size())


static func _meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(node)
	return out
