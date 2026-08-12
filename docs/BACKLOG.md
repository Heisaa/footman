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
| 2 | Let `expected_goals` see the three things it is blind to | `SimDecision.expected_goals` | - |
| 3 | Parry versus hold — the rebound cascade | `SimKeeper` | - |
| 4 | The in-box pass backwards the owner watched happen | `SimDecision._add_passes` | + |
| 5 | Blocks that cost the shooter, a keeper who narrows the angle | `SimKeeper`, `SimDuel` | - |

**(2) is the subtle one, and double-counting is the trap.** `aim_sigma` prices
skill, pressure, running speed, distance, composure, body facing and fatigue.
`expected_goals` prices distance, angle, finishing, pressure, composure and
blockers. Four of those appear in both, so multiplying expected goals by the
execution accuracy would count them twice. Add only the three the value model
cannot see: **shooting while running fast** (`speed_ratio` in `aim_sigma`), **body
facing** (`SimTouch.facing_penalty`) and **fatigue**. A player sprinting across
the box or turning away from goal prices a shot the same as one set and balanced,
and should not.

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
  Unchecked.

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
6. **2** — the three things `expected_goals` is blind to. Real, but a valuation
   correction rather than a behaviour, so almost nothing about it is visible by
   eye.

**5** and **3** are expected to cost goals, and the compressed match is already
short of them. That is a band move to report, not a reason to reorder.
