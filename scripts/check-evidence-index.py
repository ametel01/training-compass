#!/usr/bin/env python3
"""Validate the optional, ignored release evidence index without owner data."""

from __future__ import annotations

import json
from pathlib import Path
import sys


PATH = Path("evidence/gate-zero-environment.json")
REQUIRED_TOP_LEVEL = {
    "schemaVersion",
    "gitRevision",
    "commands",
    "commandRevisions",
    "environment",
    "fixtureSeed",
    "algorithmVersions",
    "artifacts",
    "compatibility",
    "rawMeasurements",
    "verdicts",
    "releaseVerdict",
    "waivers",
}
REQUIRED_ARTIFACT_PATHS = (
    "documentation/developer/reference/acceptance-matrix.md",
    "documentation/developer/reference/release-candidate-checklist.md",
    "documentation/developer/reference/migration-compatibility.md",
    "documentation/developer/reference/evidence-index.md",
    "documentation/developer/how-to-guides/record-release-evidence.md",
    "documentation/developer/reference/final-release-checklist.md",
    "documentation/developer/reference/healthkit-write-back-device-checklist.md",
    "TrainingCompassApp/Resources/PrivacyInfo.xcprivacy",
)
FORBIDDEN_TERMS = {
    "latitude",
    "longitude",
    "routepoint",
    "rawmeasurement",
    "freetext",
    "healthkituuid",
    "workoutdate",
    "ownermeasurement",
    "password",
    "recordedat",
    "creationdate",
    "expirationdate",
    "privacysafenotes",
    "profile",
}


def walk(value: object, path: str = "") -> list[str]:
    errors: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = str(key).lower()
            if lowered in FORBIDDEN_TERMS:
                errors.append(f"forbidden evidence field: {path}.{key}")
            errors.extend(walk(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(walk(child, f"{path}[{index}]"))
    elif isinstance(value, str):
        lowered = value.lower()
        for term in FORBIDDEN_TERMS:
            if term in lowered:
                errors.append(f"forbidden evidence value: {path}")
                break
    return errors


def main() -> int:
    if not PATH.exists():
        print("Evidence index not present; attended evidence has not been recorded.")
        return 0
    try:
        value = json.loads(PATH.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"Evidence index is not valid JSON: {error}", file=sys.stderr)
        return 1
    if not isinstance(value, dict):
        print("Evidence index must be a JSON object.", file=sys.stderr)
        return 1

    errors = []
    missing = REQUIRED_TOP_LEVEL - set(value)
    if missing:
        errors.append(f"evidence index is missing fields: {sorted(missing)}")
    errors.extend(walk(value))
    for artifact_path in REQUIRED_ARTIFACT_PATHS:
        if not Path(artifact_path).is_file():
            errors.append(f"required evidence artifact is missing: {artifact_path}")
    graph = value.get("artifacts", {}).get("dependencyGraph", {})
    graph_text = json.dumps(graph)
    if '"path"' in graph_text or '"url"' in graph_text:
        errors.append("dependency graph must not retain checkout paths or URLs")
    entitlements = value.get("artifacts", {}).get("entitlements", [])
    if not isinstance(entitlements, list) or not entitlements:
        errors.append("evidence index must include entitlement metadata")
    for entitlement in entitlements:
        if entitlement.get("keys") != ["com.apple.developer.healthkit"]:
            errors.append("entitlements must contain only the reviewed HealthKit capability")
    release_verdict = value.get("releaseVerdict")
    if not isinstance(release_verdict, dict):
        errors.append("releaseVerdict must be an object")
    else:
        if release_verdict.get("milestone") != 6:
            errors.append("releaseVerdict.milestone must be 6")
        if release_verdict.get("status") not in {"blocked", "eligible"}:
            errors.append("releaseVerdict.status must be blocked or eligible")
        required_milestones = [
            "gate-0",
            "health-foundation",
            "unified-events",
            "training-insights",
            "recovery-evidence",
            "personal-team-refresh",
        ]
        if release_verdict.get("requiredMilestones") != required_milestones:
            errors.append("releaseVerdict.requiredMilestones is incomplete")
        accepted = release_verdict.get("acceptedMilestones")
        if not isinstance(accepted, list) or any(item not in required_milestones for item in accepted):
            errors.append("releaseVerdict.acceptedMilestones is invalid")
        if not isinstance(release_verdict.get("writeBackEvidence"), bool):
            errors.append("releaseVerdict.writeBackEvidence must be boolean")
        if release_verdict.get("gitRevision") != value.get("gitRevision"):
            errors.append("releaseVerdict.gitRevision must match gitRevision")
    if errors:
        print("Evidence index check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Evidence index is complete and privacy-safe.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
