# The instruments

What `./run.sh diagnose` can see, what a batch can see, and what neither can.
`CLAUDE.md` has the rules for which to run; this file is the reasoning behind
them.

## Why the diagnostic blocks exist

The §11 bands are blind to a whole class of question. An engine where the ball is
welded to the dribbler and one where it runs free produce the same goals per
ninety. A defender who tailgates and one who gets round produce the same pass
completion. Minutes spent on a batch to answer "does this look right" are minutes
spent measuring the wrong thing.

These blocks are the instrument for the approach the project actually runs on —
make it look like football, and worry about the numbers afterwards. **They answer
"why did that look wrong", which is the only question being asked at this stage.**
The owner sees a thing; a block says what the engine did to produce it. A block
that cannot be tied back to something visible is measuring for its own sake.

`./run.sh diagnose --seed 7 --minutes 10` takes about fifteen seconds. Use
`--minutes` freely; counts are normalised per 90. Do **not** pass `--reduced` when
measuring decision cadence — that tier strides the decision layer, which is the
quantity being measured.

## The blocks, and what each one alone can see

**`Ball control`** — how far from a player's centre each touch was made, and the
interval and distance between consecutive dribble touches.

**`Chasing the carrier`**, off the positional trace — where the nearest defender
stands relative to a running carrier, split behind / alongside / goal-side, with the
length of the unbroken spells he spends in the carrier's slipstream. That is the
instrument for any question about how defending *looks*: a defender welded to the
carrier's back appears in no touch, duel or recovery, so no count in the event log
can see him.

**`Passing by body angle`** — every pass bucketed by the angle between the passer's
body and the line the ball was played along, with the share of attempts, the
completion rate, the mean technique-and-agility of the passers and the mean length
in each bucket. The share is the decision layer's half of the answer and the
completion rate is the execution layer's. A change to the facing model that moves
only one of them has done half of what it claimed.

The length column is the only place `SimTouch.strike_scale` is visible. A ball
played behind the body is not a worse pass, it is a shorter one — there is no
swing behind it — so the mechanic shows up as the mean length falling across the
sectors and as the far bucket completing *better* than the near ones, because
what is left of it is the short safe ball.

**`Offering for the ball`** — two halves that have to be read against each other. The
top half is `SimOffBall`'s own account of itself: how many times each way of making
yourself available was chosen, how often the ball then arrived, how many were cut off
by the team losing it, and how far up the pitch each kind of run went. The bottom half
comes off the positional trace and owes the sim nothing: with the ball at a man's
feet, how many teammates were inside a short pass, and how many were *actively* doing
something about it — coming to meet it, going into space, or beyond the last defender
— at a speed a shape-holder's jog cannot reach.

**`received` on its own cannot say why a run failed, and `offered` and `best w` are
there to split it.** `offered` is the share of runs of that kind that were ever a
scored pass candidate at all; `best w` is the largest share of the softmax the run's
own ball ever held, averaged over every run of that kind. A run nobody ever had on
his list and a run that was on every list and never chosen both come back as "not
found", and the fixes for them are in different files — the first is `_shortlist` in
`SimDecision`, which keeps six of ten teammates and ranks them by the expected threat
of the grass each is *standing on*; the second is what the pass is worth once it is on
the list. `cut short` is the third case and is neither: the team lost the ball
mid-stride. Read the three together or `received` will send you to the wrong layer.

`shot` is the possession ending in one while he was running, split out of `cut short`
because it is the attack working rather than the run failing — and it was most of that
number, which rose every time the engine got better at reaching the box. What is left
in `cut short` is a real turnover mid-stride.

**`A man was running in behind`** — the gates in front of the one pass the whole
counter is built around, and the population is a **runner rather than a decision**:
every teammate making the run at the moment somebody is deciding, filed under the
first gate that refused him, in the order the gates are applied. `Chains` can say the
run existed three times more often than the pass was offered and cannot say why, and
the answer picks the layer — `_shortlist` keeping six of ten is a different job from a
body-orientation range clamp, and both are upstream of everything the pass is worth.

It has already caught one proxy and left one piece of football standing: `not moving
forward yet` was 21% and is now 0%, because a man a stride into a committed run is not
yet at 1.2 m/s and the ball wants playing exactly then; `out of striking range` is 41–62%
and stays, because it is `SimTouch.strike_range` saying the carrier is facing the wrong
way. **A value knob cannot reach a candidate that was never generated**, and this is
the third time the project has been caught by that.

**`The two seconds after a regain`** — the same three questions asked of the window
instead of the match. `secure`, `break_bias` and `SimOffBall.BREAK_RUN` all fire
inside `SimDecision.REGAIN_WINDOW`, and until this nothing measured them there:
`Offering for the ball` answers over ninety minutes, and "the counter is not on" has
three causes that produce one number between them. Nobody on the winning side is
*eligible* to run; they are eligible and the run scores badly; or they run and the
man on the ball never picks them. The three live in three different files.

Read it top to bottom and stop at the first row that is wrong.

- the first pair of rows is **eligibility**, and it is the gate in `SimOffBall._assign`
  counted rather than reasoned about: each man on the side in possession is filed
  under the first of the gate's own tests he fails. **It is a pair on purpose** —
  `in the window` against `the rest of it` — because two men of nine resting is only a
  tax on the counter if the same row reads lower when the counter is off.
- `a run a turnover ended had served …%` is the physiology behind that, and it is what
  `_expire` charges the rest in proportion to.
- the third block is **scoring**: of the men who were free to be considered, how many
  actually took a run in the window, by kind.
- the fourth is the **carrier**, in the same `offered` / `best w` / `received` terms
  as the block above, over the offers made when the counter was on rather than all of
  them.
- `break_on` is link 1 for both multipliers hanging off it — the distribution of the
  number they are lerped through, over the decisions taken inside the window.

`Did he have a safe pass?` carries the same window on its last line, off the trace and
the recovery events rather than off the sim.

