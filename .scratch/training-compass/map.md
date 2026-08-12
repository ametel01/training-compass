Label: wayfinder:map

# Plan Training Compass

## Destination

A build-ready product and technical specification, plus a sequenced implementation roadmap, for a private local-first iPhone app that continuously imports Health Workouts and Recovery Evidence; presents transparent training trends and advisory Recovery Guidance; and plans, calculates, and logs configurable 5/3/1 Training Cycles using Training Maxes and e1RM trends. No training change occurs without user confirmation.

## Notes

- Domain: personal fitness training on iPhone, focused on 5/3/1 strength work and all workouts available through Apple Health.
- Planning only: this map resolves decisions and hands off an implementation sequence; it does not build the app.
- Consult the [domain glossary](../../CONTEXT.md) before resolving any ticket, and update it immediately when terminology is sharpened.
- Use Wayfinder throughout. Use Grilling and Domain Modeling for decision tickets, Research for external facts, and Prototype for interaction questions.
- Standing preferences: native iPhone, one person, local-first, transparent evidence, user-confirmed changes, and manual entry only within 5/3/1 Sessions.

## Decisions so far

<!-- Closed-ticket pointers are appended here. Detailed answers live only in their tickets. -->

## Not yet specified

- Permission denial, partial-data, background-delivery, stale-data, and sync-recovery behavior after the HealthKit capability envelope is known.
- Additional data-reconciliation cases surfaced by HealthKit provenance and deletion semantics.
- Any signal-calibration or interpretation research required after the rolling-insights contract identifies its exact claims.
- Screen hierarchy, visualization choices, and interaction edge cases exposed by the first workflow prototype.
- Migration, performance, and battery decisions that only become sharp after the persistence and sync architecture is chosen.

## Out of scope

- Public App Store release.
- Accounts, social features, and multi-user support.
- A companion Apple Watch app; Watch-recorded data available through Apple Health remains in scope.
- Nutrition tracking.
- Medical diagnosis or treatment advice.
- Opaque readiness scores.
- Automatic changes to schedules or Training Maxes.
- Manual entry of workouts other than 5/3/1 Sessions.
