# art/ — the figure, in Blender

A sandbox for the look of the players: a shape can be looked at in seconds here
instead of a Godot launch. It is not a port of
`presentation/character_builder.gd` — the construction is different on purpose,
see *Why a distance field* below.

**Two ways out, and `./art/model.sh` is the one that ships.** `art/toy/` builds
the same man out of rings at the density he ships at -- about 5,900 triangles --
so nothing is thinned and no hem, trim or seam is ever rewritten by a decimator.
`docs/THE_MODELS.md` has the argument and what is still open in it.

The distance-field route below is kept as the A/B: it is the only one that
ships the moulded surface itself.

**`./art/export.sh` writes
`presentation/models/body_<type>.glb` and the game instantiates it; this used to
end with a shape being carried back into GDScript by hand, because the game
could draw nothing but primitives. **`docs/THE_MODELS.md` is the contract** —
the five bodies, the axes and the 1.78 m reference, the material names, hair and
accessory variants, and the node names the animation poses. It also lists what
the export does not answer yet: the triangle budget, one hair and one face per
body, and five bodies that are still one body.

```sh
./art/export.sh --body standard              one of the five
./art/export.sh --body giant --tris 6000     a tighter triangle budget
./art/export.sh --seed 41 --shot /tmp/a.png  one player, and a look at him first
```

`model.sh` renders too, and its `--shot` takes `--yaw` and `--head`. A face is
judged from the side as much as from the front -- head-on it reads by its
shading, in profile it *is* the outline -- and until these existed there was no
way to look at one:

```sh
./art/model.sh --seed 41 --head --yaw 90 --shot /tmp/a.png   his profile
./art/model.sh --seed 41 --head --yaw 45 --shot /tmp/b.png   the game's angle
./art/model.sh --seed 41 --sheet /tmp/c.png                  every cut, one head each
```

Godot has to import a new `.glb` before `ResourceLoader.exists` can see it:
`godot --headless --import --path .` once, then `./run.sh parade --seed 7`.
`SimCharacterModel.models_enabled = false` draws everybody procedurally whatever
is on disk, which is the A/B.

```sh
./art/render.sh --who moustache          # one man, full length
./art/render.sh --mode views             # the same man from four sides
./art/render.sh --mode rank              # the four reference figures
./art/render.sh --mode squad --count 6   # seeded players: the clone-army check
./art/render.sh --mode heads --count 8   # framed on the faces
./art/render.sh --who perm --turntable 8 # eight frames round one man
./art/render.sh --blend /tmp/toy.blend   # save the scene instead of rendering
```

Renders land in `art/renders/`. `--cell` is the quality knob: `0.008` is a fast
look, `0.0045` the working default, `0.0025` publishable. `--help` lists the
rest.

About twenty seconds a figure at the default cell on this machine, most of it
Cycles rather than the mesher.

## Why a distance field

Two spheres pushed into each other **intersect**, and an intersection is a
crease. A moulded object has a **fillet** — the surface leaves one form and
arrives at the other along a curve, and the size of that curve is the strongest
single signal that a thing came out of a mould rather than being assembled from
parts. No amount of shaping individual primitives produces one.

So each moulding is a signed distance field, combined with a smooth union whose
blend radius *is* the fillet, and meshed with surface nets. That also buys the
face: an eye socket is a sphere taken **out** of the head with a small fillet,
which leaves the soft rim moulded vinyl has. Nothing on the face is drawn — the
brows are ridges, the nose is a bump, the mouth is a groove.

## Everything below is read off the pictures, not laid down

`PLAN.md` §9.1 has no rules about the look in it any more: the reference images
are the specification and they are expected to change. What follows is what was
read off the four in `reference/` and what building against them taught -- a
record, useful until a new picture says otherwise, and not law.

## The one idea to keep hold of

**A solid is one moulding and one colour.** Inside a solid everything fuses with
a fillet. Between solids the edge stays hard — and hard is exactly right for the
three edges that carry the kit: the shirt hem, the shorts hem and the sock top.
The references have those three crisp and everything else soft, and that
contrast is most of what reads as a football kit.

## The files

