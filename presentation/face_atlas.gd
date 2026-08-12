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
## The **style** is who the player is -- his brows, his eyes, his mouth, his nose
## -- and it comes off his appearance seed. A squad of twenty-two men wearing the
## same two dots is a clone army with different hair, which is the one thing
## procedural appearance exists to avoid.
##
## The **expression** is the emotion of the moment, and the sim's animation state
## picks it. It is drawn over the style rather than replacing it: the brows do
## most of the work -- lowered and driven in for effort, raised for delight,
## outer ends dropped for despair -- and the eyes keep the man's own size and
## spacing throughout. That is the Mii trick the owner asked for: the range comes
## from a brow line and an eye shape, not from more pixels.
##
## Generated on demand and cached. A match uses a few dozen combinations out of
## the thousands available, so the cache stays small.

const SIZE := 32
const INK := Color(0.13, 0.11, 0.15, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

## Eyes. `rx`/`ry` are the half-axes, `gap` half the distance between them, `y`
## how far down the face they sit, and `white` whether the eye is a bead with a
## pupil in it or a plain dot. Both belong: the reference art has plain dots, the
## Mii has a pupil, and a squad wants some of each.
## A bead needs room for three rings -- outline, white, pupil -- so the styles
## that have one are drawn a pixel larger than the plain dots. At three by three
## it came out as a target.
const EYE_STYLES := [
	{"rx": 3, "ry": 4, "gap": 6, "y": 14, "white": true},
	{"rx": 4, "ry": 4, "gap": 6, "y": 14, "white": true},
	{"rx": 2, "ry": 2, "gap": 5, "y": 14, "white": false},
	{"rx": 2, "ry": 3, "gap": 7, "y": 15, "white": false},
	{"rx": 4, "ry": 3, "gap": 7, "y": 14, "white": true},
	{"rx": 3, "ry": 3, "gap": 7, "y": 14, "white": true},
	{"rx": 3, "ry": 3, "gap": 4, "y": 15, "white": false},
	{"rx": 1, "ry": 2, "gap": 6, "y": 14, "white": false},
]

## Brows. `lift` is how far above the eye they sit, `tilt` how much the inner end
## drops below the outer one, `half` their half-length and `thick` the pen. Style
## 0 is a man with no brows to speak of.
const BROW_STYLES := [
	{"lift": 0, "tilt": 0, "half": 0, "thick": 0},
	{"lift": 5, "tilt": 0, "half": 3, "thick": 1},
	{"lift": 5, "tilt": 0, "half": 4, "thick": 2},
	{"lift": 6, "tilt": -1, "half": 4, "thick": 1},
	{"lift": 5, "tilt": 1, "half": 4, "thick": 2},
	{"lift": 7, "tilt": -2, "half": 3, "thick": 1},
	{"lift": 4, "tilt": 1, "half": 3, "thick": 2},
	{"lift": 6, "tilt": 0, "half": 5, "thick": 1},
]

## Noses, all small. The Mii has one and the reference art does not, so a plain
## `none` is in the table twice.
const NOSE_STYLES := [
	{"kind": "none"},
	{"kind": "none"},
	{"kind": "dot"},
	{"kind": "line"},
	{"kind": "hook"},
]

## Mouths, for the face a player wears when nothing is happening.
const MOUTH_STYLES := [
	{"kind": "line", "w": 6, "y": 23},
	{"kind": "smile", "w": 4, "y": 22},
	{"kind": "frown", "w": 4, "y": 24},
	{"kind": "open", "w": 3, "y": 23},
	{"kind": "line", "w": 10, "y": 23},
	{"kind": "smile", "w": 7, "y": 21},
	{"kind": "line", "w": 3, "y": 23},
	{"kind": "open", "w": 2, "y": 23},
]

static var _cache := {}


## `brow`, `eyes`, `mouth` and `nose` are the player's own; `face` is the moment.
static func texture_for(
	face: int, brow: int = 0, eyes: int = 0, mouth: int = 0, nose: int = 0
) -> Texture2D:
	var key := ((((face * 8 + brow) * 8 + eyes) * 8 + mouth) * 8) + nose
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_face(image, face, brow, eyes, mouth, nose)
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


static func _draw_face(
	image: Image, face: int, brow_style: int, eye_style: int, mouth_style: int, nose_style: int
) -> void:
	var eye: Dictionary = EYE_STYLES[posmod(eye_style, EYE_STYLES.size())]
	var brow: Dictionary = BROW_STYLES[posmod(brow_style, BROW_STYLES.size())]
	var mouth: Dictionary = MOUTH_STYLES[posmod(mouth_style, MOUTH_STYLES.size())]
	var nose: Dictionary = NOSE_STYLES[posmod(nose_style, NOSE_STYLES.size())]
	var gap: int = eye["gap"]
	var left := 16 - gap
	var right := 16 + gap
	var y: int = eye["y"]

	# The brows carry the expression. Everything else is a smaller adjustment on
	# top of the man's own face.
	var lift: int = brow["lift"]
	var tilt: int = brow["tilt"]
	match face:
		SimAppearance.Face.EFFORT:
			lift -= 2
			tilt += 2
		SimAppearance.Face.DELIGHT:
			lift += 2
			tilt -= 1
		SimAppearance.Face.DESPAIR:
			lift += 1
			tilt -= 3
		SimAppearance.Face.ANGER:
			lift -= 1
			tilt += 4
	if brow["half"] > 0:
		_brow(image, left, 1, y - lift, brow["half"], brow["thick"], tilt)
		_brow(image, right, -1, y - lift, brow["half"], brow["thick"], tilt)

	match face:
		SimAppearance.Face.EFFORT:
			# Screwed shut, whatever shape they are open.
			_line(image, left - eye["rx"], y, left + eye["rx"], y, 2)
			_line(image, right - eye["rx"], y, right + eye["rx"], y, 2)
		SimAppearance.Face.DELIGHT:
			_arc(image, left, y, eye["rx"] + 1, false)
			_arc(image, right, y, eye["rx"] + 1, false)
		SimAppearance.Face.DESPAIR:
			# Wide open: the eyes grow rather than change shape.
			_eye(image, left, y, eye["rx"] + 1, eye["ry"] + 1, eye["white"], 1)
			_eye(image, right, y, eye["rx"] + 1, eye["ry"] + 1, eye["white"], 1)
		SimAppearance.Face.ANGER:
			_eye(image, left, y + 1, eye["rx"], maxi(eye["ry"] - 1, 1), eye["white"], 0)
			_eye(image, right, y + 1, eye["rx"], maxi(eye["ry"] - 1, 1), eye["white"], 0)
		_:
			_eye(image, left, y, eye["rx"], eye["ry"], eye["white"], 0)
			_eye(image, right, y, eye["rx"], eye["ry"], eye["white"], 0)

	_nose(image, nose)

	match face:
		SimAppearance.Face.EFFORT:
			_ellipse(image, 16, 23, 4, 4, INK)
		SimAppearance.Face.DELIGHT:
			_arc(image, 16, 22, 6, true)
		SimAppearance.Face.DESPAIR:
			_arc(image, 16, 25, 5, false)
		SimAppearance.Face.ANGER:
			_line(image, 12, 24, 20, 24, 2)
		_:
			_mouth(image, mouth)


## An eye: a plain ink dot, or a bead with a pupil in it. `look` shifts the pupil
## down the eye, which is what makes a wide-open eye read as alarmed rather than
## merely large.
static func _eye(
	image: Image, cx: int, cy: int, rx: int, ry: int, white: bool, look: int
) -> void:
	_ellipse(image, cx, cy, rx, ry, INK)
	if not white:
		return
	_ellipse(image, cx, cy, maxi(rx - 1, 1), maxi(ry - 1, 1), WHITE)
	_ellipse(image, cx, cy + look, maxi(rx - 2, 1), maxi(ry - 2, 1), INK)


## One brow. `inner` is +1 for the left eye and -1 for the right, so a positive
## tilt drops the inner ends on both sides and the man scowls.
static func _brow(
	image: Image, cx: int, inner: int, y: int, half: int, thick: int, tilt: int
) -> void:
	var outer_x := cx - inner * half
	var inner_x := cx + inner * half
	_line(image, outer_x, y - tilt, inner_x, y + tilt, maxi(thick, 1))


static func _nose(image: Image, nose: Dictionary) -> void:
	match nose["kind"]:
		"dot":
			_ellipse(image, 16, 19, 1, 1, INK)
		"line":
			_line(image, 16, 17, 16, 20, 1)
		"hook":
			_line(image, 16, 17, 16, 20, 1)
			_line(image, 16, 20, 18, 20, 1)
		_:
			pass


static func _mouth(image: Image, mouth: Dictionary) -> void:
	var w: int = mouth["w"]
	var y: int = mouth["y"]
	match mouth["kind"]:
		"smile":
			_arc(image, 16, y, w, true)
		"frown":
			_arc(image, 16, y, w, false)
		"open":
			_ellipse(image, 16, y, w, w, INK)
		_:
			# A wide mouth is drawn with a finer pen: ten pixels of double-thick
			# ink is a letterbox, not a mouth.
			_line(image, 16 - w / 2, y, 16 + w / 2, y, 1 if w >= 8 else 2)


static func _plot(image: Image, x: int, y: int, colour: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	image.set_pixel(x, y, colour)


static func _ellipse(image: Image, cx: int, cy: int, rx: int, ry: int, colour: Color) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx := float(x - cx) / maxf(float(rx), 1.0)
			var dy := float(y - cy) / maxf(float(ry), 1.0)
			if dx * dx + dy * dy <= 1.0:
				_plot(image, x, y, colour)


static func _line(image: Image, x0: int, y0: int, x1: int, y1: int, thickness: int) -> void:
	var steps: int = maxi(absi(x1 - x0), absi(y1 - y0))
	for i in steps + 1:
		var t := float(i) / maxf(float(steps), 1.0)
		var x := int(round(lerpf(float(x0), float(x1), t)))
		var y := int(round(lerpf(float(y0), float(y1), t)))
		for oy in thickness:
			for ox in thickness:
				_plot(image, x + ox, y + oy, INK)


## A half-ellipse. `up` lifts the ends relative to the middle -- a smile, or an
## eye squinting shut; `up` false lifts the middle -- a frown, or an eye arched
## in delight. The image's y grows downward, and every caller had this the wrong
## way round: delight was drawn as despair and despair as delight.
static func _arc(image: Image, cx: int, cy: int, radius: int, up: bool) -> void:
	for x in range(cx - radius, cx + radius + 1):
		var t := float(x - cx) / float(radius)
		var offset := (1.0 - t * t) * float(radius) * 0.5
		var y := cy + int(round(offset if up else -offset))
		_plot(image, x, y, INK)
		_plot(image, x, y + 1, INK)
