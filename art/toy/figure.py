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

The head is the one thing worth reading twice. `PLAN.md` §9.3 wants the face
drawn on a texture and swapped for expression, and the brows and the nose
moulded -- so the skull carries no features at all, a `Face` patch laid on the
front carries the atlas, and `Brows` is two bars the game poses. That is where
the variety comes from: one head, five hundred faces.
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

# How round each thing is in plan: 2 is an ellipse, 4 a rounded rectangle. The
# head is the one that matters -- a ball head is the single easiest way to lose
# the register, and the references are emphatically boxes with the corners off.
HEAD_POWER = 2.6
TRUNK_POWER = 2.4
LIMB_POWER = 2.0

# Segments round a part. The head and the trunk carry the silhouette; a sock
# seen from twenty metres does not.
FINE = 16
COARSE = 10

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
BROW_STAND = 0.020
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
        M.Ring(h * SHIRT_HEM, w * 0.620, h * 0.088, hard=True),
        M.Ring(h * 0.400, w * 0.624, h * 0.088),
        M.Ring(h * 0.470, w * 0.628, h * 0.086),
        M.Ring(h * 0.520, w * 0.640, h * 0.082),
        # The torso stops at the armpit and **the sleeve is the shoulder**.
        # Tried the other way round -- one tube carrying the shoulder out to the
        # arm -- and a ring wide enough to reach the sleeve has to come back in
        # again above it, which folds the shirt over itself and leaves a notch
        # of daylight at each shoulder. `drop` is still what makes this a
        # shoulder and not a dome: about twenty degrees out to the arm, which is
        # what the reference measures.
        M.Ring(h * 0.556, w * 0.645, h * 0.078),
        M.Ring(h * 0.578, w * 0.720, h * 0.068, drop=h * 0.030),
        M.Ring(h * 0.598, w * 0.560, h * 0.052, drop=h * 0.020),
        M.Ring(h * 0.612, w * 0.300, h * 0.040, drop=h * 0.006),
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
        M.Ring(h * 0.592, w * 0.21, w * 0.20),
        M.Ring(h * 0.648, w * 0.22, w * 0.21),
    ], segs, SKIN, power=2.6, name="neck"))

    # The shorts, seat only: the legs hang off the hips and run up inside this,
    # so the two never share a surface and the notch between them is real.
    fig.put("Spine", M.tube([
        M.Ring(h * 0.300, w * 0.630, h * 0.078, hard=True),
        M.Ring(h * 0.318, w * 0.658, h * 0.082),
        M.Ring(h * 0.386, w * 0.660, h * 0.082),
        M.Ring(h * 0.412, w * 0.628, h * 0.078),
        M.Ring(h * 0.424, w * 0.560, h * 0.070),
    ], segs, SHORTS, power=TRUNK_POWER, name="seat"))


def _vee(shirt, w, h):
    """Paints the neckline into the shirt's front faces.

    Measured off the reference: thirty per cent of the shirt's width and a fifth
    of its height, which is half what it was first built at.
    """
    top = h * 0.604
    depth = h * 0.046
    half = w * 0.230
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
    (0.630, 0.60, -0.05, 2.6),
    (0.660, 0.84, -0.04, 2.9),
    (0.700, 0.95, -0.02, None),
    (0.745, 1.00, 0.00, None),
    (0.800, 1.00, 0.00, None),
    (0.856, 0.97, 0.00, None),
    (0.902, 0.86, 0.00, None),
    (0.932, 0.64, 0.00, 2.6),
    (0.950, 0.26, 0.00, 2.2),
]


