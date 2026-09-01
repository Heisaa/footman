# The models

What a built figure has to look like from the game's side, so a model made in
Blender can replace the procedural one without anything else changing.

`presentation/character_model.gd` is the seam. It reads the man's body out of
his `appearance_seed`, and either instantiates a model for that body or hands the
job to `SimCharacterBuilder`, which is the primitives the game has always drawn.
**With no models on disk everything works exactly as before**, so the models can
land one at a time and a half-finished library breaks nothing.

## The five bodies

Moulded silhouettes with the build scaled on top, not a morph target for every
man: a morph target is a month of work.

| Body | Who gets it | File |
|---|---|---|
| `standard` | most of a squad | `presentation/models/body_standard.glb` |
| `heavy` | build 0.66 and over, strength under 0.62 | `body_heavy.glb` |
| `buff` | build 0.66 and over, strength 0.62 and over | `body_standard.glb`, widened |
| `lean` | build 0.34 and under | `body_lean.glb` |
| `giant`, `sprite` | nobody new: height is not a body. The files stay for old seeds | `body_giant.glb`, `body_sprite.glb` |

`WorldLook.body_type_for` is the rule and `WorldLook.type_name` is the spelling
in the filename. Height is scaled on top of whichever mould, and then
`SimCharacterModel._shape_body` widens or narrows the limbs and the torso by
the build, continuously, with the buff man pushed further. A mould carries the
silhouette; the build carries the rest.

## How the body reaches the model

`appearance_seed` is the **only** thing about a man's looks that travels into a
match — `SimPlayer` carries no height and no build, because the simulation reads
neither. So the record's body rides in the seed's low bits:

    bits  0-2   body type
    bits  3-7   height, 32 steps across 1.56 m to 2.04 m
    bits  8-10  build, 8 steps
    bits 11-18  a fixed tag, so a seed carrying no body is known to carry none
    bits 19-20  complexion: fair, medium, deep
    bits 21-22  hair family: dark, brown, fair, ginger
    bits 23-24  age band: young, prime, thirties, veteran
    bits 25-28  archetype
    bits 29-31  free entropy

The face still comes off the whole seed — the RNG is seeded with all thirty-two
bits — so the packed fields are as much variety as the free ones. What they
add is that the draw answers to the record: `SimAppearance._apply_record` turns
the bands into a skin tone, a colour, a cut and a moustache.

`WorldLook` writes it and `SimCharacterModel.appearance_for` reads it back. A
seed from `SimSquadGen` or from any build before this carries no tag, and the
figure is derived from the seed the old way.

## What the Blender file has to do

**Units and orientation**

- Metres. The rig is authored at **1.78 m** and the game scales each man by his
  own height over that, so do not build the giant tall — build him *big*.
- Feet at the origin, **facing +Z**. The view sets `rotation.y = -facing + PI/2`
  and the procedural figure's nose points +Z.
- Export `.glb` into `presentation/models/`.

**Materials**

Name each material for the slot it takes:

    shirt   shorts   trim   skin   hair   boot

Colour is set at runtime from the club's kit and the man's skin, so paint them
any placeholder you like — one model serves both sides and every club in the
game. A material named anything else keeps the colour it was authored in, which
is what the eyes want.

**Name, not slot index**, and the index order this section used to ask for
cannot work. A part is one moulding and one colour, so it carries one material,
and glTF drops the slots a mesh does not use — every part would arrive in Godot
with its single surface at index 0 and be painted shirt-coloured. `SLOT_NAMES`
in `character_model.gd` is the map, and a model that uses none of the names
still falls back to the old index order.

**Socks have no slot.** `SimCharacterBuilder` draws them in the first kit
colour, so `art/export.py` gives them the shirt's material, and the separate
sock colour the art kits carry is lost on the way out. Add a seventh slot if a
kit ever wants its own.

**Variants**

- Hair: one mesh per cut, named `Hair0`, `Hair1`, … The seed picks which is
  visible and the rest are hidden. Match `SimCharacterBuilder.HAIR_LIBRARY` for
  order if you want the same man to keep his hair across the two builders.
