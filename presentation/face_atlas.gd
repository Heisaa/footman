class_name SimFaceAtlas
extends RefCounted
## The faces, generated rather than authored (PLAN.md §9.3).
##
## A drawn face on a small texture, swapped wholesale for expression. There is no
## facial rig and there never will be: a rig would cost far more than it could
## possibly add over a handful of drawn faces.
##
## Two things vary independently.
##
## The **style** is who the player is -- his brows, his eyes, his mouth -- and it
## comes off his appearance seed. A squad of twenty-two men wearing the same two
## dots is a clone army with different hair, which is the one thing procedural
## appearance exists to avoid. (The nose is not here: it is a real bump on the
## head, built in `SimCharacterBuilder`, the way the reference art does it.)
##
## The **expression** is the emotion of the moment, and the sim's animation state
## picks it. It is drawn over the style rather than replacing it: the brows do
## most of the work -- lowered and driven in for effort, raised for delight,
## outer ends dropped for despair -- and the eyes keep the man's own size and
## spacing throughout. That is the Mii trick: the range comes from a brow line
## and an eye shape, not from more pixels.
##
## Everything is drawn in the **unit grid** below -- a 32-square face, which is
## what this atlas used to be -- and scaled to whatever `SIZE` is. Shapes are
## anti-aliased from their own distance functions rather than plotted as whole
## pixels, because thirty-two squares blown up to a head at reading distance made
## a mouth a flight of stairs. Raising `SIZE` alone raises the resolution: not one
## style number below has to change.
##
## Generated on demand and cached. A match uses a few dozen combinations out of
## the thousands available.

## Texture resolution. The drawn face fills about half of it, so 128 gives a
## mouth around thirty pixels wide: clean at the distance the parade view looks
## from, and mipmapped away to nothing at match distance.
const SIZE := 128
const GRID := 32.0
const SCALE := SIZE / GRID

## Where the eyes sit in the unit grid. Every style is within a few tenths of it,
## and `SimCharacterBuilder` hangs the whole face off this number so the eye row
## lands exactly on the equator of the head.
const EYE_ROW := 14.6

