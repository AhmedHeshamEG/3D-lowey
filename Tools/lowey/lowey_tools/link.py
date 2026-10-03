"""hmm-bridge — the laptop companion for 3D-lowey (the old name, lowey-link, still works).

  hmm-bridge pair 123456                   pair with the iPad (Actions ▸ AI & laptop ▸ Pair a laptop shows the one-time code)
  hmm-bridge pair 192.168.1.20 123456      ...and say where it is if Bonjour can't find it
  hmm-bridge mcp [--http]                  run the MCP server for Claude Code / Claude Desktop (stdio by default)
  hmm-bridge status                        what's open on the iPad
  hmm-bridge push model.glb tree.usdz      send files to the iPad's library
  hmm-bridge audio voiceover.m4a           add a voiceover to the open scene (--role music|sfx)
  hmm-bridge pull [--all] [name]           download renders (videos, frames, .srt) into ./renders
  hmm-bridge watch ./exports               push every new model that appears in a folder
  hmm-bridge generate tree --seed 3        run a laptop-side generator (Blender) and push the result
  hmm-bridge generate text "a red fox"     run your text-to-3D command (LOWEY_TEXT_TO_3D) and push the result
  hmm-bridge script shot.json              send a Scene Script v3 (a Proposal on the iPad; --dry-run previews)
  hmm-bridge observe [--views top value]   save what the shot looks like (pictures + report) into ./observe
  hmm-bridge media graph.png clip.mov --at 3   pictures / videos as cards in the shot (--overlay: flat over the frame)
  hmm-bridge manim scene.py Graph --at 3   render a Manim scene (transparent) and put it in the shot at 3 s
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

from .client import Bridge, BridgeError, describe_build, discover, load_config, normalize_host, save_config

MODEL_TYPES = {".glb", ".gltf", ".usdz", ".obj"}
GENERATORS = pathlib.Path(__file__).parent / "generators"


def find_blender() -> str | None:
    if os.environ.get("BLENDER"):
        return os.environ["BLENDER"]
    found = shutil.which("blender")
    if found:
        return found
    for base in [pathlib.Path("C:/Program Files/Blender Foundation"), pathlib.Path("/Applications/Blender.app/Contents/MacOS")]:
        if base.exists():
            candidates = sorted(base.rglob("blender.exe" if os.name == "nt" else "Blender"))
            if candidates:
                return str(candidates[-1])
    return None


def run_generator(name: str, args: list[str], out_dir: pathlib.Path) -> pathlib.Path:
    """Runs a generator and returns the file it made."""
    out_dir.mkdir(parents=True, exist_ok=True)
    if name == "text":
        template = os.environ.get("LOWEY_TEXT_TO_3D")
        if not template:
            raise SystemExit("Set LOWEY_TEXT_TO_3D to your text-to-3D command, e.g.\n"
                             '  LOWEY_TEXT_TO_3D="python run_model.py --prompt {prompt} --out {out}"')
        out = out_dir / "generated.glb"
        command = template.format(prompt=shlex.quote(" ".join(args)), out=shlex.quote(str(out)))
        subprocess.run(command, shell=True, check=True)
        return out
    script = GENERATORS / f"blender_{name}.py"
    if not script.exists():
        known = sorted(p.stem.removeprefix("blender_") for p in GENERATORS.glob("blender_*.py"))
        raise SystemExit(f"No generator '{name}'. Known: {', '.join(known)}, text")
    blender = find_blender()
    if not blender:
        raise SystemExit("Blender not found. Install it or set BLENDER=path/to/blender")
    out = out_dir / f"{name}.glb"
    subprocess.run([blender, "--background", "--factory-startup", "--python", str(script), "--", "--out", str(out), *args], check=True)
    return out


def save_observe(reply: dict, folder: pathlib.Path) -> None:
    """Writes each view as a PNG and the report as JSON."""
    import base64

    folder.mkdir(parents=True, exist_ok=True)
    for view, data in (reply.get("images") or {}).items():
        (folder / f"{view}.png").write_bytes(base64.b64decode(data))
    (folder / "report.json").write_text(json.dumps(reply.get("report", {}), indent=2, ensure_ascii=False), encoding="utf-8")
    print(reply.get("summary", ""))
    print(f"→ {folder}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="hmm-bridge", description="Laptop companion for 3D-lowey")
    sub = parser.add_subparsers(dest="command", required=True)
    pair = sub.add_parser("pair", help="pair with the iPad: hmm-bridge pair [address] <code>  (the code is on the iPad)")
    pair.add_argument("target", nargs="*", metavar="[address] code")
    serve = sub.add_parser("mcp", help="run the MCP server (stdio; --http for localhost)")
    serve.add_argument("args", nargs=argparse.REMAINDER)
    look = sub.add_parser("observe", help="save the shot's observe pictures and report into a folder")
    look.add_argument("--time", type=float)
    look.add_argument("--views", nargs="*", default=["camera", "top", "value"])
    look.add_argument("--subject")
    look.add_argument("--to", type=pathlib.Path, default=pathlib.Path("observe"))
    sub.add_parser("status")
    push = sub.add_parser("push")
    push.add_argument("files", nargs="+", type=pathlib.Path)
    audio = sub.add_parser("audio")
    audio.add_argument("file", type=pathlib.Path)
    audio.add_argument("--role", default="voiceover", choices=["voiceover", "sfx", "music"])
    pull = sub.add_parser("pull")
    pull.add_argument("names", nargs="*")
    pull.add_argument("--all", action="store_true")
    pull.add_argument("--to", type=pathlib.Path, default=pathlib.Path("renders"))
    watch = sub.add_parser("watch")
    watch.add_argument("folder", type=pathlib.Path)
    generate = sub.add_parser("generate")
    generate.add_argument("generator")
    generate.add_argument("args", nargs=argparse.REMAINDER)
    media = sub.add_parser("media")
    media.add_argument("files", nargs="+", type=pathlib.Path)
    media.add_argument("--at", type=float)
    media.add_argument("--overlay", action="store_true", help="flat over the frame instead of a card in the world")
    manim = sub.add_parser("manim")
    manim.add_argument("script", type=pathlib.Path)
    manim.add_argument("scene")
    manim.add_argument("--at", type=float)
    manim.add_argument("--quality", default="high", choices=["low", "medium", "high", "4k"])
    manim.add_argument("--fps", type=int, default=30)
    manim.add_argument("--opaque", action="store_true", help="keep Manim's background (an .mp4) instead of transparency")
    script = sub.add_parser("script")
    script.add_argument("file", type=pathlib.Path)
    script.add_argument("--dry-run", action="store_true")
    options = parser.parse_args(argv)
    if options.command == "mcp":
        from .mcp_server import main as serve_mcp

        serve_mcp(options.args)
        return 0

    try:
        if options.command == "pair":
            if len(options.target) > 2:
                parser.error("pair takes an address and/or a code")
            # A code is six digits; anything else (with a dot or a colon) is the iPad's address.
            codes = [part for part in options.target if part.isdigit() and len(part) == 6]
            addresses = [part for part in options.target if part not in codes]
            if not codes:
                print("Pairing needs the code on the iPad: open Actions ▸ AI & laptop ▸ Pair a laptop, then run hmm-bridge pair <code>.",
                      file=sys.stderr)
                return 1
            code = codes[0]
            if addresses:
                host = normalize_host(addresses[0])
            else:
                print("Looking for your iPad (Bridge on)...")
                found = discover()
                if not found:
                    print("Couldn't find it. Is the Bridge on and the laptop on the same Wi-Fi? "
                          "Or give the address it shows: hmm-bridge pair 192.168.1.20 " + code, file=sys.stderr)
                    return 1
                host = found[0]
                print(f"Found {host}")
            token = Bridge(host=host, token=None).pair(code)
            config = load_config()
            config.update({"host": host, "token": token})
            save_config(config)
            print(f"Paired with {host}. Try: hmm-bridge status")
            return 0
        bridge = Bridge()
        if options.command == "status":
            print(json.dumps(bridge.status(), indent=2))
        elif options.command == "observe":
            save_observe(bridge.observe(time=options.time, views=options.views, subject=options.subject), options.to)
        elif options.command == "push":
            for path in options.files:
                print(f"{path.name}: {bridge.import_file(path)}")
        elif options.command == "audio":
            print(bridge.import_audio(options.file, role=options.role))
        elif options.command == "pull":
            options.to.mkdir(parents=True, exist_ok=True)
            available = bridge.renders()
            wanted = available if options.all else (options.names or available[-1:])
            for name in wanted:
                (options.to / name).write_bytes(bridge.download_render(name))
                print(f"↓ {options.to / name}")
        elif options.command == "watch":
            seen = {p for p in options.folder.glob("*") if p.suffix.lower() in MODEL_TYPES}
            print(f"Watching {options.folder} (Ctrl+C to stop)…")
            while True:
                for path in sorted(options.folder.glob("*")):
                    if path.suffix.lower() in MODEL_TYPES and path not in seen:
                        time.sleep(1)  # let the writer finish
                        print(f"{path.name}: {bridge.import_file(path)}")
                        seen.add(path)
                time.sleep(2)
        elif options.command == "generate":
            with tempfile.TemporaryDirectory() as folder:
                made = run_generator(options.generator, options.args, pathlib.Path(folder))
                print(f"{made.name}: {bridge.import_file(made)}")
        elif options.command == "media":
            for path in options.files:
                print(f"{path.name}: {bridge.add_media(path, at=options.at, placement='overlay' if options.overlay else 'card')}")
        elif options.command == "manim":
            from .manim_render import render

            with tempfile.TemporaryDirectory() as folder:
                video = render(options.script, options.scene, pathlib.Path(folder), quality=options.quality, fps=options.fps,
                               transparent=not options.opaque)
                placement = "card" if options.opaque else "overlay"
                print(f"{video.name}: {bridge.add_media(video, at=options.at, placement=placement)}")
        elif options.command == "script":
            payload = json.loads(options.file.read_text(encoding="utf-8"))
            reply = bridge.build(payload.get("actions", []), title=payload.get("title", options.file.stem), dry_run=options.dry_run)
            print(describe_build(reply))
    except BridgeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
