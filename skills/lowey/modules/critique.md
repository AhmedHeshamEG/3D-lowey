# Critique — the rubric and its fixes

`observe` returns a ShotReport whose `checks` already grade each line (pass / fail / skipped) with a fix; `contact_sheet`
grades Motion. Look at the pictures as well: the numbers find problems, the eye finds what they mean. A shot is done
when nothing fails, or after 3 rounds (note what's left in your report to Hesham).

| Line | Passes when | Fix recipes |
|---|---|---|
| **Read** | subject vs background ΔL* ≥ 25 in the value view | darken the world (mood, fog, a darker wall swatch) or light the subject (`light key-warm-world-cool`, intensity up); change one palette slot |
| **Focus** | exactly one subject, and it's the biggest, brightest or most contrasty element (or the accent) | move closer or a longer lens (`frame_shot` closeUp/insert); push the rival back, darker or out of frame; light the subject |
| **Frame** | subject on a third or deliberately centred; headroom sane; no tangents; nothing important cut | `frame_shot` with leftThird/rightThird/center; nudge so edges clear the border (tangents); level the camera; a wider type if the subject is cut |
| **Ground** | nothing floats (gap < 1 cm) unless airborne on purpose; no intersections | `place … on` what it stands on (the solver grounds it); `place … beside_*` to move it apart; mark deliberate fliers `airborne` |
| **Scale** | Kit models within ½–2× their real size | `scaleTo` the real size (`find_assets` has it), or a model made at that size |
| **Light** | key on the subject; the world cooler or darker; the silhouette separates | `light` with a recipe; a rim (golden-rim, moonlit); darken the mood |
| **Clutter** | ≤ 7 significant elements (copies count once) | remove what doesn't serve the beat; push things out of frame; let empty space frame the subject |
| **Motion** | arcs not lines; holds exist; eased moves; no constant-speed orbits; peaks on words | a middle key off the line; a hold after each hit; ease in/out; retime to `{"word": …}`; anticipation before big moves (not measured: check it yourself) |

## How to read the pictures

- **camera**: the shot with numbered marks; the report's objects use the same numbers.
- **top / front / side**: orthographic layout with the shot camera's wedge — is everything where you think? Is the
  camera on the right side of the action? Are things the right size relative to each other?
- **value**: squint — the subject must pop as a shape.
- **silhouette**: the subject black on white — can you tell what it is and what it's doing?

## Order of fixes

Ground and Scale first (they're bugs), then Focus and Frame (the camera), then Read and Light (values), then Clutter,
then Motion. One `build` per round that fixes everything you can in it.
