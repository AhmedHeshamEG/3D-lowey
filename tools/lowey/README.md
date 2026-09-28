# lowey-tools — the laptop side of 3D-lowey

Two commands, one Python package (Python 3.10+, the official MCP Python SDK 2.x — chosen because the laptop already runs
Python for Blender scripts, and FastMCP/MCPServer makes each tool a plain function):

- **`lowey-mcp`** — an MCP server. Claude (Claude Code, Claude Desktop) or any MCP client drives the iPad through it.
- **`lowey-link`** — pairing, sending models/audio to the iPad, downloading renders, running generators.

```powershell
cd tools/lowey
pip install -e .
# On the iPad: scene menu → "AI & laptop bridge…" → Bridge on. It shows the address and a 6-digit code.
lowey-link pair 192.168.1.20 123456
lowey-link status
```

## Claude Code / Claude Desktop

```powershell
claude mcp add lowey -- lowey-mcp                 # Claude Code
```
Claude Desktop (`claude_desktop_config.json`):
```json
{ "mcpServers": { "lowey": { "command": "lowey-mcp" } } }
```
Then: *"Read lowey://transcript and build the 'Nobody could' shot."* The iPad shows a preview; tap **Apply** (or turn on
auto-apply in the bridge panel). Every change is one undo step.

Copy `skills/lowey` into your Claude skills folder (`~/.claude/skills/lowey`): one orchestrator (`SKILL.md`, the brain
that routes) and short modules (script breakdown, shots, sets, camera, characters, cartoon animation, Manim & media,
style, troubleshooting) plus the action reference. Add a module to teach it something new; edit one to change a habit.

### Tools
`get_scene`, `list_assets`, `get_transcript`, `actions_reference`, `snapshot`, `run_script` (many actions, one approval),
`create_object`, `place_asset`, `set_property`, `add_keyframes`, `apply_preset`, `camera_move`, `set_look`, `add_overlay`,
`attach_to_word`, `add_media` (a picture/video into the shot), `render_manim` (a Manim scene, transparent, into the shot), `undo`.
Resources: `lowey://scene`, `lowey://look`, `lowey://assets`, `lowey://transcript`.
Prompts: `breakdown_script`, `plan_shots`, `build_scene`, `direct_camera`, `sync_to_voiceover`.

## Any other model

No MCP? Any model can write a **Scene Script** (JSON, see `/schemas/scene-script.schema.json` and `GET /v1/actions`).
Paste it on the iPad (scene menu → *Paste a Scene Script*) or send it: `lowey-link script shot.json`.

## Laptop → iPad

```powershell
lowey-link push fox.glb house.usdz          # into the iPad's library
lowey-link audio enigma-voiceover.m4a       # onto the open scene's timeline
lowey-link watch C:\Blender\exports          # push every new model automatically
lowey-link generate tree --seed 4 --kind round   # Blender generator → library
$env:LOWEY_TEXT_TO_3D = 'python C:\ai\txt2mesh.py --prompt {prompt} --out {out}'
lowey-link generate text "a low-poly red fox"    # your local text-to-3D → library
lowey-link pull --all                        # renders (videos, frames, .srt) → .\renders
```

Generators live in `lowey_tools/generators/blender_*.py`: a Blender Python script that takes `--out file.glb` plus its own options.
Add your own and run it with `lowey-link generate <name>`.

## Security
The bridge is off by default, answers only private/link-local addresses, and needs the pairing code. Tokens are stored in
`~/.lowey/config.json` on the laptop. "Forget all" on the iPad revokes every device.

## Tests
`pip install -e ".[test]" && pytest` — runs against a fake iPad bridge (CI does this on every push).
