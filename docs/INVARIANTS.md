# The rules, and the traps behind them

What you have to know before changing `sim/`. The rules first; then the bugs that
were invisible from the code, grouped by the layer they bit. Each of those was
real, and the general form is the part worth keeping.

## The rules

**The simulation never touches the engine.** No nodes, no physics server, no
`_process`, no frame delta, no `Time`, no input. The headless entry point is the
enforcement mechanism, not just a tool: if it stops working, the separation has
been violated.

**All randomness comes from `ctx.rng`.** `SimRng`'s methods are `unit_float`,
`range_float`, `range_int`, `gauss` and `gauss_clamped` — deliberately not
`randf`/`randfn`/`randi_range`, which exist in `@GlobalScope`, so an unqualified
call resolves to Godot's global generator instead. That cost real time to find:
matches reproducible in every respect except the gaussian draws. Do not rename
them back.

**One forecast and one value field per tick, shared.** `ctx.trajectory_now()`
computes the ball's future at most once per tick, however many agents ask. No
agent may run its own.

**Tactics are priors on the decision function, never behaviour switches**
(`PLAN.md` §5.1). Every concept in `SimTactics` resolves to a modifier on a value
the decision or movement layer was going to use anyway. Redesign any tactical
feature that cannot be expressed that way. Named patterns follow the same rule —
a trigger plus a nudge — and what makes them worth having is that they are named,
visible and counted. A pattern that fires and never resolves teaches the player
nothing, and is a bug.

**Simulation state kept in a static is reset from `SimMatch.setup`.** Most of a
match lives on the context and dies with it; `SimOffBall`'s intents and
`SimMovement`'s chase assignment are arrays outside it, and a static outlives the
match that filled it. Reset where a new match is a *fact*, never on
`ctx.tick_index == 0` from inside the layer — a layer that only runs in play
never sees tick 0. Determinism is what this protects.

**The anti-swarm guard lives in `SimMovement._assign_chasers`** and nowhere else.
Only an explicitly chosen handful of players per team may move toward the ball.
`TestMatch._whole_match_invariants` measures it.

**The shape reads `ctx.shape_ball` and `ctx.shape_phase`, never the live ball or
the possession flag.** Both are damped, both are advanced once a tick by
`SimContext.advance_shape` before anything reads a station, and between them they
are what stops the formation moving faster than the men in it. Stations slide with
the ball, so whatever the shape reads sets how fast every station in the side
moves — and a shape that moves faster than a footballer cannot be occupied by
one. It was the live ball, and the whole side sat a permanent eight to nine
metres behind its own points, all lagging the same way, which is what the clump
around the ball actually was. Chasing, pressing, marking and every decision keep
reading the real ball: those are about this pass. Only the shape is about the
phase of play. `advance_shape` is never strided — it is an integration, and a
coarse tier stepping it four times as far would build a different shape rather
than a cheaper one.

`shape_phase` is the same rule for the *other* input the shape has. The formation
has an attacking form and a defending one, and four things cross-fade between
them — `ball_pull_shift`'s midfield hold, `_build_up_width`, `lateral_pull` and
the phase shift — worth about fifteen metres of station between them. Switched on
`possession_team == p.team`, all fifteen arrived in one tick at every change of
hands. **A boolean in a positioning rule is a station that teleports**, and the
answer is to compute both forms and lerp, never to branch.

**Any positioning rule is answerable for how fast the point it names moves.**
The general form, and the one that keeps being missed: a target that moves at
7 m/s has no occupant at any pace, so the gap to it measures the target and not
the man. `diagnose`'s `Holding the shape` prints that speed per errand, and the
first cut of a positioning fix should be read there before its distance is.

Four shapes it has taken, all found by that column or the `over 8 m/s` one beside
it — **and read that one for anything that happens at a moment.** A station that
teleports fifteen metres once a turnover and stands still the rest of the time
reads as a gentle drift in the mean; the share of samples where it outran a
sprinter is what sees it, and it halved when the phase was eased.
- **A point defined relative to the ball moves at the speed of the ball.**
  `_support_adjust` returned a 12 m ring round it, so four or five men at a time
  were sent to a circle travelling at 15 m/s. Return a bounded *step* toward such
  a point, never the point.
