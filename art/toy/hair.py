"""The cuts, one mesh each, all in the file and one of them shown.

`SimCharacterBuilder.HAIR_LIBRARY` is the list and the order, because a man has
to keep his hair whichever builder drew him. Every row is the same idea: a shell
a tenth or more larger than the skull, pushed back, plus pieces. Hair that
merely skims the head is paint on a scalp -- the shell is where the volume comes
from, and the difference between a full cut and an afro is what is added on top
of it, never how big it is.

**The names are padded to two digits.** `SimCharacterModel._choose_variant`
sorts the variants by name as text, so `Hair10` would land between `Hair1` and
`Hair2` and most of a squad would wear the wrong cut.

The shell is built off `figure.SKULL`, the skull's own profile, so a cut cannot
drift off the head it belongs to when the head changes shape.
"""

import math

from . import figure as F
from . import mesh as M

HAIR = "hair"

## How far a rolled shell wanders off true, as a fraction of its own radius, and
## how big a lump is. `M.roughen` has the argument; these two numbers are the
## whole of the clay register in the hair.
ROLLED = 0.085
## Radians per metre: a lump about ten centimetres across on a head half a metre
## wide. This was 3.1 in the first pass, which put the entire figure inside one
## lobe of the noise and displaced nothing -- the lumpiness that showed was all
## normal map. `M._lumps` says why the mistake is silent.
ROLL_SCALE = 62.0

## How much further down the sides a hairline runs on a cut that wears
## sideburns, in head heights.
##
## **A sideburn is the hairline carried on past the temple**, so the shell comes
## down to meet the burn rather than the burn climbing to meet the shell. Sized
## to close the gap and about that much again: measured at the depth the burn
## sits, the rim clears its top by six hundredths of a head height, and
## `M.roughen` moves the rim by rather more than that on its own.
BURN_DROP = 0.22

## How fast a `nape` fades out up the shell. See the note where it is used: the
## rim is what the number is for, and dragging the rings above it down with the
## rim is what put bare scalp through the back of four cuts.
NAPE_FADE = 4.0

