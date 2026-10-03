# Characters (the blob house style)

Every character is a **blob**: Hesham's own avatar turned into a system. An onion head with a painted-on face, a
floating drop body, rubber-hose arms with mitten hands, no legs (it hovers over a soft glow). Everyone looks like
they belong in the same world, like TheOdd1sOut or Primer.

## Adding one

```json
{"do": "blob", "likeness": "hesham", "name": "Me", "at": [0, 0, 0], "facing": 0}
{"do": "blob", "likeness": "Isaac Newton", "at": [1.8, 0, 0]}
{"do": "blob", "recipe": {"name": "Ada", "hair": "bob", "hairColor": "#2A1C16", "prop": "gear"}}
{"do": "blob", "likeness": "einstein", "recipe": {"prop": "book"}, "label": "ALBERT"}
```

- `likeness` knows: hesham (me), newton, einstein, turing, curie, darwin, tesla, lovelace, edison, sherlock, wizard.
  Full names and "sir/dr" work.
- `recipe` fields (any subset; they override the likeness): `name`, `skin`, `hat` (none, beret, topHat, cap, beanie,
  crown, wizard), `hatColor`, `hatLabel` (text on the hat), `mark` (none, pisces), `hair` (none, tuft, wild, curlyWig,
  parted, bun, spiky, bob), `hairColor`, `accessories` (glasses, roundGlasses, monocle, mustache, bigMustache, beard,
  bowTie, tie, scarf, headphones), `accessoryColor`, `prop` (none, apple, book, lightbulb, pencil, magnifier, flask,
  envelope, gear), `blush`, `hover`, `height`.
- `label` puts a name on the hat: the fastest identity clue when hair and props aren't enough.

## Making anyone recognisable (likeness recipes)

A cartoonist's rule: **2–3 clues, the strongest first.** Silhouette beats detail.
1. **Hair or hat** (the silhouette): Einstein's white cloud, Newton's curly wig, Lincoln's top hat.
2. **One accessory** at face level: glasses, a mustache, a beard, a bow tie.
3. **One prop** that says what they did: Newton's apple, Edison's bulb, Curie's glowing flask.
Plus colour: hair and accessory colours matter more than the skin. If it's still ambiguous, `label` their name on
the hat. Never more than three clues; a cluttered blob reads as nobody.

## Faces: expressions, not face keys

The blob face is a real cartoon face: eyes squeeze into happy crescents, pop wide, close into curved lines; brows
arch, angle angry or worried; one mouth morphs between every shape. It runs on springs: key a pose and the rig
**overshoots into it and settles** (Looney Tunes timing) with squash & stretch on the hit. So:

```json
{"do": "expression", "target": "Me", "name": "shocked", "at": {"word": "what"}, "offset": -0.1}
```

Expressions: neutral, happy, laugh, smug, surprised, shocked, scared, sad, angry, sleepy, wink, thinking.
- One expression per beat; hold it (don't key a new one every word). Return to `neutral` or `smug` between beats.
- Anticipate: key it 0.1–0.2 s before the word so the overshoot peaks on the word.
- The eyes blink on their own; don't key blinks.
- Lip sync (`{"do": "lipSync", "character": "Me"}`) drives the mouth from the transcript; expressions still drive
  eyes and brows on top, and a smile/frown still shapes the talking mouth.
- The root's `cartoon` property (0…1, default 0.8) is how rubbery the springs are: 0.4 for calm, 1 for zany.

## Moving them

- The body floats (a gentle bob) by itself. Move the whole blob by its root name.
- Hands are handles: move or key `"<Name>/Hand R"` and the arm follows (rubber hose). Waves, points and grabs are
  just a hand position (see `animation.md`).
- Walking: glide the root with `transform` or a `followPath`; they hover, so there are no feet to animate.

## Humanoids (only when asked)

`{"do": "character", "recipe": {...}}` builds a low-poly person on the Humanoid standard that plays clips (Walk, Talk,
Wave…). Use it for crowds of anonymous people; use blobs for anyone who speaks or reacts.
