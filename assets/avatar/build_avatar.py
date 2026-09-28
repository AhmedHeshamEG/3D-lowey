"""Build Hesham's avatar (the Lowey mascot) in Blender.

    python assets/avatar/trace_drawing.py assets/avatar/drawing.png assets/avatar/trace.json
    blender -b --factory-startup -P assets/avatar/build_avatar.py [-- <out_dir>]

Environment: AVATAR_LABEL="TEXT" puts a name on the beret instead of the Pisces mark.

Design (v2). The drawing gives the character's identity; the build turns it into something
that animates:
  * head: the drawing's onion silhouette, turned (a surface of revolution);
  * face kit: clean, mirrored parts placed where the drawing has them, each one tagged with
    the role Lowey's face rig drives (custom property "faceRole", exported as glTF extras):
      eye.L/R (blink = squash), pupil.L/R (the shines: look), brow.L/R,
      mouth (group) with mouth.A-H, mouth.X (Rhubarb lip-sync set; X = his smirk) and the
      expression mouths mouth.smile, mouth.grin, mouth.frown;
  * body: the drawing's floating drop, inflated from its outline. No legs: he hovers,
    with a soft glow under him;
  * arms: rubber hose. A bendy tube from each shoulder to the wrist, hooked to the hand,
    so moving a hand moves the arm. Mitten hands with a thumb;
  * beret: inflated from the drawing, carrying the Pisces mark (or AVATAR_LABEL).

Writes avatar.glb (rest pose, PBR, ink shells applied), avatar.blend (toon look, live
rubber-hose arms) and renders/*.png for renders/sheet.jpg (compare.py).
Units: 683 drawing pixels = 1 unit.
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
LABEL = os.environ.get("AVATAR_LABEL", "").strip()

with open(os.path.join(HERE, "trace.json")) as f:
    T = json.load(f)

PX = 683.0
AXIS_X = T["axis_x"]
BODY_BOTTOM = T["body"]["bbox"][1] + T["body"]["bbox"][3]
GROUND_Y = BODY_BOTTOM + 0.08 * PX
INK = T["ink_px"] / PX
HAT_DEPTH = 2.4


def P(px, py):
    """Drawing pixel -> (x, z) in the front plane."""
    return ((px - AXIS_X) / PX, (GROUND_Y - py) / PX)


def centroid(poly):
    return sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly)


def bbox(poly):
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


def srgb(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i : i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# ---------------------------------------------------------------- where the face goes
# Measured from the drawing, then mirrored: the kit is symmetric so expressions read cleanly.

_face = T["face"]


def _mirror(name):
    (lx, lz), (rx, rz) = (P(*centroid(_face[f"{name}.{s}"][0])) for s in ("L", "R"))
    return (abs(lx) + abs(rx)) / 2, (lz + rz) / 2


EYE_X, EYE_Z = _mirror("Eye")
_eb = [bbox(_face[f"Eye.{s}"][0]) for s in ("L", "R")]
EYE_RX = sum(b[2] - b[0] for b in _eb) / 4 / PX
EYE_RZ = sum(b[3] - b[1] for b in _eb) / 4 / PX
BROW_X, BROW_Z = _mirror("Brow")
CHEEK_X, CHEEK_Z = _mirror("Cheek")
MOUTH_Z = P(*centroid(_face["Mouth"][0]))[1]
MOUTH_X = 0.0


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
    """The traced silhouette, averaged left/right, with a cap tucked under the beret."""
    rows = T["head_skin_rows"]
    halves = [(r - l) / 2 for _, l, r in rows]
    k = 4
    smooth = [sum(halves[max(0, i - k) : i + k + 1]) / len(halves[max(0, i - k) : i + k + 1])
              for i in range(len(halves))]
    pts = [(smooth[i] / PX, P(0, rows[i][0])[1]) for i in range(0, len(rows), 9)]
    pts.sort(key=lambda p: p[1])
    profile = [(0.0, pts[0][1] - 0.3 / PX)] + pts
    (r1, z1), (r0, z0) = pts[-3], pts[-1]
    slope = (r1 - r0) / (z0 - z1)
    peak = z0 + 0.55 * r0 / slope
    ctrl = (r0 - slope * (peak - z0), peak)
    for i in range(1, 9):
        t = i / 8
        r = (1 - t) ** 2 * r0 + 2 * (1 - t) * t * ctrl[0]
        z = (1 - t) ** 2 * z0 + 2 * (1 - t) * t * ctrl[1] + t * t * peak
        profile.append((r if i < 8 else 0.0, z))
    return profile


def egg_profile(height, radius, widest, bottom_p, top_a, top_b, z0=0.0, n=40):
    """A drop: superellipse below the widest ring, tapering above it."""
    pts = []
    for i in range(n + 1):
        t = (1 - math.cos(math.pi * i / n)) / 2
        if t <= widest:
            u = (widest - t) / widest
            r = radius * max(0.0, 1 - u ** bottom_p) ** (1 / bottom_p)
        else:
            u = (t - widest) / (1 - widest)
            r = radius * max(0.0, 1 - u ** top_a) ** top_b
        pts.append((r, z0 + t * height))
    return pts


def inflated(name, mesh, depth_scale=1.0):
    bm = bmesh.new()
    verts = []
    for x, y, d in mesh["verts"]:
        wx, wz = P(x, y)
        verts.append(bm.verts.new((wx, -d / PX * depth_scale, wz)))
    for face in mesh["faces"]:
        bm.faces.new([verts[i] for i in face])
    return finish(name, bm)


def ellipsoid_into(bm, center, radii, rotation=Matrix.Identity(3), segments=32, rings=16):
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=radii, verts=verts)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rotation, verts=verts)
    bmesh.ops.translate(bm, vec=center, verts=verts)


def mitten(name, side):
    """Palm + thumb. Fingers point down at rest, palm faces the body, thumb forward."""
    s = -1 if side == "L" else 1
    bm = bmesh.new()
    ellipsoid_into(bm, (0, 0, 0), (0.032, 0.05, 0.058))
    ellipsoid_into(bm, (-s * 0.004, -0.045, 0.012), (0.017, 0.028, 0.017),
                   Matrix.Rotation(math.radians(-35), 3, "X"), segments=20, rings=10)
    return finish(name, bm)


# ------------------------------------------------------------------ painted parts


def outline_polys(bm, polys):
    """Filled polygons (lists of (x, z) in units) in the front plane, dense enough to hug."""
    for poly in polys:
        ring = [bm.verts.new((x, 0.0, z)) for x, z in poly]
        edges = [bm.edges.new((ring[i], ring[(i + 1) % len(ring)])) for i in range(len(ring))]
        filled = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges)
        faces = [g for g in filled["geom"] if isinstance(g, bmesh.types.BMFace)]
        bmesh.ops.subdivide_edges(bm, edges=list({e for f in faces for e in f.edges}), cuts=2,
                                  use_grid_fill=True)


def catmull(points, samples):
    pts = [points[0]] + list(points) + [points[-1]]
    out, segs = [], len(points) - 1
    for i in range(samples + 1):
        f = i / samples * segs
        k = min(int(f), segs - 1)
        t = f - k
        p0, p1, p2, p3 = (Vector(pts[k + j]) for j in range(4))
        out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return out


def stroke(bm, points, widths, samples=48, across=3):
    """A brush stroke with round caps: centreline through `points`, width per point (units)."""
    pts = catmull([Vector(p) for p in points], samples)
    wid = catmull([Vector((w, 0)) for w in widths], samples)
    lengths = [0.0]
    for a, b in zip(pts, pts[1:]):
        lengths.append(lengths[-1] + (b - a).length)
    total = lengths[-1]
    rows = []
    for i, p in enumerate(pts):
        tangent = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        normal = Vector((-tangent.y, tangent.x))
        h = wid[i].x / 2
        for end in (lengths[i], total - lengths[i]):
            if end < h:
                h *= math.sqrt(max(0.0, 1 - ((h - end) / h) ** 2))
        h = max(h, 1e-5)
        row = []
        for j in range(across + 1):
            q = p + normal * h * (2 * j / across - 1)
            row.append(bm.verts.new((q.x, 0.0, q.y)))
        rows.append(row)
    for i in range(len(rows) - 1):
        for j in range(across):
            bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))


def ellipse(cx, cz, rx, rz, n=48, rot=0.0, squareness=2.0):
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        r = 1 / (abs(c) ** squareness + abs(s) ** squareness) ** (1 / squareness)
        x, z = c * r * rx, s * r * rz
        out.append((cx + x * math.cos(rot) - z * math.sin(rot), cz + x * math.sin(rot) + z * math.cos(rot)))
    return out


def paint(name, bm, target, offset, pivot=None):
    """Project the front-plane geometry in `bm` onto `target`, lifted `offset` off it."""
    project(name, bm, target, offset)
    obj = finish(name, bm)
    for poly in obj.data.polygons:
        if poly.normal.y > 0:
            poly.flip()
    if pivot is not None:
        set_origin(obj, surface_point(target, *pivot, offset))
    return obj


def project(name, bm, target, offset):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(target, depsgraph)
    mw = target.matrix_world
    inv = mw.inverted()
    direction = (inv.to_3x3() @ Vector((0, 1, 0))).normalized()
    for v in bm.verts:
        loc, normal, _, _ = bvh.ray_cast(inv @ Vector((v.co.x, -5.0, v.co.z)), direction)
        if loc is None:
            loc, normal, _, dist = bvh.find_nearest(inv @ Vector((v.co.x, 0.0, v.co.z)))
            if loc is None or dist > 0.02:
                raise RuntimeError(f"{name}: {tuple(v.co)} misses {target.name}")
        v.co = mw @ (loc + normal.normalized() * offset)


def surface_point(target, x, z, offset=0.0):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(target, depsgraph)
    mw, inv = target.matrix_world, target.matrix_world.inverted()
    loc, normal, _, _ = bvh.ray_cast(inv @ Vector((x, -5.0, z)), (inv.to_3x3() @ Vector((0, 1, 0))).normalized())
    return mw @ (loc + normal.normalized() * offset)


def local_sphere_centre(target, x, z, reach):
    """Centre of the sphere that best fits `target`'s front surface around (x, z): turning
    something about it keeps it on the surface (the head is not a sphere, its patches are)."""
    import numpy as np

    pts = [surface_point(target, x + dx * reach, z + dz * reach)
           for dx in (-1, -0.5, 0, 0.5, 1) for dz in (-1, -0.5, 0, 0.5, 1)]
    A = np.array([[2 * p.x, 2 * p.y, 2 * p.z, 1.0] for p in pts])
    b = np.array([p.length_squared for p in pts])
    c = np.linalg.lstsq(A, b, rcond=None)[0]
    return Vector(c[:3])


def set_origin(obj, pivot):
    pivot = Vector(pivot)
    obj.data.transform(Matrix.Translation(obj.location - pivot))
    obj.location = pivot


def parent(child, par):
    bpy.context.view_layer.update()
    mw = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = mw


# -------------------------------------------------------------------- the face kit

MOUTH_W = 0.085  # half-width of the speaking shapes


def mouth_shapes():
    """(name, [(layer, geometry-builder)]) for every mouth. Layers: dark, teeth, tongue, ink."""
    w = MOUTH_W
    smirk = [[P(x, y) for x, y in _face["Mouth"][0]]]
    sx = centroid([p for poly in smirk for p in poly])[0]
    smirk = [[(x - sx + MOUTH_X + 0.03, z - MOUTH_Z) for x, z in poly] for poly in smirk]  # centred

    def line(pts, width=0.016):
        return ("ink", lambda bm: stroke(bm, pts, [width] * len(pts)))

    def fill(layer, polys):
        return (layer, lambda bm: outline_polys(bm, polys))

    lens = lambda top, bottom, n=40: [  # noqa: E731  closed lens: top arc over bottom arc
        (-w + 2 * w * i / n, top * math.sin(math.pi * i / n)) for i in range(n + 1)
    ] + [(w - 2 * w * i / n, -bottom * math.sin(math.pi * i / n)) for i in range(1, n)]

    return {
        "X": [fill("ink", smirk)],
        "A": [line([(-w * 0.85, 0.002), (0, -0.004), (w * 0.85, 0.002)], 0.019)],
        "B": [fill("dark", [lens(0.012, 0.026)]),
              fill("teeth", [[(-w * 0.72, 0.004), (w * 0.72, 0.004), (w * 0.6, -0.012), (-w * 0.6, -0.012)]])],
        "C": [fill("dark", [ellipse(0, -0.012, w * 0.9, 0.042)]),
              fill("teeth", [[(-w * 0.62, 0.02), (w * 0.62, 0.02), (w * 0.5, 0.006), (-w * 0.5, 0.006)]]),
              fill("tongue", [ellipse(0, -0.04, w * 0.45, 0.014)])],
        "D": [fill("dark", [ellipse(0, -0.028, w * 1.0, 0.064, squareness=2.4)]),
              fill("teeth", [[(-w * 0.7, 0.028), (w * 0.7, 0.028), (w * 0.6, 0.012), (-w * 0.6, 0.012)]]),
              fill("tongue", [ellipse(0, -0.068, w * 0.55, 0.02)])],
        "E": [fill("dark", [ellipse(0, -0.016, w * 0.62, 0.05)]),
              fill("tongue", [ellipse(0, -0.046, w * 0.34, 0.012)])],
        "F": [fill("dark", [ellipse(0, -0.006, w * 0.34, 0.03)])],
        "G": [fill("dark", [lens(0.01, 0.022)]),
              fill("teeth", [[(-w * 0.55, 0.012), (w * 0.55, 0.012), (w * 0.5, -0.016), (-w * 0.5, -0.016)]])],
        "H": [fill("dark", [ellipse(0, -0.014, w * 0.85, 0.045)]),
              fill("tongue", [ellipse(0, 0.004, w * 0.42, 0.016)])],
        "smile": [line([(-w * 1.2, 0.02), (-w * 0.6, -0.012), (0, -0.02), (w * 0.6, -0.012), (w * 1.2, 0.02)],
                       0.018)],
        "grin": [fill("dark", [[(-w * 1.15, 0.018), (w * 1.15, 0.018)] + [
            (w * 1.15 * math.cos(math.pi * i / 30), 0.018 - 0.085 * math.sin(math.pi * i / 30)) for i in range(1, 30)
        ]]), fill("tongue", [ellipse(0, -0.045, w * 0.55, 0.02)]),
            fill("teeth", [[(-w * 0.95, 0.014), (w * 0.95, 0.014), (w * 0.85, -0.004), (-w * 0.85, -0.004)]])],
        "frown": [line([(-w * 0.9, -0.018), (-w * 0.4, 0.004), (w * 0.4, 0.004), (w * 0.9, -0.018)], 0.017)],
    }


LAYER_OFFSET = {"dark": 0.004, "ink": 0.0045, "teeth": 0.0062, "tongue": 0.0062}
LAYER_MAT = {"dark": "MouthDark", "ink": "Ink", "teeth": "Teeth", "tongue": "Tongue"}


def build_face(head, parts):
    # eyes: black ovals; the two shines are the pupil (they slide when he looks around)
    for side, sx in (("L", -1), ("R", 1)):
        cx = sx * EYE_X
        bm = bmesh.new()
        outline_polys(bm, [ellipse(cx, EYE_Z, EYE_RX, EYE_RZ, rot=sx * math.radians(4))])
        eye = paint(f"Eye.{side}", bm, head, 0.004, pivot=(cx, EYE_Z))
        eye["faceRole"] = f"eye.{side}"
        parts[eye.name] = eye
        bm = bmesh.new()
        outline_polys(bm, [ellipse(cx - 0.3 * EYE_RX, EYE_Z + 0.34 * EYE_RZ, 0.31 * EYE_RX, 0.3 * EYE_RX),
                           ellipse(cx + 0.36 * EYE_RX, EYE_Z - 0.42 * EYE_RZ, 0.13 * EYE_RX, 0.13 * EYE_RX)])
        shine = paint(f"Shine.{side}", bm, head, 0.0075, pivot=(cx, EYE_Z))
        parts[shine.name] = shine
        # looking = turning the shines about the head's centre, so they glide over the surface
        look = bpy.data.objects.new(f"Look.{side}", None)
        bpy.context.scene.collection.objects.link(look)
        look.location = local_sphere_centre(head, cx, EYE_Z, EYE_RX)
        look.empty_display_size = 0.05
        look["faceRole"] = f"pupil.{side}"
        look["lookPivot"] = True
        parts[look.name] = look

        # brows: a soft arc, thick in the middle, outer end lower (his hopeful look)
        bx = sx * BROW_X
        pts = [(bx + sx * dx, BROW_Z + dz) for dx, dz in
               ((-0.1, 0.004), (-0.045, 0.034), (0.03, 0.036), (0.105, -0.018))]
        bm = bmesh.new()
        stroke(bm, pts, [0.046, 0.06, 0.058, 0.048])
        brow = paint(f"Brow.{side}", bm, head, 0.004, pivot=(bx, BROW_Z))
        brow["faceRole"] = f"brow.{side}"
        parts[brow.name] = brow

        bm = bmesh.new()
        outline_polys(bm, [ellipse(sx * CHEEK_X, CHEEK_Z, 0.036, 0.026, squareness=2.3)])
        cheek = paint(f"Cheek.{side}", bm, head, 0.004)
        parts[cheek.name] = cheek

    # mouth: a group with one child per shape; the face rig shows one at a time
    mouth = bpy.data.objects.new("Mouth", None)
    bpy.context.scene.collection.objects.link(mouth)
    mouth.location = surface_point(head, MOUTH_X, MOUTH_Z, 0.004)
    mouth["faceRole"] = "mouth"
    parts["Mouth"] = mouth
    for shape, layers in mouth_shapes().items():
        merged = bmesh.new()
        used = []
        for layer, builder in layers:
            lbm = bmesh.new()
            builder(lbm)
            for v in lbm.verts:
                v.co.x += MOUTH_X
                v.co.z += MOUTH_Z
            project(f"Mouth.{shape}", lbm, head, LAYER_OFFSET[layer])
            if layer not in used:
                used.append(layer)
            index = used.index(layer)
            vmap = {v: merged.verts.new(v.co) for v in lbm.verts}
            for f in lbm.faces:
                nf = merged.faces.new([vmap[v] for v in f.verts])
                nf.material_index = index
            lbm.free()
        shape_obj = finish(f"Mouth.{shape}", merged)
        for poly in shape_obj.data.polygons:
            if poly.normal.y > 0:
                poly.flip()
        for layer in used:
            shape_obj.data.materials.append(bpy.data.materials[LAYER_MAT[layer]])
        set_origin(shape_obj, mouth.location)
        shape_obj["faceRole"] = f"mouth.{shape}"
        shape_obj.hide_render = shape != "X"  # never hide_viewport: hidden objects are not evaluated
        parts[shape_obj.name] = shape_obj


# ------------------------------------------------------------------ arms and hands


def shoulder_point(body, side):
    """A point just inside the body's side, a little above its middle."""
    s = -1 if side == "L" else 1
    bpy.context.view_layer.update()
    pts = [body.matrix_world @ v.co for v in body.data.vertices]
    zmin, zmax = min(p.z for p in pts), max(p.z for p in pts)
    z = zmin + 0.7 * (zmax - zmin)
    band = [p for p in pts if abs(p.z - z) < 0.02]
    edge = max(band, key=lambda p: s * p.x)
    return Vector((edge.x - s * 0.03, 0.0, z))


