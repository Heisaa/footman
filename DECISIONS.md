# Decisions

Owner calls. Three sections: open `[DECIDE]` questions with the default in force,
amendments to `PLAN.md`, and where the implementation deviates from it on purpose.

The amendments are already applied to `PLAN.md` — this is the record of what
changed and why, not a second copy of the spec.

## Open questions

`PLAN.md` §12 marks these for the owner rather than silent resolution. Each has a
default so the build could continue, and none is baked in anywhere expensive.

| # | Question | Default in force | Where it lives |
|---|---|---|---|
| 1 | Squad size for the prototype phases | **Eleven-a-side throughout.** Six-a-side is supported (`--small`) and stays useful as a fast behaviour check, but the §11 bands are all specified for eleven | `SimRunner.Options.small_sided` |
| 2 | Whether your own players' attributes become fully known | **Converge to a narrow band, never to a number.** The single biggest lever against optimisation-brain | Phase 8 — not built |
| 3 | Run length: one season or up to three | **Up to three, escalating** | Phase 10 — not built |
| 4 | Whether the player can watch at 1x at all | **Both, punctuated by default.** The 1x path costs 1.5% of a frame, so there is no performance reason to withhold it | `presentation/match_view_2d.gd` |
| 5 | Injury model depth | **Not decided.** The sim tracks fatigue and a `recovery_ticks` knock-down, so either model can be built on what exists | Phase 9 |
| 6 | Whether tactical patterns are per-run unlocks or persistent progression | **Not decided.** `SimPattern` is data-driven and lives on the plan, so it can be granted from either layer | `sim/pattern.gd` |

## Amendments to the plan

**First and second: validate for speed, tune late.** The plan asked for two
hundred matches everywhere, which is five and a half hours serially, so nothing
was ever run. §11 became two layers — wide **sanity ranges** that catch structural
breakage, and the **tuning targets**, reported but advisory — and the batch sizes
were re-cut to smoke / gate / acceptance. Counts are normalised per 90 minutes, so
a short match is a legitimate measurement of a rate. §11.1.1, the **tuning
freeze**, was added: the tuning table becomes pass/fail at the end of Phase 8, not
before. Phase 4's exit criterion is the sanity ranges plus the measured cost.

**Third: rolling resistance, and wetness separated from grass length.** The owner
noticed a slow ball rolling too long. Dry resistance went to 1.0 m/s², and long
grass and wet grass were separated — they had shared one constant, so a wet pitch
*slowed* the ball. A greasy surface makes it run on; only the grass kills it. The
pass solver reads the same constant, so passing did not need re-tuning; what moved
is loose-ball behaviour.

**Fourth: entertainment is the target, realism is the texture.** The whole tuning
table is an entertainment target, and the sanity ranges are the floor that keeps
it recognisably football. Stated so that "that isn't what real football does"
stops being an argument on its own.

**Fifth: the register is the British football comic.** *Hot-Shot Hamish* and
*Mighty Mouse*, and eighties/nineties British football, as the register for
characters, naming, body language and copy (§9.7). It governs nothing in `sim/`:
a keeper carried into the net is an animation and a line in the log over a goal
the engine scored normally.

**Sixth: the match clock is compressed, so a full match is watchable.** A ninety
minute match at 1x took ninety minutes, so nobody watched one. Amended twice on
2026-08-14: the standard match is **nine minutes** (`clock_rate` 10), and that is
the default **everywhere** — sim, runner, batches, `diagnose`, the suite, the view
— because real-time games will never be run and the instruments should measure the
match the player gets. The urgency anchor stays at 30, so the standard match runs
the scoring fit at about 0.68 strength; the five fitted constants get refit at the
freeze. `--clock-rate 1` remains the affordance for asking what the football does
without the fit, guarded by `test_clock`. Goldens are baselined at 10x.

**The pitch stays full size**, and that is the owner's call having looked at a
shrunk one: `--pitch-scale 0.65` took shots from 45 to 113 and total expected
goals only from 6.8 to 10.0. **Shrinking the pitch converts chance quality into
chance quantity and does not create expected goals.**

**Seventh: make it look like football, then tune.** The build started as "get a
simulation running, then tune it to realistic numbers". It is now "make it look
like football, ignore the numbers until it does, then tune" — the numbers are not
the goal at any point, but a description of whatever engine the behaviours
produce, fitted once at the end. The sanity ranges became a breakage detector
rather than a judgement on a change; a proposal is ordered by whether it makes the
match read as football, never by which way it moves goals per match.

**Eighth: build the attack until it overshoots, then build the defence**
(2026-08-15). Attacking behaviour has been going in against a defence missing
blocks, jockeying, cover, a box that resists and an offside trap. Balancing goals
in that state fits the attack to the absence of the defence — §11.1.1's argument
applied to a whole layer instead of a constant. So the attack is built out until
it clearly overshoots, the defensive pass follows, and the numbers meet
afterwards. `PLAN.md` §11.4 is the statement of it. The goals sanity ceiling is
**suspended for the duration** — 16 stands in for 8 as a breakage wire, and
`tools/validation.gd` keeps the settled value beside it so restoring it after the
defensive pass is one line. No tuning band was rewritten and nothing in `sim/`
changed.