- **A sign recomputed every tick flips.** `_support_press_point` chose its side of
  the ball from `signf(...)` on the presser's own position, and a man near the
  line through the ball crossed ten metres and came back. Latch a discrete choice
  for the length of the act.
- **A boolean is a teleport**, above: `shape_phase`.
- **Rules compose, so the base one is worth fixing first.** `drift` and `ascent`
  are computed on top of the support-adjusted shape and inherited the whole of
  its motion; fixing support brought all three under control and neither of the
  other two needed touching.

**Tune late** (`PLAN.md` §11.1.1). Until the decision and tactics layers stop
changing shape, a fitted coefficient is one that will need fitting again.

**The reduced-fidelity tier strides decisions, never physics.** Off-ball targets,
chase assignment, perception refresh, the value-field ascent and the pressure map
scale by `SimMatchConfig.decision_stride()`. Ball integration, locomotion,
separation and contact never do — they are where the behaviour a coarse run is
checking actually lives. At full fidelity the stride is 1, so every one of those
is a no-op and the goldens are unchanged.

**After adding a script with a new `class_name`, run `./run.sh import` once**, or
the class will not resolve.

### The compressed clock

**The match clock is compressed, and almost nothing may know.** `--clock-rate R`
runs the match clock R times faster than the simulation, so ninety minutes plays
out in `90/R` with the scoreboard still reading 0-90. Read in one place,
`SimMatch._advance_clock`. **It is not a speed multiplier** — players run at the
same metres per second and the tick is still a sixtieth. A compressed match is a
*shorter* match wearing a ninety-minute clock, and holds proportionally fewer
events. Everything defaults to `clock_rate` 10, so the instruments measure the
match the player gets.

Four things scale with it and nothing else may: **fatigue**, because "nothing
left after eighty minutes" is a fact about a match rather than a body; the
**deliberate part of a restart**, because dead time is priced in real seconds;
the **repositioning pace** at a restart, which pays for the shorter window; and
**the scoring fit**. Acceleration, turn rate, ball drag and the tick must never
know.

**The scoring fit is deliberately one object.** `SimMatchConfig.urgency` is a
single scalar, 0 at real time and 1 at 30x, and exactly six constants read it:
`SHOT_APPETITE_URGENT`, `SHOT_APPETITE_KNEE`, `SHOT_SIGMA_URGENT`,
`KEEPER_SAVE_URGENT`, `KEEPER_REACH_URGENT`, `SimDecision.TERRITORY_URGENT`. A
seventh goes in that list and in `SimMatchConfig`'s own block, never beside the
mechanic it scales.

**And an appetite paid flat decides where a side shoots from, not how often.**
`SHOT_APPETITE_URGENT`'s own note records forty matches in which moving it from
1 to 8 changed shots per team by 2.29 to 2.40 — nothing. What it did move was the
point at which shooting beats everything else, and it moved it furthest out
exactly where the shot is worst: a **three per cent** chance from twenty-seven
metres scored 0.137 against the best carry's 0.091 and took 98% of the softmax.
`SHOT_APPETITE_KNEE` pays it on the chance rather than on the attempt. It has to
ramp *steeply*, because the shot he could take now and the shot he is carrying
toward both ask the same function — a gentle ramp lifts them together and decides
nothing. **Every
one must be a no-op at `clock_rate` 1**, and `test_clock` guards it: that
property is what keeps `--clock-rate 1` meaning the patient engine. The check
after changing one is `./run.sh diagnose --seed 7 --minutes 10 --clock-rate 1`,
which must return what it returned before. `--urgency U` forces the fit on at any
clock rate for measurement; nothing in `sim/` may read it but `urgency()`.

**Match length is meant to become a player-facing setting**, with goals per match
roughly steady whichever length is chosen. A match holds `5400 / clock_rate`
seconds of football, so holding goals steady needs goals per second to scale
linearly with `clock_rate`. Only fatigue does today, and it is the model to copy:
drain scaled by `clock_rate` over a match `1 / clock_rate` as long cancels
exactly. That constrains *where* scoring knobs live — one scalar derived from
`clock_rate`, reachable from one place. Fitting it is a tuning-freeze job.

