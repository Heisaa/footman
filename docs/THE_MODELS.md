# The models

What a built figure has to look like from the game's side, so a model made in
Blender can replace the procedural one without anything else changing.

`presentation/character_model.gd` is the seam. It reads the man's body out of
his `appearance_seed`, and either instantiates a model for that body or hands the
job to `SimCharacterBuilder`, which is the primitives the game has always drawn.
**With no models on disk everything works exactly as before**, so the models can
land one at a time and a half-finished library breaks nothing.

## The five bodies

Five silhouettes, not a continuous range: five bodies with height scaled on top
is a week of work and a morph target for every man is a month of it.

| Body | Who gets it | File |
|---|---|---|
| `standard` | most of a squad | `presentation/models/body_standard.glb` |
| `giant` | archetype `giant`, or 1.94 m and over | `body_giant.glb` |
| `sprite` | archetype `sprite`, or 1.66 m and under | `body_sprite.glb` |
| `heavy` | build 0.66 and over | `body_heavy.glb` |
| `lean` | build 0.34 and under | `body_lean.glb` |

`WorldLook.body_type_for` is the rule and `WorldLook.type_name` is the spelling
in the filename. Drop in `body_giant.glb` alone and the giants use it while
everybody else stays procedural, which is also how to judge one against the
other.

## How the body reaches the model

`appearance_seed` is the **only** thing about a man's looks that travels into a
match — `SimPlayer` carries no height and no build, because the simulation reads
neither. So the record's body rides in the seed's low bits:

    bits  0-2   body type
    bits  3-7   height, 32 steps across 1.56 m to 2.04 m
    bits  8-10  build, 8 steps
    bits 11-18  a fixed tag, so a seed carrying no body is known to carry none
    bits 19-31  free entropy: hair, skin, face, nose, accessory

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

Six slots, in this order, on every mesh that takes a game colour:

    0 shirt   1 shorts   2 trim   3 skin   4 hair   5 boot

Colour is set at runtime from the club's kit and the man's skin, so paint them
any placeholder you like — one model serves both sides and every club in the
game. A mesh with fewer slots keeps its authored colours for the rest.

**Variants**

- Hair: one mesh per cut, named `Hair0`, `Hair1`, … The seed picks which is
  visible and the rest are hidden. Match `SimCharacterBuilder.HAIR_LIBRARY` for
  order if you want the same man to keep his hair across the two builders.
- Accessories: `Accessory0` is a headband, `Accessory1` a cap. No accessory
  hides both.
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

It governs what comes out. Two things have to change in that pipeline before a
figure it produces can be a figure the game builds:

**1. Height and build come from the record, not from the seed.**
`art/figure/cast.py:from_seed` draws its own height — a bell round 1.79 with a
14% chance of a tail — and its own build. The game does not: `WorldGen` decides
those, and packs them into the seed with the body type (see above). A render is
only the man the game will show if `from_seed` reads them back instead of
drawing them. That is a dozen lines of Python: the same masks, the same tag
byte, and the existing draw kept for a seed that carries no body. Everything
else `from_seed` invents — skin, hair, moustache, brows, nose, eye gap — stays
invented, because the record has no opinion about any of it and the free bits
are there for exactly that.

**2. What ships is a `.glb`, not a render.** `art/README.md` says nothing here
ships and that a winning shape is carried back into GDScript by hand. That was
the only route when the game could draw nothing but primitives. Now
`SimCharacterModel` will instantiate `presentation/models/body_<type>.glb` the
moment one exists, so the mesher can export five files instead of a person
re-deriving five silhouettes in another language. What an export has to carry is
the whole of this document: the axes, the 1.78 m reference, the six material
slots left unpainted, the hair and accessory variants, and above all the node
names — because a single fused mesh, however good it looks in a render, cannot
be animated by anything in the view today.

Neither is urgent while the shape is still being judged. Both are what "finished"
means.

## Still open

- **Animation.** The pose code drives the node names above. Whatever the models
  do, they answer to that list or somebody writes the poser.
- **Shirt numbers.** The procedural figure builds digits as geometry
  (`ShirtNumber`); a model will most likely want a decal or a texture instead,
  and nothing reads that yet.
- **The keeper.** No separate body, no gloves, no different kit slot. He is a
  standard body in the same shirt as everyone else.
