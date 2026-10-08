# Changelog

All notable changes to hmm-kit. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

## [0.5.0] - 2026-10-08

Built with Maquette 0.9.

### Added
- **HmmBrush**: the brush engine's arithmetic, moved here from Maquette so every app draws with the same brushes.
  `Brush` and its settings, `BrushStroker` (Pencil samples into a stored path, a path into stamps, seeded so a stroke
  is the same in every render), the built-in tips, grains and ten brushes (all drawn by code), `BrushKey` content keys,
  `Vec2` and `SeededRandom`. A point a brush walks along says its coordinates (`BrushPoint.brushCoordinates`), so one
  renderer draws 2D and 3D strokes.
- **HmmBrushRender**: the brush engine's Metal half. `Brush.metal` stamps strokes in a 3D scene or flat; flat strokes
  can stay in their own units and be placed by the shader (`BrushBatch.Placement`), with a texturized grain fixed to
  those units and hairlines kept visible far out. `BrushStamper`, `BrushTextureCache`, and `BrushShaders` (the
  library and pipelines for stamps, flat fills, layers and pictures).
- **HmmBoard**: the Schizzo board. An endless sheet of brush strokes, pictures, notes, arrows (their ends follow what
  they point at) and frames (they carry what lies in them). `BoardCommand` with exact inverses, `BoardOperations`,
  `BoardSession` (the six tools, selection, moving and resizing, an eraser that cuts strokes where it touched, copy
  and paste between boards), `BoardViewport`, `BoardDrawList` and `BoardLayerPlan` (what a board looks like and when
  its cached picture must be redrawn), `BoardStore` (`board.json`, the history journal, pictures by content).
- **HmmBoardUI**: the board on screen. `BoardRenderer` keeps the board in one layer a little larger than the screen and
  draws only what moves over it; `BoardCanvasView` takes the Pencil (pressure, tilt, coalesced and predicted touches),
  fingers that pan and pinch, hover, the hold menu and dropped pictures; `BoardModel` journals every change and can
  hand the app a picture of a frame or a selection as a pin; `HmmBoardScreen` is the whole screen in the studio's
  layout, with the app's own brush row and colour chooser plugged in.

## [0.4.0] - 2026-10-07

Built with Maquette 0.8.

### Added
- **HmmDesign**: `HmmHoldMenu`, the hold menu's one grammar: Duplicate · Rename · Copy · Paste, one to three extras,
  Delete last in red; a row a thing can't do is dimmed, never missing. `hmmHoldMenu(_:)` puts it on any SwiftUI view,
  `uiMenu()` builds it for UIKit, and `HmmHoldMenuInteraction` opens it under a still finger on a canvas (a moving
  finger stays a drag); `hmmHoldMenu(at:)` does the same over an area SwiftUI draws as one picture.
- **HmmDesign**: `HmmPencilOrHand`: one finger makes until an Apple Pencil has touched; from then on the Pencil makes
  and fingers move the view, with one switch to let fingers make too. Remembered in `UserDefaults`.
- **HmmDesign**: `HmmColourWell`, and `HmmSidebar(accessory:)` to put it (or anything a tool needs) under the two
  sliders.

## [0.3.0] - 2026-10-05

Built with Maquette 0.2.

### Added
- **HmmDesign**: resizable panels. `HmmPanel(sizing:)` shows a grip in the bottom corner away from the edge the panel
  hangs from; dragging it resizes the panel, double-tapping it restores the original size, and the size is
  remembered per panel on the device (`HmmPanelSizing`, `HmmPanelSize`). Any view gets the same grip with
  `hmmResizable(_:size:defaultWidth:…)` (an inspector placed by `HmmFloatingPlacement` sizes itself from it).
- **HmmDesign**: `HmmFloatingPlacement`, where a floating panel goes beside what it's about (an inspector beside the
  selection): keeps its side while it fits, flips at the screen's edge, covers as little as it can when neither side
  fits, stays inside the bounds.
