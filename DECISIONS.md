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

### Eighth: smaller heads, and the register does not touch the art

Made at the owner's direction over two passes. The first pass read §9.7 as an
instruction about the *look* and put an ink outline, an eighties collar, cuffs, a
sock turnover, a moustache and comic spectacles on the figure. The owner took all
of it off again. That correction is the important half of this amendment.

| Section | Was | Now | Why |
|---|---|---|---|
| §9.3 | Head roughly 35–40 % of total height | 30–35 % | The owner asked for it smaller. It lengthens the body, which is what carries a stride, and it is still far above a real man's three-and-a-bit, so the drawn expressions stay legible at match distance. |
| §9.7 | "The register governs presentation, naming, copy and character generation" | The register governs the writing and the feel — naming, copy, the event log, what the game reports — and the generation behind them. **It does not govern the art.** | "Presentation" was read as "the models". The look is §9.3's flat-coloured toy — Sokpop, Mii, Animal Crossing — and a drawn line on it is the register leaking into the art. The comic is in the tone of voice. |

What the pass left in place, none of it touching `sim/`:

- **Generation reaches the tails.** Height was a flat 1.62–1.95; it is now a bell
  through 1.70–1.88 with a one-in-seven draw into 1.56–2.04, and build follows
  height so the giant is built like one. A flat draw is how you get eleven
  similar men.
- **The head is not a ball.** Two scale axes off the seed, so a squad has long
  faces and wide ones. Everything hanging off the head — face, hair, beard — is a
  child of it and stretches with it, which is the Mii trick and free.
- **Eyes and mouth are per-player.** Seven drawn eye shapes and seven mouths,
  independent of the five expressions, so the neutral face a man wears for almost
  the whole match is his own. Twenty-two identical pairs of dots was a clone army
  with different hair.
- **Fourteen hair styles** from a cap, a back mass, a fringe and a tuft, built
  from a hairline rather than a scale — a cap whose lower edge crosses the drawn
  eyes reads as a blindfold.
- **The shirt number on the back**, and a sleeve on a short-sleeved shirt, which
  read as a vest without one.

Two drawing bugs were found by looking at the parade and fixed in passing:
delight and despair were drawn upside down (arched-down eyes and a frowning
"grin" on the delighted face, a smile on the despairing one), and the headband
accessory was a disc across the face rather than a band round the head.

### Ninth: the reference is the toy game and the Mii

Made at the owner's direction, with two reference images: a Sokpop-style
five-a-side game for the figures, and the Mii "choose a look-alike" grid for the
faces. The note was that the hair looked like hats and the beards looked bad.

Both were geometry problems with the same cause — a lump sitting on a head reads
as a lump sitting on a head:

- **Hair is now a sphere slightly larger than the skull, pushed back**, plus an
  optional mass down the back. Two numbers do all of it: the radius is how much
  hair there is, the push back is where the hairline lands. The previous version
  built an ellipsoid from a hairline and sat it on the crown, which is a hat by
  construction. Fourteen styles, from cropped to a big afro.
- **Beards are gone**, and `PLAN.md` §9.3 no longer lists them. A sphere on the
  jaw is a blob at any size and it covers the mouth, which is half the
  expression. If facial hair comes back it belongs on the drawn face.
- **The face got the Mii's range**: brows, eyes with whites and pupils as well as
  plain dots, noses, and more mouths — all per-player and independent of the
  expression. The **brows carry the expression**: lowered and driven in for
  effort, raised for delight, outer ends dropped for despair, driven down hard
  for anger. That is how a Mii gets range out of a face with no rig in it, and it
  costs a two-pixel line.

Two intermediate versions were wrong in instructive ways and are recorded so
nobody tries them again: a shell only a few per cent over the skull and pushed
well back shows as a **rim round the silhouette**, which is a swimming cap; and
fixing that by giving every style volume produces **eleven afros**. Volume
belongs to the two styles that want it, and the hairline does the rest.

A second round on the same note, again at the owner's direction:

- **The nose is a bump on the head**, as in the reference art, not a mark on the
  texture. Six shapes, and a ruddy version of the man's own skin -- pink on a
  pale face, warm red on a dark one, by an amount that varies per player. A
  drawn nose at this size is a smudge; a bump catches the light. The colour is
  derived from the skin rather than drawn from a table, because a pale pink
  button on a dark face reads as a mistake.
