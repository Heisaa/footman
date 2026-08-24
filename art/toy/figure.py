"""The footballer, built once at the density he ships at.

Same man as `art/figure/body.py` -- the proportions here are that file's, which
are the reference photographs' -- but assembled instead of moulded. Every part
is a stack of rings, every part is born in the joint that carries it, and
nothing is cut, split or thinned afterwards. What that buys, in the order it
cost us to learn:

- **A hem is a ring of vertices**, so it stays a hem. Nothing has to guess which
  edge loop matters.
- **A sock hoop is the sock**, two of its own bands wearing the trim material.
  There is no second surface to fight the first, at any distance, ever.
- **A seam between two posed parts is authored.** The shorts leg runs up inside
  the seat and the seat's underside is closed off inside the leg: two surfaces
  that never touch, rather than one surface held by both parts.

The head is the one thing worth reading twice. The face is drawn on a texture
and swapped for expression, and the brows and the nose are moulded -- so the
skull carries no features at all, a `Face` patch laid on the front carries the
atlas, and `Brows` is two bars the game poses. That is where the variety comes
from: one head, five hundred faces. It is a shape arrived at by looking, not a
rule: `PLAN.md` §9.1 has no numbers in it and the references are the spec.
"""

import math

import numpy as np

from . import mesh as M

SHIRT, SHORTS, TRIM, SKIN, HAIR, BOOT, FACE = (
    "shirt", "shorts", "trim", "skin", "hair", "boot", "face")

# Off the references, in fractions of total height. `art/figure/body.py` holds
# the same numbers and the same argument for them.
BOOT_TOP = 0.095
SOCK_TOP = 0.225
SHORTS_HEM = 0.245
SHIRT_HEM = 0.380
CHIN = 0.625
CROWN = 0.950

## Where a man stands, in fractions of trunk half-width. `figure/body.py` holds
## the same two numbers and the argument for them; `figure/rig.py` puts the
## pivots on them. All three have to agree or a joint sits in the middle of
## nothing.
HIP_X = 0.355
ANKLE_X = 0.395

## How far the whole arm is pulled in towards the body. `figure/body.py` holds
## the same number and the argument for it; `figure/rig.py` puts the shoulder
## and elbow pivots on it.
ARM_IN = 0.085

## How far a rolled limb wanders off true, and how big a lump is.
##
## The same thumbing the hair gets (`toy/hair.py:ROLLED`) and rather less of it.
## A head of hair is worked in the hand until it is not true anywhere; an arm is
## rolled out, so it wanders a couple of millimetres and no more. Enough that the
## outline is not a lathe's and not so much that a man looks melted.
##
## Every part is seeded off its own name and side, so the two arms are not
## mirror images of each other -- two identical lumpy arms read as a moulding
## fault rather than as something made by hand.
LIMB_ROLL = 0.058
ROLL_SCALE = 68.0

# How round each thing is in plan: 2 is an ellipse, 4 a rounded rectangle. The
# head is the one that matters -- a ball head is the single easiest way to lose
# the register, and the references are emphatically boxes with the corners off.
HEAD_POWER = 2.6
TRUNK_POWER = 2.4
LIMB_POWER = 2.0

# Segments round a part. The head and the trunk carry the silhouette; a sock
# seen from twenty metres does not.
#
# Up from 16, and `SKULL`'s plan powers are why: a jaw at 3.4 and up has corners
# in its section, which is the point -- a cheek needs an edge for the light to
# turn on -- but sixteen segments render those corners as facets. Twenty costs a
# few hundred triangles on a figure that ships at twenty thousand.
FINE = 20
COARSE = 10

## Segments round a head of hair, and it is deliberately double the head's.
##
## The hairline rises and falls as it goes round the skull -- high at the brow,
## low at the ears, lower at the nape -- so the bottom edge of a shell is a wavy
## curve in three dimensions, and how finely that curve is sampled *is* how
## clean the hairline looks. Sampled twenty times it comes out as teeth, which
## reads exactly like a bad intersection and is not one: three goes at fixing
## the crossing changed nothing, because the crossing was never the problem.
##
## Only one cut is ever drawn, so this is paid once and not seventeen times.
HAIR_SEGMENTS = 32

## Where the game's face maths thinks the head is.
##
## `SimCharacterBuilder` lays the face atlas and poses the brows on a **sphere**
## of `head_r * FACE_SHELL`, and this head is not a sphere -- it is a rounded
## box, flatter across the face than any ball through the same points. Fitted
## too large the brows float a centimetre off the cheek; too small and they sink
## into it. This is the radius, in head half-widths, that leaves them a few
## millimetres proud, which is what a moulded brow ridge is anyway.
##
## The `Face` patch does **not** use it: that is projected onto the skull's own
## surface, because a drawn eye standing off the cheek is the googly-eye failure
## the sandbox already paid for once.
FACE_RADIUS = 1.02

## How far the brow shell stands off the face, in metres.
##
## `_pose_brows` lays the bars on a **sphere** and this head is a rounded box,
## flatter across the face than any sphere through the same points -- so a shell
## sized to touch at the nose is already inside the skull by the time it has
## climbed to the brow, and the squad has no eyebrows. Sizing the sphere up
## instead does clear the skull, but the lift is an angle: on a bigger sphere it
## is more millimetres, and the brows climb into the hairline and disappear
## under the hair. So the radius is fitted for **height** and this handles
## **clearance**, and the two stop fighting.
##
## Measured, not guessed: `tools/_brow_probe.gd` prints where a built brow
## actually lands against the skull's own surface.
##
## **This is the fixed part only.** The face's own swell moves the surface a
## brow stands off, and the sphere the game poses on does not move with it, so
## `brow_stand` adds whatever `SKULL` is worth at the brow's height. Typed in
## here instead it would be a number to re-fit by hand every time the face
## changed shape, which is the mistake this file has made twice.
BROW_STAND = 0.020

## How far the eye bead's node stands off the face, in metres.
##
## The same problem `BROW_STAND` solves and measured the same way. `_pose_eyes`
## lays the beads on a **sphere** of `head_r * FACE_SHELL`, and this head is a
## rounded box that is flatter across the face than any sphere through the same
## points -- so a bead sized to sit on the sphere is a centimetre inside the
## cheek by the time it has moved out to where an eye is, and all that shows is a
## slanted sliver of its inner edge. Standing the whole node forward puts the
## front of the bead a few millimetres proud, which is where the mould has it.
##
## The fixed part only, the same as `BROW_STAND`: `eye_stand` adds the face's
## own swell at the eye row, which is more than the brows get because the swell
## is fullest at the mouth and an eye is nearer it than a brow is.
##
## **Down ten millimetres, and it is the bead's rim that says so, not its pole.**
## Fitted so the *pole* stood a few millimetres proud, the bead is a flat dome --
## a hundred millimetres across and thirty-five deep -- laid on a head that
## curves away from the sphere it is posed on. Its pole was twelve millimetres
## inside the skull and its rim was **twenty-two millimetres outside** at the
## top and the nose side, which from the side is daylight between an eye and a
## face. Sunk ten, the worst of the rim is twelve and the outer edge of the bead
## still stands six millimetres proud, which is what has to be left: at twenty
## the rim is flush and the eye is a sliver.
##
## `tools/_brow_probe.gd` measures the pole. The rim is what to look at.
EYE_STAND = 0.008
FACE_QUAD = 1.5      # SimCharacterBuilder.FACE_QUAD
FACE_SHELL = 1.02    # SimCharacterBuilder.FACE_SHELL
EYE_ROW = 14.6 / 32.0   # SimFaceAtlas.EYE_ROW / GRID


