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
	# Anything past the reach that applied to it should be impossible, so when it
	# happens the useful question is which kind of touch did it.
	#
	# The reach is per touch and not one constant, because two of them are not
	# `CONTROL_RANGE`. A ball above head height is met with a leap and
	# `SimAerial.contact_range` says how far that carries; and a keeper has his own
	# contact rules entirely -- he gathers at `GATHER_RANGE`, claims at
	# `CLAIM_RANGE` and meets a shot at the end of a three-metre dive -- so his
	# touches are counted here only for the record. Measured against the flat
	# constant, every header in the match reported as a magnetic touch and the
	# instrument stopped saying anything.
	var over := {}
	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH or not e.has("at"):
			continue
		var ball_y: float = (e["from"] as Vector3).y
		if SimConsts.horizontal_length(e["from"] - e["at"]) <= SimAerial.contact_range(ball_y):
			continue
		var k: int = e["kind"]
		over[k] = int(over.get(k, 0)) + 1
	print("")
	print("Ball control  (CONTROL_RANGE is %.2f m from the player's centre, %.2f m for a ball in the air)"
		% [SimConsts.CONTROL_RANGE, SimAerial.AERIAL_RANGE])
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
## to watch after anything that touches `_add_dribbles`, `safe_direction` or
## `_play_hold`. A pathology here does not have to be the scoring: three quarters
## of the carries in a match are settling touches, and those are aimed by
## `SimDecision.safe_direction` rather than scored by anything.
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
		# Only the carrier's own choices. A tackle, a block or a poke is the
		# defender's.
		if SimTelemetry.is_defensive_kind(kind):
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
## Which term an option lost on, for every kind that was on the list and was not
## the one played. Each pair is the losing candidate against the option that beat
## it, averaged over the decisions where that kind was the best of its kind and
## still lost. `gain` and `loss` are the raw positional terms, before the discount
## and the possession value `score_of` adds to both.
static func _why_it_lost() -> void:
	var any := false
	for kind in SimDecision.Action.size():
		if SimDecision.lost_at(kind, SimDecision.LOST_N) > 0.0:
			any = true
	if not any:
		return
	print("\nWhy an option lost  (best of its kind when it was not the one played)")
	if SimDecision.exposure_n > 0.0:
		print("  a turnover was priced at %.2f x its threat, mean, with the defensive line %.0f%% up the pitch" % [
			SimDecision.exposure_sum / SimDecision.exposure_n,
			100.0 * SimDecision.exposure_line / SimDecision.exposure_n])
	if SimDecision.stretch_n > 0.0:
		print("  and stretched at %.2f x on top, mean over candidates, worst %.2f x" % [
			SimDecision.stretch_sum / SimDecision.stretch_n, SimDecision.stretch_hi])
	print("  %-13s %7s %15s %17s %17s %9s" % [
		"", "times", "success", "gain", "loss", "score gap"])
	for kind in SimDecision.Action.size():
		var n := SimDecision.lost_at(kind, SimDecision.LOST_N)
		if n < 1.0:
			continue
		print("  %-13s %7d %7.2f v %-5.2f %8.4f v %-6.4f %8.4f v %-6.4f %+9.4f" % [
			SimDebug.ACTION_NAMES[kind], int(n),
			SimDecision.lost_at(kind, SimDecision.LOST_SUCCESS) / n,
			SimDecision.lost_at(kind, SimDecision.WON_SUCCESS) / n,
			SimDecision.lost_at(kind, SimDecision.LOST_GAIN) / n,
			SimDecision.lost_at(kind, SimDecision.WON_GAIN) / n,
			SimDecision.lost_at(kind, SimDecision.LOST_LOSS) / n,
			SimDecision.lost_at(kind, SimDecision.WON_LOSS) / n,
			(SimDecision.lost_at(kind, SimDecision.LOST_SCORE)
				- SimDecision.lost_at(kind, SimDecision.WON_SCORE)) / n,
		])


## What a spell of possession produced, and what had been played in it.
##
## The first table any of this was for. Every other block here counts acts -- how
## many carries, how many through balls, how far each went -- and none of them can
## say what came of one, because a count has no way of reaching forward. Joining on
## `poss` is what makes it reachable: every event carries the spell it happened in,
## so "what became of the ball" is a filter over a group rather than a guess at a
## tick window. See `SimContext.possession_id`.
##
## Fates are precedence-ordered, not last-event-wins. A shot that goes out for a
## corner logs the corner second, and reading backwards would file the possession
## as a ball out of play and lose the only thing about it that mattered.
const POSS_FATES := [
	"a goal", "a shot", "offside", "a foul won", "a set piece won",
	"a foul conceded", "out of play", "tackled", "intercepted",
	"picked off loose", "lost otherwise",
]
const PF_GOAL := 0
const PF_SHOT := 1
const PF_OFFSIDE := 2
const PF_FOUL_WON := 3
const PF_SET_WON := 4
const PF_FOUL_CONCEDED := 5
const PF_OUT := 6
const PF_TACKLED := 7
const PF_INTERCEPTED := 8
## The ball nobody took off anybody: a loose one the other side reached first. It
## is the largest single way this engine loses the ball and it logs no duel and no
## cut-out pass, so without a row of its own it sat inside "lost otherwise" and
## looked like a gap in the instrument rather than a fact about the football.
const PF_LOOSE := 9
const PF_OTHER := 10

## The kinds worth a row in the lower table. Every kind is counted; only these are
## printed, because a first touch appears in nearly every spell and says nothing
## about what the spell was.
const POSS_TOUCH_ROWS := [
	SimTelemetry.Touch.DRIBBLE, SimTelemetry.Touch.GROUND_PASS,
	SimTelemetry.Touch.THROUGH_BALL, SimTelemetry.Touch.LOFTED_PASS,
	SimTelemetry.Touch.CROSS, SimTelemetry.Touch.HEADER,
	SimTelemetry.Touch.CLEARANCE,
]


## Two joins, and they are not interchangeable.
##
## **The fate comes off the tag.** Possession is derived at the top of a tick, so
## the event that ends a spell -- the tackle, the cut-out pass, the whistle -- is
## logged while that spell is still the live one and carries its id. That is what
## makes the fate a filter over a group instead of a guess.
##
## **The contents come off the tick interval**, `[t - ticks, t]` off the end event.
## The touch that *wins* the ball is also logged a tick before this notices, so by
## tag it belongs to the spell it ended rather than the one it began, and a spell
## counted by tag is one touch short at the front. Read by interval, a deflection
## came back as a possession with no touches in it.
##
## **A shot is a content, not an ending event**, and getting that wrong cost two
## goes. A first-time strike off a loose ball is itself the touch that wins the
## ball, so it is tagged to the spell it ended -- the *opposition's* -- and four of
## seed 7's five goals were being thrown away by a team check that was right to
## reject them. Shots and goals are therefore matched to the spell whose team owned
## the ball at that tick, by the same interval join as the touches.
##
## Neither is a positional pairing and neither can desynchronise; the interval is
## exact rather than a window guessed in seconds.
## Every spell of possession, with what it produced and how far it got.
##
## Built once and handed to the three blocks that read it, because deriving it
## three times would be three chances for three subtly different answers to the
## same question.
static func _possession_table(ctx: SimContext, events: Array) -> Dictionary:
	var ends := {}
	var by_poss := {}
	for e in events:
		var poss := int(e.get("poss", -1))
		if poss < 0:
			continue
		if int(e["ev"]) == SimTelemetry.Ev.POSSESSION_END:
			ends[poss] = e
		if not by_poss.has(poss):
			by_poss[poss] = []
		by_poss[poss].append(e)
	# Touches in tick order, so a spell's own can be taken off its interval.
	var touch_at := PackedInt32Array()
	var touch_team := PackedInt32Array()
	var touch_kind := PackedInt32Array()
	var touch_pos := PackedVector3Array()
	for e in events:
		if int(e["ev"]) != SimTelemetry.Ev.TOUCH:
			continue
		touch_at.append(int(e["t"]))
		touch_team.append(int(e.get("team", -1)))
		touch_kind.append(int(e["kind"]))
		touch_pos.append(e.get("from", Vector3.ZERO))

	# Shots and own goals, to be matched to a spell by team and tick rather than by
	# the id they were logged under.
	var shot_at := PackedInt32Array()
	var shot_team := PackedInt32Array()
	var shot_on := PackedInt32Array()
	var shot_goal := PackedInt32Array()
	for e in events:
		var by := int(e.get("p", -1))
		if by < 0 or by >= ctx.players.size():
			continue
		if int(e["ev"]) == SimTelemetry.Ev.SHOT:
			shot_at.append(int(e["t"]))
			shot_team.append(ctx.players[by].team)
			shot_on.append(1 if bool(e.get("on_target", false)) or bool(e.get("goal", false)) else 0)
			shot_goal.append(1 if bool(e.get("goal", false)) else 0)
		elif int(e["ev"]) == SimTelemetry.Ev.GOAL and bool(e.get("own_goal", false)):
			# The one goal that logs no shot. Credited to the side it counts for.
			shot_at.append(int(e["t"]))
			shot_team.append(SimConsts.other_team(ctx.players[by].team))
			shot_on.append(1)
			shot_goal.append(1)

	var third := ctx.pitch.half_length / 3.0
	var out := {}
	for poss in ends:
		var end: Dictionary = ends[poss]
		var team := int(end["team"])
		var rows: Array = by_poss[poss]
		var last := int(end["t"])
		var first := last - int(end.get("ticks", 0))
		# The direction they were attacking, off the event rather than off the
		# pitch, which only knows where the ends point now.
		var dir := float(end.get("dir", 1.0))
		var kinds := {}
		var touched := 0
		var passed := 0
		var deepest := -INF
		var area := false
		var area_when := -1
		var final_when := -1
		var third_x := ctx.pitch.half_length / 3.0
		for i in touch_at.size():
			if touch_at[i] < first or touch_at[i] > last or touch_team[i] != team:
				continue
			touched += 1
			var k := touch_kind[i]
			if SimTelemetry.is_pass_kind(k):
				passed += 1
			kinds[k] = true
			var p: Vector3 = touch_pos[i]
			deepest = maxf(deepest, p.x * dir)
			if p.x * dir > third_x:
				final_when = maxi(final_when, touch_at[i])
			if absf(p.z) <= ctx.pitch.penalty_half_width \
					and absf(p.x - dir * ctx.pitch.half_length) <= ctx.pitch.penalty_depth:
				area = true
				area_when = maxi(area_when, touch_at[i])
		var to: Vector3 = end.get("to", Vector3.ZERO)
		deepest = maxf(deepest, to.x * dir)
		var shot := false
		var on_target := false
		var goal := false
		# The last tick each of these happened at, so a chain that starts at a
		# decision can ask whether it happened *after* that decision. Without it a
		# through ball played in the eightieth second of a move is credited with a
		# box entry from the tenth.
		var shot_when := -1
		var goal_when := -1
		for i in shot_at.size():
			if shot_at[i] < first or shot_at[i] > last or shot_team[i] != team:
				continue
			shot = true
			shot_when = maxi(shot_when, shot_at[i])
			on_target = on_target or shot_on[i] == 1
			if shot_goal[i] == 1:
				goal = true
				goal_when = maxi(goal_when, shot_at[i])
		# The fate takes the shot from here rather than from the log again, so the
		# chain and the table above it cannot disagree about how many there were.
		# They did: the chain printed 8 against the block's 19.
		var fate := _poss_fate(ctx, team, rows)
		if goal:
			fate = PF_GOAL
		elif shot:
			fate = mini(fate, PF_SHOT)
		out[poss] = {
			"team": team,
			"fate": fate,
			"first": first,
			"last": last,
			"dir": dir,
			"end_x": to.x * dir,
			"seconds": float(end.get("ticks", 0)) / float(SimConsts.TICK_HZ),
			"gained": float(end.get("gained", 0.0)),
			"touches": touched,
			"passes": passed,
			"kinds": kinds,
			"middle": deepest > -third,
			"final": deepest > third,
			"area": area,
			"shot": shot,
			"on_target": on_target,
			"goal": goal,
			# The last tick each happened at, or -1. For the chains that begin at a
			# decision rather than at a spell.
			"final_when": final_when,
			"area_when": area_when,
			"shot_when": shot_when,
			"goal_when": goal_when,
		}
	return out


static func _what_became_of_it(table: Dictionary) -> void:
	if table.is_empty():
		return

	var n := PackedInt32Array()
	var seconds := PackedFloat32Array()
	var ground := PackedFloat32Array()
	var touches := PackedInt32Array()
	var passes := PackedInt32Array()
	n.resize(POSS_FATES.size())
	seconds.resize(POSS_FATES.size())
	ground.resize(POSS_FATES.size())
	touches.resize(POSS_FATES.size())
	passes.resize(POSS_FATES.size())
	# Which spells each touch kind appeared in, and what those spells produced.
	var kind_n := {}
	var kind_shot := {}
	var kind_ground := {}

	for poss in table:
		var row: Dictionary = table[poss]
		var fate: int = row["fate"]
		var gained: float = row["gained"]
		n[fate] += 1
		seconds[fate] += row["seconds"]
		ground[fate] += gained
		touches[fate] += int(row["touches"])
		passes[fate] += int(row["passes"])
		for k in row["kinds"]:
			kind_n[k] = int(kind_n.get(k, 0)) + 1
			kind_ground[k] = float(kind_ground.get(k, 0.0)) + gained
			if fate == PF_SHOT or fate == PF_GOAL:
				kind_shot[k] = int(kind_shot.get(k, 0)) + 1

	var total := table.size()
	print("\nWhat became of the ball  (%d spells of possession that ended)" % total)
	print("  %-16s %7s %7s %9s %8s %9s %8s" % [
		"ended in", "count", "share", "seconds", "touches", "passes", "ground"])
	for f in POSS_FATES.size():
		if n[f] == 0:
			continue
		var count := float(n[f])
		print("  %-16s %7d %6.0f%% %9.1f %8.1f %9.1f %+7.1f m" % [
			POSS_FATES[f], n[f], 100.0 * count / float(total),
			seconds[f] / count, float(touches[f]) / count,
			float(passes[f]) / count, ground[f] / count,
		])

	# The join, and the reason for the whole field. It is an observational split
	# and not a causal one: a spell containing a cross is a spell that had already
	# reached the byline, so the shot rate beside it is partly the situation and
	# partly the pass. `The coin the softmax tossed` is what separates them.
	print("  and what had been played in it, by the spells containing one")
	print("  %-16s %7s %7s %11s %10s" % [
		"", "spells", "share", "-> a shot", "ground"])
	for k in POSS_TOUCH_ROWS:
		var kn := int(kind_n.get(k, 0))
		if kn < 10:
			continue
		print("  %-16s %7d %6.0f%% %10.0f%% %+9.1f m" % [
			SimTelemetry.touch_name(k), kn, 100.0 * float(kn) / float(total),
			100.0 * float(kind_shot.get(k, 0)) / float(kn),
			float(kind_ground.get(k, 0.0)) / float(kn),
		])


## Where a tie stops counting as one. The bounds are on the *propensity* -- how
## likely the engine was to play the kind it played -- rather than on a gap in
## goal probability, because the propensity is the thing that has to be near a coin
## flip and a score gap only tells you that through a temperature that varies by
## player. Between 0.40 and 0.60 the arms are assigned within a fifth of even.
const TIE_LOW := 0.40
const TIE_HIGH := 0.60
## Below this an arm is not worth printing at all, and below `TIE_SOLID` it is
## printed and tagged, on the same rule the batch runner uses for a metric under
## the sample size it needs. Ten minutes of football holds about 130 near-ties
## spread over nine pairs, so at diagnose length every row here is tagged and the
## measurement wants a full-length match. Widening the band to reach a sample is
## fitting the instrument to the run rather than to the question: at 0.35 to 0.65
## the carry arm's shot rate moved from 8% to 28% on the same seed, which is the
## noise saying so.
const TIE_MIN_ARM := 10
const TIE_SOLID := 40
## How long after the decision the side still having the ball counts as keeping it.
const TIE_KEPT := 3.0


