#!/usr/bin/env bash
set -euo pipefail

# Friendly, attended entry point for the guarded Personal Team refresh. This
# helper discovers the cable-connected iPhone and the local development team;
# the refresh script remains the sole owner of signing, profile inspection,
# in-place installation, launch verification, and continuity evidence.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFRESH_SCRIPT="$ROOT_DIR/scripts/refresh-personal-team.sh"
TEAM_DISCOVERY_SCRIPT="$ROOT_DIR/scripts/discover-xcode-development-team.py"
PROJECT_PATH="$ROOT_DIR/TrainingCompass.xcodeproj"
APP_BUNDLE_ID="com.ametel01.trainingcompass"
USER_HOME="${HOME:?HOME must be set for a logged-in macOS session}"
DEVICE_JSON="$(mktemp -t training-compass-install-device)"
APP_JSON="$(mktemp -t training-compass-install-app)"
APP_DATA_JSON="$(mktemp -t training-compass-install-app-data)"
BOOTSTRAP_PROFILE="$(mktemp -t training-compass-install-profile)"
SIGNING_BUILD_DIR="${TRAINING_COMPASS_SIGNING_BUILD_DIR:-$USER_HOME/Library/Developer/Xcode/DerivedData/TrainingCompassPersonalTeamSigning}"

cleanup() {
  rm -f "$DEVICE_JSON" "$APP_JSON" "$APP_DATA_JSON" "$BOOTSTRAP_PROFILE"
}
trap cleanup EXIT

