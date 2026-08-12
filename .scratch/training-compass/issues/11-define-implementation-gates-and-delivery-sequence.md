# Define implementation gates and delivery sequence

Type: grilling
Status: resolved
Blocked by: 07, 10, 15

## Question

What acceptance scenarios, automated test layers, HealthKit fixtures or fakes, privacy checks, performance checks, and implementation milestones make the specification safe to hand off? Produce a sequenced build roadmap whose increments remain usable and verifiable on the target iPhone.

## Comments

### Grilling round 1

- Every milestone ends in an installable, coherent vertical slice. Incomplete capabilities remain hidden; exposed paths are safe for real owner data.
- Every change passes automated correctness and privacy gates. Every milestone receives a scripted Acceptance Device smoke test. Designated release-candidate gates run the full performance, energy, migration, interruption, and recovery suite.
- The first useful slice is local 5/3/1 planning and logging: lifts and Training Maxes, Draft and Active Training Cycles, Today, and durable set logging.
- HealthKit delivery is staged: workout mirror and per-stream status; enrichment and explicit Training Event linking; recovery streams and insights; then optional write-back.
- Manual verification stays bounded to a short repeatable device checklist per milestone and a longer release-candidate protocol; exhaustive cases remain automated.

### Grilling round 2

- Verification uses six layers: pure domain and insight tests; application use-case tests with injected fakes; GRDB integration, migration, observation, and interruption tests against temporary SQLite databases; HealthKit adapter contract tests; narrow critical-path XCUITests; and full-envelope performance and recovery harnesses.
- All checked-in fixtures are synthetic and deterministically seeded. Captured or anonymized owner health and training data never enters source control.
- HealthKit tests fake the application-owned interface rather than `HKHealthStore`. The fake models pagination, anchors, additions, replacements, deletions, partial authorization, per-stream failures, delayed enrichment, locked-device deferral, background expiration, and write-back outcomes. Real framework interaction is verified at the adapter and Acceptance Device boundaries.
- A version-controlled acceptance matrix maps every critical domain rule and state transition to automated and, where required, physical-device evidence.
- XCUITest covers only critical owner journeys with stable accessibility identifiers; domain permutations remain below the UI layer.
- There is no global line-coverage threshold. Critical acceptance-matrix coverage and regression tests are mandatory; percentage coverage is diagnostic only.
- Privacy gates reject undeclared network-capable dependencies or entitlements, analytics or crash-reporting SDKs, sensitive fixtures or logs, missing file protection, incorrect reconstructible-store backup exclusion, and export behavior that bypasses explicit owner action and inspection.

### Grilling round 3

- An engineering Gate 0 establishes the package graph, dependency enforcement, databases, migration harness, fixtures, change gates, redacted logging, signing, and Acceptance Device deployment. It launches but is not approved for real owner data.
- Six owner-usable milestones follow: Local Training Core; Health Workout Foundation; Unified Events and Enrichment; Training and Running Insights; Recovery Evidence and Guidance; and Write-back and Release Hardening. Every milestone retains and migrates earlier owner data.
- Export, validated replacement import, and Full App Erasure are required before Local Training Core may hold real owner data.
- Every critical use case covers normal success, domain boundaries, missing or partial data, interruption and retry, and privacy or recovery where applicable; an explicitly justified not-applicable entry is allowed, silent omission is not.
- Correctness, durability, migration, and privacy failures stop progression. A performance or Device Energy waiver is allowed only for documented OS or HealthKit variance under the existing budget decision, with measurements, scope, an expiry condition, and explicit owner acceptance.
- The build-ready handoff includes repository-native verification commands, deterministic fixture generators, the acceptance matrix, the migration and version compatibility table, milestone device checklists, the release-candidate measurement protocol, the privacy manifest and checklist, and an evidence index. Resolved Wayfinder tickets remain the detailed specification.

## Answer

Deliver Training Compass through one engineering foundation gate followed by six installable vertical milestones. Gate 0 is not approved for owner data. Every later milestone is coherent and safe for real owner data, preserves and migrates everything delivered earlier, passes automated change gates, and completes a short scripted check on the Acceptance Device. Designated release-candidate gates additionally run the full migration, interruption, recovery, performance, memory, storage, route, and Device Energy protocol from [Define migration, performance, and energy budgets](15-define-migration-performance-and-energy-budgets.md).

