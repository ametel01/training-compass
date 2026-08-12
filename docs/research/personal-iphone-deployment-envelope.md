# Personal iPhone deployment envelope

Research date: 2026-08-12

## Question

What current Apple-supported installation and signing paths can keep Training
Compass usable on its owner's iPhone, without requiring a public App Store
release?

## Decision

Use one stable explicit App ID and bundle ID from the first device build.

- Use the free Xcode Personal Team while prototyping. It supports on-device
  testing, HealthKit, and Background Modes, but its seven-day provisioning
  lifecycle makes it unsuitable as the intended long-term operating path.
- Before relying on the app for day-to-day training history, enroll in the
  Apple Developer Program and keep the membership current. The default
  long-term path should be a paid development-signed install from Xcode on the
  owner's registered iPhone. It has the fewest moving parts for one owner who
  already has the source and a Mac.
- Keep paid Ad Hoc distribution as an optional release-like direct-install
  path. It is useful for installing an exported IPA with Xcode or Apple
  Configurator, but it adds signing/export work without solving provisioning
  expiration.
- Keep internal TestFlight as an optional convenience path when installation
  without Developer Mode and TestFlight-delivered updates are worth uploading
  builds to App Store Connect at least every 90 days. It is a beta-distribution
  channel, not a permanent private install.

There is no documented maintenance-free, indefinitely valid private path among
Personal Team, paid development signing, Ad Hoc, and TestFlight. The app must
therefore include a local-data export/backup workflow, and the owner must treat
signing renewal as routine maintenance rather than an exceptional recovery.

## Compared paths

