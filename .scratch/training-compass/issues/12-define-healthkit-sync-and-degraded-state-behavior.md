# Define HealthKit sync and degraded-state behavior

Type: grilling
Status: resolved
Blocked by: 01

## Question

What user-visible states and recovery controls govern HealthKit authorization, limited history, locally empty or unavailable data, background-delivery delays, stale evidence, locked-device failures, late workout enrichment, and write-back denial or retry? Decide freshness language, retry and foreground-reconciliation behavior, manual refresh or rebuild controls, and which failures may degrade gracefully without blocking local 5/3/1 logging, while never claiming knowledge of a hidden read-permission state.

## Answer

### Authorization and local-only use

- After an explanatory preflight, Training Compass requests the core read types together: Health Workouts and the agreed Recovery Evidence streams. HealthKit Write-back remains off by default, and write authorization is requested only when the user enables it. Route access is requested only when route functionality is used.
- Postponing or cancelling authorization, receiving no readable records, or losing Health access never blocks local cycle setup, Training Max management, prescriptions, 5/3/1 logging, local history, export, import, or restoration.
- Before read authorization is requested, the product says **Connect Health**. When a successful query returns no readable records, it says **No Health data is currently available** and offers **Check Health Access** and **Refresh Health Data**. It never infers that read access was denied or that Apple Health contains no data.
- When HealthKit positively reports a limited history window, the affected stream says **History available from [date]**. Limited scope is coverage context, not a failure, and calculations use only the records inside it.
- Returning from system Health access settings triggers Foreground Reconciliation. The product reports only observed results and positively known scope; it never claims which read permissions changed.

### Independent Health Data Stream state

- Health Workouts, sleep, resting heart rate, HRV SDNN, and applicable Workout Enrichment are independent Health Data Streams. Success in one never implies success in another.
- Each stream records orthogonal facts rather than one combinatorial status: requested or not requested; positively known limited-history scope; whether mirrored content exists; reconciliation idle, active, or interrupted; last successful check; and the current retryable or actionable failure, if any.
- Screens derive concise messages from those facts:
  - **Updating Health data…** while reconciliation is active.
  - **Last checked [time]** after a successful reconciliation.
  - **History available from [date]** alongside the last check when limited scope is known.
  - **No Health data is currently available** only after a successful empty query.
  - **Update delayed — showing data last checked [time]** after a retryable failure with cached data.
  - **Health data couldn't be updated** after a failed first reconciliation with no cache.
  - **Health needs attention** only for a known, actionable configuration or write-access problem.
- The last successful check is distinct from the timestamp of the newest sample. Exact per-stream coverage, limitations, available content, and failures remain inspectable through Health Data Status.

### Reconciliation and recovery controls

- Training Compass performs non-blocking Foreground Reconciliation at launch and whenever it becomes active. It renders cached data immediately; navigation and local training work never wait behind a sync screen.
- Background observer delivery is an opportunistic wake-up signal, not a freshness promise. Successful background work silently updates the mirror and timestamps. Background delay or failure sends no notification and becomes visible only when the user next visits a relevant screen.
- A locked-device or other transient read failure preserves the prior anchor and cached data. The app retries when protected data becomes available, on the next foreground activation, or after a Health Data Refresh. It does not continuously poll, show a modal, or send repeated alerts.
- **Refresh Health Data** performs a non-destructive incremental reconciliation of every requested stream, coalescing with work already in progress. It neither clears the mirror nor retries HealthKit Write-backs. The control lives on a single Health Data Status screen linked from compact status rows on Today and Progress and from Settings; screens do not implement separate pull-to-refresh contracts.
- The initial import is non-blocking and incremental. The owner enters the app immediately, sees per-area progress, and may dismiss the progress view while completed batches remain durable and interrupted streams resume later.
- **Health Data Rebuild** remains a separate Settings-only repair action behind confirmation that explains what it discards and preserves. The app never runs it automatically and suggests it only for persistent reconciliation inconsistency, not ordinary delay or empty results.
- After confirmation, rebuilding discards the HealthKit Mirror, Derived Projections, and sync cursors, displays **Rebuilding Health data**, saves completed batches, and resumes if interrupted. Locally Authoritative Data and historical Training Event link facts remain intact; exact HealthKit UUIDs reconnect when available. The discarded mirror is not restored as though it were current.

### Freshness, partial degradation, and Recovery Guidance

- A stream is current enough for today's Recovery Guidance only after a successful reconciliation during the current local calendar day. Existing observations remain visible while updating or after failure, with their last-check context, but do not participate in current guidance.
- Recovery Guidance requires at least two Recovery Evidence Families with established Personal Recovery Baselines and a current, successfully reconciled, comparable observation for every baseline-established family. A family that has never established a baseline does not block guidance. A missing, stale, failed, corrected, or source-incomparable observation in an otherwise eligible family suppresses only the prompt; available observations remain visible.
- Combined screens degrade by section. For example, successful Workouts, limited Sleep, delayed HRV, and cached resting heart rate all remain individually visible with their coverage. One stream's failure does not blank a screen or become a misleading global error.
- A successful enrichment query that returns no associated heart rate, distance, energy, or route ends the loading state and labels that specific detail **Not available from Health**. A later addition or replacement updates the existing Health Workout and its affected Derived Projections in place without a notification or another Training Event.

### HealthKit Write-back lifecycle

- Write-back status is independent of Health read freshness and local Session completion. The Session-level vocabulary is **Not shared**, **Queued**, **Saving**, **Saved to Health**, **Retry scheduled**, **Health access needed**, **Couldn't save**, **Deleted from Health**, and **Update pending**.
- A transient save failure schedules a retry after protected data becomes available or on a later foreground reconciliation. A known denied or unavailable write permission does not loop automatically: the Session stays Completed locally, shows **Health access needed**, and offers **Check Health Access** followed by an explicit retry. A persistent failure shows **Couldn't save** with **Try Again**.
- Pending and failed states appear on the affected Session and as a quiet aggregate count in Settings, without banners or notifications.
- A correction or reopened Session that makes an existing app-authored summary stale shows **Update pending** until a greater sync version is saved. A summary deleted in Apple Health shows **Deleted from Health** and is never recreated automatically; only **Restore to Health** creates the next version.
