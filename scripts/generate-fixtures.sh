#!/usr/bin/env bash
set -euo pipefail

fixture_path="fixtures/gate-zero.json"
generated=$(mktemp)
trap 'rm -f "$generated"' EXIT

swift run training-fixtures --seed 21571 >"$generated"

if [[ "${UPDATE_FIXTURES:-0}" == "1" ]]; then
  cp "$generated" "$fixture_path"
fi

if ! cmp -s "$generated" "$fixture_path"; then
  diff -u "$fixture_path" "$generated" || true
  echo "Synthetic fixtures are stale. Review, then run UPDATE_FIXTURES=1 make fixtures." >&2
  exit 1
fi

echo "Synthetic fixture seed 21571 is deterministic."
