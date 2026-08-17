import Foundation
@testable import TrainingApplication
@testable import TrainingPersistence
import XCTest

final class ScheduleTemplateRepositoryTests: XCTestCase {
    func testScheduleTemplateAndReplacementAuditSurviveRestart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        let lifts = try [
            LiftConfiguration(id: "squat", identity: .progression(.squat), trainingMaxKg: 100),
            LiftConfiguration(id: "bench", identity: .progression(.benchPress), trainingMaxKg: 75),
        ]
        for (index, lift) in lifts.enumerated() {
            _ = try await repository.saveLiftConfiguration(
                lift,
                expectedBefore: nil,
                auditID: "lift-audit-\(index)",
                occurredAt: Int64(index),
                action: .created,
            )
        }
        let first = ScheduleTemplate(sessions: [
            ScheduleSession(
                id: "session-1",
                intendedWeekday: .monday,
                primaryLiftID: "squat",
                assistanceLiftID: "squat",
            ),
            ScheduleSession(
                id: "session-2",
                intendedWeekday: .monday,
                primaryLiftID: "bench",
                assistanceLiftID: "squat",
            ),
        ])
        let replacement = ScheduleTemplate(sessions: [
            ScheduleSession(
                id: "session-2",
                intendedWeekday: .friday,
                primaryLiftID: "bench",
                assistanceLiftID: "bench",
            ),
        ])

        let created = try await repository.saveScheduleTemplate(
            first,
            expectedBefore: nil,
            auditID: "schedule-audit-1",
            occurredAt: 10,
            action: .created,
        )
        let reset = try await repository.saveScheduleTemplate(
            replacement,
            expectedBefore: first.snapshot,
            auditID: "schedule-audit-2",
            occurredAt: 20,
            action: .reset,
        )

        XCTAssertNil(created.before)
        XCTAssertEqual(reset.before, first.snapshot)
        let restarted = GRDBTrainingRepository(root: root)
        let saved = try await restarted.loadScheduleTemplate()
        XCTAssertEqual(saved, replacement)
        let history = try await restarted.scheduleTemplateAuditHistory()
        XCTAssertEqual(history.map(\.action), [.created, .reset])
        XCTAssertEqual(history[1].before, first.snapshot)
    }

    func testStaleReplacementDoesNotChangeTemplateOrAudit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        let lift = try LiftConfiguration(
            id: "squat", identity: .progression(.squat), trainingMaxKg: 100,
        )
        _ = try await repository.saveLiftConfiguration(
            lift,
            expectedBefore: nil,
            auditID: "lift-audit",
            occurredAt: 1,
            action: .created,
        )
        let first = ScheduleTemplate(sessions: [
            ScheduleSession(
                id: "session",
                intendedWeekday: .monday,
                primaryLiftID: "squat",
                assistanceLiftID: "squat",
            ),
        ])
        _ = try await repository.saveScheduleTemplate(
            first,
            expectedBefore: nil,
            auditID: "schedule-audit-1",
            occurredAt: 2,
            action: .created,
        )
        let replacement = ScheduleTemplate(sessions: [
            ScheduleSession(
                id: "session",
                intendedWeekday: .tuesday,
                primaryLiftID: "squat",
                assistanceLiftID: "squat",
            ),
        ])

        do {
            _ = try await repository.saveScheduleTemplate(
                replacement,
                expectedBefore: ScheduleTemplateSnapshot(id: first.id, sessions: []),
                auditID: "schedule-audit-2",
                occurredAt: 3,
                action: .edited,
            )
            XCTFail("Expected a stale template")
        } catch let error as ScheduleTemplateRepositoryError {
            XCTAssertEqual(error, .staleTemplate)
        }
        let saved = try await repository.loadScheduleTemplate()
        let historyCount = try await repository.scheduleTemplateAuditHistory().count
        XCTAssertEqual(saved, first)
        XCTAssertEqual(historyCount, 1)
    }
}
