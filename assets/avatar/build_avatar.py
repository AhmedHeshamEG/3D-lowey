"""Build Hesham's avatar (the Lowey mascot) in Blender from his drawing.

    python assets/avatar/trace_drawing.py assets/avatar/drawing.png assets/avatar/trace.json
    blender -b --factory-startup -P assets/avatar/build_avatar.py -- <out_dir>

The drawing is the source of truth. trace.json holds what was measured from it:
the head's silhouette (turned into a surface of revolution), every face mark as a
contour (painted onto the head from the front, one object per part so the face can
animate), and inflated meshes for the body and the beret (they are not round, so
they are blown up from their outlines instead of turned).

Writes avatar.glb (neutral pose, plain PBR, ink shells applied: the Lowey asset),
avatar.blend (toon look, the drawing's pose) and renders/*.png.

Units: 683 drawing pixels = 1 unit (the drawing is 4 units wide, the head about 1).
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else HERE
RENDERS = os.path.join(OUT, "renders")
os.makedirs(RENDERS, exist_ok=True)

with open(os.path.join(HERE, "trace.json")) as f:
    T = json.load(f)

PX = 683.0
AXIS_X = T["axis_x"]
BODY_BOTTOM = T["body"]["bbox"][1] + T["body"]["bbox"][3]
GROUND_Y = BODY_BOTTOM + 0.08 * PX  # he floats a little above z = 0
INK = T["ink_px"] / PX
HAT_DEPTH = 2.4  # the beret is a disc seen edge-on: much deeper than its outline is tall


def P(px, py):
    """Drawing pixel -> (x, z) in the front plane."""
    return ((px - AXIS_X) / PX, (GROUND_Y - py) / PX)


def srgb(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i : i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# ------------------------------------------------------------------------ meshes


def finish(name, bm, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def lathe(name, profile, segments=80, depth=1.0):
    """Closed surface of revolution; profile [(r, z)] from bottom pole to top pole."""
    bm = bmesh.new()
    rings = []
    for r, z in profile[1:-1]:
        rings.append([
            bm.verts.new((r * math.sin(a), -r * math.cos(a) * depth, z))
            for a in (2 * math.pi * s / segments for s in range(segments))
        ])
    bottom = bm.verts.new((0, 0, profile[0][1]))
    top = bm.verts.new((0, 0, profile[-1][1]))
    for s in range(segments):
        n = (s + 1) % segments
        bm.faces.new((bottom, rings[0][n], rings[0][s]))
        for k in range(len(rings) - 1):
            bm.faces.new((rings[k][s], rings[k][n], rings[k + 1][n], rings[k + 1][s]))
        bm.faces.new((rings[-1][s], rings[-1][n], top))
    return finish(name, bm)


def head_profile():
    """The traced silhouette, averaged left/right, with a cap tucked under the hat."""
    rows = T["head_skin_rows"]
    halves = [(r - l) / 2 for _, l, r in rows]
    k = 4
    smooth = [sum(halves[max(0, i - k) : i + k + 1]) / len(halves[max(0, i - k) : i + k + 1])
              for i in range(len(halves))]
    pts = [(smooth[i] / PX, P(0, rows[i][0])[1]) for i in range(0, len(rows), 9)]
    pts.sort(key=lambda p: p[1])  # bottom -> top
    profile = [(0.0, pts[0][1] - 0.3 / PX)] + pts
    # cap: continue the cone's slope, then round off to a horizontal tangent at the peak
    (r1, z1), (r0, z0) = pts[-3], pts[-1]
    slope = (r1 - r0) / (z0 - z1)  # radius lost per unit of height
    peak = z0 + 0.55 * r0 / slope
    ctrl = (r0 - slope * (peak - z0), peak)
    for i in range(1, 9):
        t = i / 8
        r = (1 - t) ** 2 * r0 + 2 * (1 - t) * t * ctrl[0]
        z = (1 - t) ** 2 * z0 + 2 * (1 - t) * t * ctrl[1] + t * t * peak
        profile.append((r if i < 8 else 0.0, z))
    return profile


def inflated(name, mesh, depth_scale=1.0):
    bm = bmesh.new()
    verts = []
    for x, y, d in mesh["verts"]:
        wx, wz = P(x, y)
        verts.append(bm.verts.new((wx, -d / PX * depth_scale, wz)))
    for face in mesh["faces"]:
        bm.faces.new([verts[i] for i in face])
    return finish(name, bm)


def ellipsoid(name, a, b, c):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    bmesh.ops.scale(bm, vec=(a, b, c), verts=bm.verts)
    return finish(name, bm)


def decal(name, polygons, target, offset, cuts=2):
    """Fill drawing-space polygons and paint them onto `target` from the front."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(target, depsgraph)
    mw = target.matrix_world
    inv = mw.inverted()
    direction = (inv.to_3x3() @ Vector((0, 1, 0))).normalized()
    bm = bmesh.new()
    for poly in polygons:
        ring = []
        for x, y in poly:
            wx, wz = P(x, y)
            ring.append(bm.verts.new((wx, 0.0, wz)))
        edges = [bm.edges.new((ring[i], ring[(i + 1) % len(ring)])) for i in range(len(ring))]
        filled = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges)
        faces = [g for g in filled["geom"] if isinstance(g, bmesh.types.BMFace)]
        inner = list({e for f in faces for e in f.edges})
        bmesh.ops.subdivide_edges(bm, edges=inner, cuts=cuts, use_grid_fill=True)
    for v in bm.verts:
        origin = inv @ Vector((v.co.x, -5.0, v.co.z))
        loc, normal, _, _ = bvh.ray_cast(origin, direction)
        if loc is None:  # a hair outside the silhouette: snap to the nearest surface
            loc, normal, _, dist = bvh.find_nearest(inv @ Vector((v.co.x, 0.0, v.co.z)))
            if loc is None or dist > 0.02:
                raise RuntimeError(f"{name}: {tuple(v.co)} misses {target.name}")
        v.co = mw @ (loc + normal.normalized() * offset)
    obj = finish(name, bm)
    for poly in obj.data.polygons:
        if poly.normal.y > 0:
            poly.flip()
    return obj