## Chasing and off-ball movement

- **Rank chasers on the ball's predicted path, not its current position.** Rank
  on the current position and the passer is the nearest body to his own pass, so
  he chases it while the receiver holds shape. Pass completion was 30%.

- **The cheap prefilter in front of that ranking has to use the whole path too**,
  and count the player's own velocity. Anyone it eliminates can never be chosen,
  however quick; measuring against a single instant drops the men actually in the
  race for a long ball reached thirty metres away.

- **Do not make a change of chase assignment take effect immediately.** The
  designation changes about three times a second, and the ordinary stagger is
  what stops that becoming two players ping-ponging. It is damping, not lag —
  removing it measured worse on both counts.

- **A chaser aimed straight at the ball tailgates the man in front of it.** The
  carrier pushes the ball two to four metres ahead, so the line from a defender
  behind runs through his body and he settles into the slipstream for the whole
  carry. `SimMovement._recovery_point` steps the run sideways and closes again
  over the last few metres.

- **A defender in front of the carrier is a far stronger act than one beside
  him** — pressure from a man he is facing is rated up to three times one at his
  back. A first cut of the recovery run aimed *ahead* of the carrier halved the
  shots in a match. Going round a man means arriving beside the ball.

- **A pace rule that reads its own output has to be latched.** `_contest_pace`
  sets the chaser's speed cap off the margin between his intercept and his
  rival's — and the intercept is a race with a decelerating ball, so it is very
  sensitive to the speed this rule just set. Recomputed clean every refresh the
  loop closes: the taper eases him off, easing off lengthens his intercept, the
  margin moves, the pace comes back. Measured on `race`, both men's cap went
  8.0, 5.0, 8.0, 6.0, 8.0 over two seconds of a sprint they were four metres
  down on, and the race was decided by whose brakes landed worst. The entry
  window and the release window must differ — enter on the dead heat, release
  only when the race is decided — which is the same medicine as `_press_side`.

- **"Fast enough to arrive" is the wrong rule when somebody else wants the ball
  too.** Right for a loose ball nobody contests, wrong for a fifty-fifty: two men
  who each pace themselves to turn up jog alongside each other and neither wins
  it. `_contest_pace`, `_escape_pace` and `_carry_pace` are the same fix three
  times, which is the sign that the rule needed the exception.

- **A press is not a race, and telling them apart is the whole difficulty.**
  Both sides always designate a chase-primary, so a carrier and the man closing
  him are that pair by construction and every press scored as a dead heat. The
  guard is that the ball must be genuinely loose — the man who last touched it no
  longer within a dribbler's reach.

## The decision layer

- **Softmax temperature has to be relative to the spread of candidate scores.**
  Scores are goal probabilities and often span less than 0.02, so any fixed
  temperature is either random or argmax.

- **A damp and a bias on opposite sides of one product cannot be tuned against
  each other.** The orientation beat multiplied a strike's `success` by 0.5 and
  the compressed clock's `shot_appetite` multiplied its bias by 5.7, so the beat
  could never win the pick however it was priced — measured, a man handed the
  ball at the top of the box shot at 0.01 s in every trial with the damp fully
  applied. When one of the two is a fixed object (the scoring fit is), the other
  has to become a gate. `SET_STRIKE_FLOOR`.

- **A heuristic bias multiplies the gain, not the whole score.** Multiplying a
  negative score by a penalty of 0.5 makes the option *better*.

- **Possession has a value of its own** (`POSSESSION_VALUE`). Without it a
  single-step expected-threat model prefers a fifty-metre punt to a fifteen-metre
  pass, because it only sees where the ball ends up.

- **Clamping a candidate point back inside the pitch hides that it was outside
  it.** A touch played *along* the touchline and one played *over* it came back
  with identical scores, and then the touch was executed along the raw direction.
  `carry_room` prices the direction by the grass it actually has.

