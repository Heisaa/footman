"""Meshes built to a triangle count instead of thinned down to one.

The distance-field sandbox next door makes the figure the owner judges by, and
it makes it at three quarters of a million triangles. Getting that into a game
means decimation, and decimation is where the whole thing came apart: hems
chewed off, trims fighting the garments under them, and every seam between two
posed parts tearing open because both sides carried the same stretch of skin.

None of those are triangle-count problems and none of them get better with a
bigger budget. They are all the same problem -- a surface that was authored at
one density being rewritten at another by an algorithm with no idea what a hem
is. So this builds the figure at the density it ships at. An edge loop is put
where an edge loop belongs, a hem is a real ring of vertices, and a sock hoop is
**the sock's own surface with a different material on it**, which can never
fight what it is drawn on because it is not drawn on anything.

Everything is a tube. A torso, a thigh, a sock, a sleeve, a boot and a head are
all a stack of rings with a cross-section that is an ellipse pushed towards a
rectangle -- `power` 2 is an ellipse, 4 is a rounded box, and the references'
head is nearer the second. That one primitive is most of a footballer.

Pure Python: nothing here imports `bpy`, so a shape can be measured, tested and
argued about without launching Blender.
"""

import math

import numpy as np


class Mesh:
    """Vertices, faces, and which material and shading each face wants.

    A face carries its own material so that one surface can change colour
    without a second surface being laid over it -- the sock hoops and the boot
    stripes are bands of the thing they are on, not bands stuck to it.
    """

    def __init__(self, name="part"):
        self.name = name
        self.verts = []
        self.faces = []          # (indices, material, smooth)
        self.uvs = None          # only the face patch has any

    def add(self, verts, faces, material, smooth=True):
        base = len(self.verts)
        self.verts.extend(verts)
        for face in faces:
            self.faces.append(([base + i for i in face], material, smooth))
        return self

    def merge(self, other):
        base = len(self.verts)
        self.verts.extend(other.verts)
        for face, material, smooth in other.faces:
            self.faces.append(([base + i for i in face], material, smooth))
        return self

    def transform(self, matrix):
        if not self.verts:
            return self
        pts = np.asarray(self.verts, dtype=np.float64)
        pts = np.column_stack([pts, np.ones(len(pts))]) @ np.asarray(matrix).T
        self.verts = [tuple(p) for p in pts[:, :3]]
        return self

    def translate(self, offset):
        return self.transform(translation(offset))

    def tris(self):
        return sum(len(face) - 2 for face, _m, _s in self.faces)

    def bounds(self):
        pts = np.asarray(self.verts, dtype=np.float64)
        return pts.min(axis=0), pts.max(axis=0)


# --- Transforms --------------------------------------------------------------

def translation(offset):
    m = np.eye(4)
    m[:3, 3] = offset
    return m


def scaling(factors):
    m = np.eye(4)
    m[0, 0], m[1, 1], m[2, 2] = factors
    return m


def rotation_x(angle):
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1.0]])


def rotation_y(angle):
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1.0]])


def rotation_z(angle):
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1.0]])


def roughen(mesh, amount, centre, seed=0.0, scale=16.0):
    """Thumbs a surface: pushes every vertex in or out along its own radius.

    A machined shell and a rolled one differ in exactly one way -- the rolled
    one is not true anywhere. A normal map fakes that at the pixel and it is
    most of what sells clay, but it cannot bend a silhouette, and hair is all
    silhouette. This moves the vertices instead, so the outline goes lumpy too.

    Radial, from a centre the caller names, because that keeps the shape: every
    vertex moves along the line it already sits on, so a shell stays a shell and
    a hairline stays where it was drawn.

    The noise is three sines of incommensurable frequency multiplied together,
    plus a finer copy. Not a real noise field, and it does not need to be: it is
    smooth, it is deterministic from the seed, and its zero crossings are far
    enough apart at this scale to read as thumbs rather than as sandpaper.
    """
    cx, cy, cz = centre
    for i, (x, y, z) in enumerate(mesh.verts):
        dx, dy, dz = x - cx, y - cy, z - cz
        k = 1.0 + amount * _lumps(x, y, z, seed, scale)
        mesh.verts[i] = (cx + dx * k, cy + dy * k, cz + dz * k)
    return mesh


def roughen_axis(mesh, amount, seed=0.0, scale=60.0):
    """The same thumbing, but radial about the **local Z axis**.

    A limb is a tube built up its own axis and stood where it belongs
    afterwards, so it has to be worked before it is stood: pushed out from a
    single point instead, one end of an arm swells and the other pinches.
    Called on the tube in its own space, this pushes each vertex away from the
    axis it was turned on, which is what a thumb does to a rolled sausage.
    """
    for i, (x, y, z) in enumerate(mesh.verts):
        k = 1.0 + amount * _lumps(x, y, z, seed, scale)
        mesh.verts[i] = (x * k, y * k, z)
    return mesh


def _lumps(x, y, z, seed, scale):
    """Smooth deterministic noise in [-1, 1], give or take.

    `scale` is in **radians per metre**, so a lump is about `tau / scale`
    across -- 60 is a thumbprint every ten centimetres on a figure built in
    metres. Getting that wrong is silent: at a scale of 2 the whole man sits
    inside one lobe of the noise and the surface comes out perfectly smooth,
    which is exactly what the first pass of this shipped.
    """
    u, v, w = x * scale + seed, y * scale + seed * 1.7, z * scale + seed * 2.3
    return 0.7 * (math.sin(u * 1.00) * math.sin(v * 0.87) * math.sin(w * 0.73)
                  + 0.45 * math.sin(u * 2.13) * math.sin(v * 1.91)
                  * math.sin(w * 2.37))