**`Why an option lost`** — the other half of the same question, one layer down. For
every decision, the best-scoring candidate of each kind is set against the option that
was actually played, and the terms are averaged over the decisions where that kind
lost. It names which term did it: a through ball at `success 0.05 v 0.45` is a pass
model problem, and the same row at `gain 0.02 v 0.10` would have been a value problem
instead. Read `success` first; it is the term that usually decides.

The line above it reports what `turnover_exposure` came out at and where the defensive
line was that produced it. It is there because the first version of that term was
inert — its thresholds were guessed from a mental picture of a back line and this
engine's sits at 28% up the pitch, so the multiplier averaged 1.16 and never varied.
**A constant whose input range you have not measured is a constant that may be doing
nothing**, and this line is how you tell within one run.

Underneath it, **`what the pass model made of them`** breaks that `success` into the
five factors it is a product of, for the pass kinds. This is the table to read when
`success` is the answer, because a product of 0.05 is one number and could be one
factor at 0.05 or four at 0.55 — unrelated faults in unrelated code. The row does not
multiply out exactly to the printed `success`: what is left over is `off_balance`, the
penalty for choosing while the ball is still moving, which is applied to the candidate
rather than inside the model.

**`and of the ones it played` is the calibration, and the table above it is not.**
`success` there is the best *rejected* ball of its kind and `completed` beside it is
what the played ones did, so the gap between the two columns is mostly selection —
and selection is not the same size for every kind. A through ball loses fourteen
times for every one that gets played and an ordinary pass loses twice, so the same
gap means different things in the two rows, and reading it as a calibration is how a
model that is picking well gets mistaken for one that is wrong.

The second table is the same five factors and the same model on the balls it
actually **played**, against the completion rate of those same balls. That pair is
like-for-like. Measured, every kind sits 1.3 to 1.5 times its own claim — the
residual is the model asking a stricter question than `completed` does — except the
through ball, which sat at 2.2 and had `struck` at 0.72 against a pass to feet's
0.90. `SPACE_TOLERANCE` is what that found: a ball into space was being graded
against the boot of a standing receiver. The same instrument then said the cross
claims 0.15 to 0.21 and completes at about that, which is the model being right
about a bad ball rather than wrong about a good one.

**The `gain` column is not comparable across kinds.** A shot carries a gain of 1.0 by
construction — the gain *is* the goal, and the scoring multiplies it by the chance of
one — so any row whose winner was often a shot has an inflated right-hand side. The
comparison that means something is within a column, between the two sides of the same
row, on `success`.

**A row that is missing is a run nobody ever made, and the block prints no zeros.**
`box`, the run that attacks a cross, was absent for two rounds of fixes while the
mechanic under it was scored, won its softmax six times over and was never
committed — `sim/off_ball.gd` sized its quota tally by hand and threw an
out-of-bounds error to stderr on every assignment pass. A block read through
`grep` cannot show you an error, and an absent row looks exactly like a run the
engine chose not to make. Read the whole output when a row you expect is not
there.

**When the two halves disagree, believe the trace.** An intent that is taken and never
resolves into a body arriving somewhere useful is a run that exists only in the
counter. The first version of the trace half had its speed threshold low enough to
read identically with the whole layer switched off: a broken instrument, not a null
result.

**`Shots by distance`** — whether the attack ends in anything. A shot count on its own
cannot say: a team that walks it to the six-yard line every time and one that shoots
from anywhere both produce a plausible total, and the §11 band sees one number for
both. What tells them apart is the band the shots were struck from, the mean expected
goals per attempt beside it — real football's is about 0.10, and an engine printing
0.40 only ever shoots from a tap-in — and how many were second balls rather than fresh
chances.

Under the fate rows sits **`the save model resolved N of them`**, which is the only
thing that can say *why* a goal-bound shot went in. `SimKeeper._shot_response` resolves
a save in two stages that multiply — the reach envelope, then `save_chance` — and until
this block existed only the second one was visible, because being beaten for reach
returned without logging anything. A keeper whose envelope is too small and one whose
roll is too low produce the same compound rate and want opposite fixes.

Its population is smaller than the goal-bound fates above, deliberately. A shot a
defender blocks before the keeper commits never reaches him, and one struck from six
yards can be in the net before his reaction time is up: those are goals the save model
never had an opinion about, and charging them to it would be blaming it for the
defence. The last line goes the other way — `Goalkeeping`'s `saves` counts every ball
the forecast had going in, deflections and sliced clearances included, and those are
not shots.

The `ball ... away, reach ...` pair on the beaten row is measured in the keeper's own
reach space, not in metres of grass: `_closest_approach` stretches height by
`VERTICAL_REACH_RATIO`, so a top corner is further away than the same offset along the
floor. The reach figure is the one to read first, because it is the dive he actually
got off rather than the one `REACH_DIVING` describes.

Under it sits what no count of shots can reach: what the man on the ball did with his
touches *inside* the penalty area, and how far in front of himself he pushed the ball
when he carried it there. A carrier who arrives in the box and knocks it four metres
ahead never gets a shot away, so the shot that should have happened appears nowhere in
the log. The only trace of it is a carry in a place where a carry is the wrong act.

**`Where the pass was aimed`** — the only thing that can see a pass played into an area
the opposition owns. A completion rate cannot: a ball rolled to a man with three
opponents around him and the same ball to the same man in space are the same length,
from the same place, to the same teammate, and the event log records them identically.
It counts bodies off the trace instead — how the sides are balanced within six metres
of the point the ball was aimed at. Underneath it is the other reading of the same
complaint: an opponent standing *on the line* of the pass rather than at the end of it.
That second number found something — a quarter of all passes were being threaded within
a metre and a half of a defender, completing at about 40%.

**`Passing by direction`** and the three blocks under it — because completion cannot say
whether the passing is any good. A side that rolls every ball back to its centre halves
completes 95% of them and has done nothing. Four questions, each answering what the
others cannot:

