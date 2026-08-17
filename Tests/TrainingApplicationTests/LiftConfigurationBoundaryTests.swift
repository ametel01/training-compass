import Foundation
@testable import TrainingApplication
@testable import TrainingDomain
import XCTest

final class LiftConfigurationBoundaryTests: XCTestCase {
    func testValidCreationUsesDefaultIncrementAndRecordsCreatedAudit() async throws {
        let repository = InMemoryLiftConfigurationRepository()
        let boundary = LiftConfigurationBoundary(
            repository: repository,
            clock: FixedClock(date: Date(timeIntervalSince1970: 123)),
            uuidGenerator: SequenceUUIDGenerator(values: [uuid(1), uuid(2)]),
        )

        let audit = try await boundary.save(
            LiftConfigurationRequest(
                identity: .progression(.benchPress),
                trainingMaxKg: 72.3,
            ),
        )

        XCTAssertEqual(audit.action, .created)
        XCTAssertNil(audit.before)
        XCTAssertEqual(audit.after.loadingIncrementKg, 2.5)
        let configurations = try await boundary.list()
        XCTAssertEqual(configurations.count, 1)
        let rows = try await boundary.listTMs()
        XCTAssertEqual(
            rows.prefix(4).map(\.identity.displayName),
            ["Squat", "Deadlift", "Bench Press", "Overhead Press"],
        )
    }

    func testInvalidReferenceIsRejectedBeforeRepositoryMutation() async throws {
        let repository = InMemoryLiftConfigurationRepository()
        let boundary = LiftConfigurationBoundary(
            repository: repository,
            clock: FixedClock(date: Date()),
            uuidGenerator: SequenceUUIDGenerator(values: [uuid(3), uuid(4)]),
        )

        do {
            _ = try await boundary.save(
                LiftConfigurationRequest(identity: .custom(name: "Home Lift"), trainingMaxKg: 0),
            )
            XCTFail("Expected invalid Training Max")
        } catch let error as WeightValidationError {
            XCTAssertEqual(error, .mustBePositive(.trainingMax))
        }

        let saved = await repository.savedCount
        XCTAssertEqual(saved, 0)
    }

    func testUnknownEditIDIsRejectedBeforeRepositoryMutation() async throws {
        let repository = InMemoryLiftConfigurationRepository()
        let boundary = LiftConfigurationBoundary(
            repository: repository,
            clock: FixedClock(date: Date()),
            uuidGenerator: SequenceUUIDGenerator(values: [uuid(17)]),
        )

        do {
            _ = try await boundary.preview(
                LiftConfigurationRequest(
                    id: "missing",
                    identity: .custom(name: "Home Lift"),
                    trainingMaxKg: 100,
                ),
            )
            XCTFail("Expected unknown edit ID")
        } catch let error as LiftConfigurationRepositoryError {
            XCTAssertEqual(error, .unknownConfiguration)
        }

        let saved = await repository.savedCount
        XCTAssertEqual(saved, 0)
    }

    func testCorrectiveEditIsDistinguishedAndPreservesTheBeforeValue() async throws {
        let repository = InMemoryLiftConfigurationRepository()
        let boundary = LiftConfigurationBoundary(
            repository: repository,
            clock: FixedClock(date: Date(timeIntervalSince1970: 500)),
            uuidGenerator: SequenceUUIDGenerator(values: [uuid(5), uuid(6), uuid(7)]),
        )
        let created = try await boundary.save(
            LiftConfigurationRequest(identity: .progression(.deadlift), trainingMaxKg: 140),
        )
        let corrected = try await boundary.save(
            LiftConfigurationRequest(
                id: created.liftID,
                identity: .progression(.deadlift),
                trainingMaxKg: 137.5,
                isCorrection: true,
            ),
        )

        XCTAssertEqual(corrected.action, .corrected)
        XCTAssertEqual(corrected.before?.trainingMaxKg, 140)
        XCTAssertEqual(corrected.after.trainingMaxKg, 137.5)
    }

    func testPreviewDoesNotMutateUntilConfirmation() async throws {
        let repository = InMemoryLiftConfigurationRepository()
        let boundary = LiftConfigurationBoundary(
            repository: repository,
            clock: FixedClock(date: Date(timeIntervalSince1970: 700)),
            uuidGenerator: SequenceUUIDGenerator(values: [uuid(8), uuid(9)]),
        )

        let preview = try await boundary.preview(
            LiftConfigurationRequest(identity: .progression(.squat), trainingMaxKg: 101),
        )
        let beforeConfirmation = try await boundary.list()
        XCTAssertEqual(beforeConfirmation.count, 0)

        let audit = try await boundary.confirm(preview)
        XCTAssertEqual(audit.action, .created)
        let afterConfirmation = try await boundary.list()
        XCTAssertEqual(afterConfirmation.count, 1)
    }

