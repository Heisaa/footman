# Animation improvements

Working list, started 2026-09-05. Keep this file current across sessions.
An implementation is not visually accepted until the owner has watched it.

## Watching the changes

Run `./run.sh animation-study` for close-up, repeating animation samples at
quarter speed. `./run.sh animation-study --group 4` starts on a particular group.

| Key | Action |
|---|---|
| 1–5 | Select a group |
| N | Next group |
| R | Replay the current group |
| Space | Pause/resume |
| [ / ] | Slower/faster |
| , / . | Pause and step backward/forward one simulation tick |
| F / F11 | Toggle fullscreen |
| Escape | Close |

The groups show:

1. Acceleration, braking, backpedalling, a stationary turn and side steps.
2. Pass cushioning and moving dribble touches, on each foot.
3. Shielding with an opponent on either side, then tackles on each foot.
4. A header, a jump, landing compression, falling and getting up.
5. Low/high catches and volleys on each foot.

These are controlled snapshots fed through the match's actual animation and
contact solvers. Each group loops after eight simulated seconds, with captions
at each sample change. They show the implemented poses; live football decisions
and collision outcomes still need review in a match. The original `./run.sh
study` remains the repeatable live pass example.

The samples live in `presentation/animation_study.gd`. Verified by compiling
and sampling all five groups in the real view headlessly, including group
selection and stepping; the underlying match stayed at tick zero throughout.

## Order of work

1. Grounded locomotion, braking and turning (actions 1–5).
2. Dribbling and first touches (6–9).
3. Tackles, shielding and collisions (15–20).
4. Headers, landings, falls and getting up (13–14, 20–21).
5. Keeper actions and delivery variants (10–12, 22–25).

Idle movement and reactions (26) follow these five groups.

## Actions

| # | Action | Improvement | Status |
|---|---|---|---|
| 1 | Walking, jogging and sprinting | Anchor each supporting boot while the hips move over it. Keep the speed/leg-length cadence; make push-off and sprint flight clearer. | First pass; needs visual review |
| 2 | Starting and accelerating | Lower the body, lean into movement and push from a supporting leg. Short driving steps grow with speed. | First pass; needs visual review |
| 3 | Stopping | Brake with feet ahead of the hips, absorb momentum with bent knees and finish with a settling step. Scale to deceleration. | First pass; needs visual review |
| 4 | Turning and changing direction | Plant, lower the hips, rotate and push away. Distinguish a running curve, sharp cut and stationary pivot. | First pass; sharp cuts remain |
| 5 | Sideways movement, jockeying and backpedalling | Lower stance, lateral pushes and short uncrossed jockeying steps. Turn the hips when breaking into a chase. | First pass; needs visual review |
| 6 | Dribbling | Compact foot movement at each real touch, short under pressure and longer at speed. Blend the touching leg back into the stride. | First pass; needs visual review |
| 7 | Receiving a ground pass | Reach before arrival, withdraw the boot to cushion, and orient the hips and foot toward the intended first touch. Step after the ball. | Contact/cushion pass; anticipation remains |
| 8 | Stopping or holding the ball underfoot | Solve sole–ball and support-foot–turf contact. Transfer weight to the standing leg and release with a visible roll or push. | Planned |
| 9 | Chest control | Prepare before arrival, meet the ball, yield through torso and knees, then follow its drop and position for the next touch. | Actual contact timing added; pose work remains |
| 10 | Shots and driven kicks | Stronger hip rotation, folded backswing and late lower-leg extension. Match the boot surface to the strike and step through recovery. | Planned |
| 11 | Chips, crosses and lofted passes | Distinct scoop, lift and wrapping follow-through shapes matched to the actual delivery. | Planned |
| 12 | Volleys | Adjust to ball height and direction, counterbalance with the torso, solve boot contact and land convincingly. | Foot contact added; variants/recovery remain |
| 13 | Headers | Approach, bend and take off before contact; drive torso and forehead through the ball, then absorb the landing. | Timing/landing pass; take-off remains |
| 14 | Jumps and aerial contests | Separate standing, running and wall jumps. Explicit take-off, flight and landing; both contestants attend to the same ball and react to actual contact. | Landing pass; anticipation/contests remain |
| 15 | Standing tackles | Plant and reach for the actual ball. Separate compact pokes and stretching lunges; recover according to win, miss or being beaten. | Foot contact added; variants remain |
| 16 | Sliding tackles | Drop onto a hip, extend the appropriate leg and trail the other. Maintain turf contact while slowing, then recover from that resting pose. | Planned |
| 17 | Shot blocks | Separate foot blocks, turned-body blocks and spreading lunges. React where the ball actually hits. | Planned |
| 18 | Shielding | Widen stance, put the body between opponent and ball, lean toward pressure and choose the balancing arm from the opponent's side. | Arm/lean follow nearby opponent; stance remains |
| 19 | Shoulder challenges and collisions | Coordinate both players at the same contact moment/direction. Brace, compress, displace and recover according to the simulated outcome. | Planned |
| 20 | Stumbling and falling | Follow the disturbance and remaining momentum. Try a recovery step where appropriate; distinguish forward, sideways and backward falls. | Planned |
| 21 | Getting up | Replace the reversed fall with hands bracing, knee underneath, foot planting, hips rising and a step away. Start from front, side or back. | Staged prone get-up added; contact/variants remain |
| 22 | Keeper readiness and positioning | Crouch with hands available, take adjustment steps and set before saving. Turn into a run for larger movements. | Planned |
| 23 | Keeper dives | Push from a foot and reach toward the actual interception. Separate low collapses and high extensions; land through side/shoulder and gather or recover. | Planned |
| 24 | Keeper catches and punches | Reach before contact, absorb catches through elbows/torso and drive punches through. Separate scoops, chest catches and overhead catches. | Catch absorption/height and punch landing pass; hand contact remains |
| 25 | Throw-ins and keeper distribution | Keep hand–ball contact through preparation and correct release timing. Transfer weight and follow through; separate rolls, throws and punts. | Planned |
| 26 | Idle movement and reactions | Restrained weight shifts, purposeful attention to play, and celebrations/protests/exhaustion that blend with movement and stopping steps. | Planned |

