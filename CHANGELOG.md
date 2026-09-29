# Changelog

All notable changes. Versions follow the phase plan (Phase 1 = v0.1 → v0.4, Phase 2 = v0.5 → v0.8, Phase 3 = v0.9 → v1.0,
Phase 4 = v1.1 → v1.3).

## [1.4.1] — Joystick, bridge that stays up, clean shots

- **Joystick, one layout in every mode.** The stick works on the ground (red X and blue Z, drawn inside the pad the way
  they lie from where you look), the green slider on the vertical (Y): Move slides / lifts, Rotate tips the object
  (stick) and spins it (slider). Analog: gentle near the middle, full speed at the rim, and speeds are per second (the
  pad assumed 60 frames a second, so on a 120 Hz screen or when frames dropped it jumped). No snap jump when you let go
  of a joystick turn. Stick and slider together are one undo step.
- **Cameras, light bulbs and particle emitters no longer show in the shot**: hidden while looking through a camera and
  in Export (exports never had them).
- **The bridge stays up.** It comes back on by itself if it was on, keeps the iPad from auto-locking while on, restarts
  its listeners when the app returns to the front, and saves a laptop's pairing at once (it was saved on the next status
  call, so a pairing could be lost).
- **Pairing code**: permanent by default (000000 until you change it, *Change* in the bridge panel), or *New code after
  every pairing*. `lowey-link pair` with no code uses 000000. Ten wrong codes pause pairing for a minute.
- **lowey-mcp / lowey-link answer fast or fail fast**: 2.5 s to connect (a sleeping iPad used to hang a call for up to
  200 s), no proxy lookups, and if the iPad's address changed they find it again by Bonjour and remember it.

## [1.4.0] — Polish: feel, face, media

### Feel
- **Rotation that behaves.** Objects turn around their own pivot (several: the middle of their pivots) and never drift
  while turning (the pivot used to be re-measured from the bounding box every frame). Rotate rings are thin and picked
  by their drawn line, the ring facing you winning where they cross (overlapping hit boxes grabbed the wrong axis).
  Face-on rings turn by circling, edge-on rings by sliding along them. Snapping happens in steps during the turn, with a
  tick, instead of jumping at the end. The inspector keeps the angles you typed (X 100° stays 100°, not 80°/180°/180°).
- **Two fingers on the selected object** hold it: twist turns it, pinch sizes it (Reality Composer). Elsewhere two
  fingers still move the camera.
- **Squeeze the Apple Pencil Pro** to play or pause, in any mode, with the interface hidden too (unless Squeeze is set
  to Ignore in Settings).
- **The timeline scrolls up and down again** with many rows (the lanes' drag swallowed the list's scrolling), flicks
  glide, a thin bar shows where you are. To start and Add marker are back on the header.

### Simpler, lighter chrome
- Buttons on a panel draw no glass of their own (glass on glass); the top bar's glass is one group. Undo and redo sit in
  the top bar; move / turn / size only show with something selected; the inspector keeps the numbers folded and has
  three actions (duplicate, hide, delete) plus one menu for the rest.

### Faster stage
- The selection box is rebuilt only when the selection's size changes (it was rebuilt, and the selection re-measured,
  on every camera move and every frame of playback). The drawing guide likewise.
- Live bloom at quarter size (exports keep the full filter); video frames for the stage decode at 1280 px.
- The stage renders at 1.75× (about a quarter fewer pixels); *Full-resolution stage* in the scene menu brings back
  full density. Rigs are only looked up for clip tracks.

### Face, hands and the phone
- **Set rest pose** (Character Animator): sit relaxed and tap; head angles, gaze and dials are measured from there, so
  looking at the iPad from below no longer leaves the character nodding.
- **Hands**: body tracking (Vision) moves the blob's hands and the rubber-hose arms follow; recorded with the face.
- **A camera preview** floats over the stage while you perform: the picture, green dots on the face, lines on the arms,
  Set rest pose and stop. The iPhone companion shows its own preview and streams a small one to the iPad.
- Sides are consistent: every source reports the mirror's sides (the iPhone used to mix mirrored blinks with unmirrored
  turns); head turn, nod and tilt from the iPad camera come from the face's own geometry. The iPhone measures the head
  against the phone, not against where tracking started. Live values draw once per screen frame.

