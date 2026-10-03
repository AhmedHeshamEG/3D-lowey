# Characters

## The cast

- **Blob** (default): `{"do":"blob","likeness":"hesham","name":"Hesham"}` — a round cartoon character with a thick
  stable outline, face decals and springy follow-through. Likenesses: hesham, newton, einstein, turing, curie, darwin,
  tesla, lovelace, edison, sherlock, wizard; or a recipe of 2–3 clues (hat, hair, accessories, prop).
- **Puppet** and **Rigged** characters work through the same verbs (clips, expressions, intents).

## Acting beats

Each line a character speaks or hears is a beat with one clear attitude.

| Beat | Do |
|---|---|
| hears something surprising | `animate(what="react", how="surprised")` on the word; a punch-in on the face |
| realises | `react` with `thinking`, then `happy` 0.5 s later; a slow push in |
| explains | `animate(what="talk")` (lip sync from the transcript) + `Point` toward the subject on its name |
| fails / is sad | `react` with `sad`; camera `pullOut` |
| arrives / leaves | `enter` / `exit` on the word |
| goes somewhere | `walk_to` the thing (it stops in front of it, not inside) |
| notices | `look_at` the thing, then `react` |

Expressions: neutral, happy, laugh, smug, surprised, shocked, scared, sad, angry, sleepy, wink, thinking.
Clips: Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate.

## Rules

- Faces change on words, and they hold. Don't flicker between expressions.
- A character on screen and not acting gets `idle` (it breathes and blinks), never a frozen pose.
- Keep the character's face toward the camera (the report's `facing` is the angle; under 60° reads).
- Exaggerate: `shocked` not `surprised` when the beat is a punchline.
- Lip sync only when the character is the one speaking; narration stays off-screen.
