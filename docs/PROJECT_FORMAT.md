# Project format

A Maquette project is a folder package (it shows as one file in the Files app). This document is the public
surface of that package: power users, scripts and MCP clients may **read** any of it. **Writes go through the app**
(the laptop bridge), so undo and the history journal stay true; a file changed behind the app's back is overwritten at
the next checkpoint.

Format version: package **2**, document schema **8** (`LoweySchema.currentVersion`), journal **1**.

```
My film.maquette/                 (3D-lowey's .lowey packages open too, and are upgraded in place)
  manifest.json                   which app wrote it, what it is, its package version
  project.json                    the project: name, scene list, the project Look
  scenes/<scene-id>.json          one scene each: objects, hierarchy, camera, timeline
  history/<scene-id>/             that scene's history journal (below)
  assets/                         library models the project carries (written by "Share as one file"), media,
                                  brushes/<hash>.png: the pictures of the brushes its strokes use, and
                                  paint/<hash>.png, paint/<hash>.uv: painted objects' tiles and unwraps
  audio/                          voiceovers and sounds
  renders/                        exports kept with the project
  thumbnail.png, thumbnail-loop.gif   the Home card (a still, and the model turning once in its Look)
  workspace.json                  how the project shows: the timeline, snapping, the grid, the section view (not part of undo)
```

Beside the packages, the projects folder holds `gallery.json`: Home's stacks and sort order (below).

Every JSON file is written atomically and keeps the previous good version beside it as `<name>.bak`; a damaged file
is read from its backup.

## manifest.json

```json
{"schemaVersion": 2, "app": "lowey", "kind": "project", "created": 781203000.0, "modified": 781203600.0}
```

Dates in every file are seconds since 2001-01-01 UTC (`timeIntervalSinceReferenceDate`). `app` stays `"lowey"` so
3D-lowey 2.0 and Maquette read each other's manifests.

## Versioned files

`project.json`, `scenes/*.json` and the journal's snapshots are envelopes:

```json
{"schemaVersion": 5, "kind": "project", "payload": { … }}
```

An older `schemaVersion` is migrated when read (every migration since 1.x is in `LoweySchema.migrations`); a newer one
is refused with a sentence asking to update the app. Keys are stable: a key is only ever added, and a removed or
renamed one gets a migration.

## project.json (`kind: "project"`)

| Key | Type | Meaning |
|---|---|---|
| `id` | string | The project's id. |
| `name` | string | Its name on the Home screen. |
| `created`, `modified` | number | Dates (see above). `modified` decides which of `project.json` and a scene's journal is newer for project-wide settings. |
| `look` | object | The project Look (every scene without its own uses it): `presetID` (`ink`, `comic`, `sketch`, `clay`, `lowPoly`), mood, palette, sky, fog, ground, shading, post. |
| `sceneOrder` | [string] | Scene ids in order. |
| `sceneNames` | {id: string} | Scene names by id. |
| `lastOpenedScene` | string? | Where the project reopens. |
| `looks` | [object]? | The project's own Looks ("My Look"); absent when there are none. |
| `brushes` | {key: object}? | Since schema 7: a frozen copy of every brush a stroke uses, by its content key (`b-<hash>`); absent when there are none. See "Brushes" below. |

## scenes/<scene-id>.json (`kind: "scene"`)

| Key | Type | Meaning |
|---|---|---|
| `id`, `name` | string | |
| `objects` | {id: object} | Every object by id: `id`, `name`, `kind` (what it is: primitive, model, light, camera, text, drawing, mesh, sketch, character…; see below), `parent`, `children`, `properties` (typed values: `position`, `rotation`, `scale`, `color`, `visible`, …), `shadowPaint` when the Shadow Brush painted it, and `paint` when colour is painted on it (schema 8, below). |
| `roots` | [string] | Top-level objects in outliner order. |
| `look` | object? | The scene's own Look (absent: the project's). |
| `activeCamera` | string? | The shot camera. |
| `viewpoint` | object | The work view's orbit camera. |
| `timeline` | object | fps, duration, tracks of keys, clips, markers, cuts, words and audio, effects, captions. |

