class_name MatchDebugOverlay
extends Control
## The live debug panels drawn over the match (`./run.sh view3d --debug`).
##
## It answers "why did that man just do that", which is the question a statistic
## can never answer and the reason the owner has to describe what he saw. It is
## not a second diagnostics: `diagnose` says how often something happens over a
## match, this says what happened here, once.
##
## Presentation. It reads the context and never writes to it. That is a widening
## of the §2.3 rule — the 2D view already reads `ctx.value.debug_grid` — and it
## is kept to this file and `MatchDebugWorld` so the boundary stays one place
## wide.
##
## The whole design problem is readability. Twenty-two players deciding about
## once a second is a waterfall nobody can read, so:
##
## 1. One subject, and it is the man on the ball.
## 2. Latch, never stream. A decision is instantaneous and the eye arrives late.
## 3. Show what he was choosing between — the options within one softmax spread
##    of the best — not everything that was enumerated.
## 4. Space goes on the pitch (`MatchDebugWorld`), quantities go in text.
## 5. One line per thing that is not the decision itself.
##
## The carrier panel is one moment of one man, and his last eight touches are a
## second question the same subject answers: a carrier who has hit the same
## square pass eight times running is a complaint about the engine, and no single
## decision panel can show it. One line each, chosen option only.

## Authored at this height and scaled from it, like the scoreboard, so the same
## layout numbers hold at 720p and at 4K.
const REFERENCE_HEIGHT := 720.0
const SCALE_MIN := 0.75
const SCALE_MAX := 1.6

const MARGIN := 14.0
## Where the panels start, below the scoreboard. The board sits in the top-left
## corner with a prompt chip under it, about 102 deep at its own scale, so
## anything higher than this collides with it.
const TOP := 122.0
const PAD := 9.0
const ROW := 15.0
const FONT_SIZE := 12
const HEAD_SIZE := 14

const PANEL_WIDTH := 560.0
const STRIP_WIDTH := 280.0
const TICKER_WIDTH := 400.0
## The recent-decisions pane, under the strip on the right. Wider than the strip
## because a row is a clock, an option and a score.
const RECENT_WIDTH := 330.0
## Where the score sits in that pane, from its inner edge.
const RECENT_COL_SCORE := 264.0

## Rejected options shown under the chosen one. Four rows is the whole budget:
## past that it is a list, and a list is the thing this is instead of.
const MAX_REJECTED := 4
## The two next-best are shown whether or not they cleared the gate. A panel
## saying only what he did, with nothing beside it, is the one thing here that
## cannot answer a question: the whole point is what the choice beat.
const MIN_REJECTED := 2
## How far below the best an option may score and still be worth printing, in
## multiples of the softmax's own spread. Anything outside this was never in
## contention — the softmax gave it a weight of zero — and printing it is noise.
const SPREAD_GATE := 1.0
const TICKER_LINES := 8
## Wall seconds a decision must be shown for before a newer one may replace it.
## At 8x, without this, the panel is a strobe.
const LATCH_MIN := 0.35

## Columns within the panel, in authored units from the panel's inner edge.
const COL_SCORE := 236.0
const COL_TERMS := 296.0
const COL_WEIGHT := 508.0

const PHASE_NAMES := [
	"kick-off", "build-up", "attack", "transition to defend", "transition to attack",
	"defend", "set piece", "dead ball",
]

## Set by the view each frame, so the help line can say what the keys did.
var status_line := ""
var layer_line := ""
var home_kit := SimPalette.RED
var away_kit := SimPalette.SKY
## The player whose panel is pinned open, or -1.
var pinned := -1

var _font: Font
var _ctx: SimContext = null
## The moment being shown: live while the match is running, and a recorded one
## while the picture has been stepped back. Everything drawn here comes off it,
## so the panels describe the football on screen rather than the football now.
var _frame: MatchDebugFrame = null
var _stepped_back := false
var _clock := 0.0
var _last_tick := -1
var _cursor := 0
## Whether the ticker has skipped whatever was already in the log when it opened.
var _primed := false
var _ticker: Array[Dictionary] = []
var _latched := {}
var _latch_age := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Called once a frame by the view: the context, the live snapshot, and the
## moment to describe. The two are the same thing until the picture is stepped
## back, and then `live` is what the ticker keeps reading while `frame` is what
## every panel is about.
func show_state(ctx: SimContext, live: SimSnapshot, frame: MatchDebugFrame, delta: float) -> void:
	if ctx != _ctx or live.tick < _last_tick:
		_reset()
	_ctx = ctx
	_frame = frame
	_stepped_back = frame != null and frame.captured() and frame.tick < live.tick
	_clock = live.clock
	_last_tick = live.tick
	_pump_events(ctx)
	_advance_latch(delta)
	queue_redraw()