- **Price every path to the same outcome, or the softmax just moves the
  problem.** Pricing the carry out of play but not the knock past a man relabelled
  the event and moved nothing.

- **The contact rule and the lane model read the same body.** `SimDuel.REACH_ARC`
  and `_ready_for` decide who can play an arriving ball; `SimDecision._cut_chance`
  and `_facing_cost` price the same arc and the same reaction. A charge added to
  one without the other is the drift below, and it was measured the day the
  facing charge went in alone: 0.44 said against 82% cut out.

- **The bent lane is the chord plus an offset, and nothing tighter.**
  `_cut_chance` and `_near_segment` price a curled ball by shifting the path
  `4*bow*u*(1-u)` sideways at each defender's station; the station and the local
  direction stay the chord's, a few degrees off on a real bend. The metres of
  offset are what move a leg in or out of reach and those are real; anything
  that needs the exact station or heading re-derives it rather than trusting
  this.

- **Two models of the same event drift apart unless something makes them agree.**
  `expected_goals` is calibrated against real shots; `SimTouch.shot` decided where
  the ball went from an aim error nothing reconciled with it — five times the
  ground pass's, so the least accurate act in the engine was the one a footballer
  practises most. It showed up only as summed expected goals at three times the
  goals scored, which reads like finishing and is units.

- **A man who reaches the point before the ball is a man standing there, not a
  man in a race.** The ball into space floors every arrival at the ball's — right
  for a through ball, where the race is decided as it lands — and that levelled a
  full-back seven metres from the touchline, marker seven metres off, with any
  defender who could reach the spot by the time the ball did: `space` 0.46 for a
  ball football completes nine times in ten. `there_first` in `_add_passes` hands
  that ball to the aimed model, where the defender pays `AIMED_STEP_IN`. The bench
  saw it first and nobody read it: `./run.sh control` row C had a sprinting
  receiver at 0.39 while 90% arrived.

- **A defender does not run to the line of a pass, he sticks a leg out.**
  Charging him the full locomotion cost of standing in the lane, when the first
  `CONTROL_RANGE` costs him nothing but his reaction, had a quarter of all passes
  played within a metre and a half of an opponent, completing at about 40%.

- **A gap is not a distance over the grass, and a gate written in one frame
  cannot test the other.** The knock past a man was gated at five metres of
  *gap*, which at 5 m/s is a twenty-one metre ball arriving four seconds later —
  so the engine's only take-on was a hoof into the corner wearing a take-on's
  name, and honest pricing gave it `succ 0.00`. Everything a knock has to clear
  — a defender, a touchline, a goalkeeper — is a distance over the grass, so the
  test belongs there: `carry_push_for` is the conversion and `BURST_CLEAR` is
  the test.

- **Price the man an act is *about* once.** The knock past a defender charged
  him in `_escape_value` as the race and again in `_lane_survival` as a leg in
  the lane. `control_at_time` had always taken him as its `ignore_id`; the third
  term missed the convention, and the double charge was `succ` 0.02 where one
  charge is 0.44. When a candidate names an opponent, check every term that
  walks the opponents.

- **The distance the ball runs before he plays it again is a third number, and
  it is not `carry_travel`.** That one answers "where would it be if he never
  touched it again", which is the *burst's* question -- not re-touching is what
  makes a burst a burst. Every other carry is re-taken as soon as the cooldown
  lapses and the ball is inside `CONTROL_RANGE`. Run against each other for the
  first time: `carry_travel` claims 11 m for a 1.08 m touch at a sprint, and
  `diagnose`'s own count of the ball at consecutive dribble touches in the same
  match says **0.55 m**. `touch_travel` is the honest one; `_in_play_odds` and
  the probe horizon were both charging the long journey.

- **A touch size is a gap and a horizon is a distance over the grass**, and
  `_add_dribbles` had one expression standing for both. It only survived because
  the term that dominated it was the overstated `carry_travel`; corrected, the
  forward probe collapsed to two metres in front of the carrier's own feet.
  `CARRY_HORIZON_SECONDS` is the horizon, in his own running.

