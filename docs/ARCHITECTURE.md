# Architecture

Manim-like at the core: **objects → properties → animation → timeline → scene**, saved as plain JSON. Every change
is a **command**. The UI, gestures, drawing, the library, scripts and the AI bridge all speak the same command
language, so there are no side doors and every change is one undo step.

## Modules

```mermaid
flowchart TD
    App["App<br/>entry point · menu commands · background export · Live Activity widget"]
    Features["LoweyFeatures<br/>SwiftUI editor: Shell + one folder per feature + Workspace"]
    Engine["LoweyEngine<br/>LoweyRender 2 (Metal) · import · export · stage view · audio · face · scripting"]
    Core["LoweyCore<br/>pure Swift: model · commands · timeline · geometry · modelling · characters · samples"]
    Manifold["Manifold<br/>vendored C++ booleans behind a C face"]
    subgraph HmmKit["hmm-kit (Packages/HmmKit, git subtree)"]
        Design[HmmDesign]
        Commands[HmmCommands]
        Documents[HmmDocuments]
        Bridge[HmmBridge]
        Diagnostics[HmmDiagnostics]
        Transcript[HmmTranscript]
        Media[HmmMedia]
        Perception[HmmPerception]
        Brush[HmmBrush · HmmBrushRender]
        Board[HmmBoard · HmmBoardUI]
    end
    App --> Features
    Features --> Engine
    Features --> Core
    Engine --> Core
    Core --> Manifold
    Features --> Design & Bridge & Diagnostics & Documents & Perception & Board
    Engine --> Media & Diagnostics & Transcript & Perception & Brush
    Core --> Commands & Documents & Transcript & Brush
    Board --> Brush
```

