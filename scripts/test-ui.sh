#!/usr/bin/env bash
set -euo pipefail

xcodebuild -version >/dev/null
device_id=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data["devices"].items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit
raise SystemExit("No available iOS Simulator found")
')

xcrun simctl boot "${device_id}" 2>/dev/null || true
xcrun simctl bootstatus "${device_id}" -b

xcodebuild \
  -project TrainingCompass.xcodeproj \
  -scheme TrainingCompass \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${device_id},arch=arm64" \
  -destination-timeout 120 \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  test
