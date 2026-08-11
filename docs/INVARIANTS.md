# The rules that hold the design up

From `PLAN.md`, restated because breaking them is easy and the damage is not
local. `CLAUDE.md` carries the one-line versions.

**The simulation never touches the engine.** No nodes, no physics server, no
`_process`, no frame delta, no `Time`, no input. The suite passing headless is
what proves the separation is intact, which is what the headless entry point is
*for* — it is the enforcement mechanism, not just a tool. That proof is the
owner's to run, not a reason for the agent to run the suite.

**All randomness comes from `ctx.rng`.** `SimRng`'s methods are called
`unit_float`, `range_float`, `range_int`, `gauss` and `gauss_clamped` rather than
the obvious `randf`/`randfn`/`randi_range`. Those names exist in `@GlobalScope`,
and an unqualified call to one of them inside the class silently resolves to
Godot's *global* generator instead. That bug cost real time to find: matches were
reproducible in every respect except the gaussian draws. Do not rename them back.

**One forecast and one value field per tick, shared.** `ctx.trajectory_now()`
computes the ball's future at most once per tick however many agents ask. No agent
may run its own.

**Tactics are priors on the decision function, never behaviour switches**
(`PLAN.md` §5.1). Every tactical concept in `SimTactics` resolves to a modifier on
a value the decision or movement layer was going to use anyway. A proposed
tactical feature that cannot be expressed that way should be redesigned.

Named patterns (`SimPatterns`, §5.3) follow the same rule: a trigger condition plus
a nudge to an existing value — a movement target contribution, or a multiplier on a
pass candidate's bias. What makes them worth having is not the mechanics but that
they are *named, visible and counted*. Every firing is logged and every firing is
judged, so `./run.sh diagnose` can report "overlap left: fired 11, succeeded 6". A
pattern that fires without ever being resolved teaches the player nothing and is a
bug.

**The anti-swarm guard lives in `SimMovement._assign_chasers`** and nowhere else.
Only an explicitly chosen handful of players per team may move toward the ball.
`TestMatch._whole_match_invariants` measures it.

**Tune late** (`PLAN.md` §11.1.1). Until the decision and tactics layers stop
changing shape, a fitted coefficient is a coefficient that will need fitting again.
Get concepts working and check them fast; the numbers get fitted once, at the
tuning freeze, against an engine that will hold still.

**The reduced-fidelity tier strides decisions, never physics.** Off-ball targets,
chase assignment, perception refresh, the value-field ascent and the pressure map
all scale by `SimMatchConfig.decision_stride()`. Ball integration, locomotion,
separation and contact never do — they are where the behaviour a coarse run is
meant to check actually lives. At full fidelity the stride is 1, so every one of
those expressions is a no-op and the golden digests are unchanged.

**After adding a script with a new `class_name`, run `./run.sh import` once** so
Godot refreshes its global class cache; otherwise the new class will not resolve.

**Match length is intended to become a player-facing setting**, with goals per
match holding roughly steady whichever length is chosen. That is a constraint on
where tuning knobs live, not just on their values, so the inventory of everything
that moves goals per match — and the arithmetic that says why holding it constant
is not automatic — is in `DECISIONS.md`. Read it before adding a constant that
affects scoring.
