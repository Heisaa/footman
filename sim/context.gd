class_name SimContext
extends RefCounted
## Everything the simulation modules share.
##
## Modules take a context rather than a reference to the match, so no module
## depends on the orchestrator and there are no reference cycles. Nothing here
## touches the scene tree, a viewport, or a frame delta.

var config: SimMatchConfig
var rng: SimRng
var env: SimEnv
var pitch: SimPitch
var ball: SimBall
## Never read this directly -- call trajectory_now(). The forecast is expensive
## and only a handful of agents consult it on any given tick, so it is computed
## lazily and then shared by everyone who asks in the same tick.
var trajectory: SimTrajectory
var _trajectory_dirty := true
var telemetry: SimTelemetry
var ballistics: SimBallistics
var value: SimValueField

## Both sides, indexed by SimConsts.TEAM_HOME / TEAM_AWAY.
var teams: Array[SimTeam] = []
## Every player on the pitch, in fixed id order. players[i].id == i always.
var players: Array[SimPlayer] = []
## Player ids per team, in fixed order.
var team_players: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]

var tick_index := 0
## The match clock as the scoreboard shows it. Reset to 45:00 at the interval,
## because first-half added time is not carried into the second half.
var clock := 0.0
## Match-clock seconds since kick-off, never reset. `clock` is the wrong thing
## to normalise a count by for exactly that reason: events during first-half
## added time happened, and a denominator that forgets them inflates every rate.
var elapsed_clock := 0.0
var period := SimConsts.Period.FIRST_HALF
var phase := SimConsts.Phase.KICKOFF
var score := [0, 0]
## Ticks of added time to play in the current period.
var added_time_ticks := 0
## Ticks lost to stoppages this period; the referee turns these into added time.
var stoppage_ticks := 0

## The telemetry entry for the shot currently in flight, held by reference so
## the referee can fill in whether it was on target once the ball has told us.
var active_shot := {}
var active_shot_tick := -1

## Who played the last pass, to whom, and when. Three integers, so that a player
## receiving the ball knows who gave it to him.
##
## That is the whole state a give-and-go needs. The man who has just laid it off
## is, for the next second or so, both the most likely person to be free -- he
## has a defender following the ball rather than him -- and the one most likely
## to be ignored, because nothing in a positional model makes the ball come back
## the way it came. Two priors are hung off this: the passer prefers a run over
## holding shape, and the receiver prices the return ball above its map value.
var last_pass_from := -1
var last_pass_to := -1
var last_pass_tick := -100000
## And when it got there, which is the tick both priors are actually measured
## from. Measured on the losing candidates, the return-ball bias was applied to
## a third of the decisions in the match at a mean of 1.11 against a constant of
## 1.45, and flipped 0.4% of them: the window ran from the strike, so the flight
## and the receiver's first touch spent three quarters of it before he ever
## looked up. The passer's run half had the same clock, so both halves had
## decayed to nothing by the moment they were meant to meet.
##
## Behind `last_pass_tick` means the ball is still on its way.
var last_pass_arrival_tick := -100000

## A pass has been played to a player who was offside when it was struck.
## Offside is evaluated at the moment of the passing impulse, which is trivially
## available here because passes are discrete events (PLAN.md §3.5).
var offside_pending := -1
var offside_pos := Vector3.ZERO
## The tick the flag went up. The pass itself is a touch, so without this the
## referee sees "someone other than the flagged player has played the ball" on
## the very tick the flag is raised, and clears it every single time.
var offside_tick := -1

## True while normal play is running. Set pieces and dead-ball periods clear it.
var in_play := true

# --- Restart state, owned by the set-piece module ---------------------------

var restart_kind := -1
var restart_team := -1
var restart_pos := Vector3.ZERO
var restart_ticks := 0
var restart_taker := -1
## Ticks the taker has been standing over the ball, which is not the same as
## ticks since the whistle: he has to walk there first. A throw-in needs it to
## hold the ball over his head for long enough that the throw is a throw.
var restart_hold := 0
## Positions players are walking to for the restart, keyed by player id.
var restart_spots := {}

## Per-keeper shot-response state, keyed by player id. Owned by the keeper
## module.
var keeper_state := {}

## Named tactical patterns currently mid-flight, owned by the pattern module.
## Each entry is judged when its window closes, so every firing gets an outcome.
var pattern_runs: Array[Dictionary] = []

