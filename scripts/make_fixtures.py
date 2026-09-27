"""Generates the tiny glTF test fixtures in AppTests/Fixtures (run: python scripts/make_fixtures.py).

- box.glb: one coloured low-poly box (static model).
- AnimalPack/*.glb: three differently-shaped "animals" (static) + one rigged quadruped with a walk clip,
  used to prove that a whole pack imports with thumbnails and rig detection.
"""
import json, struct, math, os

def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)

def box(sx, sy, sz, ox=0.0, oy=0.0, oz=0.0):
    hx, hz = sx / 2, sz / 2
    faces = [
        ((0, 0, 1), [(-hx, 0, hz), (hx, 0, hz), (hx, sy, hz), (-hx, sy, hz)]),
        ((0, 0, -1), [(hx, 0, -hz), (-hx, 0, -hz), (-hx, sy, -hz), (hx, sy, -hz)]),
        ((1, 0, 0), [(hx, 0, hz), (hx, 0, -hz), (hx, sy, -hz), (hx, sy, hz)]),
        ((-1, 0, 0), [(-hx, 0, -hz), (-hx, 0, hz), (-hx, sy, hz), (-hx, sy, -hz)]),
        ((0, 1, 0), [(-hx, sy, hz), (hx, sy, hz), (hx, sy, -hz), (-hx, sy, -hz)]),
        ((0, -1, 0), [(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz)]),
    ]
    pos, nor, idx = [], [], []
    for n, quad in faces:
        base = len(pos)
        for p in quad:
            pos.append((p[0] + ox, p[1] + oy, p[2] + oz))
            nor.append(n)
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    return pos, nor, idx

def merge(parts):
    pos, nor, idx = [], [], []
    for p, n, i in parts:
        base = len(pos)
        pos += p; nor += n; idx += [base + k for k in i]
    return pos, nor, idx

def write_glb(path, pos, nor, idx, color, skin=None):
    blob = b""
    views, accessors = [], []
    def add(data, target=None):
        nonlocal blob
        offset = len(blob)
        blob += pad4(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target: view["target"] = target
        views.append(view)
        return len(views) - 1
    pv = add(b"".join(struct.pack("<3f", *p) for p in pos), 34962)
    mins = [min(p[i] for p in pos) for i in range(3)]; maxs = [max(p[i] for p in pos) for i in range(3)]
    accessors.append({"bufferView": pv, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": mins, "max": maxs})
    nv = add(b"".join(struct.pack("<3f", *n) for n in nor), 34962)
    accessors.append({"bufferView": nv, "componentType": 5126, "count": len(nor), "type": "VEC3"})
    iv = add(b"".join(struct.pack("<H", i) for i in idx), 34963)
    accessors.append({"bufferView": iv, "componentType": 5123, "count": len(idx), "type": "SCALAR"})
    attributes = {"POSITION": 0, "NORMAL": 1}
    gltf = {
        "asset": {"version": "2.0", "generator": "3D-lowey fixtures"},
        "scene": 0,
        "materials": [{"pbrMetallicRoughness": {"baseColorFactor": list(color) + [1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8}}],
        "meshes": [{"primitives": [{"attributes": attributes, "indices": 2, "material": 0}]}],
    }
    if skin is None:
        gltf["nodes"] = [{"name": os.path.splitext(os.path.basename(path))[0], "mesh": 0}]
        gltf["scenes"] = [{"nodes": [0]}]
    else:
        joint_names, parents, weights_joint = skin
        jv = add(b"".join(struct.pack("<4B", j, 0, 0, 0) for j in weights_joint), 34962)
        accessors.append({"bufferView": jv, "componentType": 5121, "count": len(pos), "type": "VEC4"})
        wv = add(b"".join(struct.pack("<4f", 1, 0, 0, 0) for _ in pos), 34962)
        accessors.append({"bufferView": wv, "componentType": 5126, "count": len(pos), "type": "VEC4"})
        attributes["JOINTS_0"] = 3; attributes["WEIGHTS_0"] = 4
        ident = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        ibm = add(b"".join(struct.pack("<16f", *ident) for _ in joint_names))
        accessors.append({"bufferView": ibm, "componentType": 5126, "count": len(joint_names), "type": "MAT4"})
        nodes = [{"name": "Body", "mesh": 0, "skin": 0}]
        for n in joint_names:
            nodes.append({"name": n, "children": []})
        for j, parent in enumerate(parents):
            if parent is not None:
                nodes[1 + parent]["children"].append(1 + j)
        roots = [1 + j for j, p in enumerate(parents) if p is None]
        gltf["nodes"] = nodes
        gltf["skins"] = [{"joints": [1 + j for j in range(len(joint_names))], "inverseBindMatrices": 5, "skeleton": roots[0]}]
        gltf["scenes"] = [{"nodes": [0] + roots}]
        # A tiny "Walk" clip: the spine bobs up and down.
        times = [0.0, 0.25, 0.5, 0.75, 1.0]
        tv = add(b"".join(struct.pack("<f", t) for t in times))
        accessors.append({"bufferView": tv, "componentType": 5126, "count": len(times), "type": "SCALAR", "min": [0.0], "max": [1.0]})
        vals = [(0, 0.5 + 0.05 * math.sin(t * 2 * math.pi), 0) for t in times]
        vv = add(b"".join(struct.pack("<3f", *v) for v in vals))
        accessors.append({"bufferView": vv, "componentType": 5126, "count": len(vals), "type": "VEC3"})
        gltf["animations"] = [{"name": "Walk", "samplers": [{"input": 6, "output": 7, "interpolation": "LINEAR"}],
                               "channels": [{"sampler": 0, "target": {"node": 2, "path": "translation"}}]}]
    gltf["bufferViews"] = views
    gltf["accessors"] = accessors
    gltf["buffers"] = [{"byteLength": len(blob)}]
    js = pad4(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\x00")); f.write(blob)

root = os.path.join(os.path.dirname(__file__), "..", "AppTests", "Fixtures")
write_glb(os.path.join(root, "box.glb"), *box(1, 1, 1), (0.9, 0.55, 0.2))
pack = os.path.join(root, "AnimalPack")
# Blocky "animals" (body + head + legs) in different proportions and colours.
def animal(body, head, leg, color, name):
    parts = [box(*body, 0, leg, 0), box(*head, 0, leg + body[1] * 0.6, body[2] / 2 + head[2] / 2)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(box(0.12, leg, 0.12, sx * (body[0] / 2 - 0.08), 0, sz * (body[2] / 2 - 0.08)))
    write_glb(os.path.join(pack, name), *merge(parts), color)
animal((0.5, 0.35, 0.9), (0.3, 0.3, 0.3), 0.35, (0.95, 0.6, 0.2), "Fox.glb")
animal((0.7, 0.5, 1.3), (0.35, 0.4, 0.4), 0.7, (0.55, 0.4, 0.3), "Horse.glb")
animal((0.4, 0.3, 0.5), (0.3, 0.3, 0.25), 0.15, (0.95, 0.95, 0.9), "Chicken.glb")
pos, nor, idx = merge([box(0.6, 0.45, 1.2, 0, 0.5, 0), box(0.35, 0.35, 0.35, 0, 0.8, 0.7)])
write_glb(os.path.join(pack, "Tiger_Rigged.glb"), pos, nor, idx, (0.95, 0.55, 0.15),
          skin=(["Root", "Spine", "Neck", "Head", "FrontLeg_L", "FrontLeg_R", "BackLeg_L", "BackLeg_R", "Tail"],
                [None, 0, 1, 2, 1, 1, 0, 0, 0], [1] * len(pos)))
print("fixtures written")
