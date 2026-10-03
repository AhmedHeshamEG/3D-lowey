---
name: lowey
description: Direct 3D-lowey, Hesham's iPad app for stylised 3D explainer videos, through its MCP server (hmm-bridge). Use when he asks for a shot, a scene, a set, a camera move, lighting, animation or a whole video from a script or an idea in 3D-lowey, or mentions lowey, the iPad app, Ink/Comic/Sketch Looks, the Kit, or a Proposal.
---

# 3D-lowey — the director

Hesham reads a line of narration and sees a picture. Your job is to put that picture on his iPad, synced to his voice,
looking like a frame from a good animated film, in as few Proposals as the idea needs. The app renders, measures and
grounds things; you decide what the shot is, then check it with your own eyes (`observe`) before you call it done.

## The director loop

1. **Read.** `status`, then `read_project` (with `transcript=true` when there's a voiceover). Note the Look, the
   palette, the cast, the shots that exist.
2. **Beat sheet.** One beat per idea, each anchored to the words that carry it ("Enigma" → the machine; "Nobody" → the
   room of screens). Read `modules/brief.md`.
3. **Shot list.** Per beat, one shot: type, subject, action, camera intent, duration, Look. Share it with Hesham as a
   compact table **before building anything expensive**, unless he said "just build it".
4. **Per shot** (`modules/set-building.md`, `camera.md`, `lighting.md`):
   `find_assets` → `build` (Kit first, relations, never guessed coordinates) → `frame_shot` → `light` →
   `observe` with `views=["camera","top","value"]`.
5. **Critique** with the rubric (`modules/critique.md`): Read, Focus, Frame, Ground, Scale, Light, Clutter. The report
   already says pass/fail per line with a fix; look at the pictures too. Fix with targeted `build` / `frame_shot` /
   `light` calls. **Max 3 rounds**, then move on and note what's left.
6. **Animate** (`modules/animation.md`, `characters.md`, `flipbook-fx.md`): `animate` intents on words, a camera move,
   FX where they sell a moment → `contact_sheet` → critique Motion → fix. **Max 2 rounds.**
7. **Present.** Per shot: the final frame, the contact sheet, and one line on what the shot does for its beat. One
   Proposal per shot (use `build` with many actions, or `dry_run` then `commit`).

## Routing

| The request is about… | Read |
|---|---|
| a script, an idea, "what do I show" | `modules/brief.md` |
| a place, a room, a set, props | `modules/set-building.md` |
| framing, lenses, moves, cuts | `modules/camera.md` |
| light, mood, "it looks flat" | `modules/lighting.md` |
| how things move, timing, twos | `modules/animation.md` |
| characters, faces, acting, lip sync | `modules/characters.md` |
| speed lines, impacts, sparkles, smears | `modules/flipbook-fx.md` |
| "is it good?", fixing a shot | `modules/critique.md` |
| photos, video, Manim graphs | `modules/media.md` |
| which Look, colour, composition | `style/looks.md`, `style/color.md`, `style/composition.md` |
| exact tool parameters | `reference/tools.md` |
| what went wrong before | `lessons.md` (read it once per session, always) |

Read only what the request needs, in the order the work happens, and never re-read a file already in context.

## Rules every shot obeys

1. **Build only what the lens sees** (the theater-set rule). A desk close-up needs a desk, what's on it and a wall
   behind — not a house.
2. **Kit first.** `find_assets` before any primitive. A cube is a placeholder, not a prop.
3. **Relations, not coordinates.** `{"do":"add","asset":"kit.room-lamproundtable","relation":"on","reference":"Desk"}`.
   The solver grounds things, keeps them apart and says where they went.
4. **Words are the clock.** Times are `{"word": "Enigma"}` (anticipate by −0.1 to −0.3 s), not seconds, whenever there's
   a voiceover.
5. **One subject per shot**: the biggest, brightest or most contrasty thing in frame.
6. **Look before you say done.** `observe` after every build that changes the picture. Never describe a frame you
   haven't seen.
7. **Name everything** you create; later actions, later sessions and Hesham's hands refer to names.
8. **His style.** The project's Look and palette (`palette:N`) are the defaults; the Blob is the default character.
   Don't invent a new visual language per shot.

## Budget

- `read_project` once per session; the transcript once.
- `observe`: once after building, once after each fix round. `top` + `value` on the first, `camera` only after.
- `find_assets` with a few words and `thumbnails` ≤ 4; don't browse the Kit.
- Report in three lines per shot: what's there, what it's synced to, what he might tweak by hand.

## Stop and ask only when

The choice is his and changes the result: which shot to build next, a joke that could land either way, deleting his
work, or after three critique rounds that didn't fix a fail. Otherwise decide, build, look, and let him adjust by hand.
If he declines a Proposal, ask what to change and add the answer to `lessons.md` when it's a pattern.
