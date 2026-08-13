import Foundation
import GRDB
import XCTest

@testable import TrainingPersistence

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
      0
    )
    XCTAssertEqual(
      try stores.reconstructible.read { db in
        try Int.fetchOne(db, sql: "SELECT owner_data_accepted FROM gate_zero_metadata")
      },
      0
    )

    let locations = StoreLocations(root: root)
    XCTAssertEqual(
      protection.protectedDirectories,
      [
        locations.authoritativeDirectory,
        locations.reconstructibleDirectory,
        locations.authoritativeDatabase,
        locations.reconstructibleDatabase,
      ])
    XCTAssertEqual(protection.backupExcludedDirectories, [locations.reconstructibleDirectory])
    XCTAssertEqual(protection.verifiedProtectedDirectories, protection.protectedDirectories)
    XCTAssertEqual(
      protection.verifiedBackupExcludedDirectories, protection.backupExcludedDirectories)
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
      1
    )
    XCTAssertEqual(
      try stores.reconstructible.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gate_zero_metadata")
      },
      1
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
        arguments: ["existing-session", 42])
      for table in ["session_correction_audit", "session_projections"] {
        try db.execute(sql: "DROP TABLE \(table)")
      }
      try db.execute(
        sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
        arguments: ["authoritative_v7_session_corrections"]
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
            arguments: ["existing-session"]
          ) == 42
        return omitted && additional && completions && projections && corrections && preserved
      }
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
