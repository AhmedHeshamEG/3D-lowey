# Phase 2 — "Done when" checklist (v0.8.0)

Evidence for each criterion in `docs/phases.txt`. CI = `.github/workflows/ci.yml`; renders, frames and screenshots are
in the `test-attachments` artifact of each CI run. ⏳ = needs Hesham's iPad (cannot be done in CI).

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | The Enigma opening is animated end to end: paper under a warm lamp and the camera pushes in; the room of people at PCs; the paper grows huge over the room; a big X pops; the hero robot appears; a question mark pops | ✅ | Sample project scene **4 · Opening (animated)** (`EnigmaOpening.swift`), built only with commands, presets, camera moves, behaviours and a Perform take. Every beat is asserted at its time in `EnigmaSampleTests.testOpeningIsAnimatedEndToEnd` (desk camera pushes in, cuts desk → room → cave, screens light up in a wave, the paper grows > 6×, the X pops, the robot rises out of the ground and its eyes light up, the question mark pops, people type on twos). Rendered through its cameras in 16:9 and 9:16: `Phase2Tests.testEnigmaOpeningRendersThroughItsCameras` → attachments `opening-desk-push-in-16x9` … `opening-question-mark-9x16`. The people are blockout puppets whose arms type through a behaviour; skinned "typing" clips work the same way once a rigged office-worker pack is imported. |
| 2a | One motion made with **Perform** | ✅ pipeline / ⏳ by hand | The opening's envelope nudge is a Perform take (samples → `PerformBaker`, 35 % smoothing). Recording by touch — drag/pinch/twist/Pencil roll while it plays — is in the app (Timeline → Perform → ● Record); baking is tested in `MotionTests.testPerformTakeBecomesKeysAndReplacesItsRange`. |
| 2b | One motion with **keyframes** | ✅ | The giant paper's grow + lift and the robot's eye glow are keyframes (`KeyOperations.setKey`); key editing tested in `MotionTests.testKeyOperationsRevertAndBehave`, `testCoalescedKeyingIsOneUndoStep`. |
| 2c | One motion with a **mass stagger** | ✅ | The 12 screens pop on in a wave (`PresetBuilder.apply` with `StaggerSettings`, distance order, random timing); tested in `MotionTests.testMassStaggerOrdersAndRandomises`. |
| 2d | One camera move recorded with **the iPad as the camera** | ⏳ | Camera mode → *Use the iPad as the camera* → *Record the move* (ARKit world tracking → camera keys through Perform, one undo step). ARKit tracking needs the real device. |
| 3 | A rigged tiger walks along a path with a real walk clip | ✅ in CI / ⏳ with the real pack | `Phase2Tests.testRiggedTigerWalksAlongAPathWithItsWalkClip`: the rigged tiger glTF's skeleton and **Walk** clip are read in LoweyCore, the clip poses the RealityKit joints (spine moves), a follow-path behaviour carries it along a curve (`tiger-walks-path` render). Retargeting a walk between two different quadrupeds: `RigTests.testWalkClipPlaysOnTwoDifferentQuadrupeds`. On the iPad: import the animal pack → place the tiger → draw a path → *Add behaviour → Follow path* → *Play a clip → Walk* → *Walk speed = path speed*. |
| 4 | The same sequence exports as 16:9 and 9:16 videos that play in Photos | ✅ in CI / ⏳ Photos | `Phase2Tests.testVideoExportWritesSixteenNineAndNineSixteen` exports both framings in one job, checks sizes, duration and decodes a frame from each (`video-frame-480x270`, `video-frame-270x480`). Determinism: `testExportIsDeterministic`. PNG sequence + transparency: `testPNGSequenceAndTransparentBackground`. On the iPad: Export → *Export video* → *Save to Photos*. |
| 5 | Timeline / easing / behaviour logic is unit tested in LoweyCore | ✅ | `MotionTests` (23), `RigTests` (9), `ExportTests` (3), `TimelineTests`, `EnigmaSampleTests` — ~145 Core tests on Linux; the CI coverage gate (≥ 80 % lines) holds. |

## Everything else in the Phase 2 list

| Area | Where |
|---|---|
| Timeline drawer, Compose / Perform / Keyframe, scrubbing, loop, markers, fps | `TimelineDrawer.swift`, `EditorModel+Animation.swift` |
| Easing presets + curve editor, copy/paste/mirror/retime/reverse, stepping | `KeyOperations`, `EasingEditor`, `Animator.steppedTime` |
| 15 presets, stagger / order / randomise, animated generators | `Presets.swift` (`PresetBuilder.animateGenerator`) |
| Behaviours (path, look at, follow, orbit, wobble, wind, bob, spin), bake | `Behaviors.swift`, `Simulation.bake` |
| Scripting + 3 examples | `LoweyScript` (`ScriptRunner`, `ScriptExamples`), `Phase2Tests.testExampleScriptsBuildAndAnimate` |
| Simulations (fall, explode, flock, crowd) baked | `Simulation.swift`, `MotionTests.testPhysics…`, `testFlockAndCrowdBake` |
| Skeleton standards, auto-mapping, retargeting, clip track, crossfades, IK, crowd, puppets, walk in place | `Rig/`, `CharacterSection`, `EditorModel+Export.swift` (`makeCrowd`, `matchClipSpeedToPath`), `makeJoint` |
| Cameras, cuts, 10 moves, lens, focus pull, framings + safe zones, 9:16 per camera, virtual camera | `CameraMoves.swift`, `CameraLens`, `CameraPanel.swift`, `VirtualCameraController.swift` |
| Frame-by-frame export, both framings in one job, PNG sequence, transparent, 3D export | `VideoExporter.swift`, `ModelExport.swift`, `SceneExport.swift` |

Known limit: depth of field is stored, animatable and editable (focus pulls work) but not yet *rendered*; the lens blur
arrives with Phase 3's post-processing so preview and export blur identically (DECISIONS D50).

## iPad test checklist (after installing the .ipa)

1. **Add the Enigma sample** (Home → ⋯) → open **4 · Opening (animated)** → **Camera** mode → ▶︎. The shot cuts desk →
   room → cave. Try **Export** → 16:9 + 9:16 → *Export video* → *Save to Photos* and play both in Photos.
2. **Perform**: new scene → add a cube → **Animate** → Timeline *Perform* → ● Record → drag it around while it plays
   (twist two fingers or roll the Pencil Pro to turn it) → it plays back your motion. Undo removes the whole take.
3. **Stagger**: add 10 cones (Array → Row of 10) → select the row → *Grow it in* (or select several and tap *Bounce*).
4. **iPad as camera**: Camera mode → *Save camera from view* → *Use the iPad as the camera* → scale 5× → *Record the move*
   and walk around the room.
5. **Tiger**: import your animal pack → place the tiger → Draw a path (tube) on the ground → select the tiger →
   *Add behaviour → Follow path* → *Play a clip → Walk* → *Walk speed = path speed* → ▶︎. Check it with *Show FPS*.
