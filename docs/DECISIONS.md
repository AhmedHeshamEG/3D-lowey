# Decisions

Every non-obvious choice, with the reason. D1–D86 are the 1.x decisions, kept as history; where 2.0 replaced one,
the 2.0 entry (R…) says so. What the product is lives in [SPEC.md](SPEC.md); how it's built in
[ARCHITECTURE.md](ARCHITECTURE.md).

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

## Phase 3 — story, voice, VFX, AI, polish

**D53 — Keyframe multi-select is one gesture layer over all lanes, with the logic in Core (`KeySelection`).** Procreate
Dreams-style: long-press-drag (or the Select toggle + drag) draws a box across rows and time; the Pick menu selects all /
after / before / at the playhead / in the loop / invert; a band on the ruler stretches or squashes the selected keys'
timing; Compose mode moves several bars together. One recogniser for every lane (instead of one per row) is what makes a
box that spans tracks possible. Selecting never changes the document; moves and stretches are one undo step each.

**D54 — Audio lives in the timeline (`audio`, `transcripts`) and is mixed in Core.** Clips reference files in the
project's `audio/` folder. `AudioMixer` (pure Swift) mixes exactly what the preview plays (volume × fades × envelope, soft
limiting), so exports are deterministic and tested on Linux; the app only decodes (AVAudioFile → 48 kHz float) and plays
(one `AVAudioPlayerNode` per clip). During playback the picture follows the audio clock (host-time anchor), so sound and
picture never drift. Schema v3 (additive).

**D55 — Word timing: SpeechAnalyzer + SpeechTranscriber with `.audioTimeRange` (no Whisper).** Verified against Apple's
documentation (Speech, iPadOS 26). Audio is converted to `SpeechAnalyzer.bestAvailableAudioFormat` first; the model is
installed on first use with `AssetInventory.assetInstallationRequest`. Recogniser runs holding several words are split by
length inside their range. Words are stored in *file* time per clip, so trimming or moving the clip keeps them in place.
Corrections replace words and keep (or share) their timing. English, Arabic and Italian are offered first when supported.

**D56 — Syncing to words = snapping + word-addressed times.** Keys, the playhead, audio clips and effects snap to word
edges; transcript phrases carry presets, camera moves, cuts and markers. Scene Scripts address time as
`{"word": "Enigma"}`, so AI-built shots land on the voice by construction.

**D57 — Overlays are scene objects in frame space.** `ObjectKind.overlay` (titles, labels, arrows, the X, the question
mark…) with x/y in −1…1 of the frame, so presets, keys, Perform, stagger and scripts animate them with no new machinery.
Size is relative to the frame's short side (the same overlay reads the same in 16:9 and 9:16; titles shrink to fit narrow
frames). An overlay can follow a 3D object (projected through the shot camera). One CoreGraphics renderer draws them for the
stage and for export.

**D58 — 3D text: a built-in 5×7 block font meshed in Core ("Blocky"), system fonts through RealityKit otherwise.** The
block font is low-poly by design, exact in bounds and in 3D export, and tested; `MeshResource.generateText` covers smooth
styles and every script (Arabic).

**D59 — Particles are a pure function of time.** Each particle's life is computed in closed form from its index and a seed
(ballistic motion with drag, swirl, colour over life). Scrubbing, loops and export are exact; the same frame is the same
pixels (tested). Meshes are octahedra (diamonds, streaks, tumbling cards) grouped into ≤ 8 colour bands — a few draw calls
per effect. RealityKit's `ParticleEmitterComponent` isn't used: it simulates with the display clock and can't be evaluated
at an arbitrary time.

**D60 — One compositor for preview and export (Core Image).** Order: shot (lens blur → ink outlines → bloom → grade →
chromatic aberration → retro) → transition → screen effects (shake, zoom blur, glitch, speed lines, flash) → film (texture,
vignette, grain) → overlays and captions. The stage runs it in ARView's post-process callback, the exporter on every
rendered frame. When nothing needs it the stage switches the pass off (no cost).

**D61 — Depth for lens blur and outlines is stored as v = 0.5 / distance.** The circle of confusion is linear in
1/distance, so this is the natural encoding. Export renders a second "depth world" (every surface the unlit `loweyDepth`
shader, sky off) at half resolution; the stage converts RealityKit's reverse-Z depth buffer with the `loweyInverseDepth`
compute kernel. Both give the same v, so blur matches. This resolves the Phase 2 limitation (D50).
`Phase3Tests.testDepthPassEncodesInverseDistance` checks the export path against known distances.