### Characters
- **The neutral face is neutral**: a short level mouth, level brows, upright eyes. The smirk lives on as *Smug*.

### Media
- **Pictures and videos stand in the world as thin cards** (Add → Photo or video): a framed slab facing you, moved,
  turned, sized and keyed like any object; videos play on them frame-exact in exports. Transparent Manim renders still
  go over the frame. The bridge takes `?as=card|overlay`; `add_media(..., overlay=False)`, `lowey-link media --overlay`.

### Laptop tools
- `lowey-link pair 123456` finds the iPad by itself (Bonjour); `python -m lowey_tools` works when `Scripts` isn't on PATH.

## [1.3.1] — Smooth stage

- The live stage works out the glow halo at quarter size (it blurred the whole screen at full size every frame whenever
  anything glowed, including the blob's hover glow). Looks the same; exports keep the full-size halo.
- Blob faces stop making a new mesh every frame: springs settle to the exact pose and step in steps too small to see, so
  shapes are reused; the mouth works out each moment once instead of eight times.
- The renderer's mesh cache is bounded (it grew for as long as a face animated, so the app got slower the longer it ran).

## [1.3.0] — Phase 4: Characters, stability, feel

### Characters: the blob house style
- Hesham's own drawing turned into the house character (`assets/avatar`: traced from the drawing, built in Blender, GLB
  + .blend). In the app: **Add → Me**, or **Add → Blob** with a builder (who, hat and the name on it, hair, accessories,
  what they hold, colours).
- Famous people as blobs by their clues (Newton's wig and apple, Einstein's white hair and mustache, Turing, Curie,
  Darwin, Tesla, Lovelace, Edison, Sherlock…), in the app and in scripts (`{"do": "blob", "likeness": "Isaac Newton"}`).
- A real cartoon face: eyes, brows and one morphing mouth redrawn from dials every frame (happy crescents, wide eyes,
  curved closed lids, angry and worried brows, his smirk at rest). Springs make every pose **overshoot and settle**;
  the head squashes and stretches on the hits; the hat follows through; eyes blink on their own.
- **Expressions** (12) in one tap at the playhead, Character Animator-style, and `{"do": "expression"}` for Claude.
- Rubber-hose arms that follow the hands; no legs, a soft hover glow that stays on the ground.

### Stability
- First-launch crash fixed (the tour opened a scene with post-processing into a stage that hadn't rendered yet).
- Exports never hang: the screen stays awake, the export waits while the app is in the background and resumes, a
  stalled frame is retried and reported. The full narrated story exports start to end in CI.
- Playback no longer redraws the whole timeline every frame (lag while playing).
- Glow works (it did nothing: the surface shader multiplied it by an empty emission map); glow casts a halo; imported
  models glow in their own colours. Image overlays now reach exported videos.

### Timeline, camera, drawing
- Track groups: folders you fold; a folded group shows and moves everything inside. Drags lock to their direction,
  only selected keys and bars move, flicks glide, pinch zooms under the fingers, a quieter header with one menu.
- Camera Perform records the path you fly with your usual gestures. **Snap zoom** move.
- **QuickShape**: draw, then hold, and the stroke becomes a line, arc, circle, ellipse, triangle or rectangle.

### Media and Manim
- **Add → Photo or video**; videos play from a time and export frame-exact. `lowey-link media`, `lowey-link manim`
  (renders a Manim scene with a transparent background, ProRes 4444) and the MCP tools `add_media`, `render_manim`.

### Interface
- Liquid Glass chrome, focus mode (button, four-finger tap, ⌃⌘F), a small stats pill, Pencil hover preview off by
  default, remove colours from the palette, a gestures & shortcuts page.

### Claude
- One skill, `skills/lowey`: an orchestrator that routes to modules (breakdown, shots, sets, camera, characters,
  cartoon animation, Manim & media, style, troubleshooting). End-to-end test: pair over HTTP, send a script, approve
  on the iPad, find the result.

## [1.0.0] — Phase 3: Story, voice, VFX, AI, polish

### Timeline — keyframe multi-select (Procreate Dreams-style)
- Box-select keys across rows and time: long-press and drag, or switch on **Select** and drag. Taps add/remove in Select mode.
- **Pick** menu: all keys, everything after / before the playhead, keys at the playhead, keys in the loop, invert, none
  (scoped to the selected objects when something is selected).
- A band over the selected keys on the ruler: drag either end to **stretch or squash** their timing (proportions kept).
- Move many keys together (the earliest stops at 0), nudge by a frame (menu, ⌥⇧← / ⌥⇧→), ⌘⌥A selects all keys.
- Compose mode: pick several bars and slide them together.

### Audio & narration
- Voiceover, sound-effect and music clips: waveforms in the timeline, drag to move, volume, fade in/out, mute, trim to
  the playhead, split, delete; "duck music under the voice" from the transcript. Import from Files or record a voiceover
  while the animation plays.
- Playback follows the sound's clock (no drift). Exports carry the mixed soundtrack (AAC in .mp4/.mov; soundtrack.wav next
  to PNG sequences) — mixed exactly as previewed.