# The cuts. Row for row with `presentation/character_builder.gd:HAIR_LIBRARY` --
# the **index** is the cut and has to agree, because a man keeps his hair across
# the two builders. The parameters do not have to agree and no longer do.
#
# `r`, `up` and `back` are the library's: how big the shell is, how far it is
# lifted, and how far back it sits. The rest are this file's, and they are what
# stopped the library being one shell with the hairline in as many places:
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
#   sides_r how big the shell is low down, where `r` is the top. One number for
#           both made every cut the same shape at a different size; an undercut
#           is tight at the sides and tall on top, a bowl the reverse.
#   nape    how far down the back the hairline runs, in head heights, on top
#           of `slope`. **The back has its own rim**: the shell's back half
#           thins to the skull over the lowest `fade` of its height, so the
#           nape is an edge that tapers, not the front's step carried round.
#
#           **Every cut reaches the neck, and the band is the owner's.** The
#           hairline lands between the chin (0.625 of figure height) and the
#           mouth (0.721) on every row, buzz cut included. Hair does not stop
#           at the occiput on anybody: the whole library used to end between
#           0.70 and 0.74 -- at the mouth or above it -- and twenty-one of the
#           twenty-eight cuts read as a swim cap pulled on over a shaved neck.
#           The short rows sit at 0.665, the middle of the band.
#
#           **`nape` is not that height**, and the arithmetic is not worth
#           doing by hand: the rim is tilted by `slope`, shaped by `point` and
#           dropped by `sides`, and `_shell` bends it again. The values here
#           were solved against the built mesh -- lowest vertex on the
#           mid-plane, back half -- which is also how to move one. A row whose
#           shape changes has to be re-solved; changing `square` or `sides_r`
#           alone moved a hairline by three hundredths.
#
#           Length past the band is what makes a long cut long. Collar length
#           is 0.590, the mullet 0.560, `long` 0.545 -- below the chin, on the
#           shirt, which is the only place the eye reads them as long now that
#           the short rows come down the neck too. Further than that and the
#           cut stops being hair: at 0.490 `long` came out a plank hanging off
#           the back of the head, full width to a blunt hem.
#   back_r  the occiput: how much fuller the back half is than the rest, at
#           mid height. A crop is flat behind, a mop swells out.
#   fade    the fraction of the shell's height over which the back tapers in.
#           0 is blunt -- collar-length hair is cut straight across, and the
#           old `mass` blob is this: a deep `nape`, a full `back_r` and no
#           taper, in the shell itself and with no seam.
#   lean    a parting: the top of the shell is fuller on one side than the
#           other, so the cut is not symmetrical from the front.
#   point   the nape's shape: 1 a V, longest in the middle, 0 cut straight.
#   rough   `ROLLED` for this cut alone. A buzz cut is not rolled clay.
#   temples the hairline notched either side of the front: an M, receding.
#   bald    the crown and the forehead are sunk into the skull, so what shows
#           is a horseshoe round the sides and back at the ordinary height,
#           with the ordinary nape. Built as a shell so it matches the rest.
#   pony    a tail down the neck.
#   curl_set  how much deeper than usual the curls sit in the shell.
#   part    a parting: a groove along the top, at this many half-widths off
#           centre. 0 is a centre parting; with `lean` the hair falls away
#           from it.
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
    dict(r=1.11, sides_r=1.09, up=0.06, back=0.20, crown=0.010,
         square=2.38, nape=1.51, rough=0.03),                         # cropped
    dict(r=1.12, sides_r=1.07, up=0.06, back=0.21, crown=0.030,
         square=2.38, nape=1.47, burns=True),                         # back and sides
    dict(r=1.16, sides_r=1.20, up=0.05, back=0.22, crown=0.050, flare=-0.05,
         square=2.80, nape=1.32, back_r=0.04, fade=0.30,
         peak=True, fringe=0.55, slope=0.16, sides=0.30),             # bowl, with a point
    dict(r=1.20, sides_r=1.16, up=0.05, back=0.22, crown=0.070, flare=-0.04,
         square=2.56, nape=1.48, back_r=0.06, burns=True),            # heavier
    dict(r=1.14, sides_r=1.06, up=0.09, back=0.20, crown=0.100,
         square=2.32, nape=1.30, back_r=0.02, lean=0.06,
         quiff=True, slope=0.44),                                     # a quiff
    dict(r=1.08, sides_r=1.08, up=0.07, back=0.18, crown=0.030, flare=0.01,
         square=2.26, nape=1.49, back_r=0.04, curls=26, curl_r=0.26,
         curl_set=0.025),                                             # curly
    dict(r=1.11, sides_r=1.12, up=0.08, back=0.18, crown=0.060, flare=0.02,
         square=2.20, nape=1.07, back_r=0.08, fade=0.20,
         curls=30, curl_r=0.34, curl_skirt=True, sides=0.34,
         curl_set=0.025),                                             # a big curly head
    dict(r=1.15, sides_r=1.06, up=0.06, back=0.21, crown=0.060,
         square=2.44, nape=1.42, back_r=0.03, lean=0.14,
         quiff=True, burns=True),                                     # swept over
    # **The two that read as beanies**, and all three of the things that made
    # them read that way are here. They were the widest shells in the library
    # low down (`sides_r` over `r`, plus `flare`), which is a knitted brim; they
    # were boxy (`square` 2.5 and 2.56) where hair falling under its own weight
    # is round; and they had no parting, so the crown was one blank dome. Length
    # is what these rows are for and the length is in `nape`, not in girth.
    dict(r=1.09, sides_r=1.08, up=0.05, back=0.20, crown=0.020,
         square=2.28, nape=1.62, back_r=0.08, fade=0.35, point=0.55,
         part=0.0, sides=0.28),                                       # collar length
    dict(r=1.11, sides_r=1.11, up=0.05, back=0.22, crown=0.030, flare=0.01,
         square=2.30, nape=2.34, back_r=0.10, fade=0.35, point=0.70, burns=True,
         part=0.0, sides=0.30),                                       # long
    dict(r=1.11, sides_r=1.09, up=0.08, back=0.27, crown=0.005,
         square=2.32, nape=1.95, burns=True, recede=0.050, slope=0.42,
         rough=0.03, temples=True),                                   # receding
    dict(r=1.11, sides_r=1.10, up=0.07, back=0.23, crown=0.000,
         square=2.26, nape=1.82, sy=0.92, peak=True, recede=0.018,
         rough=0.03),                                                 # thin on top
    dict(r=1.18, sides_r=1.10, up=0.07, back=0.21, crown=0.100, flare=0.02,
         square=2.32, nape=1.54, back_r=0.05, lean=-0.08, tufts=4),   # tousled
    dict(r=1.09, sides_r=1.07, up=0.06, back=0.22, crown=0.020,
         square=2.38, nape=2.19, back_r=0.12, fade=0.35,
         sides=0.10),                                                 # a mullet
    dict(r=1.09, sides_r=1.07, up=0.05, back=0.24, crown=0.020,
         square=2.68, nape=1.23, back_r=0.04, slick=True, slope=0.42,
         sides=0.12),                                                 # slicked back
    dict(r=1.10, sides_r=1.07, up=0.04, back=0.25, crown=0.020,
         square=2.68, nape=1.21, back_r=0.04, slick=True, burns=True,
         slope=0.42, sides=0.12),                                     # slicked, with burns
    dict(r=1.11, sides_r=1.11, up=-0.05, back=0.23, crown=0.000,
         square=2.32, nape=1.66, burns=True, recede=0.040, slope=0.40,
         rough=0.03, temples=True),                                   # thinning
    dict(r=1.045, sides_r=1.045, up=0.06, back=0.20, crown=0.000,
         square=2.30, nape=1.41, rough=0.02),                          # buzz cut
    dict(r=1.12, sides_r=1.12, up=0.16, back=0.21, crown=0.020,
         square=2.38, nape=1.74, bald=True, burns=True, rough=0.03), # horseshoe: bald on top
    dict(r=1.08, sides_r=1.07, up=0.05, back=0.24, crown=0.020,
         square=2.68, nape=1.27, slick=True, slope=0.42, sides=0.12,
         pony=True),                                                  # ponytail
    dict(r=1.24, sides_r=1.045, up=0.08, back=0.20, crown=0.100,
         square=2.40, nape=1.47, lean=0.10, rough=0.05),              # undercut
    dict(r=1.12, sides_r=1.08, up=0.07, back=0.20, crown=0.120, sy=0.70,
         square=3.40, nape=1.54, rough=0.04),                         # flat top
    # **A ball the head is pushed into**, which is the owner's description and
    # the shape itself. Every other row is a shell that follows the skull and
    # tapers; this one must not. `sides_r` equal to `r` is what makes it a
    # sphere rather than a cap -- it was three hundredths narrower low down,
    # which on a shape this big is the difference between a ball and a bonnet --
    # and `fade` 0 leaves the back full instead of drawing it in to the neck.
    dict(r=1.36, sides_r=1.34, up=0.10, back=0.18, crown=0.300,
         square=2.00, nape=1.51, back_r=0.10, fade=0.30, rough=0.07), # afro
    dict(r=1.20, sides_r=1.17, up=0.05, back=0.20, crown=0.060, flare=0.03,
         square=2.40, nape=1.57, back_r=0.08, fade=0.25, slope=0.16,
         sides=0.36),                                                 # shaggy, over the ears
    dict(r=1.14, sides_r=1.10, up=0.06, back=0.20, crown=0.060,
         square=2.40, nape=1.50, part=0.0),                           # centre parting, short
    dict(r=1.18, sides_r=1.18, up=0.05, back=0.20, crown=0.060, flare=0.03,
         square=2.40, nape=1.31, back_r=0.06, fade=0.20, point=0.3,
         slope=0.12, sides=0.38, part=0.0),                           # centre parting, curtains
    dict(r=1.14, sides_r=1.08, up=0.06, back=0.20, crown=0.050,
         square=2.40, nape=1.50, part=0.35, lean=0.10),               # side parting, short
    dict(r=1.18, sides_r=1.16, up=0.05, back=0.20, crown=0.060, flare=0.03,
         square=2.40, nape=1.29, back_r=0.06, fade=0.20, point=0.3,
         slope=0.14, sides=0.34, part=0.35, lean=0.12),               # side parting, long
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
    # The skull's front-to-back size is its own number now -- the face has a
    # profile in it -- and a shell sized on the width alone is inside the head
    # wherever the two differ. At the temple that is where a sideburn hangs.
    thicks = [row[4] for row in F.SKULL]

    # Where the hairline sits, before the cut's own lift moves it.
    base = h * (HAIRLINE + style.get("recede", 0.0))
    slope = hh * style.get("slope", 0.28)
    side_drop = hh * style.get("sides", 0.19)
    nape = hh * style.get("nape", 0.45)
    point = style.get("point", 1.0)
    sides_r = style.get("sides_r", r)
    occiput = style.get("back_r", 0.0)
    fade_back = style.get("fade", 0.45)
    lean = style.get("lean", 0.0)
    part = style.get("part")
    bald = style.get("bald", False)
    temples = style.get("temples", False)
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
        thick = float(np.interp((z - rise) / h, zs, thicks))
        cy = float(np.interp((z - rise) / h, zs, depths)) * hd
        # **The push back tapers off at the nape now.** See `M.Ring.slide`: it
        # is the front and the sides that need burying, and carrying the back
        # with them stood nine centimetres of hair off the skull there and cut
        # it off with the rim's own hard edge. The shell was never too big; the
        # back of it was in the wrong place.
        push = back * (1.0 - t) ** 1.5
        if i == 0:
            # **Sized for the highest the rim gets, not for its base.** `tilt`
            # lifts the front of the rim to where the skull is narrower, and a
            # rim cut for the base is inside the skull up there -- which is the
            # sawtooth again, in the one place a hairline is actually looked at.
            # Sized for the top of its own travel, the rim is outside the skull
            # all the way round, by more at the nape than at the brow.
            # **The rim has to enclose every height it reaches, not the one
            # its `z` names.** `tilt` carries its front up by `slope` and
            # `drop` carries its sides down, so one ring spans a band of the
            # skull -- and the skull is no longer the same shape up and down
            # that band: the face has a profile in it now, and the forehead
            # falls back over the same three centimetres the hairline covers.
            # Sized at one height and centred at another, the rim dipped inside
            # the skull at the brow on a third of the cuts, which is the
            # hairline sawtooth back again.
            band = np.linspace((z - rise - max(slope + nape, side_drop)) / h,
                               (z - rise + slope) / h, 9)
            widest = float(np.interp(band, zs, scales).max())
            slide = np.interp(band, zs, depths)
            reach = np.interp(band, zs, thicks)
            front = float((slide - reach).min())
            behind = float((slide + reach).max())
            width = widest + 0.0080 / hw
            depth = (behind - front) * 0.5 + 0.0080 / hd
            cy = (behind + front) * 0.5 * hd
            # **The back of the rim is sized for the neck, not the cheek.**
            # `widest` is the cheek, and at the nape the rim reaches a
            # skull a fifth narrower, so it stood off the neck all the way
            # round the back: a beanie's brim. The back half is brought in
            # to the width the skull has where the rim actually lands.
            neck = float(np.interp((z - rise - slope - nape) / h, zs, scales))
            neck = min(1.0, (neck + 0.012 / hw) / width)
        else:
            # Sides low down, top high up, and the blend is most of what
            # tells an undercut from a bowl.
            blend = t * t * (3.0 - 2.0 * t)
            grow = (sides_r + (r - sides_r) * blend) \
                * (1.0 + flare * (1.0 - t) * (1.0 - t))
            width = scale * grow
            depth = thick * grow
        # **The rim takes the skull's own section, not the cut's.** A shell that
        # is boxier or rounder than the head is a *differently shaped* ring at
        # the same radius: wider than the skull at the diagonals or narrower,
        # and the narrow case dips inside and saws the hairline up at four
        # points. Only from the second ring on does the cut get its own shape.
        ring = M.Ring(z, hw * width, hd * depth, cy=cy,
                      power=F.skull_power((z - rise) / h) if i == 0 else square)
        ring.slide = push
        # A hairline is not level. It is highest on the forehead, comes down
        # over the ears and lowest at the nape -- three different heights on one
        # ring, which is what `tilt` (front to back) and `drop` (at the sides)
        # are for. Level, the whole cut is a beret sitting on the crown.
        fade = (1.0 - t) ** 2.0
        ring.tilt = -slope * fade
        ring.drop = side_drop * fade
        # **The nape dies off faster than the tilt does**, and it has to now
        # that a nape is more than twice what it was. At the square fade a nape
        # of 2.15 still carried a full head-height of drop a third of the way up
        # the shell: the whole back half came down with the rim, dipped inside
        # the skull near the crown, and four cuts came out with a patch of bare
        # scalp showing through the back of the head. The rim is what the number
        # is for; the rings above it only have to follow far enough that the
        # edge is not a lip.
        ring.nape = nape * (1.0 - t) ** NAPE_FADE
        ring.point = point
        ring.drop_front = True
        if i == 0:
            ring.shape = lambda u, v, k=neck: 1.0 + (k - 1.0) * _ease((v - 0.3) / 0.5)
        else:
            ring.shape = _back_shape(t, grow, occiput, fade_back, lean, neck,
                                     part)
        if bald or temples:
            ring.shape = _sunk(ring.shape, t, 1.0 if i == 0 else grow,
                               top=bald, temples=temples)
        if bald and t > 0.40:
            # Sunk radially the top rings are still *above* the crown, and a
            # narrow ring over a skull is a tuft. They go under it as well.
            ring.z = h * crown_z - hh * 0.15
            ring.nape = 0.0
            ring.tilt = 0.0
            ring.drop = 0.0
        rings.append(ring)
    return rings