**D62 — Transitions are centred on their cut and render both shots in export.** The exporter renders the outgoing camera
into a second target and blends. The live preview shows the cut (two cameras live would halve the frame rate).

**D63 — Lip sync from words with the CMU Pronouncing Dictionary, not audio analysis.** `scripts/make_visemes.py` turns
CMUdict (BSD) into word → Rhubarb / Preston Blair mouth shapes (A–H, X), shipped as a Core resource; unknown English words
use letter-to-sound rules, Italian is phonetic, Arabic letters map directly (short vowels assumed). Shapes become keys
(`mouth`, stepped) plus eased `jawOpen` / `mouthWide`, so lip sync is editable like any animation. The voice's loudness is
the fallback for words without known sounds.

**D64 — Faces are channels on the character root, applied by a face rig inside the evaluator.** `jawOpen`,
`blinkLeft/Right`, `brows`, `smile`, `mouthWide`, `lookX/Y`, `headYaw/Pitch/Roll`, `mouth`. Parts carry a `faceRole`
("eye.L", "mouth.D"…); the rig scales eyes, lifts brows, swaps mouth shapes (Toonsquid-style) and turns the head after
clips. Keys, lip sync, live face capture and the iPhone companion all write the same channels; live values are evaluator
overrides, recorded by Perform like any slider.

**D65 — Face capture: Vision landmarks on the iPad; ARKit blend shapes from an optional iPhone.** The iPad Air has no
TrueDepth camera. Ratios (eye openness, brow height, mouth opening relative to eye distance) against a calibrated neutral
face, smoothed with a One Euro filter. The same app on an iPhone is the companion (device family 1,2; iPhones only show the
companion screen) and streams newline-delimited JSON over Bonjour (`_loweyface._tcp`) — no entitlements beyond local network.

**D66 — Hesham's character is a puppet built from parts on the Humanoid standard.** The builder makes low-poly parts
under joints named with humanoid bones. `PuppetRig` turns the joints into a skeleton (arms straightened to a T-pose for
retargeting only), so every humanoid clip — the ten built-in ones and any imported Mixamo-style clip — plays on it through
the existing retargeter; poses are written back onto the joint objects. The recipe is stored on the character so it can
be reopened and rebuilt (the root keeps its id and animation).

**D67 — AI speaks "actions", compiled in Core.** Scene Script v2 adds friendly actions (names instead of ids, word times,
presets, camera moves, characters, look…) that `ScriptCompiler` turns into ordinary commands against the current document —
one undo step, with a plain-language preview. Errors name the action and what exists, so a model can correct itself. The
same language is served by the bridge, used by lowey-mcp and the skills, and by the app's own samples (the narrated Enigma
story and the welcome island are scripts).

**D68 — The LAN Bridge: HTTP/1.1 + WebSocket on Network.framework; parsing, auth and routing in Core.** Off by default;
answers only private and link-local addresses; pairing with a 6-digit code (ten wrong guesses change it); bearer tokens.
Scripts from the bridge wait for Hesham's approval on the iPad (preview sheet) unless he turns on auto-apply.

**D69 — lowey-mcp and lowey-link are Python (official MCP Python SDK 2.x).** The laptop already runs Python for Blender;
the SDK makes each tool a typed function. Tools map 1:1 onto actions; replies are a few lines (token-cheap). Tested in CI
against a fake bridge.

**D70 — Projects travel as `.loweypack` (a stored zip).** Core writes and reads it (with CRC checks), so packaging is
tested on Linux; library assets are embedded first. Archive moves projects to `Projects/Archive`.

**D71 — Diagnostics stay on the iPad.** A rotating log, MetricKit diagnostic payloads (crashes, hangs) delivered on the
next launch, an "ended unexpectedly" marker, and "Export diagnostics" (a zip Hesham chooses to share). No telemetry.

**D72 — Thermal-aware preview.** At `.serious` the stage renders at ⅔ scale and skips depth effects; at `.critical`, 1×.
Exports render offscreen and are unaffected.

**D73 — Performance pass: what was done and what was deliberately not.** Done: particles as a few banded meshes (D59),
shared meshes and materials for repeated objects (D21), the post pass switched off when unused (D60), overlays redrawn
only when they change, thermal-aware preview (D72). Not done yet: distance LODs and texture compression for imported
models, and `MeshInstancesComponent` for thousands of static copies — the 60 fps budget scene (~300 low-poly objects,
3 characters, 2 particle systems) has to be profiled on the iPad Air first ("profile before optimizing"); CI simulators
can't measure GPU frame times. Show FPS & stats is in the scene menu for that.