| Module | Imports | What it holds | Tests |
|---|---|---|---|
| **LoweyCore** | Foundation, hmm-kit's Commands / Documents / Transcript / Brush (re-exported), Manifold, XAtlas | The document model, commands with exact inverses, the session (undo, coalescing), timeline and easing, animator and behaviours, geometry and meshers, modelling (editable meshes, sketches, push/pull, booleans), the brush library and brush import (the engine's arithmetic is hmm-kit's `HmmBrush` since 0.9), paint (layers, tiles, unwraps, compositing, carrying paint to a new shape, painted exports), the glTF reader, rigs and retargeting, the one skeleton system (drawn
rigs, bone heat, IK chains, the person rig), blob and puppet characters, Scene Script compiler, Looks as data, samples (Enigma, Welcome island, Night Market) | Linux (`swift:6.1`), coverage gate |
| **Manifold** (`Packages/Manifold`) | the C++ standard library | Manifold 3.5.4 (Apache-2.0) as a C++17 target, single-threaded, and `ManifoldBridge.h`: boolean and validate in plain C, so Swift needs no C++ interop. `VENDORED.md` says how to update it | Linux and the iPad simulator (its own tests; LoweyCore's boolean tests) |
| **XAtlas** (`Packages/XAtlas`) | the C++ standard library | xatlas (MIT) as a single-threaded C++ target and `XAtlasBridge.h`: unwrap in plain C (`VENDORED.md`) | Linux (its own tests; LoweyCore's paint tests) |
| **LoweyEngine** | Core, Metal, AVFoundation, Vision, ARKit, JavaScriptCore, hmm-kit's Media / Diagnostics / Perception / Transcript / BrushRender (re-exported) | LoweyRender 2 (with the brush engine's stamps, painted layers and drawn rigs skinned on the GPU), the shot builder, the stage view (`StageView`), model loading and caching, export sessions and presets, overlays and captions, the Night Market benchmark, face capture, the JavaScript runner | iPad simulator: golden images, export, picking, skinning |
| **LoweyFeatures** | Core, Engine, SwiftUI, hmm-kit's Design / Bridge / Documents / Diagnostics / Board / BoardUI | The editor. `Workspace/` is shared by every feature (app and editor models, the session API, controls); each other folder is one feature's views; `Shell/` composes them | iPad simulator: bridge security, editor flows |
| **App** | Features, ActivityKit, BackgroundTasks | `LoweyApp`, the export Live Activity, the widget extension | UI smoke tests |

**Rules** (enforced in CI): LoweyCore imports no Apple UI or 3D framework; features never reference each other's
types (`Tools/check-feature-boundaries.py`); no file over 500 lines, no function over 60, no type body over 350,
complexity ≤ 12, no force unwraps outside tests (SwiftLint `--strict`); Swift 6 language mode with warnings as errors.

## One edit, end to end

```mermaid
sequenceDiagram
    participant UI as Feature view / gesture
    participant EM as EditorModel (Workspace)
    participant Ops as Operations (Core)
    participant ES as EditSession (Core)
    participant SB as ShotBuilder (Engine)
    participant R as LoweyRender 2
    participant J as History journal
    UI->>EM: duplicateSelection()
    EM->>Ops: duplicate(ids, in: scene)
    Ops-->>EM: EditCommand
    EM->>ES: perform(command, coalesceKey)
    ES-->>EM: ChangeSet (inverse kept for undo)
    EM->>SB: document changed
    SB->>R: FrameRequest (evaluated scene, camera, Look, editor layer)
    R-->>UI: next frame on the stage
    EM->>J: the step's ops (journalChanged)
    J-->>J: one JSON line within 50 ms; a checkpoint every 200 changes / 5 s idle
```

Continuous gestures (drags, sliders, the joystick, Perform) pass a coalesce key, so a whole gesture is one undo step.
Scene Scripts and bridge proposals compile into one `batch` command. `J` is the scene's `HistoryJournal` (below).

## Modelling

```mermaid
flowchart LR
    Tap[Tap / drag / Pencil loop<br/>StageGestures] --> EM[EditorModel+Modeling<br/>+Sketching · +PushPull]
    EM --> Ops[ModelingOperations<br/>Core]
    Ops --> PP[PushPull · Prism]
    Ops --> B[MeshBoolean]
    B --> MF[Manifold<br/>C face]
    B --> MB[MeshBuilder<br/>faces from triangles]
    Ops --> Cmd[EditCommand batch<br/>setKind · insert · delete]
    EM --> Ov[EditorModel+ModelOverlay] --> Stage[StageView.showModelOverlay<br/>editor pass]
```

- **`EditableMesh`** (Core `Modeling/`): vertices and faces (outline + holes) in the object's space, metres; the
  `mesh` object kind. `MeshTopology` builds half-edges per operation; `MeshBuilder` turns triangles (primitives,
  drawings, boolean results) into whole faces; `PolygonTriangulator` cuts faces with holes for the GPU and Manifold.
- **`MeshBoolean`** flattens both meshes into the C structs, calls `MBBoolean`, and rebuilds faces (D-115, D-117).
  `PushPull` slides a face when its neighbours stand square to it, else sweeps a `Prism` and combines it (D-119).
- **`Sketch`** (the `sketch` kind): a world plane, curves (line, rectangle, circle, arc, spline, polyline), the object
  it was drawn on; `regions` nest closed loops into areas with holes. `ModelingOperations` turns a pull, cut,
  boolean, push/pull or new curve into one labelled batch of existing commands (D-118).
- **On the stage** (Features `Workspace/Session`): `ModelingState` (mode, the picked elements or region, the shape
  being drawn, the live pull) is view state, never undone. Taps go `StageGestures` → `modelTap`; a drag on the picked
  face or region becomes `.pushPull`, a Pencil loop `.modelLasso`. While dragging, `kindOverride` shows a sliding face
  without touching the document (D-120). `EditorModel+ModelOverlay` builds the marks as `EditorOverlay`s with Core's
  `ModelOverlay` and the floating numbers (`DimensionLabel`, drawn by `Model/ModelDimensions` over the stage).

### Modelling II (0.4)

- **Shape operations** (Core `Modeling/`): `Inset` (topology only: a ring of quads, the face keeps its index),
  `EdgeBevel` (a chamfer or fillet profile swept along each edge, cut or filled with `MeshBoolean`), `Shell` (every
  face offset inward by `PlaneSolve`, the cavity cut out; open faces are push/pulled through the wall first),
  `MeshMirror` (reflection, symmetrize = keep a half-space side, mirror, union). `ModelingOperations+Shape` turns each
  into one labelled batch and re-symmetrizes objects with the `symmetry` property after every edit (D-127).
- **Exactness**: `MeshBoolean` snaps the corners Manifold creates onto the input planes they lie on (`PlaneSolve`), and
  `MeshBuilder.closeTJunctions` puts corners a neighbour kept into the other face's edge (D-126).
- **Precision**: `PointSnap` (corners, edge middles, edges, faces, grid, by screen distance) serves sketching,
  measuring and building (`EditorModel+Precision.snapPoint`). Kept measurements are `dimension` objects
  (`Dimension.swift`). The section plane (`SectionPlane`, `workspace.json`) reaches the renderer through
  `StageView.section` → `EditorScene.section` → `FrameUniforms.section` (D-131); `StageView.showPrecisionOverlay`
  draws the printer's volume and kept dimensions whatever the tool.
- **Printing**: `PrintCheck` (topology, Manifold, wall rays, the bed) and `repair`; `PrintBed` presets.
- **Building**: `Architecture` (walls from a centre line, opening blocks, slabs, stairs), driven by
  `EditorModel+Architecture`'s tap tools.
- **Features**: `EditorModel+ShapeOps` (bevel/round/inset/shell with the size that floats, mirror, symmetry, the print
  check, Make editable for placed models), `EditorModel+Measure`, `EditorModel+Architecture`, `EditorModel+Precision`;
  the views are `Model/ModelShapeControls` (the bar's pick actions, mirror and print controls) and `Model/PrecisionPage`.

## Interop

```mermaid
flowchart LR
    Scene[Scene] --> GW[GLTFScene<br/>nodes · materials · cameras · lights · keys]
    GW --> GLB[.glb]
    GW --> BP[BlenderPackage<br/>+ maquette.json + setup_maquette.py]
    Scene --> EM[ExportMesh list<br/>world space] --> USDZ[USDZ] & OBJ[OBJ + MTL] & STL[STL<br/>mm, Z up] & TMF[3MF<br/>mm, Z up]
    File[.glb / .gltf] --> GR[GLTFSceneReader] --> Frag[SceneFragment + Tracks<br/>editable objects]
    Lib[Library import<br/>USDZ · glTF · OBJ · STL · 3MF] --> Model[ImportedModel] --> EP[editableParts]
```

Everything is Core (pure Swift, Linux-tested) except reading USDZ (ModelIO) and placed models' loaded parts, which
Engine's `ModelExport` hands Core as `GLTFScene.LocalPart`s. 3MF reading uses Core's `Inflate` (D-137). CI checks the
M3 block's STL and 3MF with trimesh and renders a frame of a Blender package in Blender 4.2 and 5.2 (the `interop`
job, from files LoweyCore's tests write to `ACCEPTANCE_DIR`).

## Brushes (0.5)

```mermaid
flowchart LR
    Pencil[StrokeGestureRecognizer<br/>coalesced + predicted, pressure, tilt, time] --> SG[StageGestures+Brush]
    SG --> Guide[EditorModel+Brushes<br/>GuideAssist: straighten · symmetry copies]
    Guide --> Path[BrushStroker.path<br/>Core: streamline, dynamics]
    Path --> Dabs[BrushStroker.dabs<br/>Core: spacing, jitter, tapers, flow · seeded]
    Dabs --> Live[EditorScene.liveStroke<br/>editor layer]
    Path --> Commit[commitInkStrokes / commitFlipbookStrokes<br/>+ setBrushes on first use]
    Commit --> Doc[Document<br/>strokes: path + brush key + seed<br/>project.brushes: frozen copies]
    Doc --> Ink[SceneCompiler+Ink<br/>stamps per stroke, cached]
    Doc --> Flip[Renderer+Flipbooks<br/>a layer per blend mode]
    Ink & Flip & Live --> Stamper[BrushStamper<br/>Brush.metal: one instanced quad per stamp]
```

- **hmm-kit `HmmBrush`** (since 0.9, D-189; LoweyCore re-exports it): `Brush` (shape, grain, stroke, dynamics,
  rendering, about) and `BrushCurve`; `BrushStroker` (the path and the stamps, generic over `Vec2` and `Vec3`);
  `BrushImages` (the built-in tips and grains, drawn by code) and `GreyPNG`; `BuiltInBrushes` (ten brushes, three
  sets); `BrushKey` (content keys for brushes and pictures); `BrushResolver` (a stroke's brush from a document's
  copies); `StrokeLatency`; `Vec2`, `SeededRandom`.
- **Core `Brushes/`**: `BrushLibrary` + `BrushLibraryStore` (the device's library); `DrawingGuide`, `GuideAssist`,
  `GuideLines`. `Import/`: `BinaryPlist` + `KeyedArchive`,
  `ProcreateBrushImport`, `ABRBrushImport`, `BrushSetFile` (`.maquettebrushes`) and `BrushFileImport` (by extension).
- **hmm-kit `HmmBrushRender`** (since 0.9; LoweyEngine re-exports it): `Brush.metal`, `BrushStamper` (stamp buffers
  cached per path, brush and seed; `encode` with whatever pipeline is set), `BrushTextureCache` (grey textures with a
  CPU mip chain; imported pictures come through the frame's `mediaImage` as `brushes/<hash>.png`), `BrushShaders` (the
  library and the pipeline descriptors `PipelineBuilder.brush` finishes for the engine's targets).
- **Engine `Render/Brushes/`**: `BrushStamper.encodeFill` (a flipbook's filled shapes), `BrushPreviewRenderer` (offscreen pictures: the library's previews, Brush
  Studio's pad, the goldens). Pipelines: `brushScene` (the shading pass, MSAA, depth-tested), `brushEditor` (the editor
  layer), `brushLayer`, `brushFill`, `brushCompose` (flipbook layers). Ink keeps its ribbon in the prepass and shadows
  (`DrawItem.brushDrawn`); its stamps are `RenderScene.brushes`, drawn at the end of the shading pass. Flipbooks reach
  the renderer as `FrameRequest.flipbooks` (pixel layouts) and become layer textures the composite blends.
- **Features**: `BrushModel` (the library, the brush each tool holds, imports, shares, previews) on `AppModel`;
  `EditorModel+Brushes` (frozen copies, guides, seeds); `StageGestures+Brush` (live strokes); `Draw/BrushLibrarySheet`,
  `Draw/BrushStudioView` + `BrushStudioPages`, `Draw/BrushAndGuideControls`. The sheet is `EditorSheet.brushes`.
- **Latency**: `StageView.measureLatency` (touch timestamp → GPU completion + one refresh) into `StrokeLatency`;
  Diagnostics ▸ Apple Pencil, and the log every tenth stroke.

## Painting on models (0.6)

```mermaid
flowchart LR
    Pencil[StageGestures+Paint<br/>samples → BrushStroker dabs] --> Live[StageView.showLivePaint<br/>FrameRequest.livePaint]
    Live --> Stroke[PaintTextures+Encode.encodeStroke<br/>after the prepass]
    Stroke --> Stamp[stroke texture<br/>BrushStamper, screen space]
    Stamp --> Project[Paint.metal lw_paintProject<br/>paint mesh at its uvs · ID buffer + depth test]
    Project --> Layer[layer texture]
    Layer --> Compose[lw_paintCompose per layer → lw_paintFinish<br/>straight alpha, chart edges pushed out]
    Compose --> Shade[shading pass<br/>LW_FLAG_PAINTED: paint over the base colour]
    Stroke -. stroke ends .-> Read[finishPaintStroke<br/>changed tiles read back]
    Read --> Commit[EditorModel+Paint.commitPaintStroke<br/>PNG tiles → assets/paint · paintTiles]
```

- **Core `Paint/`**: `ObjectPaint` (surface, layers, tiles by name) on `SceneObject.paint`; `PaintUnwrap` (xatlas
  through `XAtlasCpp`, the `.uv` file, the paint mesh over a source mesh); `RGBAImage` + `PNGCodec`; `PaintComposer`
  (layers → composite, the W3C blend formulas); `PaintRaster` (coverage, dilation); `PaintTransfer` (bake a model's
  colours, carry paint onto a new unwrap by closest point); `PaintSource` (the mesh the renderer draws for an object);
  `PaintOperations` (prepare, tiles from a picture, fill, layer edits, merge down); `PaintExport` (current surface,
  flattened texture). Commands: `setPaint`, `paintTiles` (D-153).
- **Engine `Render/Paint/`**: `PaintTextures` (per object: layer textures filled from tiles, streamed a few a frame on
  the stage; the composite; the stroke's "before" copy; tiles adopted after a stroke), `PaintTextures+Encode` (uploads,
  coverage, compositing, the stroke pass, the read-back), `SceneCompiler+Paint` (the paint mesh and composite in place
  of a painted object's mesh; paint carried onto a changed shape, `CarriedPaint`), `AssetPaint` (a model's parts as one
  surface, its colours baked), `Renderer+Paint` and `StageView+Paint` (the live stroke and its read-back).
  `Benchmark/PaintBenchmark` is Diagnostics' painting benchmark.
- **Features**: `EditorModel+Paint` (getting ready, strokes committed in order, fill, eyedropper `PaintSampler`,
  pictures, rebasing paint onto a changed shape), `EditorModel+PaintLayers`, `StageGestures+Paint`,
  `Paint/ColourPaintSection` (with `PaintLayersSection`), `Paint/PaintOptionsBar` (and `PaintPictureOverlay`).
  `RenderInput.paintFile` reads `assets/paint/…` wherever a frame is rendered (stage, monitor, exports, thumbnails).

## Rigging (0.7)

```mermaid
flowchart LR
    Stroke[StageGestures+Rig<br/>Pencil samples] --> Rays[EditorModel+Rig.drawBone<br/>rays in the rig's space]
    Rays --> Line[BoneStroke.centreline<br/>CrossingPath: one depth through the part]
    Line --> Chain[BoneStroke.addingChain<br/>joints at the bends · a redrawn chain replaced]
    Line -. while drawing .-> Preview[BoneStroke.preview<br/>bones on the stage]
    Dots[EditorModel+PersonRig<br/>eight taps, mirrored] --> Human[HumanRig.rig]
    Chain & Human --> Heat[BoneHeat.weights<br/>off the main thread]
    Heat --> Set[setRig + rigs/hash.skin]
    Set --> Anim[Animator → RigPoses<br/>clips, then bone turns]
    Anim --> GPU[SceneCompiler+Rig<br/>skinned twin + joint palette]
    Anim --> Bend[drawings: strokes bent on the CPU]
    Drag[IK handles] --> CR[CharacterRig + ChainIK] --> Turns[bone.joint / part rotations]
```

- **Core `Rig/`**: `ObjectRig` (the skeleton in the rig's space, standard, tips, the `.skin` file or a drawing's inline
  `SkinWeights`, the surface fingerprint) on `SceneObject.rig`; `PropertyKey.boneTurn` (`bone.<joint>`, keyable);
  `TriangleBVH` (rays and segments against a surface, each crossing going in or out); `CrossingPath` (the stretches a
  ray spends inside the object, and the one per ray that keeps a stroke at one depth); `BoneStroke` (centreline,
  joints at the bends, the preview, chains, a chain drawn again, removing joints);
  `BoneHeat` (welded cotangent Laplacian, nearest visible bone, a PCG solve per joint); `RigOperations` (the surface a
  rig bends, weights stored as a file or inline, fits) and `WeightPaint`; `HumanRig` (the dots, the template, mirroring,
  the humanoid skeleton) and `TPose`; `CharacterRig` (the one door: Puppet joint objects, bones, the Blob) and `ChainIK`
  (FABRIK); `RigPoses` (the animator's step: clip pose, then bone turns; drawings bent), `Skinning` (CPU linear blend)
  and `RigSpace`. `IKHandles` and `PoseLibrary` (`Character/`) work through `CharacterRig`. `RigSamples` is the tailed
  creature the checks bend. Command: `setRig` (D-165).
- **Engine `Render/Rig/`**: `SceneCompiler+Rig` (the skinned twin of the mesh the object draws, a placed model's parts
  each with their slice of the weights, the joint palette `pose × rest⁻¹`, bounds grown to the pose, the weight view's
  twin and ramp), `RigSkinCache`; `SceneCompiler+Paint` skins a rigged object's paint mesh through the unwrap's source
  vertices. `ModelExport.posedParts` bakes the pose for every 3D format (D-173). `RenderInput.weightView` is the stage's
  Paint weights view.
- **Features**: `EditorModel+Rig` (what can be rigged, drawing a bone, weighing in the background, fitting, removing,
  resetting, painting weights, the bones on the stage), `EditorModel+RigSteps` (Bones → Skin → Pose and when each
  opens, the bone under the Pencil shown as it will land, forgetting the poses of replaced joints),
  `EditorModel+PersonRig`, `RigTypes` (`RigSettings` with its `Step`, `PersonRigging`), `StageGestures+Rig`,
  `Cast/RigSection` (the three steps, `RigStepRow`, `RigOptionsBar`, `PersonDotMarks`).
  `EditorModel+Poses` drags any character's joints through `IKHandles`; `restingRigTarget` shows the object being
  rigged or painted in its rest pose (D-171).

## Touch (0.8)

- **The hold menu** is hmm-kit's `HmmHoldMenu` (HmmDesign): the standard rows, up to three extras, Delete.
  `hmmHoldMenu(_:)` puts it on a SwiftUI view; `HmmHoldMenuInteraction` puts it on a UIKit canvas (the stage: a
  `UIContextMenuInteraction` hung from an invisible point under the finger, so nothing lifts); `hmmHoldMenu(at:)`
  listens from the window for an area SwiftUI draws as one picture (the timeline's lanes). The menus of things in a
  scene come from one file, `Workspace/UI/HoldMenus.swift` (`EditorModel.holdMenu(for:)`, `stageHoldMenu(at:)`,
  `holdMenu(forKey:)`, `holdMenu(forClip:)`, `holdMenu(forFlipbookDrawing:of:)`); lists build theirs where their
  state is. `ObjectRenameAlert` (on `EditorScreen`) is Rename for any object, wherever it was asked.
- **Pencil or hand** is hmm-kit's `HmmPencilOrHand` in `UserDefaults`. `StageGestures` lets both the Pencil and
  fingers reach the stroke recognizer with a making tool and decides each finger touch in `shouldReceive`:
  `fingerMakes(at:)` (fingers may make, and there's an object or the guide under the finger) sends it to the stroke,
  anything else to the orbit. `notePencil()` records the first Pencil touch or hover.
- **The Motion row** (`Inspector/MotionRow`, `EditorModel+LoopMotion`) adds, retimes and bakes behaviours through
  Core's `LoopMotion` (which motion a behaviour is and at what speed) and `Simulation.bake` for several at once.
- **The colour well** is `SidebarColourWell` in the kit's `HmmSidebar(accessory:)`; `ColourChooser` is the one
  palette-and-any-colour picker (also Paint ▸ Colour).

## The Schizzo board (0.9)

```mermaid
flowchart LR
    Touch[BoardCanvasView<br/>Pencil or hand · pan · pinch · hover · hold · drops] --> Model[BoardModel<br/>mutate]
    Model --> Session[BoardSession<br/>tools · pick · drag · stroke]
    Session --> Cmd[BoardCommand<br/>exact inverses]
    Cmd --> Journal[HistoryJournal<br/>board/history]
    Session --> List[BoardDrawList<br/>items · paper · overlay]
    List --> R[BoardRenderer<br/>one cached layer + what moves]
    R --> Stamps[BrushStamper<br/>the same stamps as ink]
    Model -. pin .-> Editor[EditorModel+Board<br/>assets/references · workspace.json]
    Editor --> Cards[ReferenceCards over the stage]
    Editor --> Plane[a card object in the scene]
```

- **hmm-kit `HmmBoard`** (pure Swift, Linux-tested): `Board` (items back to front, the frozen brushes, the paper);
  `BoardItem` (stroke, picture, note, arrow, frame); `BoardCommand` / `BoardEdit` (insert, remove, replace, order,
  brushes, paper, each with its exact inverse) and `BoardOperations`; `BoardSession` (the six tools, the selection, the
  drag or stroke in progress, undo: touches in board points come in, one command per gesture goes out);
  `BoardViewport`; `BoardDrawList` (what a board looks like, as draws in pixels) and `BoardShapes`; `BoardLayerPlan`
  (when the cached layer still serves); `BoardStore` (`board/`: `board.json`, `view.json`, `history/`, `assets/`).
- **hmm-kit `HmmBoardUI`**: `BoardRenderer` (Metal: executes a draw list with the brush pipelines; the board in one
  layer a quarter-screen larger than the screen, redrawn only when the view leaves it or the board changes under it,
  new strokes laid on top; `snapshot` for pins and shared pictures), `BoardTextures` (pictures through Image I/O,
  words through Core Text), `BoardCanvasView` (a `CAMetalLayer` that draws on demand; the making touch with coalesced
  and predicted samples; `HmmPencilOrHand`; `HmmHoldMenuInteraction`), `BoardModel` (the session observed, every
  change to the journal, a checkpoint and `board.json` at quiet moments), `HmmBoardScreen` (the layout).
- **Features**: `EditorModel+Board` (`projectBoard()` makes the model the first time; `openBoard` / `closeBoard`;
  `pinReference` writes the PNG under `assets/references/` and adds a `ReferenceCard` to the workspace;
  `standReferenceInScene` adds a card object), `Shell/BoardCover` (the kit's screen with Maquette's `BrushRow` for
  `BrushTool.board` and the Look's palette), `Board/ReferenceCards` (the cards over the stage). `EditorScreen` lays the
  cover over the stage and its chrome, under the sheets; the menu bar's Edit commands act on the board while it's
  open (D-193).

## Live performance (0.10)

```mermaid
flowchart LR
    Cam[FaceCapture / FaceLinkReceiver<br/>face + wrists] --> Ch[channels<br/>FacePerformer: rest pose, filter]
    Mic[VoiceCapture<br/>AVAudioSinkNode] --> VS[VoiceStream → VoiceSolver<br/>Core] --> Ch
    Deck[Trigger deck / keys] --> Ch
    Drag[a joint dragged while recording] --> Ch
    Ch --> Ov[propertyOverride<br/>+ takes while recording]
    Ov --> An[Animator.evaluate<br/>overrides + LivePast]
    An --> Posed[posed: keys, live, behaviours, clips, bone turns, LiveRig]
    Posed --> Dangle[Dangle: the past, sampled] --> Idle[Idle.breathe] --> Parts[LiveRig.carryParts] --> Bend[RigPoses.bend] --> Face[Idle.blink · FaceRig · Blob]
    Ov -. finishPerform .-> Take[TakeComp.recording<br/>setTracks + setTakes]
```

- **Core `Motion/Takes.swift`**: `Take` (channels of keys, its range, where the comp plays it), `TakeEdit`, the
  `setTakes` command, and `TakeComp` (a recording as one command; using a take over a stretch; where each take plays).
  `PerformTake.stepped` and `PerformBaker.held` keep a trigger's presses as held keys at their own moments.
- **Core `Rig/Dangle.swift`**: `dangle.<joint>` properties; `Dangle.apply` samples `Animator.posed` over the last
  1.2 s (30 a second, on a copy of the document cut down to the dangling characters), filters each loose bone's tip
  with a damped spring's impulse response and turns the joint to it. `LivePast` carries the live values of those
  moments.
- **Core `Rig/LiveRig.swift`**: head and hand channels on skeletons (`CharacterRig`: bones in the pose, Puppets on
  their joint objects), `carryParts` (`attachBone`), `nearestJoint`; `Idle` (breathing, blinking). `Animator.evaluate`
  is now `posed` (everything that places a skeleton) followed by what follows through; a pose changed after the bone
  turns is also written to the shown scene's `bone.` properties, so everything that reads the joints from the object
  agrees with the pose.
- **Core `Character/Triggers.swift`**: `Trigger`, `TriggerDeck` (the deck on the character, what a trigger sets, what
  letting go restores, held keys at the playhead). **Core `Face/VoiceSolver.swift`**: `VoiceSolver` (level against a
  learnt floor and ceiling, Goertzel band energies, the shape, two blocks to agree) and `VoiceStream` (any buffer size
  into 1024-sample blocks).
- **Engine `Face/VoiceCapture.swift`**: the microphone through an `AVAudioSinkNode`, measured on its own queue, the
  mouth delivered on the main actor. `FaceLinkSender` also sends `eyeWide` and `browAngle`.
- **Features**: `EditorModel+Live` (`LiveState`: the voice, the chosen joint, held triggers, the picked take, the live
  past; draggers, dangle, life, parts), `EditorModel+Triggers`, `EditorModel+Takes`; `Cast/LiveSections` (`VoiceLevel`,
  `TriggersSection`, `LifeSection`, `PartSection`, `DangleControl`, `TriggerDeckBar`), `Timeline/TakesStrip`. The
  menu bar's Perform menu holds the microphone and the trigger keys.

## LoweyRender 2

```mermaid
flowchart LR
    Doc[Document at time t] --> Shot[ShotBuilder<br/>animator · poses · camera · Look]
    Shot --> Req[FrameRequest]
    Req --> Compile[SceneCompiler<br/>draw items, mesh cache, instancing]
    Compile --> Shadow[Sun shadow map<br/>2 cascades]
    Shadow --> Pre[Prepass<br/>depth · normal · ID]
    Pre --> Shade[Look shading<br/>MSAA 4×]
    Shade --> AO[Contact shading]
    AO --> Lines[Lines]
    Lines --> Post[Post: halftone · misregistration · bloom · grade · grain · transitions · screen effects]
    Post --> Over[Overlays · captions · editor layer]
    Over --> Out{Output}
    Out --> Stage[Stage drawable<br/>dynamic scale + MetalFX]
    Out --> Export[IOSurface pixel buffer<br/>→ encoder]
    Pre -. ID buffer .-> Pick[Picking · selection outline]
```

- **Looks are data.** `LookPreset` (Core) holds shading, lines, finish and stepping; `LookResolver` turns a Look, a
  mood and per-object overrides into GPU parameters.
- **One path for everything.** The stage, thumbnails, snapshots and export all build a `FrameRequest` with
  `ShotBuilder` and render it with the same renderer; the stage adds only the editor layer (grid, gizmo, guides,
  selection outline). A test renders the stage's frame and the export's frame and compares them.
- **Geometry** comes from Core (`MeshData`: primitives with bevels, drawings, text, characters) and from imported
  models (`ModelLibrary`: glTF through Core's reader, USDZ and OBJ through ModelIO), converted once to the
  renderer's vertex format and cached.
- **Front faces are counter-clockwise**, depth is reverse-Z, uniforms are triple-buffered.

## Documents

A project is a `.maquette` folder package (3D-lowey's `.lowey` ones open too): `project.json`, `scenes/*.json`,
`history/`, `assets/`, `audio/`, `renders/`, a thumbnail and its turntable, and `workspace.json` (how it shows:
Core's `ProjectWorkspace`, outside the journal). Every file is a versioned envelope
`{schemaVersion, kind, payload}`; older versions migrate on load (1.x projects included), newer ones are refused with a
clear message. Writes are atomic and keep a `.bak` of the last good version. The format is documented for readers in
[PROJECT_FORMAT.md](PROJECT_FORMAT.md).

**The history journal** (hmm-kit's `HistoryJournal`, Maquette's `ProjectHistory`): every scene has one in
`history/<scene-id>/`. `CommandStack` records each change as a `HistoryOp` (perform, undo, redo, gesture and group
boundaries); `EditorModel+History` hands them to the journal, which appends them as JSON lines on a serial queue.
Checkpoints (every 200 changes, 5 s idle, backgrounding, closing a scene) write a snapshot, store each undo step once
by reference, then write `project.json` and the scene file from the same state. Opening a scene is
`ProjectHistory.open`: the checkpoint, its newest 64 undo steps, and the tail replayed (older steps load as undo
reaches them). The history scrubber (`HistoryCursor` in Core, Actions ▸ History) walks the undo steps both ways from
wherever it is; versions live in `history/<scene-id>/versions/`. hmm-kit's `DocumentLocator` puts projects in iCloud Drive when the build has the
entitlement, on the device otherwise; `HmmConflictSheet` resolves conflicting versions.

## The layout

docs/LAYOUT.md is the map; the Shell composes it. `RootView` shows Home (`TheaterView`) and presents the open project
over it as a full-screen cover with the zoom transition from the card's picture. `EditorScreen` stacks the stage and
the timeline by `EditorModel.timelinePresence` (hidden, transport, full; height and presence come from and go back to
`workspace.json` through `EditorModel+Workspace`). `StageChrome` lays out the sidebar and the bottom row, then the two clusters and the panel each
opens (last, so a panel is above all chrome); `FloatingInspector` places `InspectorPanel` with hmm-kit's `HmmFloatingPlacement`
beside `EditorModel.selectionScreenRect` (the selection's box projected by the stage, refreshed on edits and after the
camera settles: `EditorModel+Inspector`). Panels resize with hmm-kit's `hmmResizable`.

Home's cards (`Workspace/UI`: `GalleryGrid`, `ProjectCard`, `StackCard`, `TurntableView`) are shared by Home and
the Home benchmark (Diagnostics), so the benchmark measures the real grid. The turntable is drawn after a project
closes (`AppModel.drawCard`, `Thumbnailer.turntable`) and read a frame at a time while a card is visible. Stacks,
search and sort are hmm-kit's `GalleryArrangement` (`gallery.json` in the projects folder; `AppModel+Gallery`).
Starter templates are Core's `StarterTemplate`: a Look and Mood to suggest, a starting viewpoint and a workspace.

## Device tiers and the load meter

`DeviceTier` (hmm-kit, from the GPU family and memory) picks a `PreviewQuality` for the stage: the render-scale range
`DynamicScale` moves in and the sun's shadow-map size; the frame budget comes from the screen's refresh. Exports,
stills and thumbnails always render `.full`. `PerformanceMonitor` feeds hmm-kit's `LoadMeter` with each frame's work
(GPU time, CPU encode time) and the scene's cost (`SceneCost`). The meter is silent: near the limit
`EditorModel.adaptPreview` moves the stage's render-scale range one tier lighter (Engine's `AdaptivePreview`: back after
twenty calm seconds, longer when a recovery doesn't hold), and Diagnostics ▸ Smoothness shows the numbers
(`EditorModel.loadSummary`). `-load-level over` puts a UI test's stage under load.

## Export

`ExportSession` (Engine, main actor) renders frame by frame at full scale with no time budget, straight into the
encoder's pixel buffers, then verifies the file with HmmMedia's inspector (frames, size, duration, audio, alpha)
before returning it. 3D files come from `ModelExport.files` (glTF, USDZ, OBJ + MTL, STL, 3MF, the Blender package). In the background the app keeps exporting under a `BGContinuedProcessingTask`; progress reaches
the Live Activity through `ExportProgressReporting`, and a notification says when it's done.

## The bridge

```mermaid
sequenceDiagram
    participant L as Laptop (hmm-bridge)
    participant B as HmmBridge on the iPad
    participant U as The person at the iPad
    U->>B: Bridge on, "Pair a laptop" (shows a one-time code)
    L->>B: Bonjour _hmm._tcp, GET /v1/hello
    L->>B: POST /v1/pair {code, client}
    B-->>L: token (kept in the iPad's Keychain, listed, revocable)
    L->>B: POST /v2/build {actions} (Authorization: Bearer token)
    B-->>U: proposal banner with a preview picture
    U->>B: Apply (one undo step)
    B-->>L: what changed + an observe of the result
```

MCP v2 is sixteen tools on the laptop over a handful of `/v2` routes: `status`, `project`, `transcript`, `actions`,
`assets` (+ `thumbnail`), `build`, `observe`, `contact_sheet`, `commit`, `media`. Every scene change is a Scene Script
v3 batch compiled by LoweyCore's `ScriptCompiler` (the relation solver, the camera solver, lighting recipes, intents)
into one `EditCommand`. The v1 routes stay for 1.x laptops.

## Perception

`ShotObserver` (LoweyCore, pure Swift) measures a shot: it evaluates the scene at a time, projects every labelled
object through the shot camera into a small depth-tested CPU raster (coverage, visibility, frame cuts), checks
grounding and intersections against the Kit's metadata, reads the frame (thirds, headroom, tangents, clutter) and,
given the rendered pixels, contrast, silhouette, palette and light; `ShotRubric` grades it. `ExportSession.observe`
(Engine) renders the frame like the export, hands the drawn meshes and pixels to the observer and draws the views
(set-of-marks, orthographic diagrams with the camera's wedge, value, silhouette from the ID buffer).

Unpaired requests get 401, requests from outside the local network 403, a pairing attempt while no code is showing
409. The bridge is off by default and switched off entirely in the App Store configuration.

## CI and release

A `changes` job routes each PR by what it touches (docs → nothing, Core → Linux, Engine → render tests, Features/App
→ feature tests, app build and UI tests); every merge to main runs everything. `CI result` is the one required check.

```mermaid
flowchart LR
    Push[PR / main] --> Lint[SwiftLint --strict<br/>SwiftFormat]
    Push --> CoreT[LoweyCore tests<br/>Linux + coverage]
    Push --> Tools[Laptop tools<br/>pytest + generated files]
    Push --> EngineT[LoweyEngine<br/>simulator render tests]
    Push --> FeatT[LoweyFeatures<br/>boundaries + tests]
    Lint --> AppT[App build + UI smoke tests]
    CoreT & Tools & EngineT & FeatT & AppT --> Green
    AppT --> Shots[App Store screenshots<br/>iPad 13" + iPhone 6.9"]
    Green{CI result}
    Green -->|main| IPA[Release: Maquette.ipa artifact]
    Tag[tag v*] --> Gate{commit passed CI?}
    Gate -->|yes| Rel[GitHub Release + .ipa]
    Gate -->|yes, ASC secrets set| TF[TestFlight: App Store build]
```

The tools job also checks that `AppUITests/LayoutWalk.swift` is what `Tools/layout_walk.py` makes of docs/LAYOUT.md;
the UI tests walk every row (five tests, by precondition, Model on its own), measure the idle stage's share of the screen and run the Home benchmark.

Golden images are recorded on the CI simulator (`TEST_RUNNER_GOLDEN_OUTPUT`), reviewed and committed under
`Packages/LoweyEngine/Tests/LoweyEngineTests/Golden`.
