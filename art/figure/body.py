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
from .sdf import Barrel, Capsule, Ellipsoid, Plane, RoundBox, Solid

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

    # Which of `WorldLook`'s five bodies this man is. **Nothing here reads it
    # yet.** Every proportion in this class is a fraction of height and the game
    # scales a model by height over 1.78, so the five bodies come out of the
    # mould identical but for `build` -- a giant is a big standard man and
    # nothing more. Making him a different *shape* is a table of overrides that
    # does not exist, and `docs/THE_MODELS.md` is where the decision belongs.
    body_type = 0

    # The head is a rounded box, not a ball. This is the single biggest
    # departure from a sphere-based figure and it is what the references
    # actually are: a flat-ish front to carry the face, soft corners, and a jaw
    # that is a little narrower than the skull rather than a taper to a point.
    head_w = 0.158
    head_h = 0.163
    head_d = 0.150
    # Nearly as large as the smallest half-extent, so the box is round almost
    # everywhere and keeps only a hint of a flat plane across the face. At a
    # third of this it is a brick with the corners taken off, which is what the
    # first pass built. It must stay under `min(half)`: past that the rounded
    # box inflates instead of rounding and the distance field is nonsense.
    head_round = 0.132

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
    eye_gap = 0.066          # half the distance between the eyes, of height
    nose = 0.026             # radius of the button, of height
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


## Where a man stands, in fractions of trunk half-width.
##
## **The stance is one number and three files copy it.** `toy/figure.py` builds
## the legs, `rig.py` puts the pivots on them and this file moulds them, and a
## hip moved in one and not the others is a joint in the middle of nothing.
##
## In from 0.40 and 0.44. A thigh at 0.40 with the leg of the shorts round it
## finished wider than the shirt hem above it, so the shorts came out through
## the shirt instead of under it and the two crossed in a ragged zigzag all the
## way round the waist -- and the seat, at w*0.66, was the widest thing on the
## whole figure. The references stand with the legs close and the shirt hanging
## over the shorts, and this is what buys both.
HIP_X = 0.355
ANKLE_X = 0.395