## Phase 4

**D74 — The house character is traced, not redrawn.** `assets/avatar/trace_drawing.py` measures Hesham's drawing
(silhouette rows, every stroke as a contour, Poisson-inflated meshes for non-round parts) and the Blender build uses only
those numbers. The drawing stays the source of truth; the in-app blob uses the same measurements.

**D75 — Blobs are ordinary scene objects.** Lathes, slabs and ribbons (existing drawing kinds), so the face rig, keys,
Perform, scripts and exports needed no special cases. Face parts are true size; `faceRange` tells the rig how far.

**D76 — Cartoon timing is a spring convolution.** A blob's dials are the keyed target convolved with a damped spring's
impulse response over the last ~1.5 s. Deterministic (preview = export, any frame in any order), no simulation state.
Poses are keyed as steps; the springs make the in-betweens, overshoot and settle.

**D77 — Rubber hose over rigs.** Arms are bezier tubes rebuilt from shoulder and hand each frame, in the hose's own
space (so tilting or floating never changes their shape) and only when an end moved.

**D78 — RealityKit render callbacks wait for the first frames.** Installing `renderCallbacks.postProcess` before the
stage renders traps (EXC_BREAKPOINT); the stage now waits for two scene updates. Found by a UI test that plays the tour.

**D79 — Exports assume the GPU can disappear.** Every render has a deadline; the exporter waits while the app is in
the background; the idle timer is off during exports.

**D80 — Video overlays are keyed frames.** A video overlay becomes `file#t=seconds` at layout time; the export decodes
that exact frame, the stage the nearest one (never waiting). Manim renders arrive as ProRes 4444 with alpha, packed with
PyAV (ships with Manim), because the laptop is Windows (no HEVC-with-alpha encoder).

**D81 — One skill, an orchestrator and modules.** `skills/lowey/SKILL.md` routes and holds the rules; each module does
one job. Adding a capability is adding a module.

## v1.4

**D82 — Rotation pivots are origins.** One object turns around its own pivot; several around the mean of their pivots.
Both stay fixed while turning (a bounding-box centre moves as the box turns). Rings are picked on screen by distance to
the drawn ring, not by collision shapes.

**D83 — Face channels use the mirror's sides.** `blinkLeft` is the eye on the left of the (mirrored) picture, turns and
tilts likewise; trackers' left/right labels aren't trusted (they swap in mirrored pictures). The Mirror switch flips
everything in one place. Rest pose (head, gaze, dials) is subtracted; blinks, jaw and hands are absolute.

**D84 — Media cards are objects, overlays are graphics.** Pictures and videos default to a `card` object in the world;
overlays stay for graphics that belong to the frame (transparent Manim). Card textures change only when the frame does.

**D85 — Timeline rows scroll under our own gesture.** A SwiftUI `ScrollView` loses its pan to a `DragGesture` on its
content (iPadOS 18+), and the lanes need that drag. The lanes decide once per drag: keys, box, time or rows.


**D86 — The bridge keeps the app alive with silent audio.** iOS suspends a background app within seconds; a VPN-style
status icon needs a Network Extension (paid developer account), and Live Activities don't show on iPad. The app is
sideloaded, so it uses the audio background mode: while the bridge is on and the app is away it plays silence mixed with
other audio, and posts a quiet "Bridge on" notification. Drawing (snapshots, export) still waits for the foreground.

## 2.0 — Remaster, phase 1

**R1 — `legacy/v1` starts at the v1.4.3 tip, not v1.4.2.** 1.4.3 shipped after the remaster was specified; the legacy
branch and the `v1-final` tag point at what users actually have.

**R2 — Shared code lives in hmm-kit, a public package pulled in as a git subtree (`Packages/HmmKit`).** Public, so the
subtree needs no credentials in CI and its own CI runs on free minutes. Lowey depends on its products and never edits
the subtree in place: changes go to hmm-kit first, then `chore: sync hmm-kit`.

**R3 — Four layers: LoweyCore → LoweyEngine → LoweyFeatures → App** (supersedes D1). Core stays pure Swift and
Linux-tested. The engine owns Metal, import, export, the stage view, audio, face capture and scripting. Features are
the SwiftUI editor. The app target is only the entry point, menu commands, background tasks and the widget.

