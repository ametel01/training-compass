# Gate 0 acceptance matrix

This matrix is limited to GitHub issue #1. Later scenario families remain governed by the resolved implementation roadmap and are not exposed by this build.

| Source | Scenario variant | Preconditions | Seed | Expected external result | Evidence layer | Device check | Latest evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Issue #1: private first launch | Normal success | Fresh install; no owner data | 21571 | Four-destination pre-data shell launches after protected stores open | Application, persistence, UI | Yes | `make verify`; `make test-ui`; Gate 0 checklist |
| Issue #1: private first launch | Domain boundary | User opens Cycle, Progress, or TMs | 21571 | Destination is visibly unavailable and exposes no mutation control | UI | Yes | `TrainingCompassUITests` |
| Issue #1: private first launch | Missing or partial data | No Health authorization or network | 21571 | Shell remains usable; no Health request occurs | Application | Yes | `PreparePreDataShellTests` |
| Issue #1: private first launch | Interruption and retry | Protection verification interrupts after both migrations; preparation is retried and reopened | 21571 | Retry completes from partial state; repeat migration runs keep exactly one Gate 0 marker per store | Persistence | Yes | `ProtectedStoreBootstrapTests`; `make verify-migrations`; Gate 0 checklist |
| Issue #1: private first launch | Privacy or recovery | App becomes inactive or backgrounded | 21571 | Privacy shield replaces app content; both stores retain complete protection and reconstructible data remains excluded from backup | Source/privacy gate and device | Yes | `make verify`; Gate 0 checklist |

Owner-data workflows, Health authorization, exports, and recovery are explicitly not applicable to Gate 0 because the issue requires those capabilities to remain inaccessible.