Correctness, durability, migration, and privacy failures stop progression. A performance or Device Energy waiver is permitted only for identified OS or HealthKit variance under the existing budget decision. It records the failed measurement, comparison evidence, affected scope, owner-visible effect, expiry condition, and explicit owner acceptance; it never silently changes a budget.

### Verification layers

Use six complementary layers. A higher layer proves integration but does not replace exhaustive lower-layer behavior tests.

1. **Domain and insight tests** exercise `TrainingDomain` and `TrainingInsights` as pure Swift. They cover state transitions, invariants, prescriptions, rounding, snapshots, e1RM eligibility, rolling windows, running comparisons, recovery baselines and gates, explanations, and timezone-free calendar behavior with no database, UI, or HealthKit dependency.
2. **Application use-case tests** exercise `TrainingApplication` through application-owned interfaces. Deterministic repositories, clocks, calendars, timezones, UUID generators, filesystems, and HealthKit fakes cover orchestration, confirmation boundaries, idempotency, retry, cancellation, cross-store ordering, and failure presentation.
3. **Persistence integration tests** use real temporary SQLite databases through GRDB. They cover schema constraints, transactions, audit entries, observations, concurrent reads and the single-writer rule, atomic Health deltas and anchors, backup attributes, staged import, store replacement, every released migration, and termination or failure at each recoverable phase.
4. **HealthKit adapter contract tests** verify translation between application transfer values and HealthKit types plus coordinator state-machine behavior. Most run against a semantic application-boundary fake; focused tests and the Acceptance Device verify the real adapter, authorization, anchored queries, observer registration, routes, and write-back.
5. **Critical-journey UI tests** use stable accessibility identifiers and cover first launch and Health authorization, cycle creation and activation, Today logging and completion, Training Max proposal confirmation, degraded Health recovery, and export/import recovery. Domain permutations stay below the UI layer; final styling is not snapshot-gated.
6. **Release harnesses** generate the Verification Data Envelope and run the physical-device latency, throughput, memory, storage, migration, interruption, route, thermal, and Device Energy scenarios already specified. Simulator measurements are regression signals, never device acceptance evidence.

Do not impose a global line-coverage threshold. Publish coverage as a diagnostic, require a regression test for every fixed defect, and gate on the acceptance matrix: every critical rule and transition must point to meaningful automated evidence and, when platform behavior is involved, physical-device evidence.

### Repository command contract

Gate 0 establishes one documented, non-interactive command surface. The implementation may delegate to Xcode and supporting scripts, but contributors and evidence collection use these stable entry points:

- `make bootstrap` validates the stable Xcode, Swift, signing, and package prerequisites without acquiring secrets or changing owner data.
- `make verify` runs formatting or static checks, dependency-boundary checks, domain and insight tests, application tests, persistence tests, adapter contract tests, and privacy checks suitable for every change.
- `make test-ui` runs the critical-journey simulator UI suite.
- `make fixtures` regenerates deterministic synthetic fixture manifests and fails when regeneration produces an unexplained diff.
- `make verify-migrations` exercises direct upgrades from every retained database and export version, including interruption points.
- `make device-smoke MILESTONE=<id>` runs or prints the exact attended Acceptance Device checklist for one milestone and writes a privacy-safe result record.
- `make verify-release` runs the complete release-candidate protocol, refusing to claim success when required physical-device evidence is absent.
- `make evidence` builds an inspectable index of commands, fixture seeds, environment metadata, raw privacy-safe measurements, waivers, and verdicts for the candidate.

The command names form the handoff contract. Gate 0 may implement them with a Makefile plus versioned scripts, but no release procedure may depend on undocumented personal shell history or an IDE-only sequence.

### Acceptance matrix

Keep a version-controlled matrix whose rows identify the source decision, scenario, preconditions, deterministic seed, expected result, automated layer, whether an Acceptance Device check is required, and the latest evidence pointer. Every applicable critical use case covers five variants: normal success, domain boundary, missing or partial data, interruption and retry, and privacy or recovery. A variant may be explicitly marked not applicable with a reason; silent omission fails the gate.

At minimum, the matrix contains these scenario families:

