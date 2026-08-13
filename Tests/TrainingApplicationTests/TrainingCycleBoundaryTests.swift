import Foundation
import XCTest

@testable import TrainingApplication

final class TrainingCycleBoundaryTests: XCTestCase {
  func testCreateCopiesThreeIndependentWeeksAndUsesMondayAnchorByDefault() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate())
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let preview = try await boundary.previewCreate()
    let cycle = try XCTUnwrap(preview.after)
    XCTAssertEqual(cycle.weeks.count, 3)
    XCTAssertEqual(cycle.weeks.map(\.kind), [.week1, .week2, .week3])
    XCTAssertEqual(cycle.week1AnchorDate, TrainingDate(year: 2023, month: 11, day: 13))
    XCTAssertNotEqual(cycle.weeks[0].sessions[0].id, cycle.weeks[1].sessions[0].id)
    XCTAssertEqual(cycle.sourceTemplate, makeTemplate().snapshot)
    let beforeSave = try await boundary.draft()
    XCTAssertNil(beforeSave)

    _ = try await boundary.confirm(preview)
    let savedValue = try await boundary.draft()
    let saved = try XCTUnwrap(savedValue)
    XCTAssertEqual(saved, cycle)
  }

  func testCompletedCadenceIncludesOnlyProvisionalDeloadOnEverySecondCycle() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate(), completedCount: 1)
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let preview = try await boundary.previewCreate(
      anchorDate: TrainingDate(year: 2024, month: 1, day: 1)
    )
    let cycle = try XCTUnwrap(preview.after)
    XCTAssertTrue(cycle.includesProvisionalDeload)
    XCTAssertEqual(cycle.weeks.last?.kind, .deload)
  }

  func testActiveCycleDoesNotChangeDraftIndependenceAndSecondDraftIsRejected() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate(), active: makeActiveCycle())
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let active = try await boundary.active()
    XCTAssertEqual(active?.lifecycleState, .active)
    _ = try await boundary.create(anchorDate: TrainingDate(year: 2024, month: 1, day: 1))
    do {
      _ = try await boundary.previewCreate(anchorDate: TrainingDate(year: 2024, month: 2, day: 1))
      XCTFail("Expected one-draft limit")
    } catch let error as TrainingCycleValidationError {
      XCTAssertEqual(error, .draftAlreadyExists)
    }
  }

  func testEditChangesOnlyDraftSessionAndCannotReorderWeeks() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate())
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = try await boundary.create(anchorDate: TrainingDate(year: 2024, month: 1, day: 1))
    let cycleValue = try await boundary.draft()
    let cycle = try XCTUnwrap(cycleValue)
    var request = TrainingCycleEditRequest(cycle: cycle)
    let firstWeek = request.weeks[0]
    let firstSession = firstWeek.sessions[0]
    let changed = TrainingCycleSessionRequest(
      id: firstSession.id,
      intendedDate: TrainingDate(year: 2024, month: 1, day: 3),
      primaryLiftID: "bench",
      assistanceLiftID: "squat"
    )
    request = TrainingCycleEditRequest(
      id: request.id,
      week1AnchorDate: request.week1AnchorDate,
      weeks: [
        TrainingWeekRequest(
          id: firstWeek.id,
          position: firstWeek.position,
          kind: firstWeek.kind,
          startDate: firstWeek.startDate,
          sessions: [changed] + Array(firstWeek.sessions.dropFirst())
        )
      ] + Array(request.weeks.dropFirst())
    )
    let editedPreview = try await boundary.previewEdit(request)
    let edited = try XCTUnwrap(editedPreview.after)
    XCTAssertEqual(edited.weeks[0].sessions[0].primaryLiftID, "bench")
    XCTAssertEqual(edited.sourceTemplate, cycle.sourceTemplate)
    let draftAfterPreview = try await boundary.draft()
    XCTAssertEqual(draftAfterPreview, cycle)

    var reordered = request.weeks
    reordered.swapAt(0, 1)
    do {
      _ = try await boundary.previewEdit(
        TrainingCycleEditRequest(
          id: cycle.id,
          week1AnchorDate: cycle.week1AnchorDate,
          weeks: reordered
        )
      )
      XCTFail("Expected fixed week order")
    } catch let error as TrainingCycleValidationError {
      XCTAssertEqual(error, .invalidWeekOrder)
    }
  }

  func testDiscardRequiresExplicitOperationAndLeavesTemplateUntouched() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate())
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = try await boundary.create(anchorDate: TrainingDate(year: 2024, month: 1, day: 1))
    let discardPreview = try await boundary.previewDiscard()
    XCTAssertNotNil(discardPreview.before)
    _ = try await boundary.discard()
    let discarded = try await boundary.draft()
    XCTAssertNil(discarded)
    let savedTemplate = try await repository.loadScheduleTemplate()
    XCTAssertEqual(savedTemplate, makeTemplate())
  }

  func testActivationSnapshotsLiftsAndBuildsExactFiveThreeOnePrescriptions() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate())
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = try await boundary.create(anchorDate: TrainingDate(year: 2024, month: 1, day: 1))

    let preview = try await boundary.previewActivation()
    XCTAssertEqual(preview.after.lifecycleState, .active)
    XCTAssertEqual(preview.after.liftSnapshots["squat"]?.trainingMaxKg, 100)
    XCTAssertEqual(preview.after.liftSnapshots["bench"]?.loadingIncrementKg, 2.5)
    let session = try XCTUnwrap(preview.after.weeks[0].sessions[0])
    XCTAssertEqual(
      session.prescriptions.filter { $0.role == .primary }.map(\.repetitions), [5, 5, 5])
    XCTAssertEqual(
      session.prescriptions.filter { $0.role == .primary }.map(\.weightKg), [65, 75, 85])
    XCTAssertEqual(session.prescriptions.filter { $0.role == .assistance }.count, 5)
    XCTAssertEqual(
      Set(session.prescriptions.filter { $0.role == .assistance }.map(\.percentage)),
      [0.65]
    )
    XCTAssertEqual(session.prescriptions.filter(\.isPlusSetEligible).count, 1)

    _ = try await boundary.confirmActivation(preview)
    let draftAfterActivation = try await boundary.draft()
    let activeAfterActivation = try await boundary.active()
    XCTAssertNil(draftAfterActivation)
    XCTAssertEqual(activeAfterActivation?.lifecycleState, .active)
  }

  func testPastAnchorRequiresExplicitChoiceAndReplacementShiftsDatesWithoutTimezone() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate(), completedCount: 1)
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = try await boundary.create(anchorDate: TrainingDate(year: 2023, month: 11, day: 6))
    do {
      _ = try await boundary.previewActivation()
      XCTFail("Expected an explicit anchor choice")
    } catch let error as TrainingCycleValidationError {
      XCTAssertEqual(error, .pastAnchorRequiresChoice)
    }
    let preview = try await boundary.previewActivation(
      anchorChoice: .replace(
        TrainingDate(year: 2024, month: 2, day: 5)
      ))
    XCTAssertEqual(preview.after.week1AnchorDate, TrainingDate(year: 2024, month: 2, day: 5))
    XCTAssertEqual(preview.after.weeks[1].startDate, TrainingDate(year: 2024, month: 2, day: 12))
    XCTAssertEqual(
      preview.after.weeks[0].sessions[0].intendedDate, TrainingDate(year: 2024, month: 2, day: 5))
    XCTAssertEqual(
      preview.after.weeks.last?.startDate, TrainingDate(year: 2024, month: 2, day: 26))
  }

  func testDeloadAssistanceUsesFiftyPercentAndNoPlusSet() async throws {
    let repository = InMemoryCycleRepository(template: makeTemplate(), completedCount: 1)
    let boundary = makeBoundary(
      repository: repository,
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = try await boundary.create(anchorDate: TrainingDate(year: 2024, month: 1, day: 1))
    let preview = try await boundary.previewActivation()
    let deload = try XCTUnwrap(preview.after.weeks.last)
    XCTAssertEqual(deload.kind, .deload)
    let assistance = deload.sessions[0].prescriptions.filter { $0.role == .assistance }
    XCTAssertEqual(Set(assistance.map(\.percentage)), [0.50])
    XCTAssertEqual(Set(assistance.map(\.repetitions)), [10])
    XCTAssertTrue(assistance.allSatisfy { !$0.isPlusSetEligible })
  }

  private func makeBoundary(
    repository: InMemoryCycleRepository,
    date: Date
  ) -> TrainingCycleBoundary {
    TrainingCycleBoundary(
      repository: repository,
      scheduleTemplateBoundary: ScheduleTemplateBoundary(
        repository: repository,
        liftRepository: repository,
        clock: FixedCycleClock(date: date),
        uuidGenerator: CycleUUIDGenerator()
      ),
      liftRepository: repository,
      clock: FixedCycleClock(date: date),
      calendar: FixedCalendarProvider(),
      uuidGenerator: CycleUUIDGenerator()
    )
  }

  private func makeTemplate() -> ScheduleTemplate {
    ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "monday",
        intendedWeekday: .monday,
        primaryLiftID: "squat",
        assistanceLiftID: "bench"
      ),
      ScheduleSession(
        id: "thursday",
        intendedWeekday: .thursday,
        primaryLiftID: "bench",
        assistanceLiftID: "squat"
      ),
    ])
  }

  private func makeActiveCycle() -> TrainingCycle {
    let template = makeTemplate()
    let session = TrainingCycleSession(
      id: "active-session",
      intendedDate: TrainingDate(year: 2023, month: 12, day: 4),
      sourceTemplateSessionID: "monday",
      primaryLiftID: "squat",
      assistanceLiftID: "bench"
    )
    let week = TrainingWeek(
      id: "active-week",
      position: 1,
      kind: .week1,
      startDate: TrainingDate(year: 2023, month: 12, day: 4),
      sessions: [session]
    )
    return TrainingCycle(
      id: "active-cycle",
      week1AnchorDate: TrainingDate(year: 2023, month: 12, day: 4),
      weeks: [week],
      sourceTemplate: template.snapshot,
      includesProvisionalDeload: false,
      lifecycleState: .active
    )
  }
}

