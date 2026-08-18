#!/usr/bin/env bash
set -euo pipefail

# The Personal Team path is deliberately an attended maintenance workflow.
# This script never receives, stores, or forwards Apple Account or keychain
# credentials. It only uses the normal Xcode session and the user's unlocked
# login keychain.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/TrainingCompass.xcodeproj"
SCHEME="TrainingCompass"
CONFIGURATION="Release"
APP_BUNDLE_ID="com.ametel01.trainingcompass"
USER_HOME="${HOME:?HOME must be set for a logged-in macOS session}"
LOG_DIR="${TRAINING_COMPASS_REFRESH_LOG_DIR:-$USER_HOME/Library/Logs/TrainingCompass}"
STATE_DIR="${TRAINING_COMPASS_REFRESH_STATE_DIR:-$USER_HOME/Library/Application Support/TrainingCompass}"
BUILD_DIR="${TRAINING_COMPASS_REFRESH_BUILD_DIR:-$USER_HOME/Library/Developer/Xcode/DerivedData/TrainingCompassPersonalTeamRefresh}"
CHECKS_FILE="$(mktemp -t training-compass-refresh-checks)"
PROFILE_PLIST="$(mktemp -t training-compass-refresh-profile)"
DEVICE_JSON="$(mktemp -t training-compass-refresh-device)"
LOCK_JSON="$(mktemp -t training-compass-refresh-lock)"
COMMAND_OUTPUT="$(mktemp -t training-compass-refresh-command)"
PROFILE_CREATION_DATE=""
PROFILE_EXPIRATION_DATE=""
XCODE_VERSION="unknown"
APP_PATH=""
RESULT="fail"
FAILURES=()
macos_version="$(sw_vers -productVersion 2>/dev/null || true)"
export TRAINING_COMPASS_MACOS_VERSION="$macos_version"

cleanup() {
  rm -f "$CHECKS_FILE" "$PROFILE_PLIST" "$DEVICE_JSON" "$LOCK_JSON" "$COMMAND_OUTPUT"
}
trap cleanup EXIT

mkdir -p "$LOG_DIR" "$STATE_DIR"
LOG_PATH="$LOG_DIR/personal-team-refresh.log"
touch "$LOG_PATH"
chmod 600 "$LOG_PATH"
: > "$LOG_PATH"

record_check() {
  local name="$1"
  local status="$2"
  printf '%s\t%s\n' "$name" "$status" >> "$CHECKS_FILE"
}

pass_check() {
  record_check "$1" "pass"
}

fail_check() {
  local name="$1"
  record_check "$name" "fail"
  FAILURES+=("$name")
}

manual_check() {
  record_check "$1" "manual"
}

manual_failure_check() {
  manual_check "$1"
  FAILURES+=("$1")
}

record_stage() {
  printf 'stage=%s result=%s\n' "$1" "$2" >> "$LOG_PATH"
}

command_available() {
  command -v "$1" >/dev/null 2>&1
}

