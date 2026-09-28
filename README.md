# 3D-lowey

A native iPad app for making videos that look like a game: build low-poly worlds like Lego,
direct them with a camera, animate them fast, and sync them to your narration.

**North star:** shorten the time from "the idea pops into my head" to "it's on screen".

- Vision, references and decisions: [`docs/context.md`](docs/context.md)
- The three phases to v1.0: [`docs/phases.txt`](docs/phases.txt)
- How the code is organised: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Every non-obvious choice and why: [`DECISIONS.md`](DECISIONS.md)
- What changed: [`CHANGELOG.md`](CHANGELOG.md)

Current version: **v1.0 — Phase 3: story, voice, VFX, AI, polish.** Build worlds (Phase 1), make them move (Phase 2),
then read your script into it: voiceover with word timing, lip sync and face performance on your own character,
overlays, captions, particles, post-processing, transitions, and Claude building shots through MCP — exported as
16:9 and 9:16 videos with sound.

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
5. Open **3D-lowey**. The first launch creates two samples — the **Welcome island** (with a 60-second tour) and the
   **Enigma** project (sets, the animated opening, and *5 · The story (narrated)*).
6. Optional — the **iPhone face companion**: install the same `Lowey.ipa` on an iPhone with Face ID. On an iPhone the app
   is only the companion screen: it tracks your face and streams it to the iPad on the same Wi-Fi.

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

## Animating (Phase 2)

Open the sample **Enigma — sets → 4 · Opening (animated)**, switch to **Camera** mode and press ▶︎.

| Do this | How |
|---|---|
| Animate by moving things | **Animate** mode: move / rotate / scale anything — each change is a key at the playhead (Auto-key). ◆ **Key** keys the whole pose |
| One-tap animation | Animate panel → a preset (Pop in, Bounce, Spin…). Select many things first: they go one after another (order, delay, randomness) |
| Motion capture by touch | Timeline → **Perform** → ● Record → "Ready 3-2-1" → drag / pinch / twist (or roll the Pencil Pro) while it plays. Lift to pause. Smoothing slider. |
| Edit keys | Timeline → **Keyframe**: tap diamonds (they turn white), drag to retime; **Easing** (or *Edit curve…*); copy/paste, mirror, reverse, faster/slower |
| Move a whole animation in time | Timeline → **Compose**: drag the bar |
| Always-on motion | Animate panel → **Add behaviour**: follow a drawn path, look at, orbit, wobble, wind sway, float, spin (bake to keys any time) |
| Physics & crowds | Animate panel → Fall / Explode / Flock; **Scripts** (`{}`) → Forest grows in / Flock of birds / Crowd walks in |
| Characters | Place a rigged model → Animate panel → *Play a clip from the playhead* (clips from other models of the same skeleton work too) → *Walk speed = path speed*, feet on ground, head looks at…, *Crowd of N* |
| Puppets | Select an arm → *Puppet joint* → *Joint at the top*: it now bends at the shoulder |
| Markers & loop | ⚑ adds a marker at the playhead (long-press it to name it after a word of the script); ↻ sets a loop region |
| Cameras | **Camera** mode: *Save camera from view*, *Cut here*, moves (push in, orbit, whip pan…), lens, focus pull, 9:16 zoom/pan. Look through: drag = pan/tilt, two fingers = move, pinch = dolly, twist = roll |
| The iPad as camera | Camera panel → *Use the iPad as the camera* (allow the camera) → set the scale → *Record the move* and walk around |
| Export a video | **Export** mode: tick 16:9 and 9:16 → *Export video* (keeps working in the background) → Share / Save to Photos |
| Keyboard | Space play/pause · ⌘K key · ⌥← ⌥→ frame step · ⇧⌘R record |

## Story, voice, VFX, AI (Phase 3)

Open **Enigma → 5 · The story (narrated)** and press ▶︎ in **Camera** mode: voiceover, captions, the label that follows
the paper, the glitch on "Enigma", the flash and the X on "Nobody", sparks on "AI", and the narrator lip-syncing the last
line. (The voice is a placeholder made on the iPad — record your own and transcribe it.)

