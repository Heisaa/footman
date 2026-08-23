"""Exports a figure as `presentation/models/body_<type>.glb`.

    ./art/export.sh --body standard
    ./art/export.sh --body giant --tris 6000
    ./art/export.sh --seed 41 --name one_man     # judge a particular player

`docs/THE_MODELS.md` is the contract and this answers it: metres, feet at the
origin, authored at 1.78 m, facing +Z once glTF has turned Blender's Z-up into
its own Y-up, and every joint the animation poses present by name.

**What the split is for.** `body.py` moulds by colour -- one `skin` solid holds
the head, both arms and both legs -- and the view can only bend a figure that is
split by joint. `figure/rig.py` is the skeleton and `figure/split.py` does the
cutting; between them a moulding becomes a piece of a moulding under the joint
that carries it.

**What this does not yet produce.** `Face`, so `SimFaceAtlas` has no surface to
draw an expression on -- this head has its eyes and mouth moulded into it.
`Brows`, which are inside the `hair` solid at the brow and no bone can tell from
a fringe. And one hair mesh per cut: the man wears the one he was built with.
`SimCharacterModel` skips all three quietly, so what comes out here works, and
`docs/THE_MODELS.md` says what each of them needs from `body.py` first.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402

from figure import body, cast, mould, rig, split, studio  # noqa: E402
from figure.palette import Color  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.abspath(os.path.join(HERE, os.pardir, "presentation", "models"))

# The height the models are authored at. `SimCharacterModel.REFERENCE_HEIGHT`
# is the same number and the game scales each man by his own height over it.
REFERENCE_HEIGHT = 1.78

# Which of the game's six colour slots each moulding is painted from.
#
# Two of the ten do not map cleanly and both are worth saying out loud. **Socks
# have no slot**: `SimCharacterBuilder` draws them in the first kit colour, so
# they go in the shirt's, and the separate sock colour the art kits carry is
# lost on the way out. **The eyes have no slot and want none** -- `ink` keeps
# the colour it was moulded in, which is what an eye is.
SLOTS = {
    "shirt": "shirt",
    "shorts": "shorts",
    "trim": "trim",
    "collar": "trim",
    "stripes": "trim",
    "hoops": "trim",
    "socks": "shirt",
    "skin": "skin",
    "hair": "hair",
    "boots": "boot",
    "ink": "ink",
}

# Placeholder colours. Every one of them is overwritten at run time from the
# club's kit and the man's skin -- one model serves both sides and every club --
# so these exist only so the file is not black in a viewer.
PLACEHOLDER = {
    "shirt": Color("c8202b"), "shorts": Color("f4f2ee"), "trim": Color("f4f2ee"),
    "skin": Color("e8bd95"), "hair": Color("4a2f1e"), "boot": Color("1a1a1c"),
    "ink": Color("14141a"),
}

# The five bodies, as far as this pipeline can tell them apart.
#
# **Only `build` separates them, and that is the honest state of it.** Every
# proportion in `body.Look` is a fraction of height and the game scales a model
# by height over 1.78, so a giant authored here is a standard man at a larger
# size -- the contract's "build him big, not tall" has nowhere to live until
# `Look` carries per-body overrides. `giant` and `sprite` below are placeholders
# and will not read as their own silhouettes.
BODIES = {
    "standard": 0.50,
    "giant": 0.62,
    "sprite": 0.44,
    "heavy": 0.86,
    "lean": 0.20,
}


def parse_args(argv):
    p = argparse.ArgumentParser(prog="export.sh", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--body", default="standard", choices=list(BODIES),
                   help="which of the five bodies to write")
    p.add_argument("--seed", type=int, default=0,
                   help="export this player instead of a body type")
    p.add_argument("--cell", type=float, default=0.005,
                   help="sampling size in metres; the quality knob")
    p.add_argument("--hold", type=float, default=HARD_EDGE_HOLD,
                   help="how hard the kit's hems resist thinning; 0 lets them go")
    p.add_argument("--inset", type=float, default=0.010,
                   help="how far a part is drawn in at its seam, per step out "
                        "from the trunk; 0 is a hard cut")
    p.add_argument("--tris", type=int, default=20000,
                   help="triangle budget for the whole figure; 0 leaves it raw")
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--name", default="")
    p.add_argument("--blend", default="", help="save the scene instead of exporting")
    p.add_argument("--shot", default="",
                   help="render the figure that is about to be written, and look at it")
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    return p.parse_args(argv)


def clear():
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.materials):
        for item in list(collection):
            collection.remove(item)


def materials():
    """One material per slot, named for it.

    The name is what the game reads. Slot **index** is what
    `docs/THE_MODELS.md` originally asked for, and it cannot work here: a part
    is one moulding and one colour, so it has one material, and glTF drops the
    five unused slots on the way out -- every mesh would arrive in Godot with
    its single surface at index 0 and be painted shirt-coloured.
    """
    out = {}
    for name, colour in PLACEHOLDER.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = colour.linear()
        bsdf.inputs["Roughness"].default_value = 0.5
        bsdf.inputs["Metallic"].default_value = 0.0
        out[name] = mat
    return out


def empties(joints):
    """The posed nodes, nested, each at its own pivot and square to the world.

    Square because `match_view_3d._rotate` assigns `rotation` outright: a rest
    angle here is wiped the instant a man moves, so the arms hang out and the
    feet turn out in the geometry instead.
    """
    root = bpy.data.objects.new("Player", None)
    root.empty_display_size = 0.08
    bpy.context.collection.objects.link(root)
    nodes = {"Player": root}
    for joint in joints:
        node = bpy.data.objects.new(joint.name, None)
        node.empty_display_size = 0.03
        bpy.context.collection.objects.link(node)
        parent = nodes[joint.parent]
        node.parent = parent
        node.location = joint.pivot - _pivot_of(joints, joint.parent)
        nodes[joint.name] = node
    return nodes


def _pivot_of(joints, name):
    import numpy as np
    if name == "Player":
        return np.zeros(3)
    for joint in joints:
        if joint.name == name:
            return joint.pivot
    raise KeyError(name)


## What each moulding is worth per triangle, against a flat 1.0.
##
## A uniform ratio spends the budget by **area**, and area is not what the eye
## goes to. The eyes are two small ellipsoids and the first thing anybody looks
## at -- one dark mark is what carries at distance -- and at a
## flat ratio they come out as faceted pentagons with a spike on the bottom. The
## hair is the opposite: the biggest single part on the figure, a bag of soft
## lobes, and nothing about it is worse for being coarse.
##
## Cheap to be generous here. Lifting the eyes eightfold costs a few hundred
## triangles out of thousands.
WEIGHT = {
    "ink": 8.0,       # the eyes
    "collar": 2.0,    # the neckline V, a small sharp shape
    "hoops": 1.5,
    "stripes": 1.5,
    "trim": 1.5,      # the cuffs
    "hair": 0.7,
}


def _own(scale, weight, tris):
    """One part's share of the budget: its weight, floored and capped."""
    return min(1.0, max(scale * weight, float(MIN_TRIS) / max(tris, 1)))


