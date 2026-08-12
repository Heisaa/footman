# Status, and what each mechanic cost

Where the build has got to, and the account of every mechanic that changed how a
match reads. Read it with "What this is judged by" in `CLAUDE.md`: a band that
moved because a behaviour went in is a fact about a missing mechanic, not a
regression.

**Every number here is a snapshot of the engine on the day it was measured, and
most are void.** They are kept because the *cause* is what a section is for — why
a behaviour was wrong, what the fix was, what it cost — and a measurement is how
that was established. Do not quote one as the engine's current figure, and do not
treat a section's numbers as a target to hold. Re-measure if a quantity matters.

Proposals that have not been built are in `docs/BACKLOG.md`.

## Phases (`PLAN.md` §10)

Phases 0-5 are built. Phase 6 has begun.

**0-3** complete and tested: physical layer, decision layer, perception, off-ball
movement. A player off the ball also chooses *how* to make himself available —
come and meet the man on the ball, drift into a pocket, or run past the last
defender — in `sim/off_ball.gd`. Those are scored in the same control-times-threat
units as everything else, softmax-picked, held for a commitment window and rationed
by a quota per team. `./run.sh diagnose` prints the split under `Offering for the
ball`.

**4** complete: the engine sits inside the §11 sanity ranges, and a full
ninety-minute eleven-a-side match runs headless in about two minutes. Several
tuning bands are still out, goals per match the largest, which is drift to watch
rather than a blocker. They get fitted at the tuning freeze (§11.1.1).

**5** complete: tactical modifiers, named patterns with counted firings and success
rates, and a passing distinguishability test.

**6** started: procedural appearance, character builder, face atlas, and a 3D match
view with flat materials, painted pitch lines, pool-noodle goals and an instanced
bobbing crowd. The camera is three fixed positions off one touchline — halfway line
and both penalty areas — each panning, tilting and zooming to hold play, cutting
between them rarely. `--frame-width`, `--elevation` and `--range` override the
framing. Animation plays at the display's frame rate rather than stepped at ten
(`--step-fps 10` puts the stop-motion back), and the run cycle drives a knee and an
ankle rather than the hips alone. Not yet judged against "watchable and charming at
1x".

A clock and a scoreline sit over it (`presentation/scoreboard.gd`, §9.6): one
hand-drawn panel, kit-coloured chips either side of the score, a clock tab under it
reading HALF TIME and FULL TIME at the breaks, and a swell and a lemon flash on the
scoring side when a goal goes in. Nothing in it is a texture, so it re-skins with
the palette.

Three anim states, `THROW`, `KEEPER_HOLD` and `HOLD` — the foot laid on the ball,
named by `SimTouch.settle` because a hold shares the carry's touch kind and could
not be told from it by `_anim_for` — are driven from the sim. `SimConsts.Anim`
is appended to and never reordered — the snapshot carries the integer and the pose
sheet indexes the same list. The pose sheet lays itself out in two rows whatever the
count, and takes its camera distance from the aspect actually being rendered rather
than an assumed 16:9. The virtual display hands out 1280x1024, and the sheet had
been cutting the outer column off both ends of every row.

A look pass over the figures (`DECISIONS.md`, eighth and ninth amendments) cut
the head to 30-35% of height and widened what a seed can produce: height and
build reach the tails, the head is scaled on two axes so a squad has long faces
and wide ones, hair is fourteen styles built from a shell pushed back off the
skull in colours hair comes in, the nose is a bump on the head from a library of
six, and the brows, eyes and mouth are per-player and independent of the
expression — with the brows carrying the expression, which is where a Mii gets
its range. The face texture is drawn at four times the old resolution and
anti-aliased, and the head is built at twice the body's polygon count. An ink outline, a set of eighties kit details and the beards were
tried in the same pass and removed: §9.7's register governs the writing, not the
art, and §9.7 now says so. Delight and despair had been drawn upside down since
the atlas was written; the parade is where that became visible.

`./run.sh parade --seed N` is the view the figures are judged in: four of that
seed's players at reading distance, turning, each captioned with number, name,
height and appearance seed, `1-5` for the expressions and `--turn 180 --still`
for the backs. It is the same squad `view3d --seed N` plays, so a note taken in
one holds in the other. Not yet judged by the owner.

## The recovery run

`SimMovement`'s recovery run made the defence able to end a carry, and a carry is
now ended a good deal more often. Goals and shots trend down with it. Whether that
is the defence being right or the attack needing more mechanics is a tuning-freeze
question. `DECISIONS.md` records why it deviates from §4.3; `docs/PITFALLS.md` has
the slipstream measurement behind it.

## The receiving layer

`SimOffBall` is the same idea and larger. A carrier with men coming to meet him,
drifting into pockets and running past the last defender has more short options than
he had, takes them, and the ball circulates in midfield. Across four ten-minute
seeds, touches in the middle third went from about 49% to about 58% and the final
third from about 27% to about 21%, with shots down with it.

The mechanic that would answer that is specific and does not exist: the carrier
cannot price a ball in behind, because expected threat is a single-step model of
where the *ball* ends up and cannot see that the receiver arrives running at goal
with the defence turned. `SimDecision.POSSESSION_VALUE` patches the same hole from
the other side. Combination play is the other half. Neither is a reason to make
players worse at offering for the ball.

## Shooting

Three things were suppressing it:

- A shot was worth roughly half a goal against alternatives worth the full expected
  threat of where the ball ended up, so carrying the ball inside the six-yard box
  scored better than striking it.
- A candidate below 0.075 expected goals was never generated, and the edge of the
  box is 0.09, so there were *no* shots from outside the penalty area at all.
- Nothing shortened a carrier's touch as he got close to goal, so a man arriving in
  the box knocked the ball another four metres and gave it to the keeper.

All three are fixed in `SimDecision` (`close_control`, and the two constants in
`_add_shot`). Measured across four ten-minute seeds: shots went from 21 to 46, and
touches inside the penalty area from 53% carried / 22% struck to 25% / 61%. A third
of shots now come from outside the box, where none did.

