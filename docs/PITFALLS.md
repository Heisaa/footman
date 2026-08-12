# Things that are easy to get wrong

Each of these was a real bug, and each was invisible from the code alone. Grouped
by the layer it bit.

## Chasing and off-ball movement

- **Chaser ranking must use the ball's predicted path, not its current position.**
  Ranking on the current position makes the passer the nearest body to his own
  pass, so he chases it while the intended receiver holds shape and the ball rolls
  out of play. Pass completion was 30%.

- **The cheap prefilter in front of that ranking has to use the whole path too.**
  Only `CHASE_CANDIDATES` players per team get the real interception model; the
  rest are eliminated by a squared distance, and anyone that eliminates can never
  be chosen however quick he is. Measuring that distance against a single instant —
  where the ball would be in six tenths of a second — is wrong for every ball that
  is caught up with somewhere else, which is most of them. A clearance or a long
  pass is reached at its landing point, twenty or thirty metres away, so the men
  actually in that race were dropped before anybody looked at them. It must also
  count the player's own velocity, or a man already sprinting at the ball is judged
  as though he were standing still. Measured, the slower man was sent 18% of the
  time and arrived 0.71 s late; ranking against the nearest point of the reachable
  forecast halved it.

- **Do not make a change of chase assignment take effect immediately.** It looks
  like an obvious improvement: the newly designated chaser holds his station for up
  to a tenth of a second, so force his target to recompute on the tick he gets the
  job. It measures worse on both counts — the slower man was sent 8% of the time
  with the ordinary stagger and 12% without it, and loose balls were reached more
  slowly. The designation changes about three times a second, and the stagger is
  what stops that becoming two players ping-ponging between chasing and holding. It
  is damping, not lag.

- **A chaser aimed straight at the ball tailgates the man in front of it.** A
  dribbler pushes the ball two to four metres ahead, so the straight line from a
  defender behind him to that ball runs through his body. Soft separation holds the
  defender a body's width off and he settles into the slipstream for the whole
  carry. Measured, he was behind the carrier 87% of the time at 1.1 m, in trails
  averaging 3.3 s and one lasting 15.8 s. The fix is an approach angle, in
  `SimMovement._recovery_point`: the same interception point, stepped sideways by
  enough to run past a body, closing again over the last few metres so the run still
  finishes on the ball.

- **A defender in front of the carrier is a far stronger defensive act than one
  beside him.** `SimContext` rates pressure from an opponent the carrier is facing at
  up to three times one at his back, and the dribble touch shrinks with pressure. A
  first cut of the recovery run aimed at a point *ahead* of the carrier — a blocking
  position — and halved the shots in a match while barely changing the geometry it
  was written for. Going round a man means arriving beside the ball, not standing in
  his path.

- **"Fast enough to arrive" is the wrong rule whenever somebody else wants the ball
  too.** A chaser is paced at the speed that just gets him to the ball, which is
  right for a loose one nobody is contesting and is what keeps a match inside the
  distance a footballer runs. It is wrong for a fifty-fifty: the ball goes to whoever
  is a stride quicker, and two men who each pace themselves to turn up run alongside
  each other at a jog and neither ever wins it. Measured, a chaser running shoulder
  to shoulder with a rival was being asked for 56% of his top speed.
  `SimMovement._contest_pace` is the fix, `_escape_pace` is the same fix for the man
  in possession, and `_carry_pace` is the third. Finding it three times is the sign
  that the rule, not any one case, needed the exception.

- **A press is not a race, and telling them apart is the whole difficulty.** The
  first cut of `_contest_pace` asked only whether an opposing chaser could arrive at
  a similar time. Both sides always designate a chase-primary, so with the ball at a
  carrier's feet the carrier and the man closing him down are exactly that pair,
  every press scored as a dead heat, and both men arrived flat out. Interceptions
  went from 53 to 104 on one seed and 56% of regains were lost again inside two and
  a half seconds. The guard is that the ball has to be genuinely loose — the man who
  last touched it no longer within a dribbler's reach of it.

