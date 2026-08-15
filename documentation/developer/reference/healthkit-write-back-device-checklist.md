# HealthKit Write-back Acceptance Device checklist

Run this checklist on the in-place Acceptance Device after the automated gates
pass. Record only pass/fail state and timing; do not include workout measures,
HealthKit identifiers, or owner data in evidence artifacts.

1. Open Health and confirm the Session-summary preference is off. Verify that
   no HealthKit write authorization prompt appears during launch or read-only
   Health connection.
2. Enable the preference and record that the write authorization prompt occurs
   only after the toggle. Cancel it once and verify local training remains
   usable; re-enable and grant access for the remaining checks.
3. Complete a resolved Session. Read the disclosure and choose Keep this
   Session local. Verify the Session is Completed and its detail says Not
   shared without waiting on Health.
4. Complete another resolved Session, choose Share summary, and verify the
   detail transitions through Queued/Saving to Saved to Health while navigation
   and local history remain responsive.
5. Open the saved Health workout and verify it is Traditional Strength
   Training with start, end, duration, and Training Compass sync metadata only.
   Confirm sets, loads, prescriptions, Training Maxes, e1RM, notes, and audit
   history are absent.
6. Repeat the completion or retry action and verify no duplicate summary is
   created. Link a Session to an external Health workout during completion and
   verify no Training Compass summary is created.
7. Disable Health access or lock the device before a queued save. Verify local
   completion and navigation succeed, and the detail reports a retry/access
   state. Restore access and explicitly retry; verify the same sync identity is
   saved once.

8. With a retryable queued operation, background or lock the device before the
   save finishes. Return to the app and verify the durable state becomes
   `Retry scheduled`, then resumes at launch or the next foreground entry
   without a duplicate Health workout. Cancellation and repeated foreground
   entry must have the same result.
9. With denied or unavailable write access, verify the Session reports `Health
   access needed`, offers `Check Health Access`, and does not retry on every
   foreground entry. After access is restored, tap `Try Again` explicitly.
   With a persistent non-permission failure, verify `Couldn't save` and
   `Try Again` while the Completed local Session remains intact.
10. Verify Health Settings shows a quiet aggregate count for affected Session
    summaries. Use `Refresh Health Data` and confirm it does not retry any
    write-back; read freshness and write-back state remain independent.
11. Reopen a Completed Session with an existing Training Compass summary.
    Verify the local edit commits first and the summary reports `Update
    pending` while the Session is being edited. Re-complete without changing
    start/end facts and confirm the existing Health object is reused; change a
    start/end fact and confirm a greater sync version is published.
12. Re-import the same HealthKit UUID out of order (including a lower sync
    version) and verify the highest version remains current and superseded
    versions do not create extra timeline/history events. If equal highest
    versions exist, verify the conflict is visible and no object is deleted
    automatically.
13. Move a reopened Session to Skipped, or remove it through Program Edit,
    and verify the local summary relationship is unlinked without deleting an
    external Health workout. Any duplicate cleanup must name an explicit
    retained object and delete only objects authored by Training Compass.

14. Delete a Training Compass-authored summary in Apple Health. Verify the
    local Session remains Completed, the detail reports `Deleted from Health`,
    and no foreground, retry, or read refresh recreates it. Verify the deleted
    object remains absent from the current Health mirror while the local
    summary identity is retained.
15. Reconcile the exact deleted UUID again and verify the existing summary
    returns to `Saved to Health` without a new write. Reconcile a different UUID
    carrying the same sync identifier and verify it remains a separate Health
    Workout until the owner explicitly chooses Restore to Health. Tap Restore
    to Health and verify a new object is queued/saved with the next sync
    version and normal failure/access states remain available.
16. Choose an external Health Workout to replace an app-authored summary.
    Confirm the action and verify the app-owned object is deleted first and the
    external link is then created. Force the app-owned deletion to fail and
    verify no link is created, the prior write-back relationship is unchanged,
    and a retryable explanation is shown. Confirm an external workout is never
    deleted or rewritten.

The corresponding automated evidence is `HealthWorkoutWriteBackBoundaryTests`,
the write-back repository tests, the HealthKit adapter tests, the lifecycle/UI
integration, and `make verify`.
