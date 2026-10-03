# Lighting (toon)

Toon lighting is about **value structure**: the subject reads against the world in a squint. Three values — light,
middle, dark — and the subject owns the contrast. `light` places a recipe relative to the shot camera, so "key from
camera left" means the same in every shot. Re-lighting replaces the recipe's lamps.

## Recipes and their reasons

| Recipe | When | What it does |
|---|---|---|
| `key-warm-world-cool` | the default story light | warm key on the subject from camera-left-front; the world cool and dimmer |
| `noir-single-source` | mystery, secrets, night | one hard lamp high to the side; deep shadow everywhere else |
| `golden-rim` | warmth, endings, hope, outdoors | low sun behind the subject outlines it in gold; soft warm fill |
| `monitor-glow` | someone at a screen at night | cold glow from below-front; the room near black |
| `moonlit` | calm or eerie night exteriors | blue, soft, from behind-right with a cool rim |
| `studio-soft` | explainers, clean object shots | even soft light from front-left, little shadow |

Overrides: `intensity` (×), `warmth` (−1 cooler … 1 warmer).

## Check with `observe(views=["value"])`

- The **value** view must show the subject as the strongest light–dark contrast (ΔL* ≥ 25: the Read check).
- The **Light** check: the subject brighter than the world; not drowned in shadow; the silhouette separated (≥ 50% of
  its outline stands out). A rim (golden-rim, moonlit) fixes a merging silhouette.

## Fixes

- Subject merges with the background → darken the world (mood `night`/`dusk`, fog, a darker wall swatch) or light the
  subject (`key-warm-world-cool`, intensity 1.3).
- Everything the same brightness → a recipe with a single source; turn the sun down (noir, monitor-glow).
- Glow everywhere → glow belongs to one thing (a screen, the accent); remove the rest.