**R4 — LoweyRender 2 on Metal replaces RealityKit** (supersedes D15 and the 1.x rendering decisions). One renderer
draws the stage, thumbnails and every export, so the preview is the export (tested pixel for pixel). RealityKit
couldn't give lines, a Look system, exact picking, deterministic frames or control over the compositor.

**R5 — glTF is read by a pure-Swift reader in LoweyCore** (GLTFKit2 removed). It runs in the Linux tests, needs no
binary dependency, and the importer and the skeleton reader share one parser.

**R6 — Only the sun casts shadows (two cascades); point and spot lights don't.** Up to 16 of them light a frame (the
nearest to the camera win). Shadowed local lights cost a shadow map each; the Looks get their mood from the sun,
contact shading and lines.

**R7 — Metal front faces are counter-clockwise.** Every mesh in LoweyCore winds counter-clockwise; with Metal's
default (clockwise) every visible face read as a back face, normals flipped and objects shadowed themselves.

**R8 — Golden images are recorded on the CI simulator and reviewed before they're committed.** The simulator's GPU
differs from a device's, so goldens come from where they're checked: a missing or changed golden fails the test and
uploads the render; once it looks right it's committed. Tolerance: 1 % of pixels may differ by more than 24 levels.

**R9 — Spike results.** Metal and 4× MSAA work in the CI iPad simulator. The simulator's encoder has no 4K HEVC and
drops out (or hangs the test runner) at 4K and 1440p H.264, so the simulator runs the export pipeline at 1080p and
4K HEVC is on the device checklist. GPU
skinning works there (walker golden). MetalFX is device-only; the simulator falls back to bilinear scaling.

**R10 — 1.x projects open in the Clay Look** (Low-poly when the project used flat shading): the closest to the
RealityKit picture, so nothing looks broken after the update. Choosing another Look is one tap.

**R11 — Features are folders in one target, and folders never reference each other.** One SwiftPM target keeps build
times down; `Tools/check-feature-boundaries.py` (in CI) fails when a feature names a top-level type of another.
Workspace is shared by all (models, session API, controls); Shell is the composition root and may use every feature.
Theater settings and the tour go through `AppModel`, not across features.

**R12 — One editor, no modes, in Procreate Dreams' grammar.** Five modes hid tools behind a switcher. Now the Stage
sits over the Timeline; document things are in the top-left cluster, making tools in the top-right one, two context
sliders and undo / redo in a sidebar (mirrorable), and the inspector appears only while something is selected.
⌘1–5 open the Select, Build, Draw, Transform and Look panels.

**R13 — Auto-key belongs to the timeline's Keyframe mode; Compose (the default) never creates keys.** In 1.x an
accidental drag in Animate mode made keys nobody asked for.

**R14 — Universal gestures (two-, three- and four-finger taps, two-finger hold) live on hmm-kit's gesture layer at
the window**, so they work over panels and sheets the same way; the stage no longer handles them.

**R15 — The joystick stays, optional and off by default** (Transform ▸ Joystick). Direct touch covers most moves; the
game-controller Fly performer is phase 2.

**R16 — Selection is drawn as a silhouette outline, not a box.** It reads on any shape and in every Look, and comes
from the ID buffer the picking already has.

**R17 — Project cards play a looping GIF** (8 fps, 2.4 s) through the shot camera, next to a still PNG thumbnail.

**R18 — Export runs on the main actor, encoders on the caller's actor.** `ExportSession` is `@MainActor`, and HmmMedia
builds with `NonisolatedNonsendingByDefault`, so its async encoder API runs where it's called and pixel buffers are
never sent across actors (Swift 6, no warnings).

**R19 — Background export is a `BGContinuedProcessingTask`** (iPadOS 26), with GPU access where the device grants it;
otherwise the export waits while the app is away and continues when it's back (as in 1.x). Progress goes to a Live
Activity where the system shows them, and a notification says when it's done either way.

**R20 — Exports are verified before they're handed over** (frame count, size, length, audio track, alpha) by
HmmMedia's inspector. A broken file is an error, not a share sheet.

