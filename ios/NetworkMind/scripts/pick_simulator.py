#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator on the newest installed iOS runtime.

Used by CI so the workflow doesn't hard-code a device name that may not exist on the
runner image. Reads `xcrun simctl list devices available -j` from stdin.
"""
import json
import re
import sys


def runtime_version(key: str) -> tuple:
    # e.g. "com.apple.CoreSimulator.SimRuntime.iOS-18-5" -> (18, 5)
    match = re.search(r"iOS-(\d+)(?:-(\d+))?", key)
    if not match:
        return ()
    return tuple(int(part) for part in match.groups() if part is not None)


def main() -> int:
    devices = json.load(sys.stdin)["devices"]
    candidates = []
    for runtime, entries in devices.items():
        version = runtime_version(runtime)
        if not version or version < (17,):
            continue
        for device in entries:
            if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
                candidates.append((version, device["name"], device["udid"]))
    if not candidates:
        print("No available iPhone simulator with iOS 17+", file=sys.stderr)
        return 1
    candidates.sort()
    version, name, udid = candidates[-1]
    print(f"Using {name} (iOS {'.'.join(map(str, version))})", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