## How far the whole arm is pulled in towards the body, in the same units.
##
## **Subtracted from every x on the arm, never from one of them.** The shoulder,
## the top of the arm, the wrist and the hand were 0.68, 0.74, 0.90 and 0.92 --
## an axis leaning out at a fixed angle -- and moving any one of them changes
## that angle instead of the position. Taking the same amount off all four
## slides the limb inboard and leaves the lean exactly as it was.
##
## What it buys is the shoulder. The sleeve *is* the shoulder on this figure, so
## how far out the arm hangs is how pronounced the shoulder is; at 0.68 the
## sleeve stood off the shirt as a separate lump on each side. Buried a little
## further into the trunk it is a shoulder again.
ARM_IN = 0.085

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
    collar = Solid("collar")
    stripes = Solid("stripes")
    hoops = Solid("hoops")

    _body(skin, look, h)
    # The hair shell and its hairline are cut first: the cut takes a bite out of
    # everything already in the solid, and the brows and the moustache sit
    # squarely inside the bite.
    _hair(hair, look, h)
    _head(skin, ink, hair, look, h)
    _kit(shirt, trim, collar, shorts, socks, boots, stripes, hoops, look, h)

    parts.append((skin, look.skin))
    parts.append((shirt, look.shirt_colour))
    parts.append((trim, look.trim_colour))
    parts.append((collar, look.trim_colour))
    parts.append((shorts, look.shorts_colour))
    parts.append((socks, look.sock_colour))
    parts.append((hoops, look.trim_colour))
    parts.append((boots, look.boot_colour))
    parts.append((stripes, look.trim_colour))
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
    # **Inside the shirt at every height, not just at the widest one.** The
    # shirt rounds over towards the shoulder, so a trunk that merely starts
    # narrower than it breaks out through the top: the bare chest was standing
    # proud of the shoulder front and back, and its own square rim read as a
    # hard line straight across the shirt.
    trunk_top = h * (SHOULDER - 0.055)
    skin.add(Barrel(
        (0.0, 0.0, (h * SHIRT_HEM + trunk_top) * 0.5),
        (w * 0.56, h * 0.058), (trunk_top - h * SHIRT_HEM) * 0.5,
        round=h * 0.072))

    for side in (-1.0, 1.0):
        # Arms hang almost straight, a few degrees out. Straight down and the
        # arm merges with the trunk in silhouette; that gap is cheap daylight.
        # Outside the trunk, not inside it, with daylight between the two.
        top = (side * w * (0.74 - ARM_IN), 0.0, h * (SHOULDER - 0.090))
        wrist = (side * w * (0.90 - ARM_IN), 0.0, h * 0.295)
        # Measured: the reference arm is .060 of figure height in radius where
        # it passes the chest. Ours was .0706 -- and an arm that much thicker
        # closes the gap to the body on its own, whatever its centre line does.
        # **A small blend, not a big one.** At h*0.045 the fillet where the arm
        # meets the trunk reaches eight centimetres, which webs the two together
        # for a hand's width below the trunk's own bottom -- and that web is the
        # torso running into the arm. The join is under the shirt anyway.
        skin.add(Capsule(top, wrist, limb * 0.92, limb * 0.80), k=h * 0.004)
        # A mitten: one rounded end, no fingers, and only a little wider than
        # the wrist. Any bigger and it is a boxing glove.
        # A mitten with a **thumb**: one lobe on the inside of the hand, joined
        # with a small enough fillet to leave a crease between the two. No
        # fingers -- the reference has none either, and the thumb is the whole
        # of what says hand rather than the end of an arm.
        hand = (side * w * (0.92 - ARM_IN), 0.0, h * 0.258)
        skin.add(Ellipsoid(hand, (limb * 1.12, limb * 1.02, limb * 1.30)),
                 k=h * 0.014)
        skin.add(Ellipsoid((hand[0] - side * limb * 0.72, -limb * 0.34, h * 0.276),
                           (limb * 0.46, limb * 0.52, limb * 0.78)), k=h * 0.005)

        # Legs. Thicker than the arms, which is the way round the references
        # have it and the opposite of what a constant limb radius gives.
        # Inside the leg of the shorts, or the thigh comes through the front of
        # them as a patch of bare skin.
        hip = (side * w * HIP_X, 0.0, h * (SHORTS_HEM + 0.06))
        ankle = (side * w * ANKLE_X, 0.0, h * BOOT_TOP)
        # Small, for the same reason the arm's is: a fillet this wide blends the
        # leg into everything already in the solid, the arm included, and welds
        # the two together across a gap that should be daylight.
        # A smooth union bridges any gap narrower than its own radius, so the
        # fillet here has to be smaller than the daylight between the leg and
        # the arm hanging beside it -- about two centimetres.
        skin.add(Capsule(hip, ankle, limb * 1.32, limb * 1.16), k=h * 0.004)


