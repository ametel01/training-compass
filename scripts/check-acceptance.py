#!/usr/bin/env python3
"""Validate the Local Training Core acceptance and release contracts.

This is deliberately a small, dependency-free check.  The matrix is the
traceability gate: a feature is not considered delivered merely because a
screen or a unit test exists; each critical scenario needs an evidence
pointer and an explicit device decision.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "documentation/developer/reference/acceptance-matrix.md"
BUDGETS = ROOT / "documentation/developer/reference/release-candidate-checklist.md"
INSIGHTS_CHECKLIST = ROOT / "documentation/developer/reference/training-insights-device-checklist.md"
RECOVERY_CHECKLIST = ROOT / "documentation/developer/reference/recovery-evidence-device-checklist.md"
WRITE_BACK_CHECKLIST = ROOT / "documentation/developer/reference/healthkit-write-back-device-checklist.md"

REQUIRED_SOURCES = (
    *range(1, 24),
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
)
REQUIRED_BUDGETS = (
    "1.5 seconds",
    "500 milliseconds",
    "150 milliseconds",
    "300 milliseconds",
    "750 milliseconds",
    "2 seconds",
    "250 MiB",
    "100 MiB",
    "2 GiB",
    "15 seconds",
    "60 seconds",
    "30 seconds",
    "20 seconds",
    "500 MiB",
    "100 records",
    "1 MiB",
    "4 MiB",
    "8 MiB",
    "20%",
)


def table_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def matrix_rows(text: str) -> list[list[str]]:
    rows: list[list[str]] = []
    in_table = False
    for line in text.splitlines():
        if line.startswith("| Source | Scenario variant |"):
            in_table = True
            continue
        if in_table and line.startswith("| ---"):
            continue
        if in_table and line.startswith("|"):
            cells = table_cells(line)
            if len(cells) >= 8:
                rows.append(cells)
            continue
        if in_table and line.strip() and not line.startswith("|"):
            break
    return rows


def coverage_rows(text: str) -> list[list[str]]:
    rows: list[list[str]] = []
    marker = "| Source | Normal success | Domain boundary | Missing or partial data |"
    in_table = False
    for line in text.splitlines():
        if line.startswith(marker):
            in_table = True
            continue
        if in_table and line.startswith("| ---"):
            continue
        if in_table and line.startswith("|"):
            cells = table_cells(line)
            if len(cells) >= 6:
                rows.append(cells)
            continue
        if in_table and line.strip() and not line.startswith("|"):
            break
    return rows


def main() -> int:
    errors: list[str] = []
    matrix = MATRIX.read_text()
    budgets = BUDGETS.read_text()
    if not INSIGHTS_CHECKLIST.exists():
        errors.append("Training and Running Insights Acceptance Device checklist is missing")
    if not RECOVERY_CHECKLIST.exists():
        errors.append("Recovery Evidence and Guidance Acceptance Device checklist is missing")
    if not WRITE_BACK_CHECKLIST.exists():
        errors.append("HealthKit Write-back Acceptance Device checklist is missing")

    rows = matrix_rows(matrix)
    sources = {int(match.group(1)) for row in rows if (match := re.match(r"Issue #(\d+):", row[0]))}
    missing_sources = [number for number in REQUIRED_SOURCES if number not in sources]
    if missing_sources:
        errors.append(f"acceptance matrix is missing issue sources: {missing_sources}")

    for source in REQUIRED_SOURCES:
        source_rows = [row for row in rows if row[0].startswith(f"Issue #{source}:")]
        if not source_rows:
            errors.append(f"Issue #{source} has no scenario rows")
        for row in source_rows:
            if not row[5] or row[5].lower() in {"tbd", "todo"}:
                errors.append(f"Issue #{source} has no evidence layer: {row[1]}")
            if not row[7] or row[7].lower() in {"tbd", "todo"}:
                errors.append(f"Issue #{source} has no latest evidence pointer: {row[1]}")

    coverage = coverage_rows(matrix)
    coverage_sources = {int(match.group(1)) for row in coverage if (match := re.match(r"Issue #(\d+)", row[0]))}
    missing_coverage = [number for number in REQUIRED_SOURCES if number not in coverage_sources]
    if missing_coverage:
        errors.append(f"core coverage table is missing issue sources: {missing_coverage}")
    for row in coverage:
        if any(not cell or cell.lower() in {"tbd", "todo"} for cell in row[1:6]):
            errors.append(f"core coverage row has an unclassified scenario: {row[0]}")

    for budget in REQUIRED_BUDGETS:
        if budget not in budgets:
            errors.append(f"release-candidate checklist omits resolved budget {budget}")

    required_health_contracts = (
        "No-access, partial/limited-history, successful-empty, cached, and unavailable states",
        "paginated additions, replacements, deletions, and independent stream facts",
        "locked, later unlocked, interrupted, terminated, or a first/later reconciliation fails",
        "Write-back is not exposed before opt-in",
    )
    for contract in required_health_contracts:
        if contract not in matrix:
            errors.append(f"acceptance matrix omits Health foundation contract: {contract}")

    required_training_event_contracts = (
        "no candidate is preselected",
        "one authoritative link between stable identities",
        "The pair is counted once",
        "no-silent-overwrite contract",
    )
    for contract in required_training_event_contracts:
        if contract not in matrix:
            errors.append(f"acceptance matrix omits Training Event contract: {contract}")

    required_enrichment_contracts = (
        "Not available from Health",
        "sample intervals without inferring gaps or workout-edge coverage",
        "updates the existing Training Event in place",
    )
    for contract in required_enrichment_contracts:
        if contract not in matrix:
            errors.append(f"acceptance matrix omits Workout Enrichment contract: {contract}")

    required_route_contracts = (
        "No route is prefetched",
        "at most 2,000 retained points",
        "No partial route is represented as ready",
        "authoritative export by default",
    )
    for contract in required_route_contracts:
        if contract not in matrix:
            errors.append(f"acceptance matrix omits Workout Route contract: {contract}")

    required_unified_milestone_contracts = (
        "separate local and Health events",
        "exact-UUID reappearance",
        "source authority, provenance, current state, and audit history",
        "late heart rate, distance, energy, and route states",
        "retained-point, latency, memory, storage, logging, and export privacy",
        "local training remains usable during enrichment work",
        "unfinished insight behavior remains hidden",
    )
    for contract in required_unified_milestone_contracts:
        if contract not in matrix:
            errors.append(f"acceptance matrix omits unified milestone contract: {contract}")

    required_insight_contracts = (
        "Every derived value is source-linked",
        "Insight Explanation containing records, dates, coverage, rules, baseline, exclusions, missing data, configuration, and reconciliation",
        "no score, record, goal, claim, prediction, verdict, or prescription",
        "750-millisecond insight budget",
        "source facts; linked events remain single-counted",
    )
    for contract in required_insight_contracts:
        if contract not in matrix:
            errors.append(f"acceptance matrix omits Training and Running Insights contract: {contract}")

    required_recovery_contracts = (
        "Source overlap",
        "exact 90-minute and longer episode gaps",
        "odd/even sample medians",
        "13/14-day baselines",
        "inclusive band edges",
        "current-day rollover",
        "stream failure",
        "source-incomparable guidance states",
        "Every visible Recovery Observation, baseline, and prompt reaches an Insight Explanation",
        "no score, diagnosis, medical or injury-risk claim, causal interpretation, performance prediction, warning threshold, or training prescription",
        "750-millisecond app-controlled insight budget",
        "privacy-safe evidence contains no measurements or identifiers",
    )
    for contract in required_recovery_contracts:
        if contract not in matrix:
            errors.append(f"acceptance matrix omits Recovery Evidence and Guidance contract: {contract}")

    required_write_back_contracts = (
        "authorization is not requested before enablement",
        "Only a Traditional Strength Training summary is written",
        "No second summary is created for an external link",
        "local completion succeeds independently of Health availability",
    )
    for contract in required_write_back_contracts:
        if contract.lower() not in matrix.lower():
            errors.append(f"acceptance matrix omits HealthKit Write-back contract: {contract}")

    required_write_back_recovery_contracts = (
        "Retry scheduled",
        "Health access needed",
        "Couldn't save",
        "later foreground opportunity",
        "Refresh Health Data does not retry Write-backs",
    )
    for contract in required_write_back_recovery_contracts:
        if contract.lower() not in matrix.lower():
            errors.append(
                f"acceptance matrix omits HealthKit Write-back recovery contract: {contract}"
            )

    if errors:
        print("Acceptance contract check failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Acceptance matrix and release-candidate budget contract are complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
