# 3D-lowey 2.0 — product spec

**Procreate Dreams, in 3D, cel-shaded.** An iPad app where someone who isn't a 3D artist directs good-looking,
hand-drawn-feeling 3D animation (sets, characters, cameras, voice) and exports it as video. The measure of success
is the time from an idea to an animated shot on screen.

2.0 ships in two steps. **2.0 beta** (this branch) rebuilds the engine, the Look system and the layout and carries
every 1.x feature over. **2.0** adds the drawing and animation tools, the bundled kit, one Cast system and the
AI tools listed under *Planned*. What happened to each 1.x feature is in [MIGRATION.md](MIGRATION.md); why things
are the way they are is in [DECISIONS.md](DECISIONS.md).

## 1. What changes from 1.x

| 1.x | 2.0 | Why |
|---|---|---|
| The identity was "low-poly": untextured primitives, fog and bloom doing the work, so renders read as greybox. | Cel shading with lines (the **Ink** Look) is the default; low-poly is one Look of five. | Flat colour bands and ink lines make a cube look drawn instead of unfinished. |
| RealityKit renderer. | **LoweyRender 2**, a Metal renderer of our own. | RealityKit gives no per-fragment access to lights (no real toon lighting with cast shadows) and no normals or object IDs after rendering (no good lines). Owning the renderer also makes the preview and the export the same picture. |
| Five mode tabs, a game-style HUD, the joystick always on. | Procreate-style layout: Stage and Timeline, two corner clusters, a slider sidebar, universal gestures. The joystick is optional. | Modes hide tools behind tabs; everything should be one tap from the canvas. |
| The bridge was on by default with a permanent code, and the laptop tool could open it to the internet. | Off until turned on; a one-time code per laptop, tokens in the Keychain; local network only. | A creative tool shouldn't be an open door on café Wi-Fi. |
| Releases were published before CI finished. | Releases are built only from commits CI passed. | |

**Style references:** *Spider-Man: Into / Across the Spider-Verse*, *Paperman*, *Arcane*, *Puss in Boots: The Last
Wish*, *The Mitchells vs. the Machines*, *Klaus*, *TMNT: Mutant Mayhem*, and the games *Sable* and *Borderlands* —
the western comic and hand-drawn lineage. No anime conventions (eyes, faces, speed-line framing).

Pixar's warmth (shape language, appeal, bounce light, colour scripts) is in reach and lives in the Clay Look; its
offline path tracing isn't, and chasing it would make everything slower and uglier.

## 2. Looks

A **Look** is data (`LookPreset` JSON): shading, lines, finish and a default frame rate. Five are built in; any can be
duplicated and changed ("My Look"); a scene can override the project's Look, and an object can override its scene's.

- **Ink** (default) — cel shading that holds up close: smoothed shading normals so faceted shapes shade as smooth
  forms; two or three bands with adjustable edge softness; sun shadows inside the same bands; shadow colours shifted
  toward the sky hue rather than darkened; hemisphere ambient for bounce light; contact shading inside the shadow
  band; a rim light; optional hard specular shapes for glossy materials; restrained bloom on emissive surfaces.
  Lines from the object-ID, normal and depth buffers, scaled with distance and per object, in a darkened object
  colour by default.
- **Comic** — Ink plus halftone dots in the shadow band, colour misregistration instead of depth-of-field blur,
  heavier lines, a print finish, animated on twos by default.
- **Sketch** — desaturated Ink with pencil lines and paper grain; objects flagged **Accent** keep their colour (one
  per shot is the intent; the inspector warns when there are more).
- **Clay** — the soft 1.x look (rough materials, sky light, fog, bloom) with soft shadows, no lines. 1.x projects
  open in Clay.
- **Low-poly** — flat per-triangle normals, Ink bands or Clay lighting, optional lines.

The six **moods** (Day, Golden hour, Dusk, Night, Space, Studio) set sun, sky, ambient, fog and stars and combine with
any Look. The **palette** (linked slots, eyedropper) is shared by both. **Finish** (Clean, Cinematic, Dreamy, Retro,
Comic, Collage, Old film, plus sliders) and **Finish ▸ Outline** work over every Look.

## 3. Renderer

