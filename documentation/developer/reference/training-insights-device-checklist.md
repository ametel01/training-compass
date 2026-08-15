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
- [ ] In Health, inspect the Personal Recovery Baselines for Primary Sleep
  duration, duration consistency, timing consistency, resting heart rate, and
  HRV SDNN. Verify that the current day is excluded from each 28-day window,
  missing dates are not filled, 13 valid days withhold a baseline, 14 valid
  days establish it, and band boundaries are classified within.
- [ ] Verify a current comparison requires a current source-comparable
  observation, shows the exact full-precision difference from the median, and
  uses only longer/shorter, higher/lower, or more/less variable language.
- [ ] In Health, verify Primary Sleep and its duration/consistency measures
  count as one Recovery Evidence Family while resting heart rate and HRV SDNN
  remain separate. Confirm the optional Recovery Guidance prompt appears only
  with two established families and current, successful, comparable evidence.
- [ ] Exercise aligned, conflicting, insufficient, stale, failed, corrected,
  incomparable, disabled, and next-local-day states. Verify measurements remain
  visible, explanations remain reachable, the prompt uses neutral enumeration,
  and the owner—not the app—decides whether to keep or change the Session.

## Responsiveness and continuity

- [ ] With the Verification Data Envelope loaded, measure worst-case e1RM,
  rolling overview, Heart-Rate Zone, Running Volume, and Comparable Run
  queries; each 95th percentile is at most 750 milliseconds of app-controlled
  insight work, excluding HealthKit wait time.
- [ ] Background and resume the app during insight loading; local training
  remains usable and committed source facts are not lost.
- [ ] Verify the in-place milestone retains all earlier owner data, keeps
  Recovery Evidence and its explanations visible when Guidance is disabled,
  and keeps HealthKit Write-back hidden.

The attended record is eligible only when every checklist item passes and the
release-envelope measurements pass `scripts/check-release-envelope.py`.