## The one comparison here that is not confounded. See `SimChoices`.
##
## Every other split in this file compares what happened after a carry with what
## happened after a pass, and every one of them is a fact about the situations
## carries get chosen in as much as about carrying. This conditions on the
## decisions the engine was **undecided** about -- where the two kinds of act held
## between 40% and 60% of the weight between them -- and on those, which one got
## played was settled by `ctx.rng` and by nothing else. The gap between the arms is
## therefore caused by the choice.
##
## Read `p` first. It is the mean chance the arm's kind had of being played, and if
## the two sides of a row are not close to even the conditioning has not worked and
## the rest of the row is worth nothing.
##
## Two limits, both real. It is a *local* effect: it says what the pass was worth
## instead of the carry on the decisions where they were nearly equal, which is a
## population the engine picked, not one football cares about especially. And the
## outcome is the spell's, so a decision three seconds from a turnover is scored
## on a possession it barely influenced.
static func _near_ties(table: Dictionary) -> void:
	if SimChoices.count() == 0 or table.is_empty():
		return
	# pair key -> [arm 0 stats, arm 1 stats], each [n, shots, ground, kept, p sum].
	var pairs := {}
	var considered := 0
	for r in SimChoices.count():
		var kind_a := SimChoices.at(r, SimChoices.R_KIND_A)
		var kind_b := SimChoices.at(r, SimChoices.R_KIND_B)
		var played_kind := SimChoices.at(r, SimChoices.R_PLAYED)
		# Which of the two kinds came out, or neither: a third kind winning is not
		# a trial of these two, and dropping it is a selection on the coin rather
		# than on the situation, which is the one that would bias this.
		var played := 0 if played_kind == kind_a else (1 if played_kind == kind_b else -1)
		if played < 0:
			continue
		considered += 1
		var p_a := SimChoices.p_of(r)
		var p_played: float = p_a if played == 0 else 1.0 - p_a
		if p_played < TIE_LOW or p_played > TIE_HIGH:
			continue
		var poss := SimChoices.at(r, SimChoices.R_POSS)
		if not table.has(poss):
			continue
		var row: Dictionary = table[poss]
		# Ordered so the same pair of kinds is one row whichever way round the
		# scores came out this time.
		var lo: int = mini(kind_a, kind_b)
		var hi: int = maxi(kind_a, kind_b)
		var arm: int = 0 if (kind_a if played == 0 else kind_b) == lo else 1
		var key := lo * 100 + hi
		if not pairs.has(key):
			pairs[key] = [
				PackedFloat32Array([0, 0, 0, 0, 0]), PackedFloat32Array([0, 0, 0, 0, 0])]
		var stats: PackedFloat32Array = pairs[key][arm]
		var tick := SimChoices.at(r, SimChoices.R_TICK)
		stats[0] += 1.0
		stats[1] += 1.0 if (row["shot"] or row["goal"]) else 0.0
		stats[2] += float(row["end_x"]) - SimChoices.progress_of(r)
		stats[3] += 1.0 if float(int(row["last"]) - tick) >= TIE_KEPT * float(SimConsts.TICK_HZ) else 0.0
		stats[4] += p_played

	print("\nThe coin the softmax tossed  (%d of %d decisions were near-ties)" % [
		_tie_total(pairs), considered])
	var keys := pairs.keys()
	keys.sort_custom(func(x, y): return _tie_n(pairs[x]) > _tie_n(pairs[y]))
	var printable := 0
	for key in keys:
		if pairs[key][0][0] >= TIE_MIN_ARM and pairs[key][1][0] >= TIE_MIN_ARM:
			printable += 1
	if printable == 0:
		# A bare header over nothing reads as a broken block. The measurement is
		# fine; the run is short.
		print("  none of the %d pairs has %d in both arms yet — this wants a full-length match"
			% [keys.size(), TIE_MIN_ARM])
		return
	print("  %-22s %8s %6s %11s %12s %10s %7s" % [
		"between", "played", "n", "-> a shot", "ground on", "kept 3 s", "p"])
	var dropped := 0
	for key in keys:
		var arms: Array = pairs[key]
		var lo: int = int(key) / 100
		var hi: int = int(key) % 100
		if arms[0][0] < TIE_MIN_ARM or arms[1][0] < TIE_MIN_ARM:
			dropped += 1
			continue
		var label := "%s v %s" % [SimDebug.ACTION_NAMES[lo], SimDebug.ACTION_NAMES[hi]]
		var thin: bool = arms[0][0] < TIE_SOLID or arms[1][0] < TIE_SOLID
		for arm in 2:
			var s: PackedFloat32Array = arms[arm]
			print("  %-22s %8s %6d %10.1f%% %+11.1f m %9.0f%% %7.2f  %s" % [
				label if arm == 0 else "", SimDebug.ACTION_NAMES[lo if arm == 0 else hi],
				int(s[0]), 100.0 * s[1] / s[0], s[2] / s[0], 100.0 * s[3] / s[0], s[4] / s[0],
				"noisy at n=%d" % int(s[0]) if thin else "",
			])
			label = ""
	if dropped > 0:
		print("  and %d pairs under %d in an arm, not printed" % [dropped, TIE_MIN_ARM])


static func _tie_n(arms: Array) -> float:
	return arms[0][0] + arms[1][0]


static func _tie_total(pairs: Dictionary) -> int:
	var n := 0.0
	for key in pairs:
		n += _tie_n(pairs[key])
	return int(n)


## The chain from having the ball to scoring, one link at a time.
##
## The block to reach for when a change went in, the goals did not move, and
## nobody can say where it stopped. A count of shots says the attack failed; this
## says which link failed, and the links have different owners.
##
## **The stages are shares of the population, not nested subsets**, and the first
## version of this got that wrong in the direction that matters. Counted as a strict
## funnel -- each stage only reached through the one above -- a shot struck from
## outside the penalty area was stopped at the box row and never counted, and the
## chain printed 8 shots against the 14 the block above it had just reported. An
## instrument that disagrees with the one beside it is the one that is wrong.
##
## So each stage is counted on its own within the population the first row defines,
## and both columns are printed: the share of the whole, and the share of the row
## above. **The second can pass 100%**, and where it does it is telling you the
## stages genuinely overlap rather than nest -- this engine shooting from outside
## the box, or a regain reaching the final third quicker than three seconds.
const CHAIN_SHOT := [
	"had the ball", "into the middle third", "into the final third",
	"into the penalty area", "a shot", "on target", "a goal",
]
## The counter, which is a different chain with a different first link. It is here
## because `--ablate` said `break_bias` -- the whole counter-attacking prior, a 2.6x
## multiplier -- had never once changed which option was played, so this is where to
## look for what a regain actually turns into. `The two seconds after a regain` is
## the same question asked of the window rather than of the spell.
const CHAIN_REGAIN := [
	"won it back in play", "still had it after 3 s", "out of their own third",
	"into the final third", "a shot",
]

## The two chains that start at a decision rather than at a spell, and the reason
## `SimChoices` records which kinds were generated at all.
##
## Their first three links are invisible to every other instrument here. A cross
## that was never a candidate and a cross that was scored and beaten are the same
## absence in every count in the project, and they are different jobs: the first is
## `_add_passes` not offering it in a situation that called for it, the second is
## what it is worth once offered. A crossable moment that produced nothing leaves no
## event in the log at all, so nothing reading the log can find it.
##
## The population is a decision, not a spell, so a move offering three crossable
## moments counts three times and its outcome is counted three times with it. That
## is the right weighting for "of the moments that called for a cross, how many
## became one" and the wrong one for counting crosses; `Passes by kind` does that.
## Everything from `then ...` on is conditional on the act having been played *and*
## on happening after it -- `CHAIN_GATE` is that stage. Counted the way the spell
## chains are, over the whole population, the cross chain reported 22 spells
## reaching the area against 5 crosses played, which is 440% and is measuring
## attacks that never crossed at all.
const CHAIN_CROSS := [
	"wide in their half", "a cross was offered", "it scored best", "it was played",
	"then into the area", "then a shot", "then a goal",
]
const CHAIN_BEHIND := [
	"a runner in behind", "a through ball offered", "it scored best", "it was played",
	"then the final third", "then into the area", "then a shot",
]
const CHAIN_GATE := 3
## What counts as wide enough to be looking for a cross, as a fraction of the half
## width. The same 0.45 `SimDecision._add_passes` tests before calling a lofted ball
## a cross, so the situation and the candidate are drawn on one line.
const CROSS_WIDE := 0.45


## The chains as numbers rather than as a table, so a run can be saved and set
## against a later one. See `./run.sh chains`.
static func chain_counts(ctx: SimContext, table: Dictionary) -> Dictionary:
	var shot_chain := PackedInt32Array()
	var regain_chain := PackedInt32Array()
	shot_chain.resize(CHAIN_SHOT.size())
	regain_chain.resize(CHAIN_REGAIN.size())
	var fates := PackedInt32Array()
	fates.resize(POSS_FATES.size())
	for poss in table:
		var row: Dictionary = table[poss]
		fates[int(row["fate"])] += 1
		_advance(shot_chain, [
			true, row["middle"], row["final"], row["area"],
			row["shot"], row["on_target"], row["goal"]])
		# A spell that began in open play, which is what a regain is: the one
		# before it ended with the ball being taken rather than with a whistle.
		var before: Dictionary = table.get(int(poss) - 1, {})
		var open := not before.is_empty() and int(before["fate"]) >= PF_TACKLED
		_advance(regain_chain, [
			open, row["seconds"] >= TIE_KEPT, row["middle"], row["final"], row["shot"]])
	var chains: Array = [
		{"name": "Into a shot", "labels": CHAIN_SHOT, "counts": Array(shot_chain)},
		{"name": "After winning it back", "labels": CHAIN_REGAIN, "counts": Array(regain_chain)},
	]
	for chain in _decision_chains(ctx, table):
		chains.append(chain)
	return {"spells": table.size(), "chains": chains, "fates": Array(fates)}


## The cross and the ball in behind, off `SimChoices` rather than off the log. See
## `CHAIN_CROSS`.
static func _decision_chains(ctx: SimContext, table: Dictionary) -> Array:
	var cross := PackedInt32Array()
	var behind := PackedInt32Array()
	cross.resize(CHAIN_CROSS.size())
	behind.resize(CHAIN_BEHIND.size())
	if SimChoices.count() == 0:
		return []
	var wide := ctx.pitch.half_width * CROSS_WIDE
	for r in SimChoices.count():
		var row: Dictionary = table.get(SimChoices.at(r, SimChoices.R_POSS), {})
		if row.is_empty():
			continue
		var best := SimChoices.at(r, SimChoices.R_KIND_A)
		var played := SimChoices.at(r, SimChoices.R_PLAYED)
		var at := SimChoices.at(r, SimChoices.R_TICK)
		_advance(cross, [
			SimChoices.lateral_of(r) > wide and SimChoices.progress_of(r) > 0.0,
			SimChoices.generated(r, SimDecision.Action.CROSS),
			best == SimDecision.Action.CROSS,
			played == SimDecision.Action.CROSS,
			int(row["area_when"]) >= at, int(row["shot_when"]) >= at,
			int(row["goal_when"]) >= at], CHAIN_GATE)
		_advance(behind, [
			SimChoices.has_flag(r, SimChoices.F_RUNNER_BEHIND),
			SimChoices.generated(r, SimDecision.Action.THROUGH_BALL),
			best == SimDecision.Action.THROUGH_BALL,
			played == SimDecision.Action.THROUGH_BALL,
			int(row["final_when"]) >= at, int(row["area_when"]) >= at,
			int(row["shot_when"]) >= at], CHAIN_GATE)
	return [
		{"name": "The cross", "labels": CHAIN_CROSS, "counts": Array(cross)},
		{"name": "The ball in behind", "labels": CHAIN_BEHIND, "counts": Array(behind)},
	]


## Everything `./run.sh chains` saves for one match. Read off the same table the
## printed blocks read, so a saved run and a printed one cannot disagree.
static func measure(m: SimMatch) -> Dictionary:
	return chain_counts(m.ctx, _possession_table(m.ctx, m.ctx.telemetry.events))


static func _chains(ctx: SimContext, table: Dictionary) -> void:
	if table.is_empty():
		return
	var data := chain_counts(ctx, table)
	print("\nChains  (%d spells of possession; `of above` can pass 100%%, see the source)"
		% table.size())
	for chain in data["chains"]:
		_print_chain(chain["name"], chain["labels"], chain["counts"])


## Counts one row into every stage it reached.
##
## Stage 0 is the population: a chain that only applies to some rows says so there,
## and nothing outside it is counted at all. Everything up to `gate` is then counted
## on its own rather than through the stage above, because these stages overlap
## imperfectly and forcing them to nest loses the overlap -- which was a real
## finding both times it happened.
##
## `gate` is where that stops. Past it a stage only counts if the gate stage held,
## because "and then it reached the box" is a claim about the act at the gate and
## not about the population. A chain whose stages are all properties of the same
## spell leaves it at 0 and behaves as before.
static func _advance(counts: PackedInt32Array, stages: Array, gate: int = 0) -> void:
	if not bool(stages[0]):
		return
	var open := bool(stages[gate])
	for i in stages.size():
		if i > gate and not open:
			return
		if bool(stages[i]):
			counts[i] += 1


static func _print_chain(name: String, labels: Array, counts: Array) -> void:
	print("  %-28s %6s %8s %9s" % [name, "n", "of all", "of above"])
	for i in labels.size():
		var of_all := ""
		var of_previous := ""
		if counts[0] > 0:
			of_all = "%5.0f%%" % (100.0 * float(counts[i]) / float(counts[0]))
		if i > 0 and counts[i - 1] > 0:
			of_previous = "%5.0f%%" % (100.0 * float(counts[i]) / float(counts[i - 1]))
		print("    %-26s %6d %8s %9s" % [labels[i], counts[i], of_all, of_previous])


## Two saved runs, stage by stage. See `./run.sh chains`.
##
## **Read the conversion columns, not the counts.** A change that produces more
## possessions moves every count in the chain and has told you nothing about where
## it landed; a change that moves a *conversion* has changed what happens at that
## link, which is the question. The counts are printed because a conversion over
## nothing is noise and you need to see which rows have a population.
##
## The arrow marks the largest conversion moves. It is a pointer, not a verdict:
## these are single runs of a handful of seeds, and `n` beside it is what decides
## whether the move is real.
const DIFF_MARK := 4.0


static func chain_diff(before: Dictionary, after: Dictionary) -> void:
	print("Chain diff   before %s   after %s" % [_run_label(before), _run_label(after)])
	# The same seeds do not play the same amount of football once the engine has
	# changed -- a run came back 20 minutes against 23 -- so every count in the
	# `after` column is inflated by the extra. The conversions are immune, which is
	# why they are the column to read; the outcomes below are put on a rate.
	var b_min := float(before.get("minutes", 0.0))
	var a_min := float(after.get("minutes", 0.0))
	if b_min > 0.0 and absf(a_min - b_min) / b_min > 0.05:
		print("  the two runs are %.0f%% apart on match clock: read the conversions, not the counts"
			% (100.0 * absf(a_min - b_min) / b_min))
	var b_chains: Array = before.get("chains", [])
	var a_chains: Array = after.get("chains", [])
	for i in mini(b_chains.size(), a_chains.size()):
		var b: Dictionary = b_chains[i]
		var a: Dictionary = a_chains[i]
		var labels: Array = a["labels"]
		var bc: Array = b["counts"]
		var ac: Array = a["counts"]
		print("\n  %-26s %8s %8s %7s %11s %10s" % [
			a["name"], "before", "after", "n", "of above", "moved"])
		for k in labels.size():
			var b_n: int = int(bc[k]) if k < bc.size() else 0
			var a_n: int = int(ac[k]) if k < ac.size() else 0
			var conversion := ""
			var moved := ""
			if k > 0 and int(bc[k - 1]) > 0 and int(ac[k - 1]) > 0:
				var b_pc := 100.0 * float(b_n) / float(int(bc[k - 1]))
				var a_pc := 100.0 * float(a_n) / float(int(ac[k - 1]))
				conversion = "%3.0f%% -> %3.0f%%" % [b_pc, a_pc]
				moved = "%+6.1f %s" % [a_pc - b_pc, "<-" if absf(a_pc - b_pc) >= DIFF_MARK else ""]
			print("    %-24s %8d %8d %+7d %11s %10s" % [
				labels[k], b_n, a_n, a_n - b_n, conversion, moved])

	# The outcome the chains are an explanation of, so a run that moved nothing at
	# the end says so on one line instead of being read out of seven.
	var b_fates: Array = before.get("fates", [])
	var a_fates: Array = after.get("fates", [])
	if b_fates.is_empty() or a_fates.is_empty():
		return
	# Per 90 minutes of the match clock actually played, on the rule the batch
	# runner follows: two runs of the same seeds are not two runs of the same
	# length once the engine between them has changed.
	var b_rate := 90.0 / maxf(b_min, 0.01)
	var a_rate := 90.0 / maxf(a_min, 0.01)
	print("\n  %-26s %8s %8s %8s   per 90" % ["ended in", "before", "after", "moved"])
	for f in mini(b_fates.size(), a_fates.size()):
		if int(b_fates[f]) == 0 and int(a_fates[f]) == 0:
			continue
		var b_per := float(b_fates[f]) * b_rate
		var a_per := float(a_fates[f]) * a_rate
		print("    %-24s %8.1f %8.1f %+8.1f" % [POSS_FATES[f], b_per, a_per, a_per - b_per])