The count is the part to be careful about. Shots per team per ninety extrapolate to
about 50 against a §11 sanity ceiling of 35 — but total expected goals across those
four seeds is unchanged, 8.4 against 8.9, and so are the goals. The same chance
creation is being expressed as twice as many, half as good attempts: mean expected
goals per shot fell from 0.40 to 0.19, against about 0.10 in football.

What the break actually measures is that the engine gets into the penalty area far
too often — around a hundred touches in there per team per ninety against a real
twenty-five. That was always true, and was previously absorbed by carrying the ball
round the box instead of shooting at it. The mechanics that answer it are defensive
and in the box: blocks that cost the shooter, a keeper who narrows the angle, and
defenders who do not let a carrier walk to the six-yard line.

## Pitch control counting a crowd

The largest of these, because nine other things read that function. Every layer that
asks "do we own this patch of grass" now gets a different answer wherever the sides
are not one against one, which is most places.

Measured on seed 7 at ten minutes, lofted passes went from completing 93% to 62%: a
forty-metre ball into an area the opposition outnumbers us in is now priced as the
hopeful thing it is. Alongside it, a defender standing in the line of a pass got the
reach he actually has. The two together moved the engine's whole balance — on seed 7
the final third went from 17% of touches to 25%, shots from 5 to 14, and ground
passes down by about a third, because a great many short passes the engine used to
play were passes into somebody's shin.

Single-seed shot counts swing hard on noise: the same comparison run twice, on the
keeper change, came out in opposite directions. Treat any one of those numbers as a
direction, not a size.

## Shot accuracy

The largest single move any of these has made. `SHOT_AIM_BASE` went from 0.28 to
0.08 — `docs/PITFALLS.md`, "two models of the same event", has why 0.28 was never
defensible.

Measured across three seeds at ten minutes: on-target from the penalty spot went
from 2 of 12 to 12 of 16, goals from 2 to 10, and summed expected goals against
goals scored from 0.29 to 0.75. That last figure is what the change was aimed at: a
value model and an execution model that disagree by a factor of three are not both
right.

Two consequences worth stating plainly. Shots per team per ninety go to about 103
against a §11 sanity ceiling of 35, and a third of them are second attempts inside
four seconds of the last — the keeper parries, the rebound falls to an attacker, and
he strikes again. That rebound cascade is a real mechanic to look at and probably
means the keeper holds too little (`docs/BACKLOG.md`, item 3). And goals per ninety
go to about 30, which is absurd for a ninety-minute match and is not the
configuration being shipped: **at the three-minute compression the same rate is
about 1.0 goal per match, against a target of 2.7.**

## The receiver's half of the pass

Five pieces. `SimOffBall.destination_for` publishes where a man is going whatever
kind of offer he made; `SimDecision._lead_point` aims at it instead of dead-reckoning
on his current velocity; `_call_bias` lets a committed run bid up the pass that
serves it; `_give_and_go_bias` and `SimOffBall._just_passed` are the two halves of
the one-two; and `_arrival_gain` credits a pass with the threat the receiver builds
carrying it on, which is the second step expected threat has never had.

It works and it did not pay. Measured across three seeds at ten minutes: about a
quarter of all passes are now aimed at a committed run (`show` 19, `space` 36,
`behind` 15 across the three), through balls went from none at all on seed 7 to
eight, and ground passes rose by about a fifth. **Goals did not move — 10 across the
three seeds, exactly what the shooting fix left — and total expected goals fell from
13.3 to 10.2.** The engine passes better and creates less.

The reason recurs elsewhere: `_arrival_gain` and the call biases raise what a *pass*
is worth, and nothing raised what a *shot* is worth, so the softmax circulates more.
Expected threat peaks near 0.38 by the penalty spot, and a pass into that area lifted
by a 1.5 call bias can outscore a 0.26 shot from it. That is the "walks it in"
failure the shot bias in `_add_shot` was written to stop, arriving from the passing
side. The mechanics are right and the sizes are guesses; `CALL_BEHIND`,
`GIVE_AND_GO_BIAS` and `RECEIVER_CARRY_SECONDS` were picked by judgement and belong
in the tuning freeze.

The give-and-go fires rarely, two or three return balls per ten minutes per seed.
That is the counter doing its job rather than a verdict: the mechanism is reachable
and under-used, and the next question is whether the passer is dropped by
`_shortlist` once he starts his run.

## Support is an angle problem, not a distance problem

`Did he have a safe pass?` settled this, and it is the block to reach for before
anything that moves bodies. Counting teammates near the ball says nothing, because a
body is not an option: a man with a defender in the lane is a pass that gets cut out.

Measured over three seeds, of the 2.1-2.5 teammates in a six-to-eighteen-metre band,
**only about 1.1 are safely findable, and the filter is almost entirely the lane** —
roughly 1.0 per carrier-moment has an opponent within two metres of the passing line,
against 0.1 with a marker on them. The men are there and they are unmarked. The ball
cannot reach them.

**The carrier has no safe option at all 36% of the time, and no safe *forward* option
70% of the time.** That is the sideways passing and the middle-third circulation,
stated as a cause rather than a symptom.

**Retention and chance creation are negatively coupled here, and every lever tried so
far trades them at one for one or worse.** Five attempts, all measured across the same
three seeds at ten minutes against a baseline of 65 shots and 10 goals, all reverted:

| attempt | lanes blocked | kept 5 s | shots | goals |
|---|---|---|---|---|
| baseline | 1.03 | 52% | 65 | 10 |
| `SimOffBall.QUOTA` 1 → 3 short | 1.03 | 64% | — | 9 |
| `BALL_PULL_X/Z` 0.36/0.30 → 0.55/0.48 | 0.87 | 58% | 31 | 3 |
| support angle, chosen by open lane | 0.87 | 65% | 46 | 7 |
| support angle, chosen by `_value_of` | 1.00 | 55% | 45 | 8 |
| support angle, forbidden to drop deeper | 1.00 | 62% | 52 | 7 |

Two rows are worth their detail, because they are the first things anyone would try
and one looks like a clear win until you count the chances.

