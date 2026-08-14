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

search_recursive() {
  local pattern=$1
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$@"
  else
    grep -REn --include='*.swift' "$pattern" "$@"
  fi
}

require_pattern() {
  local pattern=$1
  local path=$2
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$path"
  else
    grep -Eq "$pattern" "$path"
  fi
}

if search_recursive '(^|[^A-Za-z])(URLSession|Network|CloudKit|Firebase|Sentry|Crashlytics|Mixpanel|PostHog)([^A-Za-z]|$)' Sources TrainingCompassApp; then
  echo "Network, cloud, analytics, or crash-reporting use is forbidden in Gate 0." >&2
  exit 1
fi

while IFS= read -r entitlement; do
  [[ -z "$entitlement" ]] && continue
  if command -v rg >/dev/null 2>&1; then
    entitlement_is_reviewed() {
      plutil -convert json -o - "$1" 2>/dev/null | rg -q '"com\.apple\.developer\.healthkit"\s*:\s*true'
    }
  else
    entitlement_is_reviewed() {
      plutil -convert json -o - "$1" 2>/dev/null | grep -Eq '"com\.apple\.developer\.healthkit"[[:space:]]*:[[:space:]]*true'
    }
  fi
  if ! entitlement_is_reviewed "$entitlement"; then
    echo "Only the reviewed HealthKit entitlement may be shipped: $entitlement" >&2
    exit 1
  fi
done < <(find . -path './.build' -prune -o -name '*.entitlements' -print)

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

require_pattern 'FileProtectionType\.complete' Sources/TrainingPersistence/StoreProtection.swift
require_pattern 'isExcludedFromBackup' Sources/TrainingPersistence/StoreProtection.swift
require_pattern 'privacySensitive\(\)' TrainingCompassApp/UI/RootView.swift
require_pattern 'scenePhase != \.active' TrainingCompassApp/App/TrainingCompassApp.swift

if search_recursive 'latitude|longitude|northSouthDegrees|eastWestDegrees|freeTextNote|rawMeasurement' fixtures evidence; then
  echo "Fixture or evidence output contains prohibited sensitive payload fields." >&2
  exit 1
fi

if search_recursive 'logger\..*(latitude|longitude|northSouthDegrees|eastWestDegrees)' Sources TrainingCompassApp; then
  echo "Route coordinates must never be logged." >&2
  exit 1
fi

if search_recursive 'public (struct|enum|class) HealthKitRouteCoordinate' Sources; then
  echo "Full-resolution HealthKit route coordinates must remain adapter-private." >&2
  exit 1
fi

require_pattern 'maximumRetainedPoints = 2_000' Sources/TrainingApplication/HealthWorkoutRouteBoundary.swift

require_pattern 'SWIFT_STRICT_CONCURRENCY = complete' TrainingCompass.xcodeproj/project.pbxproj
require_pattern 'IPHONEOS_DEPLOYMENT_TARGET = 26\.0' TrainingCompass.xcodeproj/project.pbxproj
require_pattern 'SWIFT_OPTIMIZATION_LEVEL = "-O"' TrainingCompass.xcodeproj/project.pbxproj

echo "Privacy and dependency allowlist checks passed."
