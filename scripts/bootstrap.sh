#!/usr/bin/env bash
set -euo pipefail

command -v swift >/dev/null || { echo "Swift is required." >&2; exit 1; }
swift_version=$(swift --version)
grep -Eq 'Apple Swift version 6\.' <<<"$swift_version" || {
  echo "Swift 6 is required." >&2
  exit 1
}

command -v xcodebuild >/dev/null || { echo "Full Xcode 26 or newer is required." >&2; exit 1; }
if ! xcode_version=$(xcodebuild -version 2>/dev/null); then
  echo "Select a full Xcode installation with xcode-select before continuing." >&2
  exit 1
fi
major=$(awk '/^Xcode / { split($2, parts, "."); print parts[1] }' <<<"$xcode_version")
if [[ -z "$major" || "$major" -lt 26 ]]; then
  echo "Stable Xcode 26 or newer is required; found: $xcode_version" >&2
  exit 1
fi

swift package resolve
echo "Bootstrap prerequisites are ready. Personal Team signing remains user-attended."
