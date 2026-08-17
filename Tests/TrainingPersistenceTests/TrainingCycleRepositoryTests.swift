import Foundation
@testable import TrainingApplication
@testable import TrainingPersistence
import XCTest

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
            action: .created,
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
            occurredAt: 20,
        )
        XCTAssertEqual(discarded.action, .discarded)
        let removed = try await restarted.loadDraftTrainingCycle()
        XCTAssertNil(removed)
        let history = try await restarted.trainingCycleAuditHistory(for: cycle.id)
        XCTAssertEqual(history.map(\.action), [.created, .discarded])
        XCTAssertEqual(history[1].before, cycle.snapshot)
        XCTAssertNil(history[1].after)
    }

    func testActivationReplacesDraftWithDurableSingleActiveCycle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        let draft = makeCycle()
        _ = try await repository.saveTrainingCycle(
            draft,
            expectedBefore: nil,
            auditID: "cycle-audit-create",
            occurredAt: 10,
            action: .created,
        )
        let active = TrainingCycle(
            id: draft.id,
            week1AnchorDate: draft.week1AnchorDate,
            weeks: draft.weeks,
            sourceTemplate: draft.sourceTemplate,
            includesProvisionalDeload: draft.includesProvisionalDeload,
            lifecycleState: .active,
            createdAt: draft.createdAt,
            updatedAt: 20,
            liftSnapshots: [
                "squat": LiftConfigurationSnapshot(
                    identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 2.5,
                ),
            ],
        )
        _ = try await repository.saveTrainingCycle(
            active,
            expectedBefore: draft.snapshot,
            auditID: "cycle-audit-activate",
            occurredAt: 20,
            action: .activated,
        )
        let restarted = GRDBTrainingRepository(root: root)
        let savedDraft = try await restarted.loadDraftTrainingCycle()
        let savedActive = try await restarted.loadActiveTrainingCycle()
        let history = try await restarted.trainingCycleAuditHistory(for: draft.id)
        XCTAssertNil(savedDraft)
        XCTAssertEqual(savedActive, active)
        XCTAssertEqual(history.map(\.action), [.created, .activated])
    }

    private func makeCycle() -> TrainingCycle {
        let template = ScheduleTemplate(sessions: [
            ScheduleSession(
                id: "template-session",
                intendedWeekday: .monday,
                primaryLiftID: "squat",
                assistanceLiftID: "squat",
            ),
        ])
        let session = TrainingCycleSession(
            id: "cycle-session",
            intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
            sourceTemplateSessionID: "template-session",
            primaryLiftID: "squat",
            assistanceLiftID: "squat",
        )
        let week = TrainingWeek(
            id: "week-1",
            position: 1,
            kind: .week1,
            startDate: TrainingDate(year: 2024, month: 1, day: 1),
            sessions: [session],
        )
        return TrainingCycle(
            id: "cycle-1",
            week1AnchorDate: TrainingDate(year: 2024, month: 1, day: 1),
            weeks: [week],
            sourceTemplate: template.snapshot,
            includesProvisionalDeload: false,
            createdAt: 1,
            updatedAt: 1,
        )
    }
}
