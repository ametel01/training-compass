import Foundation
import GRDB
import TrainingApplication

/// The two on-device stores intentionally have independent migration histories.
public enum TrainingStoreKind: String, Codable, Equatable, Sendable {
  case authoritative
  case reconstructible
}

public struct TrainingMigrationDescriptor: Codable, Equatable, Sendable, Identifiable {
  public let store: TrainingStoreKind
  public let version: Int
  public let identifier: String

  public init(store: TrainingStoreKind, version: Int, identifier: String) {
    self.store = store
    self.version = version
    self.identifier = identifier
  }

  public var id: String { identifier }
}

public struct TrainingMigrationVerification: Codable, Equatable, Sendable {
  public let store: TrainingStoreKind
  public let sourceVersion: Int
  public let targetVersion: Int
  public let migrationIdentifier: String
  public let deterministic: Bool
  public let preservedGateZeroMarker: Bool
  public let completedMigrationCount: Int
  public let finalSchemaVersion: Int

  public init(
    store: TrainingStoreKind,
    sourceVersion: Int,
    targetVersion: Int,
    migrationIdentifier: String,
    deterministic: Bool,
    preservedGateZeroMarker: Bool,
    completedMigrationCount: Int,
    finalSchemaVersion: Int
  ) {
    self.store = store
    self.sourceVersion = sourceVersion
    self.targetVersion = targetVersion
    self.migrationIdentifier = migrationIdentifier
    self.deterministic = deterministic
    self.preservedGateZeroMarker = preservedGateZeroMarker
    self.completedMigrationCount = completedMigrationCount
    self.finalSchemaVersion = finalSchemaVersion
  }

  public var passed: Bool {
    deterministic && preservedGateZeroMarker && completedMigrationCount == targetVersion
      && finalSchemaVersion == targetVersion
  }
}

public struct TrainingMigrationCompatibilityReport: Codable, Equatable, Sendable {
  public let authoritative: [TrainingMigrationVerification]
  public let reconstructible: [TrainingMigrationVerification]
  public let exportSchemaVersions: [Int]
  public let exportVerified: Bool

  public init(
    authoritative: [TrainingMigrationVerification],
    reconstructible: [TrainingMigrationVerification],
    exportSchemaVersions: [Int] = [1],
    exportVerified: Bool = false
  ) {
    self.authoritative = authoritative
    self.reconstructible = reconstructible
    self.exportSchemaVersions = exportSchemaVersions
    self.exportVerified = exportVerified
  }

  public var passed: Bool {
    !authoritative.isEmpty && !reconstructible.isEmpty
      && authoritative.allSatisfy(\.passed)
      && reconstructible.allSatisfy(\.passed)
      && exportSchemaVersions == [1]
      && exportVerified
  }

  public var migrationCount: Int { authoritative.count + reconstructible.count }
}

public enum TrainingMigrationVerificationError: Error, Equatable, Sendable {
  case unsupportedStoreVersion(TrainingStoreKind, Int)
  case incompleteMigration(TrainingStoreKind, Int)
  case nondeterministicMigration(TrainingStoreKind, Int)
  case gateZeroMarkerLost(TrainingStoreKind, Int)
}

/// Runs the same migration definitions used by the app against every released
/// schema prefix. Each prefix is built twice and upgraded directly to the
/// current version; the resulting schema fingerprints must match. The report
/// contains only versions, migration names, counts, and booleans, so it is
/// safe to retain as release evidence.
public struct TrainingMigrationCompatibilityVerifier: Sendable {
  private let temporaryDirectory: URL

