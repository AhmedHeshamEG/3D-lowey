"""Generates the app icon: python Tools/make_icon.py

Studio rule (STUDIO §10): a simple glyph on the app's accent, full bleed (the system draws the corners, so the three
apps share the same corner geometry). 3D-lowey's glyph is a faceted, ink-outlined cube — the low-poly world, drawn in
the Ink Look. Light: the glyph in ink on the accent. Dark: the glyph in the accent on near-black.
"""
import json
import os

from PIL import Image, ImageDraw

SIZE = 1024
SUPER = 4  # drawn large, scaled down: clean edges
ACCENT = (0xFF, 0xB8, 0x47)
INK = (0x15, 0x13, 0x1C)
NIGHT = (0x12, 0x11, 0x17)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Assets.xcassets", "AppIcon.appiconset")


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def glyph(background, ink, faces):
    """An isometric cube, three faces in three values of the glyph colour, outlined in ink."""
    s = SIZE * SUPER
    image = Image.new("RGB", (s, s), background)
    draw = ImageDraw.Draw(image)
    cx, cy, r = s / 2, s * 0.53, s * 0.30
    top = [(cx, cy - r), (cx + r * 0.866, cy - r / 2), (cx, cy), (cx - r * 0.866, cy - r / 2)]
    left = [(cx - r * 0.866, cy - r / 2), (cx, cy), (cx, cy + r), (cx - r * 0.866, cy + r / 2)]
    right = [(cx, cy), (cx + r * 0.866, cy - r / 2), (cx + r * 0.866, cy + r / 2), (cx, cy + r)]
    for polygon, colour in zip((top, left, right), faces):
        draw.polygon(polygon, fill=colour)
    width = int(s * 0.028)
    outline = [top[0], top[1], right[2], right[3], left[3], left[0]]
    draw.line(outline + [outline[0], outline[1]], fill=ink, width=width, joint="curve")
    for end in (top[1], top[3], right[3]):
        draw.line([top[2], end], fill=ink, width=width)
    # A facet line across the top face: low-poly, not a box.
    draw.line([top[0], top[2]], fill=ink, width=int(width * 0.6))
    for point in [top[2]]:
        radius = width / 2
        draw.ellipse([point[0] - radius, point[1] - radius, point[0] + radius, point[1] + radius], fill=ink)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    light = glyph(ACCENT, INK, (mix(ACCENT, (255, 255, 255), 0.55), mix(ACCENT, INK, 0.18), mix(ACCENT, INK, 0.42)))
    dark = glyph(NIGHT, (0, 0, 0), (mix(ACCENT, (255, 255, 255), 0.35), ACCENT, mix(ACCENT, INK, 0.35)))
    light.save(os.path.join(OUT, "AppIcon-1024.png"))
    dark.save(os.path.join(OUT, "AppIcon-1024-dark.png"))
    contents = {
        "images": [
            {"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-1024-dark.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(contents, handle, indent=2)
        handle.write("\n")
    print("Wrote the light and dark app icons.")


if __name__ == "__main__":
    main()
