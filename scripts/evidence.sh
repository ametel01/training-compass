#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import hashlib
import json
import os
import platform
import subprocess
from pathlib import Path

def output(*command: str) -> str:
    return subprocess.check_output(command, text=True).strip()

def sha256(path: str) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def automated_verdict(name: str) -> str:
    value = os.environ.get(name, "not_run")
    if value not in {"pass", "fail", "not_run"}:
        raise SystemExit(f"{name} must be pass, fail, or not_run")
    return value

dependency_graph = json.loads(output("swift", "package", "show-dependencies", "--format", "json"))
device_path = Path("evidence/device/gate-0.json")
device_evidence = json.loads(device_path.read_text()) if device_path.exists() else {
    "result": "missing",
    "requiredCommand": "make device-smoke MILESTONE=gate-0",
}
entitlements = [str(path) for path in Path(".").rglob("*.entitlements") if ".build" not in path.parts]
record = {
    "commands": [
        "make bootstrap",
        "make verify",
        "make test-ui",
        "make fixtures",
        "make verify-migrations",
        "make device-smoke MILESTONE=gate-0",
        "make verify-release",
        "make evidence",
    ],
    "fixtureSeed": 21571,
    "gitRevision": output("git", "rev-parse", "HEAD"),
    "artifacts": {
        "acceptanceMatrix": "documentation/developer/reference/acceptance-matrix.md",
        "deviceEvidence": device_evidence,
        "dependencyGraph": dependency_graph,
        "entitlements": entitlements,
        "fileAttributeVerification": device_evidence.get("result", "missing"),
        "loggingAllowlist": ["pre_data_stores_ready", "pre_data_stores_failed"],
        "migrationVerification": automated_verdict("MIGRATION_RESULT"),
        "privacyManifest": {
            "path": "TrainingCompassApp/Resources/PrivacyInfo.xcprivacy",
            "sha256": sha256("TrainingCompassApp/Resources/PrivacyInfo.xcprivacy"),
        },
        "privacyVerification": automated_verdict("PRIVACY_RESULT"),
    },
    "ownerDataAccepted": False,
    "platform": platform.platform(),
    "rawMeasurements": [],
    "swiftVersion": output("swift", "--version").splitlines()[0],
    "verdicts": {
        "automatedChangeGate": automated_verdict("VERIFY_RESULT"),
        "migrationGate": automated_verdict("MIGRATION_RESULT"),
        "privacyGate": automated_verdict("PRIVACY_RESULT"),
        "releaseGate": "blocked" if device_evidence.get("result") != "pass" else "eligible",
        "uiGate": automated_verdict("UI_RESULT"),
    },
    "waivers": [],
}
encoded = json.dumps(record, indent=2, sort_keys=True) + "\n"
path = Path("evidence/gate-zero-environment.json")
path.write_text(encoded)
print(path)
PY
