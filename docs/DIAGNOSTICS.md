# The instruments

What `./run.sh diagnose` can see, what a batch can see, and what neither can.
`CLAUDE.md` has the rules; this file is the reasoning behind them.

## Why the diagnostic blocks exist at all

The §11 bands are blind to a whole class of question: an engine where the ball is
welded to the dribbler and one where it runs free produce the same goals per
ninety, and a defender who tailgates and one who gets round produce the same pass
completion. Minutes spent on a batch to answer "does this look right" are minutes
spent measuring the wrong thing.

`./run.sh diagnose --seed 7 --minutes 10` is about fifteen seconds. Use
`--minutes` freely; counts are normalised per 90. Do **not** pass `--reduced` when
measuring decision cadence — that tier strides the decision layer, which is the
quantity being measured.

## The blocks, and what each one is the only thing that can see

**`Ball control`** — how far from a player's centre each touch was made, and the
interval and distance between consecutive dribble touches.

**`Chasing the carrier`**, off the positional trace — where the nearest defender
stands relative to a running carrier, split behind / alongside / goal-side, with
the length of the unbroken spells he spends in the carrier's slipstream. That is
the instrument for any question about how defending *looks*: a defender welded to
the carrier's back appears in no touch, duel or recovery, so no count in the event
log can see him.

**`Passing by body angle`** — every pass bucketed by the angle between the
passer's body and the line the ball was played along, with the share of attempts,
the completion rate and the mean technique-and-agility of the passers in each
bucket. The share is the decision layer's half of the answer and the completion
rate is the execution layer's; a change to the facing model that moves only one of
them has done only half of what it claimed.

**`Offering for the ball`** — two halves that have to be read against each other.
The top half is `SimOffBall`'s own account of itself: how many times each way of
making yourself available was chosen, how often the ball then arrived, how many
were cut off by the team losing it, and how far up the pitch each kind of run
went. The bottom half is taken off the positional trace and owes the sim nothing:
with the ball at a man's feet, how many teammates were inside a short pass, and
how many were *actively* doing something about it — coming to meet it, going off
into space, or beyond the last defender — at a speed a shape-holder's jog cannot
reach. **When the two halves disagree, the trace is the one to believe.** An
intent that is taken and never resolves into a body arriving somewhere useful is a
run that exists only in the counter, and the first version of the trace half had
its speed threshold low enough to read identically with the whole layer switched
off — a broken instrument, not a null result.

**`Shots by distance`** — whether the attack ends in anything. A shot count on its
own cannot say: a team that walks it to the six-yard line every time and one that
shoots from anywhere both produce a plausible total, and the §11 band sees one
number for both. What tells them apart is the band the shots were struck from, the
mean expected goals per attempt beside it — real football's is about 0.10, and an
engine printing 0.40 is one that only ever shoots from a tap-in — and how many of
them were second balls rather than fresh chances. Under it sits what no count of
shots can reach: what the man on the ball did with his touches *inside* the
penalty area, and how far in front of himself he pushed the ball when he carried
it there. A carrier who arrives in the box and knocks it four metres ahead never
gets a shot away, so the shot that should have happened appears nowhere in the log
— the only trace of it is a carry in a place where a carry is the wrong act.

**`Where the pass was aimed`** — the only thing that can see a pass played into an
area the opposition owns. A completion rate cannot: a ball rolled to a man with
three opponents around him and the same ball to the same man in space are the same
length, from the same place, to the same teammate, and the event log records them
identically. It counts bodies off the trace instead — how the sides are balanced
within six metres of the point the ball was aimed at — and underneath it the other
reading of the same complaint, an opponent standing *on the line* of the pass
rather than at the end of it. That second number was the one that found something:
a quarter of all passes were being threaded within a metre and a half of a
defender, completing at about 40%.

**`Passing by direction`** and the three blocks under it — because completion
cannot say whether the passing is any good. A side that rolls every ball back to
its centre halves completes 95% of them and has done nothing. Four questions, each
answering what the others cannot: which way the ball went and what it was *worth*
(`xT gained`, the honest measure of whether a pass improved anything); whether the
man who received it kept it, since a pass completed and lost two seconds later is
indistinguishable from a good one in every other count; whether passes string into
moves at all; and whether the ball played to a committed run outperforms the
ordinary one on the same terms. That last block is the one to reach for after
touching `_lead_point`, `_call_bias` or `_arrival_gain` — a mechanic that gets
played often and gains nothing is not doing what it was built for, however many of
them appear in the pass counts.

**`Restarts`** — a set piece has two halves that are invisible from the event log.
`waited` is how long the ball sat there; a goal kick struck six tenths of a second
after the whistle gives the side taking it no time to do anything, so whatever the
routine asked for never happened. The shape columns are where the kicking side
actually stood when the ball was struck.

**`Goalkeeping`** — split by whether there is anything to defend on purpose. One
number over a match answers nothing: a keeper sweeping fifteen metres behind a
high line with the ball at the other end and a keeper fifteen metres out with a
striker bearing down on him are the same figure and the opposite behaviours.

**`Taking it down`** — the only thing that can see what a first touch did. A first
touch is one event, by one player, in one place, whether he took the ball into his
stride or knocked it three metres behind himself — and the second of those starts
most of the possessions that die for no reason a completion rate or a duel count
can explain, because what the log then records is a clean interception by somebody
who was five metres away when the pass was played. It buckets every first touch by
where the ball ended up relative to *where the man wanted to go* — never relative
to the compromise he settled for, or the instrument approves of its own mechanism
— with the pace the ball still had on it and the `quality` the execution graded him
at. That last column is the one that found something: it read 0.02 to 0.10 for
every first touch in the match, meaning every footballer in the engine controlled
every pass like the worst player on the pitch.

