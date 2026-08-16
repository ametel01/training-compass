# Evidence index

`make evidence` writes `evidence/gate-zero-environment.json`. The file is
ignored by Git because it contains host and attended-device results, but it is
the inspectable release handoff for one exact repository revision.

The index has a closed top-level contract:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Evidence-index schema revision. |
| `gitRevision` | Exact source revision used for every command revision. |
| `commands` and `commandRevisions` | Canonical commands and the revision that produced each result. |
| `environment` | Coarse host, Swift, and Xcode metadata; no device identifier or owner data. |
| `fixtureSeed` and `algorithmVersions` | Deterministic fixture and migration/performance algorithm identities. |
| `artifacts` | Hashes and sanitized references for the matrix, runbooks, dependency graph, capabilities, entitlements, privacy manifest, logging allowlist, migration table, and milestone results. Each attended result carries the source revision used to collect it. |
| `compatibility` | Historical migration/export compatibility summary and fixture hash. |
| `rawMeasurements` | Only the named release-envelope measurements and coarse device conditions. |
| `verdicts` | Automated and attended milestone decisions. Missing device evidence remains `blocked`. |
| `releaseVerdict` | Milestone 6 status, required/accepted milestone list, dedicated Write-back evidence result, and the exact revision used for the final release decision. |
| `waivers` | Empty or explicit owner-accepted, time-bounded waivers with measurement, comparison, scope, effect, and expiry. |

The dependency graph is reduced to package identity, version, and dependency
names before it is written. Absolute checkout paths, URLs, HealthKit records,
workout values, routes, dates, identifiers, and free-text notes are not part of
the index. `evidence/device/*.json` remains the source for attended checks; the
index summarizes it without turning a missing result into a pass.
