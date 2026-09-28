# Decisions

Every non-obvious choice, with the reason. Binding decisions from `docs/context.md` §10 are not repeated here
unless something changed.

## Engineering

**D1 — Three layers: LoweyCore (pure Swift) / LoweyRender (RealityKit) / App (SwiftUI).**
Core has zero Apple UI/3D imports, so its 100+ tests run on Linux in seconds (Docker on Windows, `swift:6.1` in CI).
RealityKit only exists in LoweyRender.

**D2 — Commands are an enum that returns its own inverse.**
`EditCommand.apply(to:)` returns `(inverse, changes)`. Undo = apply the inverse. This makes "every command reverts
perfectly" testable generically (`assertReverts` applies, inverts, re-applies and JSON round-trips each command)
and makes commands serialisable for Scene Scripts. Applying is atomic (works on a copy, commits on success).

**D3 — Gesture coalescing.** Continuous edits (joystick, gizmo drags, sliders) carry a `coalesceKey`; the session
merges them into one undo step and keeps the *first* inverse (pre-gesture state).

**D4 — Transform is stored as three animatable properties** (`position`, `rotation`, `scale`), not a separate field.
Phase 2 keyframes any property the same way; nothing about transforms is special.

**D5 — Colours quantised to 8 bits; dates stored as raw `timeIntervalSinceReferenceDate`.**
Hex colours and ISO dates lose precision, which broke "save → reopen → identical". Quantising on creation and storing
the native date value makes round trips bit-exact (tested).

**D6 — Versioned envelope + migration chain from day one.** Files are `{schemaVersion, kind, payload}`. Unversioned
files are treated as v0 and migrated (the v0 → v1 scene migration converts object arrays and nested transforms; tested
with a hand-written fake v0 file). Files from a newer app are refused with a clear message.

**D7 — Crash-safe writes.** `Data.write(.atomic)` plus a `.bak` of the previous good version; the loader falls back to
the backup when the main file is damaged (tested by corrupting a file). A damaged file never overwrites a good backup.

**D8 — Look lives on the project with an optional per-scene override.** `Scene.look == nil` inherits the project look.
The Enigma sets need three different moods in one project, but the palette should normally be shared.
"Only this scene" in the Look panel creates/removes the override.

**D9 — Primitives pivot at the centre of their base.** Things sit on the ground and grow upward when scaled (Lego-like),
which makes placing, stacking and swapping predictable.

**D10 — Smooth shading = auto-smooth (60°), not fully welded normals.** Hesham prefers soft low-poly; fully smoothed
cubes look like blobs. Auto-smooth keeps hard edges hard and round things soft. Flat = faceted.

**D11 — Drawn objects store the recipe (strokes + style), not triangles.** Small files, deterministic regeneration,
editable later (Phase 3 could re-style a stroke).

**D12 — Prefabs are referenced, not copied.** A prefab instance is one object (`kind: prefab(id)`); the renderer
expands the library fragment. Updating the prefab bumps its version and every instance rebuilds. "Unpack" turns an
instance back into editable objects. "Save a copy" keeps the selection as plain objects.

**D13 — Swap keeps position and rotation, fits the model uniformly into the blockout's size, keeps the base on the
ground.** Literally keeping the blockout's non-uniform scale would distort the model.

**D14 — Scatter is seeded.** The seed is part of the generated command, so undo/redo and re-applying a Scene Script
reproduce the same forest.

## Rendering

**D15 — ARView (non-AR) for the live stage, RealityRenderer for offscreen.**
`ARView(cameraMode: .nonAR)` is mature on iPadOS (not deprecated), gives direct UIKit gesture control, `ray(through:)`,
`project(_:)`, and statistics overlay. SceneKit is not used (soft-deprecated). `RealityView` was considered; ARView
won for picking/projection APIs and predictable camera control. Revisit in Phase 3 if RealityView gains something we need.

