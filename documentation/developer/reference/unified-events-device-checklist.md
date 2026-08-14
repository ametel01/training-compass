# Unified Events and Enrichment Acceptance Device checklist

Run this checklist on the same paired, recently unlocked iPhone used for the
Health foundation, Training Event linking, and workout-route records. Install
the Release build in place without clearing the application container. Use one
completed local Session, two external Health Workouts, and a workout with a
route when available.

1. Before installing, confirm the prior build contains Training Maxes, a
   Completed Session, lifecycle and correction audit history, Health status,
   and export/import actions. Install in place and verify every prior owner
   record and stable identity remains present. Keep local Today, Cycle,
   Progress, and TMs workflows usable throughout the remaining enrichment work.
2. Inspect the Completed Session and a separate Health Workout. Verify they
   begin as two Training Events. Review likely and unusual candidates, confirm
   that none is preselected, and accept an unusual match only after its
   separate warning acknowledgement.
3. Verify the linked pair counts once while both stable records remain visible.
   Inspect local-training authority, Health source authority, provenance,
   current reconciliation state, source disagreement, and link audit history.
4. Exercise late heart rate, distance, and active-energy results independently:
   available, successful-but-missing, failed after cached success, changed, and
   deleted. Verify each result updates the existing event under the same
   HealthKit UUID, never creates a duplicate, and never invents a zero value or
   unobserved heart-rate interval.
5. Where a route is available, open its detail and verify authorization and
   fetch begin on demand. Exercise Loading, Unavailable, Failed, Cancelled, and
   Ready; confirm serialized operations, at most 2,000 retained points, source
   provenance, restart persistence, retry, and no partial Ready state.
6. Delete the linked workout externally and verify the local Session and former
   link remain. Import a similar workout with a new UUID and verify it remains
   separate and selectable. Restore the exact deleted UUID and verify automatic
   reconnection. Run Health Data Rebuild and repeat exact reconnection, then
   explicitly unlink and verify two events return without deleting either
   source record.
7. Where a route-bearing workout is available, after one conditioning run,
   perform ten route operations and record the nearest-rank 95th-percentile
   app-processing value. Verify the two-second route budget, route storage, and
   resource-pressure refusal. On every device, verify foreground memory and
   local responsiveness against the release envelope.
8. Inspect the default authoritative export, device logs, and evidence record.
   Verify route geometry, HealthKit UUIDs, owner measurements, dates, source
   payloads, and free-text notes are absent. Confirm only fixed privacy-safe log
   events and coarse evidence fields remain, and unfinished recovery insight or
   guidance behavior is hidden.

Record pass or fail for prior-data continuity, linked single count, source
detail, late or unavailable enrichment, exact-UUID recovery, explicit unlink,
on-demand route behavior where available, route budgets, local availability,
privacy, and hidden unfinished insights. Set `UNIFIED_ROUTE_ON_DEMAND=true` when
the route checks run, or `UNIFIED_ROUTE_ON_DEMAND=not_available` when the device
has no route-bearing workout; the latter makes route-only measurements optional
without weakening the other resource checks. Record only device model, iOS
version, coarse measurements, and these outcomes; never record owner data or
routes.
