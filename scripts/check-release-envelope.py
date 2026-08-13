#!/usr/bin/env python3
"""Check privacy-safe Acceptance Device release measurements."""

from __future__ import annotations

import json
import sys
from pathlib import Path


LIMITS = {
    "coldLaunchP95Ms": ("<=", 1500),
    "foregroundResumeP95Ms": ("<=", 500),
    "localMutationP95Ms": ("<=", 150),
    "ordinaryQueryP95Ms": ("<=", 300),
    "insightP95Ms": ("<=", 750),
    "foregroundPeakMiB": ("<=", 250),
    "backgroundPeakMiB": ("<=", 100),
    "combinedStoresGiB": ("<=", 2),
    "authoritativeStoreMiB": ("<=", 250),
    "routeGeometryMiB": ("<=", 100),
    "authoritativeMigrationP95S": ("<=", 15),
    "reconstructibleMigrationP95S": ("<=", 60),
    "exportImportStagingP95S": ("<=", 30),
    "backgroundSliceS": ("<=", 20),
    "storageAvailableMiB": (">=", 500),
}


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check-release-envelope.py MEASUREMENTS.json", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        values = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read release measurements: {error}", file=sys.stderr)
        return 1
    if not isinstance(values, dict):
        print("Release measurements must be a JSON object", file=sys.stderr)
        return 1

    errors: list[str] = []
    for key, (operator, limit) in LIMITS.items():
        value = values.get(key)
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            errors.append(f"{key} must be numeric")
            continue
        if (operator == "<=" and value > limit) or (operator == ">=" and value < limit):
            errors.append(f"{key}={value} violates {operator} {limit}")
    if values.get("interruptionRecovery") is not True:
        errors.append("interruptionRecovery must be true")
    if errors:
        print("Release envelope check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Release envelope measurements pass.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
