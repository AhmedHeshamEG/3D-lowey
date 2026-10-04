# Eval rubric

Each brief's result is scored from what the app measures, not from the model's own account:

- After the agent finishes, the harness calls `observe` (camera, top, value) at the middle of the timeline and at the
  shot's main beat, and `contact_sheet` over the whole timeline.
- Each rubric line from `critique.md` is **pass (1)**, **fail (0)** or **not measured** (left out of the score):
  Read, Focus, Frame, Ground, Scale, Light, Clutter (from observe) and Motion (from the contact sheet).
- **Score** = passes ÷ measured lines, per observe moment, averaged. A brief **passes** at ≥ 0.85 with no Ground or
  Scale fail (those are bugs, not taste).
- The harness also records the process: Proposals made, tool calls, `find_assets` before primitives (Kit first),
  whether `observe` was called before the agent said it was done, and the number of critique rounds.

| Column | Meaning |
|---|---|
| brief | the id from `briefs.md` |
| score | 0–1 as above |
| fails | rubric lines that failed (with the report's detail) |
| proposals | Proposals sent (one per shot is the target) |
| calls | tool calls |
| looked | observe/contact_sheet calls before finishing |
| result | pass / fail |

Hesham's own verdict on each run goes in `runs/<date>/verdicts.md` (one line per brief); disagreements between his
verdict and the score become lessons or rubric changes.
