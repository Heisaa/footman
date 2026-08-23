# The football: what exists, what is missing, what is next

Every behaviour a viewer can see, whether the engine has it, and — for the ones
it does not — the proposal, its location and where it sits in the order.

Read it before watching a match, so an absence can be recognised as an absence: a
cross nobody attacks is not a bug in crossing, it is a missing run.

**built** — the engine does it. **partial** — some of it, with the rest named in
the row. **absent** — a footballer does it and this engine does not. **Checked
against the working tree, not against the last commit** — 2026-08-15 found 10 and
23 listed as open proposals and already built in uncommitted code, and an order
written off that had two of its first three items done. When one is built, move the row; the account of what it cost is
the commit that built it.

**The attacking rows are the current pass** (`PLAN.md` §11.4). The defending rows
and the keeper's saves are the next one, held on purpose — a defending row marked
*absent* is scheduled, not overlooked.

## With the ball at his feet

| Behaviour | | Where |
|---|---|---|
| Pass to feet | built | `SimDecision._add_passes` |
| Through ball in behind | built | `_add_passes` |
| Shot, with a chosen placement | built | `_add_shot`, `_pick_shot_aim` |
| Clearance | built | `_add_clear` |
| Carry, eight probed directions | built — and the room it has ends at the goalkeeper, not at the paint | `_add_dribbles`, `keeper_room` |
| Knock past a man, and race him | built — same room, except when going round the keeper *is* the act | `_add_dribbles`, the burst |
| Hold — the settling touch | built | `_add_hold`, `_play_hold` |
| The dwell — a free man keeps it a beat, takes another look, then plays | built | `SimDecision.scan_gain` |
| Orient before the act — a beat between coming by the ball and striking it | built — a price either side of a gate, because the price alone loses to the shot appetite | `SimDecision.readiness`, `_apply_set_damp`, `SET_STRIKE_FLOOR` |
| First touch, and the turn | built | `SimTouch.first_touch` |
| Receive on the half-turn — hips opened while the ball travels | built | `SimMovement._orient_receiver` |
| The layoff — first-time ball back to the man facing play | built | `SimTouch.redirect_share` |
| A setting touch out of the feet before the long ball or the shot | built | `SimDecision._add_set_touch` |
| Body facing priced into the strike, and the turn before you can hit it | built | `SimTouch.facing_penalty` for the aim, `strike_scale` for the range |
| A stronger foot, and a ball shown onto the weaker one | built — the other axis of the same body model, charged through the same two functions | `SimTouch.foot_cost`, `foot_choice` |
| Bend on a struck ball, the way the foot that struck it sends it | built — the shot, the cross and the lofted ball; the driven pass is still zero-mean and says why | `SimTouch.curl_for` |
| Shielding the ball | built | `_play_hold` sets it, `SimDuel` weighs it |
| Backheel, dummy, first-time pass | built | `SimTouch.FIRST_TIME_EASY`, `_add_dummy` |
| Chip the keeper, round him, square it across the face | built | `_add_chip`, `_round_the_keeper`, `SQUARE_CONVERT` |
| Firm pass driven low, not rolled | built — offered beside the roller, with the lane it buys back and the first touch it costs | `SimDecision.DRIVEN_LANE`, `SimBallistics.ground_launch` |
| Lofted pass, cross | built — aimed where he is going, and landed short so the hops carry the rest | `_add_passes`, `SimTouch.LOFT_RUNON_SHARE` |
| Give-and-go, and the executed one-two | built — a named pattern, so the passer is committed to the run and the return ball is lifted to him | `SimPatterns._try_one_two` |
| Beating a man | partial — the knock, and the cut that wrong-foots a committed challenger; no feint at a standstill | `_try_beat` |
| Drawing a foul | built — the duel fouls the skilful or shielding carrier more, and a composed one invites the contact inside shooting range | `SimDuel.INVITE_CONTACT` |
| Time on the ball — two to three seconds before it is played | partial — about one, and four times football's touch rate with it (**28**) | `SimDecision`, `SimTouch` |

## Without it, attacking

| Behaviour | | Where |
|---|---|---|
| Come and meet it, move into space, run in behind | built | `SimOffBall` SHOW / SPACE / BEHIND |
| Check away and come back | built | `SimOffBall._commit` |
| Drop into the pocket between the lines | built | `_pocket_point` |
| Decoy run — going where the ball will not | built | `_decoy_point` |
| Anticipate the second ball | built | `_second_ball_point` |
| Stay onside | built | `SimReferee.believed_offside_line` |
| Hold shape, slide with play | built | `SimMovement.shape_position` |
| Split the back line to build out | built | `SimMovement._build_up_width` |
| Overlap, underlap, third man, switch of play | built | `SimPatterns` |
| A plan's named patterns actually firing | built — `RUN_IN_BEHIND` was installed in `high_press_direct` with no trigger and could never fire; it now does, at 13-17% | `SimPatterns._try_run_in_behind` |
| A pattern's runner being aimed at | built — `destination_for` did not read `movement_override`, so a man a pattern had sent was passed to by dead reckoning | `SimOffBall.destination_for` |
| Break on the counter | built | `SimDecision.break_on` prices the ball, `SimOffBall` sends the runners |
| Attack a cross — near post, far post, the pull-back | built — the three posts are authored in `_box_point` and `_add_crosses`, and the pull-back is its own act along the floor | `SimDecision._add_pullback` |
| Arrive as the ball does, easing the last metres | partial — box runners and runs in behind do; shows and drifts stop on their spot | `SimOffBall.point_for` |
| Link the defence to the strikers, holding height and width | partial — shape slides with play; there are no authored link players, and the middle third holds 78% of touches (**30**) | `SimMovement.shape_position` |
| Be served when the run is made | partial — a `box` run is made 26 times a match and receives the ball 0% of the time (**33**) | `SimOffBall`, `SimDecision._add_passes` |

## Defending

| Behaviour | | Where |
|---|---|---|
| Who leaves shape for the ball, and how many | built | `SimMovement._assign_chasers` |
| Press harder or sit deeper, from the plan | built | `SimTactics` |
| Mark a man | built | `SimPlayer.marking_target` |
| Recovery run | built | `SimMovement` |
| Intercept, tackle, poke it away | built | `SimDuel`, `SimTouch.poke` |
| Hold a defensive line, with offside off it | built | `SimReferee.offside_line` |
| Clear under pressure | built | `_add_clear` |
| Block a shot | partial — a defender in the path can take it; nobody throws himself in the way (**5**) | |
| Cover a beaten teammate | partial — he is penalised in the chase ranking; nobody covers the space he lost | |
| Jockey, delay, show him wide | absent — he either goes for it or holds station | |
| Escort a dying ball over the line | absent — shielding's cheapest special case | |
| Spring an offside trap | absent — the line exists; stepping up as an act does not | |
| The deliberate foul | absent | |
| Defend the penalty area | absent — the largest single hole an eye will find (**5**) | |

## In the air

Three heights are what the layer is. Below `SimConsts.FOOT_REACH_HEIGHT` the
ordinary decision has it; above `SimAerial.HEADER_FROM` — his shoulders — it is a
header; between them he has a chest, which is the commonest thing anybody does
with a ball in the air. The fourth act is not touching it at all.

| Behaviour | | Where |
|---|---|---|
| Height decides who can play the ball | built | `SimTouch.playable_height` |
| Head it — clear, shoot, flick on, nod it down for yourself | built — four acts, and the fourth was the fallback the module did not have | `SimAerial.play`, `_head_down` |
| Take it down on the chest | built | `SimTouch.chest` |
| Let a dropping ball come to you | built | `SimAerial.lets_it_drop` |
| Jump for it, contest it in the air | built | `SimDuel`, weighted by `SimAerial.duel_skill` |
| Win a knock-down, attack a corner | partial — the knock-down exists; a corner is whatever the box happens to do (**29**), and corners run at 0.02 per team a match against a target of 3-8 (**5**) | |
| Volley it, on purpose | built — sigma up on the elevation axis, pace up off the boot, both scaled by height and `technique` | `SimTouch.VOLLEY_FULL` |
| Head it at goal | partial — the act exists; 22 headers in a match produced none at goal (**29**) | `SimAerial.play` |

