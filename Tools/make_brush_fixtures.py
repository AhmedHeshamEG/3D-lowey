#!/usr/bin/env python3
"""Brush import fixtures, made from scratch in the real files' formats (no one else's brushes in the repository).

    python Tools/make_brush_fixtures.py

Writes Packages/LoweyCore/Tests/LoweyCoreTests/Fixtures/Brushes/:
  Sample.brushset  Procreate: brushset.plist + two brush folders (Brush.archive keyed archives, a Shape.png and a
                   Grain.png of our own, and one tip that points at a Procreate bundled picture by name)
  Sample.abr       Photoshop 6.2: an 8BIMsamp section with one raw and one PackBits tip, an 8BIMdesc naming them

The layouts follow real files inspected for the M5 spike (DECISIONS D-141); the settings are ours.
"""
from __future__ import annotations

import io
import math
import pathlib
import plistlib
import random
import struct
import zipfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Packages" / "LoweyCore" / "Tests" / "LoweyCoreTests" / "Fixtures" / "Brushes"


def grey_png(width: int, height: int, value) -> bytes:
    raw = b"".join(b"\0" + bytes(int(max(0, min(1, value(x / width, y / height))) * 255) for x in range(width)) for y in range(height))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def leaf_tip(x: float, y: float) -> float:
    """A leaf: pointed ellipse with a vein, clearly not round (the golden image shows it)."""
    dx, dy = (x - 0.5) / 0.22, (y - 0.5) / 0.46
    inside = 1 - (dx * dx + dy * dy)
    vein = 0.55 if abs(x - 0.5) < 0.012 else 1
    return max(0.0, min(1.0, inside * 6)) * vein


def speckle(seed: int):
    rng = random.Random(seed)
    cells = [[rng.random() for _ in range(32)] for _ in range(32)]
    return lambda x, y: 0.3 + 0.7 * cells[int(y * 32) % 32][int(x * 32) % 32]


