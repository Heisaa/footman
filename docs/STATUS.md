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
instanced crowd. One fixed camera on the halfway line, panning to hold play and
never cutting. A hand-drawn scoreboard over it. Animation runs at the
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

**The defensive pass**, from 2026-09-02, and goals are meant to fall as it
lands — `PLAN.md` §11.4 says why, `docs/THE_FOOTBALL.md` has the order of items.

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
- **The middle third still holds most of play** — 70% of touches, 17% in the
  final third since the link station (2026-09-02); 78% and 12% before the
  attacking pass. The pass model no longer referees a race nobody is running, and
  progression improved with it, but the lock eased rather than lifted. What is left
  is the runners (33), midfield structure (30), the flat value map (8b) and the
  correlated-terms half of 24.
- **The carry was the underconfident act, and is repriced (2026-09-02).** Over
  eight seeds it was priced 0.50-0.60 and kept 79%; the pass beside it 0.80 and
  78%. Priced as a man with the ball at his feet, looking as far as the lane
  will run him, with the knock past a man from a jog on the list, a free man
  with grass ahead carries 35% against 12% and a possession sequence on seed 7
  gains 15 m where it lost one. The release rate itself (28) is untouched:
  still about a second a touch. `docs/THE_FOOTBALL.md`, "the confident
  carrier", has the rows.
- **Two fast test cases fail, and did before today's work** (checked at
  `0684b82`, identical figures): `test_value_field`'s peak threat reads 0.126
  against a floor of 0.15, and `test_distances`' moving man's 20 m and 40 m
  lofted passes finish 27.3 m and 46.0 m out against ceilings of 26 and 46.
  Neither was touched; both want a look.
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
  `_worth_at` and `QUOTA` (and `CROSS_ON`, reverted later) went on goal cost,
  measured against a missing serve and byline — re-try them after 33 and 51;
  `docs/THE_FOOTBALL.md`, the order.
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
back. The nose is a round tip on a thinner bridge or a plain button, from a library of twelve, not a mark on the
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

2026-09-02, commit `75f4e6e` plus the chaser guard (the re-watch of the attack
that closes item 5 of the defensive pass), `./run.sh scenario --trials 160`,
every row, against the same rows at `9f31dfe`, the last commit before the
pass. About 4 points of standard error on a share near a half.

```
                 goal  saved   off  block  lost  none | shot s shot m  box s cross drop m | touch gap s  away  back
1v1-clear           44%    21%    22%     0%    12%     1% |   2.15   16.8  0.91   0.01      - |   3.4  1.72  1.64    3%
1v1-onrushing       36%    13%    12%     0%    35%     4% |   2.15   15.6  1.16   0.03    3.3 |   4.8  0.93  1.20    4%
1v1-angle            4%     5%     4%     1%    78%     8% |   3.23   16.9  0.53   0.03    4.6 |   1.8  0.05  0.11    1%
1v1-chased           4%     5%     4%     0%    61%    27% |   4.41   16.0  0.47   0.04    3.6 |   3.2  0.30  0.46    1%
cross-early         10%     2%     4%     2%    69%    12% |   3.44   19.5  1.12   0.28    6.4 |   5.5  0.59  1.02    2%
cross-right          5%     4%     6%     1%    79%     6% |   3.01   14.8  1.52   0.13    4.9 |   4.6  0.54  0.99    1%
cross-left           3%     5%     4%     1%    78%     9% |   2.58   15.5  1.46   0.15    5.1 |   5.0  0.48  0.94    1%
cross-loaded        14%     7%    11%     1%    63%     3% |   2.77   12.2  1.66   0.67    3.7 |   4.5  0.26  0.71    2%
cross-byline        12%     6%     8%     7%    68%     0% |   2.22    9.0  2.51   0.03    5.6 |   3.6  0.31  0.83    4%
cross-deep           4%     6%     6%     3%    77%     3% |   2.29   12.1  0.80   0.69    6.8 |   3.9  0.34  0.98    2%
cross-pullback       9%     5%    11%     6%    66%     4% |   2.09   12.5  1.68   0.03    1.4 |   3.2  0.30  0.60    3%
cross-open          80%     1%    19%     0%     0%     0% |   1.68   11.2  2.51   1.00    1.2 |   1.0  0.00  0.00    0%
through-ball         6%     6%     6%     0%    61%    22% |   4.19   13.6  1.01   0.09    8.1 |   4.8  0.20  0.56    4%
offside-trap         6%     4%     9%     0%    55%    27% |   4.26   15.5  0.55   0.03   13.5 |   4.2  0.73  0.47    2%
switch               6%     4%     5%     2%    55%    28% |   4.15   16.5  0.56   0.21    5.0 |   6.8  0.57  1.00    0%
build-up             0%     0%     0%     0%    15%    85% |      -      -  0.00   0.00      - |   2.7  0.19  0.59    0%
pocket               7%     8%     6%     1%    44%    35% |   3.23   15.4  0.40   0.21    8.3 |   7.8  0.42  0.93    0%
shot-edge           13%    15%    14%     4%    38%    15% |   2.13   13.8  1.48   0.03    2.7 |   6.4  0.54  1.02    3%
volley              36%    21%    22%    18%     2%     1% |   1.37   12.3  2.01   0.00      - |   4.2  0.75  0.76   11%
long-range          19%    16%    25%     1%    32%     6% |   1.49   18.4  0.97   0.01      - |   5.9  0.26  0.72    4%
race                20%    34%    32%     1%     8%     6% |   2.61   18.6  0.88   0.00      - |   1.6  2.29  0.12    0%
aerial               0%     0%     1%     0%    82%    18% |   5.58   17.8  0.03   0.02    5.7 |   1.8  0.86  0.33    1%
hold-up              6%     7%     6%     0%    55%    27% |   4.75   15.6  0.57   0.12    6.1 |   7.5  0.46  1.04    1%
take-on              4%     5%     9%     1%    69%    12% |   3.14   13.8  0.89   0.39    6.4 |   2.6  0.52  1.07    1%
curl-blocked         0%     0%     0%     0%    25%    75% |      -      -  0.00   0.00      - |   8.8  0.38  0.95    0%
curl-wrong           0%     0%     0%     0%    29%    71% |      -      -  0.00   0.01      - |   8.1  0.34  0.92    1%
corner-right         7%     2%     2%     2%    52%    35% |   3.80    8.0  1.18   1.01    5.4 |   1.4  0.05  0.06    1%
corner-left         11%     1%     8%     5%    49%    28% |   3.43    7.3  1.11   1.00    5.2 |   1.5  0.02  0.04    2%
fk-shot             21%    24%    18%     1%    37%     0% |   3.05   20.6  0.92   0.39    3.1 |   1.1  0.06  0.03    2%
fk-wide              9%     4%    16%     4%    59%     9% |   4.76   10.5  0.88   1.00    4.1 |   1.5  0.04  0.05    2%
penalty             80%    20%     0%     0%     0%     0% |   1.18   11.0  0.52   0.00      - |   1.0  0.00  0.00    0%
throw-in             2%     2%     3%     2%    71%    20% |   7.78   14.9  0.52   0.05    6.2 |   6.9  0.59  1.07    1%
goal-kick            0%     0%     0%     0%    22%    78% |      -      -  0.00   0.00      - |   2.4  0.12  0.29    0%
```