1. **Private first launch:** the app launches without Health access or connectivity, explains local ownership, creates protected stores, exposes no unfinished feature, and permits local training independently of HealthKit.
2. **Training setup and prescription:** configure lifts, Training Maxes, and Loading Increments; edit and copy the Schedule Template; create, edit, and activate a Draft Training Cycle; verify Deload cadence, immutable snapshots, exact rounding including ties, and the separation of template edits, Calendar Changes, and Program Edits.
3. **Today logging and durability:** start, interrupt, resume, correct, and complete a 5/3/1 Session; record actual, failed, omitted, and additional sets; keep prescription and result distinct; prove the confirmed mutation and audit entry commit atomically and appear within the responsiveness budget while reconciliation is busy.
4. **Cycle lifecycle and progression:** skip a Session, abandon a cycle with Unperformed Sessions, complete an eligible cycle, generate per-lift Training Max Proposals, inspect supporting work and e1RM evidence, and accept, reject, or manually replace each proposal without rewriting the Active Training Cycle.
5. **Authoritative recovery:** export a non-empty dataset, inspect its warning and summary, reject corrupt and unsupported archives without change, migrate and stage a supported archive, interrupt every stage, replace atomically, restore stable identities, remove temporary exports, and perform Full App Erasure with the documented HealthKit write-back choices.
6. **Health authorization and degraded operation:** exercise no access, partial readable streams, unavailable samples, later authorization changes, locked-device deferral, foreground return, a failed newer reconciliation, and recovery. Local planning and logging remain available, and the UI never converts absence into proof of denied read permission.
7. **Anchored reconciliation:** process multiple bounded pages of additions, replacements, and deletions; fail before and after database commit; prove the anchor advances only with its delta; coalesce triggers; cap concurrent streams and pending batches; resume rebuild checkpoints; and keep per-stream state independent.
8. **Late enrichment and routes:** import a workout before heart rate, distance, energy, or route detail; update that workout without duplicating its Training Event; distinguish Not Available from loading; fetch a route only on explicit opening; serialize route work; simplify within the retained-point bound; and preserve provenance and deletion behavior.
9. **Unified Training Events:** keep local and Health-only events separate by default; explicitly link and unlink an external Health Workout; automatically reconcile only Training Compass's own write-back by sync identity; preserve both sources and authority; and count a linked pair once in timelines and aggregates.
10. **Training and running insights:** reproduce e1RM points from eligible Plus Set Results; verify rolling-window boundaries, activity grouping, source and coverage explanations, recalculation after configuration changes, comparable-run distance and environment boundaries, exclusion behavior, heart-rate coverage thresholds, missing inputs, and stable Run Dates.
11. **Recovery Evidence and Guidance:** select overlapping sleep by Preferred Sleep Source, assemble Primary Sleep and Naps at interval boundaries, establish and withhold Personal Recovery Baselines at observation-count boundaries, classify middle-half boundary values, exercise stale or incomparable streams and family gates, and prove guidance remains neutral, explained, advisory, and incapable of changing training.
12. **Write-back lifecycle:** opt in persistently, opt out per completion, queue and retry independently of local completion, handle missing permission, replacement and stale versions, respect external deletion, explicitly restore when requested, and exercise partial deletion failure during Full App Erasure without touching another source's workout.
13. **Privacy controls:** verify app-switcher concealment, complete file protection, reconstructible-store backup exclusion after every relevant file operation, bounded redacted diagnostics, explicit and inspectable diagnostic export, sensitive Training Compass Export handling, and the absence of undeclared networking or telemetry.
14. **Scale, migration, and interruption:** run every numeric budget and Verification Data Envelope scenario; upgrade directly from every historical store and export version; terminate every migration, rebuild, export, import, and swap phase; exercise storage, memory, Low Power Mode, battery, and thermal pressure; and prove correctness when duration budgets are exceeded.
15. **Owner installation:** install on the Acceptance Device using the Personal Team, refresh in place before expiry, verify owner data survives reprovisioning, show the day-five reminder, and demonstrate the documented expired-build recovery path without claiming unattended or permanent availability.

### Synthetic fixtures and the HealthKit fake

Only deterministic synthetic data may be checked into the repository. Do not derive fixtures from captured or supposedly anonymized owner workouts, Health measurements, routes, UUIDs, dates, lift results, or notes. Seeds and generators are versioned; generated datasets carry schema and algorithm versions and include small readable cases, boundary cases, failure scripts, and the complete Verification Data Envelope.

Fixture families include training templates and cycles across every lifecycle state; prescription and result edge cases; Health Workouts across activity and environment classifications; paginated stream deltas with replacements and deletions; incomplete and late enrichment; overlapping sleep from ordered sources; sparse and boundary recovery observations; comparable and non-comparable runs; routes before and after simplification; historical authoritative and reconstructible schemas; historical export versions; corrupt, truncated, unsupported, and invariant-breaking imports; and deterministic filesystem, storage, thermal, background-time, and write-back failures.

