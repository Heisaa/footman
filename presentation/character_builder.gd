class_name SimCharacterBuilder
extends RefCounted
## Builds a player (PLAN.md §9.3 and §9.7, and the Sokpop reference the owner
## supplied).
##
## Slender and smoothly formed rather than blocky: a small rounded head, a
## narrow torso, thin capsule limbs, dark shorts and boots. Still a toy, still
## flat-coloured and textureless apart from the small face, but the silhouette
## is a person rather than a brick.
##
## §9.7 asks for the football comic, and a comic is drawn: every body part is
## therefore inked, with a hull grown a few millimetres and its front faces culled, so
## a figure carries a dark line round it exactly the way a strip panel does. It
## costs one extra pass per mesh and no extra nodes. Trim follows the same idea
## from the other direction -- collar, cuffs and a sock turnover in the kit's
## second colour -- because eighties kits were drawn in blocks of two colours and
## the trim is where the second one lives.
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

## The drawn line, as a fraction of the figure's height, so a giant and a small
## one carry the same weight of ink rather than the small one looking dipped.
const OUTLINE_FRACTION := 0.011
## Trim depth: how far the collar and the cuffs stand off the part they ring.
const TRIM_STANDOFF := 0.006


static func flat_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return m


## `shirt_number` under 1 leaves the back blank; `outline` off drops the ink, for
## a side-by-side comparison in the parade view.
static func build(
	appearance: SimAppearance,
	kit: PackedColorArray,
	shirt_number := 0,
	outline := true
) -> Node3D:
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

	var ink: Material = _outline_material(h) if outline else null
	var trim_colour: Color = SimPalette.INK if kit.size() < 2 else kit[1]
	var shirt := _inked(kit[0], ink)
	var shorts := _inked(trim_colour, ink)
	# Trim is not inked. The line is a fixed width in metres, which is right for a
	# torso and swallows a band a centimetre thick whole.
	var trim := flat_material(trim_colour)
	var skin := _inked(appearance.skin, ink)
	var boot := _inked(SimPalette.INK, ink)

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
		digits.modulate = trim_colour
		digits.outline_size = 24
		digits.outline_modulate = SimPalette.INK
		digits.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		# Cut rather than blended: a blended quad this close to the torso sorts
		# against it and flickers as the figure turns.
		digits.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		digits.position = Vector3(0.0, torso_h * 0.68, -shoulder * 0.78 - 0.01)
		spine.add_child(digits)

	# Collar: the one detail that dates a kit to the era at a glance.
	var collar := _ring(shoulder * 0.5, torso_h * 0.05, trim)
	collar.position = Vector3(0.0, torso_h * 0.95, 0.0)
	spine.add_child(collar)

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

	var hair := _hair(appearance, head_r, ink)
	if hair != null:
		head.add_child(hair)
	_accessory(appearance, head_r, head, kit, ink)

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
		# shoulder and the shirt reads as a vest, which no eighties kit was.
		if not appearance.sleeves_long:
			var sleeve := _capsule(limb * 1.12, torso_h * 0.16, shirt)
			sleeve.position = Vector3(0.0, -torso_h * 0.07, 0.0)
			sh.add_child(sleeve)

		var elbow := Node3D.new()
		elbow.name = "Elbow" + tag
		elbow.position = Vector3(0.0, -torso_h * 0.42, 0.0)
		sh.add_child(elbow)

		# The cuff, where a long sleeve ends. Nothing to ring on a bare arm.
		if appearance.sleeves_long:
			var cuff := _ring(limb, torso_h * 0.05, trim)
			cuff.position = Vector3(0.0, -torso_h * 0.4, 0.0)
			sh.add_child(cuff)

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
		var shin := _capsule(limb, leg_h * 0.44, _inked(sock_colour, ink))
		shin.position = Vector3(0.0, -leg_h * 0.22, 0.0)
		knee.add_child(shin)

		# The turnover at the top of a sock, in the trim colour. Socks pulled down
		# skip it: there is nothing up there to turn over.
		if appearance.socks_high:
			var turnover := _ring(limb, leg_h * 0.05, trim)
			turnover.position = Vector3(0.0, -leg_h * 0.03, 0.0)
			knee.add_child(turnover)

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


