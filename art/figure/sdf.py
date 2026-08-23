"""Signed distance fields, and the smooth union that makes a moulded toy.

Why this and not a bag of primitives parented together: two spheres pushed into
each other **intersect**, and an intersection is a crease. A moulded object has
a **fillet** -- the surface leaves one form and arrives at the other along a
curve, and the size of that curve is the single strongest signal that a thing
came out of a mould rather than being assembled.

`Solid.add(prim, k)` is that fillet, and `k` is its radius in metres. It is the
one number worth playing with in this whole file: 0 is a hard intersection, 0.02
on a head is a jaw that flows into a skull, 0.06 is a snowman.

`cut` is the same operation upside down, and it is how the face is made: an eye
socket is a sphere taken *out* of the head with a small fillet, which leaves a
soft rim round it exactly like moulded vinyl. Nothing here is drawn.

Each solid sizes its own grid to its own bounding box, so the shirt does not pay
for the height of the man wearing it.
"""

import numpy as np

FAR = np.float32(1e9)


def _rot(rotation):
    """Euler XYZ in radians -> a 3x3 world-to-local matrix, or None."""
    if rotation is None:
        return None
    rx, ry, rz = rotation
    cx, sx = np.cos(rx), np.sin(rx)
    cy, sy = np.cos(ry), np.sin(ry)
    cz, sz = np.cos(rz), np.sin(rz)
    m = np.array([
        [cy * cz, sx * sy * cz - cx * sz, cx * sy * cz + sx * sz],
        [cy * sz, sx * sy * sz + cx * cz, cx * sy * sz - sx * cz],
        [-sy, sx * cy, cx * cy],
    ], dtype=np.float64)
    return m.T  # world -> local is the transpose of local -> world


class Prim:
    """A shape that can say how far away it is and where it lives."""

    def __init__(self, centre=(0.0, 0.0, 0.0), rotation=None):
        self.centre = np.asarray(centre, dtype=np.float64)
        self.inv = _rot(rotation)

    def local(self, x, y, z):
        px = x - self.centre[0]
        py = y - self.centre[1]
        pz = z - self.centre[2]
        if self.inv is None:
            return px, py, pz
        m = self.inv
        return (m[0, 0] * px + m[0, 1] * py + m[0, 2] * pz,
                m[1, 0] * px + m[1, 1] * py + m[1, 2] * pz,
                m[2, 0] * px + m[2, 1] * py + m[2, 2] * pz)

    def reach(self):
        """Half-extent in local axes; rotation is handled by taking the worst case."""
        raise NotImplementedError

    def bounds(self):
        r = np.asarray(self.reach(), dtype=np.float64)
        if self.inv is not None:
            # A rotated box fits inside a sphere of its own diagonal. Loose, and
            # loose is free -- it only pads a grid that is thrown away.
            r = np.full(3, float(np.linalg.norm(r)))
        return self.centre - r, self.centre + r


class Ellipsoid(Prim):
    """A ball with three radii. The workhorse: a skull, a jaw, a hand, a curl."""

    def __init__(self, centre, radii, rotation=None):
        super().__init__(centre, rotation)
        self.radii = np.asarray(
            radii if hasattr(radii, "__len__") else (radii,) * 3, dtype=np.float64)

    def reach(self):
        return self.radii

    def distance(self, x, y, z):
        px, py, pz = self.local(x, y, z)
        rx, ry, rz = self.radii
        return _ellipse_distance(
            (px / rx, py / ry, pz / rz),
            (px / (rx * rx), py / (ry * ry), pz / (rz * rz)),
            float(min(rx, ry, rz)))


class Capsule(Prim):
    """A line segment with a thickness. Exact, and so it blends cleanly."""

    def __init__(self, a, b, radius, radius_b=None):
        a = np.asarray(a, dtype=np.float64)
        b = np.asarray(b, dtype=np.float64)
        super().__init__((a + b) * 0.5)
        self.a = a
        self.b = b
        self.ra = float(radius)
        self.rb = float(radius if radius_b is None else radius_b)

    def reach(self):
        half = np.abs(self.b - self.a) * 0.5
        return half + max(self.ra, self.rb)

    def distance(self, x, y, z):
        ax, ay, az = self.a
        bax, bay, baz = self.b - self.a
        px = x - ax
        py = y - ay
        pz = z - az
        ll = bax * bax + bay * bay + baz * baz
        t = np.clip((px * bax + py * bay + pz * baz) / max(ll, 1e-12), 0.0, 1.0)
        dx = px - bax * t
        dy = py - bay * t
        dz = pz - baz * t
        r = self.ra + (self.rb - self.ra) * t
        return (np.sqrt(dx * dx + dy * dy + dz * dz) - r).astype(np.float32)