## No part is thinned below this, whatever the budget says. One ratio across
## the figure sounds fair and is not: a part with a hundred triangles in it and
## a part with a quarter of a million both lose the same fraction, and the small
## one -- a cuff, a pair of eyes, the sliver of sleeve past the elbow -- comes
## out as four triangles of nothing. The figure goes over budget instead, and
## the print says by how much.
MIN_TRIS = 64


def decimate(objects, target):
    """Thins the whole figure towards a triangle budget.

    The mesher hands over the better part of a million triangles, so something
    has to do this. There is no budget written down any more -- `PLAN.md` §9.1
    took the numbers out and pointed at the reference images -- so `--tris` is
    set by looking, and about twenty thousand was where this route stopped
    looking chewed.

    **The count is measured, never predicted.** A collapse ratio is a request,
    not a result: hold the hard edges and the modifier keeps far more than the
    ratio asked for -- the first version of this printed 8,000 and wrote a
    thirteen-megabyte file. So the scale is corrected against what Blender
    actually produces, and what is printed is what is in the mesh.
    """
    raw = [_tris(obj) for obj in objects]
    total = sum(raw)
    if target <= 0 or total <= target:
        return total, total

    weights = [WEIGHT.get(obj.name.split("_", 1)[1], 1.0) for obj in objects]
    mods = []
    for obj in objects:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        group = _hard_edges(obj) if HOLD[0] > 0.0 else None
        if group is not None:
            mod.vertex_group = group
            # **Inverted, and it has to be.** The group is where collapse is
            # *allowed*, not where it is forbidden: named the obvious way round,
            # a group holding only the hems protected everything that was not a
            # hem and the figure came out at 246k of its 270k triangles with the
            # log cheerfully reporting 8,000.
            mod.invert_vertex_group = True
            mod.vertex_group_factor = HOLD[0]
        mods.append(mod)

    scale = float(target) / float(total)
    got = total
    for _ in range(8):
        for mod, tris, weight in zip(mods, raw, weights):
            mod.ratio = _own(scale, weight, tris)
        got = _evaluated_tris(objects)
        if abs(got - target) <= target * 0.04:
            break
        scale = min(1.0, max(1e-5, scale * float(target) / float(max(got, 1))))
    return total, got


