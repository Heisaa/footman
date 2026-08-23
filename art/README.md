# art/ — the figure, in Blender

A sandbox for the look of the players. **Nothing here ships.** The game builds
its figures at run time in `presentation/character_builder.gd`; this exists so a
shape can be looked at in seconds instead of a Godot launch, and so that
whatever wins gets carried back into the GDScript by hand.

It is not a port of that file. The construction is different on purpose — see
*Why a distance field* below.

```sh
./art/render.sh --who moustache          # one man, full length
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
| `reference/` | The owner's four reference images and what was measured off them. |

## Things already learned the hard way

- **The head is a rounded box**, so its front is *flat*, at exactly `face_y`. A
  feature placed at nine tenths of that is a tenth of a head-depth inside the
  man's face. That is where the brows were, and why they read as two dark
  specks.
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
- **Cut with a plane and mind the sign.** The interior is the side the normal
  points *away* from. Backwards, the shirt is a 13mm sliver at the waist and the
  socks are worn at the knee.