def set_origin(obj, pivot):
    pivot = Vector(pivot)
    obj.data.transform(Matrix.Translation(obj.location - pivot))
    obj.location = pivot


def parent(child, par):
    bpy.context.view_layer.update()
    mw = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = mw


# ------------------------------------------------------------------------ build


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = {}

    profile = head_profile()
    head = lathe("Head", profile, depth=0.92)
    parts["Head"] = head

    face = T["face"]
    for name in ("Brow.L", "Brow.R", "Eye.L", "Eye.R", "Mouth", "Cheek.L", "Cheek.R"):
        parts[name] = decal(name, face[name], head, 0.004)
    for name in ("Shine.L", "Shine.R"):
        parts[name] = decal(name, face[name], head, 0.0075)

    hat = inflated("Hat", T["hat_mesh"], HAT_DEPTH)
    parts["Hat"] = hat
    parts["Hat.Mark"] = decal("Hat.Mark", T["hat_mark"], hat, 0.003)

    body = inflated("Body", T["body_mesh"])
    parts["Body"] = body

    for side, hand in zip(("L", "R"), T["hands"]):
        minor, major = sorted(hand["axes"])
        long_angle = (hand["angle"] + 90) % 180
        long_angle = long_angle - 180 if long_angle > 90 else long_angle
        obj = ellipsoid(f"Hand.{side}", major / 2 / PX, major / 2 / PX * 0.5, minor / 2 / PX)
        x, z = P(*hand["center"])
        obj.location = (x, -0.02, z)
        obj.rotation_euler = (0, math.radians(long_angle), 0)
        parts[f"Hand.{side}"] = obj

    # Pivots where animation wants them.
    zs = [z for _, z in profile]
    set_origin(head, (0, 0, (min(zs) + max(zs)) / 2))
    hx, hz = P(*T["hat_mesh"]["peak"])
    set_origin(hat, (hx, 0, hz))
    bx, bz = P(*T["body_mesh"]["peak"])
    set_origin(body, (bx, 0, bz))

    root = bpy.data.objects.new("Avatar", None)
    bpy.context.scene.collection.objects.link(root)
    for name in ("Head", "Body", "Hand.L", "Hand.R"):
        parent(parts[name], root)
    for name, obj in parts.items():
        if name not in ("Head", "Body", "Hand.L", "Hand.R", "Hat.Mark"):
            parent(obj, head)
    parent(parts["Hat.Mark"], hat)
    return root, parts


# --------------------------------------------------------------------- the poses

POSED = ("Body", "Hand.L", "Hand.R")


def capture_pose(parts):
    return {n: (parts[n].location.copy(), parts[n].rotation_euler.copy()) for n in POSED}