# --- Perception -------------------------------------------------------------

## Believed position of every player, from every player's point of view.
## Flat, indexed [observer * n + target]. Slightly stale and slightly noisy.
var beliefs := PackedVector3Array()
## Tick at which each observer last refreshed each belief.
var belief_ticks := PackedInt32Array()

## Which team the sim currently considers to be in possession, derived from the
## last touch and contest range. There is no possession flag on the ball
## (PLAN.md §3.3) -- this is a cached derivation, refreshed each tick.
var possession_team := -1
var possession_player := -1
## A monotonic id for the spell of possession running now, stamped onto every
## event by `log_event`.
##
## Links 4 and 5 of the chain -- `docs/DIAGNOSTICS.md`, "The chain". It exists to
## make "and what became of it" a filter rather than a guess. Every
## instrument in `tools/diagnostics.gd` used to pair a touch with its consequence
## by looking a few seconds up the log, which desynchronises at the first attempt
## that never resolves -- one such pairing reported 20% against an actual 78%.
## With an id on both ends there is nothing to desynchronise.
##
## A spell is a run of one team being the side in possession. It ends when the
## other team takes over and it ends at every dead ball, because a restart sets
## `ball.last_touch_player` to -1 and drives this to -1 with it. That second rule
## is what makes a free kick to the side that already had the ball a boundary: it
## would otherwise be a possession that swallowed the foul that interrupted it,
## and the foul is the outcome worth counting.
##
## Nothing in `sim/` reads it back. It is derived, like `possession_team` above.
var possession_id := -1
var possession_start_tick := 0
var possession_start_pos := Vector3.ZERO
## The last place the ball was while this spell was live and the ball was in
## play. Not the same as where it is when the spell ends, and the difference is
## not small: a spell that ends at a dead ball ends one tick after the restart has
## already teleported the ball to the throw-in spot or the centre circle, so
## reading the position then measured the restart rather than the football. Every
## possession that ended in a goal came back at forty-four metres *lost*, which is
## the distance from a goalmouth to a kick-off.
var possession_last_pos := Vector3.ZERO
## Which way this team was attacking when the spell started.
##
## Kept rather than read at the end, because `SimPitch` only ever knows where the
## ends are pointing *now* and they swap at the interval. A spell straddling that
## swap would have its ground gain measured against the wrong goal and come back
## with the sign reversed -- the same trap `docs/DIAGNOSTICS.md` records for
## anything reading a position out of the log, priced in advance here so nothing
## downstream has to know about it.
var possession_attack_dir := 1.0
## Ticks the current possession has lasted, used for phase-of-play transitions.
var possession_ticks := 0
## Per-team tick counts, for the possession statistic.
var possession_count := [0, 0]

## Per-player pressure, recomputed each tick: a 0..1-ish measure of how closely
## opponents are breathing down their neck.
var pressure := PackedFloat32Array()
## Per-player imminence of a challenge, recomputed alongside pressure.
##
## Deliberately a *second* field rather than a term folded into `pressure`, and
## the two are not the same question. Pressure asks "how much of what I want to
## do is being taken away", so it rates an opponent in front of the player at
## three times one at his back, and it is right to. Challenge threat asks "am I
## about to be tackled", which is a question about closing distance and nothing
## to do with which way the carrier happens to be facing -- the man arriving on
## his blind side is the one who takes it off him.
##
## Folding them together would have made pressure lie about the thing it is
## already used for: the shot model, the touch error model and the marking
## assignment all read it and all mean the first question.
var challenge := PackedFloat32Array()
## Expected threat of each player's current position, from their own team's
## point of view. Refreshed with pressure; read by the marking assignment.
var player_threat := PackedFloat32Array()


## The shared forward prediction of the ball's flight, computed at most once per
## tick however many agents ask for it. This is the rule from PLAN.md §2.5:
## never let each agent run its own trajectory prediction.
func trajectory_now() -> SimTrajectory:
	if _trajectory_dirty:
		trajectory.recompute(ball, env, pitch)
		_trajectory_dirty = false
	return trajectory


## Called once at the top of every tick.
func invalidate_trajectory() -> void:
	_trajectory_dirty = true


func player_count() -> int:
	return players.size()


func opponent_ids(team: int) -> PackedInt32Array:
	return team_players[SimConsts.other_team(team)]