- which way the ball went and what it was *worth* (`xT gained`, the honest measure of
  whether a pass improved anything);
- whether the man who received it kept it, since a pass completed and lost two seconds
  later is indistinguishable from a good one in every other count;
- whether passes string into moves at all;
- whether the ball played to a committed run outperforms the ordinary one on the same
  terms.

That last block is the one to reach for after touching `_lead_point`, `_call_bias` or
`_arrival_gain`. A mechanic that gets played often and gains nothing is not doing what
it was built for, however many appear in the pass counts.

**`Restarts`** — a set piece has two halves that are invisible from the event log.
`waited` is how long the ball sat there: a goal kick struck six tenths of a second after
the whistle gives the side taking it no time to do anything, so whatever the routine
asked for never happened. `worst` is beside it because a mean hides a stall — eight
seconds is `SimSetPiece`'s timeout, so a worst of exactly eight is a restart nobody was
ever ready for and the taker was placed on the ball to stop it hanging. The shape columns
are where the kicking side actually stood when the ball was struck, and `theirs` is the
same measurement of the other side. `in the area` counts opponents inside the kicking
side's penalty area at the strike: a rule on the goal-kick row, where it should be zero,
and ordinary football on every other.

**`In the air`** — the aerial layer's own account of itself: how many headers, split
by what `SimAerial` was trying to do with each — clear it, head it at goal, or find
a shirt — how many balls were taken down on the chest instead, and how many the
keeper came out and claimed, caught against punched. Nothing else can tell the
three header intents apart: a clearing header and a knock-down are the same
player, the same touch kind and the same place in the log, and a match where every
header is a clearance is a match with no attacking aerial game in it. The chest
share answers the other question — how much of a match is played with the head,
which is the one thing that goes obviously wrong by eye when it moves. The keeper
rows are inferred from the height the ball was at when he took it, so a ball he
picked off the grass is counted separately.

What it cannot see is the ball nobody played. `SimAerial.lets_it_drop` is a
touch that does not happen, so a match where everybody stands under everything
and a match with no high balls in it look the same here: headers plus chests
falls, and neither number says why.

**`Goalkeeping`** — split by whether there is anything to defend on purpose. One number
over a match answers nothing: a keeper sweeping fifteen metres behind a high line with
the ball at the other end and a keeper fifteen metres out with a striker bearing down on
him are the same figure and the opposite behaviours.

**`Taking it down`** — the only thing that can see what a first touch did. A first touch
is one event, by one player, in one place, whether he took the ball into his stride or
knocked it three metres behind himself. The second of those starts most of the
possessions that die for no reason a completion rate or a duel count can explain, because
what the log records is a clean interception by somebody who was five metres away when
the pass was played.

It buckets every first touch by where the ball ended up relative to *where the man wanted
to go* — never relative to the compromise he settled for, or the instrument approves of
its own mechanism — with the pace the ball still had on it and the `quality` the
execution graded him at. That last column found something: it read 0.02 to 0.10 for every
first touch in the match, meaning every footballer in the engine controlled every pass
like the worst player on the pitch.

**The `touch` column in `Under challenge`** — the same instrument pointed at the carry:
how far in front of himself a man pushed the ball, split by how hard he was being closed
down. The percentages beside it say what he chose to do; only this says how big the touch
was when he chose to carry. A row that does not shorten as the pressure rises is a carrier
who has not noticed the man on him.

**`Where the carry went`** — the touch judged by what was in front of it, which no count
of carries can be. A touch knocked into fifteen metres of empty grass and the same touch
knocked into a defender standing six metres up the lane are the same kind, by the same
player, of the same size, and `Under challenge` rates the second one *free* —
`challenge_on` has a 5.5 m sight and he is outside it. The only difference between them is
what happens a second and a half later, by which time the log records an interception by
somebody who was nowhere near the ball when the decision was taken.

Read the `lost` column against the bottom row, which is the same engine carrying into
space; the gap between them is the price of carrying into somebody. The lower half asks the
same question of the paint instead of the bodies, and says whether the man on the ball is
walking it over a line or hitting a legitimate touch badly. A carry played from two metres
inside the line and one struck at ten metres a second from twenty metres inside are the
same throw-in and want opposite fixes.

A pathology here does not have to be in the scoring. Three quarters of the carries in a
match used to be settling touches aimed by `SimDecision._safe_direction`, which no
candidate is ever scored for; see `docs/STATUS.md`.

**`Did he have a safe pass?`** — the block to reach for before anything that moves bodies.
Counting teammates near the ball says nothing, because a body is not an option: a man with
a defender in the lane is a pass that gets cut out. See `docs/STATUS.md` for what it found.

**`How the ball changes hands`** — splits the balls that go out by the touch that put them
there, over which line, and for the carried ones how much grass the man had beside him and
how hard he struck it. A count of throw-ins says none of that, and a ball hammered clear
and a ball walked over the line in front of a carrier are the same restart.

**`The ball in behind, as a strike`** — the through ball judged as a weight rather than
as a choice. `Passes by kind` gives it one mean length and one completion rate, and
neither can see the thing the eye sees first: a ball in behind is aimed *past* a man on
purpose, so whether it was a good ball is not "did it reach a teammate" but "was it hit
at a weight he could run onto". Those come apart completely — a ball blasted 30 m into
the channel and collected by the keeper is resolved, is not completed, and is
indistinguishable in every other count from one cut out by a defender.

Three columns carry it, and all three are ratios against the receiver rather than
absolute numbers.

- `arrives` against his top speed. The ball's own speed as it reaches the aim point.
  Above his top speed it is a ball nobody catches, whatever else was true of the pass.
- `aimed ahead` against `he covers`. Where it was played against how far he can get
  while it travels. Over is a ball aimed at a yard he never reaches.
- `reached him` — the *intended* man. `Passes by kind` counts a through ball scuffed to
  the nearest centre back's feet as a completion.

The row marked `to feet` is the ordinary ground pass on the same columns, and it is
there so the numbers above it can be read at all: a figure is only high against
something.