| file | what it holds |
| --- | --- |
| `figure/sdf.py` | Distance-field primitives, the smooth union, and `Solid`. `k` is a fillet radius in metres and is the one number worth playing with. |
| `figure/surfacenets.py` | Field → quad mesh. Sixty lines, and quads, which is what the smoothing afterwards wants. |
| `figure/body.py` | **The figure.** Every proportion, read off the references. Start here. |
| `figure/cast.py` | The four reference figures as presets, and one integer → one player. `unpack_body` reads the body the record packed into the seed; the draw is kept for a seed that carries none. |
| `figure/rig.py` | **The skeleton.** The sixteen joints the game poses by name, where their pivots are, and which moulding is allowed to land on which. Both routes use it. |
| `toy/mesh.py` | Rings, superellipse sections and the one primitive nearly everything is made of. Pure Python -- a shape can be measured without Blender. |
| `toy/figure.py` | **The low-poly figure.** Same proportions as `figure/body.py`, assembled instead of moulded. |
| `toy/hair.py` | The eighteen cuts, one mesh each, in `HAIR_LIBRARY` order. |
| `model.py` | The `.glb` that ships: joints, named materials, hair variants, the face patch and the brows. |
| `figure/split.py` | Cuts a moulding a second way, by joint. A Voronoi of bones, with measured clip boxes and an overlap so a bend cannot open a gap. |
| `export.py` | The `.glb`: joints, materials named for their slot, a triangle budget, and `--shot` to look at what is about to be written. |
| `figure/mould.py` | Solid → Blender object: mesh, normals, smoothing, vinyl material. |
| `figure/studio.py` | The room: cyclorama, four soft lights, camera framing, render settings. |
| `figure/palette.py` | The game's `Color`, and sRGB → linear on the way into a shader socket. |
| `build.py` | The command line. |
| `measure_reference.py` | Measures the reference **photograph's** silhouette, flood-filling from the border, and prints it in fractions of figure height. Proportions get read rather than remembered. |
| `silhouette.py` | The same measurement of our own figure, in the same units, printed against the reference's numbers. |
| `crop_reference.py` | Saves a close crop of a reference photograph, in fractions of the *figure's* height. Details that a full-length view cannot show — the studs under a boot, the thumb on a hand — get looked at rather than assumed. |
| `crop_render.py` | The same for one of our own renders, so the two can be set side by side. |
| `outline.py` | Measures a moulding's plan outline for **creases**, without Blender. A crease is a concavity -- the silhouette stepping inwards as it goes round -- and finding one this way is a second's work against twenty for a render. |
| `reference/` | The owner's four reference images and what was measured off them. |

## Things already learned the hard way

- **Nothing on the face may be placed at a fixed depth.** The head is two
  rounded boxes, so its surface is flat over a small panel and curves away from
  there — and the eyes sit nearly half a head-width out, where it has curved a
  long way. Placed at a constant `y` they were first buried (two dark specks for
  brows) and then bulging five centimetres proud (googly eyes). `_front(x, z)`
  solves the head's own surface and every feature is hung off it, so changing
  the head shape does not throw the face off it.
- **`_front` has to know about the jaw as well as the skull.** Solved against
  the skull alone it is right across the brow and two centimetres too far back
  at the mouth, because down there it is the jaw that is in front. A moustache
  placed on it vanished into the chin.
- **A garment box has to run a full corner-radius past its hem.** Cut at the
  box's own bottom face, the rounding has already drawn the sides in, so the
  hem tapers instead of ending flat — the shirt finished narrower than the
  shorts under it.
- **Whatever is under a garment has to be inside it.** The bare trunk was wider
  than the shirt and the body broke out through the shoulders.
- **A neckline V is one shape used twice** — cut deep out of the shirt, added
  shallow to the trim. Sized apart, the two drift and the insert becomes a badge
  floating in front of a shirt with no neckline in it. Two leaning bars fill a
  *rhombus*, not a triangle; a stack of narrowing slabs does it directly.
- **Every hair style starts from the same shell.** Built out of its own lobes, a
  perm is a ring of curls round a bald patch.
- **A separate fringe piece does not work.** Far enough forward to show, it is a
  slug on the forehead; far enough back to hug the shell, it lands on the brows
  and the two fuse into one bar. The hairline is the cut, and the cut can simply
  come further down the forehead.
