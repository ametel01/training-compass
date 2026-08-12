# Gate 0 privacy checklist

Automated change gates verify:

- only reviewed GRDB is present in the resolved dependency graph;
- production sources contain no networking, cloud, analytics, or third-party crash reporting;
- Gate 0 ships no entitlements;
- the privacy manifest declares no tracking or collected data;
- HealthKit imports occur only inside `HealthKitAdapter`;
- both store directories receive complete file protection;
- the reconstructible directory receives and verifies backup exclusion;
- fixtures are synthetic, deterministic, versioned, and marked as not accepting owner data;
- logs accept a fixed event enum instead of arbitrary strings or payloads; and
- app content is privacy-sensitive and covered whenever the scene is not active.

The Acceptance Device checklist verifies OS-enforced file attributes, app-switcher concealment, offline launch, and absence of Health authorization on real hardware.