Every quantity comes off the strike itself — `struck`, `lead` and `rmax` on the pass
attempt — rather than being reconstructed from the 5 Hz trace, which at 16 m/s moves
three metres between samples. `rmax` is on the event rather than looked up when the log
is read because `max_speed` is fatigue-capped and falls across a match: read late, a
first-minute ball gets judged against tenth-minute legs.

**`arrives` must come off `SimBallistics.ground_pace_after` and never off
`ground_travel_time`.** There are two friction models in `sim/ballistics.gd` — the
two-phase slide-then-roll one a strike is solved against, and the single blended decel
the travel time uses — and they disagree by about a metre a second over twenty-five,
always in the direction that makes a ball look faster than it was struck to be. This
block had that bug when it was written. The check that it is right: on the bench, an
intent of 7.28 m/s reads back as 7.3.

Expect a residual on `arriving faster than the man can run` even when the aim is
correct, and read it as execution rather than as intent. Arrival pace goes as the
*square* of the strike, so at 25 m a ball overhit by 10% arrives at 9.4 m/s instead of
7.3, and `_perturb` overhits some of them by design. It runs 5% to 23% by squad.

### `./run.sh behind` — the same ball in a geometry nobody had to reach

The block above measures the through ball over a match and cannot answer the question
the eye asks. A match mixes the aim rule with the whole of the selection above it:
change the weight a through ball is hit at and the softmax plays a *different set* of
them, so the mean length moves for two reasons at once and neither is separable. That is
the right instrument for "how much of this is happening" and useless for "is this ball
hit right".

So `behind` sets the situation instead of sampling it. A passer, a runner, a flat back
four and a keeper, at distances chosen rather than found, and one question per row: the
ball the engine would play here — can the man it is for get to it? No match runs, no
tick advances, nothing is random, and it returns instantly. The same geometry gives the
same row on every build, so a row is a property of the rule.

It reads the engine's own candidate list through `SimDecision.options_for`, which
generates without playing, so the ball it prints is the ball the match would strike and
not a copy of the rule that can drift from it.

The `run` column says which branch of the aim produced the row: `committed` when the
off-ball layer has the man on a timed run in behind, `projected` when the aim is the
guess made in its absence. Those were two different rules until the projection was found
aiming a flat 12.6 m ahead of a man whatever he was doing.

A row that offers no ball names the gate that refused it, off `SimDecision.behind_gate`
— the same tally `A man was running in behind` prints. **That tally has a blind spot the
bench makes visible**: `_open_behind_gates` opens its population on
`is_running_in_behind`, so it only ever counts men the off-ball layer has *committed* to
a run. Every `projected` ball is invisible to it, in the bench and in a match alike, and
the projection is the branch that was aiming wrong.

## The chain

Four instruments and a command, one subject. Everything above measures what the
football did; these measure **why a change to it did nothing**, which is a different
question and the one that used to have no answer at all.

A constant reaches a goal down six links, and each can break on its own:

| | the link | what says it broke | how it breaks |
|---|---|---|---|
| 1 | the constant reaches the input that reads it | `--ablate`, the `value` column | a range the engine never enters |
| 2 | the term's output varies | `--ablate`, `on score` | applied, and the same for every option |
| 3 | the varying term changes which option wins | `--ablate`, `flips` and `moves p` | moves the numbers, dominated by something bigger |
| 4 | the option is generated at all, and played | `Chains`, links 1–4 | a gate upstream of every value knob |
| 5 | the act leads somewhere | `Chains`, the `then …` links; `What became of the ball` | the football stops one stage earlier than expected |
| 6 | it was the act that did it, not the situation | `The coin the softmax tossed` | it correlated, it did not cause |

`./run.sh chains --against` is the command, and it asks links 4 to 6 again about a
change rather than about a match.

**Read them in order.** A term that never reaches the pick cannot be blamed for an
outcome, and a link that broke at 2 makes every measurement below it noise about
something else. The first three cost nothing and answer most complaints on their own.

Two of them have found something already. `focus_at` multiplies every gain in the
decision layer by exactly one, in every plan, because nothing writes
`SimTactics.attacking_focus` — link 1. And only a fifth of the wide moments in the
opponent's half generate a cross candidate at all, so raising `LOFTED_BIAS` moved
`it was played` by sixty points and `a cross was offered` by −1.7 — link 4, upstream
of every prior in the file.

**`Where a term changes the decision`** — `--ablate`, links 1 to 3, and the only
block in this file that does not measure the match. It measures whether a term in the
score can reach it at all.

**Start here, because a term that never changes the pick produces a match identical
in every count there is.** No statistic over a match can see one, however many matches
are run, and this is where a knob that was turned and did nothing usually died.

So it is measured per decision and counterfactually. Each decision, the list is
scored again with one term neutralised and the two choices are compared. No second
match — and, the reason to trust it over one, no divergence cascade: two runs of one
seed become different football within seconds of the first different decision, and a
diff between them measures a different match rather than the knob.

**Read `in`, `on score`, `flips`, in that order. They fail differently and the fixes
are in different files.**

- `in` at 0% — the term is applied to no candidate. It is not wired to the situation
  it was written for, and nothing downstream can be its fault.
- `on score` at ~0 — applied, and its value never varies, so it shifts every option
  alike and discriminates between none. This is the `turnover_exposure` failure
  recorded in `SimDecision`, found by hand: guessed thresholds, a mean of 1.16, no
  variance.
- `flips` at 0% with a real `on score` — it moves the numbers and something bigger
  beats it. The only one of the three that is a judgement rather than a bug.

`flips` is a share of the decisions the term *applied to*, not of the match, because
a term cannot change a pick where it is not present. `moves p` is the same question
without the cliff edge: how far the softmax's distribution over the kinds of action
moved, which counts a term that shifts every decision a little and flips none.

**The commonest flip is two independent maxima**, the kind that most often lost the
pick and the kind that most often won it. `pass -> pass` is not a contradiction: it
means the term reorders the passes among themselves rather than changing what kind
of act gets played.