fail() {
  echo "install-iphone: $1" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  local answer=""
  read -r -p "$prompt [y/N] " answer </dev/tty
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

require_attended_terminal() {
  [[ -t 0 && -r /dev/tty ]] \
    || fail "run this attended command from an interactive Terminal session"
  select_xcode_toolchain
  command -v xcrun >/dev/null 2>&1 || fail "Xcode command-line tools are unavailable"
  command -v xcodebuild >/dev/null 2>&1 || fail "full Xcode is unavailable"
  command -v python3 >/dev/null 2>&1 || fail "python3 is unavailable"
  echo "Using $(xcodebuild -version | head -n 1) from $DEVELOPER_DIR"
}

select_xcode_toolchain() {
  if [[ -n "${TRAINING_COMPASS_DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR="$TRAINING_COMPASS_DEVELOPER_DIR"
    return
  fi
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  local selected=""
  selected="$(python3 - "$USER_HOME" <<'PY'
import plistlib
import re
import sys
from pathlib import Path

home = Path(sys.argv[1])
apps = []
for root in (Path("/Applications"), home / "Applications", home / "Downloads"):
    if root.exists():
        apps.extend(root.glob("Xcode*.app"))

choices = []
for app in apps:
    developer = app / "Contents/Developer"
    info = app / "Contents/Info.plist"
    if not developer.joinpath("usr/bin/xcodebuild").is_file():
        continue
    try:
        version = str(plistlib.loads(info.read_bytes()).get("CFBundleShortVersionString", "0"))
    except (OSError, plistlib.InvalidFileException):
        continue
    numbers = tuple(int(part) for part in re.findall(r"\d+", version))
    choices.append((numbers, str(developer)))
if choices:
    print(max(choices)[1])
PY
  )"
  [[ -n "$selected" ]] || fail "no complete Xcode installation was found"
  export DEVELOPER_DIR="$selected"
}

discover_wired_iphone() {
  xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null \
    || fail "could not query CoreDevice; unlock and trust the connected iPhone"

  local requested_id="${TRAINING_COMPASS_DEVICE_ID:-${DEVICE_ID:-}}"
  python3 - "$DEVICE_JSON" "$requested_id" <<'PY'
import json
import sys

path, requested = sys.argv[1:]
payload = json.loads(open(path, encoding="utf-8").read())
candidates = []
for device in payload.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    identifier = str(device.get("identifier") or "")
    if (
        hardware.get("platform") == "iOS"
        and hardware.get("deviceType") == "iPhone"
        and str(connection.get("transportType", "")).lower() in {"wired", "usb", "cable"}
        and str(connection.get("pairingState", "")).lower() == "paired"
        and identifier
    ):
        candidates.append(identifier)

if requested:
    if requested not in candidates:
        raise SystemExit(
            "The requested device is not a paired iPhone connected by cable."
        )
    print(requested)
elif len(candidates) == 1:
    print(candidates[0])
elif not candidates:
    raise SystemExit(
        "No paired wired iPhone found. Connect, unlock, trust this Mac, and enable Developer Mode."
    )
else:
    raise SystemExit(
        "More than one wired iPhone is connected; rerun with DEVICE_ID=<CoreDevice identifier>."
    )
PY
}

discover_team_id() {
  local configured="${TRAINING_COMPASS_DEVELOPMENT_TEAM:-${TEAM_ID:-}}"
  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
    return
  fi

  local cached_team=""
  cached_team="$(
    python3 "$TEAM_DISCOVERY_SCRIPT" \
      "$USER_HOME/Library/Preferences/com.apple.dt.Xcode.plist" 2>/dev/null \
      || true
  )"
  if [[ -n "$cached_team" ]]; then
    printf '%s\n' "$cached_team"
    return
  fi

  local identities=""
  if command -v security >/dev/null 2>&1; then
    identities="$({
      security find-identity -v -p codesigning \
        "$USER_HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true
    } | sed -nE 's/.*Apple Development:.*\(([A-Z0-9]{10})\)".*/\1/p' | sort -u)"
  fi

  local identity_count="0"
  if [[ -n "$identities" ]]; then
    identity_count="$(wc -l <<<"$identities" | tr -d ' ')"
  fi
  if [[ "$identity_count" == "1" ]]; then
    printf '%s\n' "$identities"
    return
  fi

  local profile_teams=""
  profile_teams="$(
    find \
      "$USER_HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
      "$USER_HOME/Library/MobileDevice/Provisioning Profiles" \
      "$USER_HOME/Library/Developer/Xcode/DerivedData" \
      "$ROOT_DIR/DerivedData" \
      -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) \
      -print0 2>/dev/null \
      | while IFS= read -r -d '' profile; do
          security cms -D -i "$profile" 2>/dev/null \
            | plutil -extract TeamIdentifier.0 raw -o - - 2>/dev/null \
            || true
        done \
      | grep -E '^[A-Z0-9]{10}$' \
      | sort -u \
      || true
  )"
  local profile_team_count="0"
  if [[ -n "$profile_teams" ]]; then
    profile_team_count="$(wc -l <<<"$profile_teams" | tr -d ' ')"
  fi
  if [[ "$profile_team_count" == "1" ]]; then
    printf '%s\n' "$profile_teams"
    return
  fi

  local installed_team=""
  installed_team="$(python3 - "$APP_JSON" <<'PY'
import json
import re
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
teams = set()

def walk(value):
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = key.lower().replace("_", "")
            if normalized in {"teamidentifier", "teamid"}:
                candidate = str(item)
                if re.fullmatch(r"[A-Z0-9]{10}", candidate):
                    teams.add(candidate)
            walk(item)
    elif isinstance(value, list):
        for item in value:
            walk(item)

walk(payload)
if len(teams) == 1:
    print(next(iter(teams)))
PY
  )"
  if [[ -n "$installed_team" ]]; then
    printf '%s\n' "$installed_team"
    return
  fi

  fail "Xcode has no uniquely discoverable development team. In Xcode > Settings > Accounts, confirm the intended team is available; if several teams are configured, rerun with TEAM_ID=<team identifier>"
}