    func testStaleConfirmationCannotOverwriteAConcurrentEdit() async throws {
        let repository = InMemoryLiftConfigurationRepository()
        let boundary = LiftConfigurationBoundary(
            repository: repository,
            clock: FixedClock(date: Date(timeIntervalSince1970: 800)),
            uuidGenerator: SequenceUUIDGenerator(values: [uuid(10), uuid(11), uuid(12), uuid(13)]),
        )
        let created = try await boundary.save(
            LiftConfigurationRequest(identity: .progression(.benchPress), trainingMaxKg: 72.5),
        )
        let preview = try await boundary.preview(
            LiftConfigurationRequest(
                id: created.liftID,
                identity: .progression(.benchPress),
                trainingMaxKg: 75,
            ),
        )
        _ = try await boundary.save(
            LiftConfigurationRequest(
                id: created.liftID,
                identity: .progression(.benchPress),
                trainingMaxKg: 77.5,
            ),
        )

        do {
            _ = try await boundary.confirm(preview)
            XCTFail("Expected stale preview to be rejected")
        } catch let error as LiftConfigurationRepositoryError {
            XCTAssertEqual(error, .staleConfiguration)
        }

        let current = try await boundary.list()
        XCTAssertEqual(current.first?.trainingMaxKg, 77.5)
    }

    func testInterruptedConfirmationLeavesConfigurationAndAuditUnchangedAndCanRetry() async throws {
        let repository = InMemoryLiftConfigurationRepository()
        let boundary = LiftConfigurationBoundary(
            repository: repository,
            clock: FixedClock(date: Date(timeIntervalSince1970: 900)),
            uuidGenerator: SequenceUUIDGenerator(values: [uuid(14), uuid(15), uuid(16)]),
        )
        let preview = try await boundary.preview(
            LiftConfigurationRequest(identity: .progression(.squat), trainingMaxKg: 100),
        )
        await repository.failNextSave()

        do {
            _ = try await boundary.confirm(preview)
            XCTFail("Expected interrupted save")
        } catch is InjectedSaveError {
            // The repository failed before its atomic mutation boundary.
        }

        let interruptedConfigurations = try await boundary.list()
        let interruptedAudits = try await boundary.auditHistory(for: preview.after.id)
        XCTAssertTrue(interruptedConfigurations.isEmpty)
        XCTAssertTrue(interruptedAudits.isEmpty)

        let audit = try await boundary.confirm(preview)
        XCTAssertEqual(audit.action, .created)
        let retriedConfigurations = try await boundary.list()
        XCTAssertEqual(retriedConfigurations.first?.trainingMaxKg, 100)
    }

    private func uuid(_ value: UInt8) -> UUID {
        UUID(uuidString: String(format: "%02X000000-0000-0000-0000-000000000000", value))!
    }
}

private enum InjectedSaveError: Error {
    case interrupted
}

private struct FixedClock: Clock {
    let date: Date

    func now() -> Date {
        date
    }
}

private final class SequenceUUIDGenerator: UUIDGenerator, @unchecked Sendable {
    var values: [UUID]
    private var index = 0

    init(values: [UUID]) {
        self.values = values
    }

    func makeUUID() -> UUID {
        defer { index += 1 }
        return values[min(index, values.count - 1)]
    }
}

private actor InMemoryLiftConfigurationRepository: LiftConfigurationRepository {
    private(set) var configurations: [String: LiftConfiguration] = [:]
    private(set) var audits: [LiftConfigurationAuditEntry] = []
    private var shouldFailNextSave = false

    var savedCount: Int {
        audits.count
    }

    func failNextSave() {
        shouldFailNextSave = true
    }

    func loadLiftConfigurations() async throws -> [LiftConfiguration] {
        configurations.values.sorted { $0.id < $1.id }
    }

    func saveLiftConfiguration(
        _ configuration: LiftConfiguration,
        expectedBefore: LiftConfigurationSnapshot?,
        auditID: String,
        occurredAt: Int64,
        action: LiftConfigurationAuditAction,
    ) async throws -> LiftConfigurationAuditEntry {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw InjectedSaveError.interrupted
        }
        let before = configurations[configuration.id]?.snapshot
        guard before == expectedBefore else {
            throw LiftConfigurationRepositoryError.staleConfiguration
        }
        let audit = LiftConfigurationAuditEntry(
            id: auditID,
            liftID: configuration.id,
            action: action,
            occurredAt: occurredAt,
            before: before,
            after: configuration.snapshot,
        )
        configurations[configuration.id] = configuration
        audits.append(audit)
        return audit
    }

    func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] {
        audits.filter { $0.liftID == liftID }
    }
}