def rubber_hose(name, shoulder, hand, wrist_local):
    """A bezier tube from `shoulder` (an empty) to the hand's wrist, hooked to both."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.017
    curve.bevel_resolution = 4
    curve.resolution_u = 16
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    a = shoulder.matrix_world.translation
    b = hand.matrix_world @ Vector(wrist_local)
    s = 1 if b.x > a.x else -1
    p0, p1 = spline.bezier_points
    p0.co, p1.co = a, b
    p0.handle_left_type = p0.handle_right_type = "FREE"
    p1.handle_left_type = p1.handle_right_type = "FREE"
    p0.handle_right = a + Vector((s * 0.07, 0, -0.03))
    p0.handle_left = a - Vector((s * 0.03, 0, -0.01))
    p1.handle_left = b + Vector((-s * 0.01, 0, 0.08))
    p1.handle_right = b - Vector((0, 0, 0.03))
    for target, idx in ((shoulder, [0, 1, 2]), (hand, [3, 4, 5])):
        hook = obj.modifiers.new(f"Hook.{target.name}", "HOOK")
        hook.object = target
        hook.vertex_indices_set(idx)
        hook.matrix_inverse = target.matrix_world.inverted()
    return obj


# ------------------------------------------------------------------------ build


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name in LOOK:
        bpy.data.materials.new(name)
    parts = {}

    profile = head_profile()
    head = lathe("Head", profile, depth=0.92)
    zs = [z for _, z in profile]
    set_origin(head, (0, 0, (min(zs) + max(zs)) / 2))
    head["faceRole"] = "head"
    parts["Head"] = head
    build_face(head, parts)

    hat = inflated("Hat", T["hat_mesh"], HAT_DEPTH)
    hx, hz = P(*T["hat_mesh"]["peak"])
    set_origin(hat, (hx, 0, hz))
    parts["Hat"] = hat
    bm = bmesh.new()
    if LABEL:
        hat_label(bm, LABEL)
        mark = paint("Hat.Label", bm, hat, 0.005)
    else:
        outline_polys(bm, [[P(x, y) for x, y in poly] for poly in T["hat_mark"]])
        mark = paint("Hat.Mark", bm, hat, 0.003)
    parts[mark.name] = mark

    # body, upright: the drop's long axis (tip -> far end) vertical, hovering under the head
    # body: a clean, symmetric drop with the drawing's size (its length tip -> far end, its
    # thickness from the inflation), point up, hovering just under the head
    drawn = [P(x, y) for x, y, _ in T["body_mesh"]["verts"]]
    tip = max(drawn, key=lambda p: p[1])
    far = max(drawn, key=lambda p: math.dist(p, tip))
    length = math.dist(tip, far)
    radius = T["body_mesh"]["max_depth"] / PX
    head_bottom = min(zs)
    body = lathe("Body", egg_profile(length, radius, widest=0.36, bottom_p=2.2, top_a=1.25, top_b=0.9,
                                     z0=head_bottom - 0.05 - length), segments=64)
    set_origin(body, (0, 0, head_bottom - 0.05 - length / 2))
    parts["Body"] = body

    root = bpy.data.objects.new("Avatar", None)
    bpy.context.scene.collection.objects.link(root)
    root["rigStandard"] = "blob"

    for side, s in (("L", -1), ("R", 1)):
        shoulder = bpy.data.objects.new(f"Shoulder.{side}", None)
        bpy.context.scene.collection.objects.link(shoulder)
        shoulder.empty_display_size = 0.03
        shoulder.location = shoulder_point(body, side)
        parent(shoulder, body)
        parts[shoulder.name] = shoulder
        hand = mitten(f"Hand.{side}", side)
        sp = shoulder.location
        hand.location = (sp.x + s * 0.17, -0.05, sp.z - 0.07)
        hand.rotation_euler = (0, math.radians(-s * 45), 0)
        hand["faceRole"] = f"hand.{side}"
        parts[hand.name] = hand
        parts[f"Arm.{side}"] = rubber_hose(f"Arm.{side}", shoulder, hand, (0, 0, 0.05))

    glow = hover_glow()
    parts["Hover.Glow"] = glow

    for name in ("Head", "Body", "Hand.L", "Hand.R", "Arm.L", "Arm.R", "Hover.Glow"):
        parent(parts[name], root)
    for name, obj in parts.items():
        if obj.parent is None and name != "Hat.Mark" and name != "Hat.Label" and not name.startswith("Mouth."):
            parent(obj, head)
    parent(mark, hat)
    for side in ("L", "R"):
        parent(parts[f"Shine.{side}"], parts[f"Look.{side}"])
    for name, obj in parts.items():
        if name.startswith("Mouth."):
            parent(obj, parts["Mouth"])
    return root, parts


def hat_label(bm, text):
    """Text for the beret's front, in the front plane, sized to the drawn mark's box."""
    curve = bpy.data.curves.new("LabelText", "FONT")
    curve.body = text
    curve.align_x, curve.align_y = "CENTER", "CENTER"
    curve.size = 1.0
    tmp = bpy.data.objects.new("LabelText", curve)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    mark = [p for poly in T["hat_mark"] for p in poly]
    x0, y0, x1, y1 = bbox(mark)
    (cx, cz), height = P((x0 + x1) / 2, (y0 + y1) / 2), (y1 - y0) / PX * 0.9
    width_limit = 0.5
    scale = min(height / (max(ys) - min(ys)), width_limit / (max(xs) - min(xs)))
    mx, my = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    tmp_bm = bmesh.new()
    tmp_bm.from_mesh(me)
    for v in tmp_bm.verts:
        v.co = Vector((cx + (v.co.x - mx) * scale, 0.0, cz + (v.co.y - my) * scale))
    # a font triangulates into long slivers whose middles would cut under the curved beret:
    # split every long edge until the text can hug the surface
    bmesh.ops.triangulate(tmp_bm, faces=tmp_bm.faces)
    for _ in range(8):
        long_edges = [e for e in tmp_bm.edges if e.calc_length() > 0.008]
        if not long_edges:
            break
        bmesh.ops.subdivide_edges(tmp_bm, edges=long_edges, cuts=1)
        bmesh.ops.triangulate(tmp_bm, faces=tmp_bm.faces)
    tmp_bm.to_mesh(me)
    tmp_bm.free()
    bm.from_mesh(me)
    bpy.data.objects.remove(tmp)


def hover_glow():
    """A soft disc of light under him (the hover), fading to nothing at its edge."""
    size = 128
    img = bpy.data.images.new("HoverGlow", size, size, alpha=True)
    px = []
    for y in range(size):
        for x in range(size):
            d = math.hypot((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1)
            a = min(1.0, 1.25 * max(0.0, 1 - d) ** 1.8)
            px += [0.62, 0.72, 1.0, a]
    img.pixels = px
    img.filepath_raw = os.path.join(RENDERS, "hover_glow.png")  # packed into the .blend and .glb
    img.file_format = "PNG"
    img.save()
    img.pack()
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.4)
    uv = bm.loops.layers.uv.new()
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = (loop.vert.co.x / 0.8 + 0.5, loop.vert.co.y / 0.8 + 0.5)
    obj = finish("Hover.Glow", bm, smooth=False)
    obj.location = (0, 0, 0.012)
    obj["faceRole"] = "hover"
    return obj


# --------------------------------------------------------------------- materials

LOOK = {  # name: (lit, shade or None for flat), sRGB
    "Skin": ("#ffffff", "#b3b6ff"),
    "Hat": ("#5d69ff", "#3440e0"),
    "Ink": ("#0b0b10", None),
    "HatInk": ("#2a31b8", None),
    "Shine": ("#ffffff", None),
    "Blush": ("#f0303a", None),
    "HatMark": ("#e3f6ff", None),
    "MouthDark": ("#2a0a12", None),
    "Teeth": ("#ffffff", None),
    "Tongue": ("#ff6b7a", None),
}
ASSIGN = {"Head": "Skin", "Body": "Skin", "Hand.L": "Skin", "Hand.R": "Skin", "Arm.L": "Skin",
          "Arm.R": "Skin", "Hat": "Hat", "Hat.Mark": "HatMark", "Hat.Label": "HatMark", "Brow.L": "Ink",
          "Brow.R": "Ink", "Eye.L": "Ink", "Eye.R": "Ink", "Shine.L": "Shine", "Shine.R": "Shine",
          "Cheek.L": "Blush", "Cheek.R": "Blush"}
OUTLINE = {"Head": ("Ink", INK), "Body": ("Ink", INK * 0.8), "Hand.L": ("Ink", INK * 0.5),
           "Hand.R": ("Ink", INK * 0.5), "Arm.L": ("Ink", INK * 0.45), "Arm.R": ("Ink", INK * 0.45),
           "Hat": ("HatInk", INK * 0.3)}


def pbr_fill(m, name):
    lit, shade = LOOK[name]
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Base Color"].default_value = srgb(lit)
    bsdf.inputs["Roughness"].default_value = 0.6 if shade else 0.9
    if name in ("Shine", "HatMark", "Teeth"):
        bsdf.inputs["Emission Color"].default_value = srgb(lit)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    m.use_backface_culling = name in ("Ink", "HatInk")


def toon_fill(m, name):
    lit, shade = LOOK[name]
    m.use_nodes = True
    m.use_backface_culling = name in ("Ink", "HatInk")
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs[0], out.inputs[0])
    if shade is None:
        emit.inputs["Color"].default_value = srgb(lit)
        return
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


def glow_material(toon):
    m = bpy.data.materials.get("HoverGlow") or bpy.data.materials.new("HoverGlow")
    m.use_nodes = True
    m.surface_render_method = "BLENDED"
    m.use_backface_culling = False
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images["HoverGlow"]
    if toon:
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = 2.0
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
        nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
        nt.links.new(clear.outputs[0], mix.inputs[1])
        nt.links.new(emit.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
    else:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    return m


def apply_materials(parts, toon):
    for name in LOOK:
        (toon_fill if toon else pbr_fill)(bpy.data.materials[name], name)
    for name, obj in parts.items():
        if obj.type not in ("MESH", "CURVE"):
            continue
        for mod in [m for m in obj.modifiers if m.type == "SOLIDIFY"]:
            obj.modifiers.remove(mod)
        if name == "Hover.Glow":
            obj.data.materials.clear()
            obj.data.materials.append(glow_material(toon))
            continue
        if name.startswith("Mouth."):
            continue  # per-face materials from the build
        obj.data.materials.clear()
        obj.data.materials.append(bpy.data.materials[ASSIGN[name]])
        if name in OUTLINE:
            ink, thickness = OUTLINE[name]
            obj.data.materials.append(bpy.data.materials[ink])
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
    add.inputs[7].default_value = (0.6, 0.6, 0.75, 1)
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


# ------------------------------------------------------ face states (the rig, in Blender)

REST = {}


def remember(parts):
    for name, obj in parts.items():
        REST[name] = (obj.location.copy(), obj.rotation_euler.copy(), obj.scale.copy())


def reset(parts):
    for name, (loc, rot, scale) in REST.items():
        obj = parts[name]
        obj.location, obj.rotation_euler, obj.scale = loc.copy(), rot.copy(), scale.copy()
        if name.startswith("Mouth."):
            obj.hide_render = name != "Mouth.X"
    bpy.context.view_layer.update()


def face(parts, mouth="X", blink=0.0, brows=0.0, look=(0.0, 0.0), tilt=0.0):
    """What Lowey's FaceRig does, mirrored here so the sheet shows the kit working."""
    for side, s in (("L", -1), ("R", 1)):
        parts[f"Eye.{side}"].scale.z = REST[f"Eye.{side}"][2].z * max(1 - blink * 0.92, 0.06)
        parts[f"Shine.{side}"].scale.z = parts[f"Eye.{side}"].scale.z
        arc = EYE_RX * 0.3 / (parts[f"Eye.{side}"].matrix_world.translation
                              - parts[f"Look.{side}"].matrix_world.translation).length
        parts[f"Look.{side}"].rotation_euler = (-look[1] * arc, 0, look[0] * arc)
        brow = parts[f"Brow.{side}"]
        brow.location = REST[f"Brow.{side}"][0] + Vector((0, 0, brows * 0.035))
        brow.rotation_euler = (0, s * brows * 0.18, 0)
    for name, obj in parts.items():
        if name.startswith("Mouth."):
            obj.hide_render = name != f"Mouth.{mouth}"
    parts["Head"].rotation_euler = (0, math.radians(tilt), 0)
    bpy.context.view_layer.update()


