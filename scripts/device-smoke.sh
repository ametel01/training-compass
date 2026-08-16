#!/usr/bin/env bash
set -euo pipefail

milestone=${1:-}
if [[ "$milestone" != "gate-0" && "$milestone" != "health-foundation" && "$milestone" != "unified-events" && "$milestone" != "training-insights" && "$milestone" != "recovery-evidence" && "$milestone" != "personal-team-refresh" ]]; then
  echo "Usage: make device-smoke MILESTONE=gate-0|health-foundation|unified-events|training-insights|recovery-evidence|personal-team-refresh" >&2
  exit 2
fi

checklist="documentation/developer/reference/gate-zero-device-checklist.md"
evidence_name="gate-0"
if [[ "$milestone" == "health-foundation" ]]; then
  checklist="documentation/developer/reference/health-foundation-device-checklist.md"
  evidence_name="health-foundation"
fi
if [[ "$milestone" == "unified-events" ]]; then
  checklist="documentation/developer/reference/unified-events-device-checklist.md"
  evidence_name="unified-events"
fi
if [[ "$milestone" == "training-insights" ]]; then
  checklist="documentation/developer/reference/training-insights-device-checklist.md"
  evidence_name="training-insights"
fi
if [[ "$milestone" == "recovery-evidence" ]]; then
  checklist="documentation/developer/reference/recovery-evidence-device-checklist.md"
  evidence_name="recovery-evidence"
fi
if [[ "$milestone" == "personal-team-refresh" ]]; then
  checklist="documentation/developer/reference/personal-team-refresh-device-checklist.md"
  evidence_name="personal-team-refresh"
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
  if [[ "$milestone" != "personal-team-refresh" ]]; then
    : "${MEASUREMENTS_FILE:?MEASUREMENTS_FILE is required for a passing release record}"
    if [[ "$milestone" == "unified-events" && "${UNIFIED_ROUTE_ON_DEMAND:-}" == "not_available" ]]; then
      python3 scripts/check-release-envelope.py "$MEASUREMENTS_FILE" --route-not-available
    else
      python3 scripts/check-release-envelope.py "$MEASUREMENTS_FILE"
    fi
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
if milestone == "personal-team-refresh":
    creation_date = os.environ.get("PERSONAL_TEAM_PROFILE_CREATION_DATE", "")
    expiration_date = os.environ.get("PERSONAL_TEAM_PROFILE_EXPIRATION_DATE", "")
    if result == "pass" and (not creation_date or not expiration_date):
        raise SystemExit(
            "PERSONAL_TEAM_PROFILE_CREATION_DATE and PERSONAL_TEAM_PROFILE_EXPIRATION_DATE "
            "are required for a passing personal-team-refresh record"
        )
    record["profile"] = {
        "creationDate": creation_date or "not_recorded",
        "expirationDate": expiration_date or "not_recorded",
        "kind": "Personal Team development profile",
    }
    record["privacySafeNotes"] = [
        "No credentials or device identifiers recorded.",
        "Existing app was updated in place.",
        "Owner confirmed important local data continuity.",
    ]
