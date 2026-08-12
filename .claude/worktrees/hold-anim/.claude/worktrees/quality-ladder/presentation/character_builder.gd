class_name SimCharacterBuilder
extends RefCounted
## Builds a player (PLAN.md §9.3, and the Sokpop reference the owner supplied).
##
## Slender and smoothly formed rather than blocky: a small rounded head, a
## narrow torso, thin capsule limbs, dark shorts and boots. Still a toy, still
## flat-coloured and textureless apart from the small face, but the silhouette
## is a person rather than a brick.
##
## The hierarchy is built around joints -- hips, knees, ankles, shoulders,
## elbows, a torso pivot and a neck -- because a figure this simple only reads as
## alive if several parts move. Every mesh hangs *below* its pivot so a rotation
## swings it rather than spinning it in place.
##
## The ankle is a pivot rather than a boot welded to the shin because the foot is
## the part of a run the eye actually checks. A foot that stays flat while the
## leg swings has nothing to push off with and nothing to lift clear, and reads
## as the leg being dragged along the ground however good the rest of the cycle
## is.

## Proportions as fractions of total height.
##
## The head comes from the appearance seed, which generates §9.3's 35-40%. This
## file previously hardcoded 0.26 and ignored that field, for a slender build
## rather than a chunky one. It was changed back because the head is what
## carries a figure at match distance: at the framing the camera actually uses,
## 0.26 put the face below the resolution of the shot and the expression system
## — five drawn faces, swapped constantly — was invisible. Set `head_fraction`
## in `SimAppearance.from_seed` to go back to a slimmer build.
const LEG_FRACTION := 0.46
const TORSO_FRACTION := 0.30
## Limb thickness. Thin: this is the difference between the reference and a brick.
const LIMB_RADIUS := 0.052
const SEGMENTS := 12
const RINGS := 6


static func flat_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return m


static func build(appearance: SimAppearance, kit: PackedColorArray) -> Node3D:
	var root := Node3D.new()
	root.name = "Player"

	var h := appearance.height
	var head_r := h * appearance.head_fraction * 0.5
	var leg_h := h * LEG_FRACTION
	var torso_h := h * TORSO_FRACTION
	var shoulder := h * 0.155 * appearance.body_width()

	var shirt := flat_material(kit[0])
	var shorts := flat_material(SimPalette.INK if kit.size() < 2 else kit[1])
	var skin := flat_material(appearance.skin)
	var boot := flat_material(SimPalette.INK)

	# --- Torso, on a pivot so the whole upper body can lean ------------------
	var spine := Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0.0, leg_h, 0.0)
	root.add_child(spine)

	var torso := _capsule(shoulder * 0.78, torso_h * 0.8, shirt)
	torso.position = Vector3(0.0, torso_h * 0.5, 0.0)
	spine.add_child(torso)
	# A hint of hips in the shorts colour, so the kit reads in two parts.
	var hips := _capsule(shoulder * 0.74, torso_h * 0.24, shorts)
	hips.position = Vector3(0.0, torso_h * 0.06, 0.0)
	spine.add_child(hips)

	# --- Head, on a neck pivot ----------------------------------------------
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, torso_h * 0.98, 0.0)
	spine.add_child(neck)

	var head := _sphere(head_r, skin)
	head.position = Vector3(0.0, head_r * 0.86, 0.0)
	head.name = "Head"
	neck.add_child(head)

	var face := _face_quad(head_r)
	face.position = Vector3(0.0, 0.02, head_r * 0.94)
	face.name = "Face"
	head.add_child(face)

	var hair := _hair(appearance, head_r)
	if hair != null:
		head.add_child(hair)
	_accessory(appearance, head_r, head, kit)

	# --- Arms: shoulder pivot, upper arm, elbow pivot, forearm, mitten ------
	for side in [-1.0, 1.0]:
		var tag: String = "L" if side < 0.0 else "R"
		var sh := Node3D.new()
		sh.name = "Shoulder" + tag
		sh.position = Vector3(side * shoulder * 0.62, torso_h * 0.82, 0.0)
		spine.add_child(sh)

		var upper_mat := shirt if appearance.sleeves_long else skin
		var upper := _capsule(LIMB_RADIUS, torso_h * 0.42, upper_mat)
		upper.position = Vector3(0.0, -torso_h * 0.21, 0.0)
		sh.add_child(upper)

		var elbow := Node3D.new()
		elbow.name = "Elbow" + tag
		elbow.position = Vector3(0.0, -torso_h * 0.42, 0.0)
		sh.add_child(elbow)

		var fore := _capsule(LIMB_RADIUS * 0.92, torso_h * 0.38, skin)
		fore.position = Vector3(0.0, -torso_h * 0.19, 0.0)
		elbow.add_child(fore)

		# Mitten hand: one sphere, no fingers.
		var hand := _sphere(LIMB_RADIUS * 1.5, skin)
		hand.position = Vector3(0.0, -torso_h * 0.4, 0.0)
		elbow.add_child(hand)

	# --- Legs: hip pivot, thigh, knee pivot, shin, boot ---------------------
	for side in [-1.0, 1.0]:
		var tag2: String = "L" if side < 0.0 else "R"
		var hip := Node3D.new()
		hip.name = "Hip" + tag2
		hip.position = Vector3(side * shoulder * 0.34, leg_h, 0.0)
		root.add_child(hip)

		var thigh := _capsule(LIMB_RADIUS * 1.15, leg_h * 0.46, shorts)
		thigh.position = Vector3(0.0, -leg_h * 0.23, 0.0)
		hip.add_child(thigh)

		var knee := Node3D.new()
		knee.name = "Knee" + tag2
		knee.position = Vector3(0.0, -leg_h * 0.47, 0.0)
		hip.add_child(knee)

		var sock_colour: Color = kit[0] if appearance.socks_high else appearance.skin
		var shin := _capsule(LIMB_RADIUS, leg_h * 0.44, flat_material(sock_colour))
		shin.position = Vector3(0.0, -leg_h * 0.22, 0.0)
		knee.add_child(shin)

		var ankle := Node3D.new()
		ankle.name = "Ankle" + tag2
		# Where the boot already sat, so a zero ankle rotation is the old figure
		# exactly and only the poses that ask for a foot angle see a difference.
		ankle.position = Vector3(0.0, -leg_h * 0.45, 0.0)
		knee.add_child(ankle)

		var foot := _box(Vector3(LIMB_RADIUS * 2.2, LIMB_RADIUS * 1.6, LIMB_RADIUS * 4.0), boot)
		foot.position = Vector3(0.0, 0.0, LIMB_RADIUS * 1.1)
		ankle.add_child(foot)

	return root