def skull_rings(look, h, scale=1.0, lift=0.0, back=0.0, first=0, squash=1.0):
    hw = look.head_w * h * scale
    hd = look.head_d * h * scale
    base = h * SKULL[first][0]
    out = []
    for z, s, cy, power in SKULL[first:]:
        out.append(M.Ring(base + (h * z - base) * squash + lift,
                          hw * s, hd * s,
                          cy=hd * cy + back, power=power))
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
    for side in (-1.0, 1.0):
        fig.put("Head", M.blob((side * hw * 0.99, -hd * 0.02, h * 0.792),
                               (hw * 0.10, hd * 0.20, hd * 0.20),
                               coarse, coarse // 2, SKIN, name="ear"))

    # The nose is geometry, never a drawn mark: at this size a drawn one is a
    # smudge and a bump catches the light and does the whole job.
    nose = look.nose * h
    fig.put("Head", M.blob((0.0, -hd * 0.96, h * 0.764),
                           (nose * 0.90, nose * 1.05, nose * 1.25),
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
    rows, cols = max(6, segs - 4), max(6, segs - 4)
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
    scale = np.interp(z, [0.630, 0.660, 0.700, 0.745, 0.800, 0.856, 0.902, 0.932],
                      [0.60, 0.84, 0.95, 1.00, 1.00, 0.97, 0.86, 0.64])
    cy = np.interp(z, [0.630, 0.700, 0.745], [-0.05, -0.02, 0.0]) * hd
    rx, ry = hw * scale, hd * scale
    if rx <= 0.0 or ry <= 0.0:
        return False
    e = HEAD_POWER
    return (abs(p[0] / rx) ** e + abs((p[1] - cy) / ry) ** e) <= 1.0


# --- Arms --------------------------------------------------------------------

def _arms(fig, look, h, w, limb, segs):
    for side in (-1.0, 1.0):
        tag = "L" if side < 0.0 else "R"
        shoulder = np.array([side * w * 0.68, 0.0, h * 0.545])
        arm_top = np.array([side * w * 0.74, 0.0, h * 0.515])
        wrist = np.array([side * w * 0.90, 0.0, h * 0.295])
        elbow = arm_top + (wrist - arm_top) * 0.56
        hand = np.array([side * w * 0.92, 0.0, h * 0.258])

        # Upper arm, from inside the shoulder down past the elbow: a limb is
        # built long at both ends and buried in its neighbours, which is what
        # keeps a bend from opening.
        upper = M.tube([
            M.Ring(0.0, limb * 0.94, limb * 0.94),
            M.Ring(0.30, limb * 0.93, limb * 0.93),
            M.Ring(1.06, limb * 0.88, limb * 0.88),
        ], segs, SKIN, power=LIMB_POWER, name="upper")
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
        sleeve.transform(M.along(shoulder, elbow))
        fig.put("Shoulder" + tag, sleeve)

        fore = M.tube([
            M.Ring(-0.30, limb * 0.88, limb * 0.88),
            M.Ring(0.20, limb * 0.84, limb * 0.84),
            M.Ring(0.86, limb * 0.80, limb * 0.80),
        ], segs, SKIN, power=LIMB_POWER, name="fore")
        fore.transform(M.along(elbow, hand))
        fig.put("Elbow" + tag, fore)

        # A mitten, with a thumb. No fingers -- the reference has none, and the
        # thumb is the whole of what says hand rather than end of an arm.
        fig.put("Elbow" + tag, M.blob(
            (hand[0], 0.0, hand[2]), (limb * 1.10, limb * 1.00, limb * 1.26),
            segs, segs // 2, SKIN, name="hand"))
        fig.put("Elbow" + tag, M.blob(
            (hand[0] - side * limb * 0.74, -limb * 0.32, hand[2] + limb * 0.28),
            (limb * 0.44, limb * 0.50, limb * 0.74),
            max(6, segs - 2), max(4, segs // 2 - 1), SKIN, name="thumb"))


# --- Legs --------------------------------------------------------------------

def _legs(fig, look, h, w, limb, segs):
    for side in (-1.0, 1.0):
        tag = "L" if side < 0.0 else "R"
        hip = np.array([side * w * 0.40, 0.0, h * 0.305])
        ankle = np.array([side * w * 0.44, 0.0, h * BOOT_TOP])
        knee = hip + (ankle - hip) * 0.548

        # Thigh, bare between the shorts and the sock.
        thigh = M.tube([
            M.Ring(-0.20, limb * 1.28, limb * 1.28),
            M.Ring(0.30, limb * 1.26, limb * 1.26),
            M.Ring(1.10, limb * 1.20, limb * 1.20),
        ], segs, SKIN, power=LIMB_POWER, name="thigh")
        thigh.transform(M.along(hip, knee))
        fig.put("Hip" + tag, thigh)

        # The leg of the shorts: up inside the seat, and hanging lower than it,
        # which is what puts a notch between the legs rather than a skirt.
        leg = M.tube([
            M.Ring(h * SHORTS_HEM, w * 0.300, w * 0.290, hard=True),
            M.Ring(h * 0.262, w * 0.306, w * 0.296),
            M.Ring(h * 0.352, w * 0.312, w * 0.302),
        ], segs, SHORTS, power=2.2, name="shorts_leg")
        leg.translate((side * w * 0.335, 0.0, 0.0))
        fig.put("Hip" + tag, leg)

        # Sock: a flat top, level on both legs, and its hoops are two of its own
        # bands. Nothing is laid on it, so nothing can come adrift from it.
        hoop = look.sock_hoops
        rings = [M.Ring(0.02, limb * 1.36, limb * 1.36),
                 M.Ring(0.10, limb * 1.42, limb * 1.42),
                 M.Ring(0.24, limb * 1.48, limb * 1.48)]
        at = 0.34
        for _ in range(max(0, min(hoop, 3))):
            rings.append(M.Ring(at, limb * 1.50, limb * 1.50))
            rings.append(M.Ring(at + 0.075, limb * 1.51, limb * 1.51, material=TRIM))
            at += 0.150
        rings.append(M.Ring(min(at + 0.06, 0.94), limb * 1.52, limb * 1.52))
        rings.append(M.Ring(1.0, limb * 1.52, limb * 1.52, hard=True))
        sock = M.tube(rings, segs, SHIRT, power=LIMB_POWER, name="sock")
        # Built up the leg from the ankle so the hoops sit near the top.
        sock.transform(M.along(ankle - (knee - ankle) * 0.06,
                               ankle + (hip - ankle) * 0.62))
        fig.put("Knee" + tag, sock)

        fig.put("Ankle" + tag, _boot(side, w, h, limb, segs))


def _boot(side, w, h, limb, segs):
    """A wedge with the heel under the ankle and a broad blunt toe.

    The studs matter more than they sound: cut flat the boot sits on the floor
    like a clog, and on studs it stands with daylight and a shadow under the
    sole, which is most of what says football boot.
    """
    x = side * w * 0.44
    rings = [
        M.Ring(-h * 0.130, limb * 0.66, limb * 0.44, cy=h * 0.008),
        M.Ring(-h * 0.100, limb * 1.16, limb * 0.62, cy=h * 0.004),
        M.Ring(-h * 0.070, limb * 1.32, limb * 0.74),
    ]
    # The stripes, as bands of the boot's own surface. Three of them, and they
    # stop before the ankle collar: carried round that too, four bands read as a
    # bandage rather than as stripes on a boot.
    at = -h * 0.058
    for _ in range(3):
        rings.append(M.Ring(at, limb * 1.34, limb * 0.80))
        rings.append(M.Ring(at + h * 0.009, limb * 1.35, limb * 0.82,
                            material=TRIM))
        at += h * 0.021
    rings += [
        M.Ring(h * 0.004, limb * 1.34, limb * 0.92),
        M.Ring(h * 0.032, limb * 1.26, limb * 0.98),
        M.Ring(h * 0.054, limb * 1.10, limb * 0.94),
    ]
    # Built lying down: the rings run front to back, so `power` is the section
    # of the foot and the last ring is the ankle collar.
    boot = M.tube(rings, segs, BOOT, power=2.6, name="boot")
    boot.transform(M.rotation_x(math.radians(-90.0)))
    boot.transform(M.translation((x, 0.0, h * 0.052)))
    for at_y, spread in ((-h * 0.100, 0.55), (-h * 0.056, 0.62), (h * 0.026, 0.44)):
        for out in (-1.0, 1.0):
            boot.merge(M.tube([
                M.Ring(0.0, limb * 0.26, limb * 0.26, hard=True),
                M.Ring(h * 0.016, limb * 0.30, limb * 0.30),
            ], max(5, segs // 2), BOOT, power=2.0, name="stud")
                .translate((x + out * limb * spread, at_y, 0.0)))
    return boot