## A flat material with the drawn line hung off it. `ink` null is the plain fill,
## which is what the parade view's outline toggle hands in.
static func _inked(colour: Color, ink: Material) -> StandardMaterial3D:
	var m := flat_material(colour)
	m.next_pass = ink
	return m


## The line itself: the same mesh grown a little and drawn inside out, so all
## that survives is a rim of ink round the silhouette. Shared by every part of
## one figure -- it depends on nothing but the figure's height.
static func _outline_material(height: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = SimPalette.INK
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = height * OUTLINE_FRACTION
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


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


## A rim: used for a spectacle lens, where a solid disc would blank the face.
static func _torus(inner: float, outer: float, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = SEGMENTS
	mesh.ring_segments = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


## A band of trim: a short cylinder standing just proud of whatever it rings.
static func _ring(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius + TRIM_STANDOFF
	mesh.bottom_radius = radius + TRIM_STANDOFF
	mesh.height = height
	mesh.radial_segments = SEGMENTS
	mesh.rings = 1
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
static func _hair(appearance: SimAppearance, head_r: float, ink: Material) -> Node3D:
	if appearance.hair_style == 0:
		return null
	var mat := _inked(appearance.hair_colour, ink)
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


static func _accessory(
	appearance: SimAppearance,
	head_r: float,
	head: Node3D,
	kit: PackedColorArray,
	ink: Material
) -> void:
	match appearance.accessory:
		"beard", "beard_full":
			var beard := _sphere(head_r * 0.82, _inked(appearance.hair_colour, ink))
			beard.position = Vector3(0.0, -head_r * 0.42, head_r * 0.22)
			beard.scale = Vector3(1.0, 0.75 if appearance.accessory == "beard" else 1.05, 0.85)
			head.add_child(beard)
		"moustache":
			# Wide, flat and level with the mouth. The one accessory that puts a
			# figure in 1987 on its own.
			var tache := _box(
				Vector3(head_r * 0.54, head_r * 0.13, head_r * 0.14),
				flat_material(appearance.hair_colour))
			# Above the drawn mouth, not across it: the atlas puts the mouth at
			# about a quarter of a head-radius below centre, and a moustache
			# sitting on it reads as the mouth.
			tache.position = Vector3(0.0, -head_r * 0.13, head_r * 0.96)
			head.add_child(tache)
		"glasses":
			# Two rims and a bridge, sat on the face quad. Mouse wore them, and a
			# bespectacled man in a tackle is half the joke.
			var frame := flat_material(SimPalette.INK)
			for side in [-1.0, 1.0]:
				# A rim, not a disc: the face has to show through a lens or the
				# man is wearing sunglasses.
				var lens := _torus(head_r * 0.12, head_r * 0.18, frame)
				lens.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				# Level with the atlas's eyes, which sit a little above the middle
				# of the face quad. Lower than that and they read as goggles.
				lens.position = Vector3(side * head_r * 0.38, head_r * 0.15, head_r * 1.0)
				head.add_child(lens)
			var bridge := _box(
				Vector3(head_r * 0.42, head_r * 0.04, head_r * 0.04), frame)
			bridge.position = Vector3(0.0, head_r * 0.15, head_r * 1.0)
			head.add_child(bridge)
		"headband":
			var band := _capsule(head_r * 1.03, head_r * 0.16, _inked(kit[0], ink))
			band.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			band.position = Vector3(0.0, head_r * 0.3, 0.0)
			head.add_child(band)
		"cap":
			var cap := _sphere(head_r * 1.05, _inked(kit[0], ink))
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
