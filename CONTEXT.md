# Personal Fitness Training

The language for a private iPhone app that combines Apple Health workout history with user-defined 5/3/1 strength sessions.

## Language

**Training Schedule**:
The dated arrangement of 5/3/1 Sessions within a Training Cycle. It begins as three copies of the Schedule Template's weekly layout, plus the same layout in a Deload Week when due, and may then receive cycle-only Calendar Changes or Program Edits.
_Avoid_: 5/3/1 program, app-generated program

**Schedule Template**:
The user's reusable, editable normal-week layout of intended weekdays, Primary Lift roles, and Assistance Lift roles. It is copied into each week of a new Training Cycle and changes only through an explicit template edit or save action.
_Avoid_: live schedule, global program

**Default Schedule**:
The permanent built-in Training Schedule used to initialize the user's Schedule Template: Monday squat/bench, Tuesday overhead press/Romanian deadlift, Thursday bench/squat, and Friday deadlift/overhead press, with the first lift Primary and the second Assistance.
_Avoid_: mandatory schedule, canonical 5/3/1 schedule

**Training Cycle**:
A three-week progression block. Every second Training Cycle has a Deload Week appended, so successive cycles normally alternate between three and four Training Weeks.
_Avoid_: calendar month, fixed four-week cycle

**Week 1 Anchor Date**:
The timezone-free calendar date from which a Training Cycle's seven-day Training Week spans and intended session dates are generated. It identifies the cycle without implying a deload-cadence ordinal.
_Avoid_: activation timestamp, calendar-week number

**Draft Training Cycle**:
The single optional upcoming Training Cycle, copied from the Schedule Template and editable without affecting either the template or the Active Training Cycle. Its Deload Week inclusion is provisional until explicitly reconciled against completed-cycle cadence at activation.
_Avoid_: active cycle, template

**Active Training Cycle**:
The single Training Cycle currently being performed. It remains active until the user explicitly completes or abandons it.
_Avoid_: current calendar month, latest cycle

**Abandoned Training Cycle**:
An Active Training Cycle the user explicitly ended before normal completion. It remains in history and does not advance the Deload Week cadence.
_Avoid_: deleted cycle, completed cycle

**Completed Training Cycle**:
A Training Cycle the user explicitly completed after finishing all of its Training Weeks. It advances the Deload Week cadence even when it contains Skipped Sessions.
_Avoid_: abandoned cycle, automatically closed cycle

**Training Week**:
One of the three ordered, seven-day progression stages within a Training Cycle, anchored from the cycle's user-selected Week 1 date. Its sequence is independent of calendar-week boundaries.
_Avoid_: calendar week

**Deload Week**:
The lower-intensity week appended after every second three-week block, using sets of five at 40%, 50%, and 60% of Training Max.
_Avoid_: rest week, fourth week

**5/3/1 Session**:
A manually entered strength-training session containing one Primary Lift and its paired Assistance Lift, with weights calculated from user-configured Training Maxes.
_Avoid_: Health workout, automatic workout

**Scheduled Session**:
A planned 5/3/1 Session that has not been completed or skipped. Passing its intended date does not change its status.
_Avoid_: missed session, Health workout

**Skipped Session**:
A planned 5/3/1 Session the user explicitly chose not to perform. Along with Completed Sessions, it allows its Training Week to be finished.
_Avoid_: missed session, deleted session

**Unperformed Session**:
A Session that remained Scheduled when its Training Cycle was abandoned. It is preserved in that cycle's history and is distinct from an intentional Skipped Session.
_Avoid_: skipped session, deleted session

**Calendar Change**:
A change to a Scheduled Session's intended date that preserves its Training Week and training prescription, even when moved outside that week's intended date range.
_Avoid_: program change, automatic progression

**Program Edit**:
An explicit cycle-only change to planned sessions or lift roles within the fixed Training Week sequence. It never rewrites completed work or implicitly updates the Schedule Template.
_Avoid_: calendar change, template update

**Primary Lift**:
The main prescription role in a 5/3/1 Session, performed with the Training Week's three prescribed percentage sets and final Plus Set. It may use the same movement as the session's Assistance Lift.
_Avoid_: assistance movement, accessory exercise

**Assistance Lift**:
The secondary prescription role paired with a Primary Lift in a 5/3/1 Session, normally prescribed as five sets of ten at 65% of its own Training Max. It may use the same movement as the session's Primary Lift.
_Avoid_: Health workout, unstructured light weights

