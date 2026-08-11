# Open decisions

`PLAN.md` §0 says anything marked `[DECIDE]` should be surfaced to the project
owner rather than resolved silently. This file surfaces them.

Each has a default in force so the build could continue. None is baked in
anywhere that would make changing it expensive — the "where it lives" column is
the one place to change.

| # | Question (`PLAN.md` §12) | Default in force | Why | Where it lives |
|---|---|---|---|---|
| 1 | Squad size for the prototype phases | **Eleven-a-side throughout** | Six-a-side is supported (`--small` on any headless command, `SimPitch.small_sided`, the `6aside` formation) but the §11 validation bands are all specified for eleven-a-side, so tuning against them needs eleven. Six-a-side stayed useful as a fast behaviour check. | `SimRunner.Options.small_sided` |
| 2 | Whether your own players' attributes become fully known | **Converge to a narrow band, never to a number** (the plan's own recommendation) | It is the single biggest lever against optimisation-brain, and a number would undo it. | Phase 8, scout-report generator — not yet built |
| 3 | Run length: one season or up to three | **Up to three, escalating** | Assumed for Phase 10's structure. Affects how much training and cohesion matter. | Phase 10 — not yet built |
| 4 | Whether the player can watch at 1x at all | **Both, with punctuated as the default** (the plan's own recommendation) | The 1x path already works: one tick per frame costs about 0.25 ms, which is 1.5% of a 16.7 ms frame. There is no performance reason to withhold it. | `presentation/match_view_2d.gd` |
| 5 | Injury model depth | **Not yet decided; nothing implemented** | Phase 9 territory. The sim already tracks per-player fatigue and a `recovery_ticks` knock-down, so either model can be built on what exists. | — |
| 6 | Whether tactical patterns are per-run unlocks, persistent progression, or both | **Not yet decided** | `SimPattern` is data-driven and lives on the tactical plan, so it can be granted from either layer. | `sim/pattern.gd`, Phase 10 |

## Amendments made to PLAN.md

The plan is the specification, so changes to it are listed here rather than
buried in a diff. These were made with the owner's agreement after the first
full validation run showed the batch sizes were impractical.

| Section | Was | Now | Why |
|---|---|---|---|
| §11 | "across two hundred matches" | Two tiers: a 40-match gate and a 200-match acceptance run, with a per-metric note on which converges when | A serial 200-match run is five and a half hours. A gate nobody runs is not a gate. The arithmetic for the split is in the new §11.1. |
| §11.1 (new) | — | Sample-size reasoning, and a requirement that batches run in parallel | The score-draw rate is a proportion near 0.24, so it needs ~200 matches; everything else settles by 40. Stating that stops the two being confused. |
| §11 performance table | "as fast as the implementation allows" | The measured figure, ~0.25 ms per tick / ~100 s per match, plus what follows from it | The plan asked for this to be measured in Phase 4 and the strategy set from the real number. It has been. |
| §10 Phase 4 exit | "two hundred simulated matches fall within the bands" | Same, but named as the acceptance run and cross-referenced | Unchanged in substance. |
| §10 Phase 5 exit | "across two hundred matches each" | Forty per plan | It is a comparison of two means, not an estimate of a rare event. A tactical difference needing 200 matches to detect is not one a player would ever feel. |
| §2.5 calibration | "several thousand full-fidelity matches" | A grid of conditions, a few hundred per cell, framed as an overnight parallel job | "Several thousand" serial is days. The fit needs coverage of the condition space more than depth at any one point. |

Nothing about the bands themselves changed — the acceptance criteria are the
same numbers the plan always specified.

### Second amendment: validate for speed, tune late

Made at the owner's direction. The simulation is expected to change substantially
before it settles, so fitting coefficients against the current decision function
is work that will be thrown away. What matters now is whether the *concepts*
work, checked in the shortest time that can still tell.

| Section | Was | Now | Why |
|---|---|---|---|
| §11 | One table of target bands, all pass/fail | Two layers: wide **sanity ranges** that decide pass/fail, and the original **tuning targets**, reported but advisory | "Is this still football?" and "are these numbers right?" are different questions and become urgent at different times. The sanity ranges catch the failures that actually happen; the tuning table catches drift. |
| §11.1 | Gate 40 matches, acceptance 200 | **Smoke** 6 × 12 min reduced fidelity, **gate** 6 × 90 min, **acceptance** 200 × 90 min `--strict` | The gate was ten minutes, so it was run once a day. It is now three, and there is a sub-minute check above it that can be run on every change. |
| §11.1 | Counts assumed to be per-match | Every count normalised **per 90 minutes** from ticks actually played | Makes short matches a legitimate measurement of a rate, which is what unlocks the smoke tier. Not a measurement of fatigue — hence the full-length gate. |
| §11.1 | "Converges by" was prose | Per-band `min_n` in the runner; undersampled metrics print `noisy at n=6` and are excluded from the verdict | What makes a six-match gate honest rather than merely fast. It does not claim to have measured the score-draw rate. |
| §11.1.1 (new) | — | The **tuning freeze**: the tuning table becomes pass/fail at the end of Phase 8, not before | Every hour spent on goals-per-match before the shape settles is spent twice, and it blocks Phases 5–8 on the wrong thing. |
| §11.2 (new) | — | The cost levers, ranked, with what was measured for each | Records why the gate is six matches and why the tick rate was *not* halved (at 30 Hz a 30 m/s ball moves a metre a tick against a 1.2 m control range). |
| §10 Phase 4 exit | The 200-match acceptance run | The sanity ranges, plus the measured per-match cost; the tuning table deferred to the freeze | Follows from the above. |
| §10 Phase 5 exit | Forty matches per plan | A dozen routine, forty when confidence is wanted | The \|t\| > 3 threshold is *harder* to clear at a small sample, so a pass at twelve is a real result. |
| §2.5 tier 2 | "decision cadence halved, value field sampled at fewer points" | Every decision cadence strided; physical layer never strided; used for the smoke run as well as fast-forward | The tier existed for fast-forwarding only. Making it a validation tier is free, and it is worth 15–20%. |

Verified no-op: the cadence changes were checked against golden digests at full
fidelity before and after, and are byte-identical. What is *not* preserved is
behaviour at reduced fidelity — that tier now genuinely simulates differently,
which is the point of it.

**The golden baseline was re-recorded.** It had gone stale against sim edits made
before this work started (`decision.gd`, `keeper.gd` and `movement.gd` were all
newer than `tests/golden.json`). The new baseline is the engine as it stands.

### Third amendment: rolling resistance, and wetness separated from grass length

Made at the owner's direction, after they noticed that a slow ball kept rolling
for too long.

| Section | Was | Now | Why |
|---|---|---|---|
| §3.1 | Rolling resistance 0.5 m/s² dry | **1.0 m/s² dry** | 0.5 is a coefficient of rolling resistance of 0.05, nearer a bowling green than a pitch; a football on mown grass is 0.08–0.12. The tell was a ball rolling at walking pace taking four seconds and four metres to stop, and a ground pass struck at 10 m/s running 57 m. |
| §3.1 | 0.9 for "long or wet grass" | **Composed: 1.5 long grass, × 0.85 wet** | The two were sharing one branch and one constant, so a wet pitch *slowed* the ball. A greasy surface makes the ball run on faster; only the grass kills it. They now compose, and wet long grass still comes out slower than a dry mown pitch. |

The pass solver (`SimBallistics.ground_pass_speed`) reads the same constant, so
players strike ground passes harder to reach the same target and passing did not
need re-tuning. What moves is loose-ball behaviour: balls stop in play rather
than trickling on, interception windows shorten, and keeper distribution
shortens. **The golden baseline was re-recorded**, since ball physics changed by
intent.

### Fourth amendment: entertainment is the target, realism is the texture

Made at the owner's direction.

| Section | Was | Now | Why |
|---|---|---|---|
| §1 | Three pillars, no statement of what the simulation is *for* | An explicit statement that the goal is an entertaining game that feels somewhat realistic, and that entertainment wins where the two conflict | The depth exists to make matches surprising and worth watching, not to be accurate. Stating it stops "that isn't what real football does" being treated as an argument on its own. |
| §11.3 | "Two of these are entertainment targets" — goals and draws only, everything else honest to the sport | The whole tuning table is an entertainment target; the **sanity ranges** are the floor that keeps it recognisably football | The owner wants to keep moving toward more goals and a higher tempo rather than converge on real figures. The two-layer split already existed and carries the distinction cleanly. |

The sanity ranges are unchanged and still decide pass/fail.

### Fifth amendment: the register is the British football comic

Made at the owner's direction. The plan said what the game should *look* like
(§9: Sokpop, Mii, a toy football set) and what it should *be* like as a
simulation (§1: entertaining first), but nothing said what the people in it are
like. "Cute and chunky" is satisfied perfectly by eleven interchangeable smiling
men, which is not the game.

| Section | Was | Now | Why |
|---|---|---|---|
| §1 | Three pillars and the entertainment statement, with no tonal reference | A paragraph naming ***Hot-Shot Hamish*** and ***Mighty Mouse*** — the *Scorcher* / *Tiger* / *Roy of the Rovers* strips — and eighties/nineties British football as the register | It is pillar 3 ("toys, not spreadsheets") pointed at people rather than at objects, and it was the missing half. |
| §9 intro | Sokpop / Mii / Animal Crossing | Same, plus a note that those settle the shapes and §9.7 settles what the figures are *like* | The two references answer different questions and were being asked to share one line. |
| §9.7 (new) | — | Tone and register, as five specifications: archetypes not averages, the absurd played straight, big moments as animation over normal events, nicknames as identity, small club and hostile board | A mood board cannot be checked against; these can. |
| §6.5 | Dialogue mechanics only | Plus the voice: in character, in period, never commenting on its own jokes | The dressing room is where the register is most legible and most easily lost. |
| §14 | Five modelling references | Plus a tone section: the strips, their creators, *Roy of the Rovers* as season melodrama, and the period itself | Same reason the modelling references are listed — so the next person can go and look. |

**Nothing in `sim/` changes and no band moves.** §9.7 states the boundary
explicitly: the register governs presentation, naming, copy and character
generation, and governs nothing in the simulation. A keeper carried into the net
is an animation and a line in the event log played over a goal the engine scored
normally; it is not a rule that shots ignore keepers. §11's sanity ranges are the
same numbers they were.

Nothing was built for this — it is a specification change only. What it will
touch when it is built is Phase 6's appearance generation (widen it toward the
tails), Phase 8's dialogue, and wherever player names are rendered.

