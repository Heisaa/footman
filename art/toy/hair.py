"""The cuts, one mesh each, all in the file and one of them shown.

`SimCharacterBuilder.HAIR_LIBRARY` is the list and the order, because a man has
to keep his hair whichever builder drew him. Every row is the same idea: a shell
a tenth or more larger than the skull, pushed back, plus pieces. Hair that
merely skims the head is paint on a scalp -- the shell is where the volume comes
from, and the difference between a full cut and an afro is what is added on top
of it, never how big it is.

**The names are padded to two digits.** `SimCharacterModel._choose_variant`
sorts the variants by name as text, so `Hair10` would land between `Hair1` and
`Hair2` and eighteen men would wear eight of the wrong cuts.

The shell is built off `figure.SKULL`, the skull's own profile, so a cut cannot
drift off the head it belongs to when the head changes shape.
"""

from . import figure as F
from . import mesh as M

HAIR = "hair"

## How far a rolled shell wanders off true, as a fraction of its own radius, and
## how big a lump is. `M.roughen` has the argument; these two numbers are the
## whole of the clay register in the hair.
ROLLED = 0.060
## Radians per metre: a lump about ten centimetres across on a head half a metre
## wide. This was 3.1 in the first pass, which put the entire figure inside one
## lobe of the noise and displaced nothing -- the lumpiness that showed was all
## normal map. `M._lumps` says why the mistake is silent.
ROLL_SCALE = 62.0

# The cuts. Row for row with `presentation/character_builder.gd:HAIR_LIBRARY` --
# the **index** is the cut and has to agree, because a man keeps his hair across
# the two builders. The parameters do not have to agree and no longer do.
#
# `r`, `up` and `back` are the library's: how big the shell is, how far it is
# lifted, and how far back it sits. The rest are this file's, and they are what
# stopped eighteen cuts being one shell with the hairline in eighteen places:
#
#   crown   how far the shell rises above the skull, in head heights. A crop
#           skims; a mop stands up off the head.
#   flare   extra width low down. A bowl cut hangs out past the skull at the
#           bottom and a slicked head does not.
#   square  the section, 2 an ellipse and 4 a rounded box. A mop is boxy, a
#           crop follows the skull.
#
#           **Every one of these is rounder than the head under it.** They ran
#           2.4 to 3.4 against a cranium that measures 2.4 to 2.6, so the hair
#           was the squarest thing on the figure -- and hair is most of a head's
#           outline, so the head read as square whatever the skull did. Halved
#           about 2.2: the order is kept, so a mop is still boxier than a crop,
#           but nothing is boxier than the skull.
#
# **The outline is the cut.** Judged from the front two shells of the same shape
# are the same haircut whatever their hairline does, and the four-view render is
# where that shows: half of a perm is its profile.
## Where a hairline sits, in fractions of figure height, before a cut lifts it
## or recedes it. The skull runs 0.630 to 0.950, so this is a little over two
## thirds of the way up the face.
HAIRLINE = 0.786