Raising `SimOffBall.QUOTA` from `[0, 1, 2, 2]` to `[0, 3, 3, 2]` let three men come
short instead of one. Retention went 52% to 64%, but teammates inside fifteen metres
moved only 1.83 to 1.90 and goals went 10 to 9. **The quota is not what limits
support**: the offers were never refused for lack of permission, they came short into
blocked lanes.

Raising `SimMovement.BALL_PULL_X/Z` slid the whole shape harder toward the ball.
Proximity rose to 2.0 and passes threaded past a defender fell from 18% to 15%,
completing at 57% rather than 39% — **and it halved the attack**, shots 65 to 31,
goals 10 to 3. Pulling the team toward the ball takes away the width and depth that
make a chance.

Five ideas do not fail the same way by coincidence. The sum of where the players are
is conserved: a man made available to receive is a man not stretching the defence,
and with ten outfielders against a defence already strong for the attacking mechanics
that exist, support cannot be bought except out of threat. **The answer is not in
positioning at all.** See `docs/BACKLOG.md`, "Keeping the ball without spending a
body".

## The keeper's one-on-one

`SimKeeper._one_on_one` is deliberately rare: across three seeds it fires nought to
one time in ten minutes, which is a keeper reading danger rather than one who thinks
every attack is a breakaway. It is priced straight into `expected_goals`, which counts
him as a body in the shooting line, so when it fires the engine's answer is to not
shoot. The attacking answers do not exist yet — `docs/BACKLOG.md`.

## Playing out of a challenge

The complaint was that a carrier with a man coming from behind almost always stayed in
the challenge, and that a turnover simply reversed the roles into another one.

One blind spot caused it. `SimContext.pressure` weights an opponent behind a player at
0.30 of one in front, deliberately and correctly, because pressure means "how much of
what I want to do is being taken away". Nothing else in the engine asked "am I about
to be tackled", so the carrier could not see the man on his back at all. Measured on
seed 7, 84% of his touches were another short carry and 9% were passes.

The fix is a second field, `SimContext.challenge`: angle-neutral, scaled by *relative*
closing speed, anchored so that 1.0 means the duel model would let him tackle you now.
Off it hang the escape race in `SimDecision._add_dribbles`, the knock past the man, the
hold penalty and the carrier's own speed cap. The carry now runs at 19-27% of
challenged touches, against 16-29% passes and 20-32% knocks past the man.

The regain window sits alongside the challenge field rather than inside it, because
the man who has just lost the ball is often momentarily still — he carries a recovery
penalty and a cooldown — so he reads as no threat while the pocket is still the most
crowded place on the pitch.

**Rejected: sprinting into support on a turnover.** The obvious answer to the churn
rate was that the man who wins the ball has nobody to give it to, because his
teammates amble into supporting positions at `SHAPE_SPEED`. Lifting that for the
~1.5 s after a regain, scaled by distance to the ball, moved the churn rate by nothing
at all (45% and 39% against 38% and 36% without it) and cost 40% more running, 2.4 km
per striker in a ten-minute match. It is out. The churn that remains is not the
carrier's decision and not the supporting run: a regain is stamped wherever the ball
is won, including on an isolated defender with every option covered, and answering it
needs attacking mechanics that are not built.

## The size of a touch

From the owner watching: the ball was being pushed too far in front of the man moving
it. Nothing sized a touch against the *pace of the man playing it*, though
`SimTouch.dribble` had claimed to since it was written — the size came off the
candidate's own score, a composite every term of which is high for the direction the
softmax is about to pick. Measured on seed 7, a carry pushed the ball 3.4 m in front of
a carrier travelling at about 2.9 m/s, so the ball left his foot at 5.3 and he then had
to sprint onto his own touch.

`SimDecision.stride_room` is the fix, and it is a rate rather than a size: a touch is
about half a second of his own running ahead. So the man at full pace pushes it four
metres and the same man shifting it inside his own body length keeps it under his sole,
from one rule.

Its other half is in `SimMovement._carry_pace`, and it is a loop rather than a mistake.
A carrier is chase-primary for his own touch, so he is paced at the speed that just
reaches it; the touch is then sized off that pace; a jogger therefore takes a jogger's
touch, which keeps him jogging. Nothing in it is wrong locally, and between them they
pinned a man with the whole half in front of him to about three metres a second. The
pace has to come from somewhere that is not the ball, and the honest somewhere is the
grass.

The knock past a man was freed at the same time. It required a challenger, which left
a hole exactly where the behaviour is most watchable: a man running into an empty half
has nobody near enough to *be* the challenger.

Measured across seeds 3, 7 and 11 at ten minutes: the ball runs 2.3-2.45 m between
consecutive dribble touches against 3.3 m before; a carry outside the box pushes it
2.4 m against 3.4 m, and inside the box 2.0-2.9 m against 2.7 m. Balls put out of play
fell from 39 to 24-26. Interceptions rose, 77 to 84-98, and that is a rate being read
as a count: there are half as many metres in a touch and about 50% more touches, so
more of them are contested.

One thing was built for this, measured, and taken out again, because it is the obvious
idea. A dribble is a pass to yourself, so the touch should be priced the way
`_lane_survival` prices a pass: try the sizes from the top and take the largest he
beats every opponent to. It changed nothing — the mean carry under challenge moved 2.09
to 1.98 on one seed and 1.96 to 2.17 on the other, with interceptions and balls out of
play flat. **Selection is why, and it will keep being why**: a direction with a
defender standing in it is one `_escape_value` and `control_at` have already priced out
of the softmax, so a test applied per direction only prunes touches nobody was going to
play. The blunt pressure shrink in `SimTouch.dribble` survived it and still produces the
gradient the sharp one could not: free 2.03 m, closed down 1.93 m, challenged 1.79 m, in
both seeds.

## The first touch, and the turn

From the same place: a pass received ends up behind the man, who turns in a small circle
and loses it. Three separate things, and the first two were defects.

