# Gate 0 architecture

Gate 0 makes later work replaceable and testable without pretending unfinished product behavior exists.

The iOS target is a thin composition and presentation layer. It creates one `ApplicationDependencies` value containing injectable clock, calendar, timezone, UUID, filesystem, repository, HealthKit, and logging interfaces. Store preparation, lift-configuration, schedule-template, and opt-in Health connection use cases share those seams; preparation never requests Health access.

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

`TrainingDomain` and `TrainingInsights` import no Apple persistence or presentation frameworks. `TrainingApplication` owns the seams and its `HealthWorkout` model contains no HealthKit types. `TrainingPersistence` contains GRDB, while `HealthKitAdapter` contains HealthKit. An automated parser checks both source imports and the Swift package graph.

Persistence uses independent directories and GRDB migration sequences for `authoritative.sqlite` and `reconstructible.sqlite`. Both are prepared with complete file protection. Only reconstructible data is marked and verified as excluded from backup. The authoritative v11 schema stores lift configuration and Training Max history, evidence-bearing proposals, the reusable Schedule Template, one append-only-audited Draft or Active Training Cycle with independent week/session and activation snapshots, atomic Set Results, explicit Omitted dispositions, ordered Additional Sets, Session completion, correction-backed session projections, Training Week source audit history, and targeted lifecycle audits; reconstructible v3 adds source-aware Health Workouts plus deletion, stream checkpoint, and fact ledgers while retaining the Gate 0 marker.

The SwiftUI shell exposes the stable information architecture. TMs provides the confirmed lift editor, evidence-backed Training Max proposal decisions, and Cycle provides explicit-save, reorder, and confirmed-reset controls for the Schedule Template, plus confirmed creation, independent edits, replacement, destructive discard, and activation for the Draft Training Cycle once its referenced lifts are configured. Active and Draft cycles expose separate Calendar Change and Program Edit boundaries: date moves warn when they leave a Training Week, role/session edits are restricted to Scheduled work, and change history labels the two kinds distinctly. A normal Training Week can be separately confirmed as a Schedule Template source without copying dates, prescriptions, statuses, or logged work. Activation stores immutable lift snapshots and prescriptions and leaves no independently editable draft; unresolved Training Max proposals block activation. When the scene leaves the active state, a full-screen privacy shield replaces the underlying privacy-sensitive tab content before the system captures an app-switcher snapshot.
