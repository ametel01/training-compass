#!/usr/bin/env bash
set -euo pipefail

requested_name="${1:-}"
bundle_id="com.ametel01.trainingcompass"
build_dir="${TRAINING_COMPASS_SIMULATOR_BUILD_DIR:-.build/run-simulator}"
device_info=$(python3 - "$requested_name" <<'PY'
import json
import subprocess
import sys

requested_name = sys.argv[1]
payload = subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    check=True,
    capture_output=True,
    text=True,
).stdout
data = json.loads(payload)
candidates = [
    device
    for runtime, devices in data["devices"].items()
    if "iOS" in runtime
    for device in devices
    if device.get("isAvailable") and device["name"].startswith("iPhone")
]

if requested_name:
    candidates = [device for device in candidates if device["name"] == requested_name]
elif any(device.get("state") == "Booted" for device in candidates):
    candidates = [device for device in candidates if device.get("state") == "Booted"]

if not candidates:
    wanted = requested_name or "an available iPhone"
    raise SystemExit(f"No available simulator found for {wanted}")

device = candidates[0]
print(f"{device['udid']}\t{device['name']}")
PY
)

IFS=$'\t' read -r device_id device_name <<<"$device_info"
app_path="$build_dir/Build/Products/Debug-iphonesimulator/TrainingCompass.app"

echo "Booting $device_name ($device_id)"
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b

echo "Building Training Compass for the simulator"
xcodebuild \
  -project TrainingCompass.xcodeproj \
  -scheme TrainingCompass \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${device_id},arch=arm64" \
  -derivedDataPath "$build_dir" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Installing and launching Training Compass"
xcrun simctl install "$device_id" "$app_path"
xcrun simctl launch "$device_id" "$bundle_id"
