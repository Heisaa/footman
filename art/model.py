"""Writes a figure out as `presentation/models/body_<type>.glb`.

    ./art/model.sh --body standard
    ./art/model.sh --seed 41 --shot /tmp/a.png

The other export, `art/export.py`, cuts the distance-field figure into joints
and thins it to a budget. This one does not thin anything: `art/toy/` builds the
same man to a triangle count in the first place, so a hem is a hem, a sock hoop
is a band of the sock, and no seam has two copies of one surface to fight over.
About six thousand triangles drawn -- a body of 4,300 and one head of hair --
against that one's twenty, and it is the better looking of the two. The file
itself is thirty thousand because it carries all eighteen cuts and the game
shows one.

`docs/THE_MODELS.md` is the contract and this answers all of it: the axes, the
1.78 m reference, materials named for their slot, the joints the animation poses
by name, hair variants, and the `Face` surface the atlas is drawn on.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402

from figure import cast, rig, studio  # noqa: E402
from figure.palette import Color  # noqa: E402
from toy import figure as toy  # noqa: E402
from toy import hair as toy_hair  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.abspath(os.path.join(HERE, os.pardir, "presentation", "models"))

REFERENCE_HEIGHT = 1.78

# Placeholders only: every one is overwritten at run time from the club's kit
# and the man's skin. `face` is not in the game's slot table on purpose -- the
# atlas owns that surface and `_paint` must leave it alone.
PLACEHOLDER = {
    "shirt": Color("c8202b"), "shorts": Color("f4f2ee"), "trim": Color("f4f2ee"),
    "skin": Color("e8bd95"), "hair": Color("4a2f1e"), "boot": Color("1a1a1c"),
    # Outside the game's slot table on purpose, like `face`: an eye is black in
    # every kit. The game swaps in a glossy version of this, because the gloss
    # is the whole point and a glTF material cannot carry Godot's clear coat.
    "eye": Color("101014"),
    # The face placeholder is the skin, so a render shows the head and not a
# white plate. In the game the atlas replaces it and carries its own alpha.
    "face": Color("e8bd95"),
}

# The five bodies. Only `build` separates them and that is all the owner asked
# for: a giant is a tall man with a bigger body, and the game already makes him
# tall by scaling the model by his own height over 1.78.
BODIES = {"standard": 0.50, "giant": 0.72, "sprite": 0.40,
          "heavy": 0.90, "lean": 0.16}


def parse_args(argv):
    p = argparse.ArgumentParser(prog="model.sh", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--body", default="standard", choices=list(BODIES))
    p.add_argument("--seed", type=int, default=0,
                   help="build this player instead of a body type")
    p.add_argument("--quality", type=float, default=1.0,
                   help="segments round a part; the triangle count scales with it")
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--name", default="")
    p.add_argument("--extra", type=int, default=-1,
                   help="which accessory a --shot shows: 0 headband, -1 none")
    p.add_argument("--tache", type=int, default=1,
                   help="whether a --shot wears the moustache")
    p.add_argument("--hair", type=int, default=7,
                   help="which cut a --shot shows; the file always holds them all")
    p.add_argument("--shot", default="", help="render the figure as well")
    p.add_argument("--sheet", default="",
                   help="render every hair cut side by side instead of a figure")
    p.add_argument("--blend", default="")
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    return p.parse_args(argv)


def clear():
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.materials):
        for item in list(collection):
            collection.remove(item)


def materials():
    out = {}
    for name, colour in PLACEHOLDER.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = colour.linear()
        bsdf.inputs["Roughness"].default_value = 0.45
        bsdf.inputs["Metallic"].default_value = 0.0
        out[name] = mat
    return out


def joints(skeleton):
    """The posed nodes, nested, each square to the world.

    Square because `match_view_3d._rotate` assigns `rotation` outright: a rest
    angle here is wiped the instant a man moves, so the arms hang out and the
    feet turn out in the geometry instead.
    """
    root = bpy.data.objects.new("Player", None)
    root.empty_display_size = 0.08
    bpy.context.collection.objects.link(root)
    nodes = {"Player": root}
    pivots = {"Player": (0.0, 0.0, 0.0)}
    for joint in skeleton:
        node = bpy.data.objects.new(joint.name, None)
        node.empty_display_size = 0.03
        bpy.context.collection.objects.link(node)
        node.parent = nodes[joint.parent]
        parent = pivots[joint.parent]
        node.location = (joint.pivot[0] - parent[0], joint.pivot[1] - parent[1],
                         joint.pivot[2] - parent[2])
        nodes[joint.name] = node
        pivots[joint.name] = tuple(joint.pivot)
    return nodes, pivots


def upload(part, parent, pivot, slots, recalc=True):
    """One `toy.Mesh` into the scene, measured from its joint's pivot."""
    mesh = bpy.data.meshes.new(part.name)
    verts = [(v[0] - pivot[0], v[1] - pivot[1], v[2] - pivot[2]) for v in part.verts]
    mesh.from_pydata(verts, [], [face for face, _m, _s in part.faces])
    mesh.update()

    used = []
    for _face, material, _smooth in part.faces:
        if material not in used:
            used.append(material)
    for material in used:
        mesh.materials.append(slots[material])
    for poly, (_face, material, smooth) in zip(mesh.polygons, part.faces):
        poly.material_index = used.index(material)
        poly.use_smooth = smooth

    if part.uvs is not None:
        layer = mesh.uv_layers.new(name="UVMap")
        for loop in mesh.loops:
            layer.data[loop.index].uv = part.uvs[loop.vertex_index]

    if recalc:
        # Every part here is closed, which is what makes this safe: an open
        # shell has no inside for the solver to find and can come out inverted.
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()

    obj = bpy.data.objects.new(part.name, mesh)
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def brows(head, head_r, depth, slots, pivot, head_pivot):
    """`Brows`, and the two bars the game poses on it.

    `SimCharacterBuilder._pose_brows` sets the position, roll and scale of two
    children called `BrowL` and `BrowR`, treating each as a unit sphere of
    `head_r * FACE_QUAD / 32`. All this has to do is put them there.
    """
    node = bpy.data.objects.new("Brows", None)
    node.empty_display_size = 0.02
    bpy.context.collection.objects.link(node)
    node.parent = head
    # The sphere the poser works on, centred so **its front sits on the face**.
    # Centred on the eye row instead, the sphere's front lands on the middle of
    # the skull and both brows are posed inside the man's head.
    # Forward by `BROW_STAND`, which is the whole of what makes a brow a ridge.
    # The game poses these on a sphere and this head is a rounded box, flatter
    # across the face than any sphere through the same points -- so a shell that
    # touches at the nose is *inside* the skull by the time it has climbed to
    # the brow, and the squad has no eyebrows. Standing the sphere off the face
    # fixes that without making it bigger, which would only put the brows back
    # up in the hairline.
    node.location = (0.0, head_r * toy.FACE_SHELL - depth - toy.BROW_STAND,
                     pivot[2] - head_pivot[2])
    unit = head_r * toy.FACE_QUAD / 32.0
    from toy import mesh as M
    for side in ("L", "R"):
        bar = M.blob((0.0, 0.0, 0.0), (unit, unit, unit), 8, 6, "hair",
                     name="Brow" + side)
        upload(bar, node, (0.0, 0.0, 0.0), slots)
    return node


