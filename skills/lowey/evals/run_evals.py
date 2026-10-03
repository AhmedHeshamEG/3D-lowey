"""Runs the lowey skill's eval briefs against a real 3D-lowey (an iPad, or the simulator) and scores the results.

    pip install -e Tools/lowey anthropic        # the laptop tools and the Claude API client
    hmm-bridge pair 123456                      # once
    # On the iPad: open a project for the evals; Bridge ▸ "Auto-apply for this session" (or tap Apply as Proposals come)
    set ANTHROPIC_API_KEY=...
    python skills/lowey/evals/run_evals.py                  # all twelve briefs
    python skills/lowey/evals/run_evals.py night-desk comic-impact --model claude-opus-5-5
    python skills/lowey/evals/run_evals.py --plan           # check the bridge and list the briefs, no model calls
    python skills/lowey/evals/run_evals.py --score evals/runs/2026-10-04   # re-score a saved run

Each brief runs in a fresh scene. The model gets SKILL.md and lessons.md, can read any skill file, and drives the
app through the same sixteen tools as Claude Code. The score comes from what the app measures afterwards (observe at
two moments and a contact sheet), not from the model's account: see rubric.md. Everything lands in
`runs/<date>/<brief>/` (pictures, reports, the transcript of tool calls) with `results.md` and `results.json`.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import io
import json
import pathlib
import re
import struct
import sys
import time
import wave
from dataclasses import dataclass, field
from typing import Any

HERE = pathlib.Path(__file__).resolve().parent
SKILL = HERE.parent
REPO = SKILL.parent.parent
sys.path.insert(0, str(REPO / "Tools" / "lowey"))

DEFAULT_MODEL = "claude-opus-5-5"
RUBRIC = ["Read", "Focus", "Frame", "Ground", "Scale", "Light", "Clutter", "Motion"]
BUGS = {"Ground", "Scale"}
PASS_SCORE = 0.85
CHANGING_TOOLS = {"build", "frame_shot", "light", "set_look", "animate", "camera_move", "add_overlay", "flipbook", "commit"}
LOOKING_TOOLS = {"observe", "contact_sheet"}


@dataclass
class Brief:
    id: str
    text: str
    voiceover: str | None = None
    framing: str = "16:9"
    seconds: float = 6


@dataclass
class Run:
    brief: Brief
    calls: list[dict[str, Any]] = field(default_factory=list)
    final: str = ""


# -- Briefs ------------------------------------------------------------------------------------------------------------

def parse_briefs(text: str) -> list[Brief]:
    """`## id` blocks; `voiceover:`, `framing:` and `seconds:` lines are settings, the rest is the brief."""
    briefs = []
    for block in re.split(r"^## ", text, flags=re.MULTILINE)[1:]:
        head, _, body = block.partition("\n")
        brief = Brief(id=head.strip(), text="")
        lines = []
        for line in body.strip().splitlines():
            key, _, value = line.partition(":")
            if key in {"voiceover", "framing", "seconds"} and value:
                if key == "seconds":
                    brief.seconds = float(value)
                else:
                    setattr(brief, key, value.strip())
            else:
                lines.append(line)
        brief.text = " ".join(" ".join(lines).split())
        briefs.append(brief)
    return briefs


# -- Scoring -----------------------------------------------------------------------------------------------------------

def score(observes: list[dict], sheet: dict | None) -> dict[str, Any]:
    """Rubric lines per observe moment (+ Motion from the contact sheet) → the score and the fails, as rubric.md says."""
    moments = []
    fails: dict[str, str] = {}
    motion = next((c for c in ((sheet or {}).get("report") or {}).get("checks", []) if c.get("name") == "Motion"), None)
    for observe in observes:
        checks = {c["name"]: c for c in (observe.get("report") or {}).get("checks", [])}
        if motion:
            checks["Motion"] = motion
        measured = [checks[name] for name in RUBRIC if name in checks and checks[name].get("result") in {"pass", "fail"}]
        if not measured:
            continue
        passes = sum(1 for check in measured if check["result"] == "pass")
        moments.append(passes / len(measured))
        for check in measured:
            if check["result"] == "fail":
                fails.setdefault(check["name"], check.get("detail", ""))
    value = round(sum(moments) / len(moments), 3) if moments else 0.0
    passed = value >= PASS_SCORE and not (BUGS & set(fails))
    return {"score": value, "fails": fails, "result": "pass" if passed else "fail"}


def process(calls: list[dict[str, Any]]) -> dict[str, Any]:
    """How the agent worked: Proposals, calls, Kit first, looked before finishing."""
    names = [call["tool"] for call in calls]
    proposals = sum(1 for call in calls if call["tool"] in CHANGING_TOOLS and not call["input"].get("dry_run")
                    and not (call["tool"] == "commit" and call["input"].get("action") == "undo"))
    primitives_before_kit = False
    seen_find = False
    for call in calls:
        if call["tool"] == "find_assets":
            seen_find = True
        if call["tool"] == "build" and not seen_find:
            if any(action.get("shape") not in (None, "group") for action in call["input"].get("actions", []) if isinstance(action, dict)):
                primitives_before_kit = True
    last_change = max((i for i, name in enumerate(names) if name in CHANGING_TOOLS), default=-1)
    looked = any(name in LOOKING_TOOLS for name in names[last_change + 1:]) if last_change >= 0 else False
    return {"proposals": proposals, "calls": len(calls), "kitFirst": not primitives_before_kit, "looked": looked,
            "rounds": names.count("observe")}


def table(rows: list[dict[str, Any]]) -> str:
    lines = ["| brief | score | fails | proposals | calls | looked | result |", "|---|---|---|---|---|---|---|"]
    for row in rows:
        fails = "; ".join(f"{name}: {detail}" for name, detail in row["fails"].items()) or "—"
        lines.append(f"| {row['brief']} | {row['score']:.2f} | {fails} | {row['proposals']} | {row['calls']} | "
                     f"{'yes' if row['looked'] else 'no'} | {row['result']} |")
    passed = sum(1 for row in rows if row["result"] == "pass")
    lines += ["", f"{passed} of {len(rows)} briefs pass (score ≥ {PASS_SCORE}, no Ground or Scale fail)."]
    return "\n".join(lines) + "\n"


# -- The harness -------------------------------------------------------------------------------------------------------

def silent_wav(seconds: float, rate: int = 16000) -> bytes:
    """A silent voiceover of the brief's length (its words come from the brief, timed by the `transcript` verb)."""
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(struct.pack("<h", 0) * int(seconds * rate))
    return buffer.getvalue()


