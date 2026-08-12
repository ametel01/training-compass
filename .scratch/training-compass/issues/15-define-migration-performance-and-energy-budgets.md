# Define migration, performance, and energy budgets

Type: grilling
Status: resolved
Blocked by: 10

## Question

What measurable data-scale envelope, migration and recovery guarantees, query and launch latency targets, memory limits, import batching and back-pressure rules, background execution policy, battery budget, route-enrichment limits, and on-device verification scenarios must the chosen GRDB and HealthKit architecture satisfy? Resolve the non-functional acceptance boundaries needed before implementation gates and milestones can be sequenced, without turning opportunistic HealthKit delivery into a freshness guarantee.

## Answer

### Acceptance basis and terminology

- The **Acceptance Device** is the owner's actual target iPhone running the supported iOS release. Performance and device-energy acceptance uses optimized release builds on that physical device. Simulator measurements are regression signals only.
- Record the device model, iOS version, battery health, available storage, and initial thermal state with every acceptance run. Changing the Acceptance Device establishes a new baseline but does not silently relax any budget.
- **Application Performance** means responsiveness and resource use of Training Compass itself; it is distinct from the domain's Running Performance. **Device Energy** means the app's battery and thermal cost; it is distinct from workout energy imported as Workout Enrichment.
- All latency and throughput budgets measure app-controlled work. Time spent waiting for HealthKit to return data is reported separately and cannot be represented as app processing time or a Health freshness guarantee.

### Verification Data Envelope

The following deliberately generous single-user dataset is the scale at which every numeric guarantee applies:

- 15 years of readable Health history;
- 25,000 Health Workouts;
- 10,000,000 workout-associated heart-rate samples;
- 250,000 sleep intervals;
- 50,000 resting-heart-rate samples;
- 100,000 HRV samples;
- 500 Training Cycles, 10,000 5/3/1 Sessions, and 250,000 sets; and
- 2,000 lazily requested routes, each retaining at most 2,000 simplified points.

This is a verification envelope, not a retention limit. Training Compass retains valid readable history beyond it and preserves correctness, but makes no numeric performance promise outside it and never uses the envelope to justify automatic deletion.

### Gate semantics and interactive responsiveness

- Correctness, crash freedom, bounded memory, and foreground responsiveness are hard release gates. Latency and energy are evaluated over repeated runs using the measurement protocol below. A documented waiver is allowed only for identified OS or HealthKit variance and never by silently changing a budget.
- With no blocking schema migration, the 95th-percentile cold-launch time to a usable local interface is at most 1.5 seconds. Foreground resume is at most 500 milliseconds.
- A set result or other local mutation is durable and reflected on screen within 150 milliseconds at the 95th percentile. An ordinary local screen query completes within 300 milliseconds, and a complex insight calculation within 750 milliseconds.
- No continuous main-actor work may exceed 100 milliseconds. Health reconciliation, mirror rebuilding, and projection regeneration never delay these local interaction paths.

### Health import, rebuild, batching, and back-pressure

- After HealthKit returns the first batch, Training Compass displays the first durably imported content within 10 seconds. A normal daily delta consumes at most two seconds of app-controlled processing at the 95th percentile. Processing the full Verification Data Envelope consumes at most 30 minutes of cumulative app-controlled time.
- Initial import and Health Data Rebuild may span foreground opportunities. Each resumes from the last committed batch without repeating completed work, and cached or locally authoritative features remain usable throughout.
- At most two Health Data Streams fetch concurrently. There is one database writer and no more than one pending batch per active stream.
- A batch is capped at 5,000 records or 4 MiB of decoded data, whichever comes first. Transactions target no more than 250 milliseconds, and total transient import buffers remain below 32 MiB. Batch size decreases under memory or background-time pressure.
- Route work is serialized. Background observer callbacks remain opportunistic invalidation signals and never create a delivery or completion deadline.

### Memory and persistent storage

- Peak foreground memory is at most 250 MiB at the Verification Data Envelope. Peak background memory is at most 100 MiB.
- The two persistent databases together occupy at most 2 GiB at the Verification Data Envelope. The authoritative database occupies at most 250 MiB of that total, and simplified route geometry at most 100 MiB.
- Exceeding the verification envelope does not authorize eviction of Locally Authoritative Data, silent truncation of the HealthKit Mirror, or falsification of insight coverage. Storage use remains inspectable.

### Migration, import, export, and recovery guarantees