class Figure:
    """Everything a joint has to carry, and the numbers the game needs told."""

    def __init__(self):
        self.parts = {}      # joint name -> [Mesh]
        self.head_r = 0.0

    def put(self, joint, mesh):
        if mesh is not None and mesh.faces:
            self.parts.setdefault(joint, []).append(mesh)
        return mesh

    def tris(self):
        return sum(m.tris() for parts in self.parts.values() for m in parts)


def build(look, quality=1.0):
    """The whole man, in world metres, grouped by the joint that moves him."""
    h = look.height
    w = look.width() * h
    limb = look.limb() * h
    fine = max(8, int(round(FINE * quality)))
    coarse = max(6, int(round(COARSE * quality)))

    fig = Figure()
    _trunk(fig, look, h, w, fine)
    _head(fig, look, h, fine, coarse)
    _arms(fig, look, h, w, limb, coarse)
    _legs(fig, look, h, w, limb, coarse)
    return fig


# --- Trunk -------------------------------------------------------------------

def _trunk(fig, look, h, w, segs):
    # The shirt: straight up from a flat hem, then over the shoulder. The slope
    # is the silhouette -- vertical sides and a domed lid is a postbox, whatever
    # the radius, and the sandbox spent a week finding that out.
    rings = [
        # Out from 0.620. The shirt hem is the widest thing on the trunk below
        # the shoulder in every reference, and it has to be wider than the seat
        # under it or it does not hang over the shorts -- it crosses them.
        M.Ring(h * SHIRT_HEM, w * 0.640, h * 0.088, hard=True),
        M.Ring(h * 0.400, w * 0.642, h * 0.088),
        M.Ring(h * 0.470, w * 0.644, h * 0.086),
        M.Ring(h * 0.520, w * 0.650, h * 0.082),
        # The torso stops at the armpit and **the sleeve is the shoulder**.
        # Tried the other way round -- one tube carrying the shoulder out to the
        # arm -- and a ring wide enough to reach the sleeve has to come back in
        # again above it, which folds the shirt over itself and leaves a notch
        # of daylight at each shoulder. `drop` is still what makes this a
        # shoulder and not a dome: about twenty degrees out to the arm, which is
        # what the reference measures.
        M.Ring(h * 0.556, w * 0.655, h * 0.078),
        M.Ring(h * 0.578, w * 0.720, h * 0.068, drop=h * 0.030),
        # Two rings where the neckline is, not one. `_vee` paints the V into
        # these faces, so the number of rows between the shoulder and the collar
        # **is** how many steps the V has to narrow in -- with one row it can
        # only be a bar, and raising the collar turned it into one.
        M.Ring(h * 0.592, w * 0.640, h * 0.058, drop=h * 0.024),
        M.Ring(h * 0.606, w * 0.520, h * 0.050, drop=h * 0.018),
        M.Ring(h * 0.618, w * 0.400, h * 0.044, drop=h * 0.010),
        # **The collar has to reach the chin.** The references have no neck
        # whatever -- the head sits straight on the shirt -- and the collar
        # finishing at 0.612 against a chin at 0.630 left a band of bare skin
        # nearly two centimetres deep under every jaw, which is a neck however
        # short it is. Taken up to just under the chin, the jaw sits in the
        # collar hole and closes it, which is what a collar does.
        M.Ring(h * 0.626, w * 0.300, h * 0.040, drop=h * 0.006),
    ]
    shirt = M.tube(rings, segs, SHIRT, power=TRUNK_POWER, name="shirt")
    # The neckline, as a **V of the shirt's own faces**. A separate insert has
    # to stand off the chest to be seen and then it is a badge floating in front
    # of a shirt with no neckline in it; recolouring the weave costs nothing and
    # cannot come adrift.
    _vee(shirt, w, h)
    fig.put("Spine", shirt)

    # A stub of neck so the shirt's collar hole is not a hole. The references
    # have no neck whatever and this is not one -- it is the two centimetres the
    # jaw does not reach.
    fig.put("Spine", M.tube([
        M.Ring(h * 0.606, w * 0.21, w * 0.20),
        M.Ring(h * 0.652, w * 0.22, w * 0.21),
    ], segs, SKIN, power=2.6, name="neck"))

    # The shorts, seat only: the legs hang off the hips and run up inside this,
    # so the two never share a surface and the notch between them is real.
    #
    # **In from 0.658, and under the shirt hem.** Two things were wrong with the
    # old width and they were the same thing. The seat was the widest part of
    # the whole figure -- wider than the chest, wider than the shirt hem at
    # 0.620 -- so the shirt did not hang over the shorts, it *crossed* them, and
    # two faceted rounded boxes crossing gave a zigzag right round the waist.
    # And the leg of the shorts, out at the thigh, broke back out through the
    # seat's own side at the hem, which is the vertical crease down each hip.
    # Narrowing the seat is only possible because `HIP_X` brought the legs in;
    # the two go together.
    fig.put("Spine", M.tube([
        M.Ring(h * 0.300, w * 0.608, h * 0.078, hard=True),
        M.Ring(h * 0.318, w * 0.614, h * 0.082),
        M.Ring(h * 0.386, w * 0.616, h * 0.082),
        M.Ring(h * 0.412, w * 0.588, h * 0.078),
        M.Ring(h * 0.424, w * 0.528, h * 0.070),
    ], segs, SHORTS, power=TRUNK_POWER, name="seat"))


def _vee(shirt, w, h):
    """Paints the neckline into the shirt's front faces.

    Measured off the reference: thirty per cent of the shirt's width and a fifth
    of its height, which is half what it was first built at.
    """
    top = h * 0.626
    depth = h * 0.050
    half = w * 0.235
    for i, (face, material, smooth) in enumerate(shirt.faces):
        pts = [shirt.verts[v] for v in face]
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        cz = sum(p[2] for p in pts) / len(pts)
        # Front faces only, and only the ones the neckline actually reaches.
        # Measured off the reference the V is thirty per cent of the shirt's
        # width and a fifth of its height; sized by eye it becomes a shawl.
        if cy >= -h * 0.020 or cz > top or cz < top - depth:
            continue
        # The V narrows as it drops: width is what is left of `half` by the time
        # the neckline has fallen this far.
        reach = half * (1.0 - (top - cz) / depth)
        if abs(cx) <= reach:
            shirt.faces[i] = (face, TRIM, smooth)


