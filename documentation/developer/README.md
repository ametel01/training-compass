# Developer documentation

Issue #32 approves the Training and Running Insights milestone after the
cross-feature correctness, explanation, neutral-language, recomputation,
responsiveness, and Acceptance Device gates pass. The detailed workflow lives
in the [Training and Running Insights device checklist](reference/training-insights-device-checklist.md).

Training Compass contains the protected Gate 0 shell, Local Training Core slices from issues #2 through #15, the approved Health Workout Foundation slices from issues #17 through #22, the approved Unified Events and Enrichment milestone from issues #23 and #25 through #27, the Rolling Workout Overview from issue #28, transparent Heart-Rate Zones from issue #29, source-classified individual running review and Running Volume from issue #30, and like-for-like Comparable Run comparison with reversible exact-UUID exclusions from issue #31. TMs configures kilogram Training Maxes and per-lift Loading Increments, reviews evidence-backed Training Max proposals, records decisions in history, exports a confirmed, inspectable, integrity-checked local archive, restores that archive through validated replacement import, and performs scoped Full App Erasure; Cycle maintains the reusable Schedule Template, prepares one confirmed, audited Draft Training Cycle with independent dated weeks, activates one durable cycle with immutable Training Max snapshots and 5/3/1 Set Prescriptions, and applies audited Calendar Changes and Program Edits without rewriting completed work. Today loads the current Session, records performed or failed Set Results, preserves explicit Omitted dispositions and ordered Additional Sets, requires explicit confirmation before displaying a completed planned-versus-actual Session, and supports correction-backed reopening of terminal sessions; Progress exposes per-lift e1RM history, a transparent seven-date Rolling Workout Overview, individual running facts with separate count, duration, and distance Running Volume, and a selected-reference comparison against the immediately preceding Comparable Run plus a four-run median once four prior runs exist. Comparable eligibility uses positive full-precision distance and duration, matching source-owned environment, and inclusive five-percent distance; the owner can inspect neutral metric differences, request longer history, and reversibly exclude one exact HealthKit UUID without editing or hiding its run. The overview keeps workout count, available positive duration, HealthKit activity types, and source-aware Heart-Rate Zone time separate, compares current facts with four preceding non-overlapping periods only after complete Health coverage is checked, and links every aggregate to an Insight Explanation. Health explains its read-only request, keeps local workflows available when postponed or unavailable, imports source-aware Health Workouts and independent source-aware Recovery Evidence streams into the reconstructible store in bounded durable pages, exposes independent per-stream status with coalesced incremental refresh and cached-content preservation, lets the owner copy the current Apple Watch resting and maximum references plus Zone 2–5 lower bounds, and calculates five continuous BPM ranges from unchanged associated samples with explicit covered-time and total-workout coverage. Health also offers a separately confirmed, resumable Health Data Rebuild. Today and Progress present one unified Training Event timeline: a Completed Session and an unlinked external Health Workout may be explicitly linked one-to-one, likely candidates are ranked without automatic selection, unusual matches require an additional acknowledgement, and a linked pair is counted once while preserving source authority, provenance, disagreements, reconciliation state, and unlink history. Route authorization and paging begin only from an opened workout detail; the adapter reduces paged geometry to at most 2,000 retained points before it crosses the application boundary, and the reconstructible route is excluded from authoritative export by default. The unified milestone is gated by cross-feature automated scenarios, in-place owner-data continuity, an Acceptance Device checklist, resource budgets, and privacy-safe evidence. Recovery Guidance is delivered as an optional gated self-check, and issue #39 adds optional minimized HealthKit Session summary write-back with durable, resumable delivery state.

The Health destination also exposes owner-controlled Preferred Sleep source
ordering and deterministic, source-aware Primary Sleep and Nap episode
inspection from issue #34, plus source-aware daily resting-heart-rate and HRV
SDNN observations with full-precision daily reduction and reconciliation context
from issue #35. Health also calculates independent Personal Recovery Baselines
for Primary Sleep duration and consistency, resting heart rate, and HRV SDNN
from issue #36; each baseline uses the preceding 28 local calendar days,
requires 14 valid observed days, and keeps its exact median, middle 50 percent,
source, freshness, and explanation visible without combining measures.
Issue #37 adds an owner-controlled, optional Recovery Guidance self-check that
appears only when at least two Recovery Evidence Families have established
baselines and current, successful, comparable observations. It enumerates
measurements neutrally, preserves the full evidence and explanation surface
when withheld or disabled, and never changes a Session or other training data.
Issue #38 approves these Recovery Evidence and Guidance slices as one
owner-usable milestone after the cross-feature source, explanation, language,
resource, privacy, and in-place Acceptance Device gates pass. See the [Recovery
Evidence and Guidance device checklist](reference/recovery-evidence-device-checklist.md).