- **A rim radius must be smaller than the straight run it leaves behind.** The
  shirt barrel rounded over a 135mm rim with only 81mm of straight side, so it
  began drawing in at z 0.765 while the shoulder above it did not pick up until
  0.841 — and in between the man had a wasp waist, a quarter thinner just below
  the chest than at either the hem or the shoulder. It shows only from the side.
  Small rim, top raised to meet the shoulder: 0.147–0.165 instead of
  0.113–0.158.
- **One thickness for the whole body.** The seat of the shorts was the deepest
  thing on the figure — 0.208m half-depth against the chest's 0.147 — so in
  profile the man had a belly and a backside and a chest narrower than either.
  Depth now runs 0.105–0.160 top to bottom.
- **A plane cut applies to the whole solid.** Cutting the shirt hem after the
  sleeves were added took the bottom off a long sleeve too: the keeper had a
  bare arm from the hem down and a cuff floating at his hip. Ops run in order,
  so the hem is cut before the sleeves go on.
- **A hair shell needs a bottom as well as a top.** Given only a top and a
  thickness it finishes level with the ears and every man is bald from there to
  the nape — which a front view cannot show and a back view shows instantly.
- **Judge nothing from the front alone.** `--mode views` puts the same man at
  four angles in one frame. The first pass had a bored hole where the crotch
  should be and a bare torso breaking out through the back of the shirt, and
  neither showed head-on.
- **A crease is a step in *depth*, not in width, nine times out of ten.** The
  hard line down the side of the shirt was a 44cm-deep torso meeting a 26cm-deep
  sleeve. Blending harder makes it worse: past a certain radius the smooth union
  is reading the field far from any surface, where it is only approximate.
- **Close that step by bringing the trunk in, never by pushing the shoulder
  out.** Both shut the crease. One leaves a figure that is fine from the front
  and far too deep to look at from the side, and the front view will not tell
  you which one you did — `--mode views` will. The shirt tapers front-to-back
  as it rises now, and the mass at the joint stays compact: widened into a bar
  it stops being a shoulder and becomes a shoulder pad.
- **Some seams are meant to be there.** A shirt has a shoulder seam. Chasing
  `outline.py` to zero cost the shoulder its shape three times over; the number
  is for finding a crease, not for deciding it must go.
- **The offset of an ellipse is not an ellipse.** Shrinking a barrel's plan
  section by its rim radius and inflating it back is the standard rounded-solid
  trick and it is only correct for a *circle*. Push the rim radius near the
  section's own depth and the shrunk ellipse collapses to a line — whose offset
  is a **stadium**, dead flat front and back. That flat panel across the chest
  is what made the torso read as a postbox, and easing the rim could never have
  fixed it, because easing the rim was what caused it. `Barrel` keeps the
  section exact now and rounds the rim in the 2D space of (distance to the
  ellipse, height).
- **A shirt is a body tube plus a sloping shoulder, not one barrel.** Measured
  off the reference the shoulder falls about twenty degrees from the neck out
  to the sleeve, and the sleeve then hangs at about seventy. Vertical sides and
  a domed lid is a postbox whatever the radius; that slope is most of the
  silhouette.
- **A wide smooth union inflates the surface wherever the two fields are
  equidistant.** Across a chest that is a broad band, so a shoulder blended on
  at h*0.075 printed a **flat plateau** on the shirt — 24cm of it at a constant
  depth, reading as a rectangular panel stuck to the front. The blend has to be
  small; if a step needs hiding, change the shapes, not the fillet.
- **A slab crossed with a solid gives a whole cross-section**, which closes into
  a ring. Four rings round a boot are a bandage, not stripes: the band has to be
  cut off below the instep as well.
- **Gaps are a measurement.** The reference's arms show as **separate runs** in
  the silhouette, clear of the body by .006–.008 of figure height. Ours were one
  run with the body, and three different things were welding them: the arm sat
  25% too far in, it was 18% too thick, and — the one that took longest to see —
  the fillet joining it to the trunk was 81mm wide, which webs anything within
  81mm of it. **A smooth union bridges any gap narrower than its own radius**,
  so a fillet has to be smaller than the daylight you want to keep.
