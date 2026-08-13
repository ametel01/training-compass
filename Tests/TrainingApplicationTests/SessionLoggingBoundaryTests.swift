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
    async throws
  {
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
      ),
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
        ),
      ]
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
