import TrainingDomain
import XCTest

@testable import TrainingInsights

final class RollingWorkoutOverviewTests: XCTestCase {
  func testTrailingSevenDatesUseMedianOfFourPrecedingNonOverlappingPeriods() throws {
    let today = TrainingDate(year: 2026, month: 8, day: 15)
    let records = [
      record("current-start", date: today.adding(days: -6)),
      record("current-end", date: today),
      record("baseline-1", date: today.adding(days: -7)),
      record("baseline-2-a", date: today.adding(days: -14)),
      record("baseline-2-b", date: today.adding(days: -14)),
      record("baseline-3-a", date: today.adding(days: -21)),
      record("baseline-3-b", date: today.adding(days: -21)),
      record("baseline-3-c", date: today.adding(days: -21)),
      record("baseline-4-a", date: today.adding(days: -28)),
      record("baseline-4-b", date: today.adding(days: -28)),
      record("baseline-4-c", date: today.adding(days: -28)),
      record("baseline-4-d", date: today.adding(days: -34)),
      record("outside", date: today.adding(days: -35)),
    ]

    let overview = RollingWorkoutOverviewCalculator().calculate(
      records: records,
      asOf: today,
      coverage: .complete(lastReconciliation: "2026-08-15T00:00:00Z")
    )

    XCTAssertEqual(overview.currentWindow.start, today.adding(days: -6))
    XCTAssertEqual(overview.currentWindow.end, today)
    XCTAssertEqual(
      overview.currentWindow.displayName,
      "2026-08-09 through 2026-08-15")
    XCTAssertEqual(
      overview.comparisonWindows,
      [
        .init(start: today.adding(days: -13), end: today.adding(days: -7)),
        .init(start: today.adding(days: -20), end: today.adding(days: -14)),
        .init(start: today.adding(days: -27), end: today.adding(days: -21)),
        .init(start: today.adding(days: -34), end: today.adding(days: -28)),
      ])
    XCTAssertEqual(overview.workoutCount.currentValue, 2)
    XCTAssertEqual(overview.workoutCount.comparisonMedian, 2.5)
    XCTAssertTrue(overview.workoutCount.explanation.includedRecordIDs.contains("current-start"))
    XCTAssertTrue(overview.workoutCount.explanation.includedRecordIDs.contains("baseline-4-d"))
    XCTAssertTrue(
      overview.workoutCount.explanation.includedDates.contains("2026-08-09"))
    XCTAssertTrue(
      overview.workoutCount.explanation.dateRange.contains("Current: 2026-08-09 through 2026-08-15")
    )
    XCTAssertTrue(
      overview.workoutCount.explanation.exclusions.contains {
        $0.recordID == "outside" && $0.reason == "Outside the 35-date overview horizon"
      })
  }

  func testDurationMissingAffectsOnlyDurationAndActivityTypesStaySeparate() {
    let today = TrainingDate(year: 2026, month: 8, day: 15)
    let records = [
      record("run", date: today, activityType: "Running", durationSeconds: 1_800),
      record("ride", date: today, activityType: "Cycling", durationSeconds: nil),
      record(
        "strength", date: today, activityType: "Traditional Strength Training", durationSeconds: 900
      ),
      record("baseline-a", date: today.adding(days: -7), activityType: "Running"),
      record("baseline-b", date: today.adding(days: -14), activityType: "Running"),
      record("baseline-c", date: today.adding(days: -21), activityType: "Running"),
      record("baseline-d", date: today.adding(days: -28), activityType: "Running"),
      record(
        "baseline-missing", date: today.adding(days: -34), activityType: "Running",
        durationSeconds: nil),
    ]

    let overview = RollingWorkoutOverviewCalculator().calculate(
      records: records,
      asOf: today,
      coverage: .complete(lastReconciliation: "checked")
    )

    XCTAssertEqual(overview.workoutCount.currentValue, 3)
    XCTAssertEqual(overview.totalDuration.currentValue, 2_700)
    XCTAssertTrue(
      overview.totalDuration.explanation.missingData.contains("Duration missing for ride"))
    XCTAssertTrue(
      overview.totalDuration.explanation.missingData.contains(
        "Duration missing for baseline-missing"))
    XCTAssertEqual(
      overview.activityTypes.map { "\($0.activityType):\($0.metric.currentValue)" },
      ["Cycling:1.0", "Running:1.0", "Traditional Strength Training:1.0"])
    XCTAssertTrue(
      overview.activityTypes.allSatisfy {
        $0.metric.explanation.text.contains("without combining unlike activities")
      })
    XCTAssertTrue(
      overview.activityTypes.allSatisfy {
        $0.metric.explanation.question.contains($0.activityType)
      })
  }

