#!/usr/bin/env bash
set -euo pipefail

./scripts/verify.sh
./scripts/verify-migrations.sh
make verify-performance
make acceptance
./scripts/test-ui.sh

for milestone in gate-0 health-foundation unified-events training-insights recovery-evidence personal-team-refresh healthkit-write-back; do
  if [[ ! -f "evidence/device/${milestone}.json" ]]; then
    echo "Final release verification refused: ${milestone} Acceptance Device evidence is missing." >&2
    exit 1
  fi
done

VERIFY_RESULT=pass \
MIGRATION_RESULT=pass \
PRIVACY_RESULT=pass \
UI_RESULT=pass \
make evidence
python3 scripts/check-final-release.py --require-evidence
echo "Final release verification passed for Milestone 6."
