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
## How far the arms hang off the body, and how far the toes turn out. Both are
## small and both are only there to open a gap in the silhouette: a figure with
## its arms against its sides and its feet parallel is one blob at match
## distance, and stands to attention up close.
const ARM_FLARE := 0.14
const TOE_OUT := 0.17
const SEGMENTS := 12
const RINGS := 6
## The head, the hair and the shoes are rounder than the rest of the figure. A
## twelve-sided sphere is a chunky limb and a boxy skull, and the skull is the
## thing being looked at.
##
## Thirty-two rather than twenty-four because of the hairline. It is the seam
## between two of these spheres, and a seam is only as smooth as the coarser of
## the two: at twenty-four it stepped visibly across the temple close up.
const HEAD_SEGMENTS := 32
const HEAD_RINGS := 16
## The drawn face, as a fraction of the head radius, how far out from the middle
## of the head it is bent, and how many columns the bend is made of.
const FACE_QUAD := 1.5
const FACE_SHELL := 1.02
const FACE_COLUMNS := 14
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
	# The shorts are their own colour where a kit carries one. A two-colour kit
	# falls back to the trim, which is what every kit used to do.
	var shorts_colour: Color = second_colour if kit.size() < 3 else kit[2]
	var shirt := toy_material(kit[0])
	var shorts := toy_material(shorts_colour)
	var trim := toy_material(second_colour)
	var skin := toy_material(appearance.skin)
	var boot := toy_material(SimPalette.INK)

	# --- Torso, on a pivot so the whole upper body can lean ------------------
	var spine := Node3D.new()
	spine.name = "Spine"
	spine.position = Vector3(0.0, leg_h, 0.0)
	root.add_child(spine)

	# Wide enough at the chest and long enough to have a straight section in the
	# middle. At 0.82 by 0.9 the capsule's height was barely twice its radius, so
	# it was a sphere in all but name: widest at the belly, tapering back in at the
	# chest, which is a pear. The widest part of a man is his shoulders.
	var torso := _capsule(shoulder * 0.76, torso_h, shirt)
	torso.position = Vector3(0.0, torso_h * 0.5, 0.0)
	spine.add_child(torso)
	# The shorts, in the kit's second colour, so the kit reads in two blocks.
	#
	# A flattened sphere rather than a capsule. `_capsule` floors the height at
	# twice the radius, so a garment this wide and this short was silently turned
	# back into a ball -- one hanging a fifth of a leg below the hip, bridging both
	# thighs, with a curved hem straight across. That is a nappy, and in a white
	# kit it is unmistakably one.
	var hips := _sphere(shoulder * 0.62, shorts, true)
	hips.scale = Vector3(1.0, 0.55, 0.95)
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
		digits.pixel_size = torso_h * 0.0027
		digits.modulate = second_colour
		digits.outline_size = 24
		digits.outline_modulate = SimPalette.INK
		digits.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		# Cut rather than blended: a blended quad this close to the torso sorts
		# against it and flickers as the figure turns.
		digits.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		# Between the shoulder blades. At 0.68 the top of the digit ran into the
		# collar and the shoulder took a bite out of it.
		digits.position = Vector3(0.0, torso_h * 0.5, -shoulder * 0.78 - 0.01)
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
	var face := _face_shell(head_r, appearance)
	var eye_drop: float = (16.0 - SimFaceAtlas.EYE_ROW) / SimFaceAtlas.GRID * head_r * FACE_QUAD
	# Only down the head. The bend is round the vertical axis, so sliding the
	# strip down it keeps every part of it the same distance out.
	face.position = Vector3(0.0, -eye_drop, 0.0)
	face.name = "Face"
	head.add_child(face)
	# The expression swaps at run time and has to keep the man's own face under
	# it, so the style indices ride on the figure.
	root.set_meta("brow_style", appearance.brow_style)
	root.set_meta("eye_style", appearance.eye_style)
	root.set_meta("mouth_style", appearance.mouth_style)

	_jaw(head, head_r, skin)
	_crown(head, head_r, skin)
	head.add_child(_nose(appearance, head_r))
	_ears(head, head_r, skin)

	var hair := _hair(appearance, head_r)
	if hair != null:
		head.add_child(hair)
	if appearance.moustache:
		_moustache(head, head_r, appearance)
	_accessory(appearance, head_r, head, kit)

	# --- Arms: shoulder pivot, upper arm, elbow pivot, forearm, mitten ------
	#
	# The pivot sits high and outside the torso. Set at 0.82 it was inside the
	# capsule, so the arm came out of the ribs and the figure had no shoulder line
	# at all. The line comes from the top of the arm itself, under the shirt: a
	# ball laid over the joint gives a shoulder pad and an action figure.
	#
	# The flare is on the meshes rather than on the pivot, because the animation
	# layer assigns `rotation` on every joint it poses and would wipe a rest angle
	# the moment a man moved. Hung straight down, arms and hands touch the shorts
	# and the whole figure is one mass at match distance; a few degrees out is the
	# cheapest daylight in the silhouette there is.
	var upper_len := torso_h * 0.52
	for side in [-1.0, 1.0]:
		var tag: String = "L" if side < 0.0 else "R"
		var sh := Node3D.new()
		sh.name = "Shoulder" + tag
		sh.position = Vector3(side * shoulder * 0.64, torso_h * 0.86, 0.0)
		spine.add_child(sh)

		var upper_mat := shirt if appearance.sleeves_long else skin
		var upper := _capsule(limb, upper_len, upper_mat)
		upper.position = Vector3(
			side * sin(ARM_FLARE) * upper_len * 0.5, -cos(ARM_FLARE) * upper_len * 0.5, 0.0)
		upper.rotation = Vector3(0.0, 0.0, side * ARM_FLARE)
		sh.add_child(upper)

		# A short sleeve is still a sleeve. Without this the arm is bare to the
		# shoulder and the shirt reads as a vest.
		#
		# A cylinder, not a capsule: a capsule's rounded end tapers to nothing, so
		# the cuff round it stood wider than the sleeve it was supposed to finish
		# and read as a bracelet on a bare arm. A cylinder has a hem.
		if not appearance.sleeves_long:
			# It starts above the joint, not at it. The arm's own rounded end
			# stands proud of the shoulder, and on a short sleeve that end is bare
			# skin, so a sleeve that begins at the pivot leaves a crescent of naked
			# shoulder above it.
			var sleeve_len := upper_len * 0.5 + limb
			var sleeve_at := sleeve_len * 0.5 - limb
			var sleeve := _band(limb * 1.16, sleeve_len, shirt)
			sleeve.position = Vector3(
				side * sin(ARM_FLARE) * sleeve_at, -cos(ARM_FLARE) * sleeve_at, 0.0)
			sleeve.rotation = Vector3(0.0, 0.0, side * ARM_FLARE)
			sh.add_child(sleeve)

		# The trim at the end of the sleeve, long or short. On a long sleeve it
		# sits short of the elbow, where the arm is still full width.
		var cuff_at: float = upper_len * (0.85 if appearance.sleeves_long else 0.46)
		var cuff := _band(limb * (1.14 if appearance.sleeves_long else 1.22), torso_h * 0.035, trim)
		cuff.position = Vector3(
			side * sin(ARM_FLARE) * cuff_at, -cos(ARM_FLARE) * cuff_at, 0.0)
		cuff.rotation = Vector3(0.0, 0.0, side * ARM_FLARE)
		sh.add_child(cuff)

		var elbow := Node3D.new()
		elbow.name = "Elbow" + tag
		elbow.position = Vector3(
			side * sin(ARM_FLARE) * upper_len, -cos(ARM_FLARE) * upper_len, 0.0)
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

		# The leg of the shorts hangs lower than the seat does. That is what puts a
		# notch between the legs; a seat that reaches further down than these fills
		# the notch in and the shorts are one block again.
		var short_leg := _capsule(limb * 1.3, leg_h * 0.19, shorts)
		short_leg.position = Vector3(0.0, -leg_h * 0.07, 0.0)
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
		# Turned out, like a man standing rather than a man on parade. On the mesh
		# and not on the ankle, which the animation layer poses.
		foot.rotation = Vector3(0.0, side * TOE_OUT, 0.0)
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
	#
	# Set deep, so that most of each bar is inside the chest and only a sliver of
	# it stands proud. Laid on the surface they were two tabs hovering in front of
	# a round torso -- braces rather than a collar -- because a straight box
	# touching a curve touches it in one place only.
	for side in [-1.0, 1.0]:
		var bar := _box(
			Vector3(torso_h * 0.042, torso_h * 0.24, shoulder * 0.34), trim)
		bar.position = Vector3(side * shoulder * 0.18, torso_h * 0.72, shoulder * 0.55)
		# Pitched back at the top as well as leaned out, because the chest is a
		# dome and a straight bar on a dome only touches it in the middle. Without
		# this the top of each bar hangs off the front of the shoulder in the air.
		bar.rotation = Vector3(-0.4, 0.0, -side * 0.55)
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
## half, fuller than the skull down the cheeks and the chin and back inside it
## above, which is a jaw rather than a second head.
##
## It stays inside `FACE_SHELL`, so the drawn mouth is never buried.
static func _jaw(head: Node3D, head_r: float, skin: Material) -> void:
	var jaw := _sphere(head_r, skin, true)
	jaw.name = "Jaw"
	# Tangent to the skull at the equator and progressively fuller below it. The
	# width was 1.02, which made it stand proud all the way up past the ears and
	# cross the skull at an angle: two smooth surfaces meeting at an angle leave a
	# lit crease, and on a bald man that crease ran across his face. At 1.0 it
	# crosses almost tangentially and the seam goes.
	jaw.position = Vector3(0.0, -head_r * 0.14, 0.0)
	jaw.scale = Vector3(1.0, 0.92, 0.99)
	head.add_child(jaw)


