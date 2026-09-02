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

**The defending rows are the current pass** (`PLAN.md` §11.4), opened
2026-09-02; the attacking pass is closed for now. Goals are expected to fall as
it lands, and that is the point. *Built* on an attacking row means judged
against the defence of the day it was built: the defensive pass ends with a
re-watch of the attack (the order, below), expecting rework.

## With the ball at his feet

| Behaviour | | Where |
|---|---|---|
| Pass to feet | built | `SimDecision._add_passes` |
| The ball to feet aimed off the marker, a step to the free side | built | `SimDecision.FREE_SIDE_STEP` |
| Through ball in behind | built | `_add_passes` |
| Shot, with a chosen placement | built | `_add_shot`, `_pick_shot_aim` |
| Clearance | built | `_add_clear` |
| Carry, eight probed directions | built — and the room it has ends at the goalkeeper, not at the paint | `_add_dribbles`, `keeper_room` |
| Knock past a man, and race him | built — same room, except when going round the keeper *is* the act | `_add_dribbles`, the burst |
| Hold — the settling touch | built | `_add_hold`, `_play_hold` |
| The dwell — a free man keeps it a beat, takes another look, then plays | built | `SimDecision.scan_gain` |
| Orient before the act — a beat between coming by the ball and striking it | built — a price either side of a gate, because the price alone loses to the shot appetite | `SimDecision.readiness`, `_apply_set_damp`, `SET_STRIKE_FLOOR` |
| First touch, and the turn | built | `SimTouch.first_touch` |
| Receive on the half-turn — hips opened while the ball travels | built — a look the body holds while he walks onto the ball or waits for it, and a sprint onto it keeps the hips on the run; a tight receiver closes on the ball instead | `SimMovement._orient_receiver`, `SimPlayer.look_target` |
| The layoff — first-time ball back to the man facing play | built | `SimTouch.redirect_share` |
| A setting touch out of the feet before the long ball or the shot | built | `SimDecision._add_set_touch` |
| Body facing priced into the strike, and the turn before you can hit it | built | `SimTouch.facing_penalty` for the aim, `strike_scale` for the range |
| A stronger foot, and a ball shown onto the weaker one | built — the other axis of the same body model, charged through the same two functions | `SimTouch.foot_cost`, `foot_choice` |
| Bend on a struck ball, the way the foot that struck it sends it | built — signed by the foot on every solved ball, and since the bent lane (2026-09-01) *meant*: the driven pass and the shot price a bend round a defender, trivela included | `SimTouch.curl_for` |
| Shielding the ball | built — chosen by the hold, made by the hips turned away from the man under the strafe cap, and worth the body actually between him and the ball | `_play_hold` chooses it, `SimMovement` makes it, `SimDuel.shielded` weighs it |
| Backheel, dummy, first-time pass | built | `SimTouch.FIRST_TIME_EASY`, `_add_dummy` |
| Chip the keeper, round him, square it across the face | built | `_add_chip`, `_round_the_keeper`, `SQUARE_CONVERT` |
| Firm pass driven low, not rolled | built — offered beside the roller, with the lane it buys back and the first touch it costs | `SimDecision.DRIVEN_LANE`, `SimBallistics.ground_launch` |
| Lofted pass, cross | built — aimed where he is going, and landed short so the hops carry the rest | `_add_passes`, `SimTouch.LOFT_RUNON_SHARE` |
| Give-and-go, and the executed one-two | built — a named pattern, so the passer is committed to the run and the return ball is lifted to him | `SimPatterns._try_one_two` |
| Beating a man | built — the knock, the cut, and the feint from a standstill: a body sold at the man without the ball, priced as a lottery in front of the knock across him. On the list in 7 of 100 scenario trials and chosen in none, honestly | `_try_beat`, `_add_feint`, `tools/_feint_probe.gd` |
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
| Hold width — the outlet on the touchline, ahead of the ball | built — a full-back or winger goes to the line and stays on it, wanted more the more crowded the ball is; before it the only offers a wide man could make brought him inside, and the wide fifths held 3% of passes | `SimOffBall._wide_point` |
| Overlap, underlap, third man, switch of play | built | `SimPatterns` |
| A plan's named patterns actually firing | built — `RUN_IN_BEHIND` was installed in `high_press_direct` with no trigger and could never fire; it now does, at 13-17% | `SimPatterns._try_run_in_behind` |
| A pattern's runner being aimed at | built — `destination_for` did not read `movement_override`, so a man a pattern had sent was passed to by dead reckoning | `SimOffBall.destination_for` |
| Break on the counter | built | `SimDecision.break_on` prices the ball, `SimOffBall` sends the runners |
| Attack a cross — near post, far post, the pull-back | built — the three posts are authored in `_box_point` and `_add_crosses`, and the pull-back is its own act along the floor. It fires in `cross-pullback` and **never in a match**: 0 offered over five seeds of ten minutes (2026-08-25), because nothing takes the ball to the byline — 0% of passes and 4% of touches start in the final sixth. The act is built; the approach is **51** | `SimDecision._add_pullback` |
| Arrive as the ball does, easing the last metres | built — box runners and runs in behind did; the show and the drift now hold the last stride until the ball is struck to them | `SimOffBall.MEET_EASE` |
| Link the defence to the strikers, holding height and width | built 2026-09-02 — the playmaker's station, and half of each central midfielder's, sits between the opponents' midfield and their line while in possession, width untouched; forty seeds: the middle third 74.5% to 70.5% of touches, the final third 13.5% to 17% (**30** for what is left) | `SimMovement._link_station` |
| Be served when the run is made | partial — the run in behind is served now (2026-09-02, twenty fragments: offered 63%, received 13%, 72 through balls played, 58% reaching the man); the `box` run is made about fifty times a match and received 5%, bounded by `space` at arrival in a box that is now defended, and an early cross to it doubled the crosses without serving him (**33**) | `SimOffBall`, `SimDecision._add_passes` |

## Defending

| Behaviour | | Where |
|---|---|---|
| Who leaves shape for the ball, and how many | built | `SimMovement._assign_chasers` |
| Press harder or sit deeper, from the plan | built | `SimTactics` |
| Mark a man | built | `SimPlayer.marking_target` |
| Recovery run | built | `SimMovement` |
| Intercept, tackle, poke it away | built | `SimDuel`, `SimTouch.poke` |
| React to the strike before running, as before reaching — a ball played out of his sight is not chased until it is news | built | `SimDuel.ball_news_age`, `SimMovement._recompute_target` |
| Hold a defensive line, with offside off it | built | `SimReferee.offside_line` |
| Clear under pressure | built | `_add_clear` |
| Block a shot | built — a body in front of the strike throws itself on the backlift, one roll at the strike, taken when the ball arrives; the price and the act are one function | `SimDuel.commit_blocks`, `block_chance` |
| Cover a beaten teammate | built — one man a side, latched for the carry, fills the space goal-side of the carrier who has just gone past one of ours; about a dozen a match | `SimMovement._pick_cover`, `Errand.COVER` |
| Jockey, delay, show him wide | built — the chaser who has arrived goal-side stands off a stride and a half, holds his hips on the carrier, shuffles under the strafe cap, and stands a little inside the line to goal so the easy way is the touchline; the challenge is still the duel's commit roll | `SimMovement._jockey_point`, `Errand.JOCKEY` |
| Escort a dying ball over the line | built — a ball the forecast has going out off their touch is walked out: body between it and the man, no touch of his own; rare, a few seconds a match | `SimMovement._escort_wanted`, `Errand.ESCORT` |
| Spring an offside trap | built — the back line steps up four metres together on a ball played back or a carrier pressed with his back to it, with a runner near the line; it deters the through ball and catches nobody, because the passer's belief of the line is a quarter-second stale at most | `SimMovement._consider_trap`, `trap_lift` |
| The deliberate foul | built — a man behind or level with a carrier running at his goal, outside the area, with the numbers short or the cover far, goes in when he otherwise would not and through the man when he does; rare, because the break it answers is rare here | `SimDuel._cynical`, `PRO_FOUL_COMMIT` |
| Defend the penalty area | partial — inside the area the presser closes from goal-side and the second man drops onto the line of the shot, which is what the block is thrown from; the keeper narrowing the angle and the cover for a beaten man are the rest of **5** | `SimMovement.LANE_STANDOFF`, `PRESS_FAN_NEAR` |

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
| Win a knock-down, attack a corner | partial — the knock-down exists; a corner is whatever the box happens to do (**29**), and corners run at 0.4-0.5 per team a match against a target of 3-8 (**50**, **5**) | |
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
| Where a parry goes | built — a full hand pushes it round the post or over the bar, a fingertip drops it in front of him; he is on the floor after it, with half his reach until he is up | `SimKeeper._take_the_save`, `PARRY_HAND_GOOD` |
| The one-on-one | partial — priced into `expected_goals`, so the engine's answer is not to shoot | |
| Narrow the angle | built — with the ball at an opponent's feet inside 24 m and in front of goal, he stands where his reach closes the goal as the shooter sees it, capped so he is not chipped from range; the save model and the chip already price the trade | `SimKeeper._narrowed_station` |

## Set pieces, and the laws

| Behaviour | | Where |
|---|---|---|
| Kick-off, throw-in, goal kick, corner, free kick, penalty | built | `SimSetPiece` |
| Offside, given at the moment of the pass | built | `SimReferee` |
| Fouls and cards, and a red that removes a man | built | `SimReferee` |
| Added time from stoppages | built | `SimReferee.add_stoppage` |
| Opponents out of the area at a goal kick | built | `SimSetPiece._out_of_penalty_area` |
| A restart the side reorganises around | partial — positions and a delay, and one corner routine (2026-09-02): a named post, two runners sent to the posts a second before the kick, the ball aimed at the man; the delivery lands 5-13 m off the post at that range (**29**), so the rows did not improve | `SimSetPiece._corner_choose` |
| A wall at a free kick | built 2026-09-02 — two to five of the nearest defenders on the 9.15 m across the line to the near post, facing the ball; a standing body that jumps in the block model; the taker goes round it, and the 21 m shot converts as it does everywhere here | `SimSetPiece._wall_spots`, `SimDuel.WALL_STOPS` |
| Wait for the referee's signal, and the run-up | built 2026-09-02 — a corner or free kick is taken when everyone is at his spot and two seconds after, capped at ten; the taker waits 3.5 m behind the ball facing it and runs up on the signal | `SimSetPiece.SIGNAL_DELAY`, `RUN_UP` |
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
| The scan you can see — head turned to where he is looking | partial — the body is its own state and the figure is drawn where it is held, side-stepping and backpedalling as it goes; the head turns with the hips, never on its own | `SimPlayer.look_target`, `SimMatchView3D.pose_gait` |
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
| **51** | Nothing takes the ball to the byline: the winger's carry past the full-back, the ball down the line | `SimDecision._add_dribbles`, `SimOffBall._wide_point` |
| **43** | A goal kick is nine passes in his own half and then a turnover | `SimSetPiece._take_goal_kick`, `SimMovement` |
| **44** | A striker and a centre-back are the same speed | `SimRole._WEIGHTS`, `SimAttributes` |
| **50** | Corners at 0.4-0.5 a team against a floor of 0.5: nobody puts the ball behind | `SimDuel`, `SimKeeper` |
| **52** | A committed move can still steer: a slide changes direction mid-slide, a keeper turns in the air | `SimPlayer.locomote`, `SimDuel.commit_blocks`, `SimKeeper` |

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

