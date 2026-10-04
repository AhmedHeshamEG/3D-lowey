# Camera

## Shot types (frame_shot) and when

| Type | Use it for | Lens it picks |
|---|---|---|
| extremeWide | where we are; scale | 18 mm |
| wide | the set and who's in it | 24 mm |
| full | a whole character acting | 35 mm |
| medium | most explainer beats: subject and its context | 50 mm |
| closeUp | emotion, a face, a key object | 85 mm |
| extremeCloseUp | the one detail that matters (a dial, an eye) | 100 mm |
| overTheShoulder | a conversation, someone looking at something | 50 mm |
| twoShot | two characters together | 35 mm |
| insert | an object the story turns on | 65 mm |

Compositions: `leftThird` / `rightThird` (default for anything that looks or moves: leave room in front of it),
`center` (symmetry, confrontation, a reveal), `lowAngle` (power, scale), `highAngle` (smallness, overview).

## Lenses, with reasons

- Wider than 24 mm distorts faces; use it for rooms and landscapes.
- 35–50 mm feels like being there: the default.
- 85 mm+ compresses and isolates: emotion and detail. Background falls away.
- Change lens to change feeling, not to fix framing; move the camera to fix framing.

## Moves (camera_move), each with a motivation

- **pushIn** — attention gathers: a realisation, a reveal (1.5–3 s, eased).
- **punchIn** — one word of emphasis (0.2–0.4 s). Rare.
- **snapZoom** — the explainer snap: rush, overshoot, settle (0.35–0.5 s), for punchlines.
- **pullOut** — context: "and it's everywhere".
- **orbit** — a hero moment. Never a constant-speed orbit with nothing else happening.
- **crane** — scale, an opening.
- **dolly / truck** — travel with the action.
- **whipPan** — energy between subjects. **shake** — impact (with an FX).

One move per shot, landing on its word. Holds between moves. The contact sheet flags constant-speed moves.

## Cuts

Cut on the first word of a new idea (`frame_shot ... on_word`). Straight cuts by default; `dipToBlack` when time passes.
Match shapes across a cut when you can (paper → screen in the same frame position).

## 9:16

`observe(framing="9:16")` when the video is vertical; keep the subject inside the vertical safe zone (the report's
frame cut and tangent notes catch edges).