  func testAvailableZoneTimesRemainSeparateAndShowCoverage() {
    let today = TrainingDate(year: 2026, month: 8, day: 15)
    let records = [
      record(
        "run", date: today, durationSeconds: 1_000,
        zoneTimes: .available([.below50: 10, .zone1: 20, .zone2: 30])),
      record(
        "ride", date: today, activityType: "Cycling", durationSeconds: 500,
        zoneTimes: .unavailable(reason: "Heart-rate samples unavailable")),
    ]

    let overview = RollingWorkoutOverviewCalculator().calculate(
      records: records,
      asOf: today,
      coverage: .complete(lastReconciliation: "checked")
    )

    XCTAssertEqual(overview.zoneMetrics.map(\.zone), [.below50, .zone1, .zone2])
    XCTAssertEqual(overview.zoneMetrics.first?.coveredSeconds, 10)
    XCTAssertEqual(overview.zoneMetrics.first?.coveredWorkoutDurationSeconds, 1_000)
    XCTAssertEqual(overview.zoneMetrics.first?.totalWorkoutDurationSeconds, 1_500)
    XCTAssertTrue(
      overview.zoneMetrics.first?.explanation.missingData.contains(where: { $0.contains("ride") })
        == true)
    XCTAssertNil(overview.zoneAvailabilityExplanation)
  }

  func testComparisonIsWithheldUntilCompleteHistoryButCurrentFactsRemainVisible() {
    let today = TrainingDate(year: 2026, month: 8, day: 15)
    let overview = RollingWorkoutOverviewCalculator().calculate(
      records: [record("current", date: today)],
      asOf: today,
      coverage: .incomplete(
        reason: "Health Workouts stream has not checked the complete comparison horizon")
    )

    XCTAssertEqual(overview.workoutCount.currentValue, 1)
    XCTAssertNil(overview.workoutCount.comparisonMedian)
    XCTAssertTrue(
      overview.workoutCount.explanation.text.contains("complete comparison horizon"))
  }

  func testInsightExplanationDecodesPreOverviewPayloads() throws {
    let data = Data(
      #"{"question":"How?","includedRecordIDs":[],"excludedRecords":[],"formula":"Epley","dateRange":"No included dates","roundingRule":"Full precision","sourceState":"Test"}"#
        .utf8)

    let explanation = try JSONDecoder().decode(InsightExplanation.self, from: data)

    XCTAssertEqual(explanation.includedDates, [])
    XCTAssertEqual(explanation.sourceCoverage, "Test")
    XCTAssertEqual(explanation.calculationRule, "Epley")
  }

  private func record(
    _ id: String,
    date: TrainingDate,
    activityType: String = "Running",
    durationSeconds: Double? = 1_800,
    zoneTimes: RollingWorkoutZoneTimeAvailability = .unavailable(
      reason: "Heart-Rate Zone projection unavailable")
  ) -> RollingWorkoutRecord {
    RollingWorkoutRecord(
      id: id,
      localDate: date,
      activityType: activityType,
      durationSeconds: durationSeconds,
      zoneTimes: zoneTimes)
  }
}
