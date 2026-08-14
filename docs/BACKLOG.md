# Proposed work, not built

Ideas with a location and a reason. Nothing here has been measured. When one is
built, it moves to `docs/STATUS.md` with what it cost.

**This list is not the whole of what is missing.** It holds the mechanics
somebody has already thought through. `docs/THE_FOOTBALL.md` is the wider one:
every behaviour a viewer can see, marked built, partial or absent, whether or not
anyone has proposed it yet.

The `goals` column is the expected direction on goals per match. **It is a note,
not the sort key.** Everything here is correct football or it would not be here,
and correct football goes in whichever way it moves a statistic — the compressed
match being short of goals is a tuning-freeze problem, not a reason to hold a
mechanic back (`CLAUDE.md`, `DECISIONS.md` seventh amendment). The column is kept
because knowing the direction in advance is how a band move gets explained
afterwards instead of investigated.

## Shooting

| | Proposal | Where | Goals |
|---|---|---|---|
| 2 | Let `expected_goals` see the two things it is still blind to | `SimDecision.expected_goals` | - |
| 3 | Parry versus hold — the rebound cascade | `SimKeeper` | - |
| 4 | The in-box pass backwards the owner watched happen | `SimDecision._add_passes` | + |
| 5 | Blocks that cost the shooter, a keeper who narrows the angle | `SimKeeper`, `SimDuel` | - |
| 16 | ~~Where do the goal-bound shots go?~~ answered — `docs/STATUS.md` | `SimKeeper._try_gather` | + |

**(2) is the subtle one, and double-counting is the trap.** `aim_sigma` prices
skill, pressure, running speed, distance, composure, body facing and fatigue.
`expected_goals` prices distance, angle, finishing, pressure, composure and
blockers. Four of those appear in both, so multiplying expected goals by the
execution accuracy would count them twice. Add only the three the value model
cannot see: **shooting while running fast** (`speed_ratio` in `aim_sigma`), **body
facing** (`SimTouch.facing_penalty`) and **fatigue**. A player sprinting across
the box or turning away from goal prices a shot the same as one set and balanced,
and should not.

**Body facing is now done, and by a different route.** `expected_goals` multiplies
by `SimTouch.strike_scale`, which is the *range* statement rather than the aim one,
so it does not double-count `facing_penalty` inside `aim_sigma` — a man with the
goal over his shoulder cannot get power through the ball, and `SimTouch.shot`
scales the strike by the same number. `speed_ratio` and fatigue are still
unpriced.

**(16) is answered and it was neither guess.** The shot's fate is now recorded
where it dies (`SimReferee.close_shot`) and `diagnose` prints the table. Across
three seeds, three quarters of every shot ends with the keeper touching the ball
and more than a third of those had already missed the target; nothing goes out
of play and nothing curls away. The cause is `_try_gather` asking a fresh catch
roll every tick the ball is within 1.45 m of him, which makes its real rate a
function of dwell time rather than of the probability written down — see
`docs/PITFALLS.md`. **What is left of the item is the fix**, and it is a
behaviour change with consequences worth sequencing deliberately: a keeper who
stops collecting shots that missed gives back the goal kicks and, with (5), the
corners that feed every set piece.

**(3) surfaced as a consequence of the `SHOT_AIM_BASE` fix.** With shots reaching
the target, about a third of them are second attempts within four seconds of the
last: the keeper parries, the rebound falls to an attacker, he strikes again. Real
football has rebounds, but not at that rate. It was invisible before because
almost nothing was on target to parry.

**(4) could not be reproduced at volume.** Across three seeds it is 1 of 56
touches in the penalty area, against 34 struck and 12 carried. Either it is rarer
than it looked, or it happens just outside the area where the diagnostic block
does not count it. Worth a second look with the owner's seed rather than a general
hunt.

## Attributes

Both of these came out of asking whether player stats influence a match at all.
The answer was yes, for every attribute but two, and with one hole in how quality
reaches a role. Neither is visible by eye, so neither is urgent; both are cheap.

| | Proposal | Where | Goals |
|---|---|---|---|
| 14 | Two attributes are read by nothing | `SimAttributes`, `SimRole._WEIGHTS` | ? |
| 15 | A quality-1.0 forward is an average decision-maker | `SimRole._WEIGHTS` | + |