- **The face texture is drawn at four times the resolution and anti-aliased**
  from each shape's own distance function. The style tables are unchanged: they
  are written in a 32-square unit grid and scaled, so the resolution is one
  constant. It costs about 4.5 ms to generate a face and they are cached, which
  is a fraction of a frame the first time a player pulls a new expression.
- **Hair colours are colours hair comes in.** The table carried a teal and a
  violet, and half a squad looked like a bag of sweets.
- The head and the hair are built at twice the polygon count of the body. The
  head is the thing being looked at, and at the new face resolution a
  twelve-sided sphere was the roughest edge in the frame.

A third round, again the owner's: the nose became an upright **capsule** rather
than a ball, the eyes went to **solid black shapes** -- whites and pupils were
tried and are gone, because one dark mark carries further and a bead is a grey
smudge at match distance -- and the face and head proportions were worked over.
Heads are 28-33% of height rather than 30-35, and the shape range on both axes
was narrowed so the extremes are a long face and a wide one rather than an egg
and a melon.

Then a fourth look, because the capsule could not be seen: it was sunk to 0.95
of the head radius, so only its front showed and it was a ball again, and three
of the six rows had a length under twice their radius, which **is** a sphere --
that is what a capsule collapses to. They now stand fully proud of the skull at
1.0 and every row clears the ratio. The nose colour was pushed further from the
skin at the same time, and the drawn features moved a little lower and a little
wider apart.

The face is now **hung off the eye row** rather than positioned by eye. The owner
asked for the eyes on the equator of the head, and nudging the quad up and down
kept missing it, so the builder computes the offset from
`SimFaceAtlas.EYE_ROW`: the drawn eye row sits a little above the middle of the
texture, so the texture sits that much below the middle of the skull, and the
eyes land on the equator exactly. Brows above and nose and mouth below follow
from it, and the nose lengths were cut to fit the space that leaves.

The spacing of the features is the part that took two goes. Pulling the eyes in
to a fifth of a head-width apart made every man look pinched, and it is recorded
here because it looks like the obvious fix for a face that reads as too spread
out: the answer was the opposite, roughly a quarter to a third of the head
between the pupils and the eyes drawn large, with the mouth brought up under the
nose rather than down at the jaw.

### Tenth: the toy-figure reference, and the trim comes back

The owner supplied a rank of six toy footballers and asked for the figure to be
closer to it. Two things follow, and one of them reverses part of the eighth
amendment.

**Proportions.** What made ours look top-heavy was never the head — measured
against the reference the heads are much the same, a little under a third of
height. It was a fat torso on short legs with boxing-glove hands. So: legs from
0.46 of height to 0.50, torso from 0.30 to 0.27, shoulders narrower, limbs
thinner, hands from half again the arm's radius to a tenth over it, arms longer
so they hang to the bottom of the shorts, and the boot is a rounded shoe rather
than a box — the last part of the figure that still read as Lego. The shorts now
stop at mid-thigh with bare leg below, instead of running to the knee, which was
a pair of trousers.

**The trim comes back.** The eighth amendment took out a collar, cuffs and a
sock turnover as eighties dressing. The reference has all three — a neckline in
the second colour, a cuff at the sleeve, hoops near the top of the sock — so
they are back, and the reasoning is corrected rather than quietly dropped: that
trim is not period dressing, it is *how a football kit is drawn*, in blocks of
two colours. What the eighth amendment was right about is unchanged: no ink
outline, and the register stays out of the art.

A second pass on the same reference took the rest of it, at the owner's
direction to work hard on likeness:

- **Hair is a shell plus pieces**, which is what the reference actually varies:
  a cluster of nine or thirteen spheres for curls, a lobe swept up for a quiff,
  small tufts for a tousled head, tabs at the temples for sideburns, a point at
  the centre of the hairline for a widow's peak, and a mass down the back. One
  sphere cannot be shaped into a curly head; nine of them are a curly head.
- **A V-neck**, two bars laid on the chest and a band round the back. A ring is a
  crew neck, and every figure in the reference wears a V. The first version
  leaned the bars inward and the man wore a bow tie.
- **Moustaches are back** -- two of the six reference figures wear one -- and the
  **nose is skin-coloured again**, a shade off rather than red. The red came from
  the other reference; this one has plain noses.
