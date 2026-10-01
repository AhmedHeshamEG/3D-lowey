"""Builds Packages/LoweyCore/Sources/LoweyCore/Resources/visemes.txt from the CMU Pronouncing Dictionary.

Each line: `word visemes` — one character per phoneme, Rhubarb / Preston Blair mouth shapes:
  A closed (M B P)      B teeth (most consonants, EE)   C open (EH, AE, AH)   D wide (AA, AY, AW)
  E rounded (AO, ER)    F puckered (OO, OW, W)          G lip bite (F, V)     H tongue (L)
Vowels are lower-case (they get more time than consonants when a word is spread over its duration).

Usage: python Tools/make_visemes.py cmudict.dict
CMUdict: https://github.com/cmusphinx/cmudict (BSD 2-clause, see THIRD_PARTY.md).
"""
import re
import sys

VOWELS = {
    "AA": "d", "AE": "c", "AH": "c", "AO": "e", "AW": "d", "AY": "d", "EH": "c", "ER": "e", "EY": "c",
    "IH": "b", "IY": "b", "OW": "f", "OY": "e", "UH": "f", "UW": "f",
}
CONSONANTS = {
    "B": "A", "M": "A", "P": "A", "F": "G", "V": "G", "L": "H", "W": "F", "R": "B",
    "CH": "B", "JH": "B", "SH": "B", "ZH": "B", "D": "B", "T": "B", "N": "B", "S": "B", "Z": "B",
    "K": "B", "G": "B", "NG": "B", "HH": "C", "Y": "B", "TH": "B", "DH": "B",
}


def main(path, out):
    seen = set()
    lines = []
    with open(path, encoding="utf-8") as source:
        for raw in source:
            raw = raw.split("#")[0].strip()
            if not raw:
                continue
            word, *phones = raw.split()
            if "(" in word or word in seen or not re.fullmatch(r"[a-z']{1,20}", word):
                continue
            visemes = []
            for phone in phones:
                base = re.sub(r"\d", "", phone)
                visemes.append(VOWELS.get(base) or CONSONANTS.get(base) or "B")
            seen.add(word)
            lines.append(f"{word} {''.join(visemes)}")
    lines.sort()
    with open(out, "w", encoding="utf-8", newline="\n") as target:
        target.write("\n".join(lines) + "\n")
    print(f"{len(lines)} words")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "Packages/LoweyCore/Sources/LoweyCore/Resources/visemes.txt")
