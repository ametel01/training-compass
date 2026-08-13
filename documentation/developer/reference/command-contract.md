# Command contract

These names are stable handoff interfaces. Supporting scripts may change without changing what each command proves.

| Command | Contract |
| --- | --- |
| `make bootstrap` | Validates stable Xcode 26+, Swift 6, and resolves the pinned package graph. It does not obtain credentials, sign, install, or touch owner data. |
| `make verify` | Runs formatting, dependency boundaries, privacy checks, deterministic fixtures, the package build and tests, the optimized iOS Simulator build, and diff hygiene. |
| `make acceptance` | Verifies that the version-controlled acceptance matrix covers every delivered Local Training Core source and all five required scenario classes, and that the release-candidate budget checklist retains the resolved numeric envelope. |
| `make test-ui` | Runs the critical launch/navigation journey on an available iOS Simulator. |
| `make fixtures` | Regenerates seed 21571 in memory and fails if the checked-in synthetic manifest differs. `UPDATE_FIXTURES=1 make fixtures` updates it for deliberate review. |
| `make verify-migrations` | Creates fresh authoritative and reconstructible databases through their independent migration sequences and verifies Gate 0 metadata. |
| `make device-smoke MILESTONE=gate-0` | Prints the attended physical-device checklist. With explicit result metadata, writes a privacy-safe ignored record. |
| `make verify-release` | Repeats change and UI gates, then refuses success unless passing physical-device evidence and validated release-envelope measurements exist. A passing gate approves this Local Training Core build for owner data; Health integration remains out of scope. |
| `make evidence` | Writes an ignored, inspectable JSON index containing environment metadata, resolved dependencies, privacy artifacts, synthetic seed, waivers, device evidence, and explicit gate verdicts. Automated gates use `pass`, `fail`, or `not_run`; device evidence uses `pass`, `fail`, or `missing`; the release gate is `eligible` or `blocked`. CI records `pass` only after an automated gate succeeds, and only attended device evidence can prove OS file attributes. |

No command stores Apple credentials. Device installation, profile renewal, and launch confirmation remain attended operations.
