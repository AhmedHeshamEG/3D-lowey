"""Minimal glTF 2.0 reading and GLB writing for the Kit (no dependencies beyond numpy).

load(path) reads .glb or .gltf (external .bin and image files, or data URIs) into one model: the JSON plus a single
binary buffer (images moved into it), so save(model) can write a self-contained .glb.
"""

import base64
import io
import json
import os
import struct

import numpy as np

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
TYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


class Model:
    def __init__(self, document, binary):
        self.json = document
        self.bin = bytearray(binary)


def _read_uri(uri, folder):
    if uri.startswith("data:"):
        return base64.b64decode(uri.split(",", 1)[1])
    with open(os.path.join(folder, uri.replace("%20", " ")), "rb") as handle:
        return handle.read()


def _pad(data, fill=b"\x00"):
    return data + fill * ((4 - len(data) % 4) % 4)


def load(path):
    with open(path, "rb") as handle:
        raw = handle.read()
    folder = os.path.dirname(path)
    if raw[:4] == b"glTF":
        length = struct.unpack_from("<I", raw, 8)[0]
        offset = 12
        document, binary = None, b""
        while offset < length:
            chunk_length, chunk_type = struct.unpack_from("<II", raw, offset)
            chunk = raw[offset + 8 : offset + 8 + chunk_length]
            if chunk_type == 0x4E4F534A:
                document = json.loads(chunk.decode("utf-8"))
            elif chunk_type == 0x004E4942:
                binary = chunk
            offset += 8 + chunk_length
        model = Model(document, binary)
        buffers = document.get("buffers", [])
        if len(buffers) > 1 or (buffers and "uri" in buffers[0]):
            _merge_buffers(model, folder, embedded=binary)
    else:
        model = Model(json.loads(raw.decode("utf-8")), b"")
        _merge_buffers(model, folder, embedded=b"")
    _embed_images(model, folder)
    return model


def _merge_buffers(model, folder, embedded):
    """Every buffer into one: bufferViews are re-based onto the merged binary."""
    document = model.json
    starts = []
    merged = bytearray()
    for index, buffer in enumerate(document.get("buffers", [])):
        data = _read_uri(buffer["uri"], folder) if "uri" in buffer else (embedded if index == 0 else b"")
        merged = bytearray(_pad(bytes(merged)))
        starts.append(len(merged))
        merged += data
    for view in document.get("bufferViews", []):
        view["byteOffset"] = view.get("byteOffset", 0) + starts[view.get("buffer", 0)]
        view["buffer"] = 0
    document["buffers"] = [{"byteLength": len(merged)}]
    model.bin = merged


def _embed_images(model, folder):
    document = model.json
    for image in document.get("images", []):
        if "uri" not in image:
            continue
        uri = image.pop("uri")
        try:
            data = _read_uri(uri, folder)
        except FileNotFoundError:
            # A pack that references a file it doesn't ship (a normal map, usually): the toon pass drops it.
            image["missing"] = uri
            continue
        mime = "image/png" if data[:4] == b"\x89PNG" else "image/jpeg"
        model.bin = bytearray(_pad(bytes(model.bin)))
        document.setdefault("bufferViews", []).append({"buffer": 0, "byteOffset": len(model.bin), "byteLength": len(data)})
        model.bin += data
        image["bufferView"] = len(document["bufferViews"]) - 1
        image["mimeType"] = mime
    if document.get("buffers"):
        document["buffers"][0]["byteLength"] = len(model.bin)


def save(model):
    document = dict(model.json)
    binary = _pad(bytes(model.bin))
    document["buffers"] = [{"byteLength": len(binary)}] if binary else []
    text = _pad(json.dumps(document, separators=(",", ":")).encode("utf-8"), b" ")
    chunks = struct.pack("<II", len(text), 0x4E4F534A) + text
    if binary:
        chunks += struct.pack("<II", len(binary), 0x004E4942) + binary
    return struct.pack("<III", 0x46546C67, 2, 12 + len(chunks)) + chunks


def accessor(model, index):
    """An accessor's data as a float array (count × components)."""
    spec = model.json["accessors"][index]
    count = spec["count"]
    width = COMPONENTS[spec["type"]]
    dtype = np.dtype(TYPES[spec["componentType"]])
    if "bufferView" not in spec:
        return np.zeros((count, width), dtype=np.float64)
    view = model.json["bufferViews"][spec["bufferView"]]
    start = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * width)
    rows = np.zeros((count, width), dtype=np.float64)
    data = bytes(model.bin)
    if stride == dtype.itemsize * width:
        flat = np.frombuffer(data, dtype=dtype, count=count * width, offset=start)
        rows[:] = flat.reshape(count, width)
    else:
        for row in range(count):
            rows[row] = np.frombuffer(data, dtype=dtype, count=width, offset=start + row * stride)
    if spec.get("normalized") and dtype.kind in "iu":
        rows /= np.iinfo(dtype).max
    return rows


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    t = np.array(node.get("translation", [0, 0, 0]), dtype=np.float64)
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = np.array(node.get("scale", [1, 1, 1]), dtype=np.float64)
    rotation = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    matrix = np.eye(4)
    matrix[:3, :3] = rotation * s
    matrix[:3, 3] = t
    return matrix


