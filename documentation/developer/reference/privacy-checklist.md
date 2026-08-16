# Gate 0 privacy checklist

Automated change gates verify:

- only reviewed GRDB is present in the resolved dependency graph;
- production sources contain no networking, cloud, analytics, or third-party crash reporting;
- the only shipped entitlement is the reviewed HealthKit capability;
- the privacy manifest declares no tracking or collected data;
- HealthKit imports occur only inside `HealthKitAdapter`;
- both store directories receive complete file protection;
- the reconstructible directory receives and verifies backup exclusion;
- fixtures are synthetic, deterministic, versioned, and marked as not accepting owner data;
- route coordinates are absent from fixtures, evidence, logs, and authoritative export-by-default output;
- full-resolution HealthKit route coordinates remain adapter-private while only geometry simplified to at most 2,000 points crosses the application boundary;
- logs accept a fixed event enum instead of arbitrary strings or payloads; and
- production diagnostics retain only the newest seven days or 200 events and
  serialize a closed operation/duration/count/bytes/peak-memory/result/device
  schema with no dates, identifiers, measurements, routes, or notes;
- diagnostic export is explicit, inspectable, and removed by the caller after
  review or sharing;
- diagnostic files and their directory receive complete file protection and
  backup exclusion, and full app erasure removes them on normal and recovery
  paths;
- the evidence index sanitizes dependency paths and records only the approved
  fixture, algorithm, environment, compatibility, measurement, verdict, and
  waiver fields; and
- app content is privacy-sensitive and covered whenever the scene is not active.

The Acceptance Device checklist verifies OS-enforced file attributes, app-switcher concealment, offline launch, and the opt-in Health authorization flow on real hardware.
