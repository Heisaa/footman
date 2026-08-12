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

const INK := Color(0.13, 0.11, 0.15, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

## Eyes. `rx`/`ry` are the half-axes, `gap` half the distance between them, `y`
## how far down the face they sit, and `white` whether the eye is a bead with a
## pupil in it or a plain dot. Both belong: the reference art has plain dots, the
## Mii has a pupil, and a squad wants some of each.
const EYE_STYLES := [
	{"rx": 2.6, "ry": 3.4, "gap": 6.0, "y": 14.0, "white": true},
	{"rx": 3.2, "ry": 3.6, "gap": 6.0, "y": 14.0, "white": true},
	{"rx": 1.8, "ry": 1.8, "gap": 5.0, "y": 14.0, "white": false},
	{"rx": 1.6, "ry": 2.6, "gap": 7.0, "y": 15.0, "white": false},
	{"rx": 3.4, "ry": 2.8, "gap": 7.0, "y": 14.0, "white": true},
	{"rx": 2.4, "ry": 3.0, "gap": 7.0, "y": 14.0, "white": true},
	{"rx": 2.4, "ry": 2.4, "gap": 4.5, "y": 15.0, "white": false},
	{"rx": 1.2, "ry": 2.2, "gap": 6.0, "y": 14.0, "white": false},
]

## Brows. `lift` is how far above the eye they sit, `tilt` how much the inner end
## drops below the outer one, `half` their half-length and `thick` the pen. Style
## 0 is a man with no brows to speak of.
const BROW_STYLES := [
	{"lift": 0.0, "tilt": 0.0, "half": 0.0, "thick": 0.0},
	{"lift": 5.0, "tilt": 0.0, "half": 3.0, "thick": 1.0},
	{"lift": 5.0, "tilt": 0.0, "half": 3.6, "thick": 1.6},
	{"lift": 6.0, "tilt": -0.8, "half": 3.4, "thick": 1.0},
	{"lift": 5.0, "tilt": 0.8, "half": 3.6, "thick": 1.6},
	{"lift": 6.5, "tilt": -1.6, "half": 3.0, "thick": 0.9},
	{"lift": 4.4, "tilt": 1.0, "half": 3.0, "thick": 1.8},
	{"lift": 6.0, "tilt": 0.0, "half": 4.4, "thick": 0.9},
]

## Mouths, for the face a player wears when nothing is happening.
const MOUTH_STYLES := [
	{"kind": "line", "w": 5.0, "y": 23.0},
	{"kind": "smile", "w": 4.0, "y": 22.0},
	{"kind": "frown", "w": 3.6, "y": 24.0},
	{"kind": "open", "w": 2.2, "y": 23.0},
	{"kind": "line", "w": 8.0, "y": 23.0},
	{"kind": "smile", "w": 6.0, "y": 21.5},
	{"kind": "line", "w": 3.0, "y": 23.0},
	{"kind": "open", "w": 1.6, "y": 23.0},
]

static var _cache := {}


## `brow`, `eyes` and `mouth` are the player's own; `face` is the moment.
static func texture_for(face: int, brow: int = 0, eyes: int = 0, mouth: int = 0) -> Texture2D:
	var key := ((face * 8 + brow) * 8 + eyes) * 8 + mouth
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_face(image, face, brow, eyes, mouth)
	# Mipmaps, because the same face is a hundred pixels across in the parade and
	# four in a match, and four pixels of un-mipmapped ink crawls.
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


static func _draw_face(
	image: Image, face: int, brow_style: int, eye_style: int, mouth_style: int
) -> void:
	var eye: Dictionary = EYE_STYLES[posmod(eye_style, EYE_STYLES.size())]
	var brow: Dictionary = BROW_STYLES[posmod(brow_style, BROW_STYLES.size())]
	var mouth: Dictionary = MOUTH_STYLES[posmod(mouth_style, MOUTH_STYLES.size())]
	var gap: float = eye["gap"]
	var left: float = 16.0 - gap
	var right: float = 16.0 + gap
	var y: float = eye["y"]
	var rx: float = eye["rx"]
	var ry: float = eye["ry"]

	# The brows carry the expression. Everything else is a smaller adjustment on
	# top of the man's own face.
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
	if half > 0.0:
		_brow(image, left, 1.0, y - lift, half, thick, tilt)
		_brow(image, right, -1.0, y - lift, half, thick, tilt)

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
			_eye(image, left, y, rx + 0.6, ry + 0.6, eye["white"], 0.6)
			_eye(image, right, y, rx + 0.6, ry + 0.6, eye["white"], 0.6)
		SimAppearance.Face.ANGER:
			_eye(image, left, y + 0.5, rx, ry * 0.75, eye["white"], 0.0)
			_eye(image, right, y + 0.5, rx, ry * 0.75, eye["white"], 0.0)
		_:
			_eye(image, left, y, rx, ry, eye["white"], 0.0)
			_eye(image, right, y, rx, ry, eye["white"], 0.0)

	match face:
		SimAppearance.Face.EFFORT:
			_ellipse(image, 16.0, 23.0, 3.0, 3.4, INK)
		SimAppearance.Face.DELIGHT:
			_arc(image, 16.0, 22.0, 5.0, true, 1.6)
		SimAppearance.Face.DESPAIR:
			_arc(image, 16.0, 24.5, 4.0, false, 1.5)
		SimAppearance.Face.ANGER:
			_line(image, 12.5, 24.0, 19.5, 24.0, 1.5)
		_:
			_mouth(image, mouth)


## An eye: a plain ink dot, or a bead with a pupil and a catchlight in it. `look`
## drops the pupil down the white, which is what makes a wide-open eye read as
## alarmed rather than merely large.
static func _eye(
	image: Image, cx: float, cy: float, rx: float, ry: float, white: bool, look: float
) -> void:
	_ellipse(image, cx, cy, rx, ry, INK)
	if not white:
		return
	_ellipse(image, cx, cy, rx - 0.5, ry - 0.5, WHITE)
	var pr: float = maxf(minf(rx, ry) - 1.0, 0.6)
	_ellipse(image, cx, cy + look, pr, pr, INK)
	# The catchlight: one pale spot, and it is the difference between an eye and
	# a hole.
	_ellipse(image, cx - pr * 0.35, cy + look - pr * 0.35, pr * 0.32, pr * 0.32, WHITE)


## One brow. `inner` is +1 for the left eye and -1 for the right, so a positive
## tilt drops the inner ends on both sides and the man scowls.
static func _brow(
	image: Image, cx: float, inner: float, y: float, half: float, thick: float, tilt: float
) -> void:
	_line(image, cx - inner * half, y - tilt, cx + inner * half, y + tilt, thick)


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
