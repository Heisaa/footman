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

**The `gain` column is not comparable across kinds.** A shot carries a gain of 1.0 by
construction — the gain *is* the goal, and the scoring multiplies it by the chance of
one — so any row whose winner was often a shot has an inflated right-hand side. The
comparison that means something is within a column, between the two sides of the same
row, on `success`.

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

## Two traps in reading positions

**Outcomes cannot be paired with attempts by their order in the log.** Not every attempt
resolves — a ball that runs out of play never does — so a positional pairing desynchronises
at the first missing one, and every completion rate after that point belongs to somebody
else. It reported 20% against an actual 78%.

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