## The goalkeeper

| Behaviour | | Where |
|---|---|---|
| Shot stopping, from reach and reaction | built | `SimKeeper` |
| Shooting while running flat out, and on empty legs | built — the two things `expected_goals` could not see, and they cost 1.58 goals a match | `SimDecision.SHOT_AT_PACE` |
| Dive, parry or catch | built | `SimKeeper` |
| Starting position, sweeping behind the line | built | `SimKeeper` |
| Come out and smother | built | `SimKeeper` |
| Distribution, short or long | built — and the ball is his while he holds it: nobody else is a contender for it | `decide_with_ball`, `ball_in_hands` |
| Claim a cross, command the area | built | `_claim_target`, `_try_gather` |
| Where a parry goes | partial — the rebound is a loose ball nobody aims (**3**) | |
| The one-on-one | partial — priced into `expected_goals`, so the engine's answer is not to shoot | |
| Narrow the angle | absent (**5**) | |

## Set pieces, and the laws

| Behaviour | | Where |
|---|---|---|
| Kick-off, throw-in, goal kick, corner, free kick, penalty | built | `SimSetPiece` |
| Offside, given at the moment of the pass | built | `SimReferee` |
| Fouls and cards, and a red that removes a man | built | `SimReferee` |
| Added time from stoppages | built | `SimReferee.add_stoppage` |
| Opponents out of the area at a goal kick | built | `SimSetPiece._out_of_penalty_area` |
| A restart the side reorganises around | partial — positions and a delay; routines are not authored | |
| A wall at a free kick | absent | |
| Advantage | absent — `SimReferee`'s header comment claims it; it is not in the file | |
| Substitutions, injuries | absent | |

## The body, the man, and what he knows

| Behaviour | | Where |
|---|---|---|
| Stamina, fatigue, match sharpness | built | `SimPlayer` |
| Every attribute the player pays for doing something | built — `teamwork` moves the decoy, `distribution` the keeper's short ball, and `decisions` is in the FB, WIDE and ST weights it was missing from | `SimOffBall`, `SimKeeper.decide_with_ball`, `SimRole._WEIGHTS` |
| A wet pitch, an undulating surface | built | `SimEnv` |
| Believed positions, stale and noisy | built | `SimPerception`, `ctx.beliefs` |
| A believed offside line, not the true one | built | `SimReferee.believed_offside_line` |
| Options gated by what he can perceive | built — a man outside the arc the passer is facing, beyond nine metres, is never a candidate; the arc widens with `awareness` and with a patient plan | `SimPerception.can_see` |
| The scan you can see — head turned to where he is looking | partial — the sim looks; nothing draws it | |
| Morale | absent — it moves when a goal goes in and nothing reads it | |
| Momentum, a side that is rattled | absent | |

---

# The proposals

Numbered, stable, and cited from code comments. Nothing here has been measured
*unless its entry says so* — **43** to **45** were watched and then counted, and
each says what the figure was. Every figure in them is from
`./run.sh scenario --trials 25 --acts`, whose rows are named in the entry.
When one is built its row above changes and its entry here goes.

| | Proposal | Where |
|---|---|---|
| **3** | Parry versus hold — the rebound cascade | `SimKeeper` |
| **5** | Blocks that cost the shooter, a keeper who narrows the angle | `SimKeeper`, `SimDuel` |
| **19** | Paired-run contrast | `tools/headless_main.gd` |
| **24** | The pass model is under-confident and the correlated terms are not why | `SimDecision.CORRELATED` |
| **27** | The direct plan does not play the longer pass | `SimTactics.direct_bias` |
| **28** | The engine plays at four times football's touch rate | `SimDecision`, `SimTouch`, `SimMovement` |
| **29** | What is left of the box: a corner the attacking side attacks | `SimSetPiece`, `SimOffBall` |
| **30** | Positional play in midfield, and the offside count that comes with it | `SimMovement.shape_position`, `SimOffBall` |
| **33** | The runner ahead of the ball is never generated as an option | `SimOffBall`, `SimDecision._add_passes` |
| **34** | Nothing in the sim reads the score or the clock | `SimTactics`, `SimContext` |
| **37** | The match has one tempo and football has two | `SimDecision.scan_gain`, `SimTactics` |
| **38** | Attributes make a player better, never different | `SimDecision`, `SimAttributes` |
| **43** | A goal kick is nine passes in his own half and then a turnover | `SimSetPiece._take_goal_kick`, `SimMovement` |
| **44** | A striker and a centre-back are the same speed | `SimRole._WEIGHTS`, `SimAttributes` |

**3 surfaced when shots started reaching the target.** About a third are second
attempts within four seconds of the last: parry, rebound, strike again. Real
football has rebounds, not at that rate.

**5 is the largest hole.** The engine reaches the penalty area about four times as
often as football does and nothing much resists once it is there. What is left of
the keeper's half is `_try_gather` asking a fresh catch roll every tick the ball
is near him — see `docs/INVARIANTS.md`, "a per-tick probability is a roll until it
succeeds". Fixing it gives back goal kicks and, with the rest of 5, corners.

**19 is the weakest of the four instruments** and the one that looked obvious. Two
runs of a seed diverge into different football within seconds of the first
different decision, so the diff measures a different match. Its one honest output
is the divergence tick: a knob that never diverges is dead.

**24 is what is left of the pass model's underconfidence, and it is `space`.** Two
of the five factors were constants and are gone. `space` is `control_at`, a share
of grass weighted by arrival time, read as the probability we end up with the
ball — different questions for a ball rolled to a man's feet. The aimed-ball half
is built (`control_at_pass`). What remains: **the terms fail together and are
multiplied as if they did not** — the defender who lowers `space` lowers `lane`,
and a ball struck under pressure is struck worse. **Do not close it with a scale
factor**; `which factor knew` would read a third constant exactly the same way.

**27 is a measured surprise, not a bug report.** The direct plan plays the
*shorter* ball under the standard clock (13.6 m against the patient plan's 14.7,
t = 3.1): the press circulates short and quick while the deep block clears long.
`direct_bias` values the forward ball, and forward is not long. Whether it should
prefer length is a football question — the plausible mechanic is reaching for the
ball in behind and the diagonal sooner. The suite's directional check is t-gated
until it is decided.

**28 is the tempo, and it is two facts that pull opposite ways.** On screen the
ball is played on **about every 1.1 seconds** — a possession sequence is 3.4
passes in 3.7 s of ticks, and football takes two to three seconds a man. That is
the thing an eye sees first and it is why the mean sequence gains 2.9 m and 65% of
passes go backward or square: the ball is gone before anything can be built. But
the *match* the player watches totals only **192 passes a team against a target of
300-600** (n=20), because 93 minutes of match clock hold 9.3 minutes of football.
**Slowing the man on the ball makes the second number worse.** The two countable
candidates for where the missing second went are the carry (0.33 s between
touches, the ball run 1.29 m, where a footballer pushes it 3-5 m) and the dwell (a
free man passes 48% of the time on his first opportunity, and `scan_gain` has to
out-score a pass rather than being the default); the third is that nothing costs a
man time to decide. **Which of the two facts is the target is the owner's call and
is not settled here** — see the open question at the end of the order.

**29 is what happens in the box, and most of it was the cross arriving at the
wrong height.** The pull-back and the volley are built. What was left, measured
over 24 matches by where every attempt on goal was struck from: 68% of shots
inside the penalty area and a mean of 15.3 m, which is football, but **headed
attempts at 0.60 a team a match against football's four or five, and struck from a
median of 13 m** — the edge of the box, not the six-yard box. Two causes, both now
answered, and neither was in the box:

- **The run into the box started too late.** `_box_point` carried the final-third
  test, so the striker set off when the ball was already 35 m from goal. It
  reached the list on 0.6% of the men considered and **won 90.3% of the times it
  did**. The test is the attacking half now, and the timing argument it was making
  is `_box_reach`'s to make — a man too far away is refused by his legs.