The release fired on 2, 4 and 31 ticks of a match against 392, 702 and 508 held,
because `_cross_coming` asked where the carrier is standing this tick while the
run was committed seconds earlier. The man therefore held his six metres nearly
always, including as the ball was struck.

**Two faults in the trigger, both fixed, and neither was the reason it never
fires in a match.** It read `ctx.possession_player`, which is -1 the moment an
opponent is within 2.2 m of the ball — a full-back closing the man about to
cross is the situation, not the absence of one — so it now reads the ball's own
last toucher while the ball is still within reach of him. And the answer was
recomputed from nothing every tick, so it is latched for `CROSS_COMING_HOLD`,
which is what carries it through the strike. Measured over ten match-minutes,
the ticks where a man of ours is wide on the ball: seed 1 **41 to 97**, seed 3
**26 to 31**. In `cross-right`, where the winger starts on the ball and
uncontested, the release fires **722 to 1312** ticks of 1774 and the row does
not move, which is right — the old test already worked in that geometry.

**What is left is that the run and the cross are never live at the same moment.**
Over three seeds, of 609, 195 and 346 ticks with a box run live and the ball on
the grass, **not one** had a man of ours wide on the ball, by either test. Probed
the other way round — at the 97 ticks of seed 1 where somebody was wide on the
ball — the run is refused nowhere: it is *on the list*, once, every one of those
ticks, and no man's intent is `box`. The off-ball layer only re-assigns intent
when a man on the ball is deciding (739 men considered in a match, the box run
listed for 1.1% of them and won 6 times), and the wide moment is a second long
and usually falls between two of those. So the timing has an honest trigger and
no population, and what is missing is still the run: **29** and **33**.

What is left of 29 is a set-piece question as much as an open-play one: a large
share of football's headed attempts come from corners, and corners are 0.4-0.5 a
team a match (**50**) until **5** lands.

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

**The cross family is now seven rows, 2026-08-23** (owner: *crossings from
different positions, especially closer to the extended goal line; in some
scenarios more attacking players close to the box*). Three depths on the right
flank at one width -- `cross-early` 24 m, `cross-right` 30, `cross-deep` 49 --
the byline pair, and `cross-loaded`, which is `cross-right` with three of ours
already running at the box and nothing else changed. First numbers, n=40:

```
					 goal  saved    off  block   lost   none | shot s shot m box s  cross drop m | touch
  cross-early          0%     2%     2%     2%    82%    10% |   4.64   18.0  0.93   0.90    5.1 |   6.2
  cross-right          5%     2%     5%     0%    82%     5% |   2.78   13.7  1.26   0.95    4.4 |   5.9
  cross-left          12%     5%     5%     0%    72%     5% |   3.22   14.7  1.32   0.82    6.4 |   6.3
  cross-loaded         2%    10%     2%     5%    75%     5% |   2.68   10.3  1.57   1.00    4.2 |   2.9
  cross-byline         8%     5%    20%    10%    52%     5% |   2.01   12.5  2.35   0.07    0.4 |   3.1
  cross-deep           0%    18%    10%     2%    70%     0% |   2.83   13.2  1.93   0.97    5.1 |   3.9
  cross-pullback       2%     5%     0%     0%    92%     0% |   2.09    5.2  1.60   0.25   11.3 |   2.6
```

**The pair is the finding, and it is 29's own question answered.** Three men
running at the box moves the shot from **13.7 m to 10.3**, the seconds spent in
the area from 1.26 to 1.57 and the attempts on goal from 7% of trials to 12% --
and moves the ball's arrival, which is the number this proposal is named for,
**4.4 m to 4.2**. The delivery comes down four metres from the nearest of ours
whether or not anybody is attacking it. So the run being absent is not what the
drop distance was measuring, and the aim of the ball is now the open half of 29.

**Depth pays and the finish does not.** `cross-deep`, three and a half metres
from the goal line, is the most dangerous ball in the family -- 28% of trials
end in an attempt at goal against `cross-right`'s 7% -- and it produced **no
goals in 40**. `cross-early`, hit from the edge of the final third, is the least:
one attempt in 40, from 18 m, 82% lost.

**And the cut-back is barely played.** `cross-pullback` puts the ball on the goal
line with two men arriving at the edge of the area, where `SimDecision._add_pullback`
can fire and does, 0.25 a trial; the rest is 1.4 dribbles and 0.6 through balls a
trial. When it is played the shot comes from **5.2 m**, which is what the act is
for. 92% of trials end `lost`.

**The ball played into the keeper's hands, 2026-08-29** (owner, from a bookmark:
*sometimes it looks like he is passing straight to the opponents*). `cross-pullback`
seed 12, tick 28: the winger on the byline plays a through ball to a point
**1.0 m from the keeper**, succ 0.38, 99% of the pick. Two faults.

**Pitch control had no reach.** `_lane_survival` has always given a defender
`CONTROL_RANGE` for free -- he sticks a leg out -- and `SimValueField._control`
never did: the keeper a metre off the point, drifting away at 2.8 m/s, was priced
at 1.22 s to turn and *stand on it*, level with a receiver ten metres away at
full pace, and then charged `AIMED_STEP_IN` on top. `space` said 0.79 for a ball
into his hands. `time_to_reach` now runs the race to the edge of a man's reach:
`CONTROL_RANGE` outfield, `SimKeeper.REACH_STANDING` for a keeper. That ball is
0.15. `./run.sh control` block A at 1 m went 0.84 to 0.11 with the engine keeping
100% -- `AIMED_STEP_IN` was fitted to a model without reach and the comment's own
rows are stale either way; a refit is a tuning question and waits.

**And nothing on the list could see two touches ahead.** At 0.15 the ball into
the keeper still won 92%: gain 0.35 against a hold at 0.065. The touch sideways
that would have opened the cut-back read as "0.6 m left, gain 0.03", because a
carry is worth the grass it lands on. `_add_opening` offers the sideways touch
again, worth the through ball or cut-back it opens: the scored probe's own odds,
times the pass re-priced from where the touch leaves the ball with the challenger
where he will be by then -- still closing on where the ball *was*, for the length
of the touch. Only when the re-priced ball clears the one-step ball by
`OPENING_MIN`. At that tick it puts `carry, then through -> #10` on the list at
0.033 against the blocked ball's 0.056 -- a candidate now, and the rest is the
pass model's generosity to that 0.15. Counted under `open it` in the rare acts.
Measured on `cross-pullback`, 40 trials: offered in 27, played once, never top
of the list -- compound success about 0.12 (sideways touch under pressure ~0.45
x re-priced pass ~0.3) against a cut-back worth 0.09. The parts say no, and the
parts are the carry model's price on a sideways touch, the cut-back's worth, and
the lane.

**The lane priced by facing, 2026-08-29** (owner: *price the lane by facing*;
then *reach should not be instant -- a player reacts and reaches out with his leg
if it is not struck right at his feet*). The lane read bodies and not which way
they pointed, and the contact rule was worse: any ball inside `CONTROL_RANGE`
was played the tick it got there, whichever way the man faced, whether or not
he saw it struck. Priced in the lane alone the models disagreed at once --
`./run.sh control` block B said 0.44 at 1 m against 82% cut out -- so the
mechanic went into the contact rule first and the lane reads the same facts:

- `SimDuel.REACH_ARC`: a leg reaches a ball in front of the hips or beside, not
  behind. `in_reach_arc` gates the contender; `_cut_chance` meets the ball where
  it first enters the arc rather than at the foot of the perpendicular.
- `SimDuel._ready_for`: a ball not at his feet (`AT_FEET`) takes a reaction from
  when it became news -- the strike, if he had the striker in his eyes
  (`SimPerception.saw_recently`, arc plus memory; his own side always did),
  otherwise the tick it came into view. `_facing_cost` charges the lane the
  same second reaction for a striker he had not seen.

Block B after: 0.5 m 80% cut out against 0.07 said, 1 m 48% against 0.17, 1.5 m
20% against 0.51 -- the same shape, the model a little keen. Blocks A and D did
not move. **And the cut-back did not move**: lane 0.200 before and after over
the probe's 25 seeds, `cross-pullback` goals 5% to 8% at n=40. The man 0.8 m
off the line is the one chasing the winger, facing him, and he sees the strike;
the back line facing its own goal is not in that lane. So facing was true and
was not the cut-back's answer; what the scenario still wants is a defender who
is *not* looking, which is a marking question for the defensive pass.

**Where the cross is aimed and how it bends, 2026-08-23** (owner, watching
`cross-right` and `cross-loaded`: *a lot of the crosses are aimed too much
towards the goal so it reads like a weak shot; add some spin and some curve so
the ball travels more parallel to the goal line*). Three faults, and the third
was why nobody had found the second.

**The ball was aimed into the goal frame.** `SimOffBall.box_targets` put the near
and far points on the posts -- 3.7 m either side of the middle, five and eight
metres off the line -- so a cross nobody met came down in the goal mouth in front
of the keeper, who is standing there by trade. That is a weak shot with a
different name on it. The points are outside the frame now, at fractions of the
six-yard box so they scale with the pitch: across the near corner of it, and
hanging past the far post. The run uses the same three points, so both halves
moved together.

**The ball was barely spinning.** `CROSS_CURL` was 3.4 rad/s, half a turn a
second, where a footballer whips one at five to ten. Measured on the flight, the
bow -- the furthest the ball departs from the straight line between the strike
and where it lands -- was **0.28 m over twenty-five metres**, which is a straight
ball with a number on it.

**And it could not be raised, which is the finding.** `SimBallistics.solve_lofted`
takes the spin and iterates on two things: how far the ball got and how long it
took, both measured *along the line to the target*. Nothing looked sideways. So
sidespin pushed the ball off its aim and nothing pulled it back: 1.5 m off at
3.4 rad/s, and **six metres off** at a real one. Every bend the engine could put
on a ball was a bend away from where it was aimed, which is why there was almost
none. The launch now carries a yaw, iterated like the other two corrections
(`docs/INVARIANTS.md`).