static func _run_label(run: Dictionary) -> String:
	return "%d matches, %.0f min, %d spells" % [
		int(run.get("matches", 0)), float(run.get("minutes", 0.0)), int(run.get("spells", 0))]


## Sums one match's measurement into a run. Chains add stage by stage; a run is
## several matches so that a diff is not reading one seed's weather.
static func accumulate(run: Dictionary, one: Dictionary, minutes: float) -> void:
	run["matches"] = int(run.get("matches", 0)) + 1
	run["minutes"] = float(run.get("minutes", 0.0)) + minutes
	run["spells"] = int(run.get("spells", 0)) + int(one["spells"])
	run["fates"] = _sum_into(run.get("fates", []), one["fates"])
	var chains: Array = run.get("chains", [])
	var from: Array = one["chains"]
	if chains.is_empty():
		for c in from:
			chains.append({"name": c["name"], "labels": c["labels"], "counts": []})
	for i in mini(chains.size(), from.size()):
		chains[i]["counts"] = _sum_into(chains[i]["counts"], from[i]["counts"])
	run["chains"] = chains


static func _sum_into(into: Array, add: Array) -> Array:
	while into.size() < add.size():
		into.append(0)
	for i in add.size():
		into[i] = int(into[i]) + int(add[i])
	return into


## What one spell produced, best outcome first. See `POSS_FATES`.
static func _poss_fate(ctx: SimContext, team: int, rows: Array) -> int:
	var fate := PF_OTHER
	for e in rows:
		var f := _fate_of_event(ctx, team, e)
		if f >= 0 and f < fate:
			fate = f
	return fate


static func _fate_of_event(ctx: SimContext, team: int, e: Dictionary) -> int:
	# `SHOT` and `GOAL` are deliberately absent: they are matched to a spell by team
	# and tick in `_possession_table`, not by the id they were logged under. See the
	# note there on why a shot is a content rather than an ending event.
	match int(e["ev"]):
		SimTelemetry.Ev.OFFSIDE:
			return PF_OFFSIDE
		SimTelemetry.Ev.FOUL:
			var fouler := int(e.get("p", -1))
			if fouler < 0 or fouler >= ctx.players.size():
				return -1
			return PF_FOUL_CONCEDED if ctx.players[fouler].team == team else PF_FOUL_WON
		SimTelemetry.Ev.SET_PIECE:
			# A restart to the other side is the ball given away; one to this side
			# is a corner or a throw kept, which is not the same outcome at all.
			return PF_SET_WON if int(e.get("team", -1)) == team else PF_OUT
		SimTelemetry.Ev.DUEL:
			var winner := int(e.get("winner", -1))
			if winner < 0 or winner >= ctx.players.size():
				return -1
			return PF_TACKLED if ctx.players[winner].team != team else -1
		SimTelemetry.Ev.PASS_OUTCOME:
			return -1 if bool(e.get("ok", false)) else PF_INTERCEPTED
		SimTelemetry.Ev.RECOVERY:
			var by := int(e.get("p", -1))
			if by < 0 or by >= ctx.players.size():
				return -1
			return PF_LOOSE if ctx.players[by].team != team else -1
	return -1


## Whether each term in the score ever changed what got played. Off unless
## `--ablate` was passed; see `SimAblation` for what the columns separate.
##
## The three columns to read in order are `in`, `on score`, `flips`. They fail
## differently and the fixes are in different files: a term at `in` 0% is not
## wired to the situation it was written for, one at `on score` ~0 is applied and
## does not vary, and one at `flips` 0% with a real `on score` is being beaten by
## something bigger. Only the third is a judgement call.
##
## `flips` is a share of the decisions the term applied to, not of every decision
## in the match, because a term can only change a pick where it is present at all.
static func _what_a_term_is_worth() -> void:
	if SimAblation.decisions <= 0.0:
		return
	print("\nWhere a term changes the decision  (%d decisions, one term neutralised at a time)"
		% int(SimAblation.decisions))
	print("  %-20s %-22s %6s %10s %9s %8s   %s" % [
		"term", "value where it applies", "in", "on score", "moves p", "flips", "commonest flip"])
	for term in SimAblation.TERMS:
		var applied := SimAblation.at(term, SimAblation.APPLIED)
		if applied <= 0.0:
			print("  %-20s %-22s %5.0f%%   %8s %9s %8s   %s" % [
				SimAblation.TERM_NAMES[term], "never applied", 0.0, "-", "-", "-", ""])
			continue
		var vn := SimAblation.at(term, SimAblation.VAL_N)
		var value := "-"
		if vn > 0.0:
			value = "%.3f - %.3f - %.3f" % [
				SimAblation.at(term, SimAblation.VAL_LO),
				SimAblation.at(term, SimAblation.VAL_SUM) / vn,
				SimAblation.at(term, SimAblation.VAL_HI)]
		print("  %-20s %-22s %5.0f%%   %8.5f %8.3f %7.1f%%   %s" % [
			SimAblation.TERM_NAMES[term], value,
			100.0 * applied / SimAblation.decisions,
			SimAblation.at(term, SimAblation.DSCORE) / applied,
			SimAblation.at(term, SimAblation.TVD) / applied,
			100.0 * SimAblation.at(term, SimAblation.FLIPS) / applied,
			SimAblation.flip_text(term),
		])


## And what the pass model made of the ones that lost: the five factors their
## `success` is a product of. A success of 0.05 is one number and could be any of
## a dozen faults; these five say which.
static func _why_the_pass_lost(events: Array) -> void:
	var any := false
	for kind in SimDecision.Action.size():
		if SimDecision.is_pass(kind) and SimDecision.lost_at(kind, SimDecision.LOST_N) > 0.0:
			any = true
	if not any:
		return
	# What each kind actually did, off the outcome events.
	var resolved := {}
	var ok := {}
	for e in events:
		if e["ev"] != SimTelemetry.Ev.PASS_OUTCOME:
			continue
		var k: int = e["kind"]
		resolved[k] = int(resolved.get(k, 0)) + 1
		if bool(e.get("ok", false)):
			ok[k] = int(ok.get(k, 0)) + 1
	print("\n  what the pass model made of them  (the factors of that success)")
	print("    %-11s %8s %8s %8s %9s %8s %9s %11s" % [
		"", "space", "in time", "lane", "control", "struck", "success", "completed"])
	for kind in SimDecision.Action.size():
		if not SimDecision.is_pass(kind):
			continue
		var n := SimDecision.lost_at(kind, SimDecision.LOST_N)
		if n < 1.0:
			continue
		var touch: int = SimDecision.PASS_TOUCH.get(kind, -1)
		var res: int = int(resolved.get(touch, 0))
		var rate := "  -" if res == 0 else "%9.0f%%" % (100.0 * float(ok.get(touch, 0)) / float(res))
		print("    %-11s %8.2f %8.2f %8.2f %9.2f %8.2f %9.2f %10s" % [
			SimDebug.ACTION_NAMES[kind],
			SimDecision.lost_at(kind, SimDecision.LOST_SPACE) / n,
			SimDecision.lost_at(kind, SimDecision.LOST_IN_TIME) / n,
			SimDecision.lost_at(kind, SimDecision.LOST_LANE) / n,
			SimDecision.lost_at(kind, SimDecision.LOST_CONTROL) / n,
			SimDecision.lost_at(kind, SimDecision.LOST_STRUCK) / n,
			SimDecision.lost_at(kind, SimDecision.LOST_SUCCESS) / n,
			rate,
		])
	print("    a ball in the air has no `in time` and no `lane`, and a ball on the floor has")
	print("    no `control`; each reads 1.00 rather than as a gap. See `receiver_touch`")
	print("\n  and of the ones it played  (`said` against `completed` is the calibration)")
	print("    %-11s %8s %8s %8s %9s %8s %9s %11s" % [
		"", "space", "in time", "lane", "control", "struck", "said", "completed"])
	for kind in SimDecision.Action.size():
		if not SimDecision.is_pass(kind):
			continue
		var n := SimDecision.lost_at(kind, SimDecision.PLAYED_N)
		if n < 1.0:
			continue
		var touch: int = SimDecision.PASS_TOUCH.get(kind, -1)
		var res: int = int(resolved.get(touch, 0))
		var rate := "  -" if res == 0 else "%9.0f%%" % (100.0 * float(ok.get(touch, 0)) / float(res))
		print("    %-11s %8.2f %8.2f %8.2f %9.2f %8.2f %9.2f %10s" % [
			SimDebug.ACTION_NAMES[kind],
			SimDecision.lost_at(kind, SimDecision.PLAYED_SPACE) / n,
			SimDecision.lost_at(kind, SimDecision.PLAYED_IN_TIME) / n,
			SimDecision.lost_at(kind, SimDecision.PLAYED_LANE) / n,
			SimDecision.lost_at(kind, SimDecision.PLAYED_CONTROL) / n,
			SimDecision.lost_at(kind, SimDecision.PLAYED_STRUCK) / n,
			SimDecision.lost_at(kind, SimDecision.PLAYED_MODEL) / n,
			rate,
		])
	# `said` against `completed` is the calibration, and it is the only thing here
	# that can say the model is wrong rather than merely strict.
	#
	# The pair to its left is not like-for-like and must not be read as if it were.
	# `success` is the best *rejected* candidate of its kind; `completed` is what
	# the ones that got played actually did, and those are the top of the same
	# distribution, so the right-hand column sits above the left by however hard
	# that kind is selected -- which for a through ball is fourteen rejections per
	# ball played. `said` is the same model on the same balls as `completed`, so a
	# gap there is the model disagreeing with the engine's own physics, which is a
	# defect rather than a tuning preference.
	print("    `success` is the best rejected ball of its kind and `completed` is what the")
	print("    played ones did, so the gap between them is mostly selection. `said` is the")
	print("    model on those same played balls: that pair is the calibration")
	_how_wrong_the_model_is()


## And the same calibration one ball at a time, which is what says *which* factor
## is wrong. See `SimDecision.CALIB_BUCKETS`.
##
## Two questions, and the table above can answer neither. Is the model ordered --
## does a ball it likes more actually arrive more often -- and is each factor
## charging for something the match resolves? A factor that reads the same on the
## balls that arrived and on the ones that did not is a constant wearing a
## probability's clothes, and its whole contribution is the amount the model is
## out by.
static func _how_wrong_the_model_is() -> void:
	var buckets := SimDecision.CALIB_BUCKETS.size() + 1
	var n := 0.0
	for kind in SimDecision.Action.size():
		for b in buckets:
			n += SimDecision.calib_at(kind, b, SimDecision.CAL_N)
	if n < 1.0:
		return
	print("\n  is it ordered?  (%d played balls that resolved, by what the model said)" % int(n))
	print("    %-13s %7s %8s %11s" % ["said", "balls", "said", "arrived"])
	for b in buckets:
		var count := 0.0
		var said := 0.0
		var ok := 0.0
		for kind in SimDecision.Action.size():
			count += SimDecision.calib_at(kind, b, SimDecision.CAL_N)
			said += SimDecision.calib_at(kind, b, SimDecision.CAL_SAID)
			ok += SimDecision.calib_at(kind, b, SimDecision.CAL_OK)
		if count < 1.0:
			continue
		var label := ""
		if b == 0:
			label = "under %.2f" % float(SimDecision.CALIB_BUCKETS[0])
		elif b == SimDecision.CALIB_BUCKETS.size():
			label = "%.2f up" % float(SimDecision.CALIB_BUCKETS[b - 1])
		else:
			label = "%.2f - %.2f" % [
				float(SimDecision.CALIB_BUCKETS[b - 1]), float(SimDecision.CALIB_BUCKETS[b])]
		print("    %-13s %7d %8.2f %10.0f%%" % [label, int(count), said / count, 100.0 * ok / count])
	print("\n  and which factor knew  (each kind, split by what became of the ball)")
	print("    %-11s %6s %9s %12s %9s" % ["", "balls", "arrived", "given away", "spread"])
	for kind in SimDecision.Action.size():
		if not SimDecision.is_pass(kind):
			continue
		var lost_n := SimDecision.calib_part_at(kind, false, -1)
		var ok_n := SimDecision.calib_part_at(kind, true, -1)
		if lost_n < 1.0 or ok_n < 1.0:
			continue
		print("    %s" % SimDebug.ACTION_NAMES[kind])
		for k in SimDecision.PARTS:
			var good := SimDecision.calib_part_at(kind, true, k) / ok_n
			var bad := SimDecision.calib_part_at(kind, false, k) / lost_n
			print("      %-9s %6d %9.2f %12.2f %9.2f" % [
				PART_NAMES[k], int(ok_n + lost_n), good, bad, good - bad])
	print("    a factor at zero spread decided nothing: it is a constant, and the model")
	print("    is out by it")


const PART_NAMES := ["space", "in time", "lane", "control", "struck"]


static func _cut_short_parts() -> PackedStringArray:
	var parts := PackedStringArray()
	for kind in range(1, SimOffBall.made.size()):
		var n: int = SimOffBall.made[kind]
		if n == 0:
			continue
		parts.append("%s %.0f%%" % [
			SimOffBall.KIND_NAMES[kind], 100.0 * float(SimOffBall.cut_short[kind]) / float(n)])
	return parts


static func _offering(ctx: SimContext) -> void:
	var total: int = 0
	for i in SimOffBall.made.size():
		total += SimOffBall.made[i]
	if total > 0:
		print("\nOffering for the ball  (how players made themselves available)")
		print("  %-10s %8s %9s %8s %10s %7s %9s %9s" % [
			"", "taken", "offered", "best w", "received", "shot", "mean run", "up-pitch"])
		for kind in range(1, SimOffBall.made.size()):
			var n: int = SimOffBall.made[kind]
			if n == 0:
				continue
			print("  %-10s %8d %8.0f%% %7.0f%% %9.0f%% %6.0f%% %8.1f m %+8.1f m" % [
				SimOffBall.KIND_NAMES[kind], n,
				100.0 * float(SimOffBall.offered[kind]) / float(n),
				100.0 * SimOffBall.weight[kind] / float(n),
				100.0 * float(SimOffBall.received[kind]) / float(n),
				100.0 * float(SimOffBall.shot[kind]) / float(n),
				SimOffBall.travel[kind] / float(n),
				SimOffBall.forward[kind] / float(n),
			])
		# `offered` is how many of these runs the man on the ball ever had on his
		# list; `best w` is the largest share of the softmax the run's own ball
		# ever held, averaged over every run. A run that is never offered and a run
		# that is offered and never chosen are different faults.
		#
		# `shot` is the possession ending in one while he ran, which is the attack
		# working, and `cut short` is what is left: an opponent took it off us
		# mid-stride. The two used to be one number and it read 81% for a run past
		# the last defender -- rising every time the engine got better at reaching
		# the box, which is an instrument measuring its own success.
		print("    cut short by a turnover: %s" % ", ".join(_cut_short_parts()))
		# What the ball to a man on each kind of run was priced at, averaged over
		# every candidate aimed at one. `gap` is how far below the winning score
		# it sat; the four columns before it say which half of the score did it.
		var cols := SimOffBall.PRICED_COLS
		if SimOffBall.priced.size() >= SimOffBall.KIND_NAMES.size() * cols:
			print("    and what the ball to him was priced at  (mean over the candidates aimed at him)")
			print("    %-10s %8s %7s %7s %7s %6s %9s   %6s %7s %5s %6s   %5s %6s" % [
				"", "balls", "succ", "gain", "loss", "bias", "gap", "space", "in time", "lane", "struck", "run", "marker"])
			for kind in range(1, SimOffBall.KIND_NAMES.size()):
				var b := kind * cols
				var n2 := SimOffBall.priced[b]
				if n2 <= 0.0:
					continue
				print("    %-10s %8d %7.2f %7.3f %7.3f %6.2f %9.4f   %6.2f %7.2f %5.2f %6.2f   %4.1fm %5.1fm" % [
					SimOffBall.KIND_NAMES[kind], int(n2),
					SimOffBall.priced[b + 1] / n2, SimOffBall.priced[b + 2] / n2,
					SimOffBall.priced[b + 3] / n2, SimOffBall.priced[b + 4] / n2,
					SimOffBall.priced[b + 5] / n2,
					SimOffBall.priced[b + 6] / n2, SimOffBall.priced[b + 7] / n2,
					SimOffBall.priced[b + 8] / n2, SimOffBall.priced[b + 9] / n2,
					SimOffBall.priced[b + 10] / n2, SimOffBall.priced[b + 11] / n2])
		_which_idea_he_had()

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


