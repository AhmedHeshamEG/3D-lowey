# 3D-lowey

A native iPad app for making videos that look like a game: build low-poly worlds like Lego,
direct them with a camera, animate them fast, and sync them to your narration.

**North star:** shorten the time from "the idea pops into my head" to "it's on screen".

- Vision, references and decisions: [`docs/context.md`](docs/context.md)
- The three phases to v1.0: [`docs/phases.txt`](docs/phases.txt)
- How the code is organised: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Every non-obvious choice and why: [`DECISIONS.md`](DECISIONS.md)
- What changed: [`CHANGELOG.md`](CHANGELOG.md)

Current phase: **Phase 1 — Foundation & Build (v0.4)**. Build worlds from blockout shapes, library models and
3D drawing; give them a look; save, close, reopen — identical.

---

## Install on the iPad (no Mac needed)

Every push to `main` builds an installable `Lowey.ipa` on GitHub Actions.

1. **Download the .ipa**
   - Latest release: *Releases* → newest `v…` → `Lowey.ipa`, or
   - Latest `main` build: *Actions* → **Release** workflow → newest green run → *Artifacts* → `Lowey-<version>-<build>` (a zip containing `Lowey.ipa`; unzip it).
2. **Install [Sideloadly](https://sideloadly.io)** on the laptop (Windows is fine) and plug the iPad in with a cable. Trust the computer on the iPad if asked.
3. In Sideloadly, drag `Lowey.ipa` in, pick the iPad, enter your **free Apple ID**, press **Start**.
4. On the iPad: **Settings → General → VPN & Device Management** → your Apple ID → **Trust**.
   (If asked, turn on **Settings → Privacy & Security → Developer Mode** and restart.)
5. Open **3D-lowey**. The first launch creates the **Enigma — sets** sample project.

**Every 7 days** a free Apple ID signature expires and the app stops opening. Plug in and press **Start** in
Sideloadly again with the same .ipa (or a newer one). Your projects are kept — they live in the app's Documents
folder, visible in the **Files** app under *On My iPad → 3D-lowey*.

---

## Using it (Phase 1)

| Do this | How |
|---|---|
| Orbit / pan / zoom | 1 finger / 2 fingers / pinch |
| Frame the selection | double-tap (or the ⌖ button) |
| Undo / redo | 2-finger tap / 3-finger tap (or the rail, or ⌘Z / ⇧⌘Z) |
| Add a blockout shape, light or camera | **+** on the left rail |
| Place a model | **Library** (search first) → tap, or drag a tile onto the stage |
| Import models | Library → ⬇︎ (USDZ, glTF, GLB, OBJ, or a whole folder), share sheet "Open in 3D-lowey", or drag files in |
| Move things | drag a selected object, the gizmo arrows, or the on-screen joystick (slider = up/down) |
| Rotate / scale | switch the gizmo mode on the rail (the joystick follows the mode) |
| Multi-select | long-press objects, or the **lasso** tool |
| Many copies | Inspector → **Array** (row, grid, circle) or the **Scatter** tool (drag an area on the ground) |
| Swap a blockout for a model | select the shape → **Swap…** → pick a model (it's fitted to the blockout's size) |
| Draw in 3D | **Draw** tool: Pencil draws on the guide (plane facing you / ground / front / side, box, cylinder, sphere, or on an object). Tube, ribbon, extrude an outline, or lathe a profile. Mirror on/off. Fingers keep moving the view. |
| Save something you built | Inspector → **Save to library** ("Save & link" makes it a prefab: edit it once, every copy updates) |
| Change the mood | **Look** mode: 6 mood presets, palette (with eyedropper), fog, stars, ground, fine tune |
| Snapshot | **Export** mode: 16:9, 9:16 or 1:1 PNG, HD or 4K (framed exactly like the guide on screen) |

Palette colours are linked: change a palette slot and every object using it updates.

---

## Development

Nobody needs a Mac: GitHub Actions builds, tests and packages everything.

```
LoweyCore/     pure Swift model, commands, undo, timeline math, geometry, library, serialization
LoweyRender/   RealityKit bridge: entities, materials + fog shader, environment, offscreen renderer
App/           SwiftUI app: home, stage, tools, panels, gestures
AppTests/      render tests on the iPad simulator (import, thumbnails, offscreen, 50 instances)
AppUITests/    smoke test of the critical flow (with screenshots)
```

- The Xcode project is generated from [`project.yml`](project.yml) with XcodeGen (`xcodegen generate`); it is never committed.
- Core tests run anywhere Swift runs, including Docker on Windows:
  `docker run --rm -v "$PWD/Packages/LoweyCore:/src" -w /src swift:6.1 swift test`
- CI (`.github/workflows/ci.yml`): SwiftFormat + SwiftLint → Core tests with a ≥ 80 % coverage gate (Linux) →
  app build + render tests + UI smoke test on an iPad simulator (Xcode 27.0). Screenshots and renders from the
  tests are uploaded as the `test-attachments` artifact.
- Release (`.github/workflows/release.yml`): unsigned device build → ad-hoc codesign → `Lowey.ipa`.
  Tags `v*` also publish a GitHub Release. Build number = CI run number; version = tag.
- The app's display name lives in one place: `Config/Branding.xcconfig`.
- Test fixtures (tiny glTF models) are generated by `python scripts/make_fixtures.py`.

## License

Private project by Hesham. Third-party code: see [`THIRD_PARTY.md`](THIRD_PARTY.md).