class RoundBox(Prim):
    """A box with its corners already rounded off.

    The one primitive a bag of spheres cannot fake: it has **flat sides and a
    flat hem**, which is most of what makes a pair of shorts read as clothing
    rather than as an inner tube.
    """

    def __init__(self, centre, half, radius=0.0, rotation=None):
        super().__init__(centre, rotation)
        self.half = np.asarray(half, dtype=np.float64)
        # **Clamped, and it has to be.** The distance below subtracts the radius
        # from each half-extent; ask for a radius larger than the smallest one
        # and that term goes negative, so the box *inflates* along that axis
        # instead of rounding. It stays a closed surface, which is why it went
        # unnoticed -- the jaw was built that way and came out both too big and
        # oddly square.
        self.radius = float(min(radius, float(np.min(self.half)) * 0.999))

    def reach(self):
        return self.half + self.radius

    def distance(self, x, y, z):
        px, py, pz = self.local(x, y, z)
        qx = np.abs(px) - (self.half[0] - self.radius)
        qy = np.abs(py) - (self.half[1] - self.radius)
        qz = np.abs(pz) - (self.half[2] - self.radius)
        mx = np.maximum(qx, 0.0)
        my = np.maximum(qy, 0.0)
        mz = np.maximum(qz, 0.0)
        outside = np.sqrt(mx * mx + my * my + mz * mz)
        inside = np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0.0)
        return (outside + inside - self.radius).astype(np.float32)


class Barrel(Prim):
    """An upright cylinder with an **elliptical** cross-section and eased edges.

    The primitive a torso actually wants. A rounded box has flat faces front and
    back however far its corners are taken in -- ease them enough to lose the
    flats and the whole upper half becomes a dome instead. At any three-quarter
    angle those flats read as a slab, which is what "still very boxy" is.

    An oval in plan, straight up the sides, and rounded where the sides meet the
    ends -- so a plane cut across the bottom still leaves a hem you can see.

    `radii` and `half_height` are the outer dimensions; `round` eases the top and
    bottom edges and is measured inwards from them.
    """

    def __init__(self, centre, radii, half_height, round=0.0, top=None,
                 rotation=None):
        super().__init__(centre, rotation)
        self.radii = np.asarray(radii, dtype=np.float64)
        # `top` tapers the section towards the shoulder, which is what a shirt
        # actually does. It is the honest way to close the crease where the
        # sleeve joins: bring the torso *in* to meet the arm rather than pushing
        # the shoulder out to meet the torso, which leaves a figure that is
        # crease-free and far too deep to look at from the side.
        self.top = self.radii if top is None else np.asarray(top, dtype=np.float64)
        self.half_height = float(half_height)
        # Only the height is limited: the section is no longer shrunk by this,
        # so a rim larger than the depth is merely a very round rim.
        self.round = float(min(round, self.half_height) * 0.999)

    def reach(self):
        return np.array([max(self.radii[0], self.top[0]),
                         max(self.radii[1], self.top[1]), self.half_height])

    def distance(self, x, y, z):
        px, py, pz = self.local(x, y, z)
        rise = np.clip((pz + self.half_height) / (2.0 * self.half_height), 0.0, 1.0)
        a = self.radii[0] + (self.top[0] - self.radii[0]) * rise
        b = self.radii[1] + (self.top[1] - self.radii[1]) * rise
        # **The ellipse is not shrunk.** Shrinking the plan section by the rim
        # radius and inflating it back is the standard trick and it is only
        # right for a circle: the offset of an ellipse is not an ellipse. Push a
        # rim radius near the section's own depth and the shrunk ellipse
        # collapses to a line -- whose offset is a *stadium*, flat front and
        # back. That flat panel across the chest is what made the torso read as
        # a postbox, and no amount of easing the rim could have fixed it,
        # because easing the rim was what caused it.
        #
        # Instead the section stays exactly elliptical and the rim is rounded in
        # the two-dimensional space of (distance to that ellipse, height).
        flat = _ellipse_distance((px / a, py / b), (px / (a * a), py / (b * b)),
                                 float(np.min(np.minimum(a, b))))
        near = flat + self.round
        tall = np.abs(pz) - (self.half_height - self.round)
        outside = np.sqrt(np.maximum(near, 0.0) ** 2 + np.maximum(tall, 0.0) ** 2)
        inside = np.minimum(np.maximum(near, tall), 0.0)
        return (outside + inside - self.round).astype(np.float32)


