# Architecture

Manim-like at the core: **Objects → Properties → (Animations → Timeline) → Scene**, saved as plain JSON.
Every change is a **Command**. The UI, gestures, drawing, the library, Scene Scripts and (Phase 3) the AI all
speak the same command language — there are no side doors.

```
┌──────────────────────────── App (SwiftUI) ────────────────────────────┐
│ HomeView · EditorView (TopBar, ModeSwitcher, ToolRail, Inspector,     │
│ Library, Outliner, Look, Draw, Export, Joystick) · StageCoordinator   │
│ (gestures) · AppModel · LibraryModel · EditorModel                    │
└───────────────┬───────────────────────────────┬───────────────────────┘
                │ commands (EditCommand)        │ document + ChangeSet
┌───────────────▼──────────────┐   ┌────────────▼──────────────────────┐
│ LoweyCore (pure Swift)       │   │ LoweyRender (RealityKit)           │
│ Model · Commands · Undo      │──▶│ SceneRenderer (diff sync)          │
│ Timeline/Easing · Geometry   │   │ Materials (+ fog/glow shader)      │
│ Library · Operations         │   │ EnvironmentRig · StageView         │
│ Serialization + migrations   │   │ OffscreenRenderer · AssetLoader    │
└──────────────────────────────┘   └────────────────────────────────────┘
```

## LoweyCore — no RealityKit, no UIKit

Builds and tests on Linux (CI runs it in the `swift:6.1` container) — fast, deterministic.

| Area | Files | What |
|---|---|---|
| Math | `Math/` | `Vec3`, `Quat`, `Transform`, `Bounds`, `Ray`, `RGBA` (8-bit quantised so save → load is bit-exact), `SeededRandom` |
| Model | `Model/` | `SceneObject` (id, name, kind, parent, children, typed properties), `ObjectKind` (group, primitive, asset, prefab, drawing, light, camera), `PropertyValue` + `PropertyKey` specs (type, animatable), `Look` (+ presets), `Scene`, `ProjectInfo`, `Document`, typed IDs |
| Commands | `Commands/` | `EditCommand` (insert, delete, restore, setProperties, rename, setKind, reparent, setLook, renameScene, setActiveCamera, setTimeline, batch). `apply` returns the exact inverse; atomic. `EditSession` = document + undo/redo + gesture coalescing. JSON (`{"op": …}`) = Scene Script vocabulary |
| Timeline | `Timeline/` | `Keyframe`, `Track`, `Timeline.evaluate(at:)`, `Easing` (presets + cubic bezier), `Stepping` (on twos/threes). Empty in Phase 1 but complete and tested |
| Geometry | `Geometry/` | Low-poly primitives (base-centred pivots), flat vs auto-smooth shading, stroke filtering, tube / ribbon / extrude / lathe meshers, mirror, guide-surface raycasts, mesh raycast, OBJ parser, glTF dependency scan |
| Library | `Library/` | `LibraryManifest` (assets, prefabs, looks), search ranking, filters, `RigClassifier`, `LibraryStore` (import/copy files), `ProjectAssets` (embed for export / adopt on import) |
| Operations | `Operations/` | High-level actions that *return commands*: add/place on ground, duplicate, delete, translate/rotate/scale (hierarchy-aware), group/ungroup/reparent (world transforms kept), array, scatter (seeded), align/distribute, swap-to-fit, prefab create/replace/unpack, snapping. `SceneBounds` computes bounds from Core data |
| Project | `Project/` | `.lowey` folder format, `ProjectStore` (create/list/open/save/rename/duplicate/delete, scenes), `DocumentSaver` actor |
| Serialization | `Serialization/` | Envelope `{schemaVersion, kind, payload}`, `SchemaCoder` with migration chain (v0 → v1 built in), `SafeFileWriter` (atomic + `.bak`, recovery), `JSONValue` |
| Samples | `Samples/` | The Enigma sets, built through the command system |

### Data flow for one edit

1. A tool calls an `EditorModel` method (e.g. `duplicateSelection()`).
2. It asks `Operations` for a command, then `perform(command)`.
3. `EditSession.perform` applies it (atomically), stores `(command, inverse)` for undo, returns a `ChangeSet`.
4. `SceneRenderer.sync(document, changes)` updates **only** the changed entities.
5. Autosave is debounced (1.2 s) and written off the main thread by `DocumentSaver` (atomic writes).

Continuous gestures (joystick, gizmo drag, sliders) pass a `coalesceKey`, so a whole gesture is one undo step.

## LoweyRender — the RealityKit bridge

