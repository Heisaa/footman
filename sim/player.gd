class_name SimPlayer
extends RefCounted
## A player in the simulation. Not a scene-tree node, not a physics body: a
## kinematic point with a capsule used only for soft separation (PLAN.md §3.2).

## How far sideways a player will let a change of direction carry him, in metres,
## before he would rather shed the speed and turn tighter.
##
## This and `TURN_GRIP` between them replaced a floor on the speed carried
## through a hairpin, which could not be made to work at any value. The floor was
## a function of the angle *still to be turned*, and it therefore gave the pace
## back as the turn progressed: measured tick by tick, a man reversing braked from
## 6.8 m/s to 3.5 and then began accelerating again thirty-five degrees into the
## turn, because at that point the remaining angle had released forty per cent of
## his speed budget. He came out of a 180 faster than he went in, having drawn a
## circle three and a half metres across, and lowering the floor from 0.3 to 0.08
## barely moved it -- the floor was never what he was sitting on.
##
## The honest constraint is not an angle at all, it is the ground the turn costs.
## An arc of radius R through the angle he owes carries him R * (1 - cos theta)
## off his line, and grip fixes R at v^2 / g, so the speed that keeps that inside
## his budget is sqrt(g * L / (1 - cos theta)). It does the right thing at both
## ends without being asked: a twenty-degree correction is unrestricted, because
## the arc is nearly straight, while a full turn-round is capped near two metres a
## second however fast he arrived. And it does not release early -- at ninety
## degrees still to make, he is still held to about three -- so the shape that
## comes out is brake, pivot, go, rather than a circle run at pace.
const TURN_SWING := 1.0
## How much of a turn a player will finish before he starts driving out of it,
## in radians. Sixty degrees is about the point at which he can see where he is
## going and put his foot down.
const TURN_COMMIT := 1.05
## Below this speed a player is pivoting rather than turning, and none of the
## momentum rules above apply to him.
const TURN_PIVOT := 1.5
## Sideways acceleration a player can hold while turning, in m/s^2 -- what the
## studs will take before he is skating rather than turning.
##
## This is the constraint that makes braking matter, and without it the hairpin
## speed ceiling below could not bite however low it was set. Turning a velocity
## needs lateral acceleration of `v * omega`, so at seven metres a second the
## agility turn rate of about 2.6 rad/s was asking for 18 m/s^2 -- getting on for
## two g, sideways, from a man already running flat out. He could therefore spin
## his whole velocity vector round in half a second, which is quicker than the
## 8 m/s^2 of braking can shed the pace, so the turn finished while he was still
## travelling at speed and the path it drew was a circle three and a half metres
## across. Measured: reversing from 7 m/s swung him 3.65 m sideways and he came
## out of it faster than he went in, having never once slowed down.
##
## Capped, the order of events is the one a footballer uses. At pace he can
## barely turn at all, so the angle he still owes stays large, so the ceiling
## holds his target speed near zero and he brakes in something close to a
## straight line; as the speed comes off, `v * omega` buys a rapidly tightening
## turn, and the last ninety degrees happen almost on the spot. Plant, pivot, go.
const TURN_GRIP := 9.0
## Share of top speed a man can do without turning his hips, sideways and
## backwards alike -- and past which the body is slaved to the run. One
## constant says how fast he can shuffle and past what he must turn.
const STRAFE_SHARE := 0.5
## The slaving releases at this share of the threshold. Entry and release
## differ (INVARIANTS: `_contest_pace`, `_press_side`) or a desired speed on
## the line flips the body every tick.
const STRAFE_RELEASE := 0.8
## Acceleration share at full reverse, linear in the angle between the drive
## and the body. Floored so a standing man can always start: the `TURN_COMMIT`
## deadlock, INVARIANTS.
const OFF_AXIS_ACCEL := 0.5
## Past this angle between the run and the hips, the gait is a shuffle rather
## than a stride: forty-five degrees, where a step across becomes a side-step.
const SHUFFLE_ANGLE := 0.79

var id := -1
var team := SimConsts.TEAM_HOME
## Formation slot this player occupies. Cached because the movement layer asks
## for it ten times a second per player.
var slot := 0
var shirt := 0
var player_name := ""
var role := SimRole.CM
var attrs := SimAttributes.new()
var is_keeper := false
## Seed for the procedural appearance (PLAN.md §9.1). The simulation never reads
## it; it travels with the player so presentation can rebuild the same face.
var appearance_seed := 0

