"""The footballer, as a set of mouldings.

Built from the owner's four reference images: a glossy vinyl toy footballer,
squat, big-headed, no neck at all. Read off them, in fractions of total height:

    ground 0 | boot top .095 | sock top .225 | shorts hem .245
    shirt hem .380 | chin .625 | skull top .950

and the head is nearly as wide as the shoulders -- .167 against .199 half-width.
That last number is most of what makes the register: a head this size on normal
shoulders is a caricature, and on these it is a toy.

**Each solid is one moulding and one colour.** Inside a solid everything fuses
with a fillet, because that is what a moulded object does. Between solids the
edge stays hard -- and hard is exactly right for the three edges that carry the
kit: the shirt hem, the shorts hem and the sock top. The references have all
three crisp and everything else soft, and that contrast is the kit.

Nothing here is drawn. The brows are ridges, the nose is a bump, the mouth is a
groove cut into the face. A texture would have been quicker and it would read as
a sticker on a moulded head, which is what the reference figures never do.

Built facing **-Y**, which is where Blender's front view and the studio camera
both stand, so the figure needs no turning to be photographed. `face_y` below is
the front plane of the head and everything on the face is measured off it.
"""

import math

from .palette import Color
from .sdf import Capsule, Ellipsoid, Plane, RoundBox, Solid

TAU = math.tau


class Look:
    """Everything about one player that the mould has to know.

    Fractions of total height throughout, except the colours and the counts, so
    a giant and a small man are the same figure at two sizes rather than two
    differently proportioned ones.
    """

    height = 1.80

    # Build. 0 is slight, 1 is heavy; it widens the trunk and thickens the limbs
    # and nothing else, because on a figure with no anatomy that is all "build"
    # can honestly mean.
    build = 0.5

    # The head is a rounded box, not a ball. This is the single biggest
    # departure from a sphere-based figure and it is what the references
    # actually are: a flat-ish front to carry the face, soft corners, and a jaw
    # that is a little narrower than the skull rather than a taper to a point.
    head_w = 0.167
    head_h = 0.163
    head_d = 0.150
    head_round = 0.105

    skin = Color("f2cfae")
    hair_colour = Color("4a2f1e")
    shirt_colour = Color("c8202b")
    trim_colour = Color("f4f2ee")
    shorts_colour = Color("f4f2ee")
    sock_colour = Color("c8202b")
    boot_colour = Color("1a1a1c")

    hair_style = "cap"       # cap, perm, mop, crop, bald
    moustache = False
    mouth = "line"           # line, smile, none
    brow_lift = 0.0          # up the forehead, in head half-heights
    brow_tilt = 0.0          # inner end down, in the same units
    eye_gap = 0.072          # half the distance between the eyes, of height
    nose = 0.034             # radius of the button, of height
    sleeves_long = False
    sock_hoops = 2
    shirt_number = 0

    def __init__(self, **kw):
        for key, value in kw.items():
            if not hasattr(type(self), key):
                raise AttributeError(f"no such look setting: {key}")
            setattr(self, key, value)

    def width(self) -> float:
        """Trunk half-width, of height. The references sit near the middle."""
        return 0.180 + 0.038 * self.build

    def limb(self) -> float:
        return 0.032 + 0.010 * self.build


# Heights, in fractions of total height, off the references.
BOOT_TOP = 0.095
SOCK_TOP = 0.225
SHORTS_HEM = 0.245
SHIRT_HEM = 0.380
SHOULDER = 0.605
CHIN = 0.625
CROWN = 0.950


