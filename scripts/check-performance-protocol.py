#!/usr/bin/env python3
"""Validate the privacy-safe repeated-run performance protocol contract."""

from __future__ import annotations

import json
import sys
from pathlib import Path


EXPECTED = {
    "version": 1,
    "algorithmVersion": "release-performance-protocol-v1",
    "fixtureSeed": 21571,
    "buildConfiguration": "Release",
    "conditioningRuns": 1,
    "measuredRuns": 10,
    "percentile": 95,
    "healthKitWaitExcluded": True,
    "appControlledMeasurements": True,
    "mainActorContinuousSliceLimitMs": 100,
    "firstHealthContentDeadlineS": 10,
    "dailyDeltaProcessingP95S": 2,
    "fullEnvelopeProcessingP95Minutes": 30,
}
REQUIRED_ENERGY_CONDITIONS = {
    "normal-use",
    "health-rebuild",
    "low-power-pauses-discretionary-work",
    "battery-below-20-pauses-discretionary-work",
    "serious-or-critical-thermal-pauses-discretionary-work",
}
REQUIRED_MEASUREMENTS = {
    "coldLaunchP95Ms",
    "foregroundResumeP95Ms",
    "localMutationP95Ms",
    "ordinaryQueryP95Ms",
    "insightP95Ms",
    "foregroundPeakMiB",
    "backgroundPeakMiB",
    "combinedStoresGiB",
    "authoritativeStoreMiB",
    "routeGeometryMiB",
    "mainActorContinuousSliceP95Ms",
    "firstHealthContentP95S",
    "dailyDeltaProcessingP95S",
    "fullEnvelopeProcessingP95Minutes",
    "healthKitWaitP95S",
    "appControlledReconciliationP95S",
    "healthReconciliationP95S",
    "healthRebuildP95S",
    "interruptionRecovery",
}
REQUIRED_ENERGY_MEASUREMENTS = {
    "normalUseBatteryDeltaPercent",
    "rebuildBatteryDeltaPercent",
    "normalUseThermalState",
    "rebuildThermalState",
    "normalUseEnergyBudgetPass",
    "rebuildEnergyBudgetPass",
    "lowPowerPausePass",
    "batteryPausePass",
    "thermalPausePass",
}
REQUIRED_STORAGE = {
    "authoritativeStoreMiB": 250,
    "combinedStoresGiB": 2,
    "routeGeometryMiB": 100,
    "storagePauseThresholdMiB": 500,
}
REQUIRED_WAIVER_FIELDS = {
    "measurement",
    "comparison",
    "scope",
    "effect",
    "expiry",
    "ownerAcceptance",
}


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check-performance-protocol.py PROTOCOL.json", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        protocol = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read performance protocol: {error}", file=sys.stderr)
        return 1
    if not isinstance(protocol, dict):
        print("Performance protocol must be a JSON object", file=sys.stderr)
        return 1

    errors = [
        f"{key} must equal {expected!r}"
        for key, expected in EXPECTED.items()
        if protocol.get(key) != expected
    ]
    energy_conditions = protocol.get("energyConditions")
    if (
        not isinstance(energy_conditions, list)
        or not all(isinstance(item, str) for item in energy_conditions)
        or not REQUIRED_ENERGY_CONDITIONS <= set(energy_conditions)
    ):
        errors.append("energyConditions must include normal use, rebuild, and all pause conditions")
    measurement_fields = protocol.get("measurementFields")
    if (
        not isinstance(measurement_fields, list)
        or not all(isinstance(item, str) for item in measurement_fields)
        or not REQUIRED_MEASUREMENTS <= set(measurement_fields)
    ):
        errors.append("measurementFields omit a required privacy-safe measurement")
    energy_measurement_fields = protocol.get("energyMeasurementFields")
    if (
        not isinstance(energy_measurement_fields, list)
        or not all(isinstance(item, str) for item in energy_measurement_fields)
        or set(energy_measurement_fields) != REQUIRED_ENERGY_MEASUREMENTS
    ):
        errors.append("energyMeasurementFields must enumerate matched battery, thermal, and pause verdicts")
    elif not REQUIRED_ENERGY_MEASUREMENTS <= set(measurement_fields or ()):
        errors.append("measurementFields must include every energy measurement")
    if protocol.get("thermalStatesAllowed") != ["nominal", "fair"]:
        errors.append("thermalStatesAllowed must permit only nominal and fair measured runs")
    if protocol.get("storageBudgets") != REQUIRED_STORAGE:
        errors.append("storageBudgets do not match the resolved envelope")
    waiver_fields = protocol.get("waiverFields")
    if (
        not isinstance(waiver_fields, list)
        or not all(isinstance(item, str) for item in waiver_fields)
        or set(waiver_fields) != REQUIRED_WAIVER_FIELDS
    ):
        errors.append("waiverFields must name measurement, comparison, scope, effect, expiry, and owner acceptance")
    commands = protocol.get("requiredCommands")
    if not isinstance(commands, list) or "make verify" not in commands:
        errors.append("requiredCommands must retain the canonical verification command")
    if errors:
        print("Performance protocol check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Performance protocol retains the release build, repeated-run, resource, energy, and waiver contract.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
