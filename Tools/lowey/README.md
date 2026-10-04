# hmm-bridge — the laptop side of 3D-lowey

One Python package (Python 3.10+, the official MCP Python SDK 2.x), one command:

- **`hmm-bridge mcp`** — the `lowey` MCP server. Claude (Claude Code, Claude Desktop) or any MCP client directs the iPad
  through it.
- **`hmm-bridge pair | status | push | audio | media | manim | script | observe | pull | watch | generate`** — pairing,
  sending models, audio and media to the iPad, Scene Scripts, saving what a shot looks like, downloading renders.

The 1.x names, `lowey-mcp` and `lowey-link`, still work.

```powershell
pip install "git+https://github.com/AhmedHeshamEG/3D-lowey#subdirectory=Tools/lowey"
# or, from a checkout:  cd Tools/lowey; pip install -e .
# On the iPad: Actions ▸ AI & laptop (⇧⌘B) ▸ turn the bridge on ▸ Pair a laptop. It shows a one-time 6-digit code.
hmm-bridge pair 123456                 # finds the iPad on your Wi-Fi by itself (Bonjour) and keeps a token
hmm-bridge pair 192.168.1.20 123456    # ...or say where it is
hmm-bridge status
```

`'hmm-bridge' is not recognized` means the package isn't installed yet (run the `pip install` above), or Python's
`Scripts` folder isn't on PATH: `python -m lowey_tools pair 123456` does the same thing.

## Claude Code / Claude Desktop

```powershell
claude mcp add lowey -- hmm-bridge mcp            # Claude Code
```
Claude Desktop (`claude_desktop_config.json`):
```json
{ "mcpServers": { "lowey": { "command": "hmm-bridge", "args": ["mcp"] } } }
```
### Over HTTP on this laptop

```powershell
hmm-bridge mcp --http   # http://127.0.0.1:8765/mcp  → claude mcp add --transport http lowey http://127.0.0.1:8765/mcp
```
There is no internet mode. The iPad's bridge answers only on the local network, only to laptops paired with a one-time
code (the iPad lists them and can revoke each one), and it is off until you turn it on. App Store builds ship without
the bridge (`LoweyAIBridge` off); sideloaded builds have it.

Then: *"Read the project and build the 'Nobody could' shot."* The iPad shows a Proposal with a preview thumbnail; tap
**Apply** (or turn on auto-apply in the bridge panel). Every Proposal is one undo step.

Copy `skills/lowey` into your Claude skills folder (`~/.claude/skills/lowey`): the director loop, the modules it routes
to, the rubric, and the tool reference generated from this server.

### The 16 tools (MCP v2)

| # | Tool | What it does |
|---|---|---|
| 1 | `status` | paired iPad, project, scene, shot, playhead, auto-apply |
| 2 | `read_project` | scenes, shots (and the words they cut on), cast, Look, palette, Kit Sets, transcript |
| 3 | `find_assets` | Kit and library search: ids, real sizes, surfaces, fronts, thumbnails |
| 4 | `build` | Scene Script v3: one batch = one Proposal = one undo step; replies with an observe of the result; `dry_run` |
| 5 | `frame_shot` | the camera solver: shot type, composition, lens; cuts on a word |
| 6 | `light` | lighting recipes: key-warm-world-cool, noir-single-source, golden-rim, monitor-glow, moonlit, studio-soft |
| 7 | `set_look` | Ink, Comic, Sketch, Clay, Low-poly; mood; per-object Looks |
| 8 | `animate` | intents (enter, exit, emphasise, react, walk_to, look_at, talk, idle), presets or clips; frame rate |
| 9 | `camera_move` | push in, pull out, punch in, orbit, crane… eased, landing on a word |
| 10 | `add_overlay` | titles, labels, comic language; pops in on a word |
| 11 | `flipbook` | drawn FX: speed lines, impact burst, sweat drop, sparkle, smear |
| 12 | `add_media` | a picture or video from the laptop into the shot (card or overlay) |
| 13 | `render_manim` | Manim on the laptop, transparent, laid over the shot |
| 14 | `observe` | the shot with set-of-marks, top/front/side diagrams, value, silhouette, and the ShotReport + rubric |
| 15 | `contact_sheet` | N frames with notes and motion stats (arcs, holds, speed, words) |
| 16 | `commit` | commit a dry run's proposal, or undo N steps |

Resources: `lowey://project`, `lowey://transcript`, `lowey://actions`. Prompt: `direct` (the director loop).

## Any other model

No MCP? Any model can write a **Scene Script v3** (JSON, see `schemas/scene-script.v3.schema.json` and `GET /v2/actions`).
Paste it on the iPad (⌥⌘V, or Actions ▸ *Paste script*) or send it: `hmm-bridge script shot.json` (`--dry-run` previews).

## Laptop → iPad

```powershell
hmm-bridge push fox.glb house.usdz          # into the iPad's library
hmm-bridge audio enigma-voiceover.m4a       # onto the open scene's timeline
hmm-bridge media chart.png clip.mov --at 3  # pictures / videos as cards standing in the shot (--overlay: over the frame)
hmm-bridge manim scene.py Graph --at 3      # a Manim scene, transparent, over the shot from 3 s
hmm-bridge observe --views camera top value # what the shot looks like → .\observe (PNGs + report.json)
hmm-bridge watch C:\Blender\exports          # push every new model automatically
hmm-bridge generate tree --seed 4 --kind round   # Blender generator → library
$env:LOWEY_TEXT_TO_3D = 'python C:\ai\txt2mesh.py --prompt {prompt} --out {out}'
hmm-bridge generate text "a low-poly red fox"    # your local text-to-3D → library
hmm-bridge pull --all                        # renders (videos, frames, .srt) → .\renders
```

Generators live in `lowey_tools/generators/blender_*.py`: a Blender Python script that takes `--out file.glb` plus its own options.
Add your own and run it with `hmm-bridge generate <name>`.

## Security
The bridge is off by default, answers only private/link-local addresses, and needs the pairing code. Tokens are stored in
`~/.lowey/config.json` on the laptop. "Forget all" on the iPad revokes every device.

## Tests
`pip install -e ".[test]" && pytest` — every tool runs against a fake iPad bridge (CI does this on every push); the
app's side of each endpoint is tested in `LoweyFeatures` (BridgeV2Tests).
