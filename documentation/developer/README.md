# Developer documentation

Issue #32 approves the Training and Running Insights milestone after the
cross-feature correctness, explanation, neutral-language, recomputation,
responsiveness, and Acceptance Device gates pass. The detailed workflow lives
in the [Training and Running Insights device checklist](reference/training-insights-device-checklist.md).

Training Compass contains the protected Gate 0 shell, Local Training Core slices from issues #2 through #15, the approved Health Workout Foundation slices from issues #17 through #22, the approved Unified Events and Enrichment milestone from issues #23 and #25 through #27, the Rolling Workout Overview from issue #28, transparent Heart-Rate Zones from issue #29, source-classified individual running review and Running Volume from issue #30, and like-for-like Comparable Run comparison with reversible exact-UUID exclusions from issue #31. TMs configures kilogram Training Maxes and per-lift Loading Increments, reviews evidence-backed Training Max proposals, records decisions in history, exports a confirmed, inspectable, integrity-checked local archive, restores that archive through validated replacement import, and performs scoped Full App Erasure; Cycle maintains the reusable Schedule Template, prepares one confirmed, audited Draft Training Cycle with independent dated weeks, activates one durable cycle with immutable Training Max snapshots and 5/3/1 Set Prescriptions, and applies audited Calendar Changes and Program Edits without rewriting completed work. Today loads the current Session, records performed or failed Set Results, preserves explicit Omitted dispositions and ordered Additional Sets, requires explicit confirmation before displaying a completed planned-versus-actual Session, and supports correction-backed reopening of terminal sessions; Progress exposes per-lift e1RM history, a transparent seven-date Rolling Workout Overview, individual running facts with separate count, duration, and distance Running Volume, and a selected-reference comparison against the immediately preceding Comparable Run plus a four-run median once four prior runs exist. Comparable eligibility uses positive full-precision distance and duration, matching source-owned environment, and inclusive five-percent distance; the owner can inspect neutral metric differences, request longer history, and reversibly exclude one exact HealthKit UUID without editing or hiding its run. The overview keeps workout count, available positive duration, HealthKit activity types, and source-aware Heart-Rate Zone time separate, compares current facts with four preceding non-overlapping periods only after complete Health coverage is checked, and links every aggregate to an Insight Explanation. Health explains its read-only request, keeps local workflows available when postponed or unavailable, imports source-aware Health Workouts and independent source-aware Recovery Evidence streams into the reconstructible store in bounded durable pages, exposes independent per-stream status with coalesced incremental refresh and cached-content preservation, lets the owner configure a positive maximum heart rate, and calculates fixed zones from unchanged associated samples with explicit covered-time and total-workout coverage. Health also offers a separately confirmed, resumable Health Data Rebuild. Today and Progress present one unified Training Event timeline: a Completed Session and an unlinked external Health Workout may be explicitly linked one-to-one, likely candidates are ranked without automatic selection, unusual matches require an additional acknowledgement, and a linked pair is counted once while preserving source authority, provenance, disagreements, reconciliation state, and unlink history. Route authorization and paging begin only from an opened workout detail; the adapter reduces paged geometry to at most 2,000 retained points before it crosses the application boundary, and the reconstructible route is excluded from authoritative export by default. The unified milestone is gated by cross-feature automated scenarios, in-place owner-data continuity, an Acceptance Device checklist, resource budgets, and privacy-safe evidence. Recovery Guidance and HealthKit Write-back remain outside the shipped surface.

The Health destination also exposes owner-controlled Preferred Sleep source
ordering and deterministic, source-aware Primary Sleep and Nap episode
inspection from issue #34, plus source-aware daily resting-heart-rate and HRV
SDNN observations with full-precision daily reduction and reconciliation context
from issue #35.

## How-to guides

- [Verify Gate 0](how-to-guides/verify-gate-zero.md)
- [Release-candidate checklist](reference/release-candidate-checklist.md)

## Reference

- [Command contract](reference/command-contract.md)
- [Acceptance matrix](reference/acceptance-matrix.md)
- [Dependency allowlist](reference/dependency-allowlist.md)
- [Gate 0 device checklist](reference/gate-zero-device-checklist.md)
- [Health foundation device checklist](reference/health-foundation-device-checklist.md)
- [Workout route device checklist](reference/workout-route-device-checklist.md)
- [Training Event linking device checklist](reference/training-event-linking-device-checklist.md)
- [Unified Events and Enrichment device checklist](reference/unified-events-device-checklist.md)
- [Training and Running Insights device checklist](reference/training-insights-device-checklist.md)
- [Migration compatibility](reference/migration-compatibility.md)
- [Privacy checklist](reference/privacy-checklist.md)

## Explanation

- [Gate 0 architecture](explanation/gate-zero-architecture.md)
