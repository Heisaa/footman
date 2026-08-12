class_name SimFaceAtlas
extends RefCounted
## The faces, generated rather than authored (PLAN.md §9.3).
##
## "Two dots and a simple mouth", swapped wholesale for expression. There is no
## facial rig and there never will be: a rig would cost far more than it could
## possibly add over five drawn expressions.
##
## Generated once and cached, because every player in a match shares them.

const SIZE := 32
const INK := Color(0.13, 0.11, 0.15, 1.0)

static var _cache := {}


static func texture_for(face: int) -> Texture2D:
	if _cache.has(face):
		return _cache[face]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_draw_face(image, face)
	var tex := ImageTexture.create_from_image(image)
	_cache[face] = tex
	return tex


static func _draw_face(image: Image, face: int) -> void:
	match face:
		SimAppearance.Face.EFFORT:
			# Screwed-up eyes, open mouth.
			_line(image, 8, 12, 13, 12, 2)
			_line(image, 19, 12, 24, 12, 2)
			_ellipse(image, 16, 22, 4, 4)
		SimAppearance.Face.DELIGHT:
			# Arched eyes, wide grin.
			_arc(image, 11, 14, 4, true)
			_arc(image, 21, 14, 4, true)
			_arc(image, 16, 19, 7, false)
		SimAppearance.Face.DESPAIR:
			_ellipse(image, 11, 13, 2, 3)
			_ellipse(image, 21, 13, 2, 3)
			_arc(image, 16, 26, 6, true)
		SimAppearance.Face.ANGER:
			_line(image, 8, 10, 14, 13, 2)
			_line(image, 24, 10, 18, 13, 2)
			_ellipse(image, 11, 15, 2, 2)
			_ellipse(image, 21, 15, 2, 2)
			_line(image, 11, 23, 21, 23, 2)
		_:
			# Neutral: two dots and a straight little mouth.
			_ellipse(image, 11, 14, 2, 2)
			_ellipse(image, 21, 14, 2, 2)
			_line(image, 13, 22, 19, 22, 2)


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


## A half-ellipse: `up` curves the ends upward (a smile), otherwise downward.
static func _arc(image: Image, cx: int, cy: int, radius: int, up: bool) -> void:
	for x in range(cx - radius, cx + radius + 1):
		var t := float(x - cx) / float(radius)
		var offset := (1.0 - t * t) * float(radius) * 0.5
		var y := cy + int(round(offset if up else -offset))
		_plot(image, x, y)
		_plot(image, x, y + 1)
