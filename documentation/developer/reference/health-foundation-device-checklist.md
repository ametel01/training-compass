# Health Workout Foundation Acceptance Device checklist

Run this checklist on the same paired, recently unlocked iPhone used for the
Gate 0 owner-data record. Do not erase the app container between the prior
milestone and this milestone. HealthKit wait time is external-system latency;
record only the app-controlled result and the privacy-safe evidence fields.

1. Build and install the Release configuration in place, then confirm that
   existing Training Maxes, Sessions, audit history, and export/import actions
   remain present.
2. Open Health and verify that the app explains its read-only requested types.
   Confirm that no Health prompt appears during protected-store preparation.
3. With Health access unavailable or postponed, verify that local Today, Cycle,
   Progress, TMs, export, import, and erasure remain usable. The UI must not
   claim that a successful empty query proves read denial.
4. Tap Connect Health and verify the system authorization sheet requests only
   the displayed read types and no write-back type. Record the actual
   authorization result without recording Health samples or identifiers.
5. With at least two Health Workouts available, start the first import. Verify
   that the first durable batch becomes visible while later pages continue,
   cached navigation remains responsive, and each workout retains its source
   badge, local date, provenance, and reconciliation context.
6. Inspect Health Data Status. Verify independent rows for every requested
   stream, including no access, partial or limited history, successful empty,
   first failure, later failure with cached content, and recovered success.
7. Trigger an observer invalidation and a foreground return while a refresh is
   active. Verify that one reconciliation is coalesced, anchored pages are
   applied once, replacements update the same UUID, deletions disappear from
   current events, and local training remains usable.
8. Lock the iPhone during a Health read, unlock it, and use Refresh Health Data.
   Verify that the previous cached content and last committed anchor remain,
   and that retry resumes without deleting local Sessions or audit history.
9. Open Rebuild Health Data. Confirm the destructive scope names only the
   HealthKit Mirror, derived projections, anchors, and reconstructible
   checkpoints. Cancel once, then confirm and verify incremental progress,
   protected local training availability, and exact-UUID reconnection when the
   source workout returns.
10. Inspect the app container after the run. Verify complete file protection on
    both stores, backup exclusion for reconstructible Health data, no workout
    payloads in logs or export-by-default output, and no unfinished linking,
    enrichment, insight, recovery-guidance, route, or Write-back controls.

Record a pass or fail with device model, iOS version, coarse operation
measurements, and the booleans for authorization, anchored queries, observer
registration, foreground refresh, lock/unlock recovery, protected storage, and
backup exclusion. Never record HealthKit UUIDs, owner measurements, dates,
routes, or free text copied from the device.
