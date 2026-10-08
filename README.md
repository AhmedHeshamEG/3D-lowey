# Maquette

Shapr3D's ease, Procreate's feel, Dreams' animation and ToonSquid's rigging, in 3D, for people without an engineering
or art degree. Build a set like Lego, drop in characters, direct them with a camera, sync them to your voice, and
export the video. By **studio h.**; the continuation of 3D-lowey 2.0. All rights reserved (see [LICENSE](LICENSE)).

**0.10** (phase M10): **live performance**. Your face, your voice and your hands drive any character live: Blobs,
Puppets, drawn rigs (3D and 2D), person rigs and rigged models. The microphone gives the mouth its shape; characters
breathe and blink on their own; loose bones (hair, ears, tails) dangle; triggers put a character in an expression or a
pose or swap what it holds, by a tap or a key; a hand dragged while recording is performed. Every recording is kept as
a take, and the comp is chosen by dragging across the one you want.

**0.9** (phase M9): **the Schizzo board**. Every project has an endless 2D board for planning (Actions ▸ Board):
sketch with the whole brush engine, drop pictures, write notes, draw arrows, frame what belongs together. Pin a frame
or a pick to the project and it floats over the stage as a reference card; stand it in the scene and it's a plane like
any other object. The board is written as you draw and comes back with its undo. Sketch is a starter template that
opens on it. The brush engine and the board live in hmm-kit now, so Cutaway gets the same ones.

**0.8** (phase M8): **fixes and touch**. Touch and hold anything (an object on the stage, a key, a clip, a layer, a
brush, a card) and the same menu opens in the same order. Pencil or hand is automatic: a finger draws until an Apple
Pencil has touched. Tap a thing, tap Spin, Float, Bounce, Wiggle, Swing or Follow a path, and it moves, no timeline
needed. A colour well sits on the sidebar while you draw. Rigging is three steps (Bones, Skin, Pose), and a drawn bone
runs through the middle of the part, bends where the stroke bends and shows as you draw it. Under load nothing is said
on the stage any more: the preview lightens by itself.

**0.7** (phase M7): **rigging**. Draw a bone through a limb, a tail or a rope with the Pencil and the model bends
there: shapes, modelled parts, drawings and placed models, with the weights worked out by bone heat (or painted by
hand). Rig a human-like model as a person with eight taps and every built-in clip plays on it. Drag any character's
joints to pose it (IK), keep its poses, and export or print it as posed. Blobs, Puppets, imported rigs and drawn rigs
share one skeleton system.

**0.6** (phase M6): **painting on models**. Paint ▸ Colour paints straight onto shapes, modelled parts and placed
models with the brush engine: paint, erase, fill and the eyedropper, layers with opacity and blend modes, and pictures
projected from the camera. Strokes land only where the camera sees the model, every stroke is one undo step, and the
paint follows the shape if you model it afterwards. glTF, USDZ, OBJ and the Blender package carry the paint as a texture.

**0.5** (phase M5): **brushes and drawing guides**. One brush engine draws ink and flipbooks: ten brushes, Brush
Studio with a pad to try every setting, your own pictures as tips and grains, Procreate (`.brushset`, `.brush`) and
Photoshop (`.abr`) brushes imported, sets shared as files. Strokes keep the brush they were drawn with. Drawing guides:
a 2D grid, isometric, 1-, 2- and 3-point perspective and symmetry for flipbooks, a grid, isometric or symmetry on the
guide plane for ink, with Drawing Assist.

**0.4** (phase M4): **modelling II and interop**. Bevel and round edges, inset faces, hollow solids into shells,
mirror and model with live symmetry, array along a sketch; snap to corners, edge middles, edges and faces, measure and
keep dimensions, cut the stage open with a section view; check a part for 3D printing, repair it and export STL or
3MF that stand on the bed; draw walls, floors, doors, windows and stairs. Export glTF (hierarchy, materials,
animation), USDZ, OBJ, STL, 3MF, or a Blender package that rebuilds the scene for rendering on a computer; import STL
and 3MF, and take placed models apart to edit them.

**0.3** (phase M3): **modelling**. Model ▸ Edit sketches on any surface (lines, rectangles, circles, arcs, splines,
offsets), pulls closed shapes into solids or cuts them into the face below, picks faces, edges and corners, pushes and
pulls faces with the distance floating beside them, and combines solids with union, subtract and intersect. Every
number on the stage takes an exact length (`25`, `2*12`, `1ft 6in`) in the project's units.

**0.2** (phase M2): **the canvas owns the screen**. The making tools are Model, Draw, Paint, Animate and Cast; the
timeline comes when called; the inspector floats beside what's selected; every panel resizes. **Home** is a living
gallery where each project's model turns in its own Look, grows into the stage when tapped, and can be stacked,
searched and sorted. New projects start from a template (print, room, character, animation, blank).

**0.1** (phase M1): **nothing is ever lost** (every change is recorded the moment it happens, undo survives closing
the app, Actions ▸ History scrubs back through every step); the Pencil's hover point sits exactly under the tip; every
iPad gets a preview tuned to it; a hidden load meter watches the frames (silent since 0.8).