## The decision the panel is currently showing, so the option lines drawn on the
## grass are the ones being read about rather than a newer set.
##
## Stepped back, that is the last decision anybody had taken by the tick on
## screen. The latch is a fix for an eye that arrives late at a match running at
## 8x, and there is no such thing to fix in a picture that is standing still.
func latched() -> Dictionary:
	return SimDebug.newest_at(_frame.tick) if _stepped_back else _latched


func _reset() -> void:
	_cursor = 0
	_primed = false
	_ticker.clear()
	_latched = {}
	_latch_age = 0.0
	_stepped_back = false
	pinned = -1


## New telemetry since the last frame, filtered down to the handful of kinds a
## live readout can carry. `SimDebug.event_text` owns which those are.
func _pump_events(ctx: SimContext) -> void:
	var events := ctx.telemetry.events
	if _cursor > events.size():
		_cursor = 0
	# Opened mid-match — with F1, or on a bookmark that has just fast-forwarded —
	# the log already holds an hour of football. A line is stamped with the clock
	# it was read at, so pumping that backlog would print eighty events all
	# claiming to have happened at once. The ticker starts here instead.
	if not _primed:
		_primed = true
		_cursor = events.size()
		return
	while _cursor < events.size():
		var e := events[_cursor]
		_cursor += 1
		var text := SimDebug.event_text(ctx, e)
		if text == "":
			continue
		# The tick is what the line is stamped with for the step-back, and the clock
		# is what it is printed with: a line read at 30x was read some way after it
		# happened, and the clock it was read at is the one beside it on screen.
		_ticker.append({
			"clock": _clock, "tick": int(e.get("t", -1)), "text": text,
			"team": int(e.get("team", -1)),
		})
		if _ticker.size() > TICKER_LINES:
			_ticker.remove_at(0)


## Holds the last decision until a newer one has waited its turn. Which means the
## panel keeps showing what the man who has just released the ball chose, which
## is when the eye goes looking for it.
func _advance_latch(delta: float) -> void:
	_latch_age += delta
	var newest := SimDebug.newest()
	if newest.is_empty():
		return
	if _latched.is_empty():
		_latched = newest
		_latch_age = 0.0
		return
	if int(newest["tick"]) != int(_latched["tick"]) and _latch_age >= LATCH_MIN:
		_latched = newest
		_latch_age = 0.0


func _draw() -> void:
	if _font == null or _ctx == null or _frame == null or not _frame.captured():
		return
	var s := clampf(size.y / REFERENCE_HEIGHT, SCALE_MIN, SCALE_MAX)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var view := size / s
	var subject := latched()
	var below := _draw_decision(Vector2(MARGIN, TOP), subject, -1)
	if pinned >= 0:
		_draw_decision(Vector2(MARGIN, below + 8.0), SimDebug.last_for_at(pinned, _frame.tick), pinned)
	_draw_recent(view, _draw_strip(view) + 8.0, subject)
	_draw_ticker(view)
	_draw_help(view)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- The decision panel -----------------------------------------------------


