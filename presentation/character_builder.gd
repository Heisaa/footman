class_name SimCharacterBuilder
extends RefCounted
## Builds a player (PLAN.md §9.3), from the owner's reference: a rank of moulded
## toy footballers.
##
## **The look is the toy, and only the toy** -- smooth primitives, flat colour,
## no line work, no texture apart from the small drawn face. §9.7's comic
## register governs the writing, the naming and the feel of the game; it does not
## reach the art. An ink outline was tried here and taken out again for exactly
## that reason.
##
## Everything is assembled from a seed, so five hundred players have visual
## identity for nothing. What varies: height, build, head size and shape, skin,
## hair (a library of fourteen, assembled from a shell plus curls, a quiff, a
## tuft, sideburns or a widow's peak), the nose, a moustache or not, the drawn
## brows, eyes and mouth, and the kit.
##
## The hierarchy is built around joints -- hips, knees, ankles, shoulders,
## elbows, a torso pivot and a neck -- because a figure this simple only reads as
## alive if several parts move, and because those eleven names are the contract
## the animation layer poses against. Every mesh hangs *below* its pivot so a
## rotation swings it rather than spinning it in place.
##
## The ankle is a pivot rather than a boot welded to the shin because the foot is
## the part of a run the eye actually checks. A foot that stays flat while the
## leg swings has nothing to push off with and nothing to lift clear, and reads
## as the leg being dragged along the ground however good the rest of the cycle
## is.

## Proportions as fractions of total height.
##
## Long legs, a short narrow torso and a head that sits straight on it. Measured
## against the reference the heads are much the same size as ours ever were; what
## made the figure top-heavy was a fat torso on short legs with boxing-glove
## hands.
const LEG_FRACTION := 0.50
const TORSO_FRACTION := 0.27
## Shoulder half-width, as a fraction of height, before the build multiplier.
const SHOULDER_FRACTION := 0.138
## Limb thickness. Thin: this is the difference between the reference and a brick.
const LIMB_RADIUS := 0.048
const SEGMENTS := 12
const RINGS := 6
## The head, the hair and the shoes are rounder than the rest of the figure. A
## twelve-sided sphere is a chunky limb and a boxy skull, and the skull is the
## thing being looked at.
const HEAD_SEGMENTS := 24
const HEAD_RINGS := 12
## The drawn face, as a fraction of the head radius.
const FACE_QUAD := 1.5
## Moulded vinyl, not paper: the reference figures carry a soft highlight and it
## is most of what makes them read as objects rather than flat shapes. Scenery
## keeps the old dead-flat material.
const TOY_ROUGHNESS := 0.42
const TOY_SPECULAR := 0.45


## Flat, unlit-looking material for scenery: the pitch, the goals, the stands.
static func flat_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return m