def build(look: Look):
    """Returns [(Solid, Color)], tallest first is not required -- order is only
    the order they are made in."""
    h = look.height
    parts = []
    skin = Solid("skin")
    hair = Solid("hair")
    ink = Solid("ink")
    shirt = Solid("shirt")
    trim = Solid("trim")
    shorts = Solid("shorts")
    socks = Solid("socks")
    boots = Solid("boots")

    _body(skin, look, h)
    # The hair shell and its hairline are cut first: the cut takes a bite out of
    # everything already in the solid, and the brows and the moustache sit
    # squarely inside the bite.
    _hair(hair, look, h)
    _head(skin, ink, hair, look, h)
    _kit(shirt, trim, shorts, socks, boots, look, h)

    parts.append((skin, look.skin))
    parts.append((shirt, look.shirt_colour))
    parts.append((trim, look.trim_colour))
    parts.append((shorts, look.shorts_colour))
    parts.append((socks, look.sock_colour))
    parts.append((boots, look.boot_colour))
    # Always: a bald man still has brows, and they live in the hair solid
    # because they are moulded in his hair colour. Gating this on the cut left
    # one man in six with no brows at all.
    parts.append((hair, look.hair_colour))
    parts.append((ink, Color("14141a")))
    return [(solid, colour) for solid, colour in parts if solid.ops]


# --- The body under the kit -------------------------------------------------


def _body(skin, look, h):
    """One moulding from the shoulders to the ankles, arms included.

    Most of it never sees daylight -- the shirt and the shorts cover it -- and
    it is built anyway, because the alternative is an arm that stops at the
    sleeve and a gap that opens the first time the figure is turned.
    """
    w = look.width() * h
    limb = look.limb() * h

    # Trunk. Rounded generously: the shirt sits on this and takes its shape
    # from it, and the references have no shoulder line at all, just a soft
    # turn from the top of the arm into the top of the trunk.
    skin.add(RoundBox(
        (0.0, 0.0, h * (SHIRT_HEM + SHOULDER) * 0.5),
        (w * 0.82, h * 0.118, h * (SHOULDER - SHIRT_HEM) * 0.5),
        radius=h * 0.070))

    for side in (-1.0, 1.0):
        # Arms hang almost straight, a few degrees out. Straight down and the
        # arm merges with the trunk in silhouette; that gap is cheap daylight.
        top = (side * w * 0.90, 0.0, h * (SHOULDER - 0.02))
        wrist = (side * w * 1.00, 0.0, h * 0.295)
        skin.add(Capsule(top, wrist, limb * 1.10, limb * 0.94), k=h * 0.045)
        # A mitten: one rounded end, no fingers, and only a little wider than
        # the wrist. Any bigger and it is a boxing glove.
        skin.add(Ellipsoid((side * w * 1.01, 0.0, h * 0.258),
                           (limb * 1.22, limb * 1.12, limb * 1.34)), k=h * 0.014)

        # Legs. Thicker than the arms, which is the way round the references
        # have it and the opposite of what a constant limb radius gives.
        hip = (side * w * 0.42, 0.0, h * (SHORTS_HEM + 0.06))
        ankle = (side * w * 0.44, 0.0, h * BOOT_TOP)
        skin.add(Capsule(hip, ankle, limb * 1.42, limb * 1.20), k=h * 0.04)