def eyes(head, head_r, depth, slots, pivot, head_pivot):
    """`Eyes`, and the two beads the game poses on it.

    The same shape as `brows` above and for the same reason: the game owns where
    a feature goes, because it is the game that knows the man's eye style and
    what has just happened to him. All this writes is two unit spheres in a node
    at the right place, and `SimCharacterBuilder._pose_eyes` does the rest.

    They wear a material named `eye`, which is **not** in the game's slot table
    on purpose -- an eye is black in every kit, and a name outside the table
    keeps the colour it was authored in.
    """
    node = bpy.data.objects.new("Eyes", None)
    node.empty_display_size = 0.02
    bpy.context.collection.objects.link(node)
    node.parent = head
    node.location = (0.0, head_r * toy.FACE_SHELL - depth - toy.EYE_STAND,
                     pivot[2] - head_pivot[2])
    unit = head_r * toy.FACE_QUAD / 32.0
    from toy import mesh as M
    for side in ("L", "R"):
        bead = M.blob((0.0, 0.0, 0.0), (unit, unit, unit), 12, 8, "eye",
                      name="Eye" + side)
        upload(bead, node, (0.0, 0.0, 0.0), slots)
    return node


def main():
    args = parse_args(sys.argv)
    clear()

    if args.seed:
        look = cast.from_seed(args.seed)
        stem = args.name or ("player_%d" % args.seed)
    else:
        look = cast.preset("perm")
        look.build = BODIES[args.body]
        stem = args.name or ("body_" + args.body)
    look.height = REFERENCE_HEIGHT

    if args.sheet:
        clear()
        sheet(args.sheet, look, args.quality)
        return

    slots = materials()
    skeleton = rig.skeleton(look, look.height)
    nodes, pivots = joints(skeleton)
    built = toy.build(look, args.quality)

    total = 0
    for name in sorted(built.parts):
        for part in built.parts[name]:
            upload(part, nodes[name], pivots[name], slots,
                   recalc=part.uvs is None)
            total += part.tris()
        print("  %-10s %5d tri  %s" % (
            name, sum(p.tris() for p in built.parts[name]),
            " ".join(p.name for p in built.parts[name])))

    # Every cut in the file, one of them shown. The game picks by index and the
    # rest are hidden, which is why they all have to be here.
    cuts = 0
    for name, part in toy_hair.cuts(look, look.height,
                                    max(10, int(round(toy.HAIR_SEGMENTS * args.quality))),
                                    max(6, int(round(toy.COARSE * args.quality)))):
        node = upload(part, nodes["Head"], pivots["Head"], slots)
        node.name = name
        cuts += 1
        total += part.tris()
    print("  %-10s %2d cuts" % ("Hair", cuts))

    # The moustache and the two accessories, all switched by the seed.
    for name, part in toy.extras(look, look.height,
                                 max(8, int(round(toy.FINE * args.quality))),
                                 max(6, int(round(toy.COARSE * args.quality)))):
        node = upload(part, nodes["Head"], pivots["Head"], slots)
        node.name = name
        total += part.tris()
    print("  %-10s %s" % ("extras", "Moustache Accessory0 Eyes"))

    eye_z = look.height * (toy.CHIN + toy.CROWN) * 0.5 \
        - look.head_h * look.height * 0.06
    brows(nodes["Head"], built.head_r, look.head_d * look.height, slots,
          (0.0, 0.0, eye_z), pivots["Head"])
    eyes(nodes["Head"], built.head_r, look.head_d * look.height, slots,
         (0.0, 0.0, eye_z), pivots["Head"])
    print("  %d triangles, head_r %.4f" % (total, built.head_r))

    if args.shot:
        # Every cut is in the file and the game shows one; a render has to do
        # the same or it is eighteen hats at once.
        for name, _part in toy_hair.cuts(look, look.height, 8, 6):
            obj = bpy.data.objects.get(name)
            if obj is not None:
                obj.hide_render = name != ("Hair%02d" % args.hair)
        # And the face patch: in the game it carries the atlas and its own
        # alpha, so a render of it is a blank plate over the features.
        face = bpy.data.objects.get("Face")
        if face is not None:
            face.hide_render = True
        # The accessory is worn or it is not, and the moustache is a coin toss.
        for i in (0,):
            obj = bpy.data.objects.get("Accessory%d" % i)
            if obj is not None:
                obj.hide_render = i != args.extra
        tache = bpy.data.objects.get("Moustache")
        if tache is not None:
            tache.hide_render = not args.tache
        shot(args.shot, look)
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
        print("saved " + args.blend)
        return

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, stem + ".glb")
    # `+Y up` sends Blender -Y to glTF +Z, which is the way this figure already
    # faces and the way the view expects it. Nothing is turned.
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False,
        export_apply=True, export_yup=True, export_cameras=False,
        export_lights=False, export_animations=False)
    print("wrote " + path)


