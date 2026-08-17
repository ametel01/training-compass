@testable import TrainingApplication
import XCTest

final class TrainingErasureBoundaryTests: XCTestCase {
    func testRequiresExplicitConfirmationAndNamesEveryLocalCopy() async throws {
        let repository = ErasureRepositorySpy()
        let boundary = TrainingErasureBoundary(repository: repository)

        XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("Locally Authoritative Data"))
        XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("HealthKit Mirror"))
        XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("Derived Projections"))
        XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("preferences"))
        XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("sync state"))
        XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("temporary exports"))
        XCTAssertTrue(TrainingErasureCopy.externalCopiesMessage.contains("device or iCloud backups"))
        XCTAssertTrue(TrainingErasureCopy.externalCopiesMessage.contains("previously shared exports"))
        XCTAssertTrue(TrainingErasureCopy.externalCopiesMessage.contains("HealthKit data"))
        XCTAssertFalse(TrainingErasureCopy.confirmationMessage.contains("backups"))
        XCTAssertFalse(TrainingErasureCopy.confirmationMessage.contains("HealthKit data"))

        do {
            _ = try await boundary.erase(confirmation: .cancelled)
            XCTFail("Cancellation should not erase local data")
        } catch let error as TrainingErasureError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        let cancelledCalls = await repository.eraseCallCount
        XCTAssertEqual(cancelledCalls, 0)
    }

    func testConfirmedErasureDelegatesToRepository() async throws {
        let repository = ErasureRepositorySpy()
        let boundary = TrainingErasureBoundary(repository: repository)

        let result = try await boundary.erase(confirmation: .confirmed)

        XCTAssertEqual(result, .completed)
        let confirmedCalls = await repository.eraseCallCount
        XCTAssertEqual(confirmedCalls, 1)
    }

    func testHealthKitDeletionPrecedesLocalErasureAndStopsOnPartialFailure() async throws {
        let repository = ErasureRepositorySpy()
        let writeBackRepository = ErasureWriteBackRepositorySpy()
        await writeBackRepository.seed(
            HealthWorkoutWriteBackRecord(
                sessionID: "session", syncIdentifier: "sync.session", state: .savedToHealth,
                startDate: Date(timeIntervalSince1970: 1), endDate: Date(timeIntervalSince1970: 2),
                healthKitUUID: "health-workout",
            ),
        )
        let client = ErasureHealthClientSpy()
        await client.setDeleteFailure(true)
        let writeBackBoundary = HealthWorkoutWriteBackBoundary(
            repository: writeBackRepository, client: client, clock: ErasureClock(),
        )
        let boundary = TrainingErasureBoundary(
            repository: repository, healthWorkoutWriteBackBoundary: writeBackBoundary,
        )

        let partial = try await boundary.erase(
            confirmation: .confirmed, deleteHealthKitWriteBacks: true,
        )

        guard case let .healthKitDeletionIncomplete(deletion) = partial else {
            return XCTFail("Local erasure must wait for HealthKit deletion")
        }
        XCTAssertFalse(deletion.isComplete)
        let eraseCallsAfterPartial = await repository.eraseCallCount
        let deleteCallsAfterPartial = await client.deleteRequestCount
        XCTAssertEqual(eraseCallsAfterPartial, 0)
        XCTAssertEqual(deleteCallsAfterPartial, 1)

        await client.setDeleteFailure(false)
        let completed = try await boundary.erase(
            confirmation: .confirmed, deleteHealthKitWriteBacks: true,
        )

        XCTAssertEqual(completed, .completed)
        let eraseCallsAfterCompletion = await repository.eraseCallCount
        XCTAssertEqual(eraseCallsAfterCompletion, 1)
    }

    func testCancellationDoesNotAttemptHealthKitDeletion() async throws {
        let repository = ErasureRepositorySpy()
        let writeBackRepository = ErasureWriteBackRepositorySpy()
        let client = ErasureHealthClientSpy()
        let writeBackBoundary = HealthWorkoutWriteBackBoundary(
            repository: writeBackRepository, client: client, clock: ErasureClock(),
        )
        let boundary = TrainingErasureBoundary(
            repository: repository, healthWorkoutWriteBackBoundary: writeBackBoundary,
        )

        do {
            _ = try await boundary.erase(
                confirmation: .cancelled, deleteHealthKitWriteBacks: true,
            )
            XCTFail("Cancellation should not start external deletion")
        } catch let error as TrainingErasureError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        let deleteCallsAfterCancellation = await client.deleteRequestCount
        let eraseCallsAfterCancellation = await repository.eraseCallCount
        XCTAssertEqual(deleteCallsAfterCancellation, 0)
        XCTAssertEqual(eraseCallsAfterCancellation, 0)
    }

    func testAcknowledgedLocalOnlyContinuationErasesAfterDeletionFailure() async throws {
        let repository = ErasureRepositorySpy()
        let writeBackRepository = ErasureWriteBackRepositorySpy()
        await writeBackRepository.seed(
            HealthWorkoutWriteBackRecord(
                sessionID: "session", syncIdentifier: "sync.session", state: .savedToHealth,
                startDate: Date(timeIntervalSince1970: 1), endDate: Date(timeIntervalSince1970: 2),
                healthKitUUID: "health-workout",
            ),
        )
        let client = ErasureHealthClientSpy()
        await client.setDeleteFailure(true)
        let writeBackBoundary = HealthWorkoutWriteBackBoundary(
            repository: writeBackRepository, client: client, clock: ErasureClock(),
        )
        let boundary = TrainingErasureBoundary(
            repository: repository, healthWorkoutWriteBackBoundary: writeBackBoundary,
        )

        let incomplete = try await boundary.erase(
            confirmation: .confirmed, deleteHealthKitWriteBacks: true,
        )
        guard case .healthKitDeletionIncomplete = incomplete else {
            return XCTFail("The failed external deletion should require an explicit second choice")
        }

        let completed = try await boundary.erase(
            confirmation: .confirmed, deleteHealthKitWriteBacks: false,
        )

        XCTAssertEqual(completed, .completed)
        let eraseCalls = await repository.eraseCallCount
        XCTAssertEqual(eraseCalls, 1)
    }
}