def prepare(bridge, brief: Brief) -> None:
    """A fresh scene of the right length, with the voiceover's words on the timeline when the brief has one."""
    bridge.new_scene(f"Eval · {brief.id}")
    actions: list[dict[str, Any]] = [{"do": "length", "seconds": brief.seconds}]
    if brief.voiceover:
        bridge.request("POST", "/v1/audio/import", body=silent_wav(brief.seconds), query={"name": f"{brief.id}.wav", "role": "voiceover"},
                       content_type="application/octet-stream")
        actions.append({"do": "transcript", "text": brief.voiceover, "from": 0.3, "to": max(brief.seconds - 0.4, 0.8)})
    # The iPad adds the audio clip a moment after the upload answers: try the setup again until it's there.
    from lowey_tools.client import BridgeError

    for attempt in range(8):
        try:
            bridge.build(actions, title=f"Eval setup: {brief.id}")
            return
        except BridgeError:
            if attempt == 7:
                raise
            time.sleep(0.5)


def measure(bridge, brief: Brief, folder: pathlib.Path) -> tuple[list[dict], dict | None]:
    """observe at the middle and near the end, and a contact sheet; pictures and reports saved."""
    folder.mkdir(parents=True, exist_ok=True)
    duration = bridge.status().get("duration") or brief.seconds
    observes = []
    for label, moment in (("mid", duration * 0.5), ("late", duration * 0.85)):
        observed = bridge.observe(time=moment, views=["camera", "top", "value"], framing=brief.framing)
        for view, data in (observed.get("images") or {}).items():
            (folder / f"observe-{label}-{view}.png").write_bytes(base64.b64decode(data))
        (folder / f"observe-{label}.json").write_text(json.dumps(observed.get("report", {}), indent=2, ensure_ascii=False), encoding="utf-8")
        observes.append(observed)
    sheet = bridge.contact_sheet(start=0, end=duration, frames=6)
    if sheet.get("image"):
        (folder / "contact-sheet.png").write_bytes(base64.b64decode(sheet["image"]))
    (folder / "contact-sheet.json").write_text(json.dumps(sheet.get("report", {}), indent=2, ensure_ascii=False), encoding="utf-8")
    return observes, sheet