| Do this | How |
|---|---|
| Pick many keys | Timeline → **Select** (or long-press) and drag a box across rows; **Pick** menu: all / after / before the playhead / in the loop / invert. Drag the white band's ends on the ruler to stretch their timing |
| Voiceover | Timeline → 〰 **Audio & words** → *Record voiceover* (the timeline plays while you narrate) or *Import* (also music and sound effects) |
| Word timing | Audio & words → pick the language → **Transcribe** (on the iPad, Apple speech, no internet after the first download). Words appear in a lane; keys, cuts and the playhead snap to them |
| Sync to a word | ⇧⌘T **Transcript** → tap a word to jump, long-press a word then tap another to pick a phrase → *Animate selection here*, *Camera move here*, *Cut here*, *Marker*, or *Fix words* |
| Your character | **+** → **Character**: head, hair, eyes, body, clothes, extras, colours. Animate panel → *Play a clip* (Idle, Walk, Talk, Wave…, or your imported Mixamo clips) |
| Lip sync | Select the character → Animate panel → *Lip sync to the voiceover* (or pick words in the transcript first) |
| Face performance | Animate panel → *Face (front camera)* or *Use my iPhone*; *Neutral* to recalibrate; Timeline → Perform → ● Record to capture a take |
| Titles, labels, the big X | **+** → Text / On the frame. Drag in the frame, pinch to size, twist to turn; *Follow an object* for labels. Typewriter preset types text and draws arrows |
| Captions | Animate panel → *Captions from the voiceover* (Punchy, Subtitle, Pill, Outline); burn-in on export; Export → .srt |
| Particles | **+** → Effects (fire, sparks, smoke, dust, magic, rain, snow, confetti, embers, explosion); amount / size / speed / colour in the inspector |
| The finish | **Look** → *Finish*: Cinematic, Dreamy, Retro (PS1), Ink outlines, Collage, Old film — or the sliders. Camera aperture now blurs for real |
| Flashes, shakes… | Animate panel → *Screen effects* at the playhead (flash, shake, speed lines, zoom blur, glitch); they show in the Effects lane |
| Transitions | Camera mode → *Transition* for the cut at the playhead (fade, dip to black, wipe, zoom through); *Match cut on the selection* |
| Claude / any AI | Scene menu → **AI & laptop bridge** → on. On the laptop: `lowey-link pair <address> <code>`, then `claude mcp add lowey -- lowey-mcp`. Claude's changes appear as a preview — **Apply** or **Not now**. See [`tools/lowey/README.md`](tools/lowey/README.md) |
| Scene Scripts from anywhere | Scene menu → *Paste a Scene Script* (any AI can write one — `/schemas/scene-script.schema.json`) |
| Laptop ↔ iPad | `lowey-link push model.glb`, `lowey-link audio voiceover.m4a`, `lowey-link pull --all`, `lowey-link generate tree` (Blender) |
| Projects | Home → touch and hold a project: *Share as one file (.loweypack)*, archive, duplicate; ⋯ → import, archive, tour, diagnostics |
| Keyboard | ⌘1–5 modes · Space play · ⌘K key · ⌘M marker · ⇧⌘T transcript · ⇧⌘U audio · ⌥⌘R record voice · ⇧⌘B bridge · ⌥⌘V paste script · ⇧⌘P post preview |

## Idea-to-screen time

The north star, measured for **a new simple shot: a world + a character + a camera move + synced to a word**.

| Path | Steps | Time |
|---|---|---|
| **By hand on the iPad** (Hesham, iPad Air M3) | new scene → Look mood → place 3–4 library/blockout props → **+** Character → *Play a clip → Talk* → *Save camera from view* → transcript: pick the word → *Camera move here → Push in* → *Lip sync* | **to measure on the device** (checklist below) |
| **With Claude** (lowey-mcp) | "Build the 'Nobody could' shot" → one `run_script` → preview on the iPad → *Apply* → tweak by hand | a 17-action shot script compiles and applies in well under a second (`ScriptCompilerTests`, Linux debug build); total ≈ Claude's thinking time + one tap |

How to measure (so the number is honest): start a stopwatch when the idea is said out loud, stop when the shot plays
synced in Camera mode. Do it three times with different ideas; write the median here. The components the app controls
are fast (a whole shot script compiles and applies in under a second; transcription runs on the device).

---

## Development

Nobody needs a Mac: GitHub Actions builds, tests and packages everything.

```
LoweyCore/     pure Swift model, commands, undo, timeline math, geometry, library, serialization
LoweyCore/     … + motion (timeline evaluation, presets, behaviours, Perform, camera moves, simulations),
               rigs (glTF skeletons & clips, retargeting, IK), 3D export (GLB, USDZ)
LoweyRender/   RealityKit bridge: entities, materials + fog shader, environment, offscreen renderer, video exporter
LoweyCore/     … + audio (clips, mixer, transcripts, words), text & overlays & captions, VFX (particles, post, screen effects,
               transitions), face (lip sync, face solver, face rig), characters (builder, puppet rig, built-in clips),
               AI (Scene Script actions compiler, LAN bridge core), project packages, samples (Enigma story, welcome island)
LoweyRender/   … + frame compositor (Core Image), overlay renderer, stage post-process, depth world, particles
LoweyScript/   JavaScriptCore scripting (one script run = one undoable command)
App/           SwiftUI app: home, stage, tools, panels, timeline, gestures, virtual camera, audio, speech, face capture,
               bridge server, tour, diagnostics
AppTests/      render tests on the iPad simulator (import, thumbnails, offscreen, 50 instances, video export, tiger walk, scripts,
               narrated story, post, overlays, particles, character, depth pass, soundtrack, SpeechAnalyzer)
tools/lowey/   laptop side: lowey-mcp (MCP server) and lowey-link (companion CLI), with pytest tests
skills/lowey/  The Claude skill: one orchestrator (SKILL.md) + modules (breakdown, shots, sets, camera, characters, animation, Manim & media, style)
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
- Put `[build-only]` in a commit message to make CI only compile the app (no simulator tests) — cheaper while iterating.
- Scripting reference: the Scripts panel's *What scripts can do*; examples in `Packages/LoweyScript/Sources/LoweyScript/ScriptExamples.swift`.

## License

Private project by Hesham. Third-party code: see [`THIRD_PARTY.md`](THIRD_PARTY.md).
