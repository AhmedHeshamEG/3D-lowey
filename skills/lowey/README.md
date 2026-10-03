# The `lowey` skill

Teaches Claude to direct 3D-lowey through the `lowey` MCP server (`hmm-bridge mcp`): read the project, plan beats and
shots, build sets from the Kit by relation, frame, light, look at the result with `observe`, critique it against a
rubric, fix, animate, check the motion with `contact_sheet`, and hand Hesham one Proposal per shot.

## Install

```powershell
pip install "git+https://github.com/AhmedHeshamEG/3D-lowey#subdirectory=Tools/lowey"   # hmm-bridge
hmm-bridge pair 123456                                   # the code the iPad shows
claude mcp add lowey -- hmm-bridge mcp
Copy-Item -Recurse skills\lowey $HOME\.claude\skills\lowey
```

## What's in it

| Path | What |
|---|---|
| `SKILL.md` | the brain: when it triggers, the director loop, routing, rules, budget, when to stop |
| `modules/` | one job each: brief, set-building, camera, lighting, animation, characters, flipbook-fx, critique, media |
| `style/` | looks (the five Looks and why), color (60-30-10, one accent, value structure), composition |
| `reference/tools.md` | the 16 tools, **generated** from the MCP server by `Tools/gen-skill-tools.py` (CI checks it) |
| `lessons.md` | mistakes that became rules; grows with every declined Proposal that's a pattern |
| `evals/` | twelve briefs, the rubric, and `run_evals.py` |

## Evals

`python skills/lowey/evals/run_evals.py` runs the briefs against a paired iPad (or a simulator whose bridge the laptop
can reach) with the Claude API, each in a fresh scene, and scores the results from the app's own measurements
(`observe` at two moments and a contact sheet). Results land in `evals/runs/<date>/` (pictures, reports, every tool
call, `results.md`). It needs `ANTHROPIC_API_KEY` and auto-apply on the iPad (or someone tapping Apply). `--plan`
checks the bridge without calling the model; `--score <folder>` re-scores a saved run. The harness's scoring and
bookkeeping are tested in CI (`Tools/lowey/tests/test_evals.py`); the runs themselves need the iPad.

## Changing it

Add a module to teach something new and a row to the routing table in `SKILL.md`; edit one to change a habit. Keep
modules short — they go into the model's context. After changing the MCP server, run `python Tools/gen-skill-tools.py`.
The 1.x skill is archived in `skills/_legacy/lowey`.
