# Changelog

All notable changes. Versions follow the phase plan (Phase 1 = v0.1 → v0.4, Phase 2 = v0.5 → v0.8).

## [0.8.0] — Phase 2: Motion, camera, characters, export

### Timeline
- Bottom timeline drawer in Animate and Camera modes: transport, frame stepping, scrubbing ruler, markers (tap to jump,
  long-press to rename/delete), loop region, zoom (pinch) and pan, one row per animated object (expand into property
  rows), behaviour spans, clip segments, camera-cut row.
- Modes: **Compose** (slide whole animations in time), **Perform** (record by touch), **Keyframe** (select, drag,
  retime keys). Frame rate 24/25/30/60, length, "fit to animation".
- Timeline evaluation, per-object and per-project stepping (cameras stay smooth) — all in LoweyCore, unit-tested.

### Keyframes & easing
- Keyframe any animatable property: auto-key (edits in Animate/Camera mode become keys at the playhead), animated
  properties always key, "Key" button (⌘K).
- Easing presets (linear, in, out, in-out, overshoot, bounce, elastic, step) + a curve editor with draggable handles.
- Copy/paste (also onto another object), mirror (there and back), reverse, twice as fast/slow, delete.

### Perform mode
- Record → "Ready 3-2-1" → the timeline plays; drag to move, pinch to scale, twist (or Apple Pencil Pro barrel roll)
  to turn. Lift = pause, touch again = resume. Smoothing 0–100 %. Sliders perform any number (glow, light, opacity,
  zoom, focus). Re-performing replaces only the performed range. One undo step per take.

### Presets & mass animation
- 15 one-tap presets: pop in/out, grow, shrink, bounce, wiggle, float, spin, shake, pulse, fade in/out, slide in,
  drop in, typewriter — real, editable keys.
- Many objects at once: delay, order (selection, left→right, right→left, front→back, wave), random timing and strength.
- Behaviours: follow a drawn path, look at, follow (with lag), orbit, wobble, wind sway, bob on water, spin —
  deterministic, bake to keys. Animated generators (arrays/scatters grow in one by one).
- Simulations baked to keys: fall, explode, flock of birds, crowd walks in.
- Scripting (JavaScriptCore): script panel with inline errors and a log; scripts saved in the library; examples:
  forest grows in, flock of birds, crowd walks in. Every run is one undo step.

### Characters
- Skeletons and clips read from glTF/GLB in LoweyCore; clips play on skinned models (poses → joint transforms).
- Standards Humanoid / Quadruped / Bird / Custom with auto bone mapping (Mixamo, Quaternius-style, Blender, generic).
- Retargeting: a clip for a standard plays on any character of that standard (tested on 2 humans, 2 quadrupeds).
- Clip track: play from the playhead, loop, speed, crossfade; walk speed matched to a path (no sliding); feet on the
  ground, head look-at, hand reach (IK). Crowd tool: N copies with offset, varied clips.
- Puppet joints: wrap parts in a joint that pivots at the top/middle/bottom (shoulders, hips, hinges).

### Camera
- Look through the shot camera; drag to aim, two fingers to move, pinch to dolly, twist to roll — keyed.
- Cameras + camera-cut track ("Cut here"). 10 one-tap moves: push in, pull out, punch in, orbit, dolly, truck, crane,
  whip pan, shake, reveal; follow the selection.
