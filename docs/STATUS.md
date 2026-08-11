# Status, and what each mechanic cost

Where the build has got to, and the measured account of every mechanic that moved
the numbers. Read with "What this is judged by" in `CLAUDE.md`: a band that moved
because a behaviour went in is a fact about a missing mechanic, not a regression.

## Phases (`PLAN.md` §10)

Phases 0-5 are built, and Phase 6 has begun.

- **0-3** complete and tested: physical layer, decision layer, perception,
  off-ball movement. A player off the ball also chooses *how* to make himself
  available — come and meet the man on the ball, drift into a pocket, or run past
  the last defender — in `sim/off_ball.gd`, scored in the same
  control-times-threat units as everything else, softmax-picked, held for a
  commitment window and rationed by a quota per team. `./run.sh diagnose` prints
  the split under `Offering for the ball`.
- **4** complete: the engine sits inside the §11 sanity ranges, and a full
  ninety-minute eleven-a-side match runs headless in about two minutes. Several
  tuning bands are still out — goals per match is the largest gap — which is drift
  to watch, not a blocker. They get fitted at the tuning freeze (§11.1.1).
- **5** complete: tactical modifiers, named patterns with counted firings and
  success rates, and a passing distinguishability test.
- **6** started: procedural appearance, character builder, face atlas, and a 3D
  match view with flat materials, painted pitch lines, pool-noodle goals and an
  instanced bobbing crowd. The camera is three fixed positions off one touchline —
  halfway line and both penalty areas — each panning, tilting and zooming to hold
  play, cutting between them rarely; `--frame-width`, `--elevation` and `--range`
  override the framing from the command line. Animation plays smoothly at the
  display's frame rate rather than stepped at ten (`--step-fps 10` puts the
  stop-motion back for a comparison), and the run cycle drives a knee and an ankle
  rather than the hips alone — see `DECISIONS.md`. Not yet judged against
  "watchable and charming at 1x".

  A clock and a scoreline sit over it (`presentation/scoreboard.gd`, §9.6): one
  hand-drawn panel, kit-coloured chips either side of the score, a clock tab
  hanging under it that reads HALF TIME and FULL TIME at the breaks, and a swell
  and a lemon flash on the scoring side when a goal goes in. Nothing in it is a
  texture, so it re-skins with the palette.

  Two anim states, `THROW` and `KEEPER_HOLD`, are driven from the sim.
  `SimConsts.Anim` is appended to and never reordered — the snapshot carries the
  integer and the pose sheet indexes the same list. The pose sheet lays itself out
  in two rows whatever the count, and takes its camera distance from the aspect
  actually being rendered rather than an assumed 16:9; the virtual display hands
  out 1280x1024, and the sheet had been quietly cutting the outer column off both
  ends of every row.

Open `[DECIDE]` questions from §12 are in `DECISIONS.md` with the defaults in
force, along with the amendments made to the plan itself.

## The recovery run

`SimMovement`'s recovery run made the defence able to end a carry, and a carry is
now ended a good deal more often. Goals and shots trend down with it. Whether that
is the defence being right or the attack needing more mechanics is a tuning-freeze
question, not one to fit a coefficient against now.

## The receiving layer

`SimOffBall` is the same and larger. A carrier who has men coming to meet him,
drifting into pockets and running past the last defender has more short options
than he had, takes them, and the ball circulates in midfield: across four
ten-minute seeds, touches in the middle third went from about 49% to about 58%,
and the final third from about 27% to about 21%, with shots down with it.

The mechanic that would answer it does not exist yet, and it is a specific one:
the carrier cannot price a ball in behind properly, because expected threat is a
single-step model of where the *ball* ends up and cannot see that the receiver
arrives running at goal with the defence turned. It is the same limitation
`SimDecision.POSSESSION_VALUE` exists to patch from the other side. Combination
play — the give-and-go, the third man — is the other half of turning midfield
possession into entry. Neither is a reason to make players worse at offering for
the ball.

## Shooting

