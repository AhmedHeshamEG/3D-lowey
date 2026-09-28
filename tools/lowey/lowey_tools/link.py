"""lowey-link — the laptop companion for 3D-lowey.

  lowey-link pair 192.168.1.20 123456      pair with the iPad (code from: scene menu → AI & laptop bridge)
  lowey-link status                        what's open on the iPad
  lowey-link push model.glb tree.usdz      send files to the iPad's library
  lowey-link audio voiceover.m4a           add a voiceover to the open scene (--role music|sfx)
  lowey-link pull [--all] [name]           download renders (videos, frames, .srt) into ./renders
  lowey-link watch ./exports               push every new model that appears in a folder
  lowey-link generate tree --seed 3        run a laptop-side generator (Blender) and push the result
  lowey-link generate text "a red fox"     run your text-to-3D command (LOWEY_TEXT_TO_3D) and push the result
  lowey-link script shot.json              send a Scene Script (preview + approval on the iPad)
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

from .client import Bridge, BridgeError, describe, load_config, normalize_host, save_config

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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="lowey-link", description="Laptop companion for 3D-lowey")
    sub = parser.add_subparsers(dest="command", required=True)
    pair = sub.add_parser("pair")
    pair.add_argument("host")
    pair.add_argument("code")
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
    script = sub.add_parser("script")
    script.add_argument("file", type=pathlib.Path)
    script.add_argument("--dry-run", action="store_true")
    options = parser.parse_args(argv)

    try:
        if options.command == "pair":
            host = normalize_host(options.host)
            token = Bridge(host=host, token=None).pair(options.code)
            config = load_config()
            config.update({"host": host, "token": token})
            save_config(config)
            print(f"Paired with {host}. Try: lowey-link status")
            return 0
        bridge = Bridge()
        if options.command == "status":
            print(json.dumps(bridge.status(), indent=2))
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
        elif options.command == "script":
            payload = json.loads(options.file.read_text(encoding="utf-8"))
            print(describe(bridge.script(payload.get("title", options.file.stem), payload.get("actions", []), dry_run=options.dry_run)))
    except BridgeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