**The angle term in `first_touch`'s difficulty had its sign the wrong way round**, and
it was worth more than everything else in the function put together. `-incoming` points
back up the ball's path, so dotting it against where the receiver wants to go scored the
*easiest* touch in football — a ball rolled into his path that he carries on with — at
the maximum penalty, and turning it back where it came from at nothing.

**Difficulty was subtracted from skill rather than discounting it**, and `first_touch *
technique` for an ordinary footballer is about 0.44 against a subtraction of 0.55 of the
difficulty. Between them, `quality` came out at 0.02 to 0.10 for every first touch in
the match: both attributes were dead weight and every player took the ball down like the
worst man on the pitch, keeping 55% of the pace and chasing it. This is model
disagreement in its clearest form — `SimDecision._shortlist` prices the same man's
control of the same ball at `lerpf(0.72, 0.99, first_touch)` when deciding whether to
pass to him.

**Third, a first touch was a brake and never a redirection**, so whatever pace survived
did so along the ball's own line. The intent handed down is `_safe_direction`, which
points at the goal, so a man receiving a ball played back to him attempted a 180-degree
turn on a ball travelling at ten metres a second, and failed it. He takes it on the
half-turn now, the turn limited by his touch the way `locomote` limits a body, and the
rest with his second touch.

The small circle was real, was not a receiving bug, and took three attempts. Lowering the
floor on the speed a player carries through a hairpin barely moved it. Capping the turn
rate by the lateral grip it needs made it **worse** — a correct constraint layered on a
controller that was already wrong.

The tick-by-tick trace showed what nothing else could. He braked hard into the turn and
then **started accelerating again thirty-five degrees in**, finishing the remaining
hundred and forty-five at a rising speed. Since grip fixes the radius at `v²/g`, a turn
made at rising speed is the definition of an arc opening into a circle.

The constraint that works is not an angle but a distance: how far off his line the turn
carries him. `TURN_SWING` is that budget, `TURN_COMMIT` stops him driving out of a turn he
has not made yet, and `docs/PITFALLS.md` has the derivation and the `TURN_PIVOT` guard
both of them need.

Measured across the same three seeds: first touches that left the ball behind the man fell
and touches into his stride rose, `quality` on the ball taken forward went from about 0.06
to about 0.26, and a man reversing from a sprint swings roughly half as far sideways as he
did. Mean speed over the match is slightly down, which is the price of turns costing
something and is the intended direction.

## Carriers running off the pitch

Two causes, one self-inflicted by the touch-size work: the probe distance was sized off
the touch, and `_room_ahead`'s inversion of the roll distance was broken. Both are in
`docs/PITFALLS.md`.

Nothing in the report could see either, which is why `How the ball changes hands` now
splits the balls that go out by the touch that put them there. That is what found the
burst: **the dribble touches that ended in a restart were played 16.6 m inside the
nearest line at 10.7 m/s** — nowhere near the paint and far too hard to be a carry.

Measured across seeds 3, 7 and 11 at ten minutes: balls out of play roughly halved from
where this work started, and of the ones a dribble put there, the knock past a man went
from most of them to nearly none. The knock is offered about half as often as it was,
because a great many of the ones being played had nowhere to go. The touch column keeps
its gradient throughout — a carry shortens as the man on him gets closer.

## The hold that was a carry

The complaint was that the man on the ball runs into opponents and over the touchline. It
was neither of the things it looked like.

`SimDecision._execute` had no `Action.HOLD` case, so a hold fell through the match
statement and was played as `SimTouch.dribble(dir, 0.15)`: a 2.2 m knock, in a direction
chosen by `_safe_direction` and scored by nothing. Hooking the softmax on seed 7, **68%
of on-ball decisions are holds, and 403 of the match's 527 carry touches came out of that
branch rather than out of the eight scored probes.** One every 0.47 s, 2.08 m at a time —
which is the `dribble rhythm` line, and had been all along.

The candidate says the opposite of what the execution does. `_add_hold` reads its gain and
its loss at the player's own feet and calls itself "safe but goes nowhere"; it then
covered ground at 4.5 m/s. Nothing on that path asks what is in front of him, where the
touchline is, or how near goal he is, because `carry_room`, `_in_play_odds` and
`close_control` all live in `_add_dribbles`.

Split by which path played them, on seed 7: holds were three times as likely as a scored
dribble to be knocked into a body four to fifteen metres up the lane, 28% against 10%, and
that band lost the ball inside two seconds about 45% of the time against 15% for a clear
lane. Across seeds 3, 7 and 11 the carry was 43%, 49% and 51% of every turnover in the
match, about a second after the touch — far and away the largest single way the ball
changed hands.

So the hold is now a hold: `HOLD_AHEAD`, which is `SimTouch.DRIBBLE_AHEAD_FLOOR`, capped
again by `carry_room`, in a direction that has to have the grass for it (`_hold_fits`) and
has to be clear of whoever is standing in it (`_hold_obstacle`). That last one replaces
"the nearest opponent inside four metres", which was too short, since `CHALLENGE_SIGHT` is
5.5 m, and the wrong shape, since it moved the touch for a marker three metres *behind*
the carrier and not for a defender six metres dead in front of him. How far down the lane
to look is not a constant: it is `carry_travel` plus the old radius, so a standing player
looks about five metres and a man at full pace about ten, from one rule rather than two.

**Carrying it over a line is gone.** Of 496 carries played within 11 m of a line, one went
out inside three seconds. The carries that still go out are struck hard from fifteen to
twenty metres inside the line — aim error on a long knock, the priced-not-forbidden case,
not a man walking it over the paint.

**Territory went up, not down**, on all three seeds, and turnovers fell. The engine still
carries into people, but those are scored dribbles now, priced against the alternatives,
which is the design. Losing the ball 28 fewer times in half an hour is worth more than the
metre a touch of unearned ground it replaced. Shots were flat in total and swung hard per
seed; three seeds cannot say more than that.

## A hold may not give up ground

The owner watched a carrier collect the ball near the halfway line, get chased, and run it
back to his own extended goal line without ever appearing to decide to. Nothing in the
touch log or the §11 bands could see it — every touch in the retreat is an ordinary carry,
and retreating with the ball is retaining the ball. It was measured off the positional
trace instead: on seed 1, a spell of 22.6 m over six seconds with a man on him 94% of the
time, and shorter versions several times a match.

