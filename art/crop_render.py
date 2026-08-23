"""Crops one of our own renders, so a detail can be set beside the reference.

    blender --background --python art/crop_render.py -- moustache.png feet
"""

import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

# Fractions of the image: (left, right, top, bottom).
REGIONS = {
    "feet": (0.24, 0.76, 0.80, 1.00),
    "hands": (0.14, 0.86, 0.60, 0.78),
    "chest": (0.18, 0.82, 0.36, 0.64),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name = argv[0] if argv else "moustache.png"
    region = argv[1] if len(argv) > 1 else "feet"

    image = bpy.data.images.load(os.path.join(HERE, "renders", name))
    w, h = image.size
    px = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(px)
    rgba = px.reshape(h, w, 4)[::-1]

    left, right, top, bottom = REGIONS[region]
    crop = rgba[int(top * h):int(bottom * h), int(left * w):int(right * w)]
    out = bpy.data.images.new("crop", crop.shape[1], crop.shape[0], alpha=True)
    out.pixels.foreach_set(crop[::-1].ravel())
    path = os.path.join(HERE, "renders", f"crop_{region}_{name}")
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    print(f"wrote {path}  ({crop.shape[1]}x{crop.shape[0]})")


main()
