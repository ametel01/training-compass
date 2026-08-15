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

  func testRecoveryEvidenceUpsertsReplacesDeletesAndSurvivesRebuild() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-recovery-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let first = HealthRestingHeartRateSample(
      id: "rhr-1", date: Date(timeIntervalSince1970: 1_700_000_000), beatsPerMinute: 52,
      provenance: .init(sourceName: "Watch", algorithmVersion: "v1"))
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(
        workouts: [], anchor: "recovery-1", reconciliationContext: "rhr",
        restingHeartRateSamples: [first]),
      stream: .restingHeartRate,
      limits: .default)
    let replacement = HealthRestingHeartRateSample(
      id: first.id, date: first.date, beatsPerMinute: 54,
      provenance: first.provenance)
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(
        workouts: [], reconciliationContext: "rhr-replacement",
        restingHeartRateSamples: [replacement]),
      stream: .restingHeartRate,
      limits: .default)
    let loaded = try await repository.loadHealthRecoverySamples(for: .restingHeartRate)
    XCTAssertEqual(loaded, [.restingHeartRate(replacement)])
    let content = try await repository.loadHealthMirrorContent(for: .restingHeartRate)
    XCTAssertEqual(content.availability, .available)
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(
        workouts: [], reconciliationContext: "rhr-delete", deletedHealthKitUUIDs: [first.id]),
      stream: .restingHeartRate,
      limits: .default)
    let deleted = try await repository.loadHealthRecoverySamples(for: .restingHeartRate)
    XCTAssertTrue(deleted.isEmpty)
    try await repository.beginHealthRebuild()
    let rebuilt = try await repository.loadHealthRecoverySamples(for: .restingHeartRate)
    XCTAssertTrue(rebuilt.isEmpty)
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

  func testWorkoutEnrichmentUpsertsAcrossRestartAndWorkoutDeletionRemovesProjection()
    async throws
  {
    let root = FileManager.default.temporaryDirectory
      .appending(
        path: "training-health-enrichment-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let workout = workout(activity: "running", source: "Watch")
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [workout]), stream: .workouts, limits: .default)
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_900)
    let enrichment = HealthWorkoutEnrichment(
      healthKitUUID: workout.healthKitUUID,
      heartRate: .available(
        samples: [
          HealthWorkoutHeartRateSample(
            id: "sample",
            startDate: workout.startDate.addingTimeInterval(10),
            endDate: workout.startDate.addingTimeInterval(15),
            beatsPerMinute: 145,
            provenance: HealthSampleProvenance(
              sourceName: "Watch", sourceBundleIdentifier: "com.example.source"))
        ],
        checkedAt: checkedAt,
        reconciliationContext: "enrichment-success"
      ),
      distance: .available(
        value: 5_000, unit: .meters, checkedAt: checkedAt,
        reconciliationContext: "enrichment-success"),
      activeEnergy: .notAvailableFromHealth(
        checkedAt: checkedAt, reconciliationContext: "enrichment-success")
    )

    try await repository.saveHealthWorkoutEnrichment(enrichment)
    try await repository.saveHealthWorkoutEnrichment(enrichment)
    let restarted = GRDBTrainingRepository(root: root)
    let persisted = try await restarted.loadHealthWorkoutEnrichment(for: workout.healthKitUUID)
    XCTAssertEqual(persisted, enrichment)

    try await restarted.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [], deletedHealthKitUUIDs: [workout.healthKitUUID]),
      stream: .workouts,
      limits: .default
    )
    let deleted = try await restarted.loadHealthWorkoutEnrichment(for: workout.healthKitUUID)
    XCTAssertNil(deleted)
  }

  func testSimplifiedRoutePersistsReconstructiblyAndWorkoutDeletionRemovesIt() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-health-route-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let workout = workout(activity: "running", source: "Watch")
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [workout]), stream: .workouts, limits: .default)
    let route = HealthWorkoutRoute(
      healthKitUUID: workout.healthKitUUID,
      segments: [
        .init(
          source: .init(
            healthKitUUID: "route-source-uuid",
            provenance: .init(
              sourceName: "Watch", sourceBundleIdentifier: "com.example.source")),
          points: [
            .init(northSouthDegrees: 14.5995, eastWestDegrees: 120.9842),
            .init(northSouthDegrees: 14.6095, eastWestDegrees: 120.9942),
          ],
          originalPointCount: 6_000),
        .init(
          source: .init(
            healthKitUUID: "route-source-uuid-2",
            provenance: .init(
              sourceName: "Watch", sourceBundleIdentifier: "com.example.source")),
          points: [
            .init(northSouthDegrees: 14.6195, eastWestDegrees: 121.0042),
            .init(northSouthDegrees: 14.6295, eastWestDegrees: 121.0142),
          ],
          originalPointCount: 4_000),
      ],
      retainedAt: Date(timeIntervalSince1970: 1_700_000_900),
      simplification: .boundedDouglasPeuckerV1,
      reconciliationContext: "workout-route-query")

    let saved = try await repository.saveHealthWorkoutRoute(route)
    XCTAssertTrue(saved)
    let restarted = GRDBTrainingRepository(root: root)
    let persisted = try await restarted.loadHealthWorkoutRoute(for: workout.healthKitUUID)
    XCTAssertEqual(persisted, route)
    XCTAssertEqual(
      persisted?.segments.map(\.source.healthKitUUID),
      [
        "route-source-uuid", "route-source-uuid-2",
      ])

    try await restarted.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [], deletedHealthKitUUIDs: [workout.healthKitUUID]),
      stream: .workouts,
      limits: .default)

    let deleted = try await restarted.loadHealthWorkoutRoute(for: workout.healthKitUUID)
    XCTAssertNil(deleted)
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
    let mirroredWorkout = workout(activity: "running", source: "Watch")
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [mirroredWorkout], anchor: "old-anchor"),
      stream: .workouts,
      limits: .default
    )
    try await repository.saveHealthWorkoutEnrichment(
      HealthWorkoutEnrichment(
        healthKitUUID: mirroredWorkout.healthKitUUID,
        heartRate: .loading,
        distance: .loading,
        activeEnergy: .loading))
    let routeSaved = try await repository.saveHealthWorkoutRoute(
      HealthWorkoutRoute(
        healthKitUUID: mirroredWorkout.healthKitUUID,
        segments: [
          .init(
            source: .init(
              healthKitUUID: "route-source",
              provenance: .init(sourceBundleIdentifier: "com.example.watch")),
            points: [
              .init(northSouthDegrees: 14.5995, eastWestDegrees: 120.9842),
              .init(northSouthDegrees: 14.6005, eastWestDegrees: 120.9852),
            ],
            originalPointCount: 2)
        ],
        retainedAt: Date(timeIntervalSince1970: 1_700_000_900),
        simplification: .boundedDouglasPeuckerV1,
        reconciliationContext: "workout-route-query"))
    XCTAssertTrue(routeSaved)

    try await repository.beginHealthRebuild()
    let workouts = try await repository.loadHealthWorkouts()
    let enrichment = try await repository.loadHealthWorkoutEnrichment(
      for: mirroredWorkout.healthKitUUID)
    let checkpoint = try await repository.loadHealthSyncCheckpoint(for: .workouts)
    let route = try await repository.loadHealthWorkoutRoute(for: mirroredWorkout.healthKitUUID)
    let links = try await repository.loadHealthWorkoutLinkFacts(for: "returning-uuid")
    XCTAssertTrue(workouts.isEmpty)
    XCTAssertNil(enrichment)
    XCTAssertNil(checkpoint)
    XCTAssertNil(route)
    XCTAssertEqual(links, [link])
  }

  func testRunningComparisonExclusionIsAuthoritativeAndSurvivesRebuild() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(
        path: "training-running-exclusion-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    try await repository.saveRunningComparisonExclusion(healthKitUUID: "run-a")
    let restarted = GRDBTrainingRepository(root: root)
    let persisted = try await restarted.loadRunningComparisonExclusions()
    XCTAssertEqual(persisted, ["run-a"])

    try await restarted.beginHealthRebuild()
    let afterRebuild = try await restarted.loadRunningComparisonExclusions()
    XCTAssertEqual(afterRebuild, ["run-a"])

    try await restarted.saveRunningComparisonExclusion(healthKitUUID: "run-b")
    try await restarted.deleteRunningComparisonExclusion(healthKitUUID: "run-a")
    let afterRestore = try await restarted.loadRunningComparisonExclusions()
    XCTAssertEqual(afterRestore, ["run-b"])
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
