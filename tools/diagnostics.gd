class_name SimDiagnostics
extends RefCounted
## Breaks a finished match down by touch kind, pass length and outcome.
##
## The validation bands in PLAN.md §11 say whether the engine is wrong; this
## says where. Everything is read from telemetry, so it doubles as a check that
## the event log really does carry enough to explain a match.

const LENGTH_BUCKETS := [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 40.0, 60.0, 1e9]
const REACH_BUCKETS := [0.3, 0.6, 0.9, 1.2, 1e9]

## Chase geometry (see `_chasing`). A defender is "on" a carrier inside this
## radius, and the carrier has to be moving this fast for the geometry to mean
## anything -- standing over the ball has no behind.
const CHASE_NEAR := 5.0
const CARRIER_MIN_SPEED := 2.0
## Sector boundaries on frontness: 0 is directly behind the carrier, 1 is square
## in front of him.
const BEHIND_MAX := 0.35
const AHEAD_MIN := 0.65


## How the ball behaves at a player's feet.
##
## The §11 bands cannot see this at all: an engine where the ball is welded to
## the dribbler and one where it runs free produce the same goals per ninety.
## These are the numbers that say whether a touch looks like a touch — how far
## away a player was when they played the ball, and how long the ball is
## actually theirs between touches. They come off one short match in seconds,
## which is the right loop for a question about feel.
static func _ball_control(events: Array) -> void:
	var reach_hist := PackedInt32Array()
	reach_hist.resize(REACH_BUCKETS.size())
	var reach_sum := 0.0
	var reach_max := 0.0
	var reach_n := 0

	var gaps := 0
	var gap_seconds := 0.0
	var gap_run := 0.0
	var gap_max_run := 0.0
	var prev_kind := -1
	var prev_player := -1
	var prev_tick := 0
	var prev_from := Vector3.ZERO

	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH:
			continue
		if e.has("at"):
			var d: float = SimConsts.horizontal_length(e["from"] - e["at"])
			reach_sum += d
			reach_max = maxf(reach_max, d)
			reach_n += 1
			for i in REACH_BUCKETS.size():
				if d <= float(REACH_BUCKETS[i]):
					reach_hist[i] += 1
					break
		var kind: int = e["kind"]
		var player: int = e["p"]
		# Two dribble touches in a row by the same player is a carry, and the
		# interval between them is the dribble's real rhythm.
		if kind == SimTelemetry.Touch.DRIBBLE and prev_kind == SimTelemetry.Touch.DRIBBLE and player == prev_player:
			var dt := float(int(e["t"]) - prev_tick) / float(SimConsts.TICK_HZ)
			var run: float = SimConsts.horizontal_length(e["from"] - prev_from)
			gaps += 1
			gap_seconds += dt
			gap_run += run
			gap_max_run = maxf(gap_max_run, run)
		prev_kind = kind
		prev_player = player
		prev_tick = int(e["t"])
		prev_from = e["from"]

	if reach_n == 0:
		return
	# Anything past the control range should be impossible, so when it happens
	# the useful question is which kind of touch did it.
	var over := {}
	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH or not e.has("at"):
			continue
		if SimConsts.horizontal_length(e["from"] - e["at"]) <= SimConsts.CONTROL_RANGE:
			continue
		var k: int = e["kind"]
		over[k] = int(over.get(k, 0)) + 1
	print("")
	print("Ball control  (CONTROL_RANGE is %.2f m, measured from the player's centre)" % SimConsts.CONTROL_RANGE)
	print("  reach at contact   mean %.2f m   longest %.2f m" % [reach_sum / float(reach_n), reach_max])
	var last := 0.0
	for i in REACH_BUCKETS.size():
		var hi: float = float(REACH_BUCKETS[i])
		var label := "%.1f - %.1f m" % [last, hi] if hi < 1e8 else "%.1f m +    " % last
		print("    %-14s %6d  %5.1f%%" % [label, reach_hist[i], 100.0 * float(reach_hist[i]) / float(reach_n)])
		last = hi
	if not over.is_empty():
		var parts := PackedStringArray()
		for k in over:
			parts.append("%s %d" % [SimTelemetry.touch_name(k), over[k]])
		print("  beyond reach by kind   %s" % ", ".join(parts))
	if gaps > 0:
		print("  dribble rhythm     %d carries, %.2f s between touches, ball runs %.2f m (longest %.2f m)" % [
			gaps, gap_seconds / float(gaps), gap_run / float(gaps), gap_max_run,
		])
	print("")


## Challenge bands the carrier's touches are bucketed into. `chal` on a touch is
## `SimContext.challenge_on` at the moment he played it.
const CHALLENGE_BANDS := [0.25, 0.8, 1e9]
const CHALLENGE_LABELS := ["free", "closed down", "challenged"]


## What the carrier does about a man coming to take the ball off him.
##
## The complaint this answers is that almost every answer was the same one:
## take another short touch and stay in the challenge. Nothing else printed can
## see it. Touch counts are dominated by uncontested carries, so a carrier who
## never passes out of trouble is invisible inside a healthy-looking dribble
## total, and the §11 bands are blind to it twice over -- an engine that plays
## out of a challenge and one that gets tackled produce much the same possession
## share, because losing it and winning it straight back nets to nothing.
##
## Read the rows against each other rather than any one of them. The free row is
## the baseline shape of the engine's on-ball behaviour; what matters is how far
## the challenged row moves away from it. A challenged row that looks like the
## free row is a carrier who has not noticed the man on his back.
## Half the width of the lane a carry is read as being aimed down. A body
## further off it than this is beside the ball rather than in front of it.
const CARRY_LANE := 2.5
## How far down that lane there is anything worth looking at: two or three
## touches, which is as far ahead as a carry is a decision rather than a plan.
const CARRY_LOOK := 20.0
const CARRY_LANE_BANDS := [3.0, 4.5, 6.0, 8.0, 11.0, 15.0, CARRY_LOOK]
const CARRY_LANE_LABELS := [
	"0 - 3 m", "3 - 4.5 m", "4.5 - 6 m", "6 - 8 m", "8 - 11 m", "11 - 15 m",
	"15 - 20 m", "nobody in the lane",
]
## The same question asked of the paint instead of the bodies: how much grass
## there was between the ball and the nearest line when the touch was played.
const CARRY_EDGE_BANDS := [2.0, 4.0, 7.0, 11.0]
const CARRY_EDGE_LABELS := ["0 - 2 m", "2 - 4 m", "4 - 7 m", "7 - 11 m", "11 m +"]
## How long a carry is given to survive, and a ball to go out, before the touch
## is judged to have had nothing to do with it.
const CARRY_LOST_SECONDS := 2.0
const CARRY_OUT_SECONDS := 3.0


## What the man on the ball carried it *at*, which is the one thing a count of
## carries cannot say.
##
## Every other instrument here reads a carry as one event in one place. A touch
## knocked into fifteen metres of empty grass and the same touch knocked into a
## defender standing six metres up the lane are the same kind, by the same
## player, of the same size, and `Under challenge` rates the second one "free" --
## `challenge_on` has a 5.5 m sight and he is outside it. The only difference
## between them is what happens a second and a half later, and by then the log
## records an interception by somebody who was nowhere near the ball when the
## decision was taken.
##
## So both halves are the touch judged by what was in front of it: bodies in the
## top half, the paint in the bottom. Read the `lost` column against the
## bottom row of the top half, which is the same engine carrying into space --
## that difference is the price of carrying into somebody, and it is the number
## to watch after anything that touches `_add_dribbles`, `_safe_direction` or
## `_play_hold`. A pathology here does not have to be the scoring: three quarters
## of the carries in a match are settling touches, and those are aimed by
## `SimDecision._safe_direction` rather than scored by anything.
static func _where_the_carry_went(ctx: SimContext, events: Array) -> void:
	var trace := ctx.telemetry.trace
	if trace.is_empty():
		return
	var lanes := CARRY_LANE_BANDS.size() + 1
	var lane_count := PackedInt32Array()
	var lane_lost := PackedInt32Array()
	lane_count.resize(lanes)
	lane_lost.resize(lanes)
	var edges := CARRY_EDGE_BANDS.size() + 1
	var edge_count := PackedInt32Array()
	var edge_out := PackedInt32Array()
	var edge_pace := PackedFloat32Array()
	edge_count.resize(edges)
	edge_out.resize(edges)
	edge_pace.resize(edges)

	# When each side lost the ball, and when the ball went out, so "did this
	# touch survive" is a lookup rather than a scan over the whole log.
	var lost_at := {0: PackedInt32Array(), 1: PackedInt32Array()}
	var out_at := PackedInt32Array()
	for e in events:
		match e["ev"]:
			SimTelemetry.Ev.RECOVERY:
				lost_at[SimConsts.other_team(int(e["team"]))].append(int(e["t"]))
			SimTelemetry.Ev.SET_PIECE:
				var k: int = e["kind"]
				if k == SimSetPiece.Kind.THROW_IN or k == SimSetPiece.Kind.CORNER or k == SimSetPiece.Kind.GOAL_KICK:
					out_at.append(int(e["t"]))

	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH or int(e["kind"]) != SimTelemetry.Touch.DRIBBLE:
			continue
		var dir := SimConsts.horizontal(e["vel"])
		if dir.length() < 1e-3:
			continue
		dir = dir.normalized()
		var tick: int = e["t"]
		var sample := tick / SimConsts.TRACE_TICKS
		if sample >= trace.size() or trace[sample].size() != ctx.players.size() + 1:
			continue
		var frame := trace[sample]
		var at: Vector3 = e["at"]
		var team: int = e["team"]

		var nearest := INF
		for p in ctx.players:
			if p.team == team or not p.on_pitch:
				continue
			var to := SimConsts.horizontal(frame[p.id + 1] - at)
			var along := to.dot(dir)
			if along <= 0.0 or along >= nearest:
				continue
			if absf(to.x * -dir.z + to.z * dir.x) < CARRY_LANE:
				nearest = along
		var lane := _band(nearest, CARRY_LANE_BANDS)
		lane_count[lane] += 1
		if _happened_within(lost_at[team], tick, CARRY_LOST_SECONDS):
			lane_lost[lane] += 1

		var from: Vector3 = e["from"]
		var clear: float = minf(
			ctx.pitch.half_width - absf(from.z),
			ctx.pitch.half_length - absf(from.x))
		var edge := _band(clear, CARRY_EDGE_BANDS)
		edge_count[edge] += 1
		edge_pace[edge] += SimConsts.horizontal_length(e["vel"])
		if _happened_within(out_at, tick, CARRY_OUT_SECONDS):
			edge_out[edge] += 1

	var total := 0
	for c in lane_count:
		total += c
	if total == 0:
		return
	print("\nWhere the carry went  (%d carries, judged by what was in front of the touch)" % total)
	print("  nearest opponent in a %.1f m lane down the line of it" % (CARRY_LANE * 2.0))
	for b in lanes:
		if lane_count[b] == 0:
			continue
		print("    %-20s %5d  %4.0f%%   lost inside %.0f s %3.0f%%" % [
			CARRY_LANE_LABELS[b], lane_count[b],
			100.0 * float(lane_count[b]) / float(total), CARRY_LOST_SECONDS,
			100.0 * float(lane_lost[b]) / float(lane_count[b]),
		])
	print("  grass between the ball and the nearest line")
	for b in edges:
		if edge_count[b] == 0:
			continue
		print("    %-20s %5d  %4.0f%%   struck at %4.1f m/s   out inside %.0f s %3.0f%%" % [
			CARRY_EDGE_LABELS[b], edge_count[b],
			100.0 * float(edge_count[b]) / float(total),
			edge_pace[b] / float(edge_count[b]), CARRY_OUT_SECONDS,
			100.0 * float(edge_out[b]) / float(edge_count[b]),
		])