private struct FixedCycleClock: Clock {
  let date: Date
  func now() -> Date { date }
}

private struct FixedCalendarProvider: CalendarProvider {
  func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

private final class CycleUUIDGenerator: UUIDGenerator, @unchecked Sendable {
  private var value = 0
  func makeUUID() -> UUID {
    defer { value += 1 }
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }
}

private actor InMemoryCycleRepository: TrainingCycleRepository, ScheduleTemplateRepository,
  LiftConfigurationRepository
{
  private let template: ScheduleTemplate
  private var draftCycle: TrainingCycle?
  private var activeCycle: TrainingCycle?
  private var completedCount: Int
  private var audits: [TrainingCycleAuditEntry] = []

  init(template: ScheduleTemplate, completedCount: Int = 0, active: TrainingCycle? = nil) {
    self.template = template
    self.completedCount = completedCount
    self.activeCycle = active
  }

  func loadDraftTrainingCycle() async throws -> TrainingCycle? { draftCycle }
  func loadActiveTrainingCycle() async throws -> TrainingCycle? { activeCycle }
  func completedTrainingCycleCount() async throws -> Int { completedCount }

  func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction
  ) async throws -> TrainingCycleAuditEntry {
    guard draftCycle?.snapshot == expectedBefore else {
      throw TrainingCycleRepositoryError.staleCycle
    }
    let audit = TrainingCycleAuditEntry(
      id: auditID, cycleID: cycle.id, action: action, occurredAt: occurredAt,
      before: draftCycle?.snapshot, after: cycle.snapshot
    )
    if cycle.lifecycleState == .active {
      activeCycle = cycle
      draftCycle = nil
    } else {
      draftCycle = cycle
    }
    audits.append(audit)
    return audit
  }