Fake the application-owned HealthKit interface, not `HKHealthStore` throughout the codebase. A scripted fake must model:

- per-type authorization request outcomes without pretending read denial is directly knowable;
- independently available and failing Health Data Streams;
- anchored pagination, stable UUIDs, replacements, deletions, and anchor invalidation;
- HealthKit response delay separately from app-controlled processing time;
- observer invalidation bursts, coalescing, cancellation, background expiry, device lock, and later unlock;
- enrichment that is absent, delayed, changed, deleted, or explicitly Not Available;
- route pages, cancellation, oversized geometry, simplification, and persistence failure;
- write authorization, success, retryable and terminal failure, saved-object replacement, external deletion, and explicit restoration; and
- deterministic call history so tests can prove bounds, ordering, idempotency, and the absence of polling.

Focused adapter tests verify application-value translation against actual HealthKit types. The milestone device checklist verifies platform behavior with owner-authorized data or a deliberately prepared non-sensitive device test record; repository evidence records only environment metadata and pass/fail context, never the measurement or route payload.

### Blocking privacy checks

Privacy is a change gate, not a final review. Automated checks and milestone inspection must reject:

- an undeclared network-capable dependency, networking use, entitlement, remote configuration, analytics SDK, or third-party crash reporter;
- a package or binary outside the reviewed dependency and system-framework allowlist;
- a checked-in fixture or log matching sensitive HealthKit identifiers, route coordinates, measurement payloads, free-text notes, or owner-derived data;
- raw HealthKit, GRDB, or filesystem values entering domain or presentation interfaces across the chosen module boundaries;
- missing complete file protection or failure to reapply and verify reconstructible-directory backup exclusion after creation, replacement, rebuild, or import;
- diagnostics beyond seven days or 200 events, or diagnostics containing prohibited measurements, dates, identifiers, lift results, routes, or notes;
- an export or diagnostic share flow without explicit owner action, preview or inspection, the required sensitive-data warning, and temporary-file cleanup;
- a Health Data Rebuild that changes Locally Authoritative Data, a Full App Erasure that overstates its reach, or HealthKit deletion that can target another source; and
- visible sensitive content in the app switcher while the app is backgrounded.

Each release evidence bundle includes the resolved dependency graph, entitlements and capabilities, privacy manifest, file-attribute test results, logging-field allowlist, export/cleanup results, and an attended app-switcher check.

### Gate cadence

Every change runs `make verify`; changes to navigation or a critical journey also run `make test-ui`; schema or export changes run `make verify-migrations`; fixture changes run regeneration and review. No failing required check may be merged into the milestone integration branch.

Every owner-usable milestone additionally:

- installs or refreshes in place on the Acceptance Device without erasing prior milestone data;
- completes its scripted critical journey and degraded or failure recovery check;
- verifies protected authoritative storage and reconstructible backup exclusion;
- confirms local training remains usable while newly introduced Health work is unavailable or active;
- records device model, iOS, build, schema versions, fixture or scenario identifier, result, and privacy-safe notes; and
- leaves incomplete later capabilities inaccessible rather than presenting placeholders as working features.

The full release-candidate gate runs at Milestone 1 before approving the first real-data build, again when a milestone changes persistence, import, export, reconciliation, or resource behavior materially, and at Milestone 6. Numeric verdicts use the exact Acceptance Device protocol and budgets already fixed; simulator success cannot waive a missing device result.

### Delivery roadmap

#### Gate 0 — Engineering foundation

Create the thin SwiftUI app, local Swift package and inward dependency graph; compose replaceable clocks, calendars, timezones, UUIDs, filesystems, repositories, and HealthKit boundaries; establish both protected GRDB stores and independent migration sequences; add privacy-redacted logging; implement fixture generation and the command contract; configure Personal Team signing and install a launchable shell on the Acceptance Device.

Exit when dependency checks, the initial migrations, synthetic fixture determinism, privacy checks, and Acceptance Device launch pass. The shell clearly identifies itself as pre-data and is not approved for real owner training history.

#### Milestone 1 — Local Training Core

Deliver the four-destination shell with functional Today, Cycle, Progress strength, and TMs paths; lift and Training Max configuration; Schedule Template and Default Schedule; Draft and Active Training Cycle lifecycles; prescriptions, snapshots, Calendar Changes and Program Edits; complete set logging and correction; cycle completion and abandonment; e1RM; Training Max Proposals and history; append-only audit behavior; authoritative export, validated replacement import, and Full App Erasure.

