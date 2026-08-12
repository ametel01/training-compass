# Define unified workout identity and reconciliation

Type: grilling
Status: resolved
Blocked by: 01

## Question

How should the app identify and reconcile imported Health Workouts with completed 5/3/1 Sessions written back to Apple Health? Decide provenance visibility, duplicate prevention, updates, deletions, re-imports, corrections, and the source of truth for fields that exist both locally and in HealthKit.

## Answer

### Unified identity and linking

- A Training Event is the single user-visible occurrence of training. It contains a Health Workout, a 5/3/1 Session, or one linked pair when both records describe the same real-world workout. A linked pair appears once in timelines and aggregate counts while both underlying records remain intact.
- A Training Compass HealthKit Write-back links to its local 5/3/1 Session by the stable local-session sync identifier in `HKMetadataKeySyncIdentifier`. Its `HKMetadataKeySyncVersion` orders revisions, and the current HealthKit UUID is retained as the imported object's identity.
- An externally recorded Health Workout may link one-to-one to a Completed 5/3/1 Session only through explicit user choice. The app may rank candidates by timing and activity but never auto-links from overlap, similarity, source, or workout type. Any currently unlinked Health Workout remains selectable, with a warning for an unusual match.
- If an external Health Workout is already linked when the Session is completed, Training Compass does not create another summary. Unlinking produces separate Training Events and never deletes the external workout.

### Source authority and visibility

- Linking does not merge fields or transfer ownership. The local Session remains authoritative for its schedule relationship, status, lifts, prescriptions, results, e1RM evidence, notes, audit history, and locally recorded start/end facts. HealthKit remains authoritative for the imported Health Workout's activity, start/end/duration, associated metrics, source/device provenance, and deletion state.
- Session history uses local Session facts; Health-derived workout summaries use HealthKit facts. When linked values disagree, the app preserves and can show both with their sources rather than silently overwriting either.
- Every Training Event shows a compact source badge. Detail exposes available source app/device information, both sides of a link, write-back and conflict state, missing provenance, and last successful reconciliation. Missing HealthKit provenance is represented as unavailable rather than inferred.

### Write-back consent and normal reconciliation

- HealthKit Write-back is governed by a persistent opt-in preference that defaults off. When enabled, Session completion discloses that write-back will occur and permits a per-session opt-out.
- Local completion is independent of HealthKit. Denied permission, unavailable access, or a failed save leaves the Session Completed locally and records a visible pending, unavailable, or failed write-back state for later handling.
- Re-import of the same HealthKit UUID is an idempotent upsert, not another event. A higher version for the same Training Compass sync identifier becomes the current summary and lower versions are superseded and excluded from counts.
- If multiple live objects unexpectedly share the highest sync version, the Training Event is still counted once and exposes a conflict. Repair is explicit and may delete only the extra app-owned objects; reconciliation never silently deletes them.

### Corrections, reopening, and replacement

- After an audited local correction changes a field present in the app-authored HealthKit summary, the app automatically queues a greater sync version once the correction is confirmed. Synchronization failure never rolls back the local correction.
- Reopening a Completed Session keeps its link and existing Health Workout but marks an app-authored summary stale while editing. Re-completion publishes a greater version when summary facts changed.
- If a reopened Session is ultimately Skipped, removed through an allowed Program Edit, or left Unperformed, it no longer describes that workout: Training Compass deletes an app-authored summary or unlinks an external workout. It never deletes another source's Health Workout.
- Replacing an existing app-authored summary with an external Health Workout requires explicit confirmation. The app first deletes its own summary and establishes the external link only after deletion succeeds; failure leaves the prior link unchanged.

### Deletions and re-imports

- When the user deletes an app-authored summary in Apple Health, the local 5/3/1 Session remains and the write-back is recorded as externally deleted. Training Compass does not recreate it automatically; an explicit Restore to Apple Health action creates the next version.
- When an externally linked Health Workout is deleted, the local Session remains as its own Training Event and the former link is retained as history. The app never substitutes a similar object automatically.
- If the exact deleted HealthKit UUID returns, reconciliation restores its former link. An arriving object with a new UUID is a separate Health Workout even when its source, timing, and activity resemble the deleted record; the user may explicitly choose it as a replacement.
