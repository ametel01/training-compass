# Prototype the core iPhone workflows

Type: prototype
Status: resolved
Blocked by: 03, 04, 05, 06

## Question

What interaction model makes the app fast and understandable in daily use? Build a cheap, reviewable prototype covering cycle setup, today's planned session, set logging, TM confirmation, unified workout history, rolling trends, and explained Recovery Guidance; use the user's reaction to choose the main navigation and information hierarchy.

## Answer

Use four permanent, task-named destinations. This is an information hierarchy decision, not a visual-design commitment.

### Today

- Lead with the full prescribed 5/3/1 Session when one is scheduled: Primary and Assistance Lifts, Training Max snapshots, planned weights and repetitions, recorded results, omissions, and completion state are readable in one place.
- Start or continue set logging directly from this view; keep planned and actual work side by side.
- Show same-day imported Health Workouts, including running distance, duration, pace, available heart-rate context, and source, without collapsing them into the 5/3/1 Session unless the user explicitly links them.
- Keep Recovery Evidence and its explanation subordinate to today's work. It provides context without becoming the main navigation, a readiness verdict, or a training change.

### Cycle

- Show the entire Active or Draft Training Cycle ahead as dated Training Weeks, including a due Deload Week, not only the current week or next session.
- Make the selected week's sessions and statuses scannable, with cycle setup, Calendar Changes, and Program Edits available from this destination.
- Preserve explicit anchor dates, lifecycle state, and the boundary between cycle-only edits and the reusable Schedule Template.

### Progress

- Separate Strength, Running, and unified workout-history views without combining them into a cross-activity score.
- Strength defaults to one selected lift and plots its eligible e1RM series over time, with the current Training Max as a distinct reference and every point traceable to its Plus Set Result.
- Running is a first-class activity-specific view for imported running Health Workouts. It exposes session performance and running-only trends; exact comparison and inclusion rules are delegated to [Define running performance insights](14-define-running-performance-insights.md).
- Unified history keeps linked local Sessions and Health Workouts as one Training Event while preserving their sources.

### TMs

- Provide one dedicated editor listing all lift Training Maxes with units, current values, and pending draft values.
- Keep fixed cycle-completion proposals visible here with their supporting sets and e1RM evidence, but require an explicit accept, reject, or manual value.
- One explicit save applies changes to the Draft and future cycles; the screen states that the Active Training Cycle retains its Training Max Snapshots.

The prototype deliberately does not choose final typography, colors, card styling, or animation. Those can be overhauled without changing the four-destination structure or the information contracts above.

## Comments

- Review asset: [Core workflows prototype](../prototypes/core-workflows/README.md) — revised after user feedback into one functional wireframe organized around Today, Cycle, Progress, and TMs, with first-class running/cardio performance. Visual design is intentionally deferred.
- User review priorities: make Training Max entry, today's prescribed work, per-lift e1RM progression, and the complete upcoming cycle immediately clear; retain activity-specific running/cardio session and performance tracking; defer visual design choices.
