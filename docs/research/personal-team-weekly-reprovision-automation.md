# Personal Team weekly reprovision automation

Research date: 2026-08-12

## Question

Can Training Compass, installed on its owner's iPhone with a free Xcode Personal
Team, be re-provisioned, re-signed, and reinstalled about weekly by `cron` or an
equivalent unattended macOS scheduler?

## Conclusion

**The mechanics can be scripted, but the complete workflow cannot be treated as
a safe, reliable unattended job.** `xcodebuild` can build and sign, and
`devicectl` can find a paired device, install an app, and launch a process.
Apple explicitly presents `devicectl` as suitable for scripts and CI workflows.
However, a free Personal Team depends on a personal Apple Account signed into
Xcode, a usable signing identity in the owner's login keychain, and a paired
iPhone that has been unlocked recently. Any expired account session, keychain
prompt, trust reset, disabled Developer Mode, device disconnect, or unavailable
device turns the job into an interactive recovery.
[Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference),
[WWDC26: Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/),
[physical pairing model security](https://support.apple.com/guide/security/physical-pairing-model-security-secadb5b6434/web)

For one owner who accepts weekly provisioning, the realistic path is a
**one-click, user-attended refresh script run in the logged-in macOS session**, with
a `launchd` reminder and preflight checks. The script may often complete without
further input when the phone is connected and recently unlocked, but the owner
should be present to resolve prompts. Do not make a silent weekly deployment the
only thing standing between the app and profile expiry.

## What Apple supports automating

| Stage | Scriptable mechanism | Boundary |
| --- | --- | --- |
| Build and sign | Use `xcodebuild` against the app's stable scheme, bundle ID, team, and physical-device destination. With automatic signing enabled, `-allowProvisioningUpdates` permits `xcodebuild` to communicate with Apple's developer service. | Full Xcode must be installed and selected as the active developer directory. Automatic signing still needs valid credentials and a signing identity. [Running on physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices), [build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference), [WWDC21: Distribute apps in Xcode with cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/) |
| Inspect the result | The script can inspect the built app's `embedded.mobileprovision`, read its `ExpirationDate`, verify the bundle ID, and fail before installation if they are wrong. | This verifies the artifact, not whether all later device operations will succeed. Apple's seven-day Personal Team lifetime remains authoritative. [Choosing a Membership](https://developer.apple.com/support/compare-memberships/) |
| Discover the target device | `devicectl` can list devices and emit structured JSON for a script. The script should select one pinned device identifier and reject zero or multiple matches. | `devicectl` manages devices connected to its host; discovery does not bypass pairing, trust, connectivity, or recent-unlock requirements. [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference), [WWDC26: Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/) |
| Install | `devicectl` can install the signed `.app` on the selected device. Apple's current Device Hub session explicitly describes app installation through `devicectl` and integration into scripts and CI. | Install over the existing app. Never add an uninstall/delete step to the weekly path. [WWDC26: Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/) |
| Launch and verify | `devicectl device process launch` is an Apple-supported command; a script can launch the bundle as a smoke check and use structured output/exit status. | A successful command launch is only a basic smoke check. It does not prove data integrity or HealthKit/background behavior. [Xcode 16 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes) |

The exact command lines should be finalized on the Mac after full Xcode is
installed by consulting that version's `xcodebuild -help` and
`xcrun devicectl help`. Apple identifies those local help pages as the canonical
references. This research machine currently has macOS 27.0 Command Line Tools
27.0 selected at `/Library/Developer/CommandLineTools`, but not full Xcode;
consequently neither `xcodebuild` nor `devicectl` is presently usable here.
[Installing the command-line tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools),
[configuring command-line tools settings](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings)

## Why fully unattended execution is not dependable

### Personal Team authentication

Apple requires the personal Apple Account to be signed into Xcode, and Xcode
directly manages the Personal Team's App IDs, devices, certificates, and
profiles. The profile expires seven days after issuance and the app then needs
to be rebuilt and reinstalled.
[Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)

For automated `xcodebuild` signing, Apple documents two credential sources:
an Xcode account session, which persists only “for a period of time,” or an App
Store Connect API key. The membership comparison says App Store Connect is a
paid-program benefit, so the API-key route is not available to a free Personal
Team. This means the free workflow ultimately depends on the owner's Xcode
login session and may require a fresh interactive Apple Account/2FA login.
This is an inference from the two Apple documents, not an explicit statement
that names Personal Team automation.
[WWDC21: Distribute apps in Xcode with cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/),
[Choosing a Membership](https://developer.apple.com/support/compare-memberships/)

### Signing identity and keychain

Signing requires a certificate plus its matching private key. Xcode creates
the private key in the owner's **login keychain**. A scheduled process must run
as that user and be allowed to use the identity; a locked keychain or an access
control prompt can stop unattended signing. Apple documents
`security find-identity -p codesigning` as a way to inspect available signing
identities.
[TN3161: Inside Code Signing: Certificates](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates)

Do not put an Apple Account password or login-keychain password in a script,
plist, environment variable, or command line to force unattended operation.
The local Apple `security(1)` manual explicitly marks supplying a keychain
password with `-p` as insecure in its `create-keychain` workflow; the same
secret-handling risk is a reason not to pass the login-keychain password to an
unattended refresh. Configure the normal Xcode/codesign keychain access once in
the interactive user session and let the refresh fail clearly when that access
is unavailable.

### Pairing, trust, unlock, and Developer Mode

Initial pairing is human work: the user must unlock the iPhone, accept the
host's pairing request, and enter the device passcode. Services used for Xcode
development cannot start until the device has been unlocked and will not start
unless it was unlocked recently. Wi-Fi communication also requires a pairing
previously established over USB or Thunderbolt. Pairing records expire after
30 days without use and can be cleared by resetting Network Settings or
Location & Privacy.
[Physical pairing model security](https://support.apple.com/guide/security/physical-pairing-model-security-secadb5b6434/web),
[About the “Trust This Computer” alert](https://support.apple.com/en-mide/109054)

Developer Mode is also explicitly interactive to enable: iOS restarts, the
owner confirms again, and enters the device passcode. Once enabled it need not
normally be repeated for each weekly install, but an automation must detect and
report when it is unavailable; it cannot safely click through this security
boundary.
[Enabling Developer Mode on a device](https://developer.apple.com/documentation/Xcode/enabling-developer-mode-on-a-device)

A cable is the most predictable weekly connection. A previously paired Wi-Fi
connection may work, but adds network reachability to an already time-sensitive
maintenance operation. Neither connection mode removes the recent-unlock rule.

## Scheduler assessment

`cron` is the wrong scheduler. Apple still supports it but deprecates it in
favor of `launchd`; a `cron` occurrence is simply missed while the Mac sleeps.
The local `crontab(1)` manual likewise says its function has been absorbed into
the more flexible `launchd`.
[Scheduling Timed Jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html)

A per-user `LaunchAgent` with `StartCalendarInterval` is better: Apple's local
`launchd.plist(5)` manual says a missed calendar firing runs on wake and
coalesces multiple missed occurrences. Run it in the logged-in GUI user's
domain, write stdout/stderr to dedicated logs, and use it to:

1. check the currently installed/built profile's expiry window;
2. notify the owner two or more days before expiry;
3. offer a command or shortcut that starts the attended refresh; and
4. keep notifying on failure until the refresh succeeds.

It may optionally attempt the refresh automatically while the user is logged
in, but it must be designed as **best effort**: short timeouts, no password
prompts, no device deletion, an immediate visible failure notification, and a
manual retry path. `launchd` improves wake scheduling; it does not make the
iPhone present, the keychain unlocked, or the Apple Account session valid.

## Data-preservation boundary

Use the same bundle ID, Personal Team, and application identifier every week,
and install the new signed build **over** the existing installation. Never
uninstall first. Apple's current Xcode testing documentation says Xcode
development installs update apps incrementally and explains that explicitly
removing an app can also remove its prior data.
[Testing a release build](https://developer.apple.com/documentation/xcode/testing-a-release-build)

Apple's older update contract guarantees preservation of `Documents` and
`Library` (except `Library/Caches`) for normal app updates, but the same note
warns that Xcode's optimized development install differs from App Store update
installation. It does not establish an equivalent preservation guarantee for
a re-signed Personal Team app installed by Xcode or `devicectl`. Therefore an
in-place weekly install is the least destructive approach, **not a backup
contract**.
[TN2285: Testing iOS App Updates](https://developer.apple.com/library/archive/technotes/tn2285/)

Before Training Compass becomes the authoritative copy of manual training
history, add and verify an app-level export/restore path. A weekly refresh
script should refuse to uninstall and should either create a current export
first or require the owner to confirm that one exists. Device Hub can download
and replace app data containers, but an app-owned, versioned export remains the
more portable recovery control.
[WWDC26: Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/)

## Recommended owner workflow

1. Install full current Xcode; select it as the active developer directory;
   accept its license; download iOS platform support; and perform one manual
   build-and-run from Xcode.
2. During that first run, sign the personal Apple Account into Xcode, select
   the Personal Team, enable automatic signing, pair and trust the exact
   iPhone, enable Developer Mode, and confirm the signing identity works.
3. Keep one stable bundle ID and pin the target iPhone's identifier. Store no
   Apple or keychain passwords in automation.
4. Add a per-user `LaunchAgent` that starts checking and reminding around day
   five, rather than gambling on the seventh day. Schedule during a time when
   the owner normally has the Mac awake and the phone available.
5. Connect the iPhone by cable, unlock it, and invoke the one-click refresh
   while logged into the Mac. The script should preflight Xcode, account/signing
   identity, internet, device identity/connectivity, pairing, recent unlock,
   Developer Mode, and a current data export.
6. Build with automatic signing and provisioning updates; inspect the new
   embedded profile; install over the existing app; launch it; and record the
   profile expiration and command results.
7. Open Training Compass and verify its important local data after every
   refresh. On any failure, leave the existing app installed, surface the exact
   failed precondition, and retry manually before expiry.

This preserves the zero-dollar Personal Team choice while automating the
repetitive work that Apple actually exposes. It deliberately retains a small,
honest human checkpoint around Apple's account, keychain, and device-security
boundaries.

## Primary sources

- [Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Choosing a Membership](https://developer.apple.com/support/compare-memberships/)
- [Running your app on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
- [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
- [WWDC26: Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/)
- [WWDC21: Distribute apps in Xcode with cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [TN3161: Inside Code Signing: Certificates](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates)
- [Physical pairing model security](https://support.apple.com/guide/security/physical-pairing-model-security-secadb5b6434/web)
- [About the “Trust This Computer” alert](https://support.apple.com/en-mide/109054)
- [Enabling Developer Mode on a device](https://developer.apple.com/documentation/Xcode/enabling-developer-mode-on-a-device)
- [Scheduling Timed Jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html)
- [Testing a release build](https://developer.apple.com/documentation/xcode/testing-a-release-build)
- [TN2285: Testing iOS App Updates](https://developer.apple.com/library/archive/technotes/tn2285/)
- Local Apple manuals on macOS 27.0: `crontab(1)`, `launchd.plist(5)`,
  `launchctl(1)`, and `security(1)`.