def _head(skin, ink, hair, look, h):
    """A rounded box with a jaw, and a face moulded into it."""
    mid = h * (CHIN + CROWN) * 0.5
    hw = look.head_w * h
    hh = look.head_h * h
    hd = look.head_d * h

    skull, jaw = _head_boxes(look, h)
    skin.add(RoundBox(*skull))
    skin.add(RoundBox(*jaw), k=h * 0.05)
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
                           (hw * 0.105, hd * 0.19, hh * 0.24)), k=h * 0.014)

    # The nose: a button, blended into the face rather than stuck on it. The
    # fillet is the whole point -- a ball on a face is a clown.
    nose_z = eye_z - hh * 0.16
    nose_r = look.nose * h
    skin.add(Ellipsoid((0.0, _front(0.0, nose_z, look, h) - nose_r * 0.62, nose_z),
                       (nose_r, nose_r * 1.10, nose_r * 1.05)),
             k=h * 0.014)

    # The mouth, cut in. A groove reads dark because it is dark -- it is a
    # crease, and every crease on a moulded object is where the light is not.
    if look.mouth != "none":
        _mouth(skin, look, h, mid - hh * 0.46, hw)

    # Eyes: solid black, upright ovals, and big. No whites and no pupils; at any
    # distance a white with a pupil in it is a grey smudge.
    #
    # Set on the front plane rather than at nine tenths of it. The head is a
    # rounded *box*: its front is flat, at exactly `face_y`, so a feature placed
    # at 0.9 of that is ten per cent of a head-depth inside the man's face --
    # which is where the brows were, and why they read as two dark specks.
    for side in (-1.0, 1.0):
        # Deep enough to be a shape rather than a decal, shallow enough not to
        # bulge: about a centimetre of black standing out of the cheek.
        depth = hd * 0.11
        at = _front(side * eye_x, eye_z, look, h) - depth + h * 0.006
        ink.add(Ellipsoid((side * eye_x, at, eye_z),
                          (hw * 0.145, depth, hh * 0.190)))

    # Brows: moulded ridges in the hair colour, sat above the eye with a clear
    # gap. In the references these carry more character than anything else on
    # the figure, and they are the one feature that must never be a drawn line.
    for side in (-1.0, 1.0):
        lift = hh * (0.26 + look.brow_lift)
        tilt = side * look.brow_tilt * hh
        brow_z = eye_z + lift + tilt
        deep = hd * 0.060
        at = _front(side * eye_x, brow_z, look, h) - deep + h * 0.008
        hair.add(RoundBox(
            (side * eye_x * 1.02, at, brow_z),
            (hw * 0.205, deep, hh * 0.075),
            radius=hh * 0.055,
            rotation=(0.0, side * look.brow_tilt * 1.6, 0.0)), k=h * 0.004)

    if look.moustache:
        _moustache(hair, look, h, mid - hh * 0.50, hw, hd, hh)


def _head_boxes(look, h):
    """The skull and the jaw, as (centre, half, radius).

    One box is a brick; a box plus a jaw is a head. They are returned rather
    than built so that `_front` can solve the same two shapes the head is
    actually made of.
    """
    hw = look.head_w * h
    hh = look.head_h * h
    hd = look.head_d * h
    mid = h * (CHIN + CROWN) * 0.5
    skull = ((0.0, 0.0, mid + hh * 0.10), (hw, hd, hh * 0.94),
             look.head_round * h)
    jaw = ((0.0, -hd * 0.03, mid - hh * 0.42), (hw * 0.93, hd * 0.94, hh * 0.42),
           look.head_round * h * 0.85)
    return skull, jaw


def _front(x, z, look, h):
    """Where the front of the head actually is, at this point on it.

    The head is two rounded boxes, so its surface is flat only over a small
    panel and curves away from there. Features placed at a fixed depth are right
    in the middle of the face and wrong everywhere else -- the eyes sit nearly
    half a head-width out and were standing five centimetres proud of the cheek,
    which is what googly eyes are.

    **Both boxes, and the nearer one wins.** Solved against the skull alone, the
    answer is right across the brow and two centimetres too far back by the
    time it reaches the mouth, because down there it is the jaw that is in
    front. A moustache placed on it disappeared into the chin.
    """
    best = 0.0
    for centre, half, radius in _head_boxes(look, h):
        r = min(radius, min(half)) * 0.999
        qx = max(abs(x - centre[0]) - (half[0] - r), 0.0)
        qz = max(abs(z - centre[2]) - (half[2] - r), 0.0)
        out = math.sqrt(max(r * r - qx * qx - qz * qz, 0.0))
        best = min(best, centre[1] - (half[1] - r) - out)
    return best


def _mouth(skin, look, h, z, hw):
    """A groove, cut with a line of capsules along an arc."""
    span = hw * 0.42
    steps = 9
    for i in range(steps):
        t0 = -1.0 + 2.0 * i / steps
        t1 = -1.0 + 2.0 * (i + 1) / steps
        bend = 0.0 if look.mouth == "line" else hw * 0.16
        za = z + (1.0 - t0 * t0) * -bend
        zb = z + (1.0 - t1 * t1) * -bend
        a = (t0 * span, _front(t0 * span, za, look, h) + hw * 0.020, za)
        b = (t1 * span, _front(t1 * span, zb, look, h) + hw * 0.020, zb)
        skin.cut(Capsule(a, b, hw * 0.055), k=h * 0.002)