- Word timing with Apple's on-device SpeechAnalyzer (no Whisper): the model downloads once; English, Arabic, Italian first.
- Words lane in the timeline, transcript panel (tap a word to jump; long-press + tap to pick a phrase; fix words and keep
  their timing), snapping of keys, the playhead, sounds and effects to words, phrase actions (animate here, camera move,
  cut, marker, loop).

### Lip sync, face, your character
- Lip sync from the voiceover's words (CMU Pronouncing Dictionary + rules; Arabic and Italian), with the voice's loudness as
  fallback: stepped mouth shapes plus jaw and width keys — editable like any animation.
- Face performance from the iPad's front camera (Vision landmarks): blinks, brows, mouth, smile, eyes, head turn — live on
  the character, recorded with Perform. Optional iPhone companion (Face ID / ARKit) streaming over the local network.
- Character builder: head, hair, eyes, body, top, bottom, extras, colours → a low-poly character on the Humanoid standard
  with swappable mouth shapes; edit it later; save it to the library.
- Built-in humanoid clips (Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate) that play on built characters
  and imported humanoids; imported humanoid clips play on built characters too.

### Text, overlays, captions
- 2D overlays in frame space: titles, labels, arrows (draw themselves), highlights, the big X, question / exclamation
  marks, ticks, shapes, images; drag / pinch / twist on the stage; presets animate them (typewriter types, arrows draw);
  labels can follow a 3D object.
- 3D text: Blocky (built-in low-poly font) plus Rounded, Bold, Serif, Mono (any script).
- Captions from the transcript: Punchy (karaoke highlight), Subtitle, Pill, Outline; top / middle / bottom; burn-in on
  export; .srt and .vtt export. Portrait frames get shorter lines.

### VFX & post
- Particles: fire, sparks, smoke, dust, magic, rain, snow, confetti, embers, explosion — amount, size, speed, spread,
  colour; animate emission; bursts at a time. Deterministic (scrub and export exactly).
- Post (in the Look): glow, vignette, grain, exposure, contrast, colour, warmth, ink outlines, colour fringe, retro/PS1,
  paper / collage / old-film textures, depth of field from the camera (now rendered). One-tap finishes: Clean, Cinematic,
  Dreamy, Retro, Ink outlines, Collage, Old film. Identical in the live view and in exports.
- Screen effects on the timeline: flash, shake, speed lines, zoom blur, glitch. Transitions on cuts: fade, dip to black,
  wipe, zoom-through. Match-cut helper.

### AI layer & laptop link
- Scene Script v2: friendly actions (names, spoken-word times, presets, cameras, characters, look…) → preview → apply as
  one undo step. Paste from the clipboard, open a file, or send from the laptop. JSON Schema updated.
- LAN Bridge (off by default, pairing code, local network only): scene / assets / transcript / look queries, scripts
  (with approval on the iPad), snapshots, renders, file and audio import, undo, WebSocket events.
- `tools/lowey`: **lowey-mcp** (MCP server: 16 tools, 4 resources, 5 prompts) and **lowey-link** (pair, push, pull renders,
  watch a folder, Blender / text-to-3D generators, send scripts). Claude skills in `/skills`: script-breakdown,
  shot-planner, scene-builder, camera-director.

### Projects & polish
- Share a project as one `.loweypack` file and import it; archive / restore; copy a scene to another project.
- Welcome island sample (golden-hour fly-through) and a 60-second tour; the Enigma sample gains "5 · The story (narrated)"
  with a placeholder voice.
