#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import hashlib
import json
import os
import platform
import subprocess
import tempfile
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
performance_result = subprocess.run(["make", "verify-performance"]).returncode
if performance_result != 0:
    raise SystemExit("Performance protocol check failed")

def sha256(path: str) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def migration_evidence() -> dict:
    path = Path("fixtures/migration-compatibility.json")
    if not path.exists():
        return {"path": str(path), "result": "missing"}
    report = json.loads(path.read_text())
    return {
        "path": str(path),
        "sha256": sha256(str(path)),
        "result": "pass" if report.get("authoritative")
        and report.get("reconstructible")
        and report.get("exportSchemaVersions") == [1]
        and report.get("exportVerified") is True
        and all(item.get("deterministic") and item.get("preservedGateZeroMarker") and item.get("finalSchemaVersion") == item.get("targetVersion") for item in report["authoritative"] + report["reconstructible"])
        else "fail",
        "authoritativePrefixes": len(report.get("authoritative", [])),
        "reconstructiblePrefixes": len(report.get("reconstructible", [])),
        "exportSchemaVersions": report.get("exportSchemaVersions", []),
        "exportVerified": report.get("exportVerified", False),
    }

def automated_verdict(name: str) -> str:
    value = os.environ.get(name, "not_run")
    if value not in {"pass", "fail", "not_run"}:
        raise SystemExit(f"{name} must be pass, fail, or not_run")
    return value

raw_dependency_graph = json.loads(output("swift", "package", "show-dependencies", "--format", "json"))

def sanitized_dependency(node: dict) -> dict:
    return {
        key: node[key]
        for key in ("identity", "name", "version")
        if key in node and node[key] not in (None, "unspecified")
    } | {
        "dependencies": [
            sanitized_dependency(child)
            for child in node.get("dependencies", [])
            if isinstance(child, dict)
        ]
    }

dependency_graph = sanitized_dependency(raw_dependency_graph)
def device_evidence(milestone: str) -> dict:
    path = Path(f"evidence/device/{milestone}.json")
    if path.exists():
        return json.loads(path.read_text())
    return {
        "result": "missing",
        "requiredCommand": f"make device-smoke MILESTONE={milestone}",
    }

def fixture_evidence(path: str, result: str) -> dict:
    fixture = Path(path)
    record = {
        "path": path,
        "sha256": sha256(path) if fixture.exists() else None,
        "result": result if fixture.exists() else "missing",
    }
    if fixture.exists():
        value = json.loads(fixture.read_text())
        record["schemaVersion"] = value.get("schemaVersion", value.get("version"))
        record["algorithmVersion"] = value.get("algorithmVersion")
    return record

def artifact(path: str) -> dict:
    value = Path(path)
    return {
        "path": path,
        "sha256": sha256(path) if value.exists() else None,
        "result": "present" if value.exists() else "missing",
    }

def measurement_evidence(record: dict) -> dict:
    allowed = {
        "coldLaunchP95Ms", "foregroundResumeP95Ms", "localMutationP95Ms",
        "ordinaryQueryP95Ms", "insightP95Ms", "recoveryImportP95Ms",
        "recoveryBaselineP95Ms", "recoveryGuidanceP95Ms", "routeProcessingP95Ms",
        "foregroundPeakMiB", "backgroundPeakMiB", "combinedStoresGiB",
        "authoritativeStoreMiB", "routeGeometryMiB", "authoritativeMigrationP95S",
        "reconstructibleMigrationP95S", "exportImportStagingP95S", "backgroundSliceS",
        "storageAvailableMiB", "healthReconciliationP95S", "healthRebuildP95S",
        "healthForegroundPeakMiB", "recoveryPeakMiB", "recoveryPageRecords",
        "recoveryTransientBufferMiB", "mainActorContinuousSliceP95Ms",
        "firstHealthContentP95S", "dailyDeltaProcessingP95S",
        "fullEnvelopeProcessingP95Minutes", "healthKitWaitP95S",
        "appControlledReconciliationP95S", "normalUseBatteryDeltaPercent",
        "rebuildBatteryDeltaPercent", "normalUseThermalState", "rebuildThermalState",
        "normalUseEnergyBudgetPass", "rebuildEnergyBudgetPass", "lowPowerPausePass",
        "batteryPausePass", "thermalPausePass", "interruptionRecovery",
    }
    measurements = record.get("measurements", {})
    return {
        "result": record.get("result", "missing"),
        "deviceModel": record.get("deviceModel", "not_recorded"),
        "iOSVersion": record.get("iOSVersion", "not_recorded"),
        "measurements": {key: measurements[key] for key in sorted(allowed) if key in measurements},
    }

