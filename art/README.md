# art/ — the figure, in Blender

A sandbox for the look of the players: a shape can be looked at in seconds here
instead of a Godot launch. It is not a port of
`presentation/character_builder.gd` — the construction is different on purpose,
see *Why a distance field* below.

**Two ways out, and `./art/model.sh` is the one that ships.** `art/toy/` builds
the same man out of rings at the density he ships at -- about 3,200 triangles --
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
- **Cut with a plane and mind the sign.** The interior is the side the normal
  points *away* from. Backwards, the shirt is a 13mm sliver at the waist and the
  socks are worn at the knee.
