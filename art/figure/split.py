"""Cutting the mouldings a second way: by joint.

`body.py` splits the figure by **colour** -- one solid per moulding, because a
solid is the unit of colour as well as of geometry. The game splits it by
**joint**, because that is what it can bend. This turns one into the other:
given a moulding and a skeleton, it hands back the pieces of that moulding and
the joint each piece belongs to.

The clip boxes are **measured, not guessed.** The solid is sampled once on a
coarse grid, every sample inside it is handed to the bone whose cell it falls
in, and a part's box is the extent of its own samples. A box has to be a hard
clip -- `Solid.field` fills everything outside a kept shape's bounds with far --
so a box that missed material would saw a flat face across a limb, and a
guessed one does that eventually.
"""

import numpy as np

from .rig import Cell, carries
from .sdf import Solid


def parts(solid, joints, cell, overlap=None, inset=0.010, coarse=None):
    """[(joint, clipped Solid)] for one moulding. Empty pieces are dropped.

    `overlap` is how far each part reaches into its neighbours. Two parts
    meeting on **one** surface open a crack the moment the joint between them
    bends, and daylight through a man is the worst of the three things that can
    go wrong here; a shell of shared solid costs nothing and shuts it.

    `inset` is the price of that shell and the cure for it. Inside the overlap
    the two parts hold the same stretch of the same surface twice, and once
    they are thinned to a triangle budget the two copies cross and streak. So
    the seam is taken with a **smooth** intersection rather than a hard one,
    which draws a part's surface in as it approaches its own seam, and the
    amount is `inset` per step out from the trunk -- an ankle is drawn in more
    than a knee, a knee more than a hip. At every seam the part nearer the
    trunk is plainly the one in front, and there is nothing left to fight over.
    Zero puts the hard cut back.
    """
    overlap = 2.0 * cell if overlap is None else overlap
    coarse = 2.5 * cell if coarse is None else coarse

    usable = [j for j in joints
              if j.bone is not None and carries(j.name, solid.name)]
    if not usable:
        return []

    grid, origin, step = solid.field(coarse)
    inside = np.argwhere(grid < 0.0)
    if len(inside) == 0:
        return []
    points = np.asarray(origin) + inside * step
    x, y, z = points[:, 0], points[:, 1], points[:, 2]

    if len(usable) == 1:
        near = np.stack([np.zeros(len(points), dtype=np.float32)])
    else:
        near = np.stack([j.bone.distance(x, y, z) for j in usable])

    out = []
    # A part's box has to hold its **dilated** cell, so the dilation is applied
    # here too rather than allowed for with a margin: the margin is only the
    # coarse grid's own step and a few of the fine one's.
    margin = step + 3.0 * cell
    for i, joint in enumerate(usable):
        if len(usable) == 1:
            mask = np.ones(len(points), dtype=bool)
        else:
            best_other = np.delete(near, i, axis=0).min(axis=0)
            mask = (near[i] - best_other) < overlap
        if not mask.any():
            continue
        mine = points[mask]
        box = (mine.min(axis=0) - margin, mine.max(axis=0) + margin)
        piece = Solid("%s_%s" % (joint.name, solid.name))
        piece.ops = list(solid.ops)
        piece.keep(Cell(joint.bone,
                        [o.bone for k, o in enumerate(usable) if k != i],
                        overlap, box),
                   k=inset * joint.depth)
        out.append((joint, piece))
    return out
