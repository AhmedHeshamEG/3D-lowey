# Animation

The app does the in-betweens; you choose **poses, timing and where it lands**. Say the intent with `animate`
(enter, exit, emphasise, react, walk_to, look_at, talk, idle); reach for presets, clips and keys only when the intent
vocabulary doesn't say it.

## Timing and spacing

- Fast (0.15–0.3 s) is funny and punchy; slow (1–2 s) is heavy or thoughtful.
- Ease in and out (the default). Linear motion only for machines and constant things (a conveyor, a clock hand).
- **Holds**: after every hit hold the pose 0.3–0.8 s so it reads. Constant motion reads as nothing.
- **Anticipation**: before a big move a small opposite one (a squash before a jump; a pull back before a throw), 3–5
  frames. Big moves without it feel weightless.
- **Arcs**: living things move in arcs, not ruler lines. `walk_to` arcs for you; for keys, add a middle key off the line.
- **Overlap and follow-through**: hats, hair and the Blob's springs follow through by themselves; add a `wiggle` on a
  prop when it lands.

## Ones, twos, fours

- On ones (24 fps): smooth, cinematic, the Ink Look.
- On twos: the Comic Look's snap; action beats; hand-drawn feel. `animate(..., frame_rate="twos")` per object, or the
  Look's stepping for the scene.
- On fours: deliberate limited animation (a held pose that jumps); rare.
- Mixed rates are a style: the character on twos, the camera on ones.

## Syncing to words

- Peaks land **on** the word: the pop-in's overshoot, the punch-in's stop, the impact frame.
- Anticipate by −0.1 to −0.3 s so the motion *arrives* on the word.
- The contact sheet counts moves landing within 0.25 s of a word; a third or more should.

## Check with `contact_sheet`

Fix what the Motion line flags: ruler-straight paths (add an arc), no holds (insert a hold after the hit), a glide at
one speed (ease it, or break it into a move and a settle), moves off the words (retime to `{"word": …}`).
