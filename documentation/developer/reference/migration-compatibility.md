# Migration compatibility

The two databases and future export format evolve independently.

| Store | Current version | Direct upgrade inputs | Gate |
| --- | --- | --- | --- |
| `authoritative.sqlite` | 17 | Every prefix v1–v17, an interrupted migration, or an empty database | `make verify-migrations` |
| `reconstructible.sqlite` | 10 | Every prefix v1–v10, an interrupted migration, or an empty database | `make verify-migrations` |
| Training Compass Export | 1 | Every released export (currently v1 JSON) | `make verify-migrations`; `TrainingExportBoundaryTests` |

The checked-in [migration compatibility fixture](../../../fixtures/migration-compatibility.json)
is the privacy-safe release evidence for this table. It records one direct
upgrade result for each authoritative and reconstructible schema prefix and
the supported export versions. `deterministic`, `preservedGateZeroMarker`,
`exportVerified`, and `completedMigrationCount` are the raw verdict fields;
no row values,
HealthKit identifiers, dates, or file paths are retained.

| Prefix | Migration identifier | Direct target |
| --- | --- | --- |
| Authoritative v1–v17 | `authoritative_v1_gate_zero` through `authoritative_v17_heart_rate_zone_boundaries` | v17 |
| Reconstructible v1–v10 | `reconstructible_v1_gate_zero` through `reconstructible_v10_write_back_metadata` | v10 |
| Export v1 | `training-compass-export` / manifest schema `1` | v1 import validation |

The verifier creates and round-trips the deterministic v1 export fixture through
encoding, decoding, integrity verification, and import validation. It also
creates each historical prefix twice, upgrades both copies with
the current migrator in one call (without an intermediate app release), and
compares a canonical schema/migration fingerprint. A failed migration writes
only a privacy-safe diagnostic beside the affected database and leaves the
original data available for retry or inspection. Migration and replacement
import space checks reserve the live or rollback copy, isolated staging, and a
20 percent safety margin before mutating data; progress callbacks expose the
checking, migration, and completion phases immediately for work that runs
longer than one second.

The authoritative v1 migration creates the Gate 0 marker; v2 adds lift configuration and its append-only audit ledger; v3 adds the reusable Schedule Template and replacement audit ledger; v4 adds the single Draft Training Cycle, dated weeks/sessions, lifecycle indexes, and its audit ledger; v5 adds durable Set Results and their audit ledger; v6 adds omitted dispositions, ordered Additional Sets, and explicit Session completion; v7 adds session projections and atomic correction audit history; v8 adds the Training Week source audit action for saving a normal week back to the Schedule Template; v9 adds optional notes to the cycle lifecycle audit ledger; v10 adds optional target IDs so week-finish audits identify their week; v11 adds Training Max proposals and their evidence-bearing history ledger; v12 adds authoritative HealthKit UUID link facts; v13 adds active one-to-one uniqueness, unlink history, completion-link provenance, and the explicit no-Write-back disposition; v14 adds the optional owner maximum-heart-rate configuration; v16 adds durable optional HealthKit write-back preference and per-Session delivery state; v17 expands the existing heart-rate configuration with the owner-supplied Apple Watch resting reference and Zone 2–5 lower bounds. Reconstructible v2 adds the source-aware Health Workout mirror; v3 adds the deletion, stream checkpoint, and fact ledgers used by anchored reconciliation; v4 adds durable deep-rebuild state; v5 adds per-workout heart-rate, distance, and active-energy enrichment keyed by the existing HealthKit UUID; v6 adds simplified, source-bound route segments and route provenance keyed by the same UUID; v7 adds source-owned running environment; v8 adds optional elevation; v9 adds the independent Recovery Evidence sample mirror; v10 adds optional app-authored sync identifier/version metadata for versioned HealthKit Session summaries. Every released migration remains in order. The verifier exercises interrupted fresh setup and idempotent retry for both stores; retained authoritative upgrade compatibility is covered by the repository migration tests.

Training Compass Export schema version 1 is a deterministic UTF-8 JSON document. Its manifest records the archive type, schema and generator versions, creation timestamp, and creation context. The authoritative section contains every row from the authoritative SQLite store, including audit rows, relationships, metadata, and stable record identifiers; preferences are represented separately. The readable summary is derived from those same rows. An optional `healthKitMirror` section is explicitly labelled reference material and is never treated as canonical data. The integrity section contains a SHA-256 digest over the manifest, summary, authoritative section, and optional mirror. Temporary files are created only after the sensitive-data confirmation and are removed when sharing completes, is cancelled, or fails recoverably. Version 1 is the only released export schema, and its direct upgrade/import path is exercised by the compatibility verifier rather than assumed from the current generator.

Import decodes and verifies the complete document before checking supported schema, table shape, relationships, and domain invariants. A validated archive is migrated into a same-volume staging database, projections are regenerated there, and the authoritative file is replaced only after the staged connection closes. The old file is retained as a rollback candidate during the rename sequence; injected failure before completion restores it. A non-empty store requires export-first replacement confirmation. Version 1 exports created against authoritative v12 remain importable: the v13 link fields receive explicit `false`, `notApplicable`, and `null` defaults before relationship validation. HealthKit mirror material is never installed, and the reconstructible store remains independent. Simplified routes remain reconstructible and are excluded from the authoritative export section by default. A confirmed Health Data Rebuild clears only the reconstructible mirror, routes, enrichment, anchors, facts, and checkpoints, then re-fetches bounded workout pages while regenerating projections from authoritative data. Routes return only after their workout detail is opened again. Authoritative HealthKit UUID link facts remain available for exact reconnection when an object returns; an absent Health object never deletes a local Session or audit row. Reconstructible v7 adds source-owned running environment and v8 adds optional elevation for the running projection; older workout rows migrate to an explicit `unspecified` environment with unavailable elevation.
