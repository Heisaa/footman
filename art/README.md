# art/ — the figure, in Blender

A sandbox for the look of the players. **Nothing here ships.** The game builds
its figures at run time in `presentation/character_builder.gd`; this exists so a
shape can be looked at in seconds instead of a Godot launch, and so that
whatever wins gets carried back into the GDScript by hand.

It is not a port of that file. The construction is different on purpose — see
*Why a distance field* below.

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
| `figure/cast.py` | The four reference figures as presets, and one integer → one player. |
| `figure/mould.py` | Solid → Blender object: mesh, normals, smoothing, vinyl material. |
| `figure/studio.py` | The room: cyclorama, four soft lights, camera framing, render settings. |
| `figure/palette.py` | The game's `Color`, and sRGB → linear on the way into a shader socket. |
| `build.py` | The command line. |
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
- **Cut with a plane and mind the sign.** The interior is the side the normal
  points *away* from. Backwards, the shirt is a 13mm sliver at the waist and the
  socks are worn at the knee.
