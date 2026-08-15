#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import hashlib
import json
import os
import platform
import subprocess
from pathlib import Path

subprocess_environment = os.environ.copy()
# Apple's Python launcher can inject the Command Line Tools SDKROOT even when
# full Xcode is selected. Let Swift choose the SDK paired with its compiler.
subprocess_environment.pop("SDKROOT", None)

def output(*command: str) -> str:
    return subprocess.check_output(
        command,
        env=subprocess_environment,
        text=True,
    ).strip()

acceptance_result = subprocess.run(["python3", "scripts/check-acceptance.py"]).returncode
if acceptance_result != 0:
    raise SystemExit("Acceptance contract check failed")

def sha256(path: str) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def automated_verdict(name: str) -> str:
    value = os.environ.get(name, "not_run")
    if value not in {"pass", "fail", "not_run"}:
        raise SystemExit(f"{name} must be pass, fail, or not_run")
    return value

dependency_graph = json.loads(output("swift", "package", "show-dependencies", "--format", "json"))
def device_evidence(milestone: str) -> dict:
    path = Path(f"evidence/device/{milestone}.json")
    if path.exists():
        return json.loads(path.read_text())
    return {
        "result": "missing",
        "requiredCommand": f"make device-smoke MILESTONE={milestone}",
    }

gate_zero_evidence = device_evidence("gate-0")
health_foundation_evidence = device_evidence("health-foundation")
unified_events_evidence = device_evidence("unified-events")
training_insights_evidence = device_evidence("training-insights")
recovery_evidence = device_evidence("recovery-evidence")
automated_pass = acceptance_result == 0 and all(
    os.environ.get(name) == "pass"
    for name in ("VERIFY_RESULT", "MIGRATION_RESULT", "PRIVACY_RESULT", "UI_RESULT")
)
owner_data_accepted = (
    gate_zero_evidence.get("result") == "pass"
    and gate_zero_evidence.get("ownerDataAccepted") is True
    and automated_pass
)
health_checks = health_foundation_evidence.get("healthChecks", {})
required_health_checks = {
    "authorization",
    "anchoredQueries",
    "observerRegistration",
    "foregroundRefresh",
    "lockUnlockRecovery",
    "protectedStorage",
    "backupExclusion",
}
health_foundation_accepted = (
    health_foundation_evidence.get("result") == "pass"
    and all(health_checks.get(key) is True for key in required_health_checks)
    and automated_pass
)
unified_checks = unified_events_evidence.get("unifiedEventChecks", {})
required_unified_checks = {
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
unified_events_accepted = (
    unified_events_evidence.get("result") == "pass"
    and all(unified_checks.get(key) is True for key in required_unified_checks)
    and unified_checks.get("routeOnDemand") in {"verified", "notAvailable"}
    and automated_pass
)
training_insights_checks = training_insights_evidence.get("trainingInsightsChecks", {})
required_training_insights_checks = {
    "explanationsReachable",
    "sourceSafeRecomputation",
    "neutralLanguage",
    "linkedSingleCount",
    "localAvailability",
    "performanceBudget",
    "priorDataContinuity",
}
training_insights_accepted = (
    training_insights_evidence.get("result") == "pass"
    and all(training_insights_checks.get(key) is True for key in required_training_insights_checks)
    and automated_pass
)
recovery_checks = recovery_evidence.get("recoveryEvidenceChecks", {})
required_recovery_checks = {
    "evidenceAvailable",
    "guidanceWithheld",
    "explanationsReachable",
    "neutralLanguage",
    "currentDayCorrectness",
    "resourceBudget",
    "priorDataContinuity",
    "privacy",
}
recovery_evidence_accepted = (
    recovery_evidence.get("result") == "pass"
    and all(recovery_checks.get(key) is True for key in required_recovery_checks)
    and automated_pass
)
entitlements = [str(path) for path in Path(".").rglob("*.entitlements") if ".build" not in path.parts]
record = {
    "commands": [
        "make bootstrap",
        "make verify",
        "make acceptance",
        "make test-ui",
        "make fixtures",
        "make verify-migrations",
        "make device-smoke MILESTONE=gate-0",
        "make device-smoke MILESTONE=health-foundation",
        "make device-smoke MILESTONE=unified-events",
        "make device-smoke MILESTONE=training-insights",
        "make device-smoke MILESTONE=recovery-evidence",
        "make verify-release MILESTONE=gate-0",
        "make verify-release MILESTONE=health-foundation",
        "make verify-release MILESTONE=unified-events",
        "make verify-release MILESTONE=training-insights",
        "make verify-release MILESTONE=recovery-evidence",
        "make evidence",
    ],
    "fixtureSeed": 21571,
    "gitRevision": output("git", "rev-parse", "HEAD"),
    "artifacts": {
        "acceptanceMatrix": "documentation/developer/reference/acceptance-matrix.md",
        "acceptanceMatrixSha256": sha256("documentation/developer/reference/acceptance-matrix.md"),
        "releaseCandidateChecklist": "documentation/developer/reference/release-candidate-checklist.md",
        "releaseCandidateChecklistSha256": sha256("documentation/developer/reference/release-candidate-checklist.md"),
        "acceptanceContract": "pass" if acceptance_result == 0 else "fail",
        "deviceEvidence": gate_zero_evidence,
        "milestoneDeviceEvidence": {
            "gate0": gate_zero_evidence,
            "healthFoundation": health_foundation_evidence,
            "unifiedEvents": unified_events_evidence,
            "trainingInsights": training_insights_evidence,
            "recoveryEvidence": recovery_evidence,
        },
        "dependencyGraph": dependency_graph,
        "entitlements": entitlements,
        "fileAttributeVerification": gate_zero_evidence.get("result", "missing"),
        "loggingAllowlist": ["pre_data_stores_ready", "pre_data_stores_failed"],
        "migrationVerification": automated_verdict("MIGRATION_RESULT"),
        "privacyManifest": {
            "path": "TrainingCompassApp/Resources/PrivacyInfo.xcprivacy",
            "sha256": sha256("TrainingCompassApp/Resources/PrivacyInfo.xcprivacy"),
        },
        "privacyVerification": automated_verdict("PRIVACY_RESULT"),
    },
    "healthFoundationAccepted": health_foundation_accepted,
    "ownerDataAccepted": owner_data_accepted,
    "platform": platform.platform(),
    "swiftVersion": output("swift", "--version").splitlines()[0],
    "verdicts": {
        "automatedChangeGate": automated_verdict("VERIFY_RESULT"),
        "acceptanceMatrixGate": "pass" if acceptance_result == 0 else "fail",
        "healthFoundationGate": "eligible" if health_foundation_accepted else "blocked",
        "migrationGate": automated_verdict("MIGRATION_RESULT"),
        "privacyGate": automated_verdict("PRIVACY_RESULT"),
        "releaseGate": "eligible" if owner_data_accepted else "blocked",
        "uiGate": automated_verdict("UI_RESULT"),
        "unifiedEventsGate": "eligible" if unified_events_accepted else "blocked",
        "trainingInsightsGate": "eligible" if training_insights_accepted else "blocked",
        "recoveryEvidenceGate": "eligible" if recovery_evidence_accepted else "blocked",
    },
    "unifiedEventsAccepted": unified_events_accepted,
    "trainingInsightsAccepted": training_insights_accepted,
    "recoveryEvidenceAccepted": recovery_evidence_accepted,
    "waivers": [],
}
encoded = json.dumps(record, indent=2, sort_keys=True) + "\n"
path = Path("evidence/gate-zero-environment.json")
path.write_text(encoded)
print(path)
PY
