#!/usr/bin/env bash
set -euo pipefail

fixture_path="fixtures/gate-zero.json"
verification_fixture_path="fixtures/verification-envelope.json"
generated=$(mktemp)
generated_verification=$(mktemp)
trap 'rm -f "$generated" "$generated_verification"' EXIT

swift run training-fixtures --seed 21571 >"$generated"
swift run training-fixtures --seed 21571 --profile verification-envelope >"$generated_verification"

if [[ "${UPDATE_FIXTURES:-0}" == "1" ]]; then
  cp "$generated" "$fixture_path"
  cp "$generated_verification" "$verification_fixture_path"
fi

if ! cmp -s "$generated" "$fixture_path"; then
  diff -u "$fixture_path" "$generated" || true
  echo "Synthetic fixtures are stale. Review, then run UPDATE_FIXTURES=1 make fixtures." >&2
  exit 1
fi
if ! cmp -s "$generated_verification" "$verification_fixture_path"; then
  diff -u "$verification_fixture_path" "$generated_verification" || true
  echo "Verification envelope fixture is stale. Review, then run UPDATE_FIXTURES=1 make fixtures." >&2
  exit 1
fi

python3 scripts/check-verification-envelope.py "$verification_fixture_path"
echo "Synthetic fixture seed 21571 and verification envelope are deterministic."