- **SceneRenderer**: one `Entity` "node" per object (transform, visibility, parent), with a child "content"
  entity (mesh / model clone / light / prefab expansion). A `ContentKey` decides when content must be rebuilt;
  transforms never rebuild content. Picking walks up to `LoweyObjectComponent`.
- **Materials**: every lit surface is a `CustomMaterial` running `loweySurface` (Shaders/LoweyShaders.metal):
  exponential distance fog + HDR glow, identical in the live view and offscreen. Identical surfaces share one
  material; model clones share meshes → RealityKit batches/instances them.
- **EnvironmentRig**: sky dome (gradient + stars texture, follows the camera), ground disc, sun with shadows,
  image-based ambient light generated from the same sky.
- **StageView** (`ARView`, non-AR): orbit camera from `Viewpoint`, orthographic as 2° telephoto, grid,
  selection box, gizmo, guide surface, stroke preview; ray/pick/project helpers.
- **OffscreenRenderer** (`RealityRenderer`): renders a clone of the world at any size (snapshots, thumbnails,
  and Phase 2's frame-by-frame export).
- **AssetLoader**: USDZ (`Entity(contentsOf:)`), glTF/GLB (GLTFKit2), OBJ (Core parser). Caches prototypes,
  measures bounds/triangles/joints/clips, builds faceted variants for flat shading.

## App

- `AppModel`: folders (Documents/Projects, Documents/Lowey Library), project list, open/close editor, incoming files.
- `LibraryModel`: the global library, imports (with thumbnails via the offscreen renderer), prefabs, looks.
- `EditorModel`: session, selection, mode/tool state, every editing action, autosave, snapshots.
- `StageCoordinator`: UIKit gestures → camera and editor actions; `StrokeGestureRecognizer` captures Pencil
  pressure with coalesced touches.

## On disk

```
Documents/
  Projects/<Name>.lowey/        project.json, scenes/<id>.json (+ .bak), assets/, audio/, renders/, thumbnail.png
  Lowey Library/                library.json, assets/<asset-id>/…, thumbnails/<id>.png
```

## Phase 2: motion, cameras, characters, export

```
             ┌──────────── LoweyCore ────────────┐
 document ──▶│ Animator.evaluate(document, t)     │──▶ AnimatedScene
             │  1 tracks (per-object stepping)    │      scene (values at t)
             │  2 behaviours (stateless of t)     │      animated ids
             │  3 camera cuts                     │      camera
             │  4 clip tracks → ClipMixer         │      poses (joint transforms)
             │     (retarget, crossfade, IK)      │
             └────────────────────────────────────┘
                 ▲ keys / behaviours / clips come from commands:
                 │ KeyOperations · PresetBuilder (+ stagger) · CameraMoves · PerformBaker
                 │ Simulation (physics, flock, crowd, bake) · ScriptRunner (LoweyScript)
```

| Area | Files | What |
|---|---|---|
| Timeline | `Timeline/Timeline.swift` | tracks, markers, loop, camera cuts, behaviours, clip tracks; fps, duration, project stepping |
| Motion | `Motion/` | `Animator` (evaluation), `KeyOperations` (key, move, retime, reverse, mirror, easing, copy/paste, shift, clear), `Presets` (15 presets + stagger/order/randomise, animated generators), `Behaviors` (follow path, look at, follow, orbit, wobble, wind sway, bob, spin), `Perform` (takes → smoothed keys), `CameraMoves` (10 moves + focus pull), `Simulation` (physics, flock, crowd walk, bake behaviour), `Noise`, `CameraLens` (focal length, 9:16 framing) |
| Rig | `Rig/` | `Skeleton`, `MotionClip`, `ClipTrack` (segments, crossfades, IK settings), `GLTFReader` (skins + animations from glTF/GLB), `BoneMapper` + `SkeletonStandard`, `Retargeter`, `IKSolver`, `ClipMixer`, stride speed |
| Export | `Export/SceneExport.swift` | GLB writer, USDA/USDZ writer (stored zip, 64-byte aligned), CRC-32 |
| Samples | `Samples/EnigmaOpening.swift` | the Enigma opening animated end to end (the Phase 2 proof) |

- **Commands**: `setTracks([TrackEdit])` edits keys (coalesces during gestures); `setTimeline` for markers, cuts, behaviours, clips.
- **LoweyRender**: `SceneRenderer` applies opacity, swaps materials for animated colour/glow without rebuilding, writes
  poses to `jointTransforms` (`applyPoses`), scrubs RealityKit clips for USDZ (`applyClipFallback`), hides the camera
  you look through. `RigCache` reads rigs once. `VideoExporter` renders frame by frame (see DECISIONS D49).
  `ModelExport` gathers meshes for GLB/USDZ. `StageView.setLookThrough` shows the shot camera.
- **LoweyScript** (iPadOS/macOS package): `ScriptRunner` (JavaScriptCore → one command), `ScriptExamples`.
- **App**: `EditorModel` keeps the playhead and the evaluated `displayed` scene; `EditorModel+Animation` (auto-key,
  playback clock, presets, behaviours, Perform), `+Camera` (look-through, cuts, lens, moves, touch camera, virtual
  camera), `+Export` (video jobs, Photos, 3D export, scripts, characters). Views: `TimelineDrawer`, `AnimatePanel`,
  `CameraPanel`, `ExportPanel`, `ScriptPanel`, `PerformOverlay`. `VirtualCameraController` wraps ARKit.

### Data flow for one frame of playback

1. `PlaybackClock` (display link) advances `time`.
2. `refreshDisplay()` → `Animator.evaluate` (+ live Perform overrides) → `SceneRenderer.sync` for the animated objects
   only → `applyPoses`.
3. While recording a Perform take, the overrides are sampled at `time`.
4. SwiftUI panels refresh a few times a second (not every frame).

## Phase 3: story, voice, VFX, AI, polish

```
 voice ─▶ AudioClip (timeline.audio) ─▶ SpeechAnalyzer (app) ─▶ Transcript (file-time words) ─▶ timeline.words
                                                                                  │
          ┌───────────────────────────── word times ──────────────────────────────┤
          ▼                                                                       ▼
 Scene Script actions ──ScriptCompiler──▶ EditCommand (one undo step)      LipSync ─▶ mouth / jaw keys
 (bridge · MCP · paste · samples)                                                   │
                                                                                    ▼
 Animator.evaluate: tracks → live overrides (Perform, face) → behaviours → clips (assets, puppets) → FaceRig
          │
          ▼
 SceneRenderer (+ particles, text) ──▶ render ──▶ FrameCompositor: shot post → transition → screen → film → overlays/captions
          ▲ depth world (export) / RealityKit depth (stage)                    ▲ OverlayLayout + OverlayRenderer, Captions
```

| Area | Files | What |
|---|---|---|
| Audio | `Audio/Audio.swift`, `AudioMixer.swift`, `WAV.swift` | clips (trim, fades, envelope), transcripts, timeline words, word snapping and search, transcript corrections, the mixer (export soundtrack), loudness, WAV |
| Text & overlays | `Text/Overlay.swift`, `Text3D.swift`, `Captions.swift` | frame-space overlays (placement, projection for followers), the block font, caption pages / karaoke / SRT / VTT |
| VFX | `VFX/Particles.swift`, `ParticleMesher.swift`, `Post.swift` | closed-form particles and their meshes; post settings (in the Look), screen effects, transitions, match cut |
| Face | `Face/LipSync.swift`, `Face.swift`, `Resources/visemes.txt` | phonemizer (CMUdict + rules, Arabic, Italian), lip-sync keys; landmarks → channels (One Euro); the face rig |
| Characters | `Character/CharacterBuilder.swift`, `PuppetRig.swift`, `BuiltinClips.swift` | the builder, puppet skeletons for retargeting, the ten built-in humanoid clips |
| AI | `AI/ScriptCompiler.swift`, `ScriptReference.swift`, `Bridge.swift` | actions → commands with preview, the action reference, HTTP parsing / pairing / routing / LAN policy, compact summaries |
| Projects | `Project/ProjectPackage.swift` | zip reader, `.loweypack`, archive, copy scene |
| Samples | `Samples/EnigmaStory.swift`, `IslandSample.swift` | the narrated Enigma story and the welcome island — both Scene Scripts |

**LoweyRender** adds `FrameCompositor` (Core Image stages, shared by stage and export), `OverlayRenderer` (CoreGraphics
titles, shapes, captions), `StagePost` (ARView post-process: depth → `loweyInverseDepth` kernel → compositor), the depth
world (`SceneRenderer.depthPass`, `loweyDepth` shader), particle and text content, and an exporter that composites,
renders both shots of a transition and interleaves AAC audio.

**App** adds `Audio/` (decoder, playback locked to the picture, voice recorder, `SpeechService`, placeholder voice),
`Face/` (Vision capture, iPhone link, companion screen), `Bridge/` (Network.framework server, endpoints, approvals),
`EditorModel+Audio/+Story/+Character/+AI`, the timeline's audio/words/effects lanes and multi-select layer, panels
(audio, transcript, character builder, post, effects & captions, transitions, bridge, proposals), the tour, menu-bar
commands, diagnostics and thermal handling.

**Laptop** (`tools/lowey`): `client.py` (bridge client), `mcp_server.py` (lowey-mcp), `link.py` (lowey-link), Blender
generators. `/skills`: four Claude skills.
