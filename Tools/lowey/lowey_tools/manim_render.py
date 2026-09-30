"""Manim → 3D-lowey: render a scene on the laptop and hand the iPad a video it can lay over the shot.

Transparent (the default): Manim draws PNG frames with an alpha channel; they are packed into a ProRes 4444 .mov
(alpha kept; iPads with an M-series chip decode it) with PyAV, which comes with Manim. Opaque: Manim's own .mp4.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

QUALITY = {"low": "l", "medium": "m", "high": "h", "4k": "k"}


def manim_command(script: pathlib.Path, scene: str, media_dir: pathlib.Path, quality: str, fps: int, transparent: bool) -> list[str]:
    flag = QUALITY.get(quality, quality)
    command = [sys.executable, "-m", "manim", "render", f"-q{flag}", "--fps", str(fps), "--media_dir", str(media_dir)]
    if transparent:
        command += ["--transparent", "--format", "png"]
    else:
        command += ["--format", "mp4"]
    return command + [str(script), scene]


def pack_prores(frames: list[pathlib.Path], out: pathlib.Path, fps: int) -> pathlib.Path:
    """PNG frames (RGBA) → ProRes 4444 .mov with alpha."""
    import av  # PyAV: installed with Manim
    import numpy as np
    from PIL import Image

    if not frames:
        raise RuntimeError("Manim made no frames")
    first = Image.open(frames[0])
    width, height = first.size
    container = av.open(str(out), mode="w")
    stream = container.add_stream("prores_ks", rate=fps)
    stream.width = width - width % 2
    stream.height = height - height % 2
    stream.pix_fmt = "yuva444p10le"
    stream.options = {"profile": "4444", "vendor": "apl0"}
    for path in frames:
        rgba = np.asarray(Image.open(path).convert("RGBA"))[: stream.height, : stream.width]
        frame = av.VideoFrame.from_ndarray(np.ascontiguousarray(rgba), format="rgba")
        for packet in stream.encode(frame):
            container.mux(packet)
    for packet in stream.encode():
        container.mux(packet)
    container.close()
    return out


def render(script: pathlib.Path, scene: str, work: pathlib.Path, quality: str = "high", fps: int = 30, transparent: bool = True,
           run=subprocess.run) -> pathlib.Path:
    """Renders `scene` from `script` into `work` and returns the video to send."""
    media = work / "media"
    run(manim_command(script, scene, media, quality, fps, transparent), check=True)
    if transparent:
        frames = sorted(p for p in media.rglob(f"{scene}*.png"))
        return pack_prores(frames, work / f"{scene}.mov", fps)
    videos = sorted(media.rglob(f"{scene}.mp4"), key=lambda p: p.stat().st_mtime)
    if not videos:
        raise RuntimeError(f"Manim made no video for {scene}")
    return videos[-1]