- **The cross came down through heading height 4 to 5 m short of its aim.** It was
  solved to arrive at *grass level* on the near post, which is a different point;
  `SimTouch.CROSS_ARRIVE` solves it to arrive at 1.9 m instead. And the bench that
  should have caught this was reading an air ball's finish as where it stops
  rolling, tens of metres past the far post, so `CROSS_RANGE_SPREAD` had been
  fitted to that: the decision layer was told a thirty-metre cross lands inside
  tolerance 36% of the time when the ball manages 69%, and turned down crosses it
  could hit.

**Where that left it, same 24 seeds:** headed attempts 29 to **41** and headed
goals 6 to **10**, shots inside the box 68% to **70%** with the six-yard share 13%
to **15%**, mean shot distance 15.3 to 14.5 m.

**Then the other half: who is there when it drops, and it was nobody.** `When the
cross drops` reads the trace at the strike tick plus the flight and counts bodies
around the point the ball was aimed at. It found **0.00 of ours within three
metres, on every cross of three matches**, with the nearest 9.3 m away and the man
it was aimed at 6 to 16 m off it — while making a box run. The ball and the run
were being decided in different moments by two copies of the same three points:

- The three points are **claimed, one man each** (`SimOffBall._box_claims`), best
  pair first, computed once for the side and read off by every man. Scored on his
  own race, nothing had stopped two men attacking the same point and nothing sent
  anybody to the far post: 15% went there, now 19-29%.
- **The cross is aimed at the man who claimed the point**, from the same
  `box_targets` the runs use, and still only if he can be there inside the flight.
- **The runner stops easing when a man is wide with his head up.** `BOX_EASE` holds
  him six metres short of the point until the ball is up; `BOX_EASE_CROSS` is two.

Nearest of ours at the drop went 9.3/11.6/6.2 m to **4.8/6.8/8.2**, and a quarter
of crosses now have a man within three metres of the ball, which is a quarter and
not most. **The outcome over 24 seeds went the other way**: shots 294 to 271 and
headed attempts 41 to 27, inside-the-box share 70% to 60%, goals 103 to 106. The
mechanism moved and the football did not follow it, which is the honest state.

**That third point was not running, and neither was the thing it modified.** Both
were found by probe rather than by reading, and both looked healthy from outside.
`_cross_coming` returned a float on every path — `1.0` for no and `CROSS_ON`, by
then also `1.0`, for yes — so the trigger read true always. Behind it, `point_for`
answered the onside question with an early `return`, which every box runner who is
not the man a ball in flight is for takes, so `BOX_EASE` was never reached at all:
**nought ticks of either arm over three matches**. The ease and the onside clamp
compose now, in that order, and `Which idea he had` counts the two arms so a dead
one says so. So the six metres above were never held and cannot be why he was late,
and every figure in this section was measured with the timing absent.

**Then the hold measured, seeds 1-3 at full length, against the two metres that
had been running by accident.** The six metres are right and the accident was
worse: a man within three metres of the dropping ball on 2 of 10 crosses against
**0 of 11**, and the nearest of ours 8.4 m against **10.7**. Shots 30 against 28,
headed attempts 74 against 96 with 3 at goal against 1. Held six metres short he
arrives; standing on the spot he is already past it when the ball comes down,
which is the run this was authored as. Thin -- three matches offer ten crosses --
so it settles which of the two ships and nothing about what either is worth.

The release is the part that does not work. It fired on 2, 4 and 31 ticks of a
match against 392, 702 and 508 held, because `_cross_coming` asks where the
carrier is standing this tick while the run was committed seconds earlier. The man
therefore holds his six metres nearly always, including as the ball is struck. A
trigger on a cross being *likely* is a mechanic rather than a knob, and it is what
is left of the timing.

What is left of 29 is a set-piece question as much as an open-play one: a large
share of football's headed attempts come from corners, and corners are 0.02 a team
a match until **5** lands.

**29, measured in set situations, 2026-08-23.** The scenario table puts numbers
on it that a match cannot. A corner is delivered in **100%** of trials and the
nearest of ours is **7.2 m** (right) and **9.1 m** (left) from the ball when it
comes down; headers off it run at 0.2 and 0.1 a corner; 64-72% end `lost`. The
`corner-left` trace is one event — the cross at 1.98 s — and then ten seconds of
nothing at all. A wide free kick is the same picture with the delivery even more
reliable: `fk-wide` crosses **1.0** a trial, produces **no shot in any of 25
trials**, and drops 6.4 m from the nearest of ours. The delivery is not the
problem in any of the three rows, which is what **29** has said since it was
written; now the run that is missing has a distance attached.

**30 is the owner's, 2026-08-15.** Keep structure and width, and make the midfield
a real link between the defence and the strikers. One midfielder dropping to meet
the defenders is fine; there have to be link players. **And fewer offsides** —
1.04 a team a match sits inside the 1-4 target, and the owner has still asked for
fewer, which is a judgement by eye and outranks the band. Runners going too early
and runners not going at all are the same subject.

**32 will not pay until the defence exists.** Inviting contact, the feint at a
standstill, the change of pace. There are 33 contests over the ball and 14
challenges on the man in a match, and the challenger wins 29% — too little contact
for a contact mechanic to show up in.

**33, first half: measured, and it was the trigger.** `and which idea he was
allowed to have` (new, `SimOffBall.chose_*`) counts every one of the 7824 men
`_consider` scores in a match. The run into the box was **a candidate on 0.1% of
them**, and the gate tally underneath says why: 57% were refused by the role test
and **every single one of the rest by "no cross on"** — `_box_point` carried
`_add_crosses`'s own trigger, so nobody attacked the box unless the ball was
already wide in the final third. It was never a valuation problem. Whenever the
option did survive to be scored it took **97.2% of the softmax and won**.

The width half of that test is now gone (the final third stays), and on its own
**it changed nothing**: box runs 6 to 26 a match, and box touches across 20 seeds
went 4.6 to 4.3. The run is made and still not served, which is the second half of
33 below and is now the whole of it. It also cost `test_tactics` its second
separating measure — `passes` t=2.0+ to 1.59, with `distance` steady at 4.39 — so
**the suite is red on that case pending the owner's call**; whether how deep the
ball must be before men attack the box is a plan quantity is a football question,
and inventing an answer to make a Phase 5 exit criterion pass is the wrong way
round.

The same tally found a second thing nobody was looking for: **`QUOTA` refuses
about half of everything that wins.** 3356 of 7199 space picks and 1089 of 2349
show picks won their softmax and were dropped, silently — `_consider` files a pick
and `_assign` drops it without a trace. Whether three into space and one showing
is the right ration is untested; the number was never visible before.

**33, second half — the generation gate, and it is where the attacking pass now
stops.**
`A man could be played in behind` counts every man ahead of the ball while
somebody decided and reports the first gate that refused him: over 2865 of them in
a match, **45% were refused at "not moving forward yet" and 32% at "not on his
list"**, and 5% were offered. The same fact from the other side: a `box` run is
made 6 times a match and **receives the ball 0% of the time**; a `behind` run 35
times, also 0%. Two halves, and it is not yet known which is the binding one — men
ahead of the ball are not running forward, *and* the ones who are do not reach the
candidate list. Both are `SimOffBall` and `_add_passes`, neither is a value knob,
and this is the fourth time this project has been caught pricing an option that
was never generated.

**33, measured in a set situation, 2026-08-23.** `through-ball` builds the
geometry the proposal is about — a midfielder on the ball at the top of his own
half, two forwards on the shoulder of a flat back line, grass behind it — and the
through ball is played **0.1 times a trial**. What is played instead is 7.1
carries and 2.0 ground passes, and the sequence ends wide and crossed: the trial
1 trace is three dribbles, a lofted ball to the right wing, and a first-time
cross blocked at 2.8 s. `box s` is **0.05**. The ball in behind is not being
declined by the softmax; it is not on the list.