# --- Head --------------------------------------------------------------------

# The skull's profile, as (z, scale, forward) in fractions of height and of the
# head's own half-extents. Hair is built off the same numbers, so a cut cannot
# drift off the head it is meant to be on.
SKULL = [
    # **Measured off the mould, not guessed.** These are `art/figure/body.py`'s
    # head -- two rounded boxes and a neck stub smooth-unioned at h*0.05 --
    # solved for its own half-width, its forward offset and the superellipse
    # power of its plan section, at seventeen heights. That figure is what
    # `art/renders/` shows, and the numbers here used to be a nine-row sketch of
    # it that missed the two things the eye actually reads.
    #
    # **The cheeks.** The mould is fullest at 0.745 and stays over 1.00 from
    # 0.720 to 0.805 -- a face wider than the cranium above it. The sketch
    # peaked at exactly 1.00 across 0.745 to 0.800 and gave the chin the
    # difference, so the head came out narrow through the cheek and heavy at the
    # jaw, which is the wrong way round.
    #
    # **The plan.** One power for the whole head was the other miss. The mould
    # is a rounded *box* at the jaw -- 3.4 and up, which is what gives a cheek a
    # corner to catch the light on -- and rounder than a sketch's 2.6 through
    # the cranium, where a boxy section is what makes a head read as square.
    #
    # **A ring's depth is its own number, not its width.** Every row used to
    # scale width and depth together, and one scale cannot make a face: the
    # front of the head came out a dead vertical wall from the brow to the
    # cheek, varying by a centimetre over twenty, and the jaw fell straight back
    # off it in one arc. Head-on that is invisible -- head-on a face reads by
    # its shading -- and in profile it is a plain egg with a button on it. Front
    # and back are set apart now, `depth` giving the ring its own front-to-back
    # size and `forward` sliding it, so this table is the profile itself:
    #
    #     cheek   0.745  out to 1.032, the widest and the furthest forward
    #     eye     0.775  back to 1.014
    #     forehead 0.862 back to 0.952, while the back carries on out to 0.982
    #     chin    0.632  out to 0.805 from 0.598, so there is a jaw under it
    #
    # Most of the forehead's fall is kept above 0.835, because that is where a
    # hairline sits: the shell's front is deliberately buried in the skull down
    # there -- that is what puts a hairline on a forehead instead of a fringe
    # over the eyes -- and taking the skull back out from under it let
    # `M.roughen`'s wobble through as two dark specks of hair on bare skin.
    #
    # The forehead falling away while the back of the skull does not is what
    # makes a head an egg rather than a ball, and the chin is what puts a jaw
    # under the cheek instead of one arc closing off the bottom. Nothing here is
    # more than three per cent of a head-depth except the chin. A profile does
    # not need much; it needs any at all.
    #
    # **There is no brow ridge in this table and there was, for an afternoon.**
    # A bump at 0.805 is the one thing that reads best in a still and it is also
    # exactly where a receding hairline sits: the shell skims the skull there,
    # and eight millimetres of ridge came through the hair as bare scalp on a
    # third of the seventeen cuts. Above the cheek the front recedes all the way
    # to the crown and never turns back. The ridge is the game's job -- it poses
    # two brow bars a good centimetre proud of this surface, which is what a
    # brow is here.
    #
    # **The last column is the face's own mass, and it is not a section.**
    # Everything above shapes rings, and a ring is as flat across its front as
    # its `power` says. So the front of the stack came out a plane: from the
    # brow at 0.992 to the cheek at 1.032, four per cent of a head-depth over
    # twenty centimetres, which is a wall with a nose on it. In profile there
    # was no mouth -- the mouth is drawn on the atlas, and a drawing on a wall
    # is invisible edge-on however well it is drawn.
    #
    # `bulge` pushes the **front** of the ring forward at its middle, fading to
    # nothing at its two widest points (`M.Ring.bulge`). Only the front: the
    # back of the skull, the ears, the sideburns and the hairline at the sides
    # are all where they were, so none of them has to move for a mouth.
    #
    # Fullest at 0.720, which is the upper lip, and falling away above and below,
    # so what it builds is a muzzle: a mouth standing over a jaw that recedes.
    # The brow keeps a third of it and the chin a tenth, because a swell that
    # stops dead is a step.
    #
    # Nine per cent of a head-depth is a little under two and a half centimetres
    # on this head. At seven it was invisible in the game -- the head is over
    # half a metre deep and a mouth is a few pixels of it at match distance --
    # and this is still only the mass; the mouth itself is the column below.
    #
    # **`lip` is the same push over a quarter of the width, and it is the mouth.**
    # `bulge` fades over the whole face because the mass it builds *is* the
    # whole face; a groove cut with that fade is a crease from ear to ear. So
    # the narrow column carries what sits **on** the mass -- the chin, the two
    # lips, and the grooves between them -- and `M.NARROW` is fitted to the
    # drawn mouth: `SimFaceAtlas.MOUTH_STYLES` reaches a quarter of a
    # half-width at its widest, and the fade is down to half at four tenths.
    #
    # **The negatives are the mouth.** A lip that only swells is a swelling; what
    # says mouth in a profile is the line between the lips and the dip under the
    # lower one, and both of those are grooves. 0.708 is where the atlas draws
    # the mouth -- measured by projecting `MOUTH_STYLES`' row 23.2 onto this
    # skull, not guessed -- so the drawn line lands in the moulded crease
    # instead of beside it.
    #
    # Three rows were added for it. A lip is two centimetres of a face and the
    # table's rows were four and a half apart through the mouth, which cannot
    # hold a groove at all; 0.682, 0.708 and 0.734 are the dip, the mouth and
    # the philtrum, and their first four columns are interpolated off the rows
    # that were already there so the head's own shape is untouched.
    #
    # The whole face reads, top to bottom: forehead 0.956, brow 1.033, eye
    # 1.072, the cheek and the nose's base at 1.118, the philtrum back to 1.122,
    # the upper lip out to 1.149, the mouth in at 1.075, the lower lip 1.094,
    # the dip under it 1.020, the chin 1.044, and the jaw away to 0.827.
    # (z, half-width, forward, plan power, half-depth, bulge, lip)
    (0.632, 0.595, -0.145, 2.2, 0.660, 0.010, 0.012),
    (0.650, 0.705, -0.145, 3.4, 0.760, 0.030, 0.032),
    (0.670, 0.843, -0.105, 4.2, 0.865, 0.050, 0.024),
    (0.682, 0.894, -0.081, 4.10, 0.899, 0.060, -0.020),
    (0.695, 0.949, -0.055, 4.0, 0.935, 0.072, 0.032),
    (0.708, 0.976, -0.045, 3.79, 0.958, 0.082, -0.010),
    (0.720, 1.000, -0.035, 3.6, 0.980, 0.090, 0.044),
    (0.734, 1.010, -0.027, 3.38, 0.997, 0.088, 0.010),
    (0.745, 1.018, -0.021, 3.2, 1.011, 0.082, 0.004),
    (0.775, 1.014, -0.003, 2.8, 1.011, 0.058, 0.000),
    (0.805, 1.000, 0.006, 2.5, 1.007, 0.032, 0.000),
    (0.835, 0.998, 0.007, 2.4, 0.999, 0.013, 0.000),
    (0.862, 0.967, 0.015, 2.4, 0.967, 0.004, 0.000),
    (0.885, 0.909, 0.011, 2.45, 0.909, 0.000, 0.000),
    (0.905, 0.829, 0.006, 2.5, 0.829, 0.000, 0.000),
    (0.921, 0.738, 0.003, 2.6, 0.738, 0.000, 0.000),
    (0.934, 0.636, 0.000, 2.7, 0.636, 0.000, 0.000),
    (0.944, 0.526, 0.000, 2.9, 0.526, 0.000, 0.000),
    (0.951, 0.414, 0.000, 3.2, 0.414, 0.000, 0.000),
    (0.956, 0.268, 0.000, 4.0, 0.268, 0.000, 0.000),
]


