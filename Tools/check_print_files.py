#!/usr/bin/env python3
"""Checks Maquette's print exports the way a slicer would: closed, consistently wound, enclosing a volume.

Usage: python Tools/check_print_files.py <folder with .stl / .3mf files>
CI runs it on the files LoweyCore's tests write (ACCEPTANCE_DIR): M4's acceptance, "an exported STL of the M3 block
opens watertight in a slicer check".
"""
import pathlib
import sys

import trimesh

EXPECTED_MM = (40.0, 20.0, 10.0)


def main() -> int:
    folder = pathlib.Path(sys.argv[1])
    files = sorted(list(folder.glob("*.stl")) + list(folder.glob("*.3mf")))
    if not files:
        print(f"No print files in {folder}")
        return 1
    failed = False
    for path in files:
        mesh = trimesh.load(path, force="mesh")
        checks = {
            "watertight": mesh.is_watertight,
            "consistent winding": mesh.is_winding_consistent,
            "encloses a volume": mesh.is_volume,
        }
        if path.stem == "m3-block":
            # Millimetres, standing on the bed (the block's 10 mm height is the printer's Z).
            checks["40 x 20 x 10 mm, Z up"] = all(abs(a - b) < 1e-3 for a, b in zip(mesh.extents, EXPECTED_MM))
        for name, ok in checks.items():
            print(f"{'ok  ' if ok else 'FAIL'} {path.name}: {name}")
            failed |= not ok
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