**(14): `teamwork` and `distribution` decide nothing.** Counted across `sim/`,
every attribute is read somewhere except those two — and both are in
`SimRole.attribute_weights`, teamwork for CB, FB, DM, CM and AM, distribution at
0.6 for the keeper. So they are priced into `role_rating`, into squad quality and
into every scout report, and they change nothing that happens on the pitch. This
is the state heading and jumping were in before the aerial layer went in. Either
give them something to do — teamwork is the obvious lever on `SimOffBall`'s
willingness to make a run that is not for himself, distribution on the keeper's
choice and accuracy in `decide_with_ball` — or take them out of the weights. Do
not leave them being paid for.

**(15): quality only lifts what the role weights say matters.**
`SimAttributes.generate` draws each attribute around
`lerpf(0.35 + 0.3 * quality, quality, relevance)`, so an attribute with zero
relevance sits at about 0.64 whatever the squad's level. `decisions` is not in
the ST, WIDE or FB weights and `composure` is not in FB or WIDE, which means a
quality-1.0 striker reads the game like a mid-table one. Measured off
`./run.sh replay`, a 1.0 full-back picks his best option at 49% against a 0.2
midfielder's 56% — the softmax temperature ratio is 0.21 against 0.50, and the
gap is smaller than the two squads' quality suggests because the attribute
driving it never rose. A forward's decision-making in the box is one of the
things that most separates a good one from an ordinary one, and here it is an
omission in a table rather than a design choice.

## Passing

| | Proposal | Where | Goals |
|---|---|---|---|
| 8b | ~~Price a ball played in behind as a man arriving~~ half built — `SimDecision.CLEAR_CARRY_SECONDS`; the map is still single-step | `SimValueField.xt_at` | + |
| 10 | The third man | `SimPatterns` | + |
| 11 | ~~Separate a ball into space from a ball to feet~~ built — `SimDecision.SPACE_TOLERANCE` | `SimDecision.pass_tolerance` | + |
| 12 | Check the passer can perceive the option at all | `SimPerception` | ? |
| 13 | What losing it costs the shape, not just the ball | `SimDecision.score_of` | - |
| 21 | ~~A ball in behind has no length term~~ built — `SimDecision.behind_length_bias` | `SimDecision._add_passes` | ? |
| 22 | The ball in behind is a seventh of every pass, and it is not the length | `SimDecision`, `SimOffBall._behind_point` | ? |

**(22) is what (21) did not answer, and it was measured rather than assumed.**
The length term reshaped the pass exactly as it was meant to — through balls over
thirty metres halved — and left the *count* alone, 207 against 211 over three
seeds. So the frequency does not come from the length.

The level does, and cutting it is not the answer either. `BEHIND_WORTH` at 0.75
took through balls from 207 to 161 and moved their share of all passes from 14.3%
to 14.1%, because the whole passing game shrank with it — 479 passes a match to
383. A fifth of the football for two tenths of a percentage point.

Which leaves the two places that have not been looked at: how many men are put on
a run in behind in the first place (`SimOffBall._behind_point` and its quota), and
whether `_shortlist` should be offering the carrier a through ball to more than one
of them at a time. Neither is a bias, and neither has an instrument yet — `The ball
in behind, as a strike` counts the balls played, not the candidates behind them.

**(8b) is half built.** `_arrival_gain` credits a pass with the threat the
receiver builds carrying it on, and it now asks how far he actually gets: a man
with nobody between him and the goal carries it 2.6 s rather than the 0.9 s
charged to a man in a crowd. That was worth the whole of the gap it was written
for — a through ball's `gain` went from 0.038 against the winner's 0.097 to 0.100
against 0.101, and through balls played went 54 to 75 over five seeds.
`docs/STATUS.md`, "The ball in behind, and the two gates in front of it".

**What remains is the map.** Expected threat is still single-step: the same
twenty-five metres out is worth the same whether the back four is in front of the
receiver or behind him, and nothing but the receiver's own carry knows a line has
been broken. `possession_value` patches the same hole from the other side, and its
`TERRITORY` tilt patches the flat map underneath it.

