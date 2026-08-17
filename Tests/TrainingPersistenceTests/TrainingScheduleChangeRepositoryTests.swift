import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingPersistence

final class TrainingScheduleChangeRepositoryTests: XCTestCase {
  func testPlannedSessionProjectionChangesSurviveRestartWithoutWorkChanges() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let cycle = makeCycle()
    _ = try await repository.saveTrainingCycle(
      cycle, expectedBefore: nil, auditID: "create", occurredAt: 1, action: .activated
    )
    let moved = TrainingCycle(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: [
        TrainingWeek(
          id: cycle.weeks[0].id,
          position: 1,
          kind: .week1,
          startDate: cycle.weeks[0].startDate,
          sessions: [
            TrainingCycleSession(
              id: "session",
              intendedDate: TrainingDate(year: 2024, month: 1, day: 20),
              sourceTemplateSessionID: "template",
              primaryLiftID: "squat",
              assistanceLiftID: "bench",
              prescriptions: cycle.weeks[0].sessions[0].prescriptions
            )
          ]
        )
      ],
      sourceTemplate: cycle.sourceTemplate,
      includesProvisionalDeload: false,
      lifecycleState: .active,
      liftSnapshots: cycle.liftSnapshots
    )
    _ = try await repository.saveTrainingCycle(
      moved,
      expectedBefore: cycle.snapshot,
      auditID: "calendar",
      occurredAt: 2,
      action: .calendarChanged
    )
    let restarted = GRDBTrainingRepository(root: root)
    let savedValue = try await restarted.loadActiveTrainingCycle()
    let saved = try XCTUnwrap(savedValue)
    XCTAssertEqual(
      saved.weeks[0].sessions[0].intendedDate,
      TrainingDate(year: 2024, month: 1, day: 20))
    XCTAssertEqual(
      saved.weeks[0].sessions[0].prescriptions, cycle.weeks[0].sessions[0].prescriptions)
    let history = try await restarted.trainingCycleAuditHistory(for: cycle.id)
    XCTAssertEqual(
      history.map(\.action),
      [.activated, .calendarChanged])
  }

  private func makeCycle() -> TrainingCycle {
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "template", intendedWeekday: .monday,
        primaryLiftID: "squat", assistanceLiftID: "bench")
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
              id: "session",
              intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
              sourceTemplateSessionID: "template",
              primaryLiftID: "squat",
              assistanceLiftID: "bench",
              prescriptions: [
                TrainingSetPrescription(
                  id: "prescription", setNumber: 1, role: .primary,
                  percentage: 0.65, repetitions: 5, weightKg: 65
                )
              ]
            )
          ]
        )
      ],
      sourceTemplate: template.snapshot,
      includesProvisionalDeload: false,
      lifecycleState: .active,
      liftSnapshots: [
        "squat": LiftConfigurationSnapshot(
          identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 2.5),
        "bench": LiftConfigurationSnapshot(
          identity: .progression(.benchPress), trainingMaxKg: 75, loadingIncrementKg: 2.5)
      ]
    )
  }
}