check_schemas = {
    "health-foundation": (
        "healthChecks",
        {
            "HEALTH_AUTHORIZATION": "authorization",
            "HEALTH_ANCHORED_QUERIES": "anchoredQueries",
            "HEALTH_OBSERVER_REGISTRATION": "observerRegistration",
            "HEALTH_FOREGROUND_REFRESH": "foregroundRefresh",
            "HEALTH_LOCK_UNLOCK_RECOVERY": "lockUnlockRecovery",
            "HEALTH_PROTECTED_STORAGE": "protectedStorage",
            "HEALTH_BACKUP_EXCLUSION": "backupExclusion",
        },
    ),
    "unified-events": (
        "unifiedEventChecks",
        {
            "UNIFIED_PRIOR_DATA": "priorDataContinuity",
            "UNIFIED_LINKED_EVENT": "linkedSingleCount",
            "UNIFIED_SOURCE_DETAIL": "sourceDetail",
            "UNIFIED_ENRICHMENT": "lateOrUnavailableEnrichment",
            "UNIFIED_EXACT_UUID_RECOVERY": "exactUUIDRecovery",
            "UNIFIED_UNLINK": "explicitUnlink",
            "UNIFIED_LOCAL_AVAILABILITY": "localAvailability",
            "UNIFIED_PRIVACY": "privacy",
            "UNIFIED_INSIGHTS_HIDDEN": "unfinishedInsightsHidden",
        },
    ),
    "training-insights": (
        "trainingInsightsChecks",
        {
            "INSIGHTS_EXPLANATIONS": "explanationsReachable",
            "INSIGHTS_RECOMPUTATION": "sourceSafeRecomputation",
            "INSIGHTS_NEUTRAL_LANGUAGE": "neutralLanguage",
            "INSIGHTS_SINGLE_COUNT": "linkedSingleCount",
            "INSIGHTS_LOCAL_AVAILABILITY": "localAvailability",
            "INSIGHTS_PERFORMANCE_BUDGET": "performanceBudget",
            "INSIGHTS_PRIOR_DATA": "priorDataContinuity",
        },
    ),
    "recovery-evidence": (
        "recoveryEvidenceChecks",
        {
            "RECOVERY_EVIDENCE_AVAILABLE": "evidenceAvailable",
            "RECOVERY_GUIDANCE_WITHHELD": "guidanceWithheld",
            "RECOVERY_EXPLANATIONS": "explanationsReachable",
            "RECOVERY_NEUTRAL_LANGUAGE": "neutralLanguage",
            "RECOVERY_CURRENT_DAY": "currentDayCorrectness",
            "RECOVERY_RESOURCE_BUDGET": "resourceBudget",
            "RECOVERY_PRIOR_DATA": "priorDataContinuity",
            "RECOVERY_PRIVACY": "privacy",
        },
    ),
    "personal-team-refresh": (
        "personalTeamRefreshChecks",
        {
            "PERSONAL_TEAM_STABLE_IDENTITY": "stableIdentity",
            "PERSONAL_TEAM_PREFLIGHT": "preflight",
            "PERSONAL_TEAM_PROFILE": "profileInspection",
            "PERSONAL_TEAM_IN_PLACE": "inPlaceInstall",
            "PERSONAL_TEAM_LAUNCH": "launchSmokeTest",
            "PERSONAL_TEAM_DATA_CONTINUITY": "dataContinuity",
            "PERSONAL_TEAM_PRIVACY": "privacy",
        },
    ),
}
if milestone in check_schemas:
    group, fields = check_schemas[milestone]
    if result == "pass":
        for environment_name in fields:
            value = os.environ.get(environment_name)
            if value is None:
                raise SystemExit(f"{environment_name} is required for a passing {milestone} record")
            if value != "true":
                raise SystemExit(f"{environment_name} must be true for a passing {milestone} record")
    record[group] = {
        output_name: os.environ.get(environment_name) == "true"
        for environment_name, output_name in fields.items()
    }
if milestone == "unified-events":
    route_result = os.environ.get("UNIFIED_ROUTE_ON_DEMAND")
    if result == "pass" and route_result not in {"true", "not_available"}:
        raise SystemExit(
            "UNIFIED_ROUTE_ON_DEMAND must be true or not_available for a passing unified-events record"
        )
    record["unifiedEventChecks"]["routeOnDemand"] = {
        "true": "verified",
        "not_available": "notAvailable",
    }.get(route_result, "failed")
Path(f"evidence/device/{evidence_name}.json").write_text(
    json.dumps(record, indent=2, sort_keys=True) + "\n"
)
PY
echo "Privacy-safe attended result written to evidence/device/${evidence_name}.json."
