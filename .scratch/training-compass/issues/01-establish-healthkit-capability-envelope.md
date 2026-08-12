# Establish the HealthKit capability envelope

Type: research
Status: resolved

## Question

According to current official Apple documentation and APIs, what can a native iPhone app read, observe on a rolling basis, and write for this product's Health Workouts and Recovery Evidence? Establish the applicable authorization, entitlement, background-delivery, anchored-query, source/provenance, deletion, workout-route, heart-rate-series, and strength-workout write-back constraints, including what cannot be relied upon.

## Answer

HealthKit supports authorized import of all workout records available on iPhone, the agreed sleep/resting-heart-rate/HRV evidence, and optional workout-associated heart rate, energy, distance, and routes. “Rolling” is an eventually consistent observer-plus-anchored-query reconciliation contract with foreground recovery—not a real-time guarantee. HealthKit can receive a traditional-strength summary for a completed 5/3/1 Session, while all lifting sets, loads, Training Maxes, and e1RM remain local. Full constraints and implementation consequences: [HealthKit capability envelope](../../../docs/research/healthkit-capability-envelope.md).
