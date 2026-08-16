# Where the build is

Phase state, what the engine is doing now, and what is known to be rough. What
each mechanic *cost* is in the commit that built it; this file does not keep an
archive of measurements, because a measurement is void as soon as the next
mechanic lands. Re-measure if a quantity matters.

What exists behaviour by behaviour is `docs/THE_FOOTBALL.md`.

## Phases (`PLAN.md` §10)

**0-4 complete.** Physical layer, decision layer, perception, off-ball movement,
keeper, referee, set pieces. A full ninety-minute eleven-a-side match runs
headless in about two minutes, and the engine sits inside the §11 sanity ranges.

**5 complete.** Tactical modifiers, named patterns with counted firings and
success rates, and a passing distinguishability test.

**6 started.** Procedural appearance, character builder, face atlas, and a 3D
match view with flat materials, painted pitch lines, pool-noodle goals and an
instanced crowd. Three fixed cameras off one touchline, each panning to hold play
and cutting rarely. A hand-drawn scoreboard over it. Animation runs at the
display's frame rate. **Not yet judged against "watchable and charming at 1x"**,
which is Phase 6's exit criterion and only the owner can call it.

**7-10 not started.**

## The current work

**The attacking pass**, and the goal count is meant to run high while it lasts —
`PLAN.md` §11.4 says why, `docs/THE_FOOTBALL.md` has the order of items.

## What is known to be rough

- **The match is sparse and the goals are not overshooting.** At n=20 full-length
  matches: 4.70 shots a team against a target of 8-18, 193 passes against 300-600,
  1.61 fouls against 8-16, 0.05 corners against 3-8, 4.5 box touches against
  football's rough 25 — and 3.46 goals, inside the target, held there by converting
  0.369 of shots against football's 0.10. §11.4 expects a half-built attack to
  overshoot the goal count and it does not. **Whether the answer is more football
  inside the nine minutes or a re-based §11 density table is the owner's call**,
  and `docs/THE_FOOTBALL.md` closes the order with it.
- **The middle third still holds most of play** — 78% of touches, 12% in the final
  third. The pass model no longer referees a race nobody is running, and
  progression improved with it, but the lock eased rather than lifted. What is left
  is the runners (33), midfield structure (30), the flat value map (8b) and the
  correlated-terms half of 24.
- **Seventeen things were built on 2026-08-15**, listed with their numbers in
  `docs/THE_FOOTBALL.md`. The proposals table went from 18 open to 8.
- **Where the shots come from is close to football; what happens to them is not.**
  Measured over 24 matches at the standard clock: 70% of attempts inside the
  penalty area, mean 14.5 m, mean sight-of-goal angle 29.5°, against football's
  ~60-65% and ~17 m. The engine's own xG by band reads like football's conversion
  by band — which is *why* the map is right — while the ball converts 43% inside
  the box against football's 15%, and **7% of shots are blocked against football's
  30%**. Both of those belong to the defensive pass, and the second is proposal 5
  in one number.
- **Headed attempts are a fifth of football's rate** — 0.85 a team a match after
  the cross was fixed to arrive at heading height, against four or five — and are
  struck from a median of 12 m rather than the six-yard box. `docs/THE_FOOTBALL.md`
  29 has what is left of it.
- **The middle-third lock has eased.** Touches by third 10/78/12 to 14/67/19 over
  the day, which is the item this list has called rough since it was written.
  Twenty seeds: goals 3.50 to 4.44, shots 5.09 to 5.84, box touches 4.6 to 7.3,
  offsides 10.4 to 8.4, pass completion 69.5% to 64.0%.
- **The only broken sanity range is the held one:** corners, 0.02 a team a match
  against a target of 3-8. A corner needs a defender to put the ball behind or a
  keeper to parry wide and neither act is built. It comes back with proposal 5.
- **Five changes were built, measured and reverted**, each left in the code with
  its numbers so the next reader does not repeat it: `SimOffBall._worth_at`,
  `SimDecision.CORRELATED` (24's own mechanic), `LENGTH_COST_DIRECT` (27's own),
  `line_broken` on the lofted ball, and `QUOTA` show 1 to 2. Two of those are the
  named answers to open proposals, so 24 and 27 now want fresh ideas.
- **The deferred strike behind a setting touch is an estimate** (`SET_PASS_SUCCESS`,
  a flat 0.62) rather than the scored pass, and **a first-time lofted ball is
  charged twice**, once in `off_balance` and once in strike sigma, because neither
  layer reads the other's price.
- **Squad quality reads clearly in ball control and not at all in chance
  creation**, where shots are noise-dominated across seeds. Whether the better side
  *looks* better on the grass is unchecked, and only the owner can check it —
  `match_view_3d.QUALITY_LADDER` walks 0.6 v 0.6, 1.0 v 1.0 and 1.0 v 0.6 across a
  session so that it can be watched.

## What every figure here is worth

**Everything is measured at `clock_rate` 10, and nothing is measured anywhere
else.** The nine-minute match is the match the player gets, so it is the match the
numbers are tuned to (owner, 2026-08-15). The scoring fit is on at about 0.68
strength and that is not inflation to be corrected for — it is the format. **Do
not run `--clock-rate 1`**; a figure from it is about a match nobody plays, and
this file previously said the opposite.

What the clock rate actually changes, measured rather than assumed: scoring, and
almost nothing else. Chains at n=20 against n=10 at real time — a cross offered
11.7% against 11.7%, a through ball offered 53.5% against 59.1%, the ball out of
play in 1.4% of spells against 1.6%. Goals per football-minute do move, which is
the fit doing its job.
