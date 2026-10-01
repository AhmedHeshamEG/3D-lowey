# Backlog

What's known and not done yet, so nothing lives only in someone's head. The phase 2 scope is in
[SPEC.md](SPEC.md#planned-for-20); this list is everything else, plus the phase 2 work in the order it's planned.

## Phase 2 (toward 2.0)

1. Draw: ink strokes (pressure ribbons on guides) next to the solid shapes; stroke editing (select, move, erase,
   smooth, width); strokes animatable like any object.
2. Animation: flipbook tracks on the stage, per-object frame rate up to fours, motion paths with editable keys, 3D
   onion skin, the graph editor, smears, a pose library with mirror, IK handles, multi-select everywhere.
3. One Cast panel for Blob, Puppet and Rigged; blob silhouettes (inverted hull), face decals with inner lines, Shadow
   Brush presets; blob measurements generated from `assets/avatar/trace.json`; built-in clips on all three types.
4. Fly: the on-screen stick or a game controller flies the camera while Perform records; the full shot-type and
   composition vocabulary in Frame shot.
5. The Kit: `Tools/fetch-kit.py`, about 300 curated CC0 assets with metadata, Sets in the library, `LICENSES.md`.
6. SFX track with a small CC0 foley set; attach-to-word for sounds.
7. Samples rebuilt in the Ink, Comic and Sketch Looks with kit assets; the tour rewritten for the new layout.
8. Perception (`observe`, `contact_sheet`) through HmmPerception, MCP v2 with 16 intent tools, Scene Script v3
   (relations), the rewritten `lowey` skill with evals.
9. English, Italian and Arabic (right-to-left), an accessibility pass, state restoration, Stage Manager windows.
10. App Store readiness: icon, screenshots from UI tests, privacy manifest, StoreKit configuration, a TestFlight step
    in the release workflow that runs only when the App Store Connect secrets exist.

## Known limitations

- **A script loop that never calls the API can't be stopped.** The time limit is checked at every `lowey` / `scene`
  call; JavaScriptCore has no public execution time limit on iOS. A pure `while (true) {}` keeps its worker thread
  busy until the app quits. (R29)
- **Golden images come from the simulator.** They catch regressions in the pipeline, not device-specific GPU
  differences; device renders are checked by eye from the PR's device checklist. (R8)
- **4K HEVC isn't exercised in CI.** The simulator's encoder has none; CI checks the 4K pipeline at 1440p H.264 and
  4K HEVC is a device check. (R9)
- **MetalFX upscaling is device-only.** The simulator falls back to bilinear scaling, so dynamic resolution quality is
  a device check. (R9)
- **Sideloaded builds have no iCloud.** A free Apple ID can't sign the iCloud entitlement; projects stay on the
  device and move between devices as `.loweypack` files. (R24)
- **Live Activities depend on the system.** The export's Live Activity shows where the system displays them; the
  finished-export notification always arrives. (R19)
- **Only the sun casts shadows.** Point and spot lights light but don't shadow. (R6)

## Device checks for every release

The Night Market benchmark numbers and its JSON · Pencil pressure on drawing and the Shadow Brush · Pencil Pro squeeze
and roll · face capture (front camera) and the iPhone companion · the ARKit virtual camera · SpeechAnalyzer on a real
voiceover (English, Italian, Arabic) · thermal behaviour during a 5-minute 4K export · iCloud sync between iPad and
iPhone (App Store build) · pairing the bridge from a laptop.
