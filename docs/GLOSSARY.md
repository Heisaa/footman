# The vocabulary

What the words mean in the diagnostic tables, the code and `PLAN.md`. Several are
ordinary football words used narrowly, and a few pairs read as synonyms and are
not — **read the last section first if you read nothing else.**

## What a player does with the ball

Every touch is one of these: `SimTelemetry.Touch` in the log,
`SimDecision.Action` in the decision layer. The lists do not line up — a **hold**
is an action but not a touch kind, because it is played as a small dribble.

**Touch** — any contact with the ball, by anyone. The unit the log counts. One per
`touch_cooldown_length()`, which shortens with technique.

**On-ball decision** — the moment a player in contact is asked what to do
(`choose_and_execute`). Every option generated, scored, one picked by softmax.
Roughly one per touch.

**Carry** / **dribble** — moving the ball along in a series of touches; a dribble
is one touch of a carry, generated as eight probes around the compass. The words
are used interchangeably in the code.

**Hold** — a settling touch: the ball stays where it is. Scored as keeping
possession and advancing nothing. **Played as a `dribble` touch in the log**, so a
hold and a carry cannot be told apart there.

**Knock past a man**, also **burst** — the long one. A carrier at pace pushes the
ball nine metres ahead and turns it into a foot race. Its own candidate with its
own gate: below `BURST_PACE` it is not a race, it is giving the ball away.

**First touch** — taking down a ball with pace on it. A different primitive from a
dribble: an incoming ball to kill, a limited turn, graded by `quality`.

**Clearance** — hitting it away because keeping it is not on. Valued as the threat
it *removes*.

**Poke** — a defender's touch that wins the ball without controlling it. Logged
as `tackle` from a contest, and otherwise by why he could not take it: `block` if
the ball was struck harder than his first touch can handle, `poke` if he simply
got to a loose one first.

**Pass** — four kinds, and which exist is decided by distance rather than
weighting: **ground**, **lofted**, **through ball** (into space for a runner), and
**cross**. Below `LOFTED_FROM` only the ground ball is offered, past
`MAX_GROUND_PASS` only the air, in between both and the softmax chooses.

**Shot** — struck at goal, scored as `expected_goals` times one goal.

**Header** — a ball above `SimAerial.HEADER_FROM`, the shoulders. Three intents
stamped on the touch: **cleared**, **at goal**, **to a man** (the knock-down).

**Chest** — a ball between boot and shoulders, killed and put on the grass. Same
skill and dice as a first touch, tighter cushion, no lift. It is what stops every
bounce being a header.

**Letting it drop** — declining to head it at all: free ball, nobody near, no goal
in front. Asked *before* he is a contender, because a declined touch already
booked as a recovery is a lie in the log.

**Strike reach** — how far he can hit the ball along a line, as a fraction of what
he could hit it facing that way (`strike_scale`). A ball behind the body is not a
worse pass, it is a *shorter* one, so the long ball behind you is unavailable at
any accuracy — it has to be turned onto.

## How an option is judged

Every candidate is scored as `success x gain - (1 - success) x risk_weight x
loss`, all of it in **goal probability**, which is what makes a shot, a pass and a
carry comparable.

**Success** — the chance it comes off. **Gain** — what the ball is worth where it
ends up. **Loss** — the threat conceded at the point it would be lost, which is
*where the touch was going*; read at his own feet it is the same for every option
and nothing can tell dribbling toward his own goal from dribbling away from it.

**Expected threat (xT)** — the chance a goal eventually follows from the ball
being at a point. A grid: roughly 0.0002 deep in your own half against 0.38 near
the penalty spot. Very flat at the back, very steep at the front, and much of the
engine's behaviour follows from that shape alone.

**Expected goals (xG)** — the chance a *shot* from here scores.

**Pitch control** — the probability your side wins the ball at a point. Not "who
is nearest": arrival times include the momentum each man must shed, and everyone
within reach is weighed, so five defenders read differently from one.

**Possession value** — what simply having the ball is worth. Without it the engine
compares only where the ball ends up, and a fifty-metre punt beats a fifteen-metre
pass that keeps it.

**Territory** — the tilt up the field on that value, and the only thing in the
engine saying a metre upfield is worth having. Charged twice: what your possession
gains, and what the opponent's would be worth if you lost it there.

**Bias** — a per-candidate multiplier on an option's *positional value*, where the
plan and the standing penalties live. Never on the whole score: a penalty applied
to a negative number makes a bad option look good.

**Softmax** — how the choice is made, never argmax. The **temperature** falls with
`decisions`, and is measured against the *spread* of the candidate scores, because
the whole list often fits inside 0.02.

**Regain** — the two seconds after winning it back. While it is up the priority is
securing the ball rather than advancing it.

**Uncontrolled** — the ball arrived with pace and this player did not put it
there. He is taking it down, not choosing from a full menu.

