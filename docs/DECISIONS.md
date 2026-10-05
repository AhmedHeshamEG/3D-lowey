# Decisions

Every non-obvious choice, with the reason. D1–D86 are the 1.x decisions, kept as history; where 2.0 replaced one,
the 2.0 entry (R…) says so. Maquette's decisions continue from D-87, one section per phase. What the product is lives in [SPEC.md](SPEC.md); how it's built in
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

**R35 — Frame rates resolve per object, every frame, in one place (`FrameRates`).** Own rate (keyable) → nearest
ancestor's → characters take their Look's (Comic: twos) → cameras ones → the project's. Phase 1 stored a Look frame
rate that nothing read; now it decides, and an animated `stepping` lets a character drop to twos for one beat.

**R36 — Flipbooks are timeline tracks drawn as 2D, blended in the composite.** A track is drawings with hold lengths
(the Dreams model) anchored to the camera (frame-height units, so 16:9 and 9:16 share one drawing) or to an object
(metres on the camera-facing plane through its pivot, so it shrinks with distance). Normal tracks draw into the
overlay image under titles and captions; multiply, screen and add tracks get one layer each, blended with the shot in
sRGB like a painting app. Drawing past the last drawing holds it to the playhead and starts a new one, so drawing at
the playhead is how you animate. The drawn-effects library is strokes too, so every effect stays editable. Speed lines
are parallel streaks behind the mover (Western comic), not radial focus lines.

**R37 — Motion paths, onion skin and smears are views of the keys, not new data.** Paths and smears read keys only
(object + parents, `MotionPath`), so they're cheap enough to compute every frame and the same in every export; ghosts
evaluate the whole scene at the neighbouring keys and are cached until the document or playhead frame changes. Ghosts
skip the prepass (never picked, outlined or shadowed) and only appear with the select tool.

**R38 — The graph editor edits the same per-segment easing the timeline already stored.** A segment's tangent
handles are its cubic-Bézier easing (normalised between the two keys), so the graph, the Easing menu and Scene Scripts
all speak one model and nothing old needed migrating. Rotations are drawn as the three turn angles.

**R39 — Poses and IK handles are for Blobs and built characters; imported rigs pose through their clips.** Blob and
puppet poses are values on objects the user owns (dials, joint rotations), so a pose is a set of property changes
(keyed in Keyframe mode) and a mirror is a swap of left and right. Imported skinned rigs have no joint objects to key;
their library of poses is their clip list. Poses are stored on the character (`poseLibrary`), so they travel with it.

**R40 — Characters get an inverted-hull outline on top of the Look's lines; face decals are flat.** The hull (mesh
pushed out along its normals, back faces, Look line colour, width scaled by the character and the Look's line width)
gives the stable, thick silhouette the line pass can't promise on a moving character. Eyes, brows, mouth, cheeks and
the hover glow are drawn unlit, like paint on the head, and get no hull; the line pass still draws their inner lines.

**R41 — Blob measurements are generated from `trace.json` and checked in CI.** `Tools/gen-blob-measurements.py`
reproduces the head profile, face placements and body size from the trace with the same rules as the Blender build
(the numbers came out identical to the hand-copied ones), writes `BlobCharacter+Measurements.swift`, and CI fails if
the committed file drifts. A Swift build plugin would have needed Python inside the package build on every machine;
a checked generated file gives the same guarantee. The smirk strokes stay authored: they are a design simplification
drawn over the traced mouth, not a measurement.

**R42 — Built-in clips work on all three character types.** Built and imported characters retarget the humanoid
clips; a Blob, which has no skeleton, plays the same ten clips written for its dials (hand reach, head turn, jaw,
squash, lift, lean), on the same clip tracks with the same crossfades, added on top of keys and face performances.

