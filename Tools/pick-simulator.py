#!/usr/bin/env python3
"""Prints the UDID of the newest available iPad simulator (iPad Air 13" preferred), or with --iphone the largest
iPhone (6.9", Pro Max preferred). Used by CI."""
import json
import subprocess
import sys

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
WANT_PHONE = "--iphone" in sys.argv
best = None
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split("iOS-")[-1].split("-"))
    for device in entries:
        if WANT_PHONE:
            if "iPhone" not in device["name"]:
                continue
            score = (version, "Pro Max" in device["name"], "Plus" in device["name"] or "Air" in device["name"])
        elif "iPad" not in device["name"]:
            continue
        else:
            score = (version, "iPad Air 13" in device["name"], "iPad Air" in device["name"])
        if best is None or score > best[0]:
            best = (score, device["udid"], device["name"])
if best is None:
    sys.exit("No iPhone simulator available" if WANT_PHONE else "No iPad simulator available")
print(best[2], file=sys.stderr)
print(best[1])
