# Layout

Where everything in Maquette lives. This is the map of CONTEXT §4.1 and §10.1: the layout that freezes at 1.0
(after that, it changes only through a converge session with Hesham). New features go into homes that already exist.

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ ⌂ Home  … Actions  ◐ Look  ☝ Select                Model  Draw  Paint  Animate  Cast │  corner clusters
│                                                                                      │
│ ┃ slider                                                                             │
│ ┃                         the stage (≥ 85 % of the screen at rest)          ┌──────┐ │
│ ◉ Pick                                                                      │inspec│ │  the inspector floats
│ ┃ slider                         [ selection ]                              │ -tor │ │  beside the selection
│ ● colour (drawing tools)                                                    └──────┘ │
│ ↶ ↷                                                                                  │
│                                                                                      │
│ (joystick)                    (tool options)          ⏱ Timeline · Views · ⌖ · 🎥    │  bottom row
├──────────────────────────────────────────────────────────────────────────────────────┤
│ timeline: hidden until called · the slim transport · the whole timeline (its height  │  time on call
│ remembered per project)                                                              │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## Rules

1. **One home per control.** A function has one place on screen. The menu bar, the keyboard and the gestures are
   other ways to reach it, not other homes. The outliner's eye and lock on each row are the list's own grammar (they
   act on that row), so the inspector keeps Hide and Lock for the selection.
2. **Top left is the document and the app** (Home, Actions, Look, Select). **Top right is making** (Model, Draw,
   Paint, Animate, Cast), in the order a thing gets made. A tool with nothing in it yet isn't shown (no stubs).
3. **Time lives in the timeline**, and the timeline comes when called: the corner control (⏱) or Animate. Sound,
   words and the timeline's own settings are there.
4. **Actions holds the long tail**: sharing, scenes, history, scripts, the AI bridge, help, diagnostics, settings.
5. **The inspector belongs to the selection.** It floats beside it, flips sides at the screen's edge, glides over
   when the view settles, and hides while a making tool's panel is open.
6. **Every panel resizes** from the grip in its corner (double-tap the grip for the original size); each remembers
   its size on the device.

## The walk