## The figure's own material: the same flat colour with a soft sheen on it.
static func toy_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = TOY_ROUGHNESS
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.metallic_specular = TOY_SPECULAR
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
	var shoulder := h * SHOULDER_FRACTION * appearance.body_width()
	# Limbs scale with the man. A constant radius made the giant spindly and the
	# small one stumpy, which is the wrong way round for both.
	var limb := LIMB_RADIUS * (h / 1.78) * lerpf(0.9, 1.2, appearance.build)

	var second_colour: Color = SimPalette.INK if kit.size() < 2 else kit[1]
	var shirt := toy_material(kit[0])
	var shorts := toy_material(second_colour)
	var trim := toy_material(second_colour)
	var skin := toy_material(appearance.skin)
	var boot := toy_material(SimPalette.INK)

	# --- Torso, on a pivot so the whole upper body can lean ------------------
	var spine := Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0.0, leg_h, 0.0)
	root.add_child(spine)

	var torso := _capsule(shoulder * 0.82, torso_h * 0.9, shirt)
	torso.position = Vector3(0.0, torso_h * 0.5, 0.0)
	spine.add_child(torso)
	# The shorts, in the kit's second colour, so the kit reads in two blocks.
	var hips := _capsule(shoulder * 0.7, torso_h * 0.22, shorts)
	hips.position = Vector3(0.0, torso_h * 0.02, 0.0)
	spine.add_child(hips)

	_v_neck(spine, shoulder, torso_h, trim)

	# The number on the back. A squad of twenty-two flat-coloured men is hard to
	# talk about, and a number is how a crowd names one.
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
	# Sat down onto the shoulders. The reference figures have no neck at all and
	# a gap under the chin is the first thing that breaks them. Lifted by however
	# much taller than round this head is, so a long head keeps its chin where a
	# round one has it rather than sinking into the chest.
	head.position = Vector3(0.0, head_r * (appearance.head_height - 0.22), 0.0)
	# Not a ball. The face, the hair and the ears are children of it, so one
	# scale gives a long face or a wide one and everything stretches with it.
	head.scale = Vector3(appearance.head_width, appearance.head_height, appearance.head_width)
	head.name = "Head"
	neck.add_child(head)

	# The eyes sit on the equator of the head, and the face is hung off that
	# rather than placed by hand: the drawn eye row is a little above the middle
	# of the texture, so the texture sits that much below the middle of the
	# skull. Brows above, nose and mouth below, all follow from it.
	var face := _face_quad(head_r, appearance)
	var eye_drop: float = (16.0 - SimFaceAtlas.EYE_ROW) / SimFaceAtlas.GRID * head_r * FACE_QUAD
	face.position = Vector3(0.0, -eye_drop, head_r * 0.96)
	face.name = "Face"
	head.add_child(face)
	# The expression swaps at run time and has to keep the man's own face under
	# it, so the style indices ride on the figure.
	root.set_meta("brow_style", appearance.brow_style)
	root.set_meta("eye_style", appearance.eye_style)
	root.set_meta("mouth_style", appearance.mouth_style)

	_jaw(head, head_r, skin)
	head.add_child(_nose(appearance, head_r))
	_ears(head, head_r, skin)

	var hair := _hair(appearance, head_r)
	if hair != null:
		head.add_child(hair)
	if appearance.moustache:
		_moustache(head, head_r, appearance)
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
		var cuff := _band(limb * 1.18, torso_h * 0.035, trim)
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
		var hand := _sphere(limb * 1.12, skin, true)
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

		var short_leg := _capsule(limb * 1.18, leg_h * 0.15, shorts)
		short_leg.position = Vector3(0.0, -leg_h * 0.05, 0.0)
		hip.add_child(short_leg)

		var knee := Node3D.new()
		knee.name = "Knee" + tag2
		knee.position = Vector3(0.0, -leg_h * 0.47, 0.0)
		hip.add_child(knee)

		# Everyone wears socks. `socks_high` used to leave a man bare-legged to the
		# ankle, and there is no such thing in the reference or in football.
		var shin := _capsule(limb, leg_h * 0.44, toy_material(kit[0]))
		shin.position = Vector3(0.0, -leg_h * 0.22, 0.0)
		knee.add_child(shin)

		# Two hoops near the top of the sock, as the reference has. Pulled-down
		# socks get one, further down.
		var hoops := [0.09, 0.15] if appearance.socks_high else [0.16]
		for band_at in hoops:
			var hoop := _band(limb * 1.04, leg_h * 0.022, trim)
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


# --- The head ---------------------------------------------------------------


## The V of a football shirt: two bars in the second colour laid on the chest and
## a band round the back of the neck to close it. A plain ring was what this used
## to be, and a ring is a crew neck -- every figure in the reference wears a V and
## it is the most legible thing on the kit.
static func _v_neck(spine: Node3D, shoulder: float, torso_h: float, trim: Material) -> void:
	# Each bar leans its top *outwards*. Leaning them the other way -- which is
	# what the first version did -- crosses them at the collarbone and the man is
	# wearing a bow tie.
	for side in [-1.0, 1.0]:
		var bar := _box(
			Vector3(torso_h * 0.05, torso_h * 0.3, shoulder * 0.26), trim)
		bar.position = Vector3(side * shoulder * 0.2, torso_h * 0.76, shoulder * 0.7)
		bar.rotation = Vector3(0.0, 0.0, -side * 0.55)
		spine.add_child(bar)
	# Closed round the back of the neck.
	var back := _band(shoulder * 0.46, torso_h * 0.045, trim)
	back.position = Vector3(0.0, torso_h * 0.93, 0.0)
	spine.add_child(back)


## Noses, in the flesh, as the reference does it: a small upright capsule on the
## front of the head, skin-coloured with the faintest warmth in it. Drawn on the
## texture it is a smudge; as a bump it catches the light and does the job.
##
## Length has to clear twice the radius by a margin or the capsule collapses into
## a sphere, which is what hid the shape the first time.
##
## Each row is [radius, length, height on the face, how far out, z scale].
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
		toy_material(appearance.nose_colour), true)
	nose.name = "Nose"
	nose.position = Vector3(0.0, head_r * float(row[2]), head_r * float(row[3]))
	nose.scale = Vector3(1.0, 1.0, float(row[4]))
	return nose


