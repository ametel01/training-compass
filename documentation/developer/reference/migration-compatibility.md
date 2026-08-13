# Migration compatibility

The two databases and future export format evolve independently.

| Store | Current version | Direct upgrade inputs | Gate |
| --- | --- | --- | --- |
| `authoritative.sqlite` | 11 | Gate 0 v10 database or empty database; earlier Gate 0 versions migrate through the retained chain | `make verify-migrations` |
| `reconstructible.sqlite` | 1 | Empty database | `make verify-migrations` |
| Training Compass Export | 1 | Version 1 JSON archive | `TrainingExportBoundaryTests`; `TrainingExportRepositoryTests` |

The authoritative v1 migration creates the Gate 0 marker; v2 adds lift configuration and its append-only audit ledger; v3 adds the reusable Schedule Template and replacement audit ledger; v4 adds the single Draft Training Cycle, dated weeks/sessions, lifecycle indexes, and its audit ledger; v5 adds durable Set Results and their audit ledger; v6 adds omitted dispositions, ordered Additional Sets, and explicit Session completion; v7 adds session projections and atomic correction audit history; v8 adds the Training Week source audit action for saving a normal week back to the Schedule Template; v9 adds optional notes to the cycle lifecycle audit ledger; v10 adds optional target IDs so week-finish audits identify their week; v11 adds Training Max proposals and their evidence-bearing history ledger. The reconstructible store remains v1. Every released migration remains in order, and the verifier exercises interrupted setup, idempotent retry, and a v7-to-v8 upgrade while preserving existing completion data.

Training Compass Export schema version 1 is a deterministic UTF-8 JSON document. Its manifest records the archive type, schema and generator versions, creation timestamp, and creation context. The authoritative section contains every row from the authoritative SQLite store, including audit rows, relationships, metadata, and stable record identifiers; preferences are represented separately. The readable summary is derived from those same rows. An optional `healthKitMirror` section is explicitly labelled reference material and is never treated as canonical data. The integrity section contains a SHA-256 digest over the manifest, summary, authoritative section, and optional mirror. Temporary files are created only after the sensitive-data confirmation and are removed when sharing completes, is cancelled, or fails recoverably.