Issue #39 adds an owner-enabled, minimized Traditional Strength Training
HealthKit summary for completed Sessions. Its durable preference and delivery
state are independent of local completion; authorization is requested only
after enablement, every completion can opt out, external links suppress a new
summary, and sets, loads, prescriptions, Training Maxes, e1RM, notes, and audit
history never cross the adapter boundary.

Issue #40 makes that delivery state recoverable. Retryable queued work resumes
after launch or foreground entry, access and terminal failures wait for explicit
Check Health Access/Try Again actions, cancellation never loses intent, and a
quiet aggregate Settings count remains independent of Health read refresh.

Issue #44 adds the private-build maintenance loop: a checked-in, attended
Personal Team refresh script, a per-user LaunchAgent reminder, embedded-profile
inspection, in-place `devicectl` installation and launch smoke test, and a
privacy-safe refresh result. See the [Personal Team refresh Acceptance Device
checklist](reference/personal-team-refresh-device-checklist.md). The workflow
requires a verified Training Compass Export and explicit owner confirmation of
important local data; it never stores credentials or uninstalls the app.

Issue #45 adds the migration compatibility gate. Every released authoritative
and reconstructible schema prefix is built and upgraded directly to the current
version twice, the results are compared deterministically, and the released
export schema is validated. Migration and replacement-import space checks
reserve rollback/staging storage plus a 20 percent margin; failures leave the
original or complete replacement and write only privacy-safe diagnostics. Run
`make verify-migrations` to refresh the checked-in compatibility evidence.

Issue #46 adds the deterministic Verification Data Envelope and release
performance protocol. `make verify-performance` validates the 15-year scale
manifest, ten-run Release-build measurement protocol, HealthKit wait-time
separation, resource and energy pause conditions, and privacy-safe waiver
fields. On an Acceptance Device, `make device-smoke` requires the same
protocol metadata before accepting a passing release measurement; rebuild work
pauses at the next durable page under constrained resources and resumes
without destructive mutation.

Issue #47 adds the bounded production diagnostic store and the final evidence
handoff. Diagnostics keep only the newest seven days or 200 events, serialize
only the operation, duration, record/byte counts, peak memory, result category,
and coarse device conditions, and leave export plus cleanup explicit. The
evidence index sanitizes dependency metadata and records command revisions,
fixture and algorithm versions, environment, compatibility results, raw
measurements, verdicts, milestone records, and waivers. See the [evidence
index reference](reference/evidence-index.md) and [release evidence
runbook](how-to-guides/record-release-evidence.md).

Issue #48 adds the final release-hardening gate. `make verify-final-release`
repeats the automated checks, requires all six owner-usable Acceptance Device
records plus the dedicated Write-back/erasure record, regenerates the
exact-revision evidence index, and accepts only an eligible Milestone 6 release
verdict. See the [final release checklist](reference/final-release-checklist.md).

## How-to guides

- [Verify Gate 0](how-to-guides/verify-gate-zero.md)
- [Release-candidate checklist](reference/release-candidate-checklist.md)
- [Personal Team refresh checklist](reference/personal-team-refresh-device-checklist.md)
- [Final release checklist](reference/final-release-checklist.md)

## Reference

- [Command contract](reference/command-contract.md)
- [Acceptance matrix](reference/acceptance-matrix.md)
- [Dependency allowlist](reference/dependency-allowlist.md)
- [Gate 0 device checklist](reference/gate-zero-device-checklist.md)
- [Health foundation device checklist](reference/health-foundation-device-checklist.md)
- [Workout route device checklist](reference/workout-route-device-checklist.md)
- [Training Event linking device checklist](reference/training-event-linking-device-checklist.md)
- [Training and Running Insights device checklist](reference/training-insights-device-checklist.md)
- [Recovery Evidence and Guidance device checklist](reference/recovery-evidence-device-checklist.md)
- [Unified Events and Enrichment device checklist](reference/unified-events-device-checklist.md)
- [Migration compatibility](reference/migration-compatibility.md)
- [Evidence index](reference/evidence-index.md)
- [Privacy checklist](reference/privacy-checklist.md)

## Explanation

- [Gate 0 architecture](explanation/gate-zero-architecture.md)