The cause was not the dribble probes, which price the ground they give up and mostly do not
take it. It was `HOLD`. Under a challenge it beats every other candidate comfortably — its
success is ~0.7 where a scored dribble into a goal-side defender is ~0.05 — and `_execute`
sent it down the fallback branch, which plays a real two-metre touch in `_safe_direction`:
forty percent forward, plus straight away from the nearest man. With that man goal-side,
which the recovery run made the normal case, "away" is the carrier's own goal. The option
scored as *keeping the ball where it is* walked it backwards, twelve touches in a row, with
nothing in the score sheet charged for the journey.

`_safe_direction` now strips the retreating component out of the shelter direction, and
plays square across the man — into whichever side has the pitch for it — when he is directly
goal-side. Dropping back with the ball is still available in the eight scored probes and in
a pass, which price it.

Measured on seeds 1, 3 and 7 at ten minutes: spells losing more than eight metres fell from
16/10/7 seconds of play to 3/2/5, and the longest from 22.6 m to 8.8 m. Shots on seed 7 went
7 to 4 and touches in the box 40 to 26. One ten-minute seed, so the shot count means very
little on its own, but the direction is real: a carrier who could always shelter backwards
was manufacturing time on the ball that he had not earned.

`SimDiagnostics._giving_up_ground` prints the measurement, because nothing else does, and
the first attempt at it — off the touch log, orientation read at full time — got the sign
wrong on every first-half touch and reported forward carries as retreats.

## A dribble probe is charged where the touch would be lost

The eight short probes read their `loss` term at the carrier's own feet rather than at the
point he was knocking it to. It was the only candidate in the engine that did, with the
knock past the man twenty lines below it doing it correctly.

The consequence was not a wrong number but an absent one: the same loss for all eight
directions, so the risk term could not tell dribbling toward one's own goal from dribbling
toward the other one. In one's own half it is the only term that could. Expected threat for
the team in possession is flat back there — order 0.0002, against the 0.013
`POSSESSION_VALUE` adds for merely having the ball — while the threat conceded on a turnover
climbs steeply toward one's own box.

Measured across seeds 1, 3, 5, 7 and 11 at ten minutes, shots went from 4/2/4/4/11 to
2/10/3/19/6: 25 to 40 in total, and 3 goals to 5. The seed-to-seed spread is as wide as the
shift, so five matches cannot tell it from noise. What can be said is that it did not
quieten the engine, that it costs nothing where the value field is steep, and that it gives
the attacking third bolder carries, because the threat conceded by losing it thirty yards
from the opponent's goal is near zero. Spells losing eight metres or more ran 1/0/2/0/3
across the same seeds, so the retreat the hold fix closed did not come back through this
door.

It was found while explaining that retreat and is unrelated to it: applied on its own,
before the hold fix, it moved the retreat numbers hardly at all. The escape geometry swings
a probe's success by twenty to fifty times across the eight directions, and a few percent on
the risk term does not answer that.

## Rolling resistance, and the second constant that was hiding

`ROLL_DECEL_DRY` 1.6 to 2.4 (long grass 2.3 to 3.4, the wet factor unchanged), and
`SimTouch.DRIBBLE_RELATIVE_DECEL` deleted — every site that read it now reads
`SimEnv.roll_decel`.

The complaint was that the ball reads as running away from people. Measured first, because
friction is not a free knob: pairing every touch with the next one, a carry put the ball
2.5 m away in 0.53 s and it was still doing 3.3 m/s when the same man touched it again,
which he did 80-85% of the time. **The carry was not the problem, and friction could not
have fixed the ones that were.** A ground pass arrives at a man's feet at 8.7 m/s, and
`SimBallistics.ground_pass_speed` solves the launch speed against `roll_decel`, so arrival
pace is invariant to it by construction. A first touch left 4.5 m/s on the ball, which is
`SimTouch.first_touch`'s own model. On the deck the ball spent 46% of the match above
6 m/s — faster than anyone can run — and 24% of it with nobody inside 3 m.

The constant that *was* wrong was the other one. `DRIBBLE_RELATIVE_DECEL` described
"deceleration of a dribbled ball relative to a player running alongside it", which is
`roll_decel` — a carrier holding his pace is a stationary frame for the ball — and carried a
different number for it. Two consequences, both invisible:

- **The touch never opened the gap it was struck to open.** `dribble` picks the strike speed
  from the constant and the grass then does the arithmetic: at 1.25 against a real 1.6, a
  touch played to sit 4.5 m in front sat 3.5 m in front, and the same 78% at every size.
  Every term the decision layer read off `ahead` — `carry_room`, `carry_travel`,
  `_in_play_odds`, `space` — described a touch that did not happen.
- **Pitch conditions never reached the carry.** `roll_decel` moves with grass length and
  wetness; a constant moves with nothing. On long grass the ball was slow everywhere in the
  engine except at the feet of the man carrying it.

**The ball no longer gets away from anybody.** Touches made beyond `CONTROL_RANGE` went to
nothing, and the only ones left are keeper catches and blocks — dives and deflections, which
belong there. The carry rhythm went back to a footballer's, about half a second between
touches, and that answers the caveat the hold fix left: the carry had become more touches of
a smaller size, and it is now fewer touches of the size they were scored at. The ball runs
further per touch, which is the correction and not a regression — the gap is real now, so it
costs the ground it should. Balls out of play were flat.

**Territory is down, and it is the reason to look at this by eye.** Touches in the final
third and in the box both fell, on both seeds. A grabbier ball ought to make the pitch play
*smaller*, not bigger, so this is not obviously the mechanism doing what it should. Two
seeds of ten minutes is a small sample for a count that swings this hard, and the honest
reading is that it wants a longer look rather than a coefficient.

## Pass arrival pace, and the first touch

The two things rolling resistance could not reach, in the order the measurement ranked them.

