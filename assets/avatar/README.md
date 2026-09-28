# The avatar

Hesham's character, built in 3D from his own drawing (`drawing.png`). The drawing is the source
of truth: nothing here is eyeballed, it is measured.

| File | What it is |
|---|---|
| `drawing.png` | the original drawing (2732×2048, iPad) |
| `trace_drawing.py` | measures the drawing → `trace.json` |
| `trace.json` | head silhouette, every face mark as a contour, inflated body and beret meshes, hands |
| `build_avatar.py` | Blender build → `avatar.glb`, `avatar.blend`, renders |
| `avatar.glb` | the Lowey asset: neutral pose, plain PBR, ink outlines included (~62k triangles, half of them the ink shells) |
| `avatar.blend` | the look-dev file: toon shading, the drawing's pose, cameras |
| `compare.py` | lays out `renders/sheet.jpg` (drawing vs model, overlay, hero, turnaround) |

## How it is made

- **Head**: a surface of revolution of the traced silhouette (left and right averaged), slightly
  shallower front-to-back than wide (0.92), with a cap that tucks under the beret.
- **Face**: every stroke of the drawing (brows, eyes, shines, mouth with its curl, cheeks) is
  traced as a smooth contour, filled, and painted onto the head from the front. Each part is
  its own object (`Eye.L`, `Brow.R`, `Mouth`, …) parented to `Head`, so the face can animate.
- **Body and beret**: not round, so they are *inflated* from their outlines (the Monster Mash
  technique): solve ∇²h = −4 inside the outline, depth = √h. A disc inflates to an exact
  sphere. The mesh is a UV-sphere grid from the inflation peak out to the outline, with a
  circular fall-off at the rim so the edge is clean.
- **Hands**: ellipsoids fitted to the drawn ovals. No arms, no legs: he floats.
- **Ink**: an inverted hull (a back-face-culled black shell), the same thickness as the
  drawing's line.

Hierarchy: `Avatar` → `Head` (face parts, `Hat` → `Hat.Mark`), `Body`, `Hand.L`, `Hand.R`. Units:
683 drawing pixels = 1; his beret tops out at about 1.8 units.

## Rebuild

```sh
python assets/avatar/trace_drawing.py assets/avatar/drawing.png assets/avatar/trace.json
blender -b --factory-startup -P assets/avatar/build_avatar.py
python assets/avatar/compare.py assets/avatar/renders assets/avatar/drawing.png
```

Needs Python with OpenCV, SciPy and Pillow, and Blender 5.2 (EEVEE).
