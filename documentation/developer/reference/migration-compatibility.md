# Migration compatibility

The two databases and future export format evolve independently.

| Store | Current version | Direct upgrade inputs | Gate |
| --- | --- | --- | --- |
| `authoritative.sqlite` | 2 | Gate 0 v1 database or empty database | `make verify-migrations` |
| `reconstructible.sqlite` | 1 | Empty database | `make verify-migrations` |
| Training Compass Export | Not introduced | Not applicable in Gate 0 | Build exposes no export or import path |

The authoritative v1 migration creates the Gate 0 marker; v2 adds lift configuration and its append-only audit ledger. The reconstructible store remains v1. Later releases must preserve every released migration and add direct-upgrade fixtures before changing this table.