- **Risk belongs to the touch and reward belongs to the direction.** Reading
  both at the horizon meant asking `control_at_time` who owns grass six metres
  nearer the keeper than the ball was going: at twenty-two metres from goal with
  nobody within twenty metres, a forward carry came back at `success` 0.07 beside
  its own gain of 0.517. Score `success`, `escape` and the lane at the ball's
  landing; score `gain` and `loss` at the horizon.

- **The distance a carrier *looks* and the distance he *knocks it* are two
  numbers.** Sizing the probe off the touch makes the risk model as short-sighted
  as the touch: a jogging carrier asks about the grass 1.5 m ahead, where there is
  never a defender and never a touchline. `carry_room` and `close_control` say how
  far a direction can be pursued; that is the horizon, and the touch is a step
  along it. Related: ask `_in_play_odds` about the carry he *wanted*, not the one
  the touchline already cut down, or the protection collapses to the shortening.

## The touch and the ball

- **The distance a carry needs is the ball's catch-up distance, not its roll to a
  stop.** Three lengths are easy to confuse: where the touch puts the ball
  relative to the carrier (far too short), where it would stop rolling (far too
  long — he catches this one), and the ground it covers until it has slowed to his
  pace, which is the one that matters. At a sprint that is 15 m against 27, and
  charging the larger took nearly every forward touch in the attacking half off
  the table.

- **The room a carry has ends at the goalkeeper, not at the paint.** `run_room`
  measures to the line, and on a run at goal the line is the wrong end of it: a
  ball knocked that way comes to rest in his hands twenty metres early. Measured,
  that was `1v1-clear` played as a single 6.4 m knock from thirty metres out —
  the ball ran 24 m untouched, the keeper collected it, and it was the carrier's
  only touch of the situation. `SimDecision.keeper_room` is the race for the
  ball's resting place, and it is confined to the area his hands work in: outside
  the box a ball at rest is nobody's in particular, and a rule that forgot to say
  so would ban the forward carry.

- **A ball in a goalkeeper's hands is not a loose ball, and only one place could
  say so.** `SimDuel.resolve_contacts` skips keepers as contenders and then
  contested the ball at his chest like any other, so the striker he had just
  taken it from stood over it and took it back. The general form: skipping the
  *player* is not the same as skipping the *ball he has*.

- **A carry's ball is not struck from rest, and two things followed from
  pretending it was.** `SimTouch.dribble` sized the strike to open a *further*
  `ahead` on top of wherever the ball already lay — and a carrier's ball is never
  at his feet, it is most of a metre in front, because that is where his last
  touch put it. And `_perturb` scaled the *whole* velocity, which for a carry is
  mostly the momentum the ball already shares with a running man. At 8.8 m/s the
  gap he wants is worth **0.93 m/s** of relative speed and a twenty per cent
  mis-hit on the total is **1.95** — the error was twice the intent, so the size
  of a carry was decided by the draw. Measured, the longest a ball ran between
  two touches of one carry was **16.8 m**; fixed, 4.3. `dribble_opening` is the
  first, and striking `along + delta * weight` is the second. Elsewhere
  `_perturb` is right: a pass, a shot and a clearance really are struck from
  nothing.

- **A settling touch is a check, and a sprinting man cannot make one.**
  `SimTouch.settle` leaves the ball about a metre away *measured against the
  grass*, with none of his pace on it — and he keeps all of his. Nothing priced
  the overrun: the hold read `success` 0.90 for a man doing nine metres a second,
  and measured he settled it at 9.1 m/s, the ball left his foot at 3.0, and it
  was 1.3 m *behind* him a quarter of a second later. The distance he needs to
  pull up in is his own, `v² / 2a`; when that is longer than where the ball comes
  to rest he runs past it. An *arriving* ball is exempt — that is
  `SimTouch.first_touch`, a cushion that leaves pace on the ball.

