# Backlog

What's known and not done yet, so nothing lives only in someone's head. What 2.0 is: [SPEC.md](SPEC.md).

## Left from the remaster

- [ ] The device-only checklist in the "Remaster 2.0 — Phase 1" PR (#11).
- [ ] The device-only checklist in the "Remaster 2.0 — Phase 2" PR.
- [ ] Run the skill's evals against the iPad (`python skills/lowey/evals/run_evals.py`) and record the results and
      Hesham's verdicts in `skills/lowey/evals/runs/`. CI can't: it has no paired iPad and no API key. (R50)

## Planned for 2.1

- The laptop bridge in the App Store build, after App Review of its local network use. (R52)
- A studio bundle with the other hmm. apps; the StoreKit configuration is ready for testing it. (R52)

## Known limitations

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

The Night Market benchmark numbers and its JSON · Pencil pressure on drawing and the Shadow Brush · Pencil Pro squeeze
and roll · face capture (front camera) and the iPhone companion · the ARKit virtual camera · SpeechAnalyzer on a real
voiceover (English, Italian, Arabic) · thermal behaviour during a 5-minute 4K export · iCloud sync between iPad and
iPhone (App Store build) · pairing the bridge from a laptop.
