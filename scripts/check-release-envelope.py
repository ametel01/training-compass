#!/usr/bin/env python3
"""Check privacy-safe Acceptance Device release measurements."""

from __future__ import annotations

import json
import sys
from pathlib import Path


LIMITS = {
    "coldLaunchP95Ms": ("<=", 1500),
    "foregroundResumeP95Ms": ("<=", 500),
    "localMutationP95Ms": ("<=", 150),
    "ordinaryQueryP95Ms": ("<=", 300),
    "insightP95Ms": ("<=", 750),
    "recoveryImportP95Ms": ("<=", 750),
    "recoveryBaselineP95Ms": ("<=", 750),
    "recoveryGuidanceP95Ms": ("<=", 750),
    "routeProcessingP95Ms": ("<=", 2000),
    "foregroundPeakMiB": ("<=", 250),
    "backgroundPeakMiB": ("<=", 100),
    "combinedStoresGiB": ("<=", 2),
    "authoritativeStoreMiB": ("<=", 250),
    "routeGeometryMiB": ("<=", 100),
    "authoritativeMigrationP95S": ("<=", 15),
    "reconstructibleMigrationP95S": ("<=", 60),
    "exportImportStagingP95S": ("<=", 30),
    "backgroundSliceS": ("<=", 20),
    "storageAvailableMiB": (">=", 500),
    "healthReconciliationP95S": ("<=", 60),
    "healthRebuildP95S": ("<=", 60),
    "healthForegroundPeakMiB": ("<=", 250),
    "recoveryPeakMiB": ("<=", 250),
    "recoveryPageRecords": ("<=", 100),
    "recoveryTransientBufferMiB": ("<=", 8),
}
PROTOCOL_MEASUREMENTS = {
    "mainActorContinuousSliceP95Ms",
    "firstHealthContentP95S",
    "dailyDeltaProcessingP95S",
    "fullEnvelopeProcessingP95Minutes",
    "healthKitWaitP95S",
    "appControlledReconciliationP95S",
}
PROTOCOL_LIMITS = {
    "mainActorContinuousSliceP95Ms": ("<=", 100),
    "firstHealthContentP95S": ("<=", 10),
    "dailyDeltaProcessingP95S": ("<=", 2),
    "fullEnvelopeProcessingP95Minutes": ("<=", 30),
}
ENERGY_MEASUREMENTS = {
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
WAIVER_FIELDS = {"measurement", "comparison", "scope", "effect", "expiry", "ownerAcceptance"}


def main() -> int:
    options = set(sys.argv[2:])
    allowed_options = {"--route-not-available", "--require-protocol"}
    if len(sys.argv) < 2 or not options <= allowed_options:
        print("Usage: check-release-envelope.py MEASUREMENTS.json [--route-not-available] [--require-protocol]", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        values = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read release measurements: {error}", file=sys.stderr)
        return 1
    if not isinstance(values, dict):
        print("Release measurements must be a JSON object", file=sys.stderr)
        return 1

    protocol = values.get("protocol")
    measurements = values.get(
        "measurements", {key: value for key, value in values.items() if key != "protocol"}
    )
    if not isinstance(measurements, dict):
        print("measurements must be a JSON object", file=sys.stderr)
        return 1
    if "--require-protocol" in options:
        if not isinstance(protocol, dict):
            print("Release measurements must include a privacy-safe protocol object", file=sys.stderr)
            return 1
        required_protocol = {
            "version": 1,
            "algorithmVersion": "release-performance-protocol-v1",
            "buildConfiguration": "Release",
            "conditioningRuns": 1,
            "measuredRuns": 10,
            "percentile": 95,
            "fixtureSeed": 21571,
            "healthKitWaitExcluded": True,
            "appControlledMeasurements": True,
            "mainActorContinuousSliceLimitMs": 100,
            "firstHealthContentDeadlineS": 10,
            "dailyDeltaProcessingP95S": 2,
            "fullEnvelopeProcessingP95Minutes": 30,
            "thermalStatesAllowed": ["nominal", "fair"],
        }
        protocol_errors = [
            f"protocol.{key} must equal {expected!r}"
            for key, expected in required_protocol.items()
            if protocol.get(key) != expected
        ]
        if protocol_errors:
            print("Release measurement protocol check failed:", file=sys.stderr)
            for error in protocol_errors:
                print(f"- {error}", file=sys.stderr)
            return 1
        if set(protocol.get("energyMeasurementFields", ())) != ENERGY_MEASUREMENTS:
            print("protocol.energyMeasurementFields must enumerate all energy verdicts", file=sys.stderr)
            return 1
        for key in PROTOCOL_MEASUREMENTS:
            value = measurements.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0:
                print(f"measurements.{key} must be a non-negative number", file=sys.stderr)
                return 1
        for key, (operator, limit) in PROTOCOL_LIMITS.items():
            value = measurements.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                print(f"measurements.{key} must be numeric", file=sys.stderr)
                return 1
            if operator == "<=" and value > limit:
                print(f"measurements.{key}={value} violates {operator} {limit}", file=sys.stderr)
                return 1
        for key in ENERGY_MEASUREMENTS & {"normalUseBatteryDeltaPercent", "rebuildBatteryDeltaPercent"}:
            value = measurements.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0:
                print(f"measurements.{key} must be a non-negative number", file=sys.stderr)
                return 1
        for key in ENERGY_MEASUREMENTS & {"normalUseThermalState", "rebuildThermalState"}:
            if measurements.get(key) not in {"nominal", "fair"}:
                print(f"measurements.{key} must be nominal or fair", file=sys.stderr)
                return 1
        for key in ENERGY_MEASUREMENTS & {
            "normalUseEnergyBudgetPass",
            "rebuildEnergyBudgetPass",
            "lowPowerPausePass",
            "batteryPausePass",
            "thermalPausePass",
        }:
            if measurements.get(key) is not True:
                print(f"measurements.{key} must be true", file=sys.stderr)
                return 1

    route_not_available = "--route-not-available" in options
    optional_route_keys = {"routeProcessingP95Ms", "routeGeometryMiB"}
    required_limits = {
        key: limit
        for key, limit in LIMITS.items()
        if not route_not_available or key not in optional_route_keys
    }
    errors: list[str] = []
    allowed_keys = set(LIMITS) | PROTOCOL_MEASUREMENTS | ENERGY_MEASUREMENTS | {"interruptionRecovery"}
    allowed_record_keys = allowed_keys | {"protocol", "measurements", "waivers"}
    unexpected_keys = sorted(set(values) - allowed_record_keys)
    if unexpected_keys:
        errors.append(f"unexpected measurement fields: {unexpected_keys}")
    unexpected_measurement_keys = sorted(set(measurements) - allowed_keys)
    if unexpected_measurement_keys:
        errors.append(f"unexpected measurement fields: {unexpected_measurement_keys}")
    for key, (operator, limit) in required_limits.items():
        value = measurements.get(key)
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            errors.append(f"{key} must be numeric")
            continue
        if (operator == "<=" and value > limit) or (operator == ">=" and value < limit):
            errors.append(f"{key}={value} violates {operator} {limit}")
    if measurements.get("interruptionRecovery") is not True:
        errors.append("interruptionRecovery must be true")
    waivers = values.get("waivers", [])
    if not isinstance(waivers, list):
        errors.append("waivers must be an array")
    else:
        for index, waiver in enumerate(waivers):
            if not isinstance(waiver, dict) or set(waiver) != WAIVER_FIELDS:
                errors.append(f"waivers[{index}] must record the complete waiver contract")
                continue
            for field in WAIVER_FIELDS - {"ownerAcceptance"}:
                if not isinstance(waiver[field], str) or not waiver[field].strip():
                    errors.append(f"waivers[{index}].{field} must be a non-empty string")
            if waiver["ownerAcceptance"] is not True:
                errors.append(f"waivers[{index}].ownerAcceptance must be true")
    if errors:
        print("Release envelope check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Release envelope measurements pass.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
