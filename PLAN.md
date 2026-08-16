# Football Manager Roguelike — Implementation Plan

**Version:** 2.0
**Target engine:** Godot 4.7+ (Forward+ renderer)
**Audience:** an implementing agent, working phase by phase

This document specifies *what* to build and *why*. It contains no code and no language-specific
structure. The models, constants and criteria here are the design, and they hold regardless of how
they are expressed.

This file is the spec and nothing else. Where the build has got to is `docs/STATUS.md`; what
football exists and what is proposed is `docs/THE_FOOTBALL.md`; owner decisions and amendments to
this document are `DECISIONS.md`.

---

## 0. How to use this document

Phases are ordered by dependency and by risk. **Do not skip ahead.** Each phase has explicit exit
criteria; do not begin the next phase until they are met and demonstrable.

Phases 1–4 build a match engine that must look and behave like football *before any art, UI, or
metagame exists*. This ordering is deliberate: if 22 agents don't produce football-like behaviour
in a top-down debug view, nothing built on top of them will save the project.

Numeric constants throughout are **starting points for tuning**, not final values. They are chosen
to be physically plausible. Expect to change most of them — and expect to change them *late*. Until
the engine has stopped changing shape, a constant fitted against it is a constant that will need
fitting again; §11.1.1 says when that stops being true, and §11 is arranged around it.

The same applies to every number in §11: it specifies what will eventually be measured and how, not
a target to steer toward now. `CLAUDE.md` has the order of work and the rules that follow from it.

Anything marked `[DECIDE]` is an open question the implementing agent should surface to the project
owner rather than resolve silently.

---

## 1. Vision

A football management game where the player is a manager, not a player. Matches are resolved by a
genuine physical simulation — ball flight, touches, tackles and off-ball movement all emerge from
player attributes and tactical instructions rather than from a dice roll over team ratings.

**The goal is an entertaining game that feels somewhat realistic — not a realistic one.** The
simulation is deep because depth makes a match surprising, legible and worth watching, not because
accuracy is the target. Where the two conflict, entertainment wins: matches should have more goals
and a higher tempo than real football, and that is a feature, not a drift to correct. Realism is the
*texture* — a ball that behaves like a ball, a pass that can be misweighted, a defender who can be
beaten — and the texture is what makes the entertainment feel earned. Fidelity serves the game,
never the other way round.

Realism still decides the floor. The sanity ranges of §11 exist so that "more entertaining" never
becomes "not recognisably football". Above that floor, the tuning targets are set by what is fun to
watch.

**"Looks like football" is a working criterion, not a slogan**: the ball behaves like a ball, a
carry can be ended, a defender gets round rather than tailgating, a pass is weighted for the man
receiving it, players offer for it and are found. Each either exists or does not, each is judged by
watching, and none is a coefficient. The engine is finished being *built* when a match reads as
football with the sound off, and finished being *tuned* some time after that.

**The register is the British football comic.** The tonal inspirations are *Hot-Shot Hamish* and
*Mighty Mouse* — the strips that ran in *Scorcher*, *Tiger* and then *Roy of the Rovers* through the
eighties and into the nineties — and eighties and nineties British football more broadly: mud,
floodlights, sheepskin coats, a ludicrously oversized centre-forward and a tiny clever one, and
outcomes that are absurd but played completely straight. Hamish's shot carried goalkeepers into the
net along with the ball and no panel treated that as fantasy. Copy the deadpan, not the exaggeration
on its own.

This does not contradict the paragraph above. The *simulation* stays honest to the sanity ranges;
the comic register lives in the characters, the naming, the body language and the copy. It is pillar
3 pointed at people rather than at objects, and §9.7 says what it means in practice.

Three design pillars govern every decision:

1. **Deep simulation, coarse controls.** The physics layer is where surprise comes from; the
   tactical layer is where legibility comes from. Never make the tactical interface as granular as
   the sim.
2. **Attribution over information.** The player must always be able to answer "why did that
   happen?" A game that shows less but explains more is more accessible than one that shows
   everything. The post-match screen is the most important screen in the game.
3. **Toys, not spreadsheets.** Cute, chunky, silly presentation (see §9). Players are characters
   you recognise, not rows in a table.

The roguelike frame: runs of one to three seasons with escalating difficulty, board confidence as
the run's health bar, and lateral progression (staff, perks, unlocked tactical patterns) between
matches.

**Non-goals for v1:** multiplayer, player-controlled match input, deep transfer-market economics,
real-world licensed data, mod support.

---

## 2. Architecture

### 2.1 Separate simulation from presentation, absolutely

The simulation owns all state and all logic. Godot's scene tree, nodes, and rendering read from it
and never write back.

Concretely:

- **Do not use Godot's physics engine for the match.** Ball and player motion are integrated by
  hand. A football sim needs a sphere over a plane and soft capsule separation — a general rigid
  body solver buys nothing and costs determinism, reproducibility and speed.
- **Simulation objects must not be scene-tree nodes.** They are plain data objects. Nothing in the
  sim may reference a node, a viewport, a material, or the current frame delta.
- **The sim must be runnable with rendering entirely absent.** Maintain a headless entry point from
  Phase 0 that runs matches and prints statistics. It is both the tuning tool and the architectural
  enforcement mechanism: if it stops working, the separation has been violated.

### 2.2 Module responsibilities

One module per subject, split along the seams §3 to §7 describe: ball, player, touch, value field,
decision, movement, keeper, set piece, referee, tactics, telemetry, match loop, world. They are
built, and `ls sim/` is the current list. Presentation reads snapshots and draws them; it depends on
everything and nothing depends on it.

### 2.3 The snapshot interface

Presentation gets a flat, read-only snapshot each frame: 22 player positions, orientations,
velocities and animation-state hints; ball position, orientation and spin; scoreboard state. Godot
interpolates between snapshots for smooth display. The sim runs on its own fixed clock and is
always authoritative.

When the player watches at 1×, the presentation layer advances the sim 60 steps per second. When
skipping, it advances it as fast as it can. Same code path either way.

### 2.4 Determinism

Target: **identical results for a given seed within a given build.** Cross-platform bit-identity is
not required for a single-player game and is not worth pursuing.

Fixed timestep of 1/60 s. Iterate collections in a stable, defined order, and index players by a
fixed id. Maintain a determinism test that runs one seed twice and asserts identical event logs.