class Plane(Prim):
    """A half-space. Cut with one and a garment has a hem you can see."""

    def __init__(self, point, normal):
        super().__init__(point)
        n = np.asarray(normal, dtype=np.float64)
        self.n = n / np.linalg.norm(n)

    def reach(self):
        return np.full(3, 4.0)

    def distance(self, x, y, z):
        px, py, pz = self.local(x, y, z)
        return (px * self.n[0] + py * self.n[1] + pz * self.n[2]).astype(np.float32)


def _ellipse_distance(scaled, gradient, smallest):
    """Distance to an ellipse or ellipsoid: one Newton step, not a scale factor.

    The obvious approximation is `(k - 1) * min(radii)`, where `k` is the
    distance in units of the radii. It is exact for a sphere and **badly wrong
    for anything flat**: on a 2.7-to-1 oval it under-reports the distance along
    the wide axis by that whole factor.

    That is invisible on a silhouette and ruinous everywhere a fillet is
    involved, because a fillet radius is a *distance*. A torso barrel built on
    it rounded its rim two and a half times less across the front than round the
    side -- so the shoulders stayed square however large the radius was set, and
    a hard edge ran down each side of the shirt.

    Dividing by the gradient of `k` instead gives very nearly the Euclidean
    distance, which is what every blend in this file assumes it is being given.
    """
    k = np.sqrt(sum(c * c for c in scaled))
    g = np.sqrt(sum(c * c for c in gradient))
    # At the dead centre both are zero and the answer is the inradius.
    safe = np.maximum(g, 1e-9)
    d = np.where(k > 1e-9, (k - 1.0) * k / safe, -smallest)
    return d.astype(np.float32)


def smin(a, b, k):
    """Smooth union. `k` is the fillet radius, in metres."""
    if k <= 0.0:
        return np.minimum(a, b, out=a)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - np.float32(k) * h * (1.0 - h)