def _ease(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3.0 - 2.0 * u)


def _sunk(inner, t, grow, top=False, temples=False):
    """Hair pulled inside the skull, where a man has lost it.

    `top`: everything above three tenths of the shell's height goes in, and
    the front between the temples on the rings below. What stands is the
    band round the sides and back, with its top edge where the sinking starts
    -- a horseshoe. **Well inside**, at 0.35: the shell is the skull lifted,
    so near the crown it is far wider than the skull at the same height, and
    at 0.55 a tuft of the top ring still stood out of the crown.

    `temples`: two notches either side of the front, so the hairline is an M
    -- receding. The middle keeps its hair.
    """
    top_gone = _ease((t - 0.30) / 0.10) if top else 0.0
    low = 1.0 - _ease((t - 0.42) / 0.15)

    def shape(u, v):
        ahead = _ease((-v - 0.10) / 0.2)
        gone = top_gone
        if top:
            gone = max(gone, ahead * (1.0 - _ease((abs(u) - 0.55) / 0.25)))
        if temples:
            notch = math.exp(-((abs(u) - 0.55) / 0.22) ** 2)
            gone = max(gone, ahead * notch * low)
        return inner(u, v) * (1.0 - gone * (1.0 - 0.35 / grow))
    return shape


def _back_shape(t, grow, occiput, fade_back, lean, neck=1.0, part=None):
    """The section's multiplier for one ring, `t` of the way up the shell.

    Three things, all of them nothing at the front and the widest points:
    the taper that brings the back half in to the skull towards the nape, the
    occiput that swells it out at mid height, and the lean that makes one
    side of the top fuller than the other.
    """
    # The taper lands a whisker off the skull, never on it: `M.roughen`
    # wanders the shell by more than a coincident surface can stand.
    # And into the neck: the taper's floor follows the rim in, so the
    # lowest rings behind the head narrow the way the skull does.
    # Only the lowest rings, though: the neck is narrower than the skull the
    # ring is sized on, and a ring brought in to it while still up the skull
    # is inside the head.
    floor = min(1.0, 1.035 / grow) \
        * (neck + (1.0 - neck) * _ease(t / max(fade_back * 0.5, 1e-6)))
    if fade_back > 0.0 and t < fade_back:
        u = t / fade_back
        thin = floor + (1.0 - floor) * u * u * (3.0 - 2.0 * u)
    else:
        thin = 1.0
    bump = max(0.0, 1.0 - ((t - 0.45) / 0.45) ** 2)

    def shape(u, v):
        behind = max(0.0, v) ** 2
        back = 1.0 + (thin * (1.0 + occiput * bump) - 1.0) * behind
        out = back * (1.0 + lean * u * t)
        if part is not None:
            # The groove: a twelfth of the shell's stand-off, only on the
            # rings up the top, and gone before it reaches the nape.
            # To the scalp, and from the hairline up: a parting is a line
            # of skin, and one that starts above the rim is not seen from
            # the front, which is where a parting is looked at.
            groove = math.exp(-((u - part) / 0.20) ** 2) * math.sqrt(t) \
                * max(0.0, 1.0 - max(0.0, v) ** 2)
            out *= 1.0 - (1.0 - 1.035 / grow) * groove
        return out
    return shape


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
    # **Off the cut's own side drop, before the boost below moves it.** The burn
    # hangs where it always hung; it is the hairline that comes down. Read after
    # the boost, both of them drop and the sideburn ends up on a man's jaw.
    burn_rim = (h * (HAIRLINE + style.get("recede", 0.0)) + lift
                - hh * style.get("sides", 0.19))
    if style.get("burns"):
        style = dict(style, sides=style.get("sides", 0.19) + BURN_DROP)

    crown_z = h * F.SKULL[-1][0] + lift
    rings = _shell(look, h, style, r, lift, back, squash)
    mesh = M.tube(rings, segs, HAIR, power=style.get("square", F.HEAD_POWER),
                  name=name)

    if style.get("pony"):
        # A tail down the neck, and the tie it hangs from.
        mesh.merge(M.blob((0.0, hd * 0.98, h * 0.700),
                          (hw * 0.16, hd * 0.15, hh * 0.52),
                          coarse, coarse, HAIR, power=2.2, name="pony"))
        mesh.merge(M.blob((0.0, hd * 1.00, h * 0.772),
                          (hw * 0.21, hd * 0.20, hh * 0.13),
                          coarse, coarse // 2, HAIR, name="tie"))
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
    # they came out of the same mould -- while the cuts differ.
    M.roughen(mesh, style.get("rough", ROLLED), (0.0, 0.0, h * 0.80),
              seed=float(style.get("seed", 0)) * 3.7, scale=ROLL_SCALE)
    return mesh


def _curls(mesh, look, h, style, count, coarse):
    """Fat lobes all over a shell. A perm is exactly that and no more.

    **All over, and not in rows.** Two rings of curls round the sides left
    the top bare and read as a bathing cap with bobbles on, and a curl
    exactly where the ring said is a row of teeth. So they climb to the
    crown, fewer per ring as the head narrows, and every one is jogged round,
    up and in size by the cut's own seed.
    """
    import math
    import random
    hw = look.head_w * h
    hd = look.head_d * h
    hh = look.head_h * h
    r = style["r"]
    lift = style.get("up", 0.06) * hh
    back = style.get("back", 0.20) * hd * 1.5
    size = style.get("curl_r", 0.30)
    slope = hh * style.get("slope", 0.28) / h
    # How much further into the shell this cut's curls sit: a short curly
    # head is curls in the hair, a big one is curls standing off it.
    setin = style.get("curl_set", 0.0)
    rnd = random.Random(int(style.get("seed", 0)) * 101 + count)
    # Six rings from the hairline to the crown, and each curl set into the
    # shell by a sixth or so of its radius, so they are the surface of the
    # hair and not balls resting on it.
    # The upper rings narrow, but less than the skull does: following it
    # made a cone, holding them wide made a flat top.
    rows = [(0.800, 1.00, 1.0), (0.840, 1.00, 1.0), (0.878, 0.97, 0.95),
            (0.912, 0.88, 0.85), (0.940, 0.72, 0.65), (0.962, 0.50, 0.4)]
    if style.get("curl_skirt"):
        rows.insert(0, (0.755, 0.96, 1.0))
    for row, (z, spread, share) in enumerate(rows):
        n = max(3, int(round(count * share)))
        for i in range(n):
            turn = math.tau * (i + 0.5 * (row % 2) + rnd.uniform(-0.3, 0.3)) / n
            # The hairline is not level -- the shell's rim rises by `slope`
            # at the front -- so a ring of curls at one height sits below it
            # over the forehead and is either inside the shell or on the face.
            # The front of each ring rises with the rim.
            ahead = max(0.0, -math.cos(turn))
            # Only the lower rings: lifting the upper ones as well piled the
            # front up into a point.
            zc = z + slope * ahead * max(0.0, 1.0 - (z - 0.80) / 0.12)
            # Set in means down as well as in: the rings above the shell's
            # crown would otherwise stand up out of a cut that is meant to
            # be short.
            zc -= (z - 0.80) * setin * 5.0
            # Not on the face: a curl below the hairline and in front of the
            # ears is hair growing out of a cheek.
            if zc < 0.80 and math.cos(turn) < -0.2:
                continue
            slide = M.slide(back, math.cos(turn))
            k = rnd.uniform(0.7, 1.3)
            # Set in by between an eighth and a fifth, so the curls sit at
            # different depths in the shell and not all on one surface. The
            # front sits a little shallower, so the brow is curls too.
            deep = rnd.uniform(0.84, 0.92) + 0.04 * ahead - setin
            mesh.merge(M.blob(
                (hw * r * spread * math.sin(turn) * deep,
                 hd * r * spread * math.cos(turn) * deep + slide,
                 h * (zc + rnd.uniform(-0.012, 0.012)) + lift),
                (hw * size * 0.67 * k, hd * size * 0.67 * k, hh * size * 0.64 * k),
                max(5, coarse - 3), max(4, coarse // 2 - 1), HAIR, name="curl"))
    # And one on the crown, where the rings run out.
    mesh.merge(M.blob((0.0, back * 0.2, h * (0.970 - 0.17 * setin * 5.0) + lift),
                      (hw * size * 0.85, hd * size * 0.85, hh * size * 0.55),
                      max(5, coarse - 3), max(4, coarse // 2 - 1), HAIR, name="curl"))
