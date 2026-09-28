"""Trace Hesham's drawing into numbers the Blender build uses (drawing -> trace.json).

    python assets/avatar/trace_drawing.py assets/avatar/drawing.png assets/avatar/trace.json [debug_dir]

What it measures, all in drawing pixels (build_avatar.py converts to units):
  head      row-by-row silhouette -> the lathe profile (left/right averaged)
  face      every mark painted on the head: ink (brows, eyes, mouth), shines, blush,
            as smooth outer contours (holes are the shines, traced separately)
  hat_mark  the light strokes on the beret
  body      silhouette contour (for pose fitting) + principal axis
  hands     fitted ellipses
"""

import json
import os
import sys

import cv2
import numpy as np
from scipy import sparse
from scipy.ndimage import map_coordinates
from scipy.sparse.linalg import spsolve

src, out = sys.argv[1], sys.argv[2]
debug = sys.argv[3] if len(sys.argv) > 3 else None

img = cv2.imread(src, cv2.IMREAD_COLOR)
h, w = img.shape[:2]
b, g, r = [img[..., i].astype(int) for i in range(3)]
lum = (0.299 * r + 0.587 * g + 0.114 * b)
sat = img.max(axis=2).astype(int) - img.min(axis=2).astype(int)

# white-ish skin (includes the lavender shading on the head's lower right)
skin = ((lum > 175) & (sat < 110) & (b > 200)).astype(np.uint8)
n, labels, stats, cents = cv2.connectedComponentsWithStats(skin, 8)
order = np.argsort(-stats[:, cv2.CC_STAT_AREA])
comps = [i for i in order if i != 0][:4]


def filled(mask):
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    out_m = np.zeros_like(mask)
    cv2.drawContours(out_m, cnts, -1, 1, -1)
    return out_m


head_id, body_id = comps[0], comps[1]
hand_ids = sorted(comps[2:4], key=lambda i: cents[i][0])
head_skin = (labels == head_id).astype(np.uint8)
# close the ink outline around the head so the hull includes it
head_full = filled(cv2.morphologyEx(head_skin, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8)))

# --- head profile: per row, the outer edge of the black ink line counts as the silhouette
ink = (lum < 70).astype(np.uint8)
head_with_ink = filled(cv2.morphologyEx(head_full | cv2.dilate(head_full, np.ones((3, 3))) & 0 | head_full,
                                        cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
grown = cv2.dilate(head_full, np.ones((17, 17), np.uint8))
silhouette = filled(((grown & ink) | head_full).astype(np.uint8))
ys = np.nonzero(silhouette.any(axis=1))[0]
rows = []
for y in range(ys.min(), ys.max() + 1):
    xs = np.nonzero(silhouette[y])[0]
    if len(xs):
        rows.append([int(y), float(xs.min()), float(xs.max() + 1)])

skin_rows = []
for y in range(ys.min(), ys.max() + 1):
    xs = np.nonzero(head_full[y])[0]
    if len(xs):
        skin_rows.append([int(y), float(xs.min()), float(xs.max() + 1)])
sil = {row[0]: row for row in rows}
mid = [(sil[y][2] - sil[y][1] - (rr - ll)) / 2 for y, ll, rr in skin_rows
       if y in sil and 0.3 < (y - ys.min()) / (ys.max() - ys.min()) < 0.8]
ink_px = float(np.median(mid))

# --- face marks inside the head (not the outline ring)
inner = cv2.erode(head_full, np.ones((25, 25), np.uint8))
red = ((r > 150) & (g < 90) & (b < 110) & (inner > 0)).astype(np.uint8)
reddish = cv2.dilate(((r > 90) & (r > g + 50)).astype(np.uint8), np.ones((5, 5), np.uint8))
dark = ((lum < 110) & (inner > 0) & (reddish == 0)).astype(np.uint8)


def contours(mask, min_area=20, smooth=1.2, holes=False):
    blur = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), smooth)
    m = (blur > 0.5).astype(np.uint8)
    mode = cv2.RETR_CCOMP if holes else cv2.RETR_EXTERNAL
    cnts, hier = cv2.findContours(m, mode, cv2.CHAIN_APPROX_NONE)
    outs, hole_list = [], []
    for i, c in enumerate(cnts):
        if cv2.contourArea(c) < min_area:
            continue
        c = cv2.approxPolyDP(c, 0.6, True)[:, 0, :]
        pts = [[float(x), float(y)] for x, y in c]
        if holes and hier[0][i][3] != -1:
            hole_list.append(pts)
        else:
            outs.append(pts)
    return outs, hole_list


