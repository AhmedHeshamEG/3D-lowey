# Script breakdown (3D-lowey)

Hesham reads a line and sees an image. Your job: write that image down so it can be built fast.

## Read first (cheap)
- `lowey://transcript` if a voiceover exists (word times), else the pasted script.
- `lowey://assets` (names only) — prefer what he already has.
- `lowey://look` — the project's palette and mood are the defaults. The blob characters are the house style; the project's look is the rest.

## Output: one table, nothing else
| # | Line (verbatim) | Image (one idea, concrete) | Subject | Build (4–8 things) | Beats (word → what happens) | Camera |

Rules
- One idea per shot. A visual metaphor beats a literal picture ("85 years" → a paper growing over a crowd of tiny people).
  Goofy is allowed and often best (a robot taking Alan Turing's brain).
- Name the beat words exactly as spoken: *"Nobody"* → big X pops. The app syncs to those words.
- Build list: library assets by their names first, blockout shapes second (cube, cylinder, cone…), characters as blobs ("Me", a likeness like "Newton").
- Camera: one move per shot (push in on a reveal, punch in on emphasis, orbit on a hero, cut on a new idea).
- Mood: warm light on the subject, cooler world around it — unless the project's look says otherwise.
- Keep shots 2–6 seconds; fast pacing, no dead air.

## Then
Offer: "Build shot N?" → use the `shot-planner.md` or `scene-builder.md` module (one `run_script` per shot).
Never build without Hesham saying which shot.