- **"Clear the static on tick 0" never fired once.** `SimOffBall` keeps every
  player's current offer in static arrays, and cleared them inside `update` when
  `ctx.tick_index == 0`. Tick 0 is the kick-off: the ball is dead, and the
  movement layer that calls `update` only runs while the ball is in play, so the
  line never ran. Every match built after another one in the same process — a
  batch worker, the view's `R`, its rewind, the second pass of `determinism` —
  started with the previous match's runs. Measured, two runs of seed 7 in one
  process were identical to tick 30 and had the ball in opposite halves by tick
  100. The reset belongs in `SimMatch.setup`, where a new match is a fact rather
  than a tick number to be inferred, and `SimMovement.reset` closes the same hole
  in the chase assignment. The general form is in `docs/INVARIANTS.md`.

## The decision layer

- **The softmax temperature has to be relative to the spread of candidate scores.**
  Scores are goal probabilities and often span less than 0.02. Any fixed temperature
  is either indistinguishable from random or from argmax.

- **A heuristic bias must multiply the gain, not the whole score.** Multiplying a
  negative score by a penalty of 0.5 makes the option *better*.

- **Possession has a value of its own** (`SimDecision.POSSESSION_VALUE`). Without it,
  a single-step expected-threat model prefers a fifty-metre punt to a fifteen-metre
  pass, because it only sees where the ball ends up.

- **Clamping a candidate point back inside the pitch hides the fact that it was
  outside it.** Every probe in the decision layer used to pass through
  `clamp_to_pitch` before it was scored, so a touch played *along* the touchline and
  one played *over* it came back with the same expected threat, the same pitch
  control and the same everything else — and then the touch was executed along the
  raw direction and the ball went out. Measured, 19 of the 24 balls that left the
  field in ten minutes were put there by a dribble, 11 of them carried over the goal
  line the carrier was running at. `SimDecision.carry_room` prices the direction by
  the grass it actually has, and drops it when there is not enough for the smallest
  touch.

- **Price every path to the same outcome, or the softmax just moves the problem.**
  The ordinary carry and the knock past a man both put the ball out of play. Pricing
  only the carry made carries out of play fall by a fifth while bursts out of play
  rose by a fifth: the same event, relabelled. Measured across six ten-minute
  matches, because at one match a count of ten swings by half on noise alone and
  every conclusion drawn from it was wrong.

- **Expected goals and expected threat are compared directly** when a player decides
  whether to shoot, so their relative calibration decides whether the team walks it
  in or shoots from the halfway line.

- **Two models of the same event will drift apart unless something makes them
  agree.** `SimDecision.expected_goals` is calibrated against real shot data and says
  so. `SimTouch.shot` decided where the ball actually went, from a base aim error of
  0.28 rad that nothing ever reconciled with it — five times the ground pass's 0.055,
  in a function that also covers a clearance and a diving header, so the least
  accurate act in the engine was the one a footballer practises most.

  An average player eleven metres out struck with a yaw sigma near twenty degrees:
  one standard deviation 4.1 m off centre against a post at 3.66 m, and the 1.6
  elevation weighting put the vertical miss at five metres against a 2.44 m bar.
  Twelve shots from the penalty spot over three seeds produced two on target, against
  a real two-thirds. Nothing in the event log says "that went wide because the aim
  model disagrees with the value model" — it shows up only as summed expected goals
  running at three times the goals scored, which reads like a finishing problem and
  is a units problem. `SHOT_AIM_BASE` is 0.08 now, beside the pass rather than five
  times it.

  The general lesson is the one about pricing every path to the same outcome, pointed
  at a pair of models instead of a pair of actions: if the layer that *values* an act
  and the layer that *performs* it hold separate opinions about how well it will go,
  only one of them is right and neither knows.

- **A defender does not run to the line of a pass, he sticks a leg out.**
  `SimDecision._lane_survival` charged him the full locomotion cost of standing on the
  ball's path, when the first `CONTROL_RANGE` of that gap costs him nothing but his
  reaction. Measured, a quarter of all passes were played with an opponent inside a
  metre and a half of the line, and they completed at about 40%. The engine chose
  them, watched them get cut out, and chose them again.