- **HmmDocuments**: `GalleryArrangement`, the Home gallery's stacks, search and sort (Recent, Name, Date created),
  saved as `gallery.json` beside the documents.

## [0.2.0] - 2026-10-04

Built with Maquette 0.1.

### Added
- **HmmDocuments**: `HistoryJournal`, the history journal of CONTEXT §5. Every committed change is one JSON line in
  a segment, group-committed within 50 ms on a serial queue; checkpoints (snapshot + undo history stored once per
  step) keep opening to the checkpoint plus a short tail; the undo stack is restored on open, older steps load
  lazily; a half-written last line is skipped, a damaged checkpoint falls back to the previous one; recorded ops
  migrate across command schemas. `HistoryVersions` keeps named and automatic versions.
- **HmmCommands**: `HistoryOp` and journaling on `CommandStack` (`recordsOps`, `takePendingOps`, `replay`,
  `restore`, `prependUndo`, `isQuiet`); `HistoryEntry` has a stable `id` and is `Codable` when its command is.
- **HmmDiagnostics**: `DeviceTier` (A/B/C from the GPU family and memory, `-device-tier` override) and `LoadMeter`
  (the hidden load meter: frame-time and scene-cost pressure with hysteresis).

## [0.1.0] - 2026-10-01

First release, created with 3D-lowey 2.0.

### Added
- **HmmDesign**: tokens (dark and light neutrals, one accent per app, semantic colours, type scale, 4-pt spacing,
  radii, touch targets, motion springs with a Reduce Motion cross-fade); Liquid Glass chrome with a Reduce
  Transparency fallback; `HmmButton`, `HmmPillButton`, `HmmSlider`, `HmmCornerCluster`, `HmmSidebar`, `HmmPanel`,
  `HmmSheet`, `HmmSectionHeader`, `HmmToast`, `HmmEmptyState`; the universal gestures (two-finger tap undo,
  three-finger tap redo, two-finger hold rapid undo, four-finger tap hides the chrome); haptics; the Design Gallery.
- **HmmCommands**: `EditCommand`, `CommandStack` (coalescing, nested groups, cancel, limits, menu titles) and the
  Undo menu commands.
- **HmmDocuments**: `DocumentPackage` with `manifest.json`, `SafeFileWriter` (atomic, `.bak` recovery),
  `SchemaCoder` (versioned JSON, migration chains), `PackageMigrator` (upgrades with a `.v<N>.bak` copy),
  `AutosaveScheduler`, `DocumentLocator` (iCloud Drive with a local fallback), coordinated access,
  `DocumentPresenter`, `ConflictResolver` and `HmmConflictSheet`.
- **HmmTranscript**: `Transcript`, editing that keeps timings, SRT / WebVTT / JSON, script alignment,
  `TranscriptionEngine` with engine selection by supported language, `SpeechAnalyzerEngine`.
- **HmmMedia**: `EncodeSettings`, `VideoEncoder` (H.264, HEVC, HEVC with alpha, ProRes 4444, AAC),
  `MediaInspector` and `ExportVerification`, PNG and GIF writers.
- **HmmBridge**: HTTP parsing and serialisation, local-network policy, `PairingAuthority` (random single-use
  6-digit code valid for 5 minutes, five tries, 32-byte tokens), `KeychainClientStore`, `BridgeRouter`,
  `BridgeServer` (Bonjour `_hmm._tcp`, WebSocket events for paired clients only), proposals and their card.
- **HmmPerception**: contact-sheet layout and drawing, set-of-marks placement and drawing, the value view,
  safe zones, `PerceptionReport`.
- **HmmDiagnostics**: `FrameStats`, `PerformanceHUD`, `BenchmarkRecorder` / `BenchmarkReport`, `RotatingLog`,
  signposts, memory footprint, `MetricsSubscriber`.
- **HmmStore**: `PurchaseVerifier` (StoreKit 2 app transaction).
