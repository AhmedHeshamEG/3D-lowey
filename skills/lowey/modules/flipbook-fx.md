# Flipbook FX — drawn effects that sell a moment

Hand-drawn FX over the 3D world, anchored to an object (they follow it) and timed to words. They're punctuation:
one per beat at most, on the beat's peak.

| FX | Sells | Anchor | Time |
|---|---|---|---|
| `speedLines` | speed, a rush, a dash | the moving thing | during the move |
| `impactBurst` | a hit, a reveal, "Nobody!" | the thing hit | the impact word, ~0.4 s |
| `sweatDrop` | nerves, embarrassment | a character's head | the awkward pause |
| `sparkle` | something precious, magic, "secret" | the object | from its name until the cut |
| `smear` | a very fast move between two frames | the mover | the fast frames |

`flipbook(kind, anchor, on_word, until, color)`; `color` from the palette (white for impacts on dark scenes).

## When not to

- Not on every shot: FX lose meaning when they're everywhere.
- Not with a screen `flash` and a `shake` and an impact at once — pick one strong signal.
- Not in quiet beats (Sketch Look moments): stillness is the effect.

Comic Look on twos + an `impactBurst` on the word is the house action beat.
