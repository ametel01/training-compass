import TrainingDomain
import XCTest

@testable import TrainingInsights

final class RunningPerformanceTests: XCTestCase {
  func testOnlySourceClassifiedActivityIsAcceptedAndPaceUsesFullPrecision() throws {
    XCTAssertTrue(RunningWorkoutRecord.isSourceClassifiedRunning(activityType: "Running"))
    XCTAssertTrue(RunningWorkoutRecord.isSourceClassifiedRunning(activityType: "37"))
    XCTAssertFalse(RunningWorkoutRecord.isSourceClassifiedRunning(activityType: "Walking"))

    let pace = try XCTUnwrap(
      RunningPace(durationSeconds: 1_500, distanceMeters: 5_000.25))
    XCTAssertEqual(pace.secondsPerKilometer, 299.9850007499375, accuracy: 0.0000001)
    XCTAssertEqual(pace.displayValue, "5:00 min/km")
    XCTAssertNil(RunningPace(durationSeconds: 0, distanceMeters: 5_000))
    XCTAssertNil(RunningPace(durationSeconds: 1_500, distanceMeters: 0))
  }

  func testRunningVolumeCountsEveryRunButSumsOnlyPositiveFacts() {
    let today = TrainingDate(year: 2026, month: 8, day: 15)
    let records = [
      record("current-complete", date: today, duration: 1_000, distance: 5_000),
      record("current-no-distance", date: today.adding(days: -1), duration: 900, distance: nil),
      record("current-no-duration", date: today.adding(days: -2), duration: nil, distance: 4_000),
      record("baseline-a", date: today.adding(days: -7), duration: 100, distance: 1_000),
      record("baseline-b", date: today.adding(days: -14), duration: 200, distance: 2_000),
      record("baseline-c", date: today.adding(days: -21), duration: 300, distance: 3_000),
      record("baseline-d", date: today.adding(days: -28), duration: 400, distance: 4_000),
    ]

    let volume = RunningVolumeCalculator().calculate(
      records: records,
      asOf: today,
      sourceCoverage: "Health Workouts: History available",
      lastReconciliation: "checked")

    XCTAssertEqual(volume.count.currentValue, 3)
    XCTAssertEqual(volume.availableDuration.currentValue, 1_900)
    XCTAssertEqual(volume.availableDistance.currentValue, 9_000)
    XCTAssertEqual(volume.count.comparisonMedian, 1)
    XCTAssertEqual(volume.availableDuration.comparisonMedian, 250)
    XCTAssertEqual(volume.availableDistance.comparisonMedian, 2_500)
    XCTAssertTrue(volume.count.explanation.includedRecordIDs.contains("current-complete"))
    XCTAssertTrue(
      volume.availableDuration.explanation.missingData.contains(
        "Duration unavailable for current-no-duration"))
    XCTAssertTrue(
      volume.availableDistance.explanation.missingData.contains(
        "Distance unavailable for current-no-distance"))
    XCTAssertEqual(volume.count.explanation.lastReconciliation, "checked")
  }

  func testLatestImportedRunIsSelectedAndEnvironmentIsNotChanged() {
    let date = TrainingDate(year: 2026, month: 8, day: 15)
    let records = [
      record("later-date", date: date, duration: 900, distance: 3_000, importedAt: 10),
      record(
        "latest-import", date: date.adding(days: -1), duration: 900, distance: 3_000, importedAt: 20
      ),
    ]
    let performance = RunningPerformanceCalculator().calculate(
      records: records,
      asOf: date,
      sourceCoverage: "Health Workouts: History available")

    XCTAssertEqual(performance.selectedRunID, "latest-import")
    XCTAssertEqual(performance.runs.map(\.id), ["latest-import", "later-date"])
    XCTAssertEqual(records.first?.environment, .unspecified)
  }

  func testComparableRunsMatchEnvironmentAndInclusiveFivePercentDistance() {
    let date = TrainingDate(year: 2026, month: 8, day: 15)
    let heartRate = RunningHeartRateContext(
      averageBeatsPerMinute: 150, coveredSeconds: 480, workoutDurationSeconds: 600,
      source: "Watch")
    let reference = record(
      "reference", date: date, duration: 600, distance: 10_000, importedAt: 50, start: 5_000,
      environment: .outdoor, heartRate: heartRate)
    let inclusive = record(
      "inclusive", date: date.adding(days: -1), duration: 620, distance: 9_500, importedAt: 40,
      start: 4_000, environment: .outdoor, heartRate: heartRate)
    let wrongEnvironment = record(
      "wrong-environment", date: date.adding(days: -2), duration: 600, distance: 10_000,
      importedAt: 30,
      start: 3_000, environment: .treadmill, heartRate: heartRate)
    let outsideTolerance = record(
      "outside-tolerance", date: date.adding(days: -3), duration: 600, distance: 9_499,
      importedAt: 20, start: 2_000, environment: .outdoor, heartRate: heartRate)
    let performance = RunningPerformanceCalculator().calculate(
      records: [reference, inclusive, wrongEnvironment, outsideTolerance],
      asOf: date,
      sourceCoverage: "available")

    XCTAssertEqual(performance.comparison?.precedingComparableRunID, "inclusive")
    XCTAssertEqual(performance.comparison?.precedingFourComparableRunIDs, ["inclusive"])
    XCTAssertEqual(performance.comparison?.pace.direction, .faster)
    XCTAssertEqual(performance.comparison?.duration.direction, .lower)
    XCTAssertEqual(performance.comparison?.distance.direction, .higher)
  }

  func testFourRunMedianRequiresAllFourAndExclusionIsTrendOnly() {
    let date = TrainingDate(year: 2026, month: 8, day: 15)
    let runs = (0..<5).map { index in
      let id = index == 0 ? "reference" : "prior-\(index)"
      return record(
        id,
        date: date.adding(days: -index),
        duration: 600 + Double(index),
        distance: 10_000,
        importedAt: Double(100 - index),
        start: 10_000 - Double(index),
        environment: .unspecified)
    }
    let performance = RunningPerformanceCalculator().calculate(
      records: runs,
      asOf: date,
      sourceCoverage: "available")
    XCTAssertEqual(performance.comparison?.precedingFourComparableRunIDs.count, 4)
    XCTAssertNotNil(performance.comparison?.baseline)
    XCTAssertNotNil(performance.comparison?.medianDuration)
    XCTAssertEqual(performance.runs.count, 5)
    let excluded = RunningPerformanceCalculator().calculate(
      records: runs,
      asOf: date,
      sourceCoverage: "available",
      excludedRunIDs: ["prior-1"])
    XCTAssertEqual(excluded.runs.count, 5)
    XCTAssertEqual(excluded.comparison?.precedingComparableRunID, "prior-2")
  }

  private func record(
    _ id: String,
    date: TrainingDate,
    duration: Double?,
    distance: Double?,
    importedAt: Double? = nil,
    start: Double? = nil,
    environment: RunningEnvironment = .unspecified,
    heartRate: RunningHeartRateContext = .unavailable(reason: "unavailable")
  ) -> RunningWorkoutRecord {
    RunningWorkoutRecord(
      id: id,
      localDate: date,
      startDate: start ?? importedAt ?? 1,
      durationSeconds: duration,
      distanceMeters: distance,
      environment: environment,
      heartRate: heartRate,
      importedAt: importedAt)
  }
}
