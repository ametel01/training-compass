# Choose the personal installation path

Type: grilling
Status: resolved
Blocked by: 02

## Question

Given the researched Apple signing and installation constraints, which personal deployment path should this project adopt, and what recurring maintenance or cost is acceptable to keep the app working on the owner's iPhone?

## Answer

Adopt free Xcode Personal Team signing as Training Compass's sole intended installation path for both prototyping and ongoing owner-only use. The owner accepts its roughly seven-day provisioning lifecycle and will not pay for an Apple Developer Program membership. Paid development signing, Ad Hoc distribution, and TestFlight are therefore not part of this effort.

Keep one stable explicit App ID and bundle ID across refreshes. Treat profile expiry as routine owner maintenance: if a refresh is missed, the app may temporarily stop launching until it is built, signed, and installed again. The product and recovery design must not imply a maintenance-free private install.

Use a per-user `launchd` job around day five to remind the owner and run preflight checks, followed by a one-click, user-attended refresh in the logged-in macOS session. The paired iPhone should normally be connected by cable and recently unlocked. The refresh may script the build, automatic signing/provisioning update, embedded-profile inspection, in-place installation, launch smoke test, and result logging, but it must surface authentication, keychain, pairing, Developer Mode, connectivity, or device failures for manual recovery. It must not store Apple Account or keychain passwords or claim fully unattended renewal.

Every refresh installs over the existing app and never uninstalls it. Afterward, the owner verifies important local data. Because Apple does not document Personal Team reinstallation as a sufficient data-preservation contract, the already-decided verified Training Compass Export and restore workflow remains required before the app is treated as the authoritative daily training record.

Context: [Personal Team weekly reprovision automation](../../../docs/research/personal-team-weekly-reprovision-automation.md)