- Per frame: sun shadow map (two cascades fitted to the shot) → prepass (depth, normal, object ID) → Look shading
  (4× MSAA) → contact shading → lines → post (halftone, misregistration, bloom, grade, grain, transitions, screen
  effects) → overlays and captions → the screen or the encoder.
- **One renderer** for the stage, snapshots, thumbnails and export. Export renders offscreen into IOSurface-backed
  pixel buffers for the video encoder. Tests compare the stage's frame with the exported frame.
- **Dynamic render scale** (0.66–1.0) with MetalFX upscaling when the frame budget is at risk or the device is hot;
  lines and overlays stay at native resolution. Exports always render at full scale.
- **Picking** reads the ID buffer (exact, even on thin objects). Gizmos, guides and the selection outline are drawn
  by the same renderer.
- GPU skinning for imported rigs; instanced draws for repeats; reverse-Z depth; up to 16 point and spot lights, with
  shadows from the sun only.
- The ARKit virtual camera feeds its pose to the renderer like any camera.

## 4. Building

- **Primitives** (cube, sphere, cylinder, cone, plane, torus, ramp) with a small **bevel** by default, pivoted at the
  centre of their base.
- **Draw in 3D**: solid shapes (tube, ribbon, extrude, lathe) on guides (facing me, ground, front, side, box,
  cylinder, sphere, on an object), mirror, Pencil-only, QuickShape.
- **Shadow Brush**: paint where shadows fall on any surface with the Pencil (push the shadow in, pull it out).
- Array, scatter, group / ungroup, align / distribute, swap a blockout for a model, save to the library, linked
  prefabs.
- Import USDZ, glTF / GLB, OBJ and folders, from the share sheet, drag and drop, or the laptop.

## 5. Characters

- **Blob** (the house character, from a traced drawing): hats, hair, accessories, props, marks, a likeness table for
  famous people, 12 expressions, springs, squash and stretch.
- **Puppet**: a humanoid of rigid parts with a builder.
- **Rigged**: imported glTF skins with rig classification, retargeting, IK and a clip mixer.
- Built-in clips: Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate.
- Lip sync from word timings (English dictionary plus rules, Arabic, Italian), face capture with the front camera or
  an iPhone companion, rest pose, hands through body tracking.

## 6. Animation

Three timeline modes, named as in Procreate Dreams: **Compose** (move animation in time without breaking keys),
**Perform** (record direct manipulation as keys, with filtering and Pencil roll), **Keyframe** (explicit keys, easing,
the curve editor, auto-key). Also: 15 presets with order, delay and randomness; behaviours (follow a path, look at,
orbit, wobble, wind sway, float, spin; bake to keys); fall, explode, flock; JavaScript scripts; markers; loops;
copy / paste / mirror / reverse / faster / slower; track groups; per-object stepping (ones, twos, threes).

## 7. Camera

Camera objects, shots and cuts on the Camera lane, 11 moves, lens (focal length, focus, aperture), transitions,
match cut, 9:16 framing, the iPad as a camera (ARKit), camera Perform.

- **Director view**: look through the shot camera with framing guides (thirds, safe areas, the delivery shape); drag
  to aim, two fingers to move, pinch to dolly, twist to roll — all keyed.
- **Frame shot**: pick a subject, a shot size and a composition; the camera is placed and aimed.

## 8. Voice and sound

Record a voiceover over the animation, import audio, transcription on the device (Apple's SpeechAnalyzer through
hmm-kit), the Words lane with snapping, the Transcript sheet (jump, pick a phrase → animate, camera move, cut,
marker; fix words), a placeholder voice, lip sync. Attaching things to a spoken word is a first-class action.

## 9. Layout

- **Theater** (home): project cards with looping previews; New project asks for a name, a Mood and a Look; samples;
  a card menu to share a `.loweypack`, duplicate, archive.
- **Stage** over **Timeline**, with a resizable divider; the timeline collapses to a transport bar.
- **Top-left cluster**: Theater · Actions (photos and video, sound, voiceover, export, the project file, scripts, the AI & laptop bridge, gestures, the tour, diagnostics, settings) · Look ·
  Select (tap, lasso, select similar).
