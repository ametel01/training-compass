import Foundation
import XCTest

@testable import TrainingApplication

final class RunningPerformanceBoundaryTests: XCTestCase {
  func testBoundaryFiltersSourceActivityPreservesFactsAndDefaultsLatestImport() async throws {
    let first = workout(
      id: "first", activity: "Running", localDate: "2026-08-15",
      start: 1_000, imported: 10, environment: .outdoor)
    let ignored = workout(
      id: "ignored", activity: "Cycling", localDate: "2026-08-15",
      start: 2_000, imported: 30, environment: .indoor)
    let latestImport = workout(
      id: "latest", activity: "37", localDate: "2026-08-14",
      start: 900, imported: 20, environment: .treadmill)
    let repository = RunningRepository(
      workouts: [first, ignored, latestImport],
      enrichments: [
        "first": enrichment(for: first, distance: 5_000),
        "latest": enrichment(for: latestImport, distance: 4_000)
      ],
      routes: ["first"])
    let boundary = RunningPerformanceBoundary(
      repository: repository,
      clock: RunningClock(),
      calendar: RunningCalendar())

    let performance = try await boundary.runningPerformance(
      asOf: TrainingDate(year: 2026, month: 8, day: 15))

    XCTAssertEqual(performance.runs.map(\.id), ["first", "latest"])
    XCTAssertEqual(performance.selectedRunID, "latest")
    XCTAssertEqual(performance.selectedRun?.record.environment, .treadmill)
    XCTAssertEqual(performance.runs.first?.record.routeAvailability, .available)
    XCTAssertEqual(performance.runs.last?.record.routeAvailability, .unavailable)
    XCTAssertEqual(
      try XCTUnwrap(performance.runs.first?.averageRunningPace?.secondsPerKilometer),
      360,
      accuracy: 0.000001)
    XCTAssertTrue(performance.runs.first?.explanation.text.contains("first") == true)
  }

  private func workout(
    id: String,
    activity: String,
    localDate: String,
    start: TimeInterval,
    imported: TimeInterval,
    environment: RunningEnvironment
  ) -> HealthWorkout {
    HealthWorkout(
      healthKitUUID: id,
      activityType: activity,
      startDate: Date(timeIntervalSince1970: start),
      endDate: Date(timeIntervalSince1970: start + 1_800),
      duration: 1_800,
      sourceName: "Watch",
      localDate: localDate,
      timeZoneSource: .sourceMetadata,
      runningEnvironment: environment,
      firstImportedAt: Date(timeIntervalSince1970: imported),
      reconciliationContext: "checked")
  }

  private func enrichment(
    for workout: HealthWorkout,
    distance: Double
  ) -> HealthWorkoutEnrichment {
    HealthWorkoutEnrichment(
      healthKitUUID: workout.healthKitUUID,
      heartRate: .available(
        samples: [
          HealthWorkoutHeartRateSample(
            id: "sample-\(workout.id)", startDate: workout.startDate,
            endDate: workout.endDate, beatsPerMinute: 150,
            provenance: HealthSampleProvenance(sourceName: "Watch"))
        ], checkedAt: workout.endDate, reconciliationContext: "checked"),
      distance: .available(
        value: distance, unit: .meters, provenance: HealthSampleProvenance(sourceName: "Watch"),
        checkedAt: workout.endDate, reconciliationContext: "checked"),
      activeEnergy: .notAvailableFromHealth(
        checkedAt: workout.endDate, reconciliationContext: "checked"))
  }
}

private struct RunningClock: Clock {
  func now() -> Date { Date(timeIntervalSince1970: 1_755_206_400) }
}

private struct RunningCalendar: CalendarProvider {
  func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

private actor RunningRepository: HealthWorkoutRepository, HealthWorkoutRouteRepository {
  let workouts: [HealthWorkout]
  let enrichments: [String: HealthWorkoutEnrichment]
  let routes: Set<String>

  init(
    workouts: [HealthWorkout],
    enrichments: [String: HealthWorkoutEnrichment],
    routes: Set<String> = []
  ) {
    self.workouts = workouts
    self.enrichments = enrichments
    self.routes = routes
  }

  func upsertHealthWorkouts(_ workouts: [HealthWorkout], reconciliationContext: String) async throws {}
  func loadHealthWorkouts() async throws -> [HealthWorkout] { workouts }
  func loadHealthWorkoutDeletionUUIDs() async throws -> [String] { [] }
  func loadHealthWorkoutEnrichment(for healthKitUUID: String) async throws
    -> HealthWorkoutEnrichment? {
    enrichments[healthKitUUID]
  }
  func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws -> HealthSyncCheckpoint? {
    HealthSyncCheckpoint(stream: stream, anchor: "anchor", reconciliationContext: "checked")
  }
  func saveHealthWorkoutRoute(_ route: HealthWorkoutRoute) async throws -> Bool { true }
  func loadHealthWorkoutRoute(for healthKitUUID: String) async throws -> HealthWorkoutRoute? {
    routes.contains(healthKitUUID) ? route(healthKitUUID) : nil
  }

  private func route(_ id: String) -> HealthWorkoutRoute {
    HealthWorkoutRoute(
      healthKitUUID: id,
      segments: [
        HealthWorkoutRouteSegment(
          source: HealthWorkoutRouteSource(healthKitUUID: "route-\(id)", provenance: .init()),
          points: [
            HealthWorkoutRoutePoint(northSouthDegrees: 0, eastWestDegrees: 0),
            HealthWorkoutRoutePoint(northSouthDegrees: 1, eastWestDegrees: 1)
          ], originalPointCount: 2)
      ], retainedAt: Date(timeIntervalSince1970: 1),
      simplification: .boundedDouglasPeuckerV1, reconciliationContext: "checked")
  }
}