- Menu-bar commands with shortcuts (modes ⌘1–5, transcript ⇧⌘T, audio ⇧⌘U, record ⌥⌘R, bridge ⇧⌘B, markers ⌘M…),
  Apple Pencil hover preview, localisation scaffold (Arabic, Italian), thermal-aware preview, local diagnostics log and
  "Export diagnostics".

### Engineering
- Schema v3 (additive). New Core areas: `Audio/`, `Text/`, `VFX/`, `Face/`, `Character/`, `AI/`, `Project/ProjectPackage`.
- LoweyRender: `FrameCompositor`, `OverlayRenderer`, `StagePost`, depth world + `loweyDepth` / `loweyInverseDepth` shaders,
  particle meshes, text meshes; exporter composites, renders transitions and writes audio.
- Tests: Core (~180, Linux), render and speech tests on the simulator (`Phase3Tests`), laptop tools (pytest) in CI.

## [0.8.0] — Phase 2: Motion, camera, characters, export

### Timeline
- Bottom timeline drawer in Animate and Camera modes: transport, frame stepping, scrubbing ruler, markers (tap to jump,
  long-press to rename/delete), loop region, zoom (pinch) and pan, one row per animated object (expand into property
  rows), behaviour spans, clip segments, camera-cut row.
- Modes: **Compose** (slide whole animations in time), **Perform** (record by touch), **Keyframe** (select, drag,
  retime keys). Frame rate 24/25/30/60, length, "fit to animation".
- Timeline evaluation, per-object and per-project stepping (cameras stay smooth) — all in LoweyCore, unit-tested.

### Keyframes & easing
- Keyframe any animatable property: auto-key (edits in Animate/Camera mode become keys at the playhead), animated
  properties always key, "Key" button (⌘K).
- Easing presets (linear, in, out, in-out, overshoot, bounce, elastic, step) + a curve editor with draggable handles.
- Copy/paste (also onto another object), mirror (there and back), reverse, twice as fast/slow, delete.

### Perform mode
- Record → "Ready 3-2-1" → the timeline plays; drag to move, pinch to scale, twist (or Apple Pencil Pro barrel roll)
  to turn. Lift = pause, touch again = resume. Smoothing 0–100 %. Sliders perform any number (glow, light, opacity,
  zoom, focus). Re-performing replaces only the performed range. One undo step per take.

### Presets & mass animation
- 15 one-tap presets: pop in/out, grow, shrink, bounce, wiggle, float, spin, shake, pulse, fade in/out, slide in,
  drop in, typewriter — real, editable keys.
- Many objects at once: delay, order (selection, left→right, right→left, front→back, wave), random timing and strength.
- Behaviours: follow a drawn path, look at, follow (with lag), orbit, wobble, wind sway, bob on water, spin —
  deterministic, bake to keys. Animated generators (arrays/scatters grow in one by one).
- Simulations baked to keys: fall, explode, flock of birds, crowd walks in.
- Scripting (JavaScriptCore): script panel with inline errors and a log; scripts saved in the library; examples:
  forest grows in, flock of birds, crowd walks in. Every run is one undo step.

### Characters
- Skeletons and clips read from glTF/GLB in LoweyCore; clips play on skinned models (poses → joint transforms).
- Standards Humanoid / Quadruped / Bird / Custom with auto bone mapping (Mixamo, Quaternius-style, Blender, generic).
- Retargeting: a clip for a standard plays on any character of that standard (tested on 2 humans, 2 quadrupeds).
- Clip track: play from the playhead, loop, speed, crossfade; walk speed matched to a path (no sliding); feet on the
  ground, head look-at, hand reach (IK). Crowd tool: N copies with offset, varied clips.
- Puppet joints: wrap parts in a joint that pivots at the top/middle/bottom (shoulders, hips, hinges).

### Camera
- Look through the shot camera; drag to aim, two fingers to move, pinch to dolly, twist to roll — keyed.
- Cameras + camera-cut track ("Cut here"). 10 one-tap moves: push in, pull out, punch in, orbit, dolly, truck, crane,
  whip pan, shake, reveal; follow the selection.