def _moustache(hair, look, h, z, hw, hd, hh):
    """A handlebar: a bar under the nose with the ends swept up.

    Two lobes and a centre, fused. One flat bar is a sticker, and a pair of
    lobes with nothing between them is a smirk drawn either side of the mouth.
    """
    # Two fifths of the head across, not three quarters. Wider than that and it
    # stops being a moustache and becomes a bar laid over the mouth -- and the
    # ends have to lift, or the whole thing reads as a fringe upside down.
    deep = hd * 0.115
    hair.add(Ellipsoid((0.0, _front(0.0, z, look, h) - deep + h * 0.010, z),
                       (hw * 0.235, deep, hh * 0.125)))
    for side in (-1.0, 1.0):
        wing_x = side * hw * 0.255
        wing_z = z + hh * 0.055
        hair.add(Ellipsoid(
            (wing_x, _front(wing_x, wing_z, look, h) - deep * 0.86 + h * 0.010, wing_z),
            (hw * 0.195, deep * 0.86, hh * 0.095),
            rotation=(0.0, side * 0.30, 0.0)), k=h * 0.020)


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

    # How much hair there is, where its top and its **bottom** are in head
    # half-heights off the middle of the head, and how far down the forehead it
    # comes.
    #
    # The bottom is not a detail. Given only a top and a thickness the shell
    # finished level with the ears and every man was bald from there to the
    # nape -- which a front view cannot show you and a back view shows
    # instantly. The reference perm carries down past the ears to the jaw.
    thick, top, bottom, hairline = {
        "crop": (1.04, 1.14, -0.82, 1.66),
        "cap": (1.07, 1.18, -0.86, 1.62),
        "perm": (1.10, 1.22, -1.02, 1.50),
        "mop": (1.09, 1.24, -1.00, 1.54),
    }[style]

    hair.add(RoundBox((0.0, hd * 0.05, mid + hh * (top + bottom) * 0.5),
                      (hw * thick, hd * thick, hh * (top - bottom) * 0.5),
                      radius=look.head_round * h * 1.12))
    hair.cut(Ellipsoid((0.0, -hd * hairline, mid - hh * 0.30),
                       (hw * 1.52, hd * 1.52, hh * 1.58)), k=h * 0.006)

    if style in ("cap", "crop"):
        # Sideburns, down in front of each ear. Cheap, and most of what says a
        # cut was given to a person rather than moulded onto a head.
        for side in (-1.0, 1.0):
            hair.add(Ellipsoid((side * hw * 0.90, -hd * 0.22, mid - hh * 0.02),
                               (hw * 0.095, hd * 0.22, hh * 0.24)), k=h * 0.010)

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