- Every released authoritative and reconstructible schema has a direct tested upgrade path to the current schema; an owner is never required to install an intermediate app version. Every earlier released Training Compass Export remains directly importable through its explicit export migration path.
- At the Verification Data Envelope, an authoritative database migration completes within 15 seconds at the 95th percentile, a reconstructible migration within 60 seconds, and authoritative export creation or replacement-import staging within 30 seconds. Dedicated progress appears when any operation runs longer than one second.
- Before migration, import, export, or rebuild, Training Compass measures the required staging and recovery space and requires that amount plus a 20% safety margin. Insufficient space prevents the operation from starting, explains the estimated requirement, and leaves existing data unchanged.
- A staged replacement retains the original authoritative database until validation, invariant checks, migration, and the recoverable same-volume swap succeed. Termination at every phase is safely retryable and leaves either the original or the fully validated replacement authoritative—never a partial mixture.
- An authoritative migration failure never triggers erasure. It preserves the original and offers recovery or an inspectable diagnostic export. A reconstructible failure may lead only to the already-confirmed Health Data Rebuild path.
- During incremental Health import, work checkpoints and pauses before available storage falls below 500 MiB. It never reclaims space by deleting authoritative history or silently shortening mirrored coverage.
- Duration budgets are release gates, not destructive runtime deadlines. An over-budget operation remains correct, reports progress, and offers cancellation only at a safe checkpoint. Resumable Health work may pause automatically; an authoritative migration completes or rolls back atomically. A privacy-safe diagnostic records the overrun.

### Background and Device Energy budgets

- Reconciliation favors minimum Device Energy over finishing as quickly as possible: triggers coalesce, there is no polling, completed batches checkpoint durably, and unfinished work continues during a later foreground or background opportunity.
- One opportunistic background execution slice voluntarily stops after at most 20 seconds, or earlier when iOS background time expires. It checkpoints every batch and preserves the current anchor on any uncommitted work.
- Across five matched physical-device runs, a 30-minute normal daily-use scenario consumes no more than one battery percentage point and no more than 0.5 percentage points above its idle-control run. A 30-minute full initial-import or rebuild scenario consumes no more than five battery percentage points.
- Neither scenario may reach a serious or critical thermal state. Discretionary rebuild work pauses under Low Power Mode, serious thermal pressure, or battery below 20%, unless the owner explicitly continues it in the foreground. Normal local training work remains available.

### Route enrichment

- A route is fetched only when the owner explicitly opens its route view. Training Compass permits one route operation at a time, never prefetches routes, and never retains the original full-resolution coordinates.
- Simplification retains at most 2,000 points while preserving useful path shape. After HealthKit returns the route, app-controlled decoding, simplification, persistence, and display preparation complete within two seconds at the 95th percentile.

### On-device verification and measurement

Every release candidate passes these scenarios on the Acceptance Device:

- clean cold launch, warm launch, and foreground resume;
- local set logging while Health reconciliation is active;
- a normal daily Health delta;
- a full-envelope initial import and Health Data Rebuild;
- direct upgrade from every historical authoritative and reconstructible schema;
- export and replacement import from every historical export version;
- termination and recovery during every migration, import, rebuild, and swap phase;
- worst-case Rolling Workout Overview, Running Performance, Recovery Guidance, and e1RM queries;
- route fetch and simplification at the retained-point limit;
- locked-device deferral followed by unlock recovery;
- Low Power Mode, battery below 20%, storage pressure, and simulated memory pressure; and
- the 30-minute normal daily-use and rebuild Device Energy scenarios.

Use optimized release builds with production logging settings and deterministic dataset seeds. For latency and memory, discard one conditioning run, execute ten measured runs, and gate on the 95th percentile. For Device Energy, execute five measured scenarios and five matched idle controls. Preserve the scripts, deterministic fixtures, raw measurements, and summarized verdict in the repository.

### Diagnostics and projection materialization

- Production diagnostics retain at most the newest seven days or 200 events, whichever is smaller. An event may contain operation name, duration, record count, byte count, peak-memory estimate, result category, and coarse device conditions.
- Diagnostics exclude workout measurements and dates, route coordinates, HealthKit identifiers, lift results, and free-text notes. Diagnostic export is always explicit and inspectable.
- An on-demand Derived Projection may become a persistent cache only after an indexed implementation still exceeds the 750-millisecond insight budget at the Verification Data Envelope in repeatable tests. The change requires a recorded benchmark, explicit algorithm and source-revision cache keys, equivalence tests against the uncached calculation, and proof that deleting the cache changes latency only.
