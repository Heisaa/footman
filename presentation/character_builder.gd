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

## Proportions as fractions of total height, measured off the owner's vinyl
## reference rather than argued about (`DECISIONS.md`, eleventh).
##
## A big head, a long torso and short legs -- the squat toy, not a small man.
## The tenth amendment went the other way, from a rank of slimmer toys; this
## reference is the chunky moulded kind and it wins because the owner supplied
## it. Head, torso and legs come to roughly the whole height between them, which
## is the check to make if any of the three is moved.
const LEG_FRACTION := 0.26
const TORSO_FRACTION := 0.37
## Shoulder half-width, as a fraction of height, before the build multiplier.
## Wider than it was: a head this size on the old narrow chest is a lollipop.
const SHOULDER_FRACTION := 0.185
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
## How deep the moulded brow is, as a share of its drawn half-thickness. It has
## to stay inside the nose: the nose reaches about 1.09 head-radii and a brow
## that stands further out than a man's nose is a brow ridge on a hominid.
const BROW_DEPTH := 0.6
## Moulded vinyl, not paper: the reference figures carry a soft highlight and it
## is most of what makes them read as objects rather than flat shapes. Scenery
## keeps the old dead-flat material.
const TOY_ROUGHNESS := 0.42
const TOY_SPECULAR := 0.45


## The crease shading that makes a figure read as a moulded object rather than a
## set of coloured shapes, applied to whatever `Environment` a view has built.
##
## This is most of the difference between our figures and the owner's reference.
## The reference is not lit differently from ours in any interesting way -- it is
## that every crease is dark: under the chin, along the hairline, inside the V of
## the collar, under the sleeve, between the legs. Flat colour with no contact
## shading is a shape; flat colour with it is a thing you could pick up.
##
## The radius is in metres and is set for a person: a few centimetres is the size
## of the creases on a figure, and a metre-wide radius darkens whole limbs
## instead. `light_affect` is left at zero so the sun never scrubs the crease out
## again -- on a figure this bright that is exactly where it would.
##
## It is a screen-space pass and it is not free. `view3d` carries twenty-two
## figures; if a frame budget is ever the question, this is the first switch.
static func add_crease_shading(env: Environment) -> void:
	env.ssao_enabled = true
	env.ssao_radius = 0.35
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.4
	env.ssao_light_affect = 0.0


## The sun a moulded figure wants: a soft-edged shadow rather than a stencil.
## Vinyl in a photograph is lit through something broad, and the giveaway is the
## edge of the shadow it casts, not its brightness.
static func soften_shadow(sun: DirectionalLight3D) -> void:
	sun.light_angular_distance = 1.6
	sun.shadow_blur = 1.4


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
	# A cylinder with a soft cap, not a capsule. At this height and width a
	# capsule is two domes with almost no straight section between them -- a ball
	# in a shirt. The reference shirt has straight sides and rounds over only at
	# the shoulder, and the bottom hem is square because the shorts cover it.
	var torso := _band(shoulder * 0.74, torso_h * 0.90, shirt)
	torso.position = Vector3(0.0, torso_h * 0.45, 0.0)
	spine.add_child(torso)
	var shoulders := _sphere(shoulder * 0.74, shirt, true)
	shoulders.scale = Vector3(1.0, 0.44, 1.0)
	shoulders.position = Vector3(0.0, torso_h * 0.90, 0.0)
	spine.add_child(shoulders)
	# The shorts, in the kit's second colour, so the kit reads in two blocks.
	#
	# A cylinder, so they have straight sides and a hem you can see. Every earlier
	# version was a rounded solid -- a capsule, then a flattened sphere -- and
	# both bulged wider than the hips and finished in a curved lower edge. That is
	# an inner tube, and on a pale kit it is unmistakably a nappy. A garment has a
	# flat hem; that one edge is most of what makes it read as clothing.
	var hips := _band(shoulder * 0.66, leg_h * 0.46, shorts)
	hips.position = Vector3(0.0, -leg_h * 0.06, 0.0)
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
	# The brows are posed from the head's own size long after it is built.
	root.set_meta("head_r", head_r)

	_jaw(head, head_r, skin)
	_crown(head, head_r, skin)
	head.add_child(_nose(appearance, head_r))
	_ears(head, head_r, skin)
	_brows(head, head_r, appearance)
	_pose_brows(root, SimAppearance.Face.NEUTRAL)

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
		# the notch in and the shorts are one block again. A cylinder for the same
		# reason the seat is one -- it is the hem that reads.
		var short_leg := _band(limb * 1.4, leg_h * 0.42, shorts)
		short_leg.position = Vector3(0.0, -leg_h * 0.21, 0.0)
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
		# Set out at the chest's own radius, not inside it. The torso used to be a
		# capsule, which narrows towards the top, so a bar buried at 0.55 still
		# broke the surface up near the collar. Against a cylinder of constant
		# radius the same bar is simply inside the shirt, and all that showed was
		# the two tips -- a small dark "w" printed mid-chest.
		var bar := _box(
			Vector3(torso_h * 0.040, torso_h * 0.19, shoulder * 0.30), trim)
		bar.position = Vector3(side * shoulder * 0.17, torso_h * 0.86, shoulder * 0.70)
		# Pitched back at the top as well as leaned out, because the chest is a
		# dome and a straight bar on a dome only touches it in the middle. Without
		# this the top of each bar hangs off the front of the shoulder in the air.
		bar.rotation = Vector3(-0.28, 0.0, -side * 0.55)
		spine.add_child(bar)
	# Closed round the back of the neck. Just outside the shirt for the same
	# reason the bars are: at 0.46 of the shoulder this ring was inside a 0.74
	# cylinder and never appeared at all.
	var back := _band(shoulder * 0.755, torso_h * 0.035, trim)
	back.position = Vector3(0.0, torso_h * 0.90, 0.0)
	spine.add_child(back)