With that in hand, `CROSS_CURL` is 40 rad/s and the same cross **bows 1.3 to
1.8 m and still lands where it was aimed** -- 0.65 m of residual error against
4.7 before. Measured on the rows, n=40:

```
					 goal  saved    off  block   lost   none | shot s shot m box s  cross drop m | touch
  cross-right          2%     8%     5%     0%    75%    10% |   3.03   14.6  1.41   0.78    4.6 |   6.0
  cross-loaded         8%    12%    15%     2%    58%     5% |   2.08   13.6  1.69   1.00    3.0 |   2.8
  cross-deep           8%     8%    10%     2%    72%     0% |   2.55   13.0  1.79   0.97    4.5 |   3.8
  cross-byline        12%    10%    25%     5%    45%     2% |   2.26   13.1  2.56   0.00      - |   3.4
```

**`cross-loaded` is where it shows**, because it is the row with men in the box:
the ball comes down **4.2 m to 3.0 m** from the nearest of ours, attempts at goal
12% of trials to **20%**, goals 2% to **8%**, and `lost` 75% to 58%. `cross-deep`
goes from no goals in 40 to 8%. `cross-byline` now plays no cross at all -- from
the goal line the aim points are behind him and the cut-back is the act, which is
what that row is for.

**Four seeds of ten match-minutes each say the match is unmoved**, 1 shot across
the four before and 1 after: at this length a match produces about half a shot a
side, so nothing here can be read from one. The scenario rows are the measurement
and the screen is the judge.

**How fast the ball is struck, 2026-08-23** (owner: *it still looks easy for the
goalkeeper to pick the ball from the air -- we almost need to increase the speed
of the ball. And it is a more general problem: slow short passes that are easy to
intercept, and the receiver has to turn and run back to the ball and lose
momentum*). Two numbers, one for each half of it, and both were slow.

**The short pass.** `SimDecision.arrival_pace` is the only place a ground pass's
speed is decided, and its floor was 2.0 m/s: a ten-metre ball arrived at 4.3 m/s
after **1.57 s** on the grass, a five-metre one at 3.2 m/s after a second. A
second and a half is time for anybody to step in front of it, and a ball that
slow behind a man is a ball he walks back for. The slope is what the previous
change to this curve was about -- a long ball outrunning the men -- so the slope
stayed and the floor went to 4.2. Ten metres now arrives at 6.7 m/s after
**1.18 s**, five metres at 5.6 after 0.73.

**The cross.** It was asking for `lofted_flight`, which is the clipped ball's
flight, and a twenty-five metre cross therefore hung for **1.73 s** and came down
through heading height at 11.8 m/s. That is a floated ball and the goalkeeper has
a second and a half to leave his line and take it. `SimTouch.cross_flight` is the
whipped one: 1.25 s over the same distance, off the boot at 24.9 m/s and through
heading height at **17.2 m/s**.

**Measured on the thing the owner named**, 40 trials, who got to the cross first:

```
				 keeper first     ours first   theirs first   in the air
  cross-right      9% ->  0%     14% -> 22%    77% -> 78%    1.83 -> 2.17 s
  cross-loaded    16% ->  3%     45% -> 49%    39% -> 49%    1.91 -> 1.58 s
  cross-deep       0% ->  0%     26% -> 27%    74% -> 73%    1.96 -> 1.58 s
```

**What it cost, and it is the honest cost of a whipped ball.** A flatter, faster
cross overhit by the same fraction of its weight sails much further before it
drops back through heading height. `./run.sh strike` says the same strike now
rolls 8.1, 9.5 and 12.2 m long at 20, 30 and 40 m where it rolled 5.7, 6.3 and
7.6 -- so `CROSS_RANGE_SPREAD` went 2.3 to 3.2, because the model and the ball
have to share one number or the decision layer is pricing a ball nobody hits.
Told the truth, the softmax plays fewer of them: `cross-right` 0.75 crosses a
trial to 0.53. The ball also lands further from the nearest of ours -- `drop m`
3.2 to 5.1 on `cross-loaded` -- and **`cross-deep` moved the wrong way**, 5% goals
and 78% lost to 0% and 92%, which at n=40 is one to two standard errors and wants
watching before anything is done about it.

**What it bought, on the rows the pass change is aimed at**, n=40 each. The
`before` arm is the last commit rather than the tick before this change, so the
two cross rows in it carry the curl and the whipped flight as well; the four pass
rows are the pace alone, which is nothing else in those two files touches a ball
on the floor:

```
					before                          after
  build-up      lost 82%, kept 18%             lost 65%, kept 35%
  pocket        lost 85%, no goals             lost 48%, 10% goals, 10% saved
  through-ball  lost 60%, no shot              lost 42%, a shot at 12 m
  switch        lost 65%, 2% goals             lost 58%, 5% goals
  cross-right   7% at goal, lost 82%           17% at goal, lost 68%
  cross-loaded  26% at goal, 8% goals          22% at goal, 12% goals
```

`build-up` and `pocket` are the two rows this was diagnosed from and they are the
two that moved most: the ball is now hard enough to hit that a defence stepping
into the lane does not simply arrive first. **Three seeds of ten match-minutes
say the match's pass completion is unmoved** -- 100 of 133 before, 91 of 117
after -- which is what a change to how hard the ball is struck should do to a
number that is about where it is struck.

**The cross has two flights and the ball picks its own, 2026-08-23** (owner:
*add back some higher crossing, it's nice with the variation. The main issue is
that the crosses are hit without a good goal -- they should be aimed at where
team mates are going to end up, or areas where they dominate by just being more
players*).

**One flight was the fault, not the speed.** `cross_flight` whipped every ball,
so a cross was struck to arrive before the man it was for could get there and the
choice of point was made at a flight nobody's legs had been consulted about.
`SimTouch.cross_hang` is the other end of it -- 1.95 s over twenty-five metres
against the whipped 1.25 -- and it is a higher ball by construction, because the
solver has to keep it up over the same ground.

**Both balls are scored at every point and the better one is played.** The man
who is coming decides which is even available: a ball he cannot reach is not
offered, and the hung one is offered only when it buys him the time. Fitting the
flight to him and stopping there was the first version, and it hangs the ball
into an empty six-yard box -- the only man who can get there is two seconds away
and nothing had asked what the goalkeeper does in the meantime. He is a body in
`control_at_time` like every other, so asked, it answers.

**Nothing counts heads, and that is the point.** `control_at_time`'s crowd term
already prices numbers in the area -- a hung ball puts everyone who can reach the
spot on level terms, so what decides it is how many of each side are standing
there. It could never say so while the flight was fixed. The owner's two asks are
one mechanic: the ball is aimed where our man will be, and where we have the
bodies wins the hung ball while the man already there wins the whipped one.

**The mix is a fact about the situation rather than a setting.** In a box being
attacked (`cross-loaded`) it is **50% hung, mean flight 1.68 s**; in the rows
whose box starts empty, 95-100% hung at about 2.0 s, because there is nobody to
whip it to. That second number is `docs/THE_FOOTBALL.md` 29 again and not a fact
about the flight.

**Measured, n=40** -- against the whipped-only ball of an hour earlier:

```
				 whipped only                 both flights
  cross-right    lost 68%, drop 7.1 m         lost 75%, drop 3.9 m
  cross-loaded   lost 52%, drop 5.1 m         lost 52%, drop 4.0 m
  cross-deep     lost 92%, drop 9.0 m         lost 62%, drop 4.1 m
  cross-pullback 0.25 crosses a trial         0.57, shot from 9.7 m
```

**`cross-deep` is the row that was broken and is now the best of them**: 33% of
trials end in an attempt at goal, `lost` 92% to 62%, and the ball comes down 4.1 m
from the nearest of ours rather than nine.

**And the cost is the goalkeeper, which is the trade the variation asks for.**
First to the ball after a cross, over 40 trials: in the loaded box the keeper
takes **3% to 13%**, and it comes out of the *defenders*' share, 49% to 39%,
while ours holds at about half. On `cross-deep` he goes 0% to 3% and ours goes
27% to **46%**. On `cross-right`, whose box is empty, he takes 15% -- a hung ball
into a six-yard box with nobody in it is the keeper's, and the engine is right
about that. **What is not modelled is that he claims with his hands above
everybody's heads**: he is weighed as an outfielder who happens to be standing
there, which understates him on exactly the ball that is now being played. That
belongs to the defensive pass.

**Can they finish a cross at all? 88% of the time, 2026-08-23** (owner: *the
crossing looks much better, but the defenders seem to get to the ball most of the
time -- which is realistic, though it is still before the defensive pass. I would
like to see a cross scenario without opponents, to see that they can score on one
header or touch from a crossing*).

`cross-open` is that row and it is the only one on the page with nobody defending
-- no back line, no goalkeeper, three of ours attacking the box, the ball already
in the air. n=40: **88% goals**, 5% saved, 8% off, and nothing else. The ball
comes down **1.4 m** from the nearest of ours at 1.68 s, they play **1.5 headers
a trial**, and the finish is struck from a mean of 11.2 m. **The heading and the
first touch can convert a cross**, and what the other rows are measuring is the
defending.

**Two things about the row were measured before they were chosen.** Given the
ball at his feet in an unopposed box the engine walks it in rather than crossing
-- 0.05 crosses a trial, 2.4 dribbles, a goal in 55% -- which is a correct
decision and answers nothing, so the ball starts struck. And a struck ball left
on the crosser's boot never leaves the flank: `SimDuel.resolve_contacts` hands a
ball inside his reach straight back to him, and every trial had it taken down
again three metres from where it was hit. It starts a quarter of a second into
its flight, which is where a follow-through leaves a man.

**It also found an instrument bug, and this one was in every row.** The trial's
verdict read the *first* shot of the situation and asked whether that shot was a
goal. On `cross-open` the trace is a header saved off the line at 1.68 s and a
second header put in at 1.75 -- scored `saved`, in a scenario with no goalkeeper
in it. A goal is a goal whichever shot scored it, and `SimScenario` now says so.
The affected rows are the ones where a rebound goes in: `cross-open` 38% goals to
88%, and one to two points elsewhere.

**The header at goal was leaving the forehead too slowly, 2026-08-23** (owner:
*the speed of the header is too slow, it is going to be too easy to save the ball
after a header*). Measured on `cross-open`, 61 attempts at goal left the head at a
mean **12.8 m/s** -- from eleven metres that is nearly nine tenths of a second for
a goalkeeper, which is a save every time. A struck shot in this engine leaves at
16 to 27 m/s (`SimConsts.SHOT_SPEED_MIN`), and a header is slower than a shot
rather than half of one.