| Path | What Apple documents | Expiration and recurring work | Fit for this app |
| --- | --- | --- | --- |
| Free Xcode Personal Team | An Apple Account can test apps on personal devices. A Personal Team is limited to 10 App IDs, 3 test devices per platform, and 3 installed Personal Team apps per device; the App IDs, devices, and provisioning profiles expire after 7 days. [Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account), [Choosing a Membership](https://developer.apple.com/support/compare-memberships/) | Rebuild and reinstall/re-provision about weekly. A connected or paired iPhone and Xcode are part of the development workflow. | Good for zero-cost prototyping and proving HealthKit on the physical phone; too fragile for a rolling personal training log. |
| Paid development install from Xcode | Xcode can automatically register a physical device and create a development provisioning profile. A paid membership costs USD 99 per membership year. [Running on physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices), [Choosing a Membership](https://developer.apple.com/support/compare-memberships/) | Every provisioning profile has an `ExpirationDate`; validity varies by profile type and is typically no more than a year. Regenerate an expired profile and re-sign the app. Renew program membership annually. [TN3125](https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles), [Regenerating profiles](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/), [Program renewal](https://developer.apple.com/help/account/membership/renewal/) | Preferred steady-state path for one owner with a Mac: direct, no beta channel, and Xcode can manage signing. Still not permanent. |
| Paid Ad Hoc | A registered device can receive an Ad Hoc build. The profile binds an App ID, one distribution certificate, and selected registered devices. Apple permits up to 100 iPhones per membership year. The exported IPA can be installed with Xcode or Apple Configurator. [Ad Hoc profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/), [Devices overview](https://developer.apple.com/help/account/devices/devices-overview/), [Registered-device distribution](https://developer.apple.com/documentation/Xcode/distributing-your-app-to-registered-devices) | The embedded profile expires and then must be regenerated; the app must be re-signed and reinstalled. Paid development- and Ad-Hoc-signed apps for teams created after 2021-06-06 must contact Apple's PPQ service on first launch unless using a short-lived offline profile. [Regenerating profiles](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/), [Provisioning updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates) | Viable, but mainly useful if a reproducible release archive/IPA is desirable. It offers little extra value for a single phone connected to the development Mac. |
| Internal TestFlight | Paid membership provides App Store Connect and distribution. Internal testers are App Store Connect users; Account Holder is an eligible role. A TestFlight build can be tested for up to 90 days and is installed through the TestFlight app. [Choosing a Membership](https://developer.apple.com/support/compare-memberships/), [Internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/), [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) | Upload and assign a fresh build before the current build's 90-day window ends. Maintain the paid membership and App Store Connect access. | Convenient installs and updates without Developer Mode, but the 90-day build clock creates quarterly-or-faster release work. |

## Capability envelope

Apple's current iOS capability matrix shows both **HealthKit** and **Background
Modes** as supported for all three listed account classes, including the free
"Apple Developer" class as well as paid Apple Developer Program membership.
That means a Personal Team can be used to prove the required entitlements on a
real iPhone; paying is not required solely to add these two capabilities.
[Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)

This is a provisioning capability, not a guarantee of continuous execution.
Whether HealthKit observer queries and background delivery update Training
Compass at the desired cadence is a separate runtime/API question. The
deployment decision must not be used as evidence for background freshness.

Locally installed apps require Developer Mode. Apple explicitly scopes
Developer Mode to Xcode-run apps and IPAs installed with Apple Configurator,
and says that TestFlight installation is unaffected by Developer Mode.
[Enabling Developer Mode](https://developer.apple.com/documentation/Xcode/enabling-developer-mode-on-a-device)

For Apple Developer Program teams created after 2021-06-06, development- and
Ad-Hoc-signed iOS apps must contact Apple's PPQ service when first launched.
The device needs Internet access for that verification. Apple's documented
offline development/Ad Hoc profile alternative is valid for only seven days;
Apple's page mentions extended offline support but does not provide a generally
available duration or workflow. This app should therefore assume an online
first launch after each direct re-sign/install.
[Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates)

## Signing and expiration details

### What is documented

- Personal Team App IDs, registered devices, and provisioning profiles each
  have a seven-day lifecycle. Apple says profile expiry may require rebuilding
  and reinstalling the app.
  [Choosing a Membership](https://developer.apple.com/support/compare-memberships/)
- Every provisioning profile carries an `ExpirationDate`. Apple says the
  validity varies by profile type and is typically no more than a year.
  [TN3125](https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles)
- When a profile expires, Apple instructs the developer to regenerate the
  profile, remove the expired profile, and re-sign the app with the regenerated
  profile.
  [Edit, download, or delete profiles](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/)
- Apple Developer Program membership is annual. If it expires, access to
  Certificates, Identifiers & Profiles, new submissions/updates, and TestFlight
  is lost until renewal.
  [Program renewal](https://developer.apple.com/help/account/membership/renewal/),
  [Resolving access issues](https://developer.apple.com/help/account/access/resolving-access-issues/)
- TestFlight builds become unavailable to testers after 90 days.
  [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

### What is not safely specified by current documentation

- Apple's current profile-creation help does not promise one fixed lifetime for
  every paid development or Ad Hoc profile. The generated profile's
  `ExpirationDate` is authoritative. A design or runbook should not hard-code
  "one year" even though Apple's technote says profiles are *typically* valid
  for no more than a year.
- Apple's renewal help says already-installed apps still function after an
  Apple Developer Program membership expires, but the surrounding text concerns
  App Store availability. It does not explicitly promise that an expired or
  subsequently expiring development/Ad Hoc profile will keep launching. The
  direct-install plan must continue to honor the embedded profile's expiration.
- Apple does not document that reinstalling a re-signed Personal Team,
  development, or Ad Hoc build will always preserve this app's local container.
  Data preservation across a signing failure or accidental deletion must not
  depend on that assumption.

## TestFlight review boundary

Apple documents internal testing as a path for up to 100 App Store Connect users
with eligible roles and permits a build to be marked "TestFlight Internal Only."
Apple's TestFlight overview separately says the first build added for **external**
testers may require App Review. The current pages reviewed do not describe beta
review as a step in the internal-only invitation workflow. It is therefore fair
to plan an owner-only internal TestFlight lane without external beta review, but
not to generalize that claim to external testers.
[Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/),
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

TestFlight still requires an App Store Connect app record, uploaded builds, test
information, export-compliance handling where applicable, and the TestFlight app
on the iPhone. It does not require releasing the app on the public App Store.
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## Maintenance contract for the eventual implementation plan

1. Keep the bundle ID and explicit App ID stable across every installation path.
2. During prototyping, expect a Personal Team re-provision at least every seven
   days; never treat that build as the only copy of manual 5/3/1 history.
3. Before operational use, enroll in the paid program and enable automatic
   renewal if Apple offers it in the account's region. Apple also permits manual
   renewal beginning 30 days before expiration.
   [Program renewal](https://developer.apple.com/help/account/membership/renewal/)
4. For direct installs, inspect the generated provisioning profile's
   `ExpirationDate` and schedule a new signed build before it. Preserve the
   signing private key securely; a different Mac needs the signing identity and
   private key, not merely the certificate.
   [TN3125](https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles),
   [Certificates overview](https://developer.apple.com/help/account/certificates/certificates-overview)
5. If internal TestFlight is chosen, upload and install a replacement build well
   before the 90-day deadline; use a shorter operational target such as 60 days
   to leave recovery margin. The 60-day target is a project recommendation, not
   an Apple requirement.
6. Implement export and verified restore of all app-owned data before declaring
   the app dependable. HealthKit remains the system of record for imported
   Health data, but the app's schedule, Training Maxes, manual 5/3/1 Sessions,
   and reconciliation state need their own recoverable backup.
7. Document a recovery drill: export, archive/source checkout, renew signing,
   install over the existing app if possible, verify local data, and restore from
   export if preservation fails. Steps concerning local data are project risk
   controls, not Apple-documented guarantees.

## Scope boundary

Public App Store release remains out of scope. Apple's membership-renewal page
does document that already-installed App Store apps continue functioning after
membership expiry, which highlights why the compared private paths cannot be
treated as equally durable. If the recurring private-signing burden later proves
unacceptable, changing the distribution destination should be a new explicit
decision rather than an accidental expansion of this effort.
[Program renewal](https://developer.apple.com/help/account/membership/renewal/)

## Primary sources

- [Choosing a Membership](https://developer.apple.com/support/compare-memberships/)
- [Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
- [Running your app on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
- [Enabling Developer Mode on a device](https://developer.apple.com/documentation/Xcode/enabling-developer-mode-on-a-device)
- [Create a development provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/)
- [Create an Ad Hoc provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/)
- [Distributing your app to registered devices](https://developer.apple.com/documentation/Xcode/distributing-your-app-to-registered-devices)
- [Devices overview](https://developer.apple.com/help/account/devices/devices-overview/)
- [Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates)
- [Edit, download, or delete provisioning profiles](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/)
- [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles)
- [Certificates overview](https://developer.apple.com/help/account/certificates/certificates-overview)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Program renewal](https://developer.apple.com/help/account/membership/renewal/)
- [Resolving access issues](https://developer.apple.com/help/account/access/resolving-access-issues/)