def neutral_pose(parts, drawing):
    """Symmetric rest pose: body upright under the head, hands mirrored."""
    body = parts["Body"]
    bpy.context.view_layer.update()
    pts = [body.matrix_world @ v.co for v in body.data.vertices]
    tip = max(pts, key=lambda p: p.z)
    far = max(pts, key=lambda p: (p - tip).length)  # the drop's long axis runs tip -> far end
    tilt = math.atan2(tip.x - far.x, tip.z - far.z)
    body.rotation_euler = (0, -tilt, 0)
    body.location = (0, 0, drawing["Body"][0].z - 0.04)
    hl, hr = drawing["Hand.L"], drawing["Hand.R"]
    spread = (abs(hl[0].x - drawing["Body"][0].x) + abs(hr[0].x - drawing["Body"][0].x)) / 2
    angle = (abs(hl[1].y) + abs(hr[1].y)) / 2
    z = (hl[0].z + hr[0].z) / 2
    parts["Hand.L"].location = (-spread, -0.02, z)
    parts["Hand.R"].location = (spread, -0.02, z)
    parts["Hand.L"].rotation_euler = (0, angle, 0)
    parts["Hand.R"].rotation_euler = (0, -angle, 0)
    bpy.context.view_layer.update()


def apply_pose(parts, pose):
    for n, (loc, rot) in pose.items():
        parts[n].location, parts[n].rotation_euler = loc, rot
    bpy.context.view_layer.update()


# --------------------------------------------------------------------- materials

LOOK = {  # name: (lit, shade or None for flat), sRGB
    "Skin": ("#ffffff", "#b3b6ff"),
    "Hat": ("#5d69ff", "#3440e0"),
    "Ink": ("#0b0b10", None),
    "HatInk": ("#2a31b8", None),
    "Shine": ("#ffffff", None),
    "Blush": ("#ec1c24", None),
    "HatMark": ("#e3f6ff", None),
}
ASSIGN = {
    "Head": "Skin", "Body": "Skin", "Hand.L": "Skin", "Hand.R": "Skin", "Hat": "Hat",
    "Hat.Mark": "HatMark", "Brow.L": "Ink", "Brow.R": "Ink", "Eye.L": "Ink", "Eye.R": "Ink",
    "Mouth": "Ink", "Shine.L": "Shine", "Shine.R": "Shine", "Cheek.L": "Blush", "Cheek.R": "Blush",
}
OUTLINE = {"Head": ("Ink", INK), "Body": ("Ink", INK * 0.8), "Hand.L": ("Ink", INK * 0.55),
           "Hand.R": ("Ink", INK * 0.55), "Hat": ("HatInk", INK * 0.3)}


