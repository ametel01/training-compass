import Foundation
@testable import TrainingApplication
@testable import TrainingPersistence
import XCTest

final class TrainingCycleLifecycleTests: XCTestCase {
    func testWeekSkipAuditsEachSessionAndCycleCompletionCountsSkippedWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        let cycle = makeCycle()
        _ = try await repository.saveTrainingCycle(
            cycle, expectedBefore: nil, auditID: "activate", occurredAt: 1, action: .activated,
        )
        let boundary = makeBoundary(repository)

        let entries = try await boundary.skipRemainingSessions(
            in: "week-1", confirmation: .confirmed, note: "Travel",
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.action == .sessionSkipped })
        XCTAssertEqual(entries.map(\.note), ["Travel", "Travel"])

        _ = try await boundary.skipRemainingSessions(in: "week-2", confirmation: .confirmed)
        _ = try await boundary.finishWeek(weekID: "week-1", confirmation: .confirmed)
        _ = try await boundary.finishWeek(weekID: "week-2", confirmation: .confirmed)
        let preview = try await boundary.previewCompleteCycle()
        XCTAssertEqual(preview.skippedCount, 3)
        XCTAssertTrue(preview.summary.contains("3 Sessions"))
        _ = try await boundary.completeCycle(confirmation: .confirmed)

        let activeAfterCompletion = try await repository.loadActiveTrainingCycle()
        XCTAssertNil(activeAfterCompletion)
        let history = try await repository.loadTrainingCycles()
        XCTAssertEqual(history.first?.lifecycleState, .completed)
        let completedCount = try await repository.completedTrainingCycleCount()
        XCTAssertEqual(completedCount, 1)
    }

    func testAbandonmentTurnsOutstandingSessionsIntoUnperformedWithoutAdvancingCadence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        _ = try await repository.saveTrainingCycle(
            makeCycle(), expectedBefore: nil, auditID: "activate", occurredAt: 1, action: .activated,
        )
        let boundary = makeBoundary(repository)

        let preview = try await boundary.previewAbandonCycle()
        XCTAssertEqual(preview.unperformedCount, 3)
        _ = try await boundary.abandonCycle(confirmation: .confirmed, note: "Injury")

        let history = try await repository.loadTrainingCycles()
        let abandoned = try XCTUnwrap(history.first)
        XCTAssertEqual(abandoned.lifecycleState, .abandoned)
        XCTAssertEqual(
            abandoned.weeks.flatMap(\.sessions).map(\.status),
            [.unperformed, .unperformed, .unperformed],
        )
        let completedCount = try await repository.completedTrainingCycleCount()
        XCTAssertEqual(completedCount, 0)
    }

    func testCompletionRequiresExplicitSequentialWeekFinishes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        _ = try await repository.saveTrainingCycle(
            makeCycle(), expectedBefore: nil, auditID: "activate", occurredAt: 1, action: .activated,
        )
        let boundary = makeBoundary(repository)
        _ = try await boundary.skipRemainingSessions(in: "week-1", confirmation: .confirmed)
        _ = try await boundary.skipRemainingSessions(in: "week-2", confirmation: .confirmed)

        do {
            _ = try await boundary.finishWeek(
                weekID: "week-2", confirmation: .confirmed, acknowledgeEarlierWeeks: true,
            )
            XCTFail("A later week must not be finishable before its earlier week.")
        } catch let error as TrainingCycleValidationError {
            XCTAssertEqual(error, .weekSequenceWarningRequired)
        }

        do {
            _ = try await boundary.previewCompleteCycle()
            XCTFail("Completion must require an explicit finish audit for each week.")
        } catch let error as TrainingCycleValidationError {
            XCTAssertEqual(error, .cycleNotFinishable)
        }
    }

    private func makeBoundary(_ repository: GRDBTrainingRepository) -> TrainingCycleBoundary {
        TrainingCycleBoundary(
            repository: repository,
            clock: FixedLifecycleClock(),
            calendar: FixedLifecycleCalendar(),
            uuidGenerator: LifecycleUUIDGenerator(),
        )
    }

    private func makeCycle() -> TrainingCycle {
        let template = ScheduleTemplate(sessions: [
            ScheduleSession(
                id: "template", intendedWeekday: .monday,
                primaryLiftID: "squat", assistanceLiftID: "squat",
            ),
        ])
        func session(_ id: String, _ date: TrainingDate) -> TrainingCycleSession {
            TrainingCycleSession(
                id: id, intendedDate: date, sourceTemplateSessionID: "template",
                primaryLiftID: "squat", assistanceLiftID: "squat",
            )
        }
        return TrainingCycle(
            id: "cycle", week1AnchorDate: TrainingDate(year: 2024, month: 1, day: 1),
            weeks: [
                TrainingWeek(
                    id: "week-1", position: 1, kind: .week1,
                    startDate: TrainingDate(year: 2024, month: 1, day: 1),
                    sessions: [
                        session("session-1", TrainingDate(year: 2024, month: 1, day: 1)),
                        session("session-2", TrainingDate(year: 2024, month: 1, day: 2)),
                    ],
                ),
                TrainingWeek(
                    id: "week-2", position: 2, kind: .week2,
                    startDate: TrainingDate(year: 2024, month: 1, day: 8),
                    sessions: [session("session-3", TrainingDate(year: 2024, month: 1, day: 8))],
                ),
            ],
            sourceTemplate: template.snapshot,
            includesProvisionalDeload: false,
            lifecycleState: .active,
        )
    }
}

private struct FixedLifecycleClock: Clock {
    func now() -> Date {
        TrainingDate(year: 2024, month: 1, day: 1).date()
    }
}

private struct FixedLifecycleCalendar: CalendarProvider {
    func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private final class LifecycleUUIDGenerator: UUIDGenerator, @unchecked Sendable {
    private var value = 0

    func makeUUID() -> UUID {
        defer { value += 1 }
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
