"""Renders a painted glTF in Blender and checks that its paint shows (CI's interop job; Maquette M6's acceptance).

    blender -b --factory-startup --python-exit-code 1 --python Tools/check_painted_render.py -- painted.glb render.png

The test cube's paint is red; flat Workbench shading shows the texture's own colours, so most of the cube's pixels
must be red.
"""
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
source, output = args[0], args[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
scene = bpy.context.scene
meshes = [obj for obj in scene.objects if obj.type == "MESH"]
if not meshes:
    raise RuntimeError("no mesh came in")
images = [node.image for obj in meshes for slot in obj.material_slots if slot.material and slot.material.use_nodes
          for node in slot.material.node_tree.nodes if node.type == "TEX_IMAGE" and node.image]
if not images:
    raise RuntimeError("the paint texture didn't come in")
print(f"MAQUETTE: texture {images[0].name} {tuple(images[0].size)}")

corners = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
center = sum(corners, Vector()) / len(corners)
camera = bpy.data.objects.new("Check", bpy.data.cameras.new("Check"))
scene.collection.objects.link(camera)
camera.location = center + Vector((2.6, -2.6, 2.0))
camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = camera

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "TEXTURE"
scene.view_settings.view_transform = "Standard"
scene.render.film_transparent = True
scene.render.resolution_x = 256
scene.render.resolution_y = 256
scene.render.filepath = output
bpy.ops.render.render(write_still=True)

pixels = list(bpy.data.images.load(output).pixels)
red = total = 0
for index in range(0, len(pixels), 4):
    r, g, b, a = pixels[index:index + 4]
    if a < 0.5:
        continue
    total += 1
    if r > 0.6 and g < 0.3 and b < 0.3:
        red += 1
share = red / max(total, 1)
print(f"MAQUETTE: {red} of {total} pixels are the paint ({share:.0%})")
if total < 1000 or share < 0.8:
    raise RuntimeError("the paint doesn't show")
print("MAQUETTE: paint shows")
