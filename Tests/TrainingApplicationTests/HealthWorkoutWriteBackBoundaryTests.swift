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

  private func makeCompletedSession() -> TodaySessionSnapshot {
    let prescription = TrainingSetPrescription(
      id: "prescription", setNumber: 1, role: .primary, percentage: 0.65,
      repetitions: 5, weightKg: 65)
    let result = try! SetResult(weight: SetResultWeight(kg: 65), repetitions: 5)
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
  private var record: HealthWorkoutWriteBackRecord?
  private var links: [HealthWorkoutLinkFact] = []

  func loadHealthWorkoutWriteBackPreference() async throws -> HealthWorkoutWriteBackPreference {
    preferenceValue
  }

  func saveHealthWorkoutWriteBackPreference(_ preference: HealthWorkoutWriteBackPreference)
    async throws
  {
    preferenceValue = preference
  }

  func loadHealthWorkoutWriteBack(sessionID: String) async throws -> HealthWorkoutWriteBackRecord? {
    record?.sessionID == sessionID ? record : nil
  }

  func loadHealthWorkoutWriteBacks() async throws -> [HealthWorkoutWriteBackRecord] {
    record.map { [$0] } ?? []
  }

  func saveHealthWorkoutWriteBack(_ record: HealthWorkoutWriteBackRecord) async throws {
    self.record = record
  }

  func loadHealthWorkoutLinkFacts(forLocalEntityID localEntityID: String) async throws
    -> [HealthWorkoutLinkFact]
  {
    links.filter { $0.localEntityID == localEntityID }
  }

  func setLinks(_ links: [HealthWorkoutLinkFact]) { self.links = links }
}

private actor WriteBackClientSpy: HealthWorkoutWriteBackClient {
  private(set) var authorizationRequests = 0
  private(set) var saveRequests = 0
  private(set) var summaries: [HealthWorkoutWriteBackSummary] = []

  func requestWriteAuthorization() async throws -> HealthAuthorizationSnapshot {
    authorizationRequests += 1
    return .init(state: .authorized, requested: .init(readTypes: [], writeTypes: [.workouts]))
  }

  func saveWorkout(_ summary: HealthWorkoutWriteBackSummary) async throws -> String {
    saveRequests += 1
    summaries.append(summary)
    return "health-workout"
  }

  func workoutExists(syncIdentifier: String) async throws -> Bool {
    summaries.contains { $0.syncIdentifier == syncIdentifier }
  }
}

private struct WriteBackClock: Clock {
  func now() -> Date { Date(timeIntervalSince1970: 1_000) }
}
