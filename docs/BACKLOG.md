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
| 16 | Where do the goal-bound shots go? | `SimReferee._track_shot` | + |

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

**(16) is a hole in the accounting, and it caps the compressed match.** Measured
on seed 7 at `--urgency 1`: 23 shots, about 18 of them on target, 5 saves, 3
goals. Ten shots the forecast had crossing the frame ended as neither. Two
candidate causes and they want opposite work. `SimReferee._track_shot` latches
`on_target` the first tick the shared forecast crosses the plane, so a ball that
curls or drops away afterwards is still counted — in which case the instrument
overstates and the real accuracy is lower. Or bodies in a crowded area are
eating them, in which case it is `blocked` that is undercounted, since that flag
is only set when a non-keeper touches a shot that was *not* on target. The
cheapest first move is to record the shot's actual fate at the moment it dies
rather than inferring it. `docs/STATUS.md`, "the compressed match's scoring
fit", is why it matters: with the keeper cranked to a fifth of his reach, three
quarters of goal-bound shots still do not go in, so whatever this is, it is now
the largest single thing between the engine and a goal.

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
| 8b | Price a ball played in behind as a man arriving, not as a landing spot | `SimValueField.xt_at` | + |
| 10 | The third man | `SimPatterns` | + |
| 11 | Separate a ball into space from a ball to feet | `SimDecision.pass_tolerance` | + |
| 12 | Check the passer can perceive the option at all | `SimPerception` | ? |
| 13 | What losing it costs the shape, not just the ball | `SimDecision.score_of` | - |

**(8b) is the largest of these, and it is the residue of a job half done.**
`_arrival_gain` is built and credits a pass with the threat the receiver builds
carrying it on. What remains is that expected threat itself is single-step: it
sees where the *ball* stops, so a ball played in behind is priced as its landing
spot on the map rather than as a man running onto it with the defence turned.
Until that is priced, the engine keeps preferring the safe square ball.
`possession_value` patches the same hole from the other side, and its
`TERRITORY` tilt now patches the flat map underneath it.

**(11): the flag half exists.** `_pass_success` takes an `into_space` argument and
uses it to change how arrival is judged, but the striking tolerance is
`pass_tolerance(distance) = 2.0 + distance * 0.06` — distance only. A ball that
must arrive in a runner's stride and a ball to a standing man's feet are held to
the same standard.

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
4. **8b** — pricing a ball played in behind as a man arriving rather than a
   landing spot. The largest job here, and the one that decides whether the
   engine ever plays a forward pass that looks like a footballer's idea.
5. **10, 11, 12** — small passing work. Cheap, and worth taking whenever one of
   the above is blocked or waiting on the owner.
6. **2** — the two things `expected_goals` is still blind to. Real, but a
   valuation correction rather than a behaviour, so almost nothing about it is
   visible by eye.
7. **14, 15** — the attribute bookkeeping. Nothing a viewer can see, and neither
   costs more than an afternoon, but (15) is a squad the player pays for and does
   not get and (14) is two attributes being charged for and never delivered.

**5** and **3** are expected to cost goals, and the compressed match is already
short of them. That is a band move to report, not a reason to reorder.