## Why a man making the run was never offered the ball.
##
## The population is a runner, not a decision: every teammate who is running in
## behind at the moment somebody decides, filed under the first gate that refused
## him. `Chains` says the run exists three times more often than the pass is
## offered and cannot say why, and the answer decides which layer the work is in —
## `_shortlist` keeping six of ten is a different job from a body-orientation
## range clamp, and both are upstream of everything `xt_at` is worth.
static func _why_no_ball_in_behind() -> void:
	var total := 0.0
	for i in SimDecision.behind_gate.size():
		total += SimDecision.behind_gate[i]
	if total < 1.0:
		return
	print("\nA man could be played in behind  (%d men ahead of the ball while somebody decided)" % int(total))
	var parts := PackedStringArray()
	for i in SimDecision.behind_gate.size():
		parts.append("%s %.0f%%" % [SimDecision.BEHIND_GATES[i],
			100.0 * SimDecision.behind_gate[i] / total])
	print("    %s" % ",  ".join(parts))
	print("    the first gate that refused him, in the order the gates are applied")
	var run_total := 0.0
	for i in SimDecision.behind_gate_run.size():
		run_total += SimDecision.behind_gate_run[i]
	if run_total >= 1.0:
		var rparts := PackedStringArray()
		for i in SimDecision.behind_gate_run.size():
			if SimDecision.behind_gate_run[i] > 0.0:
				rparts.append("%s %.0f%%" % [SimDecision.BEHIND_GATES[i],
					100.0 * SimDecision.behind_gate_run[i] / run_total])
		print("    of those on a committed run (%d):  %s" % [int(run_total), ",  ".join(rparts)])
	if SimDecision.behind_reach_n > 0:
		print("    the ball the range gate refused was %.0f m on average  (%d; the loft serves 24-55)" % [
			SimDecision.behind_reach_sum / float(SimDecision.behind_reach_n), SimDecision.behind_reach_n])


const BEHIND_BUCKETS := [12.0, 18.0, 24.0, 30.0, 1e9]
const BEHIND_LABELS := ["under 12 m", "12 - 18 m", "18 - 24 m", "24 - 30 m", "30 m +"]
## What became of one. `BF_FOR_HIM` is the only one that is the pass working:
## every other row is a ball that went somewhere, including the ones the log
## files as completed.
const BEHIND_FATES := [
	"the man it was for", "another teammate", "an opponent", "nobody at all",
]
const BF_FOR_HIM := 0
const BF_MATE := 1
const BF_THEM := 2
const BF_NOBODY := 3


## The ball played in behind, as a strike rather than as a choice.
##
## `Passes by kind` gives it one mean length and one completion rate, and neither
## can see the thing the eye sees first: a ball in behind is aimed *past* a man on
## purpose, so whether it was a good ball is not "did it reach a teammate" but
## "was it hit at a weight he could run onto". Those come apart completely. A
## through ball blasted 30 m into the channel and collected by the keeper is
## resolved, is not completed, and looks in every count exactly like one cut out
## by a defender — and the fixes are in different places.
##
## Three columns carry it, and they are all ratios against the receiver rather
## than absolute numbers:
##
##   `arrives` against the pace he runs at. The ball's speed as it reaches the aim
##   point. Above his top speed it is a ball he cannot catch even with a clear run
##   at it, whatever else was true of the pass.
##   `aimed ahead` against `he covers`. How far in front of him it was played,
##   against how far he can get while it is travelling. Over 1.0 is a ball aimed
##   at a yard he will not reach.
##   `reached him` — the intended man, not any teammate. `Passes by kind` counts a
##   through ball scuffed to the nearest centre back's feet as a completion.
##
## Every quantity is off the strike itself (`struck`, `lead`, `dist` on the
## attempt) rather than reconstructed from the 5 Hz trace, which at 16 m/s moves
## three metres between samples.
static func _the_ball_in_behind(ctx: SimContext, events: Array) -> void:
	var n := BEHIND_LABELS.size()
	var count := PackedInt32Array(); count.resize(n)
	var length := PackedFloat32Array(); length.resize(n)
	var struck := PackedFloat32Array(); struck.resize(n)
	var arrives := PackedFloat32Array(); arrives.resize(n)
	var lead := PackedFloat32Array(); lead.resize(n)
	var covers := PackedFloat32Array(); covers.resize(n)
	var got_it := PackedInt32Array(); got_it.resize(n)
	var fates := PackedInt32Array(); fates.resize(BEHIND_FATES.size())
	var too_fast := 0
	var too_far := 0
	var total := 0
	# Ground passes to feet, as the control. The same three columns on the pass
	# the engine plays six times as often are what say whether the numbers below
	# are a fact about the through ball or about every pass in the match.
	var feet := 0
	var feet_struck := 0.0
	var feet_arrives := 0.0
	var feet_lead := 0.0
	# And the ball over the top, which is the other ball in behind and is aimed by
	# a different rule. Only two of the columns mean anything for it -- a ball in
	# the air has no arrival pace on the grass -- but `aimed ahead` is the one that
	# matters and it is the one that says whether the ball was put in front of him
	# or dropped on his head.
	var over := 0
	var over_lead := 0.0
	var over_got := 0

	# Attempt to outcome by passer, oldest first: the same join `_passing_quality`
	# makes, and for the same reason. An attempt that never resolves -- the ball
	# that runs out of play, which is most of what is wrong here -- would
	# otherwise shift every pairing after it onto somebody else's pass.
	var pending := {}
	var rows := []
	for e in events:
		var ev: int = e["ev"]
		if ev == SimTelemetry.Ev.PASS_ATTEMPT and e.has("struck"):
			var p: int = e["p"]
			if not pending.has(p):
				pending[p] = []
			pending[p].append(rows.size())
			rows.append({"e": e, "receiver": -1, "ok": false})
		elif ev == SimTelemetry.Ev.PASS_OUTCOME:
			var p2: int = e["p"]
			if pending.has(p2) and not pending[p2].is_empty():
				var idx: int = pending[p2].pop_front()
				rows[idx]["receiver"] = int(e.get("receiver", -1))
				rows[idx]["ok"] = bool(e.get("ok", false))

	for rec in rows:
		var e: Dictionary = rec["e"]
		var kind := int(e["kind"])
		var d: float = maxf(float(e.get("dist", 0.0)), 0.6)
		var v: float = float(e.get("struck", 0.0))
		var travel: float = ctx.ballistics.ground_travel_time(d, v, ctx.env)
		# Off the two-phase law the strike was solved against, never off `travel`
		# and the blended decel -- see `SimBallistics.ground_pace_after`.
		var at_target: float = ctx.ballistics.ground_pace_after(v, d, ctx.env)
		if kind == SimTelemetry.Touch.GROUND_PASS:
			feet += 1
			feet_struck += v
			feet_arrives += at_target
			feet_lead += float(e.get("lead", 0.0))
			continue
		if kind == SimTelemetry.Touch.LOFTED_PASS:
			over += 1
			over_lead += float(e.get("lead", 0.0))
			if int(rec["receiver"]) == int(e.get("target", -1)):
				over_got += 1
			continue
		if kind != SimTelemetry.Touch.THROUGH_BALL:
			continue
		var to: int = int(e.get("target", -1))
		if to < 0 or to >= ctx.players.size():
			continue
		var mate := ctx.players[to]
		# His legs at the moment it was struck, off the event -- `max_speed` is
		# fatigue-capped and falls across a match, so reading it here would judge
		# a first-minute ball against tenth-minute legs.
		var top: float = maxf(float(e.get("rmax", 0.0)), 0.1)
		var reach: float = top * travel
		var ahead: float = float(e.get("lead", 0.0))

		var band := 0
		while band < n - 1 and d > BEHIND_BUCKETS[band]:
			band += 1
		total += 1
		count[band] += 1
		length[band] += d
		struck[band] += v
		arrives[band] += at_target
		lead[band] += ahead
		covers[band] += reach
		if at_target > top:
			too_fast += 1
		if ahead > reach:
			too_far += 1

		var receiver: int = int(rec["receiver"])
		var fate := BF_NOBODY
		if receiver == to:
			fate = BF_FOR_HIM
			got_it[band] += 1
		elif receiver >= 0 and receiver < ctx.players.size():
			fate = BF_MATE if ctx.players[receiver].team == mate.team else BF_THEM
		fates[fate] += 1

	if total == 0:
		return
	print("\nThe ball in behind, as a strike  (%d played)" % total)
	print("  %-12s %6s %7s %8s %9s %12s %10s %12s" % [
		"", "n", "share", "struck", "arrives", "aimed ahead", "he covers", "reached him"])
	for i in n:
		if count[i] == 0:
			continue
		var c := float(count[i])
		print("  %-12s %6d %6.0f%% %6.1f m/s %7.1f m/s %10.1f m %8.1f m %11.0f%%" % [
			BEHIND_LABELS[i], count[i], 100.0 * c / float(total),
			struck[i] / c, arrives[i] / c, lead[i] / c, covers[i] / c,
			100.0 * float(got_it[i]) / c,
		])
	if feet > 0:
		print("  %-12s %6d %7s %6.1f m/s %7.1f m/s %10.1f m %8s %12s" % [
			"to feet", feet, "-", feet_struck / float(feet),
			feet_arrives / float(feet), feet_lead / float(feet), "-", "-"])
	if over > 0:
		print("  %-12s %6d %7s %8s %9s %10.1f m %8s %11.0f%%" % [
			"over the top", over, "-", "-", "-", over_lead / float(over), "-",
			100.0 * float(over_got) / float(over)])
	print("  arriving faster than the man can run   %d of %d (%.0f%%)" % [
		too_fast, total, 100.0 * float(too_fast) / float(total)])
	print("  aimed further ahead than he can reach  %d of %d (%.0f%%)" % [
		too_far, total, 100.0 * float(too_far) / float(total)])
	var parts := PackedStringArray()
	for i in BEHIND_FATES.size():
		parts.append("%s %d (%.0f%%)" % [BEHIND_FATES[i], fates[i],
			100.0 * float(fates[i]) / float(total)])
	print("  who got it:  " + ",  ".join(parts))


## What the side that has just won the ball had to work with, over the two
## seconds it had won it.
##
## Every other block here answers over a match, and a match is the wrong
## population for the counter-attack: `secure`, `break_bias` and
## `SimOffBall.BREAK_RUN` all fire inside `SimDecision.REGAIN_WINDOW` and nothing
## measured them there. "The counter is not on" has three causes — nobody is
## *eligible* to run, they are eligible and the run scores badly, or they run and
## the man on the ball never picks them — they live in three different files, and
## Which idea a man off the ball was allowed to have, one gate at a time.
##
## `Offering for the ball` counts runs that were taken and cannot say why the ones
## that were not, were not. Three different failures produce the same low count and
## they are fixed in three different places:
##
##   `on the list` — the option existed at all on the grass he was standing on.
##   A kind that is rarely a candidate is a geometry or a trigger problem
##   (`_behind_point`, `_box_point` return `Vector3.INF`), and no score reaches it.
##   `share` — the mean share of the softmax it held while it was a candidate,
##   against `none`, which is holding station. A kind that is always on the list
##   and never above a few per cent is losing on value, and the thing to read next
##   is what it is scored with: `behind` and `box` are the two that skip
##   `_value_of` and so carry no `possession_value` at all.
##   `won` and `blocked` — it won the softmax, and then `QUOTA` refused it because
##   the team already had its two. That one is silent everywhere else in the
##   engine: the pick is filed and dropped without a trace.
##
## Read `won` against `taken` in the table above: they are the same event, so a
## gap between them is the quota and nothing else.
static func _which_idea_he_had() -> void:
	if SimOffBall.chose_men == 0:
		return
	print("\n  and which idea he was allowed to have  (%d men considered)" % SimOffBall.chose_men)
	print("    %-10s %10s %8s %8s %9s" % ["", "on the list", "share", "won", "blocked"])
	for kind in SimOffBall.chose_seen.size():
		var seen: int = SimOffBall.chose_seen[kind]
		if seen == 0:
			continue
		print("    %-10s %9.1f%% %7.1f%% %8d %9d" % [
			SimOffBall.KIND_NAMES[kind],
			100.0 * float(seen) / float(SimOffBall.chose_men),
			100.0 * SimOffBall.chose_share[kind] / float(seen),
			SimOffBall.chose_won[kind],
			SimOffBall.chose_blocked[kind],
		])
	print("    `share` is the mean over the passes the option was on the list for, so")
	print("    a kind that is rarely listed can still read a healthy one")
	_why_not(SimOffBall.BEHIND_WHY, SimOffBall.behind_why, "the run in behind")
	if SimOffBall.behind_gap_n > 0:
		print("    and the run aimed %.1f m wide of the nearest man on the line  (%d points)" % [
			SimOffBall.behind_gap_sum / float(SimOffBall.behind_gap_n), SimOffBall.behind_gap_n])
	_why_not(SimOffBall.BOX_WHY, SimOffBall.box_why, "the run into the box")
	_why_not(SimOffBall.WIDE_WHY, SimOffBall.wide_why, "the outlet wide")
	# Three authored points are three positions only if the men spread over them.
	var box_runs := 0
	for c in SimOffBall.box_target:
		box_runs += c
	if box_runs > 0:
		var where := PackedStringArray()
		for i in SimOffBall.box_target.size():
			where.append("%s %.0f%%" % [SimOffBall.BOX_TARGETS[i],
				100.0 * float(SimOffBall.box_target[i]) / float(box_runs)])
		print("    and which point he went to:  %s  (%d runs)" % [
			",  ".join(where), box_runs])
	# And whether the timing on that run is running at all. Zero on both is the
	# mechanic dead rather than the mechanic quiet.
	var ease_ticks := 0
	for c in SimOffBall.box_ease:
		ease_ticks += c
	var eased := PackedStringArray()
	for i in SimOffBall.box_ease.size():
		eased.append("%s %d" % [SimOffBall.BOX_EASE_NAMES[i], SimOffBall.box_ease[i]])
	print("    and while the ball was on the grass he was:  %s  (ticks)" % ",  ".join(eased))
	# The same timing for the show and the drift. Zero on both is the mechanic
	# dead rather than quiet.
	var met := PackedStringArray()
	for i in SimOffBall.meet_ease.size():
		met.append("%s %d" % [SimOffBall.MEET_EASE_NAMES[i], SimOffBall.meet_ease[i]])
	print("    and a show or drift was:  %s  (ticks)" % ",  ".join(met))
	# And how many of the runs above were a man changing his mind. A drift is the
	# one offer that can be abandoned (`SimOffBall._assign`), so this is the whole
	# population of it, and a zero is the mechanic dead rather than quiet.
	var switched := PackedStringArray()
	for i in SimOffBall.switched.size():
		if SimOffBall.switched[i] > 0:
			switched.append("%s %d" % [SimOffBall.KIND_NAMES[i], SimOffBall.switched[i]])
	print("    offers given up for a run instead:  %s" % (
		",  ".join(switched) if switched.size() > 0 else "none"))
	if ease_ticks == 0 and box_runs > 0:
		print("      -- runs were made and neither arm of the timing ran")


## And which test refused it, in the order the function applies them.
static func _why_not(names: Array, counts: PackedInt32Array, what: String) -> void:
	var total := 0
	for n in counts:
		total += n
	if total == 0:
		return
	var parts := PackedStringArray()
	for i in counts.size():
		if counts[i] > 0:
			parts.append("%s %.0f%%" % [names[i], 100.0 * float(counts[i]) / float(total)])
	print("    %s, first test failed:  %s" % [what, ",  ".join(parts)])


