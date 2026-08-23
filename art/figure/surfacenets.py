"""Turns a sampled distance field into a quad mesh. Naive surface nets.

Marching cubes would do the same job and give triangles with a 256-case table.
Surface nets gives **quads**, in about sixty lines, and quads are what a
subdivision surface wants -- which matters here, because the last step of every
part is to smooth it.

The rule is one vertex per cell that the surface passes through, placed at the
average of the crossings on that cell's twelve edges, and one quad per grid edge
that changes sign, joining the four cells around it. Averaging the crossings is
also a free half-pass of smoothing, which is why the output is already close to
the moulded surface wanted rather than a staircase.

Winding is not worried about here: `bmesh.ops.recalc_face_normals` sorts it out
once, on a watertight mesh, and cannot get it wrong.
"""

import numpy as np

CORNERS = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0),
           (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)]

EDGES = [(0, 1), (2, 3), (4, 5), (6, 7),
         (0, 2), (1, 3), (4, 6), (5, 7),
         (0, 4), (1, 5), (2, 6), (3, 7)]


def _corner(field, offset):
    n = field.shape
    return field[offset[0]:offset[0] + n[0] - 1,
                 offset[1]:offset[1] + n[1] - 1,
                 offset[2]:offset[2] + n[2] - 1]


def mesh(field, origin, cell):
    """(distances, world origin, cell size) -> (verts Nx3, quads Mx4)."""
    corners = [_corner(field, o) for o in CORNERS]
    shape = corners[0].shape

    acc = np.zeros(shape + (3,), dtype=np.float32)
    hits = np.zeros(shape, dtype=np.float32)

    for a, b in EDGES:
        da = corners[a]
        db = corners[b]
        crossing = (da < 0.0) != (db < 0.0)
        if not crossing.any():
            continue
        gap = da - db
        t = np.where(np.abs(gap) > 1e-12, da / np.where(np.abs(gap) > 1e-12, gap, 1.0), 0.5)
        np.clip(t, 0.0, 1.0, out=t)
        oa, ob = CORNERS[a], CORNERS[b]
        for axis in range(3):
            if oa[axis] == ob[axis]:
                acc[..., axis] += np.where(crossing, float(oa[axis]), 0.0)
            else:
                along = oa[axis] + t * (ob[axis] - oa[axis])
                acc[..., axis] += np.where(crossing, along, 0.0)
        hits += crossing

    live = hits > 0.0
    count = int(live.sum())
    if count == 0:
        return np.zeros((0, 3), np.float32), np.zeros((0, 4), np.int64)

    index = np.full(shape, -1, dtype=np.int64)
    index[live] = np.arange(count, dtype=np.int64)

    cells = np.argwhere(live).astype(np.float32)
    local = acc[live] / hits[live][:, None]
    verts = (cells + local) * np.float32(cell) + np.asarray(origin, dtype=np.float32)

    inside = field < 0.0
    quads = []
    # An x-edge is shared by the four cells around it, and so on for y and z.
    # The interior slices are what keeps all four of them in range.
    quads.append(_quads(
        inside[:-1, 1:-1, 1:-1] != inside[1:, 1:-1, 1:-1],
        index[:, :-1, :-1], index[:, 1:, :-1], index[:, 1:, 1:], index[:, :-1, 1:]))
    quads.append(_quads(
        inside[1:-1, :-1, 1:-1] != inside[1:-1, 1:, 1:-1],
        index[:-1, :, :-1], index[1:, :, :-1], index[1:, :, 1:], index[:-1, :, 1:]))
    quads.append(_quads(
        inside[1:-1, 1:-1, :-1] != inside[1:-1, 1:-1, 1:],
        index[:-1, :-1, :], index[1:, :-1, :], index[1:, 1:, :], index[:-1, 1:, :]))

    faces = np.concatenate([q for q in quads if len(q)], axis=0) if any(
        len(q) for q in quads) else np.zeros((0, 4), np.int64)
    return verts, faces


def _quads(crossing, a, b, c, d):
    keep = crossing & (a >= 0) & (b >= 0) & (c >= 0) & (d >= 0)
    if not keep.any():
        return np.zeros((0, 4), np.int64)
    return np.stack([a[keep], b[keep], c[keep], d[keep]], axis=1)