## Which band `value` falls in. The last band is everything past the last edge,
## infinity included, so a carry with nobody in the lane lands there.
static func _band(value: float, bands: Array) -> int:
	for b in bands.size():
		if value < float(bands[b]):
			return b
	return bands.size()


## True if any of `ticks` -- which are in order -- falls inside `seconds` after
## `tick`.
static func _happened_within(ticks: PackedInt32Array, tick: int, seconds: float) -> bool:
	var window := int(seconds * float(SimConsts.TICK_HZ))
	for t in ticks:
		if t > tick:
			return t - tick <= window
	return false


static func _under_challenge(events: Array) -> void:
	var n := CHALLENGE_BANDS.size()
	var totals := PackedInt32Array()
	totals.resize(n)
	# Counted per band: carry, knock past the man, pass, clear, shot.
	var carry := PackedInt32Array()
	var burst := PackedInt32Array()
	var pass_out := PackedInt32Array()
	var cleared := PackedInt32Array()
	var shot := PackedInt32Array()
	for a in [carry, burst, pass_out, cleared, shot]:
		a.resize(n)
	# How far in front of himself he pushed it, summed over the carries in each
	# band. The percentages above say what he chose to do; this says how big the
	# touch was when he chose to carry, which is the difference between keeping
	# the ball under his sole with a man on him and knocking it into his shins.
	# Nothing else prints it against the pressure he was under -- the box block
	# splits it by where on the pitch he was, which is a different question.
	var ahead_sum := PackedFloat32Array()
	ahead_sum.resize(n)

	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH or not e.has("chal"):
			continue
		var kind: int = e["kind"]
		# Only the carrier's own choices. A tackle or a block is the defender's.
		if kind == SimTelemetry.Touch.TACKLE or kind == SimTelemetry.Touch.BLOCK:
			continue
		var band := n - 1
		for i in n:
			if float(e["chal"]) <= float(CHALLENGE_BANDS[i]):
				band = i
				break
		totals[band] += 1
		match kind:
			SimTelemetry.Touch.DRIBBLE:
				# The long knock is logged with the distance it was pushed, so
				# running out of a challenge can be told apart from carrying.
				if float(e.get("ahead", 0.0)) > SimTouch.DRIBBLE_AHEAD_MAX:
					burst[band] += 1
				else:
					carry[band] += 1
					ahead_sum[band] += float(e.get("ahead", 0.0))
			SimTelemetry.Touch.CLEARANCE:
				cleared[band] += 1
			SimTelemetry.Touch.SHOT:
				shot[band] += 1
			_:
				if SimTelemetry.is_pass_kind(kind):
					pass_out[band] += 1

	var any := 0
	for i in n:
		any += totals[i]
	if any == 0:
		return
	print("\nUnder challenge  (what the man on the ball did about it)")
	print("  %-12s %7s %8s %8s %8s %7s %7s %7s" % ["", "touches", "carry", "touch", "knock on", "pass", "clear", "shot"])
	for i in n:
		if totals[i] == 0:
			continue
		var t := float(totals[i])
		print("  %-12s %7d %7.0f%% %7.2f m %7.0f%% %6.0f%% %6.0f%% %6.0f%%" % [
			CHALLENGE_LABELS[i], totals[i],
			100.0 * float(carry[i]) / t,
			ahead_sum[i] / maxf(float(carry[i]), 1.0),
			100.0 * float(burst[i]) / t,
			100.0 * float(pass_out[i]) / t, 100.0 * float(cleared[i]) / t,
			100.0 * float(shot[i]) / t,
		])
	_carry_split(events)


## Splits the carries made with a man closing into the ones played away from
## him, across him, and straight into him.
##
## The carry column above cannot answer the question on its own, because two
## quite different acts land in it: turning away from a challenger, and taking
## another touch into him. From outside they are one event -- a dribble touch by
## a carrier under pressure -- so the split has to come from the direction he
## actually chose relative to the man, which is logged on the touch as `away`.
##
## This is the column that says whether "change direction to get away from him"
## is a thing the engine does or a thing it only has the vocabulary for.
static func _carry_split(events: Array) -> void:
	var away := 0
	var across := 0
	var into := 0
	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH or int(e["kind"]) != SimTelemetry.Touch.DRIBBLE:
			continue
		if float(e.get("chal", 0.0)) <= float(CHALLENGE_BANDS[0]):
			continue  # Nobody on him: there is no "away" to speak of.
		var a := float(e.get("away", 0.0))
		if a > 0.34:
			away += 1
		elif a < -0.34:
			into += 1
		else:
			across += 1
	var total := away + across + into
	if total == 0:
		return
	print("  touches made with a man closing: %.0f%% away from him, %.0f%% across him, %.0f%% into him (n=%d)" % [
		100.0 * float(away) / float(total), 100.0 * float(across) / float(total),
		100.0 * float(into) / float(total), total,
	])


## Where a first touch put the ball relative to where the man taking it wanted to
## go: into his stride, square across him, or left behind him.
const SET_AHEAD := 0.5
const SET_BEHIND := -0.5
const SET_LABELS := ["into his stride", "across him", "behind him"]
## How long after a first touch the question "did he still have it" is asked.
const SET_KEPT := 3.0


## Taking it down: what the first touch actually did with the ball.
##
## The block exists because a first touch is invisible from every count in the
## report. It is one event, by one player, in one place, whether he took the ball
## into his stride or knocked it three metres behind himself -- and the second of
## those is the start of most of the possessions that die for no reason a pass
## completion or a duel count can explain. The man turns round, runs a small
## circle after it, and is tackled by somebody who was five metres away when the
## pass was played, and the log records a clean interception.
##
## `behind him` is the row to read. The other two are shapes a footballer chooses
## on purpose -- letting it run across you is a real thing -- and a ball left
## behind the man receiving it is never one of them.
static func _taking_it_down(events: Array, ticks: PackedInt32Array, teams: PackedInt32Array) -> void:
	var n := SET_LABELS.size()
	var count := PackedInt32Array()
	var pace := PackedFloat32Array()
	var arrived := PackedFloat32Array()
	var grade := PackedFloat32Array()
	var kept := PackedInt32Array()
	for a in [count, kept]:
		a.resize(n)
	for f in [pace, arrived, grade]:
		f.resize(n)
	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH or int(e["kind"]) != SimTelemetry.Touch.FIRST_TOUCH:
			continue
		if not e.has("set"):
			continue
		var s := float(e["set"])
		var band := 1
		if s >= SET_AHEAD:
			band = 0
		elif s <= SET_BEHIND:
			band = 2
		count[band] += 1
		pace[band] += float(e.get("pace", 0.0))
		arrived[band] += float(e.get("in", 0.0))
		grade[band] += float(e.get("quality", 0.0))
		if _still_holding(ticks, teams, int(e["t"]), int(e["team"]), SET_KEPT):
			kept[band] += 1
	var total := 0
	for i in n:
		total += count[i]
	if total == 0:
		return
	print("\nTaking it down  (where the first touch left the ball, relative to where he meant to go)")
	print("  %-18s %8s %7s %9s %10s %8s %9s" % ["", "touches", "share", "arrived", "pace left", "quality", "kept 3 s"])
	for i in n:
		if count[i] == 0:
			continue
		var c := float(count[i])
		print("  %-18s %8d %6.0f%% %7.1f m/s %6.2f m/s %8.2f %8.0f%%" % [
			SET_LABELS[i], count[i], 100.0 * c / float(total),
			arrived[i] / c, pace[i] / c, grade[i] / c, 100.0 * float(kept[i]) / c,
		])


## Within this many seconds, a regain handed straight back is the same incident
## rather than two of them.
const CHURN_SECONDS := 2.5


## How often winning the ball is immediately undone.
##
## The symptom this measures is the one that makes a match tiring to watch: two
## players trading the ball in the same square metre, each turnover reversing
## the roles and setting up the next challenge, so a passage of play goes
## nowhere for ten seconds. Every count that exists already reports this as
## healthy activity -- it is duels, recoveries and tackles, all of which go *up*
## when the engine is at its worst. Only the interval between a regain and the
## next one going the other way can see it.
static func _churn(events: Array) -> void:
	var regains := 0
	var churned := 0
	var clean_regains := 0
	var clean_churned := 0
	var prev_team := -1
	var prev_tick := -100000
	var window := int(CHURN_SECONDS * float(SimConsts.TICK_HZ))
	for e in events:
		if e["ev"] != SimTelemetry.Ev.RECOVERY:
			continue
		var team: int = e["team"]
		var tick: int = e["t"]
		var clean := bool(e.get("clean", false))
		regains += 1
		if clean:
			clean_regains += 1
		if prev_team >= 0 and team != prev_team and tick - prev_tick <= window:
			churned += 1
			if clean:
				clean_churned += 1
		prev_team = team
		prev_tick = tick
	if regains == 0:
		return
	# Split, because the two halves are answerable by different things. A poked
	# ball is loose by design and whoever gathers it is a race, so churn there is
	# a fact about the scramble. A clean regain is a decision, and if that is
	# handed straight back it is the decision layer doing it.
	print("  won back and lost again inside %.1f s   %d of %d regains (%.0f%%)" % [
		CHURN_SECONDS, churned, regains, 100.0 * float(churned) / float(regains),
	])
	if clean_regains > 0:
		print("    of the ones taken cleanly          %d of %d (%.0f%%)" % [
			clean_churned, clean_regains, 100.0 * float(clean_churned) / float(clean_regains),
		])


## What the man who has just won the ball does with it.
##
## Pairs each clean regain with that player's next touch. Derived entirely from
## events already logged, so it costs nothing to keep: the recovery says who won
## it and when, and his next touch says what he decided.
##
## The question it answers is the second half of the complaint -- that winning
## the ball back only swapped the roles round. If this row looks like the
## challenged row of the table above, the winner is carrying the ball straight
## back into the man he took it from.
static func _after_regain(events: Array) -> void:
	var pending := {}
	var kinds := {}
	var total := 0
	var window := int(CHURN_SECONDS * float(SimConsts.TICK_HZ))
	for e in events:
		match e["ev"]:
			SimTelemetry.Ev.RECOVERY:
				if bool(e.get("clean", false)):
					pending[int(e["p"])] = int(e["t"])
			SimTelemetry.Ev.TOUCH:
				var p := int(e["p"])
				if not pending.has(p):
					continue
				if int(e["t"]) - int(pending[p]) > window:
					pending.erase(p)
					continue
				pending.erase(p)
				var kind: int = e["kind"]
				var label := "carry"
				if kind == SimTelemetry.Touch.DRIBBLE:
					label = "knock on" if float(e.get("ahead", 0.0)) > SimTouch.DRIBBLE_AHEAD_MAX else "carry"
				elif kind == SimTelemetry.Touch.CLEARANCE:
					label = "clear"
				elif kind == SimTelemetry.Touch.SHOT:
					label = "shot"
				elif SimTelemetry.is_pass_kind(kind):
					label = "pass"
				else:
					label = SimTelemetry.touch_name(kind)
				kinds[label] = int(kinds.get(label, 0)) + 1
				total += 1
	if total == 0:
		return
	var order := kinds.keys()
	order.sort_custom(func(a, b): return int(kinds[a]) > int(kinds[b]))
	var parts := PackedStringArray()
	for k in order:
		parts.append("%s %.0f%%" % [k, 100.0 * float(kinds[k]) / float(total)])
	print("  first touch after winning it clean   %s  (n=%d)" % [" ".join(parts), total])


