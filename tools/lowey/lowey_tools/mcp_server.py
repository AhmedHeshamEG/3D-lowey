"""lowey-mcp — lets Claude (or any MCP client) drive 3D-lowey on the iPad through the LAN Bridge.

Run by the MCP client over stdio:  lowey-mcp
Every tool becomes a small Scene Script; the iPad shows a preview and Hesham approves it (unless auto-apply is on).
Everything is one undo step on the iPad and stays hand-editable.
"""
from __future__ import annotations

import json
from typing import Any

try:  # MCP Python SDK 2.x
    from mcp.server.mcpserver import Image
    from mcp.server.mcpserver import MCPServer as Server
except ImportError:  # 1.x
    from mcp.server.fastmcp import FastMCP as Server
    from mcp.server.fastmcp import Image

from .client import Bridge, BridgeError, describe

mcp = Server(
    "3D-lowey",
    instructions=(
        "3D-lowey is Hesham's iPad app for low-poly 3D videos. Read lowey://scene and lowey://transcript first. "
        "Build shots with run_script (many actions, one approval) or the small tools. Name things so later actions can "
        "refer to them. Time things to spoken words ({\"word\": \"Enigma\"}). Use the project palette (\"palette:N\"). "
        "Take a snapshot to check your work. Hesham approves every change on the iPad; if he says no, ask what to change."
    ),
)

_bridge: Bridge | None = None


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


def _script(title: str, actions: list[dict[str, Any]], dry_run: bool = False) -> str:
    try:
        return describe(bridge().script(title, actions, dry_run=dry_run))
    except BridgeError as error:
        return f"Error: {error}"


def _clean(action: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in action.items() if value is not None}


# -- Reading ----------------------------------------------------------------------------------------------------------

@mcp.tool()
def get_scene(depth: int = 2) -> str:
    """The open scene, compact: objects (name, kind, position, size), cameras, cuts, markers, effects, transcript."""
    try:
        return json.dumps(bridge().scene(depth), separators=(",", ":"))
    except BridgeError as error:
        return f"Error: {error}"


@mcp.tool()
def list_assets(query: str = "", limit: int = 30) -> str:
    """Search Hesham's asset library (models, prefabs). Use the names with place_asset."""
    try:
        return json.dumps(bridge().assets(query, limit), separators=(",", ":"))
    except BridgeError as error:
        return f"Error: {error}"


@mcp.tool()
def get_transcript() -> str:
    """The voiceover's words with start/end times (w, t, e). Sync actions to these words."""
    try:
        return json.dumps(bridge().transcript(), separators=(",", ":"))
    except BridgeError as error:
        return f"Error: {error}"


@mcp.tool()
def actions_reference() -> str:
    """The full Scene Script action vocabulary (read once before writing big scripts)."""
    try:
        return bridge().actions_reference()
    except BridgeError as error:
        return f"Error: {error}"


@mcp.tool()
def snapshot(framing: str = "16:9", time: float | None = None, through_camera: bool = True) -> Image | str:
    """A picture of the shot (through the shot camera) at a time — check your work."""
    try:
        return png(bridge().snapshot(framing=framing, long_side=960, camera=through_camera, time=time))
    except BridgeError as error:
        return f"Error: {error}"


# -- Building ---------------------------------------------------------------------------------------------------------

@mcp.tool()
def run_script(title: str, actions: list[dict[str, Any]], dry_run: bool = False) -> str:
    """Run a Scene Script (see actions_reference): many actions, ONE approval, ONE undo step. Best for whole shots.
    dry_run=True only previews."""
    return _script(title, actions, dry_run)


@mcp.tool()
def create_object(shape: str, name: str, at: list[float] | None = None, size: list[float] | None = None, color: str | None = None,
                  rotation: list[float] | None = None, glow: float | None = None) -> str:
    """Add a blockout shape (cube, sphere, cylinder, cone, plane, torus, ramp, group). Stands on the ground unless 'at' has a height."""
    return _script(f"Add {name}", [_clean({"do": "add", "shape": shape, "name": name, "at": at, "size": size, "color": color,
                                           "rotation": rotation, "glow": glow})])


@mcp.tool()
def place_asset(asset: str, name: str | None = None, at: list[float] | None = None, scale: float | None = None,
                rotation: list[float] | None = None) -> str:
    """Place a library model or prefab by search text (e.g. 'desk', 'tiger')."""
    return _script(f"Place {asset}", [_clean({"do": "place", "asset": asset, "name": name, "at": at, "scale": scale, "rotation": rotation})])


@mcp.tool()
def set_property(target: str, property: str, value: Any, at: Any = None) -> str:  # noqa: A002 - matches the app's word
    """Set a property (color, opacity, glow=emissiveIntensity, lightIntensity, fieldOfView…). With 'at' it becomes a key."""
    return _script(f"Set {property}", [_clean({"do": "set", "target": target, "property": property, "value": value, "at": at})])


@mcp.tool()
def add_keyframes(target: str, property: str, keys: list[dict[str, Any]]) -> str:
    """Keyframes: keys = [{"t": seconds or {"word": …}, "value": …, "easing": "backOut"}]. Properties: position, rotation, scale, opacity…"""
    return _script(f"Animate {target}", [{"do": "keys", "target": target, "property": property, "keys": keys}])


