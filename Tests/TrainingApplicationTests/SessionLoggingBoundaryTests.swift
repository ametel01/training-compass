import Foundation
import XCTest

@testable import TrainingApplication

final class SessionLoggingBoundaryTests: XCTestCase {
  func testTodayShowsImmutablePrescriptionSnapshotsAndUnrecordedState() async throws {
    let repository = SessionLoggingTestRepository(active: makeActiveCycle())
    let boundary = SessionLoggingBoundary(
      cycleRepository: repository,
      resultRepository: repository,
      clock: SessionLoggingFixedClock(),
      calendar: SessionLoggingFixedCalendar(),
      uuidGenerator: SessionLoggingUUIDGenerator()
    )

    let todayValue = try await boundary.today()
    let today = try XCTUnwrap(todayValue)
    XCTAssertEqual(today.session.primaryLiftID, "squat")
    XCTAssertEqual(today.primaryLift.trainingMaxKg, 100)
    XCTAssertEqual(today.sets.map(\.prescription.repetitions), [5, 5, 5, 10])
    XCTAssertTrue(today.sets.allSatisfy { $0.completionState == .notRecorded })
    XCTAssertEqual(today.state, .scheduled)
    XCTAssertEqual(today.session.prescriptions[0].weightKg, 65)
  }

  func testRecordingPersistsActualValuesAndSurfacesIncrementWarningWithoutChangingPrescription()
    async throws {
    let repository = SessionLoggingTestRepository(active: makeActiveCycle())
    let boundary = SessionLoggingBoundary(
      cycleRepository: repository,
      resultRepository: repository,
      clock: SessionLoggingFixedClock(),
      calendar: SessionLoggingFixedCalendar(),
      uuidGenerator: SessionLoggingUUIDGenerator()
    )
    let prescription = makeActiveCycle().weeks[0].sessions[0].prescriptions[0]

    _ = try await boundary.recordSetResult(
      sessionID: "session",
      prescriptionID: prescription.id,
      weightKg: 66.25,
      repetitions: 6
    )
    let todayValue = try await boundary.today()
    let today = try XCTUnwrap(todayValue)
    let set = try XCTUnwrap(today.sets.first)
    XCTAssertEqual(set.result?.weightKg, 66.25)
    XCTAssertEqual(set.result?.repetitions, 6)
    XCTAssertTrue(set.hasLoadingIncrementWarning)
    XCTAssertEqual(set.prescription.weightKg, 65)
    XCTAssertEqual(today.state, .inProgress)
    let history = try await boundary.auditHistory(for: "session")
    XCTAssertEqual(history.count, 1)
  }

  func testRecordingRemainsResponsiveWhileUnrelatedReconciliationRuns() async throws {
    let cycleRepository = SessionLoggingTestRepository(active: makeActiveCycle())
    let resultRepository = SessionLoggingTestRepository(active: nil)
    let boundary = SessionLoggingBoundary(
      cycleRepository: cycleRepository,
      resultRepository: resultRepository,
      clock: SessionLoggingFixedClock(),
      calendar: SessionLoggingFixedCalendar(),
      uuidGenerator: SessionLoggingUUIDGenerator()
    )
    let prescription = makeActiveCycle().weeks[0].sessions[0].prescriptions[0]
    let reconciliation = BlockingReconciliation()
    let reconciliationTask = Task { await reconciliation.run() }
    await reconciliation.waitUntilStarted()

    let audit = try await boundary.recordSetResult(
      sessionID: "session",
      prescriptionID: prescription.id,
      weightKg: 66.25,
      repetitions: 6
    )

    XCTAssertEqual(audit.after.weightKg, 66.25)
    await reconciliation.finish()
    await reconciliationTask.value
  }

  func testZeroRepetitionsIsAConfirmedFailedResult() async throws {
    let repository = SessionLoggingTestRepository(active: makeActiveCycle())
    let boundary = makeBoundary(repository: repository)
    let prescription = makeActiveCycle().weeks[0].sessions[0].prescriptions[0]

    _ = try await boundary.recordSetResult(
      sessionID: "session", prescriptionID: prescription.id, weightKg: 65, repetitions: 0
    )

    let todayValue = try await boundary.today()
    let today = try XCTUnwrap(todayValue)
    let set = try XCTUnwrap(today.sets.first)
    XCTAssertEqual(set.result?.repetitions, 0)
    XCTAssertEqual(set.completionState, .failed)
  }

