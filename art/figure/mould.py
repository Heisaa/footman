"""Takes a `Solid` out of the field and puts it in the scene as an object.

Sample -> surface nets -> recalculate normals -> smooth -> material. The one
judgement call is `cell`: it is the sampling size in metres and it sets both how
long a figure takes and how fine the smallest feature can be. A brow ridge is
about 8mm deep on a 1.8m figure, so 4mm is the coarsest that still has brows in
it and 3mm is where they stop looking chipped.
"""

import bmesh
import bpy
from . import surfacenets
from .palette import Color


def vinyl(colour: Color, cache: dict, gloss: float = 0.0):
    """Moulded vinyl: flat colour, a broad soft highlight, a faint clear coat.

    The coat is what separates these from flat shading. On the references the
    figures are plainly *objects* -- there is a highlight travelling across the
    forehead and down the shin, and it is doing more work than the colour is.
    """
    key = ("vinyl", colour.r, colour.g, colour.b, gloss)
    if key in cache:
        return cache[key]
    mat = bpy.data.materials.new("vinyl")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = colour.linear()
    bsdf.inputs["Roughness"].default_value = 0.34 - 0.18 * gloss
    bsdf.inputs["Metallic"].default_value = 0.0
    for name, value in (("Specular IOR Level", 0.5),
                        ("Coat Weight", 0.20 + 0.35 * gloss),
                        ("Coat Roughness", 0.10)):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = value
    cache[key] = mat
    return mat


def skin_material(colour: Color, cache: dict):
    """Skin, with a little light let into it. Vinyl this pale is faintly
    translucent at the ears and the nose, and that is a lot of the warmth."""
    key = ("skin", colour.r, colour.g, colour.b)
    if key in cache:
        return cache[key]
    mat = bpy.data.materials.new("skin")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = colour.linear()
    bsdf.inputs["Roughness"].default_value = 0.40
    for name, value in (("Subsurface Weight", 0.16), ("Subsurface Scale", 0.012),
                        ("Coat Weight", 0.14), ("Coat Roughness", 0.14)):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = value
    if "Subsurface Radius" in bsdf.inputs:
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.22)
    cache[key] = mat
    return mat


def to_object(solid, colour: Color, cell: float, material, parent=None,
              smooth_passes: int = 1):
    field, origin, size = solid.field(cell)
    verts, quads = surfacenets.mesh(field, origin, size)
    if len(verts) == 0:
        return None

    mesh = bpy.data.meshes.new(solid.name)
    mesh.from_pydata(verts.tolist(), [], quads.tolist())
    mesh.update()

    # Surface nets does not care which way round it emits a quad, so the winding
    # is fixed here rather than reasoned about there. The mesh is watertight,
    # which is what makes this reliable.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.materials.append(material)

    obj = bpy.data.objects.new(solid.name, mesh)
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    if smooth_passes > 0:
        # Takes the last of the sampling off the surface. Kept low: the hems and
        # the sock tops are the point, and enough of this rounds them away.
        mod = obj.modifiers.new("Smooth", "SMOOTH")
        mod.factor = 0.5
        mod.iterations = smooth_passes
    return obj


def figure(parts, cell: float, name: str = "Player", cache=None):
    """Builds every moulding of one figure under a single empty.

    Returns the empty. The figure is built facing -Y, which is the direction
    Blender's front view and this studio's camera both look from, so nothing is
    turned here.
    """
    cache = {} if cache is None else cache
    root = bpy.data.objects.new(name, None)
    root.empty_display_size = 0.1
    bpy.context.collection.objects.link(root)

    for solid, colour in parts:
        if solid.name == "skin":
            material = skin_material(colour, cache)
        else:
            gloss = 0.9 if solid.name in ("boots", "ink") else 0.0
            material = vinyl(colour, cache, gloss)
        to_object(solid, colour, cell, material, parent=root)
    return root
