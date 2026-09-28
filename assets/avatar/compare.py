"""Compare the renders with the drawing and lay out one review sheet.

    python assets/avatar/compare.py <renders_dir> <drawing.png>

Writes <renders_dir>/sheet.jpg:
  row 1  the drawing | the 3D model over the drawing's background | onion skin (model at 55%)
  row 2  hero | low angle
  row 3  turnaround (neutral pose, 0-180 degrees)
"""

import os
import sys

from PIL import Image, ImageDraw

renders, drawing_path = sys.argv[1], sys.argv[2]
W = 3000


def fit(img, width):
    return img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)


drawing = Image.open(drawing_path).convert("RGBA").resize((1000, 750))
model = Image.open(os.path.join(renders, "front_match.png")).convert("RGBA")
on_space = drawing.copy()
on_space.alpha_composite(model)
onion = drawing.copy()
ghost = model.copy()
ghost.putalpha(ghost.getchannel("A").point(lambda a: a * 55 // 100))
onion.alpha_composite(ghost)
row1 = Image.new("RGB", (W, 750))
for i, im in enumerate((drawing, on_space, onion)):
    row1.paste(im.convert("RGB"), (i * 1000, 0))

rows = [row1]
hero, low = (os.path.join(renders, n) for n in ("hero.png", "low_angle.png"))
if os.path.exists(hero) and os.path.exists(low):
    h = Image.open(hero).convert("RGB")
    lo = Image.open(low).convert("RGB")
    height = 1200
    h, lo = h.resize((h.width * height // h.height, height)), lo.resize((lo.width * height // lo.height, height))
    row2 = Image.new("RGB", (h.width + lo.width, height))
    row2.paste(h, (0, 0))
    row2.paste(lo, (h.width, 0))
    rows.append(fit(row2, W))
turns = sorted(f for f in os.listdir(renders) if f.startswith("turn_"))
if turns:
    frames = [Image.open(os.path.join(renders, f)).convert("RGB") for f in turns]
    strip = Image.new("RGB", (sum(f.width for f in frames), frames[0].height))
    x = 0
    for f in frames:
        strip.paste(f, (x, 0))
        x += f.width
    rows.append(fit(strip, W))

sheet = Image.new("RGB", (W, sum(r.height for r in rows) + 12 * (len(rows) - 1)), (12, 8, 20))
y = 0
for r in rows:
    sheet.paste(r, (0, y))
    y += r.height + 12
labels = ImageDraw.Draw(sheet)
for i, text in enumerate(("drawing", "3D model", "overlay (model at 55%)")):
    labels.text((i * 1000 + 20, 16), text, fill=(235, 235, 255))
sheet.save(os.path.join(renders, "sheet.jpg"), quality=88)
