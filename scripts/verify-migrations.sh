#!/usr/bin/env bash
set -euo pipefail

swift run training-migration-verifier

if xcodebuild -version >/dev/null 2>&1; then
  swift test --filter ProtectedStoreBootstrapTests
else
  echo "Full Xcode unavailable: XCTest migration assertions deferred to CI." >&2
fi
