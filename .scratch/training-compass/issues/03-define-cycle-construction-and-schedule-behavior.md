# Define cycle construction and schedule behavior

Type: grilling
Status: resolved

## Question

What exact user-controlled model governs creation, editing, scheduling, completion, skipping, and history of Training Cycles, Training Weeks, Primary Lifts, Assistance Lifts, and Deload Weeks? Resolve how the agreed default schedule becomes a reusable but editable template and how calendar changes differ from program changes.

## Answer

### Cycle structure and cadence

- A Training Cycle always contains three ordered normal Training Weeks. Every second completed Training Cycle also has a Deload Week appended, producing an alternating three-week/four-week cadence when cycles are completed normally.
- Completing a cycle advances the deload cadence even if some sessions were Skipped. The completion confirmation must summarize skipped work.
- Abandoning a cycle does not advance the cadence. The next cycle occupies the same place in the progression.
- Training Weeks cannot be added, removed, or reordered. Omitting a week's work means explicitly skipping its sessions; ending the remaining cycle early means Abandonment.
- A due Deload Week initially uses the same session and lift layout as a normal Training Week. Its set and weight rules are resolved separately by “Define weights, Training Max, and e1RM rules.”

### Templates, drafts, and activation

- The permanent built-in Default Schedule initializes and can reset one user-editable Schedule Template. The template describes one recurring normal-week layout of intended weekdays, Primary Lift roles, and Assistance Lift roles.
- A new Training Cycle receives three independent copies of that weekly layout, plus a fourth Deload Week when due. Later cycle edits never change the template implicitly.
- At most one Active Training Cycle and one optional Draft Training Cycle may exist. A draft may be edited while another cycle is active, but it cannot be activated until that cycle is Completed or Abandoned.
- A draft is a snapshot: later template changes do not update it. The user may explicitly discard and regenerate it or replace its schedule from the current template.
- A draft's Deload Week inclusion is provisional because the Active Training Cycle may be abandoned. Activation recalculates the requirement from completed-cycle cadence. A mismatch blocks activation until the user confirms a preview that adds or removes the week; removing a customized Deload Week requires a prominent warning.
- To replace the Schedule Template from a cycle, the user selects one normal Training Week and confirms a preview of the extracted weekdays and lift roles. Dates, prescriptions, statuses, and logged work are excluded, and a Deload Week cannot be the source.

### Dates and schedule changes

- Every cycle has a user-selected, timezone-free Week 1 Anchor Date, defaulting to Monday. It establishes three consecutive seven-day Training Week spans and generates intended session dates from template weekdays.
- Activation may happen before, on, or after the anchor date. If a draft's anchor has passed, activation must require the user to retain it or explicitly choose a new one; dates never shift automatically.
- A Calendar Change moves a Scheduled Session's intended date without changing its Training Week or prescription. Moving outside that week's intended date range is allowed with a warning.
- Planned dates remain fixed local calendar dates when the user changes time zones. Actual completion and audit events retain timestamps.

### Sessions and progression

- A normal week may contain any positive number of sessions, including multiple sessions on one date. Every 5/3/1 Session has exactly one Primary Lift and one Assistance Lift; both roles may use the same movement.
- Planned session states are Scheduled, Completed, and Skipped. Passing an intended date does not create a “missed” state: the session stays Scheduled until completed, rescheduled, or explicitly skipped.
- The user may complete a later week's session while an earlier week remains unfinished, with a warning. Training Weeks must still be explicitly finished in sequence.
- A week becomes eligible to finish only when all its sessions are Completed or Skipped. Finishing a week, completing a cycle, and abandoning a cycle all require explicit confirmation; nothing silently advances or creates the next cycle.
- “Skip remaining sessions in this week” is available with one confirmation and an optional shared note, but records each affected session as individually Skipped. There is no whole-cycle bulk-skip action.

### Editing, abandonment, and history

- A Program Edit changes Scheduled Sessions or their lift roles within the fixed week sequence. It is cycle-only, preserves completed work, records affected before/after values, and offers template saving only as a separate explicit action.
- While a cycle is active, a Completed or Skipped Session may be reopened. Doing so also reopens a finished containing week and creates an audit entry. A Scheduled Session may be removed through an audited Program Edit.
- Abandoning a cycle preserves it as a terminal historical snapshot. Sessions still Scheduled at abandonment remain visibly Unperformed rather than becoming Skipped.
- Completed and Abandoned cycles cannot be structurally rewritten or individually deleted. Their recorded facts may receive audited corrections; whole-app reset behavior belongs to the data-lifecycle decision.
- History shows cycles chronologically by Week 1 Anchor Date with Draft, Active, Completed, Abandoned, and Deload-included badges rather than parity-based cycle numbers. It shows planned-versus-actual session details and an expandable change history for reschedules, Program Edits, status changes, and corrections.
- Exceptional-action notes are optional. The action, timestamp, and before/after values remain mandatory audit facts where applicable.
