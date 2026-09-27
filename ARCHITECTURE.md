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

## Where Phase 2 plugs in

- Timeline UI edits `Scene.timeline` via `.setTimeline` / future fine-grained key commands; the renderer applies
  `Timeline.evaluate(at:)` as property overrides.
- Video export = `OffscreenRenderer.render` in a fixed-timestep loop → AVAssetWriter.
- Presets / Perform mode / behaviours produce keyframes through commands.
