import Foundation
import XCTest

@testable import TrainingApplication

final class RollingWorkoutOverviewBoundaryTests: XCTestCase {
  func testLinkedDuplicateAndDeletedWorkoutDoNotInflateCurrentFacts() async throws {
    let first = workout(id: "linked", localDate: "2026-08-15", duration: 1_000)
    let replacement = workout(id: "linked", localDate: "2026-08-15", duration: 1_200)
    let deleted = workout(id: "deleted", localDate: "2026-08-15", duration: 1_000)
    let repository = OverviewRepository(
      workouts: [first, replacement, deleted],
      deleted: ["deleted"],
      checkpoint: HealthSyncCheckpoint(
        stream: .workouts, anchor: "anchor", reconciliationContext: "complete"))
    let boundary = RollingWorkoutOverviewBoundary(
      repository: repository,
      clock: OverviewClock(),
      calendar: OverviewCalendar())

    let overview = try await boundary.overview(
      asOf: TrainingDate(year: 2026, month: 8, day: 15))

    XCTAssertEqual(overview.workoutCount.currentValue, 1)
    XCTAssertEqual(overview.totalDuration.currentValue, 1_200)
    XCTAssertEqual(overview.workoutCount.explanation.includedRecordIDs, ["linked"])
  }

  func testLateEnrichmentUpdatesZoneProjectionWithoutChangingWorkoutIdentity() async throws {
    let workout = workout(id: "late", localDate: "2026-08-15", duration: 1_000)
    let repository = OverviewRepository(
      workouts: [workout],
      checkpoint: HealthSyncCheckpoint(
        stream: .workouts, anchor: "anchor", reconciliationContext: "complete"))
    let provider = OverviewZoneProvider()
    let boundary = RollingWorkoutOverviewBoundary(
      repository: repository,
      clock: OverviewClock(),
      calendar: OverviewCalendar(),
      zoneProvider: provider)

    let before = try await boundary.overview(
      asOf: TrainingDate(year: 2026, month: 8, day: 15))
    XCTAssertTrue(before.zoneMetrics.isEmpty)

    await provider.set(.available([.zone3: 42]))
    let after = try await boundary.overview(
      asOf: TrainingDate(year: 2026, month: 8, day: 15))
    XCTAssertEqual(after.zoneMetrics.map(\.zone), [.zone3])
    XCTAssertEqual(after.zoneMetrics.first?.coveredSeconds, 42)
    XCTAssertEqual(after.workoutCount.currentValue, before.workoutCount.currentValue)
  }

  func testLimitedHistoryKeepsCurrentFactsAndWithholdsComparison() async throws {
    let repository = OverviewRepository(
      workouts: [workout(id: "limited", localDate: "2026-08-15", duration: 1_000)],
      checkpoint: HealthSyncCheckpoint(
        stream: .workouts,
        anchor: "anchor",
        hasLimitedHistory: true,
        reconciliationContext: "limited"))
    let boundary = RollingWorkoutOverviewBoundary(
      repository: repository,
      clock: OverviewClock(),
      calendar: OverviewCalendar())

    let overview = try await boundary.overview(
      asOf: TrainingDate(year: 2026, month: 8, day: 15))

    XCTAssertEqual(overview.workoutCount.currentValue, 1)
    XCTAssertNil(overview.workoutCount.comparisonMedian)
    XCTAssertTrue(overview.workoutCount.explanation.text.contains("limited history"))
  }

  private func workout(id: String, localDate: String, duration: TimeInterval) -> HealthWorkout {
    HealthWorkout(
      healthKitUUID: id,
      activityType: "Running",
      startDate: Date(timeIntervalSince1970: 1_755_206_400),
      endDate: Date(timeIntervalSince1970: 1_755_206_400 + duration),
      duration: duration,
      localDate: localDate,
      firstImportedAt: Date(timeIntervalSince1970: 10))
  }
}

private actor OverviewRepository: HealthWorkoutRepository {
  private var workouts: [HealthWorkout]
  private let deleted: [String]
  private let checkpoint: HealthSyncCheckpoint?

  init(
    workouts: [HealthWorkout],
    deleted: [String] = [],
    checkpoint: HealthSyncCheckpoint? = nil
  ) {
    self.workouts = workouts
    self.deleted = deleted
    self.checkpoint = checkpoint
  }

  func upsertHealthWorkouts(
    _ workouts: [HealthWorkout],
    reconciliationContext: String
  ) async throws {
    self.workouts = workouts
  }

  func loadHealthWorkouts() async throws -> [HealthWorkout] { workouts }

  func loadHealthWorkoutDeletionUUIDs() async throws -> [String] { deleted }

  func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws
    -> HealthSyncCheckpoint?
  { stream == .workouts ? checkpoint : nil }
}

private actor OverviewZoneProvider: RollingWorkoutZoneProjectionProviding {
  private var value: RollingWorkoutZoneTimeAvailability = .unavailable(reason: "not ready")

  func set(_ value: RollingWorkoutZoneTimeAvailability) { self.value = value }

  func zoneTimes(
    for workout: HealthWorkout,
    enrichment: HealthWorkoutEnrichment?
  ) async -> RollingWorkoutZoneTimeAvailability { value }
}

private struct OverviewClock: Clock {
  func now() -> Date { Date(timeIntervalSince1970: 1_755_206_400) }
}

private struct OverviewCalendar: CalendarProvider {
  func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }
}