- **The widest thing on the figure is the arm, not the sleeve.** Ours had a
  sleeve at limb*1.80 over an arm at limb*0.92, which is a puff sleeve and the
  wrong way round in every reference.
- **Measure the reference, do not remember it.** The V was twice as wide as the
  reference's and half the chest deep — the real one is thirty per cent of the
  shirt's width and a fifth of its height. Two minutes with the picture open
  beat an hour of adjusting it by eye.
- **A distance field has to be a distance.** `(k - 1) * min(radii)` for an
  ellipse under-reports the distance along the wide axis by the whole aspect
  ratio, so a fillet comes out two and a half times smaller there than it was
  asked for. Every blend in the file assumes it is being handed a real
  Euclidean distance; one Newton step (`(k - 1) * k / |grad k|`) gives it.
- **A rounded box's radius must not exceed its smallest half-extent**, or the
  box inflates along that axis instead of rounding. It stays watertight, which
  is why it goes unnoticed. `RoundBox` clamps it now.
- **Whatever is under a garment has to be inside it at every height**, not just
  at the widest one. The shirt rounds in towards the shoulder; the trunk did
  not, and its own square rim read as a hard line straight across the chest.
- **A hairline is an edge you author, not a place two shells happen to meet.**
  Every version of the hair let a smooth shell pass through the skull and called
  the intersection the hairline. Two low-poly surfaces crossing at a shallow
  angle do not make a line, they make a sawtooth, and seventeen cuts had one
  across the forehead. Three goes at fixing the *crossing* — tucking the shell
  in to steepen it, sizing the rim for the skull's widest point, matching the
  rim's section to the skull's — changed nothing at all, because the crossing
  was never the problem. The rim now sits **on** the skull, a millimetre out,
  and the ring above steps straight to full size. Same lesson as the sock
  hoops: stop laying one surface over another and make the edge yourself.
- **What looked like a bad intersection was a sampling rate.** Once the rim was
  authored the teeth were still there, and the reason is that a hairline is not
  level — it is high at the brow, low over the ears, lower at the nape — so the
  rim is a wavy curve in three dimensions. Sampled twenty times round the head
  that curve *is* a row of teeth. Doubling the segments on the hair fixed in one
  line what three geometric arguments had not.
- **A push back has to fade out as the shell rises.** Applied to every ring
  equally it does not make a hairline, it slides the whole cut backwards off the
  skull: sixteen of seventeen came out as a dark rim round the ears with a bald
  man inside it. On one head at a time that reads as a hairline that is merely a
  bit high, which is why it survived so long — the contact sheet of all
  seventeen is what showed it, in one look.
- **Anything worn on a head has to clear the hair, not the skull.** The cap and
  the headband were sized to the skull, the hair shells are a tenth larger than
  it, and both accessories were swallowed whole — all that showed of the cap was
  its peak, poking out of the top of a man's head like a fin.
- **A collapse ratio is a request, not a result — measure.** `export.py`
  printed the triangle count it had *asked* for and wrote a thirteen-megabyte
  file of 677,000 triangles while claiming 8,000. Worse, a whole afternoon of
  "look how much better the hems are now" was comparing a decimated figure
  against an undecimated one. The count now comes off the evaluated depsgraph.
- **Blender's decimate vertex group is where collapse is *allowed*, not where
  it is forbidden.** A group holding only the hems, uninverted, protects
  everything that is not a hem. And inverted it is still no use here: the
  protection is binary rather than graded, so the hem loops at full resolution
  are a 22,000-triangle floor the budget cannot go under, and the factor
  saturates — 1.0 and 3.0 give the same mesh.
- **Nearest bone alone puts the waistband up the sleeve.** Splitting the
  mouldings by joint is a Voronoi of bones, and the arm hangs beside the hip:
  the top corner of the shorts is genuinely nearer the upper arm than it is to
  the spine. Same at the collar, where the shirt's shoulder capsules reach past
  the chin before the collar hole is cut out of them and the skull claims them.
  A table saying which part of a man each garment covers is one line each and
  fixes both — and it cannot leave a hole, because the Voronoi is then computed
  over fewer bones rather than over less space.
