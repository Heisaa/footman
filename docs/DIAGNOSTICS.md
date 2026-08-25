# The instruments

What each one can see, and what none of them can. `CLAUDE.md` says which to run.

The §11 bands are blind to a whole class of question: an engine where the ball is
welded to the dribbler and one where it runs free produce the same goals per
ninety. These blocks answer **"why did that look wrong"**, which is the only
question being asked at this stage. A block that cannot be tied back to something
visible is measuring for its own sake.

`./run.sh diagnose --seed 7 --minutes 10` is about fifteen seconds. Use
`--minutes` freely — counts are normalised per 90. Do **not** pass `--reduced`
when measuring decision cadence; that tier strides the layer being measured.

## The blocks, and what each alone can see

Every one exists because a count in the event log cannot answer its question.

| Block | The question only it answers |
|---|---|
| `Ball control` | how far from the body each touch is made, and the rhythm of a carry |
| `Chasing the carrier` | where the nearest defender stands relative to a running carrier, and how long he sits in the slipstream — a tailgating defender appears in no touch, duel or recovery |
| `Passing by body angle` | share, completion, and mean *length* by the angle between body and ball — the decision layer's half and the execution layer's, side by side |
| `Offering for the ball` | how a man made himself available, and whether the ball came; the top half is `SimOffBall`'s own account, the bottom half comes off the trace and owes the sim nothing |
| `A man could be played in behind` | which gate refused the through ball, over every teammate ahead of the ball rather than every decision |
| `The two seconds after a regain` | the same three questions asked of the counter's window instead of the match |
| `The width` | the z-extent of the side in possession, and how many of its men stand within twelve metres of its ball — a clump retains the ball fine and cannot pass out of itself |
| `The clump` | the density the eye sees: distance to the nearest shirt of the same colour, how many of a 5 x 3 grid's cells the ten outfielders are spread over, and how many of both sides stand inside one circle round the ball. `The width` is satisfied by two men on the touchlines while the other eight ring the carrier |
| `Holding the shape` | whether the shape the side is standing in *is* the formation, and which errand took it somewhere else. The only block with both numbers side by side — every other one reads positions, and `shape_position` slides every station with play, so a back four squeezed into the middle third may be exactly where the formation asked or nowhere near it |
| `Why an option lost` | which *term* beat the option that lost: `success 0.05 v 0.45` is a pass model problem, `gain 0.02 v 0.10` a value one |
| `what the pass model made of them` | `success` broken into its five factors — a product of 0.05 could be one factor at 0.05 or four at 0.55, which are unrelated faults |
| `is it ordered?` / `which factor knew` | the same calibration one ball at a time: does the model rise across its own buckets, and did each factor separate the balls that arrived from the ones that did not |
| `Shots by distance` | whether the attack ends in anything, and from where — plus expected goals per attempt, which tells "shoots from anywhere" from "walks it in" |
| `the save model resolved N` | *why* a goal-bound shot went in: the reach envelope and the save roll are two stages that multiply, and only the second used to be visible |
| `Where the pass was aimed` | a ball played into grass the opposition owns — identical to a good ball in every count, and it found a quarter of all passes threaded within 1.5 m of a defender |
| `Passing by direction` | which way the ball went and what it was *worth* (`xT gained`), whether the receiver kept it, whether passes string into moves |
| `Restarts` | how long the ball sat there, and where the side actually stood when it was struck |
| `In the air` | headers split by intent — cleared, at goal, to a man, down for himself — chests, and the keeper's claims. The four are different acts and a count of headers cannot tell them apart: `docs/THE_FOOTBALL.md` 42 was a striker playing the defender's one |
| `Goalkeeping` | split by whether there was anything to defend on purpose |
| `Taking it down` | what a first touch did, bucketed by where the ball ended up relative to *where the man wanted to go* |
| `Under challenge`, `touch` column | how big the carry touch was, by how hard he was being closed down. A row that does not shorten as pressure rises is a carrier who has not noticed the man on him |
| `Where the carry went` | the touch judged by what was in front of it — a touch into empty grass and one into a defender six metres up the lane are the same kind, same size, same player |
| `The small acts` | the mechanics that leave no event of their own: first-time balls, layoffs, setting touches, dummies, shielded holds, cuts, chips — and the two ways a teammate never reaches the passer's list at all: he could not see him, or the cap cut him |
| `Did he have a safe pass?` | whether a body near the ball was an *option*; a man with a defender in the lane is a pass that gets cut out |
| `How the ball changes hands` | which touch put the ball out, over which line, with how much room beside him |
| `When the cross drops` | who is there when it comes down — read off the trace at the strike tick plus the flight. A cross into an empty six-yard box and one onto three heads are the same event in every other block |
| `The ball in behind, as a strike` | the through ball as a *weight*: did it arrive slower than the man can run, was it aimed further ahead than he can cover, did it reach the man it was for |
| `What became of the ball` | what a spell of possession produced — the only block that reaches forward from an act to an outcome |
| `Chains` | where an attack stopped, link by link, including links no event log holds: a cross that was never a candidate leaves nothing behind |
| `The coin the softmax tossed` | the only unconfounded comparison here — see below |
| `Where a term changes the decision` | `--ablate`: whether a term in the score can reach the pick at all |