def _head(skin, ink, hair, look, h):
    """A rounded box with a jaw, and a face moulded into it."""
    mid = h * (CHIN + CROWN) * 0.5
    hw = look.head_w * h
    hh = look.head_h * h
    hd = look.head_d * h

    skull = RoundBox((0.0, 0.0, mid + hh * 0.10), (hw, hd, hh * 0.94),
                     radius=look.head_round * h)
    # A jaw narrower and shallower than the skull, blended in with a wide
    # fillet. One box is a brick; a box plus a jaw is a head.
    jaw = RoundBox((0.0, -hd * 0.03, mid - hh * 0.42), (hw * 0.93, hd * 0.94, hh * 0.42),
                   radius=look.head_round * h * 0.85)
    skin.add(skull)
    skin.add(jaw, k=h * 0.05)
    # It sits straight on the shoulders. The references have no neck whatever,
    # and a gap under the chin is the first thing that breaks them.
    skin.add(Capsule((0.0, 0.0, h * (CHIN - 0.02)), (0.0, 0.0, h * (CHIN + 0.04)),
                     hw * 0.52), k=h * 0.05)

    face_y = -hd          # the front plane of the head
    eye_z = mid - hh * 0.06
    eye_x = look.eye_gap * h

    # Ears: flat tabs at the widest part of the head, at eye level. Two
    # ellipsoids and the head reads from the side, which nothing else does.
    # They have to clear the hair as well as the head: on the references an ear
    # sticks out past the cut, and a cut that swallows it takes the side of the
    # head with it.
    for side in (-1.0, 1.0):
        skin.add(Ellipsoid((side * hw * 1.08, hd * 0.04, eye_z - hh * 0.05),
                           (hw * 0.13, hd * 0.22, hh * 0.28)), k=h * 0.014)

    # The nose: a button, blended into the face rather than stuck on it. The
    # fillet is the whole point -- a ball on a face is a clown.
    skin.add(Ellipsoid((0.0, face_y * 1.00, eye_z - hh * 0.16),
                       (look.nose * h, look.nose * h * 1.10, look.nose * h * 1.05)),
             k=h * 0.014)

    # The mouth, cut in. A groove reads dark because it is dark -- it is a
    # crease, and every crease on a moulded object is where the light is not.
    if look.mouth != "none":
        _mouth(skin, look, h, face_y, mid - hh * 0.46, hw)

    # Eyes: solid black, upright ovals, and big. No whites and no pupils; at any
    # distance a white with a pupil in it is a grey smudge.
    #
    # Set on the front plane rather than at nine tenths of it. The head is a
    # rounded *box*: its front is flat, at exactly `face_y`, so a feature placed
    # at 0.9 of that is ten per cent of a head-depth inside the man's face --
    # which is where the brows were, and why they read as two dark specks.
    for side in (-1.0, 1.0):
        ink.add(Ellipsoid((side * eye_x, face_y * 0.99, eye_z),
                          (hw * 0.130, hd * 0.15, hh * 0.170)))

    # Brows: moulded ridges in the hair colour, sat above the eye with a clear
    # gap. In the references these carry more character than anything else on
    # the figure, and they are the one feature that must never be a drawn line.
    for side in (-1.0, 1.0):
        lift = hh * (0.26 + look.brow_lift)
        tilt = side * look.brow_tilt * hh
        hair.add(RoundBox(
            (side * eye_x * 1.02, face_y * 1.02, eye_z + lift + tilt),
            (hw * 0.205, hd * 0.055, hh * 0.075),
            radius=hh * 0.055,
            rotation=(0.0, side * look.brow_tilt * 1.6, 0.0)), k=h * 0.004)

    if look.moustache:
        _moustache(hair, look, h, face_y, mid - hh * 0.34, hw, hd, hh)


def _mouth(skin, look, h, face_y, z, hw):
    """A groove, cut with a line of capsules along an arc."""
    span = hw * 0.42
    steps = 9
    for i in range(steps):
        t0 = -1.0 + 2.0 * i / steps
        t1 = -1.0 + 2.0 * (i + 1) / steps
        bend = 0.0 if look.mouth == "line" else hw * 0.16
        a = (t0 * span, face_y * 1.02, z + (1.0 - t0 * t0) * -bend)
        b = (t1 * span, face_y * 1.02, z + (1.0 - t1 * t1) * -bend)
        skin.cut(Capsule(a, b, hw * 0.055), k=h * 0.002)


def _moustache(hair, look, h, face_y, z, hw, hd, hh):
    """A handlebar: a bar under the nose with the ends swept up.

    Two lobes and a centre, fused. One flat bar is a sticker, and a pair of
    lobes with nothing between them is a smirk drawn either side of the mouth.
    """
    hair.add(Ellipsoid((0.0, face_y * 1.02, z), (hw * 0.30, hd * 0.13, hh * 0.12)))
    for side in (-1.0, 1.0):
        hair.add(Ellipsoid((side * hw * 0.44, face_y * 0.94, z + hh * 0.070),
                           (hw * 0.28, hd * 0.12, hh * 0.100),
                           rotation=(0.0, side * 0.40, 0.0)), k=h * 0.014)


# --- Hair -------------------------------------------------------------------


