import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingPersistence

final class TrainingEventLinkRepositoryTests: XCTestCase {
  func testLinkIsDurableAndRejectsASecondActiveLinkForEitherStableIdentity() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-event-link-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveTrainingCycle(
      makeLinkingCycle(),
      expectedBefore: nil,
      auditID: "cycle",
      occurredAt: 10,
      action: .activated
    )
    _ = try await repository.completeSession(
      CompletedSession(sessionID: "session-1", confirmedAt: 20),
      confirmation: .confirmed
    )
    _ = try await repository.completeSession(
      CompletedSession(sessionID: "session-2", confirmedAt: 21),
      confirmation: .confirmed
    )
    let workout1 = linkWorkout(id: "health-1", start: 100)
    let workout2 = linkWorkout(id: "health-2", start: 200)
    try await repository.upsertHealthWorkouts(
      [workout1, workout2],
      reconciliationContext: "initial"
    )
    let session1Snapshot = try await repository.loadSessionCorrectionSnapshot(
      sessionID: "session-1")
    let session2Snapshot = try await repository.loadSessionCorrectionSnapshot(
      sessionID: "session-2")
    let session1Version = try XCTUnwrap(session1Snapshot).updatedAt
    let session2Version = try XCTUnwrap(session2Snapshot).updatedAt
    let storedWorkouts = try await repository.loadHealthWorkouts()
    let storedWorkout1 = try XCTUnwrap(
      storedWorkouts.first(where: { $0.healthKitUUID == workout1.healthKitUUID }))
    let storedWorkout2 = try XCTUnwrap(
      storedWorkouts.first(where: { $0.healthKitUUID == workout2.healthKitUUID }))
    let link = HealthWorkoutLinkFact(
      id: "link-1",
      healthKitUUID: workout1.healthKitUUID,
      localEntityKind: .session,
      localEntityID: "session-1",
      linkedAt: Date(timeIntervalSince1970: 30)
    )

    let saved = try await repository.createHealthWorkoutLinkFact(
      link,
      expectedSessionUpdatedAt: session1Version,
      expectedWorkout: storedWorkout1
    )
    XCTAssertEqual(saved, link)

    do {
      _ = try await repository.createHealthWorkoutLinkFact(
        HealthWorkoutLinkFact(
          id: "same-session",
          healthKitUUID: workout2.healthKitUUID,
          localEntityKind: .session,
          localEntityID: "session-1"
        ),
        expectedSessionUpdatedAt: session1Version,
        expectedWorkout: storedWorkout2
      )
      XCTFail("A Completed Session may have only one active external-workout link")
    } catch {
      XCTAssertEqual(error as? TrainingEventLinkRepositoryError, .duplicateLink)
    }

    do {
      _ = try await repository.createHealthWorkoutLinkFact(
        HealthWorkoutLinkFact(
          id: "same-workout",
          healthKitUUID: workout1.healthKitUUID,
          localEntityKind: .session,
          localEntityID: "session-2"
        ),
        expectedSessionUpdatedAt: session2Version,
        expectedWorkout: storedWorkout1
      )
      XCTFail("A HealthKit UUID may have only one active Session link")
    } catch {
      XCTAssertEqual(error as? TrainingEventLinkRepositoryError, .duplicateLink)
    }

    let restarted = GRDBTrainingRepository(root: root)
    let durable = try await restarted.loadHealthWorkoutLinkFacts(for: nil)
    XCTAssertEqual(durable, [link])