def _evaluated_tris(objects):
    """What the modifiers actually leave, which is what gets written."""
    deps = bpy.context.evaluated_depsgraph_get()
    deps.update()
    total = 0
    for obj in objects:
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        total += sum(len(poly.vertices) - 2 for poly in mesh.polygons)
        evaluated.to_mesh_clear()
    return total


## How much harder the kit's own edges are held on to than the rest of the
## figure. Collapse takes an edge loop wherever it is cheapest, and cheapest is
## a hem: a flat circular edge round a smooth tube is the first thing to go, and
## what it leaves is a skirt with a torn bottom hanging in mid air.
##
## `art/README.md`: the shirt hem, the shorts hem and the sock top are the three
## crisp edges the whole kit is made of. They are worth paying for -- and paying
## is what it is, because the triangles come off somewhere smoother.
## **Off by default, and measure before turning it on.** The protection is
## binary rather than graded: a vertex in the group survives, and the whole
## edge loop at full mesh resolution is 22,000 triangles on its own, so the
## budget cannot go below that however small the ratio is set. 1.0 and 3.0 give
## the same answer, which is what saturation looks like.
HARD_EDGE_HOLD = 0.0

## The value in force, set from `--hold`.
HOLD = [HARD_EDGE_HOLD]

## What counts as one, in degrees between the faces either side.
HARD_EDGE_ANGLE = 40.0


def _hard_edges(obj):
    """A vertex group holding the moulding's own hard edges. None if it has none.

    Found rather than named: an edge whose two faces turn through more than
    `HARD_EDGE_ANGLE` is a hem, a sock top, a sole or a neckline, and nothing on
    a moulded figure turns that sharply by accident.
    """
    limit = math.radians(HARD_EDGE_ANGLE)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    sharp = set()
    for edge in bm.edges:
        if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > limit:
            sharp.update(v.index for v in edge.verts)
    bm.free()
    if not sharp:
        return None
    group = obj.vertex_groups.new(name="hard")
    group.add(sorted(sharp), 1.0, "REPLACE")
    return group.name


def _tris(obj):
    return sum(len(poly.vertices) - 2 for poly in obj.data.polygons)


## Mouldings that are a **shell** on another one rather than a shape beside it,
## and are cut out of what they cover before anything is meshed.
##
## Both are slabs already clipped to the surface they lie on, which is what
## makes cutting them out exact. Nothing else here qualifies: the cuff is a
## capsule mostly buried in the sleeve and only its end shows, and cutting
## *that* out would hollow the sleeve and leave the buried capsule as the arm.
PROUD = ("stripes", "hoops")


