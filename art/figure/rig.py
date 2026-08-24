"""The joints a built figure has to answer to, and which part of it is whose.

`docs/THE_MODELS.md` names sixteen nodes the match animation poses **by name**.
The mouldings in `body.py` are split by *colour* -- one `skin` solid holds the
head, both arms and both legs, and `trim` runs from the sock hoops to the
collar -- so an export has to cut them a second way, by joint, or nothing in
the view can bend the figure.

**The cut is a Voronoi of bones.** Every point belongs to the bone it is
nearest, where near means distance to that bone's own segment less that bone's
radius. Nothing is placed by hand, and nothing can be dropped: the cells cover
the whole of space, so every scrap of a moulding lands somewhere. The radius is
the one tuning knob and it means what it says -- a fat bone claims more.

Each cell is then **dilated by an overlap**, so two neighbouring parts share a
shell of solid instead of meeting on one surface. Two coincident surfaces
flicker, and a bend that opens a gap shows daylight through the man; a shell of
overlap costs nothing and does neither.

**Rest angles are baked into the mesh, never into a node.**
`match_view_3d._rotate` assigns `rotation` outright, so a rest angle on a joint
is wiped the moment a man moves. The arms hang a few degrees out and the feet
turn out because `body.py` moulded them that way, and every joint here is
built square.

What this file does **not** produce, and the contract asks for: `Face` (the
atlas needs a face-shaped surface and this figure has its eyes and mouth
moulded into the head) and `Brows` (they live inside the `hair` solid, at the
brow, and no bone can tell them from a fringe). Both want a change in `body.py`
first -- see `docs/THE_MODELS.md`.
"""

import numpy as np

from .body import ANKLE_X, ARM_IN, HIP_X
from .sdf import Capsule, Prim


class Joint:
    """One posed node: where its pivot is, and the bone whose mass moves with it.

    `bone` is None for a pivot that carries no geometry of its own -- the neck,
    which on this figure is a place the head turns about and nothing else.
    """

    def __init__(self, name, parent, pivot, bone=None, depth=0):
        self.name = name
        self.parent = parent
        self.pivot = np.asarray(pivot, dtype=np.float64)
        self.bone = bone
        # How far out from the trunk this joint hangs, and the reason it is
        # recorded: two parts sharing an overlap hold **the same stretch of the
        # same surface twice**, and once they are thinned the two copies cross
        # and streak. Whichever of them is further out is inset by a little
        # more, so at every seam one surface is plainly in front of the other
        # and there is nothing left to fight over.
        self.depth = depth


def _along(a, b, t):
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    return tuple(a + (b - a) * t)


# Where on the body each moulding is allowed to land. `None` is anywhere.
#
# **Nearest bone alone is not enough, and the arm is why.** It hangs beside the
# hip, so the top corner of the shorts is nearer the upper arm than it is to
# the spine, and a chunk of waistband went up the sleeve. The same happens at
# the collar, where the shirt's shoulder capsules reach past the chin before
# the collar hole is cut out of them, and the skull claims them.
#
# A garment covers a part of a man and saying which part is one line each. The
# Voronoi is computed per moulding, so a shirt with no arm bones to be nearest
# to is not cut short -- it simply has fewer cells to fall into, and still
# fills all of them.
#
# Names match by prefix, so `Hip` covers `HipL` and `HipR`.
WHERE = {
    "skin": None,          # the man himself, and he is all of it
    "trim": None,          # cuffs, neckline and sock hoops: all over him
    "hair": ("Head",),
    "ink": ("Head",),
    "collar": ("Spine",),
    "shirt": ("Spine", "Shoulder", "Elbow"),
    "shorts": ("Spine", "Hip"),
    "socks": ("Hip", "Knee", "Ankle"),
    "hoops": ("Hip", "Knee", "Ankle"),
    "boots": ("Ankle",),
    "stripes": ("Ankle",),
}


def carries(joint_name: str, solid_name: str) -> bool:
    """May this joint hold a piece of this moulding?"""
    where = WHERE.get(solid_name)
    if where is None:
        return True
    return any(joint_name.startswith(prefix) for prefix in where)


