class_name SimDebug
extends RefCounted
## The debug capture sink: what a player decided, and what he turned down.
##
## Off by default, written by two call sites, and read by nothing inside the
## simulation. It is a one-way tap.
##
## It exists because the candidate list is scratch. `SimDecision._candidates` is
## cleared at the start of the next decision, so by the time anything outside the
## sim could ask what a player was choosing between, the answer has been
## overwritten. Everything else the overlay wants -- pressure, intents, chase
## roles, beliefs -- is still on the context when the frame is drawn.
##
## It is deliberately not a telemetry event kind. `SimTelemetry.canonical_text`
## is hashed by the golden replay test, so a debug channel routed through the
## event log would move every digest in the project for a tool that is not part
## of the match.
##
## Nothing here touches `ctx.rng`, and nothing in `sim/` reads it back, so a
## match runs identically with it on. `./run.sh determinism` with `--debug` is
## that check.

## The whole cost when nobody is watching: one boolean test per on-ball decision.
static var enabled := false

## Decisions kept per player, and overall. A decision is only taken by the man in
## contact with the ball, so the whole match runs at two to five a second and a
## few hundred records is half a minute of football.
const PER_PLAYER := 8
const RECENT := 600
## Options kept per decision, best first. `_add_passes` alone can offer six
## targets in three flavours; nothing beyond the first handful was ever in
## contention.
const MAX_OPTIONS := 8

## Mirrors `SimDecision.Action`, deliberately rather than importing it: this file
## is referenced from `SimDecision`, and naming it back would be a cycle.
const ACTION_NAMES := ["hold", "carry", "pass", "lofted", "through", "cross", "shot", "clear"]
const A_HOLD := 0
const A_DRIBBLE := 1
const A_SHOOT := 6
const A_CLEAR := 7

static var _recent: Array[Dictionary] = []
static var _by_player := {}
## The tick of the last capture, so a second match in the same process -- the
## view's `N` and `R` keys, a batch, the test suite -- does not inherit the first
## one's records. Static state outlives the context that made it. The view clears
## the sink itself at kick-off rather than wait for this, because this only fires
## on the new match's first capture and the panel is latched until then.
static var _last_tick := -1


static func reset() -> void:
	_recent.clear()
	_by_player.clear()
	_last_tick = -1


## The full record: every candidate the softmax weighed, the one it took, and the
## temperature it took it at.
static func capture_decision(ctx: SimContext, player: SimPlayer, candidates: Array[Dictionary],
		picked: int, weights: PackedFloat32Array, temp: float, spread: float, regain: float) -> void:
	if not enabled:
		return
	_roll_over(ctx)

	var total := 0.0
	for i in mini(weights.size(), candidates.size()):
		total += weights[i]
	var order := _ranked(candidates)
	var attack := ctx.pitch.attack_dir(player.team)

	var options: Array[Dictionary] = []
	var chosen := -1
	for idx in order:
		if options.size() >= MAX_OPTIONS and idx != picked:
			continue
		if idx == picked:
			chosen = options.size()
		var w := 0.0
		if idx < weights.size() and total > 0.0:
			w = weights[idx] / total
		options.append(_option(ctx, player, candidates[idx], w, attack))

	_store(_record(ctx, player, regain, options, chosen, candidates.size(), temp, spread))


## The short form, for a decision that is a branch rather than a scored list.
## The keeper's is the only one: two options and a dice roll.
static func capture_choice(ctx: SimContext, player: SimPlayer, chosen_label: String,
		other_labels: PackedStringArray) -> void:
	if not enabled:
		return
	_roll_over(ctx)
	var options: Array[Dictionary] = [_label_option(chosen_label)]
	for label in other_labels:
		options.append(_label_option(label))
	_store(_record(ctx, player, 0.0, options, 0, options.size(), NAN, NAN))


# --- Reading ----------------------------------------------------------------


## The most recent decision by anybody, or an empty dictionary.
static func newest() -> Dictionary:
	return _recent[_recent.size() - 1] if not _recent.is_empty() else {}


## The most recent decision by one player, or an empty dictionary.
static func last_for(id: int) -> Dictionary:
	var rows: Array = _by_player.get(id, [])
	return rows[rows.size() - 1] if not rows.is_empty() else {}