## The same trick as the jaw, mirrored: the stretch that makes a head taller than
## wide also draws the crown to a point, and a skull is domed. This fills the top
## back out without making the head any taller.
static func _crown(head: Node3D, head_r: float, skin: Material) -> void:
	var crown := _sphere(head_r, skin, true)
	crown.name = "Crown"
	crown.position = Vector3(0.0, head_r * 0.12, 0.0)
	crown.scale = Vector3(1.0, 0.9, 0.99)
	head.add_child(crown)


## Ears: two small tabs where the head is widest. They cost two spheres and they
## are most of why the reference heads read as heads from the side.
##
## They have to stand clear of the jaw, which is wider than the skull at this
## height, and clear of the hair shell. Set at 0.94 they reached 1.03 and the jaw
## reached 1.01, so they were flush with the head and inside every cut but the
## bald one: thirteen men in fourteen had no ears at all.
static func _ears(head: Node3D, head_r: float, skin: Material) -> void:
	for side in [-1.0, 1.0]:
		var ear := _sphere(head_r * 0.17, skin, true)
		ear.position = Vector3(side * head_r * 0.96, -head_r * 0.1, -head_r * 0.05)
		ear.scale = Vector3(0.6, 1.0, 0.85)
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
# Every cut carries some volume -- a shell at least a tenth over the skull -- and
# the push back is raised to match so the hairline stays put. Hair that merely
# skims the head reads as paint on the scalp; the difference between a full cut
# and an afro is the curls on top of it, not the shell.
#
# The shell is also **flattened and lifted**, which is what gives it a bottom
# edge. A ball centred on the skull has one: a sphere pushed back to open the
# face still reaches down past the jaw everywhere behind the ears, so from behind
# there is no hairline at all -- the head is one solid ball of hair colour, and
# the ears are inside it. Squashed to `HAIR_SQUASH` and raised by `HAIR_LIFT`,
# the same sphere clears the skull below the nape and beside the ears, and its
# underside becomes the back hairline exactly the way its front already makes the
# front one. Long styles put their length back with `mass`, which is now a piece
# hanging below a hairline rather than more helmet.
#
# The limit on every row is the face. The drawn brows sit about a quarter of a
# head-radius above the middle of the face and the face shell is just outside the
# skull, so no row may reach past about 0.95 at that height. Lifting the shell
# puts its widest ring at about brow height, so that reach is now `radius - back
# - HAIR_BACK_EXTRA`, and the rule is `back >= radius - 1.00`.