- **An overlap holds the same surface twice.** Two parts that meet on one
  surface crack open the moment the joint between them bends, so they share a
  shell of solid instead — and inside that shell both of them carry the same
  stretch of the same skin. At full resolution the two copies sit on top of each
  other and nothing shows; thinned to a triangle budget they cross, and the arms
  come out clawed. The seam is a *smooth* intersection for that reason, drawing
  each part in a little further the further out from the trunk it hangs, so at
  every seam one surface is plainly the one in front.
- **A hoop is not a ring.** The sock hoops look like thin bands and are capsules
  as fat as the sock itself, buried in it with only their equator showing. Cut
  one out of the sock to stop the two surfaces fighting and the sock is hollowed
  from the knee down and the buried capsule becomes the leg. What shows is not
  the shape.
- **One scale per ring is a head with no face in it.** Every row of `SKULL`
  sized its width and its depth together, so the front of the head was a dead
  vertical wall from the brow to the cheek -- a centimetre of variation over
  twenty -- and the jaw fell straight off it in one arc. Head-on that is
  invisible, because head-on a face reads by its shading; in profile it is a
  plain egg with a button on it. Depth is its own column now and the table is
  the profile itself: a chin that comes forward, a cheek that is the furthest
  point, a forehead that falls away while the back of the skull does not.
- **A section cannot carry a face, however many columns it has.** Depth and
  forward bought a profile of four per cent of a head-depth -- brow to cheek,
  four millimetres over twenty centimetres -- and that is still a wall. A ring
  is one closed section and its front is as flat as its `power` says; the mass a
  mouth and an upper lip sit on is not a section at any height. So `SKULL`
  carries two more columns, and `M.swell` pushes the **front** of a ring forward
  at its middle and fades it to nothing by its widest points. Only the front
  moves: the back of the skull, the ears, the hairline at the sides and the
  sideburns are all untouched, which is why a mouth costs a hairline nothing.
- **One fade cannot carry both the face and the mouth.** `bulge` fades over the
  whole width, because the mass it builds is the whole face: fullest at the
  mouth, a third of it left at the brow, a tenth at the chin, a muzzle over a
  jaw that recedes. A groove cut with that same fade is a crease from ear to
  ear, so `lip` is a second column over a quarter of the width -- the chin, the
  two lips, and the **negative** rows between them. The negatives are the point:
  a lip that only swells is a swelling, and what says mouth in a profile is the
  line between the lips and the dip under the lower one. Three rows were added
  to hold them; at four and a half centimetres apart the table could not.
- **The drawn mouth and the moulded one are the same mouth.** `MOUTH_STYLES`'
  row 23.2, projected onto this skull, lands at 0.708 of height -- so that is
  where the groove is, and the atlas's line sits in it rather than beside it.
  The face patch got twice the rows for the same reason: at sixteen it spanned
  the whole mouth in two of them and bridged the crease flat.
- **Anything measured off the front of the face has to ask where the front is.**
  The nose and both pairs of moustache lobes were placed at a number typed once,
  and a swell laid on the face buries every one of them. `skull_front` is the
  question. `brow_stand` and `eye_stand` are the same bill paid the other way:
  the game poses brows and eyes on a sphere, the sphere does not move with the
  face, so each asks the skull what the swell is worth at its own height and its
  own distance out. They are functions and not constants on purpose -- typed in,
  they are two numbers to re-fit by hand every time the face changes shape.
- **A push back that slides the whole ring puts nine centimetres of hair behind
  the nape.** `back` is what buries a shell's rim in the forehead, and a
  hairline on a forehead is the whole of what it is for -- but added to the
  ring's `cy` it moved the *back* of the ring by the same three tenths of a
  head-depth. So every cut stood off the skull at the nape and ended there in
  the rim's own hard edge: a helmet with the lid cut off. The shell was never
  too big; the back of it was in the wrong place. `M.Ring.slide` tapers the push
  to nothing at the very back, and the nape gets the hair the shell's `r` gives
  it, about three centimetres.
- **It tapers in `y`, and the first try faded it in `x` like `bulge` and cost an
  ear.** Fading sideways takes the push off at the ring's widest points, which
  is exactly where an ear is: the hairline came forward six centimetres at the
  temple and swallowed it. The sides have to keep the push. Only the back gives
  it up.
