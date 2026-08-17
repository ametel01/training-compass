import Foundation
@testable import TrainingApplication
@testable import TrainingDomain
@testable import TrainingPersistence
import XCTest

final class TrainingImportRepositoryTests: XCTestCase {
    func testCompatibilityExportFixtureRoundTripsThroughStagingAndImport() async throws {
        let destinationRoot = temporaryRoot("compatibility-fixture")
        defer { try? FileManager.default.removeItem(at: destinationRoot) }
        let destination = GRDBTrainingRepository(root: destinationRoot)
        let data = try TrainingCompassExport.makeCompatibilityFixture().encodedData()

        let result = try await TrainingImportBoundary(repository: destination).importArchive(
            data: data,
            confirmation: .confirmed,
        )

        XCTAssertEqual(result.recordCount, 1)
        let lifts = try await destination.loadLiftConfigurations()
        XCTAssertEqual(lifts.count, 0)
    }

    func testValidatedExportReplacesCurrentAuthoritativeDataAndRegeneratesProjection() async throws {
        let sourceRoot = temporaryRoot("source")
        let destinationRoot = temporaryRoot("destination")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        let source = GRDBTrainingRepository(root: sourceRoot)
        let lift = try LiftConfiguration(
            id: "lift-squat", identity: .progression(.squat), trainingMax: TrainingMax(kg: 100),
        )
        _ = try await source.saveLiftConfiguration(
            lift, expectedBefore: nil, auditID: "audit-1", occurredAt: 10, action: .created,
        )
        let archiveData = try await makeArchiveData(source: source)

        let destination = GRDBTrainingRepository(root: destinationRoot)
        let destinationLift = try LiftConfiguration(
            id: "lift-bench", identity: .progression(.benchPress), trainingMax: TrainingMax(kg: 80),
        )
        _ = try await destination.saveLiftConfiguration(
            destinationLift, expectedBefore: nil, auditID: "audit-old", occurredAt: 11, action: .created,
        )

        let boundary = TrainingImportBoundary(repository: destination)
        do {
            _ = try await boundary.importArchive(data: archiveData, confirmation: .confirmed)
            XCTFail("Replacing a non-empty store needs export-first confirmation")
        } catch let error as TrainingImportError {
            XCTAssertEqual(error, .replacementConfirmationRequired)
        }
        let result = try await boundary.importArchive(
            data: archiveData, confirmation: .confirmedAfterExport,
        )
        XCTAssertEqual(result.recordCount, 4)
        let restoredLifts = try await destination.loadLiftConfigurations().map(\.id)
        XCTAssertEqual(restoredLifts, [lift.id])
        let isEmpty = try await destination.authoritativeStoreIsEmpty()
        XCTAssertFalse(isEmpty)
    }

    func testCorruptArchiveLeavesCurrentStoreUntouched() async throws {
        let sourceRoot = temporaryRoot("source")
        let destinationRoot = temporaryRoot("destination")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        let source = GRDBTrainingRepository(root: sourceRoot)
        let lift = try LiftConfiguration(
            id: "lift-squat", identity: .progression(.squat), trainingMax: TrainingMax(kg: 100),
        )
        _ = try await source.saveLiftConfiguration(
            lift, expectedBefore: nil, auditID: "audit-1", occurredAt: 10, action: .created,
        )
        let archiveData = try await makeArchiveData(source: source)
        var corrupt = archiveData
        corrupt[corrupt.index(corrupt.startIndex, offsetBy: 20)] ^= 0x01

        let destination = GRDBTrainingRepository(root: destinationRoot)
        let boundary = TrainingImportBoundary(repository: destination)
        do {
            _ = try await boundary.importArchive(data: corrupt, confirmation: .confirmed)
            XCTFail("Expected corrupt archive to fail")
        } catch {
            XCTAssertTrue(error is TrainingImportError)
        }
        let isEmpty = try await destination.authoritativeStoreIsEmpty()
        XCTAssertTrue(isEmpty)
    }

    func testEveryReplacementPhaseFailureLeavesTheOriginalAuthoritativeDataValid() async throws {
        let sourceRoot = temporaryRoot("phase-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let source = GRDBTrainingRepository(root: sourceRoot)
        let sourceLift = try LiftConfiguration(
            id: "lift-squat", identity: .progression(.squat), trainingMax: TrainingMax(kg: 100),
        )
        _ = try await source.saveLiftConfiguration(
            sourceLift, expectedBefore: nil, auditID: "source-audit", occurredAt: 10, action: .created,
        )
        let archiveData = try await makeArchiveData(source: source)

        for phase in [
            TrainingImportPhase.staging,
            .migrating,
            .validatingStaging,
            .regeneratingProjections,
            .closingCurrentStore,
            .swappingAuthoritativeStore,
        ] {
            let destinationRoot = temporaryRoot("phase-destination")
            defer { try? FileManager.default.removeItem(at: destinationRoot) }
            let observer = FailingImportPhaseObserver(failingPhase: phase)
            let destination = GRDBTrainingRepository(root: destinationRoot, phaseObserver: observer)
            let originalLift = try LiftConfiguration(
                id: "lift-bench", identity: .progression(.benchPress), trainingMax: TrainingMax(kg: 80),
            )
            _ = try await destination.saveLiftConfiguration(
                originalLift, expectedBefore: nil, auditID: "original-audit", occurredAt: 11,
                action: .created,
            )
            let boundary = TrainingImportBoundary(repository: destination)

            do {
                _ = try await boundary.importArchive(
                    data: archiveData, confirmation: .confirmedAfterExport,
                )
                XCTFail("Expected injected failure at \(phase)")
            } catch is TrainingImportError {
                // The phase observer deliberately simulates termination/failure.
            }
            let remainingLiftIDs = try await destination.loadLiftConfigurations().map(\.id)
            XCTAssertEqual(remainingLiftIDs, [originalLift.id])
        }
    }

    private func makeArchiveData(source: GRDBTrainingRepository) async throws -> Data {
        let boundary = TrainingExportBoundary(
            repository: source,
            clock: FixedClock(date: Date(timeIntervalSince1970: 42)),
            timeZone: FixedTimeZone(identifier: "UTC"),
            uuidGenerator: FixedUUIDGenerator(),
        )
        return try await boundary.create(boundary.preview(), confirmation: .confirmed)
            .archive.encodedData()
    }

    private func temporaryRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "training-import-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private struct FixedClock: Clock {
    let date: Date
    func now() -> Date {
        date
    }
}

private struct FixedTimeZone: TimeZoneProvider {
    let identifier: String
    func timeZone() -> TimeZone {
        TimeZone(identifier: identifier)!
    }
}

private struct FixedUUIDGenerator: UUIDGenerator {
    func makeUUID() -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }
}

private struct FailingImportPhaseObserver: TrainingImportPhaseObserver {
    let failingPhase: TrainingImportPhase

    func didReach(_ phase: TrainingImportPhase) throws {
        if phase == failingPhase {
            throw InjectedImportFailure()
        }
    }
}

private struct InjectedImportFailure: Error {}
