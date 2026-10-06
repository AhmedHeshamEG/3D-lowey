# Backlog

What's known and not done yet, so nothing lives only in someone's head. What Maquette is: [SPEC.md](SPEC.md). The
phase plan (M2 … M8, then 1.0) lives in studio-h's `PHASES.md`; ideas go to its `IDEAS.md`.

## Left from M7 (Maquette 0.7)

- [ ] The device checklist in the "Maquette 0.7 — M7" PR (drawing bones with the Pencil on a placed model, a modelled
      part and a drawing; how fast the weights arrive on a big model; posing by dragging joints; painting weights and
      the weight view; rigging a person by the eight taps; a clip on the person rig; exporting a posed character and
      printing it).
- [ ] Apple's body-pose model placing the person rig's dots: the spike couldn't run it on CI (D-168); try it on the
      iPad, and ship it only with a device check of its own.
- [ ] glTF and the Blender package carry rigs as their posed shape, not as a skeleton with weights and keys (an
      armature in Blender). (D-173)
- [ ] Painting imported skinned characters (their own skeleton): still refused. (D-171, D-162)
- [ ] Weights update when a weight stroke ends, not under the brush as it moves. (D-172)
- [ ] Onion-skin ghosts of a rigged solid show it unposed.
- [ ] A drawn bone can't be removed on its own yet (Remove the rig takes them all; undo takes back the last one).
- [ ] The MCP bridge can't draw bones or rig a person yet (Scene Script v3 knows Puppets and clips).
- [ ] The layout walk's Model (and now and then Home) rows time out a UI query on CI's simulator: M5, M6 and M7's
      merges needed re-runs. (PR #22 looked at the stall in the New project sheet.)
- [ ] "A block with a hole in under thirty seconds" is timed on CI against 45 s (D-175); the 30 s is a device check.

## Left from M6 (Maquette 0.6)

- [ ] The device checklist in the "Maquette 0.6 — M6" PR (painting feel with the Pencil, strokes landing only on what
      the camera sees, layers, fill and the eyedropper, a projected picture, painting a placed Kit model, undo after
      relaunch, the painting benchmark at Tier A and as Tier B, an exported glTF and USDZ opened elsewhere).
- [ ] Roughness, metal and glow painting (CONTEXT §10.4 "later"): today paint is colour only.
- [x] Painting characters with M7's skeletons: drawn rigs are painted in their rest pose (D-171); imported skins
      are in "Left from M7".
- [ ] Paint files no history refers to any more are kept: a cleanup when old versions are pruned.
- [ ] Every painted object keeps its layers on the GPU while it's drawn (16 MB a layer at 2048); objects not being
      painted could keep only their composite.
- [ ] A soft brush on a curved surface stamps in screen space: its dabs stretch slightly where the surface turns away
      (faded by the facing falloff, D-152).
- [ ] The eyedropper finds the closest triangle by a scan of the surface (fine at 50k triangles, slow far beyond).

## Left from M5 (Maquette 0.5)

- [ ] The device checklist in the "Maquette 0.5 — M5" PR (drawing feel with every built-in brush, prediction, tilt
      shading, the latency numbers, Brush Studio and its pad, importing real Procreate and Photoshop files, the guides
      with the Pencil, sharing a set by AirDrop).
- [ ] Brush settings Procreate has and the engine doesn't yet: colour dynamics, dual brush, wet mix and bleed, smudge
      and erase per brush. (D-141)
- [ ] The eraser is still a circle of points on screen, not a brush.
- [ ] Vanishing points are set with sliders; dragging them on the stage while the guide is shown. (D-149)
- [ ] The touch-to-screen latency is an upper bound (GPU completion + one refresh) until the SDK gives a drawable's
      presented time again. (D-146)
- [ ] A texturized grain on ink is fixed to the screen, so it slides over a stroke when the camera moves.
- [ ] 3D exports (glTF, USDZ, the Blender package) carry ink as its ribbon, not its brush stamps. (D-143)

## Left from M4 (Maquette 0.4)

- [ ] The device checklist in the "Maquette 0.4 — M4" PR (bevel, round, inset and shell on real parts; symmetry while
      modelling; snapping and the snap marks with the Pencil; measure and kept dimensions; the section view; the
      print check on a real part and the STL in a slicer; walls, doors, windows and stairs; the Blender package on a
      computer).
- [ ] Moving picked corners and edges (dragging them): M3's picks can bevel now, but not move.
- [ ] Rounded corners where three rounded edges meet are pointed (the cuts meet), not a rolling-ball patch. (D-125)
- [ ] The section view's cut faces are back faces drawn flat, not real caps: a thin open surface shows through. (D-131)
- [ ] FBX: not offered while the SDK's licence keeps it out (D-133); glTF covers the same apps.
- [ ] Core failure messages (booleans, push/pull, bevel…) reach the screen in English; the String Catalog only holds
      chrome strings (an M3 gap too).

## Left from M3 (Maquette 0.3)

- [ ] The device checklist in the "Maquette 0.3 — M3" PR (sketching and push/pull with the Pencil and fingers, the
      floating numbers and the keyboard, picks and the Pencil loop, booleans on real models, the marks' look).
- [ ] Curves that cross each other don't split into separate regions yet: only closed curves (and open ones joined
      end to end) fill. (D-121)
- [x] Bevelling picked edges, snapping to edges, midpoints and faces, the measure tool and kept dimensions (0.4).

## Left from M2 (Maquette 0.2)

- [ ] The device checklist in the "Maquette 0.2 — M2" PR (the layout on the iPad, the inspector beside the
      selection, time on call, panel resizing, Home's turning cards and the zoom into the stage, stacks, the
      templates, the Home benchmark at Tier A).
- [x] The print-bed outline in *Model to print* and the walls tool (Model ▸ Add ▸ Building) arrived in 0.4. (D-111)
- [ ] *Sketch* in New project when the Schizzo board exists (M9). (D-111)

## Left from M1 (Maquette 0.1)

- [ ] The device checklist in the "Maquette 0.1 — M1" PR (hover, force-quit recovery, the History scrubber, the
      benchmark at Tier A and as Tier B, the load chip).
- [ ] Calibrate `SceneCost`'s comfortable amounts per tier from the device benchmark JSONs. (D-97)

## Left from the remaster

- [ ] The device-only checklist in the "Remaster 2.0 — Phase 1" PR (#11).
- [ ] The device-only checklist in the "Remaster 2.0 — Phase 2" PR.
- [ ] Run the skill's evals against the iPad (`python skills/lowey/evals/run_evals.py`) and record the results and
      Hesham's verdicts in `skills/lowey/evals/runs/`. CI can't: it has no paired iPad and no API key. (R50)

## Planned (from 2.0)

- The laptop bridge in the App Store build, after App Review of its local network use. (R52)
- A studio bundle with the other hmm. apps; the StoreKit configuration is ready for testing it. (R52)

## Known limitations

- **Booleans keep everything in one object.** Subtracting a shape that splits a solid in two leaves both pieces in
  the first object; there's no Separate yet. Booleans need closed solids; a plane or an open drawing is
  refused with a message.
- **The renderer's mesh cache keys editable meshes by a 64-bit fingerprint.** Two different meshes with the same
  fingerprint would share a GPU mesh; with FNV-1a over every coordinate that's vanishingly unlikely. (D-116)

- **The inspector moves after things stop.** While you orbit or drag, it stays where it was and glides beside the
  selection once the view or the object rests (measuring every frame would cost the stage frames). (D-105)
- **A card shows its still until the project is opened and closed once in 0.2.** Turntables are drawn when a
  project closes; projects from earlier versions keep their old preview until then.

- **A change made in the last 50 ms before the app is killed can be lost.** The journal group-commits within 50 ms
  (D-90); nobody force-quits that fast, but a crash can.
- **Undo keeps 500 steps.** Older ones are dropped from undo (they stay in the journal's segments); the automatic
  versions (each opening, each hour of work) reach further back.
- **3D-lowey projects start their journal when Maquette first opens them.** Their earlier history doesn't exist, so a
  future time-lapse of them starts there.
- **The load meter's scene costs are estimates** until the device benchmarks calibrate them (D-97).
- **The brush outline's line gets thicker with the brush.** It's the gizmo's ring mesh scaled (the Shadow Brush's
  resize outline), for every brush tool including Paint ▸ Colour.

- **A script loop that never calls the API can't be stopped.** The time limit is checked at every `lowey` / `scene`
  call; JavaScriptCore has no public execution time limit on iOS. A pure `while (true) {}` keeps its worker thread
  busy until the app quits. (R29)
- **Golden images come from the simulator.** They catch regressions in the pipeline, not device-specific GPU
  differences; device renders are checked by eye from the PR's device checklist. (R8)
- **4K HEVC isn't exercised in CI.** The simulator's encoder has none; CI runs the same pipeline at 1080p H.264 and 4K
  HEVC is a device check. (R9)
- **MetalFX upscaling is device-only.** The simulator falls back to bilinear scaling, so dynamic resolution quality is
  a device check. (R9)
- **Sideloaded builds have no iCloud.** A free Apple ID can't sign the iCloud entitlement; projects stay on the
  device and move between devices as `.loweypack` files. (R24)
- **Live Activities depend on the system.** The export's Live Activity shows where the system displays them; the
  finished-export notification always arrives. (R19)
- **Only the sun casts shadows.** Point and spot lights light but don't shadow. (R6)
- **Perception's raster is about 320 × 180.** Coverage and visibility are exact at that size; subjects under about 3%
  of the frame aren't judged on their silhouette, and skinned characters are measured by their box. (R48)
- **Anticipation isn't measured.** The Motion line checks arcs, holds, easing and words; anticipation before big moves
  is in the critique module's checklist for the model to look for. (R48)
- **Some messages stay English.** Plurals built inside a sentence ("model\(n == 1 ? "" : "s")") aren't in the String
  Catalog; everything else is translated. (R51)
- **Placement is by boxes and Kit surfaces.** The relation solver knows a model's box, its top surfaces and its front;
  it doesn't fit concave shapes (a chair can't be slid under a desk by relation; use `offset`). (R46)

## Device checks for every release

Pencil hover on and off with every tool · force-quit mid-edit, reopen, undo · the History scrubber · the Night Market
benchmark numbers and its JSON (and the Tier B run on an M iPad) · Pencil pressure on drawing and the Shadow Brush · Pencil Pro squeeze
and roll · face capture (front camera) and the iPhone companion · the ARKit virtual camera · SpeechAnalyzer on a real
voiceover (English, Italian, Arabic) · thermal behaviour during a 5-minute 4K export · iCloud sync between iPad and
iPhone (App Store build) · pairing the bridge from a laptop.
