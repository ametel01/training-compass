# Training Event linking Acceptance Device checklist

Run this checklist on the same paired, recently unlocked iPhone used for the
Health Workout Foundation record. Keep the existing app container so the run
also verifies migration and continuity. Record only coarse results; never copy
HealthKit UUIDs, workout measurements, dates, or source metadata into evidence.

1. Install the Release build in place. Confirm existing Training Maxes,
   Sessions, audit history, Health status, and exports remain present after the
   authoritative v14 migration.
2. Complete a 5/3/1 Session with at least two unlinked external Health Workouts
   available. Verify every workout remains selectable, likely matches appear
   first, and no candidate is preselected or linked automatically.
3. Select a candidate whose activity, local date, or completion timing is
   unusual. Verify the mismatch is explained and the link is not created until
   the separate unusual-match confirmation is accepted.
4. Confirm one link. Verify the Completed Session and Health Workout stable
   identities remain visible, the timeline contains one Training Event rather
   than two, and a second Session or Health Workout cannot claim either active
   identity.
5. Inspect Training Event detail. Verify the 5/3/1 Session is authoritative for
   local training facts, HealthKit is authoritative for workout facts, both
   provenance sections remain visible, disagreements are shown without silent
   overwrite, and the last reconciliation state and context are inspectable.
6. Refresh or replace the candidate workout while reviewing a link. Verify a
   stale confirmation is rejected and the refreshed candidates must be
   reviewed again.
7. Delete the linked workout from the Health mirror or run the confirmed Health
   Data Rebuild. Verify the local Session and authoritative link identity remain
   available, then verify the same HealthKit UUID reconnects when it returns.
8. Explicitly unlink the Training Event. Verify the timeline returns to one
   local Session event and one Health Workout event, neither source is deleted,
   and a new explicit link can use the same stable identities.
9. Repeat Session completion while explicitly selecting an existing external
   Health Workout. Verify completion and link appear together and no Training
   Compass workout-summary Write-back is requested or recorded.
10. Inspect the privacy-safe evidence and logs. Verify no workout payload,
    HealthKit UUID, owner measurement, or free-text provenance is emitted.

Record pass or fail with device model, iOS version, authoritative migration
result, candidate-ranking result, warning-confirmation result, duplicate-link
rejection, stale-confirmation rejection, single-count result, exact-UUID
reconnection, unlink result, Write-back suppression, and privacy verdict.