## Reading them without being fooled

- **Read a gate tally by asking first what its denominator excludes.** `A man
  could be played in behind` used to open on a *committed* run, and a committed man
  passes `moving_on` by construction — so the branch that was broken was the one
  branch the instrument could not see.
- **`received` alone cannot say why a run failed.** `offered` is whether it was
  ever a scored candidate; `best w` is the largest share of the softmax it ever
  held. Never-listed and always-losing are different files. `cut short` is a third
  case: the team lost the ball mid-stride.
- **A row that is missing is not a row at zero.** The block prints no zeros, and an
  absent row looks exactly like a run the engine chose not to make. `box` was absent
  for two rounds of fixes while an out-of-bounds error killed it silently. Read the
  whole output, not a `grep`.
- **When a counter and the trace disagree, believe the trace.** An intent taken and
  never resolving into a body arriving somewhere is a run that exists only in the
  counter.
- **`and of the ones it played` is the calibration; the table above it is not.**
  That one is the best *rejected* ball of its kind, and selection is not the same
  size for every kind — a through ball loses fourteen times for every one played, an
  ordinary pass twice.
- **A mean against a mean says the model is out by a factor and stops there.** It
  cannot tell one term charging for something the match never does from every term
  being a little strict. `which factor knew` is what can: **a factor with no spread
  decided nothing, and the model is out by the whole of it.**
- **The `gain` column is not comparable across kinds.** A shot carries a gain of 1.0
  by construction. Compare within a column, on `success`.
- **`Holding the shape`: read the second table before the first.** `off station`
  splits into `pulled`, how far the errand moved his target off the formation's
  point, and `behind`, how far he is from that target — and `behind` is only about
  him if the target stood still. The second table says how fast the target was
  moving, and at 4 to 7 m/s against a footballer's 7.5 flat out there is no pace
  that closes it. Read that way it found the live ball driving every station in
  the side; read the other way it says "he is too slow", and that was tried and
  measured nothing (`SimMovement.SHAPE_SPEED`).
- **`over 8 m/s` is the column for anything that happens at a moment**, and the
  mean beside it cannot see those at all. A station that teleports fifteen metres
  once a turnover and stands still in between reads as a gentle drift; the share
  of samples where it outran a sprinter reads as what it is. It is how the phase
  switch was found and how the fix was checked — 1.4/1.3/0.7% of samples down to
  0.7/0.6/0.3% over three seeds. What is left of it is `SHAPE_BALL_LEASH` doing
  its job on a ball hit sixty metres, which is the one time a side really is
  dragged at the speed of the ball.
- **`pulls in` is the column that ranks the arms**, because it is the share and
  the gap multiplied and the arms sum to the total. An errand that draws a man ten
  metres onto the ball on 2% of samples is not the swarm; one that draws six on
  40% is. `chase` and `press` belong near the ball and are not faults there.
- **A constant whose input range nobody measured may be doing nothing.** The
  `turnover_exposure` line prints what the term actually came out at, which is how
  you tell inside one run.