def sanitized_checks(value: object) -> object:
    if isinstance(value, dict):
        return {
            key: sanitized_checks(child)
            for key, child in value.items()
            if isinstance(child, (bool, dict)) or child in {"verified", "notAvailable", "failed"}
        }
    return value if isinstance(value, bool) else None

def sanitized_device_evidence(record: dict) -> dict:
    sanitized = {
        key: record[key]
        for key in ("build", "deviceModel", "iOSVersion", "milestone", "ownerDataAccepted", "result", "sourceRevision")
        if key in record
    }
    sanitized["measurements"] = measurement_evidence(record)
    for key, value in record.items():
        if key.endswith("Checks") and isinstance(value, dict):
            sanitized[key] = sanitized_checks(value)
    return sanitized

gate_zero_evidence = device_evidence("gate-0")
health_foundation_evidence = device_evidence("health-foundation")
unified_events_evidence = device_evidence("unified-events")
training_insights_evidence = device_evidence("training-insights")
recovery_evidence = device_evidence("recovery-evidence")
personal_team_refresh_evidence = device_evidence("personal-team-refresh")
healthkit_write_back_evidence = device_evidence("healthkit-write-back")
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
personal_team_checks = personal_team_refresh_evidence.get("personalTeamRefreshChecks", {})
required_personal_team_checks = {
    "stableIdentity",
    "preflight",
    "profileInspection",
    "inPlaceInstall",
    "launchSmokeTest",
    "dataContinuity",
    "privacy",
}
personal_team_refresh_accepted = (
    personal_team_refresh_evidence.get("result") == "pass"
    and all(personal_team_checks.get(key) is True for key in required_personal_team_checks)
    and automated_pass
)
write_back_checks = healthkit_write_back_evidence.get("writeBackChecks", {})
required_write_back_checks = {
    "optInBoundary",
    "localIndependence",
    "retryRecovery",
    "versionReplacement",
    "correctionReopen",
    "conflictRepair",
    "externalDeletion",
    "exactUUIDRestoration",
    "ownershipSafeReplacement",
    "erasureDeletion",
    "erasureFailureRecovery",
    "privacy",
}
write_back_accepted = (
    healthkit_write_back_evidence.get("result") == "pass"
    and all(write_back_checks.get(key) is True for key in required_write_back_checks)
    and automated_pass
)
def check_release_measurements(milestone: str, record: dict) -> bool:
    if milestone == "personal-team-refresh":
        return True
    path = Path(f"evidence/device/{milestone}.json")
    if not path.exists():
        return False
    measurements = record.get("measurements")
    if not isinstance(measurements, dict):
        return False
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as temporary:
        json.dump(measurements, temporary)
        temporary_path = Path(temporary.name)
    command = ["python3", "scripts/check-release-envelope.py", str(temporary_path), "--require-protocol"]
    if milestone == "unified-events" and record.get("unifiedEventChecks", {}).get("routeOnDemand") == "notAvailable":
        command.append("--route-not-available")
    try:
        return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    finally:
        temporary_path.unlink(missing_ok=True)

