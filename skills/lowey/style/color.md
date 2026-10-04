# Colour

Use the project palette (`palette:N`); `read_project` lists it. A palette is a decision already made — don't add new
colours per shot.

## Rules

- **60-30-10.** 60% a dominant world colour (the wall, the sky), 30% a secondary (the furniture, the ground), 10% the
  accent — on the subject.
- **One accent.** The most saturated or warmest colour belongs to the subject. Two accents is no accent. In the Sketch
  Look, `accent: true` on exactly one thing.
- **Hue-shifted shadows.** Shadows go cooler (toward blue/purple), lights warmer (toward yellow/orange) — the toon
  lighting does it when the recipe's world light is cool and the key warm. Don't darken by adding black.
- **Value structure in three.** Squint: light, middle, dark. The subject sits where its value contrasts most with what's
  behind it. The `value` view and the Read check (ΔL* ≥ 25) test this.
- **Saturation is attention.** Desaturate the world before saturating the subject further.

## The palette read

`observe` reports the frame's five dominant colours and their shares, and the saturation spread. If the accent isn't
among them, the subject is too small or too dull; if the top colour is the accent, there's too much of it.

## Fixes

- Subject lost → `recolor` it with the accent slot, or `recolor` the background darker.
- Everything saturated → move props to muted slots; keep one strong colour.
- Muddy frame → fewer colours; same-hue variations for the world.
