class_name SimCharacterBuilder
extends RefCounted
## Builds a player (PLAN.md §9.3, and the Sokpop reference the owner supplied).
##
## Slender and smoothly formed rather than blocky: a small rounded head, a
## narrow torso, thin capsule limbs, dark shorts and boots. Still a toy, still
## flat-coloured and textureless apart from the small face, but the silhouette
## is a person rather than a brick.
##
## **The look is the toy, and only the toy** -- Sokpop, Mii, Animal Crossing:
## smooth primitives, flat colour, no line work, no texture, no period dressing.
## §9.7's comic register governs the writing, the naming and the feel of the
## game; it does not reach the art. An ink outline and an eighties collar were
## tried here and taken out again for exactly that reason.
##
## Variety is carried by proportion and by the face instead: head size, head
## shape, height, build, skin, and which drawn eyes and mouth a man was born
## with. That is what keeps twenty-two flat-coloured figures from being one
## figure in different kits.
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
## The head comes from the appearance seed. This file previously hardcoded 0.26
## and ignored that field; it was changed back because the head is what carries a
## figure at match distance, and 0.26 put the face below the resolution of the
## shot with the expression system — five drawn faces, swapped constantly —
## invisible. The band itself now lives in `SimAppearance.HEAD_FRACTION_MIN/MAX`,
## which the owner cut to 0.30-0.35 for a longer body.
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


## `shirt_number` under 1 leaves the back blank.
static func build(appearance: SimAppearance, kit: PackedColorArray, shirt_number := 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Player"

	var h := appearance.height
	var head_r := h * appearance.head_fraction * 0.5
	var leg_h := h * LEG_FRACTION
	var torso_h := h * TORSO_FRACTION
	var shoulder := h * 0.155 * appearance.body_width()
	# Limbs scale with the man. A constant radius made the giant spindly and the
	# small one stumpy, which is the wrong way round for both.
	var limb := LIMB_RADIUS * (h / 1.78) * lerpf(0.9, 1.2, appearance.build)

	var second_colour: Color = SimPalette.INK if kit.size() < 2 else kit[1]
	var shirt := flat_material(kit[0])
	var shorts := flat_material(second_colour)
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

	# The number on the back. A squad of twenty-two flat-coloured men is hard to
	# talk about; a number is how a crowd names one, and it is period-correct.
	if shirt_number > 0:
		var digits := Label3D.new()
		digits.name = "ShirtNumber"
		digits.text = str(shirt_number)
		digits.font_size = 128
		digits.pixel_size = torso_h * 0.0034
		digits.modulate = second_colour
		digits.outline_size = 24
		digits.outline_modulate = SimPalette.INK
		digits.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		# Cut rather than blended: a blended quad this close to the torso sorts
		# against it and flickers as the figure turns.
		digits.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		digits.position = Vector3(0.0, torso_h * 0.68, -shoulder * 0.78 - 0.01)
		spine.add_child(digits)

	# --- Head, on a neck pivot ----------------------------------------------
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, torso_h * 0.98, 0.0)
	spine.add_child(neck)

	var head := _sphere(head_r, skin)
	head.position = Vector3(0.0, head_r * 0.86, 0.0)
	# Not a ball. Everything hanging off the head -- face, hair, beard -- is a
	# child of it, so one scale gives a long face or a wide one and the drawn
	# features stretch with it.
	head.scale = Vector3(appearance.head_width, appearance.head_height, appearance.head_width)
	head.name = "Head"
	neck.add_child(head)

	var face := _face_quad(head_r, appearance)
	face.position = Vector3(0.0, 0.02, head_r * 0.94)
	face.name = "Face"
	head.add_child(face)
	# The expression swaps at run time and has to keep the man's own eyes and
	# mouth, so the two style indices ride on the figure.
	root.set_meta("eye_style", appearance.eye_style)
	root.set_meta("mouth_style", appearance.mouth_style)

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
		var upper := _capsule(limb, torso_h * 0.42, upper_mat)
		upper.position = Vector3(0.0, -torso_h * 0.21, 0.0)
		sh.add_child(upper)

		# A short sleeve is still a sleeve. Without this the arm is bare to the
		# shoulder and the shirt reads as a vest.
		if not appearance.sleeves_long:
			var sleeve := _capsule(limb * 1.12, torso_h * 0.16, shirt)
			sleeve.position = Vector3(0.0, -torso_h * 0.07, 0.0)
			sh.add_child(sleeve)

		var elbow := Node3D.new()
		elbow.name = "Elbow" + tag
		elbow.position = Vector3(0.0, -torso_h * 0.42, 0.0)
		sh.add_child(elbow)

		var fore := _capsule(limb * 0.92, torso_h * 0.38, skin)
		fore.position = Vector3(0.0, -torso_h * 0.19, 0.0)
		elbow.add_child(fore)

		# Mitten hand: one sphere, no fingers.
		var hand := _sphere(limb * 1.5, skin)
		hand.position = Vector3(0.0, -torso_h * 0.4, 0.0)
		elbow.add_child(hand)

	# --- Legs: hip pivot, thigh, knee pivot, shin, boot ---------------------
	for side in [-1.0, 1.0]:
		var tag2: String = "L" if side < 0.0 else "R"
		var hip := Node3D.new()
		hip.name = "Hip" + tag2
		hip.position = Vector3(side * shoulder * 0.34, leg_h, 0.0)
		root.add_child(hip)

		var thigh := _capsule(limb * 1.15, leg_h * 0.46, shorts)
		thigh.position = Vector3(0.0, -leg_h * 0.23, 0.0)
		hip.add_child(thigh)

		var knee := Node3D.new()
		knee.name = "Knee" + tag2
		knee.position = Vector3(0.0, -leg_h * 0.47, 0.0)
		hip.add_child(knee)

		var sock_colour: Color = kit[0] if appearance.socks_high else appearance.skin
		var shin := _capsule(limb, leg_h * 0.44, flat_material(sock_colour))
		shin.position = Vector3(0.0, -leg_h * 0.22, 0.0)
		knee.add_child(shin)

		var ankle := Node3D.new()
		ankle.name = "Ankle" + tag2
		# Where the boot already sat, so a zero ankle rotation is the old figure
		# exactly and only the poses that ask for a foot angle see a difference.
		ankle.position = Vector3(0.0, -leg_h * 0.45, 0.0)
		knee.add_child(ankle)

		var foot := _box(Vector3(limb * 2.2, limb * 1.6, limb * 4.0), boot)
		foot.position = Vector3(0.0, 0.0, limb * 1.1)
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