- Lens: focal length, focus distance, aperture, focus on selection, animated focus pull (rendered blur arrives with
  Phase 3's post-processing — see DECISIONS D50).
- Framing guides 16:9 / 9:16 / 1:1 with safe zones and thirds; per-camera 9:16 zoom and pan, so one camera exports both.
- The iPad as a virtual camera (ARKit world tracking, scale factor), recorded through Perform.

### Export
- Video rendered frame by frame at a fixed timestep: 16:9 + 9:16 (+ 1:1) in one job, HD/4K, H.264/HEVC, PNG sequences,
  transparent background (HEVC with alpha / PNG), whole timeline or the loop region; progress and cancel; saved in the
  project's renders folder; share or save to Photos. Single frames through the camera.
- 3D export of the selection or the scene: glTF (.glb) and USDZ.

### Engineering
- Schema v2 (Phase 1 files open unchanged). New commands: `setTracks`. Deleting/duplicating objects carries their animation.
- New package `LoweyScript`. New Core modules: Motion, Rig, Export. Sample project gains "4 · Opening (animated)".
- CI: `[build-only]` in a commit message runs a compile-only app job (saves macOS minutes).
- Fixed: Mixamo "Fo**rear**m" was read as a quadruped's rear leg by the rig classifier.

## [0.4.0] — Phase 1: Foundation & Build

### Engineering
- XcodeGen project (`project.yml`), Swift 6 strict concurrency, packages `LoweyCore` + `LoweyRender`, app `LoweyApp`.
- CI: SwiftFormat + SwiftLint → LoweyCore tests on Linux with ≥ 80 % coverage gate → iPad simulator build,
  render tests and UI smoke test (screenshots exported as artifacts).
- Release: unsigned device build → ad-hoc codesign → `Lowey.ipa` on every `main` push; GitHub Release on `v*` tags.
- Docs: README (Sideloadly install), ARCHITECTURE, DECISIONS, THIRD_PARTY.

### Core model
- Objects with typed, animatable properties; groups/hierarchy; lights; cameras; drawn objects (recipes); prefab instances.
- Command system with exact inverses, batches, JSON encoding (Scene Script vocabulary); undo/redo with gesture coalescing.
- Timeline, keyframes, easing (linear, in, out, in-out, back, bounce, elastic, step, bezier), on-twos stepping.
- Project folders (`.lowey`), schema versioning + migrations (v0 → v1), atomic writes with backup recovery, autosave.

### Render
- RealityKit bridge with diff-based sync, shared meshes/materials (instancing), fog + glow surface shader.
- Looks: smooth/flat shading, linked palette, 6 mood presets, sun with shadows, sky gradient + stars, fog, ground,
  sky-driven ambient light, custom point/spot/directional lights with shadows, emissive glow.
- Offscreen renderer (RealityRenderer) for snapshots and thumbnails — the Phase 2 export path.

### Building
- Blockout primitives (cube, sphere, cylinder, cone, plane, torus, ramp); swap blockout → library model (fit to size).
- Gizmos (move/rotate/scale), on-screen joystick, direct drag, numeric inspector.
- Snapping: grid, ground, flush to other objects, rotation steps.
- Duplicate, copy/paste, array (row, grid, circle), scatter an area in one gesture (seeded), group/ungroup,
  outliner with lock/hide/reparent, align/distribute.

### Drawing in 3D
- Pencil pressure strokes with smoothing → tube or ribbon; extrude a drawn outline; lathe a drawn profile; mirror.
- Guides: plane locked to the view (or ground/front/side) with offset, box, cylinder, sphere, or any existing object.
- Save anything to the library.

### Library
- Global library (USDZ, glTF/GLB with dependencies, OBJ; files, folders, drag & drop, share sheet).
- Auto thumbnails, search-first panel, tags, favorites, recents, RIGGED badge (skeleton + clips kept), prefabs that
  update everywhere, saved looks. Projects reference assets by id; "Export" copies them in.

### UI
- Home with project thumbnails; stage with left tool rail, top-right mode switcher (Build · Animate · Camera · Look ·
  Export), inspector, library, outliner, look panel; snapshot export as PNG in 16:9, 9:16 and 1:1 (HD / 4K).
- Keyboard shortcuts (⌘Z, ⇧⌘Z, ⌘D, ⌘C, ⌘V, ⌘G, ⌘A, ⌘⌫ delete, ⌘F frame, ⌘L library), haptics, Stage Manager friendly.
- Sample project: the Enigma sets.