- **`--ablate`: read `in`, `on score`, `flips`, in that order.** `in` at 0% — not
  wired to its situation, and nothing downstream can be its fault. `on score` at ~0
  — applied and never varying, so it shifts every option alike. `flips` at 0% with a
  real `on score` — something bigger beats it, which is a judgement rather than a
  bug. It found `focus_at` multiplying every gain by exactly 1.0 in every match.
- **A term is measured against the plans the match was played with.** A prior that
  only varies away from balanced reads as inert on the default plan. Run it both
  ways before calling a tactical term dead.
- **`The coin the softmax tossed` is random assignment, and read `p` first.** When
  two kinds score close together, which one is played is settled by `ctx.rng` and
  nothing about the situation — so conditioning on near-ties is a real trial. If the
  two sides of a row are not near even, the conditioning failed and the row is worth
  nothing. It is a *local* effect and it wants a full-length match.
- **Outcomes cannot be paired with attempts by their order in the log.** Not every
  attempt resolves, so a positional pairing desynchronises at the first missing one.
  Join on `poss` instead. It once reported 20% against an actual 78%.
- **The half-time flip is applied once**, and anything reading a position out of the
  log has to know which way the team was attacking. Measured against the wrong goal,
  a tap-in comes out at ninety metres. Anything reading the *trace* rounds the swap
  index **up** from the period event's tick.
- **`What became of the ball`: the fate is precedence-ordered, not
  last-event-wins**, and the two joins are not interchangeable — the event that
  *ends* a spell is logged while that spell is live, the touch that *wins* the ball
  a tick early.
- **`Chains` stages are shares of the population, not nested subsets**, so
  `of above` can pass 100% — and that is the finding, not the bug: 22 shots against
  15 spells that reached the area is an engine shooting from outside the box.
- **Measure at `clock_rate` 10 and nowhere else.** The nine-minute match is the
  match that ships, so it is the one the numbers are tuned to (owner,
  2026-08-15). `--clock-rate 1` measures a match nobody plays. It is also not the
  shortcut it looks like: the clock rate moves scoring, by design, and moves
  almost nothing else — a cross is offered 11.7% of the time at both rates, a ball
  goes out of play in 1.4% of spells against 1.6%. A one-seed comparison across
  rates showed crosses 3 against 11 and through balls 7 against 24, and every bit
  of that was sampling noise. **A per-match tally at n=1 is noise about a rate; a
  chain at n=20 is the measurement.**

## The chain

Everything above measures what the football did. These measure **why a change to
it did nothing**. A constant reaches a goal down six links, each of which can
break on its own:

| | the link | what says it broke | how it breaks |
|---|---|---|---|
| 1 | the constant reaches the input that reads it | `--ablate`, `value` | a range the engine never enters |
| 2 | the term's output varies | `--ablate`, `on score` | applied, same for every option |
| 3 | it changes which option wins | `--ablate`, `flips`, `moves p` | dominated by something bigger |
| 4 | the option is generated at all, and played | `Chains`, links 1-4 | a gate upstream of every value knob |
| 5 | the act leads somewhere | `Chains`, `then …`; `What became of the ball` | the football stops a stage earlier |
| 6 | the act caused it, rather than sat beside it | `The coin the softmax tossed` | it correlated |

**Read them in order.** A term that never reaches the pick cannot be blamed for an
outcome, and a link broken at 2 makes every measurement below it noise. The first
three cost nothing and answer most complaints on their own.

**Link 0, which is not in the table because it is not a measurement.** Whether the
code runs at all. `BOX_EASE` sat behind an earlier `return` in the same function
and never executed once; `_cross_coming` returned `1.0` on every path into two
call sites that read it as a truth value. Both read as healthy in every block
here, because a run to a point is a run to a point and the diagnostics see the
point. The check is a counter on each arm of the branch — `Which idea he had`
carries one now, and `Holding the shape` is the same idea for the movement
ladder: `SimMovement._recompute_target` stamps `SimPlayer.errand` from inside the
branch that takes it, so an arm that stops firing stops appearing rather than
looking healthy — and it costs a line.

**The chain has a movement twin, and it is shorter.** A positioning rule reaches
the grass down three links, and only the third is a distance:

| | the link | what says it broke |
|---|---|---|
| 1 | the arm fires at all | `Holding the shape`, `share` |
| 2 | the point it names can be occupied | the same block's `station m/s` / `target m/s` / `switched` |
| 3 | he is standing on it | `pulled`, `behind` |

Read in that order, the clump resolved to link 2 — the shape was defined faster
than a footballer can run — and every reading of link 3 before that was noise.

**Two things the chain cannot say.** That a term is *right* — `_pass_success`'s
`control` factor passes links 1 to 3 outright and was worth nothing, because the
balls it liked did not arrive any more often. And that it is about the right
player — `_lofted_success` priced every cross with `passing` while the ball is
struck with `crossing`; only reading the two call sites together finds that.

**Link 4 is where the complaints usually die.** Of 122 wide moments in the
opponent's half, only 20% produced a cross candidate at all, and raising
`LOFTED_BIAS` moved `it was played` by sixty points and `a cross was offered` by
−1.7. **A value knob cannot create an option that was never generated.** So an
instrument's population is deliberately wider than the mechanic it measures — one
that adopts every gate the mechanic has can never report it refusing to fire.

`./run.sh chains --against runs/before.json` asks links 4 to 6 about a *change*
rather than a match. **Read the conversion column, not the counts** — a change
that produces more possessions moves every count and has told you nothing. Several
seeds, not one: two runs of a seed become different football within seconds of the
first different decision.

## The benches — no match, no ticks, instant

The three questions a match cannot answer, because a match mixes the rule with the
whole of the selection above it.

- **`./run.sh strike` is link 0**, and the only thing that can say the decision
  layer is being told the truth about the *ball*. It strikes the real ball with the
  real perturbation and integrates where it lands. **Read the axes separately** —
  the sideways pair was right the whole time the long pair was out by four. The
  `bias` column is the long axis signed, because an RMS cannot tell a scatter from a
  systematic short and those are different faults. **Anything touching `_perturb`,
  `aim_sigma`, `weight_sigma` or the lofted solver wants this run afterwards.**
  **Each kind is read where its man meets it**, and getting that wrong cost a
  measurement: a ground pass at the pace it was struck to arrive at, a lofted pass
  where it stops because `LOFT_RUNON_SHARE` prices it to sit down, and a cross
  coming down through heading height — read like the lofted ball, the cross was
  being charged for grass it crossed at rest, tens of metres past the far post,
  and `CROSS_RANGE_SPREAD` had been fitted to that.
- **`./run.sh behind`** sets the through-ball geometry rather than sampling it: can
  the man it is for get to it? The `run` column says whether the aim came from a
  committed run or the projection made in its absence — and the projection is
  invisible to the in-match gate tally, which only counts committed runs.
- **`./run.sh box`** does the same for the one-on-one, which a match produces zero
  to three times an hour, so it cannot be measured from matches at all. It runs at
  the compressed clock deliberately: `shot_appetite` is part of what decides this.

## The scenarios — set the situation, run it forward, watch it too

`./run.sh scenario` and `./run.sh view3d --scenario NAME`. The benches above set a
geometry and ask the decision layer what it would *choose*, without ever ticking
the clock. A scenario sets the same kind of geometry and then **plays it**, for a
few seconds, and says how it ended.

**It exists because the two slow loops are the same loop.** A match is a slow,
noisy way to ask about a moment that happens four times in it, and watching for
that moment is worse — nine minutes for a handful of glimpses. A scenario is the
moment, twenty times, in seconds.

**The two halves are one definition** (`SimScenario`, in `sim/` for exactly this
reason). `./run.sh scenario` runs it many times and prints shares;
`view3d --scenario NAME` puts the identical starting position on screen, plays it
out, and repeats it on the next seed so the same thing can be watched over and
over. **So the numbers and the eye are looking at the same football and can
disagree usefully** — which is the whole point, and is not true of any other pair
of instruments here.

- **The six outcome columns are one vocabulary for every scenario**, deliberately:
  `goal saved off blocked lost none`, shares that sum to 100. A per-scenario
  outcome set would be a new table to learn each time. `goal + saved` is the shot
  that was worth taking, `off` is the finish, `blocked` belongs to the defence,
  `lost` is the situation ending before a shot, and `none` is the clock running
  out with the ball still ours — on a one-on-one, a man who never went for goal.