**Progression Lift**:
One of Squat, Deadlift, Bench Press, or Overhead Press: the four exact lift identities eligible for a fixed Training Max Increment. Variants and custom lifts are distinct and progress manually.
_Avoid_: Primary Lift role, lift family, automatic alias

**Plus Set**:
The final Primary Lift set of a normal Training Week, with a minimum target and additional repetitions recorded as performance permits. Assistance and Deload sets are never Plus Sets.
_Avoid_: fixed-repetition set, max test

**Health Workout**:
Any training session supplied through Apple Health, regardless of workout type or the device or app that originally recorded it.
_Avoid_: Cardio session, Zone 1 session

**HealthKit Mirror**:
The app's local, eventually reconciled representation of authorized Apple Health objects, keyed by each object's HealthKit UUID and retaining available provenance. Apple Health remains the source of truth for imported objects; the mirror may be incomplete or stale and must process additions, replacements, and deletions. It has no automatic age limit, remains available offline, and may be explicitly discarded and rebuilt from the HealthKit data then available without affecting Locally Authoritative Data. It is excluded from device backup and rebuilt after restoration and renewed Health authorization. Reduced or revoked Health access does not silently purge already imported records; because an absence of readable data does not prove denial, removal remains an explicit Health Data Rebuild or Full App Erasure action.
_Avoid_: real-time feed, canonical 5/3/1 database, complete Health history

**Health Data Stream**:
One independently reconciled category of data read from Apple Health, such as Health Workouts, sleep, resting heart rate, or HRV SDNN. Each stream retains its own availability and last-reconciliation context so success in one never implies that every other stream is current or readable.
_Avoid_: global Health sync state, proof of read permission

**Foreground Reconciliation**:
The automatic, non-blocking attempt to update every requested Health Data Stream when Training Compass launches or returns to the foreground. Existing mirrored data remains usable while it runs, and failure never blocks local 5/3/1 planning or logging.
_Avoid_: blocking sync screen, real-time guarantee, background delivery

**Health Data Refresh**:
A user-requested, non-destructive incremental reconciliation of every requested Health Data Stream. It preserves the HealthKit Mirror and Locally Authoritative Data, coalesces with reconciliation already in progress, and is distinct from retrying HealthKit Write-backs or performing a Health Data Rebuild.
_Avoid_: Health Data Rebuild, clearing cached data, write-back retry

**Health Data Status**:
The inspectable, per-stream account of Health access scope, reconciliation progress, available mirrored content, last successful check, and any current failure. It may be summarized across streams for navigation, but never collapses partial success into a single claim that all Health data is synchronized.
_Avoid_: global sync flag, proof of denied read permission, latest sample time

**Workout Enrichment**:
Optional HealthKit detail associated with an already imported Health Workout, such as heart rate, distance, energy, or route data. It may arrive or change later and updates that workout in place without creating another Training Event. A successful query with no associated detail makes that detail Not Available from Health rather than indefinitely loading; later reconciliation may still supply it.
_Avoid_: required workout data, separate workout, timestamp-inferred association

**Locally Authoritative Data**:
The user-created or user-confirmed facts for which Training Compass is the source of truth: Schedule Templates and Training Cycles; 5/3/1 Sessions, prescriptions, results, and notes; lift configuration and Training Max history; preferences; explicit Training Event links; corrections; and their audit history. It remains available offline until the user explicitly deletes or resets it and may participate in the owner's encrypted Apple device or iCloud Backup without becoming app-operated cloud storage or cross-device synchronization.
_Avoid_: HealthKit Mirror, cloud-synced account data, disposable cache

**Derived Projection**:
A reproducible view calculated from Locally Authoritative Data, the HealthKit Mirror, or both, including e1RM trends, rolling insights, Personal Recovery Baselines, and Recovery Guidance. It is never an authoritative record, is excluded from device backup, and may be discarded and rebuilt; its explanation identifies the source records and reconciliation state on which it depends.
_Avoid_: source record, irreplaceable history, opaque stored conclusion

**Training Compass Export**:
A versioned, self-contained archive containing all Locally Authoritative Data as both a human-readable summary and full-fidelity machine-readable data. The user may explicitly include a separate, source-labelled snapshot of the HealthKit Mirror; Derived Projections are not canonical export data because they can be regenerated. The initial format is portable and unencrypted, so export requires a sensitive-data warning and the app removes its temporary copy after handing it to the system share flow. Import restores Locally Authoritative Data with stable identities but never installs an exported HealthKit snapshot as the live mirror. Import into a non-empty app replaces rather than merges data after explicit confirmation and a strong prompt to export the current data. Validation and supported-version migration occur before an all-or-nothing replacement; corrupt, incomplete, or unsupported future archives leave current data unchanged.
_Avoid_: HealthKit backup, opaque database copy, cloud synchronization