## `Offering for the ball` gives one number for all three.
##
## Read top to bottom, and stop at the first row that is wrong.
##
##   the first line is eligibility. `resting` is `SimOffBall._expire` charging
##   `REST_SECONDS` — up to 10 s for a run in behind — the instant possession
##   changes, which is the instant before this window opens.
##   the second is scoring: of the men who were considered, how many took a run.
##   the third is the carrier: what he made of the runs that were taken.
##   the fourth is `break_on` itself, which both multipliers are lerped through.
static func _after_the_regain() -> void:
	if SimOffBall.regain_passes.size() != 2 or SimOffBall.regain_passes[1] == 0:
		return
	var kinds := SimOffBall.KIND_NAMES.size()
	print("\nThe two seconds after a regain  (`secure`, `break_bias` and BREAK_RUN all fire here)")
	print("  the side in possession, per man per assignment pass")
	print("  %-14s %8s %9s %9s %9s %9s %11s" % [
		"", "passes", "running", "resting", "too far", "a pattern", "considered"])
	for w in 2:
		var passes := float(SimOffBall.regain_passes[w])
		if passes == 0.0:
			continue
		var live := 0
		var resting := 0
		for kind in kinds:
			live += SimOffBall.regain_live[w * kinds + kind]
			resting += SimOffBall.regain_resting[w * kinds + kind]
		print("  %-14s %8d %9.2f %9.2f %9.2f %9.2f %11.2f" % [
			"in the window" if w == 1 else "the rest of it", int(passes),
			float(live) / passes, float(resting) / passes,
			float(SimOffBall.regain_far[w]) / passes,
			float(SimOffBall.regain_held[w]) / passes,
			float(SimOffBall.regain_considered[w]) / passes,
		])
		if resting > 0:
			var parts := PackedStringArray()
			for kind in range(1, kinds):
				var n: int = SimOffBall.regain_resting[w * kinds + kind]
				if n > 0:
					parts.append("%s %.0f%%" % [SimOffBall.KIND_NAMES[kind],
						100.0 * float(n) / float(resting)])
			print("      resting from %s, %.1f s still to serve" % [
				", ".join(parts), SimOffBall.regain_rest_left[w] / float(resting)])
	var cuts := 0
	var served := 0.0
	var cut_parts := PackedStringArray()
	for kind in range(1, kinds):
		cuts += SimOffBall.cut_n[kind]
		served += SimOffBall.cut_served[kind]
		if SimOffBall.cut_n[kind] > 0:
			cut_parts.append("%s %.0f%%" % [SimOffBall.KIND_NAMES[kind],
				100.0 * SimOffBall.cut_served[kind] / float(SimOffBall.cut_n[kind])])
	if cuts > 0:
		print("  a run a turnover ended had served %.0f%% of its window  (%s)" % [
			100.0 * served / float(cuts), ", ".join(cut_parts)])
		print("    and is charged that share of `REST_SECONDS`, not the whole of it")

	var born := 0
	for kind in SimOffBall.KIND_NAMES.size():
		born += SimOffBall.born[kind]
	if born > 0:
		print("  and the runs that were begun in the window")
		print("    %-10s %8s %9s %8s %10s" % ["", "taken", "offered", "best w", "received"])
		for kind in range(1, SimOffBall.KIND_NAMES.size()):
			var n: int = SimOffBall.born[kind]
			if n == 0:
				continue
			print("    %-10s %8d %8.0f%% %7.0f%% %9.0f%%" % [
				SimOffBall.KIND_NAMES[kind], n,
				100.0 * float(SimOffBall.born_offered[kind]) / float(n),
				100.0 * SimOffBall.born_weight[kind] / float(n),
				100.0 * float(SimOffBall.born_received[kind]) / float(n),
			])
	else:
		print("  no run of any kind was begun inside the window")

	if SimDecision.break_in_window > 0.0:
		var w := SimDecision.break_in_window
		print("  break_on, over the %.0f decisions taken inside it (%.0f%% of all %.0f)" % [
			w, 100.0 * w / maxf(SimDecision.break_decisions, 1.0), SimDecision.break_decisions])
		print("    mean %.2f, their line priced at %.2f x, and `secure` on the square ball %.2f x" % [
			SimDecision.break_on_sum / w, SimDecision.break_exposed_sum / w,
			SimDecision.break_secure_sum / w])
		var cells := PackedStringArray()
		for i in SimDecision.break_hist.size():
			var label := ""
			if i == 0:
				label = "under %.2f" % float(SimDecision.BREAK_BUCKETS[0])
			elif i == SimDecision.BREAK_BUCKETS.size():
				label = "%.2f up" % float(SimDecision.BREAK_BUCKETS[i - 1])
			else:
				label = "%.2f-%.2f" % [float(SimDecision.BREAK_BUCKETS[i - 1]),
					float(SimDecision.BREAK_BUCKETS[i])]
			cells.append("%s %.0f%%" % [label, 100.0 * float(SimDecision.break_hist[i]) / w])
		print("    %s" % "   ".join(cells))


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
	# And the same four numbers over the seconds after a regain, which is a
	# different question with the same shape: a side that has just won it back and
	# has nothing safe on is a side that gives it straight back. See
	# `_after_the_regain`.
	var win_mask := _regain_mask(ctx, trace.size())
	var win_samples := 0
	var win_none := 0
	var win_safe := 0
	var win_forward := 0

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
		if i < win_mask.size() and win_mask[i] == team + 1:
			win_samples += 1
			win_safe += safe
			if safe == 0:
				win_none += 1
			if safe_fwd > 0:
				win_forward += 1

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
	if win_samples > 0:
		var w := float(win_samples)
		print("  and in the %.1f s after a regain: %.1f safe, none at all %3.0f%%, a forward one %3.0f%%" % [
			SimDecision.REGAIN_WINDOW, float(win_safe) / w,
			100.0 * float(win_none) / w, 100.0 * float(win_forward) / w,
		])


## Which trace samples fall inside a regain window, and for whom: 0 for none,
## `team + 1` for the side that has just won it back.
##
## Off the recovery events, so the window here is the same one
## `SimDecision.regain_urgency` opens — a sample is in it when the side holding
## the ball won it back within `REGAIN_WINDOW`. A sample the other side holds is
## not in anybody's window, which is why the mask carries the team rather than a
## bit.
static func _regain_mask(ctx: SimContext, samples: int) -> PackedInt32Array:
	var mask := PackedInt32Array()
	mask.resize(samples)
	var window := int(SimDecision.REGAIN_WINDOW * float(SimConsts.TICK_HZ))
	for e in ctx.telemetry.events:
		if e["ev"] != SimTelemetry.Ev.RECOVERY:
			continue
		var from := int(ceil(float(e["t"]) / float(SimConsts.TRACE_TICKS)))
		var to := int(float(int(e["t"]) + window) / float(SimConsts.TRACE_TICKS))
		for i in range(maxi(from, 0), mini(to + 1, samples)):
			mask[i] = int(e["team"]) + 1
	return mask


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


