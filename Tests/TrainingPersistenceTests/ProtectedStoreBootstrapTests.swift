import Foundation
import GRDB
@testable import TrainingPersistence
import XCTest

final class ProtectedStoreBootstrapTests: XCTestCase {
    func testCreatesSeparateProtectedStoresAndExcludesOnlyReconstructibleDataFromBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let protection = ProtectionSpy()
        let bootstrapper = ProtectedStoreBootstrapper(protection: protection)

        let stores = try bootstrapper.open(in: root)

        XCTAssertNotEqual(stores.authoritative.path, stores.reconstructible.path)
        XCTAssertEqual(
            try stores.authoritative.read { db in
                try Int.fetchOne(db, sql: "SELECT owner_data_accepted FROM gate_zero_metadata")
            },
            0,
        )
        XCTAssertEqual(
            try stores.authoritative.read { db in
                try Int.fetchOne(db, sql: "SELECT schema_version FROM gate_zero_metadata")
            },
            16,
        )
        XCTAssertEqual(
            try stores.reconstructible.read { db in
                try Int.fetchOne(db, sql: "SELECT owner_data_accepted FROM gate_zero_metadata")
            },
            0,
        )
        XCTAssertEqual(
            try stores.reconstructible.read { db in
                try Int.fetchOne(db, sql: "SELECT schema_version FROM gate_zero_metadata")
            },
            10,
        )

        let locations = StoreLocations(root: root)
        XCTAssertEqual(
            protection.protectedDirectories,
            [
                locations.authoritativeDirectory,
                locations.reconstructibleDirectory,
                locations.authoritativeDatabase,
                locations.reconstructibleDatabase,
            ],
        )
        XCTAssertEqual(protection.backupExcludedDirectories, [locations.reconstructibleDirectory])
        XCTAssertEqual(protection.verifiedProtectedDirectories, protection.protectedDirectories)
        XCTAssertEqual(
            protection.verifiedBackupExcludedDirectories, protection.backupExcludedDirectories,
        )
    }

    func testRetriesBetweenStoreMigrationsWithoutDuplicatingMigrations() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let checkpoint = InterruptOnceCheckpoint()
        let bootstrapper = ProtectedStoreBootstrapper(checkpoint: checkpoint)

        XCTAssertThrowsError(try bootstrapper.open(in: root))
        let stores = try bootstrapper.open(in: root)

        XCTAssertEqual(
            try stores.authoritative.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gate_zero_metadata")
            },
            1,
        )
        XCTAssertEqual(
            try stores.reconstructible.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gate_zero_metadata")
            },
            1,
        )
    }

    func testUpgradesAV6StoreDirectlyToV7() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootstrapper = ProtectedStoreBootstrapper()
        let stores = try bootstrapper.open(in: root)

        try stores.authoritative.write { db in
            try db.execute(
                sql: "INSERT INTO session_completions (session_id, confirmed_at) VALUES (?, ?)",
                arguments: ["existing-session", 42],
            )
            for table in ["session_correction_audit", "session_projections"] {
                try db.execute(sql: "DROP TABLE \(table)")
            }
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: ["authoritative_v7_session_corrections"],
            )
        }

        let upgraded = try bootstrapper.open(in: root)
        XCTAssertTrue(
            try upgraded.authoritative.read { db in
                let omitted = try db.tableExists("omitted_sets")
                let additional = try db.tableExists("additional_sets")
                let completions = try db.tableExists("session_completions")
                let projections = try db.tableExists("session_projections")
                let corrections = try db.tableExists("session_correction_audit")
                let preserved =
                    try Int.fetchOne(
                        db,
                        sql: "SELECT confirmed_at FROM session_completions WHERE session_id = ?",
                        arguments: ["existing-session"],
                    ) == 42
                return omitted && additional && completions && projections && corrections && preserved
            },
        )
    }

    func testVerifiesEveryReleasedMigrationPrefixDirectlyToCurrent() throws {
        let report = try TrainingMigrationCompatibilityVerifier(
            temporaryDirectory: FileManager.default.temporaryDirectory
                .appending(
                    path: "training-migration-verification-\(UUID().uuidString)", directoryHint: .isDirectory,
                ),
        ).verify()

        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.authoritative.map(\.sourceVersion), Array(1 ... 16))
        XCTAssertEqual(report.reconstructible.map(\.sourceVersion), Array(1 ... 10))
        XCTAssertEqual(report.authoritative.last?.targetVersion, 16)
        XCTAssertEqual(report.reconstructible.last?.targetVersion, 10)
        XCTAssertEqual(report.exportSchemaVersions, [1])
        XCTAssertTrue(report.exportVerified)
    }

    func testMigrationSpaceRefusalHappensBeforeAnySchemaMutationAndReportsProgress() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "training-migration-space-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = MigrationPhaseRecorder()
        let bootstrapper = ProtectedStoreBootstrapper(
            spaceProvider: FixedMigrationSpaceProvider(availableBytes: 0),
            progress: { recorder.record($0.phase) },
        )

        XCTAssertThrowsError(try bootstrapper.open(in: root)) { error in
            XCTAssertEqual(
                error as? StoreMigrationError,
                .insufficientSpace(requiredBytes: 78644, availableBytes: 0),
            )
        }
        XCTAssertEqual(recorder.phases, [.checkingSpace])
        let locations = StoreLocations(root: root)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: locations.authoritativeMigrationDiagnostic.path()),
        )
    }
}

private final class ProtectionSpy: StoreProtectionManaging, @unchecked Sendable {
    private(set) var protectedDirectories: [URL] = []
    private(set) var backupExcludedDirectories: [URL] = []
    private(set) var verifiedProtectedDirectories: [URL] = []
    private(set) var verifiedBackupExcludedDirectories: [URL] = []

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func applyCompleteFileProtection(to url: URL) throws {
        protectedDirectories.append(url)
    }

    func excludeFromBackup(_ url: URL) throws {
        backupExcludedDirectories.append(url)
    }

    func verifyCompleteFileProtection(at url: URL) throws {
        verifiedProtectedDirectories.append(url)
    }

    func verifyExcludedFromBackup(at url: URL) throws {
        verifiedBackupExcludedDirectories.append(url)
    }
}

private final class InterruptOnceCheckpoint: StoreBootstrapCheckpointing, @unchecked Sendable {
    private var shouldInterrupt = true

    func didMigrateAuthoritativeStore() throws {
        if shouldInterrupt {
            shouldInterrupt = false
            throw TestStoreBootstrapError.interrupted
        }
    }
}

private enum TestStoreBootstrapError: Error {
    case interrupted
}

private struct FixedMigrationSpaceProvider: StoreMigrationSpaceProviding {
    let availableBytes: Int64

    func availableMigrationSpaceBytes(at _: URL) throws -> Int64 {
        availableBytes
    }
}

private final class MigrationPhaseRecorder: @unchecked Sendable {
    private(set) var phases: [StoreMigrationPhase] = []
    private let lock = NSLock()

    func record(_ phase: StoreMigrationPhase) {
        lock.lock()
        phases.append(phase)
        lock.unlock()
    }
}