**A term is measured against the plans the match was played with.** A prior that only
varies away from balanced reads as a constant on the default — `risk_weight` flips
0.3% of decisions in a balanced match and 3.3% under `--plan press --away-plan block`,
and the pattern bias goes from 0% to 11%. Run it both ways before calling a tactical
term inert.

It found one immediately. **`focus_at` was dead**: `SimTactics.attacking_focus` was
`[1.0, 1.0, 1.0]` and nothing in the engine ever wrote it, so the lateral focus
multiplied every candidate's gain by exactly one, in every plan, in every match. Four
call sites, present in every gain in the decision layer, contributing nothing. It was
a channel with no plan wired into it rather than a broken formula, and it read
`never applied` at `in` 0%. `SimTactics.set_focus` is what now writes it, and the
two Phase 5 presets are what call it.

**It still reads `never applied` on the balanced plan, and that is now the right
answer rather than the bug.** `balanced()` has no lateral opinion, so its triple is
`[1, 1, 1]` and the term contributes exactly nothing — the same thing `risk_weight`
and the pattern bias do on that plan. Under `--plan press --away-plan block` it
applies to 100% of decisions and flips 3.6% of them. The two readings together are
what say the channel is alive; either one alone says nothing.

Same one-way-tap contract as the decision sink: off unless asked for, never touches
`ctx.rng`, nothing in `sim/` reads it back. Every other block in the report is
byte-identical with it on. It compares the pick on the **best** option rather than on
a second draw, because drawing again would consume the stream and the match would no
longer be the seed's. It costs about 4% of a diagnose run — scoring the list again is
nearly free, since what a decision costs is generating the candidates.

**`What became of the ball`** — what a spell of possession produced, and what had
been played in it. Every other block on this page counts acts; none of them can say
what came of one, because a count has no way of reaching forward.

`SimContext.possession_id` is what makes it reachable. Every event now carries the
spell it was logged in, so "what became of this" is a filter over a group rather
than a guess at a tick window — and it retires the pairing trap in `Two traps in
reading positions` below, because there is nothing left to desynchronise.

A spell is a run of one team being the side in possession. It ends when the other
team takes over **and at every dead ball**, because a restart sets
`ball.last_touch_player` to -1 and drives possession to -1 with it. That second rule
is deliberate: a free kick to the side that already had the ball would otherwise be a
possession that swallowed the foul that interrupted it, and the foul is the outcome
worth counting.

**The fate is precedence-ordered, not last-event-wins.** A shot that goes out for a
corner logs the corner second, and reading backwards files the possession as a ball
out of play and loses the only thing about it that mattered. Three of seed 7's six
balls out of play are shots, and they belong on the shot row.

**Two joins, and they are not interchangeable.** The fate comes off the tag: the
event that *ends* a spell — the tackle, the cut-out pass, the whistle — is logged
while that spell is still the live one, because possession is derived at the top of a
tick and football is played in the middle of one. The contents come off the tick
interval instead, because the touch that *wins* the ball is logged a tick early too,
so by tag it belongs to the spell it ended rather than the one it began. Counted by
tag, a deflection came back as a possession with no touches in it.

**`ground` is the ball, not the move.** It is how far the ball travelled toward the
goal that team was attacking, measured from where the spell started, so a goal kick
hammered eighty metres and headed clear counts eighty. The attacking direction is
captured at the spell's start rather than read at its end — `SimPitch` only knows
where the ends are pointing now, and the trap below is what that costs.

`picked off loose` is the row that had to be added, and it is the largest single way
this engine loses the ball after the cut-out pass. It logs no duel and no failed
pass, so without a row of its own it sat in "lost otherwise" and read as a gap in the
instrument rather than a fact about the football.

**The lower half is observational, and that is its limit.** A spell containing a
cross is a spell that had already reached the byline, so the shot rate beside it is
partly the pass and partly the situation it was played from. `The coin the softmax
tossed`, below, is the version that separates the two; this one says what goes
together, not what causes what.

**A shot is a content, not an ending event, and getting that wrong cost two goes.**
It is worth knowing about because it is the shape of every mistake this join can
make. A first-time strike off a loose ball *is* the touch that wins the ball, so it
is tagged to the spell it ended — the opposition's — and a team check that was right
to reject it threw four of seed 7's five goals away. Before that, goals were read off
the `GOAL` event, which lands a spell later than the strike again: the ball is
touched on its way in often enough that four of five goals were charged to the
fragment of play *after* the ball was already in the net, which is why the goal row
read two touches and three seconds long. Shots and goals are matched to the spell
whose team owned the ball at that tick, by the same interval join as the touches, and
the counts now agree with `Shots by distance` — 22 shots, 13 on target, 5 goals.

**`Chains`** — the same spells, walked link by link. The block to reach for when a
change went in, the goals did not move, and nobody can say where it stopped. A count
of shots says the attack failed; this says which link failed, and the links have
different owners.

Four chains, and they come in two shapes. `Into a shot` and `After winning it back`
start at a spell of possession; the second is the counter, and it is there because
`--ablate` said `break_bias` — the whole counter-attacking prior, a 2.6x multiplier —
had never once changed which option was played. It flips 2.3% of them since the rest
charged for a run a turnover ended was made proportional, which is what a prior on an
option nobody was generating looks like when the option starts being generated.

`The cross` and `The ball in behind` start at a **decision**, and their first three
links are invisible to every other instrument in the project. A cross that was never
a candidate and a cross that was scored and beaten are the same absence in every
count here, and they are different jobs: the first is `_add_passes` not offering it,
the second is what it is worth once offered. A crossable moment that produced nothing
leaves no event in the log at all, so nothing reading the log can find it — which is
why `SimChoices` records which kinds were generated, how wide the carrier was, and
whether anybody was running in behind.

