# Tools (generated)

Generated from the `lowey` MCP server by `Tools/gen-skill-tools.py` — don't edit by hand. 16 tools; everything that changes the scene goes through `build` (Scene Script v3, one Proposal, one undo step).

## `status`

Which iPad is paired, the open project, scene and shot, the playhead, whether auto-apply is on.

## `read_project`

The project at a glance (a summary line first): scenes, shots (cameras, when the edit cuts to them, on which word), the cast, the Look, the palette, Kit Sets in use and the voiceover text. transcript=True adds every word's timing.

| Parameter | Type | Default |
|---|---|---|
| `transcript` | boolean | `false` |

## `find_assets`

Kit and library models by words ("desk lamp", "rock", "robot"), Kit first, optionally in one Set ("Room & Desk", "Nature", "Office & Computers", "Lab & Science", "Space", "City & Street", "Kitchen & Food", "Props & Signs", "Characters"). Each has its id (use it in build's add), real size in metres, surface heights to put things on, its front. The first `thumbnails` come with a picture.

| Parameter | Type | Default |
|---|---|---|
| `query` | string | `""` |
| `set` | string or null | `null` |
| `limit` | integer | `8` |
| `thumbnails` | integer | `4` |

## `build`

Scene Script v3 (resource lowey://actions has every verb): add from the Kit, place by relation, scaleTo, recolor, remove, group, frameShot, lighting, look, intent, preset, keys, cameraMove, cut, overlay, flipbook, effect… Many actions, ONE Proposal on the iPad, ONE undo step. Returns what changed and an observe of the result (views: camera, top, front, side, value, silhouette). dry_run=True previews without proposing and returns a proposal_id for commit.

| Parameter | Type | Default |
|---|---|---|
| `actions` | list[object] | required |
| `title` | string | `"From Claude"` |
| `dry_run` | boolean | `false` |
| `views` | list[string] or null | `null` |
| `subject` | string or null | `null` |

## `frame_shot`

The camera solver: shot_type extremeWide | wide | full | medium | closeUp | extremeCloseUp | overTheShoulder | twoShot | insert; composition center | leftThird | rightThird | lowAngle | highAngle; lens in mm (the shot type picks one otherwise). `shot` names the camera (made when new). With on_word/at the edit cuts to it there.

| Parameter | Type | Default |
|---|---|---|
| `subject` | string | required |
| `shot_type` | string | `"medium"` |
| `composition` | string | `"center"` |
| `lens` | number or null | `null` |
| `shot` | string or null | `null` |
| `other` | string or null | `null` |
| `at` | any | `null` |
| `on_word` | string or null | `null` |

## `light`

A lighting recipe placed for the shot camera: key-warm-world-cool (the default story light), noir-single-source, golden-rim, monitor-glow, moonlit, studio-soft. Overrides: intensity (×), warmth (-1 cool … 1 warm).

| Parameter | Type | Default |
|---|---|---|
| `recipe` | string | required |
| `subject` | string or null | `null` |
| `intensity` | number or null | `null` |
| `warmth` | number or null | `null` |

## `set_look`

The Look (ink, comic, sketch, clay, lowpoly), the mood (day, goldenHour, dusk, night, space, studio) and per-object Looks ({"Robot": "sketch"}).

| Parameter | Type | Default |
|---|---|---|
| `look` | string or null | `null` |
| `mood` | string or null | `null` |
| `per_object` | object or null | `null` |
| `scene_only` | boolean | `true` |

## `animate`

Say the intent; the app picks the animation. what: enter | exit | emphasise | react | walk_to | look_at | talk | idle — or a preset (popIn, bounce, float…) or a clip (Wave, Walk, Nod…). how: an expression for react (surprised, happy, shocked…). to: where walk_to / look_at go (a name or [x, y, z]). frame_rate: ones | twos | threes | fours.

| Parameter | Type | Default |
|---|---|---|
| `targets` | string or list[string] | required |
| `what` | string | required |
| `at` | any | `null` |
| `on_word` | string or null | `null` |
| `duration` | number or null | `null` |
| `how` | string or null | `null` |
| `to` | any | `null` |
| `frame_rate` | string or null | `null` |

## `camera_move`

pushIn, pullOut, punchIn, snapZoom, orbit, dolly, truck, crane, whipPan, shake, reveal — eased, landing on the word.

| Parameter | Type | Default |
|---|---|---|
| `move` | string | required |
| `shot` | string or null | `null` |
| `subject` | any | `null` |
| `strength` | number or null | `null` |
| `at` | any | `null` |
| `on_word` | string or null | `null` |
| `duration` | number or null | `null` |

## `add_overlay`

Titles, labels and comic language over the frame: title, label, arrow, highlight, cross, question, exclamation, check, circle, star. It pops in on `on_word`. style: {"at": [x, y] in -1…1, "size": 1, "color": "palette:2", "follow": "Paper"}. Don't repeat the voiceover word for word.

| Parameter | Type | Default |
|---|---|---|
| `kind` | string | required |
| `text` | string or null | `null` |
| `on_word` | string or null | `null` |
| `at` | any | `null` |
| `style` | object or null | `null` |
| `name` | string or null | `null` |

## `flipbook`

Drawn FX that sell a moment: speedLines, impactBurst, sweatDrop, sparkle, smear — anchored to an object (or a point) from `on_word` (or `at`) until `until`.

| Parameter | Type | Default |
|---|---|---|
| `kind` | string | required |
| `anchor` | any | required |
| `at` | any | `null` |
| `on_word` | string or null | `null` |
| `until` | any | `null` |
| `frames` | integer or null | `null` |
| `color` | string or null | `null` |

## `add_media`

A picture or video file from this laptop into the open shot: a thin card standing in the 3D world, or overlay=True to lay it flat over the frame. Videos play from `at` seconds (default: the playhead).

| Parameter | Type | Default |
|---|---|---|
| `path` | string | required |
| `at` | number or null | `null` |
| `overlay` | boolean | `false` |

## `render_manim`

Render Manim on this laptop and lay it over the shot from `at` seconds (graphs, equations, diagrams). `code` is the Python source (or a path to a .py file); `scene` the Scene class. Transparent by default, floating over the 3D world.

| Parameter | Type | Default |
|---|---|---|
| `code` | string | required |
| `scene` | string | required |
| `at` | number or null | `null` |
| `quality` | string | `"high"` |
| `transparent` | boolean | `true` |

## `observe`

Look at the shot: the camera view with set-of-marks numbers, plus any of top / front / side (orthographic layout diagrams with the shot camera drawn on), value (the squint) and silhouette. The ShotReport measures every marked object (coverage, visible %, grounded + gap, intersects, cut by the frame, facing) and the frame (subject on thirds, headroom, ΔL* contrast, clutter, tangents, palette, key light) and checks the rubric with a fix for each fail.

| Parameter | Type | Default |
|---|---|---|
| `time` | number or null | `null` |
| `views` | list[string] or null | `null` |
| `subject` | string or null | `null` |
| `framing` | string or null | `null` |
| `report` | boolean | `true` |

## `contact_sheet`

N frames of the shot in a grid with timecodes and notes, plus motion stats per moving thing (screen path, peak speed, direction changes, holds, leaves frame, arcs vs straight lines, constant-speed glides, moves landing on words) and the camera's move. Critique motion with it.

| Parameter | Type | Default |
|---|---|---|
| `start` | number or null | `null` |
| `end` | number or null | `null` |
| `frames` | integer | `6` |
| `subject` | string or null | `null` |

## `commit`

action="commit": propose a dry run (its proposal_id) on the iPad for real. action="undo": undo `steps` changes.

| Parameter | Type | Default |
|---|---|---|
| `action` | string | `"commit"` |
| `proposal_id` | string or null | `null` |
| `steps` | integer | `1` |
