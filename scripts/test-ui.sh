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

xcodebuild \
  -project TrainingCompass.xcodeproj \
  -scheme TrainingCompass \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${device_id}" \
  CODE_SIGNING_ALLOWED=NO \
  test
