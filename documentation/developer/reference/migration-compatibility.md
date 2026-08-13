# Migration compatibility

The two databases and future export format evolve independently.

| Store | Current version | Direct upgrade inputs | Gate |
| --- | --- | --- | --- |
| `authoritative.sqlite` | 6 | Gate 0 v1/v2/v3/v4/v5 database or empty database | `make verify-migrations` |
| `reconstructible.sqlite` | 1 | Empty database | `make verify-migrations` |
| Training Compass Export | Not introduced | Not applicable in Gate 0 | Build exposes no export or import path |

The authoritative v1 migration creates the Gate 0 marker; v2 adds lift configuration and its append-only audit ledger; v3 adds the reusable Schedule Template and replacement audit ledger; v4 adds the single Draft Training Cycle, dated weeks/sessions, lifecycle indexes, and its audit ledger; v5 adds durable Set Results and their audit ledger; v6 adds omitted dispositions, ordered Additional Sets, and explicit Session completion. The reconstructible store remains v1. Later releases must preserve every released migration and add direct-upgrade fixtures before changing this table.
