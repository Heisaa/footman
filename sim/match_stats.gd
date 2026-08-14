class_name SimMatchStats
extends RefCounted
## Aggregates a finished match into the metrics of PLAN.md §11.
##
## Everything here is derived from telemetry, not from counters kept alongside
## it. If a statistic cannot be recovered from the event log, the event log is
## missing something.

var score := [0, 0]
var shots := [0, 0]
var shots_on_target := [0, 0]
var goals := [0, 0]
var passes := [0, 0]
var passes_completed := [0, 0]
var possession := [0.0, 0.0]
var fouls := [0, 0]
var cards := [0, 0]
var reds := [0, 0]
var offsides := [0, 0]
var corners := [0, 0]
var throw_ins := [0, 0]
var saves := [0, 0]
var duels := [0, 0]
var recoveries := [0, 0]
var touches := [0, 0]
## Touches taken inside the penalty area the side is attacking, a tackle or a
## block excluded because those are the defence's touches in its own box.
##
## Here rather than only in `SimDiagnostics` because it is a rate and one seed
## cannot say a rate. Football gives a side about twenty-five of these in a
## match; an engine that lets a carrier walk to the six-yard line gives it four
## times that, and the count is the instrument for the box work either way.
var box_touches := [0, 0]
var distance := [0.0, 0.0]
var max_player_distance := 0.0
var min_player_distance := 0.0
var mean_pass_length := [0.0, 0.0]
var mean_shot_distance := [0.0, 0.0]
var final_stamina := [0.0, 0.0]
var ticks := 0
## Match-clock seconds elapsed, kick-off to final whistle. Identical to
## `ticks / TICK_HZ` for an uncompressed match and `clock_rate` times larger for
## a compressed one, which is why every rate below is normalised through this
## rather than through the tick count.
var clock := 0.0
var seed_value := 0
var digest := ""


static func collect(m: SimMatch) -> SimMatchStats:
	var s := SimMatchStats.new()
	var ctx := m.ctx
	s.ticks = ctx.tick_index
	s.clock = ctx.elapsed_clock
	s.seed_value = ctx.config.seed_value
	s.score = ctx.score.duplicate()

	var pass_length_total := [0.0, 0.0]
	var shot_distance_total := [0.0, 0.0]

	# Which end a side is attacking, for the touches below. The trace is in world
	# coordinates and the sides change ends, so a first-half touch in the box a
	# team was attacking reads as inside its own: if this match has a second half
	# at all, everything before it is in the other frame. `SimDiagnostics` walks
	# it the same way for the same reason.
	var attacking_frame := true
	for e in ctx.telemetry.events:
		if e["ev"] == SimTelemetry.Ev.PERIOD and int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
			attacking_frame = false
			break

	for e in ctx.telemetry.events:
		var kind: int = e["ev"]
		match kind:
			SimTelemetry.Ev.GOAL:
				s.goals[int(e["team"])] += 1
			SimTelemetry.Ev.SHOT:
				var t: int = e["team"]
				s.shots[t] += 1
				shot_distance_total[t] += float(e.get("dist", 0.0))
				if bool(e.get("on_target", false)):
					s.shots_on_target[t] += 1
			SimTelemetry.Ev.PASS_ATTEMPT:
				var t2: int = e["team"]
				s.passes[t2] += 1
				pass_length_total[t2] += float(e.get("dist", 0.0))
			SimTelemetry.Ev.PASS_OUTCOME:
				if bool(e.get("ok", false)):
					s.passes_completed[int(e["team"])] += 1
			SimTelemetry.Ev.FOUL:
				s.fouls[int(e["team"])] += 1
			SimTelemetry.Ev.CARD:
				s.cards[int(e["team"])] += 1
				if bool(e.get("red", false)):
					s.reds[int(e["team"])] += 1
			SimTelemetry.Ev.OFFSIDE:
				s.offsides[int(e["team"])] += 1
			SimTelemetry.Ev.SAVE:
				s.saves[int(e["team"])] += 1
			SimTelemetry.Ev.DUEL:
				s.duels[int(e["team"])] += 1
			SimTelemetry.Ev.RECOVERY:
				s.recoveries[int(e["team"])] += 1
			SimTelemetry.Ev.PERIOD:
				if int(e.get("period", 0)) == SimConsts.Period.SECOND_HALF:
					attacking_frame = true
			SimTelemetry.Ev.TOUCH:
				var tt: int = e["team"]
				s.touches[tt] += 1
				var tk: int = e["kind"]
				if tk != SimTelemetry.Touch.TACKLE and tk != SimTelemetry.Touch.BLOCK:
					var inside := ctx.pitch.in_opponent_penalty_area(tt, e["from"]) if attacking_frame \
						else ctx.pitch.in_own_penalty_area(tt, e["from"])
					if inside:
						s.box_touches[tt] += 1
			SimTelemetry.Ev.SET_PIECE:
				var sp: int = e["kind"]
				if sp == SimSetPiece.Kind.CORNER:
					s.corners[int(e["team"])] += 1
				elif sp == SimSetPiece.Kind.THROW_IN:
					s.throw_ins[int(e["team"])] += 1

	var total_possession: float = maxf(float(ctx.possession_count[0] + ctx.possession_count[1]), 1.0)
	s.possession[0] = 100.0 * float(ctx.possession_count[0]) / total_possession
	s.possession[1] = 100.0 * float(ctx.possession_count[1]) / total_possession

	var counted := [0, 0]
	s.min_player_distance = INF
	for p in ctx.players:
		s.distance[p.team] += p.distance_run
		s.final_stamina[p.team] += p.stamina
		counted[p.team] += 1
		if not p.is_keeper:
			s.max_player_distance = maxf(s.max_player_distance, p.distance_run)
			s.min_player_distance = minf(s.min_player_distance, p.distance_run)
	for t in 2:
		if counted[t] > 0:
			s.final_stamina[t] /= float(counted[t])
		s.mean_pass_length[t] = pass_length_total[t] / maxf(float(s.passes[t]), 1.0)
		s.mean_shot_distance[t] = shot_distance_total[t] / maxf(float(s.shots[t]), 1.0)
	if is_inf(s.min_player_distance):
		s.min_player_distance = 0.0
	return s


