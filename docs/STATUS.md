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

**7-8 not started.**

**9 has its data layer.** `world/` holds the §8 record — player, club, season —
with period-British name generation, derived epithets, traits carrying their
intended sim effect, and a belief table the screens read instead of the truth.
No season is played and nothing in `sim/` reads it; `docs/THE_PEOPLE.md` says
what is there and what is still loose. `./run.sh world` prints a club.

**10 not started.**

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
- **The value map is multi-step as of 2026-08-23** (`docs/THE_FOOTBALL.md` 8b),
  and it is the largest single move on the sparseness this list has recorded: the
  same eight seeds of ten match-minutes produced **1 shot before it and 11
  after**, at the same passing volume and completion. Every full-match figure in
  this file predates it and is stale by however much that is worth over ninety
  minutes; re-measure before quoting one.
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

The figures have now been looked at in the parade, and a round of fixes came out
of it that reading the code had not found: the shorts, the torso, the V-neck, the
moustache and the hair lumps were all placement errors rather than values, and
`DECISIONS.md` eleventh lists them. The moulded brows do land where the drawn
ones did.

**Still not judged by the owner**, and two things want his eye rather than mine.
Whether a leg at 0.26 of height reads as a stride from the match camera — that is
what the tenth amendment lengthened it to protect, and the parade cannot answer
it because nobody runs in it. And whether the kit trim should be ink at all: it
comes from `contrast_for`, which returns black against a light shirt, so a yellow
kit gets a black collar, black cuffs and black sock hoops. It is correct football
and it reads as the ink outline the eighth amendment threw out. Every kit in the
owner's reference is trimmed in white.

**Crease shading has not been measured.** It is a screen-space pass and `view3d`
carries twenty-two figures. `./run.sh perf --profile` is the question if a frame
budget matters; `SimCharacterBuilder.add_crease_shading` is the one switch.

## The scenarios, measured

2026-08-26, commit `0ce9da5` (the outlet wide), `./run.sh scenario --trials 160`.
About 4 points of standard error on a share near a half. Against the previous
commit at n=40 only `pocket` had moved, and this run confirms it.

