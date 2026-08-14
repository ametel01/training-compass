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

  private func record(
    _ id: String,
    date: TrainingDate,
    duration: Double?,
    distance: Double?,
    importedAt: Double? = nil
  ) -> RunningWorkoutRecord {
    RunningWorkoutRecord(
      id: id,
      localDate: date,
      startDate: importedAt ?? 1,
      durationSeconds: duration,
      distanceMeters: distance,
      environment: .unspecified,
      importedAt: importedAt)
  }
}