Three things were suppressing it: a shot was worth roughly half a goal against
alternatives worth the full expected threat of where the ball ended up, so
carrying the ball inside the six-yard box scored better than striking it; a
candidate below 0.075 expected goals was never generated, and the edge of the box
is 0.09, so there were *no* shots from outside the penalty area at all; and
nothing shortened a carrier's touch as he got close to goal, so a man arriving in
the box knocked the ball another four metres and gave it to the keeper. All three
are fixed in `SimDecision` (`close_control`, and the two constants in `_add_shot`).

Measured across four ten-minute seeds: shots went from 21 to 46 and the touches
taken inside the penalty area went from 53% carried / 22% struck to 25% / 61%. A
third of shots now come from outside the box, where none did.

The count is the part to be careful about. Shots per team per ninety extrapolate
to about 50 against a §11 sanity ceiling of 35 — but the total expected goals
across those four seeds is unchanged, 8.4 against 8.9, and so are the goals. The
same chance creation is being expressed as twice as many, half as good attempts:
mean expected goals per shot fell from 0.40 to 0.19, against about 0.10 in
football. What the break actually measures is that the engine gets into the
penalty area far too often — around a hundred touches in there per team per ninety
against a real twenty-five — which was always true and was previously absorbed by
carrying the ball round the box instead of shooting at it. The mechanics that
answer it are defensive and in the box: blocks that cost the shooter something, a
keeper who narrows the angle, and defenders who do not let a carrier walk to the
six-yard line.

## Pitch control counting a crowd

The largest of these, because nine other things read that function. Every layer
that asks "do we own this patch of grass" now gets a different answer wherever the
sides are not one against one, which is most places. Measured on seed 7 at ten
minutes, lofted passes went from completing 93% to 62% — a forty-metre ball into
an area the opposition outnumbers us in is now priced as the hopeful thing it is.
Alongside it, a defender standing in the line of a pass got the reach he actually
has, and the two together moved the engine's whole balance: on seed 7 the final
third went from 17% of touches to 25%, shots from 5 to 14, and ground passes down
by about a third, because a great many short passes the engine used to play were
passes into somebody's shin.

Single-seed shot counts swing hard on noise — the same comparison run twice, on
the keeper change, came out in opposite directions — so treat any one of those
numbers as a direction and not a size.

## Shot accuracy

The largest single move any of these has made. `SHOT_AIM_BASE` went from 0.28 to
0.08 — `docs/PITFALLS.md`, "two models of the same event", has why 0.28 was never
defensible. Measured across three seeds at ten minutes: on-target from the penalty
spot went from 2 of 12 to 12 of 16, goals from 2 to 10, and summed expected goals
against goals scored from 0.29 to 0.75. That last figure is the one the change was
aimed at, since a value model and an execution model that disagree by a factor of
three are not both right.

It moves two things worth stating plainly. Shots per team per ninety go to about
103 against a §11 sanity ceiling of 35, and a third of them are now second
attempts inside four seconds of the last one — the keeper parries, the rebound
falls to an attacker, and he strikes it again. That rebound cascade is a real
mechanic to look at and probably means the keeper holds too little. And goals per
ninety go to about 30, which is absurd for a ninety-minute match and is not the
configuration being shipped: **at the three-minute compression the same rate is
about 1.0 goal per match, against a target of 2.7.**

## The receiver's half of the pass

Built as items 6, 7, 9 and 8 of the list in `DECISIONS.md`.
`SimOffBall.destination_for` publishes where a man is going whatever kind of offer
he made; `SimDecision._lead_point` aims at it instead of dead-reckoning on his
current velocity; `_call_bias` lets a committed run bid up the pass that serves it;
`_give_and_go_bias` and `SimOffBall._just_passed` are the two halves of the
one-two; and `_arrival_gain` credits a pass with the threat the receiver builds
carrying it on, which is the second step expected threat has never had.

