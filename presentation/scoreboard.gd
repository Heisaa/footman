class_name MatchScoreboard
extends Control
## The clock and the scoreline, drawn over the 3D match view (PLAN.md §9.6).
##
## Presentation only. It is handed a snapshot and two team names and draws them;
## it never asks the simulation a question and never writes to it.
##
## §9.6 asks for chunky, thick-outlined, hand-drawn panels rather than a
## broadcast overlay, so this is drawn by hand rather than assembled out of
## themed controls: flat fills from the master palette, a heavy ink border, an
## ink shadow slab behind it, and numerals with an outline thick enough to read
## against a bright kit. Nothing here is a texture, so it costs one draw pass and
## re-skins with the palette.

## The board sits in the top-left corner, one strip: the home chip, the score,
## the away chip and the clock in a row. A corner rather than the top middle
## because the middle of the top edge is where the far touchline and the
## crowd behind it are, which is the picture; a corner is where a broadcast
## keeps its bug, and the eye has learned to glance there and back.
##
## The board is authored at this viewport height and scaled from it, so the same
## layout numbers hold at 720p and at 4K. Clamped at the bottom because a very
## short window should shrink the board rather than have it eat the pitch, and at
## the top because past about twice size the outlines start to look like slabs.
const REFERENCE_HEIGHT := 720.0
const SCALE_MIN := 0.7
const SCALE_MAX := 2.0

const BOARD_HEIGHT := 48.0
const CHIP_WIDTH := 92.0
const SCORE_WIDTH := 86.0
const CLOCK_WIDTH := 96.0
const MARGIN := 16.0

const BORDER := 4.0
const SHADOW := Vector2(0.0, 5.0)
const CORNER := 9.0
const PAD := 5.0

const NAME_SIZE := 20
const SCORE_SIZE := 28
const CLOCK_SIZE := 20
const PERIOD_SIZE := 14

## The full-time prompt's chip, hung under the board and flush with its left
## edge. Sized off its own text so the two words and the six do not need two
## layouts, and set clear of the board: it appears from nothing, and something
## appearing hard against the board reads as the board having grown rather than
## as a new thing to read.
const PROMPT_SIZE := 16
const PROMPT_HEIGHT := 28.0
const PROMPT_PAD := 16.0
const PROMPT_GAP := 10.0

## A goal is the one thing the board exists to announce, so it announces it: the
## whole board swells and the scoring side's chip flashes to lemon and back.
## Timed in wall-clock seconds, not simulated ones — it is an interface flourish,
## and at 8x it should still be watchable rather than a single-frame blink.
const PULSE_SECONDS := 1.4
const PULSE_SWELL := 0.16

var home_name := "HOM"
var away_name := "AWA"
var home_kit := SimPalette.RED
var away_kit := SimPalette.SKY
## A line under the board, or empty for no line at all. Full time uses it to say
## which keys start another match; nothing else writes to it.
var prompt := ""
## The set situation on screen, named. Drawn in the prompt's slot on a paper
## chip; the full-time prompt, when it comes, takes the slot over.
var subtitle := ""

var _font: Font
var _clock := 0.0
var _period := SimConsts.Period.FIRST_HALF
var _score := PackedInt32Array([0, 0])
## Seconds left of the goal flourish, and which side it belongs to.
var _pulse := 0.0
var _pulse_team := -1


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Offsets as well as anchors: a Control under a CanvasLayer takes its parent
	# rect from the viewport, and the preset without offsets leaves it zero-sized,
	# which puts the board's centre line at the left edge of the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Called once a frame by the view with the snapshot it is drawing.
## A goal is a score going *up*. Stepping back through the recording winds one
## down again, and a board that flashes for that announces a goal for the side
## that has just had one taken off them.
func show_snapshot(snap: SimSnapshot) -> void:
	if snap.score[0] > _score[0]:
		_start_pulse(0)
	elif snap.score[1] > _score[1]:
		_start_pulse(1)
	_score[0] = snap.score[0]
	_score[1] = snap.score[1]
	_clock = snap.clock
	_period = snap.period
	queue_redraw()


## Back to nothing, for a new match. The score above all: the board reads the
## scoreline out of the snapshot and flashes when it changes, so a 2-1 followed
## by a fresh 0-0 would be announced as a goal for whoever was leading.
func reset() -> void:
	_score[0] = 0
	_score[1] = 0
	_clock = 0.0
	_period = SimConsts.Period.FIRST_HALF
	_pulse = 0.0
	_pulse_team = -1
	prompt = ""
	queue_redraw()


func _start_pulse(team: int) -> void:
	_pulse = PULSE_SECONDS
	_pulse_team = team


func _process(delta: float) -> void:
	if _pulse <= 0.0:
		return
	_pulse = maxf(0.0, _pulse - delta)
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var scale := clampf(size.y / REFERENCE_HEIGHT, SCALE_MIN, SCALE_MAX)
	# One transform rather than a scale factor threaded through thirty numbers:
	# the layout below is then written in the authored units throughout, and the
	# swell is the same transform with a different factor.
	var swell := 1.0 + PULSE_SWELL * _pulse_shape()
	# Swells out of the corner it sits in, so the margin holds and the board
	# grows into the picture rather than off the screen.
	var origin := Vector2(MARGIN, MARGIN) * scale
	draw_set_transform(origin, 0.0, Vector2(scale * swell, scale * swell))
	_draw_board()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The swell's shape: a fast rise and a slow settle, so a goal lands as a thump