  func testOmittingASetRemovesItsResultAndAllowsCompletion() async throws {
    let repository = SessionLoggingTestRepository(active: makeActiveCycle())
    let boundary = makeBoundary(repository: repository)
    let prescriptions = makeActiveCycle().weeks[0].sessions[0].prescriptions
    _ = try await boundary.recordSetResult(
      sessionID: "session", prescriptionID: prescriptions[0].id, weightKg: 65, repetitions: 0
    )
    _ = try await boundary.omitSet(
      sessionID: "session", prescriptionID: prescriptions[1].id, reason: "Equipment unavailable"
    )
    for prescription in prescriptions.dropFirst(2) {
      _ = try await boundary.recordSetResult(
        sessionID: "session", prescriptionID: prescription.id, weightKg: 50, repetitions: 5
      )
    }

    let beforeCompletionValue = try await boundary.today()
    let beforeCompletion = try XCTUnwrap(beforeCompletionValue)
    XCTAssertEqual(beforeCompletion.state, .readyToComplete)
    XCTAssertEqual(beforeCompletion.sets[1].completionState, .omitted)
    XCTAssertNil(beforeCompletion.sets[1].result)
    let completed = try await boundary.confirmSession(sessionID: "session")
    XCTAssertEqual(completed.state, .completed)
    XCTAssertEqual(completed.plannedVersusActual.omitted.count, 1)
  }

  func testHistoricalImportRecordsTopSetRepsAndCompletesOtherSetsAsPrescribed() async throws {
    let repository = SessionLoggingTestRepository(active: makeActiveCycle())
    let boundary = makeBoundary(repository: repository)

    let imported = try await boundary.importCompletedSession(
      sessionID: "session",
      topSetRepetitions: 9
    )

    XCTAssertEqual(imported.state, .completed)
    XCTAssertEqual(imported.results.count, imported.session.prescriptions.count)
    let topSet = try XCTUnwrap(
      imported.sets.first(where: { $0.prescription.isPlusSetEligible })
    )
    XCTAssertEqual(topSet.result?.repetitions, 9)
    XCTAssertEqual(topSet.result?.weightKg, topSet.prescription.weightKg)
    XCTAssertTrue(
      imported.sets.filter { !$0.prescription.isPlusSetEligible }.allSatisfy {
        $0.result?.repetitions == $0.prescription.repetitions
          && $0.result?.weightKg == $0.prescription.weightKg
      }
    )
  }

  func testAdditionalSetsCanBeEditedRemovedAndReordered() async throws {
    let repository = SessionLoggingTestRepository(active: makeActiveCycle())
    let boundary = makeBoundary(repository: repository)
    let first = try await boundary.addAdditionalSet(
      sessionID: "session", liftID: "row", weightKg: 40, repetitions: 8, note: "Strict"
    )
    let second = try await boundary.addAdditionalSet(
      sessionID: "session", liftID: "row", weightKg: 42.5, repetitions: 6
    )
    _ = try await boundary.editAdditionalSet(
      sessionID: "session", id: first.id, liftID: "row", weightKg: 45, repetitions: 5
    )
    try await boundary.reorderAdditionalSets(
      sessionID: "session", orderedIDs: [second.id, first.id])
    let snapshotValue = try await boundary.today()
    let snapshot = try XCTUnwrap(snapshotValue)
    XCTAssertEqual(snapshot.additionalSets.map(\.id), [second.id, first.id])
    XCTAssertEqual(snapshot.additionalSets[1].weightKg, 45)
    try await boundary.removeAdditionalSet(sessionID: "session", id: second.id)
    let afterRemovalValue = try await boundary.today()
    let afterRemoval = try XCTUnwrap(afterRemovalValue)
    XCTAssertEqual(afterRemoval.additionalSets.count, 1)
  }

  private func makeActiveCycle() -> TrainingCycle {
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "template",
        intendedWeekday: .monday,
        primaryLiftID: "squat",
        assistanceLiftID: "bench"
      )
    ])
    let prescriptions = [
      TrainingSetPrescription(
        id: "prescription-1", setNumber: 1, role: .primary, percentage: 0.65,
        repetitions: 5, weightKg: 65
      ),
      TrainingSetPrescription(
        id: "prescription-2", setNumber: 2, role: .primary, percentage: 0.75,
        repetitions: 5, weightKg: 75
      ),
      TrainingSetPrescription(
        id: "prescription-3", setNumber: 3, role: .primary, percentage: 0.85,
        repetitions: 5, weightKg: 85, isPlusSetEligible: true
      ),
      TrainingSetPrescription(
        id: "prescription-4", setNumber: 1, role: .assistance, percentage: 0.65,
        repetitions: 10, weightKg: 50
      )
    ]
    let session = TrainingCycleSession(
      id: "session",
      intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
      sourceTemplateSessionID: "template",
      primaryLiftID: "squat",
      assistanceLiftID: "bench",
      prescriptions: prescriptions
    )
    return TrainingCycle(
      id: "cycle",
      week1AnchorDate: TrainingDate(year: 2024, month: 1, day: 1),
      weeks: [
        TrainingWeek(
          id: "week",
          position: 1,
          kind: .week1,
          startDate: TrainingDate(year: 2024, month: 1, day: 1),
          sessions: [session]
        )
      ],
      sourceTemplate: template.snapshot,
      includesProvisionalDeload: false,
      lifecycleState: .active,
      liftSnapshots: [
        "squat": LiftConfigurationSnapshot(
          identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 2.5
        ),
        "bench": LiftConfigurationSnapshot(
          identity: .progression(.benchPress), trainingMaxKg: 75, loadingIncrementKg: 2.5
        )
      ]
    )
  }

  private func makeBoundary(repository: SessionLoggingTestRepository) -> SessionLoggingBoundary {
    SessionLoggingBoundary(
      cycleRepository: repository,
      resultRepository: repository,
      clock: SessionLoggingFixedClock(),
      calendar: SessionLoggingFixedCalendar(),
      uuidGenerator: SessionLoggingUUIDGenerator()
    )
  }
}