It works and it did not pay. Measured across three seeds at ten minutes: about a
quarter of all passes are now aimed at a committed run (`show` 19, `space` 36,
`behind` 15 across the three), through balls went from none at all on seed 7 to
eight, and ground passes rose by about a fifth. **Goals did not move — 10 across
the three seeds, exactly what the shooting fix left — and total expected goals fell
from 13.3 to 10.2.** The engine passes better and creates less.

The reason will recur: `_arrival_gain` and the call biases raise what a *pass* is
worth, and nothing raised what a *shot* is worth, so the softmax circulates more.
Expected threat peaks near 0.38 by the penalty spot, and a pass into that area
lifted by a 1.5 call bias can outscore a 0.26 shot from it — the "walks it in"
failure the shot bias in `_add_shot` was written to stop, arriving again from the
passing side. The mechanics are right and the sizes are guesses; `CALL_BEHIND`,
`GIVE_AND_GO_BIAS` and `RECEIVER_CARRY_SECONDS` were all picked by judgement and
belong in the tuning freeze.

The give-and-go fires rarely — two or three return balls per ten minutes per seed.
That is the counter doing its job rather than a verdict: the mechanism is reachable
and under-used, and the next question is whether the passer is being dropped by
`_shortlist` once he starts his run.

## Support is an angle problem, not a distance problem

`Did he have a safe pass?` is the block that settled this, and it is the one to
reach for before anything that moves bodies. Counting teammates near the ball says
nothing, because a body is not an option: a man with a defender in the lane is a
pass that gets cut out. Measured over three seeds, of the 2.1-2.5 teammates in a
six-to-eighteen-metre band, **only about 1.1 are safely findable, and the filter is
almost entirely the lane** — roughly 1.0 per carrier-moment has an opponent within
two metres of the passing line, against 0.1 with a marker on them. The men are
there and they are unmarked; the ball cannot reach them.

**The carrier has no safe option at all 36% of the time, and no safe *forward*
option 70% of the time** — which is the sideways passing and the middle-third
circulation, stated as a cause rather than a symptom.

**Retention and chance creation are negatively coupled here, and every lever tried
so far trades them at one for one or worse.** Five attempts, all measured across
the same three seeds at ten minutes against a baseline of 65 shots and 10 goals,
all reverted:

| attempt | lanes blocked | kept 5 s | shots | goals |
|---|---|---|---|---|
| baseline | 1.03 | 52% | 65 | 10 |
| `SimOffBall.QUOTA` 1 → 3 short | 1.03 | 64% | — | 9 |
| `BALL_PULL_X/Z` 0.36/0.30 → 0.55/0.48 | 0.87 | 58% | 31 | 3 |
| support angle, chosen by open lane | 0.87 | 65% | 46 | 7 |
| support angle, chosen by `_value_of` | 1.00 | 55% | 45 | 8 |
| support angle, forbidden to drop deeper | 1.00 | 62% | 52 | 7 |

Two of those rows are worth their detail, because they are the first things anyone
would try and one of them looks like a clear win until you count the chances.
Raising `SimOffBall.QUOTA` from `[0, 1, 2, 2]` to `[0, 3, 3, 2]` let three men come
short instead of one: retention went 52% to 64%, but teammates inside fifteen
metres moved only 1.83 to 1.90 and goals went 10 to 9. **The quota is not what
limits support** — the offers were never being refused for lack of permission; they
came short into blocked lanes. Raising `SimMovement.BALL_PULL_X/Z` slid the whole
shape harder toward the ball: proximity rose to 2.0 and passes threaded past a
defender fell from 18% to 15%, completing at 57% rather than 39% — **and it halved
the attack**, shots 65 to 31, goals 10 to 3. Pulling the team toward the ball takes
away the width and depth that make a chance.

Five ideas do not fail the same way by coincidence. The sum of where the players
are is conserved: a man made available to receive is a man not stretching the
defence, and with ten outfielders against a defence already strong for the
attacking mechanics that exist, support cannot be bought except out of threat.
**The answer is not in positioning at all.** The mechanics that create retention
*without* spending a body are the individual ones `PLAN.md` lists and the engine
does not have: shielding, drawing a foul, and beating a man. That is where this
should go next.