const INK := Color(0.13, 0.11, 0.15, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

## Eyes, and they are black shapes: `rx`/`ry` are the half-axes, `gap` half the
## distance between them, `y` how far down the face they sit. No whites, no
## pupils -- the reference art draws an eye as one dark mark and it carries
## further than a bead does, because at match distance a white with a pupil in it
## is a grey smudge.
##
## Every eye is a circle or a gentle oval -- nothing narrower than about three to
## four, either way round. Slits and lozenges were in here and they read as a
## squint on a face this size, which is an expression, not a feature.
##
## Spacing is the other half of the table. Eyes a fifth of a head-width apart
## huddle in the middle of the face and the man looks pinched; the reference sets
## them about a quarter to a third of the head apart and draws them big.
##
## **Big** turned out to be bigger than this table had. Measured off the owner's
## vinyl reference an eye is about a seventh of the width of the face; ours were
## nearer a ninth, which is a man with small eyes rather than a toy with big
## ones. Every row is up by about a quarter, and the taller-than-wide rows are
## kept that way -- the reference eye is an upright oval, not a bead.
const EYE_STYLES := [
	{"rx": 3.0, "ry": 3.6, "gap": 6.6, "y": 14.6},
	{"rx": 3.5, "ry": 3.5, "gap": 6.8, "y": 14.4},
	{"rx": 2.6, "ry": 2.6, "gap": 6.2, "y": 14.6},
	{"rx": 2.7, "ry": 3.4, "gap": 7.2, "y": 14.8},
	{"rx": 3.7, "ry": 3.3, "gap": 7.0, "y": 14.4},
	{"rx": 2.9, "ry": 3.7, "gap": 6.4, "y": 14.6},
	{"rx": 3.1, "ry": 3.1, "gap": 7.4, "y": 14.8},
	{"rx": 2.5, "ry": 2.9, "gap": 6.2, "y": 14.6},
]

## Brows. `lift` is how far above the eye they sit, `tilt` how much the inner end
## drops below the outer one, `half` their half-length and `thick` their
## half-thickness. Style 0 is a man with no brows to speak of.
##
## **`half` and `thick` are both half-measures**, and getting that wrong is how
## this table was last broken. Measured off the reference a brow is about 90
## units long by 28 deep on a 420-unit face -- which in this 32-unit grid is a
## `half` of 3.4 and a `thick` of 1.05, not 2.1. Reading the 28 as a half-depth
## doubled every brow and produced a stubby oval about 1.7 times as long as it
## was deep; the reference brow is a bar, better than three to one. If a brow
## ever reads as a second pair of eyes, this ratio is why.
##
## `lift` is measured to the middle of the brow, so the gap over the eye is
## `lift - thick - ry` and it wants to be about one unit -- the reference keeps
## the brow close over the eye, not floating on the forehead. These lifts are the
## originals plus 0.6, which is what the eyes growing by a quarter cost.
## Longer than they were again, and no thicker. Side by side the styles with a
## `half` near 4 read as brows and the ones near 3 read as a second pair of eyes:
## against eyes this big a short bar is just another dark oval on the face. The
## lifts come down a little with it -- a brow belongs close over the eye.
const BROW_STYLES := [
	{"lift": 0.0, "tilt": 0.0, "half": 0.0, "thick": 0.0},
	{"lift": 5.3, "tilt": 0.0, "half": 3.6, "thick": 1.0},
	{"lift": 5.3, "tilt": 0.0, "half": 3.9, "thick": 1.25},
	{"lift": 5.8, "tilt": -0.7, "half": 3.8, "thick": 1.0},
	{"lift": 5.3, "tilt": 0.7, "half": 3.9, "thick": 1.25},
	{"lift": 6.1, "tilt": -1.4, "half": 3.6, "thick": 0.9},
	{"lift": 5.0, "tilt": 0.9, "half": 3.6, "thick": 1.4},
	{"lift": 5.8, "tilt": 0.0, "half": 4.2, "thick": 0.9},
]

## Mouths, for the face a player wears when nothing is happening. They sit
## closer under the nose than they did: the features were spread over the whole
## face and read as a long jaw with a mouth lost at the bottom of it.
const MOUTH_STYLES := [
	{"kind": "line", "w": 5.0, "y": 23.2},
	{"kind": "smile", "w": 4.0, "y": 22.6},
	{"kind": "frown", "w": 3.4, "y": 23.8},
	{"kind": "open", "w": 2.1, "y": 23.2},
	{"kind": "line", "w": 7.4, "y": 23.2},
	{"kind": "smile", "w": 5.6, "y": 22.2},
	{"kind": "line", "w": 3.0, "y": 23.2},
	{"kind": "open", "w": 1.5, "y": 23.4},
]

static var _cache := {}


## `eyes` and `mouth` are the player's own; `face` is the moment. The brows are
## not here any more -- they are a moulded ridge on the head, built and posed by
## `SimCharacterBuilder`, so this texture no longer varies with `brow_style` and
## the key is that much smaller. `brow_pose` below is still the one place the
## brow numbers live.
static func texture_for(face: int, eyes: int = 0, mouth: int = 0) -> Texture2D:
	var key := (face * 8 + eyes) * 8 + mouth
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_face(image, face, eyes, mouth)
	# Mipmaps, because the same face is a hundred pixels across in the parade and
	# four in a match, and four pixels of un-mipmapped ink crawls.
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


## Where a man's brows sit for a given moment, in unit-grid numbers: `lift` above
## the eye row, `tilt` how far the inner end drops, `half` the half-length and
## `thick` the half-thickness.
##
## **The brows carry the expression** -- that is the whole Mii trick, and it is
## why this is a shared function rather than a block inside the drawing code. The
## brows are moulded now and `SimCharacterBuilder` poses them off these same
## numbers; two copies of this table drifting apart would be a squad whose faces
## disagree with themselves.
static func brow_pose(brow_style: int, face: int) -> Dictionary:
	var brow: Dictionary = BROW_STYLES[posmod(brow_style, BROW_STYLES.size())]
	var lift: float = brow["lift"]
	var tilt: float = brow["tilt"]
	match face:
		SimAppearance.Face.EFFORT:
			lift -= 1.6
			tilt += 1.6
		SimAppearance.Face.DELIGHT:
			lift += 1.6
			tilt -= 0.8
		SimAppearance.Face.DESPAIR:
			lift += 0.8
			tilt -= 2.4
		SimAppearance.Face.ANGER:
			lift -= 0.8
			tilt += 3.2
	# A man with no brows still needs them to shout with, so a strong expression
	# lends him a plain pair. Neutral leaves him as he is.
	var half: float = brow["half"]
	var thick: float = brow["thick"]
	if half <= 0.0 and face != SimAppearance.Face.NEUTRAL:
		half = 3.0
		thick = 1.0
		lift = 5.0 + (lift - float(brow["lift"]))
	return {"lift": lift, "tilt": tilt, "half": half, "thick": thick}


static func _draw_face(image: Image, face: int, eye_style: int, mouth_style: int) -> void:
	var eye: Dictionary = EYE_STYLES[posmod(eye_style, EYE_STYLES.size())]
	var mouth: Dictionary = MOUTH_STYLES[posmod(mouth_style, MOUTH_STYLES.size())]
	var gap: float = eye["gap"]
	var left: float = 16.0 - gap
	var right: float = 16.0 + gap
	var y: float = eye["y"]
	var rx: float = eye["rx"]
	var ry: float = eye["ry"]

	match face:
		SimAppearance.Face.EFFORT:
			# Screwed shut, whatever shape they are open.
			_line(image, left - rx, y, left + rx, y, 1.4)
			_line(image, right - rx, y, right + rx, y, 1.4)
		SimAppearance.Face.DELIGHT:
			_arc(image, left, y, rx + 0.8, false, 1.3)
			_arc(image, right, y, rx + 0.8, false, 1.3)
		SimAppearance.Face.DESPAIR:
			# Wide open: the eyes grow rather than change shape.
			_ellipse(image, left, y, rx + 0.5, ry + 0.7, INK)
			_ellipse(image, right, y, rx + 0.5, ry + 0.7, INK)
		SimAppearance.Face.ANGER:
			# Narrowed, not shut: squashed to seven tenths they stop being ovals.
			_ellipse(image, left, y + 0.4, rx, ry * 0.85, INK)
			_ellipse(image, right, y + 0.4, rx, ry * 0.85, INK)
		_:
			_ellipse(image, left, y, rx, ry, INK)
			_ellipse(image, right, y, rx, ry, INK)

	match face:
		SimAppearance.Face.EFFORT:
			_ellipse(image, 16.0, 23.4, 2.8, 3.2, INK)
		SimAppearance.Face.DELIGHT:
			_arc(image, 16.0, 22.6, 4.6, true, 1.5)
		SimAppearance.Face.DESPAIR:
			_arc(image, 16.0, 24.4, 3.6, false, 1.4)
		SimAppearance.Face.ANGER:
			_line(image, 12.8, 23.6, 19.2, 23.6, 1.4)
		_:
			_mouth(image, mouth)


## One brow. `inner` is +1 for the left eye and -1 for the right, so a positive
## tilt drops the inner ends on both sides and the man scowls.
static func _mouth(image: Image, mouth: Dictionary) -> void:
	var w: float = mouth["w"]
	var y: float = mouth["y"]
	match mouth["kind"]:
		"smile":
			_arc(image, 16.0, y, w, true, 1.4)
		"frown":
			_arc(image, 16.0, y, w, false, 1.4)
		"open":
			_ellipse(image, 16.0, y, w, w * 1.15, INK)
		_:
			_line(image, 16.0 - w * 0.5, y, 16.0 + w * 0.5, y, 1.4)


# --- Drawing ----------------------------------------------------------------
#
# Unit-grid coordinates in, anti-aliased pixels out. Each shape works out how far
# a pixel centre is from its own edge and uses that distance as coverage, which
# is what keeps a curve smooth instead of a staircase.


static func _blend(image: Image, x: int, y: int, colour: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE or alpha <= 0.0:
		return
	var a: float = minf(alpha, 1.0)
	var dst := image.get_pixel(x, y)
	var out_a: float = a + dst.a * (1.0 - a)
	if out_a <= 0.0:
		return
	var w_src: float = a / out_a
	image.set_pixel(x, y, Color(
		lerpf(dst.r, colour.r, w_src),
		lerpf(dst.g, colour.g, w_src),
		lerpf(dst.b, colour.b, w_src),
		out_a))


static func _ellipse(
	image: Image, cx: float, cy: float, rx: float, ry: float, colour: Color
) -> void:
	var pcx := cx * SCALE
	var pcy := cy * SCALE
	var prx: float = maxf(rx * SCALE, 0.5)
	var pry: float = maxf(ry * SCALE, 0.5)
	var x0 := int(floor(pcx - prx - 1.0))
	var x1 := int(ceil(pcx + prx + 1.0))
	var y0 := int(floor(pcy - pry - 1.0))
	var y1 := int(ceil(pcy + pry + 1.0))
	# The normalised distance is scaled back to pixels by the smaller half-axis,
	# which turns it into a one-pixel ramp at the edge.
	var ramp: float = minf(prx, pry)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (float(x) + 0.5 - pcx) / prx
			var dy := (float(y) + 0.5 - pcy) / pry
			var d := sqrt(dx * dx + dy * dy)
			_blend(image, x, y, colour, clampf((1.0 - d) * ramp + 0.5, 0.0, 1.0))


static func _line(
	image: Image, x0: float, y0: float, x1: float, y1: float, thickness: float
) -> void:
	_stroke(image, PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1)]), thickness)


