# Migration compatibility

The two databases and future export format evolve independently.

| Store | Current version | Direct upgrade inputs | Gate |
| --- | --- | --- | --- |
| `authoritative.sqlite` | 1 | Empty database | `make verify-migrations` |
| `reconstructible.sqlite` | 1 | Empty database | `make verify-migrations` |
| Training Compass Export | Not introduced | Not applicable in Gate 0 | Build exposes no export or import path |

Both v1 migrations create only a Gate 0 marker with `owner_data_accepted = false`. Later releases must preserve these migrations and add direct-upgrade fixtures before changing this table.
