# Gate 0 acceptance matrix

This matrix covers the Gate 0 shell and the implemented lift-configuration slice from GitHub issue #2.

| Source | Scenario variant | Preconditions | Seed | Expected external result | Evidence layer | Device check | Latest evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Issue #1: private first launch | Normal success | Fresh install; no owner data | 21571 | Four-destination pre-data shell launches after protected stores open | Application, persistence, UI | Yes | `make verify`; `make test-ui`; Gate 0 checklist |
| Issue #1: private first launch | Domain boundary | User opens Cycle or Progress | 21571 | Destination is visibly unavailable and exposes no mutation control | UI | Yes | `TrainingCompassUITests` |
| Issue #1: private first launch | Missing or partial data | No Health authorization or network | 21571 | Shell remains usable; no Health request occurs | Application | Yes | `PreparePreDataShellTests` |
| Issue #1: private first launch | Interruption and retry | Protection verification interrupts after both migrations; preparation is retried and reopened | 21571 | Retry completes from partial state; repeat migration runs keep exactly one Gate 0 marker per store | Persistence | Yes | `ProtectedStoreBootstrapTests`; `make verify-migrations`; Gate 0 checklist |
| Issue #1: private first launch | Privacy or recovery | App becomes inactive or backgrounded | 21571 | Privacy shield replaces app content; both stores retain complete protection and reconstructible data remains excluded from backup | Source/privacy gate and device | Yes | `make verify`; Gate 0 checklist |
| Issue #2: lift configuration | Valid owner edit | Stores are ready; owner reviews a positive Training Max and Loading Increment | 21571 | TMs lists the four exact Progression Lift identities and confirmed values persist with a timestamped audit entry | Domain, application, persistence, UI | No | `LiftConfigurationBoundaryTests`; `LiftConfigurationRepositoryTests`; `TrainingCompassUITests` |
| Issue #2: lift configuration | Invalid and boundary input | Owner enters zero, non-finite, or non-positive reference values, or a non-loadable Set Result | 21571 | Reference values are rejected; Set Result alignment is a warning and does not reject the positive result | Domain, application | No | `LiftConfigurationTests`; `LiftConfigurationBoundaryTests` |
| Issue #2: lift configuration | Interrupted or stale confirmation | A preview is confirmed after another edit or persistence is interrupted | 21571 | The stale/interrupted mutation leaves current configuration and audit history unchanged; retry can continue | Application, persistence | No | `LiftConfigurationBoundaryTests`; `LiftConfigurationRepositoryTests`; migration verifier |
| Issue #2: lift configuration | Corrective edit | Owner marks an existing lift edit as corrective and confirms the preview | 21571 | Before/after snapshots, action, and timestamp are retained without automatic aliasing | Domain, application, persistence, UI | No | `LiftConfigurationBoundaryTests`; `LiftConfigurationRepositoryTests` |

Health authorization, exports, and recovery remain outside this slice. Cycle, Today, and Progress owner-data workflows are still not exposed.
