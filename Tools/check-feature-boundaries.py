#!/usr/bin/env python3
"""Fails when one feature folder of LoweyFeatures uses a type declared in another.

Features talk through the Workspace (the shared session and Core types), never to each other. The Shell is the
composition root and may use every feature; the Workspace may use none.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Packages" / "LoweyFeatures" / "Sources" / "LoweyFeatures"
SHARED = "Workspace"
COMPOSITION = "Shell"
# Top-level, non-private declarations (nested and private types can't be used from another file anyway).
DECLARATION = re.compile(r"^(?:public |internal |final |@MainActor |@Observable )*"
                         r"(?:struct|class|enum|protocol|actor|typealias)\s+([A-Z][A-Za-z0-9_]*)", re.M)
STRINGS = re.compile(r'"(?:\\.|[^"\\])*"')
COMMENTS = re.compile(r"//.*?$", re.M)


def folder_of(path: Path) -> str:
    return path.relative_to(ROOT).parts[0]


def code(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'"""[\s\S]*?"""', '""', text)
    return COMMENTS.sub("", STRINGS.sub('""', text))


def main() -> int:
    files = sorted(ROOT.rglob("*.swift"))
    owners: dict[str, str] = {}
    for path in files:
        for name in DECLARATION.findall(path.read_text(encoding="utf-8")):
            owners.setdefault(name, folder_of(path))
    problems = []
    for path in files:
        folder = folder_of(path)
        if folder == COMPOSITION:
            continue
        body = code(path)
        for name, owner in owners.items():
            if owner in (folder, SHARED):
                continue
            if re.search(rf"\b{re.escape(name)}\b", body):
                problems.append(f"{path.relative_to(ROOT)} uses {name} from {owner}/")
    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} cross-feature reference(s). Move the shared piece into Workspace/ or compose in Shell/.")
        return 1
    print(f"Feature boundaries hold ({len(files)} files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