def _groove(solids, clearance):
    """Takes the shell mouldings out of the ones they sit on.

    A boot stripe stands 1.8 mm off the boot and a sock hoop 2.8 mm off the
    sock -- invisible at full resolution and hopeless once a triangle budget has
    moved both surfaces further than that, which comes out as a ragged band of
    the wrong colour. Cutting the host away leaves the trim in a groove and one
    surface where there were two.

    Nothing here is a judgement about the figure: at the cell the sandbox
    renders at, the grooves make no difference to a picture.
    """
    proud = [s for s, _c in solids if s.name in PROUD and s.ops]
    for solid, _colour in solids:
        if solid.name in PROUD or not solid.ops:
            continue
        for other in proud:
            solid.cut_inside(other, -clearance)


def shot(path, look):
    """One frame of the assembled figure, decimation and all."""
    for obj in list(bpy.context.collection.objects):
        if obj.type == "MESH" and obj.modifiers:
            with bpy.context.temp_override(object=obj):
                for mod in list(obj.modifiers):
                    bpy.ops.object.modifier_apply(modifier=mod.name)
    studio.cyclorama()
    studio.lights()
    target = (0.0, 0.0, look.height * 0.50)
    half_w, half_h = look.height * 0.30, look.height * 0.54
    lens = 110.0
    distance = studio.fit_distance(half_w, half_h, lens, 760, 1040)
    studio.camera(target, distance, 0.0, math.radians(2.0), lens)
    studio.render_settings(48, 760, 1040, "CYCLES")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    print("shot " + studio.render_to(os.path.abspath(path)))


def main():
    args = parse_args(sys.argv)
    HOLD[0] = args.hold
    clear()

    if args.seed:
        look = cast.from_seed(args.seed)
        stem = args.name or ("player_%d" % args.seed)
    else:
        look = cast.preset("perm")
        look.build = BODIES[args.body]
        stem = args.name or ("body_" + args.body)
    # Authored at the reference height whatever the man's own is: the game
    # scales him, and a model built tall would be scaled tall twice.
    look.height = REFERENCE_HEIGHT

    slots = materials()
    joints = rig.skeleton(look, look.height)
    nodes = empties(joints)

    solids = body.build(look)
    _groove(solids, args.cell * 0.5)

    meshes = []
    stray = []
    for solid, _colour in solids:
        slot = SLOTS.get(solid.name)
        if slot is None:
            stray.append(solid.name)
            continue
        for joint, piece in split.parts(solid, joints, args.cell,
                                        inset=args.inset):
            obj = mould.to_object(piece, PLACEHOLDER[slot], args.cell,
                                  slots[slot], parent=nodes[joint.name],
                                  offset=joint.pivot)
            if obj is None:
                continue
            obj.name = "%s_%s" % (joint.name, solid.name)
            meshes.append(obj)

    if stray:
        # A moulding nobody has given a colour slot would vanish silently.
        print("  UNPAINTED, and left out: " + ", ".join(sorted(stray)))

    by_joint = {}
    for obj in meshes:
        by_joint.setdefault(obj.parent.name, []).append(obj)
    for joint in joints:
        pieces = by_joint.get(joint.name, [])
        print("  %-10s %2d part(s) %7d tri  %s" % (
            joint.name, len(pieces), sum(_tris(o) for o in pieces),
            " ".join(sorted(o.name.split("_", 1)[1] for o in pieces))))

    before = {obj.name: _tris(obj) for obj in meshes}
    raw, kept = decimate(meshes, args.tris)
    for obj in sorted(meshes, key=lambda o: -before[o.name]):
        mod = obj.modifiers.get("Decimate")
        print("    %-18s %7d  x%.4f" % (
            obj.name, before[obj.name], mod.ratio if mod else 1.0))
    print("  %d triangles -> %d (%d meshes)" % (raw, kept, len(meshes)))

    if args.shot:
        # A budget this tight can leave a bag of triangles rather than a man,
        # and nothing else here would say so. The parts are what the glTF
        # exporter will write, modifiers and all.
        shot(args.shot, look)

    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
        print("saved " + args.blend)
        return

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, stem + ".glb")
    # `+Y up` is what sends Blender -Y to glTF +Z, which is the way the figure
    # already faces and the way the view expects it to. Nothing is turned here.
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False,
        export_apply=True, export_yup=True, export_cameras=False,
        export_lights=False, export_animations=False)
    print("wrote " + path)


if __name__ == "__main__":
    main()
