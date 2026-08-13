# Migration compatibility

The two databases and future export format evolve independently.

| Store | Current version | Direct upgrade inputs | Gate |
| --- | --- | --- | --- |
| `authoritative.sqlite` | 11 | Gate 0 v10 database or empty database; earlier Gate 0 versions migrate through the retained chain | `make verify-migrations` |
| `reconstructible.sqlite` | 1 | Empty database | `make verify-migrations` |
| Training Compass Export | Not introduced | Not applicable in Gate 0 | Build exposes no export or import path |

The authoritative v1 migration creates the Gate 0 marker; v2 adds lift configuration and its append-only audit ledger; v3 adds the reusable Schedule Template and replacement audit ledger; v4 adds the single Draft Training Cycle, dated weeks/sessions, lifecycle indexes, and its audit ledger; v5 adds durable Set Results and their audit ledger; v6 adds omitted dispositions, ordered Additional Sets, and explicit Session completion; v7 adds session projections and atomic correction audit history; v8 adds the Training Week source audit action for saving a normal week back to the Schedule Template; v9 adds optional notes to the cycle lifecycle audit ledger; v10 adds optional target IDs so week-finish audits identify their week; v11 adds Training Max proposals and their evidence-bearing history ledger. The reconstructible store remains v1. Every released migration remains in order, and the verifier exercises interrupted setup, idempotent retry, and a v7-to-v8 upgrade while preserving existing completion data.
