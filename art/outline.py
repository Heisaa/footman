"""Measures a moulding's plan outline for creases. No Blender, so it is instant.

A crease is a **concavity**: the silhouette steps inwards as it goes round. That
is what shows as a hard line down the side of a figure, and it is far cheaper to
find here than by rendering and squinting -- a render is twenty seconds and this
is one.

    python3 art/outline.py [solid] [who]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from figure import body, cast  # noqa: E402


def outline(name="shirt", who="moustache", heights=(0.42, 0.48, 0.53, 0.57)):
    look = cast.preset(who)
    solid = [s for s, _ in body.build(look) if s.name == name][0]
    grid, origin, cell = solid.field(0.004)
    worst = 0.0
    for fraction in heights:
        z = fraction * look.height
        k = int(round((z - origin[2]) / cell))
        if not 0 <= k < grid.shape[2]:
            continue
        plan = grid[:, :, k]
        cx, cy = -origin[0] / cell, -origin[1] / cell
        radii = []
        for degrees in range(0, 91, 5):
            angle = math.radians(degrees)
            r = 0.0
            while r < 0.7:
                ix = int(round(cx + math.sin(angle) * r / cell))
                iy = int(round(cy - math.cos(angle) * r / cell))
                if not (0 <= ix < plan.shape[0] and 0 <= iy < plan.shape[1]):
                    break
                if plan[ix, iy] >= 0:
                    break
                r += cell * 0.25
            radii.append(r)
        steps = [radii[i - 1] - radii[i] for i in range(1, len(radii))]
        dip = max(steps + [0.0])
        worst = max(worst, dip)
        # Half-depth as well as half-width, because the two are a trade: the
        # crease down the side of the shirt is a step in depth, and closing it
        # by pushing the shoulder out to meet the torso is how a figure ends up
        # too deep to look at from the side.
        inside = plan < 0
        ys = [i for i in range(plan.shape[1]) if inside[:, i].any()]
        depth = (ys[-1] - ys[0]) * cell * 0.5 if ys else 0.0
        print(f"  z {fraction:.2f}  half-width {max(radii):.3f}  "
              f"half-depth {depth:.3f}  inward step {dip * 1000:5.1f}mm")
    print(f"worst concavity {worst * 1000:.1f}mm")
    return worst


if __name__ == "__main__":
    outline(*(sys.argv[1:3] or ["shirt"]))
