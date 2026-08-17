import Foundation
import XCTest

@testable import TrainingApplication

final class HealthWorkoutWriteBackBoundaryTests: XCTestCase {
  func testPreferenceDefaultsOffAndAuthorizationFollowsDurableEnablement() async throws {
    let repository = WriteBackRepositorySpy()
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let initialPreference = try await boundary.preference()
    XCTAssertFalse(initialPreference.enabled)
    let initialAuthorizationRequests = await client.authorizationRequests
    XCTAssertEqual(initialAuthorizationRequests, 0)
    _ = try await boundary.setEnabled(true)
    let enabledPreference = try await boundary.preference()
    XCTAssertTrue(enabledPreference.enabled)
    let enabledAuthorizationRequests = await client.authorizationRequests
    XCTAssertEqual(enabledAuthorizationRequests, 1)
  }

  func testQueueWritesOnlyMinimizedSummaryAndIsIdempotent() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())
    let session = makeCompletedSession()

    let first = await boundary.queue(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000), choice: .share)
    let second = await boundary.queue(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000), choice: .share)

    XCTAssertEqual(first?.state, .savedToHealth)
    XCTAssertEqual(second?.state, .savedToHealth)
    let saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 1)
    let summaries = await client.summaries
    let summary = try XCTUnwrap(summaries.first)
    XCTAssertEqual(
      summary.syncIdentifier, HealthWorkoutWriteBackBoundary.syncIdentifier(for: "session"))
    XCTAssertEqual(summary.syncVersion, 1)
    XCTAssertEqual(summary.duration, 0, accuracy: 0.001)
  }

  func testExternalLinkSuppressesSummaryWithoutCallingHealth() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    await repository.setLinks([
      HealthWorkoutLinkFact(
        id: "link", healthKitUUID: "external", localEntityKind: .session,
        localEntityID: "session")
    ])
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let result = await boundary.queue(
      session: makeCompletedSession(), completedAt: Date(timeIntervalSince1970: 2_000),
      choice: .share)

    XCTAssertEqual(result?.state, .notShared)
    let saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 0)
  }

  func testPerSessionOptOutPersistsNotSharedWithoutCallingHealth() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let result = await boundary.queue(
      session: makeCompletedSession(), completedAt: Date(timeIntervalSince1970: 2_000),
      choice: .doNotShare)

    XCTAssertEqual(result?.state, .notShared)
    let saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 0)
    let persisted = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(persisted?.state, .notShared)
  }

  func testTransientFailureIsDurableAndResumesOnLaterOpportunity() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    await client.setSaveOutcomes([.inaccessible, .success])
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let first = await boundary.queue(
      session: makeCompletedSession(), completedAt: Date(timeIntervalSince1970: 2_000),
      choice: .share)
    XCTAssertEqual(first?.state, .retryScheduled)
    let queued = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(queued?.state, .retryScheduled)

    let recovered = await boundary.resumePendingWriteBacks()
    XCTAssertEqual(recovered.first?.state, .savedToHealth)
    let saved = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(saved?.state, .savedToHealth)
    let saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 2)
  }

  func testAccessFailureDoesNotLoopAndExplicitRetryRecovers() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    await client.setSaveOutcomes([.authorizationDenied, .success])
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let denied = await boundary.queue(
      session: makeCompletedSession(), completedAt: Date(timeIntervalSince1970: 2_000),
      choice: .share)
    XCTAssertEqual(denied?.state, .healthAccessNeeded)
    let pendingAfterDenied = await boundary.resumePendingWriteBacks()
    XCTAssertTrue(pendingAfterDenied.isEmpty)
    var saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 1)

    let recovered = await boundary.retry(sessionID: "session")
    XCTAssertEqual(recovered?.state, .savedToHealth)
    saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 2)
  }

  func testCheckWriteAccessRequiresAuthorizedSnapshot() async throws {
    let repository = WriteBackRepositorySpy()
    let client = WriteBackClientSpy()
    await client.setAuthorizationState(.postponed)
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    do {
      _ = try await boundary.checkWriteAccess()
      XCTFail("A postponed write authorization must remain an explicit access-needed state")
    } catch let error as HealthWorkoutWriteBackClientError {
      XCTAssertEqual(error, .authorizationDenied)
    }
  }

  func testTerminalFailurePreservesLocalCompletionUntilExplicitRetry() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    await client.setSaveOutcomes([.terminal, .success])
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let failed = await boundary.queue(
      session: makeCompletedSession(), completedAt: Date(timeIntervalSince1970: 2_000),
      choice: .share)
    XCTAssertEqual(failed?.state, .couldntSave)
    let pendingAfterTerminalFailure = await boundary.resumePendingWriteBacks()
    XCTAssertTrue(pendingAfterTerminalFailure.isEmpty)
    var saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 1)

    let recovered = await boundary.retry(sessionID: "session")
    XCTAssertEqual(recovered?.state, .savedToHealth)
    saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 2)
  }

  func testCancellationLeavesRetryableIntentAndRepeatedResumeIsIdempotent() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    await client.setSaveOutcomes([.cancelled, .success])
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let cancelled = await boundary.queue(
      session: makeCompletedSession(), completedAt: Date(timeIntervalSince1970: 2_000),
      choice: .share)
    XCTAssertEqual(cancelled?.state, .retryScheduled)

    _ = await boundary.resumePendingWriteBacks()
    _ = await boundary.resumePendingWriteBacks()
    let saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 2)
    let saved = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(saved?.state, .savedToHealth)
  }

  func testReopenMarksSummaryPendingAndOnlyChangedFactsPublishGreaterVersion() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())
    let session = makeCompletedSession()
    _ = await boundary.queue(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000), choice: .share)

    let pending = await boundary.markSessionEditing(sessionID: "session")
    XCTAssertEqual(pending?.state, .updatePending)
    XCTAssertEqual(pending?.syncVersion, 1)

    let unchanged = await boundary.reconcileCompletedSession(
      session, completedAt: Date(timeIntervalSince1970: 2_000))
    XCTAssertEqual(unchanged?.state, .savedToHealth)
    XCTAssertEqual(unchanged?.syncVersion, 1)
    let unchangedSaveRequests = await client.saveRequests
    XCTAssertEqual(unchangedSaveRequests, 1)

    let changed = await boundary.reconcileCompletedSession(
      session, completedAt: Date(timeIntervalSince1970: 3_000))
    XCTAssertEqual(changed?.state, .savedToHealth)
    XCTAssertEqual(changed?.syncVersion, 2)
    let changedSaveRequests = await client.saveRequests
    let summaries = await client.summaries
    XCTAssertEqual(changedSaveRequests, 2)
    XCTAssertEqual(summaries.last?.syncVersion, 2)
  }

  func testExternalDeletionStaysDeletedUntilExplicitRestoreAndExactUUIDCanReconcile() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())
    let session = makeCompletedSession()
    let first = await boundary.queue(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000), choice: .share)
    XCTAssertEqual(first?.state, .savedToHealth)

    _ = await boundary.markDeletedFromHealth(healthKitUUID: "health-workout")
    let deleted = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(deleted?.state, .deletedFromHealth)
    var saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 1)

    // Normal queue/retry paths do not recreate an object after the owner's
    // deletion choice.
    let queuedAfterDeletion = await boundary.queue(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000), choice: .share)
    XCTAssertEqual(queuedAfterDeletion?.state, .deletedFromHealth)
    let retriedAfterDeletion = await boundary.retry(sessionID: "session")
    XCTAssertEqual(retriedAfterDeletion?.state, .deletedFromHealth)
    saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 1)

    // The same UUID returning from Health is safe to reconnect idempotently.
    let returned = HealthWorkout(
      healthKitUUID: "health-workout", activityType: HealthWorkoutWriteBackSummary.activityType,
      startDate: first!.startDate, endDate: first!.endDate, duration: first!.duration,
      sourceName: "Training Compass",
      sourceBundleIdentifier: TrainingEventLinkBoundary.trainingCompassBundleIdentifier,
      appAuthoredSyncIdentifier: first!.syncIdentifier,
      appAuthoredSyncVersion: first!.syncVersion)
    _ = await boundary.reconcileImportedWorkouts([returned])
    let reconciled = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(reconciled?.state, .savedToHealth)
    saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 1)

    _ = await boundary.markDeletedFromHealth(healthKitUUID: "health-workout")
    let restored = await boundary.restoreToHealth(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000))
    XCTAssertEqual(restored?.state, .savedToHealth)
    XCTAssertEqual(restored?.syncVersion, 2)
    saveRequests = await client.saveRequests
    XCTAssertEqual(saveRequests, 2)
    let summaries = await client.summaries
    XCTAssertEqual(summaries.last?.syncVersion, 2)
  }

  func testDifferentUUIDDoesNotReplaceExistingSummaryAndDeletionFailureIsRetryable() async throws {
    let repository = WriteBackRepositorySpy()
    try await repository.saveHealthWorkoutWriteBackPreference(.init(enabled: true))
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())
    let session = makeCompletedSession()
    let saved = await boundary.queue(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000), choice: .share)!
    _ = await boundary.markDeletedFromHealth(healthKitUUID: saved.healthKitUUID!)
    let replacement = HealthWorkout(
      healthKitUUID: "new-health-workout", activityType: HealthWorkoutWriteBackSummary.activityType,
      startDate: saved.startDate, endDate: saved.endDate, duration: saved.duration,
      sourceName: "Training Compass",
      sourceBundleIdentifier: TrainingEventLinkBoundary.trainingCompassBundleIdentifier,
      appAuthoredSyncIdentifier: saved.syncIdentifier,
      appAuthoredSyncVersion: saved.syncVersion)
    _ = await boundary.reconcileImportedWorkouts([replacement])
    let unreconciled = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(unreconciled?.state, .deletedFromHealth)

    _ = await boundary.restoreToHealth(
      session: session, completedAt: Date(timeIntervalSince1970: 2_000))
    await client.setDeleteOutcomes([.failure])
    do {
      _ = try await boundary.deleteAppAuthoredSummaryForReplacement(sessionID: "session")
      XCTFail("A failed HealthKit deletion must prevent replacement")
    } catch let error as HealthWorkoutWriteBackReplacementError {
      XCTAssertEqual(error, .deletionFailed)
    }
    let afterFailure = try await repository.loadHealthWorkoutWriteBack(sessionID: "session")
    XCTAssertEqual(afterFailure?.state, .savedToHealth)
  }

  func testDeleteAllSummariesPreservesRemainingIdentityAcrossMixedFailureAndRetry() async throws {
    let repository = WriteBackRepositorySpy()
    await repository.seedRecords([
      HealthWorkoutWriteBackRecord(
        sessionID: "first", syncIdentifier: "sync.first", state: .savedToHealth,
        startDate: Date(timeIntervalSince1970: 1), endDate: Date(timeIntervalSince1970: 2),
        healthKitUUID: "health-first"),
      HealthWorkoutWriteBackRecord(
        sessionID: "second", syncIdentifier: "sync.second", state: .savedToHealth,
        startDate: Date(timeIntervalSince1970: 3), endDate: Date(timeIntervalSince1970: 4),
        healthKitUUID: "health-second"),
      HealthWorkoutWriteBackRecord(
        sessionID: "pending", syncIdentifier: "sync.pending", state: .queued,
        startDate: Date(timeIntervalSince1970: 5), endDate: Date(timeIntervalSince1970: 6))
    ])
    let client = WriteBackClientSpy()
    await client.setDeleteOutcomes([.success, .failure])
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let partial = await boundary.deleteAllAppAuthoredSummaries()

    XCTAssertFalse(partial.isComplete)
    XCTAssertEqual(partial.deletedSyncIdentifiers, ["sync.first"])
    XCTAssertEqual(partial.remainingRecords.map(\.sessionID), ["second"])
    let partialDeleteRequests = await client.deleteRequests
    XCTAssertEqual(partialDeleteRequests, ["health-first", "health-second"])
    let firstAfterPartial = try await repository.loadHealthWorkoutWriteBack(sessionID: "first")
    XCTAssertEqual(firstAfterPartial?.state, .deletedFromHealth)

    await client.setDeleteOutcomes([.success])
    let restartedBoundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())
    let completed = await restartedBoundary.deleteAllAppAuthoredSummaries()

    XCTAssertTrue(completed.isComplete)
    XCTAssertEqual(completed.remainingRecords, [])
    let secondAfterRetry = try await repository.loadHealthWorkoutWriteBack(sessionID: "second")
    XCTAssertEqual(secondAfterRetry?.state, .deletedFromHealth)
    let allDeleteRequests = await client.deleteRequests
    XCTAssertEqual(allDeleteRequests, ["health-first", "health-second", "health-second"])
  }

  func testDeleteAllSummariesPassesStableSyncIdentityForOwnershipCheck() async throws {
    let repository = WriteBackRepositorySpy()
    let record = HealthWorkoutWriteBackRecord(
      sessionID: "session", syncIdentifier: "sync.session", state: .savedToHealth,
      startDate: Date(timeIntervalSince1970: 1), endDate: Date(timeIntervalSince1970: 2),
      healthKitUUID: "health-workout")
    await repository.seedRecords([record])
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    _ = await boundary.deleteAllAppAuthoredSummaries()

    let expectedDeleteIdentities = await client.expectedDeleteIdentities
    XCTAssertEqual(
      expectedDeleteIdentities.map { "\($0.0)|\($0.1)" }, ["health-workout|sync.session"])
  }

  func testDeleteAllSummariesBlocksLocalErasureForSavedRecordWithoutUUID() async throws {
    let repository = WriteBackRepositorySpy()
    await repository.seedRecords([
      HealthWorkoutWriteBackRecord(
        sessionID: "session", syncIdentifier: "sync.session", state: .savedToHealth,
        startDate: Date(timeIntervalSince1970: 1), endDate: Date(timeIntervalSince1970: 2))
    ])
    let client = WriteBackClientSpy()
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let result = await boundary.deleteAllAppAuthoredSummaries()

    XCTAssertFalse(result.isComplete)
    XCTAssertEqual(result.failure, .failed)
    XCTAssertEqual(result.remainingRecords.map(\.sessionID), ["session"])
    let deleteRequests = await client.deleteRequests
    XCTAssertTrue(deleteRequests.isEmpty)
  }

  func testDeleteAllSummariesMapsPermissionFailureWithoutDroppingIdentity() async throws {
    let repository = WriteBackRepositorySpy()
    await repository.seedRecords([
      HealthWorkoutWriteBackRecord(
        sessionID: "session", syncIdentifier: "sync.session", state: .savedToHealth,
        startDate: Date(timeIntervalSince1970: 1), endDate: Date(timeIntervalSince1970: 2),
        healthKitUUID: "health-workout")
    ])
    let client = WriteBackClientSpy()
    await client.setDeleteOutcomes([.authorizationDenied])
    let boundary = HealthWorkoutWriteBackBoundary(
      repository: repository, client: client, clock: WriteBackClock())

    let result = await boundary.deleteAllAppAuthoredSummaries()

    XCTAssertEqual(result.failure, .authorizationDenied)
    XCTAssertEqual(result.remainingRecords.map(\.sessionID), ["session"])
  }

  private func makeCompletedSession() -> TodaySessionSnapshot {
    let prescription = TrainingSetPrescription(
      id: "prescription", setNumber: 1, role: .primary, percentage: 0.65,
      repetitions: 5, weightKg: 65)
    let result: SetResult
    do {
      result = try SetResult(weight: SetResultWeight(kg: 65), repetitions: 5)
    } catch {
      fatalError("fixed test fixture must create a valid set result")
    }
    let recorded = RecordedSetResult(
      id: "result", sessionID: "session", prescriptionID: prescription.id,
      result: result, recordedAt: 1_000)
    let session = TrainingCycleSession(
      id: "session", intendedDate: TrainingDate(year: 2026, month: 8, day: 15),
      sourceTemplateSessionID: "template", primaryLiftID: "squat", assistanceLiftID: "bench",
      prescriptions: [prescription], status: .completed)
    return TodaySessionSnapshot(
      cycleID: "cycle", weekID: "week", weekKind: .week1, intendedDate: session.intendedDate,
      session: session,
      primaryLift: .init(identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 5),
      assistanceLift: .init(
        identity: .progression(.benchPress), trainingMaxKg: 80, loadingIncrementKg: 2.5),
      sets: [
        TodaySetSnapshot(
          prescription: prescription, result: recorded, hasLoadingIncrementWarning: false)
      ],
      completion: .init(sessionID: "session", confirmedAt: 2_000))
  }
}

