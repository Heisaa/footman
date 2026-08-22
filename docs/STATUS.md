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
- **The side does not stand in its own formation, and that is what the clump is.**
  `diagnose` now carries `The clump` and `Holding the shape`, and the second one
  answered it: every outfielder sat a mean 11 m from the point the shape had given
  him, all lagging the same way, because the station itself moved at 2.6 to 4.6
  m/s and the target he was actually running at at 4 to 7 — against 1.9 m/s of
  shape-holding pace and 7.5 flat out. **A shape that moves faster than a
  footballer has no occupants**, so ten men trailed the ball in a bunch. The cause
  was `shape_position` reading the live ball; `ctx.shape_ball` follows it at 3 m/s
  now. Three seeds: the station's target speed 4.1 → 2.3 m/s, a man simply holding
  station 8% of samples → 12%, the side 11.0 m off its shape → 10.1, and the
  errands' net pull onto the ball 6.0 m → 5.0. Then the four arms the block had
  ranked, of which **one turned out to be the cause of three**: `_support_adjust`
  returned a 12 m ring round the ball outright, four or five men at a time, and it
  is the base `drift` and `ascent` are built on top of. Stepped rather than
  teleported and reading the shape's ball, all three came down together; `press`
  had its side-of-the-ball sign latched for the length of a press.
  **Over the whole day, three seeds:** off its own shape 11.0 → 8.7 m, net pull
  onto the ball 6.0 → 3.6 m, teammates within 8 m 3.7 → 2.5 of ten, cells occupied
  6.5 → 7.1 of fifteen, twenty men inside one 12 m circle 5.7 → 4.8, every arm's
  target bar the chase 4-8 m/s → 1.5-3.4, mean speed 2.7 m/s throughout. **A side
  spread properly occupies eight or nine cells**, so 7.1 is progress and not the
  answer.
- **The station's own jumps are eased** (`SimContext.shape_phase`). Four things
  switched between the attacking and defending shapes on
  `possession_team == p.team`, worth fifteen metres of station between them and
  arriving in one tick at every change of hands. A mean cannot see a
  once-a-turnover teleport, so `Holding the shape` gained the column that can —
  the share of samples where the station outran a sprinter — and it halved on
  every seed, 1.4/1.3/0.7% to 0.7/0.6/0.3%. Mean speed 2.7 → 2.4 m/s, the side
  0.6 m closer to its own targets. What still jumps is `SHAPE_BALL_LEASH` behind
  a ball hit sixty metres, which is meant.
- **Marking was made zonal away from the ball** (`SimMovement.mark_tightness`).
  It is 40% of all outfielder-samples and was the largest single arm taking the
  side out of shape. Ablated against itself over three seeds it is worth about
  0.6 m of the closing-in and a quarter of `mark`'s own pull; it belongs to the
  defensive pass and is here because it reads as football, not because it fixed
  the clump.
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
- **Headed attempts are a fifth of football's rate** — 0.56 to 0.85 a team a match
  across the day's arms, against football's four or five — and are struck from a
  median of 12 m rather than the six-yard box. The box is now attacked as three
  claimed points and the cross is aimed at the man who claimed one, which took the
  nearest man to a dropping cross from 9-12 m to 5-8 m; **the outcome did not
  follow the mechanism**, and a large share of football's headers come from corners,
  which are 0.02 a team a match until proposal 5. `docs/THE_FOOTBALL.md` 29.
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

## The figures

A look pass over the players, judged against two references: a Sokpop-style
five-a-side game, and a rank of toy footballers. `DECISIONS.md` eighth to tenth
carry the reasoning, including two reversals.

Where it got to. Head 30-35% of height, scaled on two axes so a squad has long
faces and wide ones; legs 0.50 of height, torso 0.27, thin limbs, small hands,
rounded shoes, shorts to mid-thigh. Height and build draw from a bell with
tails, so the giant is built like one. Hair is a shell pushed back off the skull
plus pieces — curls, quiff, tufts, sideburns, widow's peak, a mass down the
back. The nose is a bump on the head from a library of six, not a mark on the
texture. Brows, eyes and mouth are per-player and independent of the five
expressions, and the brows carry the expression, which is where a Mii gets its
range. Kit trim — V-neck, cuffs, sock hoops — and a soft vinyl sheen on the
figure only. No ink outline: §9.7's register governs the writing, not the art.

`./run.sh parade --seed N` is the view they are judged in: four of that seed's
players at reading distance, turning, captioned with number, name, height and
appearance seed. `1-5` for the expressions, `--turn 180 --still` for the backs,
`--shot out.png` for a frame with no display. The same squad `view3d --seed N`
plays, so a note taken in one holds in the other.

A third reference — four images of a chunky moulded vinyl footballer — moved it
again (`DECISIONS.md`, eleventh) and reversed part of the tenth: legs 0.50 of
height down to 0.26, torso 0.27 up to 0.37, the skull back up to 0.31-0.35, wider
shoulders. The squat toy rather than a small man. With it: crease shading in
every view, which is the largest single change and the one with an unmeasured
cost; the drawn face lit and sheened like the head instead of unshaded; brows as
moulded ridges in hair colour rather than ink, posed from the same table the face
is drawn against; eyes a quarter larger; fatter and more numerous curls with a
skirt carried down past the ears; and a paper floor under the parade.

**Not yet judged by the owner, and this is now a large unjudged pile.** Nothing
in either pass has been looked at. Two things to watch for first, because they
are the changes most likely to be wrong: whether a leg at 0.26 of height still
reads as a stride from the match camera, which is exactly what the tenth
amendment lengthened it to protect, and whether the moulded brows land where the
drawn ones did — they are placed by arithmetic off the face grid, and that
arithmetic has never been seen to produce anything.

**Crease shading has not been measured.** It is a screen-space pass and `view3d`
carries twenty-two figures. `./run.sh perf --profile` is the question if a frame
budget matters; `SimCharacterBuilder.add_crease_shading` is the one switch.

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
