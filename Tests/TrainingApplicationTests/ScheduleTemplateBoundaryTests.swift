import Foundation
@testable import TrainingApplication
import XCTest

final class ScheduleTemplateBoundaryTests: XCTestCase {
    func testFirstUseBuildsTheDefaultScheduleFromConfiguredLifts() async throws {
        let repository = try InMemoryTrainingRepository(configurations: configuredLifts())
        let boundary = ScheduleTemplateBoundary(
            repository: repository,
            clock: FixedScheduleClock(date: Date(timeIntervalSince1970: 100)),
            uuidGenerator: ScheduleUUIDGenerator(),
        )

        let template = try await boundary.list()

        XCTAssertEqual(
            template.sessions.map(\.intendedWeekday), [.monday, .tuesday, .thursday, .friday],
        )
        XCTAssertEqual(
            template.sessions.map(\.primaryLiftID), ["squat", "press", "bench", "deadlift"],
        )
        XCTAssertEqual(
            template.sessions.map(\.assistanceLiftID), ["bench", "rdl", "squat", "press"],
        )
    }

    func testPreviewSupportsReorderSharedWeekdayAndSameLiftWithoutMutation() async throws {
        let repository = try InMemoryTrainingRepository(configurations: configuredLifts())
        let boundary = ScheduleTemplateBoundary(
            repository: repository,
            clock: FixedScheduleClock(date: Date(timeIntervalSince1970: 200)),
            uuidGenerator: ScheduleUUIDGenerator(),
        )
        let initial = try await boundary.list()
        let requests = initial.sessions.reversed().enumerated().map { index, session in
            ScheduleSessionRequest(
                id: session.id,
                intendedWeekday: index < 2 ? .monday : session.intendedWeekday,
                primaryLiftID: session.primaryLiftID,
                assistanceLiftID: session.primaryLiftID,
            )
        }

        let preview = try await boundary.preview(ScheduleTemplateRequest(sessions: requests))
        let beforeConfirmation = try await boundary.list()
        XCTAssertEqual(beforeConfirmation, initial)
        let audit = try await boundary.confirm(preview)
        let saved = try await boundary.list()

        XCTAssertEqual(audit.action, .created)
        XCTAssertEqual(saved.sessions.count, 4)
        XCTAssertEqual(saved.sessions.prefix(2).map(\.intendedWeekday), [.monday, .monday])
        XCTAssertTrue(saved.sessions.allSatisfy { $0.primaryLiftID == $0.assistanceLiftID })
    }

    func testUnconfiguredLiftAndEmptyTemplateAreRejectedBeforeSave() async throws {
        let repository = try InMemoryTrainingRepository(configurations: configuredLifts())
        let boundary = ScheduleTemplateBoundary(
            repository: repository,
            clock: FixedScheduleClock(date: Date()),
            uuidGenerator: ScheduleUUIDGenerator(),
        )
        let invalid = ScheduleTemplateRequest(sessions: [
            ScheduleSessionRequest(
                intendedWeekday: .monday,
                primaryLiftID: "missing",
                assistanceLiftID: "squat",
            ),
        ])

        do {
            _ = try await boundary.preview(invalid)
            XCTFail("Expected an unconfigured lift")
        } catch let error as ScheduleTemplateValidationError {
            XCTAssertEqual(error, .unconfiguredLift("missing"))
        }
        do {
            _ = try await boundary.preview(ScheduleTemplateRequest(sessions: []))
            XCTFail("Expected an empty template error")
        } catch let error as ScheduleTemplateValidationError {
            XCTAssertEqual(error, .emptyTemplate)
        }
        let auditCount = await repository.scheduleAudits.count
        XCTAssertEqual(auditCount, 0)
    }

