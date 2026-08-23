"""Our figure's silhouette, in the same units `measure_reference.py` prints.

Side by side with the reference the two are directly comparable, which is the
only way an argument about proportion ever ends. Runs matter as much as edges: a
**gap** between the arm and the body is what says the arm is a thing hanging
beside the man rather than part of his side.

    python3 art/silhouette.py [who]
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from figure import body, cast  # noqa: E402

# Read off 01-moustache-red.png, for comparison.
REFERENCE = {
    0.34: "[-0.211..-0.144]  [-0.136..+0.067]  [+0.144..+0.211]",
    0.38: "[-0.209..-0.140]  [-0.132..+0.035]  [+0.140..+0.209]",
    0.42: "[-0.201..-0.136]  [-0.130..+0.130]  [+0.136..+0.199]",
    0.46: "[-0.197..-0.132]  [-0.126..+0.126]  [+0.130..+0.197]",
    0.50: "[-0.191..+0.191]",
    0.54: "[-0.185..+0.185]",
    0.58: "[-0.171..+0.171]",
}


def silhouette(who="moustache", cell=0.004):
    look = cast.preset(who)
    h = look.height
    fields = [(s.name, s.field(cell)) for s, _ in body.build(look)
              if s.name in ("shirt", "skin", "shorts", "socks", "boots")]

    print(f"{who}: runs as fractions of figure height off the centre line")
    for fraction in sorted(REFERENCE):
        z = fraction * h
        spans = []
        for _, (grid, origin, size) in fields:
            k = int(round((z - origin[2]) / size))
            if not 0 <= k < grid.shape[2]:
                continue
            on = np.where((grid[:, :, k] < 0).any(axis=1))[0]
            if not len(on):
                continue
            start = on[0]
            for i in range(1, len(on)):
                if on[i] != on[i - 1] + 1:
                    spans.append([(origin[0] + start * size) / h,
                                  (origin[0] + on[i - 1] * size) / h])
                    start = on[i]
            spans.append([(origin[0] + start * size) / h,
                          (origin[0] + on[-1] * size) / h])
        spans.sort()
        merged = []
        for a, b in spans:
            if merged and a <= merged[-1][1] + 0.0015:
                merged[-1][1] = max(merged[-1][1], b)
            else:
                merged.append([a, b])
        ours = "  ".join(f"[{a:+.3f}..{b:+.3f}]" for a, b in merged)
        print(f"  {fraction:.2f}  ours  {ours}")
        print(f"        ref   {REFERENCE[fraction]}")


if __name__ == "__main__":
    silhouette(*(sys.argv[1:2] or ["moustache"]))
