# Changelog

All notable changes. Versions follow the phase plan (Phase 1 = v0.1 → v0.4).

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
- Keyboard shortcuts (⌘Z, ⇧⌘Z, ⌘D, ⌘C, ⌘V, ⌘G, ⌘A, ⌫, F, ⌘L), haptics, Stage Manager friendly.
- Sample project: the Enigma sets.