# --- Kinematic state --------------------------------------------------------

var pos := Vector3.ZERO
var vel := Vector3.ZERO
## The body -- hips and shoulders, and the eyes with them -- in radians, as
## atan2(dir.z, dir.x). Slaved to the run unless `look_target` holds it.
var facing := 0.0
## Where the movement or decision layer wants the body pointed; INF means
## face the run. Held between recomputes like `move_target`, and cleared where
## a restart is a fact (`SimScenario.settle`, `SimSetPiece._snap_everyone`).
var look_target := Vector3.INF
## Whether the hips follow the velocity. Latched in `locomote`: slaved above
## `STRAFE_SHARE` of top speed or with no look to hold, released only below
## `STRAFE_SHARE * STRAFE_RELEASE`.
var body_slaved := true

# --- Condition --------------------------------------------------------------

var stamina := 1.0
## The match's clock rate, copied here by `SimMatch.setup`.
##
## Fatigue is the one physical quantity that is denominated in match time rather
## than in seconds. Everything else a player does — how fast he accelerates, how
## sharply he turns, how far the ball goes — is a fact about a body and must not
## know the clock is compressed. Tiredness is a fact about a *match*: "he has
## nothing left after eighty minutes" has to stay true when eighty minutes is
## two and a half minutes of football, or a compressed match has no fatigue arc
## at all and substitutions stop meaning anything. Drain, recovery and the
## per-action cost all scale together, so the stamina a given workload settles
## at is unchanged and only the time taken to get there compresses.
var clock_rate := 1.0
## Match sharpness and morale come from the world layer and scale output
## slightly. 1.0 is neutral.
var sharpness := 1.0
var morale := 0.5

# --- Per-tick intent, written by the movement and decision layers ------------

var desired_vel := Vector3.ZERO
## Where the movement layer last decided this player should be, and how fast
## they are willing to get there. Recomputed on the off-ball cadence and held
## between recomputes.
var move_target := Vector3.ZERO
var move_speed_cap := INF
## How close counts as "there". Wider for shape-holding than for chasing.
var move_deadband := 0.4
## Set when the movement layer has this player timing a run in behind. Such a
## run has to be made precisely -- a striker who is four metres short of the
## shoulder is not making a run, they are standing still.
var making_run := false
## Which arm of `SimMovement._recompute_target` last decided where this player
## should be: a `SimMovement.Errand`. Written by the ladder itself as it goes,
## rather than worked out afterwards from the target, because a second function
## that infers the arm is a model of the first and drifts from it. Read by
## nothing in `sim/` -- it is there so the diagnostics can say which errand
## takes a side out of its shape.
var errand := 0
## Cached gradient-ascent offset and the tick it was computed on. The value
## field is a 5 Hz quantity (PLAN.md §2.5); recomputing it on the 10 Hz movement
## cadence was doing the work twice.
var value_offset := Vector3.ZERO
var value_offset_tick := -1000
var touch_cooldown := 0.0
## When his current spell on the ball began, and how many seconds of flight he
## had to read the incoming ball before it arrived. Stamped by `SimTouch.apply`
## at the first touch of a spell; `SimDecision.readiness` sums them into "has
## he had time to orient, decide, and set himself" (DECISIONS.md, "Waiting is a
## first-class option").
var spell_start_tick := -1
var spell_prep_seconds := 0.0
## Tick at which this player last won the ball back from the opposition. For a
## second or two afterwards his priority is to secure it rather than to advance
## it; `SimDecision.regain_urgency` reads it and decays it.
var regain_tick := -100000
## The tick the ball came into his view, or -1 while it is behind him. Stamped
## by `SimDuel.resolve_contacts`, which lets him play a ball he did not see
## struck only a reaction after this.
var ball_seen_tick := -1
## Tick at which the ball was last taken off this player by an opponent. Read by
## the chase assignment: a man who has just been beaten is not the one who
## should be leading the press back.
var dispossessed_tick := -100000
## The block: a body thrown at a shot. Committed once at the strike by
## `SimDuel.commit_blocks` -- the lunge runs to `block_until`, the ball reaches
## his station at `block_tick`, `block_point` is where on its line he throws
## himself, `block_shot` is the strike it was committed to, and `block_hit` is
## whether the one roll said he gets something on it.
var block_until := -1
var block_tick := -1
var block_point := Vector3.ZERO
var block_shot := -1
var block_hit := false
## Escorting a dying ball over the line (`SimMovement._escort_wanted`): his
## body is between the ball and the man who wants it, and he does not touch
## it. `SimDuel.resolve_contacts` leaves him out while it is set.
var escorting := false
## Standing in a wall at a free kick (`SimSetPiece._wall_spots`): a body that
## does not lunge and does not duck, and the block model reads it as such.
var in_wall := false
## Whether this player's last touch was a settling one -- he put the ball down in
## front of himself and is not going anywhere with it until he decides again.
##
## Written by `SimDecision` and read by `SimMovement`, because the two floors
## that ask a man on the ball for more than "fast enough to arrive" -- driving at
## the space in front of him, and escaping a challenge -- are both about a man
## going somewhere, and a man who has just settled it is not. Without this he
## sprints straight past a ball he has just stopped.
var settling := false
## Whether this player's last touch was a shielded hold -- body between the
## challenger and the ball. Written by `SimDecision`, read by `SimDuel`: the
## contest for a shielded ball is the shielder's to lose, in proportion to his
## strength, and a challenge that has to come through the body is likelier to
## be a foul.
var shielding := false
## Ticks until this player next re-evaluates off-ball movement. Staggered at
## kickoff so no single tick evaluates every player.
var next_decision_tick := 0
var marking_target := -1
var anim := SimConsts.Anim.IDLE
var anim_hold := 0.0