login_keychain_signing_identity_available() {
  local login_keychain="$USER_HOME/Library/Keychains/login.keychain-db"
  local attempt
  # Xcode can finish signing before securityd publishes the new identity to
  # the login keychain. Allow the same bounded one-minute propagation window
  # used by the attended installer.
  for attempt in {1..30}; do
    if command_available security \
      && [[ -f "$login_keychain" ]] \
      && security find-identity -v -p codesigning "$login_keychain" 2>/dev/null \
        | grep -Eq '[1-9][0-9]* valid identities found'; then
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_for_unlocked_device() {
  local device_id="$1"
  local attempt
  echo "Keep the iPhone unlocked while Training Compass is installed and launched…"
  for attempt in {1..30}; do
    if xcrun devicectl device info lockState \
      --device "$device_id" \
      --json-output "$LOCK_JSON" >"$COMMAND_OUTPUT" 2>&1 \
      && python3 - "$LOCK_JSON" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
raise SystemExit(0 if payload.get("result", {}).get("passcodeRequired") is False else 1)
PY
    then
      return 0
    fi
    sleep 2
  done
  return 1
}

run_preflight() {
  local team_id="${TRAINING_COMPASS_DEVELOPMENT_TEAM:-}"
  local device_id="${TRAINING_COMPASS_DEVICE_ID:-}"
  local export_path="${TRAINING_COMPASS_EXPORT_PATH:-}"
  local export_verified="${TRAINING_COMPASS_EXPORT_VERIFIED:-false}"
  local fresh_install="${TRAINING_COMPASS_FRESH_INSTALL:-false}"
  local device_ready="${TRAINING_COMPASS_DEVICE_READY:-false}"
  local apple_auth_confirmed="${TRAINING_COMPASS_APPLE_AUTH_CONFIRMED:-false}"
  local personal_team_confirmed="${TRAINING_COMPASS_PERSONAL_TEAM_CONFIRMED:-false}"
  local settings_output=""
  local xcode_major="0"
  local login_keychain="$USER_HOME/Library/Keychains/login.keychain-db"

  if [[ "$(id -u)" == "0" ]]; then
    fail_check "loggedInUserSession"
  elif [[ "$(stat -f '%Su' /dev/console 2>/dev/null || true)" != "$(id -un)" ]]; then
    fail_check "loggedInUserSession"
  else
    pass_check "loggedInUserSession"
  fi

  if ! command_available xcodebuild; then
    fail_check "xcodeInstallation"
  else
    XCODE_VERSION="$(xcodebuild -version 2>/dev/null | head -n 1 || true)"
    xcode_major="$(awk '{print $2}' <<<"$XCODE_VERSION" | cut -d. -f1)"
    if [[ "$xcode_major" =~ ^[0-9]+$ ]] && (( xcode_major >= 26 )); then
      pass_check "xcodeInstallation"
    else
      fail_check "xcodeInstallation"
    fi
  fi

  if [[ -z "$team_id" || ! "$team_id" =~ ^[A-Z0-9]{10}$ ]] \
    || [[ "$personal_team_confirmed" != "true" ]]; then
    fail_check "personalTeamConfiguration"
  else
    pass_check "personalTeamConfiguration"
  fi

  if [[ ! -d "$PROJECT_PATH" ]]; then
    fail_check "stableProject"
  else
    pass_check "stableProject"
  fi

  if [[ -n "$team_id" && -x "$(command -v xcodebuild 2>/dev/null || true)" ]]; then
    if settings_output="$(
      TRAINING_COMPASS_DEVELOPMENT_TEAM="$team_id" xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -showBuildSettings 2>/dev/null
    )"; then
      if grep -Fq "PRODUCT_BUNDLE_IDENTIFIER = $APP_BUNDLE_ID" <<<"$settings_output" \
        && grep -Fq "CODE_SIGN_STYLE = Automatic" <<<"$settings_output" \
        && grep -Fq "DEVELOPMENT_TEAM = $team_id" <<<"$settings_output"; then
        pass_check "stableAppID"
        pass_check "automaticSigning"
      else
        fail_check "stableAppID"
        fail_check "automaticSigning"
      fi
    else
      fail_check "stableAppID"
      fail_check "automaticSigning"
    fi
  else
    fail_check "stableAppID"
    fail_check "automaticSigning"
  fi

  if login_keychain_signing_identity_available; then
    pass_check "loginKeychainSigningIdentity"
  else
    fail_check "loginKeychainSigningIdentity"
  fi

  if [[ -n "$team_id" && -x "$(command -v xcodebuild 2>/dev/null || true)" ]] \
    && TRAINING_COMPASS_DEVELOPMENT_TEAM="$team_id" xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -showBuildSettings \
      -allowProvisioningUpdates >"$COMMAND_OUTPUT" 2>&1; then
    if [[ "$apple_auth_confirmed" == "true" ]]; then
      pass_check "appleAuthentication"
    else
      manual_failure_check "appleAuthentication"
    fi
  else
    fail_check "appleAuthentication"
  fi

  if [[ "$fresh_install" == "true" ]]; then
    record_check "verifiedTrainingCompassExport" "not applicable (fresh install)"
  elif [[ -n "$export_path" && -s "$export_path" && "$export_verified" == "true" ]]; then
    pass_check "verifiedTrainingCompassExport"
  else
    fail_check "verifiedTrainingCompassExport"
  fi

  if [[ -z "$device_id" ]]; then
    fail_check "pinnedDeviceIdentifier"
    fail_check "devicePairing"
    fail_check "deviceConnection"
    fail_check "cableConnectivity"
    fail_check "recentUnlock"
    fail_check "developerMode"
  elif ! command_available xcrun \
    || ! xcrun devicectl list devices --json-output "$DEVICE_JSON" >"$COMMAND_OUTPUT" 2>&1; then
    pass_check "pinnedDeviceIdentifier"
    fail_check "devicePairing"
    fail_check "deviceConnection"
    fail_check "cableConnectivity"
    fail_check "recentUnlock"
    fail_check "developerMode"
  else
    pass_check "pinnedDeviceIdentifier"
    local device_summary
    device_summary="$(python3 - "$DEVICE_JSON" "$device_id" <<'PY'
import json
import sys

path, target = sys.argv[1:]
payload = json.loads(open(path, encoding="utf-8").read())
found = False
developer_mode = "unknown"
locked = "unknown"
transport = "unknown"

def walk(value):
    global found, developer_mode, locked, transport
    if isinstance(value, dict):
        identity = str(
            value.get("identifier")
            or value.get("udid")
            or value.get("deviceIdentifier")
            or ""
        )
        if identity == target:
            found = True
            for key, item in value.items():
                normalized = key.lower().replace("_", "")
                if normalized in {"developermode", "developermodeenabled"}:
                    developer_mode = "true" if item is True else "false" if item is False else str(item)
                elif normalized in {"islocked", "locked"}:
                    locked = "true" if item is True else "false" if item is False else str(item)
                elif normalized in {"transport", "transporttype", "connectiontype"}:
                    transport = str(item).lower()
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)

