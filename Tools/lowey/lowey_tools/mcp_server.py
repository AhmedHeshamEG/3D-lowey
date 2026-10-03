"""The `lowey` MCP server (MCP v2) — lets Claude, or any MCP client, direct 3D-lowey on the iPad through the LAN bridge.

Run by the MCP client over stdio:  hmm-bridge mcp   (or the old name, lowey-mcp)
Sixteen tools (PROMPT §12.2). Everything that changes the scene is Scene Script v3 sent to `build`: one batch = one
Proposal on the iPad (with a preview thumbnail) = one undo step. The app sees for the model: `build` replies carry an
`observe` of the result, and `observe` / `contact_sheet` return pictures with numbered marks and a measured report.
"""
from __future__ import annotations

import base64
import json
import pathlib
from typing import Any

try:  # MCP Python SDK 2.x
    from mcp.server.mcpserver import Image
    from mcp.server.mcpserver import MCPServer as Server
except ImportError:  # 1.x
    from mcp.server.fastmcp import FastMCP as Server
    from mcp.server.fastmcp import Image

from .client import Bridge, BridgeError, describe_build

INSTRUCTIONS = (
    "3D-lowey is Hesham's iPad app for low-poly 3D videos (Ink, Comic, Sketch, Clay and Low-poly Looks). Start with status "
    "and read_project. Build with Scene Script v3 through build: Kit models first (find_assets), placed by relation "
    "(on, beside_left, in_front_of…), never by guessing coordinates. Then frame_shot, light, observe with the top and "
    "value views, critique against the rubric, fix. Time everything to spoken words ({\"word\": \"Enigma\"}). One idea "
    "per shot; one Proposal per shot. Hesham approves every change on the iPad; if he says no, ask what to change."
)

mcp = Server("3D-lowey", instructions=INSTRUCTIONS)

_bridge: Bridge | None = None

VIEWS = ["camera", "top", "front", "side", "value", "silhouette"]


def bridge() -> Bridge:
    global _bridge
    if _bridge is None:
        _bridge = Bridge()
    return _bridge


def png(data: bytes) -> Image:
    """An image result (the SDK changed the argument name between versions)."""
    try:
        return Image(data=data, mimeType="image/png")
    except Exception:  # noqa: BLE001 - 1.x rejects mimeType (TypeError or a pydantic error)
        return Image(data=data, format="png")


