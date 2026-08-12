#!/usr/bin/env bash
set -euo pipefail

./scripts/verify.sh
./scripts/test-ui.sh

if [[ ! -f evidence/device/gate-0.json ]]; then
  echo "Release verification refused: Gate 0 Acceptance Device evidence is missing." >&2
  exit 1
fi
python3 - <<'PY'
import json
from pathlib import Path

record = json.loads(Path("evidence/device/gate-0.json").read_text())
if record.get("result") != "pass":
    raise SystemExit("Release verification refused: device evidence is not passing.")
PY
echo "Gate 0 release protocol passed. This still does not approve owner data."
