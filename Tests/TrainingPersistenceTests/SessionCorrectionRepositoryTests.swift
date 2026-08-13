import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingPersistence

final class SessionCorrectionRepositoryTests: XCTestCase {
  func testReopenCorrectAndRestartRestoresCurrentProjectionAndAuditHistory() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let cycle = makeActiveCycle()
    _ = try await repository.saveTrainingCycle(
      cycle, expectedBefore: nil, auditID: "cycle", occurredAt: 10, action: .activated)
    let original = RecordedSetResult(
      id: "result", sessionID: "session", prescriptionID: "prescription",
      result: try SetResult(weight: SetResultWeight(kg: 65), repetitions: 5), recordedAt: 20)
    _ = try await repository.saveSetResult(
      original, expectedBefore: nil, auditID: "result", occurredAt: 20, action: .recorded)
    _ = try await repository.completeSession(
      CompletedSession(sessionID: "session", confirmedAt: 21), confirmation: .confirmed)

    let boundary = SessionLoggingBoundary(
      repository: repository,
      clock: CorrectionClock(),
      calendar: CorrectionCalendar(),
      uuidGenerator: CorrectionUUIDGenerator())
    let reopened = try await boundary.reopenSession(
      sessionID: "session", confirmation: .confirmed)
    XCTAssertEqual(reopened.session.status, .inProgress)
    XCTAssertEqual(reopened.state, .readyToComplete)
    let reopenedCycleValue = try await repository.loadActiveTrainingCycle()
    let reopenedCycle = try XCTUnwrap(reopenedCycleValue)
    XCTAssertFalse(reopenedCycle.weeks[0].isFinished)

    let corrected = RecordedSetResult(
      id: "result", sessionID: "session", prescriptionID: "prescription",
      result: try SetResult(weight: SetResultWeight(kg: 67.5), repetitions: 7), recordedAt: 30)
    let beforeValue = try await boundary.correctionSnapshot(sessionID: "session")
    let before = try XCTUnwrap(beforeValue)
    let audit = try await boundary.correctSession(
      SessionCorrectionRequest(
        sessionID: "session", status: .completed,
        intendedDate: before.intendedDate,
        primaryLiftID: before.primaryLiftID,
        assistanceLiftID: before.assistanceLiftID,
        results: [corrected], completedAt: 40, note: "Corrected after reviewing the log"),
      confirmation: .confirmed,
      expectedBefore: before)
    XCTAssertEqual(audit.before.results, [original])
    XCTAssertEqual(audit.after.results, [corrected])
    XCTAssertEqual(audit.note, "Corrected after reviewing the log")
    XCTAssertGreaterThan(audit.before.updatedAt, 1_000_000_000)
    XCTAssertEqual(audit.after.updatedAt, audit.occurredAt)

    let restarted = GRDBTrainingRepository(root: root)
    let savedValue = try await restarted.loadActiveTrainingCycle()
    let saved = try XCTUnwrap(savedValue)
    XCTAssertEqual(saved.weeks[0].sessions[0].status, .completed)
    let savedResults = try await restarted.loadSetResults(for: "session")
    let savedResult = try XCTUnwrap(savedResults.first)
    XCTAssertEqual(savedResult.repetitions, 7)
    let savedCompletion = try await restarted.loadCompletedSession(sessionID: "session")
    XCTAssertEqual(
      savedCompletion,
      CompletedSession(sessionID: "session", confirmedAt: 40))
    let history = try await restarted.sessionCorrectionAuditHistory(for: "session")
    XCTAssertEqual(history.count, 2)
    XCTAssertEqual(history[0].before.status, .completed)
    XCTAssertEqual(history[0].after.status, .inProgress)
    XCTAssertEqual(history[0].after.updatedAt, audit.before.updatedAt)
    XCTAssertEqual(history[1].before.results, [original])

