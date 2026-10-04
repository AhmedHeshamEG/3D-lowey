# 3D-lowey

An iPad app for making short animated videos that look drawn: build a set like Lego, drop in characters, direct
them with a camera, sync them to your voice, and export the video. Think Procreate Dreams, in 3D, cel-shaded.

**2.0.** A Metal renderer and five Looks (Ink, Comic, Sketch, Clay, Low-poly), a layout without modes, ink strokes
and flipbooks, a Kit of about 350 real-size models, one Cast for every kind of character, and Claude as a director's
assistant that can see what it builds. In English, Italian and Arabic.

- What it is and where it's going: [docs/SPEC.md](docs/SPEC.md)
- What happened to each 1.x feature: [docs/MIGRATION.md](docs/MIGRATION.md)
- How it's built: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · why: [docs/DECISIONS.md](docs/DECISIONS.md)
- Known limits and what's next: [docs/BACKLOG.md](docs/BACKLOG.md) · changes: [CHANGELOG.md](CHANGELOG.md)
- The App Store listing, privacy and TestFlight: [docs/APPSTORE.md](docs/APPSTORE.md)

---

## Install on an iPad (no Mac needed)

Every green build of `main` produces an installable `Lowey.ipa`; tagged versions are attached to a GitHub Release.

1. **Get the .ipa**: *Releases* → the newest version → `Lowey.ipa`, or *Actions* → **Release** → the newest green
   run → *Artifacts* → `Lowey-<version>-<build>` (a zip with `Lowey.ipa` inside).
2. **Install [Sideloadly](https://sideloadly.io)** on a computer (Windows is fine) and connect the iPad with a cable.
3. Drag `Lowey.ipa` into Sideloadly, pick the iPad, sign in with a **free Apple ID**, press **Start**.
4. On the iPad: **Settings → General → VPN & Device Management** → your Apple ID → **Trust**. If asked, turn on
   **Settings → Privacy & Security → Developer Mode** and restart.
5. Open **3D-lowey**. The first launch adds the samples: the **Welcome island** (with a 60-second tour) and **Enigma**
   (a desk in Ink, a room of computers in Comic, a cave robot in Sketch, and the narrated story).

A free Apple ID signature lasts **7 days**; after that, connect the iPad and press **Start** in Sideloadly again.
Projects are kept: they live under *Files → On My iPad → 3D-lowey*. 2.0 installs next to 1.x (it has its own bundle
id), and 1.x projects open in it: share them from 1.x or pick them in Files.

**iPhone face companion**: install the same `.ipa` on an iPhone with Face ID. On a phone the app is only the companion:
it tracks your face and streams it to the iPad on the same Wi-Fi.

---

## Find your way around

The **stage** is on top, the **timeline** below (drag the divider; collapse it to a transport bar).

| Where | What's there |
|---|---|
| Top left | **Theater** (your projects) · **Actions** (photos and video, sound, voiceover, export, scripts, the AI & laptop bridge, gestures, tour, diagnostics, settings) · **Look** (Looks, mood, palette, finish) · **Select** (tap, lasso, select similar) |
| Top right | **Build** (shapes, lights and cameras, 3D text, titles and labels, effects, screen effects) · **Draw** (ink strokes, solid shapes on guides, flipbooks, Shadow Brush) · **Transform** (gizmo, snapping, align, Fly the camera) · **Cast** (Blob, Puppet, Rigged; clips, poses, faces, lip sync) · **Library** (the Kit's Sets and your models) |
| Side | two sliders for what you're doing, **Pick**, undo, redo |
| Right | the **inspector**, while something is selected: its menu has array, scatter, group, swap for a model, save to the library |
| Bottom | the timeline: **Compose** (move animation in time), **Perform** (record by touch), **Keyframe** (keys, easing, auto-key) |

| Gesture | Does |
|---|---|
| One finger / two fingers / pinch | orbit / pan / zoom |
| Double-tap | frame the selection |
| Two fingers on the selection | twist and pinch it |
| Two-finger tap / three-finger tap | undo / redo |
| Four-finger tap | hide everything but the stage |
| Pencil | draws; hover previews; Pencil Pro squeeze plays and pauses; roll during Perform |

Keyboard: ⌘1–5 Select, Build, Draw, Transform, Look · Space play · ⌘K key · ⌘M marker · ⌥⌘D Director view ·
⌥⌘Y fly the camera · ⇧⌘R record a performance · ⌥⌘R record voiceover · ⇧⌘T transcript · ⇧⌘U audio · ⌘E export ·
⇧⌘B bridge · ⌥⌘V paste a Scene Script · ⌥⌘N monitor window · ⌘Z / ⇧⌘Z.

In Stage Manager or with an external display, **Actions ▸ Monitor** opens the shot in its own window, live, as it
will export.

### A first shot

1. Theater → **New project**: a name, a mood, a Look.
2. Place **Library** models from the Kit (they arrive at real size) and draw with **Draw ▸ Ink**; **Cast** → add a Blob.
3. **Look** → try the five Looks; **Finish** for grain, bloom, outlines.
4. Select something → **Inspector ▸ Motion** → a preset (Pop in, Bounce…), or **Perform** and move it while it plays.
5. **Build** → camera, then **Director view** (⌥⌘D) to aim it; Inspector ▸ Camera for moves and focus.
6. **Actions** → **Voiceover** to record, then **Transcribe**; attach things to spoken words from the transcript.
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
Packages/LoweyCore      pure Swift: model, commands, timeline, geometry, characters, glTF, Scene Scripts, samples
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
