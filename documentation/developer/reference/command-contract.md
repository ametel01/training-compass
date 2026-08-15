# Command contract

These names are stable handoff interfaces. Supporting scripts may change without changing what each command proves.

| Command | Contract |
| --- | --- |
| `make bootstrap` | Validates stable Xcode 26+, Swift 6, and resolves the pinned package graph. It does not obtain credentials, sign, install, or touch owner data. |
| `make verify` | Runs formatting, dependency boundaries, privacy checks, deterministic fixtures, the package build and tests, the optimized iOS Simulator build, and diff hygiene. |
| `make acceptance` | Verifies that the version-controlled acceptance matrix covers every delivered issue source and all five required scenario classes, including unified identity, enrichment, and route contracts, and that the release-candidate budget checklist retains the resolved numeric envelope. |
| `make test-ui` | Runs the critical launch/navigation journey on an available iOS Simulator. |
| `make fixtures` | Regenerates seed 21571 in memory and fails if the checked-in synthetic manifest differs. `UPDATE_FIXTURES=1 make fixtures` updates it for deliberate review. |
| `make verify-migrations` | Creates fresh authoritative and reconstructible databases through their independent migration sequences and verifies Gate 0 metadata. |
| `make device-smoke MILESTONE=gate-0|health-foundation|unified-events|training-insights|recovery-evidence` | Prints the selected attended physical-device checklist. With explicit result metadata and milestone-specific booleans, writes a privacy-safe ignored record. |
| `make verify-release MILESTONE=gate-0|health-foundation|unified-events|training-insights|recovery-evidence` | Repeats change and UI gates, then refuses success unless the selected milestone's physical-device evidence and validated release-envelope measurements pass. Unified route evidence may explicitly be unavailable when the Acceptance Device has no route-bearing workout. Training and Running Insights evidence additionally proves every displayed derived value reaches an explanation and that insight queries meet the 750-millisecond budget; Recovery Evidence additionally proves available and withheld guidance, explanation reachability, current-day correctness, neutral language, resource limits, privacy, and prior-data continuity. |
| `make evidence` | Writes an ignored, inspectable JSON index containing environment metadata, resolved dependencies, privacy artifacts, synthetic seed, waivers, all milestone device evidence, and explicit gate verdicts. Automated gates use `pass`, `fail`, or `not_run`; device evidence uses `pass`, `fail`, or `missing`; each milestone gate is `eligible` or `blocked`. CI records `pass` only after an automated gate succeeds, and only attended device evidence can prove OS file attributes. |

No command stores Apple credentials. Device installation, profile renewal, and launch confirmation remain attended operations.