## The most recent decision by anybody at or before a tick.
##
## What the overlay wants when the picture has been stepped back: the decision
## that was the latest one *then*, not the latest one now. Records are stored in
## tick order, so this walks back from the end and stops at the first that had
## already happened.
static func newest_at(tick: int) -> Dictionary:
	for i in range(_recent.size() - 1, -1, -1):
		if int(_recent[i]["tick"]) <= tick:
			return _recent[i]
	return {}


## The same, for one player.
static func last_for_at(id: int, tick: int) -> Dictionary:
	var rows: Array = _by_player.get(id, [])
	for i in range(rows.size() - 1, -1, -1):
		if int(rows[i]["tick"]) <= tick:
			return rows[i]
	return {}


static func history_for(id: int) -> Array:
	return _by_player.get(id, [])


## Every decision inside a tick window, oldest first.
static func between(from_tick: int, to_tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec in _recent:
		var t: int = rec["tick"]
		if t >= from_tick and t <= to_tick:
			out.append(rec)
	return out


## One decision as text. Shared by the bookmark file and `./run.sh replay`, so
## what the owner marks on screen and what a report quotes are the same lines.
static func describe(rec: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if rec.is_empty():
		return out
	out.append("%s  #%d %s %s   pressure %.1f  challenge %.1f  regain %.1f  stamina %.2f" % [
		clock_text(rec["clock"]), rec["shirt"], rec["role"], rec["name"],
		rec["pressure"], rec["challenge"], rec["regain"], rec["stamina"],
	])
	var options: Array = rec["options"]
	for i in options.size():
		out.append("  %s %s" % ["  >" if i == int(rec["chosen"]) else "   ", option_text(options[i])])
	if not is_nan(float(rec["temp"])):
		out.append("     temp %.4f  spread %.4f  of %d candidates" % [
			rec["temp"], rec["spread"], rec["candidates"],
		])
	return out


## One option as a line: what it was, what it scored, and the three numbers the
## score is made of. A dribble taken 0.003 ahead of a pass is a different
## complaint from one taken 0.03 ahead, and only this says which it was.
static func option_text(opt: Dictionary) -> String:
	var head: String = opt["label"]
	if is_nan(float(opt["score"])):
		return head
	var tail := "%8.4f" % opt["score"]
	if not is_nan(float(opt["success"])):
		tail += "   succ %.2f  gain %.3f  loss %.3f  bias %.2f" % [
			opt["success"], opt["gain"], opt["loss"], opt["bias"],
		]
	return "%-26s %s   w %2.0f%%" % [head, tail, opt["weight"] * 100.0]


## One event as a line, or "" for the ones that must never reach a live readout.
##
## `TOUCH` is the waterfall -- several hundred a match -- and a bare
## `PASS_ATTEMPT` says nothing its outcome will not say a second later, so both
## are left out. This is the same filter on screen, in a bookmark and in a
## replay, because a complaint and the report answering it should be quoting the
## same lines.
static func event_text(ctx: SimContext, e: Dictionary) -> String:
	match int(e["ev"]):
		SimTelemetry.Ev.PASS_OUTCOME:
			var kind := SimTelemetry.touch_name(int(e.get("kind", -1)))
			if bool(e.get("ok", false)):
				return "%s %s -> %s" % [_shirt(ctx, e, "p"), kind, _shirt_of(ctx, int(e.get("receiver", -1)))]
			return "%s %s, cut out by %s" % [
				_shirt(ctx, e, "p"), kind, _shirt_of(ctx, int(e.get("receiver", -1))),
			]
		SimTelemetry.Ev.SHOT:
			var tail := "off target"
			if bool(e.get("goal", false)):
				tail = "GOAL"
			elif bool(e.get("blocked", false)):
				tail = "blocked"
			elif bool(e.get("on_target", false)):
				tail = "on target"
			return "%s shot, %.0f m, xG %.2f — %s" % [
				_shirt(ctx, e, "p"), e.get("dist", 0.0), e.get("quality", 0.0), tail,
			]
		SimTelemetry.Ev.SAVE:
			return "%s %s" % [_shirt(ctx, e, "p"), "catches it" if bool(e.get("caught", false)) else "parries it"]
		SimTelemetry.Ev.GOAL:
			return "GOAL %s%s   %d-%d" % [
				_shirt(ctx, e, "p"), " (own goal)" if bool(e.get("own_goal", false)) else "",
				e.get("score_h", 0), e.get("score_a", 0),
			]
		SimTelemetry.Ev.DUEL:
			return "%s wins the duel from %s" % [
				_shirt_of(ctx, int(e.get("winner", -1))), _shirt_of(ctx, int(e.get("loser", -1))),
			]
		SimTelemetry.Ev.RECOVERY:
			return "%s recovers%s" % [_shirt(ctx, e, "p"), "" if bool(e.get("clean", false)) else ", scrappily"]
		SimTelemetry.Ev.FOUL:
			return "foul by %s on %s" % [_shirt(ctx, e, "p"), _shirt_of(ctx, int(e.get("victim", -1)))]
		SimTelemetry.Ev.CARD:
			return "%s booked%s" % [_shirt(ctx, e, "p"), " — RED" if bool(e.get("red", false)) else ""]
		SimTelemetry.Ev.OFFSIDE:
			return "%s offside" % _shirt(ctx, e, "p")
		SimTelemetry.Ev.SET_PIECE:
			return "%s, %s" % [SimSetPiece.kind_name(int(e.get("kind", -1))), _team_name(ctx, e)]
		SimTelemetry.Ev.KICKOFF:
			return "kick-off, %s" % _team_name(ctx, e)
		SimTelemetry.Ev.PATTERN:
			if e.has("ok"):
				return "pattern: %s %s" % [e.get("name", "?"), "came off" if bool(e["ok"]) else "did not"]
			return "pattern: %s %s" % [e.get("name", "?"), _shirt(ctx, e, "p")]
		SimTelemetry.Ev.PERIOD:
			return ["first half", "half time", "second half", "full time"][int(e.get("period", 0))]
	return ""


static func _shirt(ctx: SimContext, e: Dictionary, key: String) -> String:
	return _shirt_of(ctx, int(e.get(key, -1)))


static func _shirt_of(ctx: SimContext, id: int) -> String:
	if id < 0 or id >= ctx.players.size():
		return "?"
	return "#%d" % ctx.players[id].shirt


static func _team_name(ctx: SimContext, e: Dictionary) -> String:
	var team := int(e.get("team", -1))
	if team < 0 or team >= ctx.teams.size():
		return "?"
	return ctx.teams[team].short_name


static func clock_text(clock: float) -> String:
	return "%02d:%02d" % [int(clock / 60.0), int(clock) % 60]


# --- Building ---------------------------------------------------------------


static func _record(ctx: SimContext, player: SimPlayer, regain: float, options: Array[Dictionary],
		chosen: int, candidates: int, temp: float, spread: float) -> Dictionary:
	return {
		"tick": ctx.tick_index,
		"clock": ctx.clock,
		"id": player.id,
		"shirt": player.shirt,
		"team": player.team,
		"name": player.player_name,
		"role": SimRole.name_of(player.role),
		"pos": player.pos,
		"pressure": ctx.pressure_on(player),
		"challenge": ctx.challenge_on(player),
		"regain": regain,
		"stamina": player.stamina,
		"options": options,
		"chosen": chosen,
		"candidates": candidates,
		"temp": temp,
		"spread": spread,
	}


static func _option(ctx: SimContext, player: SimPlayer, c: Dictionary, weight: float,
		attack: float) -> Dictionary:
	var action := int(c.get("action", -1))
	var point: Vector3 = c.get("point", c.get("aim", player.pos))
	var target := int(c.get("target", -1))
	var catch := _catch_point(ctx, player, c)
	return {
		"action": action,
		"label": _label(ctx, player, action, target, point, attack, catch),
		"point": point,
		"catch": catch,
		"target": target,
		"success": float(c.get("success", NAN)),
		"gain": float(c.get("gain", NAN)),
		"loss": float(c.get("loss", NAN)),
		"bias": float(c.get("bias", 1.0)),
		"score": float(c.get("score", NAN)),
		"weight": weight,
	}


static func _label_option(label: String) -> Dictionary:
	return {
		"action": -1, "label": label, "point": Vector3.ZERO, "catch": Vector3.INF, "target": -1,
		"success": NAN, "gain": NAN, "loss": NAN, "bias": NAN, "score": NAN, "weight": NAN,
	}


## Where the carrier expects to meet the ball again -- his next touch -- if he
## plays this carry. `Vector3.INF` for everything that is not one.
##
## It is a different point from the option's own `point`, and the gap between
## them is the distinction `docs/GLOSSARY.md` draws between the horizon and the
## reach. An ordinary carry's `point` is the *horizon*: how far the direction can
## be pursued at all, which is what every term in the score is read at. The ball
## does not go there. It goes `carry_travel(ahead)`, which is a good deal shorter
## at a walk and longer than it looks at a sprint, and that is the spot the next
## decision gets taken from.
##
## The burst is the exception and needs no work here: its `point` already *is*
## this, because a knock past a man is the one touch in the engine that runs to
## completion. Drawn anyway, so the layer says the same thing about both.
##
## Both halves come from the engine's own functions -- `SimTouch.dribble_ahead`
## for the touch, `SimDecision.carry_travel` for the roll -- so the mark on
## screen cannot disagree with the touch that gets played.
static func _catch_point(ctx: SimContext, player: SimPlayer, c: Dictionary) -> Vector3:
	if int(c.get("action", -1)) != SimDecision.Action.DRIBBLE:
		return Vector3.INF
	var dir: Vector3 = c.get("dir", Vector3.ZERO)
	if dir.length_squared() < 1e-6:
		return Vector3.INF
	var ahead := SimTouch.dribble_ahead(
		ctx, player, float(c.get("space", 0.0)),
		float(c.get("push", 0.0)), float(c.get("max_ahead", INF)))
	var travel := SimDecision.carry_travel(ctx, player, dir, ahead)
	return ctx.pitch.clamp_to_pitch(ctx.ball.ground_pos() + dir * travel, 0.5)


## What the option was, in football rather than in coordinates.
##
## The direction is resolved here, at the moment of the decision, against the way
## the player's side was attacking at the time. Anything that works it out later
## from a stored point has to know which half it was, and `docs/DIAGNOSTICS.md`
## has the two ways that has already gone wrong.
##
## A carry is measured to `catch` -- where he meets the ball again -- and not to
## the option's `point`, which for a carry is the horizon the direction was
## judged over. Labelled off the horizon, as it was, every carry on the panel
## read two to three times longer than the touch about to be played, and a
## four-metre knock under the sole was printed as a twelve-metre run.
static func _label(ctx: SimContext, player: SimPlayer, action: int, target: int, point: Vector3,
		attack: float, catch: Vector3 = Vector3.INF) -> String:
	var name: String = ACTION_NAMES[action] if action >= 0 and action < ACTION_NAMES.size() else "?"
	var delta := point - player.pos
	var distance := SimConsts.horizontal_length(delta)
	match action:
		A_HOLD:
			return "hold"
		A_CLEAR:
			return "clear"
		A_SHOOT:
			return "shot, %.0f m" % SimConsts.horizontal_length(
				ctx.pitch.target_goal(player.team) - player.pos)
		A_DRIBBLE:
			var run := delta if is_inf(catch.x) else catch - player.pos
			return "carry %s %.1f m" % [compass(run, attack), SimConsts.horizontal_length(run)]
		_:
			var mate := "#%d" % ctx.players[target].shirt if target >= 0 and target < ctx.players.size() else "?"
			return "%s -> %s %.0f m %s" % [name, mate, distance, compass(delta, attack)]


## Eight points of the compass in the attacking frame, so "forward" means toward
## the goal this player is attacking whichever half it is.
static func compass(delta: Vector3, attack: float) -> String:
	if SimConsts.horizontal_length(delta) < 0.5:
		return "still"
	var forward := delta.x * attack
	# With +x forward and +y up, the attacking side's right hand is +z.
	var right := delta.z * attack
	var angle := atan2(right, forward)
	var sector := int(roundf(angle / (PI / 4.0))) & 7
	return ["fwd", "fwd-R", "right", "back-R", "back", "back-L", "left", "fwd-L"][sector]


## Candidate indices, best score first.
static func _ranked(candidates: Array[Dictionary]) -> Array:
	var order := []
	for i in candidates.size():
		order.append(i)
	order.sort_custom(func(a, b): return _score_of(candidates, a) > _score_of(candidates, b))
	return order


static func _score_of(candidates: Array[Dictionary], i: int) -> float:
	return float(candidates[i].get("score", -INF))


static func _store(rec: Dictionary) -> void:
	_recent.append(rec)
	if _recent.size() > RECENT:
		_recent.remove_at(0)
	var id: int = rec["id"]
	if not _by_player.has(id):
		_by_player[id] = []
	var rows: Array = _by_player[id]
	rows.append(rec)
	if rows.size() > PER_PLAYER:
		rows.remove_at(0)


static func _roll_over(ctx: SimContext) -> void:
	if ctx.tick_index < _last_tick:
		reset()
	_last_tick = ctx.tick_index
