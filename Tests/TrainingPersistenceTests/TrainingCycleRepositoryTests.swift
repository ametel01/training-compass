import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingPersistence

final class TrainingCycleRepositoryTests: XCTestCase {
  func testDraftSurvivesRestartAndDiscardIsAuditedAtomically() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let cycle = makeCycle()

    let created = try await repository.saveTrainingCycle(
      cycle,
      expectedBefore: nil,
      auditID: "cycle-audit-1",
      occurredAt: 10,
      action: .created
    )
    XCTAssertNil(created.before)
    let restarted = GRDBTrainingRepository(root: root)
    let saved = try await restarted.loadDraftTrainingCycle()
    XCTAssertEqual(saved, cycle)
    let completedCount = try await restarted.completedTrainingCycleCount()
    XCTAssertEqual(completedCount, 0)

    let discarded = try await restarted.discardDraftTrainingCycle(
      expectedBefore: cycle.snapshot,
      auditID: "cycle-audit-2",
      occurredAt: 20
    )
    XCTAssertEqual(discarded.action, .discarded)
    let removed = try await restarted.loadDraftTrainingCycle()
    XCTAssertNil(removed)
    let history = try await restarted.trainingCycleAuditHistory(for: cycle.id)
    XCTAssertEqual(history.map(\.action), [.created, .discarded])
    XCTAssertEqual(history[1].before, cycle.snapshot)
    XCTAssertNil(history[1].after)
  }

  private func makeCycle() -> TrainingCycle {
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "template-session",
        intendedWeekday: .monday,
        primaryLiftID: "squat",
        assistanceLiftID: "squat"
      )
    ])
    let session = TrainingCycleSession(
      id: "cycle-session",
      intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
      sourceTemplateSessionID: "template-session",
      primaryLiftID: "squat",
      assistanceLiftID: "squat"
    )
    let week = TrainingWeek(
      id: "week-1",
      position: 1,
      kind: .week1,
      startDate: TrainingDate(year: 2024, month: 1, day: 1),
      sessions: [session]
    )
    return TrainingCycle(
      id: "cycle-1",
      week1AnchorDate: TrainingDate(year: 2024, month: 1, day: 1),
      weeks: [week],
      sourceTemplate: template.snapshot,
      includesProvisionalDeload: false,
      createdAt: 1,
      updatedAt: 1
    )
  }
}
