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
