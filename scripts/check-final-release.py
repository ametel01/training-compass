#!/usr/bin/env python3
"""Validate the final release contract and, optionally, one release handoff."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MILESTONES = ("gate-0", "health-foundation", "unified-events", "training-insights", "recovery-evidence", "personal-team-refresh")
WRITE_BACK_RECORD = "healthkit-write-back"
REQUIRED_FILES = (
    "documentation/developer/reference/acceptance-matrix.md",
    "documentation/developer/reference/final-release-checklist.md",
    "documentation/developer/reference/healthkit-write-back-device-checklist.md",
    "documentation/developer/reference/evidence-index.md",
    "documentation/developer/how-to-guides/record-release-evidence.md",
    "scripts/check-acceptance.py",
    "scripts/check-evidence-index.py",
    "scripts/evidence.sh",
    "scripts/verify-final-release.sh",
    "scripts/device-smoke.sh",
    "Makefile",
)
WRITE_BACK_CONTRACTS = (
    "testPreferenceDefaultsOffAndAuthorizationFollowsDurableEnablement",
    "testTransientFailureIsDurableAndResumesOnLaterOpportunity",
    "testReopenMarksSummaryPendingAndOnlyChangedFactsPublishGreaterVersion",
    "testExternalDeletionStaysDeletedUntilExplicitRestoreAndExactUUIDCanReconcile",
    "testDeleteAllSummariesPreservesRemainingIdentityAcrossMixedFailureAndRetry",
)
MILESTONE_CHECKS = {
    "health-foundation": ("healthChecks", {"authorization", "anchoredQueries", "observerRegistration", "foregroundRefresh", "lockUnlockRecovery", "protectedStorage", "backupExclusion"}),
    "unified-events": ("unifiedEventChecks", {"priorDataContinuity", "linkedSingleCount", "sourceDetail", "lateOrUnavailableEnrichment", "exactUUIDRecovery", "explicitUnlink", "localAvailability", "privacy", "unfinishedInsightsHidden"}),
    "training-insights": ("trainingInsightsChecks", {"explanationsReachable", "sourceSafeRecomputation", "neutralLanguage", "linkedSingleCount", "localAvailability", "performanceBudget", "priorDataContinuity"}),
    "recovery-evidence": ("recoveryEvidenceChecks", {"evidenceAvailable", "guidanceWithheld", "explanationsReachable", "neutralLanguage", "currentDayCorrectness", "resourceBudget", "priorDataContinuity", "privacy"}),
    "personal-team-refresh": ("personalTeamRefreshChecks", {"stableIdentity", "preflight", "profileInspection", "inPlaceInstall", "launchSmokeTest", "dataContinuity", "privacy"}),
}


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text()


def require(needle: str, haystack: str, errors: list[str], label: str) -> None:
    if needle not in haystack:
        errors.append(f"{label} omits required contract: {needle}")


def check_source_contract() -> list[str]:
    errors: list[str] = []
    missing = [path for path in REQUIRED_FILES if not (ROOT / path).is_file()]
    errors.extend(f"missing final-release artifact: {path}" for path in missing)
    if errors:
        return errors
    matrix = read("documentation/developer/reference/acceptance-matrix.md")
    checklist = read("documentation/developer/reference/final-release-checklist.md")
    command_contract = read("documentation/developer/reference/command-contract.md")
    makefile = read("Makefile")
    evidence = read("scripts/evidence.sh")
    verifier = read("scripts/verify-final-release.sh")
    index_checker = read("scripts/check-evidence-index.py")
    require("Issue #48:", matrix, errors, "acceptance matrix")
    require("Issue #48 |", matrix, errors, "acceptance coverage")
    require("Milestone 6", checklist, errors, "final-release checklist")
    for milestone in MILESTONES:
        require(milestone, checklist, errors, "final-release checklist")
        require(f"evidence/device/{milestone}.json", checklist, errors, "final-release checklist")
        require(milestone, verifier, errors, "final-release verifier")
    require(f"evidence/device/{WRITE_BACK_RECORD}.json", checklist, errors, "final-release checklist")
    require(WRITE_BACK_RECORD, verifier, errors, "final-release verifier")
    require("verify-final-release:", makefile, errors, "Makefile")
    require("make verify-final-release", command_contract, errors, "command contract")
    require('"releaseVerdict"', evidence, errors, "evidence generator")
    require('"releaseVerdict"', index_checker, errors, "evidence index checker")
    write_back_tests = read("Tests/TrainingApplicationTests/HealthWorkoutWriteBackBoundaryTests.swift")
    for contract in WRITE_BACK_CONTRACTS:
        require(contract, write_back_tests, errors, "write-back regression tests")
    return errors


def check_handoff() -> list[str]:
    errors: list[str] = []
    evidence_dir = ROOT / "evidence/device"
    records: dict[str, dict] = {}
    required_records = (*MILESTONES, WRITE_BACK_RECORD)
    for milestone in required_records:
        path = evidence_dir / f"{milestone}.json"
        if not path.is_file():
            errors.append(f"attended evidence is missing: {path.relative_to(ROOT)}")
            continue
        try:
            value = json.loads(path.read_text())
        except json.JSONDecodeError as error:
            errors.append(f"attended evidence is invalid JSON: {path.name}: {error}")
            continue
        if not isinstance(value, dict):
            errors.append(f"attended evidence must be an object: {path.name}")
            continue
        records[milestone] = value
        if value.get("result") != "pass":
            errors.append(f"attended evidence is not passing: {path.name}")
        if value.get("ownerDataAccepted") is not True:
            errors.append(f"owner-data acceptance is missing: {path.name}")
        if value.get("sourceRevision") != subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip():
            errors.append(f"attended evidence revision is stale: {path.name}")
        if milestone != WRITE_BACK_RECORD and milestone != "personal-team-refresh":
            measurements = value.get("measurements")
            if not isinstance(measurements, dict):
                errors.append(f"release measurements are missing: {path.name}")
                continue
            with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as temporary:
                json.dump(measurements, temporary)
                temporary_path = Path(temporary.name)
            command = ["python3", str(ROOT / "scripts/check-release-envelope.py"), str(temporary_path), "--require-protocol"]
            if milestone == "unified-events" and value.get("unifiedEventChecks", {}).get("routeOnDemand") == "notAvailable":
                command.append("--route-not-available")
            try:
                if subprocess.run(command, cwd=ROOT, capture_output=True).returncode != 0:
                    errors.append(f"release measurements are incomplete or over budget: {path.name}")
            finally:
                temporary_path.unlink(missing_ok=True)
        if milestone in MILESTONE_CHECKS:
            group, required = MILESTONE_CHECKS[milestone]
            checks = value.get(group, {})
            if not all(checks.get(key) is True for key in required):
                errors.append(f"attended checks are incomplete: {path.name}")
        if milestone == "personal-team-refresh":
            profile = value.get("profile", {})
            if not profile.get("creationDate") or not profile.get("expirationDate"):
                errors.append("Personal Team profile dates are missing")
    required_write_back = {
        "optInBoundary", "localIndependence", "retryRecovery", "versionReplacement",
        "correctionReopen", "conflictRepair", "externalDeletion", "exactUUIDRestoration",
        "ownershipSafeReplacement", "erasureDeletion", "erasureFailureRecovery", "privacy",
    }
    write_back = records.get(WRITE_BACK_RECORD, {}).get("writeBackChecks", {})
    if not all(write_back.get(key) is True for key in required_write_back):
        errors.append("HealthKit Write-back attended checks are incomplete")
    index_path = ROOT / "evidence/gate-zero-environment.json"
    if not index_path.is_file():
        errors.append("release evidence index is missing: evidence/gate-zero-environment.json")
        return errors
    try:
        index = json.loads(index_path.read_text())
    except json.JSONDecodeError as error:
        errors.append(f"release evidence index is invalid JSON: {error}")
        return errors
    try:
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    except subprocess.CalledProcessError as error:
        errors.append(f"could not determine current revision: {error}")
        revision = ""
    if index.get("gitRevision") != revision:
        errors.append("evidence index revision does not match HEAD")
    verdict = index.get("releaseVerdict")
    if not isinstance(verdict, dict):
        errors.append("evidence index has no release verdict")
    else:
        if verdict.get("milestone") != 6:
            errors.append("release verdict must identify Milestone 6")
        if verdict.get("status") != "eligible":
            errors.append("release verdict is not eligible")
        if verdict.get("acceptedMilestones") != list(MILESTONES):
            errors.append("release verdict does not enumerate all six milestones")
        if verdict.get("writeBackEvidence") is not True:
            errors.append("release verdict does not include passing Write-back evidence")
        if verdict.get("gitRevision") != revision:
            errors.append("release verdict revision does not match HEAD")
    if index.get("verdicts", {}).get("releaseGate") != "eligible":
        errors.append("evidence index releaseGate is not eligible")
    if records and set(records) == set(required_records):
        summary = index.get("artifacts", {}).get("milestoneDeviceEvidence", {})
        names = {"gate-0": "gate0", "health-foundation": "healthFoundation", "unified-events": "unifiedEvents", "training-insights": "trainingInsights", "recovery-evidence": "recoveryEvidence", "personal-team-refresh": "personalTeamRefresh", "healthkit-write-back": "healthkitWriteBack"}
        for milestone, name in names.items():
            if summary.get(name) is None:
                errors.append(f"evidence index omits {milestone} summary")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-evidence", action="store_true")
    args = parser.parse_args()
    errors = check_source_contract()
    if args.require_evidence:
        errors.extend(check_handoff())
    if errors:
        print("Final release contract check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    mode = "handoff" if args.require_evidence else "source"
    print(f"Final release {mode} contract is complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
