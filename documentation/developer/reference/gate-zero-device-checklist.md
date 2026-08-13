# Gate 0 Acceptance Device checklist

Use a paired, recently unlocked iPhone running stable iOS 26. Do not grant Health access; Training Max configuration, completed-cycle proposal review, and local training workflows are supported owner-data actions in this build.

1. Set `TRAINING_COMPASS_DEVELOPMENT_TEAM` to the Personal Team identifier in the attended shell or Xcode session.
2. Build and install the Release configuration without erasing the prior app container.
3. Launch Training Compass and confirm the PRE-DATA BUILD warning appears.
4. Confirm Today, Cycle, Progress, and TMs are reachable; TMs can review and confirm lift configurations and Training Max proposals when completed-cycle data exists.
5. Confirm the app never presents a Health authorization sheet or data-entry control.
6. Background the app and open the app switcher; confirm only the Training Compass privacy shield is visible.
7. Inspect the app container and confirm the authoritative and reconstructible directories use complete file protection.
8. Confirm the reconstructible directory has the backup-exclusion resource value and the authoritative directory is not intentionally excluded.
9. Relaunch while offline and confirm the shell still reaches its protected-ready state.
10. Record pass or fail with device model and iOS version only. Do not record paths, UUIDs, dates, measurements, routes, or free text copied from the device.

A passing checklist proves Gate 0 launch, storage behavior, and the confirmed local training slices. It does not approve Health integration for owner data.
