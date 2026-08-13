# Training Compass

Training Compass is a private, local-first iPhone training app. The current executable contains the protected Gate 0 shell and local training workflows: TMs manages kilogram Training Maxes and per-lift Loading Increments, Cycle maintains the reusable Schedule Template, prepares Draft Training Cycles, and activates one durable cycle with immutable 5/3/1 prescriptions. Today exposes prescribed, failed, omitted, and Additional Set work, then requires explicit confirmation to complete and display a planned-versus-actual Session. Health data remains unavailable.

The app targets stable iOS 26 with Swift 6 strict concurrency. Today becomes available after an Active Training Cycle has a Session scheduled for the current date, while Cycle becomes available after the default schedule's lifts are configured in TMs. Progress remains a pre-data destination.

See the [developer documentation](documentation/developer/README.md) for architecture, verification, privacy, migrations, and Acceptance Device evidence.