def world_triangles(model):
    """Every triangle of the default scene in world space: (n, 3, 3) positions."""
    document = model.json
    scene = document.get("scenes", [{}])[document.get("scene", 0)] if document.get("scenes") else {"nodes": list(range(len(document.get("nodes", []))))}
    triangles = []

    def visit(index, parent):
        node = document["nodes"][index]
        matrix = parent @ node_matrix(node)
        if "mesh" in node:
            for primitive in document["meshes"][node["mesh"]]["primitives"]:
                if primitive.get("mode", 4) != 4 or "POSITION" not in primitive["attributes"]:
                    continue
                positions = accessor(model, primitive["attributes"]["POSITION"])[:, :3]
                if "indices" in primitive:
                    indices = accessor(model, primitive["indices"])[:, 0].astype(np.int64)
                else:
                    indices = np.arange(len(positions))
                world = (np.c_[positions, np.ones(len(positions))] @ matrix.T)[:, :3]
                count = len(indices) // 3 * 3
                triangles.append(world[indices[:count]].reshape(-1, 3, 3))
        for child in node.get("children", []):
            visit(child, matrix)

    for root in scene.get("nodes", []):
        visit(root, np.eye(4))
    return np.concatenate(triangles) if triangles else np.zeros((0, 3, 3))


def has_skin(model):
    return bool(model.json.get("skins"))


def wrap_scene(model, matrix):
    """Puts the scene's root nodes under one new root node carrying `matrix` (column-major in glTF)."""
    document = model.json
    scene_index = document.get("scene", 0)
    scene = document["scenes"][scene_index]
    root = {"name": "Kit", "children": list(scene["nodes"]), "matrix": [float(v) for v in np.asarray(matrix).T.reshape(-1)]}
    document["nodes"].append(root)
    scene["nodes"] = [len(document["nodes"]) - 1]
    document["scene"] = scene_index
    return model


def toon_ready(model, max_texture=512):
    """Keeps what the toon Looks use: base colour (maps shrunk to `max_texture`), emissive colour, alpha. Normal,
    occlusion, metal/roughness and emissive maps go; the buffer is rebuilt with only what's still referenced."""
    from PIL import Image  # Pillow: only the Kit build needs it

    document = model.json
    for material in document.get("materials", []):
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            material.pop(key, None)
        material.get("pbrMetallicRoughness", {}).pop("metallicRoughnessTexture", None)
        if not material.get("extensions", {}).get("KHR_materials_emissive_strength"):
            material.pop("extensions", None)
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        texture = document["textures"][pbr["baseColorTexture"]["index"]] if "baseColorTexture" in pbr else None
        if texture is not None and "missing" in document["images"][texture.get("source", 0)]:
            pbr.pop("baseColorTexture")
    used_textures = sorted({material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
                            for material in document.get("materials", [])
                            if "baseColorTexture" in material.get("pbrMetallicRoughness", {})})
    texture_map = {old: new for new, old in enumerate(used_textures)}
    textures = [document["textures"][old] for old in used_textures]
    for material in document.get("materials", []):
        base = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if base is not None:
            base["index"] = texture_map[base["index"]]
    used_images = sorted({texture["source"] for texture in textures if "source" in texture})
    image_map = {old: new for new, old in enumerate(used_images)}
    images = []
    for old in used_images:
        image = document["images"][old]
        view = document["bufferViews"][image["bufferView"]]
        data = bytes(model.bin[view.get("byteOffset", 0) : view.get("byteOffset", 0) + view["byteLength"]])
        picture = Image.open(io.BytesIO(data))
        if max(picture.size) > max_texture:
            ratio = max_texture / max(picture.size)
            picture = picture.resize((max(1, round(picture.size[0] * ratio)), max(1, round(picture.size[1] * ratio))), Image.LANCZOS)
        out = io.BytesIO()
        if picture.mode in ("RGBA", "LA", "P") and picture.convert("RGBA").getextrema()[3][0] < 255:
            picture.convert("RGBA").save(out, "PNG", optimize=True)
            mime = "image/png"
        else:
            picture.convert("RGB").save(out, "JPEG", quality=88)
            mime = "image/jpeg"
        images.append((image, out.getvalue(), mime))
    for texture in textures:
        if "source" in texture:
            texture["source"] = image_map[texture["source"]]
    used_samplers = sorted({texture["sampler"] for texture in textures if "sampler" in texture})
    sampler_map = {old: new for new, old in enumerate(used_samplers)}
    for texture in textures:
        if "sampler" in texture:
            texture["sampler"] = sampler_map[texture["sampler"]]
    if "samplers" in document:
        document["samplers"] = [document["samplers"][old] for old in used_samplers]
    document["textures"] = textures
    # Rebuild the binary: only bufferViews accessors (and animations/skins through them) still use, then the images.
    used_views = sorted({accessor["bufferView"] for accessor in document.get("accessors", []) if "bufferView" in accessor})
    view_map = {}
    binary = bytearray()
    views = []
    for old in used_views:
        view = dict(document["bufferViews"][old])
        start = view.get("byteOffset", 0)
        chunk = bytes(model.bin[start : start + view["byteLength"]])
        binary = bytearray(_pad(bytes(binary)))
        view["byteOffset"] = len(binary)
        view["buffer"] = 0
        binary += chunk
        view_map[old] = len(views)
        views.append(view)
    for accessor in document.get("accessors", []):
        if "bufferView" in accessor:
            accessor["bufferView"] = view_map[accessor["bufferView"]]
    new_images = []
    for image, data, mime in images:
        binary = bytearray(_pad(bytes(binary)))
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary += data
        entry = {key: value for key, value in image.items() if key not in ("bufferView", "mimeType", "uri")}
        entry.update({"bufferView": len(views) - 1, "mimeType": mime})
        new_images.append(entry)
    document["bufferViews"] = views
    if new_images:
        document["images"] = new_images
    else:
        document.pop("images", None)
        document.pop("textures", None)
        document.pop("samplers", None)
    model.bin = binary
    document["buffers"] = [{"byteLength": len(binary)}]
    return model
