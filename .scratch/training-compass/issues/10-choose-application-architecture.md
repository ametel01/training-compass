# Choose the application architecture

Type: grilling
Status: resolved
Blocked by: 01, 03, 04, 05, 06, 07, 08, 09, 12, 14

## Question

Which native iPhone architecture best preserves the resolved domain rules, HealthKit synchronization semantics, local data ownership, testability, privacy, and chosen workflows? Decide module boundaries, dependency direction, persistence and observation seams, supported platform baseline, and where derived insight logic belongs.

## Answer

Build Training Compass as an on-device-only SwiftUI application targeting stable iOS 26 with Swift 6 language mode and strict concurrency checking. Use the latest stable Xcode that supports that baseline and exclude beta-only SDK features. The app has no backend, hosted database, API service, CloudKit container, remote configuration, analytics, or third-party crash reporting. All live application state and computation remain on the owner's iPhone. HealthKit, Apple signing and provisioning, ordinary owner-controlled Apple device or iCloud Backup, and explicit Training Compass Exports are platform or recovery facilities rather than app-operated infrastructure.

### Modules and dependency direction

Keep the iOS app target thin: it owns SwiftUI views, `@MainActor @Observable` feature models, navigation, scene and application lifecycle integration, dependency composition, and app-switcher concealment. Put non-presentation code in one local Swift package with these focused targets:

- `TrainingDomain`: cycle, session, lift, Training Max, prescription, identity, and append-only domain-audit rules.
- `TrainingInsights`: deterministic workout, running, recovery, e1RM, and explanation calculations.
- `TrainingApplication`: use cases plus app-owned repository, HealthKit, clock, calendar, timezone, UUID, filesystem, and logging interfaces.
- `TrainingPersistence`: GRDB repositories, schemas, migrations, observation queries, and database lifecycle operations.
- `HealthKitAdapter`: translation between HealthKit objects and application-owned data-transfer values, authorization requests, observer registration, anchored queries, enrichment, routes, and write-back operations.

Dependencies point inward. `TrainingDomain` and `TrainingInsights` know nothing about SwiftUI, HealthKit, GRDB, or files. Application use cases depend on interfaces, and the persistence and HealthKit targets implement those interfaces. Neither GRDB records nor HealthKit types cross into domain, insight, or presentation APIs.

### Persistence and ownership

Use GRDB over SwiftData or Core Data. Pin it to a reviewed release range and retain the resolved package version. Its explicit SQLite transactions, migrations, observations, and query control fit atomic HealthKit delta commits, auditable mutations, time-series queries, durable work queues, and staged import better than framework-managed object graphs.

Use two SQLite databases in separate directories:

- `authoritative.sqlite` contains all Locally Authoritative Data: training plans and results, current Training Maxes and their history, corrections, explicit Training Event links, Running Comparison Exclusions, preferences, append-only domain audit entries, and HealthKit Write-back intent and delivery state. It participates in ordinary encrypted Apple backup.
- `reconstructible.sqlite` contains the HealthKit Mirror, per-stream anchors and state, reconciliation and rebuild checkpoints, late enrichment, lazily fetched simplified routes, and any disposable projection caches. Exclude the whole directory from backup and verify the exclusion attribute after file operations, while making no absolute claim that the OS can never include it.

Apply complete file protection to both directories. Do not trade locked-device privacy for background access: when the device is locked, preserve anchors and defer work until a later unlock or foreground opportunity.

Model current records normally and append a separate immutable domain-audit entry in the same authoritative transaction for every confirmed or corrective action that requires history. Database engine history is not the authoritative audit ledger.

There are no cross-database foreign keys and no claim of atomicity across the two stores. Stable HealthKit UUID references remain authoritative even when the mirror record is absent. Cross-store use cases perform ordered, idempotent steps; projections tolerate missing mirrored records and explain them as unavailable. Reconciliation may repair or replace reconstructible state without changing authoritative intent.

### Synchronization, observation, and durable work

One `HealthSyncCoordinator` actor owns HealthKit scheduling, trigger coalescing, cancellation, retry policy, and per-stream state machines. Bounded per-stream tasks may fetch concurrently, but each returned delta commits its additions, deletions, stream status, and next anchor in one reconstructible-database transaction. The anchor never advances on a failed commit. Foreground reconciliation, observer wakes, manual Health Data Refresh, unlock recovery, and retries enter the same coordinator. Observer queries are registered idempotently at application launch through the app lifecycle adapter; their callbacks are invalidation signals rather than data payloads.

Represent HealthKit Write-back as a durable authoritative state machine tied to its completed local Session. Represent mirror import and Health Data Rebuild progress in the reconstructible store. Resume pending operations at launch and foreground entry, make every step idempotent, and retain only bounded privacy-redacted diagnostic history. Use Health Data Refresh for normal incremental repair and Health Data Rebuild for untrusted mirror state; do not add a separate snapshot-repair mode.

GRDB observations yield immutable application snapshots through `AsyncSequence`. Main-actor observable feature models consume those snapshots and invoke application use cases. SwiftUI views neither observe database records nor access repositories directly.

### Insights and routes

Compute Derived Projections on demand first. Let indexed SQL bound and aggregate source records, then let pure `TrainingInsights` functions return the derived value and its `Insight Explanation` together. Materialize only calculations proven expensive by measurement. Every cache key includes an explicit algorithm version and all relevant source and configuration revisions; deleting a cache changes latency only, never meaning or availability.

Fetch route data lazily when the owner opens a route-bearing workout. Store only simplified geometry and necessary provenance in the reconstructible database. Do not eagerly import every route, retain original full-resolution route coordinates locally, or include routes in the authoritative export by default.

### Evolution, recovery, and privacy

Maintain separate monotonic GRDB migration sequences for the two databases and preserve every released migration. An authoritative migration failure blocks normal opening and offers recovery or export rather than erasure. A reconstructible migration failure may offer confirmed discard and Health Data Rebuild. Database schema versions and Training Compass Export schema versions evolve independently.

The initial `.trainingcompass` export is one versioned UTF-8 JSON document containing a manifest, integrity digest, full-fidelity authoritative records with stable identifiers, schema and generator versions, a readable summary, and an optional separately labelled HealthKit Mirror snapshot. Import decodes and validates into a staging database, migrates it, verifies domain invariants, closes active connections, and replaces the authoritative database through a recoverable same-volume swap. Import never merges into an existing dataset.

For Full App Erasure with optional removal of Training Compass HealthKit Write-backs, attempt HealthKit deletion first from durable write-back state. Partial failure presents Retry or Erase Local Data Anyway; only the explicit second choice permits local erasure while failed HealthKit copies remain. Local erasure then closes database connections, removes both database directories and temporary exports, and returns to first launch.

Use privacy-redacted unified logging and bounded local diagnostics only. Diagnostic export is explicit and inspectable and excludes raw health measurements and route coordinates by default. Inject clock, calendar, timezone, UUID generation, filesystem, and HealthKit boundaries so domain, insight, migration, and failure behavior can be tested deterministically without device services.
