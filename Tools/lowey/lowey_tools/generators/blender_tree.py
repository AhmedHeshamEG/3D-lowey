"""Blender generator: a low-poly tree (trunk + stacked cones), exported as .glb for 3D-lowey.

  blender --background --factory-startup --python blender_tree.py -- --out tree.glb --seed 3 --kind pine|round
Run through: lowey-link generate tree --seed 3 --kind round
"""
import argparse
import math
import random
import sys

import bpy


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--kind", default="pine", choices=["pine", "round"])
    return parser.parse_args(argv)


def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    return mat


def main():
    options = arguments()
    random.seed(options.seed)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bark = material("Bark", (0.36, 0.22, 0.13))
    leaf = material("Leaves", (0.28 + random.random() * 0.1, 0.5 + random.random() * 0.1, 0.25))
    height = 1.2 + random.random() * 0.6
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.12, depth=height * 0.5, location=(0, 0, height * 0.25))
    trunk = bpy.context.active_object
    trunk.data.materials.append(bark)
    parts = [trunk]
    if options.kind == "pine":
        for level in range(3):
            radius = 0.8 - level * 0.2
            z = height * 0.35 + level * 0.45
            bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=radius, depth=0.8, location=(0, 0, z + 0.4),
                                            rotation=(0, 0, random.random() * math.pi))
            cone = bpy.context.active_object
            cone.data.materials.append(leaf)
            parts.append(cone)
    else:
        for index in range(4):
            angle = index / 4 * math.tau
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.45 + random.random() * 0.2,
                                                  location=(math.cos(angle) * 0.25, math.sin(angle) * 0.25, height * 0.6 + random.random() * 0.4))
            ball = bpy.context.active_object
            ball.data.materials.append(leaf)
            parts.append(ball)
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = trunk
    bpy.ops.object.join()
    bpy.context.active_object.name = f"Tree {options.kind} {options.seed}"
    bpy.ops.object.shade_flat()
    bpy.ops.export_scene.gltf(filepath=options.out, export_format="GLB", use_selection=False, export_yup=True)


main()
