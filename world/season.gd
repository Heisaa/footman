class_name WorldSeason
extends RefCounted
## A league season (PLAN.md §8): the fixture list, the results as they come in,
## and the table they make.
##
## Data and bookkeeping only. **Nothing here decides a result** -- the player's
## own fixture is simulated by `sim/`, and the rest of the division is the
## abstract model of §2.5, which is a later pass. This is what both write into.
##
## Three points for a win, goal difference then goals scored as the tiebreaks:
## the period's table, sorted the way the period sorted it.

const WIN_POINTS := 3
const DRAW_POINTS := 1

## The division, and how long a season is.
##
## Nine clubs home and away is sixteen games each over eighteen weeks. The
## constraint is the owner's wall clock rather than football: only the player's
## own fixture is simulated by `sim/` -- about nine minutes watched, or seconds
## skipped -- and the other four fixtures each week go through the abstract
## model of §2.5, which costs nothing. Sixteen watched matches is a couple of
## hours of football for a season, which is a season somebody can finish.
##
## Both are parameters everywhere they are used, so a later difficulty tier can
## lengthen or shorten a run's seasons without touching this file.
const DEFAULT_CLUBS := 9
const DEFAULT_ROUNDS := 2

var year := 1985
## Club ids, in the order the fixture list was built from.
var club_ids := PackedInt32Array()
## How many times everybody plays everybody: 2 is home and away.
var rounds := DEFAULT_ROUNDS
## One entry per match: {"round": r, "home": id, "away": id, "played": bool,
## "home_goals": int, "away_goals": int}
var fixtures: Array[Dictionary] = []
## Which round is next. A season is over when this passes the last round.
var week := 0


## Weeks in the season. An odd division needs a blank week per club, so it runs
## one week longer per pass than an even one.
func round_count() -> int:
	var n := club_ids.size()
	if n < 2:
		return 0
	return (n - 1 if n % 2 == 0 else n) * rounds


## Matches each club plays. What the wall-clock question is actually about.
func games_per_club() -> int:
	return maxi(club_ids.size() - 1, 0) * rounds


## Builds the fixture list: everybody plays everybody `rounds` times, one round
## per week, grounds swapped on the second pass.
##
## The circle method, with a bye slot when the club count is odd -- which nine
## is, so one club sits out each week.
static func create(rng: SimRng, ids: PackedInt32Array, year: int = 1985, rounds: int = DEFAULT_ROUNDS) -> WorldSeason:
	var season := WorldSeason.new()
	season.year = year
	season.rounds = maxi(rounds, 1)
	season.club_ids = ids.duplicate()

	var wheel := PackedInt32Array(ids)
	# Shuffle so the fixture list is not the club list in order.
	for i in range(wheel.size() - 1, 0, -1):
		var j := rng.range_int(0, i)
		var tmp := wheel[i]
		wheel[i] = wheel[j]
		wheel[j] = tmp
	if wheel.size() % 2 == 1:
		wheel.append(-1)

	var half := wheel.size() / 2
	var weeks_per_pass := wheel.size() - 1
	for r in weeks_per_pass:
		for i in half:
			var a := wheel[i]
			var b := wheel[wheel.size() - 1 - i]
			if a == -1 or b == -1:
				continue
			# Alternate who is at home round by round, or the same club is home
			# every week of the first pass.
			var home := a if (r + i) % 2 == 0 else b
			var away := b if home == a else a
			for pass_index in season.rounds:
				# Odd passes swap the ground, so two passes are home and away
				# and a third would start the cycle again.
				var swapped := pass_index % 2 == 1
				season.fixtures.append(_fixture(
					r + pass_index * weeks_per_pass,
					away if swapped else home,
					home if swapped else away))
		# Rotate all but the first.
		var last := wheel[wheel.size() - 1]
		for i in range(wheel.size() - 1, 1, -1):
			wheel[i] = wheel[i - 1]
		wheel[1] = last

	season.fixtures.sort_custom(func(x, y): return int(x["round"]) < int(y["round"]))
	return season


static func _fixture(round_index: int, home: int, away: int) -> Dictionary:
	return {
		"round": round_index,
		"home": home,
		"away": away,
		"played": false,
		"home_goals": 0,
		"away_goals": 0,
	}


func fixtures_in_round(round_index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in fixtures:
		if int(f["round"]) == round_index:
			out.append(f)
	return out


## This club's next unplayed fixture, or an empty dictionary at the end of the
## season.
func next_fixture_for(club_id: int) -> Dictionary:
	for f in fixtures:
		if bool(f["played"]):
			continue
		if int(f["home"]) == club_id or int(f["away"]) == club_id:
			return f
	return {}


func record_result(fixture: Dictionary, home_goals: int, away_goals: int) -> void:
	fixture["played"] = true
	fixture["home_goals"] = home_goals
	fixture["away_goals"] = away_goals


## Advances to the next round. Nothing checks that the round was played: a
## skipped fixture is a state the run layer may want, not an error here.
func advance_week() -> void:
	week += 1


func is_over() -> bool:
	return week >= round_count()


## The table, best first. One row per club:
##   {"club": id, "played", "won", "drawn", "lost", "for", "against",
##    "difference", "points"}
func table() -> Array[Dictionary]:
	var rows := {}
	for id in club_ids:
		rows[id] = {
			"club": id, "played": 0, "won": 0, "drawn": 0, "lost": 0,
			"for": 0, "against": 0, "difference": 0, "points": 0,
		}
	for f in fixtures:
		if not bool(f["played"]):
			continue
		var home: Dictionary = rows.get(int(f["home"]), {})
		var away: Dictionary = rows.get(int(f["away"]), {})
		if home.is_empty() or away.is_empty():
			continue
		var hg := int(f["home_goals"])
		var ag := int(f["away_goals"])
		home["played"] += 1
		away["played"] += 1
		home["for"] += hg
		home["against"] += ag
		away["for"] += ag
		away["against"] += hg
		if hg > ag:
			home["won"] += 1
			away["lost"] += 1
			home["points"] += WIN_POINTS
		elif ag > hg:
			away["won"] += 1
			home["lost"] += 1
			away["points"] += WIN_POINTS
		else:
			home["drawn"] += 1
			away["drawn"] += 1
			home["points"] += DRAW_POINTS
			away["points"] += DRAW_POINTS

	var out: Array[Dictionary] = []
	for id in club_ids:
		var row: Dictionary = rows[id]
		row["difference"] = int(row["for"]) - int(row["against"])
		out.append(row)
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["points"]) != int(b["points"]):
		return int(a["points"]) > int(b["points"])
	if int(a["difference"]) != int(b["difference"]):
		return int(a["difference"]) > int(b["difference"])
	if int(a["for"]) != int(b["for"]):
		return int(a["for"]) > int(b["for"])
	# A stable last resort, so two identical records do not swap places between
	# one reading of the table and the next.
	return int(a["club"]) < int(b["club"])


## Where a club is in the table, one-based. Zero if it is not in this season.
func position_of(club_id: int) -> int:
	var rows := table()
	for i in rows.size():
		if int(rows[i]["club"]) == club_id:
			return i + 1
	return 0