- Lens: focal length, focus distance, aperture, focus on selection, animated focus pull (rendered blur arrives with
  Phase 3's post-processing — see DECISIONS D50).
- Framing guides 16:9 / 9:16 / 1:1 with safe zones and thirds; per-camera 9:16 zoom and pan, so one camera exports both.
- The iPad as a virtual camera (ARKit world tracking, scale factor), recorded through Perform.

### Export
- Video rendered frame by frame at a fixed timestep: 16:9 + 9:16 (+ 1:1) in one job, HD/4K, H.264/HEVC, PNG sequences,
  transparent background (HEVC with alpha / PNG), whole timeline or the loop region; progress and cancel; saved in the
  project's renders folder; share or save to Photos. Single frames through the camera.
- 3D export of the selection or the scene: glTF (.glb) and USDZ.

### Engineering
- Schema v2 (Phase 1 files open unchanged). New commands: `setTracks`. Deleting/duplicating objects carries their animation.
- New package `LoweyScript`. New Core modules: Motion, Rig, Export. Sample project gains "4 · Opening (animated)".
- CI: `[build-only]` in a commit message runs a compile-only app job (saves macOS minutes).
- Fixed: Mixamo "Fo**rear**m" was read as a quadruped's rear leg by the rig classifier.

## [0.4.0] — Phase 1: Foundation & Build

### Engineering
- XcodeGen project (`project.yml`), Swift 6 strict concurrency, packages `LoweyCore` + `LoweyRender`, app `LoweyApp`.
- CI: SwiftFormat + SwiftLint → LoweyCore tests on Linux with ≥ 80 % coverage gate → iPad simulator build,
  render tests and UI smoke test (screenshots exported as artifacts).
- Release: unsigned device build → ad-hoc codesign → `Lowey.ipa` on every `main` push; GitHub Release on `v*` tags.
- Docs: README (Sideloadly install), ARCHITECTURE, DECISIONS, THIRD_PARTY.

### Core model
- Objects with typed, animatable properties; groups/hierarchy; lights; cameras; drawn objects (recipes); prefab instances.
- Command system with exact inverses, batches, JSON encoding (Scene Script vocabulary); undo/redo with gesture coalescing.
- Timeline, keyframes, easing (linear, in, out, in-out, back, bounce, elastic, step, bezier), on-twos stepping.
- Project folders (`.lowey`), schema versioning + migrations (v0 → v1), atomic writes with backup recovery, autosave.

### Render
- RealityKit bridge with diff-based sync, shared meshes/materials (instancing), fog + glow surface shader.
- Looks: smooth/flat shading, linked palette, 6 mood presets, sun with shadows, sky gradient + stars, fog, ground,
  sky-driven ambient light, custom point/spot/directional lights with shadows, emissive glow.
- Offscreen renderer (RealityRenderer) for snapshots and thumbnails — the Phase 2 export path.

### Building
- Blockout primitives (cube, sphere, cylinder, cone, plane, torus, ramp); swap blockout → library model (fit to size).
- Gizmos (move/rotate/scale), on-screen joystick, direct drag, numeric inspector.
- Snapping: grid, ground, flush to other objects, rotation steps.
- Duplicate, copy/paste, array (row, grid, circle), scatter an area in one gesture (seeded), group/ungroup,
  outliner with lock/hide/reparent, align/distribute.

### Drawing in 3D
- Pencil pressure strokes with smoothing → tube or ribbon; extrude a drawn outline; lathe a drawn profile; mirror.
- Guides: plane locked to the view (or ground/front/side) with offset, box, cylinder, sphere, or any existing object.
- Save anything to the library.

### Library
- Global library (USDZ, glTF/GLB with dependencies, OBJ; files, folders, drag & drop, share sheet).
- Auto thumbnails, search-first panel, tags, favorites, recents, RIGGED badge (skeleton + clips kept), prefabs that
  update everywhere, saved looks. Projects reference assets by id; "Export" copies them in.

### UI
- Home with project thumbnails; stage with left tool rail, top-right mode switcher (Build · Animate · Camera · Look ·
  Export), inspector, library, outliner, look panel; snapshot export as PNG in 16:9, 9:16 and 1:1 (HD / 4K).
- Keyboard shortcuts (⌘Z, ⇧⌘Z, ⌘D, ⌘C, ⌘V, ⌘G, ⌘A, ⌘⌫ delete, ⌘F frame, ⌘L library), haptics, Stage Manager friendly.
- Sample project: the Enigma sets.
