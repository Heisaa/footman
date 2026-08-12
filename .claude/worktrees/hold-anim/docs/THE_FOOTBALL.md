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
| Through ball in behind | built | `_add_passes` |
| Lofted pass, cross | built | `_add_passes` |
| Shot, with a chosen placement | built | `_add_shot`, `_pick_shot_aim` |
| Clearance | built | `_add_clear` |
| Carry, eight probed directions | built | `_add_dribbles` |
| Knock past a man, and race him | built | `_add_dribbles`, the burst |
| Hold — the settling touch | built | `_add_hold`, `_play_hold` |
| First touch, and the turn | built | `SimTouch.first_touch` |
| Body facing priced into the strike | built | `SimTouch.facing_penalty` |
| Give-and-go | partial | the passer is nudged to run and the receiver prices the return ball; there is no executed one-two |
| Beating a man | partial | the knock past a man is the whole of it — no feint, no change of pace that leaves a defender |
| Shielding the ball | absent | `SimPlayer` mentions it in a comment; nothing does it, and a carry under pressure has no answer but to knock it |
| Drawing a foul | absent | fouls happen to a player, never for him |
| Backheel, dummy, first-time pass | absent | first-time is modelled for shots alone |
| Chip the keeper, round him, square it across the face | absent | `docs/BACKLOG.md`, "Answers to the keeper's one-on-one" |

## Without it, attacking

| Behaviour | | Where |
|---|---|---|
| Come and meet it | built | `SimOffBall` SHOW |
| Move into space | built | `SimOffBall` SPACE |
| Run in behind | built | `SimOffBall` BEHIND |
| Stay onside | built | `SimReferee.believed_offside_line` |
| Hold shape, slide with play | built | `SimMovement.shape_position` |
| Overlap, underlap, third man, switch of play | built | `SimPatterns`, as named patterns |
| Attack a cross — near post, far post, the pull-back | absent | nobody makes a run at a ball in the air |
| Check away and come back | absent | |
| Drop into the pocket between the lines | absent | |
| Decoy run — going where the ball will not | absent | every run is made to receive |
| Anticipate the second ball | absent | |

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
| Spring an offside trap | absent | the line exists; stepping up as an act does not |
| The deliberate foul | absent | |
| Defend the penalty area | absent | the largest single hole an eye will find — `docs/BACKLOG.md` orders it first |

## In the air

The emptiest part of the engine, and the one a viewer meets every time the ball
goes up.

| Behaviour | | Where |
|---|---|---|
| Height decides who can play the ball | built | `SimTouch.playable_height` |
| Head it — clear, shoot, flick on | absent | `SimTouch.header` is written and **nothing calls it** |
| Jump for it, and contest it in the air | absent | no aerial duel exists |
| Win a knock-down, attack a corner | absent | a corner is met on the floor or not at all |

Heading, jumping and strength are generated as attributes and priced into squad
quality. In a match they decide nothing.

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
| Claim a cross, command the area | absent | |
| Narrow the angle | absent | `docs/BACKLOG.md` 5 |

## Set pieces, and the laws

| Behaviour | | Where |
|---|---|---|
| Kick-off, throw-in, goal kick, corner, free kick, penalty | built | `SimSetPiece` |
| A restart the side reorganises around | partial | positions and a delay; routines are not authored yet |
| Offside, given at the moment of the pass | built | `SimReferee` |
| Fouls and cards, and a red that removes a man | built | `SimReferee` |
| Added time from stoppages | built | `SimReferee.add_stoppage` |
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

## Watching with this list

Six things this engine cannot do, and what each looks like on screen. Seeing one
is not a finding; it is the list working.

- **A cross arrives and nobody attacks it.** The aerial layer. Nothing to do with
  crossing.
- **A carrier runs into a defender and loses it** rather than holding him off or
  going past him. Shielding and beating a man.
- **A shot from twelve yards with a defender beside it goes in cleanly.** Nobody
  blocks.
- **Attacks walk into the six-yard box.** Defending the penalty area.
- **A keeper parries straight back out and it happens again immediately.** Where
  the parry goes.
- **A goal-scoring chance is never a free kick on the edge of the box.** Nobody
  draws a foul and nobody stops an attack cynically.

**Something wrong that is not on this list is the valuable kind.** Mark it with
`M`, because it means the engine has a behaviour and is doing it badly, which is
a different and more findable problem than not having one at all.