def tool_definitions() -> list[dict[str, Any]]:
    """The sixteen MCP tools as Claude API tools, plus reading a skill file."""
    import asyncio

    from lowey_tools import mcp_server

    tools = []
    for tool in asyncio.run(mcp_server.mcp.list_tools()):
        schema = getattr(tool, "input_schema", None) or getattr(tool, "inputSchema", None) or {"type": "object"}
        tools.append({"name": tool.name, "description": tool.description or "", "input_schema": schema})
    tools.append({"name": "read_skill_file", "description": "Read a file of the lowey skill (e.g. modules/camera.md).",
                  "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}})
    return tools


def call_tool(name: str, arguments: dict[str, Any]) -> list[dict[str, Any]]:
    """Runs a tool in-process and returns Claude API content blocks (text and images)."""
    from lowey_tools import mcp_server

    if name == "read_skill_file":
        path = (SKILL / arguments.get("path", "")).resolve()
        if SKILL not in path.parents or not path.is_file():
            return [{"type": "text", "text": f"No skill file {arguments.get('path')}"}]
        return [{"type": "text", "text": path.read_text(encoding="utf-8")}]
    function = getattr(mcp_server, name, None)
    if function is None:
        return [{"type": "text", "text": f"Unknown tool {name}"}]
    try:
        result = function(**arguments)
    except Exception as error:  # noqa: BLE001 - the model sees the error and can fix its call
        return [{"type": "text", "text": f"Error: {error}"}]
    blocks = []
    for item in result if isinstance(result, list) else [result]:
        if isinstance(item, str):
            blocks.append({"type": "text", "text": item})
        elif getattr(item, "data", None) is not None:
            blocks.append({"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                                       "data": base64.b64encode(item.data).decode()}})
    return blocks or [{"type": "text", "text": "(no output)"}]


def direct(brief: Brief, model: str, max_turns: int) -> Run:
    """The agent loop: the skill as the system prompt, the brief as the task, the tools until it stops."""
    import anthropic

    client = anthropic.Anthropic()
    system = (SKILL / "SKILL.md").read_text(encoding="utf-8") + "\n\n" + (SKILL / "lessons.md").read_text(encoding="utf-8")
    task = (f"Brief ({brief.id}): {brief.text}\nFraming: {brief.framing}. Length: {brief.seconds:g} s. A fresh scene is open"
            + (f"; the voiceover says: “{brief.voiceover}” (its words are on the timeline)" if brief.voiceover else "")
            + ". Just build it (no need to share the shot list first). Finish with your three-line report.")
    messages: list[dict[str, Any]] = [{"role": "user", "content": task}]
    run = Run(brief)
    tools = tool_definitions()
    for _ in range(max_turns):
        response = client.messages.create(model=model, max_tokens=8000, system=system, tools=tools, messages=messages)
        messages.append({"role": "assistant", "content": response.content})
        uses = [block for block in response.content if block.type == "tool_use"]
        if not uses:
            run.final = "".join(block.text for block in response.content if block.type == "text")
            break
        results = []
        for use in uses:
            run.calls.append({"tool": use.name, "input": use.input})
            results.append({"type": "tool_result", "tool_use_id": use.id, "content": call_tool(use.name, use.input)})
        messages.append({"role": "user", "content": results})
    return run


def rescore(folder: pathlib.Path) -> list[dict[str, Any]]:
    rows = []
    for brief_folder in sorted(path for path in folder.iterdir() if path.is_dir()):
        observes = [{"report": json.loads(path.read_text(encoding="utf-8"))} for path in sorted(brief_folder.glob("observe-*.json"))]
        sheet_path = brief_folder / "contact-sheet.json"
        sheet = {"report": json.loads(sheet_path.read_text(encoding="utf-8"))} if sheet_path.exists() else None
        calls_path = brief_folder / "calls.json"
        calls = json.loads(calls_path.read_text(encoding="utf-8")) if calls_path.exists() else []
        rows.append({"brief": brief_folder.name, **score(observes, sheet), **process(calls)})
    return rows


def write(folder: pathlib.Path, rows: list[dict[str, Any]]) -> None:
    (folder / "results.md").write_text(table(rows), encoding="utf-8")
    (folder / "results.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the lowey skill's evals against 3D-lowey.")
    parser.add_argument("briefs", nargs="*", help="brief ids (all when none)")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--max-turns", type=int, default=40)
    parser.add_argument("--out", type=pathlib.Path, default=HERE / "runs" / dt.date.today().isoformat())
    parser.add_argument("--plan", action="store_true", help="check the bridge and list the briefs; no model calls")
    parser.add_argument("--score", type=pathlib.Path, help="re-score a saved run folder")
    options = parser.parse_args(argv)

    if options.score:
        rows = rescore(options.score)
        write(options.score, rows)
        print(table(rows))
        return 0
    briefs = parse_briefs((HERE / "briefs.md").read_text(encoding="utf-8"))
    if options.briefs:
        briefs = [brief for brief in briefs if brief.id in set(options.briefs)]
    from lowey_tools.client import Bridge, BridgeError

    try:
        bridge = Bridge()
        status = bridge.status()
    except BridgeError as error:
        print(f"Can't reach 3D-lowey: {error}", file=sys.stderr)
        return 1
    print(f"{status.get('device')} · {status.get('project')} · auto-apply {'on' if status.get('autoApply') else 'OFF (tap Apply on the iPad)'}")
    if options.plan:
        for brief in briefs:
            print(f"- {brief.id} ({brief.seconds:g} s, {brief.framing}{', voiceover' if brief.voiceover else ''}): {brief.text}")
        return 0
    options.out.mkdir(parents=True, exist_ok=True)
    rows = []
    for brief in briefs:
        folder = options.out / brief.id
        folder.mkdir(parents=True, exist_ok=True)
        print(f"▶ {brief.id}")
        prepare(bridge, brief)
        run = direct(brief, options.model, options.max_turns)
        (folder / "calls.json").write_text(json.dumps(run.calls, indent=2, ensure_ascii=False), encoding="utf-8")
        (folder / "report.md").write_text(run.final, encoding="utf-8")
        observes, sheet = measure(bridge, brief, folder)
        row = {"brief": brief.id, **score(observes, sheet), **process(run.calls)}
        rows.append(row)
        print(f"  {row['result']} · score {row['score']:.2f} · {row['proposals']} Proposal(s), {row['calls']} calls")
        write(options.out, rows)
    print(table(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
