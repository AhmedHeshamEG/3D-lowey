# The five Looks

A Look is the whole drawing style: line, shading, texture and frame rate. Set it per project, per scene (`set_look`),
or per object (`per_object`: one thing drawn differently on purpose).

| Look | Use it for | References, and why |
|---|---|---|
| **Ink** (house default) | stories, explainers, anything with characters | *Hilda* and Cartoon Saloon (clean confident lines, flat shapes, warm/cool light that does the storytelling); *Arcane*'s painted value control without its texture |
| **Comic** | action beats, punchlines, energy; on twos | *Spider-Verse* (stepped motion, bold shadows, halftone as texture not decoration); Franco-Belgian *ligne claire* for clarity of silhouettes |
| **Sketch** | memory, quiet moments, "the secret"; one accent colour | storyboard and pencil animatics (unfinished on purpose); *Klaus*'s restraint with colour — one accent tells you where to look |
| **Clay** | soft, playful, kids' and product explainers | Aardman (tactile, rounded, slight imperfection) — reads as handmade and friendly |
| **Low-poly** | tech, data, games, abstract explainers | faceted indie games (*Monument Valley*): geometry as the style, clean pastel value steps |

## Choosing

- One Look per scene; change it when the story changes register, and say why in the shot list.
- Comic wants twos; Sketch wants one accent (`set … accent: true` on the one thing) and stillness; Ink wants a
  warm/cool light split.
- Per-object Looks are a spotlight: a Sketch flashback object inside an Ink scene, a Comic impact object.

## Rejected (anime conventions we don't use)

- Speed-line backgrounds behind every action, sparkle eyes, sweat drops on every line: they flatten every beat into
  the same intensity. Our FX are rare punctuation.
- Glowing bloom on everything, lens flares, heavy chromatic aberration: they hide value structure.
- Big-eyed realism-adjacent faces: our characters are Blobs — graphic, readable at thumbnail size.