Exit when all local scenario families pass, the Acceptance Device completes setup through restored export, an interrupted mutation and import recover safely, no Health permission is required, and the first real-data release-candidate gate passes. This is the first build approved for owner data.

#### Milestone 2 — Health Workout Foundation

Add HealthKit capability messaging and authorization, Health Workout import, the HealthKit Mirror, independent stream status, actor-coordinated foreground and observer reconciliation, manual Health Data Refresh, Health Data Rebuild, bounded batching and checkpointing, deletion handling, locked-device deferral, offline use, degraded-state UI, and Health-only workout history.

Exit when paginated and failed-commit scenarios prove anchor atomicity and idempotency, local training stays responsive during full reconciliation, rebuild preserves authoritative data, and the device checklist exercises authorization, foreground refresh, a degraded state, and recovery.

#### Milestone 3 — Unified Events and Enrichment

Add explicit external-workout linking and unlinking, automatic identity only for Training Compass write-back placeholders, unified Training Event timelines and counts, late heart-rate, distance, energy, and provenance enrichment, heart-rate coverage, and lazily fetched simplified routes.

Exit when linked records retain separate authority, late enrichment never duplicates an event, deletions and rebuilds preserve explicit intent, route work respects privacy and resource bounds, and the device checklist verifies a linked event plus on-demand route behavior where available.

#### Milestone 4 — Training and Running Insights

Complete Progress with Strength, Running, and unified history; add Rolling Workout Overview, configured Heart-Rate Zones, per-lift e1RM traceability, Running Volume, reference and Comparable Run selection, exclusions, pace and sufficiently covered heart-rate comparisons, missing-data states, and complete Insight Explanations.

Exit when deterministic calculations cover every window and eligibility boundary, configuration revisions recompute affected history, all displayed conclusions trace to included and excluded sources, worst-case insight queries pass their budget, and the device checklist reaches each explanation from its displayed value.

#### Milestone 5 — Recovery Evidence and Guidance

Add sleep, resting-heart-rate, and HRV streams; Preferred Sleep Source; Primary Sleep and Naps; duration and timing consistency; Personal Recovery Baselines; source, freshness, coverage, missing-data and comparison states; neutral Recovery Observations; and strictly advisory Recovery Guidance with its evidence-family gates and explanation.

Exit when every source overlap, minimum-observation, middle-half boundary, stale/failing stream, conflicting-signal, and guidance-suppression scenario passes; the UI never emits a score, verdict, diagnosis, risk claim, or training prescription; and the device checklist demonstrates both available evidence and correctly withheld guidance.

#### Milestone 6 — Write-back and release hardening

Add the optional HealthKit strength-workout summary, persistent preference and per-session opt-out, durable write-back state machine, stable sync identity and version replacement, explicit retry and permission repair, respect for external deletion, explicit restoration, and Full App Erasure's retry-or-proceed deletion choice. Complete all historical migrations and export readers, diagnostic and evidence export, Personal Team refresh instructions and reminder, storage inspection, and release automation.

Exit only after every acceptance-matrix row has current evidence, every historical schema and export upgrades directly, the complete Verification Data Envelope and all interruption points pass, the matched Device Energy runs meet budget or carry an allowed explicit waiver, the privacy bundle is clean, owner data survives an attended in-place weekly refresh, and the final install and recovery runbooks have been performed on the Acceptance Device.

### Handoff and completion evidence

The implementation is ready to hand off because the resolved Wayfinder tickets remain the single detailed specification and this roadmap supplies their execution order and proof obligations. Gate 0 creates, and each milestone maintains:

- the repository command documentation and tool-version prerequisites;
- deterministic generators plus fixture-schema and algorithm versions;
- the acceptance matrix with source-ticket links and evidence status;
- a compatibility table for every authoritative schema, reconstructible schema, and Training Compass Export version;
- one short Acceptance Device checklist per milestone;
- the full release-candidate measurement and interruption protocol;
- the dependency allowlist, entitlements, privacy manifest, logging-field allowlist, file-protection and backup-exclusion checks, and export/privacy checklist; and
- an evidence index containing command revisions, seeds, environment metadata, privacy-safe raw measurements, summarized verdicts, and any time-bounded owner-approved waiver.

The roadmap is complete when Milestone 6 passes; visual styling and public distribution remain outside this map. No implementation milestone may reinterpret a resolved domain rule or automate a user-confirmed training decision. A newly discovered product decision returns to planning rather than being hidden inside implementation.
