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

require_pattern 'FileProtectionType\.complete' Sources/TrainingPersistence/StoreProtection.swift
require_pattern 'isExcludedFromBackup' Sources/TrainingPersistence/StoreProtection.swift
require_pattern 'privacySensitive\(\)' TrainingCompassApp/UI/RootView.swift
require_pattern 'scenePhase != \.active' TrainingCompassApp/App/TrainingCompassApp.swift

if search_recursive 'healthkitUUID|latitude|longitude|freeTextNote|rawMeasurement' fixtures Sources Tests; then
  echo "Fixture or source contains prohibited sensitive payload fields." >&2
  exit 1
fi

require_pattern 'SWIFT_STRICT_CONCURRENCY = complete' TrainingCompass.xcodeproj/project.pbxproj
require_pattern 'IPHONEOS_DEPLOYMENT_TARGET = 26\.0' TrainingCompass.xcodeproj/project.pbxproj
require_pattern 'SWIFT_OPTIMIZATION_LEVEL = "-O"' TrainingCompass.xcodeproj/project.pbxproj

echo "Privacy and dependency allowlist checks passed."
