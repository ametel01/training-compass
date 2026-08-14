import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingDomain
@testable import TrainingPersistence

final class TrainingExportRepositoryTests: XCTestCase {
  func testExportSnapshotContainsEveryAuthoritativeTableAndStableRecordIdentity() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-export-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let lift = try LiftConfiguration(
      id: "lift-squat",
      identity: .progression(.squat),
      trainingMax: try TrainingMax(kg: 100)
    )
    _ = try await repository.saveLiftConfiguration(
      lift,
      expectedBefore: nil,
      auditID: "lift-audit",
      occurredAt: 10,
      action: .created
    )

    let snapshot = try await repository.loadAuthoritativeExportData()
    XCTAssertTrue(snapshot.table(named: "lifts")?.records.contains { $0.id == lift.id } == true)
    XCTAssertTrue(
      snapshot.table(named: "lift_configuration_audit")?.records.contains {
        $0.id == "lift-audit"
      } == true
    )
    XCTAssertTrue(snapshot.table(named: "gate_zero_metadata") != nil)
    XCTAssertNil(snapshot.table(named: "session_projections"))
    XCTAssertGreaterThanOrEqual(snapshot.recordCount, 3)
    let metadataID = try XCTUnwrap(snapshot.table(named: "gate_zero_metadata")?.records.first?.id)
    XCTAssertTrue(metadataID.hasPrefix("gate_zero_metadata#"))
  }

  func testAuthoritativeExportDoesNotIncludeReconstructibleRouteGeometry() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-export-route-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let workout = HealthWorkout(
      healthKitUUID: "workout-with-route",
      activityType: "running",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_600),
      duration: 600,
      localDate: "2023-11-14")
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [workout]), stream: .workouts, limits: .default)
    let routeSaved = try await repository.saveHealthWorkoutRoute(
      HealthWorkoutRoute(
        healthKitUUID: workout.healthKitUUID,
        segments: [
          .init(
            source: .init(
              healthKitUUID: "route-source",
              provenance: .init(sourceBundleIdentifier: "com.example.watch")),
            points: [
              .init(northSouthDegrees: 14.5995, eastWestDegrees: 120.9842),
              .init(northSouthDegrees: 14.6005, eastWestDegrees: 120.9852),
            ],
            originalPointCount: 20_000)
        ],
        retainedAt: Date(timeIntervalSince1970: 1_700_000_700),
        simplification: .boundedDouglasPeuckerV1,
        reconciliationContext: "workout-route-query"))
    XCTAssertTrue(routeSaved)

    let snapshot = try await repository.loadAuthoritativeExportData()

    XCTAssertNil(snapshot.table(named: "health_workout_routes"))
    XCTAssertFalse(
      snapshot.tables.contains { table in
        table.records.contains { record in
          record.fields.values.contains(.number(14.5995))
            || record.fields.values.contains(.number(120.9842))
        }
      })
  }
}