Everything from `then …` on is conditional on the act having been **played** and on
happening **after** it. Counted the way the spell chains are, the cross chain
reported 22 spells reaching the area against 5 crosses played — 440%, and measuring
attacks that never crossed at all. `CHAIN_GATE` is where that conditioning starts.

The population is a decision, not a spell, so a move offering three crossable moments
counts three times and its outcome three times with it. That is right for "of the
moments that called for a cross, how many became one" and wrong for counting crosses;
`Passes by kind` does that.

**What they found.** Of 122 wide moments in the opponent's half, **only 20% produced a
cross candidate at all** — and raising `LOFTED_BIAS` from 0.30 to 0.60 moved that link
by −1.7 points while moving `it was played` by +60. A value knob cannot create an
option that was never generated, and the generation gate is upstream of every prior
in the file. That is the shape of the complaint this whole set of instruments exists
for, and no count of crosses can see it.

Over three seeds it was 11%, not 20% — seed 7 is the optimistic one — and
`SimDecision._add_crosses` is the answer to it: see `docs/STATUS.md`, "The ball into
the box". **The population is deliberately wider than the mechanic.** The chain asks
its question of every wide moment in the opponent's half while the generator fires
only in the final third, so the `offered` link reads 2 to 8% and most of the gap is a
design decision rather than a miss. An instrument that adopts every gate the mechanic
has can never report the mechanic refusing to fire, which is the whole job of link 4.

**The stages are shares of the population, not nested subsets, and `of above` can
pass 100%.** The first version enforced nesting and got it wrong in the direction
that matters: a shot struck from outside the penalty area was stopped at the box row
and never counted, so the chain printed 8 shots against the 19 the block above it had
just reported. An instrument that disagrees with the one beside it is the one that is
wrong. Read the other way, that same row is the finding — 22 shots against the 15
spells that reached the area, `of above` 147%, which is an engine shooting from
outside the box far more than it gets into it.

### `./run.sh chains` — what a change did to the chain

The block above says where an attack stops. This says what a change *did* to that,
which is a different question and the one that was being answered by eye across two
terminal scrollbacks.

```
./run.sh chains --matches 5 --minutes 10 --out runs/before.json    # before
#   ... change the code ...
./run.sh chains --matches 5 --minutes 10 --against runs/before.json
```

A saved run is a few hundred bytes and holds only the chain and fate counts, so it
can sit in the repo across a change. Relative paths land in the repo root, since
`run.sh` runs from there.

**Read the conversion column, not the counts.** A change that produces more
possessions moves every count in the chain and has told you nothing about where it
landed. A change that moves a *conversion* has changed what happens at that link, and
the arrow marks the largest moves. The counts are printed beside it because a
conversion over nothing is noise.

**Several matches, not one, and this is not fussiness.** A code change moves the match
wholesale — two runs of one seed become different football within seconds of the first
different decision — so a one-seed diff measures a different match rather than the
change. Five seeds is not a sample either; it is enough that a conversion moving ten
points is worth a look. The `n` column is what says whether it is.

**The two runs will not have played the same amount of football.** Measured, 20
minutes against 23 on the same four seeds, which inflates every `after` count by 15%.
The header says so when they are more than 5% apart, the conversions are immune, and
the outcome table underneath is put on a per-90 rate.

Measured against `SimDecision.TERRITORY` at 0.75 — the value the file's own comment
describes — the diff says: box entries 18% → 26% of the spells that reached the final
third, shots 97 → 112 per 90, goals 26.5 → 23.1, and the goal conversion off a shot
50% → 33%. More chances, worse chances, no more goals. That is the same finding
recorded beside `TERRITORY_URGENT`, arrived at from a standing start in ninety
seconds, which is what the command is for.

**`The coin the softmax tossed`** — the only comparison in this file that is not
confounded, and the engine has been running the trial since it was written.

Every other split here compares what happened after a carry with what happened after
a pass, and every one is as much a fact about the situations carries get chosen in as
about carrying. No number of matches fixes that; it is the wrong question asked
precisely.

But options are chosen by softmax and never by argmax, so when two kinds of act score
close together **which one gets played is settled by `ctx.rng` and by nothing about
the situation**. That is random assignment. Condition on the near-ties, split by what
came out, and the gap between the arms is caused by the choice.

Two things make it better than a real trial: the propensity is not estimated but is
the number the engine used, and both arms come from one match, so nothing about the
football differs between them. **Read `p` first** — it is the mean chance the arm's
kind had of being played, and if the two sides of a row are not near even the
conditioning has not worked and the rest of the row is worth nothing. Measured, they
come out at 0.52 against 0.49.

Two limits, both real. It is a **local** effect: it says what the pass was worth
instead of the carry on the decisions where the two were nearly equal, which is the
population the engine was undecided about rather than one football cares about. And
the outcome is the whole spell's, so a decision three seconds from a turnover is
scored on a possession it barely influenced.

**It wants a full-length match and says so.** Ten minutes holds about 130 near-ties
over fourteen pairs, so every row prints `noisy at n=`, on the same rule the batch
runner uses. Widening the band to reach a sample is fitting the instrument to the run
rather than to the question — at 0.35 to 0.65 the carry arm's shot rate moved from 8%
to 28% on the same seed, which is the noise saying so.

## Two traps in reading positions

**Outcomes cannot be paired with attempts by their order in the log.** Not every attempt
resolves — a ball that runs out of play never does — so a positional pairing desynchronises
at the first missing one, and every completion rate after that point belongs to somebody
else. It reported 20% against an actual 78%.

Anything written from now on should join on `poss` instead, which cannot desynchronise.
The blocks above predate the field and still pair by order or by tick window; they are
correct as they stand and are not worth rewriting for its own sake, but a new one that
pairs by hand is choosing the trap.

**The half-time flip is applied once.** Flipping a point that has already been flipped
cancels, and every first-half pass then reads as having gone the other way, which turned
the forward passes' expected-threat gain negative.