    func testResetPreviewsDefaultAndRecordsReplacement() async throws {
        let repository = try InMemoryTrainingRepository(configurations: configuredLifts())
        let boundary = ScheduleTemplateBoundary(
            repository: repository,
            clock: FixedScheduleClock(date: Date(timeIntervalSince1970: 300)),
            uuidGenerator: ScheduleUUIDGenerator(),
        )
        let initial = try await boundary.list()
        _ = try await boundary.confirm(
            boundary.preview(
                ScheduleTemplateRequest(
                    sessions: initial.sessions.map { session in
                        ScheduleSessionRequest(
                            id: session.id,
                            intendedWeekday: .sunday,
                            primaryLiftID: session.primaryLiftID,
                            assistanceLiftID: session.assistanceLiftID,
                        )
                    },
                ),
            ),
        )

        let preview = try await boundary.previewReset()
        XCTAssertEqual(preview.action, .reset)
        XCTAssertEqual(
            preview.after.sessions.map(\.intendedWeekday), [.monday, .tuesday, .thursday, .friday],
        )
        let beforeReset = try await boundary.list()
        XCTAssertNotEqual(beforeReset, preview.after)
        let audit = try await boundary.confirm(preview)
        let lastBefore = await repository.scheduleTemplateSnapshotBeforeLastAudit()
        let auditCount = try await boundary.auditHistory().count

        XCTAssertEqual(audit.action, .reset)
        XCTAssertEqual(audit.before, lastBefore)
        XCTAssertEqual(auditCount, 2)
    }

    private func configuredLifts() throws -> [LiftConfiguration] {
        try [
            LiftConfiguration(id: "squat", identity: .progression(.squat), trainingMaxKg: 100),
            LiftConfiguration(id: "deadlift", identity: .progression(.deadlift), trainingMaxKg: 140),
            LiftConfiguration(id: "bench", identity: .progression(.benchPress), trainingMaxKg: 75),
            LiftConfiguration(
                id: "press", identity: .progression(.overheadPress), trainingMaxKg: 50,
            ),
            LiftConfiguration(
                id: "rdl", identity: .variant(name: "Romanian Deadlift"), trainingMaxKg: 90,
            ),
        ]
    }
}

private struct FixedScheduleClock: Clock {
    let date: Date

    func now() -> Date {
        date
    }
}

private final class ScheduleUUIDGenerator: UUIDGenerator, @unchecked Sendable {
    private var value = 0

    func makeUUID() -> UUID {
        defer { value += 1 }
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private actor InMemoryTrainingRepository: TrainingRepository {
    private var configurationsByID: [String: LiftConfiguration]
    private(set) var scheduleTemplate: ScheduleTemplate?
    private(set) var scheduleAudits: [ScheduleTemplateAuditEntry] = []

    init(configurations: [LiftConfiguration]) {
        configurationsByID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
    }

    func prepareStores() async throws {}

    func loadLiftConfigurations() async throws -> [LiftConfiguration] {
        configurationsByID.values.sorted { $0.id < $1.id }
    }

    func saveLiftConfiguration(
        _ configuration: LiftConfiguration,
        expectedBefore: LiftConfigurationSnapshot?,
        auditID: String,
        occurredAt: Int64,
        action: LiftConfigurationAuditAction,
    ) async throws -> LiftConfigurationAuditEntry {
        let before = configurationsByID[configuration.id]?.snapshot
        guard before == expectedBefore else {
            throw LiftConfigurationRepositoryError.staleConfiguration
        }
        configurationsByID[configuration.id] = configuration
        return LiftConfigurationAuditEntry(
            id: auditID,
            liftID: configuration.id,
            action: action,
            occurredAt: occurredAt,
            before: before,
            after: configuration.snapshot,
        )
    }

    func auditHistory(for _: String) async throws -> [LiftConfigurationAuditEntry] {
        []
    }

    func loadScheduleTemplate() async throws -> ScheduleTemplate? {
        scheduleTemplate
    }

    func saveScheduleTemplate(
        _ template: ScheduleTemplate,
        expectedBefore: ScheduleTemplateSnapshot?,
        auditID: String,
        occurredAt: Int64,
        action: ScheduleTemplateAuditAction,
    ) async throws -> ScheduleTemplateAuditEntry {
        let before = scheduleTemplate?.snapshot
        guard before == expectedBefore else {
            throw ScheduleTemplateRepositoryError.staleTemplate
        }
        let audit = ScheduleTemplateAuditEntry(
            id: auditID,
            templateID: template.id,
            action: action,
            occurredAt: occurredAt,
            before: before,
            after: template.snapshot,
        )
        scheduleTemplate = template
        scheduleAudits.append(audit)
        return audit
    }

    func scheduleTemplateAuditHistory() async throws -> [ScheduleTemplateAuditEntry] {
        scheduleAudits
    }

    func scheduleTemplateSnapshotBeforeLastAudit() -> ScheduleTemplateSnapshot? {
        scheduleAudits.last?.before
    }
}