**R21 — The bridge is off until it's turned on, pairs with a one-time code and keeps tokens in the Keychain**
(supersedes the 1.x bridge decisions and D86's "on by default"). The permanent `000000` code and `lowey-mcp --public`
are gone, and so are the tunnel modes: a creative tool shouldn't be an open door on café Wi-Fi. Unpaired requests get
401, non-local ones 403, a pairing attempt with no code on screen 409 (tested).

**R22 — The silent-audio keep-alive (D86) stays for sideloaded builds only.** Feature flags in Info.plist
(`LoweyAIBridge`, `LoweyBackgroundBridge`) switch the bridge and the keep-alive off in the App Store configuration.

**R23 — LoweyCore's 1.x bridge code is removed.** Its HTTP parser and `BridgeAuth` (with the permanent code) are
replaced by HmmBridge; Core keeps only the compact scene, transcript and asset summaries the bridge sends.

**R24 — iCloud only in the App Store configuration.** A sideloaded build can't carry the iCloud entitlement, so
`DocumentLocator` falls back to on-device storage and says so.

**R25 — The Night Market benchmark uses a generated walker** (`BenchmarkFigure`, an 11-bone box figure with a walk
cycle, made in LoweyCore and seeded into the model library), so it needs nothing from the user's library and runs the
same everywhere. Target on a device: p95 frame time ≤ 8.3 ms at render scale ≥ 0.85.

**R26 — Finish ▸ Outline adds lines over any Look.** Lines are a renderer pass, so any Look can have them, not only
Ink and Comic.

**R27 — Lint at the STUDIO limits, strictly.** SwiftLint runs with `--strict`: files ≤ 500 lines, type bodies ≤ 350,
functions ≤ 60, complexity ≤ 12 (switch cases don't count: a switch over an enum is one decision, not twelve), no force
unwraps outside tests. Long lines inside multi-line strings are allowed: they're Scene Script and JavaScript examples
shown to people and to the AI, and wrapping JSON objects mid-line would make them harder to copy.

**R28 — Colour literals go through `RGBA.hex(_:)`,** which takes a `StaticString` and falls back to magenta, so a
mistyped literal shows on screen instead of crashing, and there are no force unwraps.

**R29 — Script time limits are checked at every API call.** JavaScriptCore has no public execution time limit on
iOS, so a loop that never calls `lowey` or `scene` can't be stopped (BACKLOG). Every loop that builds anything calls
the API, and those stop.

**R30 — Flipbook tracks are phase 2, and so is the Mac target.** Phase 1 rebuilds the engine and the editor; LoweyCore
and hmm-kit already compile for macOS.

**R31 — The 1.x app's render and export tests were ported, not dropped.** They moved from the hosted app tests to
LoweyEngine's tests on LoweyRender 2 (export, scene, library and script tests), with the animal-pack fixtures. Two
checks were 1.x-specific and are gone: the RealityKit depth-pass calibration (the Metal renderer has a real depth
buffer) and the RealityKit post-processing install timing.

**R32 — CI retries a failing engine test up to twice.** The simulator's software video encoder now and then stops
accepting frames or hangs the test runner, whatever the size (a 160 × 90 export did it once), and the same test passes
on the next run. Retrying keeps CI meaningful without hiding a real failure: a test that fails three times in a row
still fails the build, and every retry shows in the log and the result bundle. Video encoding itself is checked on a
device (the PR checklist).

**R33 — The UI smoke tests get the engine's retries, and both simulator jobs a second attempt.** On the same commit
each smoke test has passed and failed: the simulator now and then can't terminate the app between tests, or stops
answering a UI query (the app idle, the query never returning). Each UI test now gets up to three tries, like the
engine tests (R32). When the test runner itself hangs before it connects, no per-test retry runs, so the engine and
UI steps run `xcodebuild test` a second time; the build is incremental, so the second attempt costs only the tests.
A test that fails every time still fails the build, and each retry and attempt shows in the log.

## 2.0 — Remaster, phase 2

**R34 — Ink strokes are a drawing style, meshed toward the camera every frame.** `DrawingRecipe.Style.ink` keeps the
strokes (points + pressure widths) like the solid styles, so guides, mirror, Scene Scripts, export and undo all work
unchanged. The renderer builds each ink drawing as flat ribbons facing the frame's camera (`InkMesher`, cached by
eye position and reveal), unlit in the object's colour, with an ID flag that keeps the line pass from outlining
them: they are lines already. A billboarding vertex shader would have needed its own prepass, shading and shadow
pipelines for a few hundred vertices per drawing. Strokes join the selected ink drawing (a new one starts when
nothing ink is selected), like drawing on the current layer; `reveal` writes a drawing on.
