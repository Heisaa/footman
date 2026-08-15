# The football, and how much of it exists

Every behaviour a viewer can see, and whether the engine has it. One line each.

This is the list to read before watching a match. It exists so that an absence
can be recognised as an absence: a cross nobody attacks is not a bug in crossing,
it is a missing aerial layer, and knowing which of the two you are looking at is
most of the value of watching at all.

It is not the spec — `PLAN.md` §3-5 is, in engine terms. It is not the account of
what each mechanic cost — `docs/STATUS.md` is that. It is not the proposal list —
`docs/BACKLOG.md` is, and it holds only what somebody has already thought through.
This is the index across all three, from the viewer's side of the screen.

**built** — the engine does it. **partial** — something of it is there and the
rest is named in the row. **absent** — a footballer does it and this engine does
not. Checked against the code, not against the plan.

When one is built, move the row and put the account in `docs/STATUS.md`.

## With the ball at his feet

| Behaviour | | Where |
|---|---|---|
| Pass to feet | built | `SimDecision._add_passes` |
| Firm pass driven low, not rolled — skims, spins, sits down | partial — the ball does it and the model prices it as a roller; a driven ball the score treats differently is `docs/BACKLOG.md` 26 | `SimBallistics.ground_launch`, `SimTouch.ground_pass` |
| Through ball in behind | built | `_add_passes` |
| Lofted pass, cross | partial — aimed where he is going, still weighted to land on him rather than short and roll on (`docs/BACKLOG.md` 23) | `_add_passes` |
| Shot, with a chosen placement | built | `_add_shot`, `_pick_shot_aim` |
| Clearance | built | `_add_clear` |
| Carry, eight probed directions | built | `_add_dribbles` |
| Knock past a man, and race him | built | `_add_dribbles`, the burst |
| Hold — the settling touch | built | `_add_hold`, `_play_hold` |
| The dwell — a free man keeps it a beat while he takes another look, then plays | built | `SimDecision.scan_gain`, priced into `_hold_score`; the look is `SimPerception`'s staleness |
| Orient before the act — a beat between coming by the ball and striking it, pre-paid by the flight he watched | built | `SimDecision.readiness`, `_apply_set_damp`; a long ball can still be played first-time |
| First touch, and the turn | built | `SimTouch.first_touch` |
| The layoff — first-time ball back to the man facing play | built | `SimTouch.redirect_share` prices the redirect, `SimDecision._add_passes` eases `off_balance` for the helped-back ball |
| A setting touch out of the feet before the long ball or the shot | built | `SimDecision._add_set_touch`, a candidate that buys the deferred strike |
| Receive on the half-turn — the touch chosen before the ball arrives | built | `SimMovement._orient_receiver` opens the hips while the ball travels; `first_touch` already limits the turn |
| Body facing priced into the strike | built | `SimTouch.facing_penalty` for the aim, `strike_scale` for the range |
| Turn before you can hit it | built | a ball played behind the body has a fraction of the range, so the long one has to be turned onto |
| Give-and-go | partial | the passer is nudged to run and the receiver prices the return ball; there is no executed one-two |
| Beating a man | partial | the knock, and the cut that wrong-foots a committed challenger (`SimDecision._try_beat`) — still no feint at a standstill, no change of pace |
| Shielding the ball | built | `SimDecision._play_hold` sets it, the hold prices it, `SimDuel` weighs it |
| Drawing a foul | partial | the duel now fouls the skilful or shielding carrier more (`SimDuel`), and a beaten man sometimes chops (`_try_beat`); nobody invites contact on purpose |
| Backheel, dummy, first-time pass | built | first-time exists for every pass kind (`SimTouch.FIRST_TIME_EASY`); the dummy is `SimDecision._add_dummy`; the backheel is the first-time ball behind, priced by the same facing model |
| Chip the keeper, round him, square it across the face | built | `SimDecision._add_chip`, `_round_the_keeper`, and the square ball's `SQUARE_CONVERT` gain |

## Without it, attacking