## The keeper's one-on-one

`SimKeeper._one_on_one` is deliberately rare: measured across three seeds it fires
nought to one time in ten minutes, which is a keeper reading danger rather than a
keeper who thinks every attack is a breakaway. It is priced straight into
`expected_goals`, which counts him as a body in the shooting line, so when it does
fire the engine's answer is to not shoot — and the mechanics that would answer
*that* do not exist yet: the chip, the ball round him, the square pass across the
face of an empty goal.

## The size of a touch

From the owner watching: the ball was being pushed too far in front of the man
moving it. Nothing anywhere sized a touch against the *pace of the man playing it*,
though `SimTouch.dribble` had claimed to since it was written — the size came off
the candidate's own score, a composite every term of which is high for the
direction the softmax is about to pick. Measured on seed 7, a carry pushed the ball
3.4 m in front of a carrier travelling at about 2.9 m/s, so the ball left his foot
at 5.3 and he then had to sprint onto his own touch. `SimDecision.stride_room` is
the fix and it is a rate rather than a size — a touch is about half a second of his
own running ahead — so the man at full pace pushes it four metres and the same man
shifting it inside his own body length keeps it under his sole, from one rule.

Its other half is in `SimMovement._carry_pace`, and it is a loop rather than a
mistake. A carrier is chase-primary for his own touch, so he is paced at the speed
that just reaches it; the touch is then sized off that pace; a jogger therefore
takes a jogger's touch, which keeps him jogging. Nothing in it is wrong locally and
between them they pinned a man with the whole half in front of him to about three
metres a second. The pace has to come from somewhere that is not the ball, and the
honest somewhere is the grass. The knock past a man was freed at the same time: it
required a challenger, which left a hole exactly where the behaviour is most
watchable — a man running into an empty half has nobody near enough to *be* the
challenger.

Measured across seeds 3, 7 and 11 at ten minutes: the ball runs 2.3-2.45 m between
consecutive dribble touches against 3.3 m before, a carry outside the box pushes it
2.4 m against 3.4 m, and inside the box 2.0-2.9 m against 2.7 m. Balls put out of
play fell from 39 to 24-26. Interceptions rose, 77 to 84-98, and that is a rate
being read as a count: there are half as many metres in a touch and about 50% more
touches, so more of them are contested.

One thing was built for this, measured, and taken out again, because it is the
obvious idea. A dribble is a pass to yourself, so the touch should be priced the
way `_lane_survival` prices a pass: try the sizes from the top and take the largest
he beats every opponent to. It changed nothing — the mean carry under challenge
moved 2.09 to 1.98 on one seed and 1.96 to 2.17 on the other, with interceptions
and balls out of play flat. **Selection is why, and it will keep being why**: a
direction with a defender standing in it is one `_escape_value` and `control_at`
have already priced out of the softmax, so a test applied per direction only ever
prunes touches nobody was going to play. The blunt pressure shrink in
`SimTouch.dribble` survived it and still produces the gradient the sharp one could
not — free 2.03 m, closed down 1.93 m, challenged 1.79 m, in both seeds.

## The first touch, and the turn

From the same place: a pass received ends up behind the man, who turns in a small
circle and loses it. Three separate things, and the first two were defects.

The angle term in `first_touch`'s difficulty had its sign the wrong way round, and
it was worth more than everything else in the function put together: `-incoming`
points back up the ball's path, so dotting it against where the receiver wants to
go scored the *easiest* touch in football — a ball rolled into his path that he
carries on with — at the maximum penalty, and turning it back where it came from at
nothing. Second, difficulty was *subtracted* from skill rather than discounting it,
and `first_touch * technique` for an ordinary footballer is about 0.44 against a
subtraction of 0.55 of the difficulty. Between them, `quality` came out at 0.02 to
0.10 for every first touch in the match: both attributes were dead weight and every
player took the ball down like the worst man on the pitch, keeping 55% of the pace
and chasing it. This is model disagreement in its clearest form —
`SimDecision._shortlist` prices the same man's control of the same ball at
`lerpf(0.72, 0.99, first_touch)` when deciding whether to pass to him.