### Sixth amendment: the match clock is compressed, so a full match is watchable

Made at the owner's direction. A ninety-minute match at 1× took ninety minutes
of wall clock, which is the honest consequence of §2.3 — the presentation layer
advances the sim sixty steps a second — and it means nobody ever watches a whole
one. The two ways out are *Football Manager*'s highlights, which cut, and a
compressed clock, which does not. The owner chose the compressed clock: **a full
match, kick-off to full time, in about three minutes at 1× speed.**

| Section | Was | Now | Why |
|---|---|---|---|
| §2.3 | 1× viewing advances the sim 60 steps per second, so match time is wall-clock time | The match *clock* advances by `clock_rate` seconds per simulated second; the tick is still 1/60 s and 1× is still one tick per frame | The compression is in the clock, not the frame rate. Nothing about how a player moves changes, which is the entire point — see below. |
| §11 | Counting statistics normalised per ninety minutes from the tick count | Normalised from the match clock (`SimMatchStats.clock`) | Under compression the two differ by `clock_rate`, and it is the clock the rate has to be per. Identical for an uncompressed match. |
| §6.3 | A director pauses at five to eight pivots across the match | Open again — a three-minute match may not need punctuating at all | Not resolved here. Flagged because the compression removes most of the problem §6.3 exists to solve. |