def main():
    root, parts = build()
    remember(parts)

    # 1. The Lowey asset: rest pose, PBR, ink shells and rubber hoses baked, face roles as extras.
    apply_materials(parts, toon=False)
    for name, obj in parts.items():  # the GLB carries every mouth; the rig picks one
        obj.hide_render = False
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "avatar.glb"), export_format="GLB",
                              export_apply=True, export_yup=True, export_extras=True)
    reset(parts)

    # 2. Look-dev.
    apply_materials(parts, toon=True)
    key = world_and_light()
    only = os.environ.get("AVATAR_RENDERS", "all")
    w, h = T["size"]
    cx, cz = P(w / 2, h / 2)
    front = camera("Cam.Front", (cx, -10, cz), (cx, 0, cz), ortho_scale=w / PX)
    render(front, "front_match.png", (1000, 750), transparent=True)
    if only == "all":
        # hero: waving hello, head tilted, happy
        wave = parts["Hand.R"]
        wave.location = (0.5, -0.1, 0.6)
        wave.rotation_euler = (math.radians(-10), math.radians(-160), 0)
        face(parts, mouth="grin", brows=0.6, tilt=-6)
        hero = camera("Cam.Hero", (-2.3, -4.6, 1.6), (0.0, 0, 0.95), lens=62)
        render(hero, "hero.png", (1600, 1200))
        reset(parts)
        low = camera("Cam.Low", (1.7, -3.3, 0.3), (0.0, 0, 0.9), lens=50)
        render(low, "low_angle.png", (1200, 1200))
        for i, deg in enumerate((0, 45, 90, 135, 180)):
            a = math.radians(deg)
            cam = camera(f"Cam.Turn{deg}", (5.5 * math.sin(a), -5.5 * math.cos(a), 1.0), (0, 0, 0.93), lens=65)
            aim_key(key, deg)
            render(cam, f"turn_{i}_{deg}.png", (700, 1000))
        aim_key(key, 0.0)
        # expressions and the mouth set, close on the face
        close = camera("Cam.Face", (0, -3.2, 1.08), (0, 0, 1.08), lens=85)
        states = [
            ("neutral", {}),
            ("talking", {"mouth": "C", "brows": 0.2}),
            ("happy", {"mouth": "grin", "brows": 0.7, "tilt": -5}),
            ("blink", {"blink": 1.0, "mouth": "smile"}),
            ("surprised", {"mouth": "E", "brows": 1.0, "look": (0, 0.6)}),
            ("sad", {"mouth": "frown", "brows": -0.8, "look": (-0.5, -0.6), "tilt": 4}),
            ("side-eye", {"mouth": "A", "brows": -0.3, "look": (1.0, 0)}),
        ]
        for i, (label, kw) in enumerate(states):
            face(parts, **kw)
            render(close, f"face_{i}_{label}.png", (560, 560))
            reset(parts)
        mouth_cam = camera("Cam.Mouth", (0, -3.2, MOUTH_Z + 0.02), (0, 0, MOUTH_Z + 0.02), lens=260)
        for i, shape in enumerate(["X", "A", "B", "C", "D", "E", "F", "G", "H", "smile", "grin", "frown"]):
            face(parts, mouth=shape)
            render(mouth_cam, f"mouth_{i:02d}_{shape}.png", (320, 220))
        reset(parts)
    bpy.context.scene.camera = front
    for name, obj in parts.items():  # viewport: show the rest mouth only (the eye icon, not "disable")
        if name.startswith("Mouth."):
            obj.hide_set(name != "Mouth.X")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "avatar.blend"))


main()