- **Ears**, two small tabs where the head is widest.
- **A soft sheen** on the figure only. The reference is moulded vinyl and the
  highlight is most of what makes it read as an object. Scenery keeps the flat
  material.
- Everyone wears socks. `socks_high` used to leave a man bare-legged to the
  ankle, which is not a thing.

One process note, because it cost two rounds of the owner's time. The face-quad
position was edited by string replacement three times and matched nothing all
three times -- a comment had been inserted between the two lines the patch was
anchored on, and the replace failed silently. The renders still changed, because
other edits in the same batch did apply, so it looked like it had worked and was
reported as working. The eyes-on-the-equator change in particular was reported
done and was not. **Verify a targeted edit landed before reporting it**, and
prefer rewriting a whole function to patching around a comment.

### Eleventh: the vinyl reference, and the figure gets squat

The owner supplied four more images and asked for the quality and style to move
towards them. Three are a chunky moulded vinyl footballer, close up; the fourth
is a rank of four slimmer, more human figures. They agree about the finish and
disagree about the proportions, and the owner chose the chunky one.

**This reverses part of the tenth amendment**, which lengthened the legs from
0.46 to 0.50 and kept the head small, on the reasoning that a long body is what
carries a stride. That reasoning came from a slimmer reference. This one is the
squat toy, so:

| Was | Now |
|---|---|
| legs 0.50 of height | 0.26 |
| torso 0.27 | 0.37 |
| bare skull 0.27-0.31 | 0.31-0.35, with hair taking the silhouette past it |
| shoulder half-width 0.138 | 0.185 |

The three big fractions now come to about the whole height, which is the check to
make if one of them is moved again. **The open question the tenth amendment was
right about is whether a leg this short still reads as a stride from the match
camera**, and only watching answers it.

What else the reference asked for, none of it touching `sim/`:

- **Every crease is dark.** The one change here that is not about the figures'
  shapes at all, and the largest. `match_view_3d` carried a comment ruling out
  ambient occlusion along with bloom and reflections, as things that fight the
  hand-made register; the reference is full of contact shading and it is most of
  what makes a flat-coloured object read as an object rather than a set of
  shapes. The comment is corrected rather than quietly dropped. Bloom and
  reflections stay out. It is a screen-space pass over twenty-two figures and it
  has a cost nobody has measured yet.
- **The drawn face is lit.** It was `SHADING_MODE_UNSHADED` on a head that shades
  from the sun and darkens in its own creases, which is the definition of a
  sticker: brightest where the cheek turns away, and unmoved when the man walks
  into shade. It takes the head's material now, sheen included.
- **The brows are moulded, not drawn.** Thick ridges in the man's hair colour,
  standing proud of the forehead — the most characterful thing on the reference
  figure, and the last feature that was still a drawing. `SimFaceAtlas.brow_pose`
  is now the single table both the geometry and the face are posed from, because
  two copies of it drifting apart is a squad whose faces disagree with
  themselves. `texture_for` no longer takes a brow style and its cache key is
  that much smaller.
- **The eyes are a quarter bigger.** Measured off the reference an eye is about a
  seventh of the width of the face; ours were nearer a ninth, which is a man with
  small eyes rather than a toy with big ones.
- **The perm is a perm.** Curls went from nine or thirteen small lobes to twelve
  or sixteen fat ones, and the big curly head grew a skirt — a second ring
  carried down past the ears to frame the face, with the front left out of it,
  because a curl over the front of the face is a hand over the eyes rather than a
  fringe. The mass used to stop above the brow, which is hair sitting on a head.
- **The parade stands on paper.** The background was already paper, for the
  reason recorded there — a green field competes with the kit being judged — but
  the floor under it was still pitch green, which was that argument left half
  finished. A shade under the background, so the figure has something to stand on
  and the softened contact shadow has somewhere to land.

A second round on the same reference, this time with the figures on screen. The
owner kept the shoulderless torso -- the primitive reference has no shoulder line
either -- and named the shorts, the faces and the hair as what was wrong.

What looking found, none of which reading the code had:

- **The shorts were an inner tube.** Every version had been a rounded solid, and
  a rounded solid bulges wider than the hips and finishes in a curved lower edge.
  A cylinder has a flat hem, and that one edge is most of what makes a garment
  read as clothing rather than as padding.
