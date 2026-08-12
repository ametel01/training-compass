# Verify Gate 0

Use this procedure before committing any Gate 0 change.

## Prerequisites

- stable Xcode 26 or newer selected with `xcode-select`;
- Swift 6;
- an iOS 26 Simulator for the UI journey; and
- no signing identity for Simulator-only verification.

Personal Team signing is attended and is required only for the Acceptance Device checklist.

## Run the change gates

```sh
make bootstrap
make verify
make test-ui
make verify-migrations
```

`make verify` checks Swift formatting, the inward package graph, framework containment, the reviewed dependency allowlist, privacy invariants, fixture determinism, package tests, a Release iOS Simulator build, and whitespace errors.

## Verify the result

The commands must exit successfully. The UI test must find the Today, Cycle, Progress, and TMs tabs, identify the build as pre-data, and prove an unfinished destination has no data-entry path.

## Record physical-device evidence

Print the attended Gate 0 protocol:

```sh
make device-smoke MILESTONE=gate-0
```

After completing it, record only privacy-safe environment data:

```sh
RESULT=pass \
DEVICE_MODEL='owner device model' \
IOS_VERSION='26.x' \
make device-smoke MILESTONE=gate-0
```

The ignored record is written to `evidence/device/gate-0.json`. It contains no owner measurements, identifiers, routes, or notes.