**From 2.0.** A Metal renderer and five Looks (Ink, Comic, Sketch, Clay, Low-poly), a layout without modes, ink strokes
and flipbooks, a Kit of about 350 real-size models, one Cast for every kind of character, and Claude as a director's
assistant that can see what it builds. In English, Italian and Arabic.

- What it is and where it's going: [docs/SPEC.md](docs/SPEC.md)
- What happened to each 1.x feature: [docs/MIGRATION.md](docs/MIGRATION.md)
- How it's built: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · why: [docs/DECISIONS.md](docs/DECISIONS.md)
- The project file format: [docs/PROJECT_FORMAT.md](docs/PROJECT_FORMAT.md)
- Known limits and what's next: [docs/BACKLOG.md](docs/BACKLOG.md) · changes: [CHANGELOG.md](CHANGELOG.md)
- The App Store listing, privacy and TestFlight: [docs/APPSTORE.md](docs/APPSTORE.md)

---

## Install on an iPad (no Mac needed)

Every green build of `main` produces an installable `Maquette.ipa`; tagged versions are attached to a GitHub Release.

1. **Get the .ipa**: *Releases* → the newest version → `Maquette.ipa`, or *Actions* → **Release** → the newest green
   run → *Artifacts* → `Maquette-<version>-<build>` (a zip with `Maquette.ipa` inside).