**The `touch` column in `Under challenge`** — the same instrument pointed at the
carry: how far in front of himself a man pushed the ball, split by how hard he was
being closed down. The percentages beside it say what he chose to do; only this
says how big the touch was when he chose to carry, and a row that does not shorten
as the pressure rises is a carrier who has not noticed the man on him.

**`Where the carry went`** — the touch judged by what was in front of it, which no
count of carries can be. A touch knocked into fifteen metres of empty grass and the
same touch knocked into a defender standing six metres up the lane are the same
kind, by the same player, of the same size, and `Under challenge` rates the second
one *free* — `challenge_on` has a 5.5 m sight and he is outside it. The only
difference between them is what happens a second and a half later, by which time
the log records an interception by somebody who was nowhere near the ball when the
decision was taken. Read the `lost` column against the bottom row, which is the
same engine carrying into space; the gap between them is the price of carrying into
somebody. The lower half asks the same question of the paint instead of the bodies,
and it is the one that says whether the man on the ball is walking it over a line
or hitting a legitimate touch badly — a carry played from two metres inside the
line and one struck at ten metres a second from twenty metres inside are the same
throw-in and want opposite fixes.

A pathology here does not have to be in the scoring. Three quarters of the carries
in a match used to be settling touches aimed by `SimDecision._safe_direction`,
which no candidate is ever scored for; see `docs/STATUS.md`.

**`Did he have a safe pass?`** — the block to reach for before anything that moves
bodies. Counting teammates near the ball says nothing, because a body is not an
option: a man with a defender in the lane is a pass that gets cut out. See
`docs/STATUS.md` for what it found.

**`How the ball changes hands`** — splits the balls that go out by the touch that
put them there, over which line, and for the carried ones how much grass the man
had beside him and how hard he struck it. A count of throw-ins says none of that,
and a ball hammered clear and a ball walked over the line in front of a carrier
are the same restart.

## Two traps in reading positions

**Outcomes cannot be paired with attempts by their order in the log.** Not every
attempt resolves — a ball that runs out of play never does — so a positional
pairing desynchronises at the first missing one and every completion rate after
that point belongs to somebody else. It reported 20% against an actual 78%.

**The half-time flip is applied once.** Flipping a point that has already been
flipped cancels, and every first-half pass then reads as having gone the other
way, which turned the forward passes' expected-threat gain negative.

Anything that reads a position out of the event log has to know which way the team
was attacking at the time; the ends change at half time and `SimPitch` only knows
where they are pointing now. `_first_half_flip` is that, and it is not a small
correction — measured against the wrong goal, a tap-in comes out at ninety metres.
Anything reading the *trace* needs the same correction and one thing more: the
sample index it swaps at has to be rounded **up** from the period event's tick,
because the ends change partway through a tick and the sample taken at the start
of that tick still has everybody at the end they came from. Rounded down, one
sample a match reads as a keeper ninety metres from his own goal, which is enough
to ruin a maximum.

## Batches: why not, and how they work when the owner runs one

A batch measures a machine that is missing parts. It costs minutes and returns a
number that is void as soon as the next mechanic lands, and it answers a question
nobody is asking yet. Checking for a regression in goals per match right now is
checking whether the plane flies while the wings are still going on.

**Of the two printed tables, only the sanity ranges mean anything yet** — see
`PLAN.md` §11 and §11.1.1. Wide structural ranges catch an engine that has stopped
being football at all; the §11 target bands are printed for drift and are advisory
until the tuning freeze, which is `--strict` (what `accept` passes). Neither table
is a verdict on a new behaviour.

Every counting statistic is normalised per 90 minutes from the match clock the
match actually played (`SimMatchStats.clock`, the elapsed clock — not `ctx.clock`,
which is reset to 45:00 at the interval and forgets first-half added time), so
short matches are a legitimate measurement of a rate. They are **not** a
measurement of fatigue: distance per player extrapolates high and late-match
collapse goes unseen, which is what the full-length gate is for. Metrics below the
sample size they need are printed with `noisy at n=6` and excluded from the
verdict.

Quote the sample size whenever you quote a band result. The runner tags
undersampled metrics for you; do not launder the tag away. Sanity ranges are
judgeable from a handful of matches, most tuning bands want 40, and the score-draw
rate is not remotely settled below 200 (`PLAN.md` §11.1 has the arithmetic).

Batches report progress every fifteen seconds (`PROGRESS_INTERVAL` to change it),
with a running readout of goals per match, shots and draw rate alongside the count
and ETA — so a run that has obviously gone wrong can be killed at the second match
rather than discovered at the end:

```
  [  3/  6]  50%  1m02s elapsed, ~1m02s left   goals/match 2.91  shots/team 13.4  draws 25%
```

**Do not edit `run.sh` while a batch is running.** Bash reads a script
incrementally, so an edit shifts the byte offsets under the running instance and it
dies with a syntax error partway through — after the simulation time has already
been spent.

Sharding is by contiguous seed block, so the *set* of seeds a batch covers does not
depend on the worker count: changing `--workers` changes how fast the run is, never
what it measures. `--keep` leaves the shard JSON on disk, and `./run.sh aggregate
--dir <path>` re-judges a kept set without re-simulating. `tactics` shards too —
each arm is an ordinary batch with `--plan press|block`, and `./run.sh compare
--dir-a X --dir-b Y` judges two kept shard directories against each other.