private actor WriteBackRepositorySpy: HealthWorkoutWriteBackRepository {
  private var preferenceValue = HealthWorkoutWriteBackPreference()
  private var records: [String: HealthWorkoutWriteBackRecord] = [:]
  private var links: [HealthWorkoutLinkFact] = []

  func loadHealthWorkoutWriteBackPreference() async throws -> HealthWorkoutWriteBackPreference {
    preferenceValue
  }

  func saveHealthWorkoutWriteBackPreference(_ preference: HealthWorkoutWriteBackPreference)
    async throws {
    preferenceValue = preference
  }

  func loadHealthWorkoutWriteBack(sessionID: String) async throws -> HealthWorkoutWriteBackRecord? {
    records[sessionID]
  }

  func loadHealthWorkoutWriteBacks() async throws -> [HealthWorkoutWriteBackRecord] {
    records.values.sorted { $0.sessionID < $1.sessionID }
  }

  func saveHealthWorkoutWriteBack(_ record: HealthWorkoutWriteBackRecord) async throws {
    records[record.sessionID] = record
  }

  func loadHealthWorkoutLinkFacts(forLocalEntityID localEntityID: String) async throws
    -> [HealthWorkoutLinkFact] {
    links.filter { $0.localEntityID == localEntityID }
  }

  func setLinks(_ links: [HealthWorkoutLinkFact]) { self.links = links }
  func seedRecords(_ records: [HealthWorkoutWriteBackRecord]) {
    self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.sessionID, $0) })
  }
}

