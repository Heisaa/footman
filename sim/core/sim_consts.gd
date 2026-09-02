class_name SimConsts
extends RefCounted
## Physical and geometric constants for the match simulation.
##
## Every number here is a starting point for tuning, as PLAN.md §0 says. They
## are chosen to be physically plausible rather than final.
##
## Coordinate system: +X runs along the length of the pitch toward the away
## goal, +Y is up, +Z runs along the width. The origin is the centre spot. All
## units are metres, seconds, kilograms and radians.

# --- Clock ------------------------------------------------------------------

const TICK_HZ := 60
const DT := 1.0 / 60.0
## Decision cadences, expressed in ticks. Never in seconds of frame time.
const ON_BALL_DECISION_TICKS := 6  # 10 Hz
const OFF_BALL_DECISION_TICKS := 6  # 10 Hz, staggered across players
const VALUE_FIELD_TICKS := 12  # 5 Hz
const PRESSURE_TICKS := 6  # 10 Hz; pressure changes far slower than the tick rate
## The shared forecast only needs redoing while the ball is actually going
## somewhere. A rolling ball's future barely changes from tick to tick.
const FORECAST_IDLE_TICKS := 6
const TRACE_TICKS := 12  # 5 Hz positional trace

# --- Pitch ------------------------------------------------------------------

const PITCH_LENGTH := 105.0
const PITCH_WIDTH := 68.0
const HALF_LENGTH := 52.5
const HALF_WIDTH := 34.0
const GOAL_WIDTH := 7.32
const GOAL_HALF_WIDTH := 3.66
const GOAL_HEIGHT := 2.44
## The net, which is geometry both sides of the wall need: presentation draws it
## and the simulation stops a scored ball in it, now that a ball is left running
## for `SimMatch.DEAD_BALL_LINGER` after it crosses the line instead of being
## picked up the instant it goes in. Regulation is at least 1.5 m at the top and
## 2.0 at the foot; the roof slopes back from the crossbar to the top of the
## back netting.
const NET_DEPTH_TOP := 1.6
const NET_DEPTH_FOOT := 2.2
## Height of the top of the back netting, where the sloping roof meets it.
const NET_BACK_HEIGHT := 1.75
const PENALTY_AREA_DEPTH := 16.5
const PENALTY_AREA_HALF_WIDTH := 20.16
const GOAL_AREA_DEPTH := 5.5
const GOAL_AREA_HALF_WIDTH := 9.16
const PENALTY_SPOT_DIST := 11.0
const CENTRE_CIRCLE_RADIUS := 9.15

# --- Ball -------------------------------------------------------------------