| Behaviour | | Where |
|---|---|---|
| Come and meet it | built | `SimOffBall` SHOW |
| Move into space | built | `SimOffBall` SPACE |
| Run in behind | built | `SimOffBall` BEHIND |
| Stay onside | built | `SimReferee.believed_offside_line` |
| Hold shape, slide with play | built | `SimMovement.shape_position` |
| Split the back line to build out | built | `SimMovement._build_up_width` |
| Overlap, underlap, third man, switch of play | built | `SimPatterns`, as named patterns |
| Break on the counter | built | `SimDecision.break_on` prices the ball forward, `SimOffBall` sends the runners, both off the same measurement |
| Attack a cross — near post, far post, the pull-back | partial | `SimMovement` sends `AERIAL_CHASERS` men at a ball in the air instead of the one the possession cap allows, and they go at the ball; the near post and the far post are not authored positions |
| Check away and come back | built | `SimOffBall._commit`: a marked show runs its first beat the wrong way |
| Arrive as the ball does — easing the last metres, not standing at the spot | partial | a box runner holds short until the cross is up, a runner in behind checks back onside instead of standing beyond the line (`SimOffBall.point_for`); shows and drifts still stop on their spot |
| Drop into the pocket between the lines | built | `SimOffBall._pocket_point`, a probe aimed at the opponents' shape |
| Decoy run — going where the ball will not | built | `SimOffBall._decoy_point`; not offered to the passer, worth the marker it drags |
| Anticipate the second ball | built | `SimOffBall._second_ball_point`, under the drop of a contested high ball |

## Defending

| Behaviour | | Where |
|---|---|---|
| Who leaves shape for the ball, and how many | built | `SimMovement._assign_chasers`, the anti-swarm guard |
| Press harder or sit deeper, from the plan | built | `SimTactics` pressing |
| Mark a man | built | `SimPlayer.marking_target` |
| Recovery run | built | `SimMovement`, recovery |
| Intercept a pass | built | `SimDuel` |
| Tackle, poke it away | built | `SimDuel`, `SimTouch.poke` |
| Hold a defensive line, with offside off it | built | `SimReferee.offside_line` |
| Clear under pressure | built | `_add_clear` |
| Block a shot | partial | a defender already in the path can take the ball, and bodies in the line lower the chance; nobody throws himself in the way (`docs/BACKLOG.md` 5) |
| Cover a beaten teammate | partial | a beaten defender is penalised in the chase ranking; nobody covers the space he lost |
| Jockey, delay, show him wide | absent | a defender either goes for it or holds station |
| Escort a dying ball over the line, body between it and the attacker | absent | shielding's cheapest special case, and instantly recognisable |
| Spring an offside trap | absent | the line exists; stepping up as an act does not |
| The deliberate foul | absent | |
| Defend the penalty area | absent | the largest single hole an eye will find — `docs/BACKLOG.md` orders it first |

## In the air

It was the emptiest part of the engine. `sim/aerial.gd` is the layer, and
`docs/STATUS.md` has the account.

| Behaviour | | Where |
|---|---|---|
| Height decides who can play the ball | built | `SimTouch.playable_height` |
| Head it — clear, shoot, flick on | built | `SimAerial.play`, all three of them |
| Take it down on the chest, and play it off the deck | built | `SimTouch.chest`, chosen by `SimAerial._play_off_the_body` |
| Let a dropping ball come to you rather than head it | built | `SimAerial.lets_it_drop`, asked before he is a contender |
| Jump for it, and contest it in the air | built | the same `SimDuel` contest, weighted by `SimAerial.duel_skill` |
| Win a knock-down, attack a corner | partial | the knock-down is `SimAerial._header_target`; a corner is still whatever the box happens to do with it |
| Volley it, on purpose | partial | inside 18 m with a chance on, `SimAerial` hands the ball back to `SimDecision` and it is struck as an ordinary shot; there is no volley model |

Three heights, and they are what the layer is. Below
`SimConsts.FOOT_REACH_HEIGHT` it is a ball on the floor and the ordinary decision
has it. Above `SimAerial.HEADER_FROM` — his shoulders — it is a header. Between
them he has a chest, and `SimTouch.chest` kills the ball and puts it on the grass
in front of him, which is the commonest thing anybody does with a ball in the
air and was for a long time the one thing this engine could not do.