**What the compression does not do is speed anything up.** `clock_rate` is read
in exactly one place, `SimMatch._advance_clock`, and nothing else in the sim
knows it exists. Players still run at 6–8 m/s, the ball still obeys the same
drag, the tick is still a sixtieth. A compressed match is therefore not a
fast-forwarded one: it is a *shorter* one wearing a ninety-minute scoreboard, and
it contains proportionally fewer events. At `clock_rate = 30` a match is three
minutes of football, and three minutes of this engine currently produces about
0.6 goals against the 2.7 a football match wants.

Closing that gap is the retuning the owner accepted when choosing this
direction, and the lever is **space, not speed**. A full pitch played at 30×
would read as a video being scrubbed — the gait model, turn rates and ball roll
are all calibrated against real metres per second. A *smaller* pitch at ordinary
human speed reads as football in a tight space, because that is what it is, and
every metre taken off the pitch raises events per second without touching a
single thing the eye is calibrated to. That is what the six-a-side demo is for.

**Eleven-a-side on a regulation pitch remains the standard** (decision 1 is
unchanged). The compressed six-a-side match is a demo to be looked at, not a
change of default: `./run.sh demo`. `clock_rate` defaults to 1.0 everywhere, so
the goldens, the bands and every existing run are untouched until somebody asks
for compression explicitly.

## Match length as a player setting, and the knobs that decide goals per match

Recorded at the owner's request on 2026-08-10, to be measured properly once the
simulation stops changing shape. **Nothing here has been verified by a batch.**
The intended feature is a player-facing setting for how long a match takes in
wall-clock time — three minutes, ten minutes, perhaps more — with the match
statistics landing in roughly the same range whichever is chosen. **Goals per
match is the one that has to hold**; the rest can drift.

### The arithmetic that makes this hard

A match contains `5400 / clock_rate` seconds of football, and

```
goals per match  =  goals per second of football  x  5400 / clock_rate
```

So holding goals per match constant while the player changes the length
requires **goals per second of football to scale linearly with `clock_rate`**.
Nothing in the engine does that today, which means goals per match currently
varies as `1 / clock_rate`: the ten-minute setting would produce about 3.3 times
the goals of the three-minute one, from the same engine, with no bug anywhere.

There is a model for how to fix it already in the codebase, and it is worth
copying rather than reinventing. **Fatigue is already length-invariant.**
`SimPlayer._update_stamina` scales drain and recovery by `clock_rate`, so total
drain over a match is `per-second drain x clock_rate x 5400 / clock_rate` — the
rate cancels, and a side is equally tired at full time whatever the setting.
Every knob below needs the same treatment or a deliberate decision that it does
not.

