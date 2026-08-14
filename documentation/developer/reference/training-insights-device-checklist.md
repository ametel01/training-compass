# Training and Running Insights Acceptance Device checklist

Run this checklist on the in-place Acceptance Device after the optimized
Release build is installed. Do not clear the application container: the
milestone must retain the owner data approved by the earlier gates. Record only
the booleans and coarse measurements accepted by `make device-smoke`; do not
capture workout measurements, dates, identifiers, routes, or notes.

## Explanation reachability

- [ ] From Progress, open the explanation for the selected lift's latest,
  previous, cycle-best, and trailing-90-day e1RM values.
- [ ] Open the source detail for an e1RM point and verify the eligible Plus Set,
  correction state, date, formula, and excluded records are visible.
- [ ] Open explanations for rolling workout count, duration, each activity
  group, and every available Heart-Rate Zone aggregate.
- [ ] Open a workout's Heart-Rate Zone detail and reach its explanation from
  the displayed zone values; verify the configured maximum, source intervals,
  covered duration, gaps, and workout-edge coverage are named.
- [ ] Open the selected running workout, its pace and missing-fact explanation,
  each Running Volume measure, and the selected-run comparison.
- [ ] Verify every explanation names source records, dates, source coverage,
  calculation rules, comparison baseline where applicable, exclusions, missing
  data, configuration, and last reconciliation context.

## Correctness and safety

- [ ] Confirm a corrected local Set Result changes the affected e1RM projection
  while preserving the source fact and audit history.
- [ ] Change the configured maximum heart rate and verify historical zones are
  recalculated from the same Health samples without duplicating Training Events.
- [ ] Refresh Health data with a replacement and a deletion; verify rolling,
  zone, running, volume, and comparison projections update while source UUIDs,
  local dates, and linked single-count identity remain stable.
- [ ] Verify missing duration, distance, heart-rate coverage, long gaps, and
  incomplete comparison coverage remain unavailable rather than zero-filled or
  inferred.
- [ ] Verify no displayed view emits a combined training-load score, personal
  record, goal, fitness claim, inferred effort, race prediction, causal claim,
  recovery verdict, or automatic prescription.

## Responsiveness and continuity

- [ ] With the Verification Data Envelope loaded, measure worst-case e1RM,
  rolling overview, Heart-Rate Zone, Running Volume, and Comparable Run
  queries; each 95th percentile is at most 750 milliseconds of app-controlled
  insight work, excluding HealthKit wait time.
- [ ] Background and resume the app during insight loading; local training
  remains usable and committed source facts are not lost.
- [ ] Verify the in-place milestone retains all earlier owner data and keeps
  Recovery Evidence, Recovery Guidance, and HealthKit Write-back hidden.

The attended record is eligible only when every checklist item passes and the
release-envelope measurements pass `scripts/check-release-envelope.py`.