Sanity holds: every attacking row shoots, `gap s` under 1.8 s everywhere (the
`1v1-clear` 1.7 and `race` 2.3 are the knock in behind itself), `away` under
1.7 m. `build-up`, `goal-kick` and the two `curl-*` rows have no shots by
design.

What moved against the pre-pass tree, and what it says:

- **`volley` 25% to 36% goals, and it stopped reading as a volley.** Blocks
  8% to 18%, shots a trial 0.89 to 1.37, dribbles 0.9 to 3.1. The lunge model
  prices the first-time strike low with bodies in front, so he takes it down
  and carries three touches at twelve metres, and the defenders let him:
  `lost` 2%. Bisected to the block commit and to the lunge itself
  (`BLOCK_RANGE` 0 gives the old row back). The absence is the defender who
  closes a man taking a dropping ball down.
- **`shot-edge` 27% to 13% goals, `lost` 6% to 38%, `none` 2% to 15%.** He no
  longer shoots through two centre-backs, which is the row's question
  answered; what he does instead is carry into them and, one trial in seven,
  nothing. Owner's eye.
- **`1v1-clear` 35% to 44%.** A sum of small things -- the corridor pricing,
  the second man on the line, the box lane -- none alone beyond the error;
  every parry and keeper knob ablated to no move. Inside football's clean
  one-on-one rate; watch rather than tune.
- **The crosses lose 12-17 points more and score half as often** (`cross-deep`
  14% to 4%, `cross-left` 8% to 3%, `cross-right` 9% to 5%, `cross-early` 14%
  to 10%). Football completes a cross about one in four, so `lost` 70-80%
  reads right for the first time; the box runner is beaten to it by a defence
  that stands on the line of the ball. `cross-byline` went the other way, 6%
  to 12%. `cross-open` is identical: nobody defends it.
- **`hold-up` `lost` 68% to 55%**, goals 2% to 6%: the jockey stands off him
  and he keeps it. **`long-range`** 25% to 19% and `lost` 17% to 32%;
  **`race`** 28% to 20%: the defence nearer.
- **Unmoved**: `through-ball`, `pocket`, `take-on`, `switch`, `aerial`, both
  corners, both free kicks, `penalty`, `throw-in`, `goal-kick`, `build-up`,
  `curl-*`, `1v1-chased`, `1v1-onrushing`. `1v1-angle` reads 78% lost with
  1.8 touches and did before the pass (85%): a pre-existing row for the
  owner's eye, not this pass's.
- **`offside-trap`** is new: the line steps and deters, offsides 0.1 a trial.

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
