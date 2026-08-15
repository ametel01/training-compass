# Recovery Evidence and Guidance Acceptance Device checklist

Run this checklist on the in-place Acceptance Device after the optimized
Release build is installed. Do not clear the application container: Recovery
Evidence and Guidance must retain the owner data approved by earlier gates.
Record only booleans and coarse release measurements; never capture recovery
measurements, dates, source identifiers, HealthKit UUIDs, or free-text notes.

## Evidence and explanation reachability

- [ ] In Health, verify Primary Sleep and Nap episodes remain separate, source
  overlap is represented once, Preferred Sleep source changes are visible, and
  exact 90-minute versus longer gaps produce the documented episode boundaries.
- [ ] Inspect resting-heart-rate and HRV SDNN observations with sparse dates,
  sample counts/medians, source and algorithm context, coverage, freshness,
  failure state, and last successful reconciliation.
- [ ] Inspect every Personal Recovery Baseline and its explanation. Verify the
  28-day local window, current-day exclusion, 13/14-day threshold, middle-half
  band boundaries, exact difference, source, exclusions, limitations, and
  reconciliation time are named.
- [ ] Open the explanation for an available Recovery Guidance prompt and verify
  that each measurement is enumerated independently with neutral language.

## Withholding and safety

- [ ] Exercise aligned, conflicting, missing, stale, failed, corrected,
  disabled, insufficient-family, and incomparable-source states. Verify that
  evidence, history, collection, and explanations remain visible while the
  prompt is withheld whenever its gate is not satisfied.
- [ ] Verify no displayed Recovery output contains a score, diagnosis, medical
  or injury-risk claim, causal interpretation, performance prediction, warning
  threshold, or training prescription. The owner alone decides whether to
  keep or change a Session.
- [ ] Refresh or rebuild Health data and confirm current-day correctness,
  bounded batching, cached-content preservation, and local training
  availability during interruption, backgrounding, and resume.

## Resource, privacy, and continuity envelope

- [ ] With the Verification Data Envelope loaded, measure worst-case Recovery
  import, baseline, and guidance work. Each app-controlled insight query is at
  most 750 milliseconds at P95; Health wait time is recorded separately.
- [ ] Confirm peak memory, persistent storage, page size, and transient buffers
  remain within the release-candidate checklist. Evidence and logs contain no
  recovery values, dates, source identifiers, or HealthKit UUIDs.
- [ ] Verify the in-place install preserves earlier local training data and
  leaves HealthKit Write-back hidden.

The attended record is eligible only when every checklist item passes and the
release-envelope measurements pass `scripts/check-release-envelope.py`.