LIBRARY = [
    dict(r=0.0),                                                      # bald
    dict(r=1.10, up=0.06, back=0.20, crown=0.010, flare=0.00,
         square=2.38),                                                 # cropped
    dict(r=1.12, up=0.06, back=0.21, crown=0.015, flare=0.01,
         square=2.38, burns=True),                                     # back and sides
    dict(r=1.15, up=0.05, back=0.22, crown=0.030, flare=0.055,
         square=2.80, peak=True, fringe=0.55, slope=0.16, sides=0.30),                         # bowl, with a point
    dict(r=1.17, up=0.05, back=0.22, crown=0.045, flare=0.045,
         square=2.56, burns=True),                                     # heavier
    dict(r=1.12, up=0.09, back=0.20, crown=0.055, flare=0.00,
         square=2.32, quiff=True, slope=0.44),                                     # a quiff
    dict(r=1.10, up=0.07, back=0.18, crown=0.035, flare=0.02,
         square=2.26, curls=12),                                       # curly
    dict(r=1.09, up=0.08, back=0.18, crown=0.040, flare=0.03,
         square=2.20, curls=16, curl_r=0.40, curl_skirt=True, sides=0.34),         # a big curly head
    dict(r=1.13, up=0.06, back=0.21, crown=0.050, flare=0.01,
         square=2.44, quiff=True, burns=True),                         # swept over
    dict(r=1.13, up=0.05, back=0.20, crown=0.025, flare=0.035,
         square=2.50, mass=1.0, sides=0.28),                                       # collar length
    dict(r=1.15, up=0.05, back=0.22, crown=0.030, flare=0.055,
         square=2.56, mass=1.0, burns=True, sides=0.30),                           # long
    dict(r=1.08, up=0.08, back=0.27, crown=0.005, flare=0.00,
         square=2.32, burns=True, recede=0.030, slope=0.42),                                     # receding
    dict(r=1.07, up=0.07, back=0.23, crown=0.000, flare=0.00,
         square=2.26, sy=0.92, peak=True, recede=0.018),                             # thin on top
    dict(r=1.13, up=0.07, back=0.21, crown=0.045, flare=0.02,
         square=2.32, tufts=4),                                        # tousled
    dict(r=1.09, up=0.06, back=0.22, crown=0.015, flare=0.01,
         square=2.38, mass=1.45, burns=True, sides=0.30),                          # a mullet
    dict(r=1.10, up=0.05, back=0.24, crown=0.020, flare=0.00,
         square=2.68, slick=True, slope=0.42, sides=0.12),                                     # slicked back
    dict(r=1.11, up=0.04, back=0.25, crown=0.020, flare=0.00,
         square=2.68, slick=True, burns=True, slope=0.42, sides=0.12),                         # slicked, with burns
    dict(r=1.11, up=-0.05, back=0.23, crown=0.000, flare=0.00,
         square=2.32, burns=True, recede=0.026, slope=0.40),                                     # thinning
]


