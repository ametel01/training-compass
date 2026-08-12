Label: wayfinder:map

# Plan Training Compass

## Destination

A build-ready product and technical specification, plus a sequenced implementation roadmap, for a private local-first iPhone app that continuously imports Health Workouts and Recovery Evidence; presents transparent training trends and advisory Recovery Guidance; and plans, calculates, and logs configurable 5/3/1 Training Cycles using Training Maxes and e1RM trends. No training change occurs without user confirmation.

## Notes

- Domain: personal fitness training on iPhone, focused on 5/3/1 strength work and all workouts available through Apple Health.
- Planning only: this map resolves decisions and hands off an implementation sequence; it does not build the app.
- Consult the [domain glossary](../../CONTEXT.md) before resolving any ticket, and update it immediately when terminology is sharpened.
- Use Wayfinder throughout. Use Grilling and Domain Modeling for decision tickets, Research for external facts, and Prototype for interaction questions.
- Standing preferences: native iPhone, one person, on-device-only runtime and live storage with no app-operated external infrastructure, transparent evidence, user-confirmed changes, and manual entry only within 5/3/1 Sessions. Owner-controlled Apple backup and explicit exports remain allowed recovery facilities.

## Decisions so far

<!-- Closed-ticket pointers are appended here. Detailed answers live only in their tickets. -->

- [Define cycle construction and schedule behavior](issues/03-define-cycle-construction-and-schedule-behavior.md) — Fixed a three-week user-controlled cycle model, reusable weekly template, explicit lifecycle and scheduling semantics, deload cadence, and auditable history.
- [Define weights, Training Max, and e1RM rules](issues/04-define-weights-training-max-and-e1rm-rules.md) — Fixed kilogram prescriptions, load rounding, actual-set and e1RM eligibility, user-confirmed per-lift progression, snapshots, and audit semantics.
- [Establish the HealthKit capability envelope](issues/01-establish-healthkit-capability-envelope.md) — Use an eventually consistent, deletion-aware HealthKit mirror; keep 5/3/1 detail local and write only an optional strength-workout summary.
- [Establish the personal iPhone deployment envelope](issues/02-establish-personal-iphone-deployment-envelope.md) — Documented the free and paid signing envelopes and their expiry, maintenance, capability, and recovery constraints for an owner-only installation.
- [Establish the recovery interpretation envelope](issues/13-establish-recovery-interpretation-envelope.md) — Keep recovery interpretation descriptive and source-aware; no signal or combination becomes a readiness verdict, diagnosis, risk claim, or training prescription.
- [Define rolling training and recovery insights](issues/05-define-rolling-training-and-recovery-insights.md) — Fixed rolling workout, zone, strength, sleep, baseline, transparency, missing-data, and strictly advisory recovery-guidance contracts.
- [Define unified workout identity and reconciliation](issues/06-define-unified-workout-identity-and-reconciliation.md) — Treat linked local Sessions and Health Workouts as one Training Event while preserving source authority, explicit external linking, idempotent versioned write-back, and deletion-aware reconciliation.
- [Prototype the core iPhone workflows](issues/07-prototype-core-iphone-workflows.md) — Organize daily use around Today, Cycle, Progress, and TMs; keep per-lift e1RM, running performance, unified history, and Recovery Evidence transparent and subordinate to those tasks.
- [Decide local data ownership and lifecycle](issues/08-decide-local-data-ownership-and-lifecycle.md) — Separate locally authoritative, HealthKit-mirrored, and derived data with explicit offline, backup, portable recovery, rebuild, privacy, and full-erasure guarantees.
- [Choose the personal installation path](issues/09-choose-personal-installation-path.md) — Use free Personal Team signing with a day-five reminder and attended in-place weekly refresh; accept expiry risk without paid, Ad Hoc, or TestFlight distribution.
- [Define HealthKit sync and degraded-state behavior](issues/12-define-healthkit-sync-and-degraded-state-behavior.md) — Fixed independent stream state, non-blocking reconciliation, current-evidence gating, degraded UI and recovery controls, late enrichment, and an independent write-back lifecycle.
- [Define running performance insights](issues/14-define-running-performance-insights.md) — Fixed source-classified running views, transparent volume and comparable-run rules, coverage-aware heart-rate context, missing-data behavior, and non-prescriptive interpretation boundaries.
- [Choose the application architecture](issues/10-choose-application-architecture.md) — Chose an on-device-only SwiftUI and Swift 6 architecture with inward-pointing packages, GRDB-separated authority domains, actor-coordinated HealthKit sync, deterministic insights, and explicit recovery boundaries.
- [Define migration, performance, and energy budgets](issues/15-define-migration-performance-and-energy-budgets.md) — Fixed the physical-device verification envelope, measurable responsiveness and resource ceilings, resumable batching, migration and storage guarantees, energy limits, route bounds, and release-gate protocol.
- [Define implementation gates and delivery sequence](issues/11-define-implementation-gates-and-delivery-sequence.md) — Fixed layered behavioral and privacy gates, synthetic HealthKit verification, traceable acceptance evidence, and a Gate 0 plus six usable milestones from local training through release hardening.

## Not yet specified

<!-- No remaining in-scope fog is known. -->

## Out of scope

- Public App Store release.
- Accounts, social features, and multi-user support.
- A companion Apple Watch app; Watch-recorded data available through Apple Health remains in scope.
- Nutrition tracking.
- Medical diagnosis or treatment advice.
- Opaque readiness scores.
- Automatic changes to schedules or Training Maxes.
- Manual entry of workouts other than 5/3/1 Sessions.
- Final visual styling, typography, color, animation, and production polish; this effort fixes information hierarchy and behavior only.