## Noses, in the flesh, as the reference does it: a small upright capsule on the
## front of the head, skin-coloured with the faintest warmth in it. Drawn on the
## texture it is a smudge; as a bump it catches the light and does the job.
##
## Length has to clear twice the radius by a margin or the capsule collapses into
## a sphere, which is what hid the shape the first time.
##
## Each row is [radius, length, height on the face, how far out, z scale].
## Bigger and rounder than they were. On the reference the nose is one of the
## three things you see at a glance, a soft rounded bump about an eighth of the
## head across; ours were half that and drawn long, so they read as a small beak
## rather than a button. Length still has to clear 2.05 times the radius or
## `_capsule` floors it into a sphere -- which for the roundest rows here is very
## nearly what is wanted anyway.
const NOSE_LIBRARY := [
	[0.118, 0.27, -0.13, 1.00, 1.05],  # a small straight one
	[0.128, 0.30, -0.14, 0.99, 0.95],  # broader
	[0.108, 0.24, -0.12, 1.01, 1.15],  # short and fine
	[0.135, 0.34, -0.16, 0.99, 1.00],  # a big one
	[0.105, 0.23, -0.11, 1.01, 1.00],  # a neat short one, high on the face
	[0.138, 0.32, -0.15, 0.98, 0.95],  # broad
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


## Brows, moulded rather than drawn.
##
## In the reference these are the most characterful thing on the figure: thick
## rounded ridges in the man's hair colour, standing proud enough to catch the
## light along the top. Drawn flat on the face texture they were an ink line on a
## moulded head -- the one feature that stayed a drawing when everything around
## it had become an object.
##
## They are placed off the same unit grid the face texture is drawn in, so a brow
## lands exactly where the drawn one did: `SimFaceAtlas.brow_pose` is the single
## table, and `_pose_brows` turns its four numbers into a position, a roll and a
## scale. Children of the head, so a long face stretches them with everything
## else.
static func _brows(head: Node3D, head_r: float, appearance: SimAppearance) -> void:
	var node := Node3D.new()
	node.name = "Brows"
	head.add_child(node)
	# A unit sphere in grid units, scaled to length and thickness when posed.
	var unit := head_r * FACE_QUAD / SimFaceAtlas.GRID
	var mat := toy_material(appearance.hair_colour)
	for side in [-1.0, 1.0]:
		var bar := _sphere(unit, mat, true)
		bar.name = "Brow" + ("L" if side < 0.0 else "R")
		node.add_child(bar)


## Puts the brows where the moment wants them. Called once at build and again on
## every expression change, which is what makes the expression read at all.
static func _pose_brows(root: Node3D, face: int) -> void:
	var brows := root.find_child("Brows", true, false)
	if brows == null:
		return
	var head_r: float = root.get_meta("head_r", 0.0)
	if head_r <= 0.0:
		return
	var pose := SimFaceAtlas.brow_pose(int(root.get_meta("brow_style", 0)), face)
	var eye: Dictionary = SimFaceAtlas.EYE_STYLES[posmod(
		int(root.get_meta("eye_style", 0)), SimFaceAtlas.EYE_STYLES.size())]
	var half: float = pose["half"]
	var thick: float = pose["thick"]
	var unit := head_r * FACE_QUAD / SimFaceAtlas.GRID
	var radius := head_r * FACE_SHELL
	# Grid y counts downward from the top of the face and the eye row is the
	# datum the whole face hangs off, so this is the same arithmetic the face
	# quad gets, one feature at a time.
	var y_grid: float = float(eye["y"]) - float(pose["lift"])
	# `tilt` is the rise at the ends over a run of `half`, which is an angle.
	var roll: float = atan2(float(pose["tilt"]), maxf(half, 0.001))
	for child in brows.get_children():
		var bar := child as MeshInstance3D
		if bar == null:
			continue
		# A man with no brows has none to show until he needs them to shout with.
		bar.visible = half > 0.0
		if not bar.visible:
			continue
		var side := -1.0 if String(bar.name).ends_with("L") else 1.0
		var x_grid: float = 16.0 + side * float(eye["gap"])
		# The face is bent round the vertical axis, so a feature's place on it is
		# an angle, not an offset.
		var angle: float = (x_grid / SimFaceAtlas.GRID - 0.5) * (head_r * FACE_QUAD) / radius
		bar.position = Vector3(
			sin(angle) * radius,
			unit * (SimFaceAtlas.EYE_ROW - y_grid),
			cos(angle) * radius)
		# Roll in the plane of the face first, then swing round the head. Godot's
		# default euler order applies Z before Y, which is that order exactly.
		bar.rotation = Vector3(0.0, angle, side * roll)
		bar.scale = Vector3(half, thick, thick * BROW_DEPTH)


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
		# Wide and shallow, and set close under the nose. Deeper than this it
		# stops reading as a moustache and starts reading as a mouth -- a dark
		# curved mass where a mouth belongs is a scowl, whoever is wearing it.
		# Out at the face, not inside it. The skull at this height reaches about
		# 0.97 of a radius forward, so a lobe centred at 0.88 with a depth of 0.08
		# is buried except at its two widest points -- which showed as a pair of
		# dark dots either side of the mouth, like a smirk drawn on.
		var half := _sphere(head_r * 0.16, mat, true)
		half.position = Vector3(side * head_r * 0.13, -head_r * 0.26, head_r * 0.95)
		half.scale = Vector3(1.35, 0.36, 0.5)
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
## Raising the shell drags the hairline down the forehead, and this is what pays
## for it. It is a tax on every row, so it is the one number to reach for when the
## whole squad looks like it is receding: 0.05 put every hairline a tenth of a
## radius too high.
const HAIR_BACK_EXTRA := 0.0

const HAIR_LIBRARY := [
	{"r": 0.0},  # bald
	{"r": 1.12, "up": 0.08, "back": 0.20},  # cropped
	{"r": 1.14, "up": 0.07, "back": 0.21, "burns": true},  # short back and sides
	{"r": 1.16, "up": 0.06, "back": 0.22, "peak": true},  # a bowl cut with a point
	{"r": 1.18, "up": 0.05, "back": 0.22, "burns": true},  # heavier, with sideburns
	{"r": 1.14, "up": 0.12, "back": 0.20, "quiff": true},  # a quiff
	{"r": 1.10, "up": 0.08, "back": 0.18, "curls": 12},  # curly
	# The reference perm: a heavy ring of fat lobes carried down past the ears.
	{"r": 1.10, "up": 0.10, "back": 0.18, "curls": 16, "curl_r": 0.40,
		"curl_skirt": true},  # a big curly head
	{"r": 1.14, "up": 0.06, "back": 0.21, "quiff": true, "burns": true},  # swept over
	{"r": 1.14, "up": 0.06, "back": 0.20, "mass": 1.0},  # collar length
	{"r": 1.16, "up": 0.05, "back": 0.22, "mass": 1.0, "burns": true},  # long
	{"r": 1.10, "up": 0.11, "back": 0.25, "burns": true},  # receding
	{"r": 1.11, "up": 0.10, "back": 0.22, "sy": 0.94, "peak": true},  # thin on top
	{"r": 1.14, "up": 0.08, "back": 0.21, "tufts": 4},  # tousled
	# Short on top, long at the back, and sideburns to finish it.
	{"r": 1.10, "up": 0.07, "back": 0.22, "mass": 1.45, "burns": true},  # a mullet
	# Combed back off a slightly high forehead, with the dome on top carrying the
	# sweep. Two things this row cannot do: shrink the shell, which sinks its top
	# to the skull and leaves a bald man with a rim, or push it much further back,
	# which takes the hairline up to the crown and leaves the same man.
	{"r": 1.12, "up": 0.06, "back": 0.21, "slick": true},  # slicked back
	{"r": 1.13, "up": 0.05, "back": 0.22, "slick": true, "burns": true},  # slicked, with burns
	# Going. Dropping the shell below its usual lift takes it off the front and the
	# top and leaves the hair round the sides and the back.
	#
	# One row of this, not two. A squad already has a bald man, a receding one and
	# a thin-on-top one, and four men in nineteen losing their hair is a squad of
	# veterans.
	{"r": 1.13, "up": -0.05, "back": 0.22, "burns": true},  # thinning
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
	#
	# Bigger and more numerous than they were, against the owner's reference: a
	# perm there is a dozen and a half fat lobes, each about a fifth of the head
	# across, not a sparse ring of small ones. Small curls at this count read as
	# gravel on the scalp.
	var curls: int = style.get("curls", 0)
	if curls > 0:
		var curl_r: float = style.get("curl_r", 0.34)
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

		# The skirt: a second ring lower down, which is what makes a perm rather
		# than a curly cap. In the reference the mass comes down past the ears to
		# about the jaw and frames the face; ours stopped above the brow, so it
		# was hair sitting on top of a head.
		#
		# The front is left out of it -- `cos(a)` positive is towards the face --
		# because a curl there is not a fringe, it is a hand over the eyes.
		if style.get("curl_skirt", false):
			for i in curls:
				var a2 := TAU * float(i) / float(curls)
				if cos(a2) > 0.35:
					continue
				_add_lump(root, head_r, curl_r * 0.9, mat,
					Vector3(sin(a2) * 0.88, -0.10, cos(a2) * 0.88 - back * 0.5))

	# A quiff: hair swept up off the front of the hairline. One lobe on top of the
	# shell is a ball resting on a head and reads as nothing at all. Three across
	# the front, tallest and furthest forward in the middle and falling away to
	# either side, is a front with a shape to it.
	if style.get("quiff", false):
		# The whole top of the head, filled with lobes that get taller and bigger
		# towards the front, so the hair swells forward and breaks over the brow.
		#
		# Anything less than the whole top fails the same way twice over. A single
		# lobe at the hairline is a ball resting on a head. A row of three is a
		# ball resting on a head as well, because the two outer ones sit under the
		# surface of the shell and only the middle one ever shows. What makes a
		# quiff read is not the lump at the front, it is that the hair behind the
		# lump rises to meet it.
		#
		# Each lobe is placed by where its top should come, not by where its middle
		# goes: the back row is set flush with the shell so the fill starts
		# invisibly, and every row after it stands that much prouder.
		# Four rows of five, small and heavily overlapped. Nine bigger ones covered
		# the same shape but each was its own bump: it is the count that makes a
		# mass, not the size, and stretching a few lobes wide enough to touch only
		# turns nine bumps into nine ridges.
		# One wide, flattened mass swept up over the front of the crown, rather
		# than a grid of lobes.
		#
		# The grid was five lobes across by four back, and however much they were
		# overlapped the top of the head came out scalloped -- five distinct buds
		# in a row, which reads as a topknot. Overlapping spheres still meet in a
		# valley, and a valley on a crown is a bud either side of it. The note
		# that a single lobe is "a ball resting on a head" was written about a
		# small one placed at the hairline; a wide flat one that starts inside the
		# shell at the back and rises out of it at the front is a sweep, and the
		# shell hides where it begins.
		var sweep := _sphere(head_r * 0.52, mat, true)
		sweep.position = Vector3(0.0, head_r * 0.74, head_r * 0.16)
		sweep.scale = Vector3(1.14, 0.62, 1.0)
		root.add_child(sweep)
		# The break over the brow: a smaller mass further forward and higher, so
		# the front edge stands up rather than tapering away to the hairline.
		var crest := _sphere(head_r * 0.34, mat, true)
		crest.position = Vector3(0.0, head_r * 0.86, head_r * 0.40)
		crest.scale = Vector3(1.18, 0.72, 0.9)
		root.add_child(crest)

	# Swept back instead: a low wide dome over the crown, running to the back of
	# the head. With the hairline pushed well up the forehead it reads as hair
	# combed back off the face rather than hair grown forward over it.
	if style.get("slick", false):
		var slick := _sphere(head_r * 0.42, mat, true)
		slick.position = Vector3(0.0, head_r * 0.86, -head_r * 0.42)
		slick.scale = Vector3(1.15, 0.75, 1.9)
		root.add_child(slick)

	# Tufts: hair that will not lie flat. Wide, shallow and set low enough to
	# break the shell rather than sit on it.
	#
	# At a radius of 0.26 centred at 0.9 these cleared the top of the shell by up
	# to a tenth of a radius, as four separate spheres on a ring -- which is not a
	# tousled head, it is four buds on a crown. Flattened and dropped so their
	# tops run just about level with the shell, the same four lumps read as a
	# surface that is not smooth, which is all a tuft has to do.
	var tufts: int = style.get("tufts", 0)
	for i in tufts:
		var a := TAU * (float(i) / float(maxi(tufts, 1)))
		var high := mini(i, tufts - i) % 2
		_add_lump(root, head_r, 0.23, mat,
			Vector3(sin(a) * 0.42, 0.82 + 0.06 * float(high), cos(a) * 0.42 - back * 0.5),
			Vector3(1.3, 0.62, 1.3))

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
	root: Node3D, head_r: float, radius: float, mat: Material, at: Vector3,
	shape := Vector3.ONE
) -> void:
	var lump := _sphere(head_r * radius, mat, true)
	lump.position = at * head_r
	lump.scale = shape
	root.add_child(lump)


static func _accessory(
	appearance: SimAppearance,
	head_r: float,
	head: Node3D,
	kit: PackedColorArray
) -> void:
	match appearance.accessory:
		"headband":
			# A band has to be cut to the head at the height it is worn, and the
			# head is a ball: at six tenths up, the skull is only eight tenths of
			# a radius across. A band of 0.92 there stands a tenth of a radius off
			# the skull all the way round and reads as a halo hanging in front of
			# the forehead, which is what this was doing.
			# Below the hairline as well as above the brows. Raised to 0.55 it was
			# inside the hair on every cut that has any, and all that showed was a
			# sliver of kit colour across the forehead like a scratch.
			var band := _band(head_r * 0.93, head_r * 0.14, toy_material(kit[0]))
			band.position = Vector3(0.0, head_r * 0.40, 0.0)
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
		player_root.get_meta("eye_style", 0),
		player_root.get_meta("mouth_style", 0))
	# The brows are geometry now, so swapping the texture is only half of it.
	_pose_brows(player_root, face)


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
	# Lit, and lit exactly like the skull it lies on.
	#
	# This was unshaded, which is what a decal is. On a head that shades from the
	# sun and darkens in its own creases, a face that ignores both is a sticker
	# stuck to a moulded object -- brightest where the cheek is turning away, and
	# unmoved when the man walks into shade. The reference has no such patch: the
	# eyes and the mouth are part of the moulding and go dark with the rest of it.
	#
	# `toy_material` rather than `flat_material` for the same reason. The head
	# carries a sheen; a matte patch across the front of a glossy skull is the
	# same tell one step quieter.
	var m := toy_material(Color.WHITE)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = SimFaceAtlas.texture_for(
		SimAppearance.Face.NEUTRAL, appearance.eye_style, appearance.mouth_style)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = m
	return node