- **`touch`, `gap s` and `back` say whether the football was real**, which the
  outcome columns cannot — a goal scored off a keeper who handed the ball back is
  a goal in the `goal` column and nowhere else. `touch` is attacking touches per
  trial (a man carrying it takes one every three tenths of a second), `gap s` the
  longest stretch the ball went untouched with nothing struck — a hanging cross
  does not count, a ball rolling away from its owner does — and `back` the share
  of trials where the defence touched it and we had it again within a second.
  **`1v1-clear` found `docs/THE_FOOTBALL.md` 39 with this column** and nothing
  else could have: `gap s` 2.8 and `lost` 56% against `goal` 20%, on a row whose
  outcome columns read like a one-on-one that sometimes goes in. It was a single
  24 m knock into the keeper's hands. It now runs `gap s` 1.1 and `lost` 12%.
- **`away` is the distance half of `gap s`, and it is the one the eye reads.**
  Seconds cannot tell a man running alongside his own ball without touching it —
  football — from a man standing still while it rolls off him. Same seconds,
  different pictures. `away` is the furthest the ball got from the man whose it
  was while nobody had struck it, and it only counts once somebody has actually
  controlled it: before that a scenario's ball has a nominal owner thirty metres
  away who has never been near it, and `aerial` read a drift of 59 m. **A carry
  that is working keeps it inside about a metre and a half.**
- **`cross` and `drop m` separate the two ways a cross fails**, which are fixed
  in different files: crosses struck per trial, and how far the nearest of ours
  was from the ball when the first of them came down through heading height. A
  scenario that ends with no shot is either a ball nobody put in or a ball nobody
  attacked, and **29** is the second of those. **A `drop m` in the twenties is
  neither and is a bug in the restart**: `fk-shot` read 20.8 because nothing put
  men in the box for a free kick and the ball was struck at 0.7 s anyway
  (`SimSetPiece._load_box`, `FK_BOX_FLOOR`). It reads 3.0.
- **`--acts` is the second instrument and answers the question the table cannot:
  what was actually played.** Touches by the attacking side per trial, by kind,
  then duels, offsides and fouls. It is the only one of the three that separates
  **an act that is never a candidate from an act that is chosen and fails** — the
  distinction `docs/THE_FOOTBALL.md` says this project has been caught by three
  times. A kind nothing ever played is not printed as a column at all.
- **`replay --scenario NAME --tick 1` is the fourth, and it is the only one that
  shows the candidate *list*.** The three below say what was played; a row that
  reads wrong because an act was never on the list, or was on it and lost, is
  answered by nothing else. `docs/THE_FOOTBALL.md` 41 is the worked example: the
  act was generated, the beat that should have beaten it was applied, and the
  line `bias 5.74` beside `set 0.50` is the whole finding.
- **`--trace N` is the third, and the other two send you to it.** Every event of
  trial N of each selected scenario, in order, with who and from where. A share
  says a situation ends badly and `--acts` says which act was played; only the
  order says the keeper caught it at 2.6 s and the striker had it back at 3.3.
- **A share near a half carries about `50/sqrt(n)` points of standard error**, so
  8 points at the default 40 trials. The header prints it. **A row that moved by
  less than that has not moved**, and `--trials` is the answer before believing a
  small one.
- **The variants are different questions, not samples of one.** A keeper set on
  his line and a keeper committed to closing are opposite problems; splitting them
  is what lets a change say *which* it moved.
- **The one-on-one starts twenty-five to thirty metres out, with the defence
  higher up the pitch than the ball** — a man who has just been played through,
  not a man stood over it with everyone already goal-side. The first version was
  the latter and read as a penalty with a run-up: the only thing left to decide
  was where he put the shot.
- **Each trial is a different seed, so the squads differ.** The situation is fixed
  and the players in it are not: a scenario is a property of the rules, not of one
  striker.
