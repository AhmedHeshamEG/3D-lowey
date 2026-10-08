# hmm-kit

The shared foundation of the **hmm.** studio apps (3D-lowey, Retake, Editoro): one design language, one undo
system, one document format, one transcript model, one LAN bridge to Claude, and one set of diagnostics.

Each app pulls hmm-kit in with `git subtree` at `Packages/HmmKit` (so CI needs no extra credentials) and never edits
it in place: changes land here first, then `Tools/sync-hmmkit.sh` in the app pulls them.

## Modules

| Module | What it is | Platforms |
|---|---|---|
| `HmmDesign` | Tokens (neutrals, accents, type scale, 4-pt spacing, radii, motion springs), Liquid Glass chrome, `HmmButton`, `HmmSlider` (Procreate-style vertical slider), `HmmCornerCluster`, `HmmSidebar`, `HmmPanel`, `HmmSheet`, `HmmToast`, `HmmEmptyState`, the universal gestures (`hmmUniversalGestures`), haptics, and the Design Gallery | tokens everywhere; views on iOS/macOS |
| `HmmCommands` | `EditCommand` (apply returns its exact inverse) and `CommandStack` (coalescing, grouping, limits, "Undo Move Camera" labels), plus the Undo menu | everywhere |
| `HmmDocuments` | `DocumentPackage` (`manifest.json` + payload + `assets/` + thumbnail), crash-safe writes with `.bak` recovery, versioned JSON with migration chains, package upgrades with a `.v<N>.bak` copy, debounced autosave, iCloud Drive storage with a local fallback, coordinated access, conflict resolution (keep both / this / other) and its sheet | everywhere; iCloud on Apple |
| `HmmTranscript` | One `Transcript` model, SRT / WebVTT / JSON in and out, script-to-transcript alignment (word-level Needleman–Wunsch with fuzzy costs), the `TranscriptionEngine` protocol and Apple's on-device SpeechAnalyzer engine | everywhere; SpeechAnalyzer on Apple |
| `HmmMedia` | Hardware encoding (H.264, HEVC, HEVC with alpha, ProRes 4444) into IOSurface/Metal pixel buffers with interleaved AAC, export verification, PNG and GIF writers | settings/verification everywhere |
| `HmmBridge` | The LAN link to Claude: HTTP + WebSocket, Bonjour `_hmm._tcp`, pairing with a random single-use code traded for a Keychain token, local-network-only policy, proposals (Apply / Not now) | protocol everywhere; server on Apple |
| `HmmPerception` | The AI's eyes: contact-sheet layout and drawing, set-of-marks markers, the value (squint) view in CIE L*, safe zones for 16:9 / 9:16 / 1:1, reports with a plain-English summary | layout everywhere; drawing on Apple |
| `HmmDiagnostics` | Frame statistics (p50/p95/p99, dropped frames, hitches), the Performance HUD, the benchmark recorder and report, a rotating log with export, signposts, MetricKit | everywhere |
| `HmmStore` | StoreKit 2 app-transaction check for paid-upfront apps | Apple |
| `HmmBrush` | The brush engine's arithmetic: `Brush` (shape, grain, stroke, dynamics, rendering), `BrushStroker` (samples into a stored path, a path into stamps, the same for the live stroke and the kept one), the built-in tips, grains and brushes drawn by code, content keys, `Vec2`, `SeededRandom` | everywhere |
| `HmmBrushRender` | The brush engine on the GPU: `Brush.metal` (one instanced quad per stamp, in a 3D scene or flat), `BrushStamper` (stamp buffers cached per stroke), tip and grain textures, pipelines for stamps, flat fills and pictures | Apple (Metal) |
| `HmmBoard` | The Schizzo board, pure: brush strokes, pictures, notes, arrows and frames on an endless sheet; every change a command with its exact inverse; `BoardSession` (tools, selection, drags, the stroke in progress); the view; the draw list every picture of a board comes from; `BoardStore` (the board, its history journal and pictures in a folder any document can hold) | everywhere |
| `HmmBoardUI` | The board on screen: `BoardRenderer` (Metal: the board kept in one layer, strokes by the brush engine), `BoardCanvasView` (Pencil or hand, pan, pinch, hover, the hold menu, drops), `BoardModel`, and `HmmBoardScreen` in the studio's layout | iOS |

## Using it

```swift
// Package.swift of an app package
.package(path: "../HmmKit")
// …
.product(name: "HmmCommands", package: "HmmKit")
```

## Building and testing

No Mac is needed. The pure parts build and test on Linux (`swift test` in the `swift:6.1` container, locally through
Docker); the SwiftUI, AVFoundation, Network and Speech parts are tested in the iOS simulator on GitHub Actions. See
[docs/CI.md](docs/CI.md) for the recipe every hmm. app reuses.

```sh
docker run --rm -v "$PWD:/work" -w /work swift:6.1 swift test
```

## Versions

See [CHANGELOG.md](CHANGELOG.md). 0.x while the three apps move onto it; 1.0.0 once all three consume it.