# --- Availability -----------------------------------------------------------

var on_pitch := true
var sent_off := false
var yellow_cards := 0
## Ticks remaining before the player can act again (after a fall or a foul).
var recovery_ticks := 0

# --- Match accumulators (mirrored into telemetry) ---------------------------

var distance_run := 0.0
var touches := 0
var passes_attempted := 0
var passes_completed := 0
var shots := 0
var minutes_played := 0.0


func configure(p_id: int, p_team: int, p_role: int, p_attrs: SimAttributes, p_name: String = "") -> void:
	id = p_id
	team = p_team
	role = p_role
	attrs = p_attrs
	is_keeper = p_role == SimRole.GK
	player_name = p_name if p_name != "" else "P%d" % p_id
	refresh_caps()


## Output multiplier from fatigue: 1.0 above the knee, falling linearly to
## STAMINA_FLOOR_OUTPUT at zero stamina.
func fatigue_factor() -> float:
	if stamina >= SimConsts.STAMINA_FATIGUE_KNEE:
		return 1.0
	return lerpf(SimConsts.STAMINA_FLOOR_OUTPUT, 1.0, maxf(stamina, 0.0) / SimConsts.STAMINA_FATIGUE_KNEE)


## Derived caps, recomputed once per tick rather than on every one of the
## hundreds of arrival-time estimates that ask for them.
var _nominal_speed := 7.5
var _cap_speed := 7.5
var _cap_accel := 4.5
var _cap_decel := 8.1
## What a lost challenge takes out of a man's momentum, as a share of his own
## braking, for as long as `recovery_ticks` lasts.
##
## It was **twice** his maximum deceleration, and that is not a footballer losing
## a fifty-fifty, it is a footballer being stopped. Measured on `1v1-chased`: a
## carrier running at 3.0 m/s lost a duel, was braked to **0.0 m/s in three
## tenths of a second**, and then could not touch the ball for the 0.55-1.1 s
## cooldown `SimDuel` gives the loser -- so the ball that was still his rolled
## two metres away from a man standing still. That is "the ball runs away from
## the player" (owner, 2026-08-23), and it is not a one-on-one problem: every
## lost duel in the match does it.
##
## Off balance rather than stopped. He keeps running; what he has lost is the
## drive and the act, and the act is denied by `can_touch()` -- untouched here,
## and the anti-pinball guard `SimDuel` relies on is that cooldown rather than
## this braking. A man beaten by a feint still reads as beaten, because what
## makes him beaten is the direction he has committed to and `time_to_arrive`
## charges him for that whatever his speed.
const RECOVERY_BRAKE := 0.35

## Reaction delay before acting on new information. Constant for a match.
var reaction := 0.26
var _caps_countdown := 1


## Recomputes the per-tick derived caps. Called once per player per tick, and
## whenever attributes or condition change outside a match.
func refresh_caps() -> void:
	_nominal_speed = lerpf(SimConsts.SPEED_MIN, SimConsts.SPEED_MAX, attrs.pace)
	var f := fatigue_factor()
	_cap_speed = _nominal_speed * f * sharpness
	_cap_accel = lerpf(SimConsts.ACCEL_MIN, SimConsts.ACCEL_MAX, attrs.acceleration) * f
	_cap_decel = lerpf(SimConsts.DECEL_MIN, SimConsts.DECEL_MAX, attrs.acceleration) * f
	reaction = lerpf(0.36, 0.16, attrs.awareness)


