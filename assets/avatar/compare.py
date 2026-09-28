"""Lay out the review sheet from the renders.

    python assets/avatar/compare.py <renders_dir> <drawing.png>

Writes <renders_dir>/sheet.jpg:
  row 1  the drawing | the model, front | hero (waving, happy)
  row 2  turnaround (0-180 degrees)
  row 3  expressions (the face rig: blink, brows, look, mouths, head tilt)
  row 4  the mouth set (lip-sync shapes A-H, X = rest, plus smile, grin, frown)
"""

import os
import sys

from PIL import Image, ImageDraw

renders, drawing_path = sys.argv[1], sys.argv[2]
W, GAP = 3000, 12
BG = (12, 8, 20)


def row(images, height):
    images = [im.convert("RGB").resize((round(im.width * height / im.height), height), Image.LANCZOS)
              for im in images]
    out = Image.new("RGB", (sum(im.width for im in images) + GAP * (len(images) - 1), height), BG)
    x = 0
    for im in images:
        out.paste(im, (x, 0))
        x += im.width + GAP
    return out.resize((W, round(out.height * W / out.width)), Image.LANCZOS)


def files(prefix):
    return sorted(f for f in os.listdir(renders) if f.startswith(prefix) and f.endswith(".png"))


def label(img, texts):
    d = ImageDraw.Draw(img)
    step = img.width / len(texts)
    for i, t in enumerate(texts):
        d.text((i * step + 10, 8), t, fill=(235, 235, 255))
    return img


drawing = Image.open(drawing_path).convert("RGBA").resize((1000, 750))
front = Image.new("RGBA", drawing.size, (22, 12, 36, 255))
front.alpha_composite(Image.open(os.path.join(renders, "front_match.png")).convert("RGBA"))
rows = [label(row([drawing, front, Image.open(os.path.join(renders, "hero.png"))], 750),
              ["drawing", "model", "hero"])]
if files("turn_"):
    rows.append(row([Image.open(os.path.join(renders, f)) for f in files("turn_")], 1000))
if files("face_"):
    names = [f.split("_", 2)[2][:-4] for f in files("face_")]
    rows.append(label(row([Image.open(os.path.join(renders, f)) for f in files("face_")], 560), names))
if files("mouth_"):
    names = [f.split("_", 2)[2][:-4] for f in files("mouth_")]
    rows.append(label(row([Image.open(os.path.join(renders, f)) for f in files("mouth_")], 220), names))

sheet = Image.new("RGB", (W, sum(r.height for r in rows) + GAP * (len(rows) - 1)), BG)
y = 0
for r in rows:
    sheet.paste(r, (0, y))
    y += r.height + GAP
sheet.save(os.path.join(renders, "sheet.jpg"), quality=88)