inspect_installed_app() {
  local device_id="$1"
  if ! xcrun devicectl device info apps \
    --device "$device_id" \
    --bundle-id "$APP_BUNDLE_ID" \
    --json-output "$APP_JSON" >/dev/null; then
    fail "could not inspect installed apps; keep the iPhone unlocked, trusted, and in Developer Mode, then rerun"
  fi
  python3 - "$APP_JSON" "$APP_BUNDLE_ID" <<'PY'
import json
import sys

path, bundle_id = sys.argv[1:]
payload = json.loads(open(path, encoding="utf-8").read())
found = False

def walk(value):
    global found
    if isinstance(value, dict):
        identifiers = {
            str(value.get("bundleIdentifier") or ""),
            str(value.get("bundleID") or ""),
        }
        if bundle_id in identifiers:
            found = True
        for item in value.values():
            walk(item)
    elif isinstance(value, list):
        for item in value:
            walk(item)

walk(payload)
print("true" if found else "false")
PY
}

installed_app_has_authoritative_store() {
  local device_id="$1"
  if ! xcrun devicectl device info files \
    --device "$device_id" \
    --domain-type appDataContainer \
    --domain-identifier "$APP_BUNDLE_ID" \
    --subdirectory 'Library/Application Support/TrainingCompass/authoritative' \
    --json-output "$APP_DATA_JSON" >/dev/null; then
    return 2
  fi
  python3 - "$APP_DATA_JSON" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
files = payload.get("result", {}).get("files", [])
found = any(
    isinstance(item, dict)
    and item.get("name") == "authoritative.sqlite"
    and not item.get("resources", {}).get("isDirectory", False)
    for item in files
)
raise SystemExit(0 if found else 1)
PY
}

resolve_verified_export() {
  local export_path="${TRAINING_COMPASS_EXPORT_PATH:-${EXPORT_PATH:-}}"
  if [[ -z "$export_path" ]]; then
    export_path="$(python3 - "$USER_HOME" <<'PY'
from pathlib import Path
import sys

home = Path(sys.argv[1])
roots = [
    home / "Downloads",
    home / "Desktop",
    home / "Documents",
    home / "Library/Mobile Documents/com~apple~CloudDocs",
]
candidates = []
for root in roots:
    if not root.exists():
        continue
    try:
        for path in root.rglob("*.trainingcompass"):
            try:
                if path.is_file() and path.stat().st_size > 0:
                    candidates.append((path.stat().st_mtime, path))
            except OSError:
                pass
    except OSError:
        pass
if candidates:
    print(max(candidates, key=lambda item: item[0])[1])
PY
    )"
  fi
  export_path="${export_path/#\~/$USER_HOME}"
  [[ -n "$export_path" && -s "$export_path" ]] \
    || fail "no local .trainingcompass export was found. In the existing iPhone app, create a Training Compass Export, share it to this Mac (Downloads is fine), verify it opens, then rerun"
  printf '%s\n' "$export_path"
}

has_login_keychain_signing_identity() {
  command -v security >/dev/null 2>&1 \
    && security find-identity -v -p codesigning \
      "$USER_HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
      | grep -Eq '[1-9][0-9]* valid identities found'
}

wait_for_login_keychain_signing_identity() {
  local attempt
  # Xcode may finish the signed build before securityd publishes the newly
  # created certificate/key pair to the login keychain. Keep this bounded, but
  # allow up to one minute for that propagation before failing the handoff.
  for attempt in {1..30}; do
    if has_login_keychain_signing_identity; then
      return 0
    fi
    sleep 2
  done
  return 1
}

signed_bootstrap_artifact_is_valid() {
  local team_id="$1"
  local app_path="$SIGNING_BUILD_DIR/Build/Products/Release-iphoneos/TrainingCompass.app"
  local application_identifier=""
  local profile_team=""
  [[ -d "$app_path" ]] \
    && codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 \
    && security cms -D -i "$app_path/embedded.mobileprovision" \
      -o "$BOOTSTRAP_PROFILE" >/dev/null 2>&1 \
    || return 1
  application_identifier="$(
    /usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' \
      "$BOOTSTRAP_PROFILE" 2>/dev/null || true
  )"
  profile_team="$(
    /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' \
      "$BOOTSTRAP_PROFILE" 2>/dev/null || true
  )"
  [[ "$application_identifier" == "$team_id.$APP_BUNDLE_ID" \
    && "$profile_team" == "$team_id" ]]
}

