#!/usr/bin/env bash
set -euo pipefail

milestone=${1:-}
if [[ "$milestone" != "gate-0" ]]; then
  echo "Usage: make device-smoke MILESTONE=gate-0" >&2
  exit 2
fi

cat documentation/developer/reference/gate-zero-device-checklist.md

if [[ -z "${RESULT:-}" ]]; then
  echo
  echo "Checklist printed. To record attended evidence, rerun with RESULT=pass|fail DEVICE_MODEL=... IOS_VERSION=..."
  exit 0
fi

if [[ "$RESULT" != "pass" && "$RESULT" != "fail" ]]; then
  echo "RESULT must be pass or fail." >&2
  exit 2
fi
: "${DEVICE_MODEL:?DEVICE_MODEL is required}"
: "${IOS_VERSION:?IOS_VERSION is required}"
if [[ "$RESULT" == "pass" ]]; then
  : "${MEASUREMENTS_FILE:?MEASUREMENTS_FILE is required for a passing release record}"
  python3 scripts/check-release-envelope.py "$MEASUREMENTS_FILE"
fi

mkdir -p evidence/device
python3 - "$RESULT" "$DEVICE_MODEL" "$IOS_VERSION" "${MEASUREMENTS_FILE:-}" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

result, device, ios, measurements_path = sys.argv[1:]
record = {
    "build": "gate-0",
    "deviceModel": device,
    "iOSVersion": ios,
    "milestone": "gate-0",
    "ownerDataAccepted": result == "pass",
    "recordedAt": datetime.now(timezone.utc).isoformat(),
    "result": result,
}
if measurements_path:
    record["measurements"] = json.loads(Path(measurements_path).read_text())
Path("evidence/device/gate-0.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
PY
echo "Privacy-safe attended result written to evidence/device/gate-0.json."
