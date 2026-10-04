# Project format

A Maquette project is a folder package (it shows as one file in the Files app). This document is the public
surface of that package: power users, scripts and MCP clients may **read** any of it. **Writes go through the app**
(the laptop bridge), so undo and the history journal stay true; a file changed behind the app's back is overwritten at
the next checkpoint.

Format version: package **2**, document schema **4** (`LoweySchema.currentVersion`), journal **1**.

```
My film.maquette/                 (3D-lowey's .lowey packages open too, and are upgraded in place)
  manifest.json                   which app wrote it, what it is, its package version
  project.json                    the project: name, scene list, the project Look
  scenes/<scene-id>.json          one scene each: objects, hierarchy, camera, timeline
  history/<scene-id>/             that scene's history journal (below)
  assets/                         library models the project carries (written by "Share as one file")
  audio/                          voiceovers and sounds
  renders/                        exports kept with the project
  thumbnail.png, thumbnail-loop.gif   the Home card
```

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
{"schemaVersion": 4, "kind": "project", "payload": { … }}
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

## scenes/<scene-id>.json (`kind: "scene"`)

| Key | Type | Meaning |
|---|---|---|
| `id`, `name` | string | |
| `objects` | {id: object} | Every object by id: `id`, `name`, `kind` (what it is: primitive, model, light, camera, text, drawing, character…), `parent`, `children`, `properties` (typed values: `position`, `rotation`, `scale`, `color`, `visible`, …), and `shadowPaint` when painted. |
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

## Sharing

**Share as one file** writes a `.maquettepack`: a stored (uncompressed) zip of the package, with the library models
the project uses copied into `assets/`. 3D-lowey's `.loweypack` files import the same way.