def _kit(shirt, trim, collar, shorts, socks, boots, stripes, hoops, look, h):
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
    trunk = w * 0.62
    # **A body tube and a sloping shoulder**, which is what a T-shirt is.
    #
    # One barrel for the whole shirt reads as a postbox and no amount of easing
    # its rim fixes that: vertical sides and a domed lid is a postbox whatever
    # the radius. Measured off the reference the shoulder falls about twenty
    # degrees from the neck out to the sleeve, and that slope is most of the
    # silhouette -- it is the difference between a shirt on a man and a tube
    # with a head on it.
    #
    # So the barrel stops at the armpit and two capsules per side carry the
    # shape up and out: a shoulder that slopes, and a sleeve hung off it.
    # **The rim radius has to be smaller than the straight run it leaves.** At
    # h*0.075 the barrel rounded over a 135mm rim but had only 81mm of straight
    # side, so it began drawing in at 0.765 while the shoulder above did not
    # pick up until 0.841 -- and in between the man had a wasp waist, a quarter
    # thinner just below the chest than at either the hem or the shoulder.
    #
    # A small rim and a top raised to meet the shoulder: the section now runs
    # straight from the hem to where the shoulder takes over.
    shirt_round = h * 0.038
    shirt_low = h * SHIRT_HEM - shirt_round
    shirt_high = h * 0.545
    shirt.add(Barrel(
        (0.0, 0.0, (shirt_low + shirt_high) * 0.5),
        (trunk, h * 0.088), (shirt_high - shirt_low) * 0.5,
        round=shirt_round, top=(trunk * 0.99, h * 0.080)))

    # **The hem is cut before the sleeves go on.** A plane cut applies to the
    # whole solid, so cutting it afterwards takes the bottom off a long sleeve
    # as well as off the shirt -- the keeper had a bare arm from the shirt hem
    # down and a cuff floating at his hip. Ops run in order, so the sleeves are
    # simply added after it.
    shirt.cut(Plane((0.0, 0.0, h * SHIRT_HEM), (0.0, 0.0, 1.0)), k=h * 0.006)

    sleeve_end = h * (0.492 if not look.sleeves_long else 0.300)
    # A long sleeve has to arrive at the wrist about the width of the wrist. Run
    # down at the width it leaves the shoulder, it finishes in a cuff wider than
    # the hand below it, which reads as a bandage rather than a sleeve.
    cuff_r = limb * (1.15 if not look.sleeves_long else 1.00)
    for side in (-1.0, 1.0):
        # The shoulder: from beside the neck, out and **down**. Its top at the
        # neck end comes to the chin exactly, which is where the reference puts
        # the collar, and it has dropped a tenth of a metre by the time it
        # reaches the sleeve.
        # Fat enough to *be* the top of the shirt. Thin, it is a strap laid
        # over a barrel and the barrel's own top still shows as a ledge across
        # the chest.
        shirt.add(Capsule((side * w * 0.10, 0.0, h * 0.575),
                          (side * w * 0.56, 0.0, h * 0.545),
                          h * 0.084, h * 0.078), k=h * 0.028)
        # The sleeve hangs off that, angled out as it falls. Started further in
        # than the arm it would be narrower at the top than the arm inside it,
        # and the bare arm breaks out through it.
        # It **hangs**, at about seventy degrees off the horizontal, which is
        # what the reference does. Thrown out at forty-five it reads as a stub
        # stuck on the side of the shirt, and the widest point of the figure
        # ends up being the cuff instead of the shoulder.
        # About the arm's own thickness plus cloth. At limb*1.80 it was a puff
        # sleeve: the widest thing on the figure was the shirt's sleeve rather
        # than the man's arm, which is the wrong way round in every reference.
        shirt.add(Capsule((side * w * 0.64, 0.0, h * 0.560),
                          (side * w * 0.80, 0.0, sleeve_end),
                          limb * 1.45, cuff_r), k=h * 0.050)
        # The cuff, in the trim colour, standing a little proud of the sleeve.
        cuff_a = (side * w * 0.792, 0.0, sleeve_end + h * 0.018)
        cuff_b = (side * w * 0.80, 0.0, sleeve_end - h * 0.001)
        trim.add(Capsule(cuff_a, cuff_b, cuff_r * 1.10, cuff_r * 1.09))

    # The collar: the head's own jaw, enlarged, taken out of the shirt, so the
    # shirt hugs the jaw instead of disappearing inside it.
    hw = look.head_w * h
    hh = look.head_h * h
    hd = look.head_d * h
    mid = h * (CHIN + CROWN) * 0.5
    neck = RoundBox((0.0, -hd * 0.03, mid - hh * 0.44),
                    (hw * 0.86, hd * 0.90, hh * 0.46),
                    radius=look.head_round * h * 0.80)
    shirt.cut(neck, k=h * 0.014)

    # The V. **One shape, used twice**: the same pair of bars is cut out of the
    # shirt and added to the trim, so the white insert lands in the hole to the
    # millimetre. Sized and placed apart, the two drifted and the result was a
    # white badge floating in front of a shirt with no neckline in it.
    #
    # The trim sits a few millimetres behind the shirt's own surface, which is
    # what a neckline does -- the insert is under the shirt, not on it.
    # The cut reaches from outside the shirt to well inside it, so it opens a
    # hole rather than scoring a line.
    face = h * 0.088
    for prim in _vee_slabs(w, h, -face - h * 0.030, -face + h * 0.050):
        shirt.cut(prim, k=h * 0.009)
    for prim in _vee_slabs(w, h, -face - h * 0.030, -face + h * 0.075):
        collar.add(prim, k=h * 0.009)
    # **Clipped to the shirt's own surface**, three millimetres in. A flat slab
    # laid on a rounded chest touches it in one place: at the middle it is
    # buried and at the ends of the V it stands a centimetre out in front, which
    # is a badge, not a neckline. Following the curve is what `keep` is for.
    inset = h * 0.003
    # Clipped to the body tube and the shoulder both, because the V spans them.
    collar.keep_inside(shirt, inset)
    # And out of the collar hole, or the white shows round the back of the neck.
    collar.cut(neck, k=h * 0.006)

    # --- Shorts --------------------------------------------------------------
    # **A seat with two legs hanging off it**, not a block with a hole bored
    # through it. Cut as a bore, the gap between the legs is exactly that -- you
    # see daylight through a slab, and the inside of each leg is the wall of a
    # drilled hole rather than the inside of a leg. Two tubes fused into a seat
    # give a real crotch, and the fillet where they meet is the seam.
    #
    # The legs are as wide as the seat, so the garment has one straight line
    # down each side from the waist to the hem.
    shorts_round = h * 0.072
    crotch = h * (SHORTS_HEM + 0.070)
    shorts_high = h * SHIRT_HEM + h * 0.030
    # In from 0.66. `HIP_X` has the argument: the seat was the widest thing on
    # the figure and the shirt hem could not hang over it.
    seat_half = w * 0.600
    shorts.add(Barrel(
        (0.0, 0.0, (crotch + shorts_high) * 0.5),
        (seat_half, h * 0.082), (shorts_high - crotch) * 0.5,
        round=shorts_round))
    leg_r = w * 0.285
    for side in (-1.0, 1.0):
        leg_x = side * (seat_half - leg_r)
        shorts.add(Capsule((leg_x, 0.0, crotch + h * 0.030),
                           (leg_x, 0.0, h * SHORTS_HEM - leg_r),
                           leg_r, leg_r * 0.97), k=h * 0.038)
    shorts.cut(Plane((0.0, 0.0, h * SHORTS_HEM), (0.0, 0.0, 1.0)), k=h * 0.006)

    # --- Socks ---------------------------------------------------------------
    # Everyone wears them and they are pulled up. A flat top, level on both
    # legs, is the third of the three hard edges the kit is made of.
    for side in (-1.0, 1.0):
        top = (side * w * (ANKLE_X - 0.010), 0.0, h * (SOCK_TOP + 0.02))
        ankle = (side * w * ANKLE_X, 0.0, h * (BOOT_TOP - 0.005))
        socks.add(Capsule(top, ankle, limb * 1.52, limb * 1.28))
    socks.cut(Plane((0.0, 0.0, h * SOCK_TOP), (0.0, 0.0, -1.0)), k=h * 0.004)

    # The hoops: **a slab crossed with the sock's own shell**, the same trick as
    # the boot stripes and the neckline insert, and for the same reason.
    #
    # They used to be capsules a shade wider than the sock, placed on its centre
    # line. A capsule of radius r is a *ball* until its ends are further apart
    # than r, and these were 28 mm apart at a radius of 98 mm -- so each "hoop"
    # spanned 220 mm of a 280 mm sock, and two of them covered the leg. Worse,
    # at that radius the ball ran tangent to the sock for its whole length, so
    # the two surfaces were never more than a millimetre or two apart and any
    # thinning at all made them cross.
    #
    # **No render in this sandbox could have shown it**, and that is the part
    # worth remembering: every kit in `cast.KITS` paints the sock and the trim
    # the same colour, so a sock swallowed by its own hoops looks exactly like a
    # sock. It took a `.glb` painted from a real club's palette.
    #
    # A slab clipped to the sock is a band that follows the taper and the lean
    # for nothing, and it has a real thickness rather than a radius.
    for side in (-1.0, 1.0):
        for i in range(look.sock_hoops):
            at = h * (SOCK_TOP - 0.024 - i * 0.030)
            hoops.add(RoundBox((side * w * ANKLE_X, 0.0, at),
                               (limb * 2.2, limb * 2.2, h * 0.009),
                               radius=h * 0.0026))
    # Standing a little proud of it, the way the stripes stand off the boot.
    hoops.keep_inside(socks, -h * 0.0016)

    # --- Boots ---------------------------------------------------------------
    # A rounded wedge with the toe forward and the heel under the ankle, plus
    # three things off the reference that a plain wedge has not got: a **tongue**
    # standing proud of the instep, **stripes** laid across it, and **studs**
    # holding the sole clear of the ground.
    #
    # The studs matter more than they sound. Cut flat at zero the boot sits on
    # the floor like a clog; on studs it stands on six little feet with daylight
    # and a shadow under the sole, and that is most of what says football boot.
    sole = h * 0.017
    for side in (-1.0, 1.0):
        x = side * w * ANKLE_X
        # The last: heel under the ankle, toe forward and lower, so the boot is
        # a wedge rather than a sausage lying down. A broad round toe -- the
        # reference boot is wide and blunt at the front, never pointed.
        boots.add(Capsule((x, h * 0.040, h * 0.046), (x, -h * 0.122, h * 0.026),
                          limb * 1.38, limb * 1.02))
        # The ankle collar, kept low: the boot finishes below the sock top on
        # every one of the references, and a collar that reaches it is a
        # wellington.
        boots.add(Ellipsoid((x, h * 0.020, h * 0.046),
                            (limb * 1.30, limb * 1.10, limb * 1.05)), k=h * 0.024)
        # The tongue, rising off the instep towards the ankle. It is what the
        # stripes are laid over, and it is the part of a boot that reads first.
        boots.add(Ellipsoid((x, h * 0.012, h * 0.074),
                            (limb * 0.80, limb * 0.72, limb * 0.52)), k=h * 0.012)
    boots.cut(Plane((0.0, 0.0, sole), (0.0, 0.0, 1.0)), k=h * 0.005)

    # Studs, added after the sole is cut so the cut does not take them off with
    # it -- ops run in order, and a plane cut applies to the whole solid.
    for side in (-1.0, 1.0):
        x = side * w * ANKLE_X
        for at_y, spread in ((-h * 0.104, 0.52), (-h * 0.058, 0.62),
                             (h * 0.030, 0.42)):
            for out in (-1.0, 1.0):
                foot = (x + out * limb * spread, at_y, sole)
                boots.add(Capsule(foot, (foot[0], at_y, h * 0.004), limb * 0.30))
    boots.cut(Plane((0.0, 0.0, 0.0), (0.0, 0.0, 1.0)), k=h * 0.002)

    # The stripes: **a slab crossed with the boot's own shell**, the same trick
    # as the neckline insert. Laid on as free-standing bars they float off a
    # curved instep at their ends, and no amount of placing them by hand fixes
    # that on a surface this round.
    for side in (-1.0, 1.0):
        x = side * w * ANKLE_X
        for i in range(4):
            # On the **instep**, well in front of the ankle collar. The slab
            # runs across the whole boot, so any of it that reaches back as far
            # as the collar wraps round that too -- and four bands round a man's
            # ankle read as a bandage, not as stripes on a boot.
            t = 0.44 + i * 0.105
            stripes.add(RoundBox(
                (x, h * (0.040 - 0.162 * t),
                 h * (0.046 - 0.020 * t) + limb * 0.78),
                (limb * 2.0, h * 0.0030, limb * 0.72),
                radius=h * 0.0026,
                rotation=(0.140, side * 0.16, 0.0)))
    stripes.keep_inside(boots, -h * 0.0018)
    # And taken off below the instep. A slab crossed with the boot gives a whole
    # cross-section, which closes into a **ring** round the foot -- four of them
    # read as a bandage. A stripe stops at the sides.
    stripes.cut(Plane((0.0, 0.0, h * 0.050), (0.0, 0.0, 1.0)), k=h * 0.004)


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
    # Measured off reference 1: the white V is about **thirty per cent** of the
    # shirt's width and only a fifth of its height. Ours was twice that across
    # and half the chest deep, which is a bib.
    top = h * 0.600
    point = h * 0.548
    reach = w * 0.23
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
