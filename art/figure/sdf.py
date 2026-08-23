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
        k = np.sqrt((px / rx) ** 2 + (py / ry) ** 2 + (pz / rz) ** 2)
        # The usual approximation. Exact only for a sphere, and wrong by a few
        # per cent on a squashed one -- which moves a fillet, never a silhouette.
        return ((k - 1.0) * float(min(rx, ry, rz))).astype(np.float32)


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
        self.radius = float(radius)

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

    def bounds(self, pad=0.0):
        los, his = [], []
        for kind, prim, k in self.ops:
            if kind != "add":
                continue
            lo, hi = prim.bounds()
            los.append(lo - k - pad)
            his.append(hi + k + pad)
        if not los:
            raise ValueError(f"solid {self.name!r} has nothing in it")
        return np.min(los, axis=0), np.max(his, axis=0)

    def field(self, cell: float):
        """Samples the solid on its own grid. Returns (distances, origin, cell)."""
        lo, hi = self.bounds(pad=3.0 * cell)
        counts = np.maximum(np.ceil((hi - lo) / cell).astype(int) + 1, 2)
        axes = [lo[i] + np.arange(counts[i], dtype=np.float64) * cell for i in range(3)]
        grid = np.full(tuple(counts), FAR, dtype=np.float32)

        for kind, prim, k in self.ops:
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
            here = grid[sl]
            if kind == "add":
                grid[sl] = smin(here, d, k)
            else:
                grid[sl] = smax(here, -d, k)
        return grid, lo, cell