## A half-ellipse. `up` lifts the ends relative to the middle -- a smile, or an
## eye squinting shut; `up` false lifts the middle -- a frown, or an eye arched
## in delight. The image's y grows downward, and every caller had this the wrong
## way round once: delight was drawn as despair, and despair as delight.
static func _arc(
	image: Image, cx: float, cy: float, radius: float, up: bool, thickness: float
) -> void:
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var t := -1.0 + 2.0 * float(i) / float(steps)
		var offset := (1.0 - t * t) * radius * 0.5
		points.append(Vector2(cx + t * radius, cy + (offset if up else -offset)))
	_stroke(image, points, thickness)


## A polyline in ink with round caps and joins, drawn from the distance to it.
static func _stroke(image: Image, points: PackedVector2Array, thickness: float) -> void:
	if points.size() < 2:
		return
	var half: float = maxf(thickness * 0.5 * SCALE, 0.5)
	var pixels := PackedVector2Array()
	var min_at := Vector2(INF, INF)
	var max_at := Vector2(-INF, -INF)
	for p in points:
		var q := p * SCALE
		pixels.append(q)
		min_at = min_at.min(q)
		max_at = max_at.max(q)
	var x0 := int(floor(min_at.x - half - 1.0))
	var x1 := int(ceil(max_at.x + half + 1.0))
	var y0 := int(floor(min_at.y - half - 1.0))
	var y1 := int(ceil(max_at.y + half + 1.0))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var at := Vector2(float(x) + 0.5, float(y) + 0.5)
			var best := INF
			for i in pixels.size() - 1:
				best = minf(best, _distance_to_segment(at, pixels[i], pixels[i + 1]))
			_blend(image, x, y, INK, clampf(half - best + 0.5, 0.0, 1.0))


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.00001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