def _compact(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def _clean(action: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in action.items() if value is not None}


def _at(at: Any = None, on_word: str | None = None) -> Any:
    """A time: a spoken word wins over seconds."""
    return {"word": on_word} if on_word else at


def _images(observe: dict | None, views: list[str] | None = None) -> list[Image]:
    images = (observe or {}).get("images") or {}
    order = views or VIEWS
    return [png(base64.b64decode(images[name])) for name in order if name in images]


def _build(title: str, actions: list[dict[str, Any]], dry_run: bool = False, views: list[str] | None = None,
           subject: str | None = None) -> list[Any] | str:
    """Sends a v3 batch; returns the reply in words plus the observe pictures of the result."""
    try:
        reply = bridge().build(actions, title=title, dry_run=dry_run, views=views, subject=subject)
    except BridgeError as error:
        return f"Error: {error}"
    text = describe_build(reply)
    pictures = _images(reply.get("observe"), views)
    return [text, *pictures] if pictures else text


# -- 1–3: reading ------------------------------------------------------------------------------------------------------

@mcp.tool()
def status() -> str:
    """Which iPad is paired, the open project, scene and shot, the playhead, whether auto-apply is on."""
    try:
        return _compact(bridge().status())
    except BridgeError as error:
        return f"Error: {error}"


@mcp.tool()
def read_project(transcript: bool = False) -> str:
    """The project at a glance (a summary line first): scenes, shots (cameras, when the edit cuts to them, on which word),
    the cast, the Look, the palette, Kit Sets in use and the voiceover text. transcript=True adds every word's timing."""
    try:
        project = bridge().read_project()
        if transcript:
            project["timedWords"] = bridge().transcript().get("words", [])
        return _compact(project)
    except BridgeError as error:
        return f"Error: {error}"


@mcp.tool()
def find_assets(query: str = "", set: str | None = None, limit: int = 8, thumbnails: int = 4) -> list[Any] | str:  # noqa: A002
    """Kit and library models by words ("desk lamp", "rock", "robot"), Kit first, optionally in one Set ("Room & Desk",
    "Nature", "Office & Computers", "Lab & Science", "Space", "City & Street", "Kitchen & Food", "Props & Signs",
    "Characters"). Each has its id (use it in build's add), real size in metres, surface heights to put things on, its front.
    The first `thumbnails` come with a picture."""
    try:
        found = bridge().find_assets(query, set_name=set, limit=limit)
        pictures = []
        for asset in found[: max(thumbnails, 0)]:
            try:
                pictures.append(png(bridge().thumbnail(asset["id"])))
            except BridgeError:
                continue
        return [_compact(found), *pictures]
    except BridgeError as error:
        return f"Error: {error}"


# -- 4: build ------------------------------------------------------------------------------------------------------------

@mcp.tool()
def build(actions: list[dict[str, Any]], title: str = "From Claude", dry_run: bool = False, views: list[str] | None = None,
          subject: str | None = None) -> list[Any] | str:
    """Scene Script v3 (resource lowey://actions has every verb): add from the Kit, place by relation, scaleTo, recolor,
    remove, group, frameShot, lighting, look, intent, preset, keys, cameraMove, cut, overlay, flipbook, effect… Many actions,
    ONE Proposal on the iPad, ONE undo step. Returns what changed and an observe of the result (views: camera, top, front,
    side, value, silhouette). dry_run=True previews without proposing and returns a proposal_id for commit."""
    return _build(title, actions, dry_run, views, subject)


# -- 5–11: directing (each is one small build) --------------------------------------------------------------------------

@mcp.tool()
def frame_shot(subject: str, shot_type: str = "medium", composition: str = "center", lens: float | None = None,
               shot: str | None = None, other: str | None = None, at: Any = None, on_word: str | None = None) -> list[Any] | str:
    """The camera solver: shot_type extremeWide | wide | full | medium | closeUp | extremeCloseUp | overTheShoulder |
    twoShot | insert; composition center | leftThird | rightThird | lowAngle | highAngle; lens in mm (the shot type picks
    one otherwise). `shot` names the camera (made when new). With on_word/at the edit cuts to it there."""
    action = _clean({"do": "frameShot", "subject": subject, "shotType": shot_type, "composition": composition, "lens": lens,
                     "camera": shot, "other": other, "at": _at(at, on_word)})
    return _build(f"Frame {subject}", [action], views=["camera"], subject=subject)


@mcp.tool()
def light(recipe: str, subject: str | None = None, intensity: float | None = None, warmth: float | None = None) -> list[Any] | str:
    """A lighting recipe placed for the shot camera: key-warm-world-cool (the default story light), noir-single-source,
    golden-rim, monitor-glow, moonlit, studio-soft. Overrides: intensity (×), warmth (-1 cool … 1 warm)."""
    action = _clean({"do": "lighting", "recipe": recipe, "subject": subject, "intensity": intensity, "warmth": warmth})
    return _build(f"Light: {recipe}", [action], views=["camera", "value"], subject=subject)


@mcp.tool()
def set_look(look: str | None = None, mood: str | None = None, per_object: dict[str, str] | None = None,
             scene_only: bool = True) -> list[Any] | str:
    """The Look (ink, comic, sketch, clay, lowpoly), the mood (day, goldenHour, dusk, night, space, studio) and per-object
    Looks ({"Robot": "sketch"})."""
    action = _clean({"do": "look", "look": look, "mood": mood, "perObject": per_object, "sceneOnly": scene_only})
    return _build("Look", [action], views=["camera"])


@mcp.tool()
def animate(targets: str | list[str], what: str, at: Any = None, on_word: str | None = None, duration: float | None = None,
            how: str | None = None, to: Any = None, frame_rate: str | None = None) -> list[Any] | str:
    """Say the intent; the app picks the animation. what: enter | exit | emphasise | react | walk_to | look_at | talk | idle
    — or a preset (popIn, bounce, float…) or a clip (Wave, Walk, Nod…). how: an expression for react (surprised, happy,
    shocked…). to: where walk_to / look_at go (a name or [x, y, z]). frame_rate: ones | twos | threes | fours."""
    when = _at(at, on_word)
    presets = {"popIn", "popOut", "grow", "shrink", "bounce", "wiggle", "float", "spin", "shake", "pulse", "fadeIn", "fadeOut",
               "slideIn", "dropIn", "typewriter"}
    clips = {"Idle", "Walk", "Run", "Talk", "Wave", "Point", "Type", "Nod", "Shrug", "Celebrate"}
    if what in presets:
        action = _clean({"do": "preset", "target": targets, "preset": what, "at": when, "duration": duration})
    elif what in clips:
        action = _clean({"do": "clip", "character": targets, "clip": what, "at": when, "duration": duration})
    else:
        action = _clean({"do": "intent", "target": targets, "what": what, "how": how, "to": to, "at": when, "duration": duration,
                         "frameRate": frame_rate})
    return _build(f"Animate: {what}", [action], views=["camera"])


@mcp.tool()
def camera_move(move: str, shot: str | None = None, subject: Any = None, strength: float | None = None, at: Any = None,
                on_word: str | None = None, duration: float | None = None) -> list[Any] | str:
    """pushIn, pullOut, punchIn, snapZoom, orbit, dolly, truck, crane, whipPan, shake, reveal — eased, landing on the word."""
    action = _clean({"do": "cameraMove", "move": move, "camera": shot, "subject": subject, "strength": strength,
                     "at": _at(at, on_word), "duration": duration})
    return _build(f"Camera: {move}", [action], views=["camera"])


@mcp.tool()
def add_overlay(kind: str, text: str | None = None, on_word: str | None = None, at: Any = None, style: dict[str, Any] | None = None,
                name: str | None = None) -> list[Any] | str:
    """Titles, labels and comic language over the frame: title, label, arrow, highlight, cross, question, exclamation,
    check, circle, star. It pops in on `on_word`. style: {"at": [x, y] in -1…1, "size": 1, "color": "palette:2",
    "follow": "Paper"}. Don't repeat the voiceover word for word."""
    style = style or {}
    overlay_name = name or (text or kind)[:24]
    actions = [_clean({"do": "overlay", "shape": kind, "text": text, "name": overlay_name, "at": style.get("at"),
                       "size": style.get("size"), "color": style.get("color"), "follow": style.get("follow")})]
    if on_word or at is not None:
        preset = "typewriter" if kind in {"title", "label"} else "popIn"
        actions.append({"do": "preset", "target": overlay_name, "preset": preset, "at": _at(at, on_word)})
    return _build(f"Overlay: {overlay_name}", actions, views=["camera"])


@mcp.tool()
def flipbook(kind: str, anchor: Any, at: Any = None, on_word: str | None = None, until: Any = None, frames: int | None = None,
             color: str | None = None) -> list[Any] | str:
    """Drawn FX that sell a moment: speedLines, impactBurst, sweatDrop, sparkle, smear — anchored to an object (or a
    point) from `on_word` (or `at`) until `until`."""
    action = _clean({"do": "flipbook", "fx": kind, "anchor": anchor, "at": _at(at, on_word), "until": until, "frames": frames,
                     "color": color})
    return _build(f"Flipbook: {kind}", [action], views=["camera"])


# -- 12–13: media from the laptop ---------------------------------------------------------------------------------------

@mcp.tool()
def add_media(path: str, at: float | None = None, overlay: bool = False) -> str:
    """A picture or video file from this laptop into the open shot: a thin card standing in the 3D world, or overlay=True
    to lay it flat over the frame. Videos play from `at` seconds (default: the playhead)."""
    try:
        return _compact(bridge().add_media(pathlib.Path(path).expanduser(), at=at, placement="overlay" if overlay else "card"))
    except (BridgeError, OSError) as error:
        return f"Error: {error}"


@mcp.tool()
def render_manim(code: str, scene: str, at: float | None = None, quality: str = "high", transparent: bool = True) -> str:
    """Render Manim on this laptop and lay it over the shot from `at` seconds (graphs, equations, diagrams). `code` is the
    Python source (or a path to a .py file); `scene` the Scene class. Transparent by default, floating over the 3D world."""
    import tempfile

    from .manim_render import render

    with tempfile.TemporaryDirectory() as folder:
        source = pathlib.Path(code).expanduser()
        if not (len(code) < 400 and source.suffix == ".py" and source.exists()):
            source = pathlib.Path(folder) / "scene.py"
            source.write_text(code, encoding="utf-8")
        try:
            video = render(source, scene, pathlib.Path(folder), quality=quality, transparent=transparent)
            return _compact(bridge().add_media(video, at=at, placement="overlay" if transparent else "card"))
        except (BridgeError, RuntimeError, OSError) as error:
            return f"Error: {error}"


# -- 14–15: seeing -------------------------------------------------------------------------------------------------------

@mcp.tool()
def observe(time: float | None = None, views: list[str] | None = None, subject: str | None = None, framing: str | None = None,
            report: bool = True) -> list[Any] | str:
    """Look at the shot: the camera view with set-of-marks numbers, plus any of top / front / side (orthographic layout
    diagrams with the shot camera drawn on), value (the squint) and silhouette. The ShotReport measures every marked
    object (coverage, visible %, grounded + gap, intersects, cut by the frame, facing) and the frame (subject on thirds,
    headroom, ΔL* contrast, clutter, tangents, palette, key light) and checks the rubric with a fix for each fail."""
    wanted = [view for view in (views or ["camera", "top", "value"]) if view in VIEWS]
    try:
        reply = bridge().observe(time=time, views=wanted, subject=subject, framing=framing)
    except BridgeError as error:
        return f"Error: {error}"
    text = reply.get("summary", "")
    if report:
        text += "\n" + _compact(reply.get("report", {}))
    return [text, *_images(reply, ["camera", *[view for view in wanted if view != "camera"]])]


@mcp.tool()
def contact_sheet(start: float | None = None, end: float | None = None, frames: int = 6, subject: str | None = None) -> list[Any] | str:
    """N frames of the shot in a grid with timecodes and notes, plus motion stats per moving thing (screen path, peak
    speed, direction changes, holds, leaves frame, arcs vs straight lines, constant-speed glides, moves landing on words)
    and the camera's move. Critique motion with it."""
    try:
        reply = bridge().contact_sheet(start=start, end=end, frames=frames, subject=subject)
    except BridgeError as error:
        return f"Error: {error}"
    text = reply.get("summary", "") + "\n" + _compact(reply.get("report", {}))
    image = reply.get("image")
    return [text, png(base64.b64decode(image))] if image else text


# -- 16: commit / undo ---------------------------------------------------------------------------------------------------

@mcp.tool()
def commit(action: str = "commit", proposal_id: str | None = None, steps: int = 1) -> list[Any] | str:
    """action="commit": propose a dry run (its proposal_id) on the iPad for real. action="undo": undo `steps` changes."""
    try:
        if action == "undo":
            reply = bridge().commit(action="undo", steps=steps)
            return f"Undone {reply.get('undone', 0)} step(s)."
        if not proposal_id:
            return "Error: commit needs the proposal_id a dry run returned."
        reply = bridge().commit(proposal_id=proposal_id)
    except BridgeError as error:
        return f"Error: {error}"
    pictures = _images(reply.get("observe"), ["camera"])
    return [describe_build(reply), *pictures] if pictures else describe_build(reply)


# -- Resources and prompts ----------------------------------------------------------------------------------------------

@mcp.resource("lowey://project")
def project_resource() -> str:
    """The project summary (same as read_project)."""
    return read_project()


@mcp.resource("lowey://transcript")
def transcript_resource() -> str:
    """The voiceover's words with start/end times (w, t, e)."""
    try:
        return _compact(bridge().transcript())
    except BridgeError as error:
        return f"Error: {error}"


@mcp.resource("lowey://actions")
def actions_resource() -> str:
    """Every Scene Script v3 verb, one line each."""
    try:
        return bridge().actions()
    except BridgeError as error:
        return f"Error: {error}"


@mcp.prompt()
def direct(brief: str) -> str:
    """The director loop for a brief or a script."""
    return (
        "Direct this in 3D-lowey, following the lowey skill's director loop: read_project; a beat sheet (one beat per idea, "
        "anchored to words); a shot list as a compact table (share it before building anything expensive); per shot "
        "find_assets → build (Kit first, relations) → frame_shot → light → observe with top + value → critique with the "
        "rubric → fix (max 3 rounds); animate → contact_sheet → fix (max 2). One Proposal per shot.\n\n" + brief
    )


def main(argv: list[str] | None = None) -> None:
    import argparse

    from .remote import DEFAULT_HTTP_PORT, serve

    parser = argparse.ArgumentParser(prog="hmm-bridge mcp", description="3D-lowey MCP server (stdio by default).")
    parser.add_argument("--http", action="store_true", help="serve over HTTP on localhost: http://127.0.0.1:PORT/mcp")
    parser.add_argument("--port", type=int, default=DEFAULT_HTTP_PORT, help="local port for --http")
    args = parser.parse_args(argv)
    if args.http:
        serve(mcp, port=args.port)
    else:
        mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