The rest of what this requires — no frame delta, no clock, no input, all randomness through
`ctx.rng` — is the separation of §2.1 stated again, and `docs/INVARIANTS.md` owns it with the bugs
that produced each rule.

### 2.5 Computational budget and tiered fidelity

The full physics sim is expensive, and a matchday requires resolving every fixture in the league.
Solve this by **not physically simulating matches the player isn't watching.**

Three tiers:

1. **Full fidelity** — the player's match. Everything in §3 and §4.
2. **Reduced fidelity** — same logic, every decision cadence strided: off-ball targets, chase
   assignment, perception refresh, the value-field ascent and the pressure map. No positional trace.
   The physical layer is never strided. Two uses: fast-forwarding the player's own match, and the
   smoke run of §11.1, which is the cheapest structural check available.
3. **Abstract model** — every other fixture in the league. A lightweight statistical model that
   consumes team ratings, tactical plans and form, and emits a scoreline plus summary statistics.

Tier 3 must be **calibrated against tier 1**: run full-fidelity matches across a range of squad
qualities and tactical plans, then fit the abstract model so its output distributions match. The
sample needs to cover the *grid* of conditions rather than be large at any one point — a few hundred
matches per cell, a few dozen cells. Treat it as an overnight parallel job, and re-run it whenever
the sim is retuned. This keeps the league consistent with the match engine without paying for it.

Per-tick budget for the full-fidelity sim, as a design constraint on §4:

| Work | Cadence | Notes |
|---|---|---|
| Ball integration | 60 Hz | Trivial |
| Trajectory forecast | 60 Hz, ~75 steps | Computed **once**, shared by all agents |
| Player locomotion + separation | 60 Hz | Trivial |
| Value-field evaluation | ~5 Hz | **At sampled points only — see §4.1** |
| On-ball decision | 10 Hz, one player | Only the player who may touch the ball |
| Off-ball movement | 10 Hz, staggered | Spread across ticks so no tick evaluates all 21 |

The single most important rule here: **never let each agent run its own trajectory prediction or
its own value field.** Compute once per tick, share.

---

## 3. Match engine — physical layer

Every number in this section is the starting point it was specified as. **The live values are in
`SimConsts`, and several have moved.** Where one has, the constant's own comment says why — usually
because the specified figure was defensible and read wrong. Do not treat a figure here as the
current value, and do not edit the code to match a figure here; what §3 specifies is the *model*,
and that has held.

### 3.1 Ball

State: position, velocity, and spin (angular velocity as an axis-magnitude vector).

Constants (regulation ball):

| | |
|---|---|
| Radius | 0.11 m |
| Mass | 0.43 kg |
| Air density | 1.225 kg/m³ |
| Drag coefficient | The drag crisis, not a single number — see `SimConsts` and `DECISIONS.md` |
| Magnus coefficient | tune until ~6 rad/s of sidespin bends a 30 m cross by roughly 2 m |
| Gravity | 9.81 m/s² |

Per-tick forces:

- **Gravity**, downward.
- **Drag**, opposing velocity, proportional to speed squared and to cross-sectional area.
- **Magnus**, the cross product of spin and velocity, scaled by the Magnus coefficient.
- **Spin decay**, roughly 0.5 % per tick in flight.

Integrate with semi-implicit Euler.

**Ground interaction**, when the ball's centre is at or below its radius:

- Clamp to the surface.
- Vertical component reverses and is scaled by restitution — 0.6 dry, 0.45 wet.
- Horizontally, if the contact-point velocity differs from the surface velocity, the ball is
  *sliding*: apply sliding friction (coefficient ≈ 0.4) which decelerates tangential motion and
  converts it into spin, until the rolling condition is satisfied.
- Once rolling, apply a rolling resistance deceleration. Grass length and wetness are separate
  effects that move in opposite directions and compose: long grass raises it, and a wet surface is
  greasy, so it *multiplies* it down and the ball runs on faster. Wet long grass is still slower
  than a dry mown pitch. **The values live in `SimConsts` and are deliberately past what the physics
  would give** — a textbook 1.0 m/s² makes every loose ball a foot race to the touchline, and how
  the ball reads matters more than the coefficient. The comment at the constant has the history.
- Below a small vertical-speed threshold after a bounce, snap into the rolling state.

Implement the sliding-to-rolling transition properly. It is why a backspin pass checks up, why a
topspin ball runs on, and it is a large part of why the ball will feel real rather than arcade.

**Trajectory forecast.** Once per tick, run the same integrator forward 2.5 seconds at 1/30 s steps
into a shared buffer, recording sample positions and the index of the first ground contact. Every
agent reads this buffer. This is both a large performance saving and a correctness property: all
agents believe the same future.

### 3.2 Player locomotion

Players are **not** physics bodies. Each is a kinematic point with a capsule used only for
separation.

| Property | Range | Driven by |
|---|---|---|
| Max speed | 6.2 – 8.8 m/s | pace |
| Acceleration | 2.8 – 6.5 m/s² | acceleration |
| Deceleration | 1.8 × acceleration | — |
| Turn rate | falls off with current speed | — |

**The speed-dependent turn rate is essential.** Turning ability should scale roughly as
`base / (1 + speed × 0.35)`. This is why fast players overrun the ball, why a sharp change of
direction beats a quicker opponent, and why the sim will look like football rather than air hockey.
Do not simplify it away.

**Stamina** drains with the square of speed plus a per-action cost, scaled by the work-rate
attribute. Below 40 % stamina, max speed and acceleration scale down linearly to 75 % of nominal at
zero. Fatigue must be visible in the animation (§9.5).

**Separation** is a soft push-apart over a capsule radius of about 0.35 m. Overlap is resolved by
moving both players, weighted inversely by strength — the stronger player yields less. No impulses,
no bounce.

### 3.3 The touch model — no ball glued to feet

This is the mechanical heart of the project. **There is no possession flag.** Possession is derived
after the fact: the last player to touch the ball, when no opponent is within contest range.