**HealthKit Write-back**:
The optional traditional-strength workout summary saved to Apple Health after a completed 5/3/1 Session, identified by a stable local-session sync identifier and version. A persistent user preference opts into write-back, and each completion may opt out. Detailed sets, loads, Training Maxes, and e1RM remain local; unavailable write permission or a failed write never blocks local completion. Deletion in Apple Health is respected until the user explicitly restores the summary. Full App Erasure leaves write-backs in Apple Health unless the user separately requests their deletion; another source's workouts are never deleted.
_Avoid_: 5/3/1 backup, full session record, required completion step

**HealthKit Write-back State**:
The independent delivery state of one completed 5/3/1 Session's optional HealthKit Write-back: Not Shared, Queued, Saving, Saved to Health, Retry Scheduled, Health Access Needed, Couldn't Save, Deleted from Health, or Update Pending. It never changes whether the local Session is Completed; retry, permission repair, restoration after external deletion, and replacement of a stale summary are explicit state transitions.
_Avoid_: Session completion state, Health read freshness, automatic restoration after deletion

**Health Data Rebuild**:
An explicit repair and privacy action that discards the HealthKit Mirror, Derived Projections, and sync cursors before reconciling again from the HealthKit data currently available. It preserves all Locally Authoritative Data, including explicit Training Event links and their audit history; exact HealthKit UUIDs reconnect when they return. Rebuilding is resumable and retains completed batches if interrupted; it does not reinstate the discarded mirror as though it were current.
_Avoid_: Full App Erasure, deleting Apple Health data, resetting 5/3/1 history

**Full App Erasure**:
An explicit destructive action that removes all Locally Authoritative Data, the HealthKit Mirror, Derived Projections, preferences, and sync state from the current installation, returning Training Compass to first launch. It may separately attempt to delete Training Compass HealthKit Write-backs, but failure requires a retry-or-proceed choice and never permits deletion of another source's workouts. It does not claim to erase prior device or iCloud backups, shared exports, or HealthKit copies, which the owner manages separately.
_Avoid_: Health Data Rebuild, uninstalling Health data, individual cycle deletion

**Training Event**:
One user-visible occurrence of training. It may contain only a Health Workout, only a 5/3/1 Session, or a one-to-one link between both when they describe the same real-world workout. A linked pair appears once in timelines and aggregate counts while preserving both records, their provenance, and each source's authority over its own facts. Training Compass links its own HealthKit Write-back by sync identity; an externally recorded Health Workout may be linked only by explicit user choice, never by time overlap or similarity. Unlinking restores two Training Events without deleting the external workout.
_Avoid_: merged workout record, inferred duplicate, source-erasing workout

**Recovery Evidence**:
Available Apple Health measurements shown with their underlying trends. The initial evidence set is sleep duration, duration consistency, timing consistency, resting heart rate, and heart-rate variability SDNN; sleep stages may appear only as descriptive detail because they can be incomplete or source-dependent. Duration consistency describes variation in total asleep time, while timing consistency describes variation in sleep midpoint; neither becomes a score.
_Avoid_: readiness score, medical diagnosis

**Preferred Sleep Source**:
The user-ordered source selected to represent a sleep episode when multiple devices or apps provide overlapping asleep intervals. The highest-priority source with usable intervals is used without adding overlaps from alternatives, and the chosen source remains visible.
_Avoid_: combined overlapping sleep, hidden source selection

**Primary Sleep**:
The longest sleep episode ending on a wake-up date, assembled from asleep intervals supplied by the Preferred Sleep Source when consecutive intervals are separated by no more than 90 minutes. Personal Recovery Baselines use Primary Sleep duration and midpoint; other episodes are Naps.
_Avoid_: medically normal sleep, required sleep, sum of overlapping sources

**Nap**:
A sleep episode on a wake-up date other than its Primary Sleep. Nap duration is descriptive Recovery Evidence and does not enter the Primary Sleep duration or timing baseline.
_Avoid_: Primary Sleep replacement, missing overnight sleep

**Personal Recovery Baseline**:
The median and middle 50% of the user's valid daily observations during the preceding 28 calendar days, used to contextualize current Recovery Evidence. It requires at least 14 observed days; missing days are neither zero-filled nor carried forward. A current observation is described as below, within, or above the recent middle half, with boundary values counted as within. The comparison provides context without applying population thresholds or claiming a medically normal range.
_Avoid_: population norm, clinical reference range, readiness score