Third, a first touch was a brake and never a redirection, so whatever pace survived
did so along the ball's own line; and the intent handed down is `_safe_direction`,
which points at the goal, so a man receiving a ball played back to him attempted a
180-degree turn on a ball travelling at ten metres a second and failed it. He takes
it on the half-turn now, the turn limited by his touch the way `locomote` limits a
body, and the rest with his second touch.

The small circle was real, was not a receiving bug, and took three attempts.
`SimPlayer.locomote` floored the speed a player could carry through a hairpin at
0.3 of top pace; lowering that floor barely moved it — a reversal from 7 m/s swung
the man 3.65 m sideways at 0.08 against 4.49 m at 0.3, so the floor was never what
he was sitting on. Capping the turn rate by the lateral grip it needs (`v * omega`
at 7 m/s and the agility turn rate is 18 m/s², nearly two g) made it **worse**,
7.90 m: a correct constraint layered on a controller that was already wrong.

What the tick-by-tick trace showed, and nothing else could have: he braked from
6.8 m/s to 3.5 and then **started accelerating again thirty-five degrees into the
turn**, finishing the remaining hundred and forty-five at a rising speed. The
ceiling was a function of the angle *still owed*, and `severity²` hands the speed
budget back almost as soon as the turn starts. Since grip fixes the radius at
`v²/g`, a turn made at rising speed is the definition of an arc opening into a
circle.

The constraint that works is not an angle. An arc of radius R through the angle he
owes carries him `R(1 - cos θ)` off his line, so the speed that keeps that inside a
budget is `sqrt(g * L / (1 - cos θ))` — `TURN_SWING` is that budget. It asks
nothing of a twenty-degree correction and holds a full turn-round near two metres a
second however fast he arrived. Beside it, `TURN_COMMIT`: he may shed speed at any
point but may not *add* it while still more than sixty degrees off, because driving
out of a turn you have not made is the thing that drew the circle. It needs its
`TURN_PIVOT` guard — see `docs/PITFALLS.md`.

Measured across the same three seeds: first touches that left the ball behind the
man went from 26% to 17-28%, into his stride from 44% to 45-56%, and `quality` from
0.02-0.10 to 0.25-0.27 on the ball taken forward. Reversing from 7 m/s swings a man
1.81 m sideways against 3.65 m, and from 5 m/s 1.39 m against 2.81 m. Mean speed
over the match is 2.25-2.32 m/s against 2.26-2.51 m/s, which is the price of turns
costing something and is the intended direction.

The ball still comes off a first touch at about 4 m/s, which is a heavy touch by
any standard and is the next thing to look at here — `residual` runs 0.55 down to
0.06 and an ordinary touch is still landing near the top of it.

## Carriers running off the pitch

Two causes, one of them self-inflicted by the touch-size work: the probe distance
was sized off the touch, and `_room_ahead`'s inversion of the roll distance was
broken. Both are in `docs/PITFALLS.md`. Nothing in the report could see either,
which is why `How the ball changes hands` now splits the balls that go out by the
touch that put them there. That is what found the burst: **the dribble touches that
ended in a restart were played 16.6 m inside the nearest line at 10.7 m/s** —
nowhere near the paint and far too hard to be a carry.

Measured across seeds 3, 7 and 11 at ten minutes: balls out of play 21-24 against
39 at the start of this work and 27-31 before the inversion was fixed; the ones a
dribble put there 8-10 against 12-15; and of those, 0-2 are now the knock past a
man rather than most of them. The knock is offered about half as often as it was —
5-6% of touches when closed down against 12%, 12-15% when challenged against 23% —
because a great many of the ones being played had nowhere to go. The touch column
keeps its gradient throughout: free 2.07-2.14 m, closed down 1.98-2.04, challenged
1.69-1.85.

