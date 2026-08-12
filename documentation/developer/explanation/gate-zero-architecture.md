# Gate 0 architecture

Gate 0 makes later work replaceable and testable without pretending unfinished product behavior exists.

The iOS target is a thin composition and presentation layer. It creates one `ApplicationDependencies` value containing injectable clock, calendar, timezone, UUID, filesystem, repository, HealthKit, and logging interfaces. Its only use case prepares protected stores and records a fixed privacy-safe event. Health authorization remains composed but untouched.

The local Swift package points inward:

```text
TrainingDomain
    ↑
TrainingInsights
    ↑
TrainingApplication
    ↑                 ↑
TrainingPersistence  HealthKitAdapter
```

`TrainingDomain` and `TrainingInsights` import no Apple persistence or presentation frameworks. `TrainingApplication` owns the seams. `TrainingPersistence` contains GRDB, while `HealthKitAdapter` contains HealthKit. An automated parser checks both source imports and the Swift package graph.

Persistence uses independent directories and GRDB migration sequences for `authoritative.sqlite` and `reconstructible.sqlite`. Both are prepared with complete file protection. Only reconstructible data is marked and verified as excluded from backup. Their v1 schemas contain no owner records and enforce `owner_data_accepted = false`.

The SwiftUI shell exposes the stable information architecture while unavailable destinations contain no action controls. When the scene leaves the active state, a full-screen privacy shield replaces the underlying privacy-sensitive tab content before the system captures an app-switcher snapshot.
