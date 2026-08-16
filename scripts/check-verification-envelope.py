#!/usr/bin/env python3
"""Validate the deterministic, privacy-safe Verification Data Envelope."""

from __future__ import annotations

import json
import sys
from pathlib import Path


EXPECTED = {
    "schemaVersion": 1,
    "algorithmVersion": "verification-envelope-lcg-v1",
    "ownerDataAccepted": False,
    "timeZoneIdentifier": "Etc/UTC",
    "coverageYears": 15,
    "healthWorkouts": 25_000,
    "heartRateSamples": 10_000_000,
    "sleepIntervals": 250_000,
    "restingHeartRateSamples": 50_000,
    "hrvSamples": 100_000,
    "trainingCycles": 500,
    "sessions": 10_000,
    "sets": 250_000,
    "routes": 2_000,
    "routeRetainedPoints": 2_000,
}
ALLOWED_KEYS = set(EXPECTED) | {"seed", "referenceDate", "identifierSamples"}
FORBIDDEN_TERMS = (
    "latitude",
    "longitude",
    "routePoint",
    "rawMeasurement",
    "freeText",
    "healthKitUUID",
    "workoutDate",
    "ownerMeasurement",
)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check-verification-envelope.py FIXTURE.json", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read verification envelope: {error}", file=sys.stderr)
        return 1
    if not isinstance(value, dict):
        print("Verification envelope must be a JSON object", file=sys.stderr)
        return 1

    errors: list[str] = []
    unexpected = sorted(set(value) - ALLOWED_KEYS)
    if unexpected:
        errors.append(f"unexpected fields: {unexpected}")
    for key, expected in EXPECTED.items():
        if value.get(key) != expected:
            errors.append(f"{key} must equal {expected!r}")
    if not isinstance(value.get("seed"), int) or isinstance(value.get("seed"), bool):
        errors.append("seed must be an integer")
    if not isinstance(value.get("referenceDate"), str) or not value["referenceDate"].endswith("Z"):
        errors.append("referenceDate must be an ISO-8601 UTC string")
    identifiers = value.get("identifierSamples")
    if not isinstance(identifiers, list) or len(identifiers) != 4:
        errors.append("identifierSamples must contain four deterministic samples")
    elif not all(isinstance(item, str) for item in identifiers):
        errors.append("identifierSamples must contain unique strings")
    elif len(set(identifiers)) != len(identifiers):
        errors.append("identifierSamples must contain unique strings")

    encoded = json.dumps(value, sort_keys=True).lower()
    for term in FORBIDDEN_TERMS:
        if term.lower() in encoded:
            errors.append(f"forbidden sensitive field or payload: {term}")
    if errors:
        print("Verification envelope check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Verification Data Envelope is deterministic, complete, and privacy-safe.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