- Noses: one mesh per shape, `Nose00`, `Nose01`, … in
  `SimCharacterBuilder.NOSE_LIBRARY` order; `art/toy/figure.py` `NOSES` is the
  source. Painted `skin` in the file and repainted with the man's nose colour.
- Moustaches `Moustache00..02` (chevron, walrus, horseshoe) and beards
  `Beard00..02` (goatee, full, stubble), picked by the seed;
  `SimAppearance._face_hair` pairs them. `Beard02` is stubble and carries a
  material named `stubble`, painted between skin and hair at runtime.
- Accessories: `Accessory0` is a headband, and it is the only one. A cap was
  here and came out -- sized to clear a head of hair it covers the whole skull
  in kit colour and reads as a hard hat. No accessory hides it.
- Face: a mesh named `Face` whose albedo texture the game replaces —
  `SimFaceAtlas` draws all five expressions at runtime, so the model needs a
  face-shaped surface and no face art.

**Node names — the part that will bite**

The animation poses nodes by name. A figure the match can animate has to carry
these, and they have to be `Node3D`s that can be rotated:

    Player  Spine  Neck  Head  Face  Brows
    ShoulderL  ShoulderR  ElbowL  ElbowR
    HipL  HipR  KneeL  KneeR  AnkleL  AnkleR

That means **the first models should be rigid parts, not a skinned skeleton** —
which is what the toy register wants anyway. A skinned rig is possible but needs
a poser written against `Skeleton3D` first, and nothing in the view does that
today. Say so before authoring a skeleton, not after.

**Rest angles go in the mesh, never on a node.** `match_view_3d._rotate`
assigns `rotation` outright and wipes anything the file put there the instant a
man moves. The arms hang a few degrees out and the feet turn out because the
geometry is built that way; every joint is square to the world.

`Face` and `Brows` are the two `art/export.py` does not write yet, and both want
a change in `body.py` first. The atlas needs a face-shaped surface carrying **no
face art**, and that head has its eyes and its mouth moulded into it. The brows
are moulded ridges in the hair colour — which is right, and `face_atlas.gd`
stopped drawing them for that reason — but they sit inside the `hair` solid at
the brow, and no bone can tell them from a fringe. Both are missing quietly:
`SimCharacterModel` skips a node it cannot find.

## A model is not a drop-in until it is shaped like one

glTF import hands back a **wrapper**: the file's own `Player` node arrives as a
child of a scene root, so a built figure is one level deeper than a procedural
one. `SimCharacterModel` unwraps it now, and the reason is worth keeping.

`_pose_run` sets the spine's height from `_spine_base`, which looked the spine
up as a **direct child** of the figure. On a procedural figure that works. On a
wrapped model it finds nothing and falls back to zero -- and zero is a perfectly
plausible height for a node to sit at, so nothing errored. Every man in the
match had his torso planted on his hips and no legs to speak of.

Two things let it through, and both are fixed:

- **The parade could not show it.** Its stand pose caches the same meta first,
  with a recursive lookup, so the figure it posed was correct while the match's
  was not. A view that sets up state the other view reads is not an A/B.
- **The pose sheet could not show it either.** `./run.sh poses` built its
  seventeen figures straight off `SimCharacterBuilder`, so the one tool that
  shows every animation state was the one tool that never showed a model. It
  goes through `SimCharacterModel` now, like the match.

The general rule: **reach for a joint with `_joint`, never `get_node_or_null`.**
A recursive cached lookup costs nothing after the first frame and does not care
how deep the figure is.

## Judging one

    ./run.sh parade --seed 7              four men at reading distance, captioned
    ./run.sh parade --seed 7 --shot a.png one frame, no display needed
    ./run.sh view3d --seed 7              the same men in a match

`SimCharacterModel.models_enabled = false` draws everybody procedurally whatever
is on disk, which is the A/B while a model is being judged.

## The sandbox in `art/`

