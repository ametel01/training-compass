import Foundation
import GRDB

public final class TrainingStores: @unchecked Sendable {
  public let authoritative: DatabaseQueue
  public let reconstructible: DatabaseQueue

  init(authoritative: DatabaseQueue, reconstructible: DatabaseQueue) {
    self.authoritative = authoritative
    self.reconstructible = reconstructible
  }
}

public struct ProtectedStoreBootstrapper: Sendable {
  private let protection: any StoreProtectionManaging
  private let checkpoint: any StoreBootstrapCheckpointing

  public init(
    protection: any StoreProtectionManaging = FileManagerStoreProtection(),
    checkpoint: any StoreBootstrapCheckpointing = NoOpStoreBootstrapCheckpoint()
  ) {
    self.protection = protection
    self.checkpoint = checkpoint
  }

  public func open(in root: URL) throws -> TrainingStores {
    let locations = StoreLocations(root: root)
    try prepareDirectory(locations.authoritativeDirectory, excludedFromBackup: false)
    try prepareDirectory(locations.reconstructibleDirectory, excludedFromBackup: true)

    var configuration = Configuration()
    configuration.label = "TrainingCompass"
    let authoritative = try DatabaseQueue(
      path: locations.authoritativeDatabase.path(),
      configuration: configuration
    )
    let reconstructible = try DatabaseQueue(
      path: locations.reconstructibleDatabase.path(),
      configuration: configuration
    )

    try Self.authoritativeMigrator.migrate(authoritative)
    try checkpoint.didMigrateAuthoritativeStore()
    try Self.reconstructibleMigrator.migrate(reconstructible)

    try protection.applyCompleteFileProtection(to: locations.authoritativeDatabase)
    try protection.applyCompleteFileProtection(to: locations.reconstructibleDatabase)
    try protection.verifyCompleteFileProtection(at: locations.authoritativeDirectory)
    try protection.verifyCompleteFileProtection(at: locations.reconstructibleDirectory)
    try protection.verifyCompleteFileProtection(at: locations.authoritativeDatabase)
    try protection.verifyCompleteFileProtection(at: locations.reconstructibleDatabase)
    try protection.verifyExcludedFromBackup(at: locations.reconstructibleDirectory)

    return TrainingStores(
      authoritative: authoritative,
      reconstructible: reconstructible
    )
  }

  private func prepareDirectory(_ url: URL, excludedFromBackup: Bool) throws {
    try protection.createDirectory(at: url)
    try protection.applyCompleteFileProtection(to: url)
    if excludedFromBackup {
      try protection.excludeFromBackup(url)
    }
  }

  public static var authoritativeMigrator: DatabaseMigrator {
    gateZeroMigrator(named: "authoritative_v1_gate_zero")
  }

  public static var reconstructibleMigrator: DatabaseMigrator {
    gateZeroMigrator(named: "reconstructible_v1_gate_zero")
  }

  private static func gateZeroMigrator(named migrationName: String) -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration(migrationName) { db in
      try db.create(table: "gate_zero_metadata") { table in
        table.column("schema_version", .integer).notNull()
        table.column("owner_data_accepted", .boolean).notNull()
          .check { $0 == false }
      }
      try db.execute(
        sql: "INSERT INTO gate_zero_metadata (schema_version, owner_data_accepted) VALUES (1, 0)"
      )
    }
    return migrator
  }
}

public protocol StoreBootstrapCheckpointing: Sendable {
  func didMigrateAuthoritativeStore() throws
}

public struct NoOpStoreBootstrapCheckpoint: StoreBootstrapCheckpointing {
  public init() {}

  public func didMigrateAuthoritativeStore() throws {}
}
