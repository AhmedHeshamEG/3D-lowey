"""The String Catalog (App/Resources/Localizable.xcstrings): English source, Italian and Arabic at 2.0.

    python Tools/strings.py extract          # add every chrome string in the code to the catalog (new ones untranslated)
    python Tools/strings.py check            # CI: every string in the code is in the catalog, translated to it and ar
    python Tools/strings.py merge it.json ar.json   # write translations ({english: translation}) into the catalog
    python Tools/strings.py missing it       # what still needs an Italian (or ar) translation, as JSON

Chrome strings are found where the code shows text: string literals given to SwiftUI views and to the hmm. design
components (Text, Button, Label, Toggle, HmmPillButton, HmmSectionHeader, Hint…), toasts (`app.show`), accessibility
labels, and the titles that enums return for display (`var title`, `displayName`, `label`, `reason`, …). Strings with
interpolation are keyed the way SwiftUI keys them (`%lld` for integers, `%@` for the rest); they are translated like the rest.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "Resources" / "Localizable.xcstrings"
LANGUAGES = ["it", "ar"]
SOURCES = [ROOT / "Packages" / "LoweyFeatures" / "Sources", ROOT / "App" / "Sources", ROOT / "Packages" / "HmmKit" / "Sources" / "HmmDesign",
           ROOT / "Packages" / "HmmKit" / "Sources" / "HmmDocuments", ROOT / "Packages" / "HmmKit" / "Sources" / "HmmBridge"]
# Display names that live in Core (enum titles the app shows).
CORE_TITLES = ROOT / "Packages" / "LoweyCore" / "Sources"

CALLS = ["Text", "Button", "Label", "Toggle", "Picker", "Menu", "Section", "TextField", "SecureField", "HmmPillButton", "HmmSectionHeader",
         "HmmPanel", "HmmSheet", "HmmSidebarSlider", "HmmEmptyState", "Hint", "LabeledSlider", "ControlGroup", "Link", "Stepper",
         "navigationTitle", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "help", "confirmationDialog", "alert", "show",
         "ShareLink", "PanelSection", "ContentUnavailableView", "LabeledContent", "GroupBox", "DisclosureGroup", "Tab",
         # The panels' own slider helpers (`slider("Volume", …)`).
         "slider"]
# A literal right after one of the calls (first argument), or after a display keyword argument.
CALL_LITERAL = re.compile(r"\b(?:" + "|".join(CALLS) + r")\(\s*\"((?:[^\"\\]|\\.)*)\"")
KEYWORD_LITERAL = re.compile(r"\b(?:title|label|message|subtitle|text|hint|prompt|actionTitle|placeholder|caption|summary|reason):\s*\"((?:[^\"\\]|\\.)*)\"")
TITLE_BLOCK = re.compile(r"\bvar (?:title|displayName|label|reason|subtitle|hint|summary|caption|explanation)\s*:\s*String\s*\{")
LITERAL = re.compile(r"\"((?:[^\"\\]|\\.)*)\"")
# Not text for people: identifiers, symbol names, file names, keys, formats.
INTERPOLATION = re.compile(r"\\\(((?:[^()]|\([^()]*\))*)\)")
# Interpolations of integers: SwiftUI and String.LocalizationValue key them as %lld, everything else as %@.
NUMERIC = re.compile(r"(^|\.)(count|placed|accentCount|hold|onionAfter|onionBefore|segments)$|^Int\(|^\$0$|\+ 1$|\.count - \d+$")
NOT_TEXT = re.compile(r"^([a-z0-9]+([.\-_][a-z0-9]+)+|[a-z]+[A-Z][A-Za-z0-9]*|[A-Z_]+|#?[0-9A-Fa-f]{6,8}|%[^ ]*|[\W\d_]*)$")


def key_for(literal: str) -> str | None:
    """The catalog key SwiftUI uses for a literal: interpolations become %@ (a fallback that matches any argument)."""
    text = literal.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\u" in literal else literal
    text = INTERPOLATION.sub(lambda match: "%lld" if NUMERIC.search(match.group(1)) else "%@", text)
    text = text.replace('\\"', '"').replace("\\n", "\n")
    # A literal cut short by quotes inside an interpolation isn't a whole string: skip it.
    if "\\(" in text or text.startswith(")") or text.count('"') % 2:
        return None
    if not re.search(r"[A-Za-z]{2}", text) or NOT_TEXT.match(text) or re.match(r"^[A-Z]{2,}[a-z]\w*$", text):
        return None
    return text


def title_literals(text: str) -> list[str]:
    """String literals returned by display-title computed properties (`var title: String { switch self { case …: "…" } }`)."""
    found = []
    for match in TITLE_BLOCK.finditer(text):
        depth = 0
        index = match.end() - 1
        while index < len(text):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        found += LITERAL.findall(text[match.end():index])
    return found


def extract() -> set[str]:
    keys: set[str] = set()
    for folder in SOURCES:
        for path in folder.rglob("*.swift"):
            text = path.read_text(encoding="utf-8")
            for literal in CALL_LITERAL.findall(text) + KEYWORD_LITERAL.findall(text) + title_literals(text):
                key = key_for(literal)
                if key:
                    keys.add(key)
    for path in CORE_TITLES.rglob("*.swift"):
        for literal in title_literals(path.read_text(encoding="utf-8")):
            key = key_for(literal)
            if key:
                keys.add(key)
    return keys


def load() -> dict:
    if CATALOG.exists():
        return json.loads(CATALOG.read_text(encoding="utf-8"))
    return {"sourceLanguage": "en", "strings": {}, "version": "1.0"}


def save(catalog: dict) -> None:
    catalog["strings"] = dict(sorted(catalog["strings"].items(), key=lambda item: item[0].lower()))
    CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def translated(entry: dict, language: str) -> str | None:
    unit = ((entry.get("localizations") or {}).get(language) or {}).get("stringUnit") or {}
    return unit.get("value") if unit.get("state") == "translated" and unit.get("value") else None


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "check"
    catalog = load()
    strings = catalog["strings"]
    if command == "extract":
        added = 0
        for key in sorted(extract()):
            if key not in strings:
                strings[key] = {}
                added += 1
        save(catalog)
        print(f"{added} new strings; {len(strings)} in the catalog.")
        return 0
    if command == "merge":
        for path in argv[2:]:
            language = pathlib.Path(path).stem
            for key, value in json.loads(pathlib.Path(path).read_text(encoding="utf-8")).items():
                entry = strings.setdefault(key, {})
                entry.setdefault("localizations", {})[language] = {"stringUnit": {"state": "translated", "value": value}}
        save(catalog)
        print(f"Merged {', '.join(argv[2:])}.")
        return 0
    if command == "missing":
        language = argv[2]
        print(json.dumps({key: "" for key in sorted(strings) if not translated(strings[key], language)}, indent=1, ensure_ascii=False))
        return 0
    # check
    problems = []
    absent = sorted(extract() - set(strings))
    if absent:
        problems.append(f"{len(absent)} strings in the code aren't in the catalog (run python Tools/strings.py extract), e.g. {absent[:5]}")
    for language in LANGUAGES:
        untranslated = [key for key in strings if not translated(strings[key], language)]
        if untranslated:
            problems.append(f"{len(untranslated)} strings have no {language} translation, e.g. {untranslated[:5]}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"String Catalog complete: {len(strings)} strings in en, {', '.join(LANGUAGES)}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
