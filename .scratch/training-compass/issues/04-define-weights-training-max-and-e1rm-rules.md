# Define weights, Training Max, and e1RM rules

Type: grilling
Status: resolved
Blocked by: 03

## Question

What exact rules calculate prescribed weights, round them to loadable values, record actual work, estimate one-rep maxes, recommend per-lift Training Max changes, confirm or reject those changes, and preserve an auditable history? Resolve units, equipment increments, Plus Set eligibility, formula choice, exceptional sets, and the timing of TM changes around Deload Weeks.

## Answer

### Prescriptions and loadable weights

- Kilograms are the app's sole Equipment Unit.
- The numerical 5/3/1 scheme is fixed in this version. Users may configure schedules, lift roles, Training Maxes, and Loading Increments, but Program Edits do not create arbitrary percentage programs.
- Normal Primary prescriptions are:
  - Week 1: 65% × 5, 75% × 5, 85% × 5+.
  - Week 2: 70% × 3, 80% × 3, 90% × 3+.
  - Week 3: 75% × 5, 85% × 3, 95% × 1+.
- Deload Primary work is 40% × 5, 50% × 5, and 60% × 5, with no Plus Set.
- Assistance work is five sets of ten at 65% in normal weeks and five sets of ten at 50% in a Deload Week. Assistance work never has a Plus Set.
- Each prescribed weight is calculated independently from the lift's exact Training Max, then rounded to the nearest Loading Increment. Exact ties round down. The per-lift Loading Increment defaults to 2.5 kg and does not model individual plate inventory.
- A Training Max may be any positive kilogram value because it is a calculation reference rather than a necessarily loadable weight. Set Results accept the exact positive weight entered and warn, without blocking, when it conflicts with the configured Loading Increment. Repetitions are non-negative whole numbers.

### Lift identity and actual work

- A lift owns one Training Max shared wherever it appears as Primary or Assistance. Squat, Deadlift, Bench Press, and Overhead Press are four exact Progression Lift identities. Variants and custom lifts are distinct, retain separate histories, and are never automatically aliased.
- Each performed prescribed set preserves its immutable Set Prescription and records a separate Set Result containing actual weight and repetitions. Actuals may differ from their targets, and zero repetitions records a failed attempt.
- A prescribed set may instead be explicitly marked as an Omitted Set with an optional reason. Every prescribed set must have either a Set Result or an Omitted disposition before its session can be Completed.
- Additional Sets may be recorded in order with lift, weight, repetitions, and an optional note. They never alter the prescription.
- Corrections preserve mandatory timestamps and before/after values; an explanatory note is optional.

### e1RM observations

- e1RM uses the Epley formula: `weight × (1 + repetitions ÷ 30)`, calculated from actual weight and repetitions. One repetition is special-cased so the e1RM equals the lifted weight; zero repetitions produces no estimate.
- Only the normal-week Primary Lift's prescribed Plus Set can create an e1RM observation. The observation remains eligible when the target was missed or the actual weight differed, provided at least one repetition was completed.
- Assistance, Deload, Omitted, failed, and Additional Sets never create e1RM observations.
- Calculations retain full precision and display one decimal place. They are estimates, not loadable prescriptions, so they are not rounded to a Loading Increment.

### Training Max progression

- After a Training Cycle is explicitly Completed, the app creates a fixed Training Max Proposal for each Progression Lift that appeared as a Primary Lift during the cycle: 5 kg for Squat and Deadlift, and 2.5 kg for Bench Press and Overhead Press. Variants and custom lifts change manually.
- A due Deload Week must be finished before that cycle's proposals appear. An Abandoned Training Cycle creates no proposals.
- Each proposal shows the current and proposed Training Max, its source cycle, eligible e1RM trend, and skipped or omitted work. Missing or weak evidence does not alter the fixed increment; the user makes the decision.
- The user must accept or reject every proposal independently before activating the next Training Cycle. Acceptance updates that lift's Training Max and previews recalculated Set Prescriptions in any Draft Training Cycle. Rejection retains the current value. No Training Max ever changes automatically.

### Effective values and audit history

- Every lift used by a cycle requires a Training Max before activation. Activation captures per-lift Training Max and Loading Increment Snapshots for the cycle.
- Intentional manual changes and accepted proposals affect Draft and future cycles, never silently rewriting the Active Training Cycle.
- A genuine correction to an erroneous Training Max or Loading Increment may recalculate only Scheduled Sessions in the Active Training Cycle after an explicit before/after preview. Completed, Skipped, Omitted, and performed work remains unchanged. Every replacement Set Prescription is audited.
- The chronological per-lift Training Max History records initial and manual values; every proposal and its evidence; accept-or-reject decisions; source and effective cycles; timestamps; optional reasons; and all before/after values.
- Correcting a Set Result recalculates the current e1RM trend and adds a visible correction marker. Superseded results and estimates remain available through audit history rather than appearing as current evidence.
