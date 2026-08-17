import Foundation
import XCTest

@testable import TrainingApplication

final class TrainingScheduleChangeBoundaryTests: XCTestCase {
  func testCalendarChangeMovesOnlyScheduledDateAndRequiresOutsideWeekAcknowledgement() async throws {
    let cycle = makeActiveCycle()
    let repository = ScheduleChangeRepository(active: cycle, template: makeTemplate())
    let boundary = makeBoundary(repository: repository)

    let preview = try await boundary.previewCalendarChange(
      sessionID: "scheduled",
      intendedDate: TrainingDate(year: 2024, month: 1, day: 20)
    )
    XCTAssertEqual(preview.action, .calendarChanged)
    XCTAssertTrue(preview.requiresWarningAcknowledgement)
    let before = try XCTUnwrap(preview.before)
    let after = try XCTUnwrap(preview.after)
    let old = before.weeks[0].sessions[0]
    let changed = after.weeks[0].sessions[0]
    XCTAssertEqual(changed.intendedDate, TrainingDate(year: 2024, month: 1, day: 20))
    XCTAssertEqual(changed.primaryLiftID, old.primaryLiftID)
    XCTAssertEqual(changed.assistanceLiftID, old.assistanceLiftID)
    XCTAssertEqual(changed.prescriptions, old.prescriptions)
    do {
      _ = try await boundary.confirmCalendarChange(preview)
      XCTFail("Expected outside-week acknowledgement")
    } catch let error as TrainingCycleValidationError {
      XCTAssertEqual(error, .calendarChangeWarningRequired)
    }
    let audit = try await boundary.confirmCalendarChange(
      preview,
      acknowledgeOutsideWeek: true
    )
    XCTAssertEqual(audit.changeKind, .calendarChange)
    let saved = try await repository.loadActiveTrainingCycle()
    XCTAssertEqual(
      saved?.weeks[0].sessions[0].intendedDate,
      TrainingDate(year: 2024, month: 1, day: 20))
  }

  func testProgramEditCanAddRemoveAndChangeOnlyScheduledSessions() async throws {
    let cycle = makeActiveCycle()
    let repository = ScheduleChangeRepository(active: cycle, template: makeTemplate())
    let boundary = makeBoundary(repository: repository)
    let week = cycle.weeks[0]
    let scheduled = week.sessions[0]
    let completed = week.sessions[1]
    let request = TrainingCycleEditRequest(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: [
        TrainingWeekRequest(
          id: week.id,
          position: week.position,
          kind: week.kind,
          startDate: week.startDate,
          sessions: [
            TrainingCycleSessionRequest(
              id: scheduled.id, intendedDate: scheduled.intendedDate,
              primaryLiftID: "bench", assistanceLiftID: "squat"
            ),
            TrainingCycleSessionRequest(
              id: completed.id, intendedDate: completed.intendedDate,
              primaryLiftID: completed.primaryLiftID, assistanceLiftID: completed.assistanceLiftID
            ),
            TrainingCycleSessionRequest(
              id: "", intendedDate: TrainingDate(year: 2024, month: 1, day: 3),
              primaryLiftID: "squat", assistanceLiftID: "bench"
            )
          ]
        )
      ]
    )
    let preview = try await boundary.previewProgramEdit(request)
    let edited = try XCTUnwrap(preview.after)
    XCTAssertEqual(preview.action, .programEdited)
    XCTAssertEqual(edited.weeks[0].sessions.count, 3)
    XCTAssertEqual(edited.weeks[0].sessions[0].primaryLiftID, "bench")
    XCTAssertEqual(edited.weeks[0].sessions[1], completed)
    XCTAssertFalse(edited.weeks[0].sessions[0].prescriptions.isEmpty)
    _ = try await boundary.confirmProgramEdit(preview)
    let saved = try await repository.loadActiveTrainingCycle()
    XCTAssertEqual(saved?.weeks[0].sessions.count, 3)

    let illegalRemoval = TrainingCycleEditRequest(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: [
        TrainingWeekRequest(
          id: week.id, position: 1, kind: week.kind, startDate: week.startDate,
          sessions: [
            TrainingCycleSessionRequest(
              id: scheduled.id, intendedDate: scheduled.intendedDate,
              primaryLiftID: scheduled.primaryLiftID, assistanceLiftID: scheduled.assistanceLiftID
            )
          ]
        )
      ]
    )
    do {
      _ = try await boundary.previewProgramEdit(illegalRemoval)
      XCTFail("Expected completed session removal to be rejected")
    } catch let error as TrainingCycleValidationError {
      XCTAssertEqual(error, .scheduledSessionRequired)
    }
  }

