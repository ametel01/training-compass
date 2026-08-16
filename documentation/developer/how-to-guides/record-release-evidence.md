# Record release evidence

Use this guide when preparing a release-candidate handoff for one exact
Training Compass revision.

## Automated evidence

Run the repository-native gates from a clean, selected Xcode toolchain:

```sh
make verify
make verify-migrations
make verify-performance
make acceptance
```

The gates validate dependency direction, package and capability allowlists,
privacy-manifest values, protected-store and backup contracts, deterministic
fixtures, migration compatibility, the release-performance protocol, and the
acceptance matrix. The production diagnostic store is covered by
`PrivacyDiagnosticsTests`; its export is explicit and its cleanup is
caller-owned.

## Attended device evidence

For each owner-usable milestone, print and complete its checklist:

```sh
make device-smoke MILESTONE=gate-0
make device-smoke MILESTONE=health-foundation
make device-smoke MILESTONE=unified-events
make device-smoke MILESTONE=training-insights
make device-smoke MILESTONE=recovery-evidence
make device-smoke MILESTONE=personal-team-refresh
```

Record only the fields accepted by `scripts/device-smoke.sh`: coarse device
conditions, privacy-safe measurements, and pass/fail booleans. Never put
HealthKit identifiers, workout measurements, routes, dates, credentials, or
free-text notes in a result. If a route-bearing workout is unavailable, use
the explicit `UNIFIED_ROUTE_ON_DEMAND=not_available` boundary rather than
inventing a pass.

## Build the index

After the automated and attended records are available, generate the ignored
handoff index:

```sh
VERIFY_RESULT=pass \
MIGRATION_RESULT=pass \
PRIVACY_RESULT=pass \
UI_RESULT=pass \
make evidence
```

Inspect `evidence/gate-zero-environment.json`. Confirm that `gitRevision`
matches the reviewed commit, the dependency graph contains only the reviewed
package, every current device result is meaningful (or explicitly missing),
and `verdicts` never reports an eligible release gate without attended owner
approval. Preserve the index with the release handoff; it is not a substitute
for the owner-attended checklists.