**R43 — Fly is a flight model with a short ease, fed by the on-screen sticks or any game controller.** Velocity and
turn rates follow the sticks with a time constant (the sidebar's Ease), moves stay level with the ground and tilt
stops short of straight up, so a flown take reads as an operator's move. It writes the camera through the same path
as the Director view's touch gestures: one undo step per flight, or the camera's keys while Perform records. A on a
controller records or stops a take, B stops flying.

**R44 — The Kit: 355 CC0 assets in nine Sets, all in the app (27 MB).** `Tools/fetch-kit.py` downloads Kenney packs
from kenney.nl and Quaternius packs through itch.io's free-download flow (their official pages), refuses any pack
whose own licence file doesn't say CC0, and converts the curated assets (`Tools/kit/curation.json`) into
`.loweyasset` folders: a GLB scaled to metres from each pack's reference asset of known size, pivot at the base
centre, facing +Z, toon-ready (normal, roughness and occlusion maps dropped, colour maps at most 512 px: the toon
Looks don't use the rest, and the Quaternius props shrank from 300 MB to 4 MB), plus `asset.json` with the semantic
metadata (real size, front, the surfaces things can stand on, tags, set, category, rig, clips, source, licence).
Faceted and smooth variants aren't separate files: every Look picks its normals in the shader. Thumbnails are
rendered by the app in the Ink Look the first time a tile shows and then cached, so they always match the renderer.
The whole Kit fits the 150 MB budget with room to spare, so the Background Assets spike's fallback is taken: no
download path (Apple-hosted Background Assets can't be exercised from CI or a sideloaded build anyway). CI checks the
built Kit against the curation, its licences and the budget. Kit assets live in the library manifest at runtime
only (`kit.` ids, never written to `library.json`), so projects using them open anywhere the app is installed.

**R45 — The foley set is synthesised, not sampled.** Whoosh, pop, impact, click and swell are generated by LoweyCore
(seeded noise, filters and oscillators shaped to the move each one sells), written once per project as WAV clips on
the sound-effects track. They're ours, so CC0 by construction; identical on every device; and weigh nothing in the
app. Each has a hit time, so attaching one to a word puts the whoosh's peak (not its start) on the word.

**R46 — The relation solver came before the samples.** Phase 2 lists the samples (step 7) before Scene Script v3
(step 9), but samples built from the Kit should be placed the way the AI will place things: by relation, with the
Kit's surfaces and fronts. So `RelationSolver` and the v3 verbs (`place … relation`, `add … asset`, `scaleTo`,
`recolor`) landed first, and the samples are built with them. Left and right are as seen from the reference's front
(for something facing the camera, screen left and right). Things put `on` furniture face the way it faces. Every
relation grounds what it places and slides it off anything it would intersect; `on` looks for a free spot on the
surface, nearest its middle. v2 scripts upgrade on compile (aliases become verbs, v2's `place` becomes `add asset`).

**R47 — The shipped samples are new, built from the Kit; the 1.x samples stay as fixtures.** The Theater's Welcome
island (Ink, golden hour) and Enigma story (a desk at night in Ink, a room of computers in Comic on twos, a cave robot
in Sketch with one accent, and the narrated story cut on the voiceover's words) are Scene Script v3 built with the
Kit and the relation solver, so they show what the app and the AI actually make. A Core test builds them from the real
Kit and fails if anything floats or intersects. The primitive-built 1.x samples (`IslandSample`, `EnigmaSample` and
its opening and story) keep driving the engine, export and file-format tests, which check exact names and frames;
rewriting those around Kit models would test less, not more.

**R48 — Perception measures geometry in Core and colour from the render.** `observe` (ShotReport) and
`contact_sheet` are pure Swift in LoweyCore (`Perception/`), so every number is unit-tested on Linux against scenes
where the answer is known (a floating cube reports `grounded: false` and a 100 cm gap). Coverage and visible % come
from a small depth-tested CPU rasteriser (about 320 × 180) of the meshes the renderer drew (Core's own meshes, else
boxes, in tests): exact enough to say "the lamp is 26% visible", deterministic everywhere. Contrast (ΔL* in the
squinted value view), silhouette separation (each outline pixel against the pixel a short step out, past the ink
line and glow the Looks draw on the edge), palette and the light read come from the rendered pixels; without them
those rubric lines are `skipped`, never guessed. Intersections compare surfaces, not boxes (a chair tucked under a
desk isn't intersecting), and set pieces (floors, walls, terrain over 6 m or 40% of the frame) may overlap each other.
Things in the air on purpose carry `airborne` (`above` sets it; 3D words count as signs). Clutter counts copies of one
model once (nine desks read as one pattern). Kit models may be half to twice their real size before Scale fails.
Focus passes when the subject is the accent, the biggest, the brightest or the most contrasty thing in frame. Motion
is measured on screen with velocities over a 0.17 s window, so animation on twos or fours isn't read as stop-start;
anticipation isn't measured (it's in the critique module's checklist instead). The Engine adds the pictures: the
camera view with set-of-marks, top/front/side diagrams from an orthographic camera with the shot camera drawn on,
the value view, and the subject's silhouette from the ID buffer. Turning perception on the shipped samples found a
chair blocking the desk push-in, Hesham hiding the one lit screen, the cave camera inside a rock and a chest scaled to
a third of its size; all four were fixed.

**R49 — MCP v2 is sixteen tools over one `build`.** The laptop's `hmm-bridge mcp` exposes the sixteen tools of PROMPT
§12.2. Seven of them (`frame_shot`, `light`, `set_look`, `animate`, `camera_move`, `add_overlay`, `flipbook`) are
small, typed front doors that each send one Scene Script v3 batch to `POST /v2/build`, so every change, however it
arrives, is the same thing on the iPad: one Proposal with a preview thumbnail, one undo step, and a reply carrying an
`observe` of the result. That needed three new v3 verbs in Core — `frameShot` (the camera solver), `lighting` (six
recipes placed relative to the shot camera; re-lighting replaces the recipe's lamps) and `intent` (enter, exit,
emphasise, react, walk_to, look_at, talk, idle, resolved to presets, clips, expressions, lip sync, keys and a look-at
behaviour) — and `look` learned the Look itself and per-object Looks. A dry run returns a `proposal_id` that `commit`
proposes for real, recompiled against the scene as it is then. The v1 routes stay for 1.x laptops; the package is
`hmm-bridge` (its CLI is `hmm-bridge`, and `lowey-link` / `lowey-mcp` remain as aliases).
`schemas/scene-script.v3.schema.json` lists every verb with its fields, and a Core test fails if the compiler and the
schema disagree.

**R50 — The skill is rewritten around looking; its evals score what the app measures.** The 1.x skill is archived in
`skills/_legacy/lowey`. The new one follows PROMPT §12.3: a director loop in `SKILL.md` (read → beats → shot list →
build → observe → critique → fix, at most three rounds; animate → contact sheet → fix, at most two), short modules,
style notes with references and reasons, `lessons.md` seeded with the 1.x failures and the bugs perception found in
the 2.0 samples. `reference/tools.md` is generated from the MCP server's own schemas (`Tools/gen-skill-tools.py`, checked
in CI). `evals/run_evals.py` drives Claude through the same sixteen tools against a real app, one fresh scene per brief
(the bridge gained `POST /v2/scenes/new` for this, outside the sixteen), and scores each brief from `observe` and
`contact_sheet` rather than from the model's own account; a Ground or Scale fail fails a brief whatever its score.
Voiceover briefs get a silent clip and their words through a new `transcript` verb (known words and timings on a
voiceover — also how a laptop TTS can sync). The evals are not run in CI: it has no paired iPad, no simulator bridge
reachable from a model, and no API key. The harness's parsing, scoring and bookkeeping are tested; the runs are
Hesham's to do on his iPad.

**R51 — Localisation, accessibility, windows and restoration (2.0).** English, Italian and Arabic live in one String
Catalog in the app (`App/Resources/Localizable.xcstrings`, plus `InfoPlist.xcstrings` for the permission prompts).
`Tools/strings.py` finds the chrome strings in the code (literals given to SwiftUI and the hmm. components, toasts,
accessibility labels, and the titles enums return for display) and CI fails when one is missing or untranslated.
hmm-kit's components now look their titles up in the app's catalog (changed upstream, then synced), so passing a
String to `HmmPillButton` localises like a literal; toasts take a `String.LocalizationValue`. Interpolated strings are
keyed the way SwiftUI keys them (integers `%lld`, the rest `%@`); English plurals built with `?:` inside a string are
not in the catalog and stay English. Arabic mirrors the chrome; the timeline and the stage's overlays stay left to
right (time and frame space aren't text). Accessibility: every tap target is a button to VoiceOver, panels scroll
under large Dynamic Type and numbers scale too, animations go through the Reduce Motion-aware helpers, and Increase
Contrast gets opaque outlined chrome like Reduce Transparency. Windows: one window edits (a stage edits one project
at a time); another main window offers to take over or become a monitor, and the Monitor window (Actions ▸ Monitor,
⌥⌘N) shows the shot live through its camera as it exports — beside the editor in Stage Manager or on an external
display. The app reopens the project, scene, playhead, panel, Director view and timeline state it was left in.

**R52 — App Store readiness without a Mac.** The icon follows the studio rule: one glyph on the accent (a faceted,
ink-outlined cube on #FFB847), full bleed so the system's corners match the other apps, with a dark variant; it's
drawn by `Tools/make_icon.py`. App Store screenshots come from UI tests on CI's iPad 13" and largest-iPhone
simulators, with a launch flag that hides the UI-test overlays. The App Store variant is made by the TestFlight job
from the same project by switching three Info.plist values (bridge off, no background audio) rather than keeping a
second target. The TestFlight upload signs with an App Store Connect API key and is skipped, not failed, when the
secrets aren't set. 2.0 is paid upfront: the StoreKit configuration exists for testing later purchases and is empty.

## Maquette 0.1 — M1, foundation & feel

**D-87 — 3D-lowey becomes Maquette; code names stay.** Display name, bundle ids `studio.h.maquette` (+ `.widgets`,
`.uitests`), app group `group.studio.h` (entitlement on the app and the widget), projects `.maquette` and packs
`.maquettepack`, licence "All rights reserved", the GitHub repo renamed to `maquette`. The modules, the Xcode target
and the bridge's wire name stay `Lowey`/`lowey` (CONTEXT §10: code names may stay), and the manifest's `app` stays
`"lowey"` so 2.0 and Maquette read each other's packages. A new bundle id is a new app with its own sandbox, so
3D-lowey's `.lowey` and `.loweypack` files are still declared, listed and imported. Maquette's phase tags are two-part
(`v0.1` … `v0.8`, then `v1.0.0`) beside 3D-lowey's three-part history tags, and its releases are marked Latest
explicitly (by version alone, 3D-lowey v2.0.0 would stay Latest). *Rejected:* keeping `.lowey` (the Files app shows
the extension); renaming every module (churn with no user-visible gain).

**D-88 — The journal records history ops, not just commands.** A line is `perform` (command + coalescing key),
`endCoalescing`, `begin/end/cancelGroup`, `undo` or `redo`; replaying them through `CommandStack.replay` rebuilds the
document *and* the undo stack exactly, including merged gestures and named groups. One journal per scene
(`history/<scene-id>/`), because an edit session is one scene. *Rejected:* journaling forward commands only (undo and
redo after a relaunch couldn't be rebuilt); one journal per project (scenes are opened and edited one at a time).

**D-89 — Checkpoints store each undo step once, by reference.** A checkpoint writes the snapshot and a list of
`{file, offset, length}` refs into append-only `entries/<n>.jsonl`; steps already stored are reused, files nothing
points at are removed. Opening reads the newest 64 steps; older ones load when undo reaches them (16 left). Opening
50 000 commands with a 150-change tail takes 23 ms in CI's Linux container (the test allows 1.5 s; the device budget
is 500 ms). *Rejected:* writing the whole 500-step stack into every checkpoint (megabytes rewritten every 5 s);
rebuilding the stack by replaying every segment (50 000 lines decoded on open).

**D-90 — Group commit within 50 ms, on a serial queue.** `record` buffers ops and schedules one write; a checkpoint
takes the ops recorded before it at call time (a test caught the queue flushing later ops into the old segment, behind
the checkpoint's sequence number, which lost them on replay). Leaving the screen and closing flush and `fsync`.
*Rejected:* writing on the main thread per change (a drag is 120 changes a second); the 100 ms the CONTEXT allows
(a shorter window costs nothing).

**D-91 — `project.json` and the scene file are written at every checkpoint, from the checkpoint's own state.** They
stay the readable surface (`docs/PROJECT_FORMAT.md`). Opening merges: the journal owns this scene's changes;
`project.json` owns the scene list and the project name, and its project Look wins when this scene replayed nothing
and the file is newer (another scene changed it since). *Rejected:* the journal as the only truth (scripts, MCP
clients and 2.0 read the files); writing the files on every change (the old debounce, the bug this phase removes).

**D-92 — Journal ops migrate by document schema.** A segment's header carries the `LoweySchema` version its commands
were written in; `ProjectHistory.opMigrations` upgrades older lines, and a Core test fails when a schema bump has no op
migration. The first journals are schema 4.

**D-93 — Going back in the history scrubber is undo, with the future kept as a version.** "Go back here" saves the
current state as an automatic version, then undoes to the moment; redo still goes forward until the next change,
which starts the new branch. Restoring a version is one undo step (`replaceScene`, a new command). Automatic versions:
each time a scene opens and each hour of work, the newest 40 kept; named ones stay. *Rejected:* a branch tree to
navigate (a decision wall; the versions list already holds every abandoned future).

**D-94 — The hover point is drawn in the stage's editor pass.** Two spheres (a dark rim, a light centre) just past the
near plane on the ray through the tip, sized from the view's height so they're 2.5 pt at any distance; the brush ring
faces the camera and shows only while a size slider moves (under the tip, or mid-stage when the Pencil is away). The
setting rules every tool. Hover position is no longer observed state, so hovering doesn't re-run SwiftUI. *Rejected:*
the SwiftUI overlay (a frame late); a CPU-drawn overlay image (a texture upload per hover event).

**D-95 — Device tiers set three preview knobs.** `DeviceTier` (hmm-kit) is A for GPU family ≥ 7 with ≥ 7.5 GB (M iPads
and the 8 GB A17 Pro mini), B for family ≥ 7 or ≥ 4.5 GB, C below; `-device-tier B` forces one. `PreviewQuality`
gives the render-scale range (A 0.66–1, B 0.6–0.85, C 0.5–0.7) and the sun's shadow map (2048/1536/1024); the frame
budget comes from the screen (most iPads are 60 Hz, and holding them to 120 fps lowered their scale for nothing).
Exports, stills and thumbnails always use `.full`. Lines stay native on every tier (crisp edges are the Looks). MSAA
isn't a knob: pipeline states are built for the device's sample count. There's no simulation-rate knob yet: 2.0's
simulations bake to keys at the timeline's rate, so nothing simulates live (it arrives with dangle physics and
mechanisms). The "Tier B/C configuration" is the Engine suite rendering every Look with each tier's quality: simulators
all use the Mac's GPU, so a Tier B simulator would test nothing more. *Rejected:* a model-identifier table (breaks on
every new iPad).

**D-96 — The benchmark's pass rule follows the screen.** Frames are timed present to present, so a perfect run sits at
the screen's interval with vsync jitter around it: p95 ≤ 1.2 intervals (10 ms at 120 Hz, 20 ms at 60 Hz) means no
frame dropped. The minimum render scale is 55% up the tier's range (0.85 at A). A Tier B run is offered on A iPads.
*Rejected:* the 2.0 rule (p95 ≤ 8.3 ms): Hesham's iPad Air M3 is 60 Hz and could never pass it.

**D-97 — The load meter measures work, not intervals.** The stage redraws on demand, so the interval between frames
says nothing when idle; the meter takes max(GPU time, CPU encode time) against the budget, plus a scene cost
(triangles and draw calls against what the tier draws comfortably: first estimates, refined by the device
benchmarks). The chip shows after a second at 85% and leaves after a second under 70%. Its fixes are the ones that
exist: a lighter preview for the session, or Adaptive resolution when Full-resolution stage is on. *Rejected:*
"instance repeats" (the renderer already instances every run of one mesh) and "simplify" (no simplify operation until
modelling).

**D-98 — The M1 performance pass was a code read of the per-frame paths.** Fixed: smears scanned and copied every
object on every frame (now cached per edit and playhead; hovering redraws at 120 Hz with neither changing); the
stroke preview was uploaded to the GPU every frame (now once per shape); each frame allocated a `Task` to report its
time (now a main-queue hop). Signposts mark "Build frame" and "Encode frame" for Instruments. GPU time can only be
measured on the device: the benchmark JSON in the device checklist is the gate (CONTEXT §6).

**D-99 — CI runs once per change, routed by what it touches.** PRs and main only (a PR used to run twice: as a push
and as a PR). A `changes` job sends docs-only changes nowhere, Core-only changes to lint and Linux, Engine changes to
the render tests, and Features/App changes to feature tests, the app build and the UI tests; every merge to main runs
everything, so a tagged commit passed the UI tests. The app job no longer waits for the Engine job (it builds the same
sources itself). DerivedData is cached per job. `CI result` is the one required check (skipped jobs count as passed),
so auto-merge waits for it. The release workflow skips commits marked `[build-only]`. Timings: D-100.

**D-100 — CI wall time, measured.** Before (2.0's workflow): 46.0 min for a push to main, 45.8 min for a PR, and every
PR ran twice (push + PR). After, on this phase's PR with every job routed in (Core, kit, Engine, Features and App all
changed): **21.5 min**, once. The slowest job is now the Engine render tests (21 min); the app build and UI tests
finish in 12 min beside it instead of 28 min after it. A docs-only change runs only the routing job and `CI result`.

## Maquette 0.2 — M2, the canvas owns the screen

**D-101 — The making tools are Model, Draw, Paint, Animate and Cast.** Model holds what 2.0 called Build (shapes,
lights, cameras, words, marks on the frame, effects, screen effects, and now photos and videos), the Library (the
Kit and your models) and snapping, as three pages; the modelling tools of M3 join it. Draw keeps ink, solid shapes
and flipbooks. Paint has the Shadow Brush and Scatter, which already paint (on objects and over the ground); colour
painting joins them in M6. Animate has no panel: it calls the whole timeline (again: back to the transport). Cast is
unchanged. *Rejected:* the Library as a sixth button (CONTEXT allows five); Animate as a panel (it would repeat the
timeline's header); hiding Paint until M6 (it has real tools today, so it isn't empty).

**D-102 — One home per function, and time lives in the timeline.** The audit (docs/LAYOUT.md) found six controls in
two places: Actions ▸ Sound and Voiceover beside the timeline's Sound and words, Actions ▸ Timeline beside the
timeline menu's settings, Transform's Drop to the ground beside the inspector's, the palette's own Pick beside the
sidebar's, Build's "Open the library" beside the Library button. Each now has one home; sound and the timeline's
settings stay in the timeline, which the corner control calls in one tap. The menu bar and the keyboard are other
ways in, not other homes. *Rejected:* keeping Sound in Actions for discoverability (the tour now says time is called
from Animate and the corner control).

**D-103 — The timeline is on call: hidden, the slim transport, or whole.** A new project shows no timeline. The
corner control (bottom right, beside the views) calls the transport and sends the timeline away; Animate opens it
whole and, tapped again, folds it to the transport. The divider resizes it; dragged down past the transport it goes
away. Each project remembers which of the three it was and its height. *Rejected:* one global height (2.0's
`@AppStorage`): a character piece and an animation want different room.

**D-104 — How a project shows lives in `workspace.json`, beside `project.json`.** The timeline's presence and
height, snapping, the grid, the starter template and its first panel. It's view state, not the project, so it stays
out of the history journal and undo, is written 0.4 s after a change (and when the project closes), and falls back
to the defaults when missing, damaged or from the future. It travels with the package (copies, `.maquettepack`,
iCloud Drive). *Rejected:* a `project.json` field (every resize would be a command in the journal and an undo step);
`UserDefaults` keyed by project (it wouldn't follow the project to another device).

**D-105 — The inspector floats beside the selection.** hmm-kit's `HmmFloatingPlacement` keeps it on its side while
it fits, flips it at the screen's edge and, when neither side fits, covers as little as it can. The selection's
box is projected onto the stage at once when the selection changes, 0.12 s after edits to it pause and 0.15 s after
the camera stops moving, so a drag or an orbit doesn't re-run SwiftUI 120 times a second; the inspector glides over
when things come to rest. It stays
in the room the chrome leaves (below the clusters, clear of the sidebar, an open panel and the bottom row), docks to
the edge when the selection is off screen, and hides while a making tool's panel is open. *Rejected:* tracking every
frame (layout per frame for a panel nobody reads mid-orbit); a popover (it closes on the first touch of the stage).

**D-106 — Every panel resizes from a corner grip and remembers its size on the device.** hmm-kit's `hmmResizable`
(`HmmPanel(sizing:)` uses it): drag the grip, double-tap it for the original size; sizes live in `UserDefaults` per
panel. *Rejected:* sizes per project (they fit the person's screen and hands, not the project).

**D-107 — The joystick is on by default and can leave from its own ×.** Settings ▸ Stage brings it back and holds its
speed. *Rejected:* keeping its toggle in a tool panel (a preference isn't a tool).

**D-108 — Home's cards turn: a turntable rendered once, played a frame at a time.** When a project closes, its card
is drawn after the editor has gone (closing no longer waits): the still first, then 48 frames of the scene turning
once around everything in it, from the work view's height, in its Look (6 s a turn at 8 fps, 480 px wide), cached in
the package as a GIF. A card opens the GIF only while it's on screen and decodes just the frame it shows; it pauses
while the gallery scrolls and while a project is open; Reduce Motion keeps the still. Stills load off the main
thread into an 80-card cache. *Rejected:* rendering each card live with Metal (a GPU pass per card); keeping decoded
frames (25 MB a project, 2.5 GB at a hundred); looping HEVC with a player per card (a dozen hardware decoders).

**D-109 — A card grows into the stage with the system's zoom transition.** The open project is a full-screen cover
over Home with `navigationTransition(.zoom)` from the card's picture, so it grows out of the card and shrinks back
into it. Interactive dismissal is off: pinching and dragging belong to the stage, and the project closes from Home in
the corner. *Rejected:* a hand-built matched-geometry overlay (it re-lays out the Metal stage every frame of the
animation).

**D-110 — Stacks, search and sort are hmm-kit's `GalleryArrangement`, saved as `gallery.json` beside the projects.**
Cutaway's home will use the same. Drop a card on another to stack them; projects that disappear are pruned; search
looks through every project and stack by name; the sort (Recent, Name, Date created) is remembered. *Rejected:*
stacks as folders on disk (the project list, iCloud Drive and Files bookmarks all follow package locations).

**D-111 — Starter templates prepare the workspace and place nothing.** Blank, Model to print (Clay, studio light, a
1 cm grid, 5 cm shapes, close up, Model open), Room or building (a 25 cm grid, the view from above, Model open),
Character (Cast open, eye level, the transport showing), Animation (the timeline open). Each suggests a Look and a
Mood that New project lets you change. Sketch arrives with the Schizzo board; millimetres and the print-bed outline
with M3/M4's precision tools; the walls tool with M4. *Rejected:* listing Sketch now (a template promising a tool
that isn't there is a stub); templates that place objects (CONTEXT §4.2: an empty project).

**D-112 — LAYOUT.md is walked by the UI tests, and the gates are measured.** `Tools/layout_walk.py` turns each walkable
row into `AppUITests/LayoutWalk.swift` (CI fails when they disagree) and `LayoutTests` taps every row from a new
project. The idle stage's share is the window minus the frames of the clusters, the sidebar and the bottom-right
controls. The Home benchmark (Diagnostics) builds a hundred projects in a scratch folder as clones of one real project
(no extra space on APFS), scrolls the real gallery grid down and back for 20 s at one speed and records every
presented frame with the Night Market's pass rule; CI runs it on the simulator to prove it runs, and the device JSON
is the gate (CONTEXT §6). *Rejected:* a synthetic grid of placeholder cards (it wouldn't measure the cards people see).

**D-113 — Panel section titles are translated too.** `Tools/strings.py` didn't scan `PanelSection`, so 27 section
titles (Shapes, Light & camera, Palette…) showed in English in the Italian and Arabic builds; they're found and
translated now. In Arabic, Move is نقل: it read the same as Animate (تحريك), now beside it.

**D-114 — People see "Home", and the studio is studio h.** The Theater is called Home everywhere a person reads it
(code names stay); Settings ▸ About says "Made by studio h.".

## Maquette 0.3 — M3, modelling I

**D-115 — Booleans are Manifold, vendored, behind a C face (spike passed).** The spike built Manifold v3.5.4 with
SwiftPM and ran it from Swift in the Linux container, on the iPad simulator and as an `iphoneos` arm64 build, on CI
(a throwaway `spike/manifold-ios` branch, since deleted). It lives in `Packages/Manifold` as a C++17 target (single
thread, no TBB, no 2D cross sections so no Clipper2) with `ManifoldBridge.h`, a few C functions Swift imports as plain
C. LoweyCore depends on it and still builds and tests on Linux. *Rejected:* Swift's C++ interop (it must be switched
on in every module that imports the target, Core through App and the tests); a prebuilt XCFramework (the Linux tests
couldn't link it); the BSP fallback (not needed).

**D-116 — The editable mesh is polygons with holes; its topology is built when needed.** `EditableMesh` stores
vertices and faces (an outline, counter-clockwise from outside, then holes); `MeshTopology` builds half-edges from it
for each operation and is thrown away. Stored compactly (`{"v": […], "f": […]}`, coordinates to the nanometre).
Equality and hashing go by a fingerprint computed once per mesh, so the renderer's cache keys on a mesh every frame
without walking it. *Rejected:* storing half-edges (larger files, and states that can't be valid become storable);
triangles only (nothing to push or pull: a face is what you touch).

**D-117 — Clean results: faces rebuilt from triangles.** `MeshBuilder` merges neighbouring triangles on one plane into
one face (holes kept, loops that touch at a corner split), then removes corners on a straight run where exactly two
faces meet, from both or neither. A boolean's result isn't welded (Manifold keeps near-coincident corners apart on
purpose; welding them broke edges in a 1 000-case soak); renderer meshes are, with a neighbour-cell search so seam
copies on either side of a grid cell still join. Corners Manifold kept come back with their exact Double positions, so
typed sizes survive any number of booleans. Cuts start a hair above the face and, when they end exactly on a face of
the solid (cutting through), go a hair past it: exactly coplanar faces can leave a skin. *Rejected:* trusting
Manifold's own face ids for merging (two coplanar faces from different inputs must still merge).

**D-118 — Modelling is the commands that already exist.** Push/pull, pulls, cuts, booleans and drawing are
`setKind` / `insert` / `delete` / `setProperties` in one labelled `batch`, so undo, the journal, versions and the
bridge needed nothing new. The schema goes to 5 (no-op migrations for documents and journal ops) only so 0.2 and
3D-lowey 2.0 refuse 0.3 files with a clear message instead of failing on an unknown object type. *Rejected:* new
command cases (more surface for the same result); keeping schema 4 (older apps would misreport the files as damaged).

**D-119 — Push/pull slides when it can, sweeps when it must.** When every face around the picked one stands square to
it (a block's top, a pocket's floor), its corners move and its neighbours stretch: the faces stay and the typed number
is the new size exactly; it refuses to pass the opposite side. Otherwise the face's outline is swept into a prism and
added or cut with a boolean, which works on any face. A shape is made an editable mesh, with its scale baked into the
vertices so lengths are real, before its first face moves (its own undo step); objects with children keep their scale
and the distance is converted. *Rejected:* always sweeping (renumbers the faces and loses the pick on every drag
step).

**D-120 — While dragging, nothing is committed.** A sliding face shows its new shape through `kindOverride` (the stage
draws the overridden kind; the document is untouched) and a sweep shows the prism it will add or cut; release commits
one command. *Rejected:* coalesced commands per drag step (each journal line would hold the whole mesh: megabytes per
drag).

**D-121 — Sketches are objects, drawn by taps, and only on the stage.** A `sketch` object holds a world plane, its
curves and the object it was drawn on. The first tap picks the plane (the face under it, else the ground) and joins a
sketch already on that plane; then taps place points (a rectangle's corners, a circle's centre and edge, an arc's
start, end and bend, a line's corners until the first is tapped again, a spline's points until closed or Done), so a
finger, the Pencil and a UI test all draw the same. Closed curves, and open ones that meet end to end, fill into
regions; a loop inside another makes a hole and is a region of its own. Pulling or cutting a region uses its curves
up; the sketch goes when empty. Sketches are construction lines: the editor pass draws them, exports never do.
Curves that cross aren't split into regions yet (BACKLOG). *Rejected:* drag-to-draw (a finger drag orbits:
CONTEXT §4.1 "fingers navigate"); sketches as children of the object (moving the object would have to rewrite them).

**D-122 — Exact numbers float beside what they measure.** The pull distance, a rectangle's two sides, a circle's
diameter, a line's length and an offset are chips on the stage; tapping one opens an empty field with the current
value as its placeholder, so typing replaces it. Lengths are typed in the project's units with any unit on any number
and arithmetic (`25`, `25mm`, `2*12`, `1ft 6in`, `(40-6)/2`). Units are `workspace.json`'s (Model to print: mm, Room:
m, others cm), set in Model ▸ Snapping. Dragging snaps to other corners' heights along the axis within 10 points,
else to one unit when grid snapping is on; sketch points snap to one unit too (or the grid when it's finer). The
stage's camera comes in to 3 cm (its near plane follows it in), so double-tap frames a millimetre part; a shape tool
shows its hint once, when chosen, not a toast per tap. *Rejected:* a numeric keypad sheet (a decision wall between the drag and
the number).

**D-123 — The marks are drawn in the editor pass; the element under a tap is found on the CPU.** The ID buffer finds
the object; `MeshPicking` then raycasts its faces (and picks the nearest edge or corner of the hit face on screen),
because element ids don't fit in the ID buffer without a second, larger pass. Wireframe, picked faces / edges /
corners, sketch lines and regions, pull previews are `EditorOverlay` meshes (bars sized from the camera so they stay
about two points wide), depth-tested against the frame except corners and the shape being drawn. *Rejected:* a
per-element ID pass (GPU memory and a readback for something the CPU answers in microseconds at these mesh sizes).

**D-124 — Model ▸ Shape holds the modelling tools; the bar holds the rest.** The page has the sketch shapes, the pick
modes and the booleans (and Make editable when a shape is selected); choosing a shape or a mode closes the panel so the
stage is free, and the Model tool's bar at the bottom switches modes, finishes a line or spline, grows / shrinks /
selects similar, and ✕ leaves it. A Pencil loop picks elements; a finger drag still orbits, except on the picked face
or region, where it pushes or pulls. The inspector shows the selection's size and what's picked; it steps aside while a sketch shape is chosen (the
floating numbers are the controls then, and it would cover them beside a large selection). *Rejected:* a sixth
top-right button (CONTEXT allows five); a separate Select-elements tool in the top left (picking faces is modelling).