def _hair(hair, look, h):
    """A shell over the skull with a hairline cut into it, plus pieces.

    **Every cut starts from the same shell.** A style built out of its own
    lobes alone leaves the skull showing between them -- which is what the perm
    and the mop both did, each of them a ring of curls round a bald patch.

    The shell is a rounded box rather than an ellipsoid because the head is: an
    ellipsoid over a rounded box pulls in at the temples and the corners of the
    skull come through it.

    The hairline is a **cut**, not a shrunken shell. Two round things intersect
    in a round edge, so cutting the face back out of the shell gives a hairline
    with a curve in it for nothing; and pushing the cutting sphere forward
    brings that hairline down the forehead, because the crossing moves with it.
    """
    style = look.hair_style
    if style == "bald":
        return
    mid = h * (CHIN + CROWN) * 0.5
    hw = look.head_w * h
    hh = look.head_h * h
    hd = look.head_d * h

    # How much hair there is, and how far down the forehead it comes.
    thick, lift, hairline = {
        "crop": (1.04, 0.22, 1.66),
        "cap": (1.07, 0.26, 1.62),
        "perm": (1.10, 0.30, 1.50),
        "mop": (1.09, 0.32, 1.54),
    }[style]

    hair.add(RoundBox((0.0, hd * 0.05, mid + hh * lift),
                      (hw * thick, hd * thick, hh * 0.92),
                      radius=look.head_round * h * 1.12))
    hair.cut(Ellipsoid((0.0, -hd * hairline, mid - hh * 0.30),
                       (hw * 1.52, hd * 1.52, hh * 1.58)), k=h * 0.006)

    if style in ("cap", "crop"):
        # Sideburns, down in front of each ear. Cheap, and most of what says a
        # cut was given to a person rather than moulded onto a head.
        for side in (-1.0, 1.0):
            hair.add(Ellipsoid((side * hw * 0.92, -hd * 0.34, mid - hh * 0.06),
                               (hw * 0.11, hd * 0.30, hh * 0.30)), k=h * 0.010)

    elif style == "perm":
        # The reference perm: a ring of **fat lobes**, each about a fifth of the
        # head across, carried down past the ears to the jaw. It is the size and
        # the count that make it read -- small curls at this scale are gravel on
        # a scalp.
        lobe = hw * 0.29
        for ring, (z_at, radius, count) in enumerate((
                (mid + hh * 1.02, 0.50, 6),
                (mid + hh * 0.58, 0.95, 10),
                (mid + hh * 0.06, 1.06, 11),
                (mid - hh * 0.46, 1.04, 10),
                (mid - hh * 0.94, 0.88, 8))):
            for i in range(count):
                a = TAU * (i + 0.5 * (ring % 2)) / count
                y = math.cos(a) * hd * radius
                # The front is left out below the crown: a curl over the face is
                # not a fringe, it is a hand over the eyes.
                if ring > 0 and y < -hd * 0.40:
                    continue
                hair.add(Ellipsoid((math.sin(a) * hw * radius, y, z_at),
                                   (lobe, lobe, lobe * 0.92)), k=h * 0.014)

    elif style == "mop":
        # The third reference's register: a heap of separate balls, barely
        # fused, so the silhouette is lumpy all over rather than a smooth cap
        # with pieces on it.
        for i in range(30):
            a = TAU * i * 0.618
            r = 0.42 + 0.62 * ((i * 7) % 11) / 10.0
            y = math.cos(a) * hd * r
            z = mid + hh * (-0.35 + 1.55 * (((i * 5) % 7) / 6.0))
            if y < -hd * 0.42 and z < mid + hh * 0.72:
                continue
            size = hw * (0.20 + 0.11 * ((i * 3) % 5) / 4.0)
            hair.add(Ellipsoid((math.sin(a) * hw * r, y, z), (size, size, size)),
                     k=h * 0.007)


# --- The kit ----------------------------------------------------------------