```
                 goal  saved   off  block  lost  none | shot s shot m  box s cross drop m | touch gap s  away  back
1v1-clear         29%   22%   23%    1%   22%    2% |  2.07   17.6   1.14  0.03   3.6 |  5.1  0.90  1.42   4%
1v1-onrushing     49%   23%   20%    1%    6%    1% |  1.44   19.3   1.15  0.00     - |  4.6  0.60  1.15   9%
1v1-angle         28%   19%   12%    1%   38%    2% |  2.88   13.7   1.91  0.26   4.9 |  3.9  0.79  1.25   8%
1v1-chased         9%   12%   13%    0%   46%   20% |  4.07   16.3   0.82  0.29   2.3 |  5.4  1.03  1.67   3%
cross-early        7%    7%    2%    1%   69%   14% |  2.80   12.7   1.12  0.87   5.2 |  4.7  0.41  0.99   2%
cross-right       12%   12%   13%    2%   57%    4% |  2.44   12.7   1.52  0.77   5.6 |  4.7  0.37  0.92   5%
cross-left        12%   16%   10%    2%   58%    1% |  2.47   14.3   1.41  0.81   5.6 |  5.4  0.35  0.92   7%
cross-loaded      12%   15%   11%    4%   53%    5% |  2.36   12.8   1.46  1.01   5.2 |  3.7  0.27  0.68   2%
cross-byline      17%   18%   18%    4%   42%    1% |  2.07   11.4   2.42  0.07   8.3 |  4.7  0.35  0.73   7%
cross-deep        10%   10%    8%    6%   63%    2% |  2.26   12.1   1.38  0.87   6.7 |  3.8  0.35  1.15   4%
cross-pullback     8%    4%    5%    3%   79%    0% |  2.10    9.9   1.58  0.01     - |  3.8  0.30  0.77   6%
cross-open        76%    1%   24%    0%    0%    0% |  1.68   11.2   2.53  1.00   1.3 |  1.0  0.00  0.00   0%
through-ball      11%   11%   17%    1%   54%    8% |  3.47   19.5   0.44  0.02   2.7 |  8.2  0.27  0.74   2%
switch             8%   10%    6%    2%   62%   11% |  3.03   13.4   0.63  0.18   5.2 |  5.1  0.44  0.92   2%
build-up           0%    0%    0%    0%   18%   82% |     -      -   0.00  0.00     - |  2.8  0.26  0.66   0%
pocket             6%    5%   12%    1%   35%   41% |  3.25   17.8   0.36  0.23   5.8 |  8.1  0.36  0.81   1%
shot-edge         32%   29%   31%    1%    4%    3% |  0.53   17.5   0.76  0.01     - |  3.3  0.32  0.79   3%
volley            29%   38%   31%    2%    0%    0% |  0.95   13.4   2.11  0.00     - |  1.4  0.84  0.27   2%
long-range        40%   28%   27%    0%    5%    1% |  1.22   19.7   0.77  0.00     - |  5.5  0.24  0.67   3%
race              17%   14%   16%    0%   51%    2% |  1.88   19.0   0.45  0.00     - |  0.8  1.51  0.29   2%
aerial             2%    4%    3%    0%   68%   23% |  5.30   16.1   0.27  0.04   1.5 |  3.5  0.94  0.69   1%
hold-up            7%    8%    7%    1%   55%   22% |  4.42   13.9   0.61  0.23   5.0 |  7.0  0.37  0.88   3%
take-on            5%    5%    6%    0%   78%    6% |  2.30   15.8   0.61  0.55   4.1 |  2.3  0.31  1.02   1%
corner-right      14%    2%    9%    2%   48%   24% |  3.46    7.3   1.07  1.01   5.3 |  1.5  0.03  0.05   4%
corner-left       11%    2%    8%    6%   51%   22% |  3.50    8.4   1.11  1.02   5.1 |  1.4  0.05  0.04   4%
fk-shot           21%   28%   21%    2%   29%    0% |  3.18   19.4   0.91  0.39   2.4 |  1.2  0.14  0.08   2%
fk-wide           14%    8%   15%    2%   51%    9% |  4.65   10.4   0.99  1.00   4.0 |  1.8  0.08  0.10   4%
penalty           79%   21%    0%    0%    0%    0% |  1.18   11.0   0.52  0.00     - |  1.0  0.00  0.00   0%
throw-in           4%    3%    3%    2%   74%   14% |  7.84   14.3   0.56  0.16   8.3 |  8.0  0.41  0.89   1%
goal-kick          0%    0%    0%    0%   33%   67% |     -      -   0.00  0.00     - |  2.3  0.21  0.40   1%
```

Sanity holds: every attacking row shoots, `gap s` under 1.5 s everywhere (the
`race` 1.5 is the knock in behind itself), `away` under 1.7 m. `build-up` and
`goal-kick` have no shots by design.

What it says:

- **One-on-ones read right.** `clear` 51% on target, `onrushing` 72%. `chased`
  is the weak one: 46% lost and 20% `none` — one in five never goes for goal.
- **Crosses lose 53–79%**, with `cross` near one per trial and `drop m` 5–8: the
  ball is put in and comes down five metres from the nearest of ours. A
  box-attack problem, not a delivery problem.
- **`cross-pullback` and `cross-byline` never cross** (`cross` 0.01, 0.07). The
  cut-back from the goal line is either counted as a pass or never generated;
  `--acts` on those two says which. `pullback` at 79% lost is the worst row.
- **`cross-open`**: 24% missed with nobody defending. A finishing miss rate.
- **`pocket`**: 41% `none`, 11% shots. The outlet wide makes him keep it rather
  than lose it (`lost` 55% to 35% across the commit), and the clock runs out.
  Football or dithering is the eye's call: `view3d --scenario pocket`.
- **`take-on` 78% lost.** High against a real take-on, but `lost` swallows
  "beat him, then the cross failed" (`cross` 0.55).
- **Set pieces**: penalty 79%. Corners 13–16% shots on target. `fk-shot` 21%
  goals from 21 m is far above real; no wall yet.
- **`block` is 6% or under on every row**, `shot-edge` with bodies in front
  reads 1%. That is the missing defence, expected until the defensive pass.

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