class Archive:
    """An NSKeyedArchiver archive: `$objects` with `$null` first, values pointing at objects by UID."""

    def __init__(self) -> None:
        self.objects: list = ["$null"]

    def add(self, value) -> plistlib.UID:
        self.objects.append(value)
        return plistlib.UID(len(self.objects) - 1)

    def klass(self, name: str, *parents: str) -> plistlib.UID:
        return self.add({"$classname": name, "$classes": [name, *parents, "NSObject"]})

    def curve(self, points: list[tuple[float, float]]) -> plistlib.UID:
        refs = [self.add("{%f, %f}" % p) for p in points]
        array = self.add({"NS.objects": refs, "$class": self.klass("NSArray")})
        return self.add({"points": array, "$class": self.klass("ValkyrieMagnitudinalCurve")})

    def data(self, settings: dict) -> bytes:
        root = {}
        for key, value in settings.items():
            if isinstance(value, str):
                root[key] = self.add(value)
            elif isinstance(value, list):
                root[key] = self.curve(value)
            else:
                root[key] = value
        root["$class"] = self.klass("SilicaBrush", "ValkyrieBrush")
        self.objects.insert(1, root)
        # Inserting the root at 1 shifts every UID after it.
        shifted = [self._shift(o) for o in self.objects]
        archive = {"$archiver": "NSKeyedArchiver", "$version": 100000, "$top": {"root": plistlib.UID(1)}, "$objects": shifted}
        return plistlib.dumps(archive, fmt=plistlib.FMT_BINARY)

    def _shift(self, value):
        if isinstance(value, plistlib.UID):
            return plistlib.UID(value.data + 1 if value.data >= 1 else value.data)
        if isinstance(value, dict):
            return {k: self._shift(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self._shift(v) for v in value]
        return value


def brush_archive(settings: dict) -> bytes:
    base = {
        "version": 2, "plotSpacing": 0.1, "plotSmoothing": 0.3, "plotJitter": 0.0, "shapeRoundness": 1.0, "shapeRotation": 0.0,
        "shapeScatter": 0.0, "shapeCount": 0.0, "oriented": True, "shapeInverted": False, "textureScale": 0.5, "textureMovement": 0.0,
        "grainDepth": 1.0, "textureInverted": False, "dynamicsPressureSize": 0.6, "dynamicsPressureOpacity": 0.0, "dynamicsTiltSize": 0.0,
        "dynamicsTiltOpacity": 0.0, "dynamicsSpeedSize": 0.0, "dynamicsSpeedOpacity": 0.0, "dynamicsJitterSize": 0.0,
        "dynamicsJitterOpacity": 0.0, "dynamicsFalloff": 0.0, "dynamicsGlazedFlow": 1.0, "wetEdgesAmount": 0.0,
        "pencilTaperStartLength": 0.0, "pencilTaperEndLength": 0.0, "pencilTaperSize": 0.0, "pencilTaperOpacity": 0.0,
        "bundledShapePath": "$null", "bundledGrainPath": "$null", "authorName": "studio h.",
        "dynamicsPressureSizeCurve": [(0.0, 0.0), (1.0, 1.0)],
    }
    base.update(settings)
    return Archive().data(base)


def brushset() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("brushset.plist", plistlib.dumps({"name": "Sample Set", "brushes": ["LEAF-0001", "PEN-0002"]},
                                                          fmt=plistlib.FMT_BINARY))
        archive.writestr("LEAF-0001/Brush.archive", brush_archive({
            "name": "Leaf Stamp", "plotSpacing": 0.6, "shapeScatter": 0.5, "oriented": True, "textureMovement": 1.0,
            "textureScale": 0.4, "grainDepth": 0.6, "dynamicsPressureSize": 0.4, "dynamicsJitterSize": 0.2,
            "dynamicsPressureSizeCurve": [(0.0, 0.0), (0.4, 0.7), (1.0, 1.0)],
        }))
        archive.writestr("LEAF-0001/Shape.png", grey_png(96, 96, leaf_tip))
        archive.writestr("LEAF-0001/Grain.png", grey_png(64, 64, speckle(3)))
        archive.writestr("PEN-0002/Brush.archive", brush_archive({
            "name": "Hard Pen", "bundledShapePath": "Brush-Preset-Hard.png", "plotSpacing": 0.0, "plotSmoothing": 0.5,
            "dynamicsPressureSize": 0.9, "pencilTaperStartLength": 0.5, "pencilTaperEndLength": 0.5, "pencilTaperSize": 1.0,
        }))
    return buffer.getvalue()


def packbits(row: bytes) -> bytes:
    out = bytearray()
    index = 0
    while index < len(row):
        run = 1
        while index + run < len(row) and run < 128 and row[index + run] == row[index]:
            run += 1
        if run > 1:
            out += struct.pack("b", 1 - run) + row[index:index + 1]
            index += run
        else:
            literal = bytearray()
            while index < len(row) and len(literal) < 128 and (index + 1 >= len(row) or row[index + 1] != row[index]):
                literal.append(row[index])
                index += 1
            out += struct.pack("b", len(literal) - 1) + literal
    return bytes(out)


def abr_sample(uuid: str, width: int, height: int, value, compressed: bool) -> bytes:
    pixels = [bytes(int(max(0, min(1, value(x / width, y / height))) * 255) for x in range(width)) for y in range(height)]
    if compressed:
        rows = [packbits(row) for row in pixels]
        bitmap = b"".join(struct.pack(">H", len(r)) for r in rows) + b"".join(rows)
    else:
        bitmap = b"".join(pixels)
    body = bytes([len(uuid)]) + uuid.encode() + bytes(264)
    body += struct.pack(">IIIIHB", 0, 0, height, width, 8, 1 if compressed else 0) + bitmap
    padding = (4 - len(body) % 4) % 4
    return struct.pack(">I", len(body)) + body + bytes(padding)


def unicode(text: str) -> bytes:
    encoded = (text + "\0").encode("utf-16-be")
    return struct.pack(">I", len(encoded) // 2) + encoded


def abr() -> bytes:
    samples = [
        ("0f4a1c00-0000-4000-8000-000000000001", 48, 48, lambda x, y: 1 - min(1, ((x - .5) ** 2 + (y - .5) ** 2) ** .5 * 2.2), False),
        ("0f4a1c00-0000-4000-8000-000000000002", 80, 40, lambda x, y: 1.0 if (int(x * 8) + int(y * 4)) % 2 == 0 else 0.0, True),
    ]
    samp = b"".join(abr_sample(*s) for s in samples)
    desc = bytearray(bytes(22))
    for (uuid, *_), (name, spacing) in zip(samples, [("$$$/Presets/Brushes/Dot=Soft Dot", 15.0), ("Checker Stamp", 80.0)]):
        desc += b"Nm  TEXT" + unicode(name)
        desc += b"SpcnUntF#Prc" + struct.pack(">d", spacing)
        desc += b"sampledDataTEXT" + unicode(uuid)

    def section(key: bytes, body: bytes) -> bytes:
        return b"8BIM" + key + struct.pack(">I", len(body)) + body + bytes((4 - len(body) % 4) % 4)

    return struct.pack(">HH", 6, 2) + section(b"samp", samp) + section(b"desc", bytes(desc))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Sample.brushset").write_bytes(brushset())
    (OUT / "Sample.abr").write_bytes(abr())
    print("wrote", OUT)


if __name__ == "__main__":
    main()