## One player's last decision, and for a pinned man what the movement layers have
## him doing as well. Returns the y the panel ended at.
func _draw_decision(at: Vector2, rec: Dictionary, pin_id: int) -> float:
	var is_pin := pin_id >= 0
	var rows := _rows_of(rec)
	var extra := 2 if is_pin else 1
	var height := PAD * 2.0 + ROW * float(rows.size() + 2 + extra)
	var rect := Rect2(at, Vector2(PANEL_WIDTH, height))
	_panel(rect)
	var x := at.x + PAD
	var y := at.y + PAD + ROW * 0.8

	if rec.is_empty():
		_text(Vector2(x, y), "PINNED %s" % _shirt(pin_id) if is_pin else "ON THE BALL",
			HEAD_SIZE, SimPalette.SAND)
		_text(Vector2(x, y + ROW),
			_pin_state(pin_id) if is_pin else "nothing decided yet",
			FONT_SIZE, _dim(SimPalette.CHALK))
		return rect.end.y

	var team := int(rec["team"])
	_chip(Vector2(x, y - ROW * 0.75), _kit(team))
	_text(Vector2(x + 14.0, y), "%s  #%d %s %s" % [
		"PINNED" if is_pin else "ON THE BALL", rec["shirt"], rec["role"], rec["name"],
	], HEAD_SIZE, SimPalette.SAND)
	_right(Vector2(at.x + PANEL_WIDTH - PAD, y), SimDebug.clock_text(rec["clock"]), FONT_SIZE,
		_dim(SimPalette.CHALK))
	y += ROW

	_text(Vector2(x, y), "pressure %.1f   challenge %.1f   regain %.1f   stamina %.2f" % [
		rec["pressure"], rec["challenge"], rec["regain"], rec["stamina"],
	], FONT_SIZE, _dim(SimPalette.CHALK))
	y += ROW

	for row in rows:
		_draw_option(Vector2(x, y), row["opt"], row["chosen"])
		y += ROW
	if not is_nan(float(rec["temp"])):
		_text(Vector2(x, y), "temp %.4f   spread %.4f   of %d candidates" % [
			rec["temp"], rec["spread"], rec["candidates"],
		], FONT_SIZE, _dim(SimPalette.SLATE))
	if is_pin:
		y += ROW
		_text(Vector2(x, y), _pin_state(int(rec["id"])), FONT_SIZE, _dim(SimPalette.CHALK))
	return rect.end.y