prepare_signing_identity() {
  local team_id="$1"
  local device_id="$2"
  if has_login_keychain_signing_identity; then
    echo "Using the existing Apple Development signing identity."
    return
  fi

  echo "No Apple Development identity is available in the login keychain."
  echo "Asking Xcode to create or refresh signing materials for this Apple Development team…"
  mkdir -p "$SIGNING_BUILD_DIR"
  TRAINING_COMPASS_DEVELOPMENT_TEAM="$team_id" xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme TrainingCompass \
    -configuration Release \
    -destination "platform=iOS,id=$device_id" \
    -derivedDataPath "$SIGNING_BUILD_DIR" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    -quiet \
    build &
  local build_pid="$!"
  while kill -0 "$build_pid" 2>/dev/null; do
    sleep 15
    if kill -0 "$build_pid" 2>/dev/null; then
      echo "Xcode is still preparing signing and compiling the first device build…"
    fi
  done
  if ! wait "$build_pid"; then
    fail "Xcode could not prepare automatic signing; open Xcode Settings > Accounts and repair the Personal Team session"
  fi
  if wait_for_login_keychain_signing_identity; then
    return
  fi
  if signed_bootstrap_artifact_is_valid "$team_id"; then
    echo "Xcode produced an exactly signed development artifact; continuing while its keychain service settles."
    return
  fi
  fail "Xcode finished without a usable identity or an exactly signed Training Compass artifact"
}

main() {
  require_attended_terminal

  local device_id team_id export_path existing_app
  if ! device_id="$(discover_wired_iphone)"; then
    fail "device discovery failed"
  fi
  existing_app="$(inspect_installed_app "$device_id")"
  team_id="$(discover_team_id)"
  [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] \
    || fail "Personal Team ID must contain exactly 10 uppercase letters or digits"
  export_path=""
  if [[ "$existing_app" == "true" ]]; then
    local store_status=0
    if installed_app_has_authoritative_store "$device_id"; then
      export_path="$(resolve_verified_export)"
      echo "Updating the existing Training Compass installation in place."
      echo "Using verified export: $export_path"
    else
      store_status="$?"
      if [[ "$store_status" == "1" ]]; then
        existing_app="false"
        echo "The installed app has no authoritative store; treating it as an interrupted fresh install."
      else
        fail "could not verify whether the installed app contains authoritative data; no install was attempted"
      fi
    fi
  else
    echo "Training Compass is not installed on this iPhone; treating this as a fresh install."
  fi

  echo "Ready to sign with Apple Development team $team_id and install on the paired wired iPhone."
  echo "No Apple Account password, keychain secret, or device identifier will be logged."
  confirm "Is this the intended owner-controlled Xcode development team?" \
    || fail "Xcode development team confirmation was not accepted"
  if [[ "$existing_app" == "true" ]]; then
    confirm "Is the selected export current, opened successfully, and verified in Training Compass?" \
      || fail "verified export confirmation was not accepted"
  fi
  confirm "Is the iPhone connected by cable, unlocked, trusted, and in Developer Mode?" \
    || fail "attended device confirmation was not accepted"

  prepare_signing_identity "$team_id" "$device_id"

  export TRAINING_COMPASS_DEVELOPMENT_TEAM="$team_id"
  export TRAINING_COMPASS_DEVICE_ID="$device_id"
  export TRAINING_COMPASS_EXPORT_PATH="$export_path"
  export TRAINING_COMPASS_EXPORT_VERIFIED="$existing_app"
  if [[ "$existing_app" == "true" ]]; then
    export TRAINING_COMPASS_FRESH_INSTALL="false"
  else
    export TRAINING_COMPASS_FRESH_INSTALL="true"
  fi
  export TRAINING_COMPASS_DEVICE_READY="true"
  export TRAINING_COMPASS_APPLE_AUTH_CONFIRMED="true"
  export TRAINING_COMPASS_PERSONAL_TEAM_CONFIRMED="true"

  exec "$REFRESH_SCRIPT" --refresh
}

main "$@"
