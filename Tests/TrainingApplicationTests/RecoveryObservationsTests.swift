import Foundation
import XCTest

@testable import TrainingApplication

final class RecoveryObservationsTests: XCTestCase {
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }

  private func date(_ day: Int, _ hour: Int = 8, _ minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
  }

  private func resting(
    _ id: String,
    day: Int,
    hour: Int = 8,
    value: Double,
    source: String = "com.watch"
  ) -> HealthRestingHeartRateSample {
    HealthRestingHeartRateSample(
      id: id,
      date: date(day, hour),
      beatsPerMinute: value,
      provenance: .init(sourceName: "Watch", sourceBundleIdentifier: source))
  }

  private func hrv(
    _ id: String,
    day: Int,
    hour: Int = 8,
    value: Double,
    source: String = "com.watch",
    algorithm: String? = nil
  ) -> HealthHRVSDNNSample {
    HealthHRVSDNNSample(
      id: id,
      date: date(day, hour),
      milliseconds: value,
      provenance: .init(
        sourceName: "Watch", sourceBundleIdentifier: source, algorithmVersion: algorithm))
  }

  func testRestingHeartRateKeepsSampleDateAndLatestIncludedContext() {
    let samples = [
      resting("morning", day: 14, hour: 7, value: 51),
      resting("later", day: 14, hour: 9, value: 52),
      resting("next-day", day: 16, value: 49)
    ]

    let projection = HealthRecoveryObservationCalculator().calculate(
      restingHeartRate: samples,
      heartRateVariability: [],
      statuses: [],
      calendar: calendar,
      now: date(16, 12))

    XCTAssertEqual(
      projection.restingHeartRate.map(\.date.iso8601String), ["2026-08-14", "2026-08-16"])
    XCTAssertEqual(projection.restingHeartRate.map(\.value), [52, 49])
    XCTAssertEqual(projection.restingHeartRate.first?.sampleIDs, ["morning", "later"])
    XCTAssertEqual(projection.restingHeartRate.first?.latestIncludedSampleID, "later")
    XCTAssertEqual(projection.restingHeartRate.first?.sampleCount, 2)
  }

  func testHRVUsesFullPrecisionOddAndEvenDailyMedians() {
    let samples = [
      hrv("odd-1", day: 14, value: 10),
      hrv("odd-2", day: 14, value: 30),
      hrv("odd-3", day: 14, value: 20),
      hrv("even-1", day: 15, value: 1),
      hrv("even-2", day: 15, value: 2),
      hrv("even-3", day: 15, value: 8),
      hrv("even-4", day: 15, value: 9)
    ]

    let observations = HealthRecoveryObservationCalculator().calculate(
      restingHeartRate: [],
      heartRateVariability: samples,
      statuses: [],
      calendar: calendar,
      now: date(16)
    ).heartRateVariability

    XCTAssertEqual(observations[0].value, 20, accuracy: 0.0000001)
    XCTAssertEqual(observations[1].value, 5, accuracy: 0.0000001)
    XCTAssertEqual(observations.map(\.sampleCount), [3, 4])
    XCTAssertEqual(observations.map(\.algorithmVersions), [[], []])
  }

  func testDuplicateImportReplacementDeletionAndSparseDaysRecomputeOnlyAffectedDates() {
    let first = resting("same", day: 14, value: 55)
    let replacement = resting("same", day: 14, hour: 10, value: 56)
    let downwardCorrection = resting("downward", day: 14, value: 60)
    let correctedDownward = HealthRestingHeartRateSample(
      id: "downward",
      date: date(14),
      beatsPerMinute: 55,
      provenance: .init(
        sourceName: "Watch", sourceBundleIdentifier: "com.watch", algorithmVersion: "v2"))
    let untouched = resting("untouched", day: 16, value: 50)
    let duplicate = resting("duplicate", day: 18, value: 48)
    let samples = [first, replacement, untouched, duplicate, duplicate]

    let calculator = HealthRecoveryObservationCalculator()
    let changed = calculator.calculate(
      restingHeartRate: samples,
      heartRateVariability: [],
      statuses: [],
      calendar: calendar,
      now: date(18, 12))
    XCTAssertEqual(changed.restingHeartRate.map(\.value), [56, 50, 48])
    XCTAssertEqual(changed.restingHeartRate.last?.sampleIDs, ["duplicate"])

    let reversed = calculator.calculate(
      restingHeartRate: [replacement, first, untouched],
      heartRateVariability: [],
      calendar: calendar,
      now: date(18, 12))
    XCTAssertEqual(reversed.restingHeartRate.first?.value, 56)

    let corrected = calculator.calculate(
      restingHeartRate: [downwardCorrection, correctedDownward],
      heartRateVariability: [],
      calendar: calendar,
      now: date(18, 12))
    XCTAssertEqual(corrected.restingHeartRate.first?.value, 55)
    XCTAssertEqual(
      corrected.restingHeartRate.first?.latestIncludedSample.provenance.algorithmVersion, "v2")

    let deleted = calculator.calculate(
      restingHeartRate: [untouched],
      heartRateVariability: [],
      statuses: [],
      calendar: calendar,
      now: date(18, 12))
    XCTAssertEqual(deleted.restingHeartRate.map(\.date.iso8601String), ["2026-08-16"])
    XCTAssertFalse(deleted.restingHeartRate.contains { $0.date.iso8601String == "2026-08-14" })
    XCTAssertFalse(deleted.restingHeartRate.contains { $0.date.iso8601String == "2026-08-18" })
  }

  func testStaleFailureCoverageAndAlgorithmContextRemainVisibleAndNeutral() {
    let checkedAt = date(15, 12)
    let status = HealthStreamStatus(
      stream: .heartRateVariability,
      requested: true,
      authorization: .authorized,
      coverage: .limitedHistory,
      mirroredContent: .available,
      reconciliation: .idle,
      lastSuccessfulCheck: checkedAt,
      failure: .init(code: "hrv-refresh-failed", occurredAt: checkedAt.addingTimeInterval(1)))
    let observation = HealthRecoveryObservationCalculator().calculate(
      restingHeartRate: [],
      heartRateVariability: [
        hrv("one", day: 14, value: 42, algorithm: "v1"),
        hrv("two", day: 14, value: 44, algorithm: "v2")
      ],
      statuses: [status],
      calendar: calendar,
      now: date(16)
    ).heartRateVariability.first!

    XCTAssertFalse(observation.isCurrent)
    XCTAssertEqual(observation.coverage, .limitedHistory)
    XCTAssertEqual(observation.reconciliation, .idle)
    XCTAssertEqual(observation.lastSuccessfulReconciliation, checkedAt)
    XCTAssertEqual(observation.algorithmVersions, ["v1", "v2"])
    XCTAssertTrue(
      observation.explanation.missingData.contains(
        "Heart-rate variability (SDNN) stream failure: hrv-refresh-failed"))
    XCTAssertFalse(observation.explanation.text.localizedCaseInsensitiveContains("recovery"))
    XCTAssertFalse(observation.explanation.text.localizedCaseInsensitiveContains("stress"))
  }

  func testIncomparableSourceSuppressesOnlyThatDate() {
    let projection = HealthRecoveryObservationCalculator().calculate(
      restingHeartRate: [
        resting("good", day: 14, value: 52),
        resting("unknown", day: 15, value: 53, source: "com.phone"),
        HealthRestingHeartRateSample(
          id: "no-source", date: date(15, 9), beatsPerMinute: 54, provenance: .init()),
        resting("good-later", day: 16, value: 51)
      ],
      heartRateVariability: [],
      statuses: [],
      calendar: calendar,
      now: date(16)
    )

    XCTAssertEqual(
      projection.restingHeartRate.map(\.date.iso8601String), ["2026-08-14", "2026-08-16"])
    XCTAssertTrue(
      projection.explanation.missingData.contains(
        "Resting heart rate on 2026-08-15 has incomparable sources"))
  }

  func testSnapshotComposesIndependentStatusesWithoutBorrowingFreshness() {
    let now = date(16, 12)
    let currentCheck = date(16, 9)
    let staleCheck = date(15, 9)
    let snapshot = HealthRecoveryEvidenceSnapshot(
      restingHeartRate: [resting("resting", day: 16, value: 51)],
      heartRateVariability: [hrv("hrv", day: 16, value: 42)],
      statuses: [
        HealthStreamStatus(
          stream: .restingHeartRate,
          requested: true,
          authorization: .authorized,
          coverage: .available,
          mirroredContent: .available,
          lastSuccessfulCheck: currentCheck),
        HealthStreamStatus(
          stream: .heartRateVariability,
          requested: true,
          authorization: .authorized,
          coverage: .available,
          mirroredContent: .available,
          lastSuccessfulCheck: staleCheck)
      ])

    let projection = snapshot.dailyObservations(calendar: calendar, now: now)
    XCTAssertTrue(projection.restingHeartRate.first?.isCurrent == true)
    XCTAssertFalse(projection.heartRateVariability.first?.isCurrent == true)
    XCTAssertEqual(projection.statuses.map(\.stream), [.restingHeartRate, .heartRateVariability])
  }

  func testPersonalBaselinesUsePrimarySleepAndKeepEachMeasureIndependent() {
    let source = HealthRecoverySampleProvenance(
      sourceName: "Watch", sourceBundleIdentifier: "com.watch")
    var sleep: [HealthSleepSample] = (1...15).map { day in
      HealthSleepSample(
        id: "sleep-\(day)",
        startDate: date(day, 1),
        endDate: date(day, 7),
        provenance: source)
    }
    sleep.append(
      HealthSleepSample(
        id: "nap", startDate: date(14, 13), endDate: date(14, 14), provenance: source))
    sleep.append(
      HealthSleepSample(
        id: "sleep-current", startDate: date(29, 1), endDate: date(29, 9), provenance: source))

    let currentCheck = date(29, 12)
    let statuses = [
      HealthStreamStatus(
        stream: .sleep,
        requested: true,
        authorization: .authorized,
        coverage: .available,
        mirroredContent: .available,
        lastSuccessfulCheck: currentCheck),
      HealthStreamStatus(
        stream: .restingHeartRate,
        requested: true,
        authorization: .authorized,
        coverage: .available,
        mirroredContent: .available,
        lastSuccessfulCheck: currentCheck),
      HealthStreamStatus(
        stream: .heartRateVariability,
        requested: true,
        authorization: .authorized,
        coverage: .available,
        mirroredContent: .available,
        lastSuccessfulCheck: currentCheck)
    ]
    let snapshot = HealthRecoveryEvidenceSnapshot(
      sleep: sleep,
      restingHeartRate: (1...14).map {
        resting("rest-\($0)", day: $0, value: Double(50 + $0))
      } + [resting("rest-current", day: 29, value: 70)],
      heartRateVariability: (1...14).map {
        hrv("hrv-\($0)", day: $0, value: Double(30 + $0))
      } + [hrv("hrv-current", day: 29, value: 60)],
      statuses: statuses)

    let baselines = snapshot.personalRecoveryBaselines(
      calendar: calendar, asOfDate: TrainingDate(year: 2026, month: 8, day: 29), now: date(29, 12))
    XCTAssertEqual(baselines.baselines.count, 5)
    XCTAssertTrue(baselines.baseline(for: .primarySleepDuration)?.isEstablished == true)
    XCTAssertEqual(
      baselines.baseline(for: .primarySleepDuration)?.validObservationDays, 15)
    XCTAssertEqual(
      baselines.baseline(for: .primarySleepDuration)?.currentObservation?.value, 8 * 60 * 60)
    XCTAssertTrue(
      baselines.baseline(for: .primarySleepDuration)?.explanation.includedRecordIDs.contains("nap")
        == false)
    XCTAssertEqual(
      baselines.baseline(for: .restingHeartRate)?.differenceFromMedian, 12.5)
    XCTAssertEqual(
      baselines.baseline(for: .heartRateVariabilitySDNN)?.differenceFromMedian, 22.5)
    XCTAssertTrue(baselines.baseline(for: .sleepTimingConsistency)?.isEstablished == true)
    XCTAssertEqual(baselines.baseline(for: .sleepTimingConsistency)?.median, 0)
    XCTAssertTrue(
      baselines.baseline(for: .sleepTimingConsistency)?.explanation.sourceState.contains(
        "sleep-episodes-v1") == true)
    XCTAssertTrue(
      baselines.baseline(for: .primarySleepDuration)?.explanation.sourceCoverage.contains(
        "History available") == true)
    XCTAssertTrue(baselines.explanation.text.contains("no combined score"))

    let guidance = snapshot.recoveryGuidance(
      calendar: calendar,
      asOfDate: TrainingDate(year: 2026, month: 8, day: 29),
      now: date(29, 12))
    let beforeGuidance = snapshot
    XCTAssertTrue(guidance.isAvailable)
    XCTAssertEqual(guidance.establishedFamilies.count, 3)
    XCTAssertTrue(guidance.prompt?.contains("Consider how you feel") == true)
    XCTAssertEqual(snapshot, beforeGuidance)

    let failedStatuses = statuses.map { status in
      status.stream == .restingHeartRate
        ? HealthStreamStatus(
          stream: status.stream,
          requested: status.requested,
          authorization: status.authorization,
          coverage: status.coverage,
          mirroredContent: status.mirroredContent,
          reconciliation: status.reconciliation,
          lastSuccessfulCheck: status.lastSuccessfulCheck,
          failure: .init(code: "refresh-failed", occurredAt: date(29, 13)),
          attemptCount: status.attemptCount + 1)
        : status
    }
    let failedSnapshot = HealthRecoveryEvidenceSnapshot(
      sleep: sleep,
      restingHeartRate: snapshot.restingHeartRate,
      heartRateVariability: snapshot.heartRateVariability,
      statuses: failedStatuses)
    let failedGuidance = failedSnapshot.recoveryGuidance(
      calendar: calendar,
      asOfDate: TrainingDate(year: 2026, month: 8, day: 29),
      now: date(29, 12))
    XCTAssertFalse(failedGuidance.isAvailable)
    XCTAssertNil(failedGuidance.prompt)
    XCTAssertFalse(failedGuidance.measurements.isEmpty)
    XCTAssertFalse(failedSnapshot.sleep.isEmpty)
    XCTAssertFalse(failedSnapshot.heartRateVariability.isEmpty)

    let disabled = snapshot.recoveryGuidance(
      calendar: calendar,
      asOfDate: TrainingDate(year: 2026, month: 8, day: 29),
      now: date(29, 12),
      enabled: false)
    XCTAssertFalse(disabled.isAvailable)
    XCTAssertEqual(disabled.suppressionReason, .disabled)
    XCTAssertEqual(disabled.measurements.count, guidance.measurements.count)
  }
}