func teammate_ids(team: int) -> PackedInt32Array:
	return team_players[team]


func tactics(team: int) -> SimTactics:
	return teams[team].ensure_tactics()


## How far out a closing opponent starts to register as an imminent challenge.
##
## Wider than `SimDuel.CHALLENGE_RADIUS` on purpose. A carrier who only notices
## the man on his back at the instant he is inside tackling range has no time
## left to do anything about it, so his only remaining option is to stay in the
## challenge -- which is precisely the behaviour this field exists to break. At
## 5.5 m and a closing speed of 4 m/s he has most of a second: enough for one
## more touch, taken somewhere else.
const CHALLENGE_SIGHT := 5.5


## Recomputes the per-player pressure and challenge fields. Pressure is what
## makes a player rush: it widens every error distribution in the touch model.
## Challenge threat is what makes him do something about it.
func update_pressure() -> void:
	if pressure.size() != players.size():
		pressure.resize(players.size())
	if challenge.size() != players.size():
		challenge.resize(players.size())
	if player_threat.size() != players.size():
		player_threat.resize(players.size())
	for i in players.size():
		var p := players[i]
		if not p.on_pitch:
			pressure[i] = 0.0
			challenge[i] = 0.0
			player_threat[i] = 0.0
			continue
		player_threat[i] = value.xt_at(p.team, p.pos, pitch)
		var total := 0.0
		var closing_in := 0.0
		for j in opponent_ids(p.team):
			var o := players[j]
			if not o.on_pitch:
				continue
			var d2 := p.dist_sq_to(o.pos)
			if d2 > 36.0:
				continue
			var d := sqrt(d2)
			# An opponent closing from in front presses harder than one behind.
			var to_opp := (o.pos - p.pos)
			var facing_factor := 1.0
			if d > 0.1:
				facing_factor = 0.65 + 0.35 * (to_opp / d).dot(p.heading_dir())
			total += facing_factor * (1.0 - d / 6.0) * (1.0 - d / 6.0)
			if d < CHALLENGE_SIGHT and d > 0.1:
				closing_in += _challenge_from(p, o, to_opp / d, d)
		pressure[i] = clampf(total, 0.0, 2.5)
		challenge[i] = clampf(closing_in, 0.0, 2.0)


## One opponent's contribution to the threat of being tackled.
##
## The speed term is *relative*: a defender running alongside at the carrier's
## own pace is not challenging him, however close he is, and a defender standing
## still as the carrier runs at him is. Closing speed is what separates a man
## coming to win the ball from a man who merely happens to be nearby, and it is
## also what the carrier can actually see coming.
func _challenge_from(p: SimPlayer, o: SimPlayer, toward: Vector3, d: float) -> float:
	# Anchored on the radius inside which the duel model will actually let him
	# challenge, so that a reading of 1 means "he can take it off you now" and
	# not some arbitrary fraction. Between that radius and challenge sight it
	# falls off linearly: he is on his way, and the carrier has time in hand
	# proportional to the gap. Scaling it any other way makes every coefficient
	# that reads this field a number with no meaning behind it.
	var near: float = clampf((CHALLENGE_SIGHT - d) / (CHALLENGE_SIGHT - SimDuel.CHALLENGE_RADIUS), 0.0, 1.0)
	var closing: float = (o.vel - p.vel).dot(-toward)
	# A share of the threat is simply proximity: a defender already inside
	# tackling range does not have to close any further to take it.
	var urgency: float = 0.4 + 0.6 * clampf(closing / 5.0, 0.0, 1.0)
	return near * urgency * lerpf(0.75, 1.2, o.attrs.tackling)


func pressure_on(player: SimPlayer) -> float:
	return pressure[player.id] if player.id < pressure.size() else 0.0


## How close this player is to being tackled, 0 to 2.
func challenge_on(player: SimPlayer) -> float:
	return challenge[player.id] if player.id < challenge.size() else 0.0