## A jaw. One sphere is an egg: it tapers to the same point at the bottom as at
## the top, and a head does not. This is a second ellipsoid overlapping the lower
## half, wide enough to stand proud of the skull between the ears and the chin
## and back inside it above and below, which is cheeks rather than a second head.
##
## It stays behind the face quad at 0.96 of the radius, so the drawn mouth is
## never buried.
static func _jaw(head: Node3D, head_r: float, skin: Material) -> void:
	var jaw := _sphere(head_r, skin, true)
	jaw.name = "Jaw"
	# Almost tangent to the skull at the equator and progressively fuller below
	# it. Set squatter than this it crosses the head at an angle and leaves a
	# crease across the cheek, which reads as a mask rather than a jaw.
	jaw.position = Vector3(0.0, -head_r * 0.16, 0.0)
	jaw.scale = Vector3(1.02, 0.9, 0.98)
	head.add_child(jaw)


## Ears: two small tabs where the head is widest. They cost two spheres and they
## are most of why the reference heads read as heads from the side.
static func _ears(head: Node3D, head_r: float, skin: Material) -> void:
	for side in [-1.0, 1.0]:
		var ear := _sphere(head_r * 0.17, skin, true)
		ear.position = Vector3(side * head_r * 0.94, -head_r * 0.06, -head_r * 0.05)
		ear.scale = Vector3(0.55, 1.0, 0.85)
		head.add_child(ear)


## Under the nose and clear of the mouth, in hair colour. Two of the six figures
## in the reference wear one.
static func _moustache(head: Node3D, head_r: float, appearance: SimAppearance) -> void:
	var mat := toy_material(appearance.hair_colour)
	# Two lobes rather than one bar, so it has a shape rather than a moustache
	# sticker.
	for side in [-1.0, 1.0]:
		var half := _sphere(head_r * 0.17, mat, true)
		half.position = Vector3(side * head_r * 0.11, -head_r * 0.3, head_r * 0.88)
		half.scale = Vector3(1.15, 0.5, 0.55)
		head.add_child(half)


# --- Hair -------------------------------------------------------------------
#
# Two numbers do most of it. The **radius** is how much hair there is: a few per
# cent over the skull is hair lying on the head, a fifth over is an afro. The
# **push back** is the hairline: the two spheres meet in a circle, and shoving
# the hair sphere backwards drags that circle up the forehead. Push a small shell
# far back and all that is left is a rim round the silhouette, which is a
# swimming cap; give every style volume instead and you get eleven afros.
#
# On top of the shell sit the pieces that make a style recognisable, which is
# what the reference actually varies: a cluster of **curls**, a **quiff** swept up
# at the front, **tufts** standing up, **sideburns** at the temples, a **peak** at
# the centre of the hairline, and a **mass** down the back.
#
# The limit on every row is the face. The drawn brows sit about a quarter of a
# head-radius above the middle of the face and the face quad is at 0.96 of the
# radius, so no row may reach past about 0.95 at that height.

const HAIR_LIBRARY := [
	{"r": 0.0},  # bald
	{"r": 1.04, "up": 0.08, "back": 0.22},  # cropped
	{"r": 1.06, "up": 0.06, "back": 0.16, "burns": true},  # short back and sides
	{"r": 1.09, "up": 0.05, "back": 0.13, "peak": true},  # a bowl cut with a point
	{"r": 1.11, "up": 0.04, "back": 0.16, "burns": true},  # heavier, with sideburns
	{"r": 1.06, "up": 0.12, "back": 0.16, "quiff": true},  # a quiff
	{"r": 1.05, "up": 0.08, "back": 0.18, "curls": 9},  # curly
	{"r": 1.04, "up": 0.10, "back": 0.20, "curls": 13, "curl_r": 0.34},  # a big curly head
	{"r": 1.06, "up": 0.05, "back": 0.13, "side": 0.05, "quiff": true},  # swept over
	{"r": 1.06, "up": 0.05, "back": 0.13, "mass": true},  # collar length
	{"r": 1.07, "up": 0.04, "back": 0.12, "side": 0.04, "mass": true, "burns": true},  # long
	{"r": 1.04, "up": 0.11, "back": 0.26, "burns": true},  # receding
	{"r": 1.05, "up": 0.10, "back": 0.21, "sy": 0.92, "peak": true},  # thin on top
	{"r": 1.05, "up": 0.08, "back": 0.18, "tufts": 4},  # tousled
]