- **Thirty situations, in five families**, so a change can be asked which
  kind of football it moved:
  - **the one-on-one** — `1v1-clear`, `1v1-onrushing`, `1v1-angle`, `1v1-chased`
  - **the cross** — `cross-early`, `cross-right`, `cross-left`, `cross-loaded`,
    `cross-byline`, `cross-deep`, `cross-pullback`, `cross-open`
  - **the pass** — `through-ball`, `switch`, `build-up`, `pocket`
  - **the shot** — `shot-edge`, `volley`, `long-range`
  - **the duel** — `race`, `aerial`, `hold-up`, `take-on`
  - **the restart** — `corner-right`, `corner-left`, `fk-shot`, `fk-wide`,
    `penalty`, `throw-in`, `goal-kick`
- **The cross family varies two things and only two**, because a row that
  differs from its neighbour in one thing is the only kind that answers
  anything. **Depth**: `cross-early` at 24 m, `cross-right` at 30 and
  `cross-deep` at 49, all on the right flank at the same width, plus the byline
  pair. **Bodies**: `cross-loaded` is `cross-right` with three of ours already
  attacking the box and nothing else changed, so the difference between the two
  rows is what the runs are worth — which no match measurement has ever been
  able to separate from the delivery (`docs/THE_FOOTBALL.md` 29).
- **A loaded row starts its men short of the ball and moving**, twelve metres
  off the point they are running at (`ARRIVAL_BACK`, about `SimOffBall.BOX_WINDOW`
  of running). Men standing on the penalty spot when the ball is struck would
  measure the delivery and nothing else, which is what the empty-box rows are
  already for.
- **`cross-open` is the control, and it is the only row with nobody defending.**
  No back line, no goalkeeper, three of ours attacking the box, and the ball
  already in the air. It asks what no other row can: **can the side finish a
  cross at all**. A ball met in front of an empty net that does not go in is a
  fault in the header or the first touch, and nothing to do with a defence the
  attacking pass has not built yet. Two things about it are deliberate and both
  were measured before they were chosen. **The ball starts struck**, because
  given it at his feet in an unopposed box the engine does what a footballer
  does -- walks it in, 0.05 crosses a trial -- and the finish stops being the
  question. **And the ball starts a quarter-second into its flight**, past the
  man who hit it: left on his boot, `SimDuel` hands it straight back to him and
  it never leaves the flank.
- **`cross-pullback` is a pass row, not a cross row.** From the goal line the
  cut-back is the act, so it is read in `--acts` — 0.9 ground passes a trial
  against 0.0 crosses — and the `shot m` column is what the act is for. It
  reads 10.5 with `lost` at 82%: the ball is cut back and the box eats it,
  which is the defending half of **29** and belongs to the defensive pass.
- **`build-up` and `goal-kick` read backwards**, and they are the only two:
  `none` is the good outcome (the ball is still ours) and `lost` the bad one.
  Playing out is the commonest thing a defence does with the ball and nothing
  else on this page asks whether the engine can do it. **They are also the only
  two that stop early on success** (`SimScenario.escape_x`): past the top of the
  defending third with the ball still ours the situation is over, because a row
  that played on was scoring the next ten seconds of match instead. It read 70%
  and 80% `lost` while doing that -- a goal kick worked out through the press,
  six passes and sixty metres, then tackled on the halfway line at 10.5 s, came
  back on the row as a failure to play out. They now read 15% and 28%.
- **The restarts are `SimSetPiece`'s own routines, started rather than authored**,
  and both sides are settled around the spot the restart will be taken from
  before it begins. That last part is not cosmetic: settled around the middle of
  the third instead, a throw-in had no teammate inside `throw_range` and nine in
  ten came out as a clearance — the row was measuring its own placement. **A
  scenario that places the bodies badly produces a bug report about the
  scenario**, and two of the first twenty-five did.
- **It runs at the standard compressed clock**, for `./run.sh box`'s reason —
  `shot_appetite` is part of what decides a shot, and a bench that turned it off
  would describe a match nobody watches.
- **Watching one runs at real time**, and it **ends when the situation does** —
  `SimScenario.live`, the same rule the table scores by, plus a hold so the eye
  sees how it ended. Both were the other way round and both were wrong: half
  speed was sized for a striker starting on the edge of the box, and a fixed
  clock meant the screen played on past the moment the row stopped counting and
  showed a goal the table had already called `lost`.

## The live overlay

