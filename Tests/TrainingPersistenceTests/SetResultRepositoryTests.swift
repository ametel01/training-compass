import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingPersistence

final class SetResultRepositoryTests: XCTestCase {
  func testConfirmedResultAndAuditSurviveRestartWithoutChangingPrescription() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let cycle = makeActiveCycle()
    _ = try await repository.saveTrainingCycle(
      cycle,
      expectedBefore: nil,
      auditID: "cycle-audit",
      occurredAt: 10,
      action: .activated
    )
    let actual = RecordedSetResult(
      id: "result",
      sessionID: "session",
      prescriptionID: "prescription",
      result: try SetResult(weight: SetResultWeight(kg: 66.25), repetitions: 6),
      recordedAt: 20
    )
    let audit = try await repository.saveSetResult(
      actual,
      expectedBefore: nil,
      auditID: "result-audit",
      occurredAt: 20,
      action: .recorded
    )
    XCTAssertNil(audit.before)
    XCTAssertEqual(audit.after, actual)

    let restarted = GRDBTrainingRepository(root: root)
    let results = try await restarted.loadSetResults(for: "session")
    XCTAssertEqual(results, [actual])
    let auditHistory = try await restarted.setResultAuditHistory(for: "session")
    XCTAssertEqual(auditHistory.map(\.after), [actual])
    let savedCycleValue = try await restarted.loadActiveTrainingCycle()
    let savedCycle = try XCTUnwrap(savedCycleValue)
    XCTAssertEqual(savedCycle.weeks[0].sessions[0].prescriptions[0].weightKg, 65)
  }

  func testAuditFailureRollsBackResultAndAuditTogether() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveTrainingCycle(
      makeActiveCycle(),
      expectedBefore: nil,
      auditID: "cycle-audit",
      occurredAt: 10,
      action: .activated
    )
    let actual = RecordedSetResult(
      id: "result",
      sessionID: "session",
      prescriptionID: "prescription",
      result: try SetResult(weight: SetResultWeight(kg: 65), repetitions: 5),
      recordedAt: 20
    )
    _ = try await repository.saveSetResult(
      actual,
      expectedBefore: nil,
      auditID: "duplicate-audit",
      occurredAt: 20,
      action: .recorded
    )
    do {
      _ = try await repository.saveSetResult(
        actual,
        expectedBefore: actual,
        auditID: "duplicate-audit",
        occurredAt: 30,
        action: .recorded
      )
      XCTFail("Expected duplicate audit ID to fail")
    } catch {
      // The transaction must leave both current and audit rows at their prior values.
    }
    let results = try await repository.loadSetResults(for: "session")
    XCTAssertEqual(results, [actual])
    let history = try await repository.setResultAuditHistory(for: "session")
    XCTAssertEqual(history.count, 1)
  }

  private func makeActiveCycle() -> TrainingCycle {
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "template",
        intendedWeekday: .monday,
        primaryLiftID: "squat",
        assistanceLiftID: "squat"
      )
    ])
    let session = TrainingCycleSession(
      id: "session",
      intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
      sourceTemplateSessionID: "template",
      primaryLiftID: "squat",
      assistanceLiftID: "squat",
      prescriptions: [
        TrainingSetPrescription(
          id: "prescription",
          setNumber: 1,
          role: .primary,
          percentage: 0.65,
          repetitions: 5,
          weightKg: 65
        )
      ]
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
        )
      ]
    )
  }
}
