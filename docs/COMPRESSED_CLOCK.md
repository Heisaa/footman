# The compressed clock

`--clock-rate R` runs the match clock R times faster than the simulation, so a
full ninety minutes is played out in `90/R` minutes of football with the
scoreboard still reading 0-90. It is read in one place — `SimMatch._advance_clock`
— and nothing else in the sim knows it exists. **It is not a speed multiplier.**
Players run at the same metres per second, the ball obeys the same drag, the tick
is still a sixtieth; a compressed match is a *shorter* match wearing a
ninety-minute clock, and it holds proportionally fewer events. `DECISIONS.md`,
sixth amendment, has why this direction was chosen over highlights.

Do not confuse it with `--minutes`. `--minutes 10` plays the first ten minutes and
stops, which samples a rate. `--clock-rate 30` plays all ninety, kick-off to full
time, which changes what a match *is*. Both together bound a window inside a
compressed match, which is how a compressed run gets measured without a
full-length one.

**The 3D view defaults to the compressed match and nothing else does.**
`match_view_3d.gd` opens at `clock_rate = 30`, eleven a side on a **regulation
pitch** — a full ninety in about three minutes, because that scene exists to be
watched. The sim, the headless runner, every batch and the test suite still
default to an uncompressed clock, so the §11 bands and the golden digests are
measuring the same engine they always measured. Pass `--clock-rate 1` to the view
to watch in real time.

## What scales with it

Three things, and nothing else. Fatigue, in `SimPlayer._update_stamina` and
`spend_action`, because "nothing left after eighty minutes" is a fact about a
match and not about a body. The deliberate part of a restart, in
`SimSetPiece._compress`, because dead time is priced in real seconds while the
match budget is not — floored, though, since part of every restart is players
physically going somewhere. And the repositioning pace in `SimSetPiece.update`,
which is what pays for the shorter window. Everything else — acceleration, turn
rate, ball drag, the tick — must never know.

## Where the football per second has to come from

The retuning this implies is the owner's stated price for it, and the lever is
**space, not speed**: a smaller pitch raises events per second while every
quantity the eye is calibrated to stays where it was, and a faster world does not.
`--pitch-scale F` is that lever, eleven a side kept, and it goes through
`SimPitch.scaled`.

**Shrinking the pitch buys shots, not expected goals, and the difference is the
whole problem.** Measured across three seeds at ten minutes: at `--pitch-scale
0.65` shots went from 45 to 113 while total expected goals went only from 6.8 to
10.0, because the extra shots are marginal ones that clear the generation
threshold on a shorter pitch and nothing else. Squeezing the pitch converts chance
quality into chance quantity. It does not create expected goals, and a compressed
match needs the thing itself.

The pitch stays full size by the owner's call, having looked at a shrunk one. Of
the two places a compressed match could get its football per second from, space is
closed and **chance quality is the one left**. A three-minute match on a
regulation pitch currently holds about 0.68 expected goals, and converts at
roughly a third of that, so it will finish goalless far more often than it should.
That gap is the work, and `--pitch-scale F` remains available for measuring
against.

Judge a change to scoring per second of football, not per ninety: the §11 bands
describe an uncompressed game nobody will play.