## Design calls made during the build

**Waiting is a first-class option: an unpressured man is not rushed** (2026-08-14,
after the owner watched real football against the engine). Players need time to
orient, decide, then act, and keeping the ball a beat with no pressure on is
normal football. `scan_gain` is the dwell, `FREE_WAIT_COST` runs the wait discount
at a quarter rate for a free man, and `_apply_set_damp` is the beat. The guard all
three keep: a closed-down man still releases at once, and waiting stays a losing
game in itself.

**Width in build-up: hold the structure, and the far man is a real option**
(2026-08-14). The owner watched the defence and midfield collapse onto the
carrier, closing every lane. The direction is the reverse of five earlier failed
experiments, which pulled support *in*; this holds the shape *out*.
`BALL_PULL_Z_BUILD`, `BUILD_UP_WIDTH_MID`, a man showing into a blocked lane
stepping off it, and `_switch_lift` guaranteeing the widest free man a shortlist
slot with the anti-hoof prior refunded for a genuine switch.

**Goals and draws are stated against a different reference from the rest of the
table.** They are set by what is fun to watch (§11.3); everything else is stated
against the sport. The band comments in `tools/validation.gd` say which is which.

**Animation is smooth, not stepped.** §10 Phase 6 asked for stepped animation and
the owner asked for smooth after watching it. `--step-fps 10` keeps the old look
available, because the two are a judgement the owner may want to make again.

**The run cycle lifts the knee and the foot.** The old one slid the feet forward
along the ground: hips swung, the knee bent a little on the wrong half of the
cycle, and nothing ever left the grass. Each leg now has an ankle pivot and the
cycle drives three joints against the hip's pendulum, with the body riding up
between footfalls and sinking over the planted foot.

**Three cameras, and they pan** (§9.2 amended). Twenty-one authored positions
cutting to whichever sat nearest the ball meant a ball played twenty metres
sideways changed the shot, and the viewer spent the match re-finding play. All
three now stand off the *same* touchline — reversing the side would reverse the
direction of play, the one thing a viewer cannot re-learn mid-match. The elevation
is no longer fixed and neither is the field of view, which is solved each frame to
hold a fixed frame width. Three numbers hold the cutting down, and the one that
did the work is a **commitment delay**: play has to stay in the new camera's
territory before the cut is taken, so a ball cleared straight back out is covered
by the pan and costs nothing.

## Deviations from the plan

**The ball has a drag crisis, which §3.1 said to ignore.** A football's boundary
layer goes turbulent around 12-15 m/s and the coefficient falls from about 0.45 to
about 0.2. A single number in the middle gets both ends wrong in the direction that
reads worst: it over-drags the shot and under-drags the floated ball.

**Stamina drain is scaled by the stamina attribute, not work rate**, which §3.2
specifies. Reading work rate as *how much a player chooses to run* and stamina as
*how well he copes* makes both do something. A one-line change if the intent was
literal.

**Set pieces snap players into position for kickoffs and penalties only.**
Everywhere else they jog in simulated time, which is what §3.5 describes.

**Chasers approach a carrier at an angle**, which §4.3 leaves implicit — and the
implicit answer, a straight line, is a tailgate. `SimMovement._recovery_point` aims
*beside* the ball, never in front of the carrier, and carries a pace allowance
because the way round is longer than the way through. The consequence is that a
carry can be ended by a defender who started behind, which is what §3.3 wanted.

**Body orientation costs accuracy on every touch that is aimed**, not only the
pass — the dribble touch and the first touch too, because the reason a pass is
harder is not a fact about passing. The shot, header, clearance and poke are left
out on purpose. Two properties are load-bearing: the penalty is charged through
`aim_sigma`, so the decision layer pays for it and a player *chooses* the option he
can see; and a man standing still pays a fixed share (`FACING_STATIC_SHARE`),
because the engine has no notion of taking a moment to turn.

**Phase ordering was compressed at the module level.** Keeper, referee and set
pieces were written earlier than §10 places them, because the match loop cannot run
without them. The *validation* order was kept.

**The compressed match is fitted to a scoreline; the real-time match is not.**
Owner's call, taken against the default ordering in `CLAUDE.md` and with the
arithmetic in front of them: a nine-minute match holds 540 seconds of football, so
a steady scoreline needs about 27 goals per ninety of play. Nothing that reads as
football produces that. So the compression carries the fit —
`SimMatchConfig.urgency` and the five constants that read it tune the *format*,
not the football, and they are no-ops at `clock_rate` 1. What it costs, stated
plainly: the compressed match converts about a quarter of its shots and puts four
fifths on target, against football's tenth and third. **Anything measured at the
default clock is a measurement of the format**; `--clock-rate 1` is the honest way
to ask what the football is doing.
