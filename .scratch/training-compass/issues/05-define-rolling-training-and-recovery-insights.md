# Define rolling training and recovery insights

Type: grilling
Status: resolved
Blocked by: 01, 13

## Question

Which Health Workouts, heart-rate-zone views, rolling windows, strength trends, and Recovery Evidence should the app turn into useful information, and what transparent rules distinguish observation from Recovery Guidance? Define the user's actionable questions, acceptable explanations, missing-data treatment, and the boundary that prevents medical or automatic training claims.

## Answer

### Information hierarchy and time horizons

- The product first answers what the user should consider before today's planned session, then how current Recovery Evidence compares with the user's record, how strength is progressing, and what training has occurred recently.
- The home view presents a calm daily recovery context whether or not a session is scheduled. When one is planned, the context may refer to it without generating urgency or a warning notification.
- General training uses a Rolling Workout Overview: the trailing seven days including today, compared with the median of the preceding four non-overlapping seven-day periods. Training Cycle summaries remain separate. Strength views use cycle and trailing-90-day horizons, with longer history available on demand.

### Health Workouts and heart-rate zones

- The Rolling Workout Overview includes every available Health Workout and describes frequency, total duration, HealthKit activity types, and available Heart-Rate Zone time. It preserves HealthKit activity types rather than collapsing them into invented categories or a combined training-load score.
- Energy and distance remain workout-level or activity-specific facts; the app does not total unlike distances or use energy as a universal cross-activity measure.
- Heart-Rate Zones are app-owned bands based on a maximum heart rate explicitly configured by the user: 50–59%, 60–69%, 70–79%, 80–89%, and 90–100%. Time below 50% is separate. Without an explicit maximum, the app shows available heart-rate facts but no zones.
- Zone calculations use only heart-rate samples HealthKit associates with the workout. Elapsed time between adjacent samples is assigned to the earlier sample's zone only when the gap is at most 60 seconds; longer gaps and uncovered workout edges remain unavailable.
- Every aggregate discloses workout and duration coverage. Missing samples are never treated as below-zone time or extrapolated across gaps.

### Strength trends

- Per-lift strength views show eligible Plus Set e1RM observations, Training Max history, Plus Set results, and skipped or omitted work. Volume is secondary and is not compared across unlike lifts as a measure of strength.
- e1RM views show the latest and previous observation, cycle best, and trailing-90-day direction. They use neutral higher/lower/unchanged language.
- Observations remain discrete. A thin connecting guide may aid reading, but the app never interpolates across gaps, fills missed sessions, or treats a Training Max change as an e1RM observation. Cycle boundaries and corrected observations remain visible.

### Recovery Evidence and personal baselines

- Primary Recovery Evidence comprises Primary Sleep duration, duration consistency, and timing consistency; resting heart rate; and HRV SDNN. Sleep stages and Naps are descriptive details only.
- Sleep belongs to its wake-up date. The Preferred Sleep Source supplies non-overlapping intervals; the highest-priority usable source wins when sources overlap, while alternatives remain inspectable.
- Intervals separated by at most 90 awake minutes form an episode. The longest episode ending on a wake-up date is Primary Sleep; other episodes are Naps. Primary Sleep duration is total asleep time, duration consistency is variation in that total, and timing consistency is variation in sleep midpoint. These remain separate observations without a score.
- Resting heart rate belongs to its HealthKit sample date. Multiple HRV SDNN values on one date reduce to their median. Source, sample count, algorithm changes when available, latest included sample, and reconciliation time remain visible.
- A Personal Recovery Baseline uses the preceding 28 calendar days' median and middle 50% band and requires at least 14 observed days. Missing days are ignored rather than zero-filled or carried forward. A current comparison requires an actual current observation.
- Baseline language is limited to below, within, or above the user's recent middle half, with boundary values counted as within. The band is descriptive, not a target, normal range, anomaly threshold, population comparison, or statement of sufficiency.

### Observation and guidance boundary

- A Recovery Observation may state the recorded or estimated value, its exact difference from the baseline median, and whether it is higher, lower, longer, shorter, or more or less variable than the recent record. It never translates direction into good or poor recovery, stress, illness, fitness, injury risk, or predicted performance.
- Primary Sleep and all of its submetrics form one Recovery Evidence Family; resting heart rate and HRV SDNN form one family each. At least two families need established baselines and comparable current observations before cross-signal Recovery Guidance appears. This is a presentation guardrail, not a validated classifier.
- When measurements align, the app may say, “Several measurements differ from your recent record,” then enumerate them. When they conflict, it may say, “The measurements do not move together,” then enumerate them. It never votes, weighs signals, chooses a winner, assigns confidence, or produces a readiness score.
- The strongest permitted prompt is: “Before today's planned session, consider how you feel and anything that may have influenced these measurements. You decide whether to keep or change the session.” It links to ordinary user-controlled actions without preselecting or performing one.
- If evidence is missing, stale, corrected, source-incomparable, or lacks enough baselines, the app shows the available measurements and limitation but suppresses the cross-signal prompt: “There is not enough comparable evidence for guidance.” Missing evidence is never neutral or favorable.
- Trend and snapshot are distinct; one daily observation is not a trend. Current derived views recalculate after HealthKit reconciliation rather than preserving stale conclusions. A guidance snapshot is retained only if a later explicit user decision records reliance on it.
- Recovery Guidance can be disabled while Recovery Evidence, collection, history, and training functions remain available.
- Static medical-help information may link authoritative symptom and care guidance, but it is separate from computed output and never triggered by crossing a Personal Recovery Baseline band.

The evidentiary basis and safe-language envelope are recorded in [Establish the recovery interpretation envelope](13-establish-recovery-interpretation-envelope.md) and its linked research note.

### Transparency contract

Every derived observation offers an Insight Explanation containing the question answered, included dates and records, source and coverage, formula or grouping rule, comparison baseline, missing or excluded data, and last reconciliation time. Main views may summarize this material, but no derived conclusion is opaque.