- **A sideburn as deep as it is tall is a disc.** At 0.34 of a head-depth it was
  round in the one view it is looked at from. Halved front to back and longer
  down, it is a strip in front of the ear, which is what a sideburn is. The
  overlap that guarantees its join to the shell is still six centimetres of
  depth and `BURN_DROP` vertically.
- **An eye bead is fitted at its rim, not at its pole.** `EYE_STAND` was set so
  the pole stood a few millimetres proud, and the bead is a flat dome -- a
  hundred millimetres across, thirty-five deep -- laid on a head that curves
  away from the sphere the game poses it on. Pole twelve millimetres inside the
  skull, **rim twenty-two millimetres outside** at the top and the nose side,
  which from the side is daylight between an eye and a face. The two numbers do
  not even have the same sign; measuring the one that was easy to measure hid it
  for as long as it existed. Sunk ten, and what stops it going further is the
  bead's outer edge: six millimetres of it are still proud, and at twenty the
  rim is flush and the eye is a sliver.
- **Sinking it cannot fix a lean, and the lean was most of it.** With the bead
  sunk, its top rim still stood six to eight millimetres out while its bottom
  was twenty in -- because the game aims each bead along a radius of a shell
  centred on the eye row, and the face at the eye row is leaning back as it
  climbs to the brow. Nothing about how deep the bead sits changes that; the
  spread just slides. Leaning the whole `Eyes` node puts the top of the rim
  five to seven millimetres **inside**, which is an eye set in a face.
- **The lean is the secant, not the tangent.** The face's slope at the eye row
  is six degrees; the bead reaches a third of a head-width above and below it,
  and over that span the face falls back fourteen. Fitted to the tangent it
  would have closed less than half the gap. `eye_node` measures the face at the
  bead's own top and bottom, so it re-fits itself when the head changes shape.
- **A lean about the node is a lean about a point behind the face**, a third of
  a metre back, so on its own it swings both eyes down the cheek. `eye_node`
  returns the offsets that put them back. Both beads take the same one: they
  differ only in `x`, which a lean about `x` does not touch. A per-eye yaw would
  need the same treatment and cannot have it -- the game writes each bead's own
  rotation, so the node is the only lever the model owns.
- **A profile shot on a short lens is a picture of the near cheek.** At 110 mm
  the camera stands two metres from a head half a metre deep, and the outline at
  `--yaw 90` is the cheek nearest the lens, magnified by being a quarter of a
  metre closer -- not the face's own centre line. A mouth plainly in the mesh
  and plainly in the game was simply not in that picture, and two hours went on
  believing the picture. `--head` shoots at 320 mm now, which is near enough to
  orthographic that the profile is the profile.
- **The brow ridge belongs to the posed bars, not to the skull.** A bump on the
  forehead is the single thing that reads best in a still, and 0.805 of height
  is also exactly where a receding hairline sits: eight millimetres of ridge
  came through the hair as bare scalp on a third of the seventeen cuts. Above
  the cheek the skull's front recedes all the way to the crown and never turns
  back. The game poses two brow bars a centimetre proud of it, and that is the
  ridge.
- **A hairline is buried on purpose, so anything that moves the forehead moves
  it.** The shell's front is pushed *into* the skull near its rim -- that is
  what puts a hairline on a forehead rather than a fringe over the eyes -- so
  taking the forehead back out from under it let `M.roughen`'s wobble through
  as two specks of hair on bare skin. The fall of the forehead is kept above
  0.835 for that reason.
- **A rim ring has to enclose every height it reaches, not the one its `z`
  names.** `tilt` carries a hairline's front up and `drop` carries its sides
  down, so one ring spans three centimetres of skull. Sized at one height and
  centred at another it was fine while the skull was the same shape all the way
  up that band, and dipped inside the moment the face had a profile in it.
- **A nose is judged in profile and sized from the front.** Buried to its centre
  it stood five centimetres off a head fifty-three deep. Longer, not bigger:
  depth is the only axis a profile sees, and the front view was already right.
- **Cut with a plane and mind the sign.** The interior is the side the normal
  points *away* from. Backwards, the shirt is a 13mm sliver at the waist and the
  socks are worn at the knee.
