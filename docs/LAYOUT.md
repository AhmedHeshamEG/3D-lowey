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
│ ↶ ↷                                                                         └──────┘ │
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
| A project's menu: open, rename, duplicate, add to stack, move out, share, export folder, archive, delete | touch and hold a card |
| A stack's menu: open, rename, unstack | touch and hold a stack |
| Make a stack | drag a card onto another |

## Top left

### Home (⌂)

| Control | Walk |
|---|---|
| Back to Home (the stage shrinks into its card) | `Home` |

### Actions

| Control | Walk |
|---|---|
| Export (presets, stills, GIF, background export) | `Actions › open-export` |
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
| Diagnostics, the benchmark | `Actions › Diagnostics` |
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
| The outliner: select, eye, lock, rename, move into a group, frame, delete | `Select › outliner` |

## Top right

### Model

| Control | Walk |
|---|---|
| Shapes (cube, sphere, cylinder, cone, plane, torus, ramp; bevelled) | `Model › model-add › add-cube` |
| | `Model › model-add › add-ramp` |
| Lamp, spot, sun | `Model › model-add › add-spot` |
| Camera from this view | `Model › model-add › add-camera` |
| 3D text | `Model › model-add › add-text3d` |
| Title and label on the frame | `Model › model-add › add-title` |
| Photo or video (a card in the world) | `Model › model-add › add-media` |
| Marks on the frame (arrow, circle, star…) | `Model › model-add › add-overlay-arrow` |
| Effects (fire, sparks, smoke…) | `Model › model-add › add-fx-fire` |
| Screen effects at the playhead | `Model › model-add › effect-flash` |
| Library: the Kit's sets, your models, builds, worlds, scripts; search | `Model › model-library › library-search` |
| Import models (USDZ, glTF, GLB, OBJ) | `Model › model-library › Import models` |
| Snap to grid and its size | `Model › model-snapping › snap-grid` |
| Snap to objects, to the ground | `Model › model-snapping › Snap to objects` |
| Turn in steps | `Model › model-snapping › Turn in steps` |
| Grid on the ground | `Model › model-snapping › show-grid` |
| Swap a shape for a model | `[cube] more-actions` (Swap for a model… opens Model's library) |

### Draw

| Control | Walk |
|---|---|
| Ink: draw, erase, select strokes | `Draw › tool-ink › ink-erase` |
| Solid shape: tube, ribbon, extrude, lathe; guide; mirror | `Draw › tool-draw › Tube` |
| Flipbook: draw, erase, tracks | `Draw › tool-flipbook › flipbook-tracks` |

### Paint

| Control | Walk |
|---|---|
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

## The inspector (beside the selection)

| Control | Walk |
|---|---|
| Name | `[cube] inspector-name` |
| Move, turn, size (the gizmo and the joystick) | `[cube] gizmo-rotate` |
| Position, rotation, size as numbers | `[cube] transform-toggle` |
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
| To the slim transport | `[timeline] Collapse the timeline` |
| The slim transport: play, the time | `[transport] Play` |
| Back to the whole timeline | `[transport] Show the timeline` |
| Send the timeline away | `[transport] hide-timeline` |

## Elsewhere, on purpose

- **Gestures** (CONTEXT §4.1): two-finger tap undo, three-finger tap redo, two-finger hold rapid undo, four-finger
  tap hides everything but the stage, pinch, double-tap to frame, touch and hold for options.
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
| Transform: snapping, grid | Model ▸ Snapping | Precision is modelling (units and measuring join it) |
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
