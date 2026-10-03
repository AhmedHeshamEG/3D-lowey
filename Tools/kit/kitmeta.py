"""Semantic metadata for Kit assets: real size, the base centre as the pivot, which way it faces, the surfaces other
things can stand on (a desk's top, a shelf), its rig and clips. This is what lets the app (and the AI) place
"a lamp on the desk" by relation instead of by coordinates.
"""

import math

import numpy as np

import glb

LICENSE = "CC0 1.0 Universal (public domain)"
_reference_cache = {}


def _bounds(points):
    return points.min(axis=0), points.max(axis=0)


def pack_scale(pack_id, curation, cache_folder):
    """Metres per model unit, from the pack's reference asset of known real size."""
    if pack_id in _reference_cache:
        return _reference_cache[pack_id]
    spec = curation["packScale"][pack_id]
    reference = next((a for a in curation["assets"] if a["pack"] == pack_id and a["file"].rsplit("/", 1)[-1].split(".")[0] == spec["reference"]), None)
    path = f"{cache_folder}/{pack_id}/{reference['file']}" if reference else None
    if path is None:
        import os

        for directory, _, files in os.walk(f"{cache_folder}/{pack_id}"):
            for name in files:
                if name.split(".")[0] == spec["reference"] and name.lower().endswith((".glb", ".gltf")):
                    path = os.path.join(directory, name)
                    break
            if path:
                break
    points = glb.world_triangles(glb.load(path)).reshape(-1, 3)
    low, high = _bounds(points)
    size = high - low
    scale = spec["height"] / size[1] if "height" in spec else spec["length"] / max(size[0], size[2])
    _reference_cache[pack_id] = scale
    return scale


def placement(model, scale, rotate_y_degrees):
    """The root transform that puts the base centre at the origin, turns the asset to face +Z and scales it to
    metres, as glTF TRS, plus the same as a 4×4 matrix."""
    points = glb.world_triangles(model).reshape(-1, 3)
    low, high = _bounds(points)
    center = np.array([(low[0] + high[0]) / 2, low[1], (low[2] + high[2]) / 2])
    angle = math.radians(rotate_y_degrees)
    rotation = np.array([[math.cos(angle), 0, math.sin(angle)], [0, 1, 0], [-math.sin(angle), 0, math.cos(angle)]])
    translation = -(scale * (rotation @ center))
    matrix = np.eye(4)
    matrix[:3, :3] = rotation * scale
    matrix[:3, 3] = translation
    quaternion = [0.0, math.sin(angle / 2), 0.0, math.cos(angle / 2)]
    return {"translation": translation.tolist(), "rotation": quaternion, "scale": [scale] * 3}, matrix


def top_surfaces(triangles, size):
    """Upward-facing flat areas above the ground, grouped by height: where things can be put."""
    if len(triangles) == 0:
        return []
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    normals = np.cross(b - a, c - a)
    areas = np.linalg.norm(normals, axis=1) / 2
    with np.errstate(invalid="ignore", divide="ignore"):
        up = normals[:, 1] / np.maximum(np.linalg.norm(normals, axis=1), 1e-12)
    flat = (up > 0.92) & (areas > 1e-6)
    heights = triangles[:, :, 1].mean(axis=1)
    footprint = max(size[0] * size[2], 1e-4)
    groups = {}
    for index in np.nonzero(flat)[0]:
        if heights[index] < 0.05:
            continue
        key = round(heights[index] / 0.02)
        groups.setdefault(key, []).append(index)
    surfaces = []
    for key, members in groups.items():
        area = float(areas[members].sum())
        if area < max(0.004, footprint * 0.04):
            continue
        points = triangles[members].reshape(-1, 3)
        low, high = _bounds(points)
        surfaces.append({"height": round(float(points[:, 1].mean()), 3), "min": [round(float(low[0]), 3), round(float(low[2]), 3)],
                         "max": [round(float(high[0]), 3), round(float(high[2]), 3)], "area": round(area, 4)})
    surfaces.sort(key=lambda surface: -surface["area"])
    return surfaces[:4]


def describe(model, entry, pack, curation, cache_folder):
    """(metadata, root TRS) for one curated asset."""
    scale = pack_scale(pack["id"], curation, cache_folder) * entry.get("scale", 1.0)
    rotate = entry.get("rotateY", curation["packScale"][pack["id"]].get("rotateY", 0))
    trs, matrix = placement(model, scale, rotate)
    triangles = glb.world_triangles(model)
    if len(triangles):
        flat = triangles.reshape(-1, 3)
        placed = (np.c_[flat, np.ones(len(flat))] @ matrix.T)[:, :3].reshape(-1, 3, 3)
    else:
        placed = triangles
    low, high = _bounds(placed.reshape(-1, 3)) if len(placed) else (np.zeros(3), np.zeros(3))
    size = high - low
    meta = {
        "id": entry["id"],
        "name": entry["name"],
        "set": entry["set"],
        "category": entry["category"],
        "tags": entry["tags"],
        "realSizeMeters": [round(float(v), 3) for v in size],
        "groundAnchor": [0.0, 0.0, 0.0],
        "front": [0.0, 0.0, 1.0],
        "topSurfaces": top_surfaces(placed, size) if entry.get("surfaces") else [],
        "triangles": int(len(placed)),
        "author": pack["author"],
        "source": pack["page"],
        "license": LICENSE,
        "file": "model.glb",
    }
    rig = entry.get("rig") or ("skinned" if glb.has_skin(model) else None)
    if rig:
        meta["rig"] = rig
    clips = [animation.get("name", f"Clip {index + 1}") for index, animation in enumerate(model.json.get("animations", []))]
    if clips:
        meta["clips"] = clips
    if entry.get("clipsOnly"):
        meta["clipsOnly"] = True
    return meta, trs


def normalised(model, trs):
    """The model with a root node carrying the placement (base centre at the origin, facing +Z, in metres)."""
    document = model.json
    scene_index = document.get("scene", 0)
    if not document.get("scenes"):
        children = {child for node in document.get("nodes", []) for child in node.get("children", [])}
        document["scenes"] = [{"nodes": [i for i in range(len(document.get("nodes", []))) if i not in children]}]
    scene = document["scenes"][scene_index]
    root = {"name": "Kit", "children": list(scene["nodes"]), **trs}
    document.setdefault("nodes", []).append(root)
    scene["nodes"] = [len(document["nodes"]) - 1]
    document["scene"] = scene_index
    return model
