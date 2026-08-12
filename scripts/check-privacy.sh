#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
from pathlib import Path

resolved = json.loads(Path("Package.resolved").read_text())
identities = {pin["identity"] for pin in resolved["pins"]}
allowed = {"grdb.swift"}
if identities != allowed:
    raise SystemExit(f"Dependency allowlist mismatch: {sorted(identities)} != {sorted(allowed)}")
PY

if rg -n '(^|[^A-Za-z])(URLSession|Network|CloudKit|Firebase|Sentry|Crashlytics|Mixpanel|PostHog)([^A-Za-z]|$)' Sources TrainingCompassApp; then
  echo "Network, cloud, analytics, or crash-reporting use is forbidden in Gate 0." >&2
  exit 1
fi

if find . -path './.build' -prune -o -name '*.entitlements' -print | grep -q .; then
  echo "Gate 0 must not ship capabilities or entitlements." >&2
  exit 1
fi

if find . -path './.build' -prune -o \( -name '*.xcframework' -o -name '*.framework' -o -name '*.a' -o -name '*.dylib' \) -print | grep -q .; then
  echo "Unreviewed local binary or framework detected." >&2
  exit 1
fi

tracking=$(plutil -extract NSPrivacyTracking raw TrainingCompassApp/Resources/PrivacyInfo.xcprivacy)
[[ "$tracking" == "false" ]] || { echo "Privacy manifest must disable tracking." >&2; exit 1; }
collected=$(plutil -extract NSPrivacyCollectedDataTypes json -o - TrainingCompassApp/Resources/PrivacyInfo.xcprivacy)
[[ "$collected" == "[]" ]] || { echo "Gate 0 privacy manifest must declare no collected data." >&2; exit 1; }
accessed=$(plutil -extract NSPrivacyAccessedAPITypes json -o - TrainingCompassApp/Resources/PrivacyInfo.xcprivacy)
[[ "$accessed" == "[]" ]] || { echo "Gate 0 privacy manifest must declare no required-reason APIs." >&2; exit 1; }

rg -q 'FileProtectionType\.complete' Sources/TrainingPersistence/StoreProtection.swift
rg -q 'isExcludedFromBackup' Sources/TrainingPersistence/StoreProtection.swift
rg -q 'privacySensitive\(\)' TrainingCompassApp/UI/RootView.swift
rg -q 'scenePhase != \.active' TrainingCompassApp/App/TrainingCompassApp.swift

if rg -n 'healthkitUUID|latitude|longitude|freeTextNote|rawMeasurement' fixtures Sources Tests; then
  echo "Fixture or source contains prohibited sensitive payload fields." >&2
  exit 1
fi

rg -q 'SWIFT_STRICT_CONCURRENCY = complete' TrainingCompass.xcodeproj/project.pbxproj
rg -q 'IPHONEOS_DEPLOYMENT_TARGET = 26\.0' TrainingCompass.xcodeproj/project.pbxproj
rg -q 'SWIFT_OPTIMIZATION_LEVEL = "-O"' TrainingCompass.xcodeproj/project.pbxproj

echo "Privacy and dependency allowlist checks passed."