## Room, and the sizes of a touch

Four measurements of "how much space is there", answering four questions.
Confusing them is how a carrier knocks the ball into touch.

**`run_room`** — raw distance to the boundary along a direction. The primitive.

**`carry_room`** — how big a touch this direction has room for: the intended gap
converted into the ground the ball covers before slowing to the carrier's pace,
then inverted.

**`_room_ahead`** — the same for the knock past a man, charged against where the
ball would *stop rolling*. He does not catch this one; that is the foot race.

**`stride_room`** — how big a touch his pace *this way* is worth. A sprinter
shifting it square across himself has none of that pace going where the ball goes.

**`close_control`** — shrinks a touch by how near goal it is played. Inside the box
there is no ground left to cover; the ball has to stay strikeable.

**`ahead`** / **`push`** — how far in front of himself the ball is put, in metres
of *relative* gap. The `touch` column of `Under challenge`.

**`space`** — 0 to 1, how much room the direction bought, which sizes the touch.
Read off metres and nothing else: take it from the candidate's *score* and the
chosen touch is the long one whatever the traffic.

**`max_ahead`** — the cap that guarantees the touch played is the touch that was
scored.

**Horizon** vs **reach** — the distance a direction is *judged* over against the
distance the ball is *knocked*. Two numbers, deliberately.

**`_in_play_odds`** — the probability the touch leaves the ball on the field, given
the aim error. Priced rather than forbidden, and the softmax turns him infield.

**`_escape_value`** — the race between carrier and closing man for the touch's
landing point. What makes a change of direction a real option; pitch control
cannot express it, because the carrier is nearest to all of his own probes.

## Off the ball

**Chase primary / support** — who goes for a loose ball and who backs him up,
assigned in `_assign_chasers`, where the **anti-swarm guard** also lives. **A
carrier is chase-primary for his own touch**, which is the source of several subtle
bugs.

**Recovery run** — a chaser from behind runs *round* the carrier rather than into
the back of him, and at pace, because the way round is longer.

**Slipstream** — a defender stuck directly behind a running carrier, unable to
reach a ball two metres in front of the man. What the recovery run breaks.

**Shape** — where a player stands when doing nothing else: the formation's home
position, slid with the ball and shifted by the plan.

**Offering for the ball** — how a man makes himself available: **show** (come and
meet it), **space** (drift into a pocket), **behind** (past the last defender).
Chosen and held for a commitment window.

**Claim** — the keeper coming for a ball in the air in his own area. Above head
height it is his by right; below it he must beat the first attacker by a margin
scaled by `command`. Then he holds it or **punches**.

## Contests

**Pressure** — a field, per player: how much company he has, weighted so an
opponent in front presses harder than one behind. It makes him rush. It rates the
man on a carrier's back at nearly nothing, which is why it cannot stand in for the
next one.

**Challenge** — how close he is to being *tackled*, from the closing speed of
whoever is coming, out to `CHALLENGE_SIGHT`.

**Challenger** — the specific opponent most likely to be the one.

**Contest** — two or more players going for a ball nobody owns. **Challenge (the
duel)** — a man going in on somebody who *has* it: harder, harder still from
behind, far more likely to be a foul. `Duels` reports the two separately.

## Tactics and running the thing

**Tactics are priors on the decision function, never behaviour switches.** A plan
shifts what options are worth; it does not add or remove options.

**Pattern** — a named, recognisable move: a trigger plus a nudge, on a cooldown,
counted, with a success rate after the match. A pattern that fires two hundred
times a match is not a move, it is a background hum.

**Clock rate** — match-clock seconds per simulated second. `--clock-rate 10` plays
ninety minutes in nine and is the default everywhere; `--clock-rate 1` is real
time. **Not the same as `--minutes 10`**, which plays the first ten minutes of an
ordinary match: one changes what a match *is*, the other samples a rate.

**Trace** — positions of ball and players, five times a second. The only thing
that owes the sim nothing: **when a counter and the trace disagree, believe the
trace.**

## Words that are not synonyms

**Pressure and challenge.** Pressure is company; challenge is a man arriving to
take it off you. A diagnostic bucketed on pressure calls the tailgated carrier
*free*.

**A carry and a hold.** Both are `dribble` touches in the log and they are
opposite acts: one covers ground, one refuses to.

**`ahead` and how far the ball travels.** `ahead` is the gap struck open against a
man who keeps running; the ball's own journey is two or three times that. Every
touchline bug in this engine's history has been someone checking the room against
the first number.

**A body and an option.** Counting teammates near the ball says nothing about
whether there is a pass on.

**Completed and good.** A side that rolls every ball back to its centre halves
completes 95% of them and has done nothing. `xT gained` is the honest measure.

**Sanity ranges and the §11 bands.** Two printed tables, read differently.
`CLAUDE.md` says how.
