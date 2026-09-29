# Manim renders and media

Pictures and videos stand in the world as **cards**: a thin framed slab, one metre tall at scale 1, facing the camera
where it was added. Move, turn, size and key them like any object; the camera can walk around them and a character can
stand in front of one (a photo on a stand, a screen on the set). Transparent Manim renders go **over the frame** as
overlays instead (graphics floating over the 3D world). Videos play from a time on the timeline, hold their last frame
when they end (or loop), and export frame-exact, on cards and overlays alike.

## Tools

- `render_manim(script, scene, at, quality="high", transparent=True)`: renders a Manim scene on the laptop with a
  transparent background and drops it into the shot from `at` seconds. Graphs, equations and diagrams then float over
  the 3D world.
- `add_media(path, at, overlay=False)`: any picture or video file from the laptop (a screenshot, a chart, a clip) as a
  card in the world; `overlay=True` lays it flat over the frame. Move the card with a script afterwards (`set_property`
  position / rotation / scale on the name it returns): put it beside the character, angled a little towards the camera.
- CLI equivalents: `lowey-link manim scene.py Graph --at 3`, `lowey-link media chart.png` (`--overlay` for the frame).

`at` is seconds; get it from the transcript word (`get_transcript` → the word's start, minus 0.1–0.2 s).

## Writing the Manim scene (board style, from the video-explainer skill)

- **Nothing floats, nothing leaves the frame, nothing unreadable.** Build each element relative to the last; keep a
  margin; split long expressions over two lines instead of shrinking them.
- **Only what is being said.** A formula appears while the voice says it (Write/Create timed to the words), never as a
  decoration in a corner.
- **The board holds what's still live.** FadeOut what the narration is done with; keep what it will point at.
- **Transparent background:** don't draw a background rectangle; use light strokes (white/yellow on the 3D scene's
  dark areas, or the project's palette colours) so it reads over the world.
- **Size for the frame it will sit in:** a lower-third graph is small; a full explanation fills the middle. The overlay
  is scaled in the app; render at quality "high" (1080p) and 30 fps.
- Keep each render short (3–12 s) and aligned to one idea; several short renders beat one long one.

Example scene:
```python
from manim import *

class Gravity(Scene):
    def construct(self):
        ax = Axes(x_range=[0, 3, 1], y_range=[0, 45, 15], x_length=6, y_length=3.6, tips=False)
        curve = ax.plot(lambda t: 4.9 * t * t, color=YELLOW)
        label = MathTex(r"d = \tfrac{1}{2} g t^2").next_to(ax, UP)
        self.play(Create(ax), run_time=0.6)
        self.play(Create(curve), Write(label), run_time=1.4)
        self.wait(1)
```
Then: `render_manim("gravity.py", "Gravity", at=7.2)` and position the overlay in the frame with a small script
(`{"do": "set", "target": "Gravity", ...}`) or let Hesham drag it.

## Pairing Manim with the 3D shot

- A character points or looks at the graph (see `characters.md`, `animation.md`).
- Punch in or snap zoom on the moment the curve lands.
- For "3D maths" (a surface, vectors in space) prefer building it in the scene (shapes, drawings, 3D text) so it
  lives in the world and the camera can move around it; use Manim for 2D boards.