**34 is the cheapest football on this page, and it was found by grep.** `ctx.score`
is written by `SimMatch` when a goal goes in, copied into the snapshot and the
telemetry, and **read by nothing that decides anything**. Neither is the clock:
`SimTactics` contains no reference to the minute. So a side three down with five
left plays exactly the football it played at kick-off — same directness, same line,
same width, same ration of men beyond the ball — and the last ten minutes of a
match look like the first ten. That is the one shape every viewer knows by heart,
and its absence is not a missing mechanic: every dial a chasing side would move
already exists (`directness`, `line_height`, `counter`, `retention_bias`, the
`QUOTA` rations). What is missing is the *reader* — one function from goal
difference and minutes remaining onto the dials the plans already set, with the
protecting side's mirror of it. It is an attacking item and belongs to this pass:
a side chasing a goal pushes bodies past the ball, and the game stretches.

Two cautions, both from this file's own history. It has to be **the shape of the
match, not a scale factor on scoring** — the thing a viewer sees is more men in
the box and a longer ball, not a better shot. And it will make the goals
correlated within a match, which every per-match measurement here assumes away;
`chains --against` compares across seeds and is the honest instrument.

**37 is the fresh idea 28 has been waiting for, and it does not need 28's question
answered.** The open question at the end of this order asks whether the man on the
ball is too quick (1.1 s a touch against football's two to three) or the match too
short to hold enough of them, and says the two pull opposite ways: slowing the
carrier makes the pass total worse. **Contrast is the way through that costs
nothing on the mean.** Football is not played at one tempo — it is twenty seconds
of the ball going sideways at the back, then three passes in two seconds — and this
engine has one rate for both. Raise the variance and leave the mean where it is:
the same number of passes a match, and a match that has phases in it.

The state is a possession's own phase — settle, probe, attack — with hysteresis
so it does not flicker, driven by pressure on the ball and where play is rather
than by a timer, and moving `scan_gain`, pass-length appetite and the errand
rations together. **The thing that makes it football rather than a knob is the
acceleration being caused**: the phase turns over when a man is free between the
lines, which is the moment 30 built the link players for.

**38 is that the engine has a quality axis and no style axis.** The softmax
temperature reads `decisions`, so a better player plays closer to the best option
and a worse one further from it — but every player is aiming at the *same* best
option. Two equally good midfielders play differently in football: one takes the
ball into contact and tries the pass through, the other has it and gives it. Here
they are the same man with different error bars.

The mechanic is a per-player bias on the terms that are already separated and
already named — `retention_bias` against the forward ball, the through ball's own
weight, the carry against the release — drawn once at squad generation and stable
for a career, because the point of it is that the same man is recognisable across
matches. It also answers half of the `STATUS.md` note that squad quality reads in
ball control and not at all in chance creation: **a better side that is only more
accurate looks like the same side**, and this is what a viewer would be reading
instead. It is worth nothing until 33 and 30 give a midfielder a forward option to
be characteristically brave about, so it is not next.

**The owner's shape for it, 2026-08-23: traits, as their own layer.** Not a bias
threaded through the attribute set but *a separate thing beside it* — a named
list a player either has or does not, read by the decision layer where the
attributes are read, and never averaged into a rating. An idea, recorded rather
than designed; what follows is only what the note has to carry.

Why the separation is the whole of it. An attribute is a quantity on a ladder
and every one of them is better upwards, which is exactly why they cannot express
taste: there is no value of `passing` that means *tries the ball nobody else
sees*, only values that mean more or less accurate. `SimAttributes.ALL` is
iterated to draw a player against his quality and again to average him into
`role_rating`, and a trait belongs in neither loop — "shoots from distance" is not
a thing a better player has more of, and a squad rating that counted it would be
saying it is. This is the argument the foot already makes in miniature and is
worth reading first: `foot` and `weak_foot` sit outside `ALL` for exactly these
two reasons, and 35 is the small end of the same idea.

The three things a trait layer has to settle, none of them settled here:

- **What a trait attaches to.** The candidate's score, or its generation? A trait
  that only reweights is a value knob, and this file's own history says a value
  knob cannot create an option that was never generated — the box run was priced
  for a year while nothing put it on the list. "Runs beyond the striker" has to
  reach `SimOffBall`'s errand quota, not the softmax.
- **Whether they are drawn or authored.** A drawn trait makes every squad various;
  an authored one makes a *particular player* legible across a season, which is
  the thing a manager remembers. Probably both, and the split is a design question.
- **Whether a viewer can see one without being told.** The test of the layer. A
  trait nobody can name from the stand is a number in a save file, and the engine
  already has plenty of those.

**39 and 40 were one thing on screen and two in the code** (owner, 2026-08-23,
watching `1v1-clear`), and both are built. The striker was through, took one
touch, and the ball simply ran on without him; the keeper collected it; a beat
later the ball was at the striker's feet again and he scored. The owner's words:
*even though it is a goal the behaviour is wrong.*

**39 was the carry, and the act was the burst.** The trace of `1v1-clear` at seed
4001 is one `dribble` of 6.4 m at 0.0 s from thirty metres out and then nothing
until the keeper takes it at 2.6 s: the ball ran 24 m untouched and the row read
`touch` 3.4, `gap s` **2.84**, `lost` **56%**. It was not a man dribbling badly
and it was not a candidate that failed to generate — the knock was generated,
scored and played, and it was sized against the *touchline*. Nothing asked
whether the ball would come to rest in the keeper's hands twenty metres before
it got there. `SimDecision.keeper_room` is the room test that asks: a hard one,
which is the right shape for a line he is running at, and it only bites inside
the area his hands work in. Measured after: `gap s` **1.05**, `touch` 5.0,
`lost` **12%**, and the trace is an opening stride touch, five short ones and a
shot from eighteen metres.

**40 was the keeper, and it was what made it a goal instead of a lost ball.**
`SimDuel.resolve_contacts` skips goalkeepers as contenders and then treated the
ball sitting at his chest as a loose one, so the striker he had just taken it
from was a contender for it and took it straight back. A caught ball is dead —
the situation is over and the restart is his — and `SimKeeper.ball_in_hands` is
now the one place that says so.

**41 was the orientation beat, priced but not enforced**, and it is built.
`shot-edge` puts the ball at the top of the box with two centre-backs four
metres in front of it. Every trial, at **0.01 s**, he shot: 1.0 shots and 0.0
carries a trial, mean time to shot one hundredth of a second.

**The candidate list is what named it**, and it needed an instrument that did
not exist — `replay` now takes `--scenario NAME`, so the situations the table
scores can be opened at the decision that made them. Seed 4001, tick 1:

```
> shot, 19 m    0.1356   succ 0.03  gain 1.000  bias 5.74  set 0.50   w 98%
  hold          0.0820   succ 0.63  gain 0.135             bias 1.05  w  2%
  carry fwd     0.0351   succ 0.18  gain 0.235             bias 1.16  w  0%
```

Eleven candidates, so nothing was missing from the list and the settling touch
was there to be picked. **`set 0.50` is the beat, already applied** — and the
shot still takes 98% of the softmax, because `bias 5.74` is the compressed
match's `shot_appetite` and the two sit on opposite sides of one product.
Neither can be tuned against the other: the appetite is the scoring fit and is
one object (`docs/INVARIANTS.md`), and the beat is a fact about a body.

So the beat is a gate as well as a price — `SET_STRIKE_FLOOR`, a quarter of a
second of orientation below which no strike at goal is generated. It is narrow
by construction: only a man whose ball is already under control and who has had
*no* look at all. A first-time strike is a different act and is exempt, and
`readiness` counts a pass's flight as preparation, so a received ball is never
gated — what it catches in a match is the man who has just won a tackle, for a
quarter of a second.

Measured after: shots struck at **0.53 s** rather than 0.01, from 17.4 m rather
than 18.6, with **1.6 carries** a trial in front of them where there were none.
The trace is two setting touches and then the shot. **The 1v1 rows moved with
it** — every strike out of a fresh spell now waits a beat — but at n=25 those
moves are one to two standard errors and the row that was aimed at is the only
one that moved decisively.

**The same row is where 5 has a number on it.** Two centre-backs standing four
metres in front of the ball produced **0 blocks in 25 trials**, and 80% of the
shots through them reached the target: 32% goal, 48% saved, 20% off. With the
beat in front of the shot it is 1 block in 25 — the defence gets the quarter of
a second it never had, and does almost nothing with it.

**42 was 25 aerial duels, 25 headers, 25 losses**, and it is built. `aerial`
drops a long ball between a striker and a centre-back twenty-eight metres out.
Our man won it and headed it — 1.0 headers a trial, so the duel and the header
both worked — and the resolution was `lost` **100% of the time**, every trial,
with no shot and no retained possession anywhere.

**The trace named the act: `head=0`, cleared, every seed.** `SimAerial.play`
had three acts and the third was the fallback for all of them — a man who found
no teammate inside `HEADER_REACH` played `head_clear`, which aims at the far
goal and *wide*. That is the right ball out of your own six-yard box and a
giveaway from anywhere else, and an isolated striker thirty metres from the
opposition goal is anywhere else: the ball went eight to twenty-five metres
toward the corner flag with nobody of ours going after it.

**The fourth act is nodding it down for himself** (`_head_down`), aimed by
`SimDecision.safe_direction` — the same function the chest-down asks, and the
same question: not where the goal is, but where the ball is still his. It is a
cushion rather than a nod, which needed `SimTouch.header` to gain a
`power_scale`: the power there is entirely about how far a man can *send* one,
so a knock-down at full power is a clearance whatever it is aimed at.

Measured after: `lost` **68%**, `none` **28%** — the clock running out with the
ball still ours, which is the good outcome here — 4.0 touches a trial against
1.0, and a shot where there was none. What is left is a lone striker losing a
fifty-fifty to a centre-back with no support, which is football. The knock lands
one to two metres away and is still moving; roughly a third of the time the
centre-back gets a head to it before our man turns, and **whether the man who
nodded it down should be favourite for his own knock-down is an open question**
— nothing in `SimMovement` knows he chose where it was going.

**43 is the goal kick, and the trace is the finding.** `goal-kick` retains the
ball for eleven seconds and 88% of trials end `lost`, `box s` **0.00** — the
side never once reaches the opposition box. Trial 1 in full: eight passes from
x=-47 to x=-6, not one of them past halfway, then a duel lost on the touchline.
The passes are not bad; there is nowhere forward to put one, which is **30** and
**33** seen from the goalkeeper's boot. It is listed separately because the
restart is the one moment a side has eight seconds to arrange itself and this is
what it arranges.

**44 is measured, and it is small enough to be worth writing down.** `race`
knocks a ball into the channel and starts a striker and a centre-back level with
it. Seed 4001: the striker's top speed is **8.09** and the centre-back's
**8.83**. Seed 4004: **9.36** against **8.92**. The race is a coin toss decided
by the draw, because `pace` has relevance 0.8 for a striker and 0.6 for a
centre-back, and at quality 0.6 the draw `lerpf(0.35 + 0.3 * q, q, relevance)`
puts them at **0.586 and 0.572** — one and a half per cent of the range apart.
A centre-back is as quick as a striker in this engine. It is **38**'s point
("attributes make a player better, never different") with a specific number, and
**15**'s draw formula is the mechanism.

**The arithmetic is confirmed and it was not what was deciding the row**, which
is worth writing down because it nearly went in as a fix. Probed tick by tick,
the two men in `race` were not sprinting: the speed cap on each of them read
8.0, 8.0, 8.0, **5.0**, 5.0, 8.0, **6.0**, 6.0, 8.0 over two seconds of a foot
race they were four metres down on. Both were braking for a third of it, and the
race was settled by whose brakes landed worst. `_contest_pace` reads its own
output — the cap sets his speed, his speed sets the intercept, the intercept
sets the margin, the margin sets the cap — and recomputed clean every refresh
the loop closes. Latched (`docs/INVARIANTS.md`), both men now hold top speed for
the whole race and it is decided by pace, which is what the row is named for.

**What is left of 44 is a change to every player in the game**, and it is 38's
rather than this row's. `lerpf(0.35 + 0.3 * q, q, relevance)` has two anchors
that converge at mid quality: at q = 0.6 they are 0.53 and 0.60, so the whole
role system spans **0.07 of attribute while the draw's own spread is 0.12**.
Role is noise at the level the game is measured at. And relevance can only pull
an attribute *up* toward its owner's quality — it can never put one below the
population, so **a player has strengths and no weaknesses** and "a centre-back
is slow" is not a thing this engine can say. Fixing that means a tilt term with
a fitted coefficient, applied to every attribute of every player, at a moment
`PLAN.md` §11.1.1 says to tune late. It is the owner's call, not a side effect
of a scenario row.

**45 was the take-on**, and it is built. `take-on` puts a wide man on the ball
twenty-six metres out with a full-back two metres in front of him and nobody
else near. **92% of trials ended `lost` and none in a goal**; the trace was
three small touches and then a thirty-metre ball infield at 19.6 m/s to where
the other side picked it up. He did not run at the man and he did not go round
him.

**Two things were wrong and the candidate list separated them.**

**The row was measuring its own placement.** `SimDecision.BURST_PACE` is 3.5 —
below it the engine holds that knocking the ball past a man is not a foot race
but a giveaway — and the scenario started the winger at **3.0**. The take-on was
never a candidate, so the softmax was not declining it and no value knob could
have reached it. The third of the twenty-five to do this. He starts at 5.0 now,
which is what a winger receiving in the final third is doing.

**And the act on the list was not a take-on.** Started at burst pace, the
candidate read `burst fwd 21.6 m` at **`succ 0.00`**: a twenty-one-metre ball
arriving 4.3 seconds later, which `control_at_time` correctly prices at nothing
because by then the whole defence is level with it. The size gate was
`push < BURST_DISTANCE * 0.55` — five metres of *gap* — and a gap is not a
distance over the grass: at 5 m/s five metres of gap is twenty-one metres of
ball. The knock is now sized by the man rather than by a constant, `BURST_CLEAR`
to `BURST_PAST_MAX` past where he stands, in the frame he is standing in.

**And the man being beaten was charged twice.** `_escape_value` prices the race
against him and `_lane_survival` then charged him again as a leg in the lane,
which is the same man in the same act — the whole point of a take-on is that he
is in the way. `control_at_time` already took him as its `ignore_id`; this term
had missed the convention. Measured on its own, that one line is `succ` **0.02
to 0.44** and the weight the softmax gives the take-on **0% to 96%**.

The trace now goes forward and outside — 27 to 32 in x, 24 to 21 in z — with
0.7 duels a trial against 0.1, and crosses up from 0.28 to 0.44 a trial. `lost`
is **80%**, barely moved, because what he now reaches the byline to do is put in
a cross, and **29** is what happens to it.

**One measurement hazard, found while doing this.** `SimDuel` logs
`SimTelemetry.Touch.BLOCK` for *any* loose ball won without control that did not
come from a contest, so a defender jogging onto a ball nobody struck at him is
recorded as having blocked it. `race` reads "block" where the football is "he got
there first". Anything counting blocks — including `--acts` — is counting those
too.

**46 is where the shot gets taken from** (owner, 2026-08-23, watching the
one-on-one): *the shooting range is a bit too far away. Long shots should be an
option, but not the default, especially in 1v1 situations.* Four things were
found and fixed under it and the row it was named for still has not moved, so
it stays open with what is known written down.

**The carry was priced against a model of itself that was eight to twenty times
out.** `carry_travel` is where the ball would be if he never touched it again --
the burst's question -- and it was the horizon every carry probe was scored at.
`./run.sh diagnose`, counting the ball at consecutive dribble touches in the
same match, says the ball runs **0.55 m** between them where that function
claims 4.3 at the mean speed of a match and 11 at a sprint. `touch_travel` is
the honest one and `_in_play_odds` now asks it, which stopped an unpressured
striker being charged for putting the ball over a line it was never going to
reach.

**Correcting it exposed a units bug it had been hiding.** `_add_dribbles` used
one expression as both the size of the touch (a gap) and how far down the line
he is going (a distance over the grass). With the overstated travel gone the
horizon collapsed: at twenty-one metres from goal the forward probe came back
priced two metres in front of his own feet. `CARRY_HORIZON_SECONDS` separates
them.

**And the risk and the reward were being read at the same point.** At
twenty-two metres from goal with nobody within twenty metres, the forward carry
scored `success` **0.07** beside its own gain of 0.517 -- `control_at_time` was
being asked who owned grass six metres nearer the keeper than the ball was
going. Split, the same probe reads **0.53**.

**Measured, the shot came closer nearly everywhere and not where it was
watched.** `hold-up` 23.5 m to 12.8 (since drifted back), `cross-left` 16.3 to
9.5, `cross-right` 15.2 to 12.1, `shot-edge` 17.4 to 16.7 with goals 28% to
**44%**, `1v1-onrushing` 22.6 to 21.2 with `lost` 20% to 8% and goals to 52%,
`cross-byline` to 28% goals. **`1v1-clear` went 21.6 to 21.3 and is the row the
owner watched.**

**46 was the settling touch, and it is fixed.** He took six touches and advanced
nine metres, seven of them on the first: after that `hold` won decision after
decision, and a hold goes nowhere. `_hold_score`'s own docstring says a hold
"cannot beat a winning one" -- and the arithmetic of a man through on goal was
`0.83 success x 1.05 bias x 1.28 look x 0.99 discount` = **1.10 times the option
it was deferring**. The term that broke the invariant is the dwell. `scan_gain`
is the understatement in a continuation caused by `SimPerception` keeping his
view of his *teammates* stale, and it was being applied to continuations that do
not depend on them at all: a shot at goal, a carry, a clearance. Gated on
whether a look could buy anything, the invariant holds again. `1v1-clear` goals
**12% to 20%** and `lost` **28% to 20%**.

**What it did not do is move the shot distance**, which is what was watched.
`1v1-clear` has read 21.3 to 21.6 m through every one of these, and the reason
is arithmetic rather than football: a shot from twenty-two metres has an
`expected_goals` of **0.03** and scores 0.19, because `shot_appetite` is 5.74.
Nothing else on a one-on-one list reaches 0.19 -- the best carry is about 0.17 at
its healthiest -- so the shot wins, and it wins from wherever he happens to be
standing when it first clears the floor.

**A flat multiplier on every shot cannot be the right shape for this.** The
appetite exists because a compressed match holds fewer seconds of football and
needs goals per second scaled to match; applied as a flat bias it also moves the
crossover between shooting and everything else, and it moves it furthest out
exactly where the shot is worst. That is the one-line statement of "long shots
are the default". But it is the compressed clock's scoring fit, it is
deliberately one object, and `docs/INVARIANTS.md` says a sixth constant goes in
that list rather than beside the mechanic it scales -- so **this is a tuning
freeze job and the owner's call**, not something to be quietly reshaped from a
scenario row.

**47 was the ball running away from the man carrying it** (owner, 2026-08-23,
watching `1v1-clear` trials 4 and 7: *a carry forward becomes much longer than
the player intended*). It is built, and it was two faults in the strike.

**The ball is not at his feet when he plays it.** `SimTouch.dribble` sized the
touch to open a further `ahead` metres, on top of the 0.86 m the ball already
lay in front of him -- so a man asking for it 1.7 m ahead got it 2.6 m ahead,
struck at 9.0 m/s while he ran at 5.3, and it stayed outside his 0.9 m reach for
**1.15 seconds and nine metres** with his touch cooldown reading zero the whole
way: ready to play it and unable to reach it.

**And the mis-hit was bigger than the intent.** `_perturb` scales the whole
velocity, which is right for a pass or a shot -- struck from nothing, so all the
speed is his. A carry is not: most of the ball's speed is momentum it already
shares with a running man, and that is in the ball whether he strikes it well or
badly. At 8.8 m/s the gap he wants is worth 0.93 m/s of relative speed and a
twenty per cent error on the total is 1.95, so **the size of every carry was
decided by the draw rather than by the decision**. The weight now scales
`delta` alone.

Measured in a match, the longest a ball ran between two touches of one carry:
**16.8 m to 4.3 m**. Across the scenario table the `away` column -- the furthest
the ball got from the man whose it was -- fell in every row: `through-ball` 3.33
to 2.39, `cross-right` 2.54 to 1.77, `take-on` 2.20 to 1.68, `1v1-chased` 2.01
to 1.57, `hold-up` 1.60 to 0.99. Trial 4 is now ten touches at 0.22 s intervals
and a shot from nineteen metres; trial 7 is a goal from fourteen.

**It moved the bands and some of it wants watching.** Touch counts are up
everywhere and several rows now produce no shot at all -- `take-on`,
`through-ball`, `aerial`, `switch`, `build-up`. A carry that keeps the ball is
an option that got better, so the softmax takes it more often; whether that is
football or whether the shot now needs to answer it is the next thing to look
at, and it belongs beside **46**'s note on the appetite.

**49 is the shot appetite, and it was the wall behind everything above**
(owner, 2026-08-23). Four separate fixes to the carry — the strike, the re-touch
model, the pace floor, the keeper race — each did what it claimed and none moved
where the shot came from, because a **three per cent** chance from twenty-seven
metres scored 0.137 against the best carry's 0.091 and took 98% of the softmax.
`shot_appetite` is 5.76 at the nine-minute clock and it was paid flat on every
strike.

**A flat appetite does not buy shots, it buys them from the wrong places.** The
constant's own note records forty compressed matches in which moving it from 1 to
8 changed shots per team by 2.29 to 2.40. What it moves is the crossover between
shooting and everything else, and it moves it furthest out where the shot is
worst — which is the whole of "long shots should be an option, but not the
default".

`SHOT_APPETITE_KNEE` pays it on the chance instead: in full on a chance worth
0.10 expected goals and in proportion below, squared. **Squared because the ramp
scales both sides of the question** — the shot he could take now and the shot he
is carrying toward ask the same function through `_carry_shot_gain`, so a gentle
ramp lifts them together and decides nothing. Measured on `1v1-clear`, a linear
ramp moved the shot in by one metre and moving the knee *out* made it worse.

Measured at the knee, `1v1-clear`: shots from **22.4 m to 16.3**, goals **24% to
44%**, off target 40% to 16%. Elsewhere `1v1-angle` 15.2 to 13.4, `through-ball`
to 11.1, `cross-byline` to 12.7, `hold-up` to 16.0. `shot-edge` is unmoved at
17.5, which is right: a chance from the edge of the box with two bodies in front
of it is a poor one however keen the format is.

**The value is a first fit and belongs in the tuning freeze** (`PLAN.md`
§11.1.1). It was chosen by measuring 0.06 to 0.30 on one row at twenty-five
trials, which is enough to see that lower is better and not enough to settle it.

## Order

Two passes, attack first (`PLAN.md` §11.4). Within a pass: by how wrong the match
looks without it, cheapest first. **Every figure below is measured at
`clock_rate` 10, the match that ships, and nothing is measured anywhere else** —
`docs/STATUS.md`, "what every figure here is worth".

**The attacking pass — the current work**

**Built 2026-08-23: the foot, and what it does to the ball.** **35** and **36**,
taken together because they are one subject — a footballer's strike has two body
axes and the engine had one.

The foot rides the seam the facing model already cut. `off_axis` asks how far off
the way he is pointing the ball is going; `lateral_of` asks which side of him it
is on, and `foot_cost` prices it exactly where `facing_penalty` is priced — into
`aim_sigma`, which `execution_accuracy` shares, so **the decision layer paid for
it the moment the strike did and no valuation code was written at all**. A carry
onto the wrong side scores worse, a cross from the wrong flank scores worse, and
the winger cutting inside is the softmax noticing. `strike_scale` takes it as a
second factor, so the weak foot shortens the ball as well as spraying it, and
`facing_control` refunds what `aim_sigma` charges because a candidate priced under
one and struck under the other is the bug that reciprocal exists to prevent.

`foot` and `weak_foot` sit outside `SimAttributes.ALL` deliberately: that list is
iterated to draw a player against his quality and again to average him into
`role_rating`, and a foot is neither a quantity nor better in one direction.
Footedness is drawn against the *slot*, not flat — a flat draw has no such thing
as an inverted winger, because there is no expectation to invert.

**36 was written as an absence and the code said otherwise, which was the useful
half.** `SimBall` has carried a three-axis spin and a `spin.cross(vel)` Magnus
term all along, and `SimTouch` already yawed the driven ball, the lofted ball and
the cross. The physics was free; the *intention* was missing. Every curl was
zero-mean noise scaled by technique, so the better a player was the harder he bent
it in a direction `ctx.rng` chose, and half of every cross curled into the
keeper's hands. `curl_for` signs it by the foot that struck it — the inside of the
boot turns the ball away from the foot, so right-footed it bends left — and the
sign is read off `foot_choice`, the same comparison that charged him for the foot,
so the ball bends off the boot he was billed for.

Only balls whose launch is *solved* with the spin in hand can carry a signed mean:
the shot, the lofted pass and the cross all pass their spin to `solve_direct` or
`solve_lofted` and arrive where they were aimed along a bent path. **The driven
ground pass does not** — its spin is stapled on after `ground_launch` has solved
the speed — so it keeps its zero-mean noise and a comment saying why, which is the
one place a signed curl would simply bend every pass in the game off its target.

**And a bug fell out of it.** The corner's swing was `-signf(taker.pos.z)`, which
reads the same at both ends of the pitch while the goal being attacked does not:
one team's corners from a given flag swung in and the other's swung out, from the
same expression. It asks the taker's foot now.

**What it was verified with, and what was deliberately not measured.** A term that
never varies cannot be the cause of anything, and this project has been caught
four times pricing something dead, so the first question was whether the foot
reaches the strike at all: `SimTouch.foot_strikes` and the two means beside it,
printed by `diagnose` under `The small acts`. Over a ten-match-minute fragment the
mean ball is struck **0.54 across the body** — so no, a carrier does not simply
face where he plays it, and the term has its full range — **9% of strikes are off
the weaker foot**, and the mean foot cost is 0.16. Then the mechanism itself, in
`test_touch`: the lateral geometry and its sign, a right-footer paying on his
right and a left-footer mirroring him, a two-footed man paying nothing either way,
the curl's sign off each foot, and the right-footed corner from the left flag
swinging toward the goal.

**Nothing was measured about what it is worth**, and that is the point rather than
an omission. Which way goals, shots or completion should move for footedness is
not a question anybody has answered — a mechanic that makes half of every player's
options worse is expected to cost goals (`PLAN.md` §11.1.1) — and a check that
asserted a direction would be failing for being right. The golden digests moved,
as a changed mechanic makes them, and were re-recorded.

**Built 2026-08-15.** The box run's trigger; `RUN_IN_BEHIND`, installed in a plan
with no trigger; `destination_for` ignoring a pattern's override; the pattern
runner's missing check-back; the `moving_on` gate; the box and space rations;
**14**, **15**; the pull-back; the volley; **31**, the one-two; **26**, the driven
ball; **2**; **12**, which needed the visibility model built rather than a gate
added to one; **8b**, on the ball in behind; **32** entire — inviting contact and
the feint at a standstill; and **30**, the link players.

**Built 2026-08-16.** The passer's memory — `can_see` was an instantaneous cone
and refused 46% of every teammate weighed, which is two models of the same event
(`update` prices the staleness of a man behind you, and this said he was not
there); it asks when he was last in the arc now, and refuses 19%. The pass
shortlist's cap, which bound on 78% of decisions and threw away 2.6 men each to
save about 1,700 scorings a match: nine, measured at no cost. And **29**'s two
halves, above.

**Where it left the engine, twenty seeds, start of day to end:** goals 3.50 to
**4.44**, shots 5.09 to **5.84**, touches in the opposition box 4.6 to **7.3**,
offsides 10.4 to **8.4**, distance 13.0 to 14.4 km, pass completion 69.5% to 64.0%.
Touches by third went 10/78/12 to **14/67/19** — the middle-third lock this file has
called rough since it was written, easing at last. **One sanity range is broken and
it is the held one:** corners at 0.02 a team a match, which needs a defender to put
the ball behind and is **5**.

**Built 2026-08-16, second half of the day: the shape.** Two instruments and one
cause. `diagnose` gained `The clump` — the density the eye sees rather than the
extent `The width` measures — and `Holding the shape`, which puts the formation's
own point beside where the man ended up, split by which arm of
`SimMovement._recompute_target` took him there. It found the side standing a mean
11 m off its shape, every arm alike, and the second table said why: the point each
man was running at was moving at 4 to 7 m/s against 1.9 of shape-holding pace.
**The shape was defined faster than a footballer can run**, because
`shape_position` read the live ball and every station slides with it.
`ctx.shape_ball` follows the ball at 3 m/s now, and only the shape reads it.
Marking was made zonal away from the ball in the same pass — it is 40% of every
outfielder-sample and was the largest single arm out of shape.

Then the same question of the four remaining arms, which the block had ranked:
`drift` naming a point moving at 7.9 m/s, `ascent` 7.7, `support` 5.3, `press`
changing its mind on 47% of consecutive samples. **One of the four was the cause
of three.** `_support_adjust` returned the ring outright — every man level with
or behind the ball and inside `SUPPORT_REACH` put on one 12 m circle round it,
four or five at a time, and a circle round the ball travels at the speed of the
ball. It is also the base `drift` and `ascent` are computed on top of, so both
inherited its motion. Stepped instead of teleported (`SUPPORT_STEP`), and reading
the shape's ball like every other station rule, all three came down together.
`press` was the only one left, and its side-of-the-ball sign was recomputed every
tick: a presser near the line through the ball flipped it and his target crossed
ten metres. Latched for the length of the press.

**Where that left it, three seeds, against the start of the day:**

| | before | after |
|---|---|---|
| off its own shape | 11.0 m | 8.7 m |
| of that, errand | 11.2 m | 9.0 m |
| net pull onto the ball | 6.0 m | 3.6 m |
| teammates within 8 m, of ten | 3.7 | 2.5 |
| cells of fifteen occupied | 6.5 | 7.1 |
| most in one cell | 3.2 | 2.8 |
| of twenty inside one 12 m circle | 5.7 | 4.8 |
| every arm's target, bar the chase | 4-8 m/s | 1.5-3.4 m/s |
| mean speed | 2.7 m/s | 2.7 m/s |

**The picture followed the mechanism this time**, which the first cut's did not.

**And then the station's own jumps.** The shape has an attacking form and a
defending one, and four things switched between them on
`possession_team == p.team` — `ball_pull_shift`'s midfield hold,
`_build_up_width`, `lateral_pull` and the phase shift — worth fifteen metres of
station between them and arriving in a single tick at every change of hands. A
mean cannot see a once-a-turnover teleport, so `Holding the shape` gained the
column that can: the share of samples where the station outran a sprinter.
`SimContext.shape_phase` eases the switch over 2.5 s, and with
`SHAPE_PHASE_SECONDS` set to nothing as an ablation the old behaviour comes back
exactly: **1.4%, 1.3%, 0.7% of samples against 0.7%, 0.6%, 0.3%**, halved on
every seed. Mean speed came down with it, 2.7 m/s to 2.4, and the side ended
0.6 m closer to its own targets. What is left is item 7.

**One thing was got wrong on the way and is worth keeping.** The first cut gave
`lateral_pull` `_build_up_width`'s depth ramp, on the reasoning that build-up
width and build-up lateral pull are the same idea. They are, but that ramp only
reaches full strength in the defensive third, and four fifths of the football is
in the middle third — so it quietly put the possessing side back near
`BALL_PULL_Z` almost everywhere and undid the owner's own 0.16-to-0.10 dial. It
cost 0.8 m of closing onto the ball on all three seeds before the block caught
it. `BUILD_UP_FADE` is a 12 m band at the halfway line instead. **A smoothing
that changes where a constant applies is not a smoothing.**

The subject in one line: **a positioning rule is answerable for how fast the
point it names moves**, and its corollary — **a boolean in one is a station that
teleports.**

**Tried, measured and reverted — results, not gaps.** Each is left in the code with
its numbers, because the next reader of the proposal will reach for the same thing:

- **`SimOffBall._worth_at`** — pricing the run in behind and the run into the box
  like positions cost 1.1 goals. The men who go beyond are the men who were
  linking, which is **30** from the other side.
- **`SimDecision.CORRELATED`** — **24**'s own mechanic. Cost 0.84 goals and **the
  calibration it exists to fix did not move**. The under-confidence is not the
  three terms sharing a cause.
- **`LENGTH_COST_DIRECT`** — **27**'s own mechanic. Did not separate the plans on
  length (t=1.32) and took `test_tactics` red. 27's football question is still open
  with its named answer struck off.
- **`SimValueField.line_broken` on the lofted ball** — cost 1.28 goals. The ball
  over the top is *already* chosen for being beyond the line, so the term only buys
  more long balls at the rate long balls complete.
- **`QUOTA` show 1 → 2** — cost 0.93 goals. One man coming short is right, which is
  the owner's own words arriving as a measurement.
- **`SimOffBall.CROSS_ON`** — the run into the box worth three times as much while
  a man is wide with the ball. It is the third time this shape has been measured:
  more men in the box, fewer in the link. Over 24 matches it bought 6 headed
  attempts (27 to 33) and cost 23 shots and 13 goals. The same fact is kept as
  *timing* — `_cross_coming` decides how far short the runner holds — because
  where a man should be standing is not what a value knob answers. The constant is
  gone; the function it gated returns a `bool`, which is what the two call sites
  were reading it as while it returned `1.0` on every path.

**Struck on reading the code:** the two "dead pass factors"; three of the "four
constant knobs"; `territory`; **4**, an observation wanting the owner's seed rather
than a build; and the one-on-one answers, gated on a keeper who never leaves his
line, which is **5**.

1. **33, second half — the runner is made and not served.** `behind` runs 52 a
   match, received about 3% of the time. `A man could be played in behind` refuses
   42% at "not moving forward yet" and offers 7%.
2. **The cross's offer rate**, which is what is left of its two thin links. The
   delivery half is answered: the ball was arriving below heading height short of
   its aim and the model was told it scattered twice as far as it does
   (`SimTouch.CROSS_ARRIVE`, `CROSS_RANGE_SPREAD`, and **29**). The offer rate had
   not moved all day at 11.7% to 11.8% and is generation — one seed now reads 16%,
   which is one seed. See `CROSS_FROM`.
3. **24 and 27**, both now wanting a fresh idea rather than their named one.
4. **8b's other half** — the map itself is still single-step; only the ball in
   behind is corrected, and the lofted ball measured worse for it.
5. **Pattern success rates at n=20.** The instrument exists (`and was the ball it
   asks for ever on the list`); what is missing is a batch that aggregates patterns,
   which `chains` does not. At n=1 the switch has read 0% and 25% in one day.
6. **`QUOTA` behind, decoy and second** — show and space are now measured, these
   three are not.
7. **What is left of the station's motion is the leash, and it is meant.** The
   four possession switches are eased (`SimContext.shape_phase`); the stations
   that still outrun a sprinter, 0.3 to 0.9% of samples, are `SHAPE_BALL_LEASH`
   dragging the shape behind a ball hit sixty metres. That is the one moment a
   side really does turn and run, so it stays until somebody watching says
   otherwise.

**The defensive pass — next, not now.** Held deliberately; each costs goals, and
the attacking pass is allowed to run high until they land. **5** first — it is
still the largest single thing an eye would name — then **3**, then the remaining
defending rows above: jockeying, covering, the offside trap, the deliberate foul.
Two measurements belong to it and are recorded here so they are not lost:

- **Corners run at 0.02 per team a match against a target of 3-8**, n=20 — the
  emptiest number the engine produces. A corner needs a defender to put the ball
  behind or a keeper to parry wide, and neither act is built. They come back with
  **5**, as its entry already says.
- **3 of 11 shots are second attempts inside four seconds** of the same team's
  last — the rebound cascade, live now.

**19 sits outside both.** An instrument rather than a behaviour, worth taking
whenever a change is about to be judged by whether an outcome moved.

## The open question this order cannot answer

**The match is sparse, and the goals are not overshooting.** At n=20 full-length
matches: 5.09 shots a team against a target of 8-18, 192 passes against 300-600,
1.64 fouls against 8-16, 0.02 corners against 3-8, 4.6 box touches against
football's 25 — and 3.50 goals, inside the 2.9-4.1 target, held up by converting
**0.344 of shots against football's 0.10** with 74.5% of them on target. §11.4
expects the half-built attack to overshoot the goal count badly. It does not. It
produces a quiet match with a handful of near-certain chances.

Two readings, and they want different work:

- **The match holds too little football.** 93 minutes of match clock contain 9.3
  minutes of ticks, so every per-match total lands at roughly a tenth of a real
  match's. Distance makes this unarguable: 1.30 km a player, and no mechanic makes
  a man run 10 km in nine minutes. On this reading the §11 per-match density rows
  are unhittable at `clock_rate` 10 by construction, and it is **§11 that needs
  the decision**, at the tuning freeze.
- **The football inside those minutes is wrong.** The ball moves every 1.1 s, 65%
  of passes go backward or square, a sequence gains 2.9 m, and almost nothing
  reaches the box. On this reading the order above is the work and the totals
  follow.

The two are not exclusive and the order above is written for the second, because
every item in it is a behaviour an eye can check. **The first is the owner's
call** and nothing here should be tuned against it in the meantime.

## Watching with this list

Things the engine cannot do, and what each looks like on screen. Seeing one is
not a finding; it is the list working.

- **A man ahead of the ball stands still**, or runs and is never found (**33**).
- **Nobody holds the ball.** It is played on within about a second of arriving,
  every time, by everyone (**28**) — but check the open question at the end of the
  order before treating it as a fault.
- A cross arrives and nobody makes the run to the near or far post (**29**) — a
  corner comes down **seven to nine metres** from the nearest of ours, and a wide
  free kick produces no shot at all.
- The two centre-backs four metres in front of a shot from the edge of the box
  block one in twenty-five of them (**5**).
- A ball is headed in the box and goes anywhere but at goal (**29**).
- Play crabs across the middle third with no one between the lines to give it
  forward (**30**).
- A shot from twelve yards with a defender beside it goes in cleanly — nobody
  blocks.
- Attacks walk into the six-yard box.
- A keeper parries straight back out and it happens again immediately.
- The ball almost never goes behind for a corner (**5**).
- A free kick on the edge of the box is possible but rare; the cynical foul is
  absent.
- **The last ten minutes look like the first ten**, whatever the score (**34**).
  A side two down keeps its shape, its width and its patience to the whistle.
- The ball is circulated at one speed from the first minute to the last: there is
  no settled passage and therefore no moment it quickens (**37**).
- The better side is more accurate and plays the same football (**38**).
- A carrier runs straight into a defender and loses it — shielding and the cut
  both exist, so this is the softmax declining them, a tuning fact rather than an
  absence.

**Watch at the clock the game ships with.** The nine-minute match is the match, so
it is what these are judged on and what the numbers are tuned to — `docs/STATUS.md`,
"what every figure here is worth".

**Something wrong that is *not* on this list is the valuable kind.** Mark it with
`M`: it means the engine has the behaviour and is doing it badly, which is more
findable than not having it at all.