Each row's **Walk** is tapped by `LayoutWalkTests` (UI tests) from a new project: every step but the last is tapped,
and the last must be there. A step is an accessibility identifier (or the control's English label; a panel section is `section-<its title>`). A row may start
with a precondition: `[cube]` a cube is added and selected, `[blob]` a Blob is added, `[timeline]` the whole timeline
is open, `[transport]` the slim transport is showing, `[home]` the steps start on Home instead of in a project.
`Tools/layout_walk.py` turns this file into `AppUITests/LayoutWalk.swift`; CI fails when they disagree.

## Home

| Control | Walk |
|---|---|
| New project (name, starter template, Mood, Look) | `[home] new-project` |
| Search projects and stacks | `[home] gallery-search` |
| Sort (Recent, Name, Date created) | `[home] gallery-sort` |
| Select several (stack, move out, duplicate, archive, delete) | `[home] gallery-select` |
| Import a project, the archive, the tour | `[home] theater-menu` |
| Settings | `[home] Settings` |
| Samples (Welcome island, the Enigma story) | `[home] Welcome island` |
| A project's menu (the hold menu): duplicate, rename; add to stack (and move out), share (one file, a folder), archive; delete | touch and hold a card |
| A stack's menu: rename, unstack | touch and hold a stack |
| Make a stack | drag a card onto another |

## Top left

### Home (⌂)

| Control | Walk |
|---|---|
| Back to Home (the stage shrinks into its card) | `Home` |

### Actions

| Control | Walk |
|---|---|
| Export (presets, stills, GIF, a 3D model as glTF, USDZ, OBJ, STL, 3MF or a Blender package; background export) | `Actions › open-export` |
| Share the project file | `Actions › Project file` |
| Monitor window (Stage Manager, external display) | `Actions › open-monitor` |
| Scenes: switch, new, duplicate, rename | `Actions › Rename` |
| Copy a scene to another project | `Actions` (shown when there is another project) |
| History scrubber, versions | `Actions › open-history` |
| Scripts | `Actions › open-scripts` |
| AI & laptop bridge | `Actions › open-bridge` |
| Paste a Scene Script | `Actions › Paste script` |
| Gestures | `Actions › Gestures` |
| The tour | `Actions › Tour` |
| Diagnostics, the benchmark, the Pencil's touch-to-screen latency | `Actions › Diagnostics` |
| Settings | `Actions › Settings` |

### Look

| Control | Walk |
|---|---|
| Only this scene | `Look › Only this scene` |
| Looks (Ink, Comic, Sketch, Clay, Low-poly, My Looks) | `Look › look-clay` |
| Duplicate as My Look (and its editor) | `Look › duplicate-look` |
| Moods | `Look › mood-dusk` |
| Palette (linked colours; the sidebar's Pick fills the slot being edited) | `Look › Add a colour` |
| Finish (clean, cinematic, dreamy, retro, ink outlines, collage, old film; grain, bloom) | `Look › Cinematic` |
| Fine tune the world | `Look › Fine tune the world` |
| Save the world to the library | `Look › Save this world to the library` |

### Select

| Control | Walk |
|---|---|
| Tap to select | `Select › Tap` |
| Lasso | `Select › tool-lasso` |
| Select similar, all, none | `Select › All` |
| The outliner: select, eye, lock; touch and hold a row for the object's menu (with move to top level, move into a group, frame) | `Select › outliner` |

## Top right

### Model

| Control | Walk |
|---|---|
| Shapes (cube, sphere, cylinder, cone, plane, torus, ramp; bevelled) | `Model › model-add › add-cube` |
| | `Model › model-add › add-ramp` |
| Building: walls along tapped corners, floor, door, window, stairs | `Model › model-add › build-walls` |
| | `Model › model-add › build-stairs` |
| Lamp, spot, sun | `Model › model-add › add-spot` |
| Camera from this view | `Model › model-add › add-camera` |
| 3D text | `Model › model-add › add-text3d` |
| Title and label on the frame | `Model › model-add › add-title` |
| Photo or video (a card in the world) | `Model › model-add › add-media` |
| Marks on the frame (arrow, circle, star…) | `Model › model-add › add-overlay-arrow` |
| Effects (fire, sparks, smoke…) | `Model › model-add › add-fx-fire` |
| Screen effects at the playhead | `Model › model-add › effect-flash` |
| Sketch on a face or the ground: line, rectangle, circle, arc, spline, offset | `Model › model-shape › sketch-rectangle` |
| | `Model › model-shape › sketch-offset` |
| Push/pull: pick faces, edges or corners (tap, Pencil loop) | `Model › model-shape › pick-face` |
| Booleans: union, subtract, intersect (two or more shapes selected) | `Model › model-shape › boolean-subtract` |
| Mirror (across the picked face or the middle), live symmetry | `[cube] Model › model-shape › symmetry` |
| 3D print: the printer, check for printing, repair | `Model › model-shape › print-check` |
| Make a shape (or a placed library model) editable | `[cube] Model › model-shape › make-editable` |
| The Model tool's bar: pick modes, sketch shapes, Done, grow / shrink / select similar, bevel / round (edges), inset / shell (faces), the measurement and Keep, ✕ | shown at the bottom while the Model tool is on |
| The numbers on the stage (pull distance, sides, diameter, length, offset, a bevel's or shell's size, the wall height and thickness): tap to type | shown beside what they measure |
| Measurements and kept dimensions on the stage: tap one to keep it, or to select it | shown beside what they measure |
| Library: the Kit's sets, your models, builds, worlds, scripts; search | `Model › model-library › library-search` |
| Import models (USDZ, glTF, GLB, OBJ, STL, 3MF) | `Model › model-library › Import models` |
| Snap to grid and its size | `Model › model-precision › snap-grid` |
| Snap to corners and middles, edges, faces | `Model › model-precision › snap-corners` |
| Snap to objects, to the ground | `Model › model-precision › Snap to objects` |
| Turn in steps | `Model › model-precision › Turn in steps` |
| Grid on the ground | `Model › model-precision › show-grid` |
| Units (mm, cm, m, in, ft) | `Model › model-precision › units` |
| Measure (two taps; keep it as a dimension) | `Model › model-precision › measure` |
| Show kept dimensions | `Model › model-precision › show-dimensions` |
| Section view: across x, y or z, along the picked face; where it cuts; the other side | `Model › model-precision › section-x` |
| Swap a shape for a model | `[cube] more-actions` (Swap for a model… opens Model's library) |

### Draw

| Control | Walk |
|---|---|
| Ink: draw, erase, select strokes | `Draw › tool-ink › ink-erase` |
| The brush ink draws with (opens the brush library) | `Draw › tool-ink › brush-ink` |
| Ink's drawing guide on the guide plane: grid, isometric, symmetry; Drawing assist | `Draw › tool-ink › drawing-guide` |
| Solid shape: tube, ribbon, extrude, lathe; guide; mirror | `Draw › tool-draw › Tube` |
| Flipbook: draw, erase, tracks | `Draw › tool-flipbook › flipbook-tracks` |
| The brush flipbooks draw with (opens the brush library) | `Draw › tool-flipbook › brush-flipbook` |
| The frame's drawing guide: 2D grid, isometric, 1-, 2- and 3-point perspective, symmetry; Drawing assist | `Draw › tool-flipbook › drawing-guide` |
| Brush library: sets, choose a brush, new set, share a set, import Procreate (.brushset, .brush) and Photoshop (.abr) brushes | the brush row's sheet |
| A brush's menu (the hold menu): duplicate, rename; Brush Studio, reset, move to a set; delete | touch and hold a brush in the library |
| Brush Studio: stroke, shape, grain, dynamics, Pencil, rendering, about; the pad to try it | a brush's menu ▸ Edit in Brush Studio |

### Paint

| Control | Walk |
|---|---|
| Colour: paint, erase, fill and the eyedropper on models | `Paint › tool-paint › paint-pick` |
| The brush painting uses (opens the brush library) | `Paint › tool-paint › brush-paint` |
| Paint the chosen object (it's laid flat for painting first; a stroke on it does the same) | `[cube] Paint › tool-paint › paint-start` |
| Layers: show or hide, the one the Pencil paints on, its opacity and blend, add a layer | `[cube] Paint › tool-paint › paint-start › paint-layer-add` |
| A layer's menu: duplicate, merge down, move up or down, clear, rename, delete; remove all paint | `[cube] Paint › tool-paint › paint-layer-menu` |
| A layer's hold menu: duplicate, rename; merge down, clear; delete | touch and hold a layer |
| Project a picture: from Photos or Files, placed with the fingers, Project from the options bar | Paint ▸ Colour on a painted object |
| Paint, erase, fill, eyedropper, the layer painted on, done (options bar) | shown under the stage while Colour is on |
| Size and opacity of the paint brush | the sidebar's two sliders while Colour is on |
| Shadow Brush: push shadow in, pull light out | `Paint › tool-shadow-brush › Push shadow in` |
| Shadow presets | `Paint › tool-shadow-brush › section-Presets` |
| Scatter copies of the selection on the ground | `Paint › tool-scatter` |

### Animate

| Control | Walk |
|---|---|
| The whole timeline | `Animate › timeline` |

### Cast

| Control | Walk |
|---|---|
| Add a Blob | `Cast › add-blob` |
| Add me | `Cast › add-me` |
| Add a Puppet | `Cast › add-character` |
| Expressions at the playhead | `[blob] Cast › expression-happy` |
| Clips | `[blob] Cast › section-Clips` |
| Lip sync | `[blob] Cast › lip-sync` |
| Face capture (front camera, iPhone) | `[blob] Cast › face-camera` |
| Rig, in three steps: Bones, Skin, Pose (each shows only its tools; a step opens when the one before is done) | `[cube] Cast › rig-step-bones` |
| Bones: draw a bone through a limb, tail or rope of anything with a surface; draw along one again to replace it | `[cube] Cast › rig-draw-bone` |
| Bones: rig as a person (the front view, tap eight dots or drag them, Rig); remove the rig | `[cube] Cast › rig-person` |
| Skin: the weights come by themselves; paint weights, fit the weights to a new shape | Cast ▸ Rig ▸ Skin once there are bones |
| Pose: drag the joints (the Select tool), reset the pose | Cast ▸ Rig ▸ Pose once the skin fits |
| The Rig tool's bar: the three steps, the bone whose weight is painted and erase (Skin), done; the person rig's Rig and cancel | shown under the stage while Rig is on |
| The weight brush's size and strength | the sidebar's two sliders while painting weights |
| Pose any character by dragging its joints (IK); poses, mirror | the joints on the stage when a character is selected; Cast ▸ Poses |

## The inspector (beside the selection)

| Control | Walk |
|---|---|
| Name | `[cube] inspector-name` |
| Move, turn, size (the gizmo and the joystick) | `[cube] gizmo-rotate` |
| Move it: spin, float, bounce, wiggle, swing, follow a path (one tap each, they loop; a second tap stops) | `[cube] motion-bounce` |
| The speed of what's moving, Make keyframes | under the six motions while one is running |
| Position, rotation, size as numbers | `[cube] transform-toggle` |
| Its size in the project's units, and what the Model tool picked | `[cube] selection-size` |
| Look override, lines, accents | `[cube] look-override` |
| Motion, behaviours, physics | `[cube] section-Motion` |
| More: metadata | `[cube] inspector-more` |
| Duplicate, hide | `[cube] Duplicate` |
| More actions: array, to the ground, group, ungroup, swap, save to library, unpack, lock, copy | `[cube] more-actions` |
| Delete | `[cube] Delete` |
| Resize | `[cube] resize-inspector` |
| Align and distribute (several selected) | in the inspector when more than one thing is selected |
| Camera: shot, framing, lens, focus, moves, transitions | in the inspector when a camera is selected |

## The sidebar

| Control | Walk |
|---|---|
| Two sliders that follow the tool (snapping and speed at rest) | `Snapping` |
| Pick a colour from the stage | `Pick` |
| The colour in the hand (the Look's palette, any colour), for Ink, solid shapes, Flipbook and Paint ▸ Colour | `Draw › tool-ink › colour-well` |
| Undo, redo | `Undo` |

## The bottom row

| Control | Walk |
|---|---|
| The timeline on call | `timeline-toggle` |
| Views (top, front, side; perspective or orthographic) | `views-menu` |
| Frame the selection | `Frame the selection` |
| Director view | `director-view` |
| Joystick (on by default; its × hides it, Settings ▸ Stage brings it back) | `[cube] hide-joystick` |
| Tool options (ink, solid shape, flipbook, Shadow Brush, scatter) | below the stage while that tool is on |

## The timeline

| Control | Walk |
|---|---|
| Compose | `[timeline] timeline-mode-compose` |
| Keyframe: key, auto-key, pick keys, easing, graph editor | `[timeline] timeline-mode-keyframe › auto-key` |
| Perform: record, Pencil roll | `[timeline] timeline-mode-perform › perform-record` |
| Markers | `[timeline] Add marker` |
| Sound and words: voiceover, music, effects, transcript | `[timeline] Sound and words` |
| Loop, fit, snap to words, timeline settings | `[timeline] timeline-menu` |
| Resize, or switch to the transport | `[timeline] timeline-divider` |
| A key's hold menu: copy, paste; easing, reverse, mirror; delete | touch and hold a key |
| A clip's hold menu: split at the playhead, loop or play once; delete | touch and hold a clip |
| A flipbook drawing's hold menu: duplicate; hold longer, hold shorter; delete (the track's is on its name) | touch and hold a drawing |
| To the slim transport | `[timeline] Collapse the timeline` |
| The slim transport: play, the time | `[transport] Play` |
| Back to the whole timeline | `[transport] Show the timeline` |
| Send the timeline away | `[transport] hide-timeline` |

## The hold menu

Touch and hold any thing and the same menu opens in the same order (CONTEXT §4.1): **Duplicate · Rename · Copy ·
Paste**, then one to three extras that fit the thing, then **Delete** in red. The first four and Delete are always in
the same places; a row a thing can't do is dimmed. On the stage (Select tool) a finger held still on an object opens
its menu (Hide, Lock, Group; **Add to the selection** when other things are selected); a finger that moves is a drag.
The same object has the same menu in the outliner and on its timeline row. Also on: keys, clips, flipbook drawings and
tracks, cuts, screen effects, paint layers, brushes, Looks, library items, poses, palette colours, Home's cards and
stacks.

## Settings

| Control | Where |
|---|---|
| Theme, sidebar on the right, haptics | Settings ▸ Appearance |
| Pencil or hand: draw with a finger too (automatic otherwise: a finger makes until an Apple Pencil has touched) | Settings ▸ Pencil or hand |
| Pencil hover preview, always full resolution, moving-around speed | Settings ▸ Stage |
| Dock the inspector at the side (off: it floats beside the selection) | Settings ▸ Stage |
| Joystick under a selection and its speed | Settings ▸ Stage |
| iCloud Drive | Settings ▸ Storage |
| How full this iPad's frame is and what the preview is doing about it; benchmarks; Pencil latency; logs | Settings ▸ Diagnostics (and Actions) |

## Elsewhere, on purpose

- **Gestures** (CONTEXT §4.1): two-finger tap undo, three-finger tap redo, two-finger hold rapid undo, four-finger
  tap hides everything but the stage, pinch, double-tap to frame, touch and hold for the hold menu.
- **Under load nothing is said on the stage** (CONTEXT §6): the preview lightens by itself and comes back.
- **The menu bar and keyboard** reach the same controls: ⌘1–⌘5 the making tools, ⌘6–⌘8 Actions, Look, Select, ⌘L the
  library, ⌥⌘1–3 move, turn, size, ⌘T the timeline, Space/J/K/L and ⌥←→ the transport. Holding ⌘ lists them.
- **Proposals** from the AI bridge appear at the bottom of the stage while one is waiting.

## What moved from 2.0

| 2.0 | Now | Why |
|---|---|---|
| Theater | Home | It's home: the living gallery |
| Build | Model ▸ Add | Model is the making tool for things in the world |
| Library (top right) | Model ▸ Library | Placing a model is modelling; a sixth button would break the ≤ 5 rule |
| Transform: gizmo modes | the inspector | They act on the selection |
| Transform: snapping, grid | Model ▸ Precision | Precision is modelling: units, measuring and the section view are there too |
| Transform: align, distribute | the inspector (several selected) | They act on the selection |
| Transform: drop to the ground | the inspector's More actions | It was in both |
| Transform: joystick toggle and speed | Settings ▸ Stage, and the joystick's own × | A preference, not a tool; on by default now |
| Draw ▸ Shadow Brush | Paint | Painting on objects |
| Inspector ▸ More ▸ Scatter | Paint ▸ Scatter | Painting copies over the ground |
| Actions ▸ Add ▸ Photo or video | Model ▸ Add | It adds a thing to the world |
| Actions ▸ Add ▸ Sound, Voiceover | the timeline's Sound and words | Time lives in the timeline; it was in both |
| Actions ▸ Project ▸ Timeline | the timeline's menu | It was in both |
| The palette's own Pick | the sidebar's Pick | It was in both |
| The timeline under the stage | on call, hidden by default | The canvas owns the screen |

## What moved in 0.8

| 0.7 | Now | Why |
|---|---|---|
| The load chip and Settings ▸ Smoothness warnings | gone; the numbers are in Diagnostics ▸ Smoothness | A message is what makes it feel not smooth (D-176) |
| Model ▸ Shape (the page) | Model ▸ Edit, same place and contents | "Shape" beside Add's "Shapes" hid the sphere (D-179) |
| Draw ▸ Draw with a finger too | Settings ▸ Pencil or hand | Automatic now; one switch, none on the canvas (D-183) |
| Touch and hold on the stage adds to the selection | the hold menu's Add to the selection | Hold is the menu everywhere (D-181) |
| Float, Wobble, Spin in the inspector's Add a behaviour | the Motion row at the top of the inspector | One tap, one home (D-184) |
| Cast ▸ Rig's six buttons | Bones → Skin → Pose | Only the step's own tools (D-187) |