const BALL_RADIUS := 0.11
const BALL_MASS := 0.43
const BALL_AREA := PI * BALL_RADIUS * BALL_RADIUS
const AIR_DENSITY := 1.225
## Drag coefficient, which a football does not have one of.
##
## The boundary layer on a ball this size goes turbulent somewhere around 12-15
## m/s, and the drag coefficient falls off a cliff when it does: about 0.45 below
## the transition, about 0.2 above it. This is the drag crisis, and it is the
## reason a hard-struck ball carries the way it does while a gently chipped one
## dies.
##
## A single coefficient in the middle of that gets both ends wrong, and it gets
## them wrong in the direction that reads worst: it over-drags the shot, which is
## the thing that should look fast, and under-drags the floated ball, which is
## the thing that should not hang. The flat 0.25 here did exactly that.
const DRAG_COEFF_SLOW := 0.45
const DRAG_COEFF_FAST := 0.20
## Middle of the transition, m/s, and how wide it is.
const DRAG_CRISIS_SPEED := 13.5
const DRAG_CRISIS_WIDTH := 4.5
## a_drag = drag_k(|v|) * |v| * v.
const DRAG_AREA_FACTOR := 0.5 * AIR_DENSITY * BALL_AREA / BALL_MASS
## Magnus, as a lift coefficient that saturates with the spin factor
## S = |omega_perp| r / |v|, rather than a force linear in spin.
##
## The linear form was calibrated at one point — 6 rad/s of sidespin bending a
## 30 m cross about 2 m (PLAN.md §3.1) — where S is about 0.02. It is accurate
## there and nonsense everywhere else, because real lift saturates around
## Cl = 0.3 while a linear model keeps climbing. A ball that has just bounced is
## rolling without slipping at 70-100 rad/s, and the linear force put 8 m/s^2 of
## downforce on it between hops: nearly a second gravity, applied to every
## bouncing ball in the match. Struck backspin was worse in the other direction.
##
## Cl = CL_MAX * S / (S + S_HALF) reproduces the calibration point and flattens
## out past it. a = MAGNUS_K * Cl * |v|^2, along the unit of omega x v.
const MAGNUS_CL_MAX := 0.33
const MAGNUS_S_HALF := 0.11
const MAGNUS_K := DRAG_AREA_FACTOR
const GRAVITY := 9.81
## Multiplicative spin decay per tick while in flight.
const SPIN_DECAY := 0.995
## Spin about the vertical axis bleeds away faster once the ball is on grass.
const GROUND_YAW_SPIN_DECAY := 0.985
const RESTITUTION_DRY := 0.6
const RESTITUTION_WET := 0.45
const SLIDE_FRICTION := 0.4
## Rolling resistance, once the ball has stopped slipping and is rolling.
##
## Deceleration in m/s^2, so the coefficient of rolling resistance is this over
## g: 1.0 is about 0.10, which is where a football on a mown pitch sits. This was
## 0.5 (a coefficient of 0.05, nearer a bowling green), and the tell was a ball
## rolling at walking pace taking four seconds and four metres to stop.
##
## It is now 2.4, which is well past what a physicist would sign off on and is a
## choice about how the match reads rather than about grass. At the textbook
## figure a firm ground pass that missed its man ran better than thirty metres,
## so nothing ever settled, every loose ball became a foot race to the touchline
## and the pitch played bigger than it is. Passes self-correct, because
## `SimBallistics` solves the launch speed against this same number: they are
## struck harder rather than arriving short.
##
## Raised from 1.6 on the same complaint one step further on -- the ball still
## read as running away from people. Worth being plain that the measurement did
## not support the reason: what makes the ball look lively is the pace it is
## *struck* at, and a ground pass arrives at a man's feet at about 8.7 m/s
## whatever this number is, because the launch speed is solved against it. What
## this does change is every ball nobody meant to strike -- deflections, blocks,
## a tackle's poke, a clearance that has landed -- and how long a loose one stays
## loose. A ball struck at 15 m/s now runs 38 m rather than 50.
##
## The number this really wanted was the carry's, which is not a number any
## more: `SimTouch` used to hold a second, quietly different rolling
## deceleration for a dribbled ball, and it now reads this one. See
## `SimTouch.dribble`.
##
## Grass length and wetness are separate effects and move in opposite
## directions, so they compose rather than sharing a branch. Long grass kills a
## rolling ball; a wet surface is greasy and the ball runs on faster. Wet long
## grass is still slower than a dry mown pitch, which is the right ordering.
const ROLL_DECEL_DRY := 2.4
const ROLL_DECEL_LONG_GRASS := 3.4
const ROLL_DECEL_WET_FACTOR := 0.85
## Below this downward speed a bounce is not worth resolving; the ball settles.
const BOUNCE_SNAP_VY := 0.35
## Contact-point slip below this is treated as rolling without slipping.
const SLIP_EPSILON := 0.02
## Sphere constant: the tangential impulse needed to kill slip is 2/7 m |u|.
const SPHERE_SLIP_FACTOR := 2.0 / 7.0
## And slip decays at 7/2 times the linear friction deceleration.
const SPHERE_SLIP_RATE := 7.0 / 2.0
## A rolling sphere on a slope accelerates at 5/7 g sin(theta), not g sin(theta):
## the rest goes into spinning it up.
const SPHERE_ROLL_SLOPE := 5.0 / 7.0