**Recovery Observation**:
A neutral description of one recorded Recovery Evidence value, its source and coverage, and its position relative to an established Personal Recovery Baseline. It states higher, lower, longer, shorter, or more or less variable without interpreting the direction as favorable, unfavorable, causal, or predictive.
_Avoid_: warning, anomaly, recovery verdict, performance prediction

**Current Recovery Evidence**:
Recovery Evidence whose Health Data Stream has reconciled successfully during the current local calendar day. Older observations may remain visible with their last-check context, but they cannot participate in current Recovery Guidance; guidance also remains withheld while the required streams are updating or after a newer reconciliation attempt fails.
_Avoid_: latest cached evidence, real-time measurement, guaranteed complete day

**Recovery Evidence Family**:
One sufficiently independent source family used only to gate whether cross-signal Recovery Guidance may be displayed. Primary Sleep and all of its duration and consistency observations form one family; resting heart rate and HRV SDNN each form another. Family counts are not votes, confidence, or severity.
_Avoid_: recovery vote, confidence score, independent sleep metrics

**Insight Explanation**:
The inspectable basis for a derived training or recovery observation: its question, included dates and records, source and coverage, calculation or grouping rule, comparison baseline, missing or excluded data, and last reconciliation time.
_Avoid_: opaque score, unexplained conclusion

**Recovery Guidance**:
An explained, advisory self-check prompt available only when at least two Recovery Evidence Families have established Personal Recovery Baselines and every baseline-established family has a current, successfully reconciled, comparable observation. A family that has never established a baseline does not block guidance. The prompt neutrally enumerates aligned and conflicting measurements, invites the user to consider how they feel, and leaves any session decision to them; it never interprets recovery or prescribes a training change. If an otherwise eligible family is missing, stale, or source-incomparable, the app shows available observations but suppresses the prompt.
_Avoid_: automatic adaptation, readiness score, medical recommendation

**Heart-Rate Zone**:
One of five app-defined intensity bands calculated only from heart-rate samples HealthKit associates with a Health Workout and from the current maximum heart rate explicitly configured by the user: 50–59%, 60–69%, 70–79%, 80–89%, and 90–100%. Time below 50% is separate; changing the configured maximum recalculates historical zones, while missing inputs and sample gaps remain unavailable and coverage stays visible.
_Avoid_: source-provided zone, silently estimated zone, training-load score

**Rolling Workout Overview**:
A summary of all available Health Workouts during the trailing seven days, compared with the preceding four non-overlapping seven-day periods. It describes frequency, duration, HealthKit activity types, and available Heart-Rate Zone time without combining them into a training-load score. Energy and distance remain workout-level or activity-specific facts rather than cross-activity totals.
_Avoid_: calendar-week report, Training Week summary, readiness score

**Running Performance**:
An activity-specific view limited to Health Workouts that their source explicitly classifies as running, including those linked to a 5/3/1 Session; it prioritizes individual-run review, then like-for-like progress, then recent Running Volume. It preserves source-provided indoor, outdoor, or treadmill context, uses Unspecified when none is available, and never infers or manually overrides a run or its environment.
_Avoid_: cross-activity pace, training-load score, inferred race result

**Running Comparison Exclusion**:
A reversible Locally Authoritative decision, keyed to a HealthKit UUID, that removes one imported run from comparable-effort trends without editing or hiding it. It survives Health Data Rebuild and reconnects only to the exact UUID; the workout remains in Running Volume unless HealthKit deletes it.
_Avoid_: deleting a run, correcting HealthKit, excluding from volume

**Running Volume**:
The count, total available positive HealthKit workout duration, and total available positive distance of source-classified runs during the trailing seven days including today, each compared with the median of the preceding four non-overlapping seven-day periods. Every run contributes to count even when another fact is missing; the three measures remain separate and every contributing run is inspectable.
_Avoid_: training load, calendar-week mileage, combined volume score

**Comparable Run**:
A source-classified run with positive distance and duration whose source-owned environment classification matches a Running Reference Run and whose full-precision distance is inclusively within 5% of that reference distance. Unspecified environments match only Unspecified, while elevation remains visible context rather than an eligibility rule.
_Avoid_: equivalent effort, same route, inferred race

**Running Reference Run**:
The selected run around which Comparable Runs are found and performance differences are presented; the latest imported run is selected by default and choosing another run changes the reference without changing Running Volume. Earlier runs are ordered by HealthKit start time, with UUID used only to break an exact tie.
_Avoid_: target run, benchmark performance, race result