- **Top-right cluster**: Build · Draw (solid shapes, Shadow Brush) · Transform · Cast · Library.
- **Sidebar**: two sliders that follow the context (drawing, Shadow Brush, Perform, otherwise snapping and navigation
  speed), Pick, undo, redo; it can sit on either side.
- **Inspector**: slides in from the right while something is selected.
- **Gestures**: two-finger tap undo, three-finger tap redo, four-finger tap hides everything but the stage; one finger
  orbits, two fingers pan and zoom, double-tap frames the selection, two fingers on the selection twist and pinch it;
  Pencil hover previews, Pencil Pro squeeze plays and pauses, barrel roll during Perform.
- **Keyboard**: ⌘1–5 open Select, Build, Draw, Transform and Look; a full menu bar.
- Amber accent `#FFB847`; dark by default, light supported.

## 10. Documents and export

- A `.lowey` project is a folder package (JSON scenes, assets, audio, renders, thumbnail) with atomic saves, a backup
  of the last good version and autosave. 1.x projects open and migrate. `.loweypack` shares a project with its assets.
  iCloud Drive in the App Store build; on the device otherwise.
- Export presets: YouTube 16:9 4K, 1080p, Shorts / Reels 9:16, Square, Transparent (HEVC alpha), PNG still (HD / 4K),
  GIF loop, 3D (GLB / USDZ), Captions (.srt); custom size, frame rate (24 / 25 / 30 / 60), codec and quality.
- Every export is verified (length, frame count, size, audio, alpha) before it's offered. Exports keep running in the
  background, with a Live Activity where the system shows one and a notification when they finish.

## 11. Performance

- **Night Market** benchmark (Diagnostics): about 400 objects, six skinned walkers and four blob characters
  animating, sun shadows and three point lights, the Ink Look with lines and contact shading, a camera move. Pass on a
  device: p95 frame time ≤ 8.3 ms at render scale ≥ 0.85 over 20 seconds, no hitch over 33 ms. It writes a JSON
  report.
- Launch to the Theater in under a second; a project's first frame in under 500 ms.
- A 60-second 1080p Ink export in 90 seconds or less on the reference device.

## 12. AI and the laptop

In 2.0 beta: Scene Scripts (pasted or sent from the laptop) compile into one undo step and arrive as a proposal to
apply or decline; the laptop tools (`lowey-mcp` for MCP clients, `lowey-link` for files, renders, media and Manim)
talk to the iPad over the paired bridge.

## Planned for 2.0

- **Drawing and animation**: ink strokes (pressure ribbons on guides), flipbook tracks on the stage (anchored to the
  camera or an object, onion skin, holds, blend modes), per-object frame rate up to fours, motion paths with editable
  keys, 3D onion skin, a graph editor, smears, a pose library, IK handles, multi-select everywhere.
- **One Cast panel** for Blob, Puppet and Rigged characters; inverted-hull silhouettes and face decals on blobs; blob
  measurements generated from the traced drawing.
- **Fly**: fly the camera with the on-screen stick or a game controller while Perform records it.
- **The Kit**: about 300 curated CC0 assets (Kenney, Quaternius) with real sizes, top surfaces and front directions,
  in Sets; the library opens on them.
- **SFX** track with a small foley set.
- **Perception and MCP v2**: the app looks at its own shots (set-of-marks images and a shot report: coverage,
  grounding, intersections, framing, value contrast, clutter) and contact sheets with motion stats; 16 intent-level
  MCP tools; Scene Script v3 that places things by relation (on, beside, in front of, around…) using kit metadata; a
  rewritten `lowey` skill with a director loop, a critique rubric and evals.
- **Polish**: English, Italian and Arabic (right-to-left), an accessibility pass, state restoration, Stage Manager
  windows, App Store readiness.

## Device-only checks

Some things can only be checked on an iPad: the Night Market benchmark numbers · Pencil pressure on strokes and the
Shadow Brush · Pencil Pro squeeze and roll · face capture (front camera) and the iPhone companion · the ARKit virtual
camera · SpeechAnalyzer on a real voiceover (English, Italian, Arabic) · thermal behaviour during a 5-minute 4K
export · iCloud sync between iPad and iPhone · pairing the bridge from a laptop.
