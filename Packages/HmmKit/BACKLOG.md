# Backlog

Work that belongs to hmm-kit but isn't needed yet. Each item names the phase that needs it.

- **HmmTranscript · WhisperKit engine** (Retake Phase 1): the "Accurate" model downloaded on demand
  (`large-v3-turbo` on M-series iPads, `small` on phones), behind the existing `TranscriptionEngine` protocol.
- **HmmMedia · loudness** (Retake Phase 1): EBU R128 measurement and normalisation with vDSP, a true-peak limiter,
  short crossfades, a waveform-peaks disk cache.
- **HmmBridge · hmm-bridge laptop CLI** (3D-lowey Phase 2): one pip-installable MCP stdio server for every app;
  3D-lowey keeps its own `lowey-mcp` until then.
- **HmmPerception · frame capture service** (3D-lowey Phase 2): the shared `observe` / `contact_sheet` plumbing once
  a second app needs it; 3D-lowey renders its own frames for now.
- **HmmBrush · the brush library and imports** (Cutaway's board): `BrushLibrary`, Procreate `.brushset` / `.brush`
  and Photoshop `.abr` import and Brush Studio still live in Maquette; they move here when a second app needs them.
- **HmmBoard · board layers and brush blend modes**: strokes blend normally on the board; a brush's other blend modes
  need the board drawn in layers.
- **HmmBoardUI · pictures decode on the main thread** the first time they're shown (at most 2048 px on the long
  side); a board of many large photos should decode them off it.
- **HmmBoardUI · very far from the origin** (millions of units) strokes are placed with 32-bit floats and lose
  sub-pixel accuracy; re-centre the placement on the view when someone gets there.
- **HmmBoard · MCP**: the bridge has no board routes yet (read the board, add notes and arrows as a proposal).