func nominal_max_speed() -> float:
	return _nominal_speed


func max_speed() -> float:
	return _cap_speed


## Acceleration off the mark. See `accel_at` for what is left of it at speed.
func max_accel() -> float:
	return _cap_accel


## Acceleration available at `speed`: the off-the-mark figure, falling
## linearly to nothing at top speed. `SimValueField.time_to_arrive` and
## `reach_in` solve this same law; change one and change the other.
func accel_at(speed: float) -> float:
	return _cap_accel * clampf(1.0 - speed / maxf(_cap_speed, 0.1), 0.0, 1.0)


func max_decel() -> float:
	return _cap_decel


## Turn rate falls off with speed. This single line is why fast players overrun
## the ball and why a sharp change of direction beats a quicker opponent
## (PLAN.md §3.2) -- do not simplify it away.
func turn_rate(speed: float) -> float:
	var base: float = SimConsts.TURN_BASE * lerpf(0.8, 1.25, attrs.agility)
	return base / (1.0 + speed * SimConsts.TURN_SPEED_FALLOFF)


func heading_dir() -> Vector3:
	return Vector3(cos(facing), 0.0, sin(facing))


func speed() -> float:
	return vel.length()


## Sets the intent for this tick: run toward `target` at up to `speed_cap`.
##
## `deadband` is the radius inside which the player is close enough and simply
## stops. Without it, players chase a target that moves every time the ball does
## and end a match having run twice as far as a real footballer.
func steer_to(target: Vector3, speed_cap: float = INF, deadband: float = 0.4) -> void:
	var dx := target.x - pos.x
	var dz := target.z - pos.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < deadband:
		desired_vel = Vector3.ZERO
		return
	var cap: float = minf(speed_cap, max_speed())
	# Approach at the pace he can still stop from, `sqrt(2 a d)` for the ground
	# left, so he settles onto a spot instead of overrunning it and coming
	# back. It was a fixed ease-off over the last 1.6 m, which the old brakes
	# could honour from a sprint and the real ones cannot: with braking cut to
	# 5.5-8 m/s^2 and that band kept, mean speed over a match rose from 2.09
	# to 2.63 m/s, all of it men running past their spots. The floor keeps him
	# walking the last stride rather than creeping.
	var room: float = maxf(dist - deadband, 0.0)
	var wanted: float = clampf(sqrt(2.0 * max_decel() * room), cap * 0.15, cap)
	var scale := wanted / dist
	desired_vel = Vector3(dx * scale, 0.0, dz * scale)


