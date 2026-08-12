# Dependency allowlist

Gate 0 permits one third-party Swift package:

| Package | Allowed range | Resolved version | Purpose | Network behavior in the app |
| --- | --- | --- | --- | --- |
| `groue/GRDB.swift` | `7.11.1..<8.0.0` | `7.11.1` | Explicit SQLite databases, migrations, and transactions | None |

The app also uses Apple system frameworks SwiftUI, Observation, OSLog, Foundation, and HealthKit. HealthKit is contained inside `HealthKitAdapter`; Gate 0 exposes no authorization control and declares no capability or entitlement.

`scripts/check-privacy.sh` rejects any resolved Swift package outside this allowlist and scans production sources for networking, cloud, analytics, and crash-reporting frameworks.