`SimTouch.header`'s band went **5-13 to 8-18 m/s**, and the pace bonus with it --
`HEADER_PACE_BONUS_MAX` 4.5 to 6.0 off a coefficient of 0.35, because a cross now
arrives through heading height at 17 m/s where the old cap was fitted to a ball
arriving at 11.8. Measured after: **17.6 m/s**.

**Only the header at goal changed.** The clearing header, the nod to a teammate
and the knock-down are the same act with less of a man's neck in them, which is
what `power_scale` has always been for: `SimAerial.NOT_AT_GOAL_POWER` is 0.72, the
old band over the new one, and `KNOCK_POWER` came 0.45 to 0.32 to hold the
knock-down where **42** measured it. Left alone, the clearing header carried a
mean of 29 m against `tests/test_distances`' football band of 4 to 26 -- which is
the test doing its job, and it now exercises the act's own power rather than the
primitive flat out. It gained the other half of the question too: **a header at
goal must leave the head above 13 m/s**, a floor that is structural rather than
tuned -- below it a keeper on his line saves everything.

`cross-open` 88% goals to **92%**, off target 8% to 2%. `cross-deep` 5% to 8%.
`cross-loaded` unmoved.

**Where a cross actually comes down, 2026-08-23** (owner: *let's improve
`cross-loaded`, it should score more often -- the crosses are almost always hit
too far or far forward, close to the goal, so the attacking players do not really
have a chance*). The row is 15% goals at n=100 and it did not move; what moved is
the ball, and what the measuring found is worth more than the change.

**The owner's read was right and the cause was the elevation error.** Traced,
trial after trial the ball either dropped nine metres short of its aim or sailed
nine metres past it onto the goal line -- `./run.sh strike` had the number all
along: a cross's range scatter rolled **8.1 m at 20 m**. Halving the weight error
moved it to 6.9 and no further, because it is not the weight: a five-degree error
in the angle a flat ball leaves at is worth more range than a tenth of its speed.
`_perturb` has carried an elevation scale since it was written -- *flat balls are
far less sensitive to it than lofted ones* -- and the cross is the flattest ball
the engine strikes. `SimTouch.CROSS_ELEVATION_SCALE` is 0.5, on the argument that
a winger's fifty crosses a day are the one strike whose whole difficulty is this.

Measured: the rolled range scatter **8.1 to 6.75 m** at 20 m, 9.5 to 7.3 at 30,
12.2 to 8.6 at 40, and the bias with it (-1.2 to -1.0, -1.3 to -0.6, -2.4 to
-0.7). `CROSS_RANGE_SPREAD` 3.2 to 2.6 and `CROSS_HANG_SPREAD` 2.3 to 1.9 so the
model still says what the ball does. On the row: the ball comes down **4.0 m to
3.5 m** from the nearest of ours.

**And the ball is now dropped on the man rather than on the point he is running
at** (`_meet_point`). Measured before it: the ball came down 7.3 m from the man it
was for and, 90% of the time, *in front of him* -- two metres nearer the goal,
which is two metres on the side the defenders are already standing.

**None of it made the row score more, and the reason is two measured facts.**
**Twenty-eight of thirty-eight crosses are met in the air** before they land, and
the defence takes 39-49% of those: eleven of them are in that box against three of
ours, which is the row's whole point and the owner's own reading of it. And **the
ball goes to the penalty spot every single time** -- the mean aim was 11.0 m from
the goal line on every cross in 40 trials -- so the header that follows is struck
from 12.6 m, which is a distance no header scores from. Ranking the three points
by the header they would give instead of by the value map was built and reverted
with its numbers (`SimDecision._add_crosses`): the ball goes nearer the goal and
into worse company, `lost` 49% to 60%. **What the near post is worth is a
value-map question, 8b**, and not one to settle from a cross.

**8b's other half is built, 2026-08-23: the map is no longer single-step.**

The old expected-threat map was one hand-made function of distance and angle to
goal, baked into the grid. That function says what a *shot* from a patch of grass
is worth, and the engine was using it as the value of the grass. Football does not
work that way: a wide position in the final third is worth something because of
the ball that comes next, and to a single-step map it is simply a poor shooting
position. That is why the flanks and the middle third read flat, and it is what
**8b** has named since the ball in behind took the other half of it.

The value of a cell is now the value of what happens from it, which is the
textbook definition of the thing:

```
v(c) = shot(c) * goal(c)  +  (1 - shot(c)) * SUM over c' of  move(c -> c') v(c')
```

iterated until it stops moving. `shot(c)` is how often a possession there becomes
an attempt, `goal(c)` what the attempt is worth, and the move kernel is where the
ball goes when it is not a shot -- forward-weighted, short more often than long,
and losing the ball more often the further it travels. **Nothing in it knows about
players**: the grid stays a pure lookup on a 5 Hz cadence, which is rule 1 of
`SimValueField`, and the context correction stays where it was (`line_broken`).
It is baked once per match, about a tenth of the work one tick of pitch control
does.

**What the map says now**, against the old one at the same points, both
normalised to `XT_PEAK`:

```
					  old      new
  six-yard middle    0.378    0.299
  near post          0.212    0.166
  penalty spot       0.191    0.126
  far post           0.142    0.099
  edge of box        0.091    0.067
  wide, final third  0.0088   0.0222
  halfway, middle    0.0018   0.0083
```

The box is worth a quarter less and **the grass that leads to it is worth two and
a half to nearly five times more**, which is the whole change in two rows. It also
separates the three points a cross is aimed at: the near post was 11% better than
the penalty spot and is now 32% better.

**Measured in matches, and it is the sparseness that moved.** Eight seeds of ten
match-minutes, the same eight before and after: **1 shot against 11**. Passing
volume and completion are unchanged -- 354 attempts at 81% against 375 at 80% --
and the mean pass is 11.4 m against 12.1. The engine is not passing more, it is
passing to somewhere.

**On the set situations, at n=100**, it is mixed and worth writing down:
`cross-deep` goals 6% to **13%**; `cross-loaded` on goal 30% to 34%; `cross-right`
plays almost no crosses at all, 0.60 a trial to **0.16**, because with an empty
box in front of him and wide grass now worth something the winger keeps it --
defensible in that row and worth watching in a match. Against them, `build-up`
keeps the ball 35% of trials against 26%, and `pocket` scores 4% against 10%:
the map values progression more, so playing out from the back takes more risk.
**Neither is a reason to gate the mechanic** (`CLAUDE.md`), and both are rows to
re-read once the defensive pass exists.

**A commitment was a blindfold, 2026-08-23, and it is built.** The scenario work
found this twice in one day and named it wrongly both times -- as the cadence of
the off-ball layer, which is fine, and as the release trigger having no
population, which is a symptom.

**What it actually was.** `SimOffBall._assign` skipped any man who already had a
live intent, so an offer could not be reconsidered until its own window ran out --
and a drift into space holds for **4.5 seconds**. Measured over ten match-minutes:
at the 104 ticks where a man of ours was wide on the ball with a cross on, the run
into the box was offered to **nobody at all**, and `_box_point` was reached five
times in that whole window because eight of ten men were mid-drift. The run into
the box is offered four to six times a *match* for the same reason, and wins
almost every time it is offered -- the value layer has never disagreed that
attacking the box is the right idea, it was simply never asked at the moment the
question came up.

**A drift can be abandoned and a run cannot.** `SPACE` is a few metres off a
station he is still holding; the two things worth giving it up for are the two
runs that are about a moment rather than a position, so `BOX` and `BEHIND` are the
only kinds allowed to take it over. Anything else -- including another drift --
would let a man restart his own window every fifth of a second and every tally
counted from `_since` would read one run as twenty. The abandoned offer is retired
through the same bookkeeping a lapsed one is (`_retire`, split out of `_expire`
for exactly this) minus the rest it has not earned: he is not stopping, he is
going somewhere better.

**Measured, ten match-minutes, two seeds.** Runs into the box offered per match
**4 to 6** and **6 to 7**, of which **5 and 4 were a man changing his mind** --
about half of every box run in a match is now one. `diagnose` carries the count
(`offers given up for a run instead`) because the mechanic has exactly one
population and a zero would mean it is dead. The cost is that a drifting man is
scored again on every pass: men considered went 739 to 1394 in ten match-minutes,
and the run is 4.8 s against 4.4.

**The set-piece rows barely moved**, which is right -- `cross-loaded` and the rest
place their runners by hand, so the mechanic has nothing to do there. At n=100:
`cross-loaded` on goal 34% to 24%, `cross-right` 24% to 25%, `cross-deep` 24% to
21%, all within a standard error or two of each other and of the noise.

**The switch, 2026-08-23: the row was measuring its own placement, and then the
ball was measuring the wrong model.**

**The placement first.** `switch` held the ball on the left touchline and put the
free man on the right one, **54 m** away, against `MAX_LOFTED_PASS` of 45. So the
ball the row is named for was never a candidate: the first decision of every trial
was twelve carries and a hold, with no pass to anybody on the list at all. The
fourth scenario to do this, and the fourth time the answer was that a value knob
cannot create an option that was never generated. Both men are 20 m off the middle
now -- 14 m from their own touchlines, where a winger holding width stands -- and
the ball is 42 m from him.

**Then the ceiling went up, 45 to 55** (owner). Football's own long ball is longer
than the old limit: a touchline-to-touchline switch is fifty-odd metres and a
goalkeeper's kick is more. `SimTouch.strike_range` still caps every ball by the
man striking it, so this is a ceiling on the act and not a promise about anybody's
leg. Measured in a match, it did not open a floodgate: 3 to 7 lofted balls per ten
match-minutes at a mean of 24 m, and passing volume and completion unchanged.

**And the bench found two mismatches at once, both of which were making the long
ball look worse than it is.** `./run.sh strike`, six rows:

- **The range error in the air does not grow with the length of the ball.** The
  lofted pass rolls **6.1, 8.5 and 9.0 m** long at 20, 30 and 40 m, where a
  straight line through the first puts 12 at forty -- drag limits how far an
  overhit long ball actually goes. `AIR_RANGE_KNEE` is that saturation, one knee
  for both air axes with a scale each, and it was charging a 42 m switch a quarter
  more scatter than the ball has.