Restart dead time is invariant too, though by a different route:
`SimSetPiece._compress` floors the delays, and above `clock_rate` ≈ 2.5 the
floors bind, so both the three- and ten-minute settings get the same real dead
time per restart and the same number of restarts per second of football. Any
setting longer than about thirty-six minutes leaves that regime and the share
changes.

### What can and cannot be invariant

Worth being explicit, because holding goals constant *forces* other things to
move. If two settings differ by 3.3x in seconds of football but score the same,
then goals per second of football differ by 3.3x, and so does the texture: the
short setting is necessarily more end-to-end, with more shots and fewer passes
per minute of football. That is a consequence of the requirement, not a defect.

- **Should hold:** goals per match, the scoreline distribution, cards, the
  fatigue arc, the share of the match that is dead time.
- **Cannot hold:** passes per match, possession sequences per match, distance
  covered, and how densely anything happens second to second.
- **Must never move with length:** the physical layer. Player speed,
  acceleration, turn rate, ball drag and bounce, the 1/60 tick. The whole
  compression design rests on a compressed match not being a sped-up one, and
  the animation is calibrated against real metres per second.

### Where the engine sits today

Post the `SHOT_AIM_BASE` fix, measured across three seeds at ten minutes:
about 0.0056 goals per second of football. Solving the identity above for 2.7
goals per match gives `clock_rate` ≈ 11, or **a match of about eight minutes**.
So the engine as it stands is roughly calibrated for an eight-minute game: the
three-minute setting needs about 2.7x more per second, and a ten-minute setting
would need slightly less than it currently produces.

### The knobs, grouped by what they do

Chance creation — how often a shooting position happens at all:

| Knob | Where |
|---|---|
| Pitch size | `SimPitch.scaled`, `SimRunner.Options.pitch_scale`. Measured: raises shots steeply, total xG barely. Converts quality into quantity. |
| Value of keeping the ball vs progressing | `SimDecision.POSSESSION_VALUE` |
| Expected threat scale, and its single-step blindness | `SimValueField.xt_at` |
| Off-ball offers: quotas, commitment windows, run kinds | `SimOffBall` |
| Pass accuracy bases (0.055 ground, 0.085 lofted) | `SimTouch.aim_sigma` callers |
| Defensive effectiveness: pressure, recovery runs, duels, lanes | `SimContext.pressure_on`, `SimMovement._recovery_point`, `SimDuel`, `SimDecision._lane_survival` |
| Dead time | `SimSetPiece._compress` and its three floors |

Chance conversion — whether a shooting position becomes a goal:

| Knob | Where |
|---|---|
| Shot aim error | `SimTouch.SHOT_AIM_BASE`, plus the 1.45 first-time multiplier and the 1.6 elevation weighting in `SimTouch.shot` |
| Expected goals calibration (1.35, `exp(-0.11 d)`, angle power 0.7, blocker 0.72) | `SimDecision.expected_goals` |
| Shot generation floor (0.025) and range cap (38 m) | `SimDecision._add_shot` |
| What a shot is worth over the goal itself | the `bias` in `SimDecision._add_shot` |
| Keeper save rate, positioning, the one-on-one | `SimKeeper` |
| Parry versus hold, which drives the rebound cascade | `SimKeeper` — currently about a third of all shots are second attempts |

### The shape the solution should take

Do not scatter length-dependent multipliers through these files. The tractable
version is **one scalar derived from `clock_rate`**, tuned once at a reference
length, that drives the handful of knobs above — the same way `clock_rate`
already drives fatigue from a single field. That has a consequence for how the
knobs should be organised *now*: they want to be named constants reachable from
one place rather than literals buried in expressions, which several of them
currently are.

### How to measure it, when the time comes

Not from diagnostics — this is a distribution question. Batches at two or more
settings, compared on goals per match. Per `PLAN.md` §11.1, goals per match
settles by about forty matches; the score-draw rate needs two hundred, so if
scoreline *shape* is to be held invariant too, that is the sample size that
decides it. `./run.sh pbatch --clock-rate R --keep` at each setting, then
`./run.sh compare`. Owner's runs, at the tuning freeze.

## Proposed shooting and passing work, not yet built

Collected 2026-08-10 so the ideas survive the session. One of these has been
built; the rest are proposals with a location and a reason, and none has been
measured. The `+` / `-` column is the expected direction on goals per match,
which matters because the compressed match is short of them: anything marked `-`
is correct football that makes the immediate target worse, and the ordering at
the bottom takes that into account.

### Shooting

| | Proposal | Where | Goals |
|---|---|---|---|
| 1 | **Done.** Shot aim error brought beside the pass, 0.28 → 0.08 | `SimTouch.SHOT_AIM_BASE` | + |
| 2 | Let `expected_goals` see the three things it is blind to | `SimDecision.expected_goals` | - |
| 3 | Parry versus hold — the rebound cascade | `SimKeeper` | - |
| 4 | The in-box pass backwards the owner watched happen | `SimDecision._add_passes` | + |
| 5 | Blocks that cost the shooter, a keeper who narrows the angle | `SimKeeper`, `SimDuel` | - |

