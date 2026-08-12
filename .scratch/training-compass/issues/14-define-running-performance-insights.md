# Define running performance insights

Type: grilling
Status: resolved
Blocked by: 05, 07

## Question

Which activity-specific running views and transparent comparison rules should Training Compass provide for imported running Health Workouts? Decide the useful distance, duration, pace, heart-rate, zone-coverage, elevation, route, rolling-volume, and comparable-effort trends; define how treadmill, indoor, outdoor, incomplete, and dissimilar runs remain distinguishable; and prevent the view from implying a training-load score, race result, or automatic prescription.

## Answer

### Scope and information hierarchy

- Running Performance includes only Health Workouts their source explicitly classifies as running. Training Compass never infers a run from pace, distance, route, or another activity type and never manually overrides the source-owned environment classification.
- Preserve source-provided Outdoor, Indoor, or Treadmill context; use **Unspecified** when none is available. Unspecified runs compare only with Unspecified runs.
- In Progress > Running, lead with the latest imported run and its key facts, then its comparable-run context, Running Volume, and a reverse-chronological list of all imported runs. Selecting another run makes it the Running Reference Run and updates the first two sections without changing the volume period.
- A source-classified run explicitly linked to a local 5/3/1 Session remains in Running Performance and contributes exactly once to Running Volume. Linking changes unified presentation, not the Health Workout's identity or activity facts.

### Individual-run facts

- Lead with HealthKit total distance, HealthKit workout duration, and Average Running Pace. Calculate pace only when distance and duration are positive, using duration divided by distance; display minutes per kilometre rounded to the nearest second while retaining full precision for calculations.
- Do not substitute wall-clock elapsed time, extrapolate missing distance, or derive kilometre splits in the initial product.
- Show available average heart rate, Heart-Rate Zone distribution and coverage, source-provided elevation ascent or descent, route availability, workout source, and reconciliation context as secondary facts.
- Show an associated route only on that run's detail view. Do not derive elevation from route points, compare route similarity, aggregate routes, build heat maps, or name locations.
- Assign the whole run to the calendar date containing its HealthKit start time, using source timezone metadata when available. Otherwise capture the device timezone at first import and retain that stable assignment. A run crossing midnight is not split.

### Running Volume

- Running Volume comprises three separate facts for the trailing seven local calendar dates including today: run count, total available positive HealthKit workout duration, and total available positive distance.
- Compare each fact with the median of the preceding four non-overlapping seven-day periods. Do not calculate that median until the Health Workouts stream has successfully checked the entire comparison horizon; meanwhile show current facts and explain why no baseline is available.
- Count every source-classified run even when another measurement is absent. Sum available positive duration and distance independently. Keep every contributing run inspectable and never combine the measures into a training-load or volume score.

### Comparable Runs and pace comparisons

- A Comparable Run must have positive distance and duration, the same source-owned environment classification as the selected Running Reference Run, and a full-precision distance inclusively within 5% of the reference distance. Elevation stays visible as context but is not an eligibility rule.
- Default comparable history to the trailing 90 days, with longer history available on demand. Earlier runs are ordered by HealthKit start time, using UUID only to break an exact tie.
- Compare the reference with its immediately preceding Comparable Run as soon as one exists. Add a median comparison only when all four preceding Comparable Runs exist; never silently calculate the four-run baseline from fewer runs.
- For an even set of four values, the median is the arithmetic mean of the middle two sorted full-precision values. Calculate pace differences and medians at full precision, then round for display. Use **unchanged at displayed precision** when displayed values tie.
- Report pace, duration, and distance differences separately using neutral language such as faster, slower, higher, lower, or unchanged. Show discrete observations rather than interpolation.

### Heart rate and zones

- Calculate a run's comparable heart rate as a time-weighted average over the same covered intervals used for Heart-Rate Zones. Assign an interval to its earlier associated sample only when the gap is at most 60 seconds; longer gaps and uncovered edges remain unavailable.
- Always disclose covered duration. A run may show available heart-rate facts with any coverage, but compare heart rate only when each participating run has at least 80% workout-duration coverage. A four-run heart-rate median requires all four preceding runs to meet the same threshold; unavailable heart-rate comparison never suppresses pace comparison.
- For each run, show zone time, percentage of covered time, and coverage of total workout duration. Comparable runs meeting the 80% threshold may show zone distributions side by side, but zones do not produce a winner, effort adjustment, or combined trend.
- Apply the current user-configured maximum heart rate to all visible historical Heart-Rate Zone projections. A configuration change recalculates history for one consistent definition; raw samples remain unchanged and the Insight Explanation identifies the maximum used.

### Missing data, correction, and exclusion

- Every imported run remains visible. Positive distance and duration contribute independently to Running Volume, but both are required for Average Running Pace and Comparable Run eligibility. Missing heart rate, elevation, or route does not otherwise exclude the run; unavailable fields and coverage remain explicit.
- A Running Comparison Exclusion is a reversible Locally Authoritative decision keyed to the HealthKit UUID. It removes the run only from comparable-effort trends, never from history or Running Volume, and never edits the Health Workout.
- Recalculate projections when HealthKit updates the same UUID. Preserve an exclusion through Health Data Rebuild and reconnect it if that exact workout returns. A deleted workout contributes nowhere; a replacement with a new UUID does not inherit the exclusion automatically.

### Interpretation boundary and transparency

- Do not add personal-record labels, goals, goal achievement, race equivalents, predicted results, cross-activity comparisons, training-load scores, inferred effort, fitness claims, or automatic prescriptions.
- Differences remain factual observations. Faster pace or lower heart rate never becomes an improvement, recovery judgment, causal claim, or training recommendation.
- Every derived view offers an Insight Explanation naming the question, selected and included runs, exact dates, environment and distance rule, calculation and rounding rules, source and coverage, exclusions and missing data, comparison baseline, current maximum heart rate where applicable, and last reconciliation time.