`./run.sh view3d --debug`, or **`F1` in any running match** — built the first time
it is asked for, so a match nobody is debugging pays nothing. The blocks above
answer "how often, over a match"; the overlay answers "that man, just now, why".

Everything about it is a readability decision: **one subject, the man on the
ball**; **latch, never stream**, so the panel holds his last decision after he has
released it; **show what he was choosing between**, not the twenty enumerated;
**about twelve lines, ever**.

- **The carrier panel** prints the chosen option, what it beat, and the three
  numbers each score is made of. A carry taken 0.003 ahead of a pass and one taken
  0.03 ahead look identical on the grass and are different complaints.
- **`LAST 8 ON THE BALL`** is the same man's last eight decisions. A midfielder who
  has hit the same nine-metre square pass every time shows up here and nowhere else.
- **Layers** `1` options, `2` pressure, `3` runs, `4` chasing, `5` value, `6`
  belief, `7` trails, `8` names. Layer 1 earns the overlay: "he never passes to the
  winger" resolves to "not a candidate" or "scored 0.02 lower", which are two
  different jobs. Layer 6 is the other half — an option he cannot perceive is never
  scored.
- **On layer 1 a carry has two marks.** The ring is the **horizon**, how far the
  direction can be pursued, which is what every term was read at; the cross is where
  he expects to meet the ball again, which is where it goes.
- **`M` marks the moment** — writes `bookmarks/seedN-tT.md` and the frame: ball,
  everyone within twenty metres, every decision and event of the last eight seconds,
  and the command that reproduces it.
- **`,` `.` step the picture, `<` `>` jump half a second.** Thirty seconds are kept,
  drawn from the recorded sample rather than the context, so the panels belong to
  that moment. **`enter`** plays on from there — same football, rebuilt from the seed
  and fast-forwarded, which costs what those minutes cost. **`N`** next match, **`R`**
  this one again; `N` also walks the squad-quality ladder.

**What it cannot see.** Nothing off-ball: the sink hangs off the on-ball decision,
so a run never made appears nowhere — the layers answer that, and they are
positions rather than reasons. A layer turned on after the fact has nothing to draw
for earlier samples. Beyond thirty seconds is gone; `--from-bookmark` or
`./run.sh replay` reaches it. **The compressed clock makes it unreadable**, so
`--debug` drops to real time unless told otherwise; slow motion and stepping are
worth more than any panel, because most of what looks wrong is two seconds long.

**The sink is a one-way tap** — off unless asked for, never touches `ctx.rng`,
never read back by `sim/`. `determinism --debug` runs one pass with it on and one
off and compares digests. It is deliberately not a telemetry event kind, because
`canonical_text` is hashed by the golden test.

## Batches

A batch measures a machine that is missing parts. It costs minutes and returns a
number that is void as soon as the next mechanic lands.

**Of the two printed tables, only the sanity ranges mean anything yet.** The §11
target bands are printed for drift and become pass/fail only at the tuning freeze
(`--strict`, which `accept` passes). Neither table is a verdict on a new
behaviour. **A high goal count is expected right now** — the goals ceiling is
suspended for the attacking pass (`PLAN.md` §11.4), and the runner says so under
the table.

**Quote the sample size whenever you quote a band result.** The runner tags
undersampled metrics; do not launder the tag away. Sanity ranges are judgeable
from a handful of matches, most tuning bands want 40, and the score-draw rate is
not settled below 200.

`--keep` leaves the shard JSON on disk; `./run.sh aggregate` re-judges a kept set
without re-simulating and `compare` judges two against each other, which is how
the `tactics` arms are compared. Neither is in `--help`.

**Do not edit `run.sh` while a batch is running.** Bash reads a script
incrementally, so an edit shifts the byte offsets under the running instance and
it dies partway through, after the simulation time has been spent.

**Everything measures the compressed match, and that is the point.** `clock_rate`
defaults to 10, which is the match that ships, so it is the match the numbers are
tuned to (owner, 2026-08-15). The scoring fit is part of the format rather than
inflation to be corrected for. **Do not run `--clock-rate 1`** — it measures a
match nobody plays. `--urgency U` forces the fit at any clock rate and is the way
to ask what the fit alone is doing, without leaving the shipping clock.