def along(a, b):
    """A frame whose +Z runs from `a` to `b`, with the length baked in as 1.

    A limb is a tube built up its own axis and then stood where it belongs; this
    is the standing. Roll is left unspecified because every section here is
    symmetric about the axis, so it does not matter.
    """
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    z = b - a
    length = float(np.linalg.norm(z))
    if length < 1e-9:
        return translation(a)
    z /= length
    # Any vector not parallel to z will do for the first cross product.
    up = np.array([0.0, 1.0, 0.0]) if abs(z[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = np.cross(up, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    m = np.eye(4)
    m[:3, 0] = x
    m[:3, 1] = y
    m[:3, 2] = z * length
    m[:3, 3] = a
    return m


# --- The one primitive -------------------------------------------------------

def section(rx, ry, segments, power=2.0):
    """One ring of a tube: a superellipse, in the XY plane.

    `power` 2 is an ellipse and 4 is a rounded rectangle. The references' head is
    emphatically not a ball -- a flat-ish front to carry a face, soft corners --
    and a rounded box is the shape that says so. Torsos want a little of it too.
    """
    out = []
    e = 2.0 / power
    for i in range(segments):
        t = math.tau * i / segments
        c, s = math.cos(t), math.sin(t)
        out.append((rx * math.copysign(abs(c) ** e, c),
                    ry * math.copysign(abs(s) ** e, s)))
    return out


class Ring:
    """One level of a tube.

    `hard` splits the ring in two so no normal is shared across it, which is how
    a hem stays a hem: the shirt hem, the shorts hem and the sock top are the
    three crisp edges the whole kit is made of, and they are crisp here because
    the vertices are simply not welded.

    `material` is the material of the band **below** this ring, so a sock hoop
    is two rings with the trim named on the upper one.
    """

    def __init__(self, z, rx, ry, cy=0.0, power=None, hard=False, material=None,
                 drop=0.0):
        self.z = z
        self.rx = rx
        self.ry = ry
        self.cy = cy
        # How far the ring falls at its own widest point. A ring is a closed
        # loop and a shoulder is not level: measured off the reference the shirt
        # drops about twenty degrees from the neck out to the sleeve, and that
        # slope is most of the silhouette. Without it the top of a torso is a
        # dome, and a dome on straight sides is a postbox.
        self.drop = drop
        # How far the ring rises towards the back. A hairline is not level --
        # it sits high on the forehead and low on the nape -- and one number
        # per ring says so without a second shape to align.
        self.tilt = 0.0
        self.power = power
        self.hard = hard
        self.material = material


def tube(rings, segments, material, power=2.0, cap_lo=True, cap_hi=True,
         name="tube"):
    """A stack of rings, skinned. The workhorse.

    Caps are single n-gons rather than fans: a flat hem needs no geometry in the
    middle of it, and glTF triangulates on the way out anyway.
    """
    mesh = Mesh(name)
    loops = []
    for ring in rings:
        pts = section(ring.rx, ring.ry, segments,
                      ring.power if ring.power is not None else power)
        wide = max(ring.rx, 1e-9)
        deep = max(ring.ry, 1e-9)
        loops.append([(x, y + ring.cy,
                       ring.z - ring.drop * (abs(x) / wide) ** 2
                       + ring.tilt * (y / deep))
                      for x, y in pts])

    lower = mesh_ring(mesh, loops[0])
    if cap_lo:
        mesh.faces.append((list(reversed(lower)), material, False))
    for i in range(1, len(rings)):
        band = rings[i].material or material
        if rings[i - 1].hard:
            lower = mesh_ring(mesh, loops[i - 1])
        upper = mesh_ring(mesh, loops[i])
        smooth = not rings[i].hard
        for s in range(segments):
            t = (s + 1) % segments
            mesh.faces.append(([lower[s], lower[t], upper[t], upper[s]],
                               band, smooth))
        if rings[i].hard:
            upper = mesh_ring(mesh, loops[i])
        lower = upper
    if cap_hi:
        mesh.faces.append((list(lower), rings[-1].material or material, False))
    return mesh


def mesh_ring(mesh, loop):
    base = len(mesh.verts)
    mesh.verts.extend(loop)
    return list(range(base, base + len(loop)))


def blob(centre, radii, segments, stacks, material, power=2.0, name="blob"):
    """A closed superellipsoid: the same rings, shut with a fan at each end.

    Hands, ears, the nose, a curl of hair. One topology for the whole figure.
    """
    stacks = max(3, stacks)
    rings = []
    for i in range(1, stacks):
        v = math.pi * i / stacks
        rings.append(Ring(-radii[2] * math.cos(v),
                          radii[0] * math.sin(v), radii[1] * math.sin(v),
                          power=power))
    mesh = tube(rings, segments, material, power=power,
                cap_lo=False, cap_hi=False, name=name)
    count = len(mesh.verts)
    _fan(mesh, list(range(segments)), (0.0, 0.0, -radii[2]), material, down=True)
    _fan(mesh, list(range(count - segments, count)), (0.0, 0.0, radii[2]),
         material, down=False)
    return mesh.translate(centre)


def _fan(mesh, loop, tip, material, down):
    index = len(mesh.verts)
    mesh.verts.append(tip)
    for s in range(len(loop)):
        t = (s + 1) % len(loop)
        face = [loop[t], loop[s], index] if down else [loop[s], loop[t], index]
        mesh.faces.append((face, material, True))
