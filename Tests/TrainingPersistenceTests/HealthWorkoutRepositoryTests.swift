import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingPersistence

final class HealthWorkoutRepositoryTests: XCTestCase {
  func testHealthWorkoutUpsertIsStableAcrossReplacementAndRestart() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-health-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let first = HealthWorkout(
      healthKitUUID: "health-uuid",
      activityType: "running",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_300),
      duration: 300,
      sourceName: "Watch",
      sourceBundleIdentifier: "com.example.source",
      sourceTimeZoneIdentifier: "UTC",
      localDate: "2023-11-14",
      timeZoneSource: .deviceAtFirstImport,
      firstImportedAt: Date(timeIntervalSince1970: 1_700_000_500),
      reconciliationContext: "initial"
    )
    try await repository.upsertHealthWorkouts([first], reconciliationContext: "initial")

    let replacement = HealthWorkout(
      healthKitUUID: first.healthKitUUID,
      activityType: "traditional-strength-training",
      startDate: first.startDate,
      endDate: first.endDate,
      duration: first.duration,
      sourceName: "Watch",
      sourceBundleIdentifier: first.sourceBundleIdentifier,
      sourceProductType: first.sourceProductType,
      sourceTimeZoneIdentifier: first.sourceTimeZoneIdentifier,
      localDate: first.localDate,
      timeZoneSource: first.timeZoneSource,
      firstImportedAt: first.firstImportedAt,
      reconciliationContext: "replacement"
    )
    try await repository.upsertHealthWorkouts(
      [replacement, replacement], reconciliationContext: "replacement")
    let loaded = try await repository.loadHealthWorkouts()
    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded.first?.activityType, "traditional-strength-training")
    XCTAssertEqual(loaded.first?.reconciliationContext, "replacement")

    let restarted = GRDBTrainingRepository(root: root)
    let afterRestart = try await restarted.loadHealthWorkouts()
    XCTAssertEqual(afterRestart, loaded)
  }

  func testAnchoredPageCommitDeletesAndCheckpointsAtomically() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-health-sync-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let first = HealthWorkout(
      healthKitUUID: "health-uuid",
      activityType: "running",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_300),
      duration: 300,
      sourceName: "Watch",
      sourceBundleIdentifier: "com.example.source",
      sourceTimeZoneIdentifier: "UTC",
      localDate: "2023-11-14",
      timeZoneSource: .deviceAtFirstImport,
      firstImportedAt: Date(timeIntervalSince1970: 1_700_000_500),
      reconciliationContext: "initial"
    )
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [first], nextPageToken: "anchor-1"),
      stream: .workouts,
      limits: .default
    )
    let firstCheckpoint = try await repository.loadHealthSyncCheckpoint(for: .workouts)
    XCTAssertEqual(firstCheckpoint?.anchor, "anchor-1")

    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(
        workouts: [],
        reconciliationContext: "observer",
        deletedHealthKitUUIDs: [first.healthKitUUID]
      ),
      stream: .workouts,
      limits: .default
    )
    let loaded = try await repository.loadHealthWorkouts()
    let finalCheckpoint = try await repository.loadHealthSyncCheckpoint(for: .workouts)
    XCTAssertTrue(loaded.isEmpty)
    XCTAssertNil(finalCheckpoint?.anchor)
  }

  func testDeviceTimezoneDateRemainsStableAcrossFallbackReplacement() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-health-date-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let first = HealthWorkout(
      healthKitUUID: "health-uuid",
      activityType: "running",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_300),
      duration: 300,
      sourceName: "Watch",
      sourceBundleIdentifier: "com.example.source",
      sourceTimeZoneIdentifier: "UTC",
      localDate: "2023-11-14",
      timeZoneSource: .deviceAtFirstImport,
      firstImportedAt: Date(timeIntervalSince1970: 1_700_000_500),
      reconciliationContext: "initial"
    )
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [first]), stream: .workouts, limits: .default)

    let fallbackReplacement = HealthWorkout(
      healthKitUUID: first.healthKitUUID,
      activityType: "cycling",
      startDate: first.startDate,
      endDate: first.endDate,
      duration: first.duration,
      sourceName: first.sourceName,
      sourceBundleIdentifier: first.sourceBundleIdentifier,
      sourceTimeZoneIdentifier: "America/Los_Angeles",
      localDate: "2023-11-13",
      timeZoneSource: .deviceAtFirstImport,
      firstImportedAt: first.firstImportedAt,
      reconciliationContext: "device-timezone-changed"
    )
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [fallbackReplacement]), stream: .workouts, limits: .default)

    let loaded = try await repository.loadHealthWorkouts()
    XCTAssertEqual(loaded.first?.activityType, "cycling")
    XCTAssertEqual(loaded.first?.localDate, first.localDate)
    XCTAssertEqual(loaded.first?.sourceTimeZoneIdentifier, first.sourceTimeZoneIdentifier)
    XCTAssertEqual(loaded.first?.timeZoneSource, .deviceAtFirstImport)
  }

  func testDeepRebuildClearsReconstructibleStateButRetainsAuthoritativeHealthLinkFacts()
    async throws
  {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-health-rebuild-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let link = HealthWorkoutLinkFact(
      id: "link-1", healthKitUUID: "returning-uuid", localEntityKind: .session,
      localEntityID: "session-1", linkedAt: Date(timeIntervalSince1970: 1_700_000_000))
    try await repository.saveHealthWorkoutLinkFact(link)
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(
        workouts: [workout(activity: "running", source: "Watch")], anchor: "old-anchor"),
      stream: .workouts,
      limits: .default
    )

    try await repository.beginHealthRebuild()
    let workouts = try await repository.loadHealthWorkouts()
    let checkpoint = try await repository.loadHealthSyncCheckpoint(for: .workouts)
    let links = try await repository.loadHealthWorkoutLinkFacts(for: "returning-uuid")
    XCTAssertTrue(workouts.isEmpty)
    XCTAssertNil(checkpoint)
    XCTAssertEqual(links, [link])
  }

  private func workout(activity: String, source: String) -> HealthWorkout {
    HealthWorkout(
      healthKitUUID: "health-uuid",
      activityType: activity,
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_300),
      duration: 300,
      sourceName: source,
      sourceBundleIdentifier: "com.example.source",
      sourceProductType: "Watch",
      sourceTimeZoneIdentifier: "UTC",
      localDate: "2023-11-14",
      timeZoneSource: .sourceMetadata,
      firstImportedAt: Date(timeIntervalSince1970: 1_700_000_500),
      reconciliationContext: "initial"
    )
  }
}
