# Personal Team refresh Acceptance Device checklist

This is an attended maintenance check for the owner's private iPhone. It is
not a distribution or unattended-renewal path. Use the same paired iPhone and
the same stable bundle identifier (`com.ametel01.trainingcompass`) on every
run. Record only the booleans, profile dates, device model, iOS version, and
privacy-safe notes accepted by `make device-smoke`; never record Apple Account
details, keychain material, device identifiers, HealthKit identifiers, owner
measurements, or free-text training data.
The workflow never stores credentials.

## Before the first refresh

1. Install full Xcode 26 or newer, select it as the active developer
   directory, accept its license, and complete one manual build-and-run.
2. Sign the owner into Xcode's Apple Account session, select the free Personal
   Team, and keep automatic signing enabled. The repository's project must
   continue to show one explicit bundle ID and the
   `TRAINING_COMPASS_DEVELOPMENT_TEAM` setting; do not add a paid, Ad Hoc,
   TestFlight, or distribution certificate path.
3. Pair and trust exactly one owner iPhone, enable Developer Mode on that
   device, and record its CoreDevice identifier locally in
   `TRAINING_COMPASS_DEVICE_ID`. Keep the identifier out of evidence.
4. Create and open a current, verified Training Compass Export. Keep its path
   in `TRAINING_COMPASS_EXPORT_PATH` and set
   `TRAINING_COMPASS_EXPORT_VERIFIED=true` only after the archive validates in
   the app. The refresh must refuse without this recovery prerequisite.
5. In the logged-in shell, export the non-secret team/device/export inputs and
   the attended confirmations before installing the reminder:

   ```shell
   export TRAINING_COMPASS_DEVELOPMENT_TEAM=YOUR_PERSONAL_TEAM_ID
   export TRAINING_COMPASS_DEVICE_ID=YOUR_PAIRED_COREDEVICE_ID
   export TRAINING_COMPASS_EXPORT_PATH=/path/to/verified-training-compass-export
   export TRAINING_COMPASS_EXPORT_VERIFIED=true
   export TRAINING_COMPASS_DEVICE_READY=true
   export TRAINING_COMPASS_APPLE_AUTH_CONFIRMED=true
   export TRAINING_COMPASS_PERSONAL_TEAM_CONFIRMED=true
   ```

6. Install the per-user reminder from that logged-in macOS session:

   ```shell
   make install-personal-team-refresh-reminder
   ```

   The LaunchAgent checks once per day around the Personal Team day-five
   window. It may notify and run preflight, but it never builds, signs,
   installs, uninstalls, or handles credentials by itself. Apple authentication
   and free-Team confirmation are intentionally not persisted in the plist;
   re-export them in the attended shell before a refresh.

## Attended refresh

For the normal cable-connected path, run the friendly entry point and follow
its attended prompts:

```shell
make install-iphone
```

It selects the newest complete Xcode installation by default, discovers exactly
one paired, unlocked wired iPhone, checks whether the stable
Training Compass bundle is already installed, and reuses one local Apple
Development team from Xcode's account cache, signing identities, or profiles
without asking for a Team ID. This supports the owner account's unambiguous free
Personal Team or Individual development team for cable installation only; it
does not enable distribution signing. Set `TRAINING_COMPASS_DEVELOPER_DIR` or
`DEVELOPER_DIR` to override the Xcode selection. If
no team is discoverable yet, use Xcode > Settings > Accounts to add the Apple
Account if needed, then use Manage Certificates to create one Apple Development
certificate for the free Personal Team. Rerun the command after Xcode finishes;
this one-time setup does not change the project file. A fresh install skips the
recovery-export gate because no app
dataset is being replaced. For an existing installation, the helper selects the
newest `.trainingcompass` export in Downloads, Desktop, Documents, or iCloud
Drive and asks the owner to confirm it was opened and verified. Create and share
an export from the iPhone app first if none is present on the Mac; an iPhone Files
path is not a macOS path and cannot be passed to `xcodebuild`. Optional
`TEAM_ID=...` and `EXPORT_PATH=...` Make arguments remain ambiguity overrides.
If the login keychain does not yet contain an Apple Development identity, the helper asks Xcode
automatic signing to create or refresh one for the selected Personal Team and
connected device before continuing. The helper does not persist a device
identifier or accept an Apple Account password; it delegates to the guarded
refresh workflow below.

1. Connect the iPhone by cable (Wi-Fi transport is refused), unlock it, and keep the Mac's login session
   and login keychain available. Confirm the owner-facing preflight reports
   Xcode, Apple authentication (confirmed in the attended Xcode session), signing identity/keychain, pinned device,
   pairing, cable, recent unlock, Developer Mode, stable App ID, and the
   verified export. Set `TRAINING_COMPASS_DEVICE_READY=true` after those
   device checks have been visually confirmed.
2. Run the one-click workflow from the repository root:

   ```shell
   make personal-team-refresh
   ```

   The workflow builds the Release device artifact with automatic signing and
   provisioning updates, inspects `embedded.mobileprovision` for the exact
   bundle ID, Personal Team, development devices, and profile dates, installs
   with `devicectl` over the existing app, and launches the bundle for a smoke
   test. There is deliberately no uninstall or delete command.
3. Open the refreshed app and verify Today, Cycle, Progress, TMs, Health,
   existing Training Maxes, Sessions, audit history, Health status, and the
   export/import recovery actions are still present. Confirm that the local
   dataset was preserved before accepting the result. If the app does not
   launch after the profile expires, record temporary inability to launch
   until this attended rebuild/install is completed; do not describe it as
   data deletion.
4. Inspect the privacy-safe result at
   `~/Library/Application Support/TrainingCompass/last-personal-team-refresh.json`.
   It must contain only fixed check names, profile creation/expiration dates,
   coarse environment information, a result, and the data-continuity boolean.
   The log and result must not contain credentials, device identifiers,
   HealthKit identifiers, owner measurements, or training notes.

## Recording the Acceptance Device result

After the attended run, record only the checklist booleans and profile dates;
this milestone does not require the unrelated release-measurement envelope:

```shell
RESULT=pass DEVICE_MODEL='your iPhone model' IOS_VERSION='your iOS version' \
PERSONAL_TEAM_PROFILE_CREATION_DATE='YYYY-MM-DD HH:MM:SS +0000' \
PERSONAL_TEAM_PROFILE_EXPIRATION_DATE='YYYY-MM-DD HH:MM:SS +0000' \
PERSONAL_TEAM_STABLE_IDENTITY=true PERSONAL_TEAM_PREFLIGHT=true \
PERSONAL_TEAM_PROFILE=true PERSONAL_TEAM_IN_PLACE=true \
PERSONAL_TEAM_LAUNCH=true PERSONAL_TEAM_DATA_CONTINUITY=true \
PERSONAL_TEAM_PRIVACY=true make device-smoke MILESTONE=personal-team-refresh
```

Verify the saved record with `make verify-release
MILESTONE=personal-team-refresh` when the physical-device evidence is ready.

## Failure and retry rules

- A failed preflight, build, profile inspection, install, or launch leaves the
  existing app installed and names the failed check for manual recovery.
- Apple Account prompts, keychain access, pairing/trust, Developer Mode,
  cable connection, and recent unlock remain human checkpoints. Never put
  those secrets or passcodes in a script, plist, environment file, or log.
- A missed reminder is a maintenance interruption only. Reconnect, unlock,
  export/verify current data, repair the named preflight condition, and rerun
  the attended workflow before the seven-day Personal Team profile expires.