- **The distance a carrier *looks* and the distance he *knocks it* are two numbers and
  have to stay two numbers.** Sizing the probe off the touch made the whole risk model
  as short-sighted as the touch: `control_at`, `_escape_value`, `_in_play_odds`,
  `xt_at` and the carrier's own `move_target` are all read at `pos + dir * d`, so a
  jogging carrier taking a 1.5 m touch was asking about the grass a metre and a half in
  front of his feet, where there is never a defender and never a touchline. A carry is
  a direction he will still be going in several touches from now, and `carry_room` and
  `close_control` already say how far it can be pursued; that is the horizon. The touch
  is the step along it.

  Related: `_in_play_odds` has to be asked about the carry he *wanted*, not the one the
  touchline has already cut down. Fed the shortened figure it is self-defeating, and
  the protection collapses to the shortening alone.

## The touch and the ball

- **The distance a carry needs is the ball's catch-up distance, not its roll to a
  stop.** Three lengths are easy to confuse. Where the touch puts the ball relative to
  the carrier (`ahead`, one to four metres) is far too short — the ball is struck to sit
  that far in front of a man who keeps running, so in the world frame it travels much
  further. Where it would stop rolling, which is what `_room_ahead` rightly charges the
  *burst*, is far too long, because a carrier catches this one and it never gets to
  stop. The one that matters is the ground it covers until it has slowed to his pace:
  the roll-to-a-stop figure without its `along * along` term. At a sprint that is 15
  metres against 27, and charging an ordinary carry the larger of the two took nearly
  every forward touch in the attacking half off the table and cost half the shots in a
  match.

- **A hard room test is the wrong shape for a line you are running beside.** It is right
  for a line you are running *at*: there is no touch to be played that way and the
  direction should go. It says nothing useful about a winger carrying it up the
  touchline, who has all the grass in the world along his direction and none at all
  beside it. What puts that touch out is the aim error, and the honest answer is that
  his touch up the line is a riskier act than the same touch played infield. So price it
  in `success`, the way `SimTouch.execution_accuracy` prices a pass the player cannot
  hit; the softmax then turns him inside on its own. Shortening the touch instead is
  worse than doing nothing — he stays beside the line longer and takes more touches
  there.

- **The lofted solver's descent test must use a height the ball can reach.** Testing
  against y = 0 never fires, since the ball rests at its own radius, so the solver
  "corrects" every cross into a flat drive.

- **Inverting a roll distance means inverting the square.** `_room_ahead` checked the
  full nine-metre knock against the grass and, when it did not fit, scaled the knock by
  `room / travel`. But travel goes as the square of the launch speed, and the launch
  speed has the carrier's own pace in it, so that ratio does not make the ball fit the
  room. A man at 6 m/s with 20 m of grass was cleared for a 5 m knock, which leaves the
  ball at 9.5 m/s and rolling 28 m: eight metres out of play, from the test whose whole
  job was to stop it. The launch speed that brings the ball to rest on the line is
  `sqrt(2 * decel * room)`, and the knock is what is left of that after his own pace —
  the same arithmetic `carry_room` already does.

- **`TURN_COMMIT` needs its `TURN_PIVOT` guard or the locomotion deadlocks**, and the
  failure is silent rather than loud. A stationary man facing the wrong way may not
  accelerate until he has turned; `vel` is `new_dir * cur_speed`, so a speed of zero
  cannot express a turn; and `facing` is only written when he is moving. He stands there
  for the rest of the match. Measured, mean speed over the whole match fell from 2.4 m/s
  to 0.6 and the touch count fell with it — and every other number in the report still
  looked like a match being played.

- **A correct constraint layered on a broken controller composes badly.** Capping the
  turn rate by the lateral grip it needs is right in itself, and applied to a controller
  that re-accelerated mid-turn it made the swing worse, 4.49 m to 7.90 m. Fix the
  controller first. `docs/STATUS.md`, "The first touch, and the turn", has the full
  account.

## The value field

- **Pitch control has to count everybody who can get there, not the fastest man on each
  side.** Comparing the two best arrival times is a model that cannot see a crowd at
  all: one defender near a point and five defenders near it come back with exactly the
  same number so long as the nearest is the same distance away. That is why the engine
  would play a ball into an area the opposition owned outright.

  `SimValueField._control` weighs everyone by how far behind the earliest arrival they
  are and reads off the share belonging to the team asking. It is a strict
  generalisation — with one man in contention per side the sum collapses to the logistic
  it replaced, to the last decimal — and it is where a long ball into a packed box gets
  priced properly, because a ball hung up for a second and a half puts everyone who can
  reach it on level terms, and what decides it is how many of each side are standing
  there.