def _kit(shirt, trim, shorts, socks, boots, look, h):
    w = look.width() * h
    limb = look.limb() * h

    # --- Shirt ---------------------------------------------------------------
    # A shell over the trunk with soft shoulders and a **flat hem**. The hem is
    # cut with a plane rather than modelled, because a plane cut through a
    # rounded solid is the only way to get an edge that is straight all the way
    # round and still soft to the touch.
    #
    # The trunk is narrower than the figure's widest point and the sleeves carry
    # it out to full width. Built at full width it read as a barrel: the sleeve
    # then blends outwards from an already-wide shoulder and the arms arrive
    # somewhere under the armpit.
    trunk = w * 0.90
    shirt_round = h * 0.072
    shirt_low = h * SHIRT_HEM - shirt_round
    shirt_high = h * SHOULDER + h * 0.017
    shirt.add(RoundBox(
        (0.0, 0.0, (shirt_low + shirt_high) * 0.5),
        (trunk, h * 0.126, (shirt_high - shirt_low) * 0.5),
        radius=shirt_round))

    sleeve_end = h * (0.442 if not look.sleeves_long else 0.300)
    for side in (-1.0, 1.0):
        # On the arm's own line, not the trunk's. Started further in, the
        # sleeve is narrower at the shoulder than the arm inside it and the bare
        # arm breaks out through the top of it.
        top = (side * w * 0.90, 0.0, h * (SHOULDER - 0.012))
        end = (side * w * 0.99, 0.0, sleeve_end)
        shirt.add(Capsule(top, end, limb * 1.40, limb * 1.20), k=h * 0.055)
        # The cuff, in the trim colour, standing a little proud of the sleeve.
        cuff_a = (side * w * 0.97, 0.0, sleeve_end + h * 0.026)
        cuff_b = (side * w * 0.99, 0.0, sleeve_end - h * 0.002)
        trim.add(Capsule(cuff_a, cuff_b, limb * 1.25))

    shirt.cut(Plane((0.0, 0.0, h * SHIRT_HEM), (0.0, 0.0, 1.0)), k=h * 0.006)
    # The collar: the head's own jaw, enlarged, taken out of the shirt, so the
    # shirt hugs the jaw instead of disappearing inside it.
    hw = look.head_w * h
    hh = look.head_h * h
    hd = look.head_d * h
    mid = h * (CHIN + CROWN) * 0.5
    shirt.cut(RoundBox((0.0, -hd * 0.03, mid - hh * 0.44),
                       (hw * 0.86, hd * 0.90, hh * 0.46),
                       radius=look.head_round * h * 0.80), k=h * 0.014)

    # The V. **One shape, used twice**: the same pair of bars is cut out of the
    # shirt and added to the trim, so the white insert lands in the hole to the
    # millimetre. Sized and placed apart, the two drifted and the result was a
    # white badge floating in front of a shirt with no neckline in it.
    #
    # The trim sits a few millimetres behind the shirt's own surface, which is
    # what a neckline does -- the insert is under the shirt, not on it.
    face = h * 0.132
    # The cut reaches from outside the shirt to well inside it, so it opens a
    # hole rather than scoring a line. The insert stops three millimetres short
    # of where the shirt's surface was, which is what a neckline does: the white
    # is *under* the shirt, not stuck on it.
    step = _vee_slabs(w, h, -face - h * 0.020, -face + h * 0.050)
    for prim in step:
        shirt.cut(prim, k=h * 0.009)
    for prim in _vee_slabs(w, h, -face + h * 0.003, -face + h * 0.075):
        trim.add(prim, k=h * 0.009)

    # --- Shorts --------------------------------------------------------------
    # Up under the shirt hem and down to about the crotch. A flat hem again, and
    # a **notch** between the legs: without it the two legs are one block and the
    # garment reads as a nappy, which every rounded version of this did.
    shorts_round = h * 0.055
    shorts_low = h * SHORTS_HEM - shorts_round
    shorts_high = h * SHIRT_HEM + h * 0.030
    shorts.add(RoundBox(
        (0.0, 0.0, (shorts_low + shorts_high) * 0.5),
        (w * 0.78, h * 0.122, (shorts_high - shorts_low) * 0.5),
        radius=shorts_round))
    shorts.cut(Plane((0.0, 0.0, h * SHORTS_HEM), (0.0, 0.0, 1.0)), k=h * 0.006)
    # Low enough that it opens through the hem. Centred a notch-radius higher
    # and it is a round hole punched in a skirt, which is what it was.
    shorts.cut(Capsule((0.0, -h * 0.20, h * (SHORTS_HEM + 0.028)),
                       (0.0, h * 0.20, h * (SHORTS_HEM + 0.028)),
                       h * 0.056), k=h * 0.012)

    # --- Socks ---------------------------------------------------------------
    # Everyone wears them and they are pulled up. A flat top, level on both
    # legs, is the third of the three hard edges the kit is made of.
    for side in (-1.0, 1.0):
        top = (side * w * 0.43, 0.0, h * (SOCK_TOP + 0.02))
        ankle = (side * w * 0.44, 0.0, h * (BOOT_TOP - 0.005))
        socks.add(Capsule(top, ankle, limb * 1.52, limb * 1.28))
        for i in range(look.sock_hoops):
            at = h * (SOCK_TOP - 0.024 - i * 0.030)
            # On the sock's own line rather than at a fixed x: the sock leans
            # and tapers, and a hoop that ignores both climbs the leg.
            t = (h * (SOCK_TOP + 0.02) - at) / (h * (SOCK_TOP + 0.025 - BOOT_TOP))
            x = side * w * (0.43 + 0.01 * t)
            r = limb * (1.52 - 0.24 * t) + h * 0.0016
            trim.add(Capsule((x, 0.0, at + h * 0.008), (x, 0.0, at - h * 0.008), r))
    socks.cut(Plane((0.0, 0.0, h * SOCK_TOP), (0.0, 0.0, -1.0)), k=h * 0.004)

    # --- Boots ---------------------------------------------------------------
    # A rounded wedge with the toe forward and the heel under the ankle, cut
    # flat underneath so the figure stands on a sole rather than balancing on a
    # curve.
    for side in (-1.0, 1.0):
        x = side * w * 0.44
        # The last: heel under the ankle, toe forward and lower, so the boot is
        # a wedge rather than a sausage lying down. It wants real length -- a
        # boot as long as it is wide is a shoe on a snowman.
        boots.add(Capsule((x, h * 0.040, h * 0.046), (x, -h * 0.130, h * 0.022),
                          limb * 1.38, limb * 0.86))
        # The ankle collar, kept low: the boot finishes below the sock top on
        # every one of the references, and a collar that reaches it is a
        # wellington.
        boots.add(Ellipsoid((x, h * 0.020, h * 0.046),
                            (limb * 1.30, limb * 1.10, limb * 1.05)), k=h * 0.024)
    boots.cut(Plane((0.0, 0.0, 0.0), (0.0, 0.0, 1.0)), k=h * 0.004)


def _vee_slabs(w, h, y_front, y_back, steps=14):
    """The neckline V, as a stack of slabs that narrow to a point.

    Built twice at two depths: once deep, to cut a hole in the shirt, and once
    shallow, to fill it in the trim colour. One shape used for both is what
    keeps the white inside the hole -- sized apart, the two drift and the insert
    becomes a badge sitting in front of a shirt with no neckline in it.

    Two leaning bars were tried first and they fill a rhombus, not a triangle:
    each bar has to be about as thick as the V is deep before the two meet in
    the middle, and by then both ends are standing past the collar.
    """
    top = h * (SHOULDER + 0.014)
    point = h * 0.536
    reach = w * 0.38
    rise = top - point
    band = rise / steps
    slabs = []
    for i in range(steps):
        t = (i + 0.5) / steps
        slabs.append(RoundBox(
            (0.0, (y_front + y_back) * 0.5, top - rise * t),
            (reach * (1.0 - t) + h * 0.004, abs(y_back - y_front) * 0.5, band * 0.75),
            radius=h * 0.004))
    return slabs