**`SimDecision.arrival_pace`, slope 0.35 off a floor of 3.5, put an ordinary fourteen-metre
ball into a man's feet at 9.2 m/s.** That is not a pass, it is a drive, and it was the
largest single reason the ball read as running away from people. It is also the one number
friction cannot touch: `SimBallistics.ground_pass_speed` solves the launch speed *against*
`roll_decel` to hit the pace asked for here, so a grabbier pitch strikes the ball harder and
it still arrives at 9.2. It is now `2.2 + distance * 0.21`: about 3.5 m/s at five metres,
4.7 at ten, 5.6 at fourteen, 7 at twenty, just under 10 where a ground pass stops being
offered at all. The original docstring's point survives in the slope — a long ball is still
driven. It was the intercept that was wrong.

**The first touch was missing half of its own physics.** `residual` is purely proportional,
and proportional alone cannot express the act: it says a ball arriving twice as fast leaves
twice as fast however well it is controlled, so a driven ball taken down by the best receiver
on the pitch still ran away from him — at a good quality of 0.4 a 15 m/s ball left his foot
at 5.4, faster than he can run. No value of `residual` fixes that without also making a bad
touch gentle, and a bad touch on a firm ball *should* spray it; that is where the loose balls
come from.

What was missing is that a footballer does not scale the ball's pace down, he absorbs it, and
how much sting a man can take out is a fact about his technique rather than about how hard it
arrived. The touch now keeps the lesser of the two — `CUSHION_WORST` to `CUSHION_BEST` on
`quality`, proportional for an ordinary ball and absorbed for a fierce one. Keyed on quality,
so it barely exists for a poor touch and nothing is clamped away.

**And one inconsistency the friction change had made worse.**
`SimBallistics.ground_travel_time` approximated the slide-then-roll deceleration as
`roll_decel * 1.7`, a fitted number that sat 21% high at a rolling resistance of 1.6 and went
to 38% high at 2.4. `ground_pass_range` is `k v^2` and constant deceleration is `v^2 / 2a`, so
the two agree at `a = 1 / 2k` and there was nothing to fit. `_pass_success` prices every pass
off the travel time this returns, so a long ball was being charged for a journey it did not
make, by an amount that depended on the grass. It is now `blended_decel`, derived from the
same `k`.

Also fixed in passing: the through ball was *scored* on `t_pace` — `t_travel`, `t_success` and
the arrival gain all came from it — and *struck* at a flat 6.0. The same mismatch between the
scored option and the played one that the carry had, in the other half of the decision layer.

Measured on seeds 7, 11 and 3 at ten minutes. **The first touch leaves about 3 m/s on the
ball rather than about 4**, and the receiver still has it three seconds later 80% of the
time. **Most passes no longer need a first touch at all** — an ordinary ball now arrives
below the `uncontrolled` threshold and the receiver simply plays it. That is also why
`Taking it down`'s `arrived` column still reads high and is *not* evidence the fix failed:
the block only sees balls above that threshold, so its population is now the fast tail of
long balls, clearances and deflections. Completion falls with length now, because a slower
ball is easier to control and easier to cut out, which is the trade football makes. The
carry is untouched.

**What moved, and what would answer it.** Shots are down and final-third touches with them.
The seed spread is enormous at this sample size, so the honest statement is that it wants a
batch rather than a coefficient.

The mechanism is not mysterious: a slower ball is longer in flight, `_pass_success` prices
interception off exactly that, and the forward passes are the long ones, so the engine plays
shorter and safer. The mechanics that would answer it are in `docs/BACKLOG.md`: expected
threat still cannot price a receiver arriving at goal with the defence turned, and of the
combination play only the give-and-go exists, firing two or three times per ten minutes.
Neither is a reason to put a nine-metre-a-second pass back into a man's feet from fourteen
metres.

## A hold is a hold in the pitch's frame, not the carrier's

The owner watched #7 take five holds near the halfway line and the ball leave him at ten
metres a second. Reproduced on seed 2 at 1.0 v 1.0, decisions at t94, t105, t116, t163,
t224 — five holds, weight 100/99/99/97/95%, and nothing else chosen.

`SimTouch.dribble` strikes at `along + delta`: the carrier's own pace, plus the 2.3 m/s
that opens a metre of daylight. For a carry that is right and is what `carry_room` and
`carry_travel` price. For a hold it made the constant and the strike disagree —
`HOLD_AHEAD` does not grow with his pace and the launch speed did — and the disagreement
feeds itself. He is chase-primary for his own touch, so he runs to catch a ball struck
harder than he meant, arrives quicker, and strikes the next one harder still:

| touch | his speed | ball leaves at |
|---|---|---|
| t106 | 1.08 m/s | 3.19 m/s |
| t117 | 1.71 | 4.93 |
| t164 | 5.60 | 7.95 |
| t225 | 7.59 | 10.68 |

Four holds took a standing midfielder to 8.7 m/s with no decision to run anywhere, and the
last settling touch ran eleven metres into nobody. `SimTouch.settle` drops the `along` term
so `ahead` is measured against the grass, and `SimPlayer.settling` turns off the two
movement floors that ask a man on the ball for more than the pace that reaches it —
otherwise he sprints past a ball he has just stopped. On the same passage he now holds it
at his feet through eleven touches and plays a 14 m pass to #6 as the challenge builds.

**Seed 7, ten minutes.** Interceptions 92 to 63, scrappy turnovers 22 to 5, balls out of
play 14 to 4 and none of them carried out, regains lost again 35% to 22%, passes 97 to 200.

**Territory fell and that is this mechanic.** Own/middle/final went 23/58/18 to 12/75/14 and
box touches 18 to 2. A hold used to walk the ball several metres upfield on every touch,
aimed at goal, charged nothing, on 68% of decisions — the team was being carried forward by
the option scored as going nowhere. The second symptom is the same fact: 1019 carry touches
at 0.26 s and 0.62 m against 335 at 0.53 s and 2.61 m. He was always choosing hold at that
rate; the runaway hid it by making each touch bigger. What would answer it is the scoring,
not the execution: in flat midfield almost all of a candidate's score is `POSSESSION_VALUE`
and the hold has the highest success by construction, so it wins until a challenge arrives.

