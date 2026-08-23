"""Saves a close crop of a reference image, so details can be looked at.

    blender --background --python art/crop_reference.py -- 01-moustache-red.png boots

The regions are given in fractions of the *figure's* height rather than the
image's, because the figures are photographed at different sizes and the only
stable ruler is the man himself.
"""

import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

# name: (bottom, top) up the figure, and (left, right) off its centre line.
REGIONS = {
    "boots": (-0.01, 0.26, -0.26, 0.26),
    "hands": (0.22, 0.36, -0.30, 0.30),
    "hand": (0.28, 0.44, 0.09, 0.26),
    "face": (0.55, 0.90, -0.25, 0.25),
    "kit": (0.30, 0.62, -0.28, 0.28),
    "feet": (-0.01, 0.20, -0.26, 0.26),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name = argv[0] if argv else "01-moustache-red.png"
    region = argv[1] if len(argv) > 1 else "boots"

    image = bpy.data.images.load(os.path.join(HERE, "reference", name))
    w, h = image.size
    px = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(px)
    rgba = px.reshape(h, w, 4)[::-1]

    step = 8
    small = rgba[::step, ::step, :3]
    corner = small[1:6, 1:6].reshape(-1, 3).mean(axis=0)
    background = np.abs(small - corner).max(axis=2) < 0.055
    sh, sw = background.shape
    outside = np.zeros_like(background)
    stack = ([(0, x) for x in range(sw)] + [(sh - 1, x) for x in range(sw)]
             + [(y, 0) for y in range(sh)] + [(y, sw - 1) for y in range(sh)])
    while stack:
        y, x = stack.pop()
        if not (0 <= y < sh and 0 <= x < sw) or outside[y, x] or not background[y, x]:
            continue
        outside[y, x] = True
        stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    solid = ~outside
    rows = np.where(solid.any(axis=1))[0]
    top, bottom = rows[0] * step, rows[-1] * step
    height = bottom - top
    chest = solid[int(rows[-1] - 0.5 * (rows[-1] - rows[0]))]
    on = np.where(chest)[0]
    centre = (on[0] + on[-1]) * 0.5 * step

    lo, hi, left, right = REGIONS[region]
    y0 = int(np.clip(bottom - hi * height, 0, h - 1))
    y1 = int(np.clip(bottom - lo * height, 0, h))
    x0 = int(np.clip(centre + left * height, 0, w - 1))
    x1 = int(np.clip(centre + right * height, 0, w))
    crop = rgba[y0:y1, x0:x1]

    out = bpy.data.images.new("crop", crop.shape[1], crop.shape[0], alpha=True)
    out.pixels.foreach_set(crop[::-1].ravel())
    path = os.path.join(HERE, "renders", f"crop_{region}_{name}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    print(f"wrote {path}  ({crop.shape[1]}x{crop.shape[0]})")


main()