## Integrates locomotion for one step. Turn-rate limiting comes first, so a
## player cannot instantly reverse at speed.
func locomote(dt: float) -> void:
	# Stamina moves slowly, so the derived caps do not need recomputing sixty
	# times a second. Staggered by id so the cost is spread across ticks.
	_caps_countdown -= 1
	if _caps_countdown <= 0:
		_caps_countdown = 6
		refresh_caps()
	if recovery_ticks > 0:
		recovery_ticks -= 1
		vel = vel.move_toward(Vector3.ZERO, max_decel() * RECOVERY_BRAKE * dt)
		pos += vel * dt
		return

	# Hand-rolled 2D rotation. Vector3.rotated() builds a Basis, which is far
	# too much machinery for twenty-two players sixty times a second.
	var cur_speed := sqrt(vel.x * vel.x + vel.z * vel.z)
	var looking := not is_inf(look_target.x)
	if cur_speed < 0.02 and desired_vel.x == 0.0 and desired_vel.z == 0.0:
		# Standing still and asked to stay there. Half the squad is in this
		# state at any moment, so it is worth the early exit. The receiver
		# waiting for the ball is this man, and his body still turns.
		vel = Vector3.ZERO
		if looking:
			body_slaved = false
			_turn_body(0.0, dt)
		_update_stamina(dt, 0.0)
		_update_anim(0.0, false)
		if touch_cooldown > 0.0:
			touch_cooldown = maxf(0.0, touch_cooldown - dt)
		return
	var desired_speed := sqrt(desired_vel.x * desired_vel.x + desired_vel.z * desired_vel.z)
	# The body: slaved to the run, or held on the look. Latched, because a
	# desired speed on the threshold would otherwise flip it every tick, and
	# a chase is never slowed by a look -- the sprint takes the hips with it.
	if not looking or desired_speed > max_speed() * STRAFE_SHARE:
		body_slaved = true
	elif desired_speed < max_speed() * STRAFE_SHARE * STRAFE_RELEASE:
		body_slaved = false
	var want_x := 0.0
	var want_z := 0.0
	if desired_speed > 1e-4:
		want_x = desired_vel.x / desired_speed
		want_z = desired_vel.z / desired_speed
	var dir_x := 0.0
	var dir_z := 0.0
	if cur_speed > 0.05:
		dir_x = vel.x / cur_speed
		dir_z = vel.z / cur_speed
	elif body_slaved or desired_speed <= 1e-4:
		dir_x = cos(facing)
		dir_z = sin(facing)
	else:
		# A standing man with his hips held steps off in any direction: the
		# side-step is what a held body is for.
		dir_x = want_x
		dir_z = want_z
	if desired_speed <= 1e-4:
		want_x = dir_x
		want_z = dir_z

	# Signed angle from current heading to desired heading, about +Y.
	var cross := dir_x * want_z - dir_z * want_x
	var dot: float = clampf(dir_x * want_x + dir_z * want_z, -1.0, 1.0)
	var turn_needed := atan2(cross, dot)
	# What his body will do, and then what the ground will let him do with it.
	var max_turn: float = minf(turn_rate(cur_speed), TURN_GRIP / maxf(cur_speed, 0.35)) * dt
	var applied_turn: float = clampf(turn_needed, -max_turn, max_turn)
	var ca := cos(applied_turn)
	var sa := sin(applied_turn)
	var new_dir := Vector3(dir_x * ca - dir_z * sa, 0.0, dir_x * sa + dir_z * ca)

	# A player cannot hold top speed through a hairpin: the sharper the turn still
	# to be made, the lower the speed he can carry. Priced as the sideways ground
	# the turn would cost him at this pace -- see `TURN_SWING`.
	var swing := 1.0 - cos(turn_needed)
	var speed_ceiling := max_speed()
	if not body_slaved:
		speed_ceiling = minf(speed_ceiling, max_speed() * STRAFE_SHARE)
	if swing > 1e-3:
		speed_ceiling = minf(speed_ceiling, sqrt(TURN_GRIP * TURN_SWING / swing))
	var target_speed: float = minf(desired_speed, speed_ceiling)
	# And he does not drive out of a turn he has not finished yet. The ceiling
	# above is read off the angle still owed, so it lifts steadily as he comes
	# round, and left to itself he starts accelerating about a third of the way
	# through -- the remaining two thirds are then made at a rising speed, and
	# since grip fixes the radius at v^2/g, that is precisely how an arc widens
	# into a circle. He may still shed speed at any point; he simply may not add
	# it while he is pointing the wrong way.
	#
	# Only once he is actually travelling. A man at a standstill has no momentum
	# to fight and turns on the spot, and applying it to him deadlocks the
	# locomotion outright: he may not accelerate until he has turned, `vel` is
	# `new_dir * cur_speed` so a speed of zero cannot express a turn, and `facing`
	# is only written when he is moving -- so he stands still facing the wrong way
	# for the rest of the match. Measured with the guard missing, mean speed over
	# the whole match fell from 2.4 m/s to 0.6 and the touch count with it.
	if cur_speed > TURN_PIVOT and absf(turn_needed) > TURN_COMMIT:
		target_speed = minf(target_speed, cur_speed)

	var was_speed := cur_speed
	var run := atan2(new_dir.z, new_dir.x)
	if target_speed > cur_speed:
		var push := accel_at(cur_speed)
		if not body_slaved:
			# Driving off the hips costs him: a shuffle starts slower than a
			# stride, and a backpedal slower still.
			push *= lerpf(1.0, OFF_AXIS_ACCEL, absf(angle_difference(facing, run)) / PI)
		cur_speed = minf(target_speed, cur_speed + push * dt)
	else:
		cur_speed = maxf(target_speed, cur_speed - max_decel() * dt)

	vel = new_dir * cur_speed
	pos += vel * dt
	pos.y = 0.0
	if body_slaved:
		if cur_speed > 0.05:
			# The velocity turned at most `max_turn`, which is inside the
			# body's own rate, so a body on the run stays on it exactly; a
			# body caught off it -- a look just released -- turns onto it at
			# the rate the hips have, rather than snapping.
			var most: float = turn_rate(cur_speed) * dt
			var owed: float = angle_difference(facing, run)
			if absf(owed) <= most:
				facing = run
			else:
				facing += clampf(owed, -most, most)
	else:
		_turn_body(cur_speed, dt)
	distance_run += cur_speed * dt

	_update_stamina(dt, cur_speed)
	_update_anim(cur_speed, absf(applied_turn) > max_turn * 0.9 and absf(was_speed - cur_speed) > 0.0)

	if touch_cooldown > 0.0:
		touch_cooldown = maxf(0.0, touch_cooldown - dt)