## How flat the shell is, how far up it sits, and how much further back it goes
## to pay for the lift. The three move together: flattening alone bares the
## crown, lifting alone drags the front hairline down over the brows.
const HAIR_SQUASH := 0.72
const HAIR_LIFT := 0.24
const HAIR_BACK_EXTRA := 0.05

const HAIR_LIBRARY := [
	{"r": 0.0},  # bald
	{"r": 1.12, "up": 0.08, "back": 0.20},  # cropped
	{"r": 1.14, "up": 0.07, "back": 0.21, "burns": true},  # short back and sides
	{"r": 1.16, "up": 0.06, "back": 0.22, "peak": true},  # a bowl cut with a point
	{"r": 1.18, "up": 0.05, "back": 0.24, "burns": true},  # heavier, with sideburns
	{"r": 1.14, "up": 0.12, "back": 0.20, "quiff": true},  # a quiff
	{"r": 1.10, "up": 0.08, "back": 0.18, "curls": 9},  # curly
	{"r": 1.10, "up": 0.10, "back": 0.18, "curls": 13, "curl_r": 0.34},  # a big curly head
	{"r": 1.14, "up": 0.06, "back": 0.21, "quiff": true, "burns": true},  # swept over
	{"r": 1.14, "up": 0.06, "back": 0.20, "mass": 1.0},  # collar length
	{"r": 1.16, "up": 0.05, "back": 0.22, "mass": 1.0, "burns": true},  # long
	{"r": 1.10, "up": 0.11, "back": 0.28, "burns": true},  # receding
	{"r": 1.11, "up": 0.10, "back": 0.24, "sy": 0.94, "peak": true},  # thin on top
	{"r": 1.14, "up": 0.08, "back": 0.21, "tufts": 4},  # tousled
	# Short on top, long at the back, and sideburns to finish it.
	{"r": 1.10, "up": 0.07, "back": 0.22, "mass": 1.45, "burns": true},  # a mullet
	# Combed back off a slightly high forehead, with the dome on top carrying the
	# sweep. Two things this row cannot do: shrink the shell, which sinks its top
	# to the skull and leaves a bald man with a rim, or push it much further back,
	# which takes the hairline up to the crown and leaves the same man.
	{"r": 1.12, "up": 0.06, "back": 0.21, "slick": true},  # slicked back
	{"r": 1.13, "up": 0.05, "back": 0.22, "slick": true, "burns": true},  # slicked, with burns
	# Going, and going faster. Dropping the shell below its usual lift lets the
	# crown come up through it, which is a bald patch with hair all round it --
	# a thinning man rather than a bald one, and the difference is the patch.
	{"r": 1.13, "up": -0.05, "back": 0.24, "burns": true},  # thinning
	{"r": 1.13, "up": -0.13, "back": 0.27},  # thin to the bone
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
		0.0, head_r * (up + HAIR_LIFT), -head_r * (back + HAIR_BACK_EXTRA))
	shell.scale = Vector3(1.0, float(style.get("sy", 1.0)) * HAIR_SQUASH, 1.0)
	root.add_child(shell)

	# Curls: a ring of them round the crown and a couple on top. Nine spheres and
	# the head is unmistakable, which no amount of shaping one sphere achieves.
	var curls: int = style.get("curls", 0)
	if curls > 0:
		var curl_r: float = style.get("curl_r", 0.3)
		for i in curls:
			var a := TAU * float(i) / float(curls)
			# Alternated by distance round the ring rather than by index, so a curl
			# and its mirror get the same treatment. Counted by index with an odd
			# number of curls -- nine and thirteen, both of them -- the two halves
			# of the head came out different.
			var out := mini(i, curls - i) % 2 == 0
			var ring: float = 0.82 if out else 0.68
			var lift: float = 0.52 if out else 0.78
			_add_lump(root, head_r, curl_r, mat,
				Vector3(sin(a) * ring, lift, cos(a) * ring - back * 0.6))
		_add_lump(root, head_r, curl_r * 1.05, mat, Vector3(0.0, 1.05, -back * 0.6))

	# A quiff: hair swept up off the front of the hairline. One lobe on top of the
	# shell is a ball resting on a head and reads as nothing at all. Three across
	# the front, tallest and furthest forward in the middle and falling away to
	# either side, is a front with a shape to it.
	if style.get("quiff", false):
		for i in 3:
			var across := float(i) - 1.0
			var off := absf(across)
			var lobe := _sphere(head_r * (0.36 - off * 0.08), mat, true)
			lobe.position = Vector3(
				across * head_r * 0.33,
				head_r * (0.82 - off * 0.12),
				head_r * (0.32 - off * 0.14))
			lobe.scale = Vector3(1.0, 0.9, 0.72)
			root.add_child(lobe)

	# Swept back instead: a low wide dome over the crown, running to the back of
	# the head. With the hairline pushed well up the forehead it reads as hair
	# combed back off the face rather than hair grown forward over it.
	if style.get("slick", false):
		var slick := _sphere(head_r * 0.42, mat, true)
		slick.position = Vector3(0.0, head_r * 0.86, -head_r * 0.42)
		slick.scale = Vector3(1.15, 0.75, 1.9)
		root.add_child(slick)

	# Tufts standing up: the same idea, smaller and scattered. Scattered evenly
	# from straight ahead, and raised by distance round the ring rather than by
	# index, for the same reason the curls are.
	var tufts: int = style.get("tufts", 0)
	for i in tufts:
		var a := TAU * (float(i) / float(maxi(tufts, 1)))
		var high := mini(i, tufts - i) % 2
		_add_lump(root, head_r, 0.26, mat,
			Vector3(sin(a) * 0.4, 0.9 + 0.08 * float(high), cos(a) * 0.4 - back * 0.5))

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
	# sees of a long style. The number is how long: 1 is collar length, and much
	# past 1.4 it is a cape.
	var mass: float = style.get("mass", 0.0)
	if mass > 0.0:
		var back_hair := _sphere(head_r * 0.78 * sqrt(mass), mat, true)
		back_hair.position = Vector3(0.0, -head_r * 0.34 * mass, -head_r * 0.48)
		back_hair.scale = Vector3(0.85, 1.15, 0.72)
		root.add_child(back_hair)

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