## Fields that are per-team pairs, and the scalars. Listed once so the JSON
## round-trip cannot drift from the class.
const PAIR_FIELDS := [
	"score", "shots", "shots_on_target", "goals", "passes", "passes_completed",
	"possession", "fouls", "cards", "reds", "offsides", "corners", "throw_ins",
	"saves", "duels", "recoveries", "touches", "box_touches", "distance", "mean_pass_length",
	"mean_shot_distance", "final_stamina",
]
const SCALAR_FIELDS := ["max_player_distance", "min_player_distance", "ticks", "clock", "seed_value", "digest"]


## Serialises to a plain dictionary so a batch can be split across processes and
## aggregated afterwards. Matches are independent and seeded, so sharding a
## batch across cores is the difference between a five-minute gate and an
## hour-long one (PLAN.md §11.1).
func to_dict() -> Dictionary:
	var out := {}
	for key in PAIR_FIELDS:
		out[key] = Array(get(key))
	for key in SCALAR_FIELDS:
		out[key] = get(key)
	return out


static func from_dict(data: Dictionary) -> SimMatchStats:
	var s := SimMatchStats.new()
	for key in PAIR_FIELDS:
		if data.has(key):
			s.set(key, Array(data[key]))
	for key in SCALAR_FIELDS:
		if data.has(key):
			s.set(key, data[key])
	return s


## Minutes of match clock actually played, added time included. A batch may be
## run at any match length -- the validation gate uses short matches, because a
## count is a count and the wall clock is the scarce resource (PLAN.md §11.1) --
## so every counting statistic is normalised through this rather than assumed
## to be a per-90 figure.
##
## It is the *match clock*, not the ticks. Under compression those differ by
## `clock_rate`, and it is the clock that the answer has to be per: a match that
## reads 0-90 on the scoreboard produced whatever it produced in ninety minutes
## of football, however few ticks it took to do it. Normalising on ticks instead
## would report a three-minute match's four goals as a hundred and twenty per
## ninety. Shard JSON written before the field existed carries no clock, so fall
## back to the tick count, which was the definition at the time.
func minutes_played() -> float:
	var seconds := clock if clock > 0.0 else float(ticks) / float(SimConsts.TICK_HZ)
	return maxf(seconds / 60.0, 1.0)


## Scales a per-match count to per ninety minutes.
func per_90(value: float) -> float:
	return value * 90.0 / minutes_played()


## Minutes of *football* actually played -- the ticks, which never compress.
## Under the standard clock these are a tenth of `minutes_played()`.
func football_minutes() -> float:
	return maxf(float(ticks) / float(SimConsts.TICK_HZ) / 60.0, 1.0)


## Scales a count to per ninety minutes of football. The sanity ranges use this
## for the rows that are football density -- passes, fouls, corners, distance --
## because "is this still football" is a question about the football, and a
## compressed match holds proportionally less of it. Rows the scoring fit
## deliberately moves -- goals, shots, on-target -- stay per match clock, since
## the format holds those steady per match, not per football minute.
func per_football_90(value: float) -> float:
	return value * 90.0 / football_minutes()


func total_goals() -> int:
	return goals[0] + goals[1]


func is_draw() -> bool:
	return score[0] == score[1]


## Mean distance covered per outfield player, in kilometres.
func km_per_player(team: int, squad_size: int) -> float:
	return distance[team] / 1000.0 / maxf(float(squad_size), 1.0)


func on_target_share(team: int) -> float:
	return 100.0 * float(shots_on_target[team]) / maxf(float(shots[team]), 1.0)


func pass_completion(team: int) -> float:
	return 100.0 * float(passes_completed[team]) / maxf(float(passes[team]), 1.0)


func summary_line() -> String:
	return "%d-%d  shots %d/%d (on target %d/%d)  passes %d/%d  poss %.0f/%.0f  fouls %d/%d  corners %d/%d" % [
		score[0], score[1], shots[0], shots[1], shots_on_target[0], shots_on_target[1],
		passes[0], passes[1], possession[0], possession[1], fouls[0], fouls[1],
		corners[0], corners[1],
	]