**D16 — Offscreen rendering spike: `RealityRenderer` (iPadOS 18+).**
Findings (verified against Apple's documentation):
- `RealityRenderer` is available on iPadOS 18+ (we target 26). It renders a separate set of entities
  (`entities`, `activeCamera`, `lighting` IBL, `cameraSettings.colorBackground/antialiasing`) into any `MTLTexture`
  via `updateAndRender(deltaTime:cameraOutput:…onComplete:)` with `CameraOutput(.singleProjection(colorTexture:))`.
- It needs its own entities, so we render a **clone** of the world (helpers stripped). Clones share meshes and
  materials, so this is cheap.
- `deltaTime` is ours to choose → Phase 2 video export renders frame by frame at a fixed timestep, independent of
  real-time speed. Output textures are `bgra8Unorm_srgb`, shared storage, read back with `getBytes`.
- Proven in CI by `RenderTests.testEnigmaSetsRenderOffscreen` (renders every Enigma set at 16:9 and 9:16 and checks the
  image isn't blank) and by library thumbnails. Fallbacks considered: `ARView.snapshot` (only what's on screen, fixed
  size) and raw Metal (too much to rebuild). Not needed.

**D17 — Fog is in the material, not a post-process.** RealityKit has no fog. ARView's post-process callback has depth
but `RealityRenderer` exposes no depth output, so a post-process fog would differ between preview and export.
A `CustomMaterial` surface shader computes exponential distance fog per pixel from the view-space position — identical
everywhere. Imported materials are converted with `CustomMaterial(from:surfaceShader:)` (textures kept). If the shader
library can't load, everything falls back to `PhysicallyBasedMaterial` without fog (logged; tested in CI).

**D18 — The shader lives in the LoweyRender package** and is compiled by Xcode into the package bundle
(`makeDefaultLibrary(bundle: .module)`), so the render tests exercise it too; the loader also checks the app bundle.

**D19 — Orthographic = 2° telephoto.** `OrthographicCameraComponent` exists (iOS 18) but ARView/RealityRenderer camera
support for it is less proven, and picking/projection would need a second code path. A 2° field of view from far away
is visually orthographic, works in both renderers, and keeps one ray/projection path. The sky dome follows the camera
and grows so it never clips.

**D20 — Sky = unlit dome with a generated gradient + stars texture; ambient light = IBL generated from the same sky.**
Night scenes get dark, cool ambient light automatically; day scenes get bright ambient — one decision (the mood)
drives both.

**D21 — Instancing: shared resources, not `MeshInstancesComponent` (yet).** Model clones share their prototype's
`MeshResource` and materials; identical Lowey surfaces share one material instance. RealityKit batches these.
`RenderTests.testFiftyInstancesPlaceAndRender` asserts the 50 foxes share one mesh. `MeshInstancesComponent` (iOS 26)
is the Phase 3 performance-pass option for thousands of static objects (it loses per-instance selection).

**D22 — Selection and picking use box collision shapes** from content bounds (cheap). Drawing on an object uses an
exact CPU raycast against the object's world mesh (`MeshRaycast`, tested), built on demand when a stroke starts.

**D23 — Snapshots match the on-screen framing guide.** The export camera's field of view is derived from the guide
rectangle drawn over the stage, so a 9:16 snapshot contains exactly what the portrait guide showed.

## Library & assets

**D24 — glTF/GLB are kept as files in the library and loaded with GLTFKit2 each session.** Converting to USDZ on device
isn't possible without Mac tools. `.gltf` imports copy their referenced `.bin`/textures (tested).

**D25 — Rig detection by joint-name heuristics** (Mixamo, Quaternius-style, generic; birds via wing/beak, quadrupeds via
front/back legs or tail without arms). Skeletons and clips are kept intact for Phase 2; the library shows a RIGGED badge.

**D26 — Search-first library with ranking** (exact name > prefix > word prefix > tag > substring > fuzzy subsequence,
every word must match, favourites get a boost). Filters: All, Favorites, Recent, Models, Built (prefabs), Looks.

## Product

**D27 — New project = a name + one mood.** Few decisions, big result; everything else can change later.

**D28 — First launch creates the "Enigma — sets" sample** (desk + paper + warm lamp; 12 people at PCs; hero robot in a
cave), built only from blockout, drawing recipes and lights through the command system. It's both onboarding and the
Phase 1 proof.

**D29 — Pencil draws, fingers navigate** (Draw tool). A toggle allows finger drawing for people without a Pencil.

**D30 — Tapping part of a group selects the top-most group; tapping again digs one level deeper** (Keynote/Figma
style), so blocked-out assemblies behave like Lego pieces.

## CI

**D31 — Runner `xcode-27` with Xcode 27.0 pinned (`DEVELOPER_DIR`).** It's the image with the iPadOS 27 SDK.
Deployment target stays iPadOS 26.0 (SpeechAnalyzer needs 26).

**D32 — Render tests run as an unhosted test bundle** linking the packages directly, so RealityKit code is tested on
the simulator without linking the packages twice into a hosted bundle. The UI smoke test drives the real app.

**D33 — Test screenshots and renders are exported from the xcresult as a CI artifact** (`test-attachments`) — visual
evidence without a Mac.

## Phase 2 — motion, camera, characters, export

**D34 — One evaluator for everything that moves: `Animator.evaluate(document, at:)`.** Tracks, per-object stepping,
behaviours, camera cuts and character poses are resolved by one pure function in LoweyCore. The stage, snapshots,
the exporter and the tests all call it, so preview and export can't drift apart and every rule is unit-tested on Linux.

**D35 — The stage shows the scene *as evaluated at the playhead*; tools edit what you see.** `EditorModel.scene` is
the evaluated scene. Editing an animated property (or any animatable property in Animate/Camera mode with auto-key on)
is rewritten into a key at the playhead (`EditorModel.keyed`). A brand-new track also gets a key at 0 holding the old
value, so the first edit already animates instead of just snapping. Structural edits (add, delete, group) are never keyed.

**D36 — `setTracks` is the fine-grained key command; everything else in the timeline uses `setTimeline`.** Keying
while dragging happens many times per second: `setTracks` carries only the touched tracks and coalesces (latest
track wins, first inverse kept), so a whole gesture or Perform take is one undo step. Markers, cuts, behaviours and
clip tracks change rarely and go through `setTimeline`.

**D37 — Deleting / duplicating objects takes their animation along.** Delete removes their tracks, behaviours, clips and
cuts in the same undo step; duplicate copies them (position keys of top-level copies are shifted with the copy).

**D38 — Schema v2.** New timeline fields are optional with defaults (Phase 1 files open unchanged; tested), but the
version is bumped so a Phase 1 app refuses v2 files instead of silently dropping animation when it re-saves them.

**D39 — Presets, camera moves, simulations and Perform takes all produce plain keyframes.** Nothing is a hidden effect:
everything can be edited, retimed, copied or deleted in the timeline. Presets are relative to how the object looks at
the playhead; applying one replaces keys only inside its own time span.

**D40 — Behaviours are stateless functions of time.** Noise is lattice value noise seeded by the behaviour id; `follow`
with lag reads the target's *keyed* position at `time - lag` (no simulation state). Any frame can be evaluated in any
order — required for scrubbing and for exact, parallelisable export. Baking samples them at the project fps.

**D41 — Simulations run in LoweyCore at a fixed timestep and bake, instead of RealityKit's live physics.** RealityKit's
simulation advances with the display clock, can't be stepped headlessly, and doesn't promise identical replays; a baked
take must be exact and testable. Rigid bodies are spheres fitted to the bounds (ground + body collisions, bounce,
friction, explode impulse); flocks are boids; crowds walk to targets with separation. All deterministic (tested).

**D42 — Perform = live override + recorded samples → `PerformBaker`.** While recording, touches drive a per-object
override on top of the evaluated scene (you see the motion immediately); samples are taken on every display frame at
the playhead time. Lifting the finger ends a segment (the timeline keeps playing). At the end the baker resamples to the
project fps, smooths with a zero-phase filter (the curve doesn't lag behind the finger), simplifies (Ramer–Douglas–Peucker)
unless smoothing is 0 % ("capture everything"), and replaces only the performed ranges — one undo step.

**D43 — Characters: skeletons and clips are read by LoweyCore from the glTF file (`GLTFReader`), not from RealityKit.**
RealityKit plays clips but can't sample, blend, retarget or apply IK to them deterministically. Reading the glTF skin
and animation channels in pure Swift makes clip playback, crossfades, retargeting, IK and path-speed matching part of
the tested evaluator. Poses are written to `ModelEntity.jointTransforms`, applied relative to the model's own rest pose
(so armature/axis conventions don't matter). USDZ models without Core rig data fall back to RealityKit's own animation,
paused and scrubbed (`applyClipFallback`).

**D44 — Retargeting in model space.** Bones are auto-mapped to a standard (Humanoid, Quadruped, Bird) by name and
chain; each mapped bone's rotation change from rest is transferred as a model-space delta, and the hips' travel is
scaled by hip height. Works across Mixamo/Quaternius/Blender naming and differing local bone axes, as long as rest
poses are similar (T/A pose facing +Z). Tested on two humans of different sizes and naming, and two quadrupeds.

**D45 — Walking without foot sliding = speed matching, plus feet-on-ground IK.** The clip's stride speed is measured
(root motion if the hips travel, otherwise from how far the feet sweep in a cycle); "Walk speed = path speed" sets the
clip speed to path speed ÷ stride speed. IK keeps feet above the ground; look-at turns the head; reach bends an arm.

**D46 — Cameras: the stage looks *through* the shot camera in Camera mode.** The stage widens its field of view so the
framing guide covers exactly the camera's frame (WYSIWYG with export). Dragging aims the camera (pan/tilt), two
fingers move it, pinch dollies, twist rolls — keyed at the playhead. Cuts are a list of (time, camera).

**D47 — One camera, two framings.** 16:9 uses the camera as framed; 9:16 uses the same vertical field of view × a
per-camera *portrait zoom* and a *portrait pan* (a small yaw), both animatable. One scene exports both without a
second camera.

**D48 — Virtual camera = ARKit world tracking relative to where you started.** The rear camera tracks the iPad
(works on iPad Air; no TrueDepth needed). The device's motion since the start is applied to the scene camera with a
scale factor (1 m of walking can be 10 m in the world) and recorded through Perform like any other take.

**D49 — Export renders frame by frame in a dedicated world.** `VideoExporter` owns a second `SceneRenderer` without
editor helpers and one persistent `RealityRenderer`; for each frame it evaluates the timeline, syncs only what moved,
renders every framing into its own texture and appends it to an `AVAssetWriter` (H.264/HEVC .mp4; HEVC-with-alpha
.mov when transparent) or writes PNGs. It waits for models to load and renders warm-up frames before frame 0. The
stage stays usable; progress and cancel are in the Export panel. Determinism is tested (same frame twice → same pixels).

**D50 — Depth of field is stored and animatable (focus distance, aperture, focus pulls) but not yet rendered.**
`RealityRenderer` exposes no depth output (see D17), so a correct lens blur needs a separate depth pass. The lens data
is in place so Phase 3's post-processing pass (bloom, grain, lens blur…) can render it identically in preview and export.

**D51 — Scripting is JavaScriptCore in its own package (`LoweyScript`), returning ONE command.** Scripts run on a
worker thread against a copy of the document with a time limit; every API call is a real command applied to that
copy (so later calls see earlier results); the collected commands come back as one batch the editor performs —
undoable like any tool. No file, network or timer APIs are exposed. `lowey.random(seed)` is a deterministic xorshift.
JavaScriptCore doesn't exist on Linux, so its tests live in the app test bundle.

**D52 — 3D export is written in LoweyCore (GLB + USDZ).** Blockout and drawn objects export from their exact recipes;
library models and prefab instances are read back from their loaded meshes (geometry only — textures aren't carried).
USDZ is an uncompressed zip with 64-byte-aligned entries around a USD text layer with `UsdPreviewSurface` materials.
