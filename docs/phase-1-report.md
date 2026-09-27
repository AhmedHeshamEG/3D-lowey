# Phase 1 — "Done when" checklist (v0.4.0)

Evidence for each criterion in `docs/phases.txt`. CI = `.github/workflows/ci.yml`; renders and screenshots are in the
`test-attachments` artifact of each CI run.

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | CI is green and every `main` push produces an installable .ipa | ✅ in CI / ⏳ on device | CI: lint → Linux core tests (coverage gate) → iPad simulator build + render tests + UI smoke test. `release.yml` builds `Lowey.ipa` (unsigned device build → ad-hoc codesign → `Payload/`) on every `main` push; tag `v0.4.0` publishes a GitHub Release. **Install on the iPad with Sideloadly is the one step only Hesham can do** (README → *Install*). |
| 2 | The Enigma scenes can be built as static sets (desk + paper + warm lamp; room of people at PCs; hero robot in a cave) from library assets + blockout + drawing, saved, closed, reopened — identical | ✅ | `EnigmaSample` builds all three through the command system (blockout, drawn tube lamp arm, lathe stalagmites, array of 12 workstations, lights). Tests: `EnigmaSampleTests.testSaveCloseReopenIdentical`, `ProjectStoreTests.testCreateSaveCloseReopenIsIdentical` (bit-identical re-save), `SerializationTests.testSceneRoundTripIsIdentical`. Renders: `enigma-1/2/3-16x9`, `-9x16` (RenderTests), app screenshots `sample-scene-1/2/3` (UI test). Library assets in scenes: `RenderTests.testFiftyInstancesPlaceAndRender`, swap blockout → asset: `OperationsTests.testSwapFitsTheBlockout`. |
| 3 | Undo/redo works across every action | ✅ | Every command type reverts exactly and round-trips JSON (`CommandTests`, `assertReverts`); every high-level operation (add, duplicate, delete, transform, group/ungroup, reparent, array, scatter, align, distribute, swap, colour, flags, prefab save/unpack, look changes, drawing) is asserted with `assertReverts` in `OperationsTests`; full undo-all/redo-all walk in `EditSessionTests.testUndoRedoAcrossEveryKindOfAction`; gestures coalesce into one step (`testCoalescingMakesOneUndoStep`); UI smoke test drives duplicate / undo / redo / delete / undo in the real app. |
| 4 | A glTF animal pack imports with thumbnails and can be placed 50 times with no frame drop | ✅ import & 50 instances in CI / ⏳ fps on device | `RenderTests.testAnimalPackImportsWithThumbnailsAndRig` (4 GLB models incl. a rigged quadruped with a Walk clip → library entries, thumbnails on disk, rig = quadruped, clip kept, searchable). `RenderTests.testFiftyInstancesPlaceAndRender` (50 scattered instances, all share one mesh resource → batched, rendered). The 60 fps check needs the real iPad: open *Show FPS & stats* in the scene menu, scatter 50 animals, orbit. |
| 5 | Core test coverage ≥ 80 % | ✅ | 106 LoweyCore tests; ~97.8 % line coverage (enforced in CI: build fails below 80 %). |

## iPad test checklist (after installing the .ipa)

1. Open **Enigma — sets** → switch between the three scenes (scene menu). Check the warm lamp, the room, the robot.
2. **+** → Cube, drag it, use the joystick, undo with a 2-finger tap, redo with a 3-finger tap.
3. **Draw** tool → Pencil: draw a tube on the plane facing you, then switch to *Lathe* and draw half a vase profile.
4. **Library → Import**: pick a folder of glTF/GLB animals. Tap one, then **Scatter** 50 of them; turn on *Show FPS & stats*.
5. Home → reopen the project: everything is where you left it. **Export** → snapshot 9:16 → share to Photos.
