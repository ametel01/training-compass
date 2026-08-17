#!/usr/bin/env python3
"""Print the one appropriate local Xcode development team identifier."""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


def main() -> int:
    preferences = (
        Path(sys.argv[1]).expanduser()
        if len(sys.argv) > 1
        else Path.home() / "Library/Preferences/com.apple.dt.Xcode.plist"
    )
    try:
        payload = plistlib.loads(preferences.read_bytes())
    except (OSError, plistlib.InvalidFileException):
        return 1

    discovered: dict[str, bool] = {}

    def walk(value: object) -> None:
        if isinstance(value, dict):
            candidate = value.get("teamID")
            if isinstance(candidate, str) and re.fullmatch(r"[A-Z0-9]{10}", candidate):
                discovered[candidate] = bool(value.get("isFreeProvisioningTeam", False))
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    walk(payload.get("IDEProvisioningTeamByIdentifier", {}))
    if len(discovered) == 1:
        print(next(iter(discovered)))
        return 0

    free_teams = [team_id for team_id, is_free in discovered.items() if is_free]
    if len(free_teams) == 1:
        print(free_teams[0])
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