The fourth act is not touching it at all. A man with a dropping ball, nobody
near him and no goal in front of him lets it come down and takes it on his chest
a second later. Without that every ball off the grass was headed, whatever the
situation, and a match had a header in it every time the ball bounced.

Heading and jumping decide the aerial duel and the power on the header;
`first_touch` and `technique` decide what a chest is worth, the same two that
decide a first touch; `command` decides what the keeper comes for and whether he
holds it.

## The goalkeeper

| Behaviour | | Where |
|---|---|---|
| Shot stopping, from reach and reaction | built | `SimKeeper` |
| Dive, parry or catch | built | `SimKeeper`, `caught` in the save |
| Starting position, sweeping behind the line | built | `SimKeeper` |
| Come out and smother | built | `SimKeeper`, smother range |
| Distribution, short or long | built | `SimKeeper.decide_with_ball` |
| Where a parry goes | partial | the rebound is a loose ball nobody aims — `docs/BACKLOG.md` 3 |
| The one-on-one | partial | priced into `expected_goals`, so the engine's answer is to not shoot |
| Claim a cross, command the area | built | `SimKeeper._claim_target`, and `_try_gather` holds it or punches it |
| Narrow the angle | absent | `docs/BACKLOG.md` 5 |

## Set pieces, and the laws

| Behaviour | | Where |
|---|---|---|
| Kick-off, throw-in, goal kick, corner, free kick, penalty | built | `SimSetPiece` |
| A restart the side reorganises around | partial | positions and a delay; routines are not authored yet |
| Offside, given at the moment of the pass | built | `SimReferee` |
| Fouls and cards, and a red that removes a man | built | `SimReferee` |
| Added time from stoppages | built | `SimReferee.add_stoppage` |
| Opponents out of the area at a goal kick | built | `SimSetPiece._out_of_penalty_area`, and the kick waits for them |
| A wall at a free kick | absent | |
| Advantage | absent | `SimReferee`'s own header comment claims it; it is not in the file |
| Substitutions | absent | a telemetry event kind with nothing behind it |
| Injuries | absent | |

## The body, and the man

| Behaviour | | Where |
|---|---|---|
| Stamina, and fatigue slowing him | built | `SimPlayer` |
| Match sharpness | built | scales his speed caps |
| A wet pitch, an undulating surface | built | `SimEnv` |
| Morale | absent | it moves when a goal goes in and nothing ever reads it |
| Momentum, a side that is rattled | absent | |

## What a player knows

| Behaviour | | Where |
|---|---|---|
| Believed positions, stale and noisy | built | `SimPerception`, `ctx.beliefs` |
| A believed offside line, not the true one | built | `SimReferee.believed_offside_line` |
| Options gated by what he can perceive | absent | he is scored for passes he cannot see — `docs/BACKLOG.md` 12 |
| The scan you can see — head turned to where he is looking | partial | the sim has the looking (`SimPerception`'s refresh, and the dwell prices it); nothing in `presentation/` draws a head turn or a raised arm calling for it |

## Watching with this list

Six things this engine cannot do, and what each looks like on screen. Seeing one
is not a finding; it is the list working.

- **A cross arrives and nobody makes the run to the near or far post.** The runs
  themselves. Two men now go at a ball in the air and head it; where they go from
  is still the shape they were standing in.
- **A carrier who holds a man off or cuts past him is new** — shielding and the
  cut went in together. A carrier who still runs straight into a defender and
  loses it is now the softmax declining both, which is a tuning fact, not an
  absence.
- **A shot from twelve yards with a defender beside it goes in cleanly.** Nobody
  blocks.
- **Attacks walk into the six-yard box.** Defending the penalty area.
- **A keeper parries straight back out and it happens again immediately.** Where
  the parry goes.
- **A free kick on the edge of the box is now possible but rare.** The duel
  fouls the skilful or shielded carrier more and a beaten man sometimes chops;
  the deliberate cynical foul is still absent.

**Something wrong that is not on this list is the valuable kind.** Mark it with
`M`, because it means the engine has a behaviour and is doing it badly, which is
a different and more findable problem than not having one at all.
