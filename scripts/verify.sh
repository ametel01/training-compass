#!/usr/bin/env bash
set -euo pipefail

swift format lint --recursive --parallel --strict Sources Tests TrainingCompassApp TrainingCompassUITests
./scripts/check-boundaries.py
python3 ./scripts/check-acceptance.py
python3 ./scripts/check-personal-team-refresh.py
make verify-performance
./scripts/check-privacy.sh
make verify-evidence
./scripts/generate-fixtures.sh
swift build
swift test

if xcodebuild -version >/dev/null 2>&1; then
  xcodebuild \
    -project TrainingCompass.xcodeproj \
    -scheme TrainingCompass \
    -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build
else
  echo "Full Xcode unavailable: Release iOS build deferred to CI." >&2
fi

git diff --check HEAD
if [[ -n "${CI_BASE_REF:-}" ]]; then
  git diff --check "${CI_BASE_REF}"...HEAD
elif [[ -n "${CI_BEFORE_SHA:-}" && ! "${CI_BEFORE_SHA}" =~ ^0+$ ]] && git cat-file -e "${CI_BEFORE_SHA}^{commit}" 2>/dev/null; then
  git diff --check "${CI_BEFORE_SHA}"..HEAD
elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  git diff --check HEAD^ HEAD
fi