## Where each team's lines sit, and whether they move with the ball.
##
## The question is one the engine cannot answer about itself. `shape_position`
## slides every station with play by construction, so the code always looks as
## though the shape responds; what it cannot say is by how much, once the ball
## pull, the tactical line height, the phase shift and the pitch clamp have all
## been applied on top of each other and the players have run at the result with
## a deadband and a speed cap.
##
## Read off the trace, so it owes the sim nothing. The defensive line is the
## second-deepest outfielder, because the deepest is often a full-back who has
## not got back yet and taking the minimum reads one straggler as the whole line.
## `highest` is the furthest man up. Both are metres from that team's own goal,
## and each sample counts once for each team, bucketed by where the ball was for
## that team.
##
## What football does, for the eye that has not got a metre stick: with the ball
## in your own third the line sits around 20 to 25 m out, in the middle third
## around 30 to 35, and with the ball in theirs a side that is pressing plays it
## at 40 to 50. The team is 30 to 40 m long through most of that and stretches
## further only in transition. A line that reads the same number in all three
## rows is a shape that is not responding to anything, whatever the code says.
static func _team_lines(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var swap_tick := 1 << 30
	for e in ctx.telemetry.events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", -1)) == SimConsts.Period.SECOND_HALF:
			swap_tick = int(e["t"])
			break
	var full := ctx.pitch.half_length * 2.0
	var n := PackedFloat32Array()
	var line_sum := PackedFloat32Array()
	var high_sum := PackedFloat32Array()
	n.resize(3)
	line_sum.resize(3)
	high_sum.resize(3)
	for i in trace.size():
		var sample := trace[i]
		if sample.size() != ctx.players.size() + 1:
			continue
		var flip: float = 1.0 if i * SimConsts.TRACE_TICKS >= swap_tick else -1.0
		for team in 2:
			var dir := ctx.pitch.attack_dir(team) * flip
			var deepest := INF
			var line := INF
			var high := -INF
			for pid in ctx.players.size():
				var p := ctx.players[pid]
				if p.is_keeper or not p.on_pitch or p.team != team:
					continue
				var up: float = sample[pid + 1].x * dir + ctx.pitch.half_length
				high = maxf(high, up)
				if up < deepest:
					line = deepest
					deepest = up
				elif up < line:
					line = up
			if is_inf(line) or is_inf(high):
				continue
			var ball_up: float = sample[0].x * dir + ctx.pitch.half_length
			var third: int = clampi(int(ball_up / full * 3.0), 0, 2)
			n[third] += 1.0
			line_sum[third] += line
			high_sum[third] += high
	var total := n[0] + n[1] + n[2]
	if total <= 0.0:
		return
	print("\nThe lines  (off the trace, both teams, metres from their own goal)")
	print("  %-14s %8s %10s %9s %10s" % ["ball in", "line", "highest", "length", "of play"])
	var names := ["own third", "middle third", "their third"]
	for t in 3:
		if n[t] <= 0.0:
			continue
		print("  %-14s %7.0f m %9.0f m %8.0f m %9.0f%%" % [
			names[t], line_sum[t] / n[t], high_sum[t] / n[t],
			(high_sum[t] - line_sum[t]) / n[t], 100.0 * n[t] / total,
		])


## How close counts as part of the clump around the ball.
const WIDTH_NEAR := 12.0


## The width of the side in possession, and the crowd around its own ball.
##
## The other axis of `_team_lines`, and the one the owner watches collapse: a
## side building up that has lost its width reads as a clump of shirts around
## the carrier in the middle of its own half, and every lane out of the clump
## is a lane through it. The lines cannot see it — a team can hold 40 m of
## length with all ten men in the central channel.
##
## Off the trace like the lines, so it owes the sim nothing. Possession is
## inferred the way `_giving_up_ground` infers it — the man within `OWN_BALL`
## of the ball — so dead-ball and in-flight samples drop out. `width` is the
## z-extent of the possessing side's outfielders; `crowd` is how many of them
## stand within `WIDTH_NEAR` of the ball, carrier included.
##
## For the eye without a metre stick: a real side building out occupies 40 to
## 55 m of the 68, and two or three shirts near the ball is support while five
## is the collapse.
static func _team_width(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var swap := _trace_swap(ctx)
	var full := ctx.pitch.half_length * 2.0
	var n := PackedFloat32Array()
	var width_sum := PackedFloat32Array()
	var crowd_sum := PackedFloat32Array()
	n.resize(3)
	width_sum.resize(3)
	crowd_sum.resize(3)
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
		if carrier < 0:
			continue
		var team := ctx.players[carrier].team
		var flip: float = 1.0 if i * SimConsts.TRACE_TICKS >= swap else -1.0
		var dir := ctx.pitch.attack_dir(team) * flip
		var lo := INF
		var hi := -INF
		var crowd := 0.0
		for pid in ctx.team_players[team]:
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var z: float = sample[pid + 1].z
			lo = minf(lo, z)
			hi = maxf(hi, z)
			if SimConsts.horizontal_length(sample[pid + 1] - ball) < WIDTH_NEAR:
				crowd += 1.0
		if is_inf(lo):
			continue
		var ball_up: float = ball.x * dir + ctx.pitch.half_length
		var third: int = clampi(int(ball_up / full * 3.0), 0, 2)
		n[third] += 1.0
		width_sum[third] += hi - lo
		crowd_sum[third] += crowd
	var total := n[0] + n[1] + n[2]
	if total <= 0.0:
		return
	print("\nThe width  (off the trace, the side in possession; crowd is its men within %.0f m of the ball)" % WIDTH_NEAR)
	print("  %-14s %8s %8s %10s" % ["ball in", "width", "crowd", "of samples"])
	var names := ["own third", "middle third", "their third"]
	for t in 3:
		if n[t] <= 0.0:
			continue
		print("  %-14s %7.0f m %8.1f %9.0f%%" % [
			names[t], width_sum[t] / n[t], crowd_sum[t] / n[t], 100.0 * n[t] / total,
		])


## The pitch is cut into this many channels across and bands along, and the ten
## outfielders are counted into the grid. Five and three because that is how a
## coach draws it: two half-spaces, two flanks, a middle, and three thirds.
const GRID_CHANNELS := 5
const GRID_BANDS := 3
## Two shirts closer than this are standing on each other. A footballer's
## nearest teammate is rarely inside it and never for long.
const CLOSE_MATE := 8.0


## The clump, as the eye sees it: how far a man is from the nearest shirt of his
## own colour, how much of the pitch his side is standing on, and how many
## bodies of both colours are inside one circle round the ball.
##
## `The width` measures the possessing side's z-extent, which two men on either
## touchline satisfy while the other eight stand in a ring round the carrier.
## This is the density question instead, and it is asked of both sides, because
## what the owner watches is twenty-two shirts converging and a defending side
## swarming is half of that.
##
## `nearest mate` is the mean over the ten outfielders of the distance to the
## closest of the other nine. `cells` is how many of the %d x %d grid cells the
## ten are spread across, and `biggest` the most of them in any one cell -- a
## side properly spread occupies eight or nine cells with two in the fullest, a
## clump three or four with five. `crowd` counts every outfielder of both sides
## within `WIDTH_NEAR` of the ball, which is the picture rather than one team's
## half of it.
##
## Off the trace, so it owes the sim nothing. Possession is inferred the way
## `_team_width` infers it, so dead-ball and in-flight samples drop out.
static func _the_clump(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	if trace.size() < 2:
		return
	var full := ctx.pitch.half_length * 2.0
	var wide := ctx.pitch.half_width * 2.0
	# Row 0 is the side in possession, row 1 the side without it.
	var n := PackedFloat32Array()
	var mate_sum := PackedFloat32Array()
	var close_sum := PackedFloat32Array()
	var cells_sum := PackedFloat32Array()
	var biggest_sum := PackedFloat32Array()
	var crowd_sum := PackedFloat32Array()
	n.resize(2)
	mate_sum.resize(2)
	close_sum.resize(2)
	cells_sum.resize(2)
	biggest_sum.resize(2)
	crowd_sum.resize(2)
	var both_sum := 0.0
	var both_n := 0.0
	var counts := PackedInt32Array()
	counts.resize(GRID_CHANNELS * GRID_BANDS)
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
		if carrier < 0:
			continue
		var holder := ctx.players[carrier].team
		var both := 0.0
		for team in 2:
			var row: int = 0 if team == holder else 1
			for c in counts.size():
				counts[c] = 0
			var mates := 0.0
			var mate_total := 0.0
			var close := 0.0
			var crowd := 0.0
			for pid in ctx.team_players[team]:
				var p := ctx.players[pid]
				if p.is_keeper or not p.on_pitch:
					continue
				var at: Vector3 = sample[pid + 1]
				var nearest := INF
				for other in ctx.team_players[team]:
					if other == pid:
						continue
					var q := ctx.players[other]
					if q.is_keeper or not q.on_pitch:
						continue
					nearest = minf(nearest, SimConsts.horizontal_length(sample[other + 1] - at))
				if not is_inf(nearest):
					mates += 1.0
					mate_total += nearest
					if nearest < CLOSE_MATE:
						close += 1.0
				# The grid is read in pitch coordinates and never flipped: which
				# end a side is attacking does not change how spread out it is.
				var cx: int = clampi(int((at.x + ctx.pitch.half_length) / full * float(GRID_BANDS)), 0, GRID_BANDS - 1)
				var cz: int = clampi(int((at.z + ctx.pitch.half_width) / wide * float(GRID_CHANNELS)), 0, GRID_CHANNELS - 1)
				counts[cx * GRID_CHANNELS + cz] += 1
				if SimConsts.horizontal_length(at - ball) < WIDTH_NEAR:
					crowd += 1.0
					both += 1.0
			if mates <= 0.0:
				continue
			var used := 0.0
			var biggest := 0.0
			for c in counts.size():
				if counts[c] > 0:
					used += 1.0
				biggest = maxf(biggest, float(counts[c]))
			n[row] += 1.0
			mate_sum[row] += mate_total / mates
			close_sum[row] += close
			cells_sum[row] += used
			biggest_sum[row] += biggest
			crowd_sum[row] += crowd
		both_sum += both
		both_n += 1.0
	if n[0] <= 0.0:
		return
	print("\nThe clump  (off the trace, both sides; %d cells of a %d x %d grid, %.0f m circle round the ball)"
		% [GRID_CHANNELS * GRID_BANDS, GRID_BANDS, GRID_CHANNELS, WIDTH_NEAR])
	print("  %-14s %13s %11s %8s %9s %8s" % [
		"side", "nearest mate", "under %.0f m" % CLOSE_MATE, "cells", "biggest", "crowd",
	])
	var names := ["in possession", "defending"]
	for row in 2:
		if n[row] <= 0.0:
			continue
		print("  %-14s %11.1f m %10.1f %8.1f %9.1f %8.1f" % [
			names[row], mate_sum[row] / n[row], close_sum[row] / n[row],
			cells_sum[row] / n[row], biggest_sum[row] / n[row], crowd_sum[row] / n[row],
		])
	if both_n > 0.0:
		print("  and %.1f of the 20 outfielders stand inside that one circle" % (both_sum / both_n))


## Distance from a man's own station at which he has stopped holding it. Wide
## enough that the shape's own deadband and the jog back to it are inside it.
const OFF_STATION := 8.0

## Above this a station is moving faster than the man on it can run flat out, so
## whatever it is doing is not something he can follow. A shade under the
## engine's own top speed, which is 7.5 m/s before sharpness.
const SPRINT_SPEED := 8.0


## How far the side is from the shape it was given, and which errand took it
## there.
##
## `The lines`, `The width` and `The clump` all say what the shape looked like.
## None of them can say whether that *was* the shape: `SimMovement.shape_position`
## slides every station with play, so a back four squeezed into the middle third
## may be exactly where the formation asked or nowhere near it, and both read the
## same off the trace. This is the only block that has both numbers side by side.
##
## The distance from the station splits in two and the split is the point.
## `pulled` is how far the errand moved his *target* off the formation's point --
## the shape being overridden. `behind` is how far he is from that target -- the
## shape being asked for and not reached. They add up to `off station`, and they
## are different faults with different fixes.
##
## The errand is stamped by the branch of `SimMovement._recompute_target` that
## took him, so an arm that stops firing stops appearing here -- which is
## `docs/DIAGNOSTICS.md` link 0, a counter on each arm of the branch.
##
## The reading: a side is holding a shape when most of its player-seconds are on
## `station` with a small `pulled`. A large `pulled` on a big share is a
## formation that is decoration; a large `behind` is one nobody can keep up with.
## The body against the run: the angle between each step and the hips, for
## every moving outfield player, by errand. Positions cannot see it -- a man
## shuffling sideways and a man running are one dot on the trace -- and it is
## the instrument for the body being its own state (`SimPlayer.look_target`):
## `side` and `back` are the shuffles and backpedals, and an errand whose men
## are mostly held is an errand paying the strafe cap.
static func _the_body(ctx: SimContext) -> void:
	var trace := ctx.telemetry.trace
	var facings := ctx.telemetry.facing_trace
	var errands := ctx.telemetry.errand_trace
	if trace.size() < 2 or facings.size() != trace.size() or errands.size() != trace.size():
		return
	var dt := float(SimConsts.TRACE_TICKS) / float(SimConsts.TICK_HZ)
	var arms := SimMovement.ERRAND_NAMES.size()
	var n := PackedFloat32Array()
	var angle_sum := PackedFloat32Array()
	var side := PackedFloat32Array()
	var back := PackedFloat32Array()
	n.resize(arms + 1)
	angle_sum.resize(arms + 1)
	side.resize(arms + 1)
	back.resize(arms + 1)
	for i in range(1, trace.size()):
		var sample := trace[i]
		var prev := trace[i - 1]
		if sample.size() != ctx.players.size() + 1 or prev.size() != sample.size():
			continue
		if facings[i].size() != ctx.players.size() or errands[i].size() != ctx.players.size():
			continue
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var step := sample[pid + 1] - prev[pid + 1]
			var v := SimConsts.horizontal_length(step) / dt
			if v < 0.4 or v > SimConsts.SPEED_MAX * 1.2:
				continue
			var off: float = absf(angle_difference(facings[i][pid], atan2(step.z, step.x)))
			var e: int = clampi(errands[i][pid], 0, arms - 1)
			for slot in [e, arms]:
				n[slot] += 1.0
				angle_sum[slot] += off
				if off > PI * 0.75:
					back[slot] += 1.0
				elif off > PI * 0.25:
					side[slot] += 1.0
	if n[arms] < 1.0:
		return
	print("\nThe body  (angle between the step and the hips, moving outfield players, off the 5 Hz trace)")
	print("  %-12s %8s %8s %6s %6s %6s" % ["", "samples", "forward", "side", "back", "mean"])
	for slot in arms + 1:
		if n[slot] < 1.0:
			continue
		var f: float = n[slot] - side[slot] - back[slot]
		print("  %-12s %8d %7.0f%% %5.0f%% %5.0f%% %5.0f\u00b0" % [
			SimMovement.ERRAND_NAMES[slot] if slot < arms else "all",
			int(n[slot]), 100.0 * f / n[slot], 100.0 * side[slot] / n[slot],
			100.0 * back[slot] / n[slot], rad_to_deg(angle_sum[slot] / n[slot])])


static func _holding_shape(ctx: SimContext) -> void:
	var shapes := ctx.telemetry.shape_trace
	var targets := ctx.telemetry.target_trace
	var errands := ctx.telemetry.errand_trace
	var trace := ctx.telemetry.trace
	if shapes.size() < 2 or shapes.size() != trace.size():
		return
	var dt := float(SimConsts.TRACE_TICKS) / float(SimConsts.TICK_HZ)
	var arms := SimMovement.ERRAND_NAMES.size()
	var n := PackedFloat32Array()
	var off_sum := PackedFloat32Array()
	var pull_sum := PackedFloat32Array()
	var behind_sum := PackedFloat32Array()
	var ball_sum := PackedFloat32Array()
	var station_ball_sum := PackedFloat32Array()
	var moved_sum := PackedFloat32Array()
	var station_moved_sum := PackedFloat32Array()
	var moved_n := PackedFloat32Array()
	var switched := PackedFloat32Array()
	var jumped := PackedFloat32Array()
	var pairs := PackedFloat32Array()
	var far := PackedFloat32Array()
	n.resize(arms)
	moved_sum.resize(arms)
	station_moved_sum.resize(arms)
	moved_n.resize(arms)
	switched.resize(arms)
	jumped.resize(arms)
	pairs.resize(arms)
	off_sum.resize(arms)
	pull_sum.resize(arms)
	behind_sum.resize(arms)
	ball_sum.resize(arms)
	station_ball_sum.resize(arms)
	far.resize(arms)
	var roles := SimRole.NAMES.size()
	var role_n := PackedFloat32Array()
	var role_off := PackedFloat32Array()
	var role_station := PackedFloat32Array()
	var role_far := PackedFloat32Array()
	role_n.resize(roles)
	role_off.resize(roles)
	role_station.resize(roles)
	role_far.resize(roles)
	for i in shapes.size():
		var sample := trace[i]
		var station := shapes[i]
		var target := targets[i]
		var arm := errands[i]
		if sample.size() != ctx.players.size() + 1 or station.size() != ctx.players.size():
			continue
		var ball := sample[0]
		for pid in ctx.players.size():
			var p := ctx.players[pid]
			if p.is_keeper or not p.on_pitch:
				continue
			var e: int = clampi(arm[pid], 0, arms - 1)
			var d := SimConsts.horizontal_length(sample[pid + 1] - station[pid])
			n[e] += 1.0
			off_sum[e] += d
			pull_sum[e] += SimConsts.horizontal_length(target[pid] - station[pid])
			behind_sum[e] += SimConsts.horizontal_length(sample[pid + 1] - target[pid])
			ball_sum[e] += SimConsts.horizontal_length(sample[pid + 1] - ball)
			station_ball_sum[e] += SimConsts.horizontal_length(station[pid] - ball)
			# How fast the point he is running at is itself running away. A target
			# that moves faster than a footballer cannot be occupied at any pace,
			# and then the gap to it is a fact about the target rather than about
			# him -- which is the difference between "he is too slow" and "he is
			# being sent somewhere new ten times a second".
			#
			# Measured only across pairs where he was on the same errand, because a
			# target that jumps when the errand changes is the errand changing, and
			# that is counted separately as `switched`. Mixed together, an arm that
			# is perfectly steady while it lasts reads as chaos because it keeps
			# being handed over.
			if i > 0 and targets[i - 1].size() == ctx.players.size():
				if errands[i - 1][pid] == arm[pid]:
					moved_sum[e] += SimConsts.horizontal_length(target[pid] - targets[i - 1][pid]) / dt
					var station_speed := SimConsts.horizontal_length(station[pid] - shapes[i - 1][pid]) / dt
					station_moved_sum[e] += station_speed
					# A mean cannot see a discontinuity: a station that teleports
					# fifteen metres once a turnover and stands still the rest of
					# the time reads as a gentle drift. This counts the samples
					# where it outran a sprinter, which is the fault itself.
					if station_speed > SPRINT_SPEED:
						jumped[e] += 1.0
					moved_n[e] += 1.0
				else:
					switched[e] += 1.0
				pairs[e] += 1.0
			if d > OFF_STATION:
				far[e] += 1.0
			var r: int = clampi(p.role, 0, roles - 1)
			role_n[r] += 1.0
			role_off[r] += d
			if d > OFF_STATION:
				role_far[r] += 1.0
			if e == SimMovement.Errand.STATION:
				role_station[r] += 1.0
	var total := 0.0
	for e in arms:
		total += n[e]
	if total <= 0.0:
		return
	print("\nHolding the shape  (every outfielder every sample: where the formation put him against where he was)")
	print("  the last two are the whole clump question: a station further from the ball than the")
	print("  man standing on it is an errand that pulled him in, and ten of those is the swarm")
	print("  %-10s %7s %12s %9s %9s %14s %8s %9s" % [
		"errand", "share", "off station", "pulled", "behind",
		"ball: station", "him", "pulls in",
	])
	var order := []
	for e in arms:
		order.append(e)
	order.sort_custom(func(a, b): return n[a] > n[b])
	var off_all := 0.0
	var pull_all := 0.0
	var behind_all := 0.0
	var ball_all := 0.0
	var station_ball_all := 0.0
	for e in order:
		if n[e] <= 0.0:
			continue
		off_all += off_sum[e]
		pull_all += pull_sum[e]
		behind_all += behind_sum[e]
		ball_all += ball_sum[e]
		station_ball_all += station_ball_sum[e]
		# The share and the gap multiplied: how many of the side's mean six metres
		# of closing-in this arm is responsible for. It sums to the total below,
		# so the arms can be ranked against each other rather than read one at a
		# time -- an arm that pulls a man ten metres in on 2% of samples is not
		# the swarm, and one that pulls six on 40% is.
		print("  %-10s %6.0f%% %10.1f m %7.1f m %7.1f m %12.1f m %6.1f m %7.2f m" % [
			SimMovement.ERRAND_NAMES[e], 100.0 * n[e] / total, off_sum[e] / n[e],
			pull_sum[e] / n[e], behind_sum[e] / n[e],
			station_ball_sum[e] / n[e], ball_sum[e] / n[e],
			(station_ball_sum[e] - ball_sum[e]) / total,
		])
	print("  the side is a mean %.1f m from its own shape: %.1f m of errand, %.1f m of not getting there"
		% [off_all / total, pull_all / total, behind_all / total])
	print("  the shape stands %.1f m from the ball and the side stands %.1f m from it: %.1f m of closing in"
		% [station_ball_all / total, ball_all / total, (station_ball_all - ball_all) / total])
	# Whether a man can hold his position at all is a separate question from where
	# he was asked to stand, and no pace will close a gap to a point that is
	# moving faster than he can run. A footballer tops out near 8 m/s.
	print("  and could he hold it  (how fast the point he was running at moved, while he stayed on that errand)")
	print("  %-10s %13s %12s %11s %11s" % [
		"errand", "station m/s", "target m/s", "over %.0f m/s" % SPRINT_SPEED, "switched",
	])
	var jumped_all := 0.0
	var moved_all := 0.0
	for e in order:
		if pairs[e] <= 0.0:
			continue
		var mn: float = maxf(moved_n[e], 1.0)
		jumped_all += jumped[e]
		moved_all += moved_n[e]
		print("  %-10s %11.1f %12.1f %10.1f%% %10.0f%%" % [
			SimMovement.ERRAND_NAMES[e], station_moved_sum[e] / mn, moved_sum[e] / mn,
			100.0 * jumped[e] / mn, 100.0 * switched[e] / pairs[e],
		])
	print("  the station outran a sprinter on %.1f%% of samples" % (100.0 * jumped_all / maxf(moved_all, 1.0)))
	print("  %-10s %13s %12s %11s" % ["role", "off station", "on station", "over %.0f m" % OFF_STATION])
	for r in roles:
		if role_n[r] <= 0.0:
			continue
		print("  %-10s %11.1f m %11.0f%% %10.0f%%" % [
			SimRole.NAMES[r], role_off[r] / role_n[r],
			100.0 * role_station[r] / role_n[r], 100.0 * role_far[r] / role_n[r],
		])


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
	var length := PackedFloat32Array()
	tried.resize(n)
	resolved.resize(n)
	ok.resize(n)
	deft.resize(n)
	length.resize(n)

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
			length[bucket] += float(e.get("dist", 0.0))
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
	# The length column is what `SimTouch.strike_scale` shows up as. A ball played
	# behind the body is not a worse pass, it is a shorter one -- there is no swing
	# behind it -- so the mechanic is visible here as the mean length falling away
	# across the sectors, and nowhere else.
	print("  sector                 attempts   share   resolved   completed   deftness   mean len")
	var low := 0.0
	for i in n:
		if tried[i] == 0:
			low = float(BODY_BUCKETS[i])
			continue
		var pct := "     -" if resolved[i] == 0 else "%5.0f%%" % (100.0 * float(ok[i]) / float(resolved[i]))
		print("  %-18s %3.0f-%3.0f  %6d  %5.1f%%   %8d      %s      %.2f     %5.1f m" % [
			BODY_LABELS[i], low, minf(float(BODY_BUCKETS[i]), 180.0), tried[i],
			100.0 * float(tried[i]) / float(total), resolved[i], pct,
			deft[i] / float(tried[i]), length[i] / float(tried[i]),
		])
		low = float(BODY_BUCKETS[i])


## The height above which the keeper is using his hands rather than his feet.
## Read off the ball's own position at the moment of the touch, because a keeper
## claiming a cross and a keeper picking one off the grass are the same event
## kind in the log and nothing else separates them.
const KEEPER_HANDS_UP := SimConsts.FOOT_REACH_HEIGHT


## What the aerial layer did.
##
## Four questions, and none of them is answerable from a touch count. Are balls
## in the air being played at all, or landing among people who let them bounce?
## How much of that is a head and how much a chest -- because a match in which
## every ball off the grass is headed is a match nobody would recognise, and that
## is exactly what this engine produced before `SimTouch.chest` existed. When
## they are headed, is it a clearance, a knock-down or an attempt on goal --
## because a match where every header is a clearance is a match with no attacking
## aerial game in it. And does the keeper come for anything?
##
## `head` on the touch is the intent `SimAerial` stamped, so the third question
## is read rather than inferred. The keeper rows are inferred, from the height
## the ball was at when he took it.
## How near the six-yard box counts as being in it when the ball comes down, and
## how near a man has to be to the dropping ball to be attacking it rather than
## watching it.
const AT_THE_BALL := 3.0
const IN_THE_AREA := 8.0


## Who is there when the cross drops.
##
## `docs/THE_FOOTBALL.md` 29's own question, and nothing could answer it. The
## chain says whether a cross reached the penalty area and `In the air` says how
## many headers happened, but a cross that lands on an empty six-yard box and one
## that drops onto three men are the same event in both. This reads the trace at
## the moment the ball arrives -- the strike tick plus the flight the ball was
## solved for -- and counts bodies around the point it was aimed at.
##
## The rows say different things and the second is the one that matters. A man
## within `AT_THE_BALL` is attacking it; men in the area with nobody at the ball
## is a box full of players and a cross nobody meets, which is what a viewer sees
## as "the ball goes through everybody".
static func _when_the_cross_drops(ctx: SimContext, events: Array) -> void:
	var trace := ctx.telemetry.trace
	if trace.is_empty():
		return
	var crosses := 0
	var contested := 0
	var at_ball := 0.0
	var in_area := 0.0
	var nearest_sum := 0.0
	var theirs_first := 0
	var intended := 0
	var intended_miss := 0.0
	var intent := {}
	for e in events:
		if e["ev"] != SimTelemetry.Ev.PASS_ATTEMPT:
			continue
		if int(e.get("kind", -1)) != SimTelemetry.Touch.CROSS:
			continue
		if not e.has("to"):
			continue
		var to: Vector3 = e["to"]
		# The flight it was actually struck with -- a cross is whipped or hung and
		# the two are three quarters of a second apart, which is the difference
		# between reading the box as the ball comes down and reading it early.
		var flight: float = float(e.get("flight", 0.0))
		if flight <= 0.0:
			flight = SimTouch.cross_flight(float(e.get("dist", 0.0)))
		var tick := int(e["t"]) + int(flight * float(SimConsts.TICK_HZ))
		var index := tick / SimConsts.TRACE_TICKS
		if index < 0 or index >= trace.size():
			continue
		var sample: PackedVector3Array = trace[index]
		if sample.size() != ctx.players.size() + 1:
			continue
		var team := int(e["team"])
		var mine := 0
		var area := 0
		var nearest := INF
		var nearest_theirs := INF
		for pid in ctx.players.size():
			var player := ctx.players[pid]
			if not player.on_pitch or player.is_keeper or pid == int(e["p"]):
				continue
			var d := SimConsts.horizontal_length(sample[pid + 1] - to)
			if player.team == team:
				if d <= AT_THE_BALL:
					mine += 1
				if d <= IN_THE_AREA:
					area += 1
				nearest = minf(nearest, d)
			else:
				nearest_theirs = minf(nearest_theirs, d)
		crosses += 1
		at_ball += float(mine)
		in_area += float(area)
		nearest_sum += minf(nearest, 40.0)
		if mine > 0:
			contested += 1
		if nearest_theirs < nearest:
			theirs_first += 1
		# And the man it was actually played to: what he was doing when it was
		# struck, and how far off it he was when it came down. The crosser picks
		# him on a race he has not agreed to run, so these two are the coordination
		# between the ball and the run, which nothing else measures.
		var target := int(e.get("target", -1))
		if target >= 0 and target < ctx.players.size():
			intended += 1
			intended_miss += minf(SimConsts.horizontal_length(sample[target + 1] - to), 40.0)
			var call := int(e.get("call", SimOffBall.NONE))
			intent[call] = int(intent.get(call, 0)) + 1
	if crosses == 0:
		return
	var n := float(crosses)
	print("\nWhen the cross drops  (%d crossed, read off the trace at the strike plus the flight)" % crosses)
	print("  ours at the ball (%.0f m)   %.2f men   -- %.0f%% of crosses had one" % [
		AT_THE_BALL, at_ball / n, 100.0 * float(contested) / n])
	print("  ours in the area (%.0f m)   %.2f men" % [IN_THE_AREA, in_area / n])
	print("  nearest of ours            %.1f m from where it came down" % (nearest_sum / n))
	print("  and theirs was nearer on %.0f%% of them" % (100.0 * float(theirs_first) / n))
	if intended > 0:
		var parts := PackedStringArray()
		var kinds: Array = intent.keys()
		kinds.sort()
		for k in kinds:
			parts.append("%s %d" % [SimOffBall.KIND_NAMES[k], int(intent[k])])
		print("  the man it was for was %.1f m off it, and was running:  %s" % [
			intended_miss / float(intended), ",  ".join(parts)])


static func _in_the_air(ctx: SimContext, events: Array) -> void:
	var headers := PackedInt32Array()
	headers.resize(SimAerial.INTENT_NAMES.size())
	var unmarked := 0
	var chests := 0
	var chest_quality := 0.0
	var caught_high := 0
	var punched := 0
	var caught_low := 0
	for e in events:
		if e["ev"] != SimTelemetry.Ev.TOUCH:
			continue
		var kind := int(e["kind"])
		if kind == SimTelemetry.Touch.CHEST:
			chests += 1
			chest_quality += float(e.get("quality", 0.0))
			continue
		if kind == SimTelemetry.Touch.HEADER:
			var intent := int(e.get("head", -1))
			if intent >= 0 and intent < headers.size():
				headers[intent] += 1
			else:
				unmarked += 1
			continue
		var by := int(e["p"])
		if by < 0 or by >= ctx.players.size() or not ctx.players[by].is_keeper:
			continue
		var height: float = (e["from"] as Vector3).y
		if kind == SimTelemetry.Touch.KEEPER_CATCH:
			if height > KEEPER_HANDS_UP:
				caught_high += 1
			else:
				caught_low += 1
		elif kind == SimTelemetry.Touch.CLEARANCE and height > KEEPER_HANDS_UP:
			punched += 1

	var total := unmarked
	for c in headers:
		total += c
	print("\nIn the air  (balls played above %.2f m)" % SimAerial.CHEST_FROM)
	if total == 0:
		print("  no headers")
	else:
		var parts := PackedStringArray()
		for i in headers.size():
			parts.append("%s %d" % [SimAerial.INTENT_NAMES[i], headers[i]])
		print("  headers %d  (above %.2f m):  %s" % [total, SimAerial.HEADER_FROM, ", ".join(parts)])
	if chests == 0:
		print("  nothing taken down off the chest")
	else:
		print("  taken down off the chest %d:  quality %.2f   (%d%% of the balls played off the grass)" % [
			chests, chest_quality / float(chests), roundi(100.0 * float(chests) / float(chests + total)),
		])
	print("  keeper came and claimed it:  caught %d, punched %d   (off the floor: caught %d)" % [
		caught_high, punched, caught_low,
	])


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
	var where := {}
	for e in events:
		if e["ev"] == SimTelemetry.Ev.PARRY:
			var w: String = str(e.get("where", "?"))
			where[w] = int(where.get(w, 0)) + 1
	print("  saves %d, of which caught %d; parried wide %d, over %d, in front %d" % [
		saves, caught, int(where.get("wide", 0)), int(where.get("over", 0)), int(where.get("front", 0)),
	])


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
##
## `theirs` is the same measurement of the other side, off the same goal line, and
## `in the area` is how many of them were inside the kicking side's penalty area
## when the ball was struck. That last one is only a rule for a goal kick, where it
## should be zero; on every other row it is ordinary football, since a side
## defending a throw-in deep in its own half stands where it likes.
##
## `worst` is there because the mean hides a stall. Eight seconds is the timeout in
## `SimSetPiece.update`, so a worst of exactly eight is a restart where nobody was
## ever ready and the taker was put on the ball to stop it stalling.
static func _restarts(ctx: SimContext, events: Array) -> void:
	var n := SET_PIECE_NAMES.size()
	var count := PackedInt32Array()
	var waited := PackedFloat32Array()
	var mean_depth := PackedFloat32Array()
	var deepest := PackedFloat32Array()
	var highest := PackedFloat32Array()
	var measured := PackedInt32Array()
	# And where the other side stood, which is the half of a restart the columns
	# above cannot see. `their_nearest` is their deepest man's distance from the
	# kicking side's own goal line, and `their_inside` is how many of them were
	# still inside the penalty area when the ball was struck -- which at a goal
	# kick is a count of how often the law was broken, and should be zero.
	var their_nearest := PackedFloat32Array()
	var their_inside := PackedFloat32Array()
	# The mean hides a stall, and a stall is the failure mode of every condition
	# that has to be met before a restart may be taken: eight seconds is the
	# timeout in `SimSetPiece.update`, so a `worst` at eight is a restart nobody
	# was ever going to be ready for.
	var worst := PackedFloat32Array()
	count.resize(n)
	waited.resize(n)
	mean_depth.resize(n)
	deepest.resize(n)
	highest.resize(n)
	measured.resize(n)
	their_nearest.resize(n)
	their_inside.resize(n)
	worst.resize(n)

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
			var sat := float(taken - pending_tick) / float(SimConsts.TICK_HZ)
			waited[pending_kind] += sat
			worst[pending_kind] = maxf(worst[pending_kind], sat)
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
					# The other side, measured off the same goal line so the two
					# rows are comparable. Distance and lateral offset rather than
					# `in_own_penalty_area`, because the trace is in world
					# coordinates and the pitch has swapped ends by the time this
					# runs -- `flip` is already in `dir` and this reuses it.
					var closest := INF
					var inside := 0
					for pid in ctx.players.size():
						var p := ctx.players[pid]
						if p.team == pending_team or p.is_keeper or not p.on_pitch:
							continue
						var from_goal := sample[pid + 1].x * dir + ctx.pitch.half_length
						closest = minf(closest, from_goal)
						if from_goal <= ctx.pitch.penalty_depth \
								and absf(sample[pid + 1].z) <= ctx.pitch.penalty_half_width:
							inside += 1
					if bodies > 0:
						mean_depth[pending_kind] += total / float(bodies)
						deepest[pending_kind] += low
						highest[pending_kind] += high
						measured[pending_kind] += 1
						their_nearest[pending_kind] += closest if not is_inf(closest) else 0.0
						their_inside[pending_kind] += float(inside)
		pending_kind = -1

	var any := false
	for i in n:
		if count[i] > 0:
			any = true
	if not any:
		return
	print("\nRestarts  (distances from the kicking side's own goal line)")
	print("  kind             count   waited  worst   own outfield: deepest    mean   highest   theirs: nearest  in the area")
	for i in n:
		if count[i] == 0:
			continue
		var shape := "         -       -         -              -            -"
		if measured[i] > 0:
			var m := float(measured[i])
			shape = "%10.0f m %5.0f m %7.0f m %12.0f m %11.1f" % [
				deepest[i] / m, mean_depth[i] / m, highest[i] / m,
				their_nearest[i] / m, their_inside[i] / m,
			]
		print("  %-16s %5d  %5.1f s %4.1f s %s" % [
			SET_PIECE_NAMES[i], count[i], waited[i] / float(maxi(count[i], 1)), worst[i], shape,
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
	_shot_fates(events)
	_save_funnel(events)
	# A shot total is two quite different things added together: chances created,
	# and second balls hammered back at the goal after the first was parried or
	# blocked. Only the first is a measure of the attack, and only the split says
	# which one a rising total was.
	if follow_ups > 0:
		print("  %d of them second attempts, inside %.0f s of the same team's last shot" % [
			follow_ups, REBOUND_SECONDS,
		])
	_lunges(events, total)
	_in_the_box(ctx, events)


## Offside traps sprung, and the offsides given inside three seconds of one:
## the act and what it caught, side by side, because an offside count alone
## cannot tell a runner who mistimed from a line that stepped up.
static func _traps(events: Array) -> void:
	var sprung := 0
	var offsides := 0
	var caught := 0
	var last_trap := PackedInt32Array([-100000, -100000])
	var window := int(3.0 * float(SimConsts.TICK_HZ))
	for e in events:
		if e["ev"] == SimTelemetry.Ev.TRAP:
			sprung += 1
			last_trap[int(e["team"])] = int(e.get("t", 0))
		elif e["ev"] == SimTelemetry.Ev.OFFSIDE:
			offsides += 1
			var against: int = SimConsts.other_team(int(e.get("team", 0)))
			if int(e.get("t", 0)) - last_trap[against] <= window:
				caught += 1
	print("  offside traps sprung    %4d   offsides given %d, of which %d inside 3 s of a trap; the trigger held on %d refreshes" % [
		sprung, offsides, caught, SimMovement.trap_triggers])


## Bodies thrown at shots (`SimDuel.commit_blocks`): how many, at what chance,
## and how many got there. A block share that stays low reads two ways -- no
## man in front of the strike, or a man in front who never gets there -- and
## only this line tells them apart.
static func _lunges(events: Array, shots: int) -> void:
	var lunges := 0
	var hits := 0
	var chance := 0.0
	for e in events:
		if e["ev"] != SimTelemetry.Ev.BLOCK_LUNGE:
			continue
		lunges += 1
		chance += float(e.get("chance", 0.0))
		if bool(e.get("hit", false)):
			hits += 1
	if lunges == 0:
		print("  bodies thrown at them: none")
	else:
		print("  bodies thrown at them: %d lunges over %d shots, mean chance %.2f, %d got there" % [
			lunges, shots, chance / float(lunges), hits,
		])
	# And the geometry the lunge model was asked about: the nearest body in
	# front of each strike.
	var near := 0
	var seen := 0
	var along_sum := 0.0
	var lat_sum := 0.0
	var none := 0
	for e in events:
		if e["ev"] != SimTelemetry.Ev.SHOT:
			continue
		if not e.has("near_along"):
			none += 1
			continue
		var along := float(e["near_along"])
		along_sum += along
		lat_sum += float(e["near_lat"])
		if along <= SimDuel.BLOCK_RANGE:
			near += 1
			if bool(e["near_saw"]):
				seen += 1
	var offs := 0.0
	var offn := 0
	for e in events:
		if e["ev"] == SimTelemetry.Ev.SHOT and e.has("k_off"):
			offs += float(e["k_off"])
			offn += 1
	if offn > 0:
		print("  the keeper stood %.1f m off his line at the strike (mean of %d)" % [offs / float(offn), offn])
	var with_body := shots - none
	if with_body > 0:
		print("  nearest body in front of the strike: %.1f m along, %.1f m off the line (mean of %d); inside %.0f m on %d, of which %d had the striker in his eyes; nobody in front on %d" % [
			along_sum / float(with_body), lat_sum / float(with_body), with_body,
			SimDuel.BLOCK_RANGE, near, seen, none,
		])


## What actually became of every shot, counted where it died.
##
## The block above cannot answer this and never could. `on_target` is a latch --
## true from the first tick the forecast crosses the frame and never cleared --
## so it counts a ball that curled away as one that was kept out, and the old
## `blocked` flag was only set for shots that were *not* on target, which is the
## opposite of a block. Between them, ten of seed 7's twenty-three shots were
## accounted for by nothing at all.
##
## The rows are exclusive and they sum to the shot count. `blocked` is now a
## defender getting something to a ball that was going in; `curled away` is the
## engine's own aim, and a large number there means the on-target share above is
## overstating rather than the defence being good.
static func _shot_fates(events: Array) -> void:
	var fates := {}
	var total := 0
	for e in events:
		if e["ev"] != SimTelemetry.Ev.SHOT:
			continue
		total += 1
		var f: String = str(e.get("fate", "still live at the whistle"))
		fates[f] = int(fates.get(f, 0)) + 1
	if total == 0:
		return
	var keys := fates.keys()
	keys.sort_custom(func(a, b): return int(fates[a]) > int(fates[b]))
	print("  what became of them")
	for k in keys:
		var c: int = fates[k]
		print("    %-18s %4d   %3.0f%%" % [k, c, 100.0 * float(c) / float(total)])


## Which stage of the save model resolved each shot the keeper faced.
##
## The fate table above says how many goal-bound shots were kept out. It cannot
## say why, and the two answers want opposite fixes. `SimKeeper._shot_response`
## resolves a save in two stages that multiply — the reach envelope, then
## `save_chance` — and only the second carries a calibration. A shot beaten for
## reach logged nothing at all, so the compound rate was the only figure
## available: a keeper whose envelope is too small and one whose roll is too low
## produced the same number.
##
## `ball ... away, reach ...` is the mean of the two on the beaten rows, in the
## keeper's own reach space rather than in metres of grass — `_closest_approach`
## stretches height by `VERTICAL_REACH_RATIO`, so a top corner is further away
## than the same offset along the floor. A gap of half a metre is a keeper who
## nearly got there and a gap of three is one who was never in it.
##
## The population is smaller than the goal-bound rows above and is meant to be. A
## shot a defender blocks before the keeper commits never reaches him, and one
## struck from six yards can be in the net before his reaction time is up — those
## are goals the save model never had an opinion about, and counting them here
## would blame it for them. The last line is the other direction: `Goalkeeping`
## counts every ball the forecast had going in, deflections and sliced clearances
## included, and those are not shots.
static func _save_funnel(events: Array) -> void:
	var faced := 0
	var reached := 0
	var saved := 0
	var beaten_margin := 0.0
	var beaten_reach := 0.0
	var saves := 0
	for e in events:
		if e["ev"] == SimTelemetry.Ev.SAVE:
			saves += 1
			continue
		if e["ev"] != SimTelemetry.Ev.SHOT or not e.has("k_reached"):
			continue
		faced += 1
		if bool(e["k_reached"]):
			reached += 1
			if bool(e["k_saved"]):
				saved += 1
		else:
			beaten_margin += float(e.get("k_margin", 0.0))
			beaten_reach += float(e.get("k_reach", 0.0))
	if faced == 0:
		return
	var f := float(faced)
	var beaten := faced - reached
	print("  the save model resolved %d of them" % faced)
	if beaten > 0:
		print("    beaten for reach   %4d   %3.0f%%   ball %.1f m away, reach %.1f m" % [
			beaten, 100.0 * float(beaten) / f,
			beaten_margin / float(beaten), beaten_reach / float(beaten),
		])
	if reached > saved:
		print("    reached, not held  %4d   %3.0f%%" % [
			reached - saved, 100.0 * float(reached - saved) / f,
		])
	print("    saved              %4d   %3.0f%%" % [saved, 100.0 * float(saved) / f])
	if saves > saved:
		print("    %d saves in the match, so %d were on balls that were not logged shots" % [
			saves, saves - saved,
		])


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
		if SimTelemetry.is_defensive_kind(kind):
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
	_why_no_ball_in_behind()
	_the_ball_in_behind(ctx, events)
	_after_the_regain()
	var possessions := _possession_table(ctx, events)
	_what_became_of_it(possessions)
	_chains(ctx, possessions)
	_near_ties(possessions)
	_why_it_lost()
	_why_the_pass_lost(events)
	_what_a_term_is_worth()
	_safe_options(ctx)
	_team_lines(ctx)
	_team_width(ctx)
	_the_clump(ctx)
	_holding_shape(ctx)
	_the_body(ctx)
	_giving_up_ground(ctx)
	_the_tempo(ctx, events)
	_new_mechanics(events)

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
	_pass_heatmap(ctx, events)
	_in_the_air(ctx, events)
	_when_the_cross_drops(ctx, events)
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
	# A success rate of zero has two causes that look the same from outside: the
	# ball was played there and did not arrive, or no ball there was ever on the
	# list. `offered` separates them for the switch, which is the pattern that
	# reads zero.
	# Was the ball the pattern asks for ever on anybody's list? A pattern that
	# fires and never succeeds is either a move that does not come off or a move
	# nobody was ever offered, and only this separates them.
	var any := false
	for k in SimPatterns.asked_weighed.size():
		if SimPatterns.asked_weighed[k] > 0:
			any = true
	if any:
		print("  and was the ball it asks for ever on the list")
		for k in SimPatterns.asked_weighed.size():
			var w: int = SimPatterns.asked_weighed[k]
			if w == 0:
				continue
			print("    %-24s %6d candidates weighed while live, %5d were the one it wanted (%.1f%%)" % [
				SimPattern.KIND_NAMES[k], w, SimPatterns.asked_offered[k],
				100.0 * float(SimPatterns.asked_offered[k]) / float(w)])

	# --- Running ------------------------------------------------------------
	print("\nDistance covered (km)")
	for team in 2:
		var line := PackedStringArray()
		for pid in ctx.team_players[team]:
			var p := ctx.players[pid]
			line.append("%s %.1f" % [SimRole.name_of(p.role), p.distance_run / 1000.0])
		print("  %s: %s" % [ctx.teams[team].short_name, " ".join(line)])


## The individual acts that leave no event of their own, counted where they are
## played. Each is a mechanic from the owner's watching list; a row at zero for
## a whole match is the mechanic not firing, which is the first thing to know
## about it.
## The possession's phase (`SimTempo`): how much of the ball is played in each
## and how quickly it is moved on. What 37 is for is the contrast between the
## rows, with the match line as the mean the phases are meant to leave where it
## was. `hold` is a man's time on the ball, his first touch to the touch that
## sends it away -- the figure 28 quotes against football's two to three
## seconds -- and `s/pass` is the phase's possession time per pass played.
## `entered` counts changes into the phase by the cause that made them; a side
## losing the ball is not one.
static func _the_tempo(ctx: SimContext, events: Array) -> void:
	var n := SimTempo.NAMES.size()
	var phase := PackedInt32Array([SimTempo.PROBE, SimTempo.PROBE])
	var since := PackedInt32Array([0, 0])
	var held := PackedInt32Array([1, 1])
	var ticks := PackedInt32Array()
	var touches := PackedInt32Array()
	var passes := PackedInt32Array()
	var forward := PackedInt32Array()
	var long_balls := PackedInt32Array()
	var holds := PackedInt32Array()
	var hold_ticks := PackedInt32Array()
	for arr in [ticks, touches, passes, forward, long_balls, holds, hold_ticks]:
		arr.resize(n)
	var causes := []
	for i in n:
		causes.append({})
	var hold_player := -1
	var hold_start := 0
	var hold_last := 0
	var hold_phase := SimTempo.PROBE
	var last_tick := 0
	for e in events:
		var ev: int = e["ev"]
		var t: int = int(e.get("t", 0))
		last_tick = t
		if ev == SimTelemetry.Ev.TEMPO:
			var team: int = e["team"]
			if held[team] == 1:
				ticks[phase[team]] += t - since[team]
			var cause: int = e["cause"]
			phase[team] = int(e["phase"])
			since[team] = t
			held[team] = 0 if cause == SimTempo.Cause.LOST else 1
			if held[team] == 1:
				var by: Dictionary = causes[phase[team]]
				by[cause] = int(by.get(cause, 0)) + 1
			continue
		if ev == SimTelemetry.Ev.PASS_ATTEMPT:
			var team: int = e["team"]
			var ph: int = phase[team]
			passes[ph] += 1
			var from: Vector3 = e.get("from", Vector3.ZERO)
			var to: Vector3 = e.get("to", from)
			if (to.x - from.x) * ctx.pitch.attack_dir(team) > 3.0:
				forward[ph] += 1
			if SimConsts.horizontal_length(to - from) > 25.0:
				long_balls[ph] += 1
			continue
		if ev != SimTelemetry.Ev.TOUCH:
			continue
		var team: int = e["team"]
		var ph: int = phase[team]
		touches[ph] += 1
		var pid: int = int(e.get("p", -1))
		if pid != hold_player:
			# The last man's hold is closed at his last touch, in the phase he
			# released it in.
			if hold_player >= 0:
				holds[hold_phase] += 1
				hold_ticks[hold_phase] += hold_last - hold_start
			hold_player = pid
			hold_start = t
		hold_last = t
		hold_phase = ph
	if hold_player >= 0:
		holds[hold_phase] += 1
		hold_ticks[hold_phase] += hold_last - hold_start
	for team in 2:
		if held[team] == 1:
			ticks[phase[team]] += last_tick - since[team]
	var total_ticks := 0
	var total_passes := 0
	var total_holds := 0
	var total_hold_ticks := 0
	var total_touches := 0
	for i in n:
		total_ticks += ticks[i]
		total_passes += passes[i]
		total_holds += holds[i]
		total_hold_ticks += hold_ticks[i]
		total_touches += touches[i]
	if total_ticks == 0:
		return
	var hz := float(SimConsts.TICK_HZ)
	print("\nThe tempo  (the possession's phase, `SimTempo`; hold is a man's first touch to his release)")
	print("  %-8s %7s %8s %7s %7s %7s %5s %6s %8s   entered by" % [
		"phase", "of ball", "touches", "passes", "hold s", "s/pass", "fwd", "long", "entered"])
	for i in n:
		var by: Dictionary = causes[i]
		var keys := by.keys()
		keys.sort_custom(func(a, b): return int(by[a]) > int(by[b]))
		var parts := PackedStringArray()
		var entered := 0
		for k in keys:
			entered += int(by[k])
			parts.append("%s %d" % [SimTempo.CAUSE_NAMES[int(k)], by[k]])
		print("  %-8s %6.0f%% %8d %7d %7s %7s %4.0f%% %5.0f%% %8d   %s" % [
			SimTempo.NAMES[i], 100.0 * float(ticks[i]) / float(total_ticks),
			touches[i], passes[i],
			("%.2f" % (float(hold_ticks[i]) / float(holds[i]) / hz)) if holds[i] > 0 else "-",
			("%.2f" % (float(ticks[i]) / float(passes[i]) / hz)) if passes[i] > 0 else "-",
			100.0 * float(forward[i]) / maxf(float(passes[i]), 1.0),
			100.0 * float(long_balls[i]) / maxf(float(passes[i]), 1.0),
			entered, ", ".join(parts)])
	print("  %-8s %7s %8d %7d %7s %7s" % [
		"match", "", total_touches, total_passes,
		("%.2f" % (float(total_hold_ticks) / float(total_holds) / hz)) if total_holds > 0 else "-",
		("%.2f" % (float(total_ticks) / float(total_passes) / hz)) if total_passes > 0 else "-"])


static func _new_mechanics(events: Array) -> void:
	print("\nThe small acts  (tallies, whole match)")
	print("  first-time balls struck %4d   of them layoffs %4d" % [
		SimTouch.ft_played, SimTouch.ft_layoff])
	print("  setting touches         %4d" % SimDecision.tally_set)
	print("  dummies                 %4d" % SimDecision.tally_dummy)
	print("  shielded holds          %4d" % SimDecision.tally_shield)
	print("  cuts tried %4d   beat his man %4d   and was fouled %4d" % [
		SimDecision.tally_feint, SimDecision.tally_beat, SimDecision.tally_beat_foul])
	print("  chips                   %4d" % SimTouch.chips_played)
	print("  covers for a beaten man %4d" % SimMovement.covers_taken)
	print("  escorts of a dying ball %4d  (cadences)" % SimMovement.escorts)
	_traps(events)
	print("  the link station: asked %d, no gap between their lines %d, pocket not ahead %d, applied %d moving the station %.1f m; the man stood %.1f m ahead of the shape's ball" % [
		SimMovement.link_asked, SimMovement.link_no_gap, SimMovement.link_no_ahead, SimMovement.link_applied,
		SimMovement.link_moved / maxf(float(SimMovement.link_applied), 1.0),
		SimMovement.link_stood / maxf(float(SimMovement.link_applied), 1.0)])
	var fouls := 0
	for e in events:
		if e["ev"] == SimTelemetry.Ev.FOUL:
			fouls += 1
	print("  fouls %d;  the cynical moment on %d ticks, challenges from it %d, fouls from those %d" % [
		fouls, SimDuel.cynical_moments, SimDuel.cynical_challenges, SimDuel.cynical_fouls])
	print("  driven ground passes    %4d" % SimTouch.driven_played)
	print("  volleys                 %4d" % SimTouch.volleys_struck)
	# Does the foot reach the strike. `mean across` at zero would mean every ball
	# in the match is played straight down the line the striker is facing, and the
	# whole of `SimTouch.foot_cost` would be a term that cannot vary.
	if SimTouch.foot_strikes > 0:
		var n := float(SimTouch.foot_strikes)
		print("  struck with a foot %4d   off his weaker one %4d (%.0f%%)" % [
			SimTouch.foot_strikes, SimTouch.foot_off_foot,
			100.0 * float(SimTouch.foot_off_foot) / n])
		print("    mean across the body %.2f   mean foot cost %.2f" % [
			SimTouch.foot_across_sum / n, SimTouch.foot_cost_sum / n])
	# Generated against played, for the acts that read zero. A zero on the left is
	# a gate and a zero on the right with a number on the left is the softmax
	# declining it, and those are fixed in different files.
	if SimDecision.rare_offered.size() == SimDecision.RARE_ACTS.size():
		var parts := PackedStringArray()
		for i in SimDecision.RARE_ACTS.size():
			parts.append("%s %d offered / %d played" % [SimDecision.RARE_ACTS[i],
				SimDecision.rare_offered[i], SimDecision.rare_played[i]])
		print("  and were they even on the list:  %s" % ",  ".join(parts))
	if SimDecision.feint_gate.size() == SimDecision.FEINT_GATES.size():
		var gates := PackedStringArray()
		for i in SimDecision.FEINT_GATES.size():
			gates.append("%s %d" % [SimDecision.FEINT_GATES[i], SimDecision.feint_gate[i]])
		print("  the feint, first test failed:  %s" % ",  ".join(gates))
	if SimDecision.shortlisted + SimDecision.unseen > 0:
		print("  teammates he could not see, and so never weighed:  %d of %d (%.0f%%)" % [
			SimDecision.unseen, SimDecision.shortlisted + SimDecision.unseen,
			100.0 * float(SimDecision.unseen)
				/ float(SimDecision.shortlisted + SimDecision.unseen)])
	# The other way onto the list is off it: the cap. A high share here with the
	# line above low means the passer's options are being chosen by a constant
	# rather than by what he could see.
	if SimDecision.lists > 0:
		print("  lists cut to the %d best:  %d of %d (%.0f%%), dropping %.1f men each" % [
			SimDecision.MAX_PASS_TARGETS, SimDecision.lists_capped, SimDecision.lists,
			100.0 * float(SimDecision.lists_capped) / float(SimDecision.lists),
			float(SimDecision.dropped) / maxf(float(SimDecision.lists_capped), 1.0)])


## Where passes are played from, per team, on a grid.
##
## Every count above says how many and how well; none says where. A side that
## plays all its passes from its own half and one that plays them in the final
## third have the same totals. Each cell is one team's pass attempts started in
## it, with the completion beside it, drawn in the team's own frame: its goal at
## the left, the goal it attacks at the right, so both halves and both sides
## read the same way. Columns are sixths of the length, rows fifths of the width.
##
## Touches are counted on the same grid, because a wide fifth with touches and no
## passes is a winger carrying, and one with neither is a winger never found.
## The table by role is the other half of that: who plays the ball and who it is
## aimed at. A full-back who is passed to and never passes has been found and
## then abandoned; one who is never passed to was never a candidate.
const HEAT_COLS := 6
const HEAT_ROWS := 5


static func _pass_heatmap(ctx: SimContext, events: Array) -> void:
	var flip := _first_half_flip(events)
	var swap_tick := _trace_swap(ctx)
	var cells := HEAT_COLS * HEAT_ROWS
	var tried := [PackedInt32Array(), PackedInt32Array()]
	var ok := [PackedInt32Array(), PackedInt32Array()]
	var touched := [PackedInt32Array(), PackedInt32Array()]
	for team in 2:
		tried[team].resize(cells)
		ok[team].resize(cells)
		touched[team].resize(cells)
	var roles := SimRole.NAMES.size()
	var from_role := PackedInt32Array()
	var to_role := PackedInt32Array()
	var to_role_ok := PackedInt32Array()
	var men_of_role := PackedInt32Array()
	from_role.resize(roles)
	to_role.resize(roles)
	to_role_ok.resize(roles)
	men_of_role.resize(roles)
	for p in ctx.players:
		if p.on_pitch:
			men_of_role[p.role] += 1

	# Pair each attempt with the outcome that follows it, per passer, in order.
	var pending := {}
	for e in events:
		if e["ev"] == SimTelemetry.Ev.TOUCH or e["ev"] == SimTelemetry.Ev.PASS_ATTEMPT:
			var team: int = e["team"]
			var side := flip if int(e["t"]) < swap_tick else 1.0
			var at: Vector3 = e.get("at", e.get("from", Vector3.ZERO)) * side * ctx.pitch.attack_dir(team)
			var col := clampi(int((at.x + ctx.pitch.half_length) / (2.0 * ctx.pitch.half_length) * HEAT_COLS), 0, HEAT_COLS - 1)
			var row := clampi(int((at.z + ctx.pitch.half_width) / (2.0 * ctx.pitch.half_width) * HEAT_ROWS), 0, HEAT_ROWS - 1)
			var cell := row * HEAT_COLS + col
			if e["ev"] == SimTelemetry.Ev.TOUCH:
				touched[team][cell] += 1
				continue
			tried[team][cell] += 1
			var pid: int = e["p"]
			from_role[ctx.players[pid].role] += 1
			var target: int = int(e.get("target", -1))
			var to := -1
			if target >= 0 and target < ctx.players.size():
				to = ctx.players[target].role
				to_role[to] += 1
			if not pending.has(pid):
				pending[pid] = []
			pending[pid].append([cell, to])
		elif e["ev"] == SimTelemetry.Ev.PASS_OUTCOME:
			var p: int = e["p"]
			if not pending.has(p) or pending[p].is_empty():
				continue
			var held: Array = pending[p].pop_front()
			if bool(e.get("ok", false)):
				ok[int(e["team"])][int(held[0])] += 1
				if int(held[1]) >= 0:
					to_role_ok[int(held[1])] += 1

	print("\nWhere passes are played from   (own goal left, attacking right; passes, completion, touches)")
	for team in 2:
		var total := 0
		for c in cells:
			total += tried[team][c]
		print("  %s  %d passes" % [ctx.teams[team].short_name, total])
		for row in HEAT_ROWS:
			var line := "   "
			for col in HEAT_COLS:
				var cell := row * HEAT_COLS + col
				var n: int = tried[team][cell]
				var t: int = touched[team][cell]
				if n == 0:
					line += "    .    %3dt  " % t if t > 0 else "     .         "
				else:
					line += " %3d %3d%% %3dt  " % [n, int(round(100.0 * float(ok[team][cell]) / float(n))), t]
			print(line)
	print("  by role          men   played   per man   aimed at   completed")
	var passes_total := 0
	for r in roles:
		passes_total += from_role[r]
	for r in roles:
		if men_of_role[r] == 0:
			continue
		print("    %-6s %10d %8d %9.1f %10d %9.0f%%" % [
			SimRole.NAMES[r], men_of_role[r], from_role[r],
			float(from_role[r]) / float(men_of_role[r]), to_role[r],
			100.0 * float(to_role_ok[r]) / maxf(float(to_role[r]), 1.0)])