def smax(a, b, k):
    """Smooth intersection -- and, with a negated argument, smooth subtraction."""
    if k <= 0.0:
        return np.maximum(a, b, out=a)
    h = np.clip(0.5 - 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h + np.float32(k) * h * (1.0 - h)


class Solid:
    """One moulding: a list of shapes added and taken away with fillets.

    A solid is the unit of colour as well as of geometry. Everything inside one
    fuses; where two solids meet, the edge stays crisp -- which is what a
    sleeve, a hem and a sock top all want.
    """

    def __init__(self, name: str):
        self.name = name
        self.ops = []

    def add(self, prim, k=0.0):
        self.ops.append(("add", prim, float(k)))
        return self

    def cut(self, prim, k=0.0):
        self.ops.append(("cut", prim, float(k)))
        return self

    def keep(self, prim, k=0.0):
        """Smooth intersection: throw away everything outside `prim`.

        The one operation that cannot be done inside a bounding box, because it
        changes the answer *everywhere* -- outside the shape there is nothing
        left. That is what it is for: clipping a flat insert to a curved surface
        so it follows the curve instead of standing off it at the edges.
        """
        self.ops.append(("keep", prim, float(k)))
        return self

    def keep_inside(self, other, offset=0.0, k=0.0):
        """Clip to another solid's outer form, `offset` metres in from it.

        For a garment made of more than one shape -- and a shirt is a body tube
        plus a shoulder plus a sleeve -- an insert clipped to any single one of
        them sits in a box-shaped recess wherever the others are what is
        actually there. Clipping to the garment itself is the only thing that
        follows it.

        Only the other solid's **added** shapes are sampled, never its cuts:
        the hole the insert is filling is one of those cuts, and honouring it
        would clip the insert straight back out of the hole.

        Adding a constant to a distance field moves its surface inwards by that
        much, so `offset` is an exact inset and costs nothing.
        """
        self.ops.append(("keep_inside", (other, float(offset)), float(k)))
        return self

    def cut_inside(self, other, offset=0.0, k=0.0):
        """Take another solid's outer form out of this one.

        `keep_inside` upside down, and it is for the same trouble seen from the
        other side. A trim laid on a garment -- a hoop on a sock, a cuff on a
        sleeve -- stands a couple of millimetres proud of it, and both surfaces
        are there, two millimetres apart. Thin the pair to a triangle budget and
        they cross, and the hoop comes out as a ragged band of the wrong colour.

        Cut the host away underneath and there is only one surface: the trim
        sits in a groove of its own, which is what a hoop knitted into a sock
        looks like anyway. A **negative** `offset` cuts that much beyond the
        other's surface, which is the clearance the two need.
        """
        self.ops.append(("cut_inside", (other, float(offset)), float(k)))
        return self

    def bounds(self, pad=0.0):
        los, his = [], []
        clip = None
        for kind, prim, k in self.ops:
            if kind == "add":
                lo, hi = prim.bounds()
                los.append(lo - k - pad)
                his.append(hi + k + pad)
            elif kind == "keep":
                # A smooth intersection never leaves anything outside the shape
                # it kept, so the grid need not reach past it. Only an
                # optimisation, and the one that makes a solid clipped to a
                # single limb cost a limb rather than a whole figure.
                lo, hi = prim.bounds()
                pair = (lo - k - pad, hi + k + pad)
                clip = pair if clip is None else (np.maximum(clip[0], pair[0]),
                                                  np.minimum(clip[1], pair[1]))
        if not los:
            raise ValueError(f"solid {self.name!r} has nothing in it")
        lo, hi = np.min(los, axis=0), np.max(his, axis=0)
        if clip is not None:
            lo, hi = np.maximum(lo, clip[0]), np.minimum(hi, clip[1])
        return lo, hi

    def sample(self, axes, shape):
        """This solid's outer form on someone else's grid: added shapes only."""
        grid = np.full(shape, FAR, dtype=np.float32)
        x = axes[0][:, None, None]
        y = axes[1][None, :, None]
        z = axes[2][None, None, :]
        for kind, prim, k in self.ops:
            if kind == "add":
                grid = smin(grid, prim.distance(x, y, z), k)
        return grid

    def field(self, cell: float):
        """Samples the solid on its own grid. Returns (distances, origin, cell)."""
        lo, hi = self.bounds(pad=3.0 * cell)
        counts = np.maximum(np.ceil((hi - lo) / cell).astype(int) + 1, 2)
        axes = [lo[i] + np.arange(counts[i], dtype=np.float64) * cell for i in range(3)]
        grid = np.full(tuple(counts), FAR, dtype=np.float32)

        for kind, prim, k in self.ops:
            if kind == "keep_inside":
                other, offset = prim
                grid = smax(grid, other.sample(axes, grid.shape) + np.float32(offset), k)
                continue
            if kind == "cut_inside":
                other, offset = prim
                grid = smax(grid, -(other.sample(axes, grid.shape) + np.float32(offset)), k)
                continue
            plo, phi = prim.bounds()
            pad = k + 2.0 * cell
            i0 = np.maximum(np.floor((plo - pad - lo) / cell).astype(int), 0)
            i1 = np.minimum(np.ceil((phi + pad - lo) / cell).astype(int) + 1, counts)
            if np.any(i1 <= i0):
                continue
            sl = tuple(slice(int(i0[i]), int(i1[i])) for i in range(3))
            x = axes[0][sl[0]][:, None, None]
            y = axes[1][sl[1]][None, :, None]
            z = axes[2][sl[2]][None, None, :]
            d = prim.distance(x, y, z)
            if kind == "add":
                grid[sl] = smin(grid[sl], d, k)
            elif kind == "cut":
                grid[sl] = smax(grid[sl], -d, k)
            else:
                # Everything beyond the shape's own box is outside it, so the
                # grid is refilled rather than edited in place.
                kept = np.full_like(grid, FAR)
                kept[sl] = smax(grid[sl], d, k)
                grid = kept
        return grid, lo, cell