## Restarts, shape and the keeper

- **A restart taker has to be placed comfortably inside `CONTROL_RANGE`, not on it.**
  `SimSetPiece.update` will not let him strike a ball he cannot reach, and he was being
  stood at 0.9 m for a free kick and 1.2 m for a goal kick: at the boundary and outside
  it. He arrived at his spot, stopped, and never became ready, so every free kick and
  every goal kick sat there for the full eight-second timeout and was then taken by
  teleporting him onto the ball. Nothing in the event log says so; the `Restarts` block's
  `waited` column is what found it.

- **The shape slides with the ball, and a dead ball is somewhere no shape should slide
  to.** `SimMovement.shape_position` pulled the whole formation 0.36 of the ball's own
  depth, so a goal kick put the back four on the goal line they were defending and
  stretched the side over eighty metres. Restarts pass an override
  (`SimSetPiece.RESTART_SHAPE_DEPTH`) so the kicking side builds its shape around the
  halfway line instead. The keeper is not an outfielder and must not be positioned by
  that function at all — at the opposition's goal kick it had him thirty metres off his
  own line — so he takes `SimKeeper.station` instead.

- **A keeper carrying the ball needs a limit on the destination, not the step.** The
  carry target is recomputed every tick from where he now is, so `pos + forward * 6`
  walks him upfield for as long as he holds it. At the old one-second hold that was three
  metres and invisible; at a realistic hold it put him twenty-eight metres out with the
  ball under his arm.

## Presentation

- **Never set one component of a `Node3D.rotation`.** It is a read-modify-write, and
  Godot returns Euler angles decomposed out of the basis with the pitch folded into ±90°.
  Anything past that reads back as a different triple, so the next component write builds
  a wholly different orientation from it. Arms raised overhead came back as
  `(0.29, π, π)`, and goals were celebrated with the arms hanging down. `_rotate` and
  `_root` in `match_view_3d.gd` write whole vectors.

- **Anything the pose layer measures over time is measured in seconds, never in frames.**
  The view used to quantise to ten frames a second, and two measurements were quietly
  using that quantum as their filter: the turn rate averaged facing over a stepped frame,
  and smoothed by a fixed fraction of it. Play the same code smoothly and both collapse —
  facing is measured over a sixtieth again, which is the noise that made the heads twitch,
  and the smoothing runs six times as fast. Window and time constant are durations now.

- **A pose has to read in the plane the camera watches from.** Play is seen roughly in
  profile, so a celebration spread sideways foreshortens to a stub at the chest. It also
  has to clear the head, which at §9.3's proportions is wider than the arms are long.

## A per-tick probability is a roll until it succeeds

`SimKeeper._try_gather` catches the ball with probability `handled` — about 0.14
for a shot at 25 m/s — and it is asked **every tick the ball is within 1.45 m of
the keeper**. That is not a 14% chance of gathering. A ball crossing a 1.45 m
radius at 25 m/s spends about seven ticks inside it, and `1 - 0.86^7` is about
65%.

The number in the expression is not the number the mechanic produces, and which
one you get depends on the ball's speed and the tick rate rather than on
anything anybody modelled. It is the same shape as the swarm guard and the
challenge commit roll: any per-tick chance applied to a passing object is
governed by the dwell time, and the dwell time is usually an accident.

What made it hard to see is that the *modelled* keeper sits right beside it.
`_shot_response` has a reaction time, a reach envelope that grows with the dive,
an ellipsoid margin and a `save_chance` calibrated against real save
percentages. All of that is careful and most of it is bypassed, because
`_try_gather` runs on the same tick and only needs him to be near the ball —
which he is, by construction, since `_position` stands him on the line between
the ball and his goal.

The tell was in the accounting, not in the code: seed 7 at `--urgency 1`
reported **fifteen of twenty-seven shots ending at the keeper and `saves 0`**.
Zero logged saves in a match the keeper dominated.