private struct SessionLoggingFixedClock: Clock {
  func now() -> Date { TrainingDate(year: 2024, month: 1, day: 1).date() }
}

private struct SessionLoggingFixedCalendar: CalendarProvider {
  func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

private final class SessionLoggingUUIDGenerator: UUIDGenerator, @unchecked Sendable {
  private var counter = 0

  func makeUUID() -> UUID {
    defer { counter += 1 }
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
  }
}

private actor SessionLoggingTestRepository: TrainingCycleRepository, SetResultRepository {
  let active: TrainingCycle?
  var results: [String: RecordedSetResult] = [:]
  var omissions: [String: OmittedSet] = [:]
  var additional: [String: AdditionalSet] = [:]
  var completion: CompletedSession?
  var audits: [SetResultAuditEntry] = []

  init(active: TrainingCycle?) { self.active = active }

  func loadActiveTrainingCycle() async throws -> TrainingCycle? { active }
  func loadSetResults(for sessionID: String) async throws -> [RecordedSetResult] {
    results.values.filter { $0.sessionID == sessionID }
  }

  func saveSetResult(
    _ result: RecordedSetResult,
    expectedBefore: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: SetResultAuditAction
  ) async throws -> SetResultAuditEntry {
    let key = "\(result.sessionID):\(result.prescriptionID)"
    let before = results[key]
    guard before == expectedBefore else { throw SetResultRepositoryError.staleResult }
    results[key] = result
    omissions.removeValue(forKey: key)
    let audit = SetResultAuditEntry(
      id: auditID,
      sessionID: result.sessionID,
      prescriptionID: result.prescriptionID,
      action: action,
      occurredAt: occurredAt,
      before: before,
      after: result
    )
    audits.append(audit)
    return audit
  }

  func setResultAuditHistory(for sessionID: String) async throws -> [SetResultAuditEntry] {
    audits.filter { $0.sessionID == sessionID }
  }

  func loadOmittedSets(for sessionID: String) async throws -> [OmittedSet] {
    omissions.values.filter { $0.sessionID == sessionID }
  }

  func saveOmittedSet(
    _ omission: OmittedSet,
    expectedResult: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: OmittedSetAuditAction
  ) async throws {
    let key = omission.id
    let current = results[key]
    guard current == expectedResult else { throw SetResultRepositoryError.staleResult }
    results.removeValue(forKey: key)
    omissions[key] = omission
  }

  func loadAdditionalSets(for sessionID: String) async throws -> [AdditionalSet] {
    additional.values.filter { $0.sessionID == sessionID }.sorted { $0.position < $1.position }
  }

  func saveAdditionalSet(_ set: AdditionalSet) async throws -> AdditionalSet {
    additional[set.id] = set
    return set
  }

  func deleteAdditionalSet(sessionID: String, id: String) async throws {
    additional.removeValue(forKey: id)
    let remaining = additional.values.filter { $0.sessionID == sessionID }.sorted {
      $0.position < $1.position
    }
    for (position, set) in remaining.enumerated() {
      additional[set.id] = try AdditionalSet(
        id: set.id, sessionID: set.sessionID, position: position, liftID: set.liftID,
        weightKg: set.weightKg, repetitions: set.repetitions, note: set.note,
        recordedAt: set.recordedAt
      )
    }
  }

  func reorderAdditionalSets(sessionID: String, orderedIDs: [String]) async throws {
    for (position, id) in orderedIDs.enumerated() {
      guard let set = additional[id], set.sessionID == sessionID else {
        throw SetResultRepositoryError.unknownPrescription
      }
      additional[id] = try AdditionalSet(
        id: set.id, sessionID: set.sessionID, position: position, liftID: set.liftID,
        weightKg: set.weightKg, repetitions: set.repetitions, note: set.note,
        recordedAt: set.recordedAt
      )
    }
  }

  func loadCompletedSession(sessionID: String) async throws -> CompletedSession? {
    completion?.sessionID == sessionID ? completion : nil
  }

  func completeSession(
    _ completion: CompletedSession,
    confirmation: SessionCompletionConfirmation
  ) async throws -> CompletedSession {
    guard confirmation == .confirmed else { throw SessionLoggingError.incompleteSession }
    self.completion = completion
    return completion
  }
}

private actor BlockingReconciliation {
  private var started = false
  private var release: CheckedContinuation<Void, Never>?

  func run() async {
    started = true
    await withCheckedContinuation { continuation in
      release = continuation
    }
  }

  func waitUntilStarted() async {
    while !started {
      await Task.yield()
    }
  }

  func finish() {
    release?.resume()
    release = nil
  }
}