- **And the sideways claim was stale.** `AIR_MODEL_AIM_BASE` was 0.085 on the
  reasoning that a ball in the air lands further out than the yaw at the boot
  implies, measured at 4.19 said against 4.52 rolled. `solve_lofted` now corrects
  the launch heading for the spin on the ball (this morning's cross work), so that
  spread is gone: the same row reads 5.05 said against **3.83** rolled. 0.066 is
  the quarter it was overstating.

Together they take the switch's `succ` from **0.12 to 0.19-0.26** as the man
settles over it. **And it still takes 0-2% of the softmax**, because `bias 0.10`
-- `LOFTED_BIAS` times the length penalty -- is a tenth of its value before
anything else is asked. The row reads 88% `lost` and 3.0 dribbles a trial: he
carries into contact instead. **That is 27**, whose own named mechanic was built,
measured and reverted, and it now has a second row asking for it.

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

**33, re-measured 2026-08-25, and the last sentence above is now wrong: it is on
the list, and it is priced at nothing.** `replay --scenario through-ball --tick 1`
has `through -> #9 35 m fwd` on the candidate list with the largest `gain` of any
option there, `0.352`, and `succ 0.01`. Two things underneath it were faults and
are fixed; a third is not a fault and is where the item now stands.

- **The scenario stood the runner on a defender.** It put its two forwards on
  fixed lanes and the back line's z spacing comes from the shape, so the man the
  ball was for was **1.35 m from a centre-back** and the pass model was simply
  right about him. `SimScenarios._gap_lanes` now puts them in the two widest gaps.
- **The escape contest was reading the length of the pass and calling it a
  marker.** `_pass_success` asks a second control contest at the receiver's own
  feet, and handed it the ball's whole flight: he is floored at the arrival and no
  opponent is, so on a three-second ball every defender within a dozen metres beat
  him to grass he was already standing on. The same runner, the same marker, came
  back at 0.003 on a 28 m ball and 0.99 on a 12 m one. `ESCAPE_WINDOW`.
- **What is left is the lane, and it is real.** With both fixed the ball still
  comes back at `space 0.30, lane 0.000`: the passer is 22 m from the line and a
  defensive midfielder is standing 1.6 m off the line of the pass. That is not a
  ball a footballer plays either — it is the one he moves first. `through` went
  from 0.0 to 0.1 a trial and the row is still a midfielder passing sideways.
  **The binding half of 33 is therefore the first one**: men ahead of the ball are
  not getting into a position where the ball to them exists, which is `SimOffBall`
  and not the pass model.

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

**50 is measured, and it is the defence's absence wearing a set-piece count.**
Corners run at **0.4-0.5 per team across 150+ matches** (2026-08-25), below the
0.5 sanity floor and far below football's 3-8. Up from the 0.02 of 2026-08-16 —
shots and crosses reaching the box is what moved it — but a corner is *conceded*:
it needs a defender who blocks or deflects behind, a keeper who parries wide,
and neither act is built. No attacking mechanic can move this number and none
should try (`PLAN.md` §11.4). It comes back with **5**, whose entry already says
so; this one exists so the defensive pass starts with the figure in hand.

**52 is the owner's, 2026-09-02, watching the block land (`M`).** A defender who
slides at a shot can change direction during the slide, and a keeper who has
left the ground for a ball can change direction in the air; the owner expects
other committal moves to allow the same. The body is locomoted every tick by
`SimPlayer.locomote` from a fresh `desired_vel`, and nothing in it knows that
a man is off his feet: the block's lunge is a `move_target` with the ordinary
steering under it, the dive is `play_anim` over a keeper still steered to the
ball, the jump for a header is a reach test with no flight. The rule the owner
named: **in the air the body follows its ballistic trajectory; in a slide it
is locked in one direction until he stands up.** The general form is a
committed-move state on the body -- entered by the slide, the dive, the jump
and the fall, with its own velocity law and a duration, released into
`recovery_ticks` -- read by `locomote` before any steering. Not built; noted
so the next committal act is built onto it rather than beside it.

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

**One measurement hazard, found while doing this, and it is fixed.** `SimDuel`
logged `SimTelemetry.Touch.BLOCK` for *any* loose ball won without control that
did not come from a contest, so a defender jogging onto a ball nobody struck at
him was recorded as having blocked it. `race` read "block" where the football is
"he got there first", and anything counting blocks — including `--acts` — was
counting those too.

**What the touch is called is now decided by why he could not take it.** The
test was already there and its two arms are different football: the ball
arriving faster than his first touch can handle is a block, a man getting in the
way of a strike; his own closing speed or the pressure on him is a poke, a loose
ball hooked away by whoever got there first. `SimTelemetry.Touch.POKE` is the
second, and `is_defensive_kind` is asked wherever a list of "not the carrier's
own touch" is needed — there are three of them now and every consumer needs all
three. Ten match-minutes of seed 1: 3 pokes against 1 block, where before it was
4 blocks.

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

**Built 2026-09-01: the body frame.** The engine had a heading and no body:
`facing` was written from the velocity every tick a man moved, so the receiver's
half-turn was clobbered in the same tick, nobody could move sideways or
backwards without turning the hips, a shield was a flag, and a feint had nothing
to turn. Now the body is its own state -- `look_target` holds it, `body_slaved`
latches it to the run above half pace and releases it below 40%, a slaved run
is bit-identical to before and a chase is never slowed by a look; held, the
hips turn at `turn_rate`, the pace is capped at the strafe share and the drive
off the hips is taxed. The predictor keeps the velocity's view (INVARIANTS).
Then, one commit each, watched between: the gait reads the body (`SHUFFLE`, the
run posed in the frame of the hips); the consumers read it honestly (the
strike's run-up is the pace along the hips, the keeper holds his arc facing the
ball); the touch turns the hips and the shield is geometry (`SimDuel.shielded`,
the flag stays as the choice); and the feint is a candidate, with defenders who
close half-way to where the carrier's hips say the next touch goes. The jockey
is the same arm with the errand turned round and is held for the defensive
pass. Measured at ten minutes across four seeds: `could not see` moved 23/25/31/32%
to 21/30/23/20%, three of the four after-runs scored where none had before;
`hold-up` lost 58% to 61% at n=160, no move; the feint was on the list in 7 of
100 trials and chosen in none -- once losing to the coin with a positive score
gap. `The body` block in `diagnose` reads the shuffles by errand.

**Built 2026-09-01: the bent lane.** The engine could bend a ball (36) and never
chose to: every lane was priced as a straight chord, so a pass blocked straight
and open on a bend was never a candidate. Now the bend is intent. The two named
solver holes closed first — `solve_direct` corrects a yaw the way `solve_lofted`
does (the invariant said it would bite the day a shot meant its bend; this was
that day), and `ground_launch` solves the driven ball with its spin in hand,
exactly, because rotating a launch about UP rotates the whole trajectory
rigidly. `SimBallistics.curl_bow` predicts the bow closed-form, validated
against the integrator by two-flight difference in `test_ball`. `_cut_chance`
prices a defender against the path the ball actually takes (a `bow`, quadratic
offset, station kept on the chord and said so); the driven pass offers the
curled variant *inside* its one candidate when the bent lane clears `CURL_MIN`,
the shot when the bend takes a blocker out of the corridor — an integer, no
tuned threshold. The foot picks the side, so the decision is whether, never
which way; the trivela is the fallback when the natural side is closed and the
other open, taxed twice (`TRIVELA_CONTROL`, `TRIVELA_SIGMA`) and gated by no
band. Tallied under `The small acts` (`bend it`, `trivela`) and ablatable
(`curl (the bent lane)`): over ten-minute fragments the term is in at 2–8% of
decisions, swings 0.88–1.39 on success, and flips nothing yet — rare and small
at the unturned starting values, which is a result and not a target.

**Second cut, same day: the lifted bend.** The first cut measured out. 0.18 m
of bow against a leg's 0.9 m of *free* reach — `_cut_chance` charges nothing
for the first `CONTROL_RANGE` of gap — so `curl-blocked` offered the bend in 0
of 25 seeds; the gate was honest and the ball could not bend enough to pay it
(`tools/_curl_probe.gd`). Two causes, both physics: the lift coefficient
saturates, so past `MAGNUS_S_HALF` more spin stops buying bend, and a driven
ball bends only in its hops. The football answer is football's own — you
cannot whip a flat skimmer. A *meant* bend is now a lifted ball: `BEND_LIFT`
clips it up into knee-high hops, `PASS_CURL` rises to the cross's 40 rad/s
(the same act of the boot), and the bow comes out near half a metre over
twenty. The lesson, for the next lane mechanic: a bend buys nothing until it
clears the leg's free reach — and a man with the ball's whole journey in hand
covers that extra half-metre anyway, so the bend beats the *closing window*,
the defender arriving with nothing to spare, and never the man stood on the
chord with time. The paired rows were re-cut to place exactly that window.

**And a correction fell out of it.** The probe found the driven ball's bend
branch dead at twenty metres, and the reason was the driven ball itself:
`d_pace` was `minf(pace * DRIVEN_PACE, 1.0)` from the day **26** landed — a
normalized cap typed into a real-units field — so every driven pass in the
game arrived at one metre a second, softer than the roller beside it, and
under ~24 m its launch never reached `DRIVE_FROM` at all. The ball priced as
airborne and taxed as hot was a roller arriving dead. The cap is now
`arrival_pace`'s own 12 m/s. A correction, not a tune, like `SHOT_AT_PACE`:
whatever it moves is recorded, not absorbed.

**Third cut, same day: the bend as shape.** Measured with the tallies that were
missing (offered *and* played, and how many driven balls there were to ride
in): 25 of 32 ground passes in ten minutes were driven, the bend was offered on
nine to sixteen candidates and played once. The gate was honest and the
geometry it needs is rare, and a played bend bowed 0.35 m -- a straight ball
from the stand. The owner saw no curled balls because there were none to see.
The old reason the driven pass stayed zero-mean was that the solver could not
put a signed bend back on its target; that closed above, so nothing kept it.
Now every driven ball carries its foot's bend as *shape*, the cross's own spin
scaled by technique -- about 0.2 m over twenty metres, more on a longer ball --
and the plain driven candidate is priced on that bowed path, so the model and
the strike agree. The meant, lifted bend stays as the variant on top, and it
is now measured against the shape's lane rather than the chord. A skimming
drive is airborne for half its journey, so the shape bend is modest by
physics; the visible whip is the lifted one.

**Open question, recorded rather than asserted:** the owner's "outside of the
boot is power". No inside-curl pace cost exists yet for the trivela to be
exempt from, so a power refund would assert a direction nobody has decided;
when an inside-curl pace cost lands, the trivela's exemption is the power.

**Not built, said out loud:** the curled *cross* changes nothing in pricing,
because `_lofted_success` has no lane term at all — the aerial lane model is
the missing mechanic, not the bend; a rolling ball cannot bend by design
(`SimBall`, yaw does nothing on grass), so curl is a driven and airborne act
for free; and `_pick_shot_aim` still chooses its corner blocker-blind.
`curl-blocked` and `curl-wrong` are the paired rows. The golden digests moved,
as a changed mechanic makes them, and were re-recorded.

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
`solve_lofted` and arrive where they were aimed along a bent path. The driven
ground pass used to be the exception — its spin was stapled on after
`ground_launch` had solved the speed, an error the solution never saw — and is
not any more: the curl is drawn before the solve and `ground_launch` answers it
with a yaw, exact because rotating a launch about UP rotates the whole trajectory
rigidly. So it carries a signed mean like the rest: every driven ball bends the
way its foot sends it (`SimTouch.pass_shape_curl`, at `PASS_CURL`), and the
decision prices the driven lane on that bowed path.

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

**Tried, measured and reverted.** Each is left in the code with its numbers,
because the next reader of the proposal will reach for the same thing. They are
not all the same kind of result. `CORRELATED`, `LENGTH_COST_DIRECT` and
`line_broken` failed on **mechanism** — the thing each proposal claimed did not
happen — and are closed. `_worth_at`, `QUOTA` and `CROSS_ON` were reverted on
**goal cost**, which is the band-gating `CLAUDE.md` forbids, and the cost was
measured in an engine missing the serve (**33**) and the byline (**51**) that
would make men in the box pay. **Re-try those three after 33 and 51 land**;
until then they are provisional, not results:

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
   **Stages one and two of the serve, built 2026-09-01.** The run bends into a
   channel now: `_behind_point` aims at the nearest interior gap of 4 m or more
   between the line's defenders instead of `p.pos.z * 0.85`, and generated
   points land 4.8-7.9 m wide of the nearest man on the line (three seeds).
   The gate tally gained a committed-runner row, and it reversed the diagnosis:
   a committed runner is never refused at "not moving forward yet" -- he is
   refused at the shortlist (14-27%, perception and the 60 m cap) and at
   striking range (36-57%), and the refused ball averages 37 m, which is the
   lofted ball's own ground (24-55 m, aimed at his committed destination
   through `_lead_point`). "Run too short" never fires: every "no run to make"
   is `BEHIND_MAX_RUN` at 18 m refusing a midfielder far back, not a striker
   on the shoulder. Offered rose from 10% to 27-29% of committed runners on
   two seeds (the third made one run); **it scored best 0% everywhere**, so
   the item now stands at the pick, not the offer -- and the lane refusal
   recorded above is already known to be real football.
   **And seen from the receiving end, owner, 2026-09-01 (`M`):** the man the
   ball in behind is played to stops on it and turns back toward the passer
   instead of taking it in stride past the line. The mechanism is in the code:
   the struck ball makes its man the designated chaser (`SimMovement`), which
   stops his off-ball errand and aims him at the intercept point -- a spot, not
   a direction -- and `_orient_receiver` then turns any receiver moving under
   1.6 m/s halfway between ball and goal, which is the turn the eye sees.
   `MEET_EASE`'s release half is counted for `show` and `space` only; a `behind`
   runner has no arriving-ball handling of his own. Taking it in stride is a
   chase target ahead of the intercept along the run, for the man the ball is
   for -- the serve half of this item, not a new proposal. Built the same day:
   `SimMovement.RUN_ON_THROUGH` carries his chase target past the intercept
   along the run. Unverified by number -- no measured fragment played a through
   ball -- so the through-ball scenario's eye is the check.

   **And the strike under it, same day, owner's eye again: too long, mostly too
   short and slow, and into the runner's back.** The bench had it exactly --
   `ahead` 11.5-14.1 m against `he covers` 14.8-29.0 -- and the cause was three
   deep. `_behind_aim` capped the lead at the *destination* of the run, so every
   flight that outlasted the run was under-led by the difference: it aims at the
   meeting point of his flat-out run and the ball's flight now, two rounds of a
   loop. A meeting point past the passer's reach was then not a reason to offer
   nothing: the aim clamps to what he can strike (`clamp_to_reach`). And a
   clamped ball crawled, because `BEHIND_ARRIVE` slows the strike for a chasing
   man -- a man who beats the ball to the spot by a stride (`BEHIND_EARLY`) gets
   it firm, priced as the pass to feet it has become. The bench reads met in
   stride at 1.6 m, rolled a stride ahead, or firm to a man arrived; offered
   went 27% to 64% of committed runners on seed 7.

   **The first cut of the stride fix was a regression the scenario caught.**
   `RUN_ON_THROUGH` ran the receiver through *every* ball while he was
   committed, a pass to feet included, so he overran those on purpose:
   `through-ball` read 90% lost with two touches a trial, every trial ending on
   the first ball. Gated on the intercept sitting ahead of him along his own
   run (`RUN_ON_AHEAD`), and with the gate the row reads lost 65%, through
   balls **0.7 a trial against 0.1** at the 2026-08-26 measurement, box shots
   0.72 against 0.44 (n=40, about 8 points of error on a share near a half).
   The act the scenario is named for is played at last. In a full match it is
   still offered and never picked -- scored best 0% -- which is where the item
   stands. **Second look, same day: mostly too slow, some way
   too hard** -- the two pace branches, read separately. `BEHIND_ARRIVE` 0.8 to
   0.9, then to 1.0 on the third look ("looks like a normal pass"): under the
   meeting-point aim the catch is geometry, so the arrival pace is only the
   character of the ball, and at his full pace the strike is firmer and the
   meet deeper. And the firm branch capped at the runner's own top speed instead of the
   uncapped `arrival_pace` (11-12 m/s down to about 9.4). Both are eye
   constants; the bench reads 0.9-3.4 m to spare in stride, and the 37 m
   clamped ball still waits -- no ground ball covers that in the time, and that
   geometry is the lofted ball's, refused honestly.

   **Fourth look, same day: most still slow, "no chance of getting past the
   defenders" -- and they were not through balls.** `_lead_point` follows a
   committed run wherever it goes, so the *ordinary ground pass* to a runner in
   behind was aimed past the line at pass-to-feet weight: the through ball's
   slow twin, played six times as often, and the safer-priced duplicate that
   kept the real act from ever scoring best ("price every path to the same
   outcome"). The ground pass now stops at the believed line (`BEHIND_BREAK`);
   the ball in behind is the through ball's act and the loft's.

   **Fifth look: still slow -- and the pick was the fault, measured to its
   factor.** `tools/_behind_probe.gd` (the pull-back probe's twin) splits the
   through ball's success: succ 0.127 = space 0.484 x lane 0.849 x struck
   0.620 x set 0.500, and the geometry line convicts the aim -- 11.8 m beyond
   the line, 12.3 m from goal, **the keeper there in 1.97 s against the ball's
   2.30**. The meeting point of a deep run lands where the keeper collects:
   the room a ball in behind has ends at the goalkeeper, not at the paint --
   `keeper_room`'s rule, in its fourth home. `_behind_aim` now steps the aim
   back toward the runner until the ball beats the keeper by `KEEPER_BEAT`.
   Probed: space 0.484 to 0.647, succ to 0.181, and the scenario's box shots
   0.44 to 0.96 a trial with misses 8% to 2% (n=40). `set` 0.50 is the scenario's own settle and decays.

   **Stage three closed the same day: the pick is won.** The probe, given
   `score_of` per candidate, reads the through ball best on the board in the
   set geometry -- 0.0536 against the safe pass's 0.0454 -- once the keeper
   bound shortened the ball under `BEHIND_FREE` and the length bias stopped
   taxing it. And the match chain runs end to end at last: over nine
   ten-minute fragments, 69 runners, 48 offered (70%), **4 scored best, 3
   played** -- zero on every link at the start of 2026-09-01. What remains is
   *rate* -- how often the run is made (2 to 19 a fragment, `QUOTA` and the
   stage-one items) and how often the pick goes through -- which is frequency
   tuning against the owner's eye, not a mechanism, and belongs with §11.1.1.
2. **The cross's offer rate**, which is what is left of its two thin links. The
   delivery half is answered: the ball was arriving below heading height short of
   its aim and the model was told it scattered twice as far as it does
   (`SimTouch.CROSS_ARRIVE`, `CROSS_RANGE_SPREAD`, and **29**). The offer rate had
   not moved all day at 11.7% to 11.8% and is generation — one seed now reads 16%,
   which is one seed. See `CROSS_FROM`.
3. **24 and 27**, both now wanting a fresh idea rather than their named one.
4. ~~**8b's other half**~~ — built 2026-08-23: the map is multi-step now. What is
   left of it is that the correction for who is standing where (`line_broken`) is
   still applied to the through ball alone, and the lofted ball measured worse
   for it.
5. **Pattern success rates at n=20.** The instrument exists (`and was the ball it
   asks for ever on the list`); what is missing is a batch that aggregates patterns,
   which `chains` does not. At n=1 the switch has read 0% and 25% in one day.
6. **`QUOTA` behind, decoy and second** — show and space are now measured, these
   three are not.
   **51, measured to its terms, 2026-09-01** (`tools/_byline_probe.gd`: the
   same winger at five depths on the flank, every candidate's score and the
   carry's factors). The board is carries infield at every depth; the cross --
   when the box is loaded -- beats the down-line carry; nothing approaches the
   byline. Three causes, each with its number. **The map prices the byline cell
   level with the infield one** (gain 0.022 v 0.022 at 24 m, flat at every
   depth), so any tax decides infield. **The facing tax is the largest steer**:
   `facing_control` reads 0.46-0.72 on any carry off the man's goal-facing,
   every decision, and whether a multi-touch carry should pay first-touch
   facing on its whole direction -- the locomotion layer already charges the
   turn as time -- is the named open question this measurement leaves. And
   `ctrl` at the down-line landing drops with depth (0.83 to 0.61), part
   full-back, part the deep landing nearing the defence.

   **Built: `_carry_delivery_gain`** -- `_carry_shot_gain`'s wide sibling: a
   carry whose horizon lands in crossing ground is worth a share of the
   delivery from there (the box point's map value times who owns the dropping
   ball, `CARRY_DELIVERY_CONVERT` 0.55). Two shapes measured: with a length
   gradient it dies under the map everywhere; flat, its signal is the box --
   ~0.036 loaded against ~0.02 empty, "the wide man goes when his mates
   arrive" -- and flat is what shipped. Scenario rows moved with it
   (cross-loaded 15% goal + 30% saved against the stale table's 12+15;
   cross-early crosses 0.93 a trial; byline and pullback unmoved), all n=40.
   **The pull-back's two-point fix from the probe was already built** in the
   working tree; the stale 79%-lost figure is 52% today.

   **Two faults found on the way and not yet fixed, 2026-09-01.**
   **`_lead_point` has the through ball's old under-lead, and the lofted ball
   over the top pays it**: the lead is capped at the *destination* of a
   committed run (`minf(span, ...)`), so a ball whose flight outlasts the run
   is aimed where the runner will already be standing -- the exact fault
   `_behind_aim` was cured of with the meeting-point loop, still live for the
   loft that serves the 24-55 m runners the range gate refuses. Same fix
   shape; mind the ball to feet, which the cap is right for.
   **The scenario table in `docs/STATUS.md` is stale**: measured 2026-08-26 at
   n=160, and the day's work moved several rows (`cross-pullback` lost reads
   52% against the recorded 79%). Worth one fresh `./run.sh scenario
   --trials 160` before any row is quoted again.

7. **51, the approach to the byline.** The cut-back and the cross from the line
   are both built and both wait on a ball that never arrives: `_add_pullback` was
   offered 0 times in fifty minutes and `Where passes are played from` reads the
   final sixth at 0% of passes. The outlet wide (`_wide_point`) gets the ball to
   the touchline; what is missing is the man taking it on from there.
8. **What is left of the station's motion is the leash, and it is meant.** The
   four possession switches are eased (`SimContext.shape_phase`); the stations
   that still outrun a sprinter, 0.3 to 0.9% of samples, are `SHAPE_BALL_LEASH`
   dragging the shape behind a ball hit sixty metres. That is the one moment a
   side really does turn and run, so it stays until somebody watching says
   otherwise.

**The defensive pass — the current work, from 2026-09-02.** Each costs goals,
and goals are meant to fall. **5** first — it is still the largest single thing
an eye would name — then **3**, then the remaining defending rows above:
jockeying, covering, the offside trap, the deliberate foul.

**Built 2026-09-02: the block, and the box defended.** A defender in the shot's
path could take it only on the ordinary contact rule -- a leg inside 0.9 m
after his reaction had run -- and a shot at 25 m/s is past a man four metres
away in 0.16 s, so nobody in front of a strike ever got there. Now a body
inside `SimDuel.BLOCK_RANGE` who has the striker in his eyes moves on the
backlift (`BLOCK_READ`), and what he covers is a thrown body plus the lunge
over the ball's flight; one roll at the strike, taken on the tick the ball
reaches him, the keeper's own pattern. `block_chance` is one function for the
price (`expected_goals`) and the act. Where it goes is `SimTouch.block`:
mostly back out at a fraction of the pace and off the floor, three in ten
carrying on -- which is the corner the engine could not concede.
**And the model measured out first**: over twenty ten-minute fragments it
fired zero times, because the nearest body in front of a strike stood 6-12 m
along and 4-20 m off the line. Nobody was in front of a shot to throw himself
at it. So the box defence went in beside it: inside `BOX_DEFEND_RANGE` the
presser closes from goal-side (`LANE_STANDOFF`, the one place a chaser in
front of the carrier is the football) and the second man's fan-out shrinks
onto the line of the shot (`PRESS_FAN_NEAR`). Same twenty fragments: shots 21
to 15, goals 3 to 1, blocked 0 to 2, corners 0 to 1 -- thin, and reported as
such. `shot-edge` reads block 0% to 10% with `lost` 2% to 35%: the man at the
top of the box with bodies in front now carries into them instead of shooting
through them, which is the row's own question answered. `1v1-clear` did not
move. `Shots by distance` carries the lunges and where the nearest body stood.

**Built 2026-09-02: the keeper narrows the angle.** The arc (`station`) is a
resting depth, 0.45 m plus 0.17 a metre, so a shooter at sixteen metres found
him three metres out and waiting; `_one_on_one` only came for a man *running*
at goal. `_narrowed_station` stands him where what he covers either side
(`NARROW_REACH`, set and stepping) closes the goal from the shooter's point of
view -- `D * (1 - reach / half_width)` down the ball's line -- capped at
`NARROW_MAX` and only for a ball in front of the goal, since coming down the
line of a ball on the byline abandons the far post. No new price: the save
model already pays less dive time for less angle, and the chip is priced off
his distance out. Measured with the rule switched off against on, same twenty
fragments: the keeper stood **3.4 m off his line at the strike against 4.1**.
`1v1-clear` 48% to 45%, `1v1-onrushing` 35% to 45%, `long-range` 25% to 28%
(n=40, eight points of error): nothing the eye should read as a change yet,
and the one-on-one answers gated on a keeper who never left his line are now
gated on one who does.

**Built 2026-09-02: the escort.** A ball the forecast has going out
(`SimTrajectory.out_index`) inside `ESCORT_HORIZON`, last touched by them, that
our chaser can reach before it is out: he puts himself `ESCORT_GAP` on the far
side of it from whoever wants it, holds his look on the ball, and
`resolve_contacts` leaves him out, so it runs over the line for our restart
instead of being hooked clear from the byline. Twenty fragments: 39 cadences
of it, about four seconds of escorting; the ball went out of play 44 times
before and 49 after on the same seeds. Rare and cheap, as its row said.

**Built 2026-09-02, item 8: the wall, and one corner routine.** A direct
free kick inside `WALL_RANGE` and in front of goal puts the nearest two to
five defenders shoulder to shoulder on the law's 9.15 m across the line to
the near post (`_wall_spots`), looking at the ball; `SimDuel.block_chance`
reads `in_wall` as a standing body that jumps -- `WALL_BODY` either side,
`WALL_JUMP` high, `WALL_STOPS` of what comes through -- with no read and no
lunge; the taker aims round it to the keeper's side. `fk-shot` at n=160 read
goals 21% to 5% and blocked 0% to 24% on the first cut, **and that was men
still walking into the line when the kick came**: with the referee's signal
below, the wall set and the taker going round it, the row reads goals 22%,
blocked 7%, saved 24% -- a 21 m shot converting as every 21 m shot does here
(`long-range` 19-25%), which is the range shot's fit and not the wall's. The corner routine (`_corner_choose`, `_corner_plant`): a post is
named at the restart, the two attackers the spots put deepest are sent to
the posts a `CORNER_HOLD` before the kick and steered there over the dead
ball, and the delivery is aimed at the named post and the man going to it.
Watched with a probe, the ball came down 5-13 m from the post -- the
delivery's range error at 31-39 m, which is **29**'s recorded bound and a
tuning-freeze decision. **And the referee's signal, the owner's (2026-09-02):**
a corner or a free kick is not taken until everyone is within
`SET_TOLERANCE` of his spot and `SIGNAL_DELAY` more has passed, capped at
`SET_PIECE_WAIT`; the two-second timeout had taken every corner before a man
had crossed the box, and the routine's runners were still walking to their
spots when they were sent. Struck at 9.3 s on the corner row and 7.6 s on the
free kick. With it, the corner comes down **4.7-4.9 m** from the nearest of
ours against 6.7 before and 5.4 before the routine, `none` 39% to 26%; goals
6% and 2% at n=160, inside the error of where they were. The runs are made
and arrive; the ball still lands off the post. **And the run-up, the owner's
(2026-09-02):** the taker stood 0.63 m over the ball facing wherever his walk
had left him. He waits `RUN_UP` behind it now, on the line from where he is
sending it, looking at the ball, and on the signal runs up and strikes; the
corner's runners go as he does, so his run-up is their head start
(`_taker_stance`). Struck at 10.0 s and 8.5 s on the rows. With everyone
set and the box loaded before the ball, `fk-wide` reads 19% goals against
8%, corners 7-8% with the ball 4.7 m from the nearest of ours, `fk-shot`
18%.

**Built 2026-09-02, item 7: the link players (30).** The pocket between the
opponents' lines was only an *offer* (`_pocket_point`, a lift on a space
probe), taken or not by the softmax and mostly not; now it is the station.
`SimMovement._link_station`: in possession, the playmaker's shape x goes to
the midpoint of their midfield and their line (a stride onside), the central
midfielders' by half, blended on the possession phase, width the formation's
own. The pocket is read off where their men stand, which moves at a line's
pace, and the over-8-m/s column did not move. Tallied under `The small
acts`: asked on 19,600 cadences over twenty fragments, applied on 77% (the
rest: the pocket behind the ball or too far ahead; never for want of a gap),
moving the station 7.4 m forward, the man standing 2.6 m ahead of the shape's
ball on average. **Forty seeds, on against off**: touches by third own /
middle / final **12 / 74.5 / 13.5 to 12.5 / 70.5 / 17**, the same direction
on both batches of twenty; shots halved on one batch and rose by half on the
other, which is what twenty fragments are worth. Modest, and the middle
third still holds seven touches in ten: the man is there, and the ball into
him is priced through their midfield's lane, which is the defence being
right. What is left of 30 is the pass into the pocket, a decision question.

**Item 6 of the pass, 2026-09-02: the runner served, re-measured against the
defence.** The brief's figure -- offered to 27-29% of committed runners,
scores best 0% -- was the morning of 2026-09-01; stage three closed it that
day. With the defence in, twenty fragments: the run in behind is made 87
times, offered 63%, received **13%**, 72 through balls played and 58% of them
reaching the man he was for; when it loses it loses on `success` (0.15
against 0.73), which is the lane and the space it is played into, honestly.
Taking it in stride is `RUN_ON_THROUGH` (2026-09-01) and the through-ball
row's eye is still the check on it. **The box run** is made 118 times,
offered 49-53%, received **5%**; the ball to him is priced at `succ` 0.18
(`space` 0.51, `lane` 0.64, `struck` 0.75) and loses by 0.06 to the safe
ball. One thing was tried and reverted: the early cross to a committed run
(the cross gated to a fifth of their half instead of a third when a box
point is claimed). It doubled the crosses -- offered 45 to 86, played 9 to
18 -- served the runner no more (5% to 4%) and cost shots 22 to 9 on the same
fragments: a hopeful ball into a box that is now defended. The serve is
bounded by the space at arrival, which is the defence doing its job; football
serves a box run about one cross in four and the engine's price is near that.
What is left is the *rate* the run is made at, about fifty a match, which is
`QUOTA` and the owner's eye (§11.1.1), not a mechanic.

**The re-watch of the attack, 2026-09-02 (item 5 of the pass).** Every row at
n=160 against the same rows at the last pre-pass commit; the table and the
reading are in `docs/STATUS.md`, "The scenarios, measured". Rows that stopped
reading as football, named: **`volley`** -- the first-time strike is priced
low with bodies in front, so he takes it down and carries, and nobody closes
him (goals 25% to 36%, `lost` 2%); the missing defender is the one who
closes a man taking a dropping ball down. **`shot-edge`** -- he no longer
shoots through two centre-backs, and carries into them instead, one in seven
to nothing. Rows that moved and read right: the crosses lose 70-80% now,
which is football's rate; `hold-up` keeps it under a jockey; `long-range` and
`race` score less. `1v1-clear` rose 35% to 44% from small pricing effects,
none alone beyond the error, and sits inside football's rate. One guard went
in on the way: the box lane is not given to a chaser behind the carrier, who
runs round first (`_recovery_weight`), the tailgate INVARIANTS names.

**Built 2026-09-02: the deliberate foul.** The cynical foul that stops a
break had been falling out of `CHALLENGE_FOUL_BEHIND` by accident; this is the
choice. `SimDuel._cynical`: a challenger behind or level with a carrier
running at his goal, outside his own area and inside `PRO_FOUL_RANGE`, with
their men goal-side of the ball outnumbering ours or the nearest cover further
than `PRO_FOUL_COVER_NEAR..FAR` from the carrier, commits `PRO_FOUL_COMMIT`
times as often and fouls `PRO_FOUL` times as often when he loses the contest,
scaled by aggression. The card is the referee's. Counted as the moment, the
challenges from it and the fouls from those, under `The small acts`. **The
first cut was never a candidate**: the numbers test alone held on zero ticks
in twenty fragments, because a side here keeps four or five men goal-side of
any carrier -- the break is rare, and that is `The two seconds after a
regain`'s subject, not this one's. With the cover gap beside it the moment
held on 88 ticks in twenty fragments, produced 2 challenges and 1 foul; fouls
4 to 6 on the same seeds. `1v1-chased` reads no foul a trial at n=40 before
and after. Built and rare; the rate is the break's, and the owner's eye.

**Built 2026-09-02: the offside trap as an act.** The line's standing height
was a station (`offside_trap * 5` metres with the ball far); the step is
`_consider_trap`: on a ball played back or a carrier pressed with his back to
us, with a runner inside `TRAP_BAIT` of the line, the back four go up
`TRAP_STEP` together -- eased in over a quarter-second and out over half a
one, latched for `TRAP_HOLD`, at a run (`TRAP_PACE`), rolled per refresh at
`TRAP_PER_SECOND * offside_trap`. Added after the marking blend, which
otherwise ate most of the step. Two things measured out on the way: the
trigger read `possession_player`, which is -1 for most of a pass's flight,
so a trap on the back pass could not fire (5 in twenty fragments; 18 once it
read the last touch); and it catches nobody -- 0 offsides inside three
seconds of 18 traps, and on the new `offside-trap` row (the ball played back
in front of a line with the trap turned up) through balls 1.4 to 1.2 a trial
and offsides 0.2 to 0.1 with the trap on. **The step deters and does not
catch, and the reason is perception**: beliefs refresh at 4-8 Hz with the
velocity extrapolated, so the passer sees the line go and declines the ball,
which is the engine being right about a man looking up. Whether a passer with
his head down on the strike, or a runner watching the ball, should see the
line move is a perception question for the owner, not a knob here.

**Built 2026-09-02: where a parry goes (3).** Every parry was pushed
forty-five degrees back into play at a fifth to two fifths of the pace, with
the keeper up and set for the rebound at once -- the cascade. Now the hand he
got to it decides (`closeness` from the save model, scaled by `handling`): a
full hand goes round the post with a share toward the byline (`PARRY_BACK`),
or over the bar if the ball was rising and high; a fingertip drops in front
of him at a fraction of the pace. And he is down for `PARRY_DOWN_MIN..MAX`
with half his reach, so the rebound is somebody's before it is his. Tallied
under `Goalkeeping` (wide / over / in front). Forty fragments before and
after: second attempts inside four seconds **9 of 37 to 7 of 35**, parries 6
in all (2 wide, 4 in front), corners 0 to 1. Six parries is not a
measurement of the rate; the direction is the mechanism and that is what
changed. Whether the cascade has gone is the eye's and a longer run's.

**Built 2026-09-02: the jockey.** The errand turned round, as the body frame
promised: a chaser inside `JOCKEY_FAR` of the ball and goal-side of the carrier
(`_jockey_weight`, both ramped) has his target blended onto a point
`JOCKEY_STANDOFF` from the *man* -- outside `CONTROL_RANGE`, inside
`CHALLENGE_RADIUS`, so the commit roll still fires -- with his look held on the
ball, and inside the line to goal by `SHOW_WIDE` when the ball is off centre.
Under the look and the strafe cap he shuffles; when the carrier goes past at
pace the target outruns the cap, the body slaves and he turns and runs. `The
body` reads it: over twenty fragments, 326 jockey samples, **20% of his steps
sideways and 11% backwards**, against 1% and 0% for every other errand. The
scenario rows it touches did not move at n=40 (`take-on` 68% lost, `hold-up`
58%, `1v1-chased` 65%), and `shot-edge` at n=120 reads 22/10/11/8/37: no move.
Two honest faults recorded. The point was first set off the ball and moved at
8-9 m/s, because a carrier's ball leaves his foot at several metres a second
every quarter-second; off the man it reads 2-9, which is the same class as the
chase it sits inside (5-8 m/s: the intercept point moves with the ball at a
carrier's feet) and the fix for both is one fix, not this item's. And the
errand's `switched` column reads 20-60%, the blend crossing `JOCKEY_FAR`.

**Owner's eye on the jockey, 2026-09-02: hints of it, and the carrier passes
before it can be seen.** Agreed and deferred: it is **28** and **37**, the
release rate. Two things to separate when it is picked up. `Under challenge`
reads 70% pass closed down against 40% free, and a decision comes every
quarter second, so the pass need only win one. And `pressure_on` weighs a
facing man inside 6 m by proximity alone, so a jockey standing off reads to
the carrier like a man charging him -- `challenge_on` has the closing-speed
term, `pressure_on` does not. The check first: `Why an option lost` on a
jockeyed carrier, whether the carry lost on `success` (pressure; the fix is a
closing-speed term in `pressure_on`, this pass's) or on `gain` (the map; 37).

**Noted 2026-09-02, owner's eye on the block: 52**, the committed move that
still steers. Not this item's to fix; it is on the list so it is built once,
under the slide, the dive and the jump together.

**Built 2026-09-02: cover.** A beaten man was only penalised in the chase
ranking, which chooses who presses next and leaves the lane he had stood in
empty. `_pick_cover` names one man a side -- the nearest eligible to a point
`COVER_DEPTH` goal-side of a carrier who has one of ours behind him or has
just taken it off him -- and latches him for the carry, because a cover
recomputed every refresh from whoever is nearest is two men trading the
errand three times a second. The point moves at the carrier's pace and says
so under its own name in `Holding the shape` (target 4.4 m/s on the seed that
had one, 0% of samples: it is rare and brief, as it should be). Twenty
fragments: **28 covers taken**, about a dozen a match. `take-on` 72% lost
before and after; `race` and `1v1-clear` inside the error.

**Where 5 leaves the corner count.** Still not back: 0-1 over twenty
fragments, about 0.3 a team a match. The block gives the defence a way to put
the ball behind and it did once; the parry that goes wide is **3**, next, and
the clearing header under a cross is the other half. Reported as a result,
not a target.
**And the pass ends with a re-watch of the attack.** Every attacking row marked
built was judged, by eye and by number, against a defence that cannot jockey,
block or defend its box; a judgment made against no resistance is provisional.
Expect rework, and treat a built row that stops reading as football then as
scheduled work, not a regression.
Two measurements belong to it and are recorded here so they are not lost:

- **Corners run at 0.4-0.5 per team a match against a target of 3-8**, 150+
  matches, 2026-08-25 (**50**; 0.02 at n=20 when first written). A corner needs
  a defender to put the ball behind or a keeper to parry wide, and neither act
  is built. They come back with **5**, as its entry already says.
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

**2026-08-25: the owner made a density call, and the knobs cannot deliver it.**
The stat screen need not read as real football; the eye wants pass density at
**1.5-1.75x football**, down from ~2x — passes per team 176 to 132-154. The
composed-receive mechanics went in (the receive's first touch aimed by value and
space, a pressure-scaled take-down bias, the flight-prep cap on the strike beat)
and moved 176 to **169**. Every tempo prior after that saturated flat, 30
matches each: a pass-bias patience at 0.7 and at 0.45 both read ~169 with the
free-man pass share unmoved, and default `tempo` 0.65 to 0.45 read 167.5. The
priors cannot reach the release rate because the pass's score edge lives in
possession value and positional gain, which no bias touches by design — and a
decision comes every quarter second, so the pass only has to win one of them.
The release rate is **37**'s subject (and 28's), not a knob: fewer passes means
seconds where carrying or waiting genuinely outscores releasing, which is a
possession phase, not a discount. Note also that ~60% of on-ball moments are
already pressured — pressing intensity sets part of the tempo, and that half of
the answer belongs to the defensive pass.

## Watching with this list

Things the engine cannot do, and what each looks like on screen. Seeing one is
not a finding; it is the list working.

- **A man ahead of the ball stands still**, or runs and is never found (**33**).
- **Nobody holds the ball.** It is played on within about a second of arriving,
  every time, by everyone (**28**) — but check the open question at the end of the
  order before treating it as a fault.
- A cross arrives and nobody makes the run to the near or far post (**29**) — a
  corner has two men running to the posts now (2026-09-02) and still comes
  down six to seven metres from the nearest of ours, because the ball lands
  5-13 m off the post it was aimed at.
- The two centre-backs four metres in front of a shot from the edge of the box
  throw themselves at it, one in ten, and the shooter mostly carries into them
  instead: built 2026-09-02, watch whether the lunge reads as one.
- A ball is headed in the box and goes anywhere but at goal (**29**).
- Play crabs across the middle third with no one between the lines to give it
  forward (**30**) — the playmaker stands between the lines now (2026-09-02);
  what to watch is whether the ball ever goes to him.
- A shot from twelve yards with a defender beside it: he blocks now if he was
  in front of it and saw it coming; beside it he still does not.
- Attacks walk into the six-yard box.
- A keeper parries straight back out and it happens again immediately — he
  pushes it round the post now when he gets a hand to it, and is on the floor
  after; what still comes back out is the fingertip.
- The ball almost never goes behind for a corner (**5** is in; the parry
  wide, **3**, and the clearing header are what is left).
- A free kick on the edge of the box is possible but rare; the cynical foul is
  built (2026-09-02) and fires about as often as a break happens, which is
  seldom.
- **The last ten minutes look like the first ten**, whatever the score (**34**).
  A side two down keeps its shape, its width and its patience to the whistle.
- The ball is circulated at one speed from the first minute to the last: there is
  no settled passage and therefore no moment it quickens (**37**).
- The better side is more accurate and plays the same football (**38**).
- A carrier runs straight into a defender and loses it — shielding and the cut
  both exist, so this is the softmax declining them, a tuning fact rather than an
  absence. Since the jockey (2026-09-02) the defender should be standing off him
  side-on rather than running through him; a defender who still does is a
  chaser who never got goal-side.

**Watch at the clock the game ships with.** The nine-minute match is the match, so
it is what these are judged on and what the numbers are tuned to — `docs/STATUS.md`,
"what every figure here is worth".

**Something wrong that is *not* on this list is the valuable kind.** Mark it with
`M`: it means the engine has the behaviour and is doing it badly, which is more
findable than not having it at all.