## The other half of the hold: a first touch that was scored at a standstill

`_play_hold` has two branches and only one was fixed. A ball arriving with pace goes to
`SimTouch.first_touch`, which is a cushion and not a stop — measured, it leaves 2.6 to
3.5 m/s on the ball, one to two and a half metres of grass — while `_add_hold` read its gain
and its loss at the player's own feet. Every `first_touch` in a match comes from this branch;
the only other caller is the empty-candidate fallback.

`SimTouch.first_touch_drift` is the execution's own model with the dice taken out, and
`_add_hold` scores the uncontrolled case where it says the ball stops. The direction and
quality calculation is now shared by both layers (`_resolve_first_touch`) so they cannot
part company again — `docs/PITFALLS.md` has the general case.

Deliberately not changed: `success` still reads the attribute rather than the touch's own
`quality`. It is already about right — `Taking it down` measures 86-92% kept three seconds
later against the 0.72-0.97 this scores. The known cost is that a poorer receiver is
credited with the extra ground his worse touch runs.

**Seed 7, ten minutes, against the settle fix alone.** Shots flat at 6, box touches 2 to 5,
interceptions 63 to 58, balls out of play 4 to 3, thirds 12/75/14 to 13/73/14. Small, and
expected: the drift is one to two metres and expected threat is flat over that everywhere
except near the box.

## The knock past a man was scored a third of the way to where the ball goes

`push` is a gap between two moving things — the daylight left between the ball and a man who
keeps running — and the four value terms beside it read a fixed spot on the grass at
`pos + dir * push`. The ball's own journey is `push` plus every metre the carrier covers
while it is still faster than him:

	travel = push + along * delta / decel        (`carry_travel`)

At a roll of 2.4 and a nine-metre knock the ball is out in front for 2.7 s, and a carrier at
6 m/s runs 16 of the 25 metres it covers. Two and a half to three and a half times `push`,
rising with his pace.

The ordinary carry has the same geometry and is fine: he plays it again every third of a
second and the gap never opens, which is what the `horizon` comment means by pricing a
direction over several touches. **The burst is the one touch in the engine that runs to
completion** — not re-touching is the act — so it is the only candidate whose ball travels
the whole distance. The touchline half of this was converted years of bugs ago, in
`_room_ahead`; `control_at`, `_escape_value` and the two `xt_at` calls sat four lines below
it and were not. `point` moves too, so a man who has knocked it twenty-five metres does not
set off toward the nine-metre mark.

**Two seeds, ten minutes each, and they agree about two things.** Middle-third share rose on
both (73 to 78, 74 to 78), final-third share fell on both (14 to 11, 18 to 14), and
turnovers in contact rose on both (7 to 12, 6 to 10). Everything else disagrees by seed:
shots 6 to 11 on one and 14 to 11 on the other, box touches 5 to 12 and 6 to 4,
interceptions up on one and down on the other.

The direction that replicated is the one the mechanism predicts. A nine-metre knock from
thirty metres out puts the ball five metres from their goal — on the byline or at the
keeper — and that is what it is now priced as, where before it was priced as the good
position nine metres away. Whether an engine that answers by playing in the middle third is
better football is a question for the eye, not for this table.

## A hold is worth the decision it defers, not the ball it keeps

Every other candidate resolves the possession: a pass ends with the ball somewhere else and a
new situation on the pitch, a shot ends it outright, and `score_of` states what the
possession is worth afterwards. A hold states nothing — the ball is where it was, he still
has it, and he still has to decide. Scoring it as `POSSESSION_VALUE` plus the grass under his
feet credited him for retaining what was never at stake, and did it again every touch
cooldown.

Since expected threat is flat through the middle third, `POSSESSION_VALUE` was thirteen times
the whole positional signal there, every candidate's gain collapsed to roughly the same
number, and what was left discriminating between them was `success`. The hold is the highest
success by construction — it is the option defined as not attempting anything. On seed 2 one
midfielder held eleven times in a row at 95-100% of the softmax weight, with a through ball
on the list whose positional gain was twelve times the hold's, scoring negative.

`_hold_score` prices it as one step of waiting: with `success` he still has the ball and
faces this board one touch later, otherwise he has lost it here. The continuation is the best
of his other options put back through `score_of` with an extra discount, so a good option
decays toward nothing while a bad one stays as bad — the hold can beat a list of losing
options and cannot beat a winning one. On the same passage he now holds at 39-40% against
the best pass at 55%, which is a choice rather than a foregone conclusion.

**Two defects in the first cut, both found by measuring and both worth recording.**

*The discount had no units.* `future_discount()` is a discount on an action — a pass in
flight, a carry into space, something on the order of a second — and a hold defers by one
touch cooldown, 0.17 to 0.27 s. Charged in full it costs 16% per hold; charged per second of
actual delay, `DISCOUNT_SECONDS`, it costs 4%, and eleven in a row still cost a third. The
constant existed implicitly and was wrong the moment anything had to be priced against the
same option taken *now*.

*A prior applied to a negative value is not a prior.* `score_of` guards its `bias` by
ignoring it when the value is negative, which is right for a penalty and silently drops a
promotion. The 1.5 on `uncontrolled` is the whole of "take a touch rather than play a ball
that is still moving", and in the middle third the continuation is usually negative, so it
was being dropped exactly where it works. First touches fell from 142 in a match to 27 —
one-touch football, every ball played away before it was controlled. Scaling toward zero
above one and away from it below keeps a prior a prior.

**Seeds 7 and 3, ten minutes.** The carry is a footballer's again on both: 0.42 s and 2.11 m
between touches, 0.56 s and 3.06 m, against 0.27 s and 0.61 m. That is the 4 Hz patting gone,
and it is the visible one.

The cost is on both seeds too. Ground passes 218 to 334 and 211 to 354, against a real ten
minutes of football at something like a hundred. Own-third touches 11% to 18% and 8% to 17%,
final third 11% to 8% and 14% to 8%. Shots 11 to 5 and 11 to 9. Box touches disagree by seed
(12 to 5, 4 to 15) and so do turnovers (35% to 42%, 33% to 34%).