## Shared requirements

- Give actions preparation, contact and recovery timing, plus contact position
  and direction. Several current poses only start after the ball has left.
- Reuse the pass's leg contact solver where appropriate. Account for the actual
  model's proportions and limit reach rather than stretching limbs.
- Keep match outcomes and player movement authoritative in the simulation.
  Presentation contact must not drag the player or ball to fit a pose.
- Release planted feet before they become unreachable. Reset presentation
  history when seeking, rewinding or changing action.
- Show weight and intent clearly with the existing toy figures.

## Session log

### 2026-09-05 — first movement pass

Started priority 1 in `presentation/match_view_3d.gd`, building on the existing
uncommitted pass/contact work, then made a first pass in each of priorities 2–5.

Implemented:

- Supporting ankles stay at a world-space turf anchor, with a roll over the
  boot's toe at push-off. Sprint support is shorter to leave flight between
  steps. Excessive reach fades the constraint rather than stretching a leg.
- Smoothed acceleration changes torso lean and body height. Braking shortens
  the stride, brings the feet forward and bends the knees more.
- Stopped players gather their feet with a small, alternating settling step.
- Stationary turns get a stepping cadence; moving turns lower the body.
- Lateral movement gets a shorter stride and wider, lower stance, with inward
  hip swing limited. Backpedalling now reverses the fore/aft leg swing, and its
  cadence accounts for the shorter stride.
- Contact, acceleration, turn and gait history reset across replay jumps.
  Named actions release gait anchors, leaving the existing strike solver in
  charge of kicks.

Still to refine in priority 1: deliberate outside-foot selection for sharp
cuts, dedicated first driving steps, and transitions between jockeying and a
full chase. Watch normal match movement, quick stops and reversals, both travel
directions, and the transition into/out of the improved pass before tuning.

### 2026-09-05 — first passes in priorities 2–5

Added actual touch kind, tick, position and incoming/outgoing velocity to the
player's presentation observations and snapshot copies. These stay separate
from a queued kick's forecast. Repeated traps now restart from their own touch
tick even if the animation enum has not changed; headers, chest controls and
catches also receive their actual contact time/height.

- **Ball control:** dribbles use a compact nudge sized by the outgoing pace
  relative to the player, blended into the running stride. The striking boot
  meets the actual contact. Traps present the inside of the boot to the arriving
  ball and withdraw in its direction, with the other foot supporting the body.
- **Player contact:** standing tackles target the actual ball contact and plant
  the other foot. Shielding mirrors its arm and lean toward the nearby opponent;
  a small deadband prevents swapping arms when he is directly behind.
- **Recovery:** a brace/kneel/rise sequence replaces the reversed fall. Headers,
  jumps and punches compress through the knees on landing; header/jump pose
  durations now match the ordinary 0.45 s animation hold.
- **Keeper/deliveries:** catches vary their reach and crouch by contact height,
  absorb through the elbows/knees and finish at the carrying pose. Removed the
  post-contact hop. Volleys now use a short boot-contact solve and support plant.

Existing uncommitted pass/simulation work was preserved. The added simulation
fields are observations only; this pass does not change decisions, movement or
ball outcomes, and does not require new golden recordings.

Validation: `./run.sh check`, `git diff --check`, and
`./run.sh test --only windup` (55 checks passed, including successive touches,
incoming/outgoing ball observations, non-foot contacts and replay-copy isolation).
Visual acceptance is pending for all five groups.

### 2026-09-05 — shoes stretching during playback

The leg solver multiplied global bases and reused their measured scale on each
frame. Small transform errors accumulated: an isolated repeated-contact test
exceeded 1% local scale drift at frame 1,255. The solver now writes normalized
local rotations with each joint's original scale, preserving model proportions.

Regression: `godot --headless --path . --script
res://tests/test_animation_contacts.gd --log-file /tmp/footman-animation-contacts.log`.
It runs 12,000 frames without a match, including a scaled figure and an ankle
with different scale on each axis. This presentation test stays separate from
the simulation-only test runner. Also checked with `./run.sh check`.

Next session:

1. Watch the first passes in a match, including both feet, repeat touches,
   transitions into/out of passes, and replay stepping. Record specific moments
   in this file or a bookmark.
2. Add preparation before first touches and headers. This requires a reliable
   intended contact/take-off observation before contact; do not infer a touch
   merely from proximity to the ball.
3. Continue the remaining rows in priority order. Paired collision reactions,
   directional falls, keeper dive/hand targets and delivery variants are still
   planned. The new catch pose does not yet solve hands to the ball, and the
   get-up sequence does not yet constrain hands/knees to the turf.