The Scene Script schema (`schemas/scene-script.v3.schema.json`) documents the commands that change these files.

## The history journal: history/<scene-id>/

Every change to a scene is recorded moments after it happens, so a killed app loses nothing and undo survives a
relaunch. Opening a scene reads its latest checkpoint and replays the changes after it.

```
history/<scene-id>/
  checkpoint.json      the latest checkpoint (checkpoint.json.bak: the one before)
  snapshots/<n>.json   the scene and project at checkpoint n (a versioned file, kind "document")
  segments/<n>.jsonl   every change since checkpoint n, one JSON line each
  entries/<n>.jsonl    undo steps first stored by checkpoint n
  base.json            the scene when its journal began (where a time-lapse starts)
  versions/            named and automatic versions
```

### Segments

The first line is a header; every other line is one change, numbered across segments:

```json
{"journal":1,"schema":4,"segment":3}
{"op":{"command":{"op":"setProperties","changes":[…]},"key":"drag-…","op":"perform"},"seq":401,"t":781203612.4}
{"op":{"op":"endCoalescing"},"seq":402,"t":781203612.9}
{"op":{"op":"undo"},"seq":403,"t":781203614.0}
```

`op` is one of `perform` (a command, as in a Scene Script, with the gesture's coalescing `key`), `endCoalescing`,
`beginGroup` (`label`), `endGroup`, `cancelGroup`, `undo`, `redo`. Replaying them in order on the snapshot they
follow rebuilds the scene and its undo history exactly. A line cut short by a killed app is skipped. Segments are
never deleted: together they are the whole making-of. `schema` is the document schema the commands were written in;
older ones are migrated line by line (`ProjectHistory.opMigrations`).

### Checkpoints

Every 200 changes, after 5 seconds without one, when the app leaves the screen and when a scene closes:

```json
{"format":1,"seq":400,"segment":3,"saved":781203610.0,
 "undo":[{"id":"…","file":2,"offset":18233,"length":412,"label":"Move Lamp"}, …],
 "redo":[…]}
```

`undo` and `redo` point at steps in `entries/<file>.jsonl` (`offset` and `length` in bytes): each step is stored once,
and opening reads only the newest 64; older ones are read when undo reaches them. A checkpoint also rewrites
`project.json` and the scene file from the same state.

### Versions

`versions/index.json` lists them (`id`, `name`, `date`, `automatic`); `versions/<id>.json` holds each as a snapshot.
Maquette keeps one automatically each time a scene opens and after each hour of work (the newest 40), and whenever
the history scrubber goes back (the state it left). Named versions stay until deleted.

### Meshes and sketches (schema 5)

A modelled object is `{"type": "mesh", "mesh": {"v": [x, y, z, …], "f": [[[0, 1, 2, 3]], …]}}`: `v` is every vertex as
three numbers in a row, in the object's own space (metres, to the nanometre); `f` is every face as a list of loops of
vertex indices, the outline first (counter-clockwise seen from outside) and then its holes (clockwise). A closed,
outward-facing mesh is a solid.

A sketch is `{"type": "sketch", "sketch": {"plane": {"origin", "normal", "u", "v"}, "curves": […], "target": "<id>"?}}`:
the plane in world space (`u` and `v` are its in-plane axes; curve points are `[u, v]` metres along them), and the
object it was drawn on, if any. Each curve is one of `{"line": {"_0": p, "_1": p}}`, `{"rectangle": {"_0": p, "_1": p}}`
(opposite corners), `{"circle": {"center": p, "radius": r}}`, `{"arc": {"_0": start, "_1": through, "_2": end}}`,
`{"spline": {"_0": [p, …], "closed": bool}}`, `{"polyline": {"_0": [p, …], "closed": bool}}`. Sketches are construction
lines: renders and exports leave them out.

Schema 5 only added these two kinds; files from schema 4 open unchanged. Apps that read schema 4 refuse schema 5
files with a message saying the project needs a newer Maquette.

### Dimensions and symmetry (schema 6)

A kept dimension is `{"type": "dimension", "dimension": {"start": [x, y, z], "end": [x, y, z]}}`: its two ends in the
object's own space (it sits under the object it measured, so it moves with it). Like sketches, it's drawn on the stage
only: renders and exports leave it out.

A modelled object with live symmetry has the property `symmetry`: `{"enum": "x"}` (or `y`, `z`), the plane through its
pivot square to that axis. Model edits keep the side they touched and make the other side its mirror image; the mesh
stored is always the whole, symmetric shape.

Schema 6 only added the kind and the property; files from schema 5 open unchanged, and Maquette 0.3 refuses schema 6.

### Brushes (schema 7)

A brush (`project.json` › `brushes` › `b-<hash>`) is `{"id", "name", "shape", "grain", "stroke", "dynamics", "rendering",
"about"}`:

- `shape`: `source` (a built-in tip: `hardRound`, `softRound`, `pencilTip`, `chalkTip`, `bristleTip`, `flatTip`,
  `splatterTip`, or a picture key `brushes/<hash>.png` under `assets/`), `roundness`, `angle` (degrees),
  `followsStroke`, `rotationJitter`, `flipXJitter`, `flipYJitter`, `count`, `inverted`.
- `grain`: `source` (absent for none; `paper`, `canvas`, `noise`, `charcoal` or a picture key), `scale`, `depth`,
  `movement` (`rolling` or `texturized`), `inverted`.
- `stroke`: `spacing` (tip diameters), `streamline`, `jitter`, `falloff`, `taperStart`, `taperEnd`, `taperSize`,
  `taperOpacity`.
- `dynamics`: `pressureSize`, `pressureOpacity`, `pressureCurve` (`{"points": [{"x", "y"}…]}`), `tiltSize`,
  `tiltOpacity`, `speedSize`, `speedOpacity`, `sizeJitter`, `opacityJitter`, `minimumSize`, `minimumOpacity`.
- `rendering`: `flow`, `wetEdges`, `softness`. `about`: `origin` (`builtIn`, `made`, `procreate`, `photoshop`,
  `shared`), `author`, `resetsTo`.

The key is a hash of the settings, so the same brush is stored once however many strokes use it, and a brush edited in
the library is a new key. Pictures are grey PNGs (white paints).

An ink stroke (`drawing` › `strokes[]`) and a flipbook stroke (`timeline.flipbooks[]` › `frames[]` › `strokes[]`) may
carry `alphas` (each point's opacity, from the brush's dynamics), `brush` (a key in `brushes`) and `seed` (the jitter's
seed, so the stroke draws the same every time). A stroke without `brush` draws with Ink Pen, as 2.0's did. Points and
widths are the smoothed path the brush stamps along (widths are radii).

Schema 7 only added optional keys and the `setBrushes` journal command; files from schema 6 open unchanged, and
Maquette 0.4 refuses schema 7.

### Paint (schema 8)

Colour painted on an object is its `paint`: a surface and layers, bottom first.

```json
"paint": {
  "surface": {"size": 2048, "unwrap": "paint/1f3a…c2.uv", "mesh": "9b0e…41"},
  "layers": [
    {"id": "l1", "name": "Layer 1", "opacity": 1, "blend": "normal", "visible": true,
     "tiles": {"3,1": "paint/77ac…08.png", "4,1": "paint/e2d1…9f.png"}}
  ]
}
```

- `surface.size`: pixels a side of every layer, a multiple of 256 (2048 for new paint).
- `surface.unwrap`: where every corner of the mesh lies on the texture (below).
- `surface.mesh`: the fingerprint (FNV-1a, 16 hex digits) of the mesh the unwrap was made for: the triangles the app
  draws for the object, in its own space. When the object's shape changes (modelling, a bevel), the fingerprint no
  longer matches and the app carries the paint onto the new shape by position, without changing the file; the next
  stroke stores the carried paint.
- `layers[]`: `id`, `name`, `opacity` (0–1), `blend` (`normal`, `multiply`, `screen`, `overlay`, `add`: the W3C
  compositing formulas on the stored sRGB values), `visible`, and `tiles`: `"column,row"` (from the top left, 256
  pixels each) to a PNG under `assets/`. A missing tile is transparent. Tiles are RGBA, straight alpha, sRGB.

Every file is named by a hash of its bytes, so the same pixels are stored once and a stroke only adds the tiles it
changed. Files stay as long as the history may need them (undo puts old names back).

The `.uv` file is little-endian binary: `MQUV`, version (1), vertex count, index count (u32 each); then per vertex the
mesh vertex it came from (u32), its position in the object's space (3 × f32) and its uv (2 × f32, 0–1, v down); then the
triangles (u32 indices; triangle *t* is the mesh's triangle *t*). Placed models' surfaces are their parts as one mesh.

Two journal commands change paint: `setPaint` (`{"op": "setPaint", "id", "paint"}`, the whole paint or none) and
`paintTiles` (`{"op": "paintTiles", "id", "tiles": [{"layer", "tile", "file"}]}`, a stroke, a fill or a projected
picture; a missing `file` clears the tile).

Schema 8 only added the optional key and the two commands; files from schema 7 open unchanged, and Maquette 0.5
refuses schema 8.

## workspace.json

How the project shows when it opens. It isn't the project (it's never undone and isn't in the journal); it's
written moments after it changes and when the project closes. A missing file means the defaults; a damaged value
falls back to its default; unknown keys are ignored. Plain JSON, no envelope.

| Key | Type | Meaning |
|---|---|---|
| `schemaVersion` | number | 1. |
| `template` | string? | The starter template it began from: `blank`, `print`, `room`, `character`, `animation`. |
| `timeline` | string | `hidden` (the default), `transport` (the slim transport) or `full`. |
| `timelineHeight` | number | The whole timeline's height in points, 150–900 (260 by default). |
| `snap` | object | `grid`, `gridSize` (m), `rotation`, `rotationStep` (degrees), `ground`, `objects`, `objectThreshold` (m), and since 0.4 `corners`, `edges`, `faces` (points snap to corners and edge middles, edges, faces; on when missing). |
| `showsGrid` | bool | The grid on the ground. |
| `shapeSize` | number | New shapes' size in metres (1; `print` uses 0.05). |
| `firstPanel` | string? | A tool panel to open the first time the project opens (then removed): `model`, `cast`. |
| `units` | string | The unit lengths are shown and typed in: `mm`, `cm` (the default), `m`, `in`, `ft`. `print` uses `mm`, `room` `m`. |
| `printBed` | string? | The 3D printer whose build volume the stage outlines (`PrintBed.presets`: `filament-220`, `filament-256`, `filament-180`, `prusa-mk4`, `bambu-x1`, `bambu-a1-mini`, `ender-3-v3`, `resin-218`, `form-4`); `print` starts with `filament-220`. An unknown id is dropped. |
| `section` | object? | The section view: `{"normal": [x, y, z], "offset": d}`; what's beyond the plane (`normal · p > offset`) is cut away on the stage. Missing: off. |
| `showsDimensions` | bool | Kept dimensions show on the stage (true). |
| `frameGuide` | object? | Since 0.5: the drawing guide over the frame for flipbooks. `kind` (`grid`, `isometric`, `perspective`, `symmetry`), `assisted`, `spacing` (frame heights), `origin` (`{"x","y"}`, frame heights from the centre, y up), `angle` (degrees), `vanishingPoints` (1–3, same units), `symmetry` (`vertical`, `horizontal`, `quadrant`, `radial`), `segments`, `mirrorRadial`. Missing: off. |
| `planeGuide` | object? | Since 0.5: the same, laid on the guide plane for ink (`grid`, `isometric`, `symmetry`; `spacing` in metres). Missing: off. |

## gallery.json (in the projects folder)

Home's arrangement, beside the packages (it moves with them to iCloud Drive). Plain JSON, dates in ISO 8601.

```json
{"schemaVersion": 1, "sort": "recent", "stacks": [{"id": "…", "name": "Rooms", "members": ["<project id>", "…"], "created": "2026-10-05T10:00:00Z"}]}
```

`sort` is `recent`, `name` or `created`. A project id that no longer exists is dropped; a stack left empty goes.

## Sharing

**Share as one file** writes a `.maquettepack`: a stored (uncompressed) zip of the package, with the library models
the project uses copied into `assets/`. 3D-lowey's `.loweypack` files import the same way.