  func testNormalWeekCanBeSavedBackWithoutDeloadOrLoggedFacts() async throws {
    let cycle = makeActiveCycle()
    let repository = ScheduleChangeRepository(active: cycle, template: makeTemplate())
    let boundary = makeBoundary(repository: repository)
    let preview = try await boundary.previewSaveWeekToTemplate(weekPosition: 1)
    XCTAssertEqual(preview.action, .savedFromTrainingWeek)
    XCTAssertEqual(preview.after.sessions.map(\.primaryLiftID), ["squat", "bench"])
    XCTAssertEqual(preview.after.sessions.map(\.intendedWeekday), [.monday, .thursday])
    let audit = try await boundary.confirmSaveWeekToTemplate(preview)
    XCTAssertEqual(audit.action, .savedFromTrainingWeek)
    XCTAssertNil(audit.after.sessions.first?.id.isEmpty == true ? true : nil)
  }

  private func makeBoundary(repository: ScheduleChangeRepository) -> TrainingCycleBoundary {
    let clock = FixedScheduleChangeClock()
    return TrainingCycleBoundary(
      repository: repository,
      scheduleTemplateBoundary: ScheduleTemplateBoundary(
        repository: repository, liftRepository: repository,
        clock: clock, uuidGenerator: ScheduleChangeUUIDGenerator()
      ),
      liftRepository: repository,
      clock: clock,
      calendar: FixedScheduleChangeCalendar(),
      uuidGenerator: ScheduleChangeUUIDGenerator()
    )
  }

  private func makeTemplate() -> ScheduleTemplate {
    ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "monday", intendedWeekday: .monday, primaryLiftID: "squat", assistanceLiftID: "bench"),
      ScheduleSession(
        id: "thursday", intendedWeekday: .thursday, primaryLiftID: "bench",
        assistanceLiftID: "squat")
    ])
  }

  private func makeActiveCycle() -> TrainingCycle {
    let template = makeTemplate()
    let prescriptions = [
      TrainingSetPrescription(
        id: "prescription", setNumber: 1, role: .primary,
        percentage: 0.65, repetitions: 5, weightKg: 65)
    ]
    let week = TrainingWeek(
      id: "week", position: 1, kind: .week1,
      startDate: TrainingDate(year: 2024, month: 1, day: 1),
      sessions: [
        TrainingCycleSession(
          id: "scheduled", intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
          sourceTemplateSessionID: "monday", primaryLiftID: "squat", assistanceLiftID: "bench",
          prescriptions: prescriptions),
        TrainingCycleSession(
          id: "completed", intendedDate: TrainingDate(year: 2024, month: 1, day: 4),
          sourceTemplateSessionID: "thursday", primaryLiftID: "bench", assistanceLiftID: "squat",
          prescriptions: prescriptions, status: .completed)
      ]
    )
    return TrainingCycle(
      id: "cycle", week1AnchorDate: week.startDate, weeks: [week],
      sourceTemplate: template.snapshot, includesProvisionalDeload: false,
      lifecycleState: .active,
      liftSnapshots: [
        "squat": LiftConfigurationSnapshot(
          identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 2.5),
        "bench": LiftConfigurationSnapshot(
          identity: .progression(.benchPress), trainingMaxKg: 75, loadingIncrementKg: 2.5)
      ])
  }
}