**(2) is the subtle one and the double-counting is the trap.** `aim_sigma`
prices skill, pressure, running speed, distance, composure, body facing and
fatigue. `expected_goals` prices distance, angle, finishing, pressure, composure
and blockers. Four of those appear in both, so multiplying expected goals by the
execution accuracy would count them twice and is wrong. Only the three the value
model cannot currently see should be added: **shooting while running fast**
(`speed_ratio` in `aim_sigma`), **body facing** (`SimTouch.facing_penalty`) and
**fatigue**. A player sprinting across the box or turning away from goal should
not price a shot the same as one set and balanced, and today he does.

**(3) surfaced as a consequence of the fix rather than a proposal.** With shots
now reaching the target, about a third of all of them are second attempts within
four seconds of the last — the keeper parries, the rebound falls to an attacker,
he strikes again. Real football has rebounds but not at that rate. It was
invisible before because almost nothing was on target to parry.

**(4) could not be reproduced at volume**: across three seeds it is 1 of 56
touches in the penalty area, against 34 struck and 12 carried. Either it is
rarer than it looked, or it is happening just outside the area where the
diagnostic block would not count it. Worth a second look with the owner's seed
rather than a general hunt.

### Passing

| | Proposal | Where | Goals |
|---|---|---|---|
| 6 | Pass to the run, not to the velocity | `SimDecision._add_passes:271` | + |
| 7 | The receiver's call: a committed run bids for the ball | `SimOffBall`, `SimDecision._add_passes` | + |
| 8 | Value a pass by where the receiver *arrives*, not where the ball stops | `SimValueField.xt_at` | + |
| 9 | The give-and-go | `SimDecision`, `SimOffBall` | + |
| 10 | The third man | `SimPatterns` | + |
| 11 | Separate a ball into space from a ball to feet | `SimDecision.pass_tolerance` | + |
| 12 | Check the passer can perceive the option at all | `SimPerception` | ? |

**(6) is the owner's idea, and the information already exists unused.**
`SimOffBall` computes each player's committed destination and exposes it as
`point_for`; the movement layer reads it and the pass generator does not.
`_add_passes` instead aims at `believed + mate.vel * travel * 0.6` — dead
reckoning on present velocity. Two failures follow. A player who has just
committed to a run has not accelerated yet, so `mate.vel` is small and the ball
is played to his feet: the through ball is mispriced precisely because the
runner is still turning when it should be struck. And the `0.6` under-leads by
design, so the ball arrives behind him even when the run is visible.

**(7) is the other half of the same idea** — not "he can see where I am going"
but "I am demanding it". A player inside his commitment window raises the bias
on the pass candidate that serves him. This is the shape `PLAN.md` §5.1 requires
of everything tactical: a modifier on a value the decision layer was going to
use anyway, never a behaviour switch. It also makes an ignored run cost
something, which is what would make runs mean anything.

**(8) is the known single-step limitation and the largest of these.** Expected
threat sees where the *ball* ends up, so a ball played in behind is priced as
its landing spot on the map rather than as a man running onto it with the
defence turned. Until that is priced the engine will keep preferring the safe
square ball, and (6) and (7) will feed it options it still declines.
`POSSESSION_VALUE` (0.013) exists to patch the same hole from the other side.

**(11): the flag half exists.** `_pass_success` takes an `into_space` argument
and uses it to change how arrival is judged, but the striking tolerance is
`pass_tolerance(distance) = 2.0 + distance * 0.06` — distance only. A ball that
must arrive in a runner's stride and a ball to a standing man's feet are held to
the same standard.

**(12) is a question, not a finding.** Nothing has been checked. But perception
gates what a player knows, and an option outside it can never be generated —
which would look exactly like a player ignoring an obvious ball.

### Order

Given the compressed match is short of goals, and cheapest-first within that:
**6, 7, 9** — the owner's idea and the cheap combination play, all `+`, all
small. Then **8**, which is the real unlock and the largest job. Then **11** and
**12**, both small and both possibly explaining more than they look. **2, 3, 5**
are correct football that costs goals and should wait until the attack produces;
**5** in particular would make the current match strictly worse.

## Deviations from the plan worth flagging

**Stamina drain is scaled by the stamina attribute, not the work-rate
attribute.** `PLAN.md` §3.2 says drain is "scaled by the work-rate attribute",
but §8 lists both `stamina` and `work_rate` as separate attributes. Reading work
rate as *how much a player chooses to run* and stamina as *how well they cope
with it* makes both attributes do something: work rate scales the movement
layer's willingness to cover ground, stamina scales the drain. If the intent was
literal, it is a one-line change in `SimPlayer._update_stamina`.

