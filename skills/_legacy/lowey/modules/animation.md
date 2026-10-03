# Cartoon animation (how things should move)

The reference is Looney Tunes and Adobe Character Animator: poses that snap, overshoot and settle; exaggeration over
realism; timing that lands on the words. The rig does the in-betweens: **your job is poses and timing.**

## The principles you actually use here

- **Pose to pose.** Key the extremes (the expression, where the hand ends up), not the path. Step-like changes are
  fine: the springs make them bounce.
- **Anticipation.** Before a big action, a small opposite one: a quick `squash` −0.4 for 0.1 s before a shocked
  stretch, a hand pulling back before a throw. 3–5 frames.
- **Overshoot & settle.** Built into blob faces and hands. For objects, use presets that overshoot (`popIn`,
  `bounce`, easing `backOut`/`elastic`).
- **Squash & stretch.** The `squash` channel (−1…1) on a blob's root squashes/stretches the head from the neck;
  surprised/shocked expressions do it for you. Keep volume: never squash and shrink at once.
- **Holds.** After a hit, hold the pose 0.3–0.8 s so the viewer reads it. Constant motion reads as nothing.
- **Exaggeration.** If a reaction is worth showing, make it big: `shocked` not `surprised`, a punch-in on the face.
- **Secondary motion.** Hats and hair follow through by themselves; add a `wiggle` on a prop when it lands.
- **Timing = meaning.** Fast (0.15–0.3 s) is funny and punchy; slow (1–2 s) is heavy or thoughtful.

## Recipes

- **Wave:** key `Me/Hand R` position up and out at the word, then 3 small left-right keys 0.15 s apart, then down.
- **Point at something:** hand toward the object at the word before its name; `thinking` or `smug` face.
- **Double take:** look away (`lookX` keys 0 → 0.6), 0.4 s later snap back (`lookX` 0) with `shocked` and a
  `snapZoom` on the face.
- **Jump for joy:** root up 0.4 m with `backOut` easing, `laugh` expression, squash −0.3 on the landing.
- **Sad shrink:** `sad` expression, root scale 0.9 over 1 s, camera `pullOut`.

## Don'ts

- Don't key face channels by hand (brows, eyeWide…) when an expression says it.
- Don't animate everything at once; one focus per beat.
- Don't fill silence with motion; holds are part of the joke.
