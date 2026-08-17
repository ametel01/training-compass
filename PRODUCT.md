# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Training Compass is for people who plan and log strength training, running, and recovery on their iPhone. They need a dependable view of today's work, their current cycle, evidence-backed progress, and optional Apple Health context without handing their data to an account or cloud service.

## Product Purpose

The app keeps local training plans, session results, cycle history, training-max decisions, running analysis, recovery evidence, and exports together. Success means a person can plan, complete, review, correct, and recover training with clear provenance and an offline-capable local record.

## Positioning

Its differentiator is an explicit evidence and privacy boundary: local training remains authoritative, Health data is optional and reconciled visibly, and derived insights explain their source instead of pretending to be scores or medical advice.

## Operating Context

The product is used on iPhone during planning, at the gym while logging sets, and during later review. Apple Health may be connected for read/reconciliation and optional session-summary write-back. Export, import, erasure, recovery, and Personal Team workflows are owner-controlled.

## Capabilities and Constraints

- Preserve the existing five-tab shell: Today, Cycle, Progress, TMs, and Health.
- Preserve all current navigation, session logging, corrections, cycle editing, progress and running views, HealthKit authorization/import/reconciliation, write-back preference, recovery evidence, heart-rate configuration, export/import, and erasure flows.
- Local training data remains usable without Health access.
- Health access, write-back, recovery guidance, and derived comparisons remain optional, explicit, and explainable.
- The app is SwiftUI/UIKit on iOS 26 with Dynamic Type, safe-area, dark-mode, and native navigation expectations.

## Brand Commitments

The product name is Training Compass. The supplied design references are binding: a compass mark, warm paper-like surfaces, navy editorial headings, SF body copy, blue primary actions, green positive/health states, and restrained topographic line detail.

## Evidence on Hand

The existing SwiftUI source and acceptance UI tests are the behavioral source of truth. Visual references are stored in `design/` as the nine supplied PNG boards. No testimonials, customer claims, or commercial proof may be invented.

## Product Principles

- Private by default.
- Evidence before inference.
- Local training remains usable when optional integrations are unavailable.
- Every destructive or consequential action is explicit and recoverable where possible.
- Progress should feel calm, clear, and earned.

## Accessibility & Inclusion

Use native iOS controls and navigation, Dynamic Type-compatible system text styles, semantic colors that adapt to Dark Mode and increased contrast, and minimum 44pt touch targets. Preserve VoiceOver identifiers and existing accessibility labels.
