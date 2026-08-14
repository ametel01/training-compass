#!/usr/bin/env bash
set -euo pipefail

milestone=${1:-}
if [[ "$milestone" != "gate-0" && "$milestone" != "health-foundation" ]]; then
  echo "Usage: make device-smoke MILESTONE=gate-0|health-foundation" >&2
  exit 2
fi

checklist="documentation/developer/reference/gate-zero-device-checklist.md"
evidence_name="gate-0"
if [[ "$milestone" == "health-foundation" ]]; then
  checklist="documentation/developer/reference/health-foundation-device-checklist.md"
  evidence_name="health-foundation"
fi
cat "$checklist"

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
  if [[ "$milestone" == "health-foundation" ]]; then
    for check in \
      HEALTH_AUTHORIZATION \
      HEALTH_ANCHORED_QUERIES \
      HEALTH_OBSERVER_REGISTRATION \
      HEALTH_FOREGROUND_REFRESH \
      HEALTH_LOCK_UNLOCK_RECOVERY \
      HEALTH_PROTECTED_STORAGE \
      HEALTH_BACKUP_EXCLUSION; do
      value=${!check:?$check is required for a passing Health foundation record}
      [[ "$value" == "true" ]] || {
        echo "$check must be true for a passing Health foundation record." >&2
        exit 2
      }
    done
  fi
fi

mkdir -p evidence/device
python3 - "$RESULT" "$DEVICE_MODEL" "$IOS_VERSION" "${MEASUREMENTS_FILE:-}" "$milestone" "$evidence_name" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

result, device, ios, measurements_path, milestone, evidence_name = sys.argv[1:]
record = {
    "build": evidence_name,
    "deviceModel": device,
    "iOSVersion": ios,
    "milestone": milestone,
    "ownerDataAccepted": result == "pass",
    "recordedAt": datetime.now(timezone.utc).isoformat(),
    "result": result,
}
if measurements_path:
    record["measurements"] = json.loads(Path(measurements_path).read_text())
if milestone == "health-foundation":
    record["healthChecks"] = {
        "authorization": os.environ.get("HEALTH_AUTHORIZATION") == "true",
        "anchoredQueries": os.environ.get("HEALTH_ANCHORED_QUERIES") == "true",
        "observerRegistration": os.environ.get("HEALTH_OBSERVER_REGISTRATION") == "true",
        "foregroundRefresh": os.environ.get("HEALTH_FOREGROUND_REFRESH") == "true",
        "lockUnlockRecovery": os.environ.get("HEALTH_LOCK_UNLOCK_RECOVERY") == "true",
        "protectedStorage": os.environ.get("HEALTH_PROTECTED_STORAGE") == "true",
        "backupExclusion": os.environ.get("HEALTH_BACKUP_EXCLUSION") == "true",
    }
Path(f"evidence/device/{evidence_name}.json").write_text(
    json.dumps(record, indent=2, sort_keys=True) + "\n"
)
PY
echo "Privacy-safe attended result written to evidence/device/${evidence_name}.json."
