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
## Long legs, a short narrow torso and a head that sits straight on it. The
## reference figure is a good deal slimmer than this file used to build: what
## made ours look top-heavy was never the head, it was a fat torso on short legs.
const LEG_FRACTION := 0.50
const TORSO_FRACTION := 0.27
## Limb thickness. Thin: this is the difference between the reference and a brick.
const LIMB_RADIUS := 0.048
const SEGMENTS := 12
const RINGS := 6
## The head and the hair are rounder than the rest of the figure. A twelve-sided
## sphere is a chunky limb and a boxy skull, and the skull is the thing being
## looked at.
## The drawn face, as a fraction of the head radius.
const FACE_QUAD := 1.5
const HEAD_SEGMENTS := 24
const HEAD_RINGS := 12



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
	var shoulder := h * 0.138 * appearance.body_width()
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

	var torso := _capsule(shoulder * 0.82, torso_h * 0.86, shirt)
	torso.position = Vector3(0.0, torso_h * 0.52, 0.0)
	spine.add_child(torso)
	# The shorts, in the kit's second colour, so the kit reads in two blocks.
	var hips := _capsule(shoulder * 0.76, torso_h * 0.30, shorts)
	hips.position = Vector3(0.0, torso_h * 0.06, 0.0)
	spine.add_child(hips)

	# The neckline. A thin ring of the second colour where the reference has a
	# V: at this size the trim is a line of colour and the shape of it is below
	# the resolution of anything but a close-up.
	var collar := _band(shoulder * 0.5, torso_h * 0.05, flat_material(second_colour))
	collar.position = Vector3(0.0, torso_h * 0.95, 0.0)
	spine.add_child(collar)

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

	var head := _sphere(head_r, skin, true)
	head.position = Vector3(0.0, head_r * 0.86, 0.0)
	# Not a ball. The face and the hair are children of it, so one scale gives a
	# long face or a wide one and the drawn features stretch with it.
	head.scale = Vector3(appearance.head_width, appearance.head_height, appearance.head_width)
	head.name = "Head"
	neck.add_child(head)

	var face := _face_quad(head_r, appearance)
	# Just proud of the skull. At 0.94 the quad sits inside a sphere this size and
	# only shows because the sphere is faceted, which leaves no room for hair to
	# come down the forehead without swallowing the brows.
	face.position = Vector3(0.0, 0.02, head_r * 0.96)
	face.name = "Face"
	head.add_child(face)
	# The expression swaps at run time and has to keep the man's own face under
	# it, so the style indices ride on the figure.
	root.set_meta("brow_style", appearance.brow_style)
	root.set_meta("eye_style", appearance.eye_style)
	root.set_meta("mouth_style", appearance.mouth_style)

	head.add_child(_nose(appearance, head_r))

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
		var upper := _capsule(limb, torso_h * 0.52, upper_mat)
		upper.position = Vector3(0.0, -torso_h * 0.26, 0.0)
		sh.add_child(upper)

		# A short sleeve is still a sleeve. Without this the arm is bare to the
		# shoulder and the shirt reads as a vest.
		if not appearance.sleeves_long:
			var sleeve := _capsule(limb * 1.15, torso_h * 0.24, shirt)
			sleeve.position = Vector3(0.0, -torso_h * 0.11, 0.0)
			sh.add_child(sleeve)

		# The cuff at the end of the sleeve, long or short.
		var cuff_at: float = -torso_h * (0.52 if appearance.sleeves_long else 0.23)
		var cuff := _band(limb * 1.18, torso_h * 0.035, flat_material(second_colour))
		cuff.position = Vector3(0.0, cuff_at, 0.0)
		sh.add_child(cuff)

		var elbow := Node3D.new()
		elbow.name = "Elbow" + tag
		elbow.position = Vector3(0.0, -torso_h * 0.52, 0.0)
		sh.add_child(elbow)

		var fore := _capsule(limb * 0.92, torso_h * 0.48, skin)
		fore.position = Vector3(0.0, -torso_h * 0.24, 0.0)
		elbow.add_child(fore)

		# Mitten hand: one sphere, no fingers, and small. At half again the arm it
		# was a boxing glove.
		var hand := _sphere(limb * 1.12, skin)
		hand.position = Vector3(0.0, -torso_h * 0.5, 0.0)
		elbow.add_child(hand)

	# --- Legs: hip pivot, thigh, knee pivot, shin, boot ---------------------
	for side in [-1.0, 1.0]:
		var tag2: String = "L" if side < 0.0 else "R"
		var hip := Node3D.new()
		hip.name = "Hip" + tag2
		hip.position = Vector3(side * shoulder * 0.34, leg_h, 0.0)
		root.add_child(hip)

		# Bare thigh, with the shorts pulled over the top of it. The thigh used to
		# be shorts-coloured end to end, which is a pair of trousers.
		var thigh := _capsule(limb * 1.1, leg_h * 0.46, skin)
		thigh.position = Vector3(0.0, -leg_h * 0.23, 0.0)
		hip.add_child(thigh)

		var short_leg := _capsule(limb * 1.18, leg_h * 0.2, shorts)
		short_leg.position = Vector3(0.0, -leg_h * 0.08, 0.0)
		hip.add_child(short_leg)

		var knee := Node3D.new()
		knee.name = "Knee" + tag2
		knee.position = Vector3(0.0, -leg_h * 0.47, 0.0)
		hip.add_child(knee)

		var sock_colour: Color = kit[0] if appearance.socks_high else appearance.skin
		var shin := _capsule(limb, leg_h * 0.44, flat_material(sock_colour))
		shin.position = Vector3(0.0, -leg_h * 0.22, 0.0)
		knee.add_child(shin)

		# Two hoops near the top of the sock, as the reference has.
		if appearance.socks_high:
			for band_at in [0.09, 0.15]:
				var hoop := _band(limb * 1.04, leg_h * 0.022, flat_material(second_colour))
				hoop.position = Vector3(0.0, -leg_h * band_at, 0.0)
				knee.add_child(hoop)

		var ankle := Node3D.new()
		ankle.name = "Ankle" + tag2
		# Where the boot already sat, so a zero ankle rotation is the old figure
		# exactly and only the poses that ask for a foot angle see a difference.
		ankle.position = Vector3(0.0, -leg_h * 0.45, 0.0)
		knee.add_child(ankle)

		# A rounded shoe rather than a block: the reference boots are domes, and a
		# box on the end of a round leg is the one part that still read as Lego.
		var foot := _sphere(limb * 1.35, boot, true)
		foot.scale = Vector3(1.0, 0.62, 1.7)
		foot.position = Vector3(0.0, -limb * 0.1, limb * 0.85)
		ankle.add_child(foot)

	return root