**Before touching any of that, read `A man was running in behind`.** Two gates in
front of the value were holding the pass, and one of them still is: the carrier is
out of striking range of the run 41-62% of the time, which is
`SimTouch.strike_range` saying he is facing the wrong way. A value knob cannot
reach a candidate that is never generated, and this project has now been caught by
that three times.

**(11) is built.** `SPACE_TOLERANCE` is 1.8 and the measurement that found it is in
`docs/STATUS.md`, "What the pass model said about the balls it played": the through
ball's `struck` read 0.72 against a pass to feet's 0.90, and the model priced the
balls it played at 0.29 while 65% of them arrived.

**(13) is the counterweight `TERRITORY` is missing**, and the burst has been
waiting on the same thing since it was written. `loss` says what the ball is worth
to the opponent where they win it and nothing about what shape the side is in when
they do. A long ball forward and a short ball square are lost in the same currency,
so the only thing holding the engine back from hitting the long one is `success`.
`docs/STATUS.md`, "Passing forward, and the term that was missing", is the
measurement: territory has to stay small because this does not exist. It is a
second-order term on every candidate, so it wants care -- see the burst's own note
in `_add_dribbles`, which declines to paper it over with a coefficient.

**(12) is a question, not a finding.** Nothing has been checked. Perception gates
what a player knows, and an option outside it can never be generated — which
would look exactly like a player ignoring an obvious ball.

## Keeping the ball without spending a body

`docs/STATUS.md`, "Support is an angle problem", measured five positional attempts
at improving retention. All five traded chance creation away at one for one or
worse, because the sum of where the players are is conserved: a man made available
to receive is a man not stretching the defence.

The mechanics that create retention without spending a body are individual, are
listed in `PLAN.md`, and do not exist yet:

- **Shielding** — holding a defender off, so a carry under pressure is a real
  option. The engine also cannot currently tell a man shielding the ball from a man
  running with it, and their touch frequencies are very different.
- **Drawing a foul.**
- **Beating a man.**

This is where the retention work should go next.

## Answers to the keeper's one-on-one

`SimKeeper._one_on_one` is priced straight into `expected_goals`, which counts the
keeper as a body in the shooting line, so the engine's answer when it fires is to
not shoot. The attacking answers do not exist: the chip, the ball round him, the
square pass across the face of an empty goal.

## Instruments that tie a decision to what came of it

Four proposals from one question: how to see the *causal* link between a decision
and an outcome, rather than turning a number and hoping.

All but one are built, all in `docs/DIAGNOSTICS.md`. `--ablate` covers the links
between the constant and the pick. `SimContext.possession_id` and "What became of the
ball" cover the join from a touch to what came of it. "Chains" walks four intended
chains link by link and `./run.sh chains --against` diffs them across a change, and
"The coin the softmax tossed" separates what a decision caused from what it merely
sat beside.

| | Proposal | Where | Goals |
|---|---|---|---|
| 19 | Paired-run contrast | `tools/headless_main.gd` | - |

**19 — paired-run contrast.** `contrast --seed 7 --set SimDecision.TERRITORY=0.75`,
and the weakest of the four despite looking like the obvious one. Two runs of one seed
diverge into different football within seconds of the first different decision, so the
diff measures a different match rather than the knob. Its one honest output is the
divergence tick: a knob that never diverges is dead, and that is worth five seconds.
Take the quantity off `--ablate` or off `Chains` instead, across several seeds.

## The break on the regain

Half of everything won was given straight back. Measured over three seeds at ten
minutes: **48-53% of regains still have the ball after three seconds**, 64-68% of
all spells end intercepted or picked off loose against 7-10% tackled, and the
possessions that end `picked off loose` last 2.3 s and contain 0.4-0.7 passes.
The first touch after winning it clean is a pass 79% of the time.

**20a, 20b, 20c and 20d are all done, and three of the four answers were not the
ones expected.** `docs/STATUS.md`, "A run a turnover ended is not a run he
finished", has the numbers. In short:

- **20a** is built: `The two seconds after a regain`, in `tools/diagnostics.gd`,
  with the eligibility gate counted in `SimOffBall._sample_regain` and the window
  carried onto the last line of `Did he have a safe pass?`. Every row is a pair,
  the window against the rest of the match, because a row on its own cannot say
  the window is special.