private actor WriteBackClientSpy: HealthWorkoutWriteBackClient {
  enum SaveOutcome: Sendable {
    case success
    case authorizationDenied
    case unavailable
    case inaccessible
    case protectedDataUnavailable
    case terminal
    case cancelled
  }

  private(set) var authorizationRequests = 0
  private(set) var saveRequests = 0
  private(set) var deleteRequests: [String] = []
  private(set) var expectedDeleteIdentities: [(String, String)] = []
  private(set) var summaries: [HealthWorkoutWriteBackSummary] = []
  private var authorizationState = HealthAuthorizationState.authorized
  private var saveOutcomes: [SaveOutcome] = []
  private var deleteOutcomes: [DeleteOutcome] = []

  enum DeleteOutcome: Sendable {
    case success
    case failure
    case authorizationDenied
    case protectedDataUnavailable
  }

  func setSaveOutcomes(_ outcomes: [SaveOutcome]) { saveOutcomes = outcomes }
  func setDeleteOutcomes(_ outcomes: [DeleteOutcome]) { deleteOutcomes = outcomes }
  func setAuthorizationState(_ state: HealthAuthorizationState) { authorizationState = state }

  func requestWriteAuthorization() async throws -> HealthAuthorizationSnapshot {
    authorizationRequests += 1
    return .init(
      state: authorizationState, requested: .init(readTypes: [], writeTypes: [.workouts]))
  }

  func saveWorkout(_ summary: HealthWorkoutWriteBackSummary) async throws -> String {
    saveRequests += 1
    if !saveOutcomes.isEmpty {
      let outcome = saveOutcomes.removeFirst()
      switch outcome {
      case .success:
        break
      case .authorizationDenied:
        throw HealthWorkoutWriteBackClientError.authorizationDenied
      case .unavailable:
        throw HealthWorkoutWriteBackClientError.unavailable
      case .inaccessible:
        throw HealthWorkoutWriteBackClientError.inaccessible
      case .protectedDataUnavailable:
        throw HealthWorkoutWriteBackClientError.protectedDataUnavailable
      case .terminal:
        throw WriteBackTerminalFailure()
      case .cancelled:
        throw CancellationError()
      }
    }
    summaries.append(summary)
    return "health-workout"
  }

  func workoutExists(syncIdentifier: String) async throws -> Bool {
    summaries.contains { $0.syncIdentifier == syncIdentifier }
  }

  func deleteWorkout(healthKitUUID: String) async throws {
    deleteRequests.append(healthKitUUID)
    guard !deleteOutcomes.isEmpty else { return }
    switch deleteOutcomes.removeFirst() {
    case .success: return
    case .failure: throw WriteBackTerminalFailure()
    case .authorizationDenied: throw HealthWorkoutWriteBackClientError.authorizationDenied
    case .protectedDataUnavailable:
      throw HealthWorkoutWriteBackClientError.protectedDataUnavailable
    }
  }

  func deleteWorkout(healthKitUUID: String, expectedSyncIdentifier: String) async throws {
    expectedDeleteIdentities.append((healthKitUUID, expectedSyncIdentifier))
    try await deleteWorkout(healthKitUUID: healthKitUUID)
  }
}

private struct WriteBackTerminalFailure: Error, Sendable {}

private struct WriteBackClock: Clock {
  func now() -> Date { Date(timeIntervalSince1970: 1_000) }
}
