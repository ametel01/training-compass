#!/usr/bin/env python3
"""Validate the attended Personal Team refresh contract without Xcode.

The physical-device commands are intentionally not run in CI. This check keeps
the safe boundary executable: stable identity, explicit attended gates,
profile inspection, in-place install, privacy-safe evidence, and a per-user
reminder must remain present in the repository.
"""

from __future__ import annotations

import re
import subprocess
import tempfile
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REFRESH = ROOT / "scripts/refresh-personal-team.sh"
CONNECTED_INSTALLER = ROOT / "scripts/install-connected-iphone.sh"
TEAM_DISCOVERY = ROOT / "scripts/discover-xcode-development-team.py"
INSTALLER = ROOT / "scripts/install-personal-team-refresh-reminder.sh"
CHECKLIST = ROOT / "documentation/developer/reference/personal-team-refresh-device-checklist.md"
COMMAND_CONTRACT = ROOT / "documentation/developer/reference/command-contract.md"
MAKEFILE = ROOT / "Makefile"
PROJECT = ROOT / "TrainingCompass.xcodeproj/project.pbxproj"


def require(needle: str, text: str, errors: list[str], label: str) -> None:
    if needle not in text:
        errors.append(f"{label} omits required contract: {needle}")


def main() -> int:
    errors: list[str] = []
    for path in (
        REFRESH,
        CONNECTED_INSTALLER,
        TEAM_DISCOVERY,
        INSTALLER,
        CHECKLIST,
        COMMAND_CONTRACT,
        MAKEFILE,
        PROJECT,
    ):
        if not path.exists():
            errors.append(f"missing Personal Team refresh artifact: {path.relative_to(ROOT)}")

    if errors:
        for error in errors:
            print(f"- {error}")
        return 1

    refresh = REFRESH.read_text()
    connected_installer = CONNECTED_INSTALLER.read_text()
    installer = INSTALLER.read_text()
    checklist = CHECKLIST.read_text()
    command_contract = COMMAND_CONTRACT.read_text()
    makefile = MAKEFILE.read_text()
    project = PROJECT.read_text()

    if not REFRESH.stat().st_mode & 0o111:
        errors.append("refresh workflow is not executable")
    if not CONNECTED_INSTALLER.stat().st_mode & 0o111:
        errors.append("connected-iPhone installer is not executable")
    if not INSTALLER.stat().st_mode & 0o111:
        errors.append("LaunchAgent installer is not executable")

    for command in (REFRESH, CONNECTED_INSTALLER, INSTALLER):
        result = subprocess.run(["bash", "-n", str(command)], capture_output=True, text=True)
        if result.returncode:
            errors.append(f"{command.relative_to(ROOT)} has invalid shell syntax: {result.stderr.strip()}")

    with tempfile.TemporaryDirectory() as directory:
        preferences = Path(directory) / "com.apple.dt.Xcode.plist"
        preferences.write_bytes(
            plistlib.dumps(
                {
                    "IDEProvisioningTeamByIdentifier": {
                        "account": [
                            {
                                "teamID": "A1B2C3D4E5",
                                "teamType": "Individual",
                                "isFreeProvisioningTeam": False,
                            }
                        ]
                    }
                }
            )
        )
        result = subprocess.run(
            ["python3", str(TEAM_DISCOVERY), str(preferences)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or result.stdout.strip() != "A1B2C3D4E5":
            errors.append("Xcode cached Individual development team is not auto-discovered")

    for needle in (
        'APP_BUNDLE_ID="com.ametel01.trainingcompass"',
        "TRAINING_COMPASS_DEVELOPMENT_TEAM",
        "TRAINING_COMPASS_DEVICE_ID",
        "TRAINING_COMPASS_EXPORT_PATH",
        "TRAINING_COMPASS_EXPORT_VERIFIED",
        "TRAINING_COMPASS_DEVICE_READY",
        "TRAINING_COMPASS_APPLE_AUTH_CONFIRMED",
        "TRAINING_COMPASS_PERSONAL_TEAM_CONFIRMED",
        "appleAuthentication",
        "loginKeychainSigningIdentity",
        "devicePairing",
        "cableConnectivity",
        "recentUnlock",
        "developerMode",
        "-allowProvisioningUpdates",
        "security cms -D -i",
        "ProvisionedDevices",
        "profileNotExpired",
        "devicectl device install app --device",
        "devicectl device process launch --device",
        "importantLocalData",
        "No Apple Account or keychain credentials are stored.",
        "no uninstall step exists",
    ):
        require(needle, refresh, errors, "refresh workflow")

    for needle in (
        "xcrun devicectl list devices --json-output",
        "xcrun devicectl device info apps",
        "select_xcode_toolchain",
        "discover-xcode-development-team.py",
        'hardware.get("deviceType") == "iPhone"',
        'connection.get("transportType", "")',
        'connection.get("pairingState", "")',
        "TRAINING_COMPASS_DEVELOPMENT_TEAM",
        "TRAINING_COMPASS_DEVICE_ID",
        "TRAINING_COMPASS_EXPORT_PATH",
        "TRAINING_COMPASS_EXPORT_VERIFIED",
        "TRAINING_COMPASS_FRESH_INSTALL",
        "TRAINING_COMPASS_DEVICE_READY",
        "TRAINING_COMPASS_APPLE_AUTH_CONFIRMED",
        "TRAINING_COMPASS_PERSONAL_TEAM_CONFIRMED",
        "has_login_keychain_signing_identity",
        "wait_for_login_keychain_signing_identity",
        "signed_bootstrap_artifact_is_valid",
        "Xcode is still preparing signing and compiling",
        "-allowProvisioningDeviceRegistration",
        'exec "$REFRESH_SCRIPT" --refresh',
        "no local .trainingcompass export was found",
    ):
        require(needle, connected_installer, errors, "connected-iPhone installer")

    require(
        "login_keychain_signing_identity_available",
        refresh,
        errors,
        "refresh workflow",
    )

    for forbidden_prompt in ("Personal Team ID:", "Verified export path:"):
        if forbidden_prompt in connected_installer:
            errors.append(f"connected-iPhone installer still prompts for {forbidden_prompt}")

    for needle in (
        'StartInterval": 86400',
        'LimitLoadToSessionType": "Aqua"',
        '"--remind"',
        "launchctl bootstrap",
        "It will never build, install, uninstall, or store credentials",
    ):
        require(needle, installer, errors, "LaunchAgent installer")

    for needle in (
        "one explicit bundle ID",
        "verified Training Compass Export",
        "Developer Mode",
        "profile creation/expiration dates",
        "no uninstall or delete command",
        "temporary inability to launch",
        "Never put\n  those secrets",
    ):
        require(needle, checklist, errors, "Acceptance Device checklist")

    device_smoke = (ROOT / "scripts/device-smoke.sh").read_text()
    for needle in (
        '"profile"',
        '"privacySafeNotes"',
        "PERSONAL_TEAM_PROFILE_CREATION_DATE",
        "PERSONAL_TEAM_PROFILE_EXPIRATION_DATE",
    ):
        require(needle, device_smoke, errors, "device-smoke Personal Team evidence")

    require("personal-team-refresh:", makefile, errors, "Makefile")
    require("install-iphone:", makefile, errors, "Makefile")
    require("install-personal-team-refresh-reminder:", makefile, errors, "Makefile")
    require("make personal-team-refresh", command_contract, errors, "command contract")
    require("make install-iphone", command_contract, errors, "command contract")
    require("make install-personal-team-refresh-reminder", command_contract, errors, "command contract")
    require('PRODUCT_BUNDLE_IDENTIFIER = com.ametel01.trainingcompass', project, errors, "Xcode project")
    require('DEVELOPMENT_TEAM = "$(TRAINING_COMPASS_DEVELOPMENT_TEAM)"', project, errors, "Xcode project")
    require('CODE_SIGN_STYLE = Automatic', project, errors, "Xcode project")

    forbidden_patterns = (
        r"security\s+[^\n]*\s-p\s+(?:password|passphrase|secret|keychain)",
        r"(?:APPLE|KEYCHAIN|TRAINING_COMPASS)_(?:ACCOUNT|PASSWORD|PASSCODE)",
        r"devicectl\s+device\s+uninstall",
        r"simctl\s+uninstall\s+.*com\.ametel01\.trainingcompass",
    )
    for pattern in forbidden_patterns:
        if re.search(pattern, refresh, flags=re.IGNORECASE):
            errors.append(f"refresh workflow contains forbidden credential/destructive command: {pattern}")
        if re.search(pattern, connected_installer, flags=re.IGNORECASE):
            errors.append(
                "connected-iPhone installer contains forbidden credential/destructive "
                f"command: {pattern}"
            )

    if errors:
        print("Personal Team refresh contract check failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Personal Team refresh contract is complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
