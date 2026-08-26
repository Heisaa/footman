"""The room the figures are photographed in.

Copied off the references rather than invented: a seamless cyclorama in warm
off-white, one broad key high and to the left, a weaker fill opposite, a rim
behind, and a soft contact shadow on the floor. Nothing dramatic -- the point of
a product shot is that the object is the only thing in it.

The one thing that matters photographically is that the key is **big**. A small
lamp puts a hard-edged shadow under the chin and a pinprick highlight on the
forehead, and both read as computer graphics. A two-metre softbox at three
metres gives the broad travelling highlight the reference figures have.
"""

import math

import bpy
from mathutils import Vector

from .palette import Color

SENSOR = 36.0


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                  bpy.data.objects, bpy.data.lights, bpy.data.cameras,
                  bpy.data.curves):
        for item in list(block):
            block.remove(item)


def cyclorama(colour=Color("f3f0ea"), width=24.0, depth=14.0, rise=9.0,
              fillet=2.2, steps=12, stand=4.5, yaw=0.0):
    """Floor curving into a wall with no seam, which is why the background in
    the references has no horizon in it.

    The wall stands `stand` metres behind the origin and the whole thing is
    turned by `yaw`, the camera's own, so it stays behind the figure from
    wherever he is shot. It used to rise at y=0, through the middle of the man:
    hidden from the front, and a plane through his head from the side. `stand`
    also clears the rim light, which sat behind the wall.
    """
    profile = [(stand - depth, 0.0)]
    for i in range(steps + 1):
        a = math.pi * 0.5 * i / steps
        profile.append((stand + fillet * (1.0 - math.sin(a)) - fillet,
                        fillet * (1.0 - math.cos(a))))
    profile.append((stand, rise))

    verts, faces = [], []
    for y, z in profile:
        verts.append((-width * 0.5, y, z))
        verts.append((width * 0.5, y, z))
    for i in range(len(profile) - 1):
        a = i * 2
        faces.append((a, a + 1, a + 3, a + 2))

    mesh = bpy.data.meshes.new("Cyclorama")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True

    mat = bpy.data.materials.new("cyc")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = colour.linear()
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.15
    mesh.materials.append(mat)

    obj = bpy.data.objects.new("Cyclorama", mesh)
    obj.rotation_euler = (0.0, 0.0, yaw)
    bpy.context.collection.objects.link(obj)
    return obj


def lights(strength=1.0):
    made = []
    for name, at, size, power, shape in (
        ("Key", (-2.6, -3.2, 4.0), 3.2, 130.0, "RECTANGLE"),
        ("Fill", (3.4, -3.0, 1.6), 4.0, 55.0, "RECTANGLE"),
        ("Rim", (1.4, 3.6, 3.2), 2.4, 70.0, "RECTANGLE"),
        ("Top", (0.0, -0.4, 5.4), 4.0, 60.0, "RECTANGLE"),
    ):
        data = bpy.data.lights.new(name, type="AREA")
        data.shape = shape
        data.size = size
        data.size_y = size
        data.energy = power * strength
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = at
        aim(obj, Vector((0.0, 0.0, 0.95)))
        made.append(obj)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = Color("e6e6e8").linear()
    bg.inputs["Strength"].default_value = 0.25
    bpy.context.scene.world = world
    return made


def aim(obj, target: Vector):
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def fit_distance(half_width, half_height, lens, width, height, margin=1.10):
    """How far back the camera has to stand for a box that size to fit."""
    if width >= height:
        h = math.atan(SENSOR * 0.5 / lens)
        v = math.atan(SENSOR * 0.5 * (height / width) / lens)
    else:
        v = math.atan(SENSOR * 0.5 / lens)
        h = math.atan(SENSOR * 0.5 * (width / height) / lens)
    return margin * max(half_width / math.tan(h), half_height / math.tan(v))


def camera(target, distance, yaw=0.0, pitch=0.0, lens=110.0):
    data = bpy.data.cameras.new("Camera")
    data.lens = lens
    obj = bpy.data.objects.new("Camera", data)
    bpy.context.collection.objects.link(obj)
    place(obj, target, distance, yaw, pitch)
    bpy.context.scene.camera = obj
    return obj


def place(obj, target, distance, yaw, pitch):
    t = Vector(target)
    obj.location = t + Vector((
        math.sin(yaw) * math.cos(pitch) * distance,
        -math.cos(yaw) * math.cos(pitch) * distance,
        math.sin(pitch) * distance))
    aim(obj, t)
    return obj


def render_settings(samples=64, width=800, height=1100, engine="CYCLES"):
    scene = bpy.context.scene
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    # Standard, not AgX: the palette is flat saturated colour and a film curve
    # takes the life out of a red shirt, which is the one thing it must not do.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    if engine.upper() == "CYCLES":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = samples
        scene.cycles.use_denoising = True
        scene.cycles.max_bounces = 6
        scene.cycles.diffuse_bounces = 3
        scene.cycles.glossy_bounces = 3
    else:
        names = scene.render.bl_rna.properties["engine"].enum_items.keys()
        scene.render.engine = next(n for n in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE")
                                   if n in names)
        scene.eevee.taa_render_samples = max(samples, 32)
    return scene


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