def skull_power(z):
    """The plan section of the skull at this height, in fractions of height.

    `SKULL` carries a power per row now -- boxy at the jaw, round through the
    cranium -- so anything that has to sit **on** the head has to ask for the
    section there rather than assume one. A ring rounder than the skull dips
    inside it at the diagonals and saws, which is the hairline sawtooth in its
    original form.
    """
    return float(np.interp(z, [row[0] for row in SKULL],
                           [row[3] for row in SKULL]))


def skull_depth(z):
    """The front-to-back half-size of the skull at this height.

    Its own column since the face was given a profile: anything that has to sit
    **on** the head has to ask for the depth rather than reuse the width, or it
    rides a few millimetres inside the skull wherever the two differ -- which at
    the jaw is three centimetres, and a hair rim that dips inside the skull is
    the hairline sawtooth all over again.
    """
    return float(np.interp(z, [row[0] for row in SKULL],
                           [row[4] for row in SKULL]))


def skull_forward(z):
    """How far the ring at this height is slid forward, in head half-depths."""
    return float(np.interp(z, [row[0] for row in SKULL],
                           [row[2] for row in SKULL]))


def skull_bulge(z):
    """The face's broad swell at this height, in head half-depths.

    At the middle of the face only: it fades to nothing by the ring's widest
    points, so anything out at the temple or the ear should ignore it.
    """
    return float(np.interp(z, [row[0] for row in SKULL],
                           [row[5] for row in SKULL]))


def skull_lip(z):
    """The narrow swell -- the chin, the lips and the grooves -- in half-depths.

    Negative wherever the face has a groove in it, which is most of what makes a
    mouth. `M.NARROW` is how far out from the middle it reaches.
    """
    return float(np.interp(z, [row[0] for row in SKULL],
                           [row[6] for row in SKULL]))


def skull_swell(z, u=0.0):
    """Both swells together at this height, `u` sideways in half-widths."""
    return M.swell(skull_bulge(z), skull_lip(z), u)


def skull_front(z, u=0.0):
    """Where the front of the face is, in head half-depths. Negative is forward.

    The nose and the moustache are placed against this rather than against a
    number typed once, because the front of the face is a thing that moves now:
    a swell put on it is a swell that buries anything measured off the old one.
    """
    return skull_forward(z) - skull_depth(z) - skull_swell(z, u)


## Where the game's two posed features sit on this head, as a height in
## fractions of the figure and a sideways offset in head half-widths.
##
## Read off `SimFaceAtlas`: the eye row is the datum the whole face is drawn
## from, the brows sit about three and a half grid units above it, and
## `EYE_STYLES`' gap times `EYE_SPREAD` puts both a third of a half-width out.
## They are here because `brow_stand` and `eye_stand` have to ask the skull how
## far the face has moved at exactly those two places.
EYE_AT = (0.778, 0.333)
BROW_AT = (0.804, 0.333)

## The game's own eye numbers, mirrored so this file can work out where a bead
## lands: `SimCharacterBuilder.EYE_SPREAD` and `EYE_SWELL`, and the middle row
## of `SimFaceAtlas.EYE_STYLES` for the gap and the height. Only the *nominal*
## style is needed -- what they are used for is leaning the whole `Eyes` node,
## which is shared by both beads and every expression.
EYE_SPREAD = 1.12
EYE_SWELL = 1.35
EYE_PROUD = 0.002
EYE_GAP = 6.8
EYE_HIGH = 3.1       # the middle of EYE_STYLES' `ry`, before `EYE_VARY`
GRID = 32.0


def brow_stand(look, h):
    """How far the brow shell stands off the face, in metres, on this figure.

    `BROW_STAND` is the sphere-against-a-box part and never changes. The rest is
    the face's own swell at the brow's height and the brow's own distance out
    from the middle -- a number that moves whenever `SKULL` does, which is why it
    is asked for rather than typed.
    """
    return BROW_STAND + look.head_d * h * skull_swell(*BROW_AT)


def eye_stand(look, h):
    """The same, for the eye beads. `EYE_STAND` is the fixed part."""
    return EYE_STAND + look.head_d * h * skull_swell(*EYE_AT)


def skull_face(look, h, z, u):
    """Where the front of the face is, in metres, at this height and offset.

    `u` is sideways in head half-widths. `skull_front` answers the same question
    down the middle of the face; this one answers it out where an eye is, which
    is a different number on a rounded box and a different one again once the
    face has a swell on it.
    """
    hw, hd = look.head_w * h, look.head_d * h
    scale = float(np.interp(z, [row[0] for row in SKULL],
                            [row[1] for row in SKULL]))
    rx, ry = hw * scale, hd * skull_depth(z)
    e = skull_power(z)
    x = u * hw
    t = max(0.0, 1.0 - abs(x / rx) ** e) ** (1.0 / e)
    return -ry * t + hd * skull_forward(z) - hd * skull_swell(z, x / rx)


