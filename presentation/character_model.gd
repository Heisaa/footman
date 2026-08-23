class_name SimCharacterModel
extends RefCounted
## Where a figure comes from: a built model if there is one for his body, and
## the procedural figure if there is not (PLAN.md §9.3).
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

## Material slots, in the order the Blender file has to declare them. Index is
## the slot; a model with fewer slots keeps its authored colours for the rest.
const SLOT_SHIRT := 0
const SLOT_SHORTS := 1
const SLOT_TRIM := 2
const SLOT_SKIN := 3
const SLOT_HAIR := 4
const SLOT_BOOT := 5

## Which `AccessoryN` mesh each accessory is. `SimAppearance.ACCESSORIES` holds
## repeats of "none" to weight the draw, so the list itself is not the index.
const ACCESSORY_INDEX := {"none": -1, "headband": 0, "cap": 1}

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
		_model_cache[body_type] = ResourceLoader.exists(model_path(body_type))
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
	root.name = "Player"
	root.scale = Vector3.ONE * (appearance.height / REFERENCE_HEIGHT)
	_paint(root, appearance, kit)
	_choose_variant(root, "Hair", appearance.hair_style)
	_choose_variant(root, "Accessory", int(ACCESSORY_INDEX.get(appearance.accessory, -1)))
	set_expression(root, appearance.face)
	return root


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
		own.albedo_texture = SimFaceAtlas.texture_for(face)
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
	for node in _meshes(root):
		for slot in mini(node.get_surface_override_material_count(), colours.size()):
			node.set_surface_override_material(slot, SimCharacterBuilder.toy_material(colours[slot]))


## Shows one of a set of variant meshes named `Prefix0`, `Prefix1`, ... and
## hides the rest. How hair and accessories are chosen: the Blender file carries
## every cut, and the seed picks which one is visible.
static func _choose_variant(root: Node3D, prefix: String, index: int) -> void:
	var variants: Array[Node3D] = []
	for node in root.find_children("%s*" % prefix, "Node3D", true, false):
		variants.append(node)
	if variants.is_empty():
		return
	variants.sort_custom(func(a, b): return a.name < b.name)
	for i in variants.size():
		variants[i].visible = index >= 0 and i == posmod(index, variants.size())


static func _meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(node)
	return out