## rather than a fade. Zero when nothing is happening.
func _pulse_shape() -> float:
	if _pulse <= 0.0:
		return 0.0
	var t := 1.0 - _pulse / PULSE_SECONDS
	return sin(pow(clampf(t, 0.0, 1.0), 0.45) * PI)


## Everything below is in authored units, with (0, 0) at the board's top-left
## corner.
func _draw_board() -> void:
	var width := PAD * 2.0 + CHIP_WIDTH * 2.0 + SCORE_WIDTH + CLOCK_WIDTH
	var board := Rect2(0.0, 0.0, width, BOARD_HEIGHT)
	_panel(board.grow(BORDER * 0.5).abs(), SimPalette.INK, SimPalette.INK, SHADOW)
	_panel(board, SimPalette.PAPER, SimPalette.INK, Vector2.ZERO)

	var inner := board.grow(-PAD)
	var x := inner.position.x
	var home_chip := Rect2(x, inner.position.y, CHIP_WIDTH, inner.size.y)
	x += CHIP_WIDTH
	var middle := Rect2(x, inner.position.y, SCORE_WIDTH, inner.size.y)
	x += SCORE_WIDTH
	var away_chip := Rect2(x, inner.position.y, CHIP_WIDTH, inner.size.y)
	x += CHIP_WIDTH
	var clock := Rect2(x, inner.position.y, CLOCK_WIDTH, inner.size.y)

	_draw_chip(home_chip, home_name, home_kit, 0)
	_text(middle, "%d - %d" % [_score[0], _score[1]], SCORE_SIZE, SimPalette.INK, SimPalette.PAPER)
	_draw_chip(away_chip, away_name, away_kit, 1)
	_draw_clock(clock)
	_draw_prompt(board)


## A team's end of the board: kit colour behind, the short name in whatever
## reads on top of it, flashing to lemon while that side's goal is being sold.
func _draw_chip(rect: Rect2, label: String, kit: Color, team: int) -> void:
	var fill := kit
	if _pulse_team == team:
		fill = kit.lerp(SimPalette.LEMON, _pulse_shape())
	_panel(rect, fill, SimPalette.INK, Vector2.ZERO)
	var ink := SimPalette.contrast_for(fill)
	_text(rect, label, NAME_SIZE, ink, SimPalette.contrast_for(ink))


## The clock, or the name of the break when play has stopped for one, on an ink
## chip at the end of the strip so it reads apart from the two kits. A period
## label is longer than a time and gets the smaller size, which is also how the
## eye is told the number it was reading has been replaced by a word.
func _draw_clock(rect: Rect2) -> void:
	var label := ""
	var size_px := CLOCK_SIZE
	match _period:
		SimConsts.Period.HALF_TIME:
			label = "HALF TIME"
			size_px = PERIOD_SIZE
		SimConsts.Period.FULL_TIME:
			label = "FULL TIME"
			size_px = PERIOD_SIZE
		_:
			label = "%02d:%02d" % [int(_clock / 60.0), int(_clock) % 60]
	_panel(rect, SimPalette.INK, SimPalette.INK, Vector2.ZERO)
	_text(rect, label, size_px, SimPalette.PAPER, SimPalette.INK)


## What to press when the football has stopped, on a chip of its own hung below
## the board and flush with its left edge. Lemon, because it is the one thing on
## screen asking to be acted on, and sized to its words so it reads as a label
## on the board rather than a second board.
func _draw_prompt(board: Rect2) -> void:
	var text := prompt if prompt != "" else subtitle
	if text == "":
		return
	var fill := SimPalette.LEMON if prompt != "" else SimPalette.PAPER
	var width := _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_SIZE
	).x + PROMPT_PAD * 2.0
	var chip := Rect2(
		Vector2(board.position.x, board.end.y + PROMPT_GAP), Vector2(width, PROMPT_HEIGHT)
	)
	_panel(chip.grow(BORDER * 0.5).abs(), SimPalette.INK, SimPalette.INK, SHADOW)
	_panel(chip, fill, SimPalette.INK, Vector2.ZERO)
	_text(chip, text, PROMPT_SIZE, SimPalette.INK, fill)


func _panel(rect: Rect2, fill: Color, border: Color, offset: Vector2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(BORDER))
	box.set_corner_radius_all(int(CORNER))
	draw_style_box(box, Rect2(rect.position + offset, rect.size))


## Centred in both axes, with an outline heavy enough that a dark numeral still
## reads where the panel behind it happens to be dark too.
func _text(rect: Rect2, text: String, size_px: int, colour: Color, outline: Color) -> void:
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var baseline := (
		rect.position.y
		+ rect.size.y * 0.5
		+ (_font.get_ascent(size_px) - _font.get_descent(size_px)) * 0.5
	)
	var at := Vector2(rect.position.x + (rect.size.x - extent.x) * 0.5, baseline)
	var thickness := maxi(2, size_px / 7)
	draw_string_outline(
		_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, thickness, outline
	)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)
