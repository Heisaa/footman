"""Measures the reference photograph's silhouette, so proportions are read
rather than remembered.

    blender --background --python art/measure_reference.py -- 01-moustache-red.png

Blender is only here to decode the PNG; everything after that is numpy. It
prints, for a series of heights up the figure, where the silhouette's edges are
in fractions of total figure height -- which is the only unit that survives the
picture being a different size from the model.

The gaps matter as much as the edges: a **gap** between the arm and the body is
what says the arm is a separate thing hanging beside the man rather than part of
his side, and that is the one measurement a front view of our own figure kept
failing.
"""

import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name = argv[0] if argv else "01-moustache-red.png"
    image = bpy.data.images.load(os.path.join(HERE, "reference", name))
    w, h = image.size
    px = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(px)
    rgb = px.reshape(h, w, 4)[::-1, :, :3]          # top row first

    # **Flood fill from the border, do not threshold.** Thresholding against the
    # background colour loses the white shorts and the white cuffs -- they are
    # nearly the background's own cream -- and the silhouette comes apart into
    # a dozen runs with the man's legs missing from the middle of them. What is
    # wanted is "not reachable from outside", which is a fill.
    step = 8
    small = rgb[::step, ::step]
    corner = small[1:6, 1:6].reshape(-1, 3).mean(axis=0)
    background = np.abs(small - corner).max(axis=2) < 0.055
    sh, sw = background.shape

    outside = np.zeros_like(background)
    stack = [(0, x) for x in range(sw)] + [(sh - 1, x) for x in range(sw)]
    stack += [(y, 0) for y in range(sh)] + [(y, sw - 1) for y in range(sh)]
    while stack:
        y, x = stack.pop()
        if not (0 <= y < sh and 0 <= x < sw) or outside[y, x] or not background[y, x]:
            continue
        outside[y, x] = True
        stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    solid = ~outside

    rows = np.where(solid.any(axis=1))[0]
    top, bottom = rows[0], rows[-1]
    # The shadow pools to one side, so the centre comes off the chest rather
    # than off the whole bounding box.
    chest = solid[int(bottom - 0.50 * (bottom - top))]
    on = np.where(chest)[0]
    centre = (on[0] + on[-1]) * 0.5
    height = bottom - top
    print(f"{name}: figure {height * step}px tall")
    print("  up     runs, as fractions of figure height off the centre line")

    for frac in (0.10, 0.16, 0.22, 0.26, 0.30, 0.34, 0.38, 0.42,
                 0.46, 0.50, 0.54, 0.58, 0.62, 0.70, 0.80):
        row = int(bottom - frac * height)
        line = solid[row]
        on = np.where(line)[0]
        if not len(on):
            continue
        runs, start = [], on[0]
        for i in range(1, len(on)):
            if on[i] != on[i - 1] + 1:
                runs.append((start, on[i - 1]))
                start = on[i]
        runs.append((start, on[-1]))
        spans = "  ".join(f"[{(a - centre) / height:+.3f}..{(b - centre) / height:+.3f}]"
                          for a, b in runs if b - a > 0)
        print(f"  {frac:.2f}  {spans}")


main()
