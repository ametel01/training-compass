# Training Compass release-candidate checklist

Issue #22 is the approval gate for the second owner-usable milestone, and issue
#27 approves Unified Events and Enrichment. The first owner-data milestone
remains covered by issue #16. The Acceptance Device is the owner's iPhone
running the supported iOS release; Simulator numbers are regression signals
only. A milestone candidate is eligible only
when the automated change, migration, UI, privacy, and acceptance-matrix gates
pass and the attended device record is passing.

## Critical journeys

Run the optimized Release build through these journeys without clearing the
application container between steps:

1. First launch and resume: launch offline, confirm protected stores are ready,
   background and resume, and confirm the privacy shield hides sensitive views.
2. Training setup: configure all Progression Lifts and Loading Increments, edit
   and explicitly save the Schedule Template, prepare and edit a Draft Training
   Cycle, and activate it with the immutable prescription preview.
3. Today logging: record performed, failed, omitted, and Additional Sets, close
   and relaunch, then complete a Session and inspect planned-versus-actual work.
4. Cycle lifecycle: skip a Session, finish a Training Week, complete and abandon
   separate cycles, and inspect the lifecycle and change history.
5. Progression: inspect e1RM evidence and independently accept, reject, and
   manually replace Training Max Proposals without changing Active snapshots.
6. Recovery: create and inspect a Training Compass Export, cancel and share it,
   validate a replacement import, reject a corrupt archive, and verify temporary
   files are removed.
7. Erasure: open Full App Erasure, verify its local scope and external-copy
   warning, confirm it, relaunch, and verify the first-launch state.
8. Health foundation: on the in-place install, open Health without clearing
   local data; exercise Connect Health or the unavailable path, dismiss the
   first-batch progress view, navigate with cached content, inspect Health Data
   Status, run Refresh Health Data, and open the confirmed Health Data Rebuild
   action. Verify that local Today, Cycle, Progress, TMs, export, import, and
   erasure remain usable throughout.
9. Training Event linking: complete a Session with multiple external workout
   candidates, confirm an unusual match, inspect both source authorities and
   reconciliation context in the single-count detail, reject duplicate and
   stale confirmations, exercise exact-UUID reconnection, then explicitly
   unlink. Repeat by linking during completion and verify the no-Write-back
   disposition.
10. Workout route, where a route-bearing workout is available: confirm ordinary
    import and enrichment cause no route prompt or query, then open its detail.
    Exercise loading,
    cancellation, retry, unavailable, failure, and ready presentation; verify
    the ready map survives relaunch and disappears when the workout is deleted
    or Health data is rebuilt.
11. Unified milestone: retain prior owner data during the in-place install,
    exercise missing, failed, available, changed, and deleted enrichment on a
    linked event, then verify exact-UUID rebuild reconnection, explicit unlink,
    route resource budgets, export/log/evidence privacy, local availability,
    and hidden unfinished recovery insights.

The critical XCUITest suite covers the stable launch, navigation, recovery, and
erasure accessibility contracts. The application and persistence suites cover
the lifecycle permutations and injected failure points that are intentionally
not repeated through UI automation. HealthKit authorization and observer
registration are attended-device checks because Simulator cannot provide the
system Health database. See the acceptance matrix for the exact evidence
pointer for every rule and state transition.

## Numeric release envelope

Measure ten runs after one conditioning run and gate on the 95th percentile.
HealthKit wait time is reported separately from app-controlled work.

| Area | Budget |
| --- | --- |
| Cold launch to usable local interface | 1.5 seconds |
| Foreground resume | 500 milliseconds |
| Local mutation reflected on screen | 150 milliseconds |
| Ordinary local query | 300 milliseconds |
| Complex insight calculation | 750 milliseconds |
| Route decoding, simplification, persistence, and display preparation after HealthKit returns | 2 seconds |
| Foreground peak memory | 250 MiB |
| Background peak memory | 100 MiB |
| Combined persistent stores | 2 GiB |
| Authoritative store | 250 MiB |
| Simplified route geometry | 100 MiB |
| Authoritative migration | 15 seconds |
| Reconstructible migration | 60 seconds |
| Export or replacement-import staging | 30 seconds |
| Opportunistic background slice | 20 seconds |
| Storage pause threshold | 500 MiB available |

## Health reconciliation envelope

HealthKit wait time is external-system latency and is recorded separately.
Application-controlled reconciliation is bounded by the following contract;
the limits are enforced by `HealthSyncBatchLimits` and are measured against
the full verification data envelope below.

| Health operation | Bound |
| --- | --- |
| Records in one anchored page | 100 records |
| Encoded page and transaction input | 1 MiB |
| Maximum transaction | 4 MiB |
| Maximum transient page buffer | 8 MiB |
| Concurrent reconciliation coordinators | 1 per installation |
| First durable batch visibility | before the next page is requested |
| Rebuild staging safety margin | 20% or the configured absolute margin, whichever is greater |

The verification envelope is 15 years, 25,000 Health Workouts, 10,000,000
workout heart-rate samples, 250,000 sleep intervals, 50,000 resting-heart-rate
samples, 100,000 HRV samples, 500 Training Cycles, 10,000 Sessions, 250,000
sets, and 2,000 routes capped at 2,000 retained points each. It is a test
envelope, never a retention limit.

## Recovery and interruption evidence

Terminate and retry every migration, export, import, and store-swap phase. The
result must be either the original authoritative data or the fully validated
replacement; a partial mixture is a failure. Duration overruns remain correct
and produce a privacy-safe diagnostic. Insufficient space must refuse before
mutation with a 20% safety margin. Storage pressure, Low Power Mode, battery
below 20%, and serious thermal pressure pause discretionary rebuild work while
leaving local training available.

Record only device model, iOS version, battery health, available storage,
thermal state, operation name, duration, coarse record/byte counts, and a
pass/fail verdict. For the Health foundation also record whether authorization,
anchored queries, observer registration, foreground refresh, lock/unlock
recovery, protected storage, and backup exclusion were verified. The validated
Training Event linking record also contains only pass/fail booleans for
ranking, warning acknowledgement, duplicate and stale rejection, single-count
projection, exact-UUID reconnection, unlinking, and Write-back suppression. The
validated measurement JSON contains only the named coarse budget values and
`interruptionRecovery`; never record owner measurements, dates, identifiers,
routes, or free-text notes.
