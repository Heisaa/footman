# The rules that hold the design up

The architectural rules, and why each one matters. `CLAUDE.md` carries the
one-line versions; `PLAN.md` specifies them. This file is the reasoning.

**The simulation never touches the engine.** No nodes, no physics server, no
`_process`, no frame delta, no `Time`, no input. The headless entry point is what
proves the separation holds, which is what it is *for* — it is the enforcement
mechanism, not just a tool. Running that proof is the owner's job, not a reason
for the agent to run the suite.

**All randomness comes from `ctx.rng`.** `SimRng`'s methods are `unit_float`,
`range_float`, `range_int`, `gauss` and `gauss_clamped`, not the obvious
`randf`/`randfn`/`randi_range`. Those names exist in `@GlobalScope`, so an
unqualified call to one inside the class resolves to Godot's *global* generator
instead. That bug cost real time to find: matches were reproducible in every
respect except the gaussian draws. Do not rename them back.

**One forecast and one value field per tick, shared.** `ctx.trajectory_now()`
computes the ball's future at most once per tick, however many agents ask. No
agent may run its own.

**Tactics are priors on the decision function, never behaviour switches**
(`PLAN.md` §5.1). Every tactical concept in `SimTactics` resolves to a modifier
on a value the decision or movement layer was going to use anyway. Redesign any
tactical feature that cannot be expressed that way.

Named patterns (`SimPatterns`, §5.3) follow the same rule: a trigger condition
plus a nudge to an existing value — a movement target contribution, or a
multiplier on a pass candidate's bias. What makes them worth having is not the
mechanics but that they are named, visible and counted. Every firing is logged
and judged, so `./run.sh diagnose` can report "overlap left: fired 11, succeeded
6". A pattern that fires and never resolves teaches the player nothing, and is a
bug.

**Simulation state that lives in a static is reset from `SimMatch.setup`.** Most
of a match lives on the context and dies with it. Two layers keep arrays outside
it because they are read for every player every tick — `SimOffBall`'s intents and
`SimMovement`'s chase assignment — and a static outlives the match that filled
it. Anything of that kind needs a `reset()` called where a new match is a fact,
not a tick number to be inferred: clearing on `ctx.tick_index == 0` from inside
the layer looks equivalent and is not, because a layer that only runs in play
never sees tick 0. `docs/PITFALLS.md` has what that cost. Determinism is what
this protects: the same seed has to produce the same match whether it is the
first thing the process does or the fortieth.

**The anti-swarm guard lives in `SimMovement._assign_chasers`** and nowhere else.
Only an explicitly chosen handful of players per team may move toward the ball.
`TestMatch._whole_match_invariants` measures it.

**Tune late** (`PLAN.md` §11.1.1). Until the decision and tactics layers stop
changing shape, a fitted coefficient is one that will need fitting again. Get
concepts working and check them fast. The numbers get fitted once, at the tuning
freeze, against an engine that will hold still.

**The reduced-fidelity tier strides decisions, never physics.** Off-ball targets,
chase assignment, perception refresh, the value-field ascent and the pressure map
all scale by `SimMatchConfig.decision_stride()`. Ball integration, locomotion,
separation and contact never do — they are where the behaviour a coarse run is
meant to check actually lives. At full fidelity the stride is 1, so every one of
those expressions is a no-op and the golden digests are unchanged.

**After adding a script with a new `class_name`, run `./run.sh import` once** so
Godot refreshes its global class cache. Otherwise the new class will not resolve.

**The match clock is compressed, and almost nothing may know.** `--clock-rate R`
runs the match clock R times faster than the simulation, so a full ninety plays
out in `90/R` minutes with the scoreboard still reading 0-90. It is read in one
place, `SimMatch._advance_clock`. **It is not a speed multiplier** — players run
at the same metres per second and the tick is still a sixtieth. A compressed
match is a *shorter* match wearing a ninety-minute clock, and it holds
proportionally fewer events.

Three things scale with it and nothing else may: **fatigue**, because "nothing
left after eighty minutes" is a fact about a match rather than about a body; the
**deliberate part of a restart**, because dead time is priced in real seconds
while the match budget is not; and the **repositioning pace** at a restart, which
is what pays for the shorter window. Acceleration, turn rate, ball drag and the
tick must never know. The 3D view opens at `clock_rate = 30` because it exists to
be watched; the sim, the runner, every batch and the suite default to 1.0, so the
bands and the goldens measure the engine they always measured.

**Match length is meant to become a player-facing setting**, with goals per match
holding roughly steady whichever length is chosen. A match holds
`5400 / clock_rate` seconds of football, so goals per match is goals per second
of football times that — and holding it steady across settings requires goals per
second to scale linearly with `clock_rate`. Nothing does today except fatigue,
which is the model to copy: drain scaled by `clock_rate` over a match `1 /
clock_rate` as long cancels exactly. That constrains where scoring knobs live,
not just their values — the tractable version is one scalar derived from
`clock_rate`, so a constant that affects scoring wants to be reachable from one
place rather than buried in an expression. Fitting it is a tuning-freeze job.