def skeleton(look, h):
    """The sixteen joints, in world metres, for this man at this height.

    Every number is read off `body.py`'s own constants: the pivots sit where
    that file already put the top of an arm, the crotch, the sock top. A pivot
    moved here and not there is a joint in the middle of nothing.
    """
    w = look.width() * h
    limb = look.limb() * h
    joints = []

    # --- Trunk ---------------------------------------------------------------
    # The waist, a little above the crotch: the shorts seat leans with the man
    # and the legs do not, which is where `SimCharacterBuilder` puts the split
    # too -- its hips hang off the root, not off the spine.
    spine_at = (0.0, 0.0, h * 0.335)
    joints.append(Joint("Spine", "Player", spine_at, Capsule(
        spine_at, (0.0, 0.0, h * 0.560), w * 0.55, w * 0.50), depth=0))

    # No neck on this figure and none wanted -- the references have the head
    # sitting straight on the shoulders. This is the pivot it turns about.
    joints.append(Joint("Neck", "Spine", (0.0, 0.0, h * 0.600), depth=1))

    head_at = (0.0, 0.0, h * 0.628)
    joints.append(Joint("Head", "Neck", head_at, Capsule(
        (0.0, 0.0, h * 0.660), (0.0, 0.0, h * 0.920), h * 0.160), depth=2))

    for side in (-1.0, 1.0):
        tag = "L" if side < 0.0 else "R"

        # --- Arm -------------------------------------------------------------
        # The shoulder pivot is **not** the top of the arm capsule. Put there,
        # the sleeve -- which hangs off the shirt's shoulder slope, above and
        # inboard of the arm -- falls outside the arm's cell and stays behind
        # when the arm lifts. Set inside the sleeve, the sleeve goes with it.
        shoulder_at = (side * w * (0.68 - ARM_IN), 0.0, h * 0.545)
        arm_top = (side * w * (0.74 - ARM_IN), 0.0, h * 0.515)
        wrist = (side * w * (0.90 - ARM_IN), 0.0, h * 0.295)
        elbow_at = _along(arm_top, wrist, 0.56)
        hand_at = (side * w * (0.92 - ARM_IN), 0.0, h * 0.258)

        joints.append(Joint("Shoulder" + tag, "Spine", shoulder_at, Capsule(
            shoulder_at, elbow_at, limb * 1.55, limb * 1.15), depth=1))
        joints.append(Joint("Elbow" + tag, "Shoulder" + tag, elbow_at, Capsule(
            elbow_at, hand_at, limb * 1.15, limb * 1.35), depth=2))

        # --- Leg -------------------------------------------------------------
        # `body.HIP_X` and `body.ANKLE_X`, not copies of them: a pivot that
        # does not sit where the leg was built is a joint in the middle of
        # nothing, and this file said so about the numbers it was duplicating.
        hip_at = (side * w * HIP_X, 0.0, h * 0.305)
        ankle_at = (side * w * ANKLE_X, 0.0, h * 0.095)
        knee_at = _along(hip_at, ankle_at, 0.548)
        # Forward and down, under the instep: the boot is a wedge with its heel
        # under the ankle, so a bone straight down would leave the toe nearer
        # the shin than the foot.
        toe = (side * w * ANKLE_X, -h * 0.100, h * 0.030)

        # Fat enough to take the leg of the shorts with the thigh. The tube is
        # w*0.31 across, which is about the same as limb*1.75 at any build.
        joints.append(Joint("Hip" + tag, "Player", hip_at, Capsule(
            hip_at, knee_at, limb * 1.75, limb * 1.60), depth=1))
        # The sock is limb*1.52 at its top. A thinner bone than that and the
        # thigh claims the shin through it.
        joints.append(Joint("Knee" + tag, "Hip" + tag, knee_at, Capsule(
            knee_at, ankle_at, limb * 1.60, limb * 1.55), depth=2))
        joints.append(Joint("Ankle" + tag, "Knee" + tag, ankle_at, Capsule(
            ankle_at, toe, limb * 1.35), depth=3))

    return joints


class Cell(Prim):
    """The volume nearer one bone than any other, dilated by `overlap`.

    Not a distance -- it is the difference of two distances, so it runs up to
    twice as steep. That is fine and only here: every surface it makes is an
    interior seam buried in the next part along, and the sign is what decides
    which side of the seam a sample is on.

    `box` is a hard clip as well as a grid bound, because `Solid.field` fills
    everything outside a kept shape's own bounds with far. `split.py` measures
    it off the solid rather than guessing it, so nothing can be quietly lost
    outside it.
    """

    def __init__(self, mine, others, overlap, box):
        super().__init__((0.0, 0.0, 0.0))
        self.mine = mine
        self.others = list(others)
        self.overlap = float(overlap)
        self.box = (np.asarray(box[0], dtype=np.float64),
                    np.asarray(box[1], dtype=np.float64))

    def reach(self):  # pragma: no cover - bounds is overridden
        return (self.box[1] - self.box[0]) * 0.5

    def bounds(self):
        return self.box

    def distance(self, x, y, z):
        mine = self.mine.distance(x, y, z)
        if not self.others:
            return np.full(np.broadcast(x, y, z).shape, -self.overlap,
                           dtype=np.float32)
        worst = None
        for other in self.others:
            gap = mine - other.distance(x, y, z)
            worst = gap if worst is None else np.maximum(worst, gap, out=worst)
        return (worst - np.float32(self.overlap)).astype(np.float32)