## A band round something: a short upright cylinder.
static func _band(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = SEGMENTS
	mesh.rings = 1
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


static func _face_quad(head_r: float, appearance: SimAppearance) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(head_r * 1.5, head_r * 1.5)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var m := flat_material(Color.WHITE)
	m.albedo_texture = SimFaceAtlas.texture_for(
		SimAppearance.Face.NEUTRAL, appearance.eye_style, appearance.mouth_style)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = m
	return node


## Hair, from four smooth pieces: a cap over the crown, a mass down the back, a
## fringe over the forehead and a tuft on top. Fourteen recognisably different
## heads out of one small function, and every piece is a squashed sphere -- the
## look is the toy, so nothing here is line work or texture.
##
## The cap is built from a **hairline** rather than a scale, because the number
## that matters is where the hair stops on the forehead. The drawn eyes sit at
## about a tenth of a head-radius above the middle of the face, and a cap whose
## lower edge crosses them reads as a blindfold. Deriving the ellipsoid from the
## hairline puts that edge exactly where the row asks for it.
##
## Each row is [hairline, back, fringe, tuft].
const HAIR_CROWN := 1.12
const HAIR_LIBRARY := [
	[0.00, 0, 0, 0],  # bald
	[0.44, 0, 0, 0],  # receding
	[0.30, 0, 0, 0],  # cropped
	[0.30, 0, 1, 0],  # cropped with a fringe
	[0.20, 0, 0, 0],  # thick on top
	[0.20, 0, 1, 0],  # thick with a fringe
	[0.26, 0, 0, 1],  # a tuft
	[0.20, 0, 1, 1],  # fringe and tuft
	[0.26, 1, 0, 0],  # collar length
	[0.22, 1, 1, 0],  # collar length with a fringe
	[0.16, 1, 0, 0],  # long
	[0.16, 1, 1, 0],  # long with a fringe
	[0.24, 1, 0, 1],  # long with a tuft
	[0.34, 0, 1, 0],  # a fringe and not much else
]


static func _hair(appearance: SimAppearance, head_r: float) -> Node3D:
	var style: int = posmod(appearance.hair_style, HAIR_LIBRARY.size())
	if style == 0:
		return null
	var row: Array = HAIR_LIBRARY[style]
	var hairline: float = row[0]
	var mat := flat_material(appearance.hair_colour)
	var root := Node3D.new()
	root.name = "Hair"

	# An ellipsoid whose bottom lands on the hairline and whose top clears the
	# crown, gripping the skull a little wider than the skull itself.
	var half := (HAIR_CROWN - hairline) * 0.5
	var cap := _sphere(head_r * 1.04, mat)
	cap.position = Vector3(0.0, head_r * (HAIR_CROWN - half), -head_r * 0.05)
	cap.scale = Vector3(1.0, half / 1.04, 1.0)
	root.add_child(cap)

	if int(row[1]) == 1:
		# The mass down the back, which is what the high match camera actually
		# sees of a long style.
		var back := _sphere(head_r * 0.8, mat)
		back.position = Vector3(0.0, -head_r * 0.16, -head_r * 0.56)
		back.scale = Vector3(1.05, 1.05, 0.62)
		root.add_child(back)

	if int(row[2]) == 1:
		# A patch on the forehead, standing proud of it. Narrower than the head so
		# it cannot close into a band round the whole skull.
		var fringe := _sphere(head_r * 0.62, mat)
		fringe.position = Vector3(0.0, head_r * (hairline + 0.12), head_r * 0.5)
		fringe.scale = Vector3(0.95, 0.34, 0.5)
		root.add_child(fringe)

	if int(row[3]) == 1:
		var tuft := _sphere(head_r * 0.3, mat)
		tuft.position = Vector3(0.0, head_r * 1.02, -head_r * 0.08)
		tuft.scale = Vector3(0.8, 1.2, 0.8)
		root.add_child(tuft)

	return root


static func _accessory(
	appearance: SimAppearance,
	head_r: float,
	head: Node3D,
	kit: PackedColorArray
) -> void:
	match appearance.accessory:
		"beard", "beard_full":
			# Under the drawn mouth, not over it. The mouth is half the expression
			# and a beard centred on the jaw swallowed it.
			var beard := _sphere(head_r * 0.82, flat_material(appearance.hair_colour))
			beard.position = Vector3(0.0, -head_r * 0.48, head_r * 0.2)
			beard.scale = Vector3(0.92, 0.62 if appearance.accessory == "beard" else 0.82, 0.82)
			head.add_child(beard)
		"headband":
			# A band round the forehead. It was a capsule turned on its side, which
			# is a disc across the face rather than a band round the head.
			var band := _band(head_r * 1.02, head_r * 0.15, flat_material(kit[0]))
			band.position = Vector3(0.0, head_r * 0.3, 0.0)
			head.add_child(band)
		"cap":
			var cap := _sphere(head_r * 1.05, flat_material(kit[0]))
			cap.position = Vector3(0.0, head_r * 0.24, 0.0)
			cap.scale = Vector3(1.0, 0.5, 1.0)
			head.add_child(cap)
		_:
			pass


## Swaps the expression and keeps the man's own eyes and mouth under it. The two
## style indices were written onto the figure when it was built, because the sim
## side of this call knows an animation state and nothing else.
static func set_expression(player_root: Node3D, face: int) -> void:
	var quad := player_root.find_child("Face", true, false) as MeshInstance3D
	if quad == null:
		return
	var mat := quad.material_override as StandardMaterial3D
	if mat == null:
		return
	var eyes: int = player_root.get_meta("eye_style", 0)
	var mouth: int = player_root.get_meta("mouth_style", 0)
	mat.albedo_texture = SimFaceAtlas.texture_for(face, eyes, mouth)
