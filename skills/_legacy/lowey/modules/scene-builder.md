# Scene builder (3D-lowey)

Few decisions, big results (Townscaper / Tiny Glade): express the intent, let arrays and scatters fill details.

## Budget
- 1 read of `get_scene`, 1 `list_assets` per kind of thing, 1 `run_script`, 1–2 `snapshot`s. Don't dump the whole library.

## Composition rules
- Ground at y = 0. Everything stands on it or on something with a stated height.
- Big simple shapes: a room is a floor plane + 2–3 walls (cubes 0.2 thick), not 40 props.
- Repetition via `array` (rows of desks: `"count": 6, "step": [2, 0, 0]`) and `scatter` (forests, rocks: `"count": 30, "radius": 10`).
- Characters: `blob` actions (see `characters.md`); humanoid `character`s only for anonymous crowds.
- Light: one warm key (`light` point, `#FFB347`, glow on the lamp object) against the scene's mood. Night/dusk moods read best with one warm source.
- Palette: use `palette:N`; add colours with `look` only if Hesham asks.
- Keep it under ~60 objects unless it's a crowd (arrays/scatters count as one decision).

## After building
`snapshot` from the shot camera (or add a camera first). Look for: floating things, things inside each other, empty frame, flat light.
Fix with a small follow-up script (move/scale/delete by name).

## Hand-off
List the names you created so Hesham (and later scripts) can refer to them.
