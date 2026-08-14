#!/usr/bin/env bash
set -euo pipefail

milestone=${1:-gate-0}
case "$milestone" in
  gate-0|health-foundation|unified-events) ;;
  *)
    echo "Usage: make verify-release MILESTONE=gate-0|health-foundation|unified-events" >&2
    exit 2
    ;;
esac

./scripts/verify.sh
./scripts/test-ui.sh

evidence_path="evidence/device/${milestone}.json"
if [[ ! -f "$evidence_path" ]]; then
  echo "Release verification refused: ${milestone} Acceptance Device evidence is missing." >&2
  exit 1
fi
python3 - "$evidence_path" "$milestone" <<'PY'
import json
import sys
from pathlib import Path

path, milestone = sys.argv[1:]
record = json.loads(Path(path).read_text())
if record.get("result") != "pass":
    raise SystemExit("Release verification refused: device evidence is not passing.")
if "measurements" not in record:
    raise SystemExit("Release verification refused: release measurements are missing.")
if milestone == "gate-0" and record.get("ownerDataAccepted") is not True:
    raise SystemExit("Release verification refused: owner-data approval is missing.")
if milestone == "health-foundation":
    checks = record.get("healthChecks", {})
    required = {
        "authorization",
        "anchoredQueries",
        "observerRegistration",
        "foregroundRefresh",
        "lockUnlockRecovery",
        "protectedStorage",
        "backupExclusion",
    }
    if not all(checks.get(key) is True for key in required):
        raise SystemExit("Release verification refused: Health foundation checks are incomplete.")
if milestone == "unified-events":
    checks = record.get("unifiedEventChecks", {})
    route_result = checks.get("routeOnDemand")
    required = {
        "priorDataContinuity",
        "linkedSingleCount",
        "sourceDetail",
        "lateOrUnavailableEnrichment",
        "exactUUIDRecovery",
        "explicitUnlink",
        "localAvailability",
        "privacy",
        "unfinishedInsightsHidden",
    }
    if (
        not all(checks.get(key) is True for key in required)
        or route_result not in {"verified", "notAvailable"}
    ):
        raise SystemExit("Release verification refused: Unified Events checks are incomplete.")
PY
echo "${milestone} release protocol passed."