## The opponent most likely to be the one who challenges `player`: the nearest
## inside challenge sight. Null when nobody is near enough to matter.
##
## Read by the decision layer to score a way out and by the movement layer to
## decide whether the carrier is running or jogging. Both want the same man.
func nearest_challenger(player: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_d2 := CHALLENGE_SIGHT * CHALLENGE_SIGHT
	for j in opponent_ids(player.team):
		var o := players[j]
		if not o.on_pitch or o.is_keeper:
			continue
		var d2 := player.dist_sq_to(o.pos)
		if d2 < best_d2:
			best_d2 = d2
			best = o
	return best


## Nearest opponent to a player, or null.
func nearest_opponent(player: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_d2 := INF
	for j in opponent_ids(player.team):
		var o := players[j]
		if not o.on_pitch:
			continue
		var d2 := player.dist_sq_to(o.pos)
		if d2 < best_d2:
			best_d2 = d2
			best = o
	return best


## Nearest player of either team to a point, optionally restricted to a team.
func nearest_to(point: Vector3, team: int = -1, exclude_id: int = -1) -> SimPlayer:
	var best: SimPlayer = null
	var best_d2 := INF
	for p in players:
		if not p.on_pitch or p.id == exclude_id:
			continue
		if team >= 0 and p.team != team:
			continue
		var d2 := p.dist_sq_to(point)
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


## Players within `radius` of a point, in id order.
func players_within(point: Vector3, radius: float, team: int = -1) -> Array[SimPlayer]:
	var out: Array[SimPlayer] = []
	var r2 := radius * radius
	for p in players:
		if not p.on_pitch:
			continue
		if team >= 0 and p.team != team:
			continue
		if p.dist_sq_to(point) <= r2:
			out.append(p)
	return out


## Derives possession: the last player to touch the ball holds it while no
## opponent is inside contest range. Cheap, so it runs every tick.
func update_possession() -> void:
	var previous := possession_team
	var holder := ball.last_touch_player
	if holder < 0 or holder >= players.size():
		possession_team = -1
		possession_player = -1
	else:
		var p := players[holder]
		var contest_range := 2.2
		var contested := false
		if p.dist_to(ball.ground_pos()) > 3.0:
			# The ball has left them; whoever is closest is contesting it.
			contested = true
		else:
			for j in opponent_ids(p.team):
				if players[j].on_pitch and players[j].dist_to(ball.ground_pos()) < contest_range:
					contested = true
					break
		possession_team = p.team
		possession_player = -1 if contested else holder
	if possession_team == previous:
		possession_ticks += 1
	else:
		# The spell that is ending is logged before the id moves on, so the event
		# carries its own id like everything else that happened inside it.
		if previous >= 0:
			_end_possession(previous)
		if possession_team >= 0:
			possession_id += 1
			# The touch that won it, not the tick this was noticed on. Possession
			# is derived at the top of a tick and a touch is played in the middle
			# of one, so a spell always begins a tick before anything here can see
			# it -- and dated from here, a spell excluded its own first touch and
			# included the opponent's winning one.
			possession_start_tick = tick_index if ball.last_touch_tick < 0 else ball.last_touch_tick
			possession_start_pos = ball.ground_pos()
			possession_attack_dir = pitch.attack_dir(possession_team)
		possession_ticks = 0
	if possession_team >= 0 and in_play:
		possession_count[possession_team] += 1
	if in_play:
		possession_last_pos = ball.ground_pos()


## Ball position projected onto the ground plane.
func ball_ground() -> Vector3:
	return ball.ground_pos()


## What the spell was, at the moment it stopped being one.
##
## Deliberately facts and not a verdict. What ended it is derivable from the
## events already carrying this id -- a shot, a failed pass, a duel, the set piece
## awarded -- and deriving it here would put a taxonomy nothing in `sim/` uses
## inside the simulation. `tools/diagnostics.gd` owns that reading.
##
## `gained` is metres toward the goal this team was attacking, so it is signed and
## needs no half-time correction: `attack_dir` already knows which way they were
## going when the spell ran.
func _end_possession(team: int) -> void:
	var here := possession_last_pos
	log_event(SimTelemetry.Ev.POSSESSION_END, {
		"team": team,
		"ticks": tick_index - possession_start_tick,
		"from": possession_start_pos,
		"to": here,
		"gained": (here.x - possession_start_pos.x) * possession_attack_dir,
		# Which way they were going, so nothing reading this back has to work it
		# out from the half. Every instrument that has tried has got it wrong once.
		"dir": possession_attack_dir,
	})


func log_event(kind: int, data: Dictionary = {}) -> void:
	data["poss"] = possession_id
	telemetry.log_event(kind, tick_index, data)


func minute() -> float:
	return clock / 60.0