**What would answer it.** With the retention fiction gone every option in the middle third
scores near zero, because expected threat is flat there and cannot say that one pass breaks a
line and another does not. The engine picks among near-equals and the ball changes feet more
often than football does. Both of the mechanics that would price the difference are in
`docs/BACKLOG.md`. The second is deeper: the score is now honest per decision while the
*cadence* is still per touch, so a man is asked the whole question afresh every 0.17 s and has
no way to express "I am still doing the thing I decided to do." The hold was standing in for
that, propped up by a fiction, and removing the fiction leaves the gap visible.

## A carrier could not see where his own touch would finish

The owner watched a full-back carry it out of play at pace with nobody near him, and read it
as a friction problem. It was a horizon problem, and `carry_room`'s own comment stated it:

> It is the ground the ball covers until it has slowed to his pace, which is the moment he
> starts closing on it.

That is not where the ball ends up. At the moment it has slowed to his pace the ball is still
doing seven metres a second, the gap is fully open, and he has closed nothing. Closing
`ahead` metres on a ball that is still rolling takes as long again, and the two stages come to
`2 * along * delta / decel`:

| his pace | slows to his pace at | he reaches it at | it stops at |
|---|---|---|---|
| 2 m/s | 3.0 m | 3.8 m | 3.8 m |
| 4 | 7.6 | 10.8 | 10.9 |
| 7 | 16.3 | 25.0 | 26.5 |
| 8.5 | 20.1 | 31.8 | 35.2 |

Ten metres at a sprint, and the ball is beyond his reach for all of it — there is no second
touch to shorten it with, so the decision that struck it is the only one that could have
known. It matches the old measurement exactly: carries that went out were struck 16.8 m
inside the nearest line at 11.2 m/s, which passes a sixteen-metre test and rolls twenty-six.

`carry_travel` now reports the second figure and `carry_room` inverts it, so one convention
answers both. `settle_room` splits off the hold, which does not carry his pace at all since
`SimTouch.settle` went in and was being refused touches it could comfortably make.

**Seeds 7 and 3, ten minutes.** Carries out of play 2 and 2 to **0 and 1**; every edge band on
both seeds reports nothing going out inside three seconds. The balls still leaving the field
are shots behind the goal, which rose because shots rose.

Shots went **up** on both, 5 to 14 and 9 to 13, and final-third touches with them, 8% to 10%
and 8% to 12%. That is worth flagging rather than celebrating: this figure is within six per
cent of the free-roll test recorded above under "the distance to price it against", which was
measured to take "nearly every forward touch in the attacking half off the table and cost half
the shots in a match". It did not reproduce. The likeliest reason is that the engine around it
is not the one that measurement was made in — `close_control` and `_in_play_odds` both post-date
it, and the hold rework changed what the carry is competing against. Worth a second look if
the attacking third ever looks thin.

## Passing forward, and the term that was missing

The owner watched the ball go backwards out of positions where a safe forward pass was
on. Measured on seed 7 at ten minutes, **42% of every pass in the match went backwards
and 15% went more than fifteen metres forward.**

The cause is arithmetic and it is the same one `_hold_score` was written for. Expected
threat as this engine bakes it is 0.0001 on your own eighteen-yard line and 0.004 at the
halfway line, against the flat 0.013 the engine added for merely having the ball. The
whole of your own half — thirty-five metres of ground — was worth under a third of what
having the ball at all was worth, and `_add_passes` then multiplied that positional
difference by a length bias of about a fifth while the possession term went in after the
bias, untouched. What was left separating a pass forward from a pass back was `success`,
and the ball rolled back to a man with nobody near him is the highest success on the list
by construction.

So `POSSESSION_VALUE` became `SimDecision.possession_value`, a function of where the ball
ends up, tilted up the pitch by `TERRITORY`. Every candidate now carries an `end` — where
the possession stands once the option is played — and it is charged twice: what your own
possession is worth there, and what the opponent's would be worth if you lost it there.
`SimOffBall._value_of` and the throw-in in `SimSetPiece` read the same function, so a man
offering ahead of the ball is now worth more than the same man offering behind it, which
is the receiver's half of the same complaint.

**Lifting the expected-threat map instead does not work**, and the reason is worth
keeping. The map is read twice per candidate, once as `gain` where the ball is going and
once as `loss` for the opponent at the same point, and only `gain` is scaled by the bias.
Add the same territory to both and the loss half wins — a flatter map makes the *forward*
pass score worse. Territory has to be priced where the bias cannot reach it.

Also removed: the `maxf(gain, current_threat * 0.85)` floor under a ground pass's gain,
which handed the ball played backwards most of the value of the position it was giving up.

**Seed 7, ten minutes, against the same engine with `TERRITORY` at zero.**

| | flat | 0.4 | 0.75 |
|---|---|---|---|
| passes backward | 42% | 33% | 19% |
| forward, of which long | 39% (15%) | 56% (27%) | 67% (37%) |
| long-forward completion | 74% | 72% | 47% |
| ground gained per possession | 5.2 m | 8.7 m | 8.6 m |
| passes per possession | 3.2 | 2.4 | 1.4 |
| touches in the final third | 9% | 16% | 24% |
| shots | 14 | 15 | 34 |

**0.4 is the size that leaves it a passing side.** At 0.75 the ball goes further forward
again and the engine stops passing: better than a third of every ball long and forward at
47% completion, possessions of one and a half passes, shots up two and a half times. That
is not the mechanic being tuned away from a band — it is the mechanic having no
counterweight. Territory is credited in metres, so the ball that gains most of it is the
long one, and a long ball escapes the length bias entirely because this term is added
after it. What should pay for that is the cost of losing it stretched, which is the same
thing the knock past a man cannot price and which a single-step model has no vocabulary
for. Until that exists, territory stays modest and `success` carries what there is.

One seed, ten minutes, and the seed spread on this engine is large. What it can see is the
direction and the character; what it cannot is the rate.
