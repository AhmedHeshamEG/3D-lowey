# Phase 4 — report (v1.3.0)

What Hesham asked for, where it is, and how it's proven. CI = `.github/workflows/ci.yml`; renders and screenshots are in
each run's `test-attachments` artifact. ⏳ = needs his iPad.

| # | Asked | Status | Where / evidence |
|---|---|---|---|
| 1 | His drawing as a 3D character, checked in Blender first | ✅ | `assets/avatar` (trace → Blender build → GLB/.blend, `renders/sheet.jpg`) |
| 2 | v2: a designed character (arms, face, hat clue, no legs, hover) | ✅ | `BlobCharacter.swift`, Add → Me / Blob; `Phase4Tests.testBlobCharactersRender`, UI `11-me` |
| 3 | A face that acts: exaggerated, overshooting (Character Animator, Looney Tunes) | ✅ | `BlobRig.swift` (springs, squash & stretch, auto blink, expressions); `BlobCharacterTests` |
| 4 | Anyone recognisable (Newton, Turing…) | ✅ | `Likeness` table + recipes; skill `modules/characters.md` |
| 5 | Stability: crashes, freezes, lag, stuck export | ✅ / ⏳ | Tour crash reproduced + fixed (`testTourRunsToTheEnd`); export watchdog (`testExportWaitsWhileTheAppIsAwayThenFinishes`, `testFullNarratedStoryExportsToTheEnd`); timeline redraws. Device check: long exports with the screen off, general smoothness |
| 6 | Glow on objects | ✅ | shader fix + halo; `testGlowCastsAHalo` |
| 7 | Perform camera = the path you fly | ✅ / ⏳ | `EditorModel+Camera`, `StageCoordinator`; try it on the iPad |
| 8 | Zach D Films zoom | ✅ | `snapZoom` move; `MotionTests` |
| 9 | Minimize button, stats in a corner, Pencil cursor off | ✅ | focus mode, stats pill, `AppSettings.pencilHoverPreview` |
| 10 | Delete colours | ✅ | `Palette.remove(slot:)` (kept hidden so nothing recolours); `ModelTests` |
| 11 | Timeline: groups, organisation, better gestures | ✅ / ⏳ | `TimelineOutline` (+ tests), `TimelineDrawer` gestures; feel on device |
| 12 | QuickShape | ✅ / ⏳ | `QuickShape.swift` (+ 9 tests), `StrokeGestureRecognizer` hold |
| 13 | Gesture guide in the main menu | ✅ | `GestureGuide.swift` (Home ⋯ and scene menu) |
| 14 | Manim + media | ✅ / ⏳ | video overlays, Add → Photo or video, `lowey-link media|manim`, MCP `add_media`/`render_manim`; tools tests encode ProRes 4444 |
| 15 | Skill as orchestrator + modules | ✅ | `skills/lowey` (installed to `~/.claude/skills/lowey`) |
| 16 | MCP works end to end | ✅ | UI test pairs over HTTP, sends a script, approves on the iPad, finds Newton |
| 17 | Premium, sleek, ultraminimal UI | ✅ / ⏳ | Liquid Glass chrome, quieter timeline header, one-menu layout; judge on the iPad |

## iPad checklist
1. First launch: the tour runs without crashing. Export the Enigma story with the screen locking mid-way: it pauses and resumes.
2. Add → Me. Animate → Expressions: tap Shocked, move the playhead, tap Happy. Play: it overshoots and settles.
3. Lip sync him to a voiceover; tap expressions on top.
4. Camera mode → look through → Perform → Record, fly with your fingers.
5. Draw a circle and hold. Four-finger tap. Timeline: fold a group, flick, pinch.
6. Laptop: `lowey-link manim scene.py Graph --at 2` with the bridge on.
