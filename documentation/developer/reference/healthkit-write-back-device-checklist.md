# HealthKit Write-back Acceptance Device checklist

Run this checklist on the in-place Acceptance Device after the automated gates
pass. Record only pass/fail state and timing; do not include workout measures,
HealthKit identifiers, or owner data in evidence artifacts.

1. Open Health and confirm the Session-summary preference is off. Verify that
   no HealthKit write authorization prompt appears during launch or read-only
   Health connection.
2. Enable the preference and record that the write authorization prompt occurs
   only after the toggle. Cancel it once and verify local training remains
   usable; re-enable and grant access for the remaining checks.
3. Complete a resolved Session. Read the disclosure and choose Keep this
   Session local. Verify the Session is Completed and its detail says Not
   shared without waiting on Health.
4. Complete another resolved Session, choose Share summary, and verify the
   detail transitions through Queued/Saving to Saved to Health while navigation
   and local history remain responsive.
5. Open the saved Health workout and verify it is Traditional Strength
   Training with start, end, duration, and Training Compass sync metadata only.
   Confirm sets, loads, prescriptions, Training Maxes, e1RM, notes, and audit
   history are absent.
6. Repeat the completion or retry action and verify no duplicate summary is
   created. Link a Session to an external Health workout during completion and
   verify no Training Compass summary is created.
7. Disable Health access or lock the device before a queued save. Verify local
   completion and navigation succeed, and the detail reports a retry/access
   state. Restore access and explicitly retry; verify the same sync identity is
   saved once.

The corresponding automated evidence is `HealthWorkoutWriteBackBoundary`, the
write-back repository tests, the HealthKit adapter tests, and `make verify`.