private actor ErasureRepositorySpy: TrainingErasureRepository {
    private(set) var eraseCallCount = 0

    func eraseAllData(progress: TrainingErasureProgressHandler?) async throws {
        eraseCallCount += 1
        progress?(.init(phase: .completed, fraction: 1, message: "Erased"))
    }
}

private actor ErasureWriteBackRepositorySpy: HealthWorkoutWriteBackRepository {
    private var record: HealthWorkoutWriteBackRecord?

    func loadHealthWorkoutWriteBackPreference() async throws -> HealthWorkoutWriteBackPreference {
        .init(enabled: true)
    }

    func saveHealthWorkoutWriteBackPreference(
        _: HealthWorkoutWriteBackPreference,
    ) async throws {}

    func loadHealthWorkoutWriteBack(sessionID: String) async throws -> HealthWorkoutWriteBackRecord? {
        record?.sessionID == sessionID ? record : nil
    }

    func loadHealthWorkoutWriteBacks() async throws -> [HealthWorkoutWriteBackRecord] {
        record.map { [$0] } ?? []
    }

    func saveHealthWorkoutWriteBack(_ record: HealthWorkoutWriteBackRecord) async throws {
        self.record = record
    }

    func loadHealthWorkoutLinkFacts(
        forLocalEntityID _: String,
    ) async throws -> [HealthWorkoutLinkFact] {
        []
    }

    func seed(_ record: HealthWorkoutWriteBackRecord) {
        self.record = record
    }
}

private actor ErasureHealthClientSpy: HealthWorkoutWriteBackClient {
    private(set) var deleteRequestCount = 0
    private var deleteFailure = false

    func requestWriteAuthorization() async throws -> HealthAuthorizationSnapshot {
        .init(state: .authorized)
    }

    func saveWorkout(_: HealthWorkoutWriteBackSummary) async throws -> String {
        "health"
    }

    func workoutExists(syncIdentifier _: String) async throws -> Bool {
        false
    }

    func deleteWorkout(healthKitUUID _: String) async throws {
        deleteRequestCount += 1
        if deleteFailure {
            throw HealthWorkoutWriteBackClientError.protectedDataUnavailable
        }
    }

    func setDeleteFailure(_ value: Bool) {
        deleteFailure = value
    }
}

private struct ErasureClock: Clock {
    func now() -> Date {
        Date(timeIntervalSince1970: 10)
    }
}