Each tick, a player may apply an impulse to the ball if the ball is within control range (about
0.9 m, adjusted for whether the ball's height is reachable), their touch cooldown has expired
(about 0.28 s base, shorter with better technique), and their chosen action requires contact.
Control range is measured from the player's centre and has to be a distance the character can be
*seen* to reach — the leg is 0.46 of height — or every touch looks magnetic.

Every action below is the same primitive — an impulse plus a spin — with different parameters and
different error distributions:

| Action | Intent | Spin | Error grows with |
|---|---|---|---|
| **Dribble touch** | place the ball 2–4 m ahead, matched to stride | slight topspin | speed, pressure, weak foot |
| **Ground pass** | solve for the speed that arrives at the target at the intended pace | backspin proportional to weight | distance, pressure, body orientation, passing |
| **Lofted pass / cross** | solve launch angle and speed for the target under a flight-time constraint | sidespin for curl | as above, on both angle and power |
| **Shot** | up to 18–32 m/s depending on power | player-chosen | distance, angle, pressure, first-time flag, finishing |
| **First touch** | a damping impulse opposing the incoming ball | — | incoming speed and angle vs first-touch attribute |
| **Clearance / poke** | high and away from goal | — | wide by nature — it is a panic action |
| **Header** | reflection, power from heading and jumping | — | height contest |

Two consequences are features, not bugs:

- **A bad first touch leaves the ball loose.** Residual velocity from a failed reception produces
  50/50 balls, deflections and scrambles for free. A large share of the game's drama comes from
  here. Do not clamp it away.
- **Tackling is not a special case.** A defender within control range may attempt a poke or block
  like any other touch. When two players are in range on the same tick, resolve by weighted random
  on tackling versus dribbling and closing speed, then roll for a foul — probability rising with
  closing speed and with the tackler being the loser.

**Challenging the carrier, not just the ball.** Contact resolution keyed only on distance to the
ball has a large hole in it. A dribbler pushes the ball two to four metres ahead and runs onto it,
so the ball is usually out in front of him and he is only within control range of it at the instant
he touches it. A defender tracking him from a metre behind is three to five metres from the ball and
can never contest: no shoulder-to-shoulder, no tackle from behind, no nicking it away as the carrier
takes a touch. His only route to the ball is to get goal-side and intercept a pass. The symptoms are
a carrier who runs unopposed until he chooses to pass, carries of ten touches and more, tackle counts
a third of the real figure, and turnovers that are almost entirely clean interceptions.

So a defender within a **challenge radius of the carrier** — about twice control range — is a
contender too, provided the carrier is himself in control of the ball. This is deliberately a change
to *who enters the contest*, not a new subsystem: the existing weighted resolution already models
the right things, and it is reused whole.

- The challenger is contesting the *player*, not a loose ball, so he wins the ball cleanly less
  often than someone arriving at a ball nobody owns. A challenge that does not win possession is
  not nothing — it holds the carrier up, which is what the existing "the winner only plays the ball
  if free to" branch already expresses.
- **A challenge from behind is worse on both counts**: less likely to win the ball, more likely to
  foul. Approach angle relative to the carrier's heading scales both. This is what makes
  shepherding, jockeying and the cynical foul that stops a break emerge from the model rather than
  being authored as special cases.
- The carrier defends with strength and dribbling as he already does, so holding players off is an
  attribute that finally does something.

The point of this is not tackle counts. It is that **a carry has to be endable by the defence.**
Without it, the only thing that ends a carry is the carrier's own choice or his own mistake, and any
attempt to fix long carries in the decision layer is compensating for a missing mechanic by making a
present one lie.

### 3.4 Goalkeeper

Special-cased, but physically resolved rather than dice-rolled.

- **Positioning:** on the arc between ball and goal centre, at a depth that varies with ball
  distance. Comes off the line for through balls when the keeper's time-to-intercept beats the
  attacker's.
- **Shot response:** on a shot, sample a reaction time around 0.20 s (standard deviation 0.04),
  scaled by reflexes. After reacting, determine whether any point on the ball's forecast trajectory
  intersects the keeper's reach envelope — an ellipsoid growing over the dive duration, sized by
  height and agility — before the goal line. If so, attempt the save; success probability comes
  from handling and the margin. Parry versus catch is decided by margin and ball speed.

This yields fingertip saves, tip-arounds and beaten-but-recovering keepers as emergent outcomes
rather than authored ones.

### 3.5 Set pieces and referee

The set-piece module suspends normal play, positions players from a routine, and releases after a
delay: throw-in, goal kick, corner, direct and indirect free kick, penalty, kickoff. Routines are
tactical assets and are unlockable in the roguelike layer.

The referee module owns offside, fouls, cards, advantage, added time and the whistle. Offside is
evaluated at the moment of the passing impulse — trivially available, because passes are discrete
events in this model.

---

## 4. Match engine — decision layer

### 4.1 Spatial value

Two concepts, both shared by all agents and both refreshed at about 5 Hz.

**Pitch control** — for a given point on the pitch, the probability each team arrives there first.
Compute each player's time-to-arrive using a constant-acceleration-then-max-speed model from their
current position *and velocity* (velocity matters — it is why a committed run cannot be undone),
then convert the difference between the fastest home and away arrival times into a probability with
a logistic curve.

**Expected threat** — a static grid of positional value, roughly 16 × 12, bilinearly interpolated:
near zero in one's own third, rising steeply inside the box, peaking around the penalty spot.

**Evaluate pitch control at sampled points, not across a full grid.** The points that matter are:
every teammate's position and near-future position, a handful of candidate dribble targets, and a
small set of space probes ahead of the ball. That is typically 30–60 evaluations rather than the
one to two thousand a full grid requires — a difference of one to two orders of magnitude in cost,
for no loss of decision quality.

A coarse full grid may be computed at low frequency **for the debug view and post-match heat maps
only**. It must never be on the decision path.

The product of pitch control and expected threat is the field that off-ball attackers climb.

### 4.2 On-ball decision

Evaluated at about 10 Hz, only for the player currently able to touch the ball.

1. Generate candidates: hold, dribble in eight directions, pass to each teammate (ground, lofted
   and through-ball variants), shoot, clear.
2. For each, estimate: probability of success, from pitch control at the target plus interception
   geometry along the ball's path plus the executing player's relevant attributes; value gained, as
   expected threat at the resulting location; and value conceded on failure, weighted by the
   opponent's counter-attacking threat from that turnover position.
3. Score as `success × gain − (1 − success) × risk_weight × loss`.
4. **Select via a softmax, not by taking the maximum.** Temperature falls with the decisions
   attribute, so better decision-makers more often pick the genuinely best option and weaker ones
   make plausible-but-wrong choices. Deterministic argmax selection is the most common way this
   kind of engine ends up feeling robotic — avoid it.

### 4.3 Off-ball movement

Each player's target position is a sum of contributions:

- the formation's home position for their role
- a response vector scaled by how far the ball has moved from centre — the shape slides with play
- a phase-of-play offset (build-up, attack, transition, defend)
- a role behaviour vector (inverted fullback, false nine, and so on)
- for attackers, a clamped local gradient ascent on pitch control × expected threat
- for defenders, an assignment vector: position between the assigned opponent and goal, biased
  toward the ball side

Pressing triggers come from tactical zones (§5). When one player engages, the others shift to close
passing lanes rather than converging on the ball.

**The primary failure mode to watch for is ball-swarming.** If the debug view shows players
collapsing onto the ball, the fix is almost always in this function, not in the physics.

### 4.4 Perception

Players are not omniscient. Each carries a slightly stale, slightly noisy view of the others,
refreshed at a per-player cadence of roughly 4–8 Hz scaled by awareness, with positional error
growing for players behind them. This is cheap and it is where blind passes, missed runners and
defensive lapses come from.

---

## 5. Tactics layer

### 5.1 The rule that makes everything else work

**Tactics must not be behaviour switches. Tactics are priors on the decision function.**

Every tactical concept resolves to a modifier on values already used in §4:

| Concept | Modifies |
|---|---|
| Pressing intensity and trigger zone | territory weighting, engagement distance, which zones trigger a press |
| Defensive line height | formation home positions, offside-trap aggressiveness |
| Tempo and directness | discount rate on future value, ground-versus-lofted bias, hold-versus-release threshold |
| Risk | the risk weighting in the scoring expression |
| Width | lateral spread of formation home positions |
| Attacking focus | expected-threat multipliers by pitch region |

This is what makes tactical options composable rather than a pile of special cases, and it means
overlapping instructions genuinely interact instead of one silently overwriting another. **Any
proposed tactical feature that cannot be expressed as a modifier on the shared value function
should be rejected or redesigned.**

### 5.2 The whiteboard

There is **no settings screen with sliders.** Tactical input is a pitch diagram the player draws on.

Tools:

- **Drag tokens** — set shape by moving players
- **Arrow** — assign a movement pattern (overlap, underlap, run in behind, drop deep)
- **Zone** — paint a pressing trigger area, or a target area to attack
- **Line** — drag the defensive height line
- **Link** — connect two players into a partnership, biasing passes and supporting runs between them

The output is a tactical plan that maps onto the modifiers in §5.1.

**The whiteboard's real purpose is attribution.** The post-match screen re-uses the identical widget,
overlaying what actually happened: the pressing zone the player drew beside the heat map of where
pressure actually occurred; the intended shape ghosted behind actual average positions; drawn runs
beside the runs actually made and their success rate. "You asked for this, you got that" is a
sentence a slider can never say, and it is the mechanism by which a deep game becomes learnable.
Budget real time for this screen — it is the most important interface in the project.

### 5.3 Named patterns

Rather than abstract axes, the player installs a small number of recognisable, named moves — start
with five to eight slots: *overlap left*, *third-man run*, *keeper plays short*, *switch to the far
side*, *press the goal kick*. Each is a fragment of a tactical plan. Each fires visibly on the
pitch, is logged in telemetry, and is reported after the match with a count and a success rate.

Named things with visible, counted occurrences are dramatically more learnable than parameters.
Unlocking new patterns is the main tactical progression axis of the roguelike layer.

---

## 6. Accessibility systems

These separate this game from Football Manager. They are not polish; treat them as core.

### 6.1 Hidden numbers

Attributes are stored internally as normalised values and drive the sim exactly. **The player never
sees a number for a player attribute.**

Instead, a scout-report generator maps a true value and a confidence level onto natural language
from a template bank, with hedging calibrated to confidence:

- Low confidence: *"Looked quick in the one game I saw, but I couldn't tell you much more."*
- High confidence: *"He's genuinely rapid. Best pace in your squad, no question."*

Confidence rises with minutes observed, scout quality, and matches played for you. This is the
single biggest lever against optimisation-brain: you cannot spreadsheet a hunch.

`[DECIDE]` Whether your own players' attributes eventually become fully known. Recommendation: they
converge to a narrow band but never to a number.

### 6.2 The assistant manager

A rule-based analyser running over live match telemetry. It detects patterns and surfaces at most
two or three suggestions at a time, each with a plain-language rationale and a one-click tactical
change:

> *"Their right back is caught upfield every time we turn it over — four times now. Shall we push
> the winger onto that side?"* **[Do it] [Leave it]**

Detection rules are simple threshold queries over telemetry — for example, *opponent fullback
average position beyond a threshold, and our recoveries in that zone above a count*. Start with
about fifteen rules covering the common tactical situations.

This is adaptive difficulty without a difficulty setting: a novice always has a good option
available and learns causal reasoning by watching someone else's, while an expert ignores the panel.
It is also diegetic — **the assistant's quality is a staff attribute you hire for**, controlling
detection sensitivity, false-positive rate and how many suggestions surface. A poor assistant giving
mediocre advice is an early-run problem to solve, not a design compromise.

### 6.3 Punctuated match flow

The sim runs continuously, but a director watches telemetry and pauses at genuine pivots — target
five to eight per match:

- a sustained spell of pressure against you
- a goal, injury, or card
- the opponent visibly changing shape
- a big chance missed at either end
- the 75th minute with the game in the balance

Full physics underneath; the player's engagement is paced rather than ambient.

### 6.4 Attention budget

**Three tactical interventions per match**, plus one refreshed at half-time. Substitutions are
separate. Scarcity converts *adjustment* into *decision*, and it is the honest simulation of the
job: you cannot fix everything from the touchline.

Assistant suggestions cost from the same budget, so accepting advice is a real spend and the
assistant never trivialises the game.

### 6.5 Dressing-room dialogue

Some instruction happens as conversation rather than menus: pre-match, half-time, full-time. The
player picks a line, players respond in character, and their reaction depends on personality and on
their trust in the manager. This fuses tactics and man-management into one interface instead of two,
and characters are always more accessible than form fields.

Use a transparent probability model — show the odds and the stakes before committing. Manager
attributes are the speech skill.

The voice of this screen is §9.7's: players answer back in character and in period, and the game
never comments on its own jokes.

---

## 7. Telemetry

Every match produces a full event log. This is not optional instrumentation — three systems depend
on it (post-match attribution, the assistant, and the statistical test suite), so build it in Phase 1
rather than retrofitting it.

Events to record, each with a timestamp: touches (with the acting player, the touch kind, ball
position before and after, spin, and the pressure on the player), pass attempts (with intended
target, kind, and the expected value the engine estimated), pass outcomes, shots (with the chance
quality and whether on target), duels and their winner and whether a foul resulted, recoveries,
pattern firings and whether they succeeded, phase changes, and goals.

Also record a positional trace at 5 Hz for heat maps and average-position overlays.

---

## 8. Data model

**Player:** identity (id, name, age, nationality); an appearance seed (§9.3); attributes; two or
three personality traits; condition, sharpness, morale and trust in the manager; contract; and a
separate record of *known* attributes as an estimate-plus-confidence pair per attribute.

Attributes are grouped physical, technical, mental and keeper. `SimAttributes` is the list, and it
is the authority — every one of them drives something in `sim/`, so the code says which exist and a
copy here would only go stale.

**Club:** name, palette, squad, staff, finances, reputation.
**Season:** league table, fixtures, current week.
**Run state:** seed, current club, board confidence, the run's expectations, unlocked patterns,
hired staff, perks, and the season index within the run.

---

## 9. Art direction

Reference: **Sokpop** games, plus Nintendo Mii and Animal Crossing villager proportions. Silly,
cute, chunky, hand-made. The visual target is *a toy football set*, not a broadcast.

Those three settle the *shapes*. What the figures are *like* comes from somewhere else — the British
football comics of §1, `Hot-Shot Hamish` and `Mighty Mouse` — and §9.7 states it, because a toy
football set can be charming and characterless at the same time and this one must not be.

### 9.1 Rendering

- Forward+ renderer, but **unlit or two-band toon shading**. No physically-based materials —
  roughness at maximum, metallic at zero.
- **No textures on geometry** except small face atlases and painted pitch lines. Colour comes from
  vertex colour or flat per-material albedo.
- No normal maps, no ambient occlusion, no bloom, no screen-space reflections. A single soft
  directional light plus flat ambient.
- Optional very subtle vertex wobble on world geometry for the hand-made feel — keep it under half a
  percent of scale or it reads as a bug.
- Background: a single saturated flat colour or simple gradient, varying by stadium and competition.
  The warm salmon of the reference images is exactly the register — bold and non-naturalistic.

### 9.2 Camera

Perspective with a **low field of view**, at a high angle, to approximate isometric. Prefer a small
set of authored camera positions that cut between each other over a free-orbit camera; the
faked-isometric look breaks if the player can tilt to eye level.

**Three positions, and they pan** (amended — see `DECISIONS.md`). All three stand off the same
touchline, one on the halfway line and one level with each penalty area, and each pans, tilts and
zooms to hold play. Motion inside a shot is free; cutting is expensive, and a grid of authored
positions dense enough to keep play framed spends it constantly. The elevation is stated at the
middle of the pitch (35°) because a panning camera has a different angle on every point it can
look at, and the field of view is solved each frame to hold a fixed frame width, which keeps a
player the same size on screen wherever play is.

### 9.3 Characters

- Six hundred to twelve hundred triangles. Head roughly 35–40 % of total height. Stubby limbs,
  mitten hands, no separate fingers, no neck.
- **No facial rig.** The face is two dots and a simple mouth on a small texture atlas, swapped
  wholesale for expression — neutral, effort, delight, despair, anger. Expression swaps deliver an
  enormous amount of character for almost no cost; use them constantly.
- Hair, hats and beards are single-piece meshes drawn from a small library.
- **Procedural appearance from a seed**, Mii-style: body type, skin tone, hair mesh and colour, face
  atlas index, accessory. A five-hundred-player database therefore has visual identity essentially
  for free — and memorable-looking players are what make the man-management layer land at all.
- Kits are flat two- or three-colour materials driven by a palette resource. Define a master palette
  of sixteen to twenty-four colours so the game stays coherent and can be re-skinned per competition.

### 9.4 Ball, pitch and crowd

The ball is a plain white sphere with a handful of dark pentagon dots, or plain white, with a slight
squash on hard contact. The pitch is a flat plane with painted lines and mowing stripes as flat
colour bands. Goals are thick rounded tubes in a bright accent colour — they should read as pool
noodles, not steel.

The crowd is instanced low-poly heads bobbing on a sine wave with per-instance phase offsets,
coloured from the home palette. Cheap, and the collective motion sells the stadium.

### 9.5 Animation

- Heavy squash and stretch on kicks, landings, dives and falls.
- Minimum clip set: idle, jog, run, sprint, sharp turn, light kick, hard kick, header, slide, fall,
  get up, celebrate, dejected, exhausted, keeper dive left and right, keeper catch.
- **No root motion.** Animation is driven by simulated velocity; the sim is always authoritative.
- **Play it smoothly, at the display's frame rate.** An earlier build quantised every pose to ten
  frames a second for a stop-motion register; the owner asked for smooth motion instead (see
  `DECISIONS.md`). The locomotion cycle in particular has to lift the knee and the foot clear of the
  grass — a leg that swings through straight reads as being dragged along the ground however good
  the rest of the figure is.
- Legibility over realism. Players should visibly fall over, throw their arms up, sit down when
  exhausted, and trudge when morale is low. Big, readable body language is how the player reads the
  match without reading numbers.

### 9.6 Interface

Chunky, thick-outlined, hand-drawn numerals and panels, as in the reference scoreboard. Bright
saturated primaries, large hit targets. Avoid dense tables anywhere — if a screen is starting to
look like a spreadsheet, it is wrong for this game.

### 9.7 Tone and register — the football comic

The inspirations named in §1 are *Hot-Shot Hamish* and *Mighty Mouse*: Hamish Balfour, an enormous
Highlander at a small club, with a shot that tore the net out and a pet sheep on the touchline, and
Kevin Mouse, tiny, bespectacled and clever, doing with wit what Hamish did with a size-fourteen
boot. Around them, eighties and nineties British football as it was drawn and as it was: heavy
pitches, floodlit midweek nights, hoardings, terraces, a manager in a sheepskin coat.

That is a specification, not a mood board. What it asks for:

- **Archetypes, not averages.** Generation (§9.3, §8) should be allowed to reach the tails — a giant,
  a tiny one, an ancient one, one who is superb at exactly one thing and hopeless at the rest. A
  squad of eleven competent similar men is off-register even when every number in it is plausible.
  The interesting men are the ones a player can describe in four words.
- **The absurd, played straight.** Whatever the game reports, it reports in the same flat voice: the
  shot that flattened the keeper is described like a throw-in. No winking, no nudging copy, no
  self-aware jokes about being a game. The comedy is in the event, and it dies the moment the game
  tells you it was funny.
- **Big moments are physical, and they are the animation's job.** The keeper carried backwards over
  the line, both men into the hoardings, the header won by a man a foot taller than anyone near him.
  §9.5's squash and stretch and the expression atlas of §9.3 are how these land. **They are dressing
  on a normally simulated event** — a goal is a goal the engine produced; the comic is in how it is
  shown and described, never in the physics. §11's sanity ranges are untouched by any of this.
- **Nicknames are identity.** "Hot-Shot", "Mighty" — an epithet from the trait-and-attribute
  combination (§8), used in the event log, the dialogue of §6.5 and the post-match screen ahead of
  the surname. It is the cheapest way to make five hundred generated players memorable, and
  memorable players are the whole premise of the man-management layer.
- **Small club, hostile board.** The roguelike frame of §1 already is a *Roy of the Rovers* plot:
  the unfashionable club, the run of fixtures that has to be survived, the directors' box. Name and
  present it that way.

The boundary, stated once: the register governs presentation, naming, copy and character generation.
It governs nothing in `sim/`. A proposal that reads "and Hamish's shots should ignore the keeper" is
a proposal to break §11 and is refused; a proposal that reads "a shot above some power, scored,
plays the keeper-carried-into-the-net celebration and the log says so" is the same idea, correctly
placed.

---

## 10. Phased build plan

### Phase 0 — Skeleton
Project structure, the sim/presentation separation, a headless entry point, a 2D top-down debug
view, and the test harness.
**Exit:** a stub simulation drives an on-screen object; the headless entry point runs and prints a
result; the determinism test harness exists.

### Phase 1 — Ball and one player
Ball integrator, ground interaction, the sliding-to-rolling transition, trajectory forecast. One
player with locomotion and the dribble touch. Telemetry logging.
**Exit:** a player dribbles through a slalom without the ball ever being glued to their foot;
touches sometimes get away from them; a chipped ball with sidespin visibly bends; a backspin pass
checks up on the bounce.

### Phase 2 — Bodies on the pitch
Full locomotion including turn-rate limits and stamina, player separation, formation home positions,
ball response, six-a-side with naive behaviour and no tactics.
**Exit:** the top-down debug view reads as football to an uninformed observer. **Specifically: no
ball-swarming.** Players hold shape when the ball is elsewhere.

### Phase 3 — Decisions
Sampled value evaluation, expected-value action selection, perception, off-ball gradient ascent,
defensive assignment, pressing.
**Exit:** possession sequences of four or more passes emerge unprompted; through balls appear
without being authored; players sometimes make the wrong-but-plausible choice; a six-a-side match
produces a believable pattern of chances.

### Phase 4 — A complete match
Keeper, set pieces, referee, offside, fouls and cards, eleven-a-side, ninety minutes.
**Exit:** a gate run sits inside the sanity ranges of §11, and the real headless cost of a full
match has been measured and recorded there. The tuning table is *not* an exit criterion for this
phase — it is checked at the tuning freeze of §11.1.1, once the decision and tactics layers have
stopped changing shape underneath it. Matching a band against an engine that is about to be
rewritten is work done twice, and it blocks Phases 5–8 on the wrong thing.

### Phase 5 — Tactics
Tactical plans, the modifier system of §5.1, named patterns.
**Exit:** two contrasting plans — high press and direct versus deep block and patient — produce
*statistically distinguishable* match traces: different possession, pressing intensity, pass-length
distribution and shot locations. A dozen matches per plan is the routine check and forty is the
confident one; this is a comparison of two means, not an estimate of a rare event, and a tactical
difference that needs two hundred matches to show up is not a tactical difference a player will ever
feel. The threshold is |t| > 3 per metric, which is *harder* to clear at a small sample, not easier
— so a pass at twelve matches per arm is a real result and a fail is a reason to look again with
forty. If the plans don't separate, the tactical layer is a lie; fix it before proceeding.

### Phase 6 — The look
Character system with procedural appearance, palette resources, toon shading, animation, camera,
pitch, stadium, crowd.
**Exit:** a match is watchable and charming at 1× speed with the sound off.

### Phase 7 — Whiteboard and attribution
The drawing interface, and the post-match screen re-using the same widget with real overlays.
**Exit:** a new player can draw a pressing zone, watch a match, and correctly describe from the
post-match screen whether it worked and why.

### Phase 8 — Accessibility systems
The assistant manager and its rule set, director pauses, the attention budget, the scout-report
language generator, hidden numbers throughout.
**Exit:** a playtester who has never played a management game completes a match, makes at least one
intervention, and can explain their reasoning afterwards.

### Phase 9 — Metagame
Squad, morale, trust, personality, team talks and dialogue, board confidence and expectations,
training, the season loop, and the abstract league model of §2.5 with its calibration pass.
**Exit:** a full season is playable end to end, and skipping a matchday of ten fixtures is
imperceptible.

### Phase 10 — Run structure
Run seeding, escalating seasons, unlocks, staff hires, perks, meta-progression.
**Exit:** a full run is playable and losable.

---

## 11. Validation targets

Run through the headless entry point. Two layers, because "is this still football?" and "are these
numbers right?" are different questions, cost different amounts of wall clock, and become urgent at
different times in the build.

**Sanity ranges — the breakage detector.** Wide, structural, and never tuned toward. Any engine
that is doing recognisable football passes them without anyone having touched a coefficient; the
failures that actually happen — the ball never leaving the centre circle, pass completion at 30 %,
twenty goals a match, nobody ever shooting — all trip a wire.

They catch an engine that has stopped being football at all. **They do not decide whether a change
is good**, and they are not a target: a behaviour that reads right by eye goes in whether or not it
moves one of these, and a range broken immediately after a behaviour landed is usually that
behaviour rather than a defect. Say which, and let the owner look.

| Metric, per 90 minutes | Sanity range | Judgeable from |
|---|---|---|
| Goals, both teams | 0.5 – 16 | 3 |
| Shots per team | 3 – 35 | 3 |
| Share of shots on target | 15 – 65 % | 3 |
| Possession, higher side | 50 – 80 % | 3 |
| Pass completion | 45 – 95 % | 2 |
| Passes per team | 120 – 900 | 2 |
| Fouls per team | 1 – 40 | 5 |
| Offsides per team | 0 – 12 | 5 |
| Corners per team | 0.5 – 20 | 5 |
| Distance covered per player | 6 – 15 km | 2 |

**The ceiling on goals is suspended for the attacking pass** (§11.4), which is temporary and ends
with it. The attack is being built out against a defence missing most of its behaviours, so a high
count is the intended shape of a half-built engine rather than breakage, and 8 would fire on every
mechanic that lands. 16 stands in its place — enough to catch the failure the wire is for, twenty
goals a game — and **returns to 8 when the defensive pass lands**
(`GOALS_CEILING_SETTLED` in `tools/validation.gd`). The lower bound is unchanged, and every other
range holds in both directions.

**Tuning targets — where the engine should eventually land.** Reported on every run, but advisory:
a number outside its band is information about drift, not a failing build. Only the acceptance run
promotes them to pass/fail (`--strict`).

| Metric, per 90 minutes | Target band | Converges by |
|---|---|---|
| Goals, both teams | 2.9 – 4.1 | 40 |*
| Shots per team | 8 – 18 | 40 |
| Share of shots on target | 30 – 40 % | 40 |
| Possession, stronger team | 52 – 65 % | 40 |
| Pass completion | 70 – 87 % | 20 |
| Passes per team | 300 – 600 | 20 |
| Fouls per team | 8 – 16 | 40 |
| Offsides per team | 1 – 4 | 40 |
| Corners per team | 3 – 8 | 40 |
| Distance covered per player | 9 – 12 km | 20 |
| Score draws | 12 – 22 % of matches | 200 |

\* Goals is where the *finished* game should land, with both halves of football built. The engine is
not aiming at it now and is not meant to be near it — see §11.4.

### 11.1 How many matches, and how long each

The runner is sized for the wall clock first, because a check that is not run is not a check. All
three sizes are the owner's runs; `CLAUDE.md` has the day-to-day rule, and the reason is §11.1.1's:
a batch measures a machine that is still missing parts.

Three sizes, and the runner prints which one is being quoted beside the verdict:

- **Smoke — six matches of twelve minutes, reduced fidelity.** Under a minute. Judged on the sanity
  ranges. The cheapest structural check there is, for when a structural check is what is wanted.
- **Gate — six matches of ninety minutes, full fidelity.** A few minutes. Same judgement, but at
  full length and full cadence, so fatigue, the second half and the tuning figures are all real.
  Run it before believing a result.
- **Acceptance — two hundred matches of ninety minutes, `--strict`.** Under an hour, and the only
  run where the tuning table is a pass/fail criterion. Run it at a tuning freeze, not before.

Four consequences of sizing it this way, and each is load-bearing:

**Every count is normalised to ninety minutes**, from the minutes the match actually played
(`SimMatchStats.per_90`), so a short match is a legitimate measurement of a *rate* and the same
bands judge every run length. What short matches genuinely distort is fatigue — distance per player
extrapolates high and late-match collapse goes unseen — which is why the gate exists at full length.

**A metric is only judged at a sample that can support it.** Each band carries the size it needs
(`min_n`); below it the figure is printed, tagged `noisy at n=6`, and excluded from the verdict. A
number with its sample size beside it is information; the same number quoted as a result is a lie.

**The sample size is set by the noisiest metric, which is why the acceptance run exists.** The
score-draw rate is a proportion near 0.24, so its standard error is 6.8 points at n = 40 and only
3.0 at n = 200, against a band half-width of 4.

**Matches are independent and reproducible from their seeds, so a batch is sharded across cores.**
Shard *w* takes a contiguous seed block, so `--workers` changes how fast a run is, never what it
measures. The Phase 5 test shards the same way, and run serially it is hours — which is how an exit
criterion quietly stops being run.

Wall-clock targets: smoke under a minute, gate under five minutes, acceptance under an hour.

The same reasoning applies to the test suite, the check run most often of all. A test that simulates
a match pays two seconds per minute of match clock, so the suite simulates as few matches as it can
and gets several assertions out of each one. The whole-match invariants — reaching full time, the
ball staying in play, no swarming, shape held, possession alternating — are five checks over one
stepped match, not five matches. Coverage across seeds is what the smoke and gate runs are for; the
suite's job is to be fast enough that there is no excuse for skipping it. Target: under two minutes.

### 11.1.1 Tune late

**While the engine is still changing shape, do not tune it.** A coefficient fitted against the
current decision function is worth nothing after the decision function changes, and the effort
spent fitting it is spent twice: once on the fit, and again on the false confidence that the number
means something. Every hour on goals-per-match before the shape is settled is an hour not spent on
whether patterns fire, whether tactics separate, whether the match is worth watching.

So through Phases 5–8 the priority is **concepts working, checked fast**:

- Does the mechanism do the thing it is named for? Patterns fire and get resolved; two contrasting
  plans separate; a stronger squad wins more often than not.
- Is the engine still doing football? The sanity ranges.
- Is it deterministic and reproducible? Golden replays and the determinism test — these stay
  absolute, because they cost seconds and catch a class of bug nothing else catches.

The tuning table is watched for drift and otherwise left alone. **The tuning freeze** is the moment
that changes: once the decision layer, the tactics layer and the pattern set are structurally
settled — in practice at the end of Phase 8, before the metagame is built on top of match output —
the acceptance run becomes a pass/fail criterion and the numbers get fitted once, properly, against
an engine that will not move underneath them. Phase 4's exit criterion is deferred to that point
rather than blocking Phase 6 and 7 on a goals-per-match figure.

### 11.2 The cost of a match is the real constraint

Every number above is downstream of one measurement: **0.39 ms per tick**, so a full-length match is
about two minutes of CPU. That is what makes a forty-match gate ten minutes and why the gate is six.
The levers, in the order they are worth pulling:

1. **Fewer matches.** Free, and honest as long as undersampled metrics are marked as such.
2. **Shorter matches.** Linear, and honest for rates once counts are normalised per 90.
3. **Reduced fidelity** (§2.5 tier 2). Every *decision* cadence strided — off-ball targets, chase
   assignment, perception refresh, the value-field ascent, the pressure map. Worth 15–20 %. The
   physical layer is never strided: ball integration, locomotion, separation and contact are where
   the behaviour a coarse run is checking actually lives.
4. **Making the tick cheaper.** The only lever that helps everything at once, including watching at
   1×. Movement is 38 % of a tick, locomotion 14 %, perception 12 %, separation 10 %.
5. **Halving the tick rate.** Not taken: at 30 Hz a ball travelling 30 m/s moves a metre a tick,
   against a 1.2 m control range, so touch detection degrades and the thing being measured is no
   longer the thing that ships.

Six-a-side is *not* a lever worth pulling for speed — measured at 0.31 ms per tick against 0.39,
because the per-tick costs that dominate are not all linear in player count. Use it when six-a-side
is what is being tested, not to go faster.

### 11.3 The tuning table is an entertainment target

Per §1, the bands are set by what makes a watchable match, and the sport is the reference they are
stated *against* rather than the thing they try to hit. Real football scores 2.2–3.4 goals a match
and draws about a quarter of them; this game deliberately scores more, draws less, and plays at a
higher tempo, and the intent is to keep moving that way rather than converge back.

The **sanity ranges** are the floor and stay honest: a metric leaving one is a question to answer,
not a note. The answer is usually the behaviour that just landed, and then the range comes back when
the mechanics that balance it are built, never by softening the one that went in. The **tuning
targets** above that floor are design decisions, and moving one is a conversation.

Where a number does something other than describe the sport, it says so at the point of use in
`tools/validation.gd`.

Additionally, **a stronger squad must beat a weaker one roughly 60–70 % of the time, not 95 %.**
Football's low scoring means upsets are frequent; if attribute differences dominate outcomes, the
noise in the system — softmax temperature and execution error — is tuned too tight.

Performance targets:

| | Target |
|---|---|
| Full-fidelity match, headless | measure in Phase 4 and set the fast-forward and calibration strategy from the real number |
| Abstract league match | under 5 ms |
| A full matchday of ten fixtures | under 1 s |
| Watched match at 1× | comfortably within a 16 ms frame budget, with headroom for rendering |

**Measured in Phase 4:** 0.28–0.39 ms per tick depending on the machine and what else is running,
so a ninety-minute match resolves headless in roughly two minutes of CPU time. (It began at 0.54 and
came down by a factor of two: sharing the trajectory forecast lazily, pruning the pitch-control
evaluation to players who could plausibly win the race, and running the value field at the 5 Hz this
document already specified rather than at the movement cadence.) Two consequences, and they point in
opposite directions:

- Watching at 1× is cheap. One tick per rendered frame is about 1.5 % of a 16 ms budget, so the
  1× viewing mode of §6.3 costs nothing worth discussing and the reduced-fidelity tier of §2.5 is
  not needed for it.
- Batch work is expensive, and everything that runs matches in bulk — the acceptance run, the
  abstract model's calibration — has to be parallel or it will not happen.

Maintain three test suites: golden replays (fixed seed produces a fixed event-log hash), the
statistical bands above, and the determinism test. The first and third are absolute and always have
been. The second is not a regression gate and never becomes one before the freeze: it is the
two-layer arrangement of §11.1 — sanity ranges reported on every run to catch structural breakage,
tuning targets enforced only at the freeze. A golden digest moving after a deliberate behaviour
change is expected; re-record it. A digest moving when nothing should have changed behaviour is a
real finding.

### 11.4 One half of football at a time: the attack first

The table above describes the finished game, and the engine is not being built toward it in one
pass. **The attacking pass comes first, and it is meant to overshoot.** The defensive layer is
missing most of its behaviours — nobody blocks a shot with his body, nobody jockeys, nobody covers
the man who was beaten, no side steps up, the penalty area does not resist a carrier — so an attack
built against it scores far more than the same attack will once the defence exists. Balancing the
goal count now would fit the attack to the absence of the defence: §11.1.1's argument, applied to a
whole layer instead of a constant.

Until the owner calls the switch, which is called by eye and not by a number: goals per match is
expected well above 2.9–4.1 and above the suspended ceiling of 8; attacking behaviour is the work;
and a defensive mechanic is not a response to a high score. It is the next pass, held in
`docs/THE_FOOTBALL.md` in the order it is wanted. Then the tuning freeze, where the bands are fitted
once to the engine both passes produce. `DECISIONS.md` (eighth amendment) is the record.

---

## 12. Open questions

Six `[DECIDE]` questions: squad size for the prototype phases, whether own-squad attributes ever
become fully known (§6.1), run length, whether the player can watch at 1× at all (§6.3), injury
model depth, and whether tactical patterns are per-run unlocks or persistent progression.

**`DECISIONS.md` is the live list**, with the default in force for each, why, and the one place each
would have to change. Do not keep a second copy here.

---

## 13. Risks

| Risk | Mitigation |
|---|---|
| Off-ball movement never looks convincing | It is Phase 2 and 3 for a reason. Do not build interface or metagame on an unconvincing sim. Gate hard on the Phase 2 exit criterion. |
| The engine's physics system creeps into the sim | The headless entry point is the enforcement mechanism. Check it in continuous integration. |
| The tactical layer turns out to be cosmetic | Phase 5's statistical distinguishability test exists precisely to catch this. |
| The full-fidelity sim is too slow to fast-forward | The tiered fidelity design of §2.5 removes the dependency. Measure the real cost in Phase 4 and set the tier boundaries from that measurement rather than from an assumption. |
| Scope explosion in the metagame | Phases 9 and 10 are last. A great match engine with a thin metagame is a shippable game; the reverse is not. |

---

## 14. Reference reading

- Spearman, *Beyond Expected Goals* — the pitch control model underlying §4.1
- Singh, *Introducing Expected Threat* — the positional value grid
- Reep and Benjamin, together with the modern rebuttals — for realistic possession-chain length
  distributions
- Bray and Kerwin, *Modelling the flight of a soccer ball in a direct free kick* — drag and Magnus
  coefficients, and validation targets for §3.1

For tone rather than for mechanics (§1, §9.7):

- *Hot-Shot Hamish* — Fred Baker and Julio Schiaffino, from *Scorcher* in 1973 and later *Tiger*.
  The giant at the small club, the shot nobody can stop, the sheep. The model for an outlandish
  player treated by everyone around him as an ordinary teammate.
- *Mighty Mouse* — the same creators; merged with Hamish into a single strip in *Roy of the Rovers*
  in the mid-eighties and running into the nineties. The small clever one, and the reason the roster
  wants both ends of every distribution rather than the middle.
- *Roy of the Rovers* more broadly — for the shape of a season as melodrama, which is what §10's
  Phases 9 and 10 are building.
- Eighties and nineties British football itself — the pitches, the kits, the grounds and the
  touchline furniture that the art direction of §9 dresses the comic in.
