# Workout route Acceptance Device checklist

Run this checklist on the same paired, recently unlocked iPhone used for the
Health foundation record. Use a Health Workout that has an Apple Health route
and at least one workout without an available route. Do not copy route
coordinates, screenshots, workout dates, or HealthKit identifiers into the
evidence record.

1. Install the Release configuration in place and open Health. Run ordinary
   Health import, foreground refresh, and late Workout Enrichment without
   opening a workout detail. Verify that no route authorization sheet appears
   and no route is fetched or displayed.
2. Open the route-bearing workout detail. Verify that route authorization is
   requested only now and that the detail first presents Loading, then a Ready
   route plot with source provenance and retained-versus-original point counts.
3. Open the same detail repeatedly and open a second workout detail while the
   first route is loading. Verify that duplicate opens share one operation and
   different workouts remain serialized.
4. Open the workout without a route and verify the distinct Unavailable state.
   Inject or reproduce a query failure and verify Failed; leave a detail while
   loading and verify Cancelled; use Retry to reach the current result.
5. Relaunch and reopen the successful detail. Verify that the simplified route
   is loaded from protected, backup-excluded reconstructible storage without a
   new query. Delete the source workout in Health, refresh, and verify its route
   is removed with the workout.
6. Fetch the route again, then run confirmed Health Data Rebuild. Verify that no
   partial route is shown as complete and that the route remains absent until
   the returning workout detail is deliberately opened again.
7. Exercise storage below 500 MiB, Low Power Mode, battery below 20%, and
   serious thermal pressure. Verify that route work is refused before mutation,
   local training stays usable, and retry works after pressure clears.
8. After one conditioning run, measure ten route operations. Record the coarse
   `App processing` millisecond value shown by the Ready view; it sums decoded
   page handling, simplification, reconstructible persistence verification, and
   display-ready model preparation while excluding HealthKit query wait. Sort
   the ten values, use the tenth value as the nearest-rank 95th percentile, and
   verify it is at most two seconds. Report HealthKit wait separately. Verify
   foreground memory and simplified route storage remain inside the release
   envelope.
9. Inspect the default Training Compass Export, device logs, and evidence
   payload. Verify that route geometry appears in none of them and that only
   coarse counts, duration, device/OS context, and pass/fail results are
   recorded.

Record pass or fail for on-demand authorization, no-prefetch behavior,
serialization, each presentation state, relaunch, deletion, rebuild, resource
pressure, the two-second budget, storage, and privacy. Never record the route
itself or other owner measurements.