# --- Surface ----------------------------------------------------------------
#
# The pitch is not a plane, and a ball rolling on one looks like a ball on a
# table. Two things are missing, and they work at different scales.
#
# The camber is the big one: a pitch is built higher down the middle than at the
# touchlines so that it drains, by something between fifteen and thirty
# centimetres. That is a tenth of a degree of fall — invisible as height, and
# entirely visible in the ball, because it is the one slope that does not change
# sign under a rolling ball. A ball played across the pitch bends away downhill
# the whole way.
#
# The undulation is the small one: a couple of centimetres over a few metres.
# It averages out over a long roll, so it is not what makes the ball wander; it
# is what makes the ball bob, and what makes no two bounces come up the same
# way, because the ball meets the grass on a face that is tilted a degree or so
# in some direction it did not choose.
#
# Both are fixed functions of position rather than noise: the ball's future is
# forecast by re-integrating this same code, and neither the forecast nor a
# replay may consume `ctx.rng`.

## Height of the middle of the pitch over the touchlines, metres.
const SURFACE_CAMBER := 0.20
## Peak height of the undulation, metres.
const SURFACE_AMPLITUDE := 0.024
## Wave numbers of the three components, rad/m. Deliberately not commensurate,
## so the pattern does not repeat within a pitch.
const SURFACE_K1 := 1.27
const SURFACE_K2 := 0.83
const SURFACE_K3 := 2.19
## Below this ground speed the slope stops pushing the ball. Rolling resistance
## holds a ball still on a gentle slope, and without the cutoff a ball at rest
## creeps downhill for ever.
const SURFACE_SLOPE_MIN_SPEED := 0.45

# --- Trajectory forecast ----------------------------------------------------

const FORECAST_HORIZON := 2.5
const FORECAST_DT := 1.0 / 30.0
const FORECAST_STEPS := 75

# --- Player locomotion ------------------------------------------------------

## Speed was raised from 6.9-9.7 at the owner's direction, watching: the ball
## read too fast and the players too slow, both off the mark and flat out.
## Real sprint data sits around 8-10.5 m/s for professionals, so the ceiling
## at 10.4 is an elite sprinter and the floor a heavy centre-half. The other
## half of the same feel change is `SimDecision.arrival_pace`, which came down
## a tenth.
const SPEED_MIN := 7.4
const SPEED_MAX := 10.4
## Acceleration off the mark, m/s^2. It falls linearly to zero at top speed
## (`SimPlayer.accel_at`), which is the standard sprint model: speed approaches
## its ceiling as 1 - e^(-t / tau) with tau = top speed / this, 0.9-1.0 s here
## against 1.0-1.3 measured on professionals. Measured 2026-09-01 with a
## constant 4.0-8.4: every player was at top speed inside 1.5 s and 7 m, where
## a real one takes four seconds and thirty metres, so the top of the range
## ran 30 m in 3.50 s -- a track sprinter -- and the difference between a
## quick man and a fast one collapsed. Now a mid player runs 10/20/30 m in
## 1.96/3.17/4.32 s and the best in 1.73/2.78/3.77, against tracked
## professionals at about 1.85/3.05/4.25 and 1.7/2.85/3.85.
const ACCEL_MIN := 7.0
const ACCEL_MAX := 11.5
## Braking, m/s^2. It was 1.8 x acceleration -- 7 to 15 -- and no body brakes
## at 15: a player stopped from a sprint in 3.5 m and 0.8 s, and reversed in
## under a second, which erased most of the overrun the turn model is built to
## produce. Peak deceleration in tracked football sits at 6-8, so a stop from
## top speed is 5-9 m and a second and a half.
const DECEL_MIN := 5.5
const DECEL_MAX := 8.0
## Turn rate at a standstill, in rad/s. Falls off as `TURN_BASE / (1 + v * TURN_SPEED_FALLOFF)`.
const TURN_BASE := 9.0
const TURN_SPEED_FALLOFF := 0.35
## Soft separation capsule radius.
const PLAYER_RADIUS := 0.35
const PLAYER_SEPARATION := 0.7

# --- Stamina ----------------------------------------------------------------

## Fraction of stamina drained per second at full sprint, before attributes.
## Calibrated so a player covering 10-11 km finishes a match around 0.55-0.7.
const STAMINA_SPRINT_DRAIN := 1.0 / 2000.0
const STAMINA_BASE_DRAIN := 1.0 / 30000.0
const STAMINA_ACTION_COST := 0.0008
## Stamina below this fraction starts degrading physical output.
const STAMINA_FATIGUE_KNEE := 0.4
## Output multiplier at zero stamina.
const STAMINA_FLOOR_OUTPUT := 0.75
## Recovery per second while walking or standing.
const STAMINA_RECOVERY := 1.0 / 3000.0