def upsample(mask, k=4):
    """Contour at 4x for smooth sub-pixel outlines, then scale back."""
    big = cv2.resize(mask.astype(np.float32), (mask.shape[1] * k, mask.shape[0] * k),
                     interpolation=cv2.INTER_LINEAR)
    return big


def smooth_contours(mask, min_area=20, holes=False, k=4):
    big = cv2.GaussianBlur(upsample(mask, k), (0, 0), 1.6 * k / 2)
    m = (big > 0.5).astype(np.uint8)
    mode = cv2.RETR_CCOMP if holes else cv2.RETR_EXTERNAL
    cnts, hier = cv2.findContours(m, mode, cv2.CHAIN_APPROX_NONE)
    outs, hole_list = [], []
    for i, c in enumerate(cnts):
        if cv2.contourArea(c) < min_area * k * k:
            continue
        c = cv2.approxPolyDP(c, 0.8 * k / 2, True)[:, 0, :]
        pts = [[(float(x) + 0.5) / k - 0.5, (float(y) + 0.5) / k - 0.5] for x, y in c]
        if holes and hier[0][i][3] != -1:
            hole_list.append(pts)
        else:
            outs.append(pts)
    return outs, hole_list


ink_parts, shine_parts = smooth_contours(dark, holes=True)
blush_parts, _ = smooth_contours(red)


def centroid(pts):
    a = np.array(pts)
    return float(a[:, 0].mean()), float(a[:, 1].mean())


HEAD_TOP, HEAD_BOTTOM = rows[0][0], rows[-1][0]
AXIS = float(np.median([(l + rr) / 2 for y, l, rr in rows if y > HEAD_TOP + 0.3 * (HEAD_BOTTOM - HEAD_TOP)]))


def name_ink(pts):
    cx, cy = centroid(pts)
    a = np.array(pts)
    width = a[:, 0].max() - a[:, 0].min()
    height = a[:, 1].max() - a[:, 1].min()
    side = "L" if cx < AXIS else "R"
    rel = (cy - HEAD_TOP) / (HEAD_BOTTOM - HEAD_TOP)
    if rel > 0.55:
        return "Mouth"
    if rel > 0.3:
        return f"Eye.{side}"
    return f"Brow.{side}"


face = {}
for pts in ink_parts:
    face.setdefault(name_ink(pts), []).append(pts)
face["Shine.L"] = [p for p in shine_parts if centroid(p)[0] < AXIS]
face["Shine.R"] = [p for p in shine_parts if centroid(p)[0] >= AXIS]
for pts in blush_parts:
    face.setdefault("Cheek.L" if centroid(pts)[0] < AXIS else "Cheek.R", []).append(pts)

# --- hat: blue region, and the pale mark on it
blue = ((b > 180) & (b - r > 60) & (b - g > 40)).astype(np.uint8)
nb, lb, sb, cb = cv2.connectedComponentsWithStats(blue, 8)
hat_id = 1 + int(np.argmax(sb[1:, cv2.CC_STAT_AREA]))
hat = filled((lb == hat_id).astype(np.uint8))
hx, hy, hw, hh = [int(v) for v in sb[hat_id, :4]]
hat_inner = cv2.erode(hat, np.ones((5, 5), np.uint8))
pale = ((lum > 190) & (hat_inner > 0) & (b > 200)).astype(np.uint8)
mark, _ = smooth_contours(pale, min_area=6)
# keep the symbol; drop the soft glow painted along the beret's lower edge
mark = [m_ for m_ in mark if max(pt[1] for pt in m_) < hy + hh - 20]
hat_outline, _ = smooth_contours(hat)