walk(payload)
print(f"{str(found).lower()} {developer_mode} {locked} {transport}")
PY
    )"
    local device_found developer_mode device_locked transport
    read -r device_found developer_mode device_locked transport <<<"$device_summary"
    if [[ "$device_found" == "true" ]]; then
      pass_check "devicePairing"
      pass_check "deviceConnection"
    else
      fail_check "devicePairing"
      fail_check "deviceConnection"
    fi
    if [[ "$transport" == *usb* || "$transport" == *wired* || "$transport" == *cable* ]]; then
      pass_check "cableConnectivity"
    elif [[ "$device_ready" == "true" && "$transport" == "unknown" ]]; then
      record_check "cableConnectivity" "pass (owner-confirmed)"
    elif [[ "$transport" == *wifi* ]]; then
      fail_check "cableConnectivity"
    else
      fail_check "cableConnectivity"
    fi
    if [[ "$device_locked" == "false" ]]; then
      pass_check "recentUnlock"
    elif [[ "$device_locked" == "true" ]]; then
      fail_check "recentUnlock"
    else
      manual_check "recentUnlock"
    fi
    if [[ "$developer_mode" == "true" ]]; then
      pass_check "developerMode"
    elif [[ "$developer_mode" == "false" ]]; then
      fail_check "developerMode"
    else
      manual_check "developerMode"
    fi
  fi

  if [[ "$device_ready" == "true" ]]; then
    record_check "attendedDeviceConfirmation" "pass"
  else
    fail_check "attendedDeviceConfirmation"
  fi

  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    return 0
  fi
  return 1
}