## The chosen option, and the ones that were genuinely competing with it.
func _rows_of(rec: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if rec.is_empty():
		return out
	var options: Array = rec["options"]
	var chosen := int(rec["chosen"])
	var best := -INF
	for opt in options:
		var s := float(opt["score"])
		if not is_nan(s):
			best = maxf(best, s)
	var gate := SPREAD_GATE * float(rec["spread"]) if not is_nan(float(rec["spread"])) else INF
	for i in options.size():
		var opt: Dictionary = options[i]
		var contending := float(opt["score"]) >= best - gate or is_nan(float(opt["score"]))
		var live := i == chosen or contending or out.size() <= MIN_REJECTED
		if not live or out.size() > MAX_REJECTED:
			continue
		out.append({"opt": opt, "chosen": i == chosen})
	return out


func _draw_option(at: Vector2, opt: Dictionary, chosen: bool) -> void:
	var colour: Color = SimPalette.LEMON if chosen else _dim(SimPalette.CHALK)
	_text(Vector2(at.x, at.y), "%s %s" % ["  >" if chosen else "   ", opt["label"]], FONT_SIZE, colour)
	if is_nan(float(opt["score"])):
		return
	_text(Vector2(at.x + COL_SCORE, at.y), "%.4f" % opt["score"], FONT_SIZE, colour)
	if not is_nan(float(opt["success"])):
		_text(Vector2(at.x + COL_TERMS, at.y), "succ %.2f  gain %.3f  loss %.3f" % [
			opt["success"], opt["gain"], opt["loss"],
		], FONT_SIZE, _dim(SimPalette.SLATE))
	# The softmax weight as a bar rather than a number: what matters is whether
	# the option had a real chance of being taken, not its third decimal place.
	if is_nan(float(opt["weight"])):
		return
	var w := clampf(float(opt["weight"]), 0.0, 1.0)
	draw_rect(Rect2(at.x + COL_WEIGHT, at.y - ROW * 0.55, 32.0, ROW * 0.5),
		Color(SimPalette.SLATE, 0.35))
	draw_rect(Rect2(at.x + COL_WEIGHT, at.y - ROW * 0.55, 32.0 * w, ROW * 0.5), colour)


## What the movement layers have this player doing, which is the other half of
## why he is where he is.
func _pin_state(id: int) -> String:
	if _frame == null or id < 0 or id >= _frame.count:
		return ""
	var intent: String = SimOffBall.KIND_NAMES[_frame.intent[id]]
	var chase := _frame.chase[id]
	var chasing: String = ["-", "primary", "support"][chase] if chase >= 0 and chase < 3 else "-"
	return "offering %s   chase %s   marking %s   next decision in %d ticks" % [
		intent, chasing, _shirt(_frame.marking[id]), maxi(_frame.next_decision[id], 0),
	]


# --- The state strip --------------------------------------------------------


## The four things that answer "why is nobody moving". Returns the y it ended at,
## because the recent-decisions pane sits under it and the strip grows a line at
## a time.
func _draw_strip(view: Vector2) -> float:
	var lines := PackedStringArray()
	# Said first, because every line under it is about a moment that has already
	# been and gone and there is nothing else on the strip to give that away.
	if _stepped_back:
		lines.append("STEPPED BACK  t%d, %.1f s" % [
			_frame.tick, float(_last_tick - _frame.tick) / float(SimConsts.TICK_HZ),
		])
	var phase := _frame.phase
	lines.append("phase     %s%s" % [
		PHASE_NAMES[phase] if phase >= 0 and phase < PHASE_NAMES.size() else "?",
		"" if _frame.in_play else "   (dead)",
	])
	if _frame.possession_team >= 0:
		# A team can be in possession with nobody on the ball: it is running loose
		# between two of theirs, which is a different thing from a contest.
		var who := " " + _shirt(_frame.possession_player) if _frame.possession_player >= 0 else ""
		lines.append("ball      %s%s, %.1f s" % [
			_ctx.teams[_frame.possession_team].short_name, who,
			float(_frame.possession_ticks) / float(SimConsts.TICK_HZ),
		])
	else:
		lines.append("ball      loose")
	for run in _frame.patterns:
		lines.append("pattern   %s %s, %.1f s left" % [
			run["name"], _shirt(int(run["runner"])),
			float(int(run["left"])) / float(SimConsts.TICK_HZ),
		])
	if _frame.restart_kind >= 0:
		lines.append("restart   %s %s, held %.1f s" % [
			SimSetPiece.kind_name(_frame.restart_kind), _shirt(_frame.restart_taker),
			float(_frame.restart_hold) / float(SimConsts.TICK_HZ),
		])
	if _frame.offside_pending >= 0:
		lines.append("offside   flag up on %s" % _shirt(_frame.offside_pending))

	var rect := Rect2(
		Vector2(view.x - STRIP_WIDTH - MARGIN, TOP),
		Vector2(STRIP_WIDTH, PAD * 2.0 + ROW * float(lines.size()))
	)
	_panel(rect)
	var y := rect.position.y + PAD + ROW * 0.8
	for line in lines:
		_text(Vector2(rect.position.x + PAD, y), line, FONT_SIZE, _dim(SimPalette.CHALK))
		y += ROW
	return rect.end.y


# --- What he has been doing -------------------------------------------------


## The subject's last few decisions, newest first, one line each.
##
## The panel above says why he did this; this says what he has been doing, which
## is a different complaint and the one a single decision cannot answer. Eight is
## not a choice made here — it is everything `SimDebug` keeps per player, and it
## is about half a minute of a busy midfielder.
##
## The subject is whoever the carrier panel is about, so the two always describe
## the same man: the panel is one of these lines, opened up.
func _draw_recent(view: Vector2, top: float, subject: Dictionary) -> void:
	if subject.is_empty():
		return
	var rows: Array[Dictionary] = []
	for rec in SimDebug.history_for(int(subject["id"])):
		# Stepped back, a decision he has not taken yet is not history.
		if _stepped_back and int(rec["tick"]) > _frame.tick:
			continue
		rows.append(rec)
	if rows.is_empty():
		return
	rows.reverse()

	var rect := Rect2(
		Vector2(view.x - RECENT_WIDTH - MARGIN, top),
		Vector2(RECENT_WIDTH, PAD * 2.0 + ROW * float(rows.size() + 1))
	)
	_panel(rect)
	var x := rect.position.x + PAD
	var y := rect.position.y + PAD + ROW * 0.8
	_text(Vector2(x, y), "LAST %d ON THE BALL  #%d" % [SimDebug.PER_PLAYER, subject["shirt"]],
		HEAD_SIZE, SimPalette.SAND)
	y += ROW
	for i in rows.size():
		_draw_recent_row(Vector2(x, y), rows[i], i, rows.size(), int(subject["tick"]))
		y += ROW


## One past decision: when, what he took, and what it scored.
##
## The lemon row is the one the panel opposite is about, which is not always the
## top one: the panel holds a decision for a third of a second and at 8x the man
## has taken another by then. Marking the row the panel is open on says which,
## rather than leaving two panels disagreeing about the same player. The rest
## fade back with age, so the shape of what he has been doing is still readable.
func _draw_recent_row(at: Vector2, rec: Dictionary, index: int, count: int,
		subject_tick: int) -> void:
	var open := int(rec["tick"]) == subject_tick
	var fade: float = 1.0 if open else lerpf(0.8, 0.4, float(index) / float(maxi(count - 1, 1)))
	var colour: Color = Color(SimPalette.LEMON if open else SimPalette.CHALK, fade)
	_text(at, SimDebug.clock_text(rec["clock"]), FONT_SIZE, Color(SimPalette.SLATE, fade))
	var options: Array = rec["options"]
	var chosen := int(rec["chosen"])
	if chosen < 0 or chosen >= options.size():
		return
	var opt: Dictionary = options[chosen]
	_text(Vector2(at.x + 44.0, at.y), opt["label"], FONT_SIZE, colour)
	if not is_nan(float(opt["score"])):
		_right(Vector2(at.x + RECENT_COL_SCORE, at.y), "%.4f" % opt["score"], FONT_SIZE, colour)


# --- The ticker -------------------------------------------------------------


func _draw_ticker(view: Vector2) -> void:
	# Stepped back, the lines below the moment on screen are things that have not
	# happened yet in the picture. A goal listed under a still of the build-up to
	# it is the worst version of the whole problem.
	var shown: Array[Dictionary] = []
	for line in _ticker:
		if _stepped_back and int(line["tick"]) > _frame.tick:
			continue
		shown.append(line)
	if shown.is_empty():
		return
	var height := PAD * 2.0 + ROW * float(shown.size())
	var rect := Rect2(
		Vector2(MARGIN, view.y - MARGIN - ROW * 2.0 - 12.0 - height), Vector2(TICKER_WIDTH, height)
	)
	_panel(rect)
	var y := rect.position.y + PAD + ROW * 0.8
	for i in shown.size():
		var line: Dictionary = shown[i]
		# The oldest lines fade rather than vanish, so the eye lands on the newest.
		var fade: float = lerpf(0.45, 1.0, float(i + 1) / float(shown.size()))
		var team := int(line["team"])
		var colour: Color = _kit(team) if team >= 0 else SimPalette.CHALK
		_text(Vector2(rect.position.x + PAD, y), SimDebug.clock_text(line["clock"]), FONT_SIZE,
			Color(SimPalette.SLATE, fade))
		_text(Vector2(rect.position.x + PAD + 44.0, y), line["text"], FONT_SIZE, Color(colour, fade))
		y += ROW


## Two rows: the seven layers and their keys above, the transport below. On one
## row it runs off the right-hand edge of a 720p window.
func _draw_help(view: Vector2) -> void:
	_text(Vector2(MARGIN, view.y - MARGIN - ROW), layer_line, FONT_SIZE, _dim(SimPalette.CHALK))
	_text(Vector2(MARGIN, view.y - MARGIN), status_line, FONT_SIZE, _dim(SimPalette.CHALK))


# --- Drawing helpers --------------------------------------------------------


func _panel(rect: Rect2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SimPalette.INK, 0.9)
	box.border_color = Color(SimPalette.PAPER, 0.22)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	draw_style_box(box, rect)


func _chip(at: Vector2, colour: Color) -> void:
	draw_rect(Rect2(at, Vector2(9.0, 9.0)), colour)


func _text(at: Vector2, text: String, size_px: int, colour: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)


func _right(at: Vector2, text: String, size_px: int, colour: Color) -> void:
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	draw_string(_font, at - Vector2(extent.x, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)


func _kit(team: int) -> Color:
	return home_kit if team == SimConsts.TEAM_HOME else away_kit


func _shirt(id: int) -> String:
	if _ctx == null or id < 0 or id >= _ctx.players.size():
		return "-"
	return "#%d" % _ctx.players[id].shirt


static func _dim(colour: Color) -> Color:
	return Color(colour, 0.78)