# --- body + hands
body_mask = (labels == body_id).astype(np.uint8)
body_outline, _ = smooth_contours(body_mask)
m = cv2.moments(body_mask)
bcx, bcy = m["m10"] / m["m00"], m["m01"] / m["m00"]
mu20, mu02, mu11 = m["mu20"] / m["m00"], m["mu02"] / m["m00"], m["mu11"] / m["m00"]
theta = 0.5 * np.arctan2(2 * mu11, mu20 - mu02)  # major axis angle from +x (image coords)
def body_fit(mask):
    """Tilt (deg, tip to the right = +) that makes the drop most mirror-symmetric."""
    cy_, cx_ = [float(v.mean()) for v in np.nonzero(mask)]
    size = (mask.shape[1], mask.shape[0])
    best = None
    for a in np.arange(-80, 80.01, 0.5):
        rot = cv2.warpAffine(mask, cv2.getRotationMatrix2D((cx_, cy_), float(a), 1.0), size,
                             flags=cv2.INTER_NEAREST)
        rys = np.nonzero(rot.any(axis=1))[0]
        centres = []
        for y in rys:
            xs = np.nonzero(rot[y])[0]
            centres.append((xs.min() + xs.max() + 1) / 2)
        score = float(np.mean(np.abs(np.array(centres) - np.median(centres))))
        if best is None or score < best[0]:
            best = (score, float(a))
    a = best[1]
    M = cv2.getRotationMatrix2D((cx_, cy_), a, 1.0)
    rot = cv2.warpAffine(mask.astype(np.float32), M, size, flags=cv2.INTER_LINEAR)
    rot = (rot > 0.5).astype(np.uint8)
    rys = np.nonzero(rot.any(axis=1))[0]
    prof, centres = [], []
    for y in rys:
        xs = np.nonzero(rot[y])[0]
        prof.append([float(rys.max() + 1 - y), float((xs.max() + 1 - xs.min()) / 2)])
        centres.append((xs.min() + xs.max() + 1) / 2)
    axis_x = float(np.median(centres))
    mid_y = (rys.min() + rys.max() + 1) / 2
    Minv = cv2.invertAffineTransform(M)
    mid_pt = Minv @ np.array([axis_x, mid_y, 1.0])
    length = float(rys.max() + 1 - rys.min())
    return {"tilt_deg": a, "profile": prof[::-1], "mid": [float(mid_pt[0]), float(mid_pt[1])],
            "length": length, "symmetry_px": best[0]}


body_axis = body_fit(body_mask)


def inflate(mask, spacing=6.0):
    """Monster-Mash-style inflation: solve lap(h) = -4 inside the outline (h = 0 on it),
    depth = sqrt(h). A disc of radius R inflates to an exact sphere. Returns a closed
    mesh in drawing pixels: verts [x, y, depth], front depth > 0 faces the viewer."""
    ys_, xs_ = np.nonzero(mask)
    index = -np.ones(mask.shape, np.int64)
    index[ys_, xs_] = np.arange(len(xs_))
    rows_, cols_, vals_ = [], [], []
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        ny, nx = ys_ + dy, xs_ + dx
        ok = index[ny.clip(0, mask.shape[0] - 1), nx.clip(0, mask.shape[1] - 1)]
        inside = ok >= 0
        rows_.append(np.arange(len(xs_))[inside])
        cols_.append(ok[inside])
        vals_.append(np.ones(inside.sum()))
    rows_.append(np.arange(len(xs_)))
    cols_.append(np.arange(len(xs_)))
    vals_.append(-4 * np.ones(len(xs_)))
    A = sparse.csr_matrix((np.concatenate(vals_), (np.concatenate(rows_), np.concatenate(cols_))),
                          shape=(len(xs_), len(xs_)))
    h = np.zeros(mask.shape)
    h[ys_, xs_] = spsolve(A, -4 * np.ones(len(xs_)))

    from scipy.ndimage import gaussian_filter

    hs = gaussian_filter(h, 1.0)
    outlines, _ = smooth_contours(mask)
    ring = np.array(max(outlines, key=len))
    closed = np.vstack([ring, ring[:1]])
    cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(closed, axis=0), axis=1))])
    n_around = int(np.clip(cum[-1] / (2 * spacing), 64, 112))
    t = np.linspace(0, cum[-1], n_around, endpoint=False)
    boundary = np.stack([np.interp(t, cum, closed[:, 0]), np.interp(t, cum, closed[:, 1])], 1)
    pk = np.unravel_index(np.argmax(hs), hs.shape)
    peak = np.array([float(pk[1]), float(pk[0])])

    # UV-sphere topology: rings from the peak (s = 0) out to the outline (s = 1),
    # denser towards the rim. Interior depth is the Poisson depth sqrt(h); past
    # s = RIM it hands over to a circular fall-off so the rim is exact and noise-free.
    RIM, K = 0.8, 16
    s_vals = [np.sin(0.5 * np.pi * k / K) for k in range(1, K)]  # excludes pole and rim

    def depth_at(p):
        return float(np.sqrt(max(map_coordinates(hs, [[p[1]], [p[0]]], order=1)[0], 0.0)))

    verts = [[float(x), float(y), 0.0] for x, y in boundary]  # shared rim ring
    rings = {}
    for side in (1, -1):
        rows_ = []
        for sv in s_vals:
            row = []
            for bpt in boundary:
                p = peak + (bpt - peak) * sv
                if sv <= RIM:
                    z = depth_at(p)
                else:
                    z = depth_at(peak + (bpt - peak) * RIM) * np.sqrt((1 - sv * sv) / (1 - RIM * RIM))
                row.append(len(verts))
                verts.append([float(p[0]), float(p[1]), side * z])
            rows_.append(row)
        pole = len(verts)
        verts.append([float(peak[0]), float(peak[1]), side * float(np.sqrt(hs.max()))])
        rings[side] = (rows_, pole)
    rim = list(range(n_around))
    faces = []
    for side in (1, -1):
        rows_, pole = rings[side]
        chain = [rim] + rows_[::-1]  # rim -> ... -> innermost ring
        for a_, b_ in zip(chain, chain[1:]):
            for i in range(n_around):
                j = (i + 1) % n_around
                quad = [a_[i], a_[j], b_[j], b_[i]]
                faces.append(quad if side == 1 else quad[::-1])
        inner = chain[-1]
        for i in range(n_around):
            j = (i + 1) % n_around
            tri_ = [inner[i], inner[j], pole]
            faces.append(tri_ if side == 1 else tri_[::-1])
    return {"verts": verts, "faces": faces, "peak": [float(peak[0]), float(peak[1])],
            "max_depth": float(np.sqrt(hs.max()))}


