# Changelog

All notable changes to hmm-kit. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

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