Anything that reads a position out of the event log has to know which way the team was
attacking at the time. The ends change at half time and `SimPitch` only knows where they
are pointing now. `_first_half_flip` is that correction, and it is not a small one:
measured against the wrong goal, a tap-in comes out at ninety metres.

Anything reading the *trace* needs the same correction and one thing more. The sample index
it swaps at has to be rounded **up** from the period event's tick, because the ends change
partway through a tick and the sample taken at the start of that tick still has everybody
at the end they came from. Rounded down, one sample a match reads as a keeper ninety metres
from his own goal, which is enough to ruin a maximum.

## The live overlay

`./run.sh view3d --debug`, or **`F1` in any running match**, the main scene
included — it is built the first time it is asked for, so a match nobody is
debugging pays nothing for it. The blocks above answer "how often, over a match";
the overlay answers "that man, just now, why". It is the instrument for the
moment the owner is watching, and its output is a file that can be handed to
somebody who was not.

It shows four panels and seven keyed layers, and everything about it is a
readability decision. Twenty-two players deciding about once a second is a
waterfall, so: **one subject, and it is the man on the ball**; **latch, never
stream** — the panel holds his last decision, including after he has released the
ball, which is when the eye goes looking for it; **show what he was choosing
between**, the options within one softmax spread of the best plus two for
context, never the twenty that were enumerated; **space goes on the pitch and
quantities go in text**; **about twelve lines, ever**.

**The carrier panel** is the one that answers most questions. It prints the
chosen option, the ones it beat, and the three numbers each score is made of —
`success`, `gain`, `loss` — with the softmax weight as a bar. A carry taken 0.003
ahead of a pass and one taken 0.03 ahead look identical on the grass and are
different complaints.

**`LAST 8 ON THE BALL`**, under the strip, is the same man's last eight
decisions, newest first, one line each: the clock, what he took, what it scored.
The carrier panel answers "why this touch"; this answers "what has he been
doing", and no single decision can. A midfielder who has held the ball five times
running, or hit the same nine-metre square pass every time he gets it, shows up
here as a column of identical lines and nowhere else. Eight is not a choice —
it is everything the sink keeps per player. The lemon row is the one the panel
opposite is open on, which is not always the top one, because that panel holds a
decision for a third of a second and at 8x he has taken another by then.

**The layers** are `1` options, `2` pressure, `3` runs, `4` chasing, `5` value,
`6` belief, `7` trails, `8` names — the last on by default, the rest off. Layer 1 is the one that earns the overlay: it draws every
scored pass and carry from where the man stood, so "he never passes to the
winger" resolves to either "the winger was not a candidate" or "he was, and he
scored 0.02 lower", which are two different jobs. Layer 6 is the other half of
that question — an option he cannot perceive can never be scored at all.

**On layer 1 a carry has two marks, and they are not the same distance.** The
ring at the end of the arrow is the **horizon**: how far that direction can be
pursued at all, which is what every term in the option's score was read at. The
**cross** is where he expects to meet the ball again — the next touch — and it is
where the ball actually goes. At a walk the cross is well short of the ring; at a
sprint it runs out past where the arrow's own ring was drawn, because the ball is
struck to beat a man who keeps running. The panel's `carry fwd 4.2 m` is the
cross, not the ring.

Both come from the functions the engine plays the touch with —
`SimTouch.dribble_ahead` and `SimDecision.carry_travel` — so a mark that
disagrees with what happens next is a bug in the sim, not in the drawing. Before
the cross existed, the layer and the panel both reported the horizon, and every
carry in the match read two to three times longer than the touch about to be
played.

**`M` marks the moment.** It writes `bookmarks/seedN-tT.md` and the frame beside
it: the ball, everyone within twenty metres with their intent and chase role,
every decision and event of the previous eight seconds, and the command that
reproduces it. That file is the exact description, so nobody has to write one.

**A mark can be read back or watched back.**
`./run.sh replay --seed N --tick T --around 6` re-simulates that seed to that
tick with the sink on and prints the same lines without a display, so a complaint
about something seen on screen can be answered from a report.
`./run.sh view3d --from-bookmark seed7-t34210` does the other one: same seed,
fast-forwarded to five seconds before the tick, played at quarter speed and
paused on the tick itself, as many times as it takes. It reads the flags the
moment was marked under out of the file, because a compressed clock or a scaled
pitch is a different match from the same seed and the tick would land somewhere
else. The fast-forward runs across frames with a progress readout: the sim has no
way to jump to a tick, so a mark late in a match is a hundred thousand ticks of
football to play through.

**`,` steps the picture back and `.` steps it forward; `<` and `>` jump ten
samples, half a second.** The view records a sample every three ticks and keeps
the last thirty seconds, so whatever went past can be walked over as slowly as it
takes. The panels, the ticker and every annotation layer are drawn from the
sample being shown rather than from the context, so the phase, the possession,
the pressure rings, the runs, the beliefs and the decision on screen are the ones
that belonged to that moment; the strip says `STEPPED BACK` and how far while
that is true. The camera pans and cuts through the recording exactly as it does
in play, so a move stepped through is framed the way it was watched rather than
left pointing wherever the picture stopped. Holding either key repeats. `M` there
marks the moment being looked at, not the one the sim has reached.

**`enter` plays on from the moment on screen.** The same football again — the
seed decides the match and nothing about it changes — but live rather than
recorded: the panels update as it runs, it can be watched at any speed with any
layer up, and it carries on past the end of the recording instead of stopping at
now. The simulation cannot be rewound, so this builds the match again from the
seed and fast-forwards to the tick being shown, with a percentage on the status
line. It costs what those minutes cost the first time, which an hour into a match
is a wait.

**`N` goes to the next match, `R` plays this one again.** A match used to end on
a still pitch with no way out of it, so watching a second one meant relaunching
and losing the overlay's settings with it. At full time the board asks for `N`;
both keys work at any point in a match. The next match is the next seed, so the
sequence stays reproducible and every bookmark and replay command still names a
match `--seed` can open. Everything a match leaves behind is cleared at kick-off
— the recorded snapshots the trail and the step-back read, the decision sink, the
pinned player, the scoreline, and the grass itself, which is cut from the seed's
own surface. The overlay, the layers and the playback speed carry over, because
those are how the owner is watching rather than what is being watched. The seed
is on the help line from here, since by the third match nobody remembers which
match they are looking at.