- **The torso was a ball in a shirt.** A capsule 0.37 high and 0.14 across is two
  domes with almost no straight section between them. A cylinder with a soft cap
  on top is the reference shirt: straight sides, round only at the shoulder.
- **The V-neck was buried.** It had been tuned against a capsule, which narrows
  towards the collar, so a bar set well inside the chest still broke the surface.
  Against a cylinder of constant radius the same bar never surfaced at all and
  showed as a small dark "w" mid-chest. Anything laid on the torso is now placed
  against the torso's own radius.
- **The moustache showed as two dots.** Centred at 0.88 of a head radius where
  the skull reaches 0.97, it was inside the head except at its two widest points.
- **Lumps sitting proud of the hair shell read as buds, not hair.** The tousled
  cut put four spheres on a crown and looked like a topknot; so did the quiff's
  grid of twenty. Overlapping spheres still meet in a valley, and a valley on a
  crown is a bud either side of it. Both are flattened to break the shell rather
  than sit on it. The afro is the exception and stays lumpy -- the reference perm
  is lumpy.
- **Short brows read as a second pair of eyes.** Against eyes a quarter bigger, a
  bar near 3 half-units is just another dark oval; near 4 it is a brow.

Every one of these is a placement or a primitive, not a value. None would have
been found by reading, and none needed measuring -- they needed a picture.

**Then they looked like cylinders running around**, which is the correction to
the correction and is recorded because the first fix caused it. Straight sides
cured the ball in a shirt and produced plumbing instead: nothing on a body is the
same width all the way up, and a circular cross-section is the other half of it.
Three things together, none of them a profile tweak:

- **Taper.** One radius at each end. The shirt is widest at the chest and drawn
  in slightly; the shorts are the opposite, narrow at the waist and widest at the
  hem, which is the shape a leg opening makes.
- **An oval in plan.** `TRUNK_DEPTH`, a flat 0.84 on the trunk and the shorts. A
  body is never a circle seen from above, and this one number does more than any
  amount of shaping the outline. Anything laid on the front of the shirt -- the
  collar, the number -- moves in by the same factor or it floats.
- **The shirt has to stop.** Measured off the reference the hem is at about 0.37
  of total height and the crotch at 0.24, so a seventh of the figure is shorts.
  Ours ran the shirt to the hip and left the shorts a sliver, which made the whole
  trunk one tube from the collar down. This was the largest of the three.

**Then the parade was turned round, and half the trim was floating in the air.**
Everything above had been judged head-on, which is the one angle that hides a
part standing off a curved surface. `--turn 45 --still` and `--turn 90 --still`
are now the views to check before believing any of it.

The common fault, four times over: **a part placed at a fixed depth on a curved
body**. That is right on the centre line and wrong everywhere else.

- **The drawn face was a vertical cylinder segment on a spherical head.** A strip
  1.5 radii tall held at a constant 1.02, where the skull at the chin has drawn
  in to 0.66 -- a third of a radius of daylight at the top and bottom edges. It
  is a spherical patch now, bent both ways. The old note said a vertical bend
  would have to clear the jaw; it does not, because the jaw is inside 0.95 at
  every height the face covers. The eye row is put on the equator by shifting the
  pitch the patch is drawn through, **not** by sliding the node down afterwards --
  translating a curved patch down its own axis is the same bug again.
- **The brows were placed by the same cylindrical arithmetic** and stood off the
  forehead for it. A place on a face is two angles, not an angle and a drop.
- **The V-neck was a batten strapped to the chest.** Set at a fixed depth it stood
  a quarter of the trunk's depth proud at the shoulder. It is placed on the
  trunk's ellipse at its own x now, turned to the ellipse's normal -- which is
  `(x/a², z/b²)`, not `(x, z)` -- and it is short, thin and sunk, because a
  straight bar rolled into a V lifts its own ends off a curved surface however it
  is aimed.
- **The arms hung in front of the chest.** The shoulder pivot was at 0.64 of the
  shoulder half-width, inside the trunk's own 0.80 radius, so from the side the
  whole arm floated over the shirt. Out at 0.80 it hangs beside the body with its
  top buried in the shoulder.

The shorts stopped being a skirt in the same pass, and the fix was not their
width: the leg tubes have to hang well below the seat. A seat that reaches as far
down as they do fills the notch in and the garment is a skirt again at any width.