    let unlinked = try await restarted.unlinkHealthWorkoutLinkFact(
      id: link.id,
      expectedLinkedAt: link.linkedAt,
      unlinkedAt: Date(timeIntervalSince1970: 40)
    )
    XCTAssertFalse(unlinked.isActive)
    let restartedWorkouts = try await restarted.loadHealthWorkouts()
    let currentWorkout = try XCTUnwrap(restartedWorkouts.first)
    let relinked = HealthWorkoutLinkFact(
      id: "link-2",
      healthKitUUID: workout1.healthKitUUID,
      localEntityKind: .session,
      localEntityID: "session-1",
      linkedAt: Date(timeIntervalSince1970: 50)
    )
    _ = try await restarted.createHealthWorkoutLinkFact(
      relinked,
      expectedSessionUpdatedAt: session1Version,
      expectedWorkout: currentWorkout
    )
    let history = try await restarted.loadHealthWorkoutLinkFacts(for: workout1.healthKitUUID)
    XCTAssertEqual(history, [unlinked, relinked])
  }

  func testCompletionWithExternalLinkAtomicallyRecordsWriteBackSuppression() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(
        path: "training-event-completion-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveTrainingCycle(
      makeLinkingCycle(),
      expectedBefore: nil,
      auditID: "cycle",
      occurredAt: 10,
      action: .activated
    )
    let workout = linkWorkout(id: "health-completion", start: 100)
    try await repository.upsertHealthWorkouts([workout], reconciliationContext: "initial")
    let loadedWorkouts = try await repository.loadHealthWorkouts()
    let storedWorkout = try XCTUnwrap(loadedWorkouts.first)
    let beforeValue = try await repository.loadSessionCorrectionSnapshot(sessionID: "session-1")
    let before = try XCTUnwrap(beforeValue)
    let completion = CompletedSession(sessionID: "session-1", confirmedAt: 20)
    let link = HealthWorkoutLinkFact(
      id: "completion-link",
      healthKitUUID: workout.healthKitUUID,
      localEntityKind: .session,
      localEntityID: "session-1",
      linkedAt: Date(timeIntervalSince1970: 20),
      linkedDuringCompletion: true,
      writeBackDisposition: .suppressedExternalWorkoutLinkedAtCompletion
    )

    let result = try await repository.completeSessionAndCreateHealthWorkoutLinkFact(
      completion: completion,
      fact: link,
      expectedSessionUpdatedAt: before.updatedAt,
      expectedWorkout: storedWorkout
    )

    XCTAssertEqual(result.completion, completion)
    XCTAssertEqual(result.link, link)
    let restarted = GRDBTrainingRepository(root: root)
    let durableCompletion = try await restarted.loadCompletedSession(sessionID: "session-1")
    let durableLinks = try await restarted.loadHealthWorkoutLinkFacts(for: nil)
    XCTAssertEqual(durableCompletion, completion)
    XCTAssertEqual(durableLinks, [link])
  }

  func testMissingExternalWorkoutBecomesHistoryWhenOwnerChoosesReplacement() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(
        path: "training-event-replacement-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveTrainingCycle(
      makeLinkingCycle(), expectedBefore: nil, auditID: "cycle", occurredAt: 10,
      action: .activated)
    _ = try await repository.completeSession(
      CompletedSession(sessionID: "session-1", confirmedAt: 20), confirmation: .confirmed)
    let oldWorkout = linkWorkout(id: "old-health", start: 100)
    let replacementWorkout = linkWorkout(id: "replacement-health", start: 200)
    try await repository.upsertHealthWorkouts(
      [oldWorkout, replacementWorkout], reconciliationContext: "initial")
    let storedWorkouts = try await repository.loadHealthWorkouts()
    let storedOld = try XCTUnwrap(
      storedWorkouts.first(where: { $0.healthKitUUID == oldWorkout.healthKitUUID }))
    let storedReplacement = try XCTUnwrap(
      storedWorkouts.first(where: { $0.healthKitUUID == replacementWorkout.healthKitUUID }))
    let sessionValue = try await repository.loadSessionCorrectionSnapshot(sessionID: "session-1")
    let session = try XCTUnwrap(sessionValue)
    let formerLink = HealthWorkoutLinkFact(
      id: "former-link", healthKitUUID: oldWorkout.healthKitUUID, localEntityKind: .session,
      localEntityID: "session-1", linkedAt: Date(timeIntervalSince1970: 30))
    _ = try await repository.createHealthWorkoutLinkFact(
      formerLink, expectedSessionUpdatedAt: session.updatedAt, expectedWorkout: storedOld)
    try await repository.commitHealthWorkoutPage(
      HealthWorkoutPage(workouts: [], deletedHealthKitUUIDs: [oldWorkout.healthKitUUID]),
      stream: .workouts,
      limits: .default
    )
    let replacementLink = HealthWorkoutLinkFact(
      id: "replacement-link", healthKitUUID: replacementWorkout.healthKitUUID,
      localEntityKind: .session, localEntityID: "session-1",
      linkedAt: Date(timeIntervalSince1970: 40))

    _ = try await repository.createHealthWorkoutLinkFact(
      replacementLink,
      expectedSessionUpdatedAt: session.updatedAt,
      expectedWorkout: storedReplacement
    )
    let history = try await repository.loadHealthWorkoutLinkFacts(for: nil)

    XCTAssertEqual(history.count, 2)
    XCTAssertEqual(history[0].id, formerLink.id)
    XCTAssertEqual(history[0].unlinkedAt, replacementLink.linkedAt)
    XCTAssertEqual(history[1], replacementLink)
  }

  func testV12LinkArchiveRestoresWithExplicitV13Defaults() async throws {
    let sourceRoot = FileManager.default.temporaryDirectory
      .appending(
        path: "training-event-v12-source-\(UUID().uuidString)", directoryHint: .isDirectory)
    let destinationRoot = FileManager.default.temporaryDirectory
      .appending(
        path: "training-event-v12-destination-\(UUID().uuidString)",
        directoryHint: .isDirectory
      )
    defer {
      try? FileManager.default.removeItem(at: sourceRoot)
      try? FileManager.default.removeItem(at: destinationRoot)
    }
    let source = GRDBTrainingRepository(root: sourceRoot)
    for lift in [
      try LiftConfiguration(
        id: "squat", identity: .progression(.squat), trainingMaxKg: 100,
        loadingIncrementKg: 2.5),
      try LiftConfiguration(
        id: "bench", identity: .progression(.benchPress), trainingMaxKg: 75,
        loadingIncrementKg: 2.5),
    ] {
      _ = try await source.saveLiftConfiguration(
        lift, expectedBefore: nil, auditID: "audit-\(lift.id)", occurredAt: 1,
        action: .created)
    }
    _ = try await source.saveTrainingCycle(
      makeLinkingCycle(), expectedBefore: nil, auditID: "cycle", occurredAt: 10,
      action: .activated)
    _ = try await source.completeSession(
      CompletedSession(sessionID: "session-1", confirmedAt: 20), confirmation: .confirmed)
    let workout = linkWorkout(id: "legacy-health", start: 100)
    try await source.upsertHealthWorkouts([workout], reconciliationContext: "initial")
    let storedWorkouts = try await source.loadHealthWorkouts()
    let storedWorkout = try XCTUnwrap(storedWorkouts.first)
    let sessionValue = try await source.loadSessionCorrectionSnapshot(sessionID: "session-1")
    let session = try XCTUnwrap(sessionValue)
    let legacyLink = HealthWorkoutLinkFact(
      id: "legacy-link", healthKitUUID: workout.healthKitUUID, localEntityKind: .session,
      localEntityID: "session-1", linkedAt: Date(timeIntervalSince1970: 30))
    _ = try await source.createHealthWorkoutLinkFact(
      legacyLink, expectedSessionUpdatedAt: session.updatedAt, expectedWorkout: storedWorkout)

    let exported = try await source.loadAuthoritativeExportData()
    let legacyTables = exported.tables.map { table in
      guard table.name == "health_workout_link_facts" else { return table }
      return TrainingExportTable(
        name: table.name,
        records: table.records.map { record in
          var fields = record.fields
          fields.removeValue(forKey: "linked_during_completion")
          fields.removeValue(forKey: "write_back_disposition")
          fields.removeValue(forKey: "unlinked_at")
          return TrainingExportRecord(id: record.id, fields: fields)
        }
      )
    }
    let legacyExport = TrainingAuthoritativeExportData(
      tables: legacyTables,
      preferences: exported.preferences
    )

    let destination = GRDBTrainingRepository(root: destinationRoot)
    try await destination.prepareStores()
    try await destination.replaceAuthoritativeData(legacyExport, progress: nil)
    let restored = try await destination.loadHealthWorkoutLinkFacts(for: nil)

    XCTAssertEqual(restored, [legacyLink])
    XCTAssertFalse(try XCTUnwrap(restored.first).linkedDuringCompletion)
    XCTAssertEqual(try XCTUnwrap(restored.first).writeBackDisposition, .notApplicable)
    XCTAssertNil(try XCTUnwrap(restored.first).unlinkedAt)
  }
}

