import TrainingDomain
import XCTest

@testable import TrainingInsights

final class PersonalRecoveryBaselineTests: XCTestCase {
  private let asOf = TrainingDate(year: 2026, month: 8, day: 29)

  private func observation(
    _ id: String,
    day: Int,
    value: Double,
    source: String = "watch",
    current: Bool = false,
    comparable: Bool = true
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
      algorithmVersions: ["v1"],
      lastReconciliation: "2026-08-29T08:00:00Z",
      isCurrent: current)
  }

  func testThirteenDaysWithholdsAndFourteenDaysEstablishesFullPrecisionBand() {
    let thirteen = (1...13).map { observation("d\($0)", day: $0, value: Double($0)) }
    let calculator = PersonalRecoveryBaselineCalculator()
    let withheld = calculator.calculate(
      metric: .restingHeartRate, observations: thirteen, asOfDate: asOf)
    XCTAssertFalse(withheld.isEstablished)
    XCTAssertNil(withheld.median)
    XCTAssertTrue(
      withheld.explanation.missingData.contains(
        "Only 13 valid observation days; at least 14 are required"))

    let fourteen = thirteen + [observation("d14", day: 14, value: 14)]
    let established = calculator.calculate(
      metric: .restingHeartRate, observations: fourteen, asOfDate: asOf)
    XCTAssertTrue(established.isEstablished)
    XCTAssertEqual(established.median, 7.5)
    XCTAssertEqual(established.lowerQuartile, 4.25)
    XCTAssertEqual(established.upperQuartile, 10.75)
    XCTAssertEqual(established.validObservationDays, 14)
    XCTAssertEqual(established.algorithmVersions, ["v1"])
    XCTAssertTrue(established.explanation.sourceState.contains("Algorithm context: v1"))
  }

  func testWindowEdgesExcludeCurrentAndDayTwentyNineAndIgnoreMissingDays() {
    let values = [
      observation("edge", day: 1, value: 10),  // 28 days before as-of: included
      observation("inside", day: 2, value: 20),
      observation("current", day: 29, value: 30, current: true),
      observation("outside", day: 31, value: 999),  // outside the window
    ]
    let baseline = PersonalRecoveryBaselineCalculator().calculate(
      metric: .primarySleepDuration, observations: values, asOfDate: asOf, minimumObservationDays: 1
    )
    XCTAssertEqual(baseline.observations.map(\.id), ["edge", "inside"])
    XCTAssertNil(baseline.observations.first { $0.id == "current" })
    XCTAssertNil(baseline.observations.first { $0.id == "outside" })
    XCTAssertEqual(baseline.currentObservation?.id, "current")
    XCTAssertEqual(baseline.differenceFromMedian, 15)
  }

  func testBandBoundariesAreWithinAndCurrentNeedsFreshComparableSource() {
    let history = (1...4).map { observation("d\($0)", day: $0, value: Double($0)) }
    let currentAtLower = observation("current", day: 29, value: 1.75, current: true)
    let currentAtUpper = observation("current-upper", day: 29, value: 3.25, current: true)
    let calculator = PersonalRecoveryBaselineCalculator()
    let lower = calculator.calculate(
      metric: .heartRateVariabilitySDNN,
      observations: history + [currentAtLower], asOfDate: asOf, minimumObservationDays: 1)
    let upper = calculator.calculate(
      metric: .heartRateVariabilitySDNN,
      observations: history + [currentAtUpper], asOfDate: asOf, minimumObservationDays: 1)
    XCTAssertEqual(lower.comparison, .within)
    XCTAssertEqual(upper.comparison, .within)
    XCTAssertEqual(lower.neutralDirection, "lower")
    XCTAssertEqual(upper.neutralDirection, "higher")

    let stale = observation("stale", day: 29, value: 2, current: false)
    let incomparable = observation(
      "incomparable", day: 29, value: 2, current: true, comparable: false)
    let unavailable = calculator.calculate(
      metric: .heartRateVariabilitySDNN,
      observations: history + [stale, incomparable], asOfDate: asOf, minimumObservationDays: 1)
    XCTAssertEqual(unavailable.comparison, .unavailable)
    XCTAssertNil(unavailable.currentObservation)
  }

  func testSourceChangeIsExcludedAndCorrectionsReplaceOneDailyValue() {
    let original = observation("same", day: 1, value: 10)
    let corrected = observation("same", day: 1, value: 12)
    let oldSource = observation("old", day: 2, value: 20, source: "old-watch")
    let current = observation("current", day: 29, value: 14, source: "watch", current: true)
    let baseline = PersonalRecoveryBaselineCalculator().calculate(
      metric: .restingHeartRate,
      observations: [original, corrected, oldSource, current],
      asOfDate: asOf,
      minimumObservationDays: 1)
    XCTAssertEqual(baseline.observations.map(\.value), [12])
    XCTAssertTrue(
      baseline.excludedObservations.contains {
        $0.recordID == "old" && $0.reason.contains("Source changed")
      })
    XCTAssertTrue(
      baseline.excludedObservations.contains {
        $0.recordID == "same" && $0.reason.contains("Duplicate")
      })
  }

  func testCurrentComparisonIsUnavailableAfterLocalDayRollsOver() {
    let history = (1...14).map { observation("d\($0)", day: $0, value: Double($0)) }
    let current = observation("current", day: 29, value: 20, current: true)
    let calculator = PersonalRecoveryBaselineCalculator()
    let today = calculator.calculate(
      metric: .restingHeartRate,
      observations: history + [current],
      asOfDate: asOf)
    XCTAssertEqual(today.comparison, .above)

    let nextDay = calculator.calculate(
      metric: .restingHeartRate,
      observations: history + [current],
      asOfDate: asOf.adding(days: 1))
    XCTAssertEqual(nextDay.comparison, .unavailable)
    XCTAssertNil(nextDay.currentObservation)
  }
}
