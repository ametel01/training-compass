#!/usr/bin/env bash
set -euo pipefail

milestone=${1:-gate-0}
case "$milestone" in
  gate-0|health-foundation|unified-events|training-insights|recovery-evidence|personal-team-refresh) ;;
  *)
    echo "Usage: make verify-release MILESTONE=gate-0|health-foundation|unified-events|training-insights|recovery-evidence|personal-team-refresh" >&2
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
if milestone != "personal-team-refresh" and "measurements" not in record:
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
if milestone == "training-insights":
    checks = record.get("trainingInsightsChecks", {})
    required = {
        "explanationsReachable",
        "sourceSafeRecomputation",
        "neutralLanguage",
        "linkedSingleCount",
        "localAvailability",
        "performanceBudget",
        "priorDataContinuity",
    }
    if not all(checks.get(key) is True for key in required):
        raise SystemExit("Release verification refused: Training and Running Insights checks are incomplete.")
if milestone == "recovery-evidence":
    checks = record.get("recoveryEvidenceChecks", {})
    required = {
        "evidenceAvailable",
        "guidanceWithheld",
        "explanationsReachable",
        "neutralLanguage",
        "currentDayCorrectness",
        "resourceBudget",
        "priorDataContinuity",
        "privacy",
    }
    if not all(checks.get(key) is True for key in required):
        raise SystemExit("Release verification refused: Recovery Evidence and Guidance checks are incomplete.")
if milestone == "personal-team-refresh":
    checks = record.get("personalTeamRefreshChecks", {})
    required = {
        "stableIdentity",
        "preflight",
        "profileInspection",
        "inPlaceInstall",
        "launchSmokeTest",
        "dataContinuity",
        "privacy",
    }
    if not all(checks.get(key) is True for key in required):
        raise SystemExit("Release verification refused: Personal Team refresh checks are incomplete.")
    profile = record.get("profile", {})
    if not profile.get("creationDate") or profile.get("creationDate") == "not_recorded":
        raise SystemExit("Release verification refused: Personal Team profile creation date is missing.")
    if not profile.get("expirationDate") or profile.get("expirationDate") == "not_recorded":
        raise SystemExit("Release verification refused: Personal Team profile expiration date is missing.")
    if record.get("privacySafeNotes") != [
        "No credentials or device identifiers recorded.",
        "Existing app was updated in place.",
        "Owner confirmed important local data continuity.",
    ]:
        raise SystemExit("Release verification refused: Personal Team privacy-safe notes are missing.")
PY
echo "${milestone} release protocol passed."