static func _hair(appearance: SimAppearance, head_r: float) -> Node3D:
	var style: Dictionary = HAIR_LIBRARY[posmod(appearance.hair_style, HAIR_LIBRARY.size())]
	var shell_r: float = style.get("r", 0.0)
	if shell_r <= 0.0:
		return null
	var mat := toy_material(appearance.hair_colour)
	var root := Node3D.new()
	root.name = "Hair"

	var up: float = style.get("up", 0.08)
	var back: float = style.get("back", 0.18)
	var shell := _sphere(head_r * shell_r, mat, true)
	shell.position = Vector3(
		head_r * float(style.get("side", 0.0)), head_r * up, -head_r * back)
	shell.scale = Vector3(1.0, style.get("sy", 1.0), 1.0)
	root.add_child(shell)

	# Curls: a ring of them round the crown and a couple on top. Nine spheres and
	# the head is unmistakable, which no amount of shaping one sphere achieves.
	var curls: int = style.get("curls", 0)
	if curls > 0:
		var curl_r: float = style.get("curl_r", 0.3)
		for i in curls:
			var a := TAU * float(i) / float(curls)
			var ring: float = 0.74 if i % 2 == 0 else 0.62
			var lift: float = 0.42 if i % 2 == 0 else 0.68
			_add_lump(root, head_r, curl_r, mat,
				Vector3(sin(a) * ring, lift, cos(a) * ring - back * 0.6))
		_add_lump(root, head_r, curl_r * 1.05, mat, Vector3(0.0, 0.95, -back * 0.6))

	# A quiff: one lobe swept up off the front of the hairline.
	if style.get("quiff", false):
		var quiff := _sphere(head_r * 0.42, mat, true)
		quiff.position = Vector3(
			head_r * float(style.get("side", 0.0)) * 2.0, head_r * 0.82, head_r * 0.3)
		quiff.scale = Vector3(0.95, 0.85, 0.7)
		root.add_child(quiff)

	# Tufts standing up: the same idea, smaller and scattered.
	var tufts: int = style.get("tufts", 0)
	for i in tufts:
		var a := TAU * (float(i) / float(maxi(tufts, 1))) + 0.4
		_add_lump(root, head_r, 0.26, mat,
			Vector3(sin(a) * 0.4, 0.9 + 0.08 * float(i % 2), cos(a) * 0.4 - back * 0.5))

	# Sideburns: a tab in front of each ear.
	if style.get("burns", false):
		for side in [-1.0, 1.0]:
			var burn := _sphere(head_r * 0.2, mat, true)
			burn.position = Vector3(side * head_r * 0.86, -head_r * 0.16, head_r * 0.2)
			burn.scale = Vector3(0.55, 1.3, 0.9)
			root.add_child(burn)

	# A widow's peak at the centre of the hairline.
	if style.get("peak", false):
		var peak := _sphere(head_r * 0.3, mat, true)
		peak.position = Vector3(0.0, head_r * 0.42, head_r * 0.62)
		peak.scale = Vector3(1.0, 0.5, 0.5)
		root.add_child(peak)

	# The mass down the back of the neck, which is most of what the match camera
	# sees of a long style.
	if style.get("mass", false):
		var mass := _sphere(head_r * 0.78, mat, true)
		mass.position = Vector3(0.0, -head_r * 0.34, -head_r * 0.48)
		mass.scale = Vector3(0.85, 1.15, 0.72)
		root.add_child(mass)

	return root


static func _add_lump(
	root: Node3D, head_r: float, radius: float, mat: Material, at: Vector3
) -> void:
	var lump := _sphere(head_r * radius, mat, true)
	lump.position = at * head_r
	root.add_child(lump)


static func _accessory(
	appearance: SimAppearance,
	head_r: float,
	head: Node3D,
	kit: PackedColorArray
) -> void:
	match appearance.accessory:
		"headband":
			# Clear above the brows, which sit at about four tenths of a radius,
			# and only just wider than the head is at that height -- a band cut to
			# the equator and raised to the forehead is a brim.
			var band := _band(head_r * 0.92, head_r * 0.11, toy_material(kit[0]))
			band.position = Vector3(0.0, head_r * 0.6, 0.0)
			head.add_child(band)
		"cap":
			var cap := _sphere(head_r * 1.05, toy_material(kit[0]), true)
			cap.position = Vector3(0.0, head_r * 0.24, 0.0)
			cap.scale = Vector3(1.0, 0.5, 1.0)
			head.add_child(cap)
		_:
			pass


## Swaps the expression and keeps the man's own face under it. The style indices
## were written onto the figure when it was built, because the sim side of this
## call knows an animation state and nothing else.
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


# --- Primitives -------------------------------------------------------------


static func _capsule(
	radius: float, height: float, material: Material, smooth := false
) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.05)
	mesh.radial_segments = HEAD_SEGMENTS if smooth else SEGMENTS
	mesh.rings = HEAD_RINGS if smooth else RINGS
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
	mesh.radial_segments = HEAD_SEGMENTS
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