  func discardDraftTrainingCycle(
    expectedBefore: TrainingCycleSnapshot,
    auditID: String,
    occurredAt: Int64
  ) async throws -> TrainingCycleAuditEntry {
    guard draftCycle?.snapshot == expectedBefore else {
      throw TrainingCycleRepositoryError.staleCycle
    }
    draftCycle = nil
    let audit = TrainingCycleAuditEntry(
      id: auditID, cycleID: expectedBefore.id, action: .discarded, occurredAt: occurredAt,
      before: expectedBefore, after: nil
    )
    audits.append(audit)
    return audit
  }

  func trainingCycleAuditHistory(for cycleID: String) async throws -> [TrainingCycleAuditEntry] {
    audits.filter { $0.cycleID == cycleID }
  }

  func loadScheduleTemplate() async throws -> ScheduleTemplate? { template }
  func saveScheduleTemplate(
    _ template: ScheduleTemplate,
    expectedBefore: ScheduleTemplateSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: ScheduleTemplateAuditAction
  ) async throws -> ScheduleTemplateAuditEntry { fatalError("not used") }
  func scheduleTemplateAuditHistory() async throws -> [ScheduleTemplateAuditEntry] { [] }

  func loadLiftConfigurations() async throws -> [LiftConfiguration] {
    [
      try LiftConfiguration(id: "squat", identity: .progression(.squat), trainingMaxKg: 100),
      try LiftConfiguration(id: "bench", identity: .progression(.benchPress), trainingMaxKg: 75),
    ]
  }
  func saveLiftConfiguration(
    _ configuration: LiftConfiguration,
    expectedBefore: LiftConfigurationSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: LiftConfigurationAuditAction
  ) async throws -> LiftConfigurationAuditEntry { fatalError("not used") }
  func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] { [] }
}