body_mesh = inflate(body_mask, spacing=7.0)
hat_mesh = inflate(hat, spacing=6.0)

hands = []
for i in hand_ids:
    cnts, _ = cv2.findContours((labels == i).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    (ex, ey), (ea, eb), eang = cv2.fitEllipse(max(cnts, key=cv2.contourArea))
    hands.append({"center": [ex, ey], "axes": [ea, eb], "angle": eang})

data = {
    "size": [w, h],
    "axis_x": AXIS,
    "head_rows": rows,
    "head_skin_rows": skin_rows,
    "ink_px": ink_px,
    "face": face,
    "hat_bbox": [hx, hy, hw, hh],
    "hat_outline": hat_outline,
    "hat_mark": mark,
    "body": {"centroid": [bcx, bcy], "axis_angle_deg": float(np.degrees(theta)),
             "outline": body_outline, "bbox": [int(v) for v in stats[body_id, :4]], **body_axis},
    "hands": hands,
    "body_mesh": body_mesh,
    "hat_mesh": hat_mesh,
}
with open(out, "w") as f:
    json.dump(data, f)

summary = {k: [len(v), [round(c) for c in centroid(v[0])]] for k, v in face.items() if v}
print("face parts:", summary)
print("hat bbox", data["hat_bbox"], "mark strokes", len(mark))
print("body", data["body"]["bbox"], "centroid", [round(bcx), round(bcy)], "axis", round(np.degrees(theta), 1))
print("hands", [[round(v) for v in hd["center"]] + [round(a) for a in hd["axes"]] + [round(hd["angle"])] for hd in hands])
print("ink px", round(ink_px, 1), "body tilt", body_axis["tilt_deg"], "len", body_axis["length"],
      "mid", [round(v) for v in body_axis["mid"]], "sym", round(body_axis["symmetry_px"], 2))
print("head rows", rows[0][0], "->", rows[-1][0], "axis", round(AXIS, 1))

if debug:
    os.makedirs(debug, exist_ok=True)
    vis = img.copy() // 3
    vis[silhouette > 0] = (90, 90, 90)
    for name, polys in face.items():
        color = (0, 0, 255) if "Cheek" in name else (255, 255, 255) if "Shine" in name else (0, 255, 255)
        for p in polys:
            cv2.polylines(vis, [np.array(p, np.int32)], True, color, 1)
            cx, cy = centroid(p)
            cv2.putText(vis, name, (int(cx) - 30, int(cy) - 40), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 1)
    for p in mark + hat_outline + body_outline:
        cv2.polylines(vis, [np.array(p, np.int32)], True, (255, 160, 60), 1)
    for hd in hands:
        cv2.ellipse(vis, ((hd["center"][0], hd["center"][1]), tuple(hd["axes"]), hd["angle"]), (0, 255, 0), 1)
    x0, x1 = int(min(rw[1] for rw in rows)) - 60, int(max(rw[2] for rw in rows)) + 60
    cv2.imwrite(os.path.join(debug, "trace_debug.png"), vis[HEAD_TOP - 200 : HEAD_BOTTOM + 420, x0:x1])