private struct FixedScheduleChangeClock: Clock {
  func now() -> Date { TrainingDate(year: 2024, month: 1, day: 1).date() }
}

private struct FixedScheduleChangeCalendar: CalendarProvider {
  func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

private final class ScheduleChangeUUIDGenerator: UUIDGenerator, @unchecked Sendable {
  private var counter = 0
  func makeUUID() -> UUID {
    defer { counter += 1 }
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
  }
}

private actor ScheduleChangeRepository: TrainingRepository {
  private var active: TrainingCycle?
  private var draft: TrainingCycle?
  private var template: ScheduleTemplate
  private var audits: [TrainingCycleAuditEntry] = []
  private var templateAudits: [ScheduleTemplateAuditEntry] = []

  init(active: TrainingCycle?, template: ScheduleTemplate) {
    self.active = active
    self.template = template
  }

  func prepareStores() async throws {}
  func loadActiveTrainingCycle() async throws -> TrainingCycle? { active }
  func loadDraftTrainingCycle() async throws -> TrainingCycle? { draft }
  func completedTrainingCycleCount() async throws -> Int { 0 }
  func saveTrainingCycle(
    _ cycle: TrainingCycle, expectedBefore: TrainingCycleSnapshot?, auditID: String,
    occurredAt: Int64, action: TrainingCycleAuditAction
  ) async throws -> TrainingCycleAuditEntry {
    let current = cycle.lifecycleState == .active ? active : draft
    guard current?.snapshot == expectedBefore else { throw TrainingCycleRepositoryError.staleCycle }
    if cycle.lifecycleState == .active { active = cycle } else { draft = cycle }
    let audit = TrainingCycleAuditEntry(
      id: auditID, cycleID: cycle.id, action: action,
      occurredAt: occurredAt, before: current?.snapshot, after: cycle.snapshot)
    audits.append(audit)
    return audit
  }
  func discardDraftTrainingCycle(
    expectedBefore: TrainingCycleSnapshot, auditID: String,
    occurredAt: Int64
  ) async throws -> TrainingCycleAuditEntry { fatalError() }
  func trainingCycleAuditHistory(for cycleID: String) async throws -> [TrainingCycleAuditEntry] {
    audits.filter { $0.cycleID == cycleID }
  }
  func loadScheduleTemplate() async throws -> ScheduleTemplate? { template }
  func saveScheduleTemplate(
    _ next: ScheduleTemplate, expectedBefore: ScheduleTemplateSnapshot?, auditID: String,
    occurredAt: Int64, action: ScheduleTemplateAuditAction
  ) async throws -> ScheduleTemplateAuditEntry {
    guard template.snapshot == expectedBefore else {
      throw ScheduleTemplateRepositoryError.staleTemplate
    }
    let audit = ScheduleTemplateAuditEntry(
      id: auditID, templateID: next.id, action: action,
      occurredAt: occurredAt, before: template.snapshot, after: next.snapshot)
    template = next
    templateAudits.append(audit)
    return audit
  }
  func scheduleTemplateAuditHistory() async throws -> [ScheduleTemplateAuditEntry] {
    templateAudits
  }
  func loadLiftConfigurations() async throws -> [LiftConfiguration] {
    [
      try LiftConfiguration(id: "squat", identity: .progression(.squat), trainingMaxKg: 100),
      try LiftConfiguration(id: "bench", identity: .progression(.benchPress), trainingMaxKg: 75)
    ]
  }
  func saveLiftConfiguration(
    _ configuration: LiftConfiguration, expectedBefore: LiftConfigurationSnapshot?, auditID: String,
    occurredAt: Int64, action: LiftConfigurationAuditAction
  ) async throws -> LiftConfigurationAuditEntry { fatalError() }
  func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] { [] }
}