# --- Touch ------------------------------------------------------------------

## Horizontal distance within which a player may contact the ball, measured from
## the player's centre.
##
## This has to be a distance the character can be seen to reach, or every touch
## looks magnetic. The leg is 0.46 of height — about 0.82 m — so a full-stretch
## contact is roughly 0.9 m from the centre once the boot and the ball's radius
## are counted. At 1.2 m over half of all touches were being made in the outer
## band of the radius, visibly short of the ball.
const CONTROL_RANGE := 0.9
## Highest ball a standing player can play with a foot.
const FOOT_REACH_HEIGHT := 0.75
## Highest ball a player can head, before jumping.
##
## Measured off the drawn figure rather than guessed, because this number is the
## one a viewer checks by eye: the head sits at about 1.7 m and its crown at
## about 2.0, so 2.0 is a ball met at full stretch on tiptoe. At 2.35 the contact
## was half a metre over the crown — the ball changed direction in clear air and
## nobody could see what had touched it, which is exactly the complaint that
## headers bounce above the head. `SimTouch.playable_height` adds the leap on top.
const HEAD_REACH_HEIGHT := 2.0
const TOUCH_COOLDOWN_BASE := 0.27
const TOUCH_COOLDOWN_MIN := 0.17
## Shot speed range, scaled by the power attribute. Came down from 18-32 with
## the rest of the ball (owner's direction, same session as the player speeds
## going up): 27 m/s is still a 97 km/h drive, and against the faster players
## the old 32 read like a tracer. The keeper's chances rise with the slower
## ball, which is the fit's business, not this constant's.
const SHOT_SPEED_MIN := 16.0
const SHOT_SPEED_MAX := 27.0

# --- Teams ------------------------------------------------------------------

const TEAM_HOME := 0
const TEAM_AWAY := 1

enum Period { FIRST_HALF, HALF_TIME, SECOND_HALF, FULL_TIME }

## Phase of play. Drives off-ball offsets and tactical modifiers.
enum Phase { KICKOFF, BUILD_UP, ATTACK, TRANSITION_TO_DEFEND, TRANSITION_TO_ATTACK, DEFEND, SET_PIECE, DEAD_BALL }

## Animation state hints handed to the presentation layer. The simulation never
## reads these back.
## Appended to, never reordered: the snapshot carries the anim as its integer,
## and the pose sheet indexes the same list.
## `SHUFFLE` is the gait of a body held off its run: a side-step or a
## backpedal, picked by `SimPlayer._update_anim` off the angle between the
## velocity and the hips. Appended, so the states before it keep their numbers.
enum Anim { IDLE, JOG, RUN, SPRINT, TURN, KICK_LIGHT, KICK_HARD, HEADER, SLIDE, FALL, GET_UP, CELEBRATE, DEJECTED, EXHAUSTED, DIVE_LEFT, DIVE_RIGHT, KEEPER_CATCH, THROW, KEEPER_HOLD, HOLD, CHEST, SHUFFLE, PUNCH, TACKLE, STUMBLE, JUMP, PROTEST, TRAP, VOLLEY }


static func other_team(team: int) -> int:
	return TEAM_AWAY if team == TEAM_HOME else TEAM_HOME


static func horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func horizontal_length(v: Vector3) -> float:
	return sqrt(v.x * v.x + v.z * v.z)


## Drag factor at a given speed: a_drag = drag_k(|v|) * |v| * v. The sigmoid is
## the algebraic one rather than tanh, which is a hair cheaper and is called for
## every step of every trajectory forecast in the match.
static func drag_k(speed: float) -> float:
	var u := (speed - DRAG_CRISIS_SPEED) / DRAG_CRISIS_WIDTH
	var fast := 0.5 * (1.0 + u / sqrt(1.0 + u * u))
	return DRAG_AREA_FACTOR * lerpf(DRAG_COEFF_SLOW, DRAG_COEFF_FAST, fast)