def _shell(look, h, style, r, lift, back, squash):
    """The rings of one cut's shell.

    **The hairline is a rim, not a crossing**, and that is the whole of this
    function. Every earlier version let a big smooth shell pass through the
    skull and called wherever they met the hairline. Two low-poly surfaces
    meeting at a shallow angle do not make a line, they make a sawtooth, and
    seventeen cuts had one across the forehead. Tucking the shell in to steepen
    the crossing made it worse.

    So the bottom ring is put **on** the skull -- its own radius, plus a
    millimetre -- and the ring above it steps straight out to full size. The
    hairline is then an authored edge in a known place, the step reads as the
    thickness of a head of hair, and nothing is left to an intersection. It is
    the sock hoops again: stop laying one surface over another and make the
    edge yourself.

    Front-to-back shape comes from `tilt`, faded out up the shell so the rings
    above cannot fold under the one below.
    """
    import numpy as np
    hw = look.head_w * h
    hd = look.head_d * h
    hh = look.head_h * h
    # A floor under the crown, because a shell whose top ring lands exactly on
    # the skull's flickers: two coincident surfaces, and the crown comes out
    # speckled with bare scalp.
    crown = max(style.get("crown", 0.0), 0.045) * hh
    flare = style.get("flare", 0.0)
    square = style.get("square", F.HEAD_POWER)

    crown_z = F.SKULL[-1][0]
    zs = [row[0] for row in F.SKULL]
    scales = [row[1] for row in F.SKULL]
    depths = [row[2] for row in F.SKULL]

    # Where the hairline sits, before the cut's own lift moves it.
    base = h * (HAIRLINE + style.get("recede", 0.0))
    slope = hh * style.get("slope", 0.28)
    side_drop = hh * style.get("sides", 0.19)
    # Above the skull whatever `up` does. A cut with a negative lift -- the
    # thinning one -- pulled its own crown down under the head and went bald at
    # the top, which is not what thinning on top means.
    # `crown_z`, **not** `zs[-1]`: the table above runs past the skull on
    # purpose and reading the shell's height off its last row put the top of
    # every cut 7 per cent of a man above his own head.
    top = h * crown_z + crown - min(lift, 0.0)

    # The heights the shell is sampled at: its own parametric run, **plus every
    # row of the skull it passes**.
    #
    # This is the bare stripe across the crown, and it is not an intersection.
    # Both surfaces are stacks of rings, so both are straight between their own
    # levels -- and the shell's levels are not the skull's. Where a skull row
    # falls between two shell rings, the skull has a corner there and the shell
    # only has a chord: between 0.902 and 0.950 the chord runs 30 per cent
    # inside the corner it spans, and the shell stands off by ten. So the scalp
    # came out through the hair in a band, and no amount of `r` fixes it,
    # because the gap is a chord against a corner rather than a radius against a
    # radius. Give the shell a ring wherever the skull has one and the two are
    # parallel everywhere, which is what `r` was always assuming.
    steps = 9
    heights = []
    for i in range(steps):
        t = i / (steps - 1.0)
        # `squash` flattens the cut, but the **top ring still has to clear the
        # skull**: multiplied through, a thin-on-top cut landed its crown below
        # the head it was on and came out speckled with bare scalp.
        heights.append(
            base + (top - base) * (t ** 1.12) * (squash + (1.0 - squash) * t ** 6) + lift)
    lo, hi = heights[0], heights[-1]
    # How far this cut's top clears the skull, and the number the whole shell is
    # read off. See `rise` below.
    rise = hi - h * crown_z
    for row in F.SKULL:
        at = h * row[0] + rise
        # Strictly inside, and never within a hair of an existing ring: two
        # rings at the same height are a zero-height band and a shading seam.
        if lo + h * 0.004 < at < hi - h * 0.004:
            heights.append(at)
    heights.sort()

    rings = []
    for i, z in enumerate(heights):
        # `t` is where this ring sits up the shell, which is what the hairline's
        # tilt and drop fade out over. Read off the height rather than the loop
        # counter, because the loop is no longer evenly spaced.
        t = (z - lo) / max(hi - lo, 1e-9)
        # **The shell is the skull lifted, not the skull scaled at the same
        # height.** Sampled at its own `z`, the top ring of a cut asks the
        # profile for a width the skull does not have -- it is above the crown
        # -- and every answer to that is wrong: held flat it is a chimney, ramped
        # to nothing it is a cone, and domed by hand it is a stub standing on a
        # lid, which is the little square knob that survived both. Sampled
        # `rise` lower, the shell *is* the skull moved up and out: its top ring
        # takes the crown's own width, so a cut closes exactly the way the head
        # under it does and there is nothing left on top to read.
        scale = float(np.interp((z - rise) / h, zs, scales))
        cy = float(np.interp((z - rise) / h, zs, depths)) * hd \
            + back * (1.0 - t) ** 1.5
        if i == 0:
            # **Sized for the highest the rim gets, not for its base.** `tilt`
            # lifts the front of the rim to where the skull is narrower, and a
            # rim cut for the base is inside the skull up there -- which is the
            # sawtooth again, in the one place a hairline is actually looked at.
            # Sized for the top of its own travel, the rim is outside the skull
            # all the way round, by more at the nape than at the brow.
            widest = float(np.interp((z - rise - max(slope, side_drop)) / h, zs, scales))
            width = widest + 0.0080 / hw
        else:
            width = scale * r * (1.0 + flare * (1.0 - t) * (1.0 - t))
        # **The rim takes the skull's own section, not the cut's.** A shell that
        # is boxier or rounder than the head is a *differently shaped* ring at
        # the same radius: wider than the skull at the diagonals or narrower,
        # and the narrow case dips inside and saws the hairline up at four
        # points. Only from the second ring on does the cut get its own shape.
        ring = M.Ring(z, hw * width, hd * width, cy=cy,
                      power=F.skull_power((z - rise) / h) if i == 0 else square)
        # A hairline is not level. It is highest on the forehead, comes down
        # over the ears and lowest at the nape -- three different heights on one
        # ring, which is what `tilt` (front to back) and `drop` (at the sides)
        # are for. Level, the whole cut is a beret sitting on the crown.
        fade = (1.0 - t) ** 2.0
        ring.tilt = -slope * fade
        ring.drop = side_drop * fade
        rings.append(ring)
    return rings


def cuts(look, h, segs, coarse):
    """[(name, Mesh)] -- every style, in library order, named for its index."""
    out = []
    for i, style in enumerate(LIBRARY):
        name = "Hair%02d" % i
        style = dict(style, seed=i)
        mesh = one(look, h, style, segs, coarse, name)
        if mesh is not None:
            out.append((name, mesh))
    return out