    do {
      _ = try await restarted.applySessionCorrection(
        SessionCorrectionRequest(snapshot: history[1].after),
        expectedBefore: history[1].after,
        confirmation: .confirmed,
        auditID: history[1].id,
        occurredAt: 50)
      XCTFail("Expected duplicate audit ID to roll back the correction")
    } catch {
      // The duplicate audit is intentionally rejected by the transaction.
    }
    let finalResults = try await restarted.loadSetResults(for: "session")
    XCTAssertEqual(finalResults.first?.repetitions, 7)
    let finalHistory = try await restarted.sessionCorrectionAuditHistory(for: "session")
    XCTAssertEqual(finalHistory.count, 2)
  }

  func testTerminalCycleCannotBeCorrectedThroughActiveWorkflow() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveTrainingCycle(
      makeActiveCycle(lifecycleState: .completed), expectedBefore: nil,
      auditID: "terminal", occurredAt: 10, action: .activated)
    let request = SessionCorrectionRequest(
      sessionID: "session", status: .inProgress,
      intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
      primaryLiftID: "squat", assistanceLiftID: "squat")
    do {
      _ = try await repository.applySessionCorrection(
        request, expectedBefore: nil, confirmation: .confirmed,
        auditID: "correction", occurredAt: 20)
      XCTFail("Expected terminal-cycle protection")
    } catch let error as SetResultRepositoryError {
      XCTAssertEqual(error, .terminalCycle)
    }
  }

  func testSkippedSessionReopensAndReopensItsFinishedWeek() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveTrainingCycle(
      makeActiveCycle(), expectedBefore: nil, auditID: "cycle", occurredAt: 10,
      action: .activated)
    let boundary = SessionLoggingBoundary(
      repository: repository,
      clock: CorrectionClock(),
      calendar: CorrectionCalendar(),
      uuidGenerator: CorrectionUUIDGenerator())

    let skipped = try await boundary.skipSession(sessionID: "session", confirmation: .confirmed)
    XCTAssertEqual(skipped.state, .skipped)
    let finishedValue = try await repository.loadActiveTrainingCycle()
    XCTAssertTrue(try XCTUnwrap(finishedValue).weeks[0].isFinished)

    let reopened = try await boundary.reopenSession(sessionID: "session", confirmation: .confirmed)
    XCTAssertEqual(reopened.session.status, .inProgress)
    XCTAssertEqual(reopened.state, .scheduled)
    let reopenedCycleValue = try await repository.loadActiveTrainingCycle()
    XCTAssertFalse(try XCTUnwrap(reopenedCycleValue).weeks[0].isFinished)
  }

  func testCorrectionRequiresConfirmationAndRejectsStaleCurrentProjection() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveTrainingCycle(
      makeActiveCycle(), expectedBefore: nil, auditID: "cycle", occurredAt: 10,
      action: .activated)
    let original = RecordedSetResult(
      id: "result", sessionID: "session", prescriptionID: "prescription",
      result: try SetResult(weight: SetResultWeight(kg: 65), repetitions: 5), recordedAt: 20)
    _ = try await repository.saveSetResult(
      original, expectedBefore: nil, auditID: "result", occurredAt: 20, action: .recorded)
    _ = try await repository.completeSession(
      CompletedSession(sessionID: "session", confirmedAt: 21), confirmation: .confirmed)
    let boundary = SessionLoggingBoundary(
      repository: repository,
      clock: CorrectionClock(),
      calendar: CorrectionCalendar(),
      uuidGenerator: CorrectionUUIDGenerator())

    do {
      _ = try await boundary.reopenSession(sessionID: "session", confirmation: .cancelled)
      XCTFail("Expected explicit confirmation")
    } catch let error as SessionLoggingError {
      XCTAssertEqual(error, .confirmationRequired)
    }
    let stillCompletedValue = try await boundary.correctionSnapshot(sessionID: "session")
    let stillCompleted = try XCTUnwrap(stillCompletedValue)
    XCTAssertEqual(stillCompleted.status, .completed)

    _ = try await boundary.reopenSession(sessionID: "session", confirmation: .confirmed)
    let staleValue = try await boundary.correctionSnapshot(sessionID: "session")
    let stale = try XCTUnwrap(staleValue)
    let concurrent = RecordedSetResult(
      id: "result", sessionID: "session", prescriptionID: "prescription",
      result: try SetResult(weight: SetResultWeight(kg: 66), repetitions: 6), recordedAt: 25)
    _ = try await repository.saveSetResult(
      concurrent, expectedBefore: original, auditID: "concurrent", occurredAt: 25, action: .recorded
    )
    do {
      _ = try await boundary.correctSession(
        SessionCorrectionRequest(snapshot: stale),
        confirmation: .confirmed,
        expectedBefore: stale)
      XCTFail("Expected stale correction rejection")
    } catch let error as SetResultRepositoryError {
      XCTAssertEqual(error, .staleCorrection)
    }
    let currentResults = try await repository.loadSetResults(for: "session")
    XCTAssertEqual(currentResults.first?.repetitions, 6)
  }

  private func makeActiveCycle(
    lifecycleState: TrainingCycleLifecycleState = .active
  ) -> TrainingCycle {
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "template", intendedWeekday: .monday,
        primaryLiftID: "squat", assistanceLiftID: "squat")
    ])
    let session = TrainingCycleSession(
      id: "session", intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
      sourceTemplateSessionID: "template", primaryLiftID: "squat", assistanceLiftID: "squat",
      prescriptions: [
        TrainingSetPrescription(
          id: "prescription", setNumber: 1, role: .primary,
          percentage: 0.65, repetitions: 5, weightKg: 65)
      ])
    return TrainingCycle(
      id: "cycle", week1AnchorDate: TrainingDate(year: 2024, month: 1, day: 1),
      weeks: [
        TrainingWeek(
          id: "week", position: 1, kind: .week1,
          startDate: TrainingDate(year: 2024, month: 1, day: 1), sessions: [session])
      ],
      sourceTemplate: template.snapshot, includesProvisionalDeload: false,
      lifecycleState: lifecycleState,
      liftSnapshots: [
        "squat": LiftConfigurationSnapshot(
          identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 2.5)
      ])
  }
}

private struct CorrectionClock: Clock {
  func now() -> Date { TrainingDate(year: 2024, month: 1, day: 1).date() }
}

private struct CorrectionCalendar: CalendarProvider {
  func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

private final class CorrectionUUIDGenerator: UUIDGenerator, @unchecked Sendable {
  private var value = 0

  func makeUUID() -> UUID {
    defer { value += 1 }
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }
}
