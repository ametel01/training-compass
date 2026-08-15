import TrainingDomain
import XCTest

@testable import TrainingInsights

final class RecoveryGuidanceTests: XCTestCase {
  private let asOf = TrainingDate(year: 2026, month: 8, day: 29)

  private func observation(
    _ id: String,
    day: Int,
    value: Double,
    current: Bool = false,
    source: String = "watch",
    comparable: Bool = true,
    missingData: [String] = [],
    corrected: Bool = false
  ) -> PersonalRecoveryBaselineObservation {
    PersonalRecoveryBaselineObservation(
      id: id,
      date: TrainingDate(year: 2026, month: 8, day: day),
      value: value,
      sourceID: source,
      sourceName: "Watch",
      sourceIsComparable: comparable,
      includedRecordIDs: [id],
      sourceCoverage: "Health history available",
      missingData: missingData,
      algorithmVersions: ["v1"],
      lastReconciliation: "2026-08-29T08:00:00Z",
      isCurrent: current,
      isCorrected: corrected)
  }

  private func established(
    _ metric: PersonalRecoveryBaselineMetric,
    currentValue: Double,
    current: Bool = true,
    source: String = "watch",
    comparable: Bool = true,
    missingData: [String] = [],
    corrected: Bool = false
  ) -> PersonalRecoveryBaseline {
    let history = (1...14).map {
      observation("\(metric.rawValue)-\($0)", day: $0, value: Double($0), source: source)
    }
    let currentObservation = observation(
      "\(metric.rawValue)-current",
      day: 29,
      value: currentValue,
      current: current,
      source: source,
      comparable: comparable,
      missingData: missingData,
      corrected: corrected)
    return PersonalRecoveryBaselineCalculator().calculate(
      metric: metric,
      observations: history + [currentObservation],
      asOfDate: asOf)
  }

  func testTwoIndependentFamiliesEnableNeutralSelfCheckAndKeepSleepMetricsOneFamily() {
    let baselines = PersonalRecoveryBaselineProjection(
      baselines: [
        established(.primarySleepDuration, currentValue: 20),
        established(.sleepDurationConsistency, currentValue: 20),
        established(.sleepTimingConsistency, currentValue: 20),
        established(.restingHeartRate, currentValue: 20),
      ],
      explanation: .init(
        question: "Which baselines are established?",
        includedRecordIDs: [],
        excludedRecords: [],
        formula: "Independent baselines",
        dateRange: asOf.iso8601String,
        roundingRule: "Full precision",
        sourceState: "Recorded"))

    let guidance = RecoveryGuidanceCalculator().calculate(baselines: baselines, asOfDate: asOf)

    XCTAssertTrue(guidance.isAvailable)
    XCTAssertEqual(guidance.establishedFamilies, [.primarySleep, .restingHeartRate])
    XCTAssertEqual(
      guidance.measurements.map(\.metric),
      [
        .primarySleepDuration,
        .sleepDurationConsistency,
        .sleepTimingConsistency,
        .restingHeartRate,
      ])
    XCTAssertTrue(guidance.prompt?.contains("Consider how you feel") == true)
    XCTAssertTrue(guidance.prompt?.contains("decide whether to keep or change the Session") == true)
    XCTAssertFalse(guidance.prompt?.localizedCaseInsensitiveContains("score") == true)
    XCTAssertFalse(guidance.prompt?.localizedCaseInsensitiveContains("readiness") == true)
  }

  func testConflictingMeasurementsSayTheyDoNotMoveTogether() {
    let baselines = PersonalRecoveryBaselineProjection(
      baselines: [
        established(.restingHeartRate, currentValue: 20),
        established(.heartRateVariabilitySDNN, currentValue: 0.5),
      ],
      explanation: .init(
        question: "Which baselines are established?", includedRecordIDs: [], excludedRecords: [],
        formula: "Independent baselines", dateRange: asOf.iso8601String,
        roundingRule: "Full precision", sourceState: "Recorded"))

    let guidance = RecoveryGuidanceCalculator().calculate(baselines: baselines, asOfDate: asOf)

    XCTAssertTrue(guidance.isAvailable)
    XCTAssertTrue(guidance.summary?.contains("do not move together") == true)
    XCTAssertTrue(guidance.summary?.contains("Resting heart rate") == true)
    XCTAssertTrue(guidance.summary?.contains("HRV SDNN") == true)
  }