def eye_node(look, h):
    """`(tilt, dy, dz)` for the `Eyes` node: lean it, then put it back.

    **A bead is aimed along a radius and a face is not a sphere.** The game
    poses each bead on a shell centred at the eye row, so its axis comes
    straight out of the middle of the head -- and the face at the eye row is
    leaning back as it climbs to the brow. The bead is a wide flat dome, so that
    mismatch shows at its **rim**: measured, the top of the rim stood six to
    eight millimetres outside the skull while the bottom was twenty inside,
    which is an eye with daylight over it and its chin sunk in a cheek. Sinking
    it further only trades one for the other -- the whole rim goes in and the
    eye becomes a sliver.

    The lean is the **secant** of the face over the bead's own height, not the
    tangent at its centre: the bead reaches a third of a head-width up and down,
    over which the face falls back three times what the slope at the eye row
    says. About fourteen degrees, and it halves the rim's spread.

    The lean is about the node's origin, which sits a third of a metre behind
    the face -- so on its own it swings both eyes down the cheek. `dy` and `dz`
    put them back. Both beads take the same correction because they differ only
    in `x`, which a lean about `x` does not touch.
    """
    hw = look.head_w * h
    eye_z = h * (CHIN + CROWN) * 0.5 - look.head_h * h * 0.06
    # How far the bead reaches up and down, in metres.
    reach_z = hw * FACE_RADIUS * FACE_QUAD / GRID * EYE_HIGH * EYE_SWELL
    lo = skull_face(look, h, (eye_z - reach_z) / h, EYE_AT[1])
    hi = skull_face(look, h, (eye_z + reach_z) / h, EYE_AT[1])
    tilt = -math.atan2(hi - lo, 2.0 * reach_z)

    head_r = hw * FACE_RADIUS
    radius = head_r * FACE_SHELL
    yaw = ((16.0 + EYE_GAP * EYE_SPREAD) / GRID - 0.5) * FACE_QUAD / FACE_SHELL
    py = -math.cos(yaw) * (radius + EYE_PROUD)
    return tilt, py - py * math.cos(tilt), -py * math.sin(tilt)


def skull_rings(look, h, scale=1.0, lift=0.0, back=0.0, first=0, squash=1.0):
    hw = look.head_w * h * scale
    hd = look.head_d * h * scale
    base = h * SKULL[first][0]
    out = []
    for z, s, cy, power, d, bulge, lip in SKULL[first:]:
        ring = M.Ring(base + (h * z - base) * squash + lift,
                      hw * s, hd * d,
                      cy=hd * cy + back, power=power)
        ring.bulge = hd * bulge
        ring.lip = hd * lip
        out.append(ring)
    return out


