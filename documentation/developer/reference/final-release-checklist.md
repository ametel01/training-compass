# Final release and Milestone 6 checklist

Issue #48 is the final approval boundary for the private Training Compass
build. It does not replace the individual milestone checklists; it proves that
their results belong to one exact revision and that no missing attended result
has been promoted to a release claim.

## Automated release gate

Run the repository-native gates from the selected Xcode toolchain:

```sh
make verify-final-release
```

The command runs the change, migration, performance, acceptance, and UI gates,
then requires all six attended records before generating the ignored evidence
index and checking the Milestone 6 verdict. A missing, failed, malformed, or
mixed-revision record stops the command before approval.

## Required attended records

Complete and record each checklist using `make device-smoke`:

| Milestone | Record |
| --- | --- |
| Gate 0 owner-data continuity | `evidence/device/gate-0.json` |
| Health foundation | `evidence/device/health-foundation.json` |
| Unified Events and Enrichment | `evidence/device/unified-events.json` |
| Training and Running Insights | `evidence/device/training-insights.json` |
| Recovery Evidence and Guidance | `evidence/device/recovery-evidence.json` |
| Personal Team refresh | `evidence/device/personal-team-refresh.json` |
| HealthKit Write-back and erasure | `evidence/device/healthkit-write-back.json` |

The records contain only the privacy-safe fields accepted by `device-smoke`,
including the source revision used to collect the result.
They must show `result: pass` and owner data continuity. The Personal Team
record additionally proves the stable identity, preflight, profile inspection,
in-place install, launch smoke, and profile-date boundary. The other five
records carry the Release-build Verification Data Envelope measurements and
separate HealthKit wait/app-controlled timings.
The Write-back record is a separate attended check for opt-in, local
completion independence, retry, version replacement, correction/reopen,
conflict repair, deletion/restoration, ownership-safe replacement, and
Full App Erasure. It has no owner measurements or HealthKit identifiers.

## Milestone 6 verdict

`make evidence` writes `evidence/gate-zero-environment.json` for the current
revision. Its `releaseVerdict` must identify Milestone 6, enumerate all six
milestones in order, point at the same `gitRevision` as `HEAD`, and report
`status: eligible` and `writeBackEvidence: true`. The final checker also
requires `verdicts.releaseGate` to be `eligible` and refuses approval when any
milestone or Write-back record is absent.

Do not record HealthKit identifiers, routes, measurements, dates, credentials,
or training notes in the evidence bundle. A missed device run is a blocked
release, not a waiver; only an explicit, owner-accepted, time-bounded waiver
with the complete measurement/comparison/scope/effect/expiry contract may be
retained by the release-envelope gate.