## Turns the body toward `look_target` at the hips' rate for this pace.
func _turn_body(cur_speed: float, dt: float) -> void:
	var dx := look_target.x - pos.x
	var dz := look_target.z - pos.z
	if dx * dx + dz * dz < 0.01:
		return
	var most: float = turn_rate(cur_speed) * dt
	facing += clampf(angle_difference(facing, atan2(dz, dx)), -most, most)


func _update_stamina(dt: float, cur_speed: float) -> void:
	var ratio: float = cur_speed / maxf(nominal_max_speed(), 1e-3)
	# Endurance scales the drain; a high work rate means a player chooses to run
	# more, which the movement layer expresses, not this function.
	var endurance: float = lerpf(1.4, 0.7, attrs.stamina)
	# Match time, not wall time: see `clock_rate` above.
	var elapsed := dt * clock_rate
	if ratio < 0.15:
		stamina = minf(1.0, stamina + SimConsts.STAMINA_RECOVERY * elapsed / maxf(endurance, 0.1))
	else:
		stamina -= (SimConsts.STAMINA_SPRINT_DRAIN * ratio * ratio + SimConsts.STAMINA_BASE_DRAIN) * elapsed * endurance
		stamina = maxf(0.0, stamina)


## Charges the per-action stamina cost of a touch, a tackle or a jump.
##
## Scaled by the clock rate for the same reason the drain is: a compressed match
## contains proportionally fewer actions, so an unscaled cost would leave a side
## as fresh at full time as it was at kick-off.
func spend_action(cost_scale: float = 1.0) -> void:
	var cost := SimConsts.STAMINA_ACTION_COST * cost_scale * clock_rate * lerpf(1.4, 0.7, attrs.stamina)
	stamina = maxf(0.0, stamina - cost)


func _update_anim(cur_speed: float, turning: bool) -> void:
	if anim_hold > 0.0:
		anim_hold -= SimConsts.DT
		return
	var nominal := nominal_max_speed()
	if stamina < 0.18 and cur_speed < 1.0:
		anim = SimConsts.Anim.EXHAUSTED
	elif turning and cur_speed > nominal * 0.4:
		anim = SimConsts.Anim.TURN
	elif cur_speed < 0.4:
		anim = SimConsts.Anim.IDLE
	elif absf(angle_difference(facing, atan2(vel.z, vel.x))) > SHUFFLE_ANGLE:
		anim = SimConsts.Anim.SHUFFLE
	elif cur_speed < nominal * 0.45:
		anim = SimConsts.Anim.JOG
	elif cur_speed < nominal * 0.8:
		anim = SimConsts.Anim.RUN
	else:
		anim = SimConsts.Anim.SPRINT


## Plays a one-shot animation for `hold` seconds; the sim never reads it back.
func play_anim(which: int, hold: float = 0.25) -> void:
	anim = which
	anim_hold = hold


func touch_cooldown_length() -> float:
	return lerpf(SimConsts.TOUCH_COOLDOWN_BASE, SimConsts.TOUCH_COOLDOWN_MIN, attrs.technique)


func can_touch() -> bool:
	return touch_cooldown <= 0.0 and recovery_ticks <= 0 and on_pitch


## Horizontal distance from this player to a point.
func dist_to(p: Vector3) -> float:
	var dx := pos.x - p.x
	var dz := pos.z - p.z
	return sqrt(dx * dx + dz * dz)


func dist_sq_to(p: Vector3) -> float:
	var dx := pos.x - p.x
	var dz := pos.z - p.z
	return dx * dx + dz * dz


## Highest ball this player can reach, standing. Jumping is resolved separately
## in the header contest.
func reach_height() -> float:
	return lerpf(SimConsts.FOOT_REACH_HEIGHT, SimConsts.HEAD_REACH_HEIGHT, 0.0)