`art/` is where the figure is designed: signed distance fields in Python, meshed
and rendered in Blender, judged against the reference photographs. `art/README.md`
is its own document and this one does not govern how a shape is arrived at.

There are two routes out of it, and the second is the one that ships.

**`./art/model.sh` — built to the count.** `art/toy/` assembles the same man out
of rings at the density he ships at: about 6,000 triangles drawn, several
times that in the file because every hair cut is in there and one is shown.

    ./art/model.sh --body standard              one of the five
    ./art/model.sh --seed 41 --shot /tmp/a.png  one player, and a look at him
    ./art/model.sh --hair 7 --shot /tmp/a.png   which cut the render shows

**`./art/export.sh` — the distance-field figure, cut up and thinned.** Kept
because it is the only route that ships the *moulded* surface, fillets and all,
and because it is the A/B. It writes the same filenames, so whichever ran last
is what the game loads.

**Why the second one lost.** Everything wrong with it was decimation, and none
of it got better with a bigger budget:

- Hems chewed off. A flat circular edge round a smooth tube is the cheapest
  thing for collapse to take, and what it leaves is a skirt with a torn bottom.
- Trims fighting the garments under them. A sock hoop stands 2.8 mm off the
  sock; move both surfaces further than that and they cross.
- Seams tearing. Inside the overlap that keeps a bent joint from opening, both
  parts hold the same stretch of the same surface, and thinned they interleave.
  This one was still visible at 72,000 triangles and gone at 730,000.

Built to the count, all three stop being problems rather than getting smaller. A
hem is a ring of vertices. A hoop is **two bands of the sock's own surface**
wearing the trim material, so there is no second surface to come adrift. And a
seam is authored: the shorts leg runs up inside the seat and the seat is closed
off inside the leg, two surfaces that never touch.

**What `art/toy/` answers that the other never did:** a `Face` patch carrying
the atlas, so eyes, mouth and expression are per player; `Brows` for the game to
pose; and every hair cut in the file. A squad stopped being a clone
army the day those landed.

**Still open in it:**

- **Nothing, on the brows.** They stand proud and they pose. Getting there took
  two numbers rather than one, and the reason is worth keeping: `_pose_brows`
  lays the bars on a **sphere** of `head_r * FACE_SHELL`, and this head is a
  rounded box -- flatter across the face than any sphere through the same
  points. Fit the sphere large enough to clear the skull and the brows climb,
  because the lift is an angle and an angle on a bigger sphere is more
  millimetres; they end up in the hairline. So `FACE_RADIUS` is fitted for
  **height** and `BROW_STAND` pushes the whole shell forward for **clearance**.
  `tools/_brow_probe.gd` prints where a bar actually lands.

  Both stand-offs owe the face's swell (`SKULL`'s `bulge` and `lip`) whatever it
  is worth at their own height and their own distance out from the middle: the
  front of the face moves and the sphere does not, so a swell not paid for is a
  brow or an eye that much less proud. `toy.brow_stand` and `toy.eye_stand` ask
  the skull rather than carrying a fitted number, because a fitted number is one
  to re-fit by hand every time the face changes shape.

  A man with `brow_style` 0 still has none at rest, which is the design: a
  strong expression lends him a plain pair.

- **Shirt numbers.** The only thing in the contract still missing. A model
  probably wants a decal or a texture rather than the digits-as-geometry the
  procedural figure builds, and nothing reads that yet.
- **Five bodies, one shape.** Only `build` separates them -- wider trunk,
  thicker limbs -- and per the owner that is what a giant is: tall, which the
  game does by scaling, and bigger, which that does.


## Still open

- **Animation.** The pose code drives the node names above. Whatever the models
  do, they answer to that list or somebody writes the poser.
- **Shirt numbers.** The procedural figure builds digits as geometry
  (`ShirtNumber`); a model will most likely want a decal or a texture instead,
  and nothing reads that yet.
- **The keeper.** No separate body, no gloves, no different kit slot. He is a
  standard body in the same shirt as everyone else.