def pbr_material(name):
    lit, shade = LOOK[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(lit)
    bsdf.inputs["Roughness"].default_value = 0.6 if shade else 0.9
    if name in ("Shine", "HatMark"):
        bsdf.inputs["Emission Color"].default_value = srgb(lit)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    m.use_backface_culling = name in ("Ink", "HatInk")
    return m


def toon_material(name):
    lit, shade = LOOK[name]
    m = bpy.data.materials.new(name + ".Toon")
    m.use_nodes = True
    m.use_backface_culling = name in ("Ink", "HatInk")
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs[0], out.inputs[0])
    if shade is None:
        emit.inputs["Color"].default_value = srgb(lit)
        return m
    diffuse = nt.nodes.new("ShaderNodeBsdfDiffuse")
    to_rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.02, srgb(shade)
    e[1].position, e[1].color = 0.24, srgb(lit)
    nt.links.new(diffuse.outputs[0], to_rgb.inputs[0])
    nt.links.new(to_rgb.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    return m


def apply_materials(parts, factory):
    mats = {name: factory(name) for name in LOOK}
    for name, obj in parts.items():
        obj.data.materials.clear()
        obj.data.materials.append(mats[ASSIGN[name]])
        for mod in list(obj.modifiers):
            obj.modifiers.remove(mod)
        if name in OUTLINE:
            ink, thickness = OUTLINE[name]
            obj.data.materials.append(mats[ink])
            mod = obj.modifiers.new("Ink", "SOLIDIFY")  # inverted hull
            mod.thickness = thickness
            mod.offset = 1.0
            mod.use_flip_normals = True
            mod.material_offset = 1
            mod.use_rim = False


# ----------------------------------------------------------------------- staging


def world_and_light():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"
    scene.eevee.taa_render_samples = 64
    world = bpy.data.worlds.new("Space")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    ambient = nt.nodes.new("ShaderNodeBackground")
    ambient.inputs["Color"].default_value = srgb("#8a7ab8")
    ambient.inputs["Strength"].default_value = 0.4
    sky = nt.nodes.new("ShaderNodeBackground")
    coords = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 8.0
    nebula = nt.nodes.new("ShaderNodeValToRGB")
    e = nebula.color_ramp.elements
    e[0].position, e[0].color = 0.35, srgb("#0e0618")
    e[1].position, e[1].color = 0.72, srgb("#7a2a8c")
    e.new(0.55).color = srgb("#2c1450")
    stars = nt.nodes.new("ShaderNodeTexVoronoi")
    stars.inputs["Scale"].default_value = 260.0
    star_mask = nt.nodes.new("ShaderNodeMath")
    star_mask.operation = "LESS_THAN"
    star_mask.inputs[1].default_value = 0.018
    add = nt.nodes.new("ShaderNodeMix")
    add.data_type = "RGBA"
    add.blend_type = "ADD"
    add.inputs[7].default_value = (0.6, 0.6, 0.75, 1)  # B (colour)
    path = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(coords.outputs["Window"], noise.inputs["Vector"])
    nt.links.new(coords.outputs["Window"], stars.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], nebula.inputs["Fac"])
    nt.links.new(stars.outputs["Distance"], star_mask.inputs[0])
    nt.links.new(star_mask.outputs[0], add.inputs[0])
    nt.links.new(nebula.outputs["Color"], add.inputs[6])
    nt.links.new(add.outputs[2], sky.inputs["Color"])
    nt.links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(ambient.outputs[0], mix.inputs[1])
    nt.links.new(sky.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])

    sun = bpy.data.lights.new("Key", "SUN")
    sun.energy = 3.0
    sun.use_shadow = False  # a drawing has no cast shadows: shading comes from the form only
    key = bpy.data.objects.new("Key", sun)
    bpy.context.scene.collection.objects.link(key)
    aim_key(key, 0.0)
    return key


def aim_key(key, yaw_deg):
    """Key light from the upper left of a camera that orbits by `yaw_deg`."""
    d = Matrix.Rotation(math.radians(yaw_deg), 3, "Z") @ Vector((0.7, 0.9, -0.55))
    key.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def camera(name, location, target, ortho_scale=None, lens=60):
    cam = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, cam)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    if ortho_scale:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho_scale
    else:
        cam.lens = lens
    cam.clip_start = 0.05
    return obj


def render(cam, name, size, transparent=False):
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.film_transparent = transparent
    scene.render.filepath = os.path.join(RENDERS, name)
    bpy.ops.render.render(write_still=True)


def main():
    _, parts = build()
    drawing = capture_pose(parts)
    neutral_pose(parts, drawing)
    neutral = capture_pose(parts)

    # 1. The Lowey asset: neutral pose, plain PBR, ink shells baked in.
    apply_materials(parts, pbr_material)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "avatar.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)

    # 2. Look-dev.
    apply_materials(parts, toon_material)
    key = world_and_light()
    only = os.environ.get("AVATAR_RENDERS", "all")
    w, h = T["size"]
    cx, cz = P(w / 2, h / 2)
    front = camera("Cam.Drawing", (cx, -10, cz), (cx, 0, cz), ortho_scale=w / PX)
    apply_pose(parts, drawing)
    render(front, "front_match.png", (1000, 750), transparent=True)
    if only == "all":
        hero = camera("Cam.Hero", (-2.3, -4.6, 1.75), (-0.05, 0, 1.0), lens=70)
        render(hero, "hero.png", (1600, 1200))
        low = camera("Cam.Low", (1.7, -3.3, 0.3), (0.0, 0, 0.95), lens=55)
        render(low, "low_angle.png", (1200, 1200))
        apply_pose(parts, neutral)
        for i, deg in enumerate((0, 45, 90, 135, 180)):
            a = math.radians(deg)
            cam = camera(f"Cam.Turn{deg}", (5.5 * math.sin(a), -5.5 * math.cos(a), 1.0), (0, 0, 0.95),
                         lens=65)
            aim_key(key, deg)
            render(cam, f"turn_{i}_{deg}.png", (700, 1000))
        aim_key(key, 0.0)
        apply_pose(parts, drawing)
    bpy.context.scene.camera = front
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "avatar.blend"))


main()