# --- Primitives -------------------------------------------------------------


static func _capsule(
	radius: float, height: float, material: Material, smooth := false
) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.05)
	mesh.radial_segments = SEGMENTS
	mesh.rings = RINGS
	if smooth:
		mesh.radial_segments = HEAD_SEGMENTS
		mesh.rings = HEAD_RINGS
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


static func _sphere(radius: float, material: Material, smooth := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = HEAD_SEGMENTS if smooth else SEGMENTS
	mesh.rings = HEAD_RINGS if smooth else RINGS
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
	mesh.size = Vector2(head_r * FACE_QUAD, head_r * FACE_QUAD)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var m := flat_material(Color.WHITE)
	m.albedo_texture = SimFaceAtlas.texture_for(
		SimAppearance.Face.NEUTRAL, appearance.brow_style, appearance.eye_style,
		appearance.mouth_style)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = m
	return node


## Hair: a sphere a little larger than the skull, pushed back and up, plus an
## optional mass down the back. Nothing else.
##
## The previous version built an ellipsoid from a hairline and it read as a hat,
## every time -- because a squashed sphere sitting on the crown *is* a hat, and
## its lower edge is a brim. A sphere concentric with the head cannot be: it is
## the head, slightly inflated, so the head shows through wherever the sphere is
## pushed away from. Pushing it back by `back_off` is what opens the face, and
## the amount of push is what makes the difference between a bowl cut and a
## receding one. That is how the reference art does it.
##
## The one number to respect: the drawn brows sit about a quarter of a
## head-radius above the middle of the face, and the face quad is at 0.94 of the
## radius. Hair reaching into that corner covers the brows, and the brows are
## where the expression lives. Every row below is checked against it.
##
## Noses, in the flesh. The reference art gives every figure a small bump on the
## front of the head and no drawn nose at all, and it is right: at this size an
## inked nose is a smudge between the eyes, while a bump catches the light and
## does the whole job for one sphere.
##
## A capsule rather than a ball: a nose has a length to it, and a sphere on the
## front of a head is a clown's. Standing upright it gives the bridge and the tip
## in one primitive.
##
## How far out matters more than the size: sunk to 0.95 of the radius, all that
## showed was the front of the capsule and the nose was a ball again. At 1.0 the
## whole length of it stands proud of the skull and the shape reads.
##
## Each row is [radius, length, height on the face, how far out, z scale].
## Length has to clear twice the radius by a good margin or the capsule collapses
## into a sphere -- half these rows did, which is why the shape could not be seen.
## The heights are measured from the equator, where the eyes now are, and the
## lengths are cut to fit between them and the mouth at four tenths of a radius
## down. Sized for the old layout they hung into the mouth like a proboscis.
const NOSE_LIBRARY := [
	[0.090, 0.26, -0.14, 1.00, 1.05],  # a small straight one
	[0.100, 0.28, -0.15, 0.99, 0.95],  # broader
	[0.082, 0.24, -0.13, 1.01, 1.15],  # short and fine
	[0.105, 0.32, -0.17, 0.99, 1.00],  # a big one
	[0.080, 0.22, -0.12, 1.01, 1.00],  # a neat short one, high on the face
	[0.110, 0.30, -0.16, 0.98, 0.95],  # broad
]


static func _nose(appearance: SimAppearance, head_r: float) -> MeshInstance3D:
	var row: Array = NOSE_LIBRARY[posmod(appearance.nose_style, NOSE_LIBRARY.size())]
	var nose := _capsule(
		head_r * float(row[0]), head_r * float(row[1]),
		flat_material(appearance.nose_colour), true)
	nose.name = "Nose"
	nose.position = Vector3(0.0, head_r * float(row[2]), head_r * float(row[3]))
	nose.scale = Vector3(1.0, 1.0, float(row[4]))
	return nose


## Two numbers do the work. The **radius** is how much hair there is: a few per
## cent over the skull is hair lying on the head, a fifth over is an afro. The
## **push back** is the hairline: the two spheres meet in a circle, and shoving
## the hair sphere backwards drags that circle up the forehead. Push a small
## shell far back and all that is left is a rim round the silhouette, which is a
## swimming cap; push it a little and the hair comes down the forehead.
##
## Making every style voluminous to avoid the rim was the other failure -- a
## squad of eleven afros. Volume belongs to the two styles that want it.
##
## The limit on every row is the face. The drawn brows sit about a quarter of a
## head-radius above the middle of the face and the face quad is at 0.96 of the
## radius, so no row may reach past about 0.95 at that height: that is
## `back >= radius - 0.95` at the worst point.
##
## Each row is [radius, up, back, side, height scale, mass down the back].
const HAIR_LIBRARY := [
	[0.00, 0.00, 0.00, 0.00, 1.00, 0],  # bald
	[1.04, 0.08, 0.22, 0.00, 1.00, 0],  # cropped
	[1.05, 0.06, 0.16, 0.00, 1.00, 0],  # short back and sides
	[1.09, 0.05, 0.13, 0.00, 1.00, 0],  # a bowl cut
	[1.11, 0.04, 0.16, 0.00, 1.00, 0],  # a heavy bowl cut
	[1.06, 0.14, 0.16, 0.00, 1.18, 0],  # tall on top
	[1.26, 0.12, 0.32, 0.00, 0.96, 0],  # an afro
	[1.38, 0.16, 0.44, 0.00, 0.92, 0],  # a big afro
	[1.06, 0.05, 0.13, 0.05, 1.00, 0],  # swept to one side
	[1.06, 0.05, 0.13, 0.00, 1.00, 1],  # collar length
	[1.07, 0.04, 0.12, 0.04, 1.00, 1],  # long, with a parting
	[1.02, 0.12, 0.30, 0.00, 1.00, 0],  # receding
	[1.03, 0.10, 0.24, 0.00, 0.92, 0],  # thin on top
	[1.20, 0.10, 0.26, 0.00, 1.00, 1],  # a big head of hair
]


static func _hair(appearance: SimAppearance, head_r: float) -> Node3D:
	var style: int = posmod(appearance.hair_style, HAIR_LIBRARY.size())
	if style == 0:
		return null
	var row: Array = HAIR_LIBRARY[style]
	var mat := flat_material(appearance.hair_colour)
	var root := Node3D.new()
	root.name = "Hair"

	var shell := _sphere(head_r * float(row[0]), mat, true)
	shell.position = Vector3(
		head_r * float(row[3]), head_r * float(row[1]), -head_r * float(row[2]))
	shell.scale = Vector3(1.0, float(row[4]), 1.0)
	root.add_child(shell)

	if int(row[5]) == 1:
		# Down the back of the neck, which is most of what the match camera sees
		# of a long style.
		# Behind the head rather than beside it: a mass as wide as the skull turns
		# a long style into a hood.
		var back := _sphere(head_r * 0.78, mat, true)
		back.position = Vector3(0.0, -head_r * 0.34, -head_r * 0.5)
		back.scale = Vector3(0.85, 1.15, 0.72)
		root.add_child(back)

	return root


static func _accessory(
	appearance: SimAppearance,
	head_r: float,
	head: Node3D,
	kit: PackedColorArray
) -> void:
	match appearance.accessory:
		"headband":
			# A band round the forehead. It was a capsule turned on its side, which
			# is a disc across the face rather than a band round the head.
			# Clear above the brows, which sit at about four tenths of a radius, and
			# only just wider than the head is at that height -- a band cut to the
			# equator and raised to the forehead is a brim.
			var band := _band(head_r * 0.92, head_r * 0.11, flat_material(kit[0]))
			band.position = Vector3(0.0, head_r * 0.6, 0.0)
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
	mat.albedo_texture = SimFaceAtlas.texture_for(
		face,
		player_root.get_meta("brow_style", 0),
		player_root.get_meta("eye_style", 0),
		player_root.get_meta("mouth_style", 0))
