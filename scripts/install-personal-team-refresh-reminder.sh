#!/usr/bin/env bash
set -euo pipefail

# Installs a per-user LaunchAgent only. The agent runs a preflight/reminder in
# the logged-in Aqua session; it never builds, signs, installs, or handles
# credentials on its own.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_HOME="${HOME:?HOME must be set for a logged-in macOS session}"
LAUNCH_AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/com.ametel01.trainingcompass.personal-team-refresh.plist"
LOG_DIR="${TRAINING_COMPASS_REFRESH_LOG_DIR:-$USER_HOME/Library/Logs/TrainingCompass}"
SCRIPT_PATH="$ROOT_DIR/scripts/refresh-personal-team.sh"
DOMAIN="gui/$(id -u)"

if [[ "$(id -u)" == "0" ]]; then
  echo "Install this reminder as the logged-in owner, not as root." >&2
  exit 1
fi
if [[ ! -x "$SCRIPT_PATH" ]]; then
  echo "Refresh workflow is missing or not executable: $SCRIPT_PATH" >&2
  exit 1
fi

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

python3 - "$PLIST_PATH" "$SCRIPT_PATH" "$LOG_DIR" <<'PY'
import plistlib
import os
import sys
from pathlib import Path

plist_path, script_path, log_dir = sys.argv[1:]
payload = {
    "Label": "com.ametel01.trainingcompass.personal-team-refresh",
    "ProgramArguments": ["/bin/bash", script_path, "--remind"],
    "RunAtLoad": True,
    "StartInterval": 86400,
    "LimitLoadToSessionType": "Aqua",
    "ProcessType": "Interactive",
    "StandardOutPath": str(Path(log_dir) / "personal-team-refresh-reminder.log"),
    "StandardErrorPath": str(Path(log_dir) / "personal-team-refresh-reminder.log"),
}
environment = {
    name: os.environ[name]
    for name in (
        "TRAINING_COMPASS_DEVELOPMENT_TEAM",
        "TRAINING_COMPASS_DEVICE_ID",
        "TRAINING_COMPASS_EXPORT_PATH",
        "TRAINING_COMPASS_EXPORT_VERIFIED",
        "TRAINING_COMPASS_DEVICE_READY",
    )
    if os.environ.get(name)
}
if environment:
    payload["EnvironmentVariables"] = environment
path = Path(plist_path)
path.write_bytes(plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=False))
path.chmod(0o600)
PY

launchctl bootout "$DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
echo "Installed the daily Personal Team preflight reminder for the logged-in user."
echo "It will never build, install, uninstall, or store credentials without an attended refresh command."