**Set pieces snap players into position for kickoffs and penalties only.**
Everywhere else players jog to their restart positions in simulated time, which
is what §3.5 describes. Kickoffs and penalties would otherwise burn a minute of
match clock walking.

**Chasers approach a carrier at an angle, which §4.3 does not mention.**
§4.3 gives the chaser an interception point and leaves the approach implicit, and
the implicit answer is a straight line. Against a man in possession a straight
line is a tailgate: the ball sits two to four metres in front of him, so the line
to it goes through him, and the chaser spends the carry a metre off his back
where §3.3's challenge model is at its weakest and its most foul-prone. Measured
on the positional trace, the nearest defender to a running carrier was behind him
87% of the time at 1.1 m, in unbroken spells averaging 3.3 s.

`SimMovement._recovery_point` adds the missing term: while a chaser is behind a
moving carrier, his target steps sideways off the ball's line by enough to run
past a body, closing again over the last few metres so the run still ends on the
ball. It is a weight on the target the layer already computes, not a mode, and it
fades to nothing the moment he is level. The measured split moves to roughly half
behind and half alongside, with slipstream spells under a second.

Two things about it are deliberate and worth not undoing. It aims *beside* the
ball, never in front of the carrier: standing in his path is a much stronger
defensive act — `SimContext` weights pressure from an opponent in front at up to
three times one behind — and an earlier cut that did so halved the shots in a
match. And it carries a pace allowance (`RECOVERY_PACE`), because the way round
is longer than the way through; without it the chaser never completes the
manoeuvre and the trails come straight back.

The consequence is that a carry can now be ended by a defender who started
behind, which is what §3.3 wanted, and the ball changes hands considerably more
often than it did. Goals and shots fall with it, and they should: the attacking
answers to a defender who gets across — shielding that actually holds him off,
drawing the foul, the give-and-go, the pass round the presser — are not built
yet. The numbers come back when those do, not by trimming this.

`RECOVERY_PACE` and `RECOVERY_RADIUS` were nonetheless trimmed once (0.92 to
0.85, 7.0 to 5.0) while chasing exactly that shot count. Both settings measure
the same on the chase diagnostic, so nothing was lost, but the first values are
recorded here because the reason for moving them was a bad one and the owner may
want them back on watching a match.

**Body orientation costs accuracy on every touch that is aimed, not only on the
pass.** §3.3's error table lists body orientation against the ground pass and the
lofted pass and nowhere else. `SimTouch.facing_penalty` is charged on the dribble
touch and the first touch as well, because the reason the pass is harder is not a
fact about passing — it is a fact about having to play a ball you are not looking
at, and it applies with at least as much force to knocking the ball back across
yourself or to taking a ball down and turning with it in one movement.

The shot, the header, the clearance and the tackler's poke are deliberately left
out. A shot is struck at a goal the player has usually turned to face, and the
first-time flag already prices the awkward strike; a header is an aerial contest
whose difficulty §3.3 puts in the height model; a clearance and a poke are wide
by nature and the plan says so.

Two properties of the model are load-bearing. It is charged through `aim_sigma`,
so the decision layer pays for it too — `execution_accuracy` is handed the *line*
of the pass rather than only its length, and the eight dribble probes are scored
through `facing_control`. A version that only perturbed the struck ball would
show up as passes going astray and never as a player choosing the option he can
see, which is the more visible half of the behaviour: measured on seed 7, the
share of passes played back past square fell from 40% to 29% and the share
played into the passer's own eyeline rose from 33% to 47%. And a player standing
still pays a fixed share of the cost rather than none of it
(`FACING_STATIC_SHARE`), because the engine has no notion of taking a moment to
turn; that fraction is the price of the second he does not spend, and without it
the whole mechanic vanishes the instant a carrier slows down.

**Phase ordering was compressed at the module level.** The keeper, referee and
set-piece modules were written earlier than `PLAN.md` §10 places them, because
the match loop cannot run a full match without them and stubbing them would have
meant writing them twice. The *validation* order was kept: the Phase 1 and 2
criteria are tested independently of them (`TestBall`, `TestTouch`,
`TestMatch._no_ball_swarming`) and the §11 statistical bands remain the Phase 4
gate.

## Design calls made by the owner during the build

**Goals and draws are entertainment targets, not simulation targets.** The owner
asked for slightly more goals than real football and slightly fewer draws, on
the grounds that the matches should be entertaining. `PLAN.md` §11 now reads
2.9–4.1 goals per match (real: 2.2–3.4) and 12–22% score draws (real: 20–28%),
with a new §11.0 recording why.

This is worth keeping straight, because the two dials now behave differently
from the rest of the table. If goals or draws drift, that is a design
conversation. If shots, passing, fouls, offsides, corners or distance drift, that
is a tuning bug — those stay honest to the sport. The band comments in
`tools/validation.gd` say so at the point of use.

