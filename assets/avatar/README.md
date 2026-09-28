# The avatar

Hesham's character in 3D. His drawing (`drawing.png`) gives the identity: the onion head, the
floating drop body, the beret with the Pisces mark, the blush, the smirk. The build turns that
into a character that animates: a face kit, rubber-hose arms, mitten hands and a hover glow.

| File | What it is |
|---|---|
| `drawing.png` | the original drawing (2732×2048, iPad) |
| `trace_drawing.py` | measures the drawing → `trace.json` |
| `trace.json` | head silhouette, every face mark as a contour, the beret (inflated), body and hand sizes |
| `build_avatar.py` | Blender build → `avatar.glb`, `avatar.blend`, renders |
| `avatar.glb` | the Lowey asset: rest pose, PBR, ink outlines, every mouth, face roles as glTF extras (~69k triangles) |
| `avatar.blend` | look-dev: toon shading, live rubber-hose arms (move a hand, the arm follows) |
| `compare.py` | lays out `renders/sheet.jpg` |
| `renders/sheet.jpg` | drawing vs model, hero, turnaround, expressions, the mouth set |
| `renders/label_example.jpg` | the beret carrying a name instead of the mark |

## The parts and what drives them

Every part the face rig moves carries a `faceRole` (exported as glTF extras); the root carries
`rigStandard: "blob"`.

| Part | Role | Rig |
|---|---|---|
| `Head` | `head` | turns (yaw, pitch, roll) |
| `Eye.L/R` | `eye.L/R` | blink = squash (origin at the eye's centre) |
| `Look.L/R` → `Shine.L/R` | `pupil.L/R`, `lookPivot` | looking = **turning** the shines about the centre of the sphere that best fits the head around that eye, so they glide over the surface instead of sinking into it |
| `Brow.L/R` | `brow.L/R` | raise and tilt |
| `Mouth` → `Mouth.*` | `mouth`, `mouth.A`…`H`, `mouth.X`, `mouth.smile/grin/frown` | one shape visible at a time; A–H, X are the Rhubarb lip-sync set (X, rest, is his smirk) |
| `Hand.L/R` | `hand.L/R` | the arm follows the hand (rubber hose) |
| `Hover.Glow` | `hover` | the soft light under him: no legs, he floats |

## How it is made

- **Head**: a surface of revolution of the traced silhouette (left and right averaged), 0.92 as
  deep as it is wide, with a cap that tucks under the beret.
- **Face**: placed where the drawing has it and then mirrored, so expressions read cleanly. Eyes
  are clean ovals with two shines; brows are thick arcs with the drawing's hopeful slope. The
  rest mouth is his traced smirk and curl. Everything is painted onto the head from the front,
  one object per part.
- **Body**: a symmetric drop with the drawing's length and thickness, point up, hovering.
- **Arms**: bezier tubes hooked to a shoulder (on the body) and the wrist (on the hand). The GLB
  has them baked in the rest pose; the app rebuilds them from the hand's position.
- **Beret**: inflated from the drawing's outline (∇²h = −4 inside, depth = √h, on a
  UV-sphere-style grid with a circular rim). `AVATAR_LABEL="NEWTON"` swaps the mark for text,
  the identity clue for other characters.
- **Ink**: an inverted hull (a back-face-culled shell), as thick as the drawing's line.

Units: 683 drawing pixels = 1; the beret tops out at about 1.8 units.

## Rebuild

```sh
python assets/avatar/trace_drawing.py assets/avatar/drawing.png assets/avatar/trace.json
blender -b --factory-startup -P assets/avatar/build_avatar.py
python assets/avatar/compare.py assets/avatar/renders assets/avatar/drawing.png
```

Needs Python with OpenCV, SciPy and Pillow, and Blender 5.2 (EEVEE).
