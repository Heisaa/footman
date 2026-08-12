class_name SimFaceAtlas
extends RefCounted
## The faces, generated rather than authored (PLAN.md §9.3).
##
## "Two dots and a simple mouth", swapped wholesale for expression. There is no
## facial rig and there never will be: a rig would cost far more than it could
## possibly add over a few drawn expressions.
##
## Two things vary independently. The **expression** is the emotion of the
## moment, and the sim's animation state picks it. The **style** is who the
## player is -- which eyes and which mouth he was born with -- and it comes off
## his appearance seed. A squad of twenty-two men all wearing the same two dots
## is a clone army with different hair, which is the one thing procedural
## appearance exists to avoid.
##
## The strong expressions keep their own drawing, because a grin is a grin
## whoever wears it; the eyes still take their size and spacing from the style,
## so a wide-set man stays wide-set when he is delighted. Neutral -- the face a
## player wears for almost the whole match -- is all his own.
##
## Generated on demand and cached, because every player in a match shares a
## handful of combinations.

const SIZE := 32
const INK := Color(0.13, 0.11, 0.15, 1.0)

## Eyes: half-width, half-height, how far apart, how high up the face, and
## whether a brow sits over them.
const EYE_STYLES := [
	{"rx": 2, "ry": 2, "gap": 5, "y": 14, "brow": false},
	{"rx": 2, "ry": 3, "gap": 5, "y": 14, "brow": false},
	{"rx": 2, "ry": 2, "gap": 7, "y": 15, "brow": false},
	{"rx": 3, "ry": 3, "gap": 4, "y": 14, "brow": false},
	{"rx": 2, "ry": 2, "gap": 5, "y": 15, "brow": true},
	{"rx": 3, "ry": 2, "gap": 6, "y": 14, "brow": false},
	{"rx": 1, "ry": 2, "gap": 6, "y": 14, "brow": true},
]

## Mouths, for the face a player wears when nothing is happening. `kind` is the
## shape, `w` its width, `y` how far down the face it sits.
const MOUTH_STYLES := [
	{"kind": "line", "w": 6, "y": 22},
	{"kind": "smile", "w": 4, "y": 21},
	{"kind": "frown", "w": 4, "y": 23},
	{"kind": "open", "w": 3, "y": 22},
	{"kind": "line", "w": 10, "y": 22},
	{"kind": "smile", "w": 7, "y": 20},
	{"kind": "line", "w": 4, "y": 22},
]

static var _cache := {}


static func texture_for(face: int, eyes: int = 0, mouth: int = 0) -> Texture2D:
	var key := face * 100 + eyes * 10 + mouth
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_face(image, face, eyes, mouth)
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex


static func _draw_face(image: Image, face: int, eye_style: int, mouth_style: int) -> void:
	var eye: Dictionary = EYE_STYLES[posmod(eye_style, EYE_STYLES.size())]
	var mouth: Dictionary = MOUTH_STYLES[posmod(mouth_style, MOUTH_STYLES.size())]
	var gap: int = eye["gap"]
	var left := 16 - gap
	var right := 16 + gap
	var y: int = eye["y"]

	match face:
		SimAppearance.Face.EFFORT:
			# Screwed up: the eyes close to lines whatever shape they are open.
			_line(image, left - eye["rx"], y, left + eye["rx"], y, 2)
			_line(image, right - eye["rx"], y, right + eye["rx"], y, 2)
			_ellipse(image, 16, 22, 4, 4)
		SimAppearance.Face.DELIGHT:
			# Eyes arched up, mouth curved up, and the grin low enough to be a
			# mouth: at y 19 with a radius of 7 it reached the eye row and the
			# whole face read as four eyebrows.
			_arc(image, left, y, eye["rx"] + 2, false)
			_arc(image, right, y, eye["rx"] + 2, false)
			_arc(image, 16, 21, 6, true)
		SimAppearance.Face.DESPAIR:
			_ellipse(image, left, y - 1, eye["rx"], eye["ry"] + 1)
			_ellipse(image, right, y - 1, eye["rx"], eye["ry"] + 1)
			_arc(image, 16, 25, 5, false)
		SimAppearance.Face.ANGER:
			_line(image, left - 3, y - 4, left + 3, y - 1, 2)
			_line(image, right + 3, y - 4, right - 3, y - 1, 2)
			_ellipse(image, left, y + 1, eye["rx"], eye["ry"])
			_ellipse(image, right, y + 1, eye["rx"], eye["ry"])
			_line(image, 11, 23, 21, 23, 2)
		_:
			# Neutral: his own eyes and his own mouth.
			if eye["brow"]:
				_line(image, left - eye["rx"] - 1, y - 4, left + eye["rx"], y - 4, 1)
				_line(image, right - eye["rx"], y - 4, right + eye["rx"] + 1, y - 4, 1)
			_ellipse(image, left, y, eye["rx"], eye["ry"])
			_ellipse(image, right, y, eye["rx"], eye["ry"])
			_mouth(image, mouth)


static func _mouth(image: Image, mouth: Dictionary) -> void:
	var w: int = mouth["w"]
	var y: int = mouth["y"]
	match mouth["kind"]:
		"smile":
			_arc(image, 16, y, w, true)
		"frown":
			_arc(image, 16, y, w, false)
		"open":
			_ellipse(image, 16, y, w, w)
		_:
			_line(image, 16 - w / 2, y, 16 + w / 2, y, 2)


static func _plot(image: Image, x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	image.set_pixel(x, y, INK)


static func _ellipse(image: Image, cx: int, cy: int, rx: int, ry: int) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx := float(x - cx) / maxf(float(rx), 1.0)
			var dy := float(y - cy) / maxf(float(ry), 1.0)
			if dx * dx + dy * dy <= 1.0:
				_plot(image, x, y)


static func _line(image: Image, x0: int, y0: int, x1: int, y1: int, thickness: int) -> void:
	var steps: int = maxi(absi(x1 - x0), absi(y1 - y0))
	for i in steps + 1:
		var t := float(i) / maxf(float(steps), 1.0)
		var x := int(round(lerpf(float(x0), float(x1), t)))
		var y := int(round(lerpf(float(y0), float(y1), t)))
		for oy in thickness:
			for ox in thickness:
				_plot(image, x + ox, y + oy)


## A half-ellipse. `up` lifts the ends relative to the middle -- a smile, or an
## eye squinting shut; `up` false lifts the middle -- a frown, or an eye arched
## in delight. The image's y grows downward, and every caller had this the wrong
## way round: delight was drawn as despair and despair as delight.
static func _arc(image: Image, cx: int, cy: int, radius: int, up: bool) -> void:
	for x in range(cx - radius, cx + radius + 1):
		var t := float(x - cx) / float(radius)
		var offset := (1.0 - t * t) * float(radius) * 0.5
		var y := cy + int(round(offset if up else -offset))
		_plot(image, x, y)
		_plot(image, x, y + 1)