private func makeLinkingCycle() -> TrainingCycle {
  let template = ScheduleTemplate(sessions: [
    ScheduleSession(
      id: "template-1", intendedWeekday: .monday,
      primaryLiftID: "squat", assistanceLiftID: "bench"),
    ScheduleSession(
      id: "template-2", intendedWeekday: .tuesday,
      primaryLiftID: "bench", assistanceLiftID: "squat"),
  ])
  return TrainingCycle(
    id: "cycle",
    week1AnchorDate: TrainingDate(year: 2024, month: 1, day: 1),
    weeks: [
      TrainingWeek(
        id: "week",
        position: 1,
        kind: .week1,
        startDate: TrainingDate(year: 2024, month: 1, day: 1),
        sessions: [
          TrainingCycleSession(
            id: "session-1",
            intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
            sourceTemplateSessionID: "template-1",
            primaryLiftID: "squat",
            assistanceLiftID: "bench"
          ),
          TrainingCycleSession(
            id: "session-2",
            intendedDate: TrainingDate(year: 2024, month: 1, day: 2),
            sourceTemplateSessionID: "template-2",
            primaryLiftID: "bench",
            assistanceLiftID: "squat"
          ),
        ]
      )
    ],
    sourceTemplate: template.snapshot,
    includesProvisionalDeload: false,
    lifecycleState: .active,
    createdAt: 1,
    updatedAt: 10,
    liftSnapshots: [
      "squat": LiftConfigurationSnapshot(
        identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 2.5),
      "bench": LiftConfigurationSnapshot(
        identity: .progression(.benchPress), trainingMaxKg: 75, loadingIncrementKg: 2.5),
    ]
  )
}

private func linkWorkout(id: String, start: TimeInterval) -> HealthWorkout {
  HealthWorkout(
    healthKitUUID: id,
    activityType: "traditional-strength-training",
    startDate: Date(timeIntervalSince1970: start),
    endDate: Date(timeIntervalSince1970: start + 60),
    duration: 60,
    sourceName: "External",
    sourceBundleIdentifier: "com.example.external",
    localDate: "2024-01-01",
    firstImportedAt: Date(timeIntervalSince1970: 15)
  )
}