  func testNeverBaselinedFamilyDoesNotBlockTwoOtherFamilies() {
    let baselines = PersonalRecoveryBaselineProjection(
      baselines: [
        established(.primarySleepDuration, currentValue: 10),
        established(.restingHeartRate, currentValue: 10),
        established(.heartRateVariabilitySDNN, currentValue: 10),
      ],
      explanation: .init(
        question: "Which baselines are established?", includedRecordIDs: [], excludedRecords: [],
        formula: "Independent baselines", dateRange: asOf.iso8601String,
        roundingRule: "Full precision", sourceState: "Recorded"))

    let formingSleep = PersonalRecoveryBaselineCalculator().calculate(
      metric: .sleepTimingConsistency,
      observations: (1...3).map {
        observation("timing-\($0)", day: $0, value: Double($0))
      },
      asOfDate: asOf)
    let projection = PersonalRecoveryBaselineProjection(
      baselines: baselines.baselines + [formingSleep], explanation: baselines.explanation)

    let guidance = RecoveryGuidanceCalculator().calculate(baselines: projection, asOfDate: asOf)

    XCTAssertTrue(guidance.isAvailable)
    XCTAssertFalse(guidance.measurements.contains { $0.metric == .sleepTimingConsistency })
  }

  func testFewerThanTwoEstablishedFamiliesWithholdThePrompt() {
    let onlyFamily = PersonalRecoveryBaselineProjection(
      baselines: [established(.restingHeartRate, currentValue: 10)],
      explanation: .init(
        question: "Which baselines are established?", includedRecordIDs: [], excludedRecords: [],
        formula: "Independent baselines", dateRange: asOf.iso8601String,
        roundingRule: "Full precision", sourceState: "Recorded"))

    let guidance = RecoveryGuidanceCalculator().calculate(
      baselines: onlyFamily, asOfDate: asOf)

    XCTAssertFalse(guidance.isAvailable)
    XCTAssertEqual(guidance.suppressionReason, .notEnoughEstablishedFamilies)
    XCTAssertNil(guidance.prompt)
  }

  func testMissingStaleFailedCorrectedIncomparableAndRolledOverFamiliesSuppressGuidance() {
    let missing = PersonalRecoveryBaselineCalculator().calculate(
      metric: .restingHeartRate,
      observations: (1...14).map {
        observation("restingHeartRate-\($0)", day: $0, value: Double($0))
      },
      asOfDate: asOf)
    let cases: [(String, PersonalRecoveryBaseline)] = [
      ("missing", missing),
      ("stale", established(.restingHeartRate, currentValue: 10, current: false)),
      (
        "failed",
        established(
          .restingHeartRate, currentValue: 10, missingData: ["Resting heart rate stream failure"])
      ),
      ("incomparable", established(.restingHeartRate, currentValue: 10, comparable: false)),
      ("corrected", established(.restingHeartRate, currentValue: 10, corrected: true)),
    ]

    for (label, invalid) in cases {
      let valid = established(.heartRateVariabilitySDNN, currentValue: 10)
      let projection = PersonalRecoveryBaselineProjection(
        baselines: [invalid, valid], explanation: valid.explanation)
      let guidance = RecoveryGuidanceCalculator().calculate(baselines: projection, asOfDate: asOf)
      XCTAssertFalse(guidance.isAvailable, label)
      XCTAssertNil(guidance.prompt, label)
      XCTAssertFalse(guidance.measurements.isEmpty, label)
    }

    let valid = established(.heartRateVariabilitySDNN, currentValue: 10)
    let rolledOver = established(.restingHeartRate, currentValue: 10)
    let projection = PersonalRecoveryBaselineProjection(
      baselines: [rolledOver, valid], explanation: valid.explanation)
    let nextDay = RecoveryGuidanceCalculator().calculate(
      baselines: projection, asOfDate: asOf.adding(days: 1))
    XCTAssertFalse(nextDay.isAvailable)
  }

  func testDisabledGuidancePreservesMeasurementsButEmitsNoPrompt() {
    let baselines = PersonalRecoveryBaselineProjection(
      baselines: [
        established(.restingHeartRate, currentValue: 10),
        established(.heartRateVariabilitySDNN, currentValue: 10),
      ],
      explanation: .init(
        question: "Which baselines are established?", includedRecordIDs: [], excludedRecords: [],
        formula: "Independent baselines", dateRange: asOf.iso8601String,
        roundingRule: "Full precision", sourceState: "Recorded"))

    let guidance = RecoveryGuidanceCalculator().calculate(
      baselines: baselines, asOfDate: asOf, enabled: false)

    XCTAssertFalse(guidance.isAvailable)
    XCTAssertEqual(guidance.suppressionReason, .disabled)
    XCTAssertNil(guidance.prompt)
    XCTAssertEqual(guidance.measurements.count, 2)
  }
}
