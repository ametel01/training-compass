# Gate 0 architecture

Gate 0 makes later work replaceable and testable without pretending unfinished product behavior exists.

The iOS target is a thin composition and presentation layer. It creates one `ApplicationDependencies` value containing injectable clock, calendar, timezone, UUID, filesystem, repository, HealthKit, and logging interfaces. Store preparation, lift-configuration, and schedule-template use cases share those seams; Health authorization remains composed but untouched.

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

Persistence uses independent directories and GRDB migration sequences for `authoritative.sqlite` and `reconstructible.sqlite`. Both are prepared with complete file protection. Only reconstructible data is marked and verified as excluded from backup. The authoritative v8 schema stores lift configuration, the reusable Schedule Template, one append-only-audited Draft or Active Training Cycle with independent week/session and activation snapshots, atomic Set Results, explicit Omitted dispositions, ordered Additional Sets, Session completion, correction-backed session projections, and Training Week source audit history; the reconstructible store remains a v1 Gate 0 marker.

The SwiftUI shell exposes the stable information architecture. TMs provides the confirmed lift editor and Cycle provides explicit-save, reorder, and confirmed-reset controls for the Schedule Template, plus confirmed creation, independent edits, replacement, destructive discard, and activation for the Draft Training Cycle once its referenced lifts are configured. Active and Draft cycles expose separate Calendar Change and Program Edit boundaries: date moves warn when they leave a Training Week, role/session edits are restricted to Scheduled work, and change history labels the two kinds distinctly. A normal Training Week can be separately confirmed as a Schedule Template source without copying dates, prescriptions, statuses, or logged work. Activation stores immutable lift snapshots and prescriptions and leaves no independently editable draft; unfinished destinations contain no action controls. When the scene leaves the active state, a full-screen privacy shield replaces the underlying privacy-sensitive tab content before the system captures an app-switcher snapshot.
