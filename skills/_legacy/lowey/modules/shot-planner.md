# Shot planner (3D-lowey)

Goal: a finished, synced shot in ONE `run_script` call. Hesham approves it on the iPad, then edits by hand.

## 1. Look (small reads)
- `get_transcript` → find the line's words and times.
- `get_scene` → what already exists (reuse, don't duplicate; names matter).
- `list_assets("<thing>")` only for things you need.

## 2. Write the script (actions — see `actions_reference` once)
Order: look → build → camera + cut → animation on words → overlays/effects → captions/lipSync.
- Name every object you create; later actions refer to names.
- Times are words: `{"word": "Nobody"}`, `{"word": "could", "edge": "end"}`, `"offset": -0.15` to anticipate.
- Colours: `"palette:N"` (the project's palette). Glow for light sources (`"glow": 3`).
- Stand things on the ground (y = 0) unless they sit on something (give "at" a height).
- Sizes in metres: a desk ~1.6×0.75×0.8, a person ~1.7 tall, a room ~8×3×8.
- Camera: `camera` (from, lookAt, 35–50 mm) → `cut` at the line's first word → one `cameraMove` on the beat word.
- Presets over raw keys: popIn for appearances, grow for "bigger and bigger", typewriter for text/arrows, stagger for crowds (`"stagger": 0.06, "order": "wave"`).
- Overlays for statements (big X, question mark, a title) — frame space [x, y] in −1…1.

## 3. Check
`snapshot(time=…)` at the beat words. If something's off, send a small fix script (one more approval) — don't rebuild.

## 4. Report (3 lines max)
What's there, which words it's synced to, what Hesham might want to tweak by hand.

## Example
```json
{"title": "Nobody could", "actions": [
 {"do": "overlay", "shape": "cross", "name": "Big X", "at": [0, 0], "size": 1.8},
 {"do": "preset", "target": "Big X", "preset": "popIn", "at": {"word": "Nobody"}, "duration": 0.35},
 {"do": "effect", "kind": "shake", "at": {"word": "Nobody"}, "duration": 0.4},
 {"do": "preset", "target": "Person*", "preset": "shrink", "at": {"word": "could"}, "stagger": 0.03, "order": "wave"}
]}
```