## The drawn face, bent round the skull instead of laid flat against it.
##
## A flat plate is right head-on and wrong from anywhere else. At three-quarters
## -- which is the angle the match camera actually holds -- the features slide
## towards the near edge of the plate and the far brow drifts off the cheek. One
## strip of triangles bent round the vertical axis fixes it.
##
## Bent one way only. The head yaws far more than it nods, and a vertical bend
## would have to clear the jaw, which stands proud exactly where the mouth is.
##
## The strip sits a little outside the skull, so nothing underneath can poke
## through the face, and it is drawn on both sides because the back of it is
## inside the head where nobody can see it.
static func _face_shell(head_r: float, appearance: SimAppearance) -> MeshInstance3D:
	var size := head_r * FACE_QUAD
	var radius := head_r * FACE_SHELL
	var half := size * 0.5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in FACE_COLUMNS + 1:
		var u := float(i) / float(FACE_COLUMNS)
		# Arc length, not chord: the eyes stay as far apart on the curve as they
		# were on the flat plate.
		var angle: float = (u - 0.5) * size / radius
		var at := Vector3(sin(angle), 0.0, cos(angle))
		verts.push_back(at * radius + Vector3(0.0, half, 0.0))
		verts.push_back(at * radius - Vector3(0.0, half, 0.0))
		uvs.push_back(Vector2(u, 0.0))
		uvs.push_back(Vector2(u, 1.0))
		normals.push_back(at)
		normals.push_back(at)
	for i in FACE_COLUMNS:
		var a := i * 2
		indices.append_array([a, a + 1, a + 2, a + 2, a + 1, a + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var node := MeshInstance3D.new()
	node.mesh = mesh
	var m := flat_material(Color.WHITE)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = SimFaceAtlas.texture_for(
		SimAppearance.Face.NEUTRAL, appearance.brow_style, appearance.eye_style,
		appearance.mouth_style)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = m
	return node