**Running Performance Comparison**:
A neutral comparison of one selected run with its immediately preceding Comparable Run and, only when all exist, the median of its preceding four Comparable Runs; the default history is 90 days with longer history on demand. It reports separate pace, duration, distance, and sufficiently covered heart-rate differences without records, goals, or claims about fitness, effort, or race performance.
_Avoid_: performance score, fitness gain, race prediction

**Average Running Pace**:
HealthKit workout duration divided by positive HealthKit total distance for one source-classified run, displayed in minutes per kilometre to the nearest second while retaining full calculation precision. It is unavailable when either input is absent or non-positive and never substitutes wall-clock time or extrapolated distance.
_Avoid_: split pace, moving pace, inferred pace

**Comparable Run Heart Rate**:
A time-weighted average of the Heart-Rate Zone-covered intervals of a run, eligible for comparison only when those intervals cover at least 80% of its HealthKit workout duration. A four-run heart-rate median requires all four preceding Comparable Runs to satisfy the same threshold.
_Avoid_: whole-workout heart rate, extrapolated average, effort score

**Run Date**:
The calendar date containing a run's HealthKit start time in source timezone metadata, or in the device timezone captured at first import when source timezone is unavailable. The assignment remains stable and owns the whole run even when it crosses midnight.
_Avoid_: import date, finish date, split date

**Equipment Unit**:
Kilograms, the sole weight unit used for Training Maxes, prescriptions, and recorded results in this private app.
_Avoid_: display-only unit, mixed-unit prescription, pounds

**Loading Increment**:
The configurable per-lift weight step used to turn a calculated percentage of Training Max into a physically loadable prescribed weight. It defaults to 2.5 kg; the nearest increment is used, with an exact tie rounded down.
_Avoid_: Training Max increase, plate inventory

**Loading Increment Snapshot**:
The per-lift Loading Increment values captured when a Training Cycle is activated and used by that cycle's Set Prescriptions. Intentional changes affect Draft and future cycles rather than silently rewriting the Active Training Cycle.
_Avoid_: current global Loading Increment, plate inventory

**Training Max (TM)**:
The configurable reference weight owned by a lift and shared wherever that lift appears as Primary or Assistance. It need not itself be loadable; prescribed weights calculated from it are rounded separately.
_Avoid_: one-rep max, prescribed weight

**Training Max Snapshot**:
The per-lift Training Max values captured when a Training Cycle is activated and used by that cycle's Set Prescriptions. Intentional Training Max changes affect Draft and future cycles rather than silently rewriting the Active Training Cycle.
_Avoid_: current global Training Max, live prescription value

**Training Max Increment**:
The fixed increase proposed between Completed Training Cycles: 5 kg for Squat and Deadlift, and 2.5 kg for Bench Press and Overhead Press. Other lifts have no cycle-based increment.
_Avoid_: Loading Increment, automatic Training Max change

**Training Max Proposal**:
An accept-or-reject proposal created for each eligible Primary Lift after its Training Cycle is Completed, including after a due Deload Week. It shows supporting work and e1RM evidence but never changes a Training Max without confirmation.
_Avoid_: automatic progression, performance-derived increment

**Training Max History**:
The chronological per-lift record of initial and manual values, proposals and their evidence, accept-or-reject decisions, corrections, effective cycles, timestamps, and before/after values.
_Avoid_: current Training Max, e1RM trend

**Set Prescription**:
The immutable planned role, percentage, repetition target, and calculated weight captured for one set in a 5/3/1 Session.
_Avoid_: Set Result, live recalculation after logging

**Set Result**:
The actual weight and repetitions recorded for a performed prescribed set. It may differ from its Set Prescription; zero repetitions denotes a failed attempt.
_Avoid_: Set Prescription, assumed completion

**Omitted Set**:
A Set Prescription the user explicitly chose not to perform. Every prescribed set must have either a Set Result or this disposition before its 5/3/1 Session can be completed.
_Avoid_: failed attempt, unrecorded set

**Additional Set**:
An ordered set recorded within a 5/3/1 Session that was not part of its Set Prescriptions. It records actual lift, weight, repetitions, and an optional note without altering the prescription.
_Avoid_: Program Edit, prescribed set

**Estimated One-Rep Max (e1RM)**:
An estimate of maximal strength calculated only from a normal-week Primary Lift's Plus Set Result using the Epley formula: weight × (1 + repetitions ÷ 30). A single repetition equals the lifted weight; Assistance, Deload, Omitted, failed, and Additional Sets produce no estimate.
_Avoid_: Training Max, actual one-rep max