- **20b** went in. Not for the reason it was proposed — the rest cooldown turned
  out to be a tax the whole match pays, not one the counter pays — but because
  the mechanism underneath it was exactly as described: a run a turnover ended
  had served 52% of its window and was charged all of `REST_SECONDS`. `_expire`
  now charges that share. Men considered in the window 2.84 to 3.56, runs in
  behind 36 to 58 on seed 7, and `break_bias` went from flipping 0.0% of its
  decisions to 2.3%.
- **20c** needs nothing. `break_on` means 0.41-0.44 over the 18-21% of decisions
  taken inside the window, with the opposition line priced at 1.70x and the
  distribution spread across the whole range. The input is healthy; the option is
  what is rare.
- **20d** needs nothing either, and its premise was wrong. `secure` reads
  1.33-1.36x across the window rather than 1.7x, because `break_on` cancels it as
  the counter comes on, which is the mechanic doing exactly what it says.

**What is left is the carrier, and it is 8b.** A runner in behind now exists in
449 decisions over five seeds against 306 before, and a through ball is offered in
214 of them. The run half is answered and the pass half is not: `received` on a
run begun in the window is 4-14%, and a run in behind holds 27% of the softmax at
its best moment. That is `_shortlist` and what a ball in behind is worth once it
is on the list.

**What not to do: raise `BREAK_BIAS`.** It is 2.6, and it loses to `success`
rather than to its own size. A bigger multiplier on an option that is rarely
generated is the fix this whole set of instruments exists to prevent.

## Open owner questions

- Is there a skill difference between the two teams in the main scene game?
  Partly answered. `match_view_3d.QUALITY_LADDER` walks 0.6 v 0.6, 1.0 v 1.0 and
  1.0 v 0.6 across a session, so the sides genuinely differ on the third rung.
  Measured on the numbers, quality reads clearly in ball control — first-touch
  quality 0.15 / 0.33 / 0.49 at squad quality 0.2 / 0.6 / 1.0, and a 1.0 side beat
  a 0.2 one 3-0 in ten minutes — and not at all in chance creation, where shots
  are noise-dominated across seeds. What is still unchecked is the part only the
  owner can check: whether the better side *looks* better on the grass.

## Order

By how wrong the match looks without it, cheapest-first within that. This is a
re-sort: the list used to be ordered by which items raised goals per match, which
is the old approach and put the most visible defects last.

1. **5** — blocks that cost the shooter, a keeper who narrows the angle, and
   defenders who do not let a carrier walk to the six-yard line. The engine gets
   into the penalty area about four times as often as football does, and once
   there nothing much resists. That is the largest single thing an eye watching a
   match would name, and it is deep defensive behaviour that is simply absent.
2. **3** — parry versus hold. About a third of shots are second attempts within
   four seconds of the last, so a scramble that football sees occasionally is the
   normal way this engine finishes an attack. Visible on screen every time.
3. **Shielding, drawing the foul, beating a man** — the retention answer, and
   three individual behaviours a viewer can see and name. `docs/STATUS.md`,
   "Support is an angle problem", is the measurement that says positioning cannot
   substitute for them.
4. **8b** — half done: the receiver's carry is priced, the map is not. What is
   left of it is a multi-step expected threat, and the cheaper thing in front of
   it is the carrier turning to face a run he cannot currently reach.
5. ~~**20** — the break on the regain.~~ Done, and it turned into 8b: the men now
   run, and the ball still does not go to them.
6. **10, 11, 12** — small passing work. Cheap, and worth taking whenever one of
   the above is blocked or waiting on the owner. **11 is done.**
6. **2** — the two things `expected_goals` is still blind to. Real, but a
   valuation correction rather than a behaviour, so almost nothing about it is
   visible by eye.
7. **14, 15** — the attribute bookkeeping. Nothing a viewer can see, and neither
   costs more than an afternoon, but (15) is a squad the player pays for and does
   not get and (14) is two attributes being charged for and never delivered.

**19 sits outside this order.** It is an instrument rather than a behaviour, so it
moves nothing on the grass. Worth taking whenever a change is about to be judged
by whether an outcome moved.

**5** and **3** are expected to cost goals, and the compressed match is already
short of them. That is a band move to report, not a reason to reorder.
