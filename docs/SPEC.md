# Maquette — product spec

**Shapr3D's ease, Procreate's feel, Dreams' animation and ToonSquid's rigging, in 3D, for people without an
engineering or art degree.** The measure of success is the time from an idea to seeing it 100% ready. Maquette is the
continuation of 3D-lowey 2.0, made by **studio h.**; this file is studio-h's CONTEXT §10 kept true to the code: what
is built says so, what isn't says which phase brings it. Everything 2.0 does (sections 1–12 below) is the behavioural
reference and stays.

| Area (CONTEXT §10) | Status |
|---|---|
| Name, icon, bundle ids, `.maquette` projects | **0.1.** Temporary icon (2.0's cube in the studio neutrals) until the identity phase (S1). |
| Nothing is ever lost: the history journal, undo after relaunch, versions, the History scrubber | **0.1.** [PROJECT_FORMAT.md](PROJECT_FORMAT.md) |
| Apple Pencil: hover point at the tip in the stage's own pass, outline only while resizing | **0.1** |
| Device tiers (A/B/C) and the hidden load meter | **0.1** |
| The layout of §10.1 (the canvas owns the screen, timeline on call, floating inspector, living gallery, starter templates) | **0.2.** [LAYOUT.md](LAYOUT.md) |
| Modelling I (select, push/pull with numbers, sketch on surfaces, booleans) | **0.3** |
| Modelling II (bevel, round, inset, shell, mirror and live symmetry, array along a path, corner/edge/midpoint/face snapping, measure, section view, kept dimensions, 3D printing, architecture) and interop (glTF, USDZ, OBJ, STL, 3MF, the Blender package) | **0.4.** FBX isn't offered (D-133). |
| One brush engine, Brush Studio, Procreate/Photoshop brush import, drawing guides | **0.5.** Ink and flipbooks draw with it; painting on models (M6) and the Schizzo board (M9) will. |
| Painting on models | M6 |
| One skeleton system, draw a bone, one-tap human rig, 2D puppets | M7. Today: 2.0's Cast (Blob, Puppet, Rigged). |
| Tutorials in Hesham's voice, artist info, Content Credentials, Time-lapse, 1.0 polish | M8 |
| Schizzo board, live performance, sculpting, mechanisms + AR, web layer, house kit | Free updates after 1.0 |

### Brushes and drawing guides (0.5)

- **One brush engine** (D-139) draws ink in the scene, flipbooks over the shot and the stroke under the Pencil: a tip
  and a grain stamped along the stroke, with spacing, StreamLine, jitter, fall-off, tapers, pressure/tilt/speed
  dynamics, flow, wet edges and a soft edge. What's drawn while the Pencil moves is what's kept (UIKit's predicted
  touches draw ahead, the stroke's own seed keeps its jitter).
- **Brushes**: ten built-in brushes in three sets (Inking: Ink Pen, Technical Pen, Brush Pen, Marker; Sketching:
  Pencil, Charcoal; Painting: Dry Brush, Watercolour, Soft Airbrush, Splatter). Their tips and grains are drawn by code.
  Draw ▸ Ink and Draw ▸ Flipbook each hold a brush; the row at the top opens the library.
- **The brush library**: sets (make, rename, delete, share as a `.maquettebrushes` file), choose a brush, touch and hold
  for Brush Studio, duplicate, reset, rename, move to a set, delete. **Import** Procreate `.brushset` and `.brush` files
  and Photoshop `.abr` brushes (from the library, or Open in from Files and AirDrop); the mapping is D-141.
- **Brush Studio**: every setting on seven pages (Stroke, Shape, Grain, Dynamics, Pencil, Rendering, About), your own
  picture as a tip or grain, and a pad to try the brush as it changes.
- **Strokes keep their brush**: a project carries a frozen copy of each brush it used, so editing the library never
  redraws finished work and a project opens the same on another iPad (D-140).
- **Drawing guides** (D-149): over the frame for flipbooks a 2D grid, isometric, 1-, 2- and 3-point perspective, and
  symmetry (vertical, horizontal, quadrant, radial with mirror); on the guide plane for ink a grid, isometric and
  symmetry. Drawing Assist straightens strokes along the guide; symmetry mirrors them as you draw.
- **Latency**: Diagnostics ▸ Apple Pencil shows how long a Pencil sample takes to reach the screen (D-146).

### Nothing is ever lost (0.1)

Every change is a command; every command (and every undo and redo) is written to the scene's history journal within
50 ms, off the main thread. Every 200 changes, after 5 seconds of quiet, when the app leaves the screen and when a
scene closes, a checkpoint writes the scene, its undo history and the project files. Opening a scene reads the last
checkpoint and replays what came after it, so force-quitting mid-edit and reopening shows the last edit, and it can be
undone. Undo keeps 500 steps across relaunches.

**Actions ▸ History** opens the scrubber over the stage: drag back through every step and the stage shows that
moment. *Go back here* makes it the present (the state you left is kept as a version, and redo still goes forward
until you change something); *Name* keeps the moment as a named version; *Versions* lists named and automatic
versions (one each time a scene opens and after each hour of work) and restores any of them as one undo step.

### The Pencil (0.1)

With *Settings ▸ Pencil hover preview* on, a small point sits exactly under the hovering tip, for every tool, the same
size at every height, drawn by the stage in the frame it renders. Off, there is no mark at all. The brush's outline
shows only while its size slider moves.

### Every iPad (0.1)

All iPadOS 26 iPads. At launch Maquette reads the GPU family and memory: **Tier A** (M-chips) previews at full
quality; **Tier B** (recent A-chips) with a lighter render scale and shadows; **Tier C** (the oldest) lighter still.
Tiers never remove features, and exports always render at full quality. The stage's frame budget is the screen's own
refresh. Diagnostics shows the tier and runs the Night Market benchmark (and, on an M iPad, the same run with the
Tier B preview). With **Smoothness warnings** on (Settings ▸ Stage; off by default), a calm chip appears at the
bottom of the stage when a scene nears what the iPad keeps smooth, offering a lighter preview (or adaptive resolution,
when Full-resolution stage is on). The stage keeps adapting its render scale either way.

### The canvas owns the screen (0.2)

The layout that freezes at 1.0; [LAYOUT.md](LAYOUT.md) maps every control to its one home and the UI tests walk it.
At rest the stage holds at least 85% of the screen.

- **Top left: the document and the app.** Home · Actions (export, the project file, the Monitor, scenes, history,
  scripts, the AI & laptop bridge, gestures, the tour, diagnostics, settings) · Look · Select.
- **Top right: making**, in the order a thing gets made. **Model**: shapes, lights, cameras, words, photos and videos,
  marks on the frame, effects and screen effects (Add); the Kit and your models (Library); snapping and the grid
  (Precision). **Draw**: ink, solid shapes, flipbooks. **Paint**: the Shadow Brush and Scatter. **Animate**: opens the
  whole timeline. **Cast**: characters, expressions, clips, lip sync, your face.
- **Time on call.** A new project shows no timeline. The control at the bottom right calls the slim transport (play,
  the time) and sends the timeline away; Animate opens the whole timeline. Its divider resizes it, and each project
  remembers whether it was hidden, slim or whole and how tall.
- **The inspector floats beside the selection**, on whichever side has room, flipping at the screen's edge and
  gliding over when the view settles. Move, turn and size are at its top; align and distribute appear when several
  things are selected.
- **Every panel resizes** from the grip in its corner (double-tap it for the original size) and remembers its size.
- **The joystick** shows under a selection by default; its × hides it, Settings ▸ Stage brings it back.
- **Home, the living gallery.** Each card is the project's model slowly turning in its own Look while the card is on
  screen (Reduce Motion keeps a still). Tap a card and it grows into the stage; Home in the corner shrinks it back.
  Drag a card onto another to stack them; search finds projects and stacks by name; sort by Recent, Name or Date
  created; Select acts on several (stack, move out, duplicate, archive, delete).
- **Starter templates** in New project: Blank, Model to print (millimetres, a 1 cm grid, 5 cm shapes, close up,
  Clay), Room or building (metres, a 25 cm grid, the view from above), Character (Cast open, eye level), Animation
  (the timeline open). Each suggests a Look and a Mood, both changeable there and later. Sketch arrives with the
  Schizzo board (M9); the print-bed outline and the walls tool with M4.
- **Keyboard**: ⌘1–⌘5 Model, Draw, Paint, Animate, Cast; ⌘6–⌘8 Actions, Look, Select; ⌘L the library; ⌥⌘1–3 move,
  turn, size; ⌘T the timeline.
- Diagnostics also runs the **Home benchmark**: a hundred projects turning while the gallery scrolls for 20 seconds.

### Modelling I (0.3)

Shapr3D's core loop, in **Model ▸ Shape**. Choosing a sketch shape or a pick mode closes the panel and puts the Model
tool's bar at the bottom of the stage (pick modes, sketch shapes, Done, grow / shrink / select similar, ✕).

- **Sketch on any surface.** The first tap lands on the face under it (or the ground) and the shape lies on that
  plane: **line** (tap the corners, tap the first to close), **rectangle** (two corners), **circle** (centre, edge),
  **arc** (start, end, bend), **spline** (tap through it; tap the start to close, or Done), **offset** (tap a curve,
  type the distance). Points snap to corners already drawn, else to the grid. Closed shapes fill into regions; a
  shape inside another makes a hole and is a region of its own. Sketches are construction lines: the stage shows them,
  renders and exports never do.
- **Pull a region into a solid, or cut it into the face below.** Tap a region and drag it, or tap its number and type:
  up makes a solid (or adds to the object it was drawn on), down cuts into that object. The region's lines are used
  up.
- **Pick faces, edges or corners**: tap one, touch and hold to add or remove, draw a loop with the Pencil around
  several; grow, shrink and select similar from the bar. Picks are highlighted in amber on the stage, with the
  object's edges drawn over it.
- **Push/pull a face** with its live distance floating beside it; snapping to other corners' heights and to the unit
  while dragging; tap the number to type an exact one. A face whose neighbours stand square to it slides (the number
  is the new size exactly); any other face adds or cuts a prism.
- **Exact lengths everywhere**: every number on the stage takes `25`, `25mm`, `2*12`, `1ft 6in`, `(40-6)/2`, in the
  project's units (Model ▸ Precision: mm, cm, m, in, ft).
- **Booleans**: union, subtract and intersect two or more selected shapes into the first one; results are clean
  (coplanar faces merged, welded) closed solids. Any shape (a cube, a drawn solid) becomes an editable mesh on the way,
  or with Make editable.
- **The inspector shows sizes**: the selection's width × height × depth in the project's units, and what's picked
  ("Face · 800 mm²", "2 edges · 80 mm").

### Modelling II and interop (0.4)

- **Shape operations on the pick**, from the Model tool's bar: **Bevel** and **Round** the picked edges (outside edges
  are cut, inside edges filled; where several meet the cuts meet in a point), **Inset** the picked faces (a ring
  around each, the middle stays picked to push or pull), **Shell** the solid (walls of an exact thickness; picked faces
  are left open). Each runs at once at a size that suits the units (1 mm in a print project, 5 cm in a room); its size
  then floats beside it, and typing a new one does it again from the same pick.
- **Mirror** (Model ▸ Shape): a mirror image across the picked face (it joins into one solid when it touches) or across
  the world's middle (a twin on the other side). **Symmetry**: left and right, front and back, or top and bottom, per
  object; switching it on moves the pivot to the middle on that axis and makes the shape symmetric; every Model edit
  afterwards keeps the side it touched and the other side follows (a push/pull shows both faces moving).
- **Array along a path**: the inspector's array follows a sketch's curve (copies spread evenly, optionally turning
  with it).
- **Precision** (Model ▸ Precision, was Snapping): points snap to corners, the middles of edges, edges and faces near
  the finger or Pencil (12 points on screen), then to the grid; the stage marks what a point snapped to. Sketching,
  measuring, walls and floors all snap this way. Grid sizes follow the units.
- **Measure**: two taps give the distance and how far apart along x, y and z; tap the number (or Keep) to leave it on
  the stage as a **dimension** that moves with the object it measures. Kept dimensions show whatever the tool (Show
  kept dimensions); tap one to select it. Like sketches, they're never rendered or exported.
- **Section view**: cut the stage across x, y or z through the middle of the selection, or along the picked face;
  slide where it cuts, keep the other side. Cut solids show their inside flat in their own colour. Exports are never
  cut.
- **3D printing** (Model ▸ Shape ▸ 3D print): pick the printer (its build volume is outlined on the stage; Model to
  print starts with a 220 mm one), **Check for printing** (holes, tangled edges, inside-out faces, walls thinner than
  the printer prints, fitting the bed, the thinnest wall) and **Repair** (joins, turns and closes what it can). STL and
  3MF exports are millimetres with Z up, so parts stand on the bed in a slicer.
- **Building** (Model ▸ Add): **Walls** along tapped corners (2.7 m high, 20 cm thick, both typed beside the walls
  being drawn; tap the first corner to close a room), **Floor** under tapped corners, **Door** and **Window** cut where
  a wall's side is tapped (90 × 210 cm; 120 × 120 cm at 90 cm), **Stairs** climbing away from you in 17.5 cm steps.
  Each is an editable mesh like everything else.
- **Interop.** Import (Model ▸ Library): USDZ, glTF, GLB, OBJ, STL, 3MF; **Make editable** takes a placed model apart
  into editable objects, keeping a glTF's hierarchy, materials, cameras, lights and animation. Export (Actions ▸ Export
  ▸ 3D model): **glTF** (the scene as built: hierarchy, materials, cameras, lights, the timeline's moves), **USDZ**,
  **OBJ** with its MTL, **STL**, **3MF**, and **Blender**: a folder with the scene, the Look, the sun, the sky, the
  ground, the camera cuts and render settings, and `setup_maquette.py`, which builds a ready-to-render .blend (Blender
  4.2 or newer). Kept dimensions, sketches, marks on the frame and effects stay in Maquette.

---

# 3D-lowey 2.0 — what Maquette starts from

**Procreate Dreams, in 3D, cel-shaded.** An iPad app where someone who isn't a 3D artist directs good-looking,
hand-drawn-feeling 3D animation (sets, characters, cameras, voice) and exports it as video. The measure of success
is the time from an idea to an animated shot on screen.

2.0 shipped in two steps: **2.0 beta** rebuilt the engine, the Look system and the layout and carried every 1.x
feature over; **2.0** added the drawing and animation tools, the Kit, one Cast system, perception and MCP v2, three
languages and App Store readiness. What happened to each 1.x feature is in [MIGRATION.md](MIGRATION.md); why things
are the way they are is in [DECISIONS.md](DECISIONS.md); what's next is in [BACKLOG.md](BACKLOG.md).

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
- **Ink strokes**: Pencil strokes in 3D on the guides, drawn with a brush (0.5: stamps turned to the camera); select
  (tap or loop), move, erase, smooth and change width; strokes are objects, animatable and able to write themselves on.
- **Solid shapes**: tube, ribbon, extrude, lathe on guides (facing me, ground, front, side, box, cylinder, sphere, on
  an object), mirror, Pencil-only, QuickShape.
- **The Kit**: about 350 CC0 models (Kenney, Quaternius) in nine Sets, at real size, with the surfaces things stand on
  and the way they face; the Library opens on them (`Tools/fetch-kit.py` builds it, licences checked per pack).
- **Shadow Brush**: paint where shadows fall on any surface with the Pencil (push the shadow in, pull it out).
- Array, scatter, group / ungroup, align / distribute, swap a blockout for a model, save to the library, linked
  prefabs.
- Import USDZ, glTF / GLB, OBJ and folders, from the share sheet, drag and drop, or the laptop.

## 5. Characters

One **Cast** panel and one set of verbs for every kind of character:

- **Blob** (the house character, from a traced drawing; its measurements are generated from it): hats, hair,
  accessories, props, marks, a likeness table for famous people, 12 expressions, springs, squash and stretch, a stable
  inverted-hull outline, flat face decals, Shadow Brush presets.
- **Puppet**: a humanoid of rigid parts with a builder.
- **Rigged**: imported glTF skins with rig classification, retargeting, IK and a clip mixer.
- Built-in clips on all three: Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate. A pose library with
  mirror; IK handles (two-bone limbs, blob hands).
- Lip sync from word timings (English dictionary plus rules, Arabic, Italian), face capture with the front camera or
  an iPhone companion, rest pose, hands through body tracking.

## 6. Animation

Three timeline modes, named as in Procreate Dreams: **Compose** (move animation in time without breaking keys),
**Perform** (record direct manipulation as keys, with filtering and Pencil roll), **Keyframe** (explicit keys, easing,
the curve editor, auto-key). Also: 15 presets with order, delay and randomness; behaviours (follow a path, look at,
orbit, wobble, wind sway, float, spin; bake to keys); fall, explode, flock; JavaScript scripts; markers; loops;
copy / paste / mirror / reverse / faster / slower; track groups; per-object frame rate (ones to fours, keyable);
motion paths with draggable key dots; 3D onion skin; a graph editor; smears on fast moves; multi-select of clips with
the Pencil lasso.

**Flipbooks**: frame-by-frame drawing with a brush over the shot, anchored to the camera or an object, with onion skin, holds,
blend modes (normal, multiply, screen, add) and several tracks; drawn FX (speed lines, impact burst, sweat drop,
sparkle, smear) placed on a word.

## 7. Camera

Camera objects, shots and cuts on the Camera lane, 11 moves, lens (focal length, focus, aperture), transitions,
match cut, 9:16 framing, the iPad as a camera (ARKit), camera Perform.

- **Director view**: look through the shot camera with framing guides (thirds, safe areas, the delivery shape); drag
  to aim, two fingers to move, pinch to dolly, twist to roll — all keyed.
- **Frame shot**: pick a subject, a shot type (extreme wide … extreme close-up, insert, over-the-shoulder, two-shot),
  a composition (thirds, centre, low or high angle) and a side; the camera is placed and aimed.
- **Fly**: fly the camera with on-screen sticks or a game controller, eased, and record the flight in Perform.

## 8. Voice and sound

Record a voiceover over the animation, import audio, transcription on the device (Apple's SpeechAnalyzer through
hmm-kit), the Words lane with snapping, the Transcript sheet (jump, pick a phrase → animate, camera move, cut,
marker; fix words), a placeholder voice, lip sync. Attaching things to a spoken word is a first-class action. A
sound-effects track with a synthesised CC0 foley set (whoosh, pop, impact, click, swell) whose hits land on words.

## 9. Layout (2.0; Maquette 0.2's layout above replaces it)

- **Theater** (home): project cards with looping previews; New project asks for a name, a Mood and a Look; samples;
  a card menu to share a `.loweypack`, duplicate, archive.
- **Stage** over **Timeline**, with a resizable divider; the timeline collapses to a transport bar.
- **Top-left cluster**: Theater · Actions (photos and video, sound, voiceover, export, the project file, scripts, the AI & laptop bridge, gestures, the tour, diagnostics, settings) · Look ·
  Select (tap, lasso, select similar).
- **Top-right cluster**: Build · Draw (ink, solid shapes, flipbooks, Shadow Brush) · Transform · Cast · Library.
- **Sidebar**: two sliders that follow the context (drawing, Shadow Brush, Perform, otherwise snapping and navigation
  speed), Pick, undo, redo; it can sit on either side.
- **Inspector**: slides in from the right while something is selected.
- **Gestures**: two-finger tap undo, three-finger tap redo, four-finger tap hides everything but the stage; one finger
  orbits, two fingers pan and zoom, double-tap frames the selection, two fingers on the selection twist and pinch it;
  Pencil hover previews, Pencil Pro squeeze plays and pauses, barrel roll during Perform.
- **Keyboard**: ⌘1–5 open Select, Build, Draw, Transform and Look; a full menu bar.
- Amber accent `#FFB847`; dark by default, light supported.
- **Languages**: English, Italian, Arabic (right to left; the timeline keeps time left to right).
- **Accessibility**: VoiceOver on every control, Dynamic Type in the chrome (panels scroll), Reduce Motion, Reduce
  Transparency and Increase Contrast.
- **Windows**: one window edits; a **Monitor** window shows the shot live as it exports (Stage Manager, external
  displays). The app reopens the project, scene, playhead and panel it was left in.

## 10. Documents and export

- A project is a folder package (`.maquette`; 2.0's `.lowey` opens too) of JSON scenes, assets, audio, renders and a
  thumbnail, with atomic saves and a backup of the last good version. Since Maquette 0.1 every change is in the
  scene's history journal the moment it happens (above, and [PROJECT_FORMAT.md](PROJECT_FORMAT.md)); the 2.0 autosave
  delay is gone. 1.x projects open and migrate. `.maquettepack` (and 2.0's `.loweypack`) shares a project with its
  assets.
  iCloud Drive in the App Store build; on the device otherwise.
- Export presets: YouTube 16:9 4K, 1080p, Shorts / Reels 9:16, Square, Transparent (HEVC alpha), PNG still (HD / 4K),
  GIF loop, 3D model (glTF, USDZ, OBJ, STL, 3MF, Blender; Maquette 0.4), Captions (.srt); custom size, frame rate
  (24 / 25 / 30 / 60), codec and quality.
- Every export is verified (length, frame count, size, audio, alpha) before it's offered. Exports keep running in the
  background, with a Live Activity where the system shows one and a notification when they finish.

## 11. Performance

- **Night Market** benchmark (Diagnostics): about 400 objects, six skinned walkers and four blob characters
  animating, sun shadows and three point lights, the Ink Look with lines and contact shading, a camera move. Pass on a
  device (since 0.1): no dropped frames for 95% of 20 seconds (p95 within 1.2 refreshes of the screen: 10 ms at
  120 Hz, 20 ms at 60 Hz) at a render scale near the top of the device tier's range (0.85 at Tier A), no hitch over
  33 ms. On an M iPad it also runs with the Tier B preview. It writes a JSON report.
- Launch to the Theater in under a second; a project's first frame in under 500 ms.
- A 60-second 1080p Ink export in 90 seconds or less on the reference device.

## 12. AI and the laptop

- **hmm-bridge** on the laptop: the `lowey` MCP server with sixteen intent tools (status, read_project, find_assets,
  build, frame_shot, light, set_look, animate, camera_move, add_overlay, flipbook, add_media, render_manim, observe,
  contact_sheet, commit) and a CLI for pairing, files, renders, media and Manim. The bridge is off until it's turned
  on, local-network only, paired with one-time codes; App Store builds ship without it until 2.1.
- **Scene Script v3**: relations instead of coordinates (on, beside, in front of, behind, above, under, inside,
  facing, around, row, grid, scatter, stack), real sizes, palette slots, the camera solver, six lighting recipes,
  animation by intent. The solver grounds what it places and keeps things apart. One script = one Proposal (with a
  preview picture) = one undo step. Schema: `schemas/scene-script.v3.schema.json`.
- **Perception**: `observe` returns the shot with set-of-marks, top / front / side diagrams, a value view and the
  subject's silhouette, plus a ShotReport (per object: coverage, visibility, grounding, intersections, frame cuts,
  facing; per frame: subject on the thirds, headroom, contrast, clutter, tangents, palette, light) graded against the
  critique rubric. `contact_sheet` returns frames with notes and motion stats (arcs, holds, speed, words).
- **The `lowey` skill**: a director loop (plan → build → observe → critique → fix), modules, style notes, a generated
  tool reference, lessons, and twelve eval briefs scored from the app's measurements.

## Device-only checks

Some things can only be checked on an iPad: the Night Market benchmark numbers · Pencil pressure on strokes and the
Shadow Brush · Pencil Pro squeeze and roll · face capture (front camera) and the iPhone companion · the ARKit virtual
camera · SpeechAnalyzer on a real voiceover (English, Italian, Arabic) · thermal behaviour during a 5-minute 4K
export · iCloud sync between iPad and iPhone · pairing the bridge from a laptop.