def sheet(path, look, quality):
    """Every cut, one head each, in a grid. The only way to tune seventeen.

    Heads only: a rank of whole figures at this count is a row of thumbnails,
    and hair is judged at the size a face is judged at. Built as bare meshes
    side by side rather than as duplicated hierarchies -- nothing here is posed,
    so none of the rig is needed.
    """
    from toy import mesh as M
    h = look.height
    slots = materials()
    cuts = toy_hair.cuts(look, h, max(10, int(round(toy.HAIR_SEGMENTS * quality))),
                         max(6, int(round(toy.COARSE * quality))))
    columns = 6
    gap_x, gap_z = look.head_w * h * 2.9, look.head_h * h * 2.5
    rows = (len(cuts) + columns) // columns
    for i, (name, cut) in enumerate([("Hair00", None)] + cuts):
        col, row = i % columns, i // columns
        at = ((col - (columns - 1) * 0.5) * gap_x, 0.0,
              -(row - (rows - 1) * 0.5) * gap_z)
        head = M.Mesh(name)
        head.merge(M.tube(toy.skull_rings(look, h), 20, toy.SKIN,
                          power=toy.HEAD_POWER, name="skull"))
        if cut is not None:
            head.merge(cut)
        head.translate((at[0], 0.0, at[2]))
        upload(head, None, (0.0, 0.0, 0.0), slots)

    studio.cyclorama()
    studio.lights()
    span_x = gap_x * columns
    span_z = gap_z * rows
    target = (0.0, 0.0, h * (toy.CHIN + toy.CROWN) * 0.5)
    lens = 85.0
    width, height = 1600, 1000
    distance = studio.fit_distance(span_x * 0.5, span_z * 0.5, lens, width, height)
    studio.camera(target, distance, 0.0, 0.0, lens)
    studio.render_settings(64, width, height, "CYCLES")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    print("sheet " + studio.render_to(os.path.abspath(path)))


def shot(path, look):
    studio.cyclorama()
    studio.lights()
    target = (0.0, 0.0, look.height * 0.50)
    lens = 110.0
    distance = studio.fit_distance(look.height * 0.30, look.height * 0.54,
                                   lens, 760, 1040)
    studio.camera(target, distance, 0.0, math.radians(2.0), lens)
    studio.render_settings(48, 760, 1040, "CYCLES")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    print("shot " + studio.render_to(os.path.abspath(path)))


if __name__ == "__main__":
    main()
