# Set building — the theater-set rule

Build only what the lens sees, from the Kit, placed by relation, at real size.

## Order

1. **Decide the frame first** (shot type and where the camera is). Everything outside it doesn't exist.
2. `find_assets` for the 3–7 things the shot needs, by plain words ("desk", "desk lamp", "old radio", "bookcase").
   Use each result's `id` in `add`; its `size` is real metres, `surfaces` are the heights you can put things `on`.
3. One `build` with the hero piece first, then everything relative to it:

```json
[{"do":"add","asset":"kit.office-desk","name":"Desk","at":[0,0,0]},
 {"do":"add","asset":"kit.room-lamproundtable","name":"Lamp","relation":"on","reference":"Desk","offset":[-0.45,0,-0.1]},
 {"do":"add","asset":"kit.room-books","name":"Books","relation":"on","reference":"Desk","offset":[0.5,0,-0.1]},
 {"do":"add","asset":"kit.room-bookcaseopen","name":"Bookcase","relation":"beside_left","reference":"Desk"},
 {"do":"add","shape":"cube","name":"Wall","at":[0,0,-1.2],"size":[6,3,0.1],"color":"palette:1"}]
```

4. `observe` with `top`: the diagram shows where everything stands and where the camera looks from.

## Relations

`on` (top surface; picks a free spot; faces the reference's front) · `beside_left` / `beside_right` (as seen from the
reference's front) · `in_front_of` · `behind` · `above` (in the air on purpose) · `under` · `inside` · `facing` ·
`around` (radius) · `row` (spacing) · `grid` (columns, spacing) · `scatter_in` (seed) · `stack`.
`offset` nudges in the reference's frame: x right, y up, z toward its front.

## Scale

Kit models arrive at real size. `scaleTo` only when the story needs a different size ("the tree is 6 m") or a stand-in
must match a real object (an old radio standing in for an Enigma machine: `{"do":"scaleTo","target":"Enigma","meters":0.26}`).
The Scale check fails beyond half or double a model's real size.

## Walls, floors, skies

Big flat primitives in palette colours are fine for walls and floors (they're the set, not props). Hide the ground
(`look` / the project setting) inside rooms. Fog sells depth outdoors.

## Groups of things

A room of computers is one desk and one screen arrayed (`array`, `row`, `grid`), not twelve hand placements. Copies
read as one pattern; they don't count as clutter.

## Don't

- Don't build greybox sets from cubes when a Kit model exists.
- Don't fill the frame. ≤ 7 significant things; empty space frames the subject.
- Don't place by coordinates and hope: anything floating or sunk fails Ground.