@mcp.tool()
def apply_preset(target: str | list[str], preset: str, at: Any = "now", duration: float | None = None, stagger: float | None = None,
                 order: str | None = None) -> str:
    """One-tap animation (popIn, grow, bounce, wiggle, float, spin, shake, pulse, fadeIn, slideIn, dropIn, typewriter…).
    Several targets are staggered (order: selection | leftToRight | wave)."""
    return _script(f"{preset}", [_clean({"do": "preset", "target": target, "preset": preset, "at": at, "duration": duration,
                                         "stagger": stagger, "order": order})])


@mcp.tool()
def camera_move(move: str, subject: str | None = None, at: Any = "now", duration: float | None = None, camera: str | None = None) -> str:
    """Camera move on the shot camera: pushIn, pullOut, punchIn, snapZoom, orbit, dolly, truck, crane, whipPan, shake, reveal."""
    return _script(f"{move}", [_clean({"do": "cameraMove", "move": move, "subject": subject, "at": at, "duration": duration,
                                       "camera": camera})])


@mcp.tool()
def set_look(mood: str | None = None, post: str | None = None, fog: float | None = None, scene_only: bool = True) -> str:
    """Mood (day, goldenHour, dusk, night, space, studio) and finish (clean, cinematic, dreamy, retro, comic, collage, oldFilm)."""
    return _script("Look", [_clean({"do": "look", "mood": mood, "post": post, "fog": fog, "sceneOnly": scene_only})])


@mcp.tool()
def add_overlay(shape: str, text: str | None = None, at: list[float] | None = None, size: float | None = None, follow: str | None = None,
                color: str | None = None, name: str | None = None) -> str:
    """2D overlay on the frame: title, label, arrow, highlight, cross (the big X), question, exclamation, check, circle, star.
    'at' is frame space [x, y] in -1…1. 'follow' pins it to an object."""
    return _script(f"Overlay {shape}", [_clean({"do": "overlay", "shape": shape, "text": text, "at": at, "size": size, "follow": follow,
                                                "color": color, "name": name})])


@mcp.tool()
def attach_to_word(word: str, action: dict[str, Any], occurrence: int = 1, offset: float = 0) -> str:
    """Run any action at a spoken word, e.g. word='Nobody', action={"do": "overlay", "shape": "cross"} or
    {"do": "preset", "target": "Paper", "preset": "grow"}."""
    timed = dict(action)
    timed["at"] = {"word": word, "occurrence": occurrence, "offset": offset}
    return _script(f"On '{word}'", [timed])


@mcp.tool()
def undo() -> str:
    """Undo the last change on the iPad."""
    try:
        bridge().undo()
        return "Undone."
    except BridgeError as error:
        return f"Error: {error}"


# -- Resources ----------------------------------------------------------------------------------------------------------

@mcp.resource("lowey://scene")
def scene_resource() -> str:
    """The open scene (compact JSON)."""
    return get_scene()


@mcp.resource("lowey://look")
def look_resource() -> str:
    """The project's look: palette, lighting, sky, fog, post-processing."""
    try:
        return json.dumps(bridge().look(), separators=(",", ":"))
    except BridgeError as error:
        return f"Error: {error}"


@mcp.resource("lowey://assets")
def assets_resource() -> str:
    """Hesham's asset library index."""
    return list_assets("", 200)


@mcp.resource("lowey://transcript")
def transcript_resource() -> str:
    """The voiceover transcript with word times."""
    return get_transcript()


# -- Prompts -------------------------------------------------------------------------------------------------------------

@mcp.prompt()
def breakdown_script(script: str) -> str:
    """Script → shots (what each line shows)."""
    return (
        "Break this narration into shots for a low-poly 3D explainer. For each shot give: the line, the ONE image it shows "
        "(a visual metaphor, goofy is fine), the subject, 3–6 objects (library first, blockout otherwise), the camera move and the "
        "word it lands on, overlays/effects. Keep it short — a table.\n\n" + script
    )


@mcp.prompt()
def plan_shots(line: str) -> str:
    """Plan shots for one line of the script."""
    return (
        f"Plan the shot(s) for: “{line}”. Read lowey://scene, lowey://assets and lowey://transcript. Say which words carry the beats "
        "(camera push, pop-ins, the X…). Then write ONE run_script call that builds it. Use palette colours, name everything."
    )


@mcp.prompt()
def build_scene(description: str) -> str:
    """Build a set from a description."""
    return (
        f"Build this set in 3D-lowey: {description}. Check list_assets first; use blockout shapes for the rest. Few objects, big "
        "shapes, warm light on the subject against a cooler world. One run_script, then a snapshot to check, then fix what's off."
    )


@mcp.prompt()
def direct_camera(shot: str) -> str:
    """Camera direction for a shot."""
    return (
        f"Direct the camera for: {shot}. Add a camera framing the subject (35–50 mm), cut to it, and one move timed to the key word. "
        "Fast pacing: punch-ins on emphasis, slow push on reveals. Snapshot at the start and end of the move."
    )


@mcp.prompt()
def sync_to_voiceover() -> str:
    """Re-time the shot to the voiceover."""
    return (
        "Read lowey://transcript and lowey://scene. Re-time every animation, cut and effect to the word it belongs to "
        "(use {\"word\": …} times, not seconds). Report what moved."
    )


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