## The hold that was a carry

The complaint was that the man on the ball runs into opponents and over the
touchline. It was neither of the things it looked like. `SimDecision._execute` had
no `Action.HOLD` case, so a hold fell through the match statement and was played as
`SimTouch.dribble(dir, 0.15)` — a 2.2 m knock, in a direction chosen by
`_safe_direction` and scored by nothing. Hooking the softmax on seed 7: **68% of on-
ball decisions are holds, and 403 of the match's 527 carry touches came out of that
branch rather than out of the eight scored probes.** One every 0.47 s, 2.08 m at a
time — which is the `dribble rhythm` line, and had been all along.

The candidate says the opposite of what the execution does. `_add_hold` reads its
gain and its loss at the player's own feet and calls itself "safe but goes nowhere";
it then covered ground at 4.5 m/s. And nothing on that path asks what is in front
of him, where the touchline is, or how near goal he is, because `carry_room`,
`_in_play_odds` and `close_control` all live in `_add_dribbles`.

Split by which path played them, on seed 7: holds were three times as likely as a
scored dribble to be knocked into a body four to fifteen metres up the lane — 28%
against 10% — and that band lost the ball inside two seconds about 45% of the time
against 15% for a clear lane. Every carry that went out of play beside a line was a
hold; the scored probes produced none. Across seeds 3, 7 and 11 the carry was 43%,
49% and 51% of every turnover in the match, about a second after the touch — far
and away the largest single way the ball changed hands.

So the hold is now a hold: `HOLD_AHEAD`, which is `SimTouch.DRIBBLE_AHEAD_FLOOR`,
capped again by `carry_room`, in a direction that has to have the grass for it
(`_hold_fits`) and has to be clear of whoever is standing in it (`_hold_obstacle`).
That last one replaces "the nearest opponent inside four metres" — too short, since
`CHALLENGE_SIGHT` is 5.5 m, and the wrong shape, since it moved the touch for a
marker three metres *behind* the carrier and not for a defender six metres dead in
front of him. How far down the lane to look is not a constant: it is
`carry_travel` plus the old radius, so a standing player looks about five metres
and a man at full pace about ten, from one rule rather than two.

Measured across seeds 3, 7 and 11 at ten minutes, before against after:

- **Carrying it over a line is gone.** 496 carries were played within 11 m of a
  line and **one** of them went out inside three seconds. The near-line touches are
  now struck at 2.2-4.0 m/s where they were struck at 5.1-7.5. The carries that
  still go out are played 14.8-20.5 m inside the nearest line at 9.2-10.3 m/s —
  aim error on long knocks, which is the priced-not-forbidden case, not a man
  walking it over the paint.
- Balls a dribble put out of play 19 against 28; over a touchline 16 against 21.
- Turnovers 332 against 360, clean interceptions 250 against 281.
- Carries with nobody in the lane 61-64% against 55-58%, losing 12-16% of the time.
  The engine still carries into people — but those are scored dribbles now, priced
  against the alternatives, which is the design.
- **Territory went up, not down.** Touches in the final third 20-23% against
  13-22%, up on all three seeds; touches in the box 89 against 57. Losing the ball
  28 fewer times in half an hour is worth more than the metre a touch of unearned
  ground it replaced.
- Shots 53 against 53 — 13/22/18 against 24/19/10. The per-seed swing is large and
  the total is flat; three seeds is not enough to say more than that.
- The retreat `_safe_direction` was written to stop did not come back: spells
  losing 8 m or more are 4 against 4.

What to watch, because it is a look-and-feel question and not a number: the carry
is now more touches of a smaller size. Dribble touches rose (627 against 527 on
seed 7) and the rhythm tightened to 0.38 s from 0.47 s, which is on the fast side
of a real carry and wants an eye on it. A man *shielding* the ball touches it far
less often than one running with it, and the engine does not yet tell those apart.