**Animation is smooth, not stepped.** `PLAN.md` §10 Phase 6 asked for stepped
animation and the view quantised every pose to ten frames a second for a
stop-motion register. The owner watched it and asked for smooth motion instead,
so the pose layer now runs at the display's frame rate. §9.5 and Phase 6 are
amended to match.

The stepping is still there behind `--step-fps 10`, because the two looks are a
judgement call the owner may want to make again side by side. What made that
cheap to keep is that everything the pose layer measures over time — the gait's
cadence, the turn rate — is now stated in seconds rather than in stepped frames,
so one set of code drives both. Two of those measurements were leaning on the
ten-frame quantum as a filter and had to be restated as durations: the turn rate
is measured over a tenth of a second however many frames that takes, and smoothed
on a time constant rather than a per-frame fraction. Without that, sixty frames a
second re-creates exactly the per-tick facing noise that made the heads twitch.

**The run cycle lifts the knee and the foot.** The owner's word for the old one
was that the players slid their feet forward along the ground, and that is what
it was: the hips swung, the knee bent a little and on the wrong half of the
cycle, and the boot was welded flat to the shin, so each leg passed through as a
straight rod grazing the turf. Nothing on the figure ever left the ground.

`SimCharacterBuilder` now gives each leg an ankle pivot, and the cycle drives
three joints against the hip's pendulum: the knee folds hard just after toe-off
while the thigh is still trailing and extends again before the foot plants, a
smaller bend at mid-stance takes the body's weight, and the ankle points at
toe-off and lifts through the swing. The figure also rides up between footfalls
and sinks over the planted foot, which is the same three centimetres the bent
stance knee lifts the boot by — without it a run is performed on tiptoe.

**Three cameras, and they pan.** The view had twenty-one authored positions —
seven along the pitch by three across it — and cut to whichever sat nearest the
ball. The owner's complaint was that it switched far too much, and it did: a ball
played twenty metres sideways changed the shot, so the viewer spent the match
re-finding play. Cutting is the most violent thing a camera can do and it was
being spent on nothing.

It is now the rig a television match is shot on. Three fixed positions, all off
the *same* touchline — reversing the side would reverse the direction of play,
the one thing a viewer cannot be asked to re-learn mid-match — one on the halfway
line and one level with each penalty area, each panning and tilting to hold play.
`PLAN.md` §9.2 is amended for it, on two counts: the angle is no longer fixed
(35° at the middle of the pitch, swinging from about 25° on the far touchline to
55° on the near one), and neither is the field of view. A camera bolted to one
spot is three times further from the far touchline than the near one, so the lens
is solved every frame to hold a fixed frame width — a zoom, doing what a camera
operator does with the rocker and for the same reason: keeping a player the same
size on screen wherever play is.

Three numbers hold the cutting down, and the middle one is the one that did the
work. A minimum shot length stopped the flicker but left the camera sitting out
its minimum and cutting the instant it expired. A *commitment* delay is what
removed the twitch: play has to stay in the new camera's territory before the cut
is taken, so a ball that arrives in the final third and is cleared straight back
out is covered by the pan and costs nothing. The third is a wide hysteresis: the
ball has to reach 30 m to send the shot to a penalty-area camera, and come back
inside 22 m to bring it home.

With the commitment carrying it, the minimum turned out to be nearly inert —
dropping it from 8 s to 3 s moved the rate from 2.7 cuts a minute to 2.95 and the
median shot not at all, and the handful of short shots it let through were all
the halfway camera being passed through as play swept from one box to the other.
That is worth having: at 8 s the halfway shot was skipped in that sequence and
the cut went box to box, when what the eye wants is to follow it up the pitch.

The first cut of those two numbers — the edge of the box at 36 m, and 2.5 s of
commitment — was too slow, and the owner's word for it was that the box camera
took too long to arrive. It was arriving *after* the attack, which is the one
thing a cut must not do. The line moved out to 30 and the commitment down to 1 s,
and the cost was almost nothing: measured over twenty minutes of seed 11, 2.7
cuts a minute against 2.55, median shot 16 s either way. Earlier is not busier,
because what makes a cut land early is not the same as what makes one flicker.

The pan is deliberately not a cursor. The aim point chases the ball on a time
constant so the shot trails a fast ball and settles behind it, and both the
timers and the pan are in *simulated* seconds, so a match is shot the same way at
1x and at 8x. Two limits keep the frame on grass: the tilt stops 17 m into the
far half, and the pan 38 m along the pitch. Both are asymmetric on purpose —
panning towards the viewer or the middle only brings in more pitch, while the
other direction runs out of stadium and puts a band of empty backdrop across the
frame.

**Playing out of a challenge, and what happens after it.** The complaint was
that a carrier with a man coming from behind almost always stayed in the
challenge, and that a turnover simply reversed the roles into another one. The
cause was a single blind spot: `SimContext.pressure` weights an opponent behind
a player at 0.30 of one in front, deliberately and correctly, because pressure
means "how much of what I want to do is being taken away". Nothing else in the
engine asked "am I about to be tackled", so the carrier could not see the man on
his back at all. Measured on seed 7, 84% of his touches were another short carry
and 9% were passes.