inspect_profile() {
  local app_path="$1"
  local team_id="${TRAINING_COMPASS_DEVELOPMENT_TEAM:-}"
  local application_identifier=""
  local profile_team=""
  local profile_bundle=""
  local profile_devices=""
  local profile_failed=0

  if [[ ! -f "$app_path/embedded.mobileprovision" ]] \
    || ! security cms -D -i "$app_path/embedded.mobileprovision" -o "$PROFILE_PLIST" >"$COMMAND_OUTPUT" 2>&1; then
    fail_check "embeddedProvisioningProfile"
    return 1
  fi

  PROFILE_CREATION_DATE="$(plutil -extract CreationDate raw -o - "$PROFILE_PLIST" 2>/dev/null || true)"
  PROFILE_EXPIRATION_DATE="$(plutil -extract ExpirationDate raw -o - "$PROFILE_PLIST" 2>/dev/null || true)"
  application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"
  profile_team="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"
  profile_bundle="${application_identifier#*.}"
  profile_devices="$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$PROFILE_PLIST" 2>/dev/null || true)"

  if [[ "$profile_bundle" == "$APP_BUNDLE_ID" && "$profile_team" == "$team_id" ]]; then
    pass_check "stableProvisionedAppID"
  else
    fail_check "stableProvisionedAppID"
    profile_failed=1
  fi
  if [[ -n "$profile_devices" ]]; then
    pass_check "personalTeamDevelopmentProfile"
  else
    fail_check "personalTeamDevelopmentProfile"
    profile_failed=1
  fi
  if [[ -n "$PROFILE_EXPIRATION_DATE" ]]; then
    pass_check "profileDates"
    if python3 - "$PROFILE_EXPIRATION_DATE" <<'PY'
from datetime import datetime, timezone
import sys

value = sys.argv[1]
for format_string in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%dT%H:%M:%S%z"):
    try:
        expiration = datetime.strptime(value, format_string)
        break
    except ValueError:
        expiration = None
if expiration is None or expiration.astimezone(timezone.utc) <= datetime.now(timezone.utc):
    raise SystemExit(1)
PY
    then
      pass_check "profileNotExpired"
    else
      fail_check "profileNotExpired"
      profile_failed=1
    fi
  else
    fail_check "profileDates"
    fail_check "profileNotExpired"
    profile_failed=1
  fi
  return "$profile_failed"
}

