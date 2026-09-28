# Phase 3 — "Done when" checklist (v1.0.0)

Evidence for each criterion in `docs/phases.txt`. CI = `.github/workflows/ci.yml`; renders and screenshots are in the
`test-attachments` artifact of each CI run. ⏳ = needs Hesham's iPad, voice or laptop (cannot be done in CI).

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | The Enigma voiceover is imported, the transcript appears with word markers, every shot is synced to its words | ✅ pipeline / ⏳ his voice | Import or record → **Transcribe** (SpeechAnalyzer + SpeechTranscriber, `.audioTimeRange`; `SpeechService.swift`) → words lane, transcript panel, snapping. The sample **5 · The story (narrated)** is synced by word: every beat is addressed as `{"word": …}` and checked in `EnigmaSampleTests.testTheStoryIsNarratedAndSyncedToWords`. `Phase3Tests.testSpeechAnalyzerGivesWordTimes` runs Apple's transcriber on a spoken sentence when the simulator has the model (skipped on the CI simulator, which lacks it — run on the iPad). |
| 2 | His own character narrates at least one shot with automatic lip sync and face performance | ✅ lip sync + keyed face / ⏳ live face | The story's narrator "Me" (character builder, Humanoid standard) plays *Idle* then *Talk*, lip-syncs "What's the big secret hidden for 85 years?" (CMUdict visemes, stepped mouth shapes) with keyed brows, blinks and a head turn — `testTheStoryIsNarratedAndSyncedToWords`, render `story-narrator-question-*`. Live face capture (Vision front camera, or the iPhone companion over the LAN) drives the same channels and records through Perform — needs the device. |
| 3 | Claude, via lowey-mcp on the laptop, builds one full shot from a line of the script; Hesham then edits it by hand | ✅ pipeline / ⏳ live session | `tools/lowey` (lowey-mcp: 16 tools, 4 resources, 5 prompts; `shot-planner` skill). A whole shot is one `run_script` → preview on the iPad → Apply → one undo step, then ordinary objects/keys to edit. The action language that Claude writes is tested end to end in `ScriptCompilerTests.testAShotFromOneLineOfTheScript` (17 actions from one line) and the MCP tools against a fake bridge in `tools/lowey/tests`. |
| 4 | VFX, overlays, captions and post are in the video | ✅ | Rendered by the exporter in `Phase3Tests.testNarratedStoryRendersWithPostOverlaysAndCaptions` (16:9 and 9:16 at "1941", "Enigma", "Nobody", "AI", "secret"): label following the paper, typewriter title, glitch, flash + shake, sparks, embers, question mark, punchy captions, cinematic finish; `testLensBlurAndInkOutlines`, `testParticlesAndCharacterRender`, `testEveryOverlayShapeDraws`. |
| 5 | The full Enigma video exports in 16:9 and 9:16, upload-ready | ✅ in CI / ⏳ Photos | Export mode → 16:9 + 9:16 → *Export video*: frames composited, soundtrack mixed in (AAC) — `testVideoExportCarriesTheSoundtrack`, `Phase2Tests.testVideoExportWritesSixteenNineAndNineSixteen`; captions burned in or exported as .srt. |
| 6 | Idea-to-screen time for a new simple shot is measured and written in README.md | ⏳ | README → *Idea-to-screen time*: the method and the parts the app controls; the by-hand number must be timed by Hesham on the iPad (three runs, median). |
| 7 | No known crash, CI green, docs up to date, release v1.0.0 published with the .ipa | ✅ / release on merge | CI green on `phase-3`; README, ARCHITECTURE (Phase 3 section), DECISIONS (D53–D72), CHANGELOG (1.0.0), THIRD_PARTY updated. Local diagnostics (log, MetricKit) in place for anything the device finds. Tag `v1.0.0` after merging to `main`. |

## Everything else in the Phase 3 list

| Area | Where |
|---|---|
| Keyframe multi-select (box, Pick menu, stretch band, multi-bar compose) | `KeySelection.swift`, `TimelineDrawer.swift` (lanes gesture layer) |
| Audio tracks, waveforms, fades, envelopes (ducking), recording, import | `Audio/`, `AudioSupport.swift`, `EditorModel+Audio.swift`, `AudioViews.swift` |
| Word markers, snapping, transcript panel, corrections that keep timing | `Audio.swift` (`WordSnap`, `TranscriptEditing`), `TranscriptPanel` |
| Visemes from words, jaw fallback, two mouth systems | `LipSync.swift`, `FaceRig` (swap shapes; `jawOpen` scales mouths without a set) |
| Vision face performance, iPhone companion | `FaceCapture.swift`, `FaceLink.swift`, `CompanionView.swift` |
| Character builder, humanoid clips, library | `CharacterBuilder.swift`, `PuppetRig.swift`, `BuiltinClips.swift`, `CharacterViews.swift` (save with *Save to library*) |
| 2D overlays, 3D text, captions (+SRT/VTT, burn-in) | `Overlay.swift`, `Text3D.swift`, `Captions.swift`, `OverlayRenderer.swift` |
| Particles (10 presets), post (bloom… lens blur, textures), screen effects, transitions, match cut | `Particles.swift`, `Post.swift`, `FrameCompositor.swift`, `StagePost.swift` |
| Scene Script v2, JSON Schema, import from Files / clipboard / share, preview, one undo step | `ScriptCompiler.swift`, `schemas/scene-script.schema.json`, `EditorModel+AI.swift` |
| LAN Bridge (HTTP + WebSocket, pairing, LAN-only) | `Bridge.swift` (Core), `BridgeServer.swift`, `BridgeModel.swift` |
| lowey-mcp, lowey-link, generator hook, skills | `tools/lowey`, `skills/` |
| Projects: .loweypack, archive, copy scenes | `ProjectPackage.swift`, Home screen |
| Performance: thermal-aware preview, particle bands, shared materials | D59, D72 |
| Onboarding: welcome island + 60-second tour | `IslandSample.swift`, `TourView.swift` |
| Keyboard (menu bar), Pencil hover, haptics, accessibility labels, localisation scaffold | `Commands.swift`, `StageCoordinator` hover, `Localizable.xcstrings` |
| Crash / diagnostic log, Export diagnostics | `Diagnostics.swift` |

## iPad test checklist (after installing the .ipa)

1. **Tour**: first launch plays the 60-second tour on the welcome island (or Home ⋯ → *Take the tour*).
2. **The story**: Enigma → *5 · The story (narrated)* → Camera mode → ▶︎. Sound, captions, effects, narrator's mouth.
   Export 16:9 + 9:16 → Save to Photos → play both.
3. **Your voice**: new scene → 〰 → *Record voiceover* (read a script line) → *Transcribe* (first time downloads the model)
   → words lane → transcript: pick a word → *Camera move here*.
4. **You as a character**: **+** → Character → build yourself → Animate → *Play a clip → Talk* → *Lip sync to the
   voiceover* → *Face (front camera)* → Timeline Perform → ● Record → talk. (Optional: iPhone with Face ID → *Use my iPhone*.)
5. **Claude**: iPad bridge on → laptop `pip install -e tools/lowey`, `lowey-link pair …`, `claude mcp add lowey -- lowey-mcp`
   → "build the 'Nobody could' shot" → Apply on the iPad → edit something by hand.
6. **Time it**: a new simple shot by hand (world + character + camera move + synced to a word) — write the median of
   three runs into README → *Idea-to-screen time*.
7. **Multi-select keys**: Animate → Timeline → *Select* → drag a box over several rows → drag the band's end to stretch.