The trunk was widened with them, from 0.185 of height at the shoulder to 0.215.
The reference shirt is about 0.15 half-width and ours was 0.124, and a narrow
trunk is why the shorts kept having to be narrower still to avoid reading as a
skirt -- which they did twice, in both directions, before the widths were made to
agree.

**Then the legs of the shorts were outside the seat of the shorts**, which is the
same fault as the floating trim and was found the same way -- by turning the rank.
The seat was one flattened tube, so in plan it was an ellipse; the legs were
cylinders sitting inside it. An ellipse is narrower than a circle it touches
everywhere except at the point they touch, so head on the two walls lined up and a
quarter turn later each leg had broken out through the side of the seat, leaving a
step down the hip.

Neither piece was wrong on its own. **The shape of the garment in plan was.** Shorts
are a rounded oblong seen from above -- a thigh's width at each end, a straight run
between -- and they are built that way now: a box with a cylinder on each end, the
cylinders being the legs' own, at the legs' own radius and depth. The wall is one
line from waist to hem at every angle, and the seat's only job above the legs is
the block between them.

Two things fell out of it. The seat's flare, 0.60 at the waist to 0.64 at the hem,
was **entirely under the shirt** -- the shirt finishes at 0.427 of a leg height off
the hip and the seat at 0.48, so all but half a percent of the flare was hidden.
It is gone and nothing looks different. And the first fix tried was to flatten the
legs to match the ellipse instead, which does cure the step and puts a shelf across
the front of the hem in its place: a leg thin enough to stay inside a shallow
ellipse is far shallower than the seat it hangs off. That direction has no bottom
to it -- the flatter the seat, the thinner the legs have to be, and the thigh
inside sets a floor they hit first.

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

**One camera, and it pans** (§9.2 amended again, 2026-09-02). The two
penalty-area cameras are gone at the owner's direction: even the rare cut was
more than wanted. The halfway camera takes the whole match, and its elevation
comes down from 35° to 27°, and the zoom only half-compensates for range, so
the far touchline is no longer pulled in to full size.

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

### Twelfth: the art rules come out, and the references are the specification

The owner asked for every direct rule about the look to be removed from
`PLAN.md` §9, leaving only the two in §9.5 that are not about the look — the sim
is authoritative, and legibility over realism — and §9.7's boundary. The reason
given: the art will change more than once during development, and a written rule
is a thing that has to be argued with each time.

The evidence was already in this file. Four amendments above this one are art
amendments, and every one of them was written down *after* the owner had looked
at a picture and said what was wrong with the figure beside it. The picture was
doing the work. The prose was a lagging copy, and a stale copy is worse than
none, because it argues back:

- §9.1 still said "unlit or two-band toon shading, no physically-based
  materials, roughness at maximum" long after the tenth amendment had asked for
  a soft sheen and the code had one.
- §9.1 still said "no ambient occlusion" after the eleventh amendment had
  reversed it in as many words — and the reversal was recorded and never built,
  so the document forbade the thing the project wanted and the code did neither.
- §9.3 specified six hundred to twelve hundred triangles against a built figure
  of three thousand.
- §9.3 described the head as three ellipsoids, which stopped being true when the
  figure was rebuilt out of rings.

So §9.1 is now one page saying where to look: `art/reference/`, the rank render,
the parade, and the two silhouette measuring tools. §9.3 and §9.4 are gone.
§9.2 (camera) stays as written: it is a system -- a panning position, the
elevation and the frame width solved each frame -- and not a statement about the
look. §9.6 (interface) was generalised rather than deleted, at the owner's
direction: it now says the interface is drawn in whatever look the figures
currently have, and keeps only the two lines in it that were never style -- large
hit targets, and no screen allowed to become a spreadsheet.

The §9 preamble stays too, relabelled. Sokpop, the Mii and Animal Crossing are
**inspiration and feel, and the company to keep**, not a description of what to
build; where a name there and a reference image disagree, the image wins.

**What this does not change.** The amendments above stay, as a record of what was
tried and what looking found — the moustache that read as two dots, the shorts
that were an inner tube, the hair that sat on the head like a hat. They are
lessons, not law, and none of them binds a new direction. §9.7's boundary stands
untouched: the comic register governs the writing and the feel and does not
govern the art.