write_record() {
  local result="$1"
  local record_path="$STATE_DIR/last-personal-team-refresh.json"
  local failure_json
  failure_json="$(printf '%s\n' "${FAILURES[@]}" | python3 -c 'import json, sys; print(json.dumps([line for line in sys.stdin.read().splitlines() if line]))')"
  python3 - "$CHECKS_FILE" "$record_path" "$result" "$failure_json" "${TRAINING_COMPASS_FRESH_INSTALL:-false}" <<'PY'
import json
import os
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path

checks_path, record_path, result, failures_json, fresh_install = sys.argv[1:]
checks = {}
for line in Path(checks_path).read_text().splitlines():
    if "\t" in line:
        name, status = line.split("\t", 1)
        checks[name] = status
previous_profile = {}
previous_path = Path(record_path)
if previous_path.exists():
    try:
        previous_profile = json.loads(previous_path.read_text()).get("profile", {})
    except (OSError, json.JSONDecodeError):
        previous_profile = {}
record = {
    "schemaVersion": 1,
    "workflow": "attended-personal-team-refresh",
    "recordedAt": datetime.now(timezone.utc).isoformat(),
    "result": result,
    "checks": checks,
    "failureChecks": json.loads(failures_json),
    "environment": {
        "platform": platform.platform(),
        "macOSVersion": os.environ.get("TRAINING_COMPASS_MACOS_VERSION", "unknown"),
        "xcodeVersion": os.environ.get("TRAINING_COMPASS_XCODE_VERSION", "unknown"),
        "bundleIdentifier": "com.ametel01.trainingcompass",
    },
    "profile": {
        "creationDate": os.environ.get("TRAINING_COMPASS_PROFILE_CREATION_DATE")
        or previous_profile.get("creationDate", "unknown"),
        "expirationDate": os.environ.get("TRAINING_COMPASS_PROFILE_EXPIRATION_DATE")
        or previous_profile.get("expirationDate", "unknown"),
        "kind": "Personal Team development profile",
    },
    "dataVerification": os.environ.get("TRAINING_COMPASS_DATA_VERIFIED", "false") == "true",
    "notes": (
        [
            "No Apple Account or keychain credentials are stored.",
            "A fresh install was performed; there was no existing app dataset to replace.",
            "No uninstall step exists in this workflow.",
        ]
        if fresh_install == "true"
        else [
            "No Apple Account or keychain credentials are stored.",
            "The existing app was updated in place; no uninstall step exists in this workflow.",
            "The owner must retain a verified Training Compass Export before refresh.",
        ]
    ),
}
path = Path(record_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
path.chmod(0o600)
PY
  cp "$record_path" "$LOG_DIR/last-personal-team-refresh.json"
  chmod 600 "$LOG_DIR/last-personal-team-refresh.json"
}

profile_due_state() {
  local record_path="$STATE_DIR/last-personal-team-refresh.json"
  python3 - "$record_path" <<'PY'
from datetime import datetime, timezone
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
if not path.exists():
    print("unknown")
    raise SystemExit
try:
    value = json.loads(path.read_text()).get("profile", {}).get("expirationDate", "")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
except (OSError, ValueError, json.JSONDecodeError):
    print("unknown")
    raise SystemExit
days_remaining = (parsed.astimezone(timezone.utc) - datetime.now(timezone.utc)).total_seconds() / 86400
print("due" if days_remaining <= 2 else "not_due")
PY
}

notify_owner() {
  local message="$1"
  if command_available osascript; then
    osascript -e "display notification \"$message\" with title \"Training Compass\"" \
      >/dev/null 2>/dev/null || true
  fi
}

run_reminder() {
  FAILURES=()
  local due_state
  due_state="$(profile_due_state)"
  if [[ "$due_state" == "not_due" ]]; then
    return 0
  fi
  if ! run_preflight; then
    RESULT="fail"
    export TRAINING_COMPASS_XCODE_VERSION="$XCODE_VERSION"
    write_record "$RESULT"
    notify_owner "Refresh preflight needs your attention; open Terminal for the named checks."
    return 0
  fi
  RESULT="pass"
  export TRAINING_COMPASS_XCODE_VERSION="$XCODE_VERSION"
  write_record "$RESULT"
  notify_owner "Personal Team refresh is ready to run while your iPhone is connected and unlocked."
}

run_refresh() {
  FAILURES=()
  if ! run_preflight; then
    RESULT="fail"
    export TRAINING_COMPASS_XCODE_VERSION="$XCODE_VERSION"
    write_record "$RESULT"
    echo "Personal Team refresh preflight failed: ${FAILURES[*]}" >&2
    return 1
  fi

  local team_id="${TRAINING_COMPASS_DEVELOPMENT_TEAM:?TRAINING_COMPASS_DEVELOPMENT_TEAM is required}"
  local device_id="${TRAINING_COMPASS_DEVICE_ID:?TRAINING_COMPASS_DEVICE_ID is required}"
  export TRAINING_COMPASS_XCODE_VERSION="$XCODE_VERSION"
  export TRAINING_COMPASS_DATA_VERIFIED="false"
  local fresh_install="${TRAINING_COMPASS_FRESH_INSTALL:-false}"

  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  TRAINING_COMPASS_DEVELOPMENT_TEAM="$team_id" xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    build >"$COMMAND_OUTPUT" 2>&1 &
  local build_pid="$!"
  echo "Building the signed Release app for the connected iPhone…"
  while kill -0 "$build_pid" 2>/dev/null; do
    sleep 15
    if kill -0 "$build_pid" 2>/dev/null; then
      echo "The signed Release build is still compiling…"
    fi
  done
  if wait "$build_pid"; then
    pass_check "build"
    record_stage "build" "pass"
  else
    fail_check "build"
    record_stage "build" "fail"
    RESULT="fail"
    write_record "$RESULT"
    echo "Personal Team refresh build failed; the existing app was left installed." >&2
    return 1
  fi

  APP_PATH="$BUILD_DIR/Build/Products/Release-iphoneos/TrainingCompass.app"
  if [[ -d "$APP_PATH" ]]; then
    pass_check "releaseArtifact"
  else
    fail_check "releaseArtifact"
    RESULT="fail"
    write_record "$RESULT"
    echo "Release app was not produced; the existing app was left installed." >&2
    return 1
  fi

  if inspect_profile "$APP_PATH"; then
    export TRAINING_COMPASS_PROFILE_CREATION_DATE="$PROFILE_CREATION_DATE"
    export TRAINING_COMPASS_PROFILE_EXPIRATION_DATE="$PROFILE_EXPIRATION_DATE"
  else
    RESULT="fail"
    write_record "$RESULT"
    echo "Embedded provisioning profile was invalid; the existing app was left installed." >&2
    return 1
  fi

  if ! wait_for_unlocked_device "$device_id"; then
    fail_check "recentUnlock"
    RESULT="fail"
    write_record "$RESULT"
    echo "The iPhone remained locked; no install was attempted." >&2
    return 1
  fi

  echo "Installing Training Compass on the connected iPhone…"
  if xcrun devicectl device install app --device "$device_id" "$APP_PATH" >"$COMMAND_OUTPUT" 2>&1; then
    pass_check "inPlaceInstall"
    record_stage "inPlaceInstall" "pass"
  else
    fail_check "inPlaceInstall"
    record_stage "inPlaceInstall" "fail"
    RESULT="fail"
    write_record "$RESULT"
    echo "In-place install failed; no uninstall was attempted." >&2
    return 1
  fi

  if ! wait_for_unlocked_device "$device_id"; then
    fail_check "recentUnlock"
    RESULT="fail"
    write_record "$RESULT"
    echo "The iPhone locked before launch; the installed app and its data were left in place." >&2
    return 1
  fi

  echo "Launching Training Compass for the smoke test…"
  if xcrun devicectl device process launch --device "$device_id" "$APP_BUNDLE_ID" >"$COMMAND_OUTPUT" 2>&1; then
    pass_check "launchSmokeTest"
    record_stage "launchSmokeTest" "pass"
  else
    fail_check "launchSmokeTest"
    record_stage "launchSmokeTest" "fail"
    RESULT="fail"
    write_record "$RESULT"
    echo "Launch smoke test failed; the installed app and its data were left in place." >&2
    return 1
  fi

  if [[ "$fresh_install" == "true" ]]; then
    record_check "importantLocalData" "not applicable (fresh install)"
  elif [[ "${TRAINING_COMPASS_DATA_VERIFIED:-false}" == "true" ]]; then
    pass_check "importantLocalData"
    export TRAINING_COMPASS_DATA_VERIFIED="true"
  elif [[ -t 0 && -r /dev/tty ]]; then
    printf '%s\n' "Open Training Compass and confirm Today, Cycle, Progress, TMs, Health, and the verified export/restore path are present." >&2
    read -r -p "Did the in-place refresh preserve important local data? [y/N] " data_answer </dev/tty
    if [[ "$data_answer" == "y" || "$data_answer" == "Y" ]]; then
      pass_check "importantLocalData"
      export TRAINING_COMPASS_DATA_VERIFIED="true"
    else
      fail_check "importantLocalData"
    fi
  else
    fail_check "importantLocalData"
  fi

  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    RESULT="pass"
    write_record "$RESULT"
    if [[ "$fresh_install" == "true" ]]; then
      echo "Personal Team install completed: app installed, profile inspected, and launch smoke test passed."
    else
      echo "Personal Team refresh completed: app updated in place, profile inspected, and launch smoke test passed."
    fi
    return 0
  fi
  RESULT="fail"
  write_record "$RESULT"
  echo "Personal Team refresh completed with failed checks: ${FAILURES[*]}" >&2
  return 1
}

mode="${1:-refresh}"
case "$mode" in
  --preflight)
    if run_preflight; then
      RESULT="pass"
      export TRAINING_COMPASS_XCODE_VERSION="$XCODE_VERSION"
      write_record "$RESULT"
      echo "Personal Team refresh preflight passed."
    else
      RESULT="fail"
      export TRAINING_COMPASS_XCODE_VERSION="$XCODE_VERSION"
      write_record "$RESULT"
      echo "Personal Team refresh preflight failed: ${FAILURES[*]}" >&2
      exit 1
    fi
    ;;
  --remind)
    run_reminder
    ;;
  --refresh|refresh)
    run_refresh
    ;;
  *)
    echo "Usage: $0 [--preflight|--remind|--refresh]" >&2
    exit 2
    ;;
esac