def _head(fig, look, h, fine, coarse):
    hw = look.head_w * h
    hd = look.head_d * h
    mid = h * (CHIN + CROWN) * 0.5

    # Skull and jaw in one stack. The jaw is narrower and set a little forward,
    # which is what a jaw is; a single box is a brick and a single ball is an
    # egg, and the references are neither.
    fig.put("Head", M.tube(skull_rings(look, h), fine, SKIN,
                           power=HEAD_POWER, name="skull"))

    # Ears. Two flat tabs and the head reads from the side, which nothing else
    # on it does.
    #
    # **A tab, and half of it buried.** As round as it was deep and set at 0.99
    # of the skull's own width, it was a bead balanced on the side of the head:
    # from behind it reads as a separate ball, because that is what it is --
    # only a tenth of it was inside the skull, and this route cannot fillet the
    # rest away. Pushed in to 0.94 it is mostly buried; taller than it is deep
    # it is an ear rather than a knob.
    # **It has to clear the hair, not just the skull.** At 0.94 with a tenth of
    # a head-width of reach it finished a hair inside the shell, so on a cut
    # whose hairline runs below it the tip came through the hair as a single
    # skin-coloured speck -- an ear half swallowed, which is worse than either
    # showing or hidden. `art/figure/body.py` puts it at 1.08 for this reason:
    # on the references an ear sticks out past the cut.
    for side in (-1.0, 1.0):
        fig.put("Head", M.blob((side * hw * 0.98, -hd * 0.05, h * 0.788),
                               (hw * 0.15, hd * 0.14, hd * 0.27),
                               coarse, coarse // 2, SKIN, name="ear"))

    # The nose is geometry, never a drawn mark: at this size a drawn one is a
    # smudge and a bump catches the light and does the whole job.
    # **Bigger, and pressed on rather than moulded in.** A clay nose is a ball
    # of the stuff squeezed onto the face and smoothed at the join -- Wallace's
    # is a third of his face -- where a vinyl one is a button that only has to
    # catch the light. Half again on every axis and further out.
    # Wider than it is long, and rounder than it is tall. At 1.10 deep by 1.20
    # high it came out as a beak: a cone pointing at the camera, which is the
    # one nose shape the reference never has. A ball squashed slightly flat is
    # what a thumb leaves.
    # **A nose is judged in profile and sized from the front.** At a ball buried
    # to its centre in the face it stood five centimetres off a head fifty-three
    # deep -- a tenth -- and in profile that is a button on an egg. Longer, not
    # bigger: the depth is what shows from the side, the width and the height
    # are what show from the front, and the front view was already right.
    # **Buried to its centre in the face, wherever the face now is.** At a
    # number typed once it was buried to its centre in the face as the face was
    # then; the swell in `SKULL`'s last column moved that surface forward by a
    # centimetre and a half, and a nose that does not move with it is a nose a
    # centimetre and a half shorter. `skull_front` is where the face is.
    nose = look.nose * h * 1.35
    fig.put("Head", M.blob((0.0, hd * skull_front(0.760), h * 0.760),
                           (nose * 1.05, nose * 1.18, nose * 1.00),
                           coarse, coarse // 2, SKIN, name="nose"))

    fig.head_r = hw * FACE_RADIUS
    fig.put("Head", _face(look, h, fine))


def _face(look, h, segs):
    """The patch the atlas is drawn on, laid on the skull's own surface.

    The parameterisation is `SimCharacterBuilder._face_shell`'s exactly -- the
    same arc-length yaw and pitch off the same eye row, the same `(u, v)` -- so
    a face drawn for the procedural figure lands here unchanged. Only the radius
    differs: each point is dropped onto the superellipse the skull actually is,
    rather than onto the sphere the maths assumes, because a fixed depth is how
    you get googly eyes.
    """
    hw = look.head_w * h
    hd = look.head_d * h
    head_r = hw * FACE_RADIUS
    size = head_r * FACE_QUAD
    radius = head_r * FACE_SHELL
    # **Twice as many rows as columns, because the mouth is a horizontal thing.**
    # The patch is a chord between its own vertices, and at sixteen rows it
    # spanned the whole mouth in two of them -- a flat plate bridging the crease
    # the skull now has, with the drawn line floating a centimetre above the
    # groove it is meant to sit in. Columns are left alone: nothing on this face
    # is narrow enough sideways to need them.
    rows, cols = max(12, (segs - 4) * 2), max(6, segs - 4)
    v_max = 0.86
    eye_z = h * (CHIN + CROWN) * 0.5 - look.head_h * h * 0.06

    verts, uvs = [], []
    for j in range(rows + 1):
        v = v_max * j / rows
        pitch = (EYE_ROW - v) * size / radius
        for i in range(cols + 1):
            u = i / cols
            yaw = (u - 0.5) * size / radius
            # A direction in the head's own frame, then out to the skull.
            dx = math.sin(yaw) * math.cos(pitch)
            dy = -math.cos(yaw) * math.cos(pitch)
            dz = math.sin(pitch)
            verts.append(_onto_skull(look, h, eye_z, (dx, dy, dz)))
            uvs.append((u, 1.0 - v))
    mesh = M.Mesh("Face")
    mesh.uvs = uvs
    stride = cols + 1
    faces = []
    for j in range(rows):
        for i in range(cols):
            a = j * stride + i
            faces.append([a, a + stride, a + stride + 1, a + 1])
    mesh.add(verts, faces, FACE, smooth=True)
    return mesh


def _onto_skull(look, h, eye_z, direction):
    """Walks out from the eye row until the skull's surface is reached.

    Bisection rather than algebra: the skull is a stack of rings with a power
    that changes up it, so there is no closed form, and forty halvings of a
    twenty-centimetre interval is exact to a fraction of a millimetre.
    """
    lo, hi = 0.0, look.head_w * h * 2.5
    for _ in range(40):
        t = (lo + hi) * 0.5
        p = (direction[0] * t, direction[1] * t, eye_z + direction[2] * t)
        if _inside_skull(look, h, p):
            lo = t
        else:
            hi = t
    t = lo + h * 0.0012      # a hair proud, so the drawing is never buried
    return (direction[0] * t, direction[1] * t, eye_z + direction[2] * t)


def _inside_skull(look, h, p):
    hw = look.head_w * h
    hd = look.head_d * h
    # The skull's own profile, as a function of height. Only the part the face
    # covers matters, so this is the middle of the stack in `_head`.
    z = p[2] / h
    scale = np.interp(z, [row[0] for row in SKULL], [row[1] for row in SKULL])
    cy = skull_forward(z) * hd
    rx, ry = hw * scale, hd * skull_depth(z)
    if rx <= 0.0 or ry <= 0.0:
        return False
    e = skull_power(z)
    # Undo the face's swell before asking the section, because the section does
    # not know about it: `M.tube` pushes the front of the ring forward by a
    # fade in `x`, and the front of the ring is exactly where a face patch
    # lands. Left out, the whole atlas is projected onto the skull the swell was
    # laid on -- a centimetre and a half inside the head it is drawn on, which
    # is a man with no face.
    q = p[1] - cy
    if q < 0.0:
        q += hd * skull_swell(z, p[0] / rx)
    return (abs(p[0] / rx) ** e + abs(q / ry) ** e) <= 1.0


def extras(look, h, segs, coarse):
    """[(name, Mesh)] for the parts the seed switches on and off.

    `Moustache` is shown or hidden and `Accessory0` is the headband, which
    `SimCharacterModel._choose_variant` shows or does not. Both hang off `Head`,
    so they turn with it.
    """
    hw = look.head_w * h
    hd = look.head_d * h
    hh = look.head_h * h
    out = []

    # **Two lobes, not a bar.** One shape under a nose is a moustache sticker;
    # two with a dip between them has a shape. Wide and shallow: deeper than this
    # a dark curved mass sits where a mouth belongs and the man is scowling
    # whoever he is. And it has to stand *proud* -- set at the skull's own depth
    # only its two widest points showed, as a pair of dark dots either side of
    # the mouth, like a smirk drawn on.
    # **Under the nose, not on the mouth.** At 0.729 it landed across the drawn
    # mouth, so the atlas's mouth came out from under it as a black bead and the
    # pair read as a beak. The reference wears it tucked up against the nose's
    # underside with the mouth clear below, and that is 0.745 -- and wider, too:
    # a moustache narrower than the nose is a smudge.
    # **Two lobes a side, and the outer one hangs.** One lobe a side is a bar,
    # and a bar under a nose is a smear of dark however wide it is. What the
    # reference wears is a handlebar: thick where it meets the nose and drooping
    # away past the corners of the mouth, so the outline has a fall in it. That
    # fall is the whole shape -- it is what stops a moustache reading as an
    # upper lip in shadow.
    #
    # Half again as big as the flat bar it replaces. Clay is rolled on in
    # quantity; a moustache you have to look for is a moustache nobody drew.
    # **Under the nose, and the nose is the thing that moved.** Placed at 0.745
    # it was inside the nose rather than below it -- that ball grew by half when
    # the figure went to clay and now reaches down to 0.725, near enough to the
    # mouth that there is no gap left to sit in. All that showed of a moustache
    # was two dark specks either side of a nostril.
    #
    # So it hangs off the nose's underside instead, and it is wider than the
    # nose so that it clears it: the inner pair tuck up against it, the outer
    # pair sit further out and lower, and the fall between them is the shape.
    tache = M.Mesh("Moustache")
    for side in (-1.0, 1.0):
        tache.merge(M.blob((side * hw * 0.185, hd * skull_front(0.7285),
                            h * 0.7285),
                           (hw * 0.205, hd * 0.100, hh * 0.088),
                           coarse, max(4, coarse // 2), HAIR, name="tache"))
        # **Barely set back, and against the face's own front.** Set back at
        # 0.92 on the reasoning that the face curves away out there, these came
        # out as two loose diamonds with skin between them and the moustache. It
        # hardly curves away: the swell in `SKULL` fades by a tenth over the
        # width a moustache covers, so a lobe set back by more than that is a
        # lobe buried in the cheek. Both pairs hang off `skull_front` now, so
        # neither is left behind when the face moves.
        tache.merge(M.blob((side * hw * 0.390,
                            hd * (skull_front(0.7165) + 0.011), h * 0.7165),
                           (hw * 0.165, hd * 0.090, hh * 0.108),
                           coarse, max(4, coarse // 2), HAIR, name="tache"))
    out.append(("Moustache", tache))

    # The headband, cut to the skull at the height it is worn. A ring of one
    # radius round a head that is narrowing is a halo hanging off the forehead.
    # **Above the brows and over the hairline**, which is where a headband is
    # worn -- it pushes the hair up. Set at the skull's own mid-height it lands
    # across the brows and the man is blindfolded.
    # **Over the hair, not under it.** A headband is worn on top of a head of
    # hair and the shells are 1.10 of the skull, so anything sized to the skull
    # is swallowed.
    # Sized to sit just off the **skull**, and it follows the skull's own curve
    # rather than running straight round. At 1.14, out where it would clear a
    # head of hair, it is a plank laid across a bald man's forehead. Under the
    # hair on a man who has some is the lesser wrong, and is also what a
    # headband does.
    band = M.tube([M.Ring(h * 0.822, hw * 1.055, hd * 1.055),
                   M.Ring(h * 0.840, hw * 1.075, hd * 1.075),
                   M.Ring(h * 0.858, hw * 1.060, hd * 1.060),
                   M.Ring(h * 0.872, hw * 1.010, hd * 1.010)],
                  segs, SHIRT, power=skull_power(0.845),
                  cap_lo=False, cap_hi=False, name="Accessory0")
    out.append(("Accessory0", band))

    # The cap came out. Sized to clear a head of hair it is a dome over the whole
    # skull in kit colour, and at any distance that is a hard hat rather than a
    # cap -- no reference wears one, and the headband is the accessory that
    # survives. `Accessory1` is deliberately not written: the game's
    # `ACCESSORY_INDEX` no longer asks for it.
    return out


# --- Arms --------------------------------------------------------------------

def _arms(fig, look, h, w, limb, segs):
    for side in (-1.0, 1.0):
        tag = "L" if side < 0.0 else "R"
        shoulder = np.array([side * w * (0.68 - ARM_IN), 0.0, h * 0.545])
        arm_top = np.array([side * w * (0.74 - ARM_IN), 0.0, h * 0.515])
        wrist = np.array([side * w * (0.90 - ARM_IN), 0.0, h * 0.295])
        elbow = arm_top + (wrist - arm_top) * 0.56
        hand = np.array([side * w * (0.92 - ARM_IN), 0.0, h * 0.258])

        # Upper arm, from inside the shoulder down past the elbow: a limb is
        # built long at both ends and buried in its neighbours, which is what
        # keeps a bend from opening.
        upper = M.tube([
            M.Ring(0.0, limb * 0.94, limb * 0.94),
            M.Ring(0.30, limb * 0.93, limb * 0.93),
            M.Ring(1.06, limb * 0.88, limb * 0.88),
        ], segs, SKIN, power=LIMB_POWER, name="upper")
        M.roughen_axis(upper, LIMB_ROLL, seed=11.0 * side, scale=ROLL_SCALE)
        upper.transform(M.along(shoulder + (arm_top - shoulder) * 0.2, elbow))
        fig.put("Shoulder" + tag, upper)

        # The sleeve, with a flat hem and its cuff as two of its own bands. The
        # widest thing on a footballer is his arm, not his sleeve: at limb*1.8
        # it is a puff sleeve and wrong in every reference.
        sleeve = M.tube([
            M.Ring(-0.30, limb * 1.16, limb * 1.16),
            M.Ring(-0.14, limb * 1.42, limb * 1.42),
            M.Ring(0.16, limb * 1.40, limb * 1.40),
            M.Ring(0.38, limb * 1.28, limb * 1.28),
            M.Ring(0.60, limb * 1.20, limb * 1.20),
            M.Ring(0.68, limb * 1.19, limb * 1.19, material=TRIM),
            M.Ring(0.74, limb * 1.18, limb * 1.18, material=TRIM, hard=True),
        ], segs, SHIRT, power=LIMB_POWER, name="sleeve")
        # Less than the bare arm gets. A sleeve is cloth over clay, and its hem
        # is one of the three crisp edges the kit is made of -- worked as hard
        # as an arm it goes from a hem to a frill.
        M.roughen_axis(sleeve, LIMB_ROLL * 0.55, seed=23.0 * side, scale=ROLL_SCALE)
        sleeve.transform(M.along(shoulder, elbow))
        fig.put("Shoulder" + tag, sleeve)

        # **The forearm swells into the hand.** It used to taper to limb*0.80 and
        # stop, with a mitten of limb*1.10 dropped on the end of it -- a step of
        # thirty per cent at the wrist, and this route has no fillet to hide it,
        # so the hand read as a ball stuck on an arm. Widening the last third of
        # the forearm to meet the mitten turns the step into a swell, which is
        # what a wrist is.
        fore = M.tube([
            M.Ring(-0.30, limb * 0.88, limb * 0.88),
            M.Ring(0.20, limb * 0.86, limb * 0.86),
            M.Ring(0.62, limb * 0.88, limb * 0.88),
            M.Ring(0.86, limb * 0.98, limb * 0.98),
        ], segs, SKIN, power=LIMB_POWER, name="fore")
        M.roughen_axis(fore, LIMB_ROLL, seed=37.0 * side, scale=ROLL_SCALE)
        fore.transform(M.along(elbow, hand))
        fig.put("Elbow" + tag, fore)

        # A mitten, with a thumb. No fingers -- the reference has none, and the
        # thumb is the whole of what says hand rather than end of an arm.
        # A blob is already where it belongs, so it is worked about its own
        # middle rather than about an axis.
        fig.put("Elbow" + tag, M.roughen(M.blob(
            (hand[0], 0.0, hand[2]), (limb * 1.06, limb * 0.98, limb * 1.22),
            segs, segs // 2, SKIN, name="hand"),
            LIMB_ROLL, (hand[0], 0.0, hand[2]), seed=53.0 * side,
            scale=ROLL_SCALE))
        # Down the side of the mitten and forward, not sitting on top of it.
        # Level with the middle of the hand it was a second knuckle.
        fig.put("Elbow" + tag, M.blob(
            (hand[0] - side * limb * 0.66, -limb * 0.42, hand[2] + limb * 0.08),
            (limb * 0.38, limb * 0.46, limb * 0.62),
            max(6, segs - 2), max(4, segs // 2 - 1), SKIN, name="thumb"))


# --- Legs --------------------------------------------------------------------

def _legs(fig, look, h, w, limb, segs):
    for side in (-1.0, 1.0):
        tag = "L" if side < 0.0 else "R"
        hip = np.array([side * w * HIP_X, 0.0, h * 0.305])
        ankle = np.array([side * w * ANKLE_X, 0.0, h * BOOT_TOP])
        knee = hip + (ankle - hip) * 0.548

        # Thigh, bare between the shorts and the sock.
        # Slimmer, because it has to fit inside a leg of the shorts that now
        # fits inside the seat. It is the bare stretch between the hem and the
        # sock top and nothing else stands next to it, so nobody can see the
        # difference except by what stopped breaking through.
        thigh = M.tube([
            M.Ring(-0.20, limb * 1.14, limb * 1.14),
            M.Ring(0.30, limb * 1.12, limb * 1.12),
            M.Ring(1.10, limb * 1.08, limb * 1.08),
        ], segs, SKIN, power=LIMB_POWER, name="thigh")
        M.roughen_axis(thigh, LIMB_ROLL, seed=67.0 * side, scale=ROLL_SCALE)
        thigh.transform(M.along(hip, knee))
        fig.put("Hip" + tag, thigh)

        # The leg of the shorts: up inside the seat, and hanging lower than it,
        # which is what puts a notch between the legs rather than a skirt.
        #
        # More segments than the rest of the leg gets: the hem is a hard ring
        # and it is on the silhouette, so at ten segments a rounded box comes
        # out of it as a visible stagger of flats rather than a line.
        # **Widest at the hem.** It tapered towards the bottom, which is the
        # wrong way round twice over: a leg opening is the widest part of a
        # pair of shorts, and the thigh inside is at its fattest exactly where
        # the shorts were at their narrowest -- so the bare leg broke out
        # through the outer side of each hem, which is the skin showing at the
        # bottom corners of the shorts. Flared instead, with the thigh trimmed
        # to match, and there is a centimetre of daylight all the way round.
        leg = M.tube([
            M.Ring(h * SHORTS_HEM, w * 0.286, w * 0.276, hard=True),
            M.Ring(h * 0.262, w * 0.282, w * 0.272),
            M.Ring(h * 0.352, w * 0.278, w * 0.268),
        ], max(segs, 14), SHORTS, power=2.2, name="shorts_leg")
        leg.translate((side * w * 0.310, 0.0, 0.0))
        fig.put("Hip" + tag, leg)

        # Sock: a flat top, level on both legs, and its hoops are two of its own
        # bands. Nothing is laid on it, so nothing can come adrift from it.
        # **Fat hoops, and at most two.** Three bands 0.075 of the sock deep are
        # pinstripes: at match distance they close up into one grey smear and at
        # parade distance they read as a bandage. Every reference wears one or
        # two of them and they are nearly twice as deep as the gap between, so
        # the band is the sock and the gap is the stripe rather than the other
        # way round. Hung off a fixed top instead of a fixed bottom, so one hoop
        # and two sit in the same place on the shin.
        # Trimmed with the sock. Two bands 0.140 deep were a third of a sock
        # that has since come down under the knee, and they crowded it.
        band, gap = 0.108, 0.072
        hoop = max(0, min(look.sock_hoops, 2))
        rings = [M.Ring(0.02, limb * 1.27, limb * 1.27),
                 M.Ring(0.10, limb * 1.32, limb * 1.32),
                 M.Ring(0.24, limb * 1.38, limb * 1.38)]
        at = 0.84 - band - (hoop - 1) * (band + gap) if hoop else 0.34
        for _ in range(hoop):
            rings.append(M.Ring(at, limb * 1.40, limb * 1.40))
            rings.append(M.Ring(at + band, limb * 1.41, limb * 1.41, material=TRIM))
            at += band + gap
        rings.append(M.Ring(min(at + 0.06, 0.94), limb * 1.42, limb * 1.42))
        rings.append(M.Ring(1.0, limb * 1.42, limb * 1.42, hard=True))
        sock = M.tube(rings, segs, SHIRT, power=LIMB_POWER, name="sock")
        # Built up the leg from the ankle so the hoops sit near the top.
        #
        # **Lower and tighter.** Pulled to 0.62 of the way from ankle to hip the
        # sock top was over the knee, and at limb*1.52 it was the fattest thing
        # on the leg -- fatter than the thigh above it, which is a football sock
        # nobody wears. 0.575 puts the top just under the knee, and a tenth off
        # every radius leaves the shin slimmer than the thigh, the way round the
        # renders have it.
        # Like the sleeve: cloth, and its flat top is a hem worth keeping flat.
        M.roughen_axis(sock, LIMB_ROLL * 0.55, seed=83.0 * side, scale=ROLL_SCALE)
        sock.transform(M.along(ankle - (knee - ankle) * 0.06,
                               ankle + (hip - ankle) * 0.575))
        fig.put("Knee" + tag, sock)

        fig.put("Ankle" + tag, _boot(side, w, h, limb, segs))


## How far the sole stands off the ground, and it is the length of a stud.
SOLE = 0.018


def _boot(side, w, h, limb, segs):
    """A wedge with the heel under the ankle, a broad blunt toe and a flat sole.

    The studs matter more than they sound: cut flat the boot sits on the floor
    like a clog, and on studs it stands with daylight and a shadow under the
    sole, which is most of what says football boot.

    **The sole has to be flat or the studs float.** This is built lying down --
    the rings run heel to toe, so a ring's half-depth is the boot's *height*
    there and its `cy` is how far up or down that section sits. Left at zero,
    each section hung from its own centre, so the underside followed the top:
    the boot was 5 cm deep at the collar and 2.5 cm at the toe, its sole sloped
    by a centimetre over its length, and studs all cut to one length reached it
    in one place and hung in the air everywhere else. Hanging every section from
    a **common underside** costs nothing and is what a sole is.
    """
    x = side * w * ANKLE_X
    top = h * 0.052
    sole = h * SOLE

    def ring(at, rx, ry, material=None):
        # `cy` becomes -z when the boot is stood up, so this puts the bottom of
        # every section on `sole` whatever its depth.
        return M.Ring(at, rx, ry, cy=top - sole - ry, material=material)

    rings = [
        ring(-h * 0.130, limb * 0.66, limb * 0.44),
        ring(-h * 0.100, limb * 1.16, limb * 0.62),
        ring(-h * 0.070, limb * 1.32, limb * 0.74),
    ]
    # The stripes, as bands of the boot's own surface. Three of them, and they
    # stop before the ankle collar: carried round that too, four bands read as a
    # bandage rather than as stripes on a boot.
    at = -h * 0.058
    for _ in range(3):
        rings.append(ring(at, limb * 1.34, limb * 0.80))
        rings.append(ring(at + h * 0.009, limb * 1.35, limb * 0.82,
                          material=TRIM))
        at += h * 0.021
    rings += [
        ring(h * 0.004, limb * 1.34, limb * 0.92),
        ring(h * 0.032, limb * 1.26, limb * 0.98),
        ring(h * 0.054, limb * 1.10, limb * 0.94),
    ]
    # Built lying down: the rings run front to back, so `power` is the section
    # of the foot and the last ring is the ankle collar.
    boot = M.tube(rings, segs, BOOT, power=2.6, name="boot")
    boot.transform(M.rotation_x(math.radians(-90.0)))
    boot.transform(M.translation((x, 0.0, top)))
    # From the ground up **into** the boot, not up to where the sole happens to
    # be. A stud that stops at the sole is a stud that stops short of it the
    # moment anything about the boot moves; buried, the join can never open and
    # the extra is inside a solid the same colour.
    for at_y, spread in ((-h * 0.100, 0.55), (-h * 0.056, 0.62), (h * 0.026, 0.44)):
        for out in (-1.0, 1.0):
            boot.merge(M.tube([
                M.Ring(0.0, limb * 0.26, limb * 0.26, hard=True),
                M.Ring(sole, limb * 0.30, limb * 0.30),
                M.Ring(sole + h * 0.012, limb * 0.30, limb * 0.30),
            ], max(5, segs // 2), BOOT, power=2.0, name="stud")
                .translate((x + out * limb * spread, at_y, 0.0)))
    return boot