- **The goalkeeper coming out is not a body in your lane.** `_carry_pace` counts
  opponents in the carrier's lane and withdraws his pace floor as they fill it,
  which is right for a defender and exactly backwards for a keeper: measured, a
  striker through on goal was capped at 8.05 and walked down to **5.06** as the
  keeper advanced, decelerating while the ball ran on at 6.3 — so the gap grew
  and the keeper collected it. `_contest_pace` cannot cover this either; it is
  guarded to a ball nobody has, and this one is still his.

- **A race solved in closed form cannot see the other man's velocity.**
  `keeper_room`'s arithmetic assumed a keeper starting from rest, so a knock it
  said was won by three metres was collected by an onrushing one. Solve it by
  bisection against `SimValueField.time_to_arrive`, which is the function every
  other race in the engine is settled by.

- **A hard room test is the wrong shape for a line you are running beside.** It
  is right for one you run *at*. A winger up the touchline has all the grass in
  the world along his direction and none beside it, and what puts that touch out
  is the aim error — so price it in `success` and the softmax turns him infield on
  its own. Shortening the touch instead is worse than nothing: he stays beside the
  line longer.

- **A fallback act carries the whole weight of the branch that has no other
  answer.** `SimAerial.play` offered three headers and used the defender's one --
  `head_clear`, aimed at the far goal and wide -- for every man who found no
  teammate to head it to. Measured, that was `aerial`: 25 duels won, 25 headers,
  **25 losses**, every one of them a clearance played by a striker in the
  opposition half. Read what the last `return` in a decision does before reading
  what the branches above it are worth.

- **The lofted solver's descent test must use a height the ball can reach.**
  Testing against y = 0 never fires, so the solver "corrects" every cross into a
  flat drive.

- **A solver that takes spin has to correct sideways as well as along the line.**
  `solve_lofted` iterated on how far the ball got and how long it took, both
  measured along the straight line to the target, and a curled ball's whole point
  is that it does not travel down that line. So every bend the game put on a ball
  was a bend *away* from where it was aimed: measured, 1.5 m off at the engine's
  old cross curl and six metres off at a footballer's. The fix is a yaw on the
  launch, iterated like the other two -- in both solvers. `solve_direct` had the
  same hole; it was closed before the bent shot went in, which is the day it
  would have bitten.

- **A closed form of the ball is a model of a strike the touch may not make.**
  The ground pass was priced off a slide-then-roll formula for a spinless flat
  ball, and the touch strikes a backspun roller or a skimming drive. Measured
  2026-09-01, the priced journey was 5-17% long over 15-40 m and 8-11% short
  on a slow roller, and `_pass_success` prices every interception off it.
  `SimBallistics` now reads the four ground predictors off a table of the
  engine's own strike, integrated once per surface; change `drive_loft`,
  `drive_backspin` or the integrator and the table follows. Add a predictor of
  the ball by integrating the ball, or by proving in a test that the closed
  form matches it -- `test_ball` does both.

- **Inverting a roll distance means inverting the square.** Travel goes as the
  square of launch speed, so scaling a knock by `room / travel` does not make the
  ball fit the room — it cleared a 5 m knock that left the ball rolling 28 m. The
  launch speed that stops the ball on the line is `sqrt(2 * decel * room)`.

- **A recovery that zeroes a man's velocity is a different act from the one it is
  named for.** Losing a duel set `recovery_ticks`, and that branch braked at
  *twice* his maximum deceleration with no steering — a carrier at 3.0 m/s went to
  **0.0 in three tenths of a second**, and with `SimDuel`'s 0.55–1.1 s touch
  lockout on top he could not play the ball he still owned while it rolled two
  metres off him. That is the "ball runs away from the player" the owner watched,
  and it fires on every lost duel in the match, not just in a one-on-one.
  Off balance is not stopped: `SimPlayer.RECOVERY_BRAKE`.

- **`TURN_COMMIT` needs its `TURN_PIVOT` guard or locomotion deadlocks**, and
  silently. A stationary man facing the wrong way may not accelerate until he has
  turned; `vel` is `new_dir * cur_speed`, so a speed of zero cannot express a
  turn, and `facing` is only written while moving. Mean speed fell from 2.4 m/s to
  0.6 and every other number still looked like a match.

