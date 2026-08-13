# Dependency allowlist

Gate 0 permits one third-party Swift package:

| Package | Allowed range | Resolved version | Purpose | Network behavior in the app |
| --- | --- | --- | --- | --- |
| `groue/GRDB.swift` | `7.11.1..<8.0.0` | `7.11.1` | Explicit SQLite databases, migrations, and transactions | None |

The app also uses Apple system frameworks SwiftUI, Observation, OSLog, Foundation, CryptoKit, UIKit, and HealthKit. CryptoKit provides export integrity digests; UIKit is limited to presenting the system share sheet; HealthKit is contained inside `HealthKitAdapter`. The Health connection ships only the reviewed HealthKit entitlement and keeps HealthKit values behind application-owned interfaces.

`scripts/check-privacy.sh` rejects any resolved Swift package outside this allowlist and scans production sources for networking, cloud, analytics, and crash-reporting frameworks.
