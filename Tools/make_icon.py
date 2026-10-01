"""Generates the app icon (a low-poly night island with a glowing cabin): python Tools/make_icon.py"""
import json, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Resources", "Assets.xcassets", "AppIcon.appiconset")
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
top, horizon = (12, 16, 40), (62, 54, 110)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (horizon[i] - top[i]) * t) for i in range(3)))
random.seed(1941)
for _ in range(120):
    x, y, r = random.randrange(S), random.randrange(int(S * 0.55)), random.choice([1, 1, 2, 2, 3])
    b = random.randint(150, 255)
    d.ellipse([x - r, y - r, x + r, y + r], fill=(b, b, min(255, b + 15)))

cx, cy = S / 2, S * 0.64
def iso(x, y, z):
    return (cx + (x - z) * 0.866 * 210, cy + (x + z) * 0.5 * 210 - y * 210)

d.polygon([iso(-1, 0, 1), iso(1, 0, 1), iso(1, -0.55, 1), iso(-1, -0.55, 1)], fill=(58, 74, 60))
d.polygon([iso(1, 0, -1), iso(1, 0, 1), iso(1, -0.55, 1), iso(1, -0.55, -1)], fill=(44, 56, 50))
d.polygon([iso(-1, 0, -1), iso(1, 0, -1), iso(1, 0, 1), iso(-1, 0, 1)], fill=(96, 140, 86))

def tree(x, z, h, col):
    b, t, w = iso(x, 0, z), iso(x, h, z), 0.28 * 210
    d.polygon([(b[0] - w, b[1] - h * 40), (b[0], t[1]), (b[0], b[1] - h * 10)], fill=col)
    d.polygon([(b[0] + w, b[1] - h * 40), (b[0], t[1]), (b[0], b[1] - h * 10)], fill=tuple(int(c * 0.75) for c in col))

tree(-0.55, -0.35, 1.25, (70, 120, 80))
tree(-0.1, -0.7, 1.0, (60, 110, 72))
tree(-0.75, 0.45, 0.8, (66, 116, 76))

bx, bz, h = 0.25, -0.1, 0.45
d.polygon([iso(bx - 0.3, 0, bz + 0.25), iso(bx + 0.3, 0, bz + 0.25), iso(bx + 0.3, h, bz + 0.25), iso(bx - 0.3, h, bz + 0.25)], fill=(150, 92, 64))
d.polygon([iso(bx + 0.3, 0, bz + 0.25), iso(bx + 0.3, 0, bz - 0.25), iso(bx + 0.3, h, bz - 0.25), iso(bx + 0.3, h, bz + 0.25)], fill=(112, 68, 48))
d.polygon([iso(bx - 0.35, h, bz + 0.3), iso(bx + 0.35, h, bz + 0.3), iso(bx + 0.35, h + 0.3, bz), iso(bx - 0.35, h + 0.3, bz)], fill=(200, 80, 60))
d.polygon([iso(bx + 0.35, h, bz + 0.3), iso(bx + 0.35, h, bz - 0.3), iso(bx + 0.35, h + 0.3, bz)], fill=(150, 58, 44))

glow = Image.new("RGB", (S, S))
g = ImageDraw.Draw(glow)
w = iso(bx, 0.2, bz + 0.25)
g.ellipse([w[0] - 90, w[1] - 90, w[0] + 90, w[1] + 90], fill=(255, 170, 70))
glow = glow.filter(ImageFilter.GaussianBlur(45))
img = Image.fromarray(np.clip(np.asarray(img, dtype="int32") + np.asarray(glow, dtype="int32") * 0.55, 0, 255).astype("uint8"))
d = ImageDraw.Draw(img)
d.polygon([iso(bx - 0.08, 0.12, bz + 0.25), iso(bx + 0.08, 0.12, bz + 0.25), iso(bx + 0.08, 0.3, bz + 0.25), iso(bx - 0.08, 0.3, bz + 0.25)], fill=(255, 200, 110))
img.save(os.path.join(OUT, "AppIcon-1024.png"))
json.dump({"images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(OUT, "Contents.json"), "w"), indent=2)
print("icon written")