  public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
    self.temporaryDirectory = temporaryDirectory
  }

  public func verify() throws -> TrainingMigrationCompatibilityReport {
    let authoritative = try verify(
      store: .authoritative,
      migrator: ProtectedStoreBootstrapper.authoritativeMigrator
    )
    let reconstructible = try verify(
      store: .reconstructible,
      migrator: ProtectedStoreBootstrapper.reconstructibleMigrator
    )
    let exportVerified = try verifyExportCompatibility()
    return TrainingMigrationCompatibilityReport(
      authoritative: authoritative,
      reconstructible: reconstructible,
      exportSchemaVersions: [1],
      exportVerified: exportVerified
    )
  }

  private func verifyExportCompatibility() throws -> Bool {
    let fixture = try TrainingCompassExport.makeCompatibilityFixture()
    let encoded = try fixture.encodedData()
    let decoded = try TrainingCompassExport.decode(encoded)
    try decoded.verifyIntegrity()
    try TrainingImportBoundary.validateAuthoritativeData(
      decoded.authoritativeData,
      summary: decoded.summary
    )
    return decoded.manifest.schemaVersion == 1
  }

  public static func descriptors(
    store: TrainingStoreKind
  ) -> [TrainingMigrationDescriptor] {
    let identifiers: [String] =
      switch store {
      case .authoritative: ProtectedStoreBootstrapper.authoritativeMigrator.migrations
      case .reconstructible: ProtectedStoreBootstrapper.reconstructibleMigrator.migrations
      }
    return identifiers.enumerated().map { offset, identifier in
      TrainingMigrationDescriptor(store: store, version: offset + 1, identifier: identifier)
    }
  }

  private func verify(
    store: TrainingStoreKind,
    migrator: DatabaseMigrator
  ) throws -> [TrainingMigrationVerification] {
    let identifiers = migrator.migrations
    guard !identifiers.isEmpty else { return [] }
    var results: [TrainingMigrationVerification] = []
    for (offset, identifier) in identifiers.enumerated() {
      let sourceVersion = offset + 1
      let first = try makeDatabase(store: store, sourceVersion: sourceVersion, migrator: migrator)
      let second = try makeDatabase(store: store, sourceVersion: sourceVersion, migrator: migrator)
      defer {
        try? first.database.close()
        try? second.database.close()
        try? FileManager.default.removeItem(at: first.url)
        try? FileManager.default.removeItem(at: second.url)
      }

      try migrator.migrate(first.database)
      try migrator.migrate(second.database)
      try first.database.write { db in
        try db.execute(
          sql: "UPDATE gate_zero_metadata SET schema_version = ?",
          arguments: [identifiers.count]
        )
      }
      try second.database.write { db in
        try db.execute(
          sql: "UPDATE gate_zero_metadata SET schema_version = ?",
          arguments: [identifiers.count]
        )
      }
      let firstFingerprint = try fingerprint(first.database)
      let secondFingerprint = try fingerprint(second.database)
      let marker = try first.database.read { db in
        try Int.fetchOne(db, sql: "SELECT owner_data_accepted FROM gate_zero_metadata") == 0
      }
      let schemaVersion = try first.database.read { db in
        try Int.fetchOne(db, sql: "SELECT schema_version FROM gate_zero_metadata") ?? 0
      }
      let completed = try first.database.read { db in
        try migrator.completedMigrations(db).count
      }
      guard completed == identifiers.count else {
        throw TrainingMigrationVerificationError.incompleteMigration(store, sourceVersion)
      }
      guard marker else {
        throw TrainingMigrationVerificationError.gateZeroMarkerLost(store, sourceVersion)
      }
      guard schemaVersion == identifiers.count else {
        throw TrainingMigrationVerificationError.incompleteMigration(store, sourceVersion)
      }
      guard firstFingerprint == secondFingerprint else {
        throw TrainingMigrationVerificationError.nondeterministicMigration(store, sourceVersion)
      }
      results.append(
        TrainingMigrationVerification(
          store: store,
          sourceVersion: sourceVersion,
          targetVersion: identifiers.count,
          migrationIdentifier: identifier,
          deterministic: true,
          preservedGateZeroMarker: marker,
          completedMigrationCount: completed,
          finalSchemaVersion: schemaVersion
        ))
    }
    return results
  }

  private func makeDatabase(
    store: TrainingStoreKind,
    sourceVersion: Int,
    migrator: DatabaseMigrator
  ) throws -> (database: DatabaseQueue, url: URL) {
    let url = temporaryDirectory.appending(
      path: "training-migration-\(store.rawValue)-\(sourceVersion)-\(UUID().uuidString).sqlite"
    )
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    let database = try DatabaseQueue(path: url.path())
    try migrator.migrate(database, upTo: migrator.migrations[sourceVersion - 1])
    return (database, url)
  }

  private func fingerprint(_ database: DatabaseQueue) throws -> String {
    let payload = try database.read { db in
      let schema = try Row.fetchAll(
        db,
        sql: """
          SELECT type, name, COALESCE(sql, '') AS sql
          FROM sqlite_master
          WHERE name NOT LIKE 'sqlite_%'
          ORDER BY type, name
          """
      ).map { row in
        [row["type"] as String, row["name"] as String, row["sql"] as String]
      }
      let migrations = try String.fetchAll(
        db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(FingerprintPayload(schema: schema, migrations: migrations))
    }
    return payload.base64EncodedString()
  }
}

private struct FingerprintPayload: Encodable {
  let schema: [[String]]
  let migrations: [String]
}