- **A correct constraint layered on a broken controller composes badly.** Capping
  turn rate by lateral grip is right in itself and made the swing worse on a
  controller that re-accelerated mid-turn. Fix the controller first.

## The value field

- **Pitch control has to count everybody who can get there, not the fastest man
  on each side.** Comparing the two best arrival times cannot see a crowd at all:
  one defender near a point and five come back identical. `SimValueField._control`
  weighs everyone by how far behind the earliest arrival they are — a strict
  generalisation, collapsing to the old logistic with one man per side — and it is
  where a long ball into a packed box gets priced properly.

## Restarts, shape and the keeper

- **A restart taker has to be placed comfortably inside `CONTROL_RANGE`, not on
  it.** Stood at the boundary he arrives, stops, and never becomes ready, so every
  free kick sat for the full eight-second timeout and was then taken by
  teleporting him onto the ball.

- **The shape slides with the ball, and a dead ball is somewhere no shape should
  slide to.** A goal kick put the back four on the goal line they were defending.
  Restarts pass `SimSetPiece.RESTART_SHAPE_DEPTH`, and the keeper is not an
  outfielder — he takes `SimKeeper.station` instead.

- **A keeper carrying the ball needs a limit on the destination, not the step.**
  The target is recomputed every tick from where he now is, so `pos + forward * 6`
  walks him upfield for as long as he holds it.

## Presentation

- **Never set one component of a `Node3D.rotation`.** It is a read-modify-write,
  and Godot decomposes Euler angles with the pitch folded into ±90°, so the next
  component write builds a wholly different orientation. Arms raised overhead came
  back as `(0.29, π, π)` and goals were celebrated with the arms hanging down.
  Write whole vectors.

- **Anything the pose layer measures over time is measured in seconds, never in
  frames.** Two measurements were quietly using the old ten-frame quantum as their
  filter, and both collapse when the same code plays smoothly.

- **A pose has to read in the plane the camera watches from.** Play is seen
  roughly in profile, so a celebration spread sideways foreshortens to a stub, and
  it has to clear a head wider than the arms are long.

## Four traps that are the same shape

**A per-tick probability is a roll until it succeeds.** `SimKeeper._try_gather`
catches with probability `handled` — about 0.14 for a shot at 25 m/s — asked
*every tick the ball is within 1.45 m*. A ball crossing that radius spends about
seven ticks inside it, and `1 - 0.86^7` is 65%. The number in the expression is
not the number the mechanic produces; the dwell time decides, and the dwell time
is usually an accident. The same shape as the swarm guard and the challenge commit
roll. What made it hard to see is that the carefully modelled keeper sits right
beside it and is bypassed.

**A factor with no spread is a constant, whatever it is named.**
`_pass_success` charged a 14% discount for the receiver's first touch. It reads
like a probability — attribute-driven, varies by receiver, real football meaning —
and it could not decide a single ball, because a pass here completes when a
teammate *reaches* it. Neither the mean nor the calibration can see this. What
sees it is each factor's mean on the balls that arrived beside its mean on the
ones that did not: `control` read 0.86 against 0.85, `in time` 0.96 against 0.99.
**A term is a model only if the balls it liked did better.** If it did not
separate them, its value is a coefficient.

**A model of the engine is not checked by anything the engine prints.**
`SimTouch.execution_accuracy` is the decision layer's estimate of `SimTouch`'s own
strike, and they had drifted apart three ways at once: different base sigma,
different weight sigma, and a linear weight-to-range map where range goes as the
square. The engine believed it could drop a thirty-metre ball inside seven metres
84% of the time; it does it 33%. Nothing a match prints could have found it — a
diagnose measures what the ball did, a calibration measures a model against an
outcome, and neither measures a model against *the thing it is a model of*. What
finds it is a bench that runs both: `./run.sh strike`. **The general form: any
function whose name is a claim about another function is unchecked until something
runs both.** Look for the pattern in the name.

**And when the bench exists, believe it over the derivation.** A closed form that
reproduced the measured total at two of three distances was still wrong: cutting
the elevation error to a third moved the real ball by 7% where the formula said
60%. A sum that matches is not a split that matches.
