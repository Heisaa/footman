"""Build and photograph the toy footballers.

    ./art/render.sh --who moustache
    ./art/render.sh --mode rank
    ./art/render.sh --mode squad --seed 100 --count 6
    ./art/render.sh --who perm --turntable 8

Modes:

    figure   one man, full length -- the default; `--who` picks the preset
    rank     the four reference figures side by side
    squad    `--count` seeded players, which is the clone-army check
    heads    framed on the faces, for brows, noses and hair
    parts    one man with the mouldings pulled apart, to see the fillets

`--cell` is the sampling size in metres and it is the quality knob: 0.004 is
the default, 0.0025 is publishable, 0.008 is a fast look.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from figure import body, cast, mould, studio  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "renders")


def parse_args(argv):
    p = argparse.ArgumentParser(prog="render.sh", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--mode", default="figure",
                   choices=["figure", "rank", "squad", "heads", "parts"])
    p.add_argument("--who", default="moustache", choices=list(cast.PRESETS))
    p.add_argument("--seed", type=int, default=100)
    p.add_argument("--count", type=int, default=6)
    p.add_argument("--cell", type=float, default=0.004)
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--name", default="")
    p.add_argument("--turntable", type=int, default=0)
    p.add_argument("--yaw", type=float, default=0.0)
    p.add_argument("--pitch", type=float, default=2.0)
    p.add_argument("--engine", default="CYCLES", choices=["CYCLES", "EEVEE"])
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--width", type=int, default=760)
    p.add_argument("--height", type=int, default=1040)
    p.add_argument("--blend", default="")
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    return p.parse_args(argv)


def stand(look, at, cell, name, cache):
    root = mould.figure(body.build(look), cell, name, cache)
    root.location = at
    return root


def main():
    args = parse_args(sys.argv)
    studio.clear()
    studio.cyclorama()
    studio.lights()
    cache = {}

    looks = []
    spacing = 0.86
    lens = 110.0

    if args.mode in ("figure", "parts"):
        look = cast.preset(args.who)
        looks.append(look)
        stand(look, (0.0, 0.0, 0.0), args.cell, args.who, cache)
        target = (0.0, 0.0, look.height * 0.50)
        half_w, half_h = look.height * 0.30, look.height * 0.54
    elif args.mode == "rank":
        names = cast.ORDER
        span = spacing * (len(names) - 1)
        for i, name in enumerate(names):
            look = cast.preset(name)
            looks.append(look)
            stand(look, (-span * 0.5 + i * spacing, 0.0, 0.0), args.cell, name, cache)
        target = (0.0, 0.0, 0.90)
        half_w, half_h = span * 0.5 + 0.44, 1.06
    elif args.mode == "squad":
        span = spacing * (args.count - 1)
        tallest = 0.0
        for i in range(args.count):
            look = cast.from_seed(args.seed + i)
            looks.append(look)
            stand(look, (-span * 0.5 + i * spacing, 0.0, 0.0), args.cell,
                  f"P{args.seed + i}", cache)
            tallest = max(tallest, look.height)
        target = (0.0, 0.0, tallest * 0.50)
        half_w, half_h = span * 0.5 + 0.42, tallest * 0.56
    elif args.mode == "heads":
        # One row, framed on the faces. A second row was tried on a riser, the
        # way a team photo does it, and half the squad never appeared: the
        # framing is computed off the heads and the back row lands outside it.
        # A contact sheet does not need depth.
        gap = 0.66
        span = gap * (args.count - 1)
        low, high = 1e9, 0.0
        for i in range(args.count):
            look = cast.from_seed(args.seed + i)
            looks.append(look)
            stand(look, (-span * 0.5 + i * gap, 0.0, 0.0), args.cell,
                  f"P{args.seed + i}", cache)
            top = look.height * body.CROWN
            low = min(low, top - look.height * 0.40)
            high = max(high, top + look.height * 0.05)
        target = (0.0, 0.0, (low + high) * 0.5)
        half_w, half_h = span * 0.5 + 0.32, (high - low) * 0.5
    else:  # pragma: no cover
        raise SystemExit(args.mode)

    for look in looks[:8]:
        print("  " + cast.describe(look))
    for obj in bpy.context.collection.objects:
        if obj.type == "MESH" and obj.name not in ("Cyclorama",):
            d = obj.dimensions
            print(f"  part {obj.name:9s} {len(obj.data.vertices):7d}v  "
                  f"{d.x:.3f} x {d.y:.3f} x {d.z:.3f}  "
                  f"z {obj.bound_box[0][2] + obj.location.z:+.3f}.."
                  f"{obj.bound_box[6][2] + obj.location.z:+.3f}")

    yaw = math.radians(args.yaw)
    pitch = math.radians(args.pitch)
    distance = studio.fit_distance(half_w, half_h, lens, args.width, args.height)
    cam = studio.camera(target, distance, yaw, pitch, lens)
    studio.render_settings(args.samples, args.width, args.height, args.engine)

    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
        print(f"saved {args.blend}")
        return

    os.makedirs(args.out, exist_ok=True)
    stem = args.name or (args.who if args.mode == "figure" else f"{args.mode}_{args.seed}")
    if args.turntable > 0:
        for frame in range(args.turntable):
            studio.place(cam, target, distance, math.tau * frame / args.turntable, pitch)
            print("wrote " + studio.render_to(
                os.path.join(args.out, f"{stem}_{frame:03d}.png")))
    else:
        print("wrote " + studio.render_to(os.path.join(args.out, f"{stem}.png")))


if __name__ == "__main__":
    main()