**`N` also walks the squad quality.** Match one is 0.60 v 0.60, two is 1.00 v
1.00, three is 1.00 v 0.60, and a fourth `N` wraps to the first pair on a new
seed. Two even matches at different levels and then a mismatch is what makes
quality visible by eye: whether the better side keeps the ball, and whether the
uneven one looks uneven. `R` stays on this match's pair — the same seed at
another quality is eleven other men, not the same match again. The pair is on
the help line beside the seed, the full-time board names what `N` will play, and
the replay command a bookmark writes carries `--home` and `--away` when they are
not the 0.60 default. `--home Q` / `--away Q` pin one pair for the whole session
and turn the walk off.

**The players wear their numbers** while the overlay is up (layer `8`). Every
panel, bookmark and replay line names men by shirt, and the 3D players otherwise
carry only kits and faces — which made every one of those names unusable.

### What it cannot see, and what would mislead

**Stepped back, it shows what was recorded, not what could be recomputed.** The
sample carries the strip, the pressure and challenge fields, the intents, the
chase and marking assignments, the beliefs and the value grid; the decision
panels come out of the sink, which keeps the last six hundred decisions and eight
per player. Two things follow. A layer turned on after the fact has nothing to
draw for the samples before it — the value grid is only computed while that layer
is up. And thirty seconds is the whole of it: further back than that is gone, and
`./run.sh view3d --from-bookmark` or `./run.sh replay` is what reaches a moment
the recording has dropped.

**Nothing off-ball is captured.** The sink hangs off the on-ball decision and the
keeper's, so a run that was never made, a marking assignment that was never taken
and a shape that never moved appear nowhere in the panel. The layers are what
answers that, and they are positions rather than reasons.

**The compressed clock makes it unreadable.** `view3d` and the main scene both
default to `--clock-rate 30`, which scrolls a minute of football a second, so
`--debug` drops the clock to real time unless the command line says otherwise.
The clock rate is baked into a match when it is built, so a match opened with
`F1` instead cannot be un-compressed and the help line says as much; slowing the
playback with `[` is the only answer available from there. Slow motion and
stepping a tick at a time (`.`) are worth more than any panel here: most of what
looks wrong is two seconds long at 1x.

**Reduced fidelity strides the decision layer.** The overlay would show stale
panels and be blamed for it. Watch at full fidelity, which is the view's default.

**The sink is a one-way tap.** It is off unless `--debug` is passed, it never
touches `ctx.rng`, and nothing in `sim/` reads it back, so a match runs
identically with it on: `./run.sh determinism --seed 7 --minutes 5 --debug` runs
the first pass with it on and the second with it off and compares the digests. It
is deliberately not a telemetry event kind — `canonical_text` is hashed by the
golden replay test, and a debug channel routed through the event log would move
every digest in the project for a tool that is not part of the match.

## Batches

A batch measures a machine that is missing parts. It costs minutes, returns a number that
is void as soon as the next mechanic lands, and answers a question nobody is asking yet.
`CLAUDE.md` has the rule; what follows is how one works when the owner runs it.

**Of the two printed tables, only the sanity ranges mean anything yet** — `PLAN.md` §11 and
§11.1.1. Wide structural ranges catch an engine that has stopped being football at all. The
§11 target bands are printed for drift and are advisory until the tuning freeze, which is
`--strict` (what `accept` passes). Neither table is a verdict on a new behaviour.

Every counting statistic is normalised per 90 minutes from the match clock the match
actually played — `SimMatchStats.clock`, the elapsed clock, not `ctx.clock`, which is reset
to 45:00 at the interval and forgets first-half added time. So short matches are a
legitimate measurement of a rate. They are **not** a measurement of fatigue: distance per
player extrapolates high and late-match collapse goes unseen, which is what the full-length
gate is for. Metrics below the sample size they need print `noisy at n=6` and are excluded
from the verdict.

Quote the sample size whenever you quote a band result. The runner tags undersampled metrics
for you; do not launder the tag away. Sanity ranges are judgeable from a handful of matches,
most tuning bands want 40, and the score-draw rate is not remotely settled below 200
(`PLAN.md` §11.1 has the arithmetic).

A running batch prints its progress with a live readout of the headline figures, so one that
has obviously gone wrong can be killed at the second match rather than discovered at the
end. `--keep` leaves the shard JSON on disk; `./run.sh aggregate` re-judges a kept set
without re-simulating, and `./run.sh compare` judges two kept sets against each other, which
is how the `tactics` arms are compared. Neither is in `--help`.

**Do not edit `run.sh` while a batch is running.** Bash reads a script incrementally, so an
edit shifts the byte offsets under the running instance and it dies with a syntax error
partway through, after the simulation time has been spent.

## Measuring the compressed match

`--urgency U` forces the compressed match's scoring fit on at any clock rate — 0 is the
real-time engine, 1 is the three-minute one, and without it the fit only appears above
`clock_rate` 1. It exists because the fit cannot otherwise be looked at: a whole compressed
match holds about five shots, so `Shots by distance` has no population and the question the
block answers — which stage of a chance is losing the goal — has no data behind it.
`./run.sh diagnose --seed 7 --minutes 10 --urgency 1` is ten minutes of the compressed
match's football at the length every instrument here was built for.

Two cautions. It does not reproduce a compressed match exactly, because fatigue scales with
`clock_rate` and this does not touch the clock — a `--urgency 1` run has fresh players
throughout and reads a little high on shots. And a figure measured through it is a figure
about the format: `docs/STATUS.md`, "the compressed match's scoring fit", has what that
costs. Anything asking what the *football* does wants the default.