The fix is a second field, `SimContext.challenge`, angle-neutral and scaled by
*relative* closing speed, anchored so that 1.0 means the duel model would let
him tackle you now. Off it hang the escape race in `SimDecision._add_dribbles`,
the knock past the man, the hold penalty and the carrier's own speed cap. The
carry now runs at 19-27% of challenged touches against 16-29% passes and 20-32%
knocks past the man.

**The regain window is a fact about the situation, not about an opponent.** It
sits alongside the challenge field rather than inside it because the man who has
just lost the ball is often momentarily still — he is carrying a recovery
penalty and a cooldown — so he reads as no threat while the pocket is still the
most crowded place on the pitch.

**Rejected: sprinting into support on a turnover.** The obvious answer to the
churn rate was that the man who wins the ball has nobody to give it to, because
his teammates amble into supporting positions at `SHAPE_SPEED`. Lifting that for
the ~1.5 s after a regain, scaled by distance to the ball, moved the churn rate
by nothing at all (45% and 39% against 38% and 36% without it) and cost 40% more
running — 2.4 km per striker in a ten-minute match. It is out. The churn that
remains is not the carrier's decision and not the supporting run; it is that a
regain is stamped wherever the ball is won, including on an isolated defender
with every option covered, and answering it needs the attacking mechanics that
are not built yet rather than a faster jog.

**A hold may not give up ground.** The owner watched a carrier collect the ball
near the halfway line, get chased, and run it back to his own extended goal line
without ever appearing to decide to. Nothing in the touch log or the §11 bands
could see it — every touch in the retreat is an ordinary carry, and retreating
with the ball is retaining the ball — so it was measured off the positional
trace instead: on seed 1 a spell of 22.6 m over six seconds with a man on him
94% of the time, and shorter versions of the same thing several times a match.

The cause was not the dribble probes, which price the ground they give up and
mostly do not take it. It was `HOLD`. Under a challenge it beats every other
candidate comfortably — its success is ~0.7 where a scored dribble into a
goal-side defender is ~0.05 — and `_execute` sends it down the fallback branch,
which plays a real two-metre touch in `_safe_direction`: forty percent forward,
plus straight away from the nearest man. With that man goal-side, which the
recovery run made the normal case, "away" is the carrier's own goal, and the
option scored as *keeping the ball where it is* walks it backwards, twelve
touches in a row, with nothing in the score sheet ever charged for the journey.

`_safe_direction` now strips the retreating component out of the shelter
direction, and plays square across the man — into whichever side has the pitch
for it — when he is directly goal-side. Dropping back with the ball is still
available in the eight scored probes and in a pass, which price it. Measured on
seeds 1, 3 and 7 at ten minutes, spells losing more than eight metres fell from
16/10/7 seconds of play to 3/2/5, and the longest from 22.6 m to 8.8 m. Shots on
seed 7 went 7 to 4 and touches in the box 40 to 26 — one ten-minute seed, so the
shot count means very little on its own, but the direction of it is real: a
carrier who could always shelter backwards was manufacturing time on the ball
that he had not earned.

`SimDiagnostics._giving_up_ground` prints the measurement, because nothing else
does and the first attempt at it — off the touch log, orientation read at full
time — got the sign wrong on every first-half touch and reported the engine's
forward carries as retreats.

**A dribble probe is charged where the touch would be lost.** The eight short
probes read their `loss` term at the carrier's own feet rather than at the point
he was knocking it to — the only candidate in the engine that did, with the
knock past the man twenty lines below it doing it correctly. The consequence was
not a wrong number but an absent one: the same loss for all eight directions, so
the risk term could not tell dribbling toward one's own goal from dribbling
toward the other one. In one's own half it is the only term that could. Expected
threat for the team in possession is flat back there — order 0.0002 against the
0.013 `POSSESSION_VALUE` adds for merely having the ball — while the threat
conceded on a turnover climbs steeply toward one's own box.

Measured across seeds 1, 3, 5, 7 and 11 at ten minutes, shots went from 4/2/4/4/11
to 2/10/3/19/6 — 25 to 40 in total, and 3 goals to 5. The seed-to-seed spread is
as wide as the shift, so five matches cannot tell it from noise; what can be said
is that it did not quieten the engine, and that it costs nothing where the value
field is steep and gives the attacking third bolder carries, because the threat
conceded by losing it thirty yards from the opponent's goal is near zero. Spells
losing eight metres or more ran 1/0/2/0/3 across the same seeds, so the retreat
the hold fix closed did not come back through this door.

It was found while explaining the retreat above and is unrelated to it: applied
on its own, before that fix, it moved the retreat numbers hardly at all. The
escape geometry swings a probe's success by twenty to fifty times across the
eight directions, and a few percent on the risk term does not answer that.