release_measurements_accepted = all(
    check_release_measurements(milestone, record)
    for milestone, record in (
        ("gate-0", gate_zero_evidence),
        ("health-foundation", health_foundation_evidence),
        ("unified-events", unified_events_evidence),
        ("training-insights", training_insights_evidence),
        ("recovery-evidence", recovery_evidence),
        ("personal-team-refresh", personal_team_refresh_evidence),
    )
)
accepted_milestones = [
    milestone
    for milestone, accepted in (
        ("gate-0", owner_data_accepted),
        ("health-foundation", health_foundation_accepted),
        ("unified-events", unified_events_accepted),
        ("training-insights", training_insights_accepted),
        ("recovery-evidence", recovery_evidence_accepted),
        ("personal-team-refresh", personal_team_refresh_accepted and release_measurements_accepted),
    )
    if accepted
]
release_eligible = len(accepted_milestones) == 6 and write_back_accepted
entitlements = [
    {
        "path": str(path),
        "keys": sorted(json.loads(output("plutil", "-convert", "json", "-o", "-", str(path))).keys()),
    }
    for path in Path(".").rglob("*.entitlements")
    if ".build" not in path.parts
]
git_revision = output("git", "rev-parse", "HEAD")
commands = [
    "make bootstrap",
    "make verify",
    "make verify-final-release",
    "make acceptance",
    "make test-ui",
    "make fixtures",
    "make verify-migrations",
    "make verify-performance",
    "make device-smoke MILESTONE=gate-0",
    "make device-smoke MILESTONE=health-foundation",
    "make device-smoke MILESTONE=unified-events",
    "make device-smoke MILESTONE=training-insights",
    "make device-smoke MILESTONE=recovery-evidence",
    "make device-smoke MILESTONE=personal-team-refresh",
    "make verify-release MILESTONE=gate-0",
    "make verify-release MILESTONE=health-foundation",
    "make verify-release MILESTONE=unified-events",
    "make verify-release MILESTONE=training-insights",
    "make verify-release MILESTONE=recovery-evidence",
    "make verify-release MILESTONE=personal-team-refresh",
    "make evidence",
]
fixture_versions = {
    name: fixture_evidence(path, "pass" if result == 0 else "fail")
    for name, path, result in (
        ("verificationEnvelope", "fixtures/verification-envelope.json", performance_result),
        ("performanceProtocol", "fixtures/performance-protocol.json", performance_result),
        ("migrationCompatibility", "fixtures/migration-compatibility.json", 0),
    )
}
milestone_evidence = {
    "gate0": measurement_evidence(gate_zero_evidence),
    "healthFoundation": measurement_evidence(health_foundation_evidence),
    "unifiedEvents": measurement_evidence(unified_events_evidence),
    "trainingInsights": measurement_evidence(training_insights_evidence),
    "recoveryEvidence": measurement_evidence(recovery_evidence),
    "personalTeamRefresh": measurement_evidence(personal_team_refresh_evidence),
}
record = {
    "schemaVersion": 1,
    "commands": commands,
    "commandRevisions": [{"command": command, "revision": git_revision} for command in commands],
    "fixtureSeed": 21571,
    "gitRevision": git_revision,
    "environment": {
        "platform": platform.platform(),
        "architecture": platform.machine(),
        "swiftVersion": output("swift", "--version").splitlines()[0],
        "xcodeVersion": (output("xcodebuild", "-version") if subprocess.run(["xcodebuild", "-version"], env=subprocess_environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 else "unavailable"),
    },
    "algorithmVersions": {
        "verificationEnvelope": "verification-envelope-lcg-v1",
        "performanceProtocol": "release-performance-protocol-v1",
        "migrationCompatibility": "migration-compatibility-v1",
        "diagnosticSchema": "privacy-diagnostic-v1",
    },
    "artifacts": {
        "acceptanceMatrix": "documentation/developer/reference/acceptance-matrix.md",
        "acceptanceMatrixSha256": sha256("documentation/developer/reference/acceptance-matrix.md"),
        "releaseCandidateChecklist": "documentation/developer/reference/release-candidate-checklist.md",
        "releaseCandidateChecklistSha256": sha256("documentation/developer/reference/release-candidate-checklist.md"),
        "acceptanceContract": "pass" if acceptance_result == 0 else "fail",
        "deviceEvidence": sanitized_device_evidence(gate_zero_evidence),
        "milestoneDeviceEvidence": {
            "gate0": sanitized_device_evidence(gate_zero_evidence),
            "healthFoundation": sanitized_device_evidence(health_foundation_evidence),
            "unifiedEvents": sanitized_device_evidence(unified_events_evidence),
            "trainingInsights": sanitized_device_evidence(training_insights_evidence),
            "recoveryEvidence": sanitized_device_evidence(recovery_evidence),
            "personalTeamRefresh": sanitized_device_evidence(personal_team_refresh_evidence),
            "healthkitWriteBack": sanitized_device_evidence(healthkit_write_back_evidence),
        },
        "dependencyGraph": dependency_graph,
        "entitlements": entitlements,
        "capabilities": {
            "healthKit": True,
            "requiredDeviceCapabilities": ["arm64"],
            "networking": False,
            "remoteConfiguration": False,
            "analytics": False,
            "crashReporting": False,
        },
        "fileAttributeVerification": gate_zero_evidence.get("result", "missing"),
        "loggingAllowlist": [
            "pre_data_stores_ready",
            "pre_data_stores_failed",
            "operation",
            "durationMilliseconds",
            "recordCount",
            "byteCount",
            "peakMemoryMiB",
            "resultCategory",
            "deviceConditions",
        ],
        "migrationVerification": automated_verdict("MIGRATION_RESULT"),
        "migrationCompatibility": migration_evidence(),
        "verificationEnvelope": fixture_versions["verificationEnvelope"],
        "performanceProtocol": fixture_versions["performanceProtocol"],
        "migrationTable": artifact("documentation/developer/reference/migration-compatibility.md"),
        "evidenceIndexReference": artifact("documentation/developer/reference/evidence-index.md"),
        "releaseRunbook": artifact("documentation/developer/how-to-guides/record-release-evidence.md"),
        "privacyManifest": {
            "path": "TrainingCompassApp/Resources/PrivacyInfo.xcprivacy",
            "sha256": sha256("TrainingCompassApp/Resources/PrivacyInfo.xcprivacy"),
        },
        "privacyVerification": automated_verdict("PRIVACY_RESULT"),
    },
    "healthFoundationAccepted": health_foundation_accepted,
    "ownerDataAccepted": owner_data_accepted,
    "releaseVerdict": {
        "milestone": 6,
        "status": "eligible" if release_eligible else "blocked",
        "acceptedMilestones": accepted_milestones,
        "writeBackEvidence": write_back_accepted,
        "requiredMilestones": [
            "gate-0",
            "health-foundation",
            "unified-events",
            "training-insights",
            "recovery-evidence",
            "personal-team-refresh",
        ],
        "gitRevision": git_revision,
    },
    "platform": platform.platform(),
    "swiftVersion": output("swift", "--version").splitlines()[0],
    "compatibility": migration_evidence(),
    "rawMeasurements": milestone_evidence,
    "verdicts": {
        "automatedChangeGate": automated_verdict("VERIFY_RESULT"),
        "acceptanceMatrixGate": "pass" if acceptance_result == 0 else "fail",
        "healthFoundationGate": "eligible" if health_foundation_accepted else "blocked",
        "migrationGate": automated_verdict("MIGRATION_RESULT"),
        "performanceGate": "pass" if performance_result == 0 else "fail",
        "privacyGate": automated_verdict("PRIVACY_RESULT"),
        "releaseGate": "eligible" if release_eligible else "blocked",
        "uiGate": automated_verdict("UI_RESULT"),
        "unifiedEventsGate": "eligible" if unified_events_accepted else "blocked",
        "trainingInsightsGate": "eligible" if training_insights_accepted else "blocked",
        "recoveryEvidenceGate": "eligible" if recovery_evidence_accepted else "blocked",
        "personalTeamRefreshGate": "eligible" if personal_team_refresh_accepted else "blocked",
    },
    "unifiedEventsAccepted": unified_events_accepted,
    "trainingInsightsAccepted": training_insights_accepted,
    "recoveryEvidenceAccepted": recovery_evidence_accepted,
    "personalTeamRefreshAccepted": personal_team_refresh_accepted,
    "writeBackAccepted": write_back_accepted,
    "waivers": [],
}
encoded = json.dumps(record, indent=2, sort_keys=True) + "\n"
path = Path("evidence/gate-zero-environment.json")
path.write_text(encoded)
print(path)
PY
python3 scripts/check-evidence-index.py
