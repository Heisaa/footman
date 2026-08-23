# The people

Who the footballers are, what they are called, and what the club believes about
them. `world/` owns all of it. `PLAN.md` §8 is the data model and §9.7 is the
register; this file says what was built and why it is shaped that way.

Nothing here is simulation. `world/` reads `sim/` — attributes, roles,
formations, the RNG — and `sim/` does not read `world/`. Nothing depends on
`presentation/`, so the identity layer runs headless like everything else.

## What a man is

`WorldPlayer` is the whole §8 record: identity, football, condition, standing,
contract, and what the club knows. `SimPlayer` is the same man for ninety
minutes and knows about none of it — `to_sim_player` hands the match the true
attributes, a name and an appearance seed, and the match hands nothing back.

The record is the authority. After the whistle the world writes to itself from
the telemetry; the match never writes to the world.

## Names

British, 1985 to 1995, because that is the register. The four home nations have
their own surname pools — a McQuade reads Scottish before you are told, a
Prosser Welsh — and the club's own nation takes about three quarters of its
squad. One player in twelve is foreign, which is the period being accurate
rather than the game being narrow; he carries his own country's code.

No famous names. Every surname is a real British surname and none of them
belonged to a footballer anybody remembers: a generated Dalglish reads as a bug.

**A squad has no two of anything.** Two Bloomfields, two Kevs, six Albions in a
division of twelve — each of those was in the first printed output and each is
fixed by carrying a small set of what has been used already. The name is
redrawn and nothing else is: the man was settled before he was named.

## Epithets, and who gets one

"Hot-Shot" Hamish is the specification. An epithet is only worth anything if it
is **true**, so `WorldNickname.archetype` derives it from the numbers — what the
sim will actually do with this man — and the pool supplies only the wording.
Ten archetypes, tested in the order a crowd would notice them: the freak shot,
the size, the speed, the head, the tackle, the keeper, the temper, the age, and
the man who is hopeless at the thing his shirt is for.

**Most players do not get one.** An epithet everybody has is a surname. The rest
have a terrace shortening — Gazza, Cheesy, Wetto — which is what the crowd calls
a man who has not earned better. The irregular ones are written down rather than
generated, because generating them produced "Briao" and "Keny".

## One or two tails in a squad

`WorldGen` picks one or two men per squad before anybody is drawn and builds
them to be describable in four words: raised where the archetype names them,
lowered somewhere else, because a tail is *uneven* rather than merely better.
Everybody else is a plausible pro. A squad where everybody is remarkable has
nobody remarkable in it.

The club's reputation moves the **mean** and nothing else. A better club has
better players from the same distribution; it does not get more freaks and a
bottom-division side is not denied one. The giant at the small club is the
premise of the whole register.

Order matters: the age curve runs **before** the tail is forced. The other way
round, a thirty-three-year-old whippet had his forced pace multiplied back down
by the curve and stopped being a whippet, and roughly one seed in twelve
produced a squad with nobody in it worth describing.

## Traits

Two or three things that are true about a man besides his numbers, drawn against
his attributes rather than at random: an aggressive number makes `hothead`
likely and `ice` impossible. Most men have one; three is a character.

**Nothing in `sim/` reads a trait today.** Each entry carries a `sim_note` saying
what it is meant to do when traits are wired, so that pass is a reading job
rather than a design job.

Two things stop a squad being one deck shuffled eighteen times: a rarity weight
per trait, and a running tally of what the squad already has — each man who has
a trait halves the next man's chance of it. Without them the first squad printed
had six players made of glass and five superstitious ones.

## What the club knows

`attrs` is the truth and never moves. `known` is a per-attribute estimate and a
confidence, and it is what every screen reads (`PLAN.md` §6.1: the player never
sees a number). `observe` moves an estimate toward a *noisy sample* of the truth
and raises the confidence — which is why a scout can be wrong about a player
rather than merely vague.

Team selection reads the belief, not the truth. `best_eleven` fills each
formation slot with the best believed man for it, discounting anybody out of
position, so picking a side is a decision made on incomplete information — which
is the point.

`WorldScout` turns a belief into English: eight bands of adjective, a phrase per
attribute, the traits in the scout's own words, and a closing line about how
much of it the club would stand behind. Flat voice, no winking.

## The season

`WorldSeason` is the fixture list, the results and the table: a double
round-robin by the circle method, everybody home and away, a bye slot when the
club count is odd. Three points for a win, goal difference then goals scored.

**It decides nothing.** The player's own fixture is simulated by `sim/`; the rest
of the division is the abstract model of `PLAN.md` §2.5, which is a later pass.
This is what both write into.

## Looking at it

    ./run.sh world --seed 3            one club: squad, tails, scout reports
    ./run.sh world --clubs 12          a division and its first week

No match runs, so it is instant. A squad is judged the way the match is judged —
by looking at it — and twenty names read aloud say more about the register than
any number could. `tests/test_world.gd` asserts the machinery underneath:
which pool a surname came from, that a forced tail reaches the tail, that a
belief moves toward the truth, that everybody plays everybody twice.

## Loose ends

- **Height is on the record but not on the model.** `presentation/` still builds
  the figure from `appearance_seed` alone, so a generated giant is a giant in his
  attributes and not yet in the picture. `WorldGen.player` takes an optional
  `body_oracle` — a callable mapping a seed to that seed's height — and samples
  seeds against it; `world/` must not depend on `presentation/`, so the caller
  supplies it. Passing `SimAppearance.from_seed(s).height` from the presentation
  side is the whole of the wiring.
- **`sim/` reads neither height nor traits.** A giant wins nothing in the air
  today that his `jumping` and `strength` do not already win.
- **`SimSquadGen` still exists** and still generates its own invented names for
  tests and batch runs. It is not wired to `world/`, and the two are free to
  disagree until something needs them not to.