2. **Install [Sideloadly](https://sideloadly.io)** on a computer (Windows is fine) and connect the iPad with a cable.
3. Drag `Maquette.ipa` into Sideloadly, pick the iPad, sign in with a **free Apple ID**, press **Start**.
4. On the iPad: **Settings → General → VPN & Device Management** → your Apple ID → **Trust**. If asked, turn on
   **Settings → Privacy & Security → Developer Mode** and restart.
5. Open **Maquette**. The first launch adds the samples: the **Welcome island** (with a 60-second tour) and **Enigma**
   (a desk in Ink, a room of computers in Comic, a cave robot in Sketch, and the narrated story).

A free Apple ID signature lasts **7 days**; after that, connect the iPad and press **Start** in Sideloadly again.
Projects are kept: they live under *Files → On My iPad → Maquette*. Maquette installs next to 3D-lowey (it has its
own bundle id, so it starts with its own empty folder): bring 3D-lowey projects over by sharing them from 3D-lowey
(*Share as one file*, `.loweypack`) or picking their `.lowey` folders in Files; they open in Maquette and stay
readable by 3D-lowey 2.0.

**iPhone face companion**: install the same `.ipa` on an iPhone with Face ID. On a phone the app is only the companion:
it tracks your face and streams it to the iPad on the same Wi-Fi.

---

## Find your way around

The **stage** fills the screen. Everything else floats in two corners and a thin sidebar, and comes when called. Every
control's home is in [docs/LAYOUT.md](docs/LAYOUT.md).

| Where | What's there |
|---|---|
| Top left | **Home** (your projects) · **Actions** (export, the project file, the Monitor, scenes, history, scripts, the AI & laptop bridge, gestures, tour, diagnostics, settings) · **Look** (Looks, mood, palette, finish) · **Select** (tap, lasso, select similar, the outliner) |
| Top right | **Model** (shapes, lights and cameras, 3D text, titles, photos and videos, effects; sketch, push/pull and booleans; the Kit and your models; snapping and units) · **Draw** (ink strokes and flipbooks with brushes and drawing guides, solid shapes on guides) · **Paint** (Shadow Brush, Scatter) · **Animate** (opens the timeline) · **Cast** (Blob, Puppet, Rigged; clips, poses, faces, lip sync) |
| Side | two sliders for what you're doing, **Pick**, undo, redo |
| Beside the selection | the **inspector**: move, turn, size; numbers; Look override; motion; its menu has array, group, swap for a model, save to the library |
| Bottom right | the **timeline** control (call the transport, send it away), views, frame the selection, the Director view |
| Bottom, when called | the timeline: **Compose** (move animation in time), **Perform** (record by touch), **Keyframe** (keys, easing, auto-key), sound and words |

| Gesture | Does |
|---|---|
| One finger / two fingers / pinch | orbit / pan / zoom |
| Double-tap | frame the selection |
| Two fingers on the selection | twist and pinch it |
| Two-finger tap / three-finger tap | undo / redo |
| Four-finger tap | hide everything but the stage |
| Pencil | draws; hover previews; Pencil Pro squeeze plays and pauses; roll during Perform |

Keyboard: ⌘1–5 Model, Draw, Paint, Animate, Cast · ⌘6–8 Actions, Look, Select · ⌘L library · ⌘T timeline ·
⌥⌘1–3 move, turn, size · Space play · ⌘K key · ⌘M marker · ⌥⌘D Director view ·
⌥⌘Y fly the camera · ⇧⌘R record a performance · ⌥⌘R record voiceover · ⇧⌘T transcript · ⇧⌘U audio · ⌘E export ·
⇧⌘B bridge · ⌥⌘V paste a Scene Script · ⌥⌘N monitor window · ⌘Z / ⇧⌘Z.

In Stage Manager or with an external display, **Actions ▸ Monitor** opens the shot in its own window, live, as it
will export.

### A first shot

1. Home → **New project**: a name and a template (a mood and a Look are suggested; change them if you like).
2. **Model ▸ Library**: place models from the Kit (they arrive at real size); draw with **Draw ▸ Ink**; **Cast** → add a Blob.
3. **Look** → try the five Looks; **Finish** for grain, bloom, outlines.
4. Select something → the inspector's **Motion** → a preset (Pop in, Bounce…), or **Animate ▸ Perform** and move it while it plays.
5. **Model** → camera, then **Director view** (⌥⌘D) to aim it; the inspector's Camera for moves and focus.
6. **Animate** → **Sound and words** to record a voiceover, then **Transcribe**; attach things to spoken words from the transcript.
7. **Actions** → **Export** → a preset (YouTube 4K, Shorts, GIF loop…).

---

## Claude and the laptop

The bridge is **off** until you turn it on, answers only on your local network, and lets in only laptops you pair.

```powershell
pip install "git+https://github.com/AhmedHeshamEG/3D-lowey#subdirectory=Tools/lowey"
# On the iPad: Actions ▸ AI & laptop ▸ turn the bridge on ▸ Pair a laptop (shows a one-time code)
hmm-bridge pair 123456
claude mcp add lowey -- hmm-bridge mcp
```

The `lowey` MCP server has sixteen tools: Claude reads the project, finds Kit models, builds with Scene Script v3
(relations, not coordinates), frames shots, lights them with recipes, animates by intent — and **looks** at the result
(`observe`: the shot with numbered marks, top/front/side diagrams, a value view and a measured report graded against
a critique rubric; `contact_sheet` for motion). Its changes arrive on the iPad as a proposal with a preview: **Apply**
(one undo step) or **Not now**. Any AI can also write a Scene Script
([`schemas/scene-script.v3.schema.json`](schemas/scene-script.v3.schema.json)) to paste with ⌥⌘V. See
[`Tools/lowey/README.md`](Tools/lowey/README.md). The Claude skill — the director loop, its modules and its evals —
is in [`skills/lowey`](skills/lowey). App Store builds ship without the bridge (2.1).

---

## Development

Nothing needs a Mac: GitHub Actions builds, tests and packages everything.

```
Packages/LoweyCore      pure Swift: model, commands, timeline, geometry, modelling, characters, glTF, Scene Scripts, samples
Packages/Manifold       Manifold (Apache-2.0) vendored for booleans, behind a small C face
Packages/LoweyEngine    LoweyRender 2 (Metal), stage view, import, export, overlays, audio, face, scripting, benchmark
Packages/LoweyFeatures  the SwiftUI editor (Workspace shared, one folder per feature, Shell composes them)
Packages/HmmKit         hmm-kit (git subtree): design system, commands, documents, bridge, diagnostics, media…
App/                    the app target, the export Live Activity widget
App/Resources/Kit       the Kit: CC0 models with real sizes, surfaces and fronts (built by Tools/fetch-kit.py)
AppUITests/             UI smoke tests, the right-to-left test and the App Store screenshots
Tools/                  hmm-bridge (the laptop CLI and MCP server), the Kit fetcher, generators for the schema, the
                        skill's tool reference, Blob measurements, strings and the icon; CI helpers
skills/lowey            the Claude skill (and its evals)
```

- The Xcode project is generated from [`project.yml`](project.yml) with XcodeGen; it's never committed.
- Core tests run anywhere Swift runs, Docker on Windows included:
  `docker run --rm -v "$PWD/Packages:/work" -w /work/LoweyCore swift:6.1 swift test`
- **CI** ([`ci.yml`](.github/workflows/ci.yml)): SwiftLint `--strict` and SwiftFormat → LoweyCore tests on Linux with
  an 80 % coverage gate; the laptop tools' tests and generated-file checks (Kit, Blob measurements, the v3 schema,
  the skill's tool reference, the String Catalog); LoweyEngine's render tests (golden images for every Look, the
  samples observed against the rubric) and LoweyFeatures' tests on an iPad simulator; the feature-boundary check →
  the app build, UI tests (English, Italian, Arabic) and App Store screenshots.
- **Release** ([`release.yml`](.github/workflows/release.yml)): only from commits CI passed; an unsigned device build,
  ad-hoc signed into `Lowey.ipa`; tags `v*` publish a GitHub Release and, when the App Store Connect secrets exist,
  upload the App Store build to TestFlight.
- hmm-kit changes are made in hmm-kit first, then pulled in with `Tools/sync-hmmkit.sh`.
- The app's display name and version live in [`Config/Branding.xcconfig`](Config/Branding.xcconfig).

## License

Private project by Hesham. Third-party software: [LICENSES.md](LICENSES.md).