## Where the nearest defender stands relative to a running carrier.
##
## The complaint this answers is a visual one -- a defender who spends the whole
## carry in the carrier's slipstream, a metre off his back, never getting round
## him. No count in the event log can see it: the trailing defender is not
## touching the ball, so he appears in no touch, duel or recovery. It needs the
## positional trace and it needs the carrier's heading, so it lives here.
##
## Read the sector split. A defence that gets round the man puts most of its
## time alongside or goal-side; a defence that tailgates puts it behind.
static func _chasing(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var behind := 0
	var alongside := 0
	var ahead := 0
	var behind_dist := 0.0
	# A trail is an unbroken run of samples with the same defender behind the
	# same carrier: how long he spends stuck there before something changes.
	var trail_key := Vector2i(-1, -1)
	var trail_len := 0
	var trails := 0
	var trail_samples := 0
	var trail_longest := 0
	var dt := float(SimConsts.TRACE_TICKS) / float(SimConsts.TICK_HZ)

	for i in range(1, trace.size()):
		var sample := trace[i]
		var prev := trace[i - 1]
		if sample.size() != ctx.players.size() + 1 or prev.size() != sample.size():
			continue
		var ball := sample[0]
		if ball.y > 1.0:
			continue
		# The carrier is whoever is nearest the ball and near enough to own it.
		var carrier := -1
		var best := 2.5
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var d := SimConsts.horizontal_length(sample[pid + 1] - ball)
			if d < best:
				best = d
				carrier = pid
		if carrier < 0:
			continue
		var at := sample[carrier + 1]
		var step := SimConsts.horizontal(at - prev[carrier + 1])
		if step.length() < CARRIER_MIN_SPEED * dt:
			continue
		var heading := step.normalized()

		var chaser := -1
		var chaser_d := CHASE_NEAR
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.team == ctx.players[carrier].team or p.is_keeper or not p.on_pitch:
				continue
			var d := SimConsts.horizontal_length(sample[pid + 1] - at)
			if d < chaser_d:
				chaser_d = d
				chaser = pid
		if chaser < 0:
			trail_key = Vector2i(-1, -1)
			trail_len = 0
			continue

		var to := SimConsts.horizontal(sample[chaser + 1] - at)
		var frontness: float = 0.5 * (clampf(to.normalized().dot(heading), -1.0, 1.0) + 1.0)
		var key := Vector2i(carrier, chaser)
		if frontness < BEHIND_MAX:
			behind += 1
			behind_dist += chaser_d
			if key == trail_key:
				trail_len += 1
			else:
				trail_key = key
				trail_len = 1
			if trail_len == 2:
				trails += 1
			if trail_len >= 2:
				trail_samples += 1
				trail_longest = maxi(trail_longest, trail_len)
			continue
		trail_key = Vector2i(-1, -1)
		trail_len = 0
		if frontness > AHEAD_MIN:
			ahead += 1
		else:
			alongside += 1

	var total := behind + alongside + ahead
	if total == 0:
		return
	print("\nChasing the carrier  (nearest defender within %.0f m of a carrier moving above %.0f m/s)" % [CHASE_NEAR, CARRIER_MIN_SPEED])
	print("  tracked            %.0f s of play" % (float(total) * dt))
	print("  behind him         %5.0f%%   at %.1f m mean" % [100.0 * float(behind) / float(total), behind_dist / maxf(float(behind), 1.0)])
	print("  alongside          %5.0f%%" % (100.0 * float(alongside) / float(total)))
	print("  goal-side / ahead  %5.0f%%" % (100.0 * float(ahead) / float(total)))
	if trails > 0:
		print("  slipstream trails  %d, mean %.1f s, longest %.1f s" % [
			trails, float(trail_samples) * dt / float(trails), float(trail_longest) * dt,
		])


## How hard a teammate has to be moving before he counts as doing something
## about being available rather than drifting along with the shape.
##
## Set well above a shape-holder's jog on purpose. At 1.5 m/s the measurement
## could not tell a man coming to meet the ball from a man being slid up the
## pitch by the formation, and it read the same with the whole receiving layer
## switched off -- which is a broken instrument, not a null result.
const OFFER_MOVING := 2.5
## Radius inside which a teammate is a short option for the man on the ball.
const OFFER_SHORT := 15.0
## And the range over which anyone is an option at all.
const OFFER_RANGE := 35.0


## What the man on the ball had to look at.
##
## Two halves, and they answer different questions. The first is the decision
## layer's own account of itself: how many times each way of offering was chosen
## and how often the ball actually arrived. The second is taken off the
## positional trace and owes the sim nothing -- with the ball at a man's feet,
## how many teammates were inside a short pass, how many were coming to meet it,
## and how many were beyond the last defender going the other way.
##
## The second is the one to trust when the two disagree. An intent that is taken
## and then never resolves into a body arriving somewhere useful is a run that
## exists only in the counter.
##
## Read the received column per kind, not across them. Showing for it and running
## in behind are bids for the ball and their rates mean what they say; drifting
## into a pocket is positioning rather than a bid, so a low rate there is the
## expected reading and not a fault. What would be a fault is a drift whose
## up-pitch column sits at or below zero — a layer meant to make a team available
## quietly walking it backwards.
static func _offering(ctx: SimContext) -> void:
	var total: int = 0
	for i in SimOffBall.made.size():
		total += SimOffBall.made[i]
	if total > 0:
		print("\nOffering for the ball  (how players made themselves available)")
		print("  %-10s %8s %10s %11s %10s %10s" % ["", "taken", "received", "cut short", "mean run", "up-pitch"])
		for kind in range(1, SimOffBall.made.size()):
			var n: int = SimOffBall.made[kind]
			if n == 0:
				continue
			print("  %-10s %8d %9.0f%% %10.0f%% %9.1f m %+9.1f m" % [
				SimOffBall.KIND_NAMES[kind], n,
				100.0 * float(SimOffBall.received[kind]) / float(n),
				100.0 * float(SimOffBall.cut_short[kind]) / float(n),
				SimOffBall.travel[kind] / float(n),
				SimOffBall.forward[kind] / float(n),
			])

	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var dt := float(SimConsts.TRACE_TICKS) / float(SimConsts.TICK_HZ)
	# Ends swap at half time, so an orientation read at full time is wrong for
	# the whole of the first half.
	var swap_tick := 1 << 30
	for e in ctx.telemetry.events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", -1)) == SimConsts.Period.SECOND_HALF:
			swap_tick = int(e["t"])
			break
	var samples := 0
	var short_options := 0
	var coming := 0
	var behind := 0
	var wide_open := 0
	for i in range(1, trace.size()):
		var sample := trace[i]
		var prev := trace[i - 1]
		if sample.size() != ctx.players.size() + 1 or prev.size() != sample.size():
			continue
		var ball := sample[0]
		if ball.y > 1.0:
			continue
		var carrier := -1
		var best := OWN_BALL
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var d := SimConsts.horizontal_length(sample[pid + 1] - ball)
			if d < best:
				best = d
				carrier = pid
		if carrier < 0:
			continue
		var team := ctx.players[carrier].team
		# The offside line as it stands in this sample: the second-deepest
		# opponent. Taken from the trace rather than the sim so that the whole
		# measurement is one thing, and orientation from the ends the teams are
		# actually attacking at this point in the match.
		var dir := ctx.pitch.attack_dir(team)
		if i * SimConsts.TRACE_TICKS < swap_tick:
			dir = -dir
		var first := -INF
		var second := -INF
		for pid in ctx.players.size():
			var o := ctx.players[pid]
			if o.team == team or not o.on_pitch:
				continue
			var depth: float = sample[pid + 1].x * dir
			if depth > first:
				second = first
				first = depth
			elif depth > second:
				second = depth
		samples += 1
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.team != team or pid == carrier or p.is_keeper or not p.on_pitch:
				continue
			var at := sample[pid + 1]
			var to_ball := SimConsts.horizontal_length(at - ball)
			if to_ball > OFFER_RANGE:
				continue
			if to_ball <= OFFER_SHORT:
				short_options += 1
			var step := SimConsts.horizontal(at - prev[pid + 1])
			if step.length() < OFFER_MOVING * dt:
				continue
			var was := SimConsts.horizontal_length(prev[pid + 1] - ball)
			var closing := (was - to_ball) / dt
			if at.x * dir > second and step.x * dir > 0.0:
				behind += 1
			elif closing > OFFER_MOVING:
				coming += 1
			else:
				wide_open += 1
	if samples == 0:
		return
	var n := float(samples)
	print("  with the ball at a man's feet, over %.0f s, he had on average" % (n * dt))
	print("    %.1f teammates inside %.0f m" % [float(short_options) / n, OFFER_SHORT])
	# Not a subset of the line above, and it used to say "of them", which it is
	# not: the short count is within OFFER_SHORT and the moving counts are within
	# the whole of OFFER_RANGE, so the three below routinely sum to more than the
	# one above. Anyone reading them as a breakdown of the short options is
	# reading a number that does not exist.
	print("    separately, within %.0f m and moving at %.1f m/s or better:" % [
		OFFER_RANGE, OFFER_MOVING])
	print("    %.1f coming to meet it, %.1f going off into space, %.2f beyond the last defender" % [
		float(coming) / n, float(wide_open) / n, float(behind) / n,
	])


## Whether the man on the ball actually has a safe pass, which is not the same
## question as whether he has a teammate near him.
##
## The block above counts bodies inside fifteen metres and finds about 1.8 of
## them, against three or four in real football. But a body is not an option: a
## teammate with a defender standing in the lane, or with a marker at his
## shoulder, is a pass that gets cut out or a pass that loses the ball on the
## first touch, and the engine is measurably full of both -- 18% of passes are
## threaded within a metre and a half of an opponent and complete at 39%.
##
## So this asks the question the carrier is actually facing. Of the teammates in
## range, how many could be found *safely*, and how often is the answer none. If
## a safe ball is nearly always available, then the engine is choosing the risky
## one over it and the problem is what a pass is worth. If it is usually not
## available, then the problem is that nobody offered, and a floor on
## availability is the fix. Those want opposite work, and nothing measured so
## far separates them.
##
## Read off the trace rather than the touch log, deliberately: this has to
## include the moments the carrier *did not* pass, which leave no event at all.
const SAFE_MIN := 6.0
const SAFE_MAX := 18.0
## An opponent this close to the line of the pass is on it.
const SAFE_LANE := 2.0
## And this close to the receiver is on him.
const SAFE_MARK := 3.0


static func _safe_options(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var samples := 0
	var none_at_all := 0
	var one := 0
	var forward_safe := 0
	var in_range := 0
	var blocked := 0
	var marked := 0
	var safe_total := 0

	for i in range(1, trace.size()):
		var sample := trace[i]
		if sample.size() != ctx.players.size() + 1:
			continue
		var ball := sample[0]
		if ball.y > 1.0:
			continue
		var carrier := -1
		var best := OWN_BALL
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var d := SimConsts.horizontal_length(sample[pid + 1] - ball)
			if d < best:
				best = d
				carrier = pid
		if carrier < 0:
			continue
		var team := ctx.players[carrier].team
		var dir := ctx.pitch.attack_dir(team)
		if i * SimConsts.TRACE_TICKS < _trace_swap(ctx):
			dir = -dir

		samples += 1
		var safe := 0
		var safe_fwd := 0
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.team != team or pid == carrier or p.is_keeper or not p.on_pitch:
				continue
			var at := sample[pid + 1]
			var d := SimConsts.horizontal_length(at - ball)
			if d < SAFE_MIN or d > SAFE_MAX:
				continue
			in_range += 1
			var lane_clear := true
			var unmarked := true
			for oid in ctx.players.size():
				var o := ctx.players[oid]
				if o.team == team or not o.on_pitch:
					continue
				var op := sample[oid + 1]
				if _point_to_segment(op, ball, at) < SAFE_LANE:
					lane_clear = false
				if SimConsts.horizontal_length(op - at) < SAFE_MARK:
					unmarked = false
			if not lane_clear:
				blocked += 1
				continue
			if not unmarked:
				marked += 1
				continue
			safe += 1
			if (at.x - ball.x) * dir > 1.0:
				safe_fwd += 1
		safe_total += safe
		if safe == 0:
			none_at_all += 1
		elif safe == 1:
			one += 1
		if safe_fwd > 0:
			forward_safe += 1

	if samples == 0:
		return
	var n := float(samples)
	print("\nDid he have a safe pass?  (teammates %.0f-%.0f m away, lane and man both clear)"
		% [SAFE_MIN, SAFE_MAX])
	print("  with the ball at a man's feet, on average")
	print("    %.1f teammates in range, of which %.1f safe" % [
		float(in_range) / n, float(safe_total) / n])
	print("    %.1f had an opponent in the passing lane, %.1f had a marker on them" % [
		float(blocked) / n, float(marked) / n])
	print("  no safe option at all  %3.0f%%   exactly one  %3.0f%%   a safe *forward* one  %3.0f%%" % [
		100.0 * float(none_at_all) / n, 100.0 * float(one) / n,
		100.0 * float(forward_safe) / n,
	])


## Distance from a point to a line segment, flattened to the ground plane.
static func _point_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := SimConsts.horizontal(b - a)
	var ap := SimConsts.horizontal(p - a)
	var len2 := ab.length_squared()
	if len2 < 1e-6:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return (ap - ab * t).length()


## Trace sample index at which the ends swap, rounded up: the ends change
## partway through a tick and the sample taken at the start of that tick still
## has everybody at the end they came from.
static func _trace_swap(ctx: SimContext) -> int:
	for e in ctx.telemetry.events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", -1)) == SimConsts.Period.SECOND_HALF:
			return int(e["t"])
	return 1 << 30


## Ground given up by a man with the ball at his feet.
##
## A carrier is allowed to drop back; dropping back and never stopping is the
## complaint, and it is invisible to everything else here. It leaves no event —
## every touch in it is an ordinary carry — and the per-90 counts are unmoved,
## because retreating with the ball is retaining the ball. The first version of
## this measurement was taken off the touch log and got the sign wrong on every
## first-half touch, which is why it is worth having it written down once: teams
## swap ends at half time, so the orientation has to come from the tick.
##
## A spell is one man owning the ball across consecutive trace samples. `drop` is
## the ground between where he took it and the deepest point he took it to,
## measured toward his own goal, so a carry that goes back and then comes forward
## again is still counted for the retreat.
const OWN_BALL := 2.5
const RETREAT_REPORT := 8.0


static func _giving_up_ground(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var dt := float(SimConsts.TRACE_TICKS) / float(SimConsts.TICK_HZ)
	# Ends swap at half time, so an orientation read at full time is wrong for
	# the whole of the first half.
	var swap_tick := 1 << 30
	for e in ctx.telemetry.events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", -1)) == SimConsts.Period.SECOND_HALF:
			swap_tick = int(e["t"])
			break

	var spells := 0
	var retreats := 0
	var retreat_samples := 0
	var deepest := 0.0
	var deepest_secs := 0.0
	var owned := 0

	var who := -1
	var start := 0.0
	var low := 0.0
	var since := 0
	for i in trace.size():
		var sample := trace[i]
		if sample.size() != ctx.players.size() + 1:
			continue
		var ball := sample[0]
		var carrier := -1
		var best := OWN_BALL
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var d := SimConsts.horizontal_length(sample[pid + 1] - ball)
			if d < best:
				best = d
				carrier = pid
		var forward := 0.0
		if carrier >= 0:
			forward = ball.x * ctx.pitch.attack_dir(ctx.players[carrier].team) \
				* (1.0 if i * SimConsts.TRACE_TICKS >= swap_tick else -1.0)
		if carrier != who:
			# The spell just ended: judge it.
			if who >= 0:
				spells += 1
				var drop := low - start
				if drop <= -RETREAT_REPORT:
					retreats += 1
					retreat_samples += since
					if drop < deepest:
						deepest = drop
						deepest_secs = float(since) * dt
			who = carrier
			start = forward
			low = forward
			since = 0
			continue
		if carrier < 0:
			continue
		owned += 1
		since += 1
		low = minf(low, forward)

	if spells == 0:
		return
	print("\nGiving up ground  (one man within %.1f m of the ball, toward his own goal)" % OWN_BALL)
	print("  possession spells  %d, %.0f s with the ball at someone's feet" % [spells, float(owned) * dt])
	print("  spells losing %.0f m or more   %d, %.0f s of play" % [
		RETREAT_REPORT, retreats, float(retreat_samples) * dt])
	if retreats > 0:
		print("  deepest            %.1f m, over %.1f s" % [deepest, deepest_secs])


## How much of a match is spent at each pace.
##
## The question this answers is "are they ever actually running", and nothing
## else printed can. Distance covered is a total, and a total cannot tell a
## squad that trots everywhere apart from one that walks and then sprints —
## which is the difference between a match that looks like football and one that
## looks like a slow drift. Watching cannot answer it either, because the eye
## has no scale for it: a figure at match framing is seventy pixels, and whether
## it is moving at two metres a second or five is exactly the judgement the
## animation is supposed to make for the viewer.
##
## Bands are the same ones the sim publishes as animation states
## (`SimPlayer._update_anim`), so this is a readout of what the view is being
## asked to draw. Speeds come off the 5 Hz trace, which averages over a fifth of
## a second: sustained running is measured accurately, the very top of a sprint
## reads a little low.
static func _locomotion(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var dt := float(SimConsts.TRACE_TICKS) / float(SimConsts.TICK_HZ)
	var samples := 0
	var speed_sum := 0.0
	var fastest := 0.0
	# Standing, walking, jogging, running, sprinting.
	var bands := PackedInt32Array()
	bands.resize(5)

	for i in range(1, trace.size()):
		var sample := trace[i]
		var prev := trace[i - 1]
		if sample.size() != ctx.players.size() + 1 or prev.size() != sample.size():
			continue
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var v := SimConsts.horizontal_length(sample[pid + 1] - prev[pid + 1]) / dt
			# A restart puts players on their spots in one tick (`SimSetPiece`),
			# which off a positional trace is indistinguishable from a sprint at
			# three hundred metres a second. Nobody can run past the fastest
			# player alive, so anything that does is a teleport, not a stride.
			if v > SimConsts.SPEED_MAX * 1.2:
				continue
			var nominal := p.nominal_max_speed()
			samples += 1
			speed_sum += v
			fastest = maxf(fastest, v)
			if v < 0.4:
				bands[0] += 1
			elif v < nominal * 0.25:
				bands[1] += 1
			elif v < nominal * 0.45:
				bands[2] += 1
			elif v < nominal * 0.8:
				bands[3] += 1
			else:
				bands[4] += 1

	if samples == 0:
		return
	var labels := ["standing", "walking", "jogging", "running", "sprinting"]
	print("\nPace  (outfield players, off the 5 Hz trace)")
	print("  mean speed         %.2f m/s   fastest sustained %.1f m/s" % [
		speed_sum / float(samples), fastest,
	])
	for b in labels.size():
		print("  %-18s %5.1f%%" % [labels[b], 100.0 * float(bands[b]) / float(samples)])


## Sector boundaries on the angle between the passer's body and the line the ball
## is played along, in degrees.
const BODY_BUCKETS := [45.0, 90.0, 135.0, 180.1]
const BODY_LABELS := ["ahead", "opening up", "over the shoulder", "straight back"]


## Passing by where the ball goes relative to the way the passer is pointing.
##
## Two different things are printed here on purpose, and the mechanic is only
## working if both move. `share` is a fact about *choices*: a player who has to
## turn to reach an option should take it less often, and if the shares are flat
## the decision layer is not seeing the cost its own passes are being charged.
## `completed` is a fact about *execution*: the ball played over the shoulder
## should arrive less often than the one played into the passer's own eyeline.
##
## `deftness` is the third claim and the one nothing else can check -- the mean
## technique-and-agility of the players who attempted that row. It should climb
## as the rows get harder, because the whole design intent is that hitting one
## behind you is something only the good players do well. Flat deftness across
## the rows means the engine is letting everyone try it.
static func _by_body_angle(ctx: SimContext, events: Array) -> void:
	var n := BODY_BUCKETS.size()
	var tried := PackedInt32Array()
	var resolved := PackedInt32Array()
	var ok := PackedInt32Array()
	var deft := PackedFloat32Array()
	tried.resize(n)
	resolved.resize(n)
	ok.resize(n)
	deft.resize(n)

	var pending := {}
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PASS_ATTEMPT:
			if not e.has("body"):
				continue
			var passer := int(e["p"])
			var degrees: float = rad_to_deg(acos(clampf(float(e["body"]), -1.0, 1.0)))
			var bucket := 0
			while bucket < n - 1 and degrees >= float(BODY_BUCKETS[bucket]):
				bucket += 1
			tried[bucket] += 1
			if passer < ctx.players.size():
				var a := ctx.players[passer].attrs
				deft[bucket] += a.technique * 0.6 + a.agility * 0.4
			pending[passer] = bucket
		elif e["ev"] == SimTelemetry.Ev.PASS_OUTCOME:
			var passer := int(e["p"])
			if not pending.has(passer):
				continue
			var bucket: int = pending[passer]
			pending.erase(passer)
			resolved[bucket] += 1
			if bool(e.get("ok", false)):
				ok[bucket] += 1

	var total := 0
	for i in n:
		total += tried[i]
	if total == 0:
		return
	print("\nPassing by body angle  (where the ball went, relative to the way the passer faced)")
	print("  sector                 attempts   share   resolved   completed   deftness")
	var low := 0.0
	for i in n:
		if tried[i] == 0:
			low = float(BODY_BUCKETS[i])
			continue
		var pct := "     -" if resolved[i] == 0 else "%5.0f%%" % (100.0 * float(ok[i]) / float(resolved[i]))
		print("  %-18s %3.0f-%3.0f  %6d  %5.1f%%   %8d      %s      %.2f" % [
			BODY_LABELS[i], low, minf(float(BODY_BUCKETS[i]), 180.0), tried[i],
			100.0 * float(tried[i]) / float(total), resolved[i], pct,
			deft[i] / float(tried[i]),
		])
		low = float(BODY_BUCKETS[i])


## How close to the target point a body has to be to be contesting it. Six metres
## is a couple of strides: near enough that the ball arriving there is his
## business, far enough that it is not just the intended receiver.
const CROWD_RADIUS := 6.0
## And how close a body has to be for the pass to have been played *at* him.
const AT_A_MAN := 2.0
## How close an opponent has to stand to the line of a pass to be standing in it.
const ON_THE_LINE := 1.5

const CROWD_LABELS := ["nobody there", "ours", "even", "theirs", "outnumbered"]


## Who was standing where the pass was going to land.
##
## No count of passes can answer this and neither can a completion rate: a ball
## rolled to a man with three opponents around him and the same ball to the same
## man in space are the same length, from the same place, to the same teammate,
## and the log records them identically. What tells them apart is the company the
## target point was keeping, and the trace is where that lives — the sim's own
## account of pitch control is the thing under test here, so this owes it
## nothing and counts bodies instead.
##
## The rows are the balance of bodies within `CROWD_RADIUS` of the point the ball
## was aimed at, at the moment it was struck, the passer not counted. "Theirs"
## and "outnumbered" together are the owner's complaint made into a number: a
## pass into an area the opposition owns. They will never be zero and should not
## be — a cross into a packed box is a pass into an area the opposition owns, and
## so is every ball that has to be threaded — but they should be the minority,
## and the completion rate beside them should be visibly worse than the rest.
static func _pass_destination(ctx: SimContext, events: Array) -> void:
	var trace := ctx.telemetry.trace
	if trace.is_empty():
		return
	var n := CROWD_LABELS.size()
	var tried := PackedInt32Array()
	var resolved := PackedInt32Array()
	var ok := PackedInt32Array()
	var length := PackedFloat32Array()
	tried.resize(n)
	resolved.resize(n)
	ok.resize(n)
	length.resize(n)
	var at_a_man := 0
	var nearest_total := 0.0
	var counted := 0
	## The other reading of "played at an opponent": not where it was going, but
	## what it had to get past. An opponent standing on the line of the pass is
	## invisible to the crowd rows above — he is nowhere near the target — and he
	## is the one who cuts it out.
	var through_a_body := 0
	var through_resolved := 0
	var through_ok := 0

	var pending := {}
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PASS_ATTEMPT:
			if not e.has("to"):
				continue
			var index: int = int(e["t"]) / SimConsts.TRACE_TICKS
			if index < 0 or index >= trace.size():
				continue
			var sample: PackedVector3Array = trace[index]
			if sample.size() != ctx.players.size() + 1:
				continue
			var to: Vector3 = e["to"]
			var passer := int(e["p"])
			var team := int(e["team"])
			var mates := 0
			var opponents := 0
			var nearest_opponent := INF
			var blocked := false
			var from: Vector3 = sample[passer + 1] if passer < ctx.players.size() else sample[0]
			var line := SimConsts.horizontal(to - from)
			var span: float = line.length()
			var along_dir := line / span if span > 0.1 else Vector3.ZERO
			for pid in ctx.players.size():
				if pid == passer or not ctx.players[pid].on_pitch:
					continue
				var d := SimConsts.horizontal_length(sample[pid + 1] - to)
				if ctx.players[pid].team == team:
					if d <= CROWD_RADIUS:
						mates += 1
				else:
					nearest_opponent = minf(nearest_opponent, d)
					if d <= CROWD_RADIUS:
						opponents += 1
					if along_dir != Vector3.ZERO:
						var rel := SimConsts.horizontal(sample[pid + 1] - from)
						var along: float = rel.dot(along_dir)
						# The far end of the line is the crowd rows' business, and
						# the near end is the man the passer is turning away from.
						if along > 1.5 and along < span - 3.0:
							var side := (rel - along_dir * along).length()
							if side <= ON_THE_LINE:
								blocked = true
			if blocked:
				through_a_body += 1
			var bucket := 0
			if opponents == 0 and mates == 0:
				bucket = 0
			elif opponents == 0 or mates > opponents:
				bucket = 1
			elif mates == opponents:
				bucket = 2
			elif opponents - mates == 1:
				bucket = 3
			else:
				bucket = 4
			tried[bucket] += 1
			length[bucket] += float(e.get("dist", 0.0))
			if not is_inf(nearest_opponent):
				nearest_total += nearest_opponent
				counted += 1
				if nearest_opponent <= AT_A_MAN:
					at_a_man += 1
			pending[passer] = [bucket, blocked]
		elif e["ev"] == SimTelemetry.Ev.PASS_OUTCOME:
			var passer := int(e["p"])
			if not pending.has(passer):
				continue
			var held: Array = pending[passer]
			var bucket: int = held[0]
			pending.erase(passer)
			resolved[bucket] += 1
			var made := bool(e.get("ok", false))
			if made:
				ok[bucket] += 1
			if bool(held[1]):
				through_resolved += 1
				if made:
					through_ok += 1

	var total := 0
	for i in n:
		total += tried[i]
	if total == 0:
		return
	print("\nWhere the pass was aimed  (bodies within %.0f m of the target when it was struck)" % CROWD_RADIUS)
	print("  around the target      attempts   share   resolved   completed   mean len")
	for i in n:
		if tried[i] == 0:
			continue
		var pct := "     -" if resolved[i] == 0 else "%5.0f%%" % (100.0 * float(ok[i]) / float(resolved[i]))
		print("  %-20s %7d  %5.1f%%   %8d      %s     %5.1f m" % [
			CROWD_LABELS[i], tried[i], 100.0 * float(tried[i]) / float(total),
			resolved[i], pct, length[i] / float(tried[i]),
		])
	if counted > 0:
		print("  nearest opponent to the target   %.1f m mean;  %d of %d (%.0f%%) played within %.0f m of one" % [
			nearest_total / float(counted), at_a_man, total,
			100.0 * float(at_a_man) / float(total), AT_A_MAN,
		])
	var through_pct := "-" if through_resolved == 0 else "%.0f%% completed" % (100.0 * float(through_ok) / float(through_resolved))
	print("  played through a body   %d of %d (%.0f%%) had an opponent within %.1f m of the line;  %s" % [
		through_a_body, total, 100.0 * float(through_a_body) / float(total), ON_THE_LINE, through_pct,
	])


## How near his goal the ball has to be before a keeper's position is about
## anything. Beyond this he is sweeping behind a high line and his depth says
## nothing about how he defends his goal.
const KEEPER_THREAT := 35.0
## And how far off his line he has to be, with the ball that close, for it to be
## a decision rather than a station. The resting arc tops out around sixteen
## metres with play at the other end but is inside four when the ball is in the
## box, so ten metres under threat is a keeper who has come for something.
const OFF_LINE := 10.0


## What the goalkeepers did.
##
## The event log has saves and catches in it, and they are not the question. A
## keeper is judged on where he stands when nothing is happening to him, and on
## whether the times he leaves his line are the times he should have -- neither of
## which produces an event. So this is off the trace.
##
## Split by whether there is anything to defend, because one number over the whole
## match answers nothing: a keeper sweeping fifteen metres behind a high line with
## the ball at the other end and a keeper fifteen metres out with a striker
## bearing down on him are the same figure and opposite behaviours. `play away` is
## the sweeping and should be the larger of the two. `under threat` is the one to
## read after a change to `SimKeeper._one_on_one`, and `advances` counts the
## spells he spent past `OFF_LINE` with the ball inside `KEEPER_THREAT` -- a
## handful a match is a keeper reading danger, twenty is a keeper who thinks every
## attack is a breakaway.
static func _goalkeeping(ctx: SimContext, events: Array) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var flip := _first_half_flip(events)
	# The trace has no periods in it, so find the sample the ends changed at.
	var swap_at := trace.size() + 1
	if flip < 0.0:
		for e in events:
			if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
				# The first sample at or after the swap. Rounded up, not down: the
				# ends change partway through a tick and the sample taken at the
				# start of it still has everyone at the end they came from, which
				# reads as a keeper ninety metres from his own goal.
				swap_at = (int(e["t"]) + SimConsts.TRACE_TICKS - 1) / SimConsts.TRACE_TICKS
				break
	var dt := float(SimConsts.TRACE_TICKS) / float(SimConsts.TICK_HZ)

	print("\nGoalkeeping  (off the trace; 'threat' is the ball inside %.0f m of his goal)" % KEEPER_THREAT)
	print("  keeper       play away   under threat   furthest   advances past %.0f m   mean spell" % OFF_LINE)
	for team in 2:
		var keeper := -1
		for pid in ctx.players.size():
			if ctx.players[pid].team == team and ctx.players[pid].is_keeper:
				keeper = pid
				break
		if keeper < 0:
			continue
		var away_total := 0.0
		var away_n := 0
		var near_total := 0.0
		var near_n := 0
		var furthest := 0.0
		var advances := 0
		var out_samples := 0
		var spell := 0
		for i in trace.size():
			var sample: PackedVector3Array = trace[i]
			if sample.size() != ctx.players.size() + 1:
				continue
			var dir := ctx.pitch.attack_dir(team) * (1.0 if i >= swap_at else flip)
			# Distances from his own goal line, which is behind him.
			var off: float = sample[keeper + 1].x * dir + ctx.pitch.half_length
			var ball: float = sample[0].x * dir + ctx.pitch.half_length
			if ball > KEEPER_THREAT:
				away_total += off
				away_n += 1
				if spell > 0:
					advances += 1
				spell = 0
				continue
			near_total += off
			near_n += 1
			furthest = maxf(furthest, off)
			if off > OFF_LINE:
				out_samples += 1
				spell += 1
			else:
				if spell > 0:
					advances += 1
				spell = 0
		if spell > 0:
			advances += 1
		if away_n + near_n == 0:
			continue
		var away := "     -" if away_n == 0 else "%4.1f m" % (away_total / float(away_n))
		var near := "     -" if near_n == 0 else "%4.1f m" % (near_total / float(near_n))
		print("  %-12s %8s %13s %8.1f m %14d %13.1f s" % [
			ctx.teams[team].short_name, away, near, furthest, advances,
			float(out_samples) * dt / maxf(float(advances), 1.0),
		])

	var saves := 0
	var caught := 0
	for e in events:
		if e["ev"] != SimTelemetry.Ev.SAVE:
			continue
		saves += 1
		if bool(e.get("caught", false)):
			caught += 1
	print("  saves %d, of which caught %d" % [saves, caught])


const SET_PIECE_NAMES := ["kickoff", "throw-in", "goal kick", "corner", "free kick", "indirect FK", "penalty"]


## What a restart looks like by the time it is taken.
##
## Two things nothing else can see. `waited` is how long the ball sat there,
## which is the difference between a restart and a tap: a goal kick struck six
## tenths of a second after the whistle gives the side taking it no time to do
## anything, so whatever the routine asked for never happened. `own half` is
## where the kicking side actually stood when the ball was struck, as the mean
## distance of its outfielders from the goal they are defending, with the
## deepest and the highest of them beside it -- a side pushed out for a goal kick
## reads as a mean around the halfway line and a deepest man near his own box,
## and a side that never moved reads as both numbers pinned to the goal line.
static func _restarts(ctx: SimContext, events: Array) -> void:
	var n := SET_PIECE_NAMES.size()
	var count := PackedInt32Array()
	var waited := PackedFloat32Array()
	var mean_depth := PackedFloat32Array()
	var deepest := PackedFloat32Array()
	var highest := PackedFloat32Array()
	var measured := PackedInt32Array()
	count.resize(n)
	waited.resize(n)
	mean_depth.resize(n)
	deepest.resize(n)
	highest.resize(n)
	measured.resize(n)

	var trace := ctx.telemetry.trace
	var flip := _first_half_flip(events)
	var pending_kind := -1
	var pending_team := -1
	var pending_tick := 0
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
			flip = 1.0
		if e["ev"] == SimTelemetry.Ev.SET_PIECE:
			pending_kind = int(e["kind"])
			pending_team = int(e["team"])
			pending_tick = int(e["t"])
			if pending_kind >= 0 and pending_kind < n:
				count[pending_kind] += 1
			continue
		if pending_kind < 0 or e["ev"] != SimTelemetry.Ev.TOUCH or int(e["t"]) <= pending_tick:
			continue
		# The first touch after the whistle is the restart being taken.
		var taken := int(e["t"])
		if pending_kind >= 0 and pending_kind < n:
			waited[pending_kind] += float(taken - pending_tick) / float(SimConsts.TICK_HZ)
			var index := taken / SimConsts.TRACE_TICKS
			if index >= 0 and index < trace.size():
				var sample: PackedVector3Array = trace[index]
				if sample.size() == ctx.players.size() + 1:
					var dir := ctx.pitch.attack_dir(pending_team) * flip
					var total := 0.0
					var bodies := 0
					var low := INF
					var high := -INF
					for pid in ctx.players.size():
						var p := ctx.players[pid]
						if p.team != pending_team or p.is_keeper or not p.on_pitch:
							continue
						var from_goal := sample[pid + 1].x * dir + ctx.pitch.half_length
						total += from_goal
						bodies += 1
						low = minf(low, from_goal)
						high = maxf(high, from_goal)
					if bodies > 0:
						mean_depth[pending_kind] += total / float(bodies)
						deepest[pending_kind] += low
						highest[pending_kind] += high
						measured[pending_kind] += 1
		pending_kind = -1

	var any := false
	for i in n:
		if count[i] > 0:
			any = true
	if not any:
		return
	print("\nRestarts  (distances from the kicking side's own goal line)")
	print("  kind             count   waited   own outfield: deepest    mean   highest")
	for i in n:
		if count[i] == 0:
			continue
		var shape := "         -       -         -"
		if measured[i] > 0:
			var m := float(measured[i])
			shape = "%10.0f m %5.0f m %7.0f m" % [
				deepest[i] / m, mean_depth[i] / m, highest[i] / m,
			]
		print("  %-16s %5d  %5.1f s %s" % [
			SET_PIECE_NAMES[i], count[i], waited[i] / float(maxi(count[i], 1)), shape,
		])


## Which way a team was attacking when an event was logged, as a multiplier on
## `SimPitch.attack_dir`.
##
## Teams change ends at half time and the pitch only knows where they are
## pointing *now*, so anything that reads a position out of the event log after
## full time has the first half backwards. It is not a small error: measured
## against the wrong goal, a tap-in comes out at ninety metres, which put half
## the shots in this report into the "hopeful" band and made the instrument
## useless in exactly the direction it was built to look.
##
## Returns the multiplier that applies to first-half events; second-half events
## always take 1.0. A match that never reached half time never swapped.
## Whether the passing is any good, which is four questions and not one.
##
## Completion cannot answer it and never could. A side that plays every ball
## backwards to its own centre halves completes 95% of them and has done
## nothing; a side that finds a runner in behind completes half and has created
## a goal. The engine currently sits at one end of that: after the receiver's
## half of the pass went in, passes rose, through balls appeared where there had
## been none, and expected goals *fell*. Nothing in a completion rate can
## explain that, so this asks the questions that can.
##
## Four blocks, each answering something the others cannot:
##
##   Direction    -- where the ball is going relative to the goal being attacked,
##                   and what it is worth. `xT gained` is the honest measure of
##                   whether a pass improved anything: the same completion rate
##                   over a set of passes that gain nothing is a side keeping the
##                   ball for its own sake.
##   Aftermath    -- what happened to the man who received it. A pass that
##                   completes and is lost two seconds later did not work, and
##                   it is indistinguishable from a good one in every count the
##                   engine keeps.
##   Sequences    -- whether passing strings together into anything. Territory
##                   gained and the share of moves that reach a shot is what
##                   "better passing leads to more goals" actually asserts, and
##                   it is testable.
##   New mechanics -- the ball played to a committed run and the give-and-go
##                   return, measured against the ordinary pass on the same
##                   terms. If the new pass is not gaining more or finishing in
##                   shots more often, it is not doing what it was built for
##                   however many of them get played.
##
## Everything is read from the event log rather than kept alongside it, so it
## stays honest to `SimMatchStats`'s rule: if a statistic cannot be recovered
## from the log, the log is missing something.
const PASS_DIR_BANDS := [-3.0, 3.0, 15.0, 1e9]
const PASS_DIR_LABELS := ["backward", "square", "forward", "long forward"]
## How long after a pass a shot by the same side still counts as the move that
## pass was part of.
const PASS_TO_SHOT_SECONDS := 12.0
## The two marks at which the receiving side is asked whether it still has it.
const KEPT_SHORT := 2.0
const KEPT_LONG := 5.0


static func _passing_quality(ctx: SimContext, events: Array) -> void:
	var flip := _first_half_flip(events)
	var swap_tick := 1 << 30
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", -1)) == SimConsts.Period.SECOND_HALF:
			swap_tick = int(e["t"])
			break

	# Ticks at which each side shot, so a pass can be asked whether the move it
	# belonged to ended in one.
	var shots_by_team := [PackedInt32Array(), PackedInt32Array()]
	for e in events:
		if e["ev"] == SimTelemetry.Ev.SHOT:
			shots_by_team[int(e["team"])].append(int(e["t"]))
	# Every touch in order, for asking who had the ball when.
	var touch_ticks := PackedInt32Array()
	var touch_team := PackedInt32Array()
	for e in events:
		if e["ev"] == SimTelemetry.Ev.TOUCH:
			touch_ticks.append(int(e["t"]))
			touch_team.append(int(e["team"]))
	var n := PASS_DIR_LABELS.size()
	var count := PackedInt32Array(); count.resize(n)
	var done := PackedInt32Array(); done.resize(n)
	var length := PackedFloat32Array(); length.resize(n)
	var xt := PackedFloat32Array(); xt.resize(n)
	var to_shot := PackedInt32Array(); to_shot.resize(n)

	# The three splits the new mechanics are judged on: ordinary, played to a
	# committed run, and the give-and-go return.
	var split_count := PackedInt32Array(); split_count.resize(3)
	var split_done := PackedInt32Array(); split_done.resize(3)
	var split_xt := PackedFloat32Array(); split_xt.resize(3)
	var split_shot := PackedInt32Array(); split_shot.resize(3)

	var kept_short := 0
	var kept_long := 0
	var completed := 0

	# Attempts and outcomes are separate events, and an attempt does not always
	# get one -- a ball that runs out of play never resolves. Pairing them by
	# position in the log therefore desynchronises the moment one goes missing,
	# and every completion rate after that point is somebody else's. Matched by
	# passer, oldest attempt first, which is what the two events actually share.
	var attempts := []
	var pending := {}
	for e in events:
		var ev: int = e["ev"]
		if ev == SimTelemetry.Ev.PASS_ATTEMPT and e.has("from"):
			var p: int = e["p"]
			if not pending.has(p):
				pending[p] = []
			pending[p].append(attempts.size())
			attempts.append({"e": e, "ok": false})
		elif ev == SimTelemetry.Ev.PASS_OUTCOME:
			var p2: int = e["p"]
			if pending.has(p2) and not pending[p2].is_empty():
				var idx: int = pending[p2].pop_front()
				attempts[idx]["ok"] = bool(e.get("ok", false))

	for rec in attempts:
		var e: Dictionary = rec["e"]
		var ok: bool = rec["ok"]
		var team: int = e["team"]
		var t: int = e["t"]
		# One flip, applied once. Applied twice it cancels, and every pass in the
		# first half then reads as having gone the other way.
		var side := flip if t < swap_tick else 1.0
		var from: Vector3 = e["from"] * side
		var to: Vector3 = e["to"] * side
		var up := (to.x - from.x) * ctx.pitch.attack_dir(team)
		var band := 0
		while band < n - 1 and up > PASS_DIR_BANDS[band]:
			band += 1

		var gained := ctx.value.xt_at(team, to, ctx.pitch) - ctx.value.xt_at(team, from, ctx.pitch)
		var shot_after := _shot_within(shots_by_team[team], t, PASS_TO_SHOT_SECONDS)

		count[band] += 1
		length[band] += SimConsts.horizontal_length(to - from)
		xt[band] += gained
		if ok:
			done[band] += 1
		if shot_after:
			to_shot[band] += 1

		var split := 0
		if bool(e.get("gng", false)):
			split = 2
		elif int(e.get("call", 0)) != 0:
			split = 1
		split_count[split] += 1
		split_xt[split] += gained
		if ok:
			split_done[split] += 1
		if shot_after:
			split_shot[split] += 1

		if ok:
			completed += 1
			if _still_holding(touch_ticks, touch_team, t, team, KEPT_SHORT):
				kept_short += 1
			if _still_holding(touch_ticks, touch_team, t, team, KEPT_LONG):
				kept_long += 1

	var total := 0
	for i in n:
		total += count[i]
	if total == 0:
		return

	print("\nPassing by direction  (up-pitch, toward the goal being attacked)")
	print("  %-13s %8s %7s %9s %11s %11s" % ["", "played", "share", "completed", "xT gained", "then a shot"])
	for i in n:
		if count[i] == 0:
			continue
		print("  %-13s %8d %6.0f%% %8.0f%% %+11.4f %10.0f%%" % [
			PASS_DIR_LABELS[i], count[i],
			100.0 * float(count[i]) / float(total),
			100.0 * float(done[i]) / float(count[i]),
			xt[i] / float(count[i]),
			100.0 * float(to_shot[i]) / float(count[i]),
		])
	print("  mean length: " + _mean_lengths(length, count, n))

	if completed > 0:
		print("\nAfter the ball arrives  (did the side that received it keep it)")
		print("  still in possession after %.0f s   %3.0f%%" % [
			KEPT_SHORT, 100.0 * float(kept_short) / float(completed)])
		print("  still in possession after %.0f s   %3.0f%%" % [
			KEPT_LONG, 100.0 * float(kept_long) / float(completed)])
		_how_it_was_lost(events, attempts)

	_pass_sequences(ctx, events, flip, swap_tick)

	print("\nDid the new passes pay?  (%.0f s for the move to reach a shot)" % PASS_TO_SHOT_SECONDS)
	print("  %-16s %8s %9s %11s %11s" % ["", "played", "completed", "xT gained", "then a shot"])
	var split_names := ["ordinary", "to a committed run", "give-and-go return"]
	for i in 3:
		if split_count[i] == 0:
			continue
		print("  %-16s %8d %8.0f%% %+11.4f %10.0f%%" % [
			split_names[i], split_count[i],
			100.0 * float(split_done[i]) / float(split_count[i]),
			split_xt[i] / float(split_count[i]),
			100.0 * float(split_shot[i]) / float(split_count[i]),
		])


## How a completed pass turns into a turnover, and how quickly.
##
## "Half of completed passes are lost inside five seconds" is a fact without a
## cause attached, and the causes want opposite fixes. A ball lost to a tackle on
## the receiver's first touch says the receiver cannot survive contact, and the
## answer is shielding and drawing a foul. A ball lost to an interception two
## passes later says the *next* pass was the bad one, and the answer is in the
## decision layer. A ball lost out of play says neither. Nothing already in the
## log separates them: they are all one turnover.
##
## `touches before losing it` is the half that localises the failure in time. A
## side that loses the ball on the touch it receives it with is not being
## out-passed, it is being out-fought at the moment of control.
const LOST_LABELS := ["tackled or poked away", "intercepted cleanly", "out of play", "other"]


static func _how_it_was_lost(events: Array, attempts: Array) -> void:
	var window := int(KEPT_LONG * float(SimConsts.TICK_HZ))
	var causes := PackedInt32Array(); causes.resize(4)
	var touch_hist := PackedInt32Array(); touch_hist.resize(4)
	var lost := 0

	# Event indices by tick, walked forward from each pass. The log is already in
	# tick order, so this is a scan rather than a search.
	for rec in attempts:
		if not rec["ok"]:
			continue
		var e: Dictionary = rec["e"]
		var team: int = e["team"]
		var t: int = e["t"]
		var touches := 0
		var cause := 3
		var flipped := false
		for f in events:
			var ft: int = f["t"]
			if ft <= t:
				continue
			if ft - t > window:
				break
			var ev: int = f["ev"]
			if ev == SimTelemetry.Ev.TOUCH:
				if int(f["team"]) == team:
					touches += 1
				else:
					flipped = true
					break
			elif ev == SimTelemetry.Ev.RECOVERY and int(f["team"]) != team:
				cause = 1 if bool(f.get("clean", false)) else 0
			elif ev == SimTelemetry.Ev.SET_PIECE:
				cause = 2
			elif ev == SimTelemetry.Ev.DUEL and int(f["team"]) != team \
					and bool(f.get("challenge", false)):
				cause = 0
		if not flipped:
			continue
		lost += 1
		causes[cause] += 1
		touch_hist[mini(touches, 3)] += 1

	if lost == 0:
		return
	print("  when it was lost inside %.0f s (%d of them), how:" % [KEPT_LONG, lost])
	for i in 4:
		if causes[i] == 0:
			continue
		print("    %-22s %3.0f%%" % [LOST_LABELS[i], 100.0 * float(causes[i]) / float(lost)])
	var labels := ["never touched it", "one touch", "two touches", "three or more"]
	var parts := PackedStringArray()
	for i in 4:
		parts.append("%s %.0f%%" % [labels[i], 100.0 * float(touch_hist[i]) / float(lost)])
	print("  touches taken before losing it: " + ", ".join(parts))


static func _mean_lengths(length: PackedFloat32Array, count: PackedInt32Array, n: int) -> String:
	var parts := PackedStringArray()
	for i in n:
		if count[i] > 0:
			parts.append("%s %.1f m" % [PASS_DIR_LABELS[i], length[i] / float(count[i])])
	return ", ".join(parts)


## True if this side shot within `seconds` of `tick`.
static func _shot_within(ticks: PackedInt32Array, tick: int, seconds: float) -> bool:
	var window := int(seconds * float(SimConsts.TICK_HZ))
	for t in ticks:
		if t >= tick and t - tick <= window:
			return true
		if t > tick + window:
			break
	return false


## True if `team` still had the last touch `seconds` after `tick`.
##
## The question a completion rate cannot ask. A ball played to a man who is
## dispossessed immediately completed, counted, and achieved nothing.
static func _still_holding(ticks: PackedInt32Array, teams: PackedInt32Array,
		tick: int, team: int, seconds: float) -> bool:
	var mark := tick + int(seconds * float(SimConsts.TICK_HZ))
	var holder := team
	for i in ticks.size():
		if ticks[i] <= tick:
			continue
		if ticks[i] > mark:
			break
		holder = teams[i]
	return holder == team


## Possession sequences: a maximal run of touches by one side.
##
## This is where "better passing leads to more goals" is either true or not.
## Passes per move, ground gained and the share of moves that end in a shot are
## the chain the claim depends on, and a side can improve every individual pass
## while the chain gets shorter.
static func _pass_sequences(ctx: SimContext, events: Array, flip: float, swap_tick: int) -> void:
	const PASS_KINDS := [
		SimTelemetry.Touch.GROUND_PASS, SimTelemetry.Touch.THROUGH_BALL,
		SimTelemetry.Touch.LOFTED_PASS, SimTelemetry.Touch.CROSS,
	]
	var seq_count := 0
	var seq_passes := 0
	var seq_shots := 0
	var seq_multi := 0
	var seq_seconds := 0.0
	var seq_gain := 0.0

	var team_of := -1
	var passes := 0
	var shot := false
	var start_tick := 0
	var start_x := 0.0
	var last_x := 0.0
	var last_tick := 0

	for e in events:
		var ev: int = e["ev"]
		if ev != SimTelemetry.Ev.TOUCH and ev != SimTelemetry.Ev.SHOT:
			continue
		var team: int = e["team"]
		var t: int = e["t"]
		var side := flip if t < swap_tick else 1.0
		var at: Vector3 = e.get("at", e.get("from", Vector3.ZERO))
		var x := at.x * side * ctx.pitch.attack_dir(team)
		if team != team_of:
			if team_of >= 0:
				seq_count += 1
				seq_passes += passes
				seq_gain += last_x - start_x
				seq_seconds += float(last_tick - start_tick) / float(SimConsts.TICK_HZ)
				if shot:
					seq_shots += 1
				if passes >= 3:
					seq_multi += 1
			team_of = team
			passes = 0
			shot = false
			start_tick = t
			start_x = x
		last_x = x
		last_tick = t
		if ev == SimTelemetry.Ev.SHOT:
			shot = true
		elif int(e.get("kind", -1)) in PASS_KINDS:
			passes += 1
	if team_of >= 0:
		seq_count += 1
		seq_passes += passes
		seq_gain += last_x - start_x
		seq_seconds += float(last_tick - start_tick) / float(SimConsts.TICK_HZ)
		if shot:
			seq_shots += 1
		if passes >= 3:
			seq_multi += 1

	if seq_count == 0:
		return
	var f := float(seq_count)
	# A single defensive touch -- a block, a clearance, a failed interception --
	# is a sequence by this definition, which inflates the count and pulls the
	# mean down. So the pass figure is a floor rather than football's idea of a
	# possession, and it is the *share reaching three passes* that carries the
	# meaning: that one cannot be manufactured by a deflection.
	print("\nPossession sequences  (unbroken touches by one side, a lone block included)")
	print("  sequences %6d   mean %.1f passes, %.1f s, %+.1f m up the pitch" % [
		seq_count, float(seq_passes) / f, seq_seconds / f, seq_gain / f])
	print("  three passes or more %3.0f%%   ended in a shot %3.0f%%" % [
		100.0 * float(seq_multi) / f, 100.0 * float(seq_shots) / f])


static func _first_half_flip(events: Array) -> float:
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
			return -1.0
	return 1.0


## Distance bands shots are bucketed into, in metres from the centre of the goal.
## 16.5 is the edge of the penalty area and 5.5 the edge of the six-yard box, so
## the rows line up with the places a supporter would name.
const SHOT_BANDS := [5.5, 11.0, 16.5, 23.0, 30.0, 1e9]
## How soon after a shot another one counts as a second ball rather than a
## separate chance.
const REBOUND_SECONDS := 4.0
const SHOT_LABELS := ["six-yard box", "penalty spot", "edge of box", "just outside", "distance", "hopeful"]


## Where shots are taken from, and what the ball does when it gets to the box.
##
## A count of shots says nothing about either half of this. A team that walks it
## into the six-yard box every time and one that shoots from anywhere both
## produce a plausible-looking total, and the §11 bands see one number for both;
## what tells them apart is the distance the shots were struck from. Real
## football takes a good quarter to a third of its shots from outside the
## penalty area, and an engine with none of them looks wrong long before any
## band notices.
##
## The second half is the complaint the first cannot answer: a carrier who
## arrives in the box and keeps knocking the ball ahead of himself never gets a
## shot away at all, so the shot simply never appears in the log. The only way to
## see it is to count what the man on the ball actually did with his touches
## inside the area, and how far in front of himself he pushed the ball when he
## carried -- a four-metre touch eight metres from goal is a pass to the keeper,
## whatever the decision layer thought it was choosing.
static func _shooting(ctx: SimContext, events: Array) -> void:
	var n := SHOT_BANDS.size()
	var taken := PackedInt32Array()
	var goals := PackedInt32Array()
	var on_target := PackedInt32Array()
	var blocked := PackedInt32Array()
	var quality := PackedFloat32Array()
	for a in [taken, goals, on_target, blocked]:
		a.resize(n)
	quality.resize(n)

	var follow_ups := 0
	var last_shot := PackedInt32Array([-99999, -99999])
	var rebound_ticks := int(REBOUND_SECONDS * float(SimConsts.TICK_HZ))
	var flip := _first_half_flip(events)
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
			flip = 1.0
		if e["ev"] != SimTelemetry.Ev.SHOT:
			continue
		var team: int = e["team"]
		var from: Vector3 = e["from"]
		var t := int(e.get("t", 0))
		if t - last_shot[team] <= rebound_ticks:
			follow_ups += 1
		last_shot[team] = t
		var goal := ctx.pitch.target_goal(team) * flip
		var d := SimConsts.horizontal_length(goal - from)
		var band := n - 1
		for i in n:
			if d <= float(SHOT_BANDS[i]):
				band = i
				break
		taken[band] += 1
		quality[band] += float(e.get("quality", 0.0))
		if bool(e.get("goal", false)):
			goals[band] += 1
			on_target[band] += 1
		elif bool(e.get("on_target", false)):
			on_target[band] += 1
		elif bool(e.get("blocked", false)):
			blocked[band] += 1

	var total := 0
	for i in n:
		total += taken[i]
	print("\nShots by distance  (%d shots)" % total)
	# The box block still prints when nobody managed a shot, and that is the case
	# it was written for: no shots at all with plenty of touches in the area is
	# the exact shape of a carrier who never stops carrying.
	if total == 0:
		_in_the_box(ctx, events)
		return
	print("  %-14s %7s %7s %8s %8s %8s" % ["", "shots", "share", "on target", "blocked", "mean xG"])
	for i in n:
		if taken[i] == 0:
			continue
		var t := float(taken[i])
		print("  %-14s %7d %6.0f%% %7.0f%% %7.0f%% %8.3f" % [
			SHOT_LABELS[i], taken[i], 100.0 * t / float(total),
			100.0 * float(on_target[i]) / t, 100.0 * float(blocked[i]) / t,
			quality[i] / t,
		])
	var scored := 0
	for i in n:
		scored += goals[i]
	print("  goals %d, from %s" % [scored, _goal_bands(goals, n)])
	# A shot total is two quite different things added together: chances created,
	# and second balls hammered back at the goal after the first was parried or
	# blocked. Only the first is a measure of the attack, and only the split says
	# which one a rising total was.
	if follow_ups > 0:
		print("  %d of them second attempts, inside %.0f s of the same team's last shot" % [
			follow_ups, REBOUND_SECONDS,
		])
	_in_the_box(ctx, events)


static func _goal_bands(goals: PackedInt32Array, n: int) -> String:
	var parts := PackedStringArray()
	for i in n:
		if goals[i] > 0:
			parts.append("%s %d" % [SHOT_LABELS[i], goals[i]])
	return ", ".join(parts) if parts.size() > 0 else "nowhere"


## What the man on the ball did with it inside the penalty area.
##
## The row that matters is the carry: how many of the touches taken in the box
## were another push forward, and how far forward they were pushed. Compared
## against the same figure outside the box it says whether the carrier knows
## where he is.
static func _in_the_box(ctx: SimContext, events: Array) -> void:
	var box := {"carry": 0, "shot": 0, "pass": 0, "other": 0}
	var box_ahead := 0.0
	var box_carries := 0
	var out_ahead := 0.0
	var out_carries := 0
	var flip := _first_half_flip(events)
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
			flip = 1.0
		if e["ev"] != SimTelemetry.Ev.TOUCH:
			continue
		var kind: int = e["kind"]
		if kind == SimTelemetry.Touch.TACKLE or kind == SimTelemetry.Touch.BLOCK:
			continue
		# The box a team is attacking is the one it defends after the ends change.
		var inside := ctx.pitch.in_opponent_penalty_area(e["team"], e["from"]) if flip > 0.0 \
			else ctx.pitch.in_own_penalty_area(e["team"], e["from"])
		if kind == SimTelemetry.Touch.DRIBBLE:
			if inside:
				box_ahead += float(e.get("ahead", 0.0))
				box_carries += 1
			else:
				out_ahead += float(e.get("ahead", 0.0))
				out_carries += 1
		if not inside:
			continue
		match kind:
			SimTelemetry.Touch.DRIBBLE:
				box["carry"] += 1
			SimTelemetry.Touch.SHOT:
				box["shot"] += 1
			_:
				if SimTelemetry.is_pass_kind(kind):
					box["pass"] += 1
				else:
					box["other"] += 1
	var total: int = box["carry"] + box["shot"] + box["pass"] + box["other"]
	if total == 0:
		return
	print("  in the penalty area: %d touches -- %d carried, %d struck, %d passed, %d other" % [
		total, box["carry"], box["shot"], box["pass"], box["other"],
	])
	if box_carries > 0:
		print("    carries in the box push it %.2f m ahead (outside: %.2f m over %d)" % [
			box_ahead / float(box_carries),
			out_ahead / maxf(float(out_carries), 1.0), out_carries,
		])


static func report(m: SimMatch) -> void:
	var ctx := m.ctx
	var events := ctx.telemetry.events

	# --- Touches by kind ----------------------------------------------------
	var touch_counts := {}
	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH:
			continue
		var k: int = e["kind"]
		touch_counts[k] = int(touch_counts.get(k, 0)) + 1
	print("Touches by kind")
	var kinds := touch_counts.keys()
	kinds.sort_custom(func(a, b): return int(touch_counts[a]) > int(touch_counts[b]))
	for k in kinds:
		print("  %-14s %6d" % [SimTelemetry.touch_name(k), touch_counts[k]])

	# Every touch in order, for asking who had the ball a few seconds later.
	var held_ticks := PackedInt32Array()
	var held_team := PackedInt32Array()
	for e in events:
		if e["ev"] == SimTelemetry.Ev.TOUCH:
			held_ticks.append(int(e["t"]))
			held_team.append(int(e["team"]))

	_ball_control(events)
	_taking_it_down(events, held_ticks, held_team)
	_under_challenge(events)
	_where_the_carry_went(ctx, events)
	_locomotion(ctx)
	_chasing(ctx)
	_offering(ctx)
	_safe_options(ctx)
	_giving_up_ground(ctx)

	# --- Pass attempts by kind, with completion -----------------------------
	var attempts := {}
	var lengths := {}
	for e in events:
		if e["ev"] != SimTelemetry.Ev.PASS_ATTEMPT:
			continue
		var k: int = e["kind"]
		attempts[k] = int(attempts.get(k, 0)) + 1
		lengths[k] = float(lengths.get(k, 0.0)) + float(e.get("dist", 0.0))
	var completed := {}
	var outcomes := {}
	for e in events:
		if e["ev"] != SimTelemetry.Ev.PASS_OUTCOME:
			continue
		var k: int = e["kind"]
		outcomes[k] = int(outcomes.get(k, 0)) + 1
		if bool(e.get("ok", false)):
			completed[k] = int(completed.get(k, 0)) + 1
	print("\nPasses by kind        attempts  completed   resolved   mean len")
	for k in attempts:
		print("  %-18s %8d %10d %10d %9.1f m" % [
			SimTelemetry.touch_name(k), attempts[k],
			int(completed.get(k, 0)), int(outcomes.get(k, 0)),
			float(lengths[k]) / maxf(float(attempts[k]), 1.0),
		])

	# --- Pass length histogram ---------------------------------------------
	#
	# The `in the air` column is the whole of "a longer ball should be a higher
	# ball", and it is a claim about a *shape*, not a rate: it should be zero at
	# the short end, cross over somewhere in the twenties, and be everything at
	# the long end. A flat column at any value means the engine picks its pass
	# height without reference to how far it has to go.
	var hist := PackedInt32Array()
	var hist_ok := PackedInt32Array()
	var hist_air := PackedInt32Array()
	hist.resize(LENGTH_BUCKETS.size())
	hist_ok.resize(LENGTH_BUCKETS.size())
	hist_air.resize(LENGTH_BUCKETS.size())
	# Pair each attempt with the outcome that follows it, in order.
	var pending := {}
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PASS_ATTEMPT:
			pending[int(e["p"])] = [float(e.get("dist", 0.0)), int(e["kind"])]
		elif e["ev"] == SimTelemetry.Ev.PASS_OUTCOME:
			var passer := int(e["p"])
			if not pending.has(passer):
				continue
			var held: Array = pending[passer]
			var d: float = held[0]
			pending.erase(passer)
			for i in LENGTH_BUCKETS.size():
				if d < LENGTH_BUCKETS[i]:
					hist[i] += 1
					if int(held[1]) == SimTelemetry.Touch.LOFTED_PASS or int(held[1]) == SimTelemetry.Touch.CROSS:
						hist_air[i] += 1
					if bool(e.get("ok", false)):
						hist_ok[i] += 1
					break
	print("\nCompletion by pass length")
	var low := 0.0
	for i in LENGTH_BUCKETS.size():
		if hist[i] == 0:
			low = LENGTH_BUCKETS[i]
			continue
		print("  %5.0f - %-5.0f m   %6d resolved   %5.0f%% completed   %3.0f%% in the air" % [
			low, minf(LENGTH_BUCKETS[i], 99.0), hist[i],
			100.0 * float(hist_ok[i]) / float(hist[i]),
			100.0 * float(hist_air[i]) / float(hist[i]),
		])
		low = LENGTH_BUCKETS[i]

	_by_body_angle(ctx, events)
	_passing_quality(ctx, events)
	_pass_destination(ctx, events)
	_restarts(ctx, events)
	_goalkeeping(ctx, events)

	# --- How possession ends ------------------------------------------------
	var lost_intercept := 0
	var lost_out := 0
	var lost_tackle := 0
	# What put it out, which no count of throw-ins can say. A ball hammered clear
	# and a ball a carrier walked over the touchline in front of him are the same
	# restart, and only one of them is a problem.
	var out_by := {}
	var out_side := {}
	var last_kind := -1
	var last_from := Vector3.ZERO
	var last_vel := Vector3.ZERO
	# For the carries that go out: how much grass he had beside him when he played
	# it, and how hard he hit it. A touch played a metre from the paint and a
	# full-blooded carry from eight metres inside are the same throw-in and want
	# opposite fixes -- the first is a touch that should never have been offered,
	# the second is an aim error on a legitimate one.
	var carried_out := 0
	var carried_room := 0.0
	var carried_pace := 0.0
	var knocked_out := 0
	var last_ahead := 0.0
	for e in events:
		match e["ev"]:
			SimTelemetry.Ev.TOUCH:
				last_kind = int(e["kind"])
				last_from = e["from"]
				last_vel = e["vel"]
				last_ahead = float(e.get("ahead", 0.0))
			SimTelemetry.Ev.RECOVERY:
				if bool(e.get("clean", false)):
					lost_intercept += 1
				else:
					lost_tackle += 1
			SimTelemetry.Ev.SET_PIECE:
				var kind: int = e["kind"]
				if kind == SimSetPiece.Kind.THROW_IN or kind == SimSetPiece.Kind.CORNER or kind == SimSetPiece.Kind.GOAL_KICK:
					lost_out += 1
					if last_kind >= 0:
						out_by[last_kind] = int(out_by.get(last_kind, 0)) + 1
						if kind == SimSetPiece.Kind.THROW_IN:
							out_side[last_kind] = int(out_side.get(last_kind, 0)) + 1
						if last_kind == SimTelemetry.Touch.DRIBBLE:
							carried_out += 1
							if last_ahead > SimTouch.DRIBBLE_AHEAD_MAX:
								knocked_out += 1
							carried_room += minf(
								ctx.pitch.half_width - absf(last_from.z),
								ctx.pitch.half_length - absf(last_from.x))
							carried_pace += SimConsts.horizontal_length(last_vel)
	# --- Duels and challenges ------------------------------------------------
	var duels := 0
	var challenges := 0
	var challenges_won := 0
	for e in events:
		if e["ev"] != SimTelemetry.Ev.DUEL:
			continue
		duels += 1
		if bool(e.get("challenge", false)):
			challenges += 1
			if bool(e.get("challenger_won", false)):
				challenges_won += 1
	print("\nDuels")
	print("  contests over the ball  %6d" % (duels - challenges))
	print("  challenges on the man   %6d   challenger won %d (%.0f%%)" % [
		challenges, challenges_won,
		100.0 * float(challenges_won) / maxf(float(challenges), 1.0),
	])

	print("\nHow the ball changes hands")
	print("  clean interception   %6d" % lost_intercept)
	print("  scrappy / tackled    %6d" % lost_tackle)
	print("  out of play          %6d" % lost_out)
	if not out_by.is_empty():
		var by := out_by.keys()
		by.sort_custom(func(a, b): return int(out_by[a]) > int(out_by[b]))
		var parts := PackedStringArray()
		for k in by:
			parts.append("%s %d" % [SimTelemetry.touch_name(k), out_by[k]])
		print("    last touched by      %s" % ", ".join(parts))
		var side := PackedStringArray()
		for k in by:
			if int(out_side.get(k, 0)) > 0:
				side.append("%s %d" % [SimTelemetry.touch_name(k), out_side[k]])
		if not side.is_empty():
			print("    over a touchline     %s" % ", ".join(side))
		if carried_out > 0:
			print("    the carried ones     %d (%d of them the knock past a man), played %.1f m inside the nearest line at %.1f m/s" % [
				carried_out, knocked_out,
				carried_room / float(carried_out), carried_pace / float(carried_out),
			])
	_churn(events)
	_after_regain(events)

	_shooting(ctx, events)

	# --- Where the ball is played ------------------------------------------
	var thirds := PackedInt32Array([0, 0, 0])
	var box_touches := 0
	# The ends change at half time, so the first half has to be read against the
	# goal the team was actually attacking then -- see `_first_half_flip`. Without
	# it every own-third touch of the first half was counted as a final-third one.
	var third_flip := _first_half_flip(events)
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
			third_flip = 1.0
		if e["ev"] != SimTelemetry.Ev.TOUCH:
			continue
		var team: int = e["team"]
		var at: Vector3 = e["from"]
		var forward := at.x * ctx.pitch.attack_dir(team) * third_flip
		var third := 0 if forward < -ctx.pitch.half_length / 3.0 else (2 if forward > ctx.pitch.half_length / 3.0 else 1)
		thirds[third] += 1
		var in_box := ctx.pitch.in_opponent_penalty_area(team, at) if third_flip > 0.0 \
			else ctx.pitch.in_own_penalty_area(team, at)
		if in_box:
			box_touches += 1
	var total_touches: float = maxf(float(thirds[0] + thirds[1] + thirds[2]), 1.0)
	print("\nTouches by third (own / middle / final): %.0f%% / %.0f%% / %.0f%%   in the box: %d" % [
		100.0 * thirds[0] / total_touches, 100.0 * thirds[1] / total_touches,
		100.0 * thirds[2] / total_touches, box_touches,
	])

	# --- Named patterns -----------------------------------------------------
	# PLAN.md §5.3: each pattern is reported after the match with a count and a
	# success rate. Named things with visible, counted occurrences are what make
	# a tactical layer learnable.
	print("\nNamed patterns")
	for team in 2:
		var rows := SimPatterns.summary(ctx, team)
		if rows.is_empty():
			continue
		print("  %s" % ctx.teams[team].short_name)
		for row in rows:
			print("    %-24s fired %3d   succeeded %3d   %3.0f%%" % [
				row["name"], row["fired"], row["succeeded"], 100.0 * float(row["rate"]),
			])

	# --- Running ------------------------------------------------------------
	print("\nDistance covered (km)")
	for team in 2:
		var line := PackedStringArray()
		for pid in ctx.team_players[team]:
			var p := ctx.players[pid]
			line.append("%s %.1f" % [SimRole.name_of(p.role), p.distance_run / 1000.0])
		print("  %s: %s" % [ctx.teams[team].short_name, " ".join(line)])
