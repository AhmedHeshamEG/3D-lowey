"""Writes skills/lowey/reference/tools.md from the MCP server's own tool schemas (hmm-bridge's 16 tools).

The skill's tool reference is generated, never hand-written, so it can't drift from the server. Needs the laptop
package installed (`pip install -e Tools/lowey`). `--check` (CI) fails when the file on disk is out of date.
"""
from __future__ import annotations

import asyncio
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = ROOT / "skills" / "lowey" / "reference" / "tools.md"
sys.path.insert(0, str(ROOT / "Tools" / "lowey"))


def type_name(schema: dict) -> str:
    """A short type for a JSON schema property."""
    if "anyOf" in schema:
        names = [type_name(option) for option in schema["anyOf"]]
        # "or", not "|": these go in Markdown table cells.
        return " or ".join(dict.fromkeys(name for name in names if name != "null")) + (" or null" if "null" in names else "")
    kind = schema.get("type")
    if kind == "array":
        return f"list[{type_name(schema.get('items', {}))}]"
    if kind == "object":
        return "object"
    return kind or "any"


def schema_of(tool) -> dict:
    """A tool's input schema (the SDK renamed the field between 1.x and 2.x)."""
    return getattr(tool, "input_schema", None) or getattr(tool, "inputSchema", None) or {}


def render(tools: list) -> str:
    lines = [
        "# Tools (generated)",
        "",
        "Generated from the `lowey` MCP server by `Tools/gen-skill-tools.py` — don't edit by hand. "
        f"{len(tools)} tools; everything that changes the scene goes through `build` (Scene Script v3, one Proposal, one undo step).",
        "",
    ]
    for tool in tools:
        lines += [f"## `{tool.name}`", "", " ".join((tool.description or "").split()), ""]
        properties = schema_of(tool).get("properties", {})
        required = set(schema_of(tool).get("required", []))
        if properties:
            lines += ["| Parameter | Type | Default |", "|---|---|---|"]
            for name, schema in properties.items():
                default = "required" if name in required else f"`{json.dumps(schema.get('default'), ensure_ascii=False)}`"
                lines.append(f"| `{name}` | {type_name(schema)} | {default} |")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    from lowey_tools import mcp_server

    tools = asyncio.run(mcp_server.mcp.list_tools())
    text = render(tools)
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != text:
            print("skills/lowey/reference/tools.md is out of date: run python Tools/gen-skill-tools.py", file=sys.stderr)
            return 1
        print(f"Skill tool reference is up to date ({len(tools)} tools).")
        return 0
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(text, encoding="utf-8", newline="\n")
    print(f"Wrote {TARGET.relative_to(ROOT)} ({len(tools)} tools).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