def one(look, h, style, segs, coarse, name):
    if style.get("r", 0.0) <= 0.0:
        return None
    hw = look.head_w * h
    hd = look.head_d * h
    hh = look.head_h * h
    r = style["r"]
    lift = style.get("up", 0.06) * hh
    # Scaled up on this head: `HAIR_LIBRARY` measures the push back against a
    # sphere of `head_r`, and a rounded box of the same width is deeper, so the
    # same fraction buries less of the shell and the hairline sits too low.
    back = style.get("back", 0.20) * hd * 1.5
    squash = style.get("sy", 1.0)

    # The shell starts at the hairline and runs over the crown. Its bottom ring
    # is tilted -- high on the forehead, low on the nape -- because a level one
    # is a swimming cap, and a separate fringe piece does not work: far enough
    # forward to show it is a slug, far enough back it lands on the brows.
    rings = _shell(look, h, style, r, lift, back, squash)
    mesh = M.tube(rings, segs, HAIR, power=style.get("square", F.HEAD_POWER),
                  name=name)

    crown_z = h * F.SKULL[-1][0] + lift

    if style.get("quiff"):
        mesh.merge(M.blob((0.0, -hd * r * 0.52 + back, h * 0.905 + lift),
                          (hw * 0.44, hd * 0.30, hh * 0.24),
                          coarse, coarse // 2, HAIR, name="quiff"))
    if style.get("peak"):
        mesh.merge(M.blob((0.0, -hd * r * 0.80 + back, h * 0.812 + lift),
                          (hw * 0.20, hd * 0.16, hh * 0.15),
                          coarse, coarse // 2, HAIR, name="peak"))
    if style.get("burns"):
        for side in (-1.0, 1.0):
            mesh.merge(M.blob((side * hw * r * 0.90, -hd * 0.06 + back, h * 0.712),
                              (hw * 0.12, hd * 0.20, hh * 0.20),
                              coarse, coarse // 2, HAIR, name="burn"))
    if style.get("mass"):
        # Down the back, not round the sides: a mass that wraps is a hood.
        long = style["mass"]
        mesh.merge(M.blob((0.0, hd * r * 0.62 + back, h * (0.790 - 0.055 * long)),
                          (hw * r * 0.86, hd * 0.44, hh * (0.34 + 0.22 * long)),
                          segs, coarse, HAIR, name="mass"))
    for i in range(style.get("tufts", 0)):
        turn = (i + 0.5) / max(style.get("tufts", 1), 1)
        mesh.merge(M.blob((hw * 0.34 * (1 if i % 2 else -1),
                           back + hd * 0.30 * (turn - 0.5),
                           crown_z - hh * 0.06),
                          (hw * 0.20, hd * 0.18, hh * 0.16),
                          coarse, coarse // 2, HAIR, name="tuft"))

    count = style.get("curls", 0)
    if count:
        _curls(mesh, look, h, style, count, coarse)

    # **Rolled, not machined.** The one thing every clay head in the reference
    # stills has and a lathed shell has not: the hair is not true anywhere. It
    # is worked in the hand, so its outline wanders by a few millimetres all the
    # way round, and that wander is what the eye reads as *material* before it
    # reads any shape. A normal map cannot do it -- it does not touch the
    # silhouette, and a head of hair is almost entirely silhouette.
    #
    # Radial about the middle of the skull, so a cut keeps its shape and its
    # hairline and only stops being smooth. The seed is the cut's own index, so
    # two men in the same cut are lumpy in the same places -- which is right,
    # they came out of the same mould -- while eighteen cuts differ.
    M.roughen(mesh, ROLLED, (0.0, 0.0, h * 0.80),
              seed=float(style.get("seed", 0)) * 3.7, scale=ROLL_SCALE)
    return mesh


def _curls(mesh, look, h, style, count, coarse):
    """A ring of fat lobes round a shell. A perm is exactly that and no more."""
    import math
    hw = look.head_w * h
    hd = look.head_d * h
    hh = look.head_h * h
    r = style["r"]
    lift = style.get("up", 0.06) * hh
    # Scaled up on this head: `HAIR_LIBRARY` measures the push back against a
    # sphere of `head_r`, and a rounded box of the same width is deeper, so the
    # same fraction buries less of the shell and the hairline sits too low.
    back = style.get("back", 0.20) * hd * 1.5
    size = style.get("curl_r", 0.30)
    rows = ((0.855, 1.00), (0.905, 0.86)) if not style.get("curl_skirt") \
        else ((0.760, 0.96), (0.830, 1.02), (0.898, 0.88))
    for z, spread in rows:
        for i in range(count):
            turn = math.tau * (i + 0.5 * (z * 37 % 2)) / count
            mesh.merge(M.blob(
                (hw * r * spread * math.sin(turn) * 0.94,
                 hd * r * spread * math.cos(turn) * 0.94 + back,
                 h * z + lift),
                (hw * size * 0.62, hd * size * 0.62, hh * size * 0.60),
                max(5, coarse - 3), max(4, coarse // 2 - 1), HAIR, name="curl"))
