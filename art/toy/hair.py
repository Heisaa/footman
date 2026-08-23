"""The cuts, one mesh each, all in the file and one of them shown.

`SimCharacterBuilder.HAIR_LIBRARY` is the list and the order, because a man has
to keep his hair whichever builder drew him. Every row is the same idea: a shell
a tenth or more larger than the skull, pushed back, plus pieces. Hair that
merely skims the head is paint on a scalp -- the shell is where the volume comes
from, and the difference between a full cut and an afro is what is added on top
of it, never how big it is.

**The names are padded to two digits.** `SimCharacterModel._choose_variant`
sorts the variants by name as text, so `Hair10` would land between `Hair1` and
`Hair2` and eighteen men would wear eight of the wrong cuts.

The shell is built off `figure.SKULL`, the skull's own profile, so a cut cannot
drift off the head it belongs to when the head changes shape.
"""

from . import figure as F
from . import mesh as M

HAIR = "hair"

# `presentation/character_builder.gd:HAIR_LIBRARY`, row for row.
LIBRARY = [
    dict(r=0.0),                                                     # bald
    dict(r=1.12, up=0.08, back=0.20),                                # cropped
    dict(r=1.14, up=0.07, back=0.21, burns=True),                    # back and sides
    dict(r=1.16, up=0.06, back=0.22, peak=True),                     # bowl, with a point
    dict(r=1.18, up=0.05, back=0.22, burns=True),                    # heavier
    dict(r=1.14, up=0.12, back=0.20, quiff=True),                    # a quiff
    dict(r=1.10, up=0.08, back=0.18, curls=12),                      # curly
    dict(r=1.10, up=0.10, back=0.18, curls=16, curl_r=0.40,
         curl_skirt=True),                                           # a big curly head
    dict(r=1.14, up=0.06, back=0.21, quiff=True, burns=True),        # swept over
    dict(r=1.14, up=0.06, back=0.20, mass=1.0),                      # collar length
    dict(r=1.16, up=0.05, back=0.22, mass=1.0, burns=True),          # long
    dict(r=1.10, up=0.11, back=0.25, burns=True),                    # receding
    dict(r=1.11, up=0.10, back=0.22, sy=0.94, peak=True),            # thin on top
    dict(r=1.14, up=0.08, back=0.21, tufts=4),                       # tousled
    dict(r=1.10, up=0.07, back=0.22, mass=1.45, burns=True),         # a mullet
    dict(r=1.12, up=0.06, back=0.21, slick=True),                    # slicked back
    dict(r=1.13, up=0.05, back=0.22, slick=True, burns=True),        # slicked, burns
    dict(r=1.13, up=-0.05, back=0.22, burns=True),                   # thinning
]


def cuts(look, h, segs, coarse):
    """[(name, Mesh)] -- every style, in library order, named for its index."""
    out = []
    for i, style in enumerate(LIBRARY):
        name = "Hair%02d" % i
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
    back = style.get("back", 0.20) * hd * 1.9
    squash = style.get("sy", 1.0)

    # The shell starts at the hairline and runs over the crown. Its bottom ring
    # is tilted -- high on the forehead, low on the nape -- because a level one
    # is a swimming cap, and a separate fringe piece does not work: far enough
    # forward to show it is a slug, far enough back it lands on the brows.
    rings = F.skull_rings(look, h, scale=r, lift=lift, back=back,
                          first=3, squash=squash)
    # **The hairline is not a cut, it is a crossing.** The shell is pushed back
    # far enough that it starts the day inside the skull at the forehead and
    # comes out of it partway up; where it surfaces is the hairline, and where
    # it stays buried is a bare forehead. Tilting the bottom ring up at the
    # front to force a higher line was tried and does the opposite -- it lifts
    # the shell off the skull it was supposed to be emerging from, and leaves a
    # patch of bare scalp in the middle of the hair.
    #
    # So the only two numbers are the library's own: how big the shell is and
    # how far back it sits.
    mesh = M.tube(rings, segs, HAIR, power=F.HEAD_POWER, name=name)

    crown_z = h * F.SKULL[-1][0] + lift

    if style.get("quiff"):
        mesh.merge(M.blob((0.0, -hd * r * 0.52 + back, h * 0.905 + lift),
                          (hw * 0.44, hd * 0.30, hh * 0.24),
                          coarse, coarse // 2, HAIR, name="quiff"))
    if style.get("peak"):
        mesh.merge(M.blob((0.0, -hd * r * 0.80 + back, h * 0.812 + lift),
                          (hw * 0.20, hd * 0.16, hh * 0.15),
                          coarse, coarse // 2, HAIR, name="peak"))
    if style.get("burns"):
        for side in (-1.0, 1.0):
            mesh.merge(M.blob((side * hw * r * 0.90, -hd * 0.06 + back, h * 0.712),
                              (hw * 0.12, hd * 0.20, hh * 0.20),
                              coarse, coarse // 2, HAIR, name="burn"))
    if style.get("mass"):
        # Down the back, not round the sides: a mass that wraps is a hood.
        long = style["mass"]
        mesh.merge(M.blob((0.0, hd * r * 0.62 + back, h * (0.790 - 0.055 * long)),
                          (hw * r * 0.86, hd * 0.44, hh * (0.34 + 0.22 * long)),
                          segs, coarse, HAIR, name="mass"))
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
    return mesh


def _curls(mesh, look, h, style, count, coarse):
    """A ring of fat lobes round a shell. A perm is exactly that and no more."""
    import math
    hw = look.head_w * h
    hd = look.head_d * h
    hh = look.head_h * h
    r = style["r"]
    lift = style.get("up", 0.06) * hh
    # Scaled up on this head: `HAIR_LIBRARY` measures the push back against a
    # sphere of `head_r`, and a rounded box of the same width is deeper, so the
    # same fraction buries less of the shell and the hairline sits too low.
    back = style.get("back", 0.20) * hd * 1.9
    size = style.get("curl_r", 0.30)
    rows = ((0.855, 1.00), (0.905, 0.86)) if not style.get("curl_skirt") \
        else ((0.760, 0.96), (0.830, 1.02), (0.898, 0.88))
    for z, spread in rows:
        for i in range(count):
            turn = math.tau * (i + 0.5 * (z * 37 % 2)) / count
            mesh.merge(M.blob(
                (hw * r * spread * math.sin(turn) * 0.94,
                 hd * r * spread * math.cos(turn) * 0.94 + back,
                 h * z + lift),
                (hw * size * 0.62, hd * size * 0.62, hh * size * 0.60),
                max(5, coarse - 3), max(4, coarse // 2 - 1), HAIR, name="curl"))
