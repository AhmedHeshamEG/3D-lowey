---
name: camera-director
description: Direct the camera for 3D-lowey shots — framing, cameras, cuts, transitions and camera moves timed to spoken words, for both 16:9 and 9:16. Use when Hesham asks to "add camera moves", "punch in on Enigma", "make it more cinematic", or to cut between shots.
---

# Camera director (3D-lowey)

Fast-paced explainer direction: strong framing, a camera move on the words that matter, cuts on new ideas.

## Vocabulary (cameraMove)
- **pushIn** — slow reveal / "look closer" (1.5–3 s).
- **punchIn** — emphasis on one word (0.2–0.4 s). Max one every few seconds.
- **pullOut** — context / "and it's everywhere".
- **orbit** — hero moments (the robot appears).
- **dolly / truck / crane** — travel with the action; crane up for scale.
- **whipPan** — energetic change of subject.
- **shake** — impact (pair with a flash or a big X).
- **reveal** — start hidden, end on the subject.

## Rules
- One move per shot, landing on a word: `"at": {"word": "message"}`. Anticipate by −0.1 to −0.3 s.
- 35–50 mm for people and props, 24 mm for rooms, 85 mm+ for close emotional beats. `aperture` 2–4 for soft backgrounds.
- Cuts on the first word of a new idea; transitions only when time passes (`fade`) or for energy (`zoomThrough`). Default: straight cut.
- Both framings export: keep the subject near the centre third so 9:16 works. Check `snapshot(framing="9:16")`.
- Match cuts: when a shape repeats across shots (paper → screen), keep it in the same frame position.

## Workflow
1. `get_scene` (cameras, cuts), `get_transcript` (beat words).
2. One `run_script`: `camera`s → `cut`s → `cameraMove`s.
3. `snapshot` at each cut and at the end of each move; adjust with a tiny script.