# --- Primitives -------------------------------------------------------------


static func _capsule(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.05)
	mesh.radial_segments = SEGMENTS
	mesh.rings = RINGS
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


static func _sphere(radius: float, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = SEGMENTS
	mesh.rings = RINGS
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


static func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


static func _face_quad(head_r: float) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(head_r * 1.5, head_r * 1.5)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var m := flat_material(Color.WHITE)
	m.albedo_texture = SimFaceAtlas.texture_for(SimAppearance.Face.NEUTRAL)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = m
	return node


## A smooth cap of hair rather than a block. Style 0 is bald.
static func _hair(appearance: SimAppearance, head_r: float) -> Node3D:
	if appearance.hair_style == 0:
		return null
	var mat := flat_material(appearance.hair_colour)
	var style := appearance.hair_style
	var cap := _sphere(head_r * 1.02, mat)
	cap.position = Vector3(0.0, head_r * (0.14 + 0.04 * float(style % 3)), -head_r * 0.06)
	cap.scale = Vector3(1.0, 0.66 + 0.06 * float(style % 3), 1.02)
	if style <= 4:
		return cap
	var root := Node3D.new()
	root.add_child(cap)
	# Longer styles get a smooth back, which reads from the high camera.
	var back := _sphere(head_r * 0.82, mat)
	back.position = Vector3(0.0, -head_r * 0.28, -head_r * 0.62)
	back.scale = Vector3(1.1, 1.0 + 0.2 * float(style - 5), 0.7)
	root.add_child(back)
	return root


static func _accessory(appearance: SimAppearance, head_r: float, head: Node3D, kit: PackedColorArray) -> void:
	match appearance.accessory:
		"beard", "beard_full":
			var beard := _sphere(head_r * 0.82, flat_material(appearance.hair_colour))
			beard.position = Vector3(0.0, -head_r * 0.42, head_r * 0.22)
			beard.scale = Vector3(1.0, 0.75 if appearance.accessory == "beard" else 1.05, 0.85)
			head.add_child(beard)
		"headband":
			var band := _capsule(head_r * 1.03, head_r * 0.16, flat_material(kit[0]))
			band.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			band.position = Vector3(0.0, head_r * 0.3, 0.0)
			head.add_child(band)
		"cap":
			var cap := _sphere(head_r * 1.05, flat_material(kit[0]))
			cap.position = Vector3(0.0, head_r * 0.24, 0.0)
			cap.scale = Vector3(1.0, 0.5, 1.0)
			head.add_child(cap)
		_:
			pass


static func set_expression(player_root: Node3D, face: int) -> void:
	var quad := player_root.find_child("Face", true, false) as MeshInstance3D
	if quad == null:
		return
	var mat := quad.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_texture = SimFaceAtlas.texture_for(face)
