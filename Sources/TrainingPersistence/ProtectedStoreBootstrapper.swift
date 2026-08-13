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
    #if targetEnvironment(simulator)
      // The simulator does not provide the device's protected application-support
      // filesystem semantics. Keep the same schema and transaction behavior in its
      // writable cache container so UI journeys can exercise the real repository.
      let simulatorRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "TrainingCompass", directoryHint: .isDirectory)
      let locations = StoreLocations(root: simulatorRoot)
    #else
      let locations = StoreLocations(root: root)
    #endif
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
    var migrator = gateZeroMigrator(named: "authoritative_v1_gate_zero")
    migrator.registerMigration("authoritative_v2_lift_configuration") { db in
      try db.create(table: "lifts") { table in
        table.column("id", .text).primaryKey()
        table.column("identity_kind", .text).notNull()
          .check { $0 == "progression" || $0 == "variant" || $0 == "custom" }
        table.column("identity_value", .text).notNull()
          .check { $0 != "" }
        table.column("training_max_kg", .double).notNull()
          .check { $0 > 0 }
        table.column("loading_increment_kg", .double).notNull().defaults(to: 2.5)
          .check { $0 > 0 }
        table.column("created_at", .integer).notNull()
        table.column("updated_at", .integer).notNull()
      }
      try db.create(
        index: "lifts_identity",
        on: "lifts",
        columns: ["identity_kind", "identity_value"],
        unique: true
      )
      try db.create(table: "lift_configuration_audit") { table in
        table.column("id", .text).primaryKey()
        table.column("lift_id", .text).notNull()
          .references("lifts", onDelete: .restrict)
        table.column("action", .text).notNull()
          .check { $0 == "created" || $0 == "edited" || $0 == "corrected" }
        table.column("occurred_at", .integer).notNull()
        table.column("before_identity_kind", .text)
        table.column("before_identity_value", .text)
        table.column("before_training_max_kg", .double)
        table.column("before_loading_increment_kg", .double)
        table.column("after_identity_kind", .text).notNull()
        table.column("after_identity_value", .text).notNull()
        table.column("after_training_max_kg", .double).notNull()
          .check { $0 > 0 }
        table.column("after_loading_increment_kg", .double).notNull()
          .check { $0 > 0 }
      }
      try db.create(
        index: "lift_configuration_audit_lift_time", on: "lift_configuration_audit",
        columns: [
          "lift_id", "occurred_at",
        ])
    }
    migrator.registerMigration("authoritative_v3_schedule_template") { db in
      try db.create(table: "schedule_templates") { table in
        table.column("id", .text).primaryKey()
        table.column("created_at", .integer).notNull()
        table.column("updated_at", .integer).notNull()
      }
      try db.create(table: "schedule_template_sessions") { table in
        table.column("id", .text).primaryKey()
        table.column("template_id", .text).notNull()
          .references("schedule_templates", onDelete: .cascade)
        table.column("position", .integer).notNull()
        table.column("intended_weekday", .integer).notNull()
          .check { $0 >= 1 && $0 <= 7 }
        table.column("primary_lift_id", .text).notNull()
          .references("lifts", onDelete: .restrict)
        table.column("assistance_lift_id", .text).notNull()
          .references("lifts", onDelete: .restrict)
      }
      try db.create(
        index: "schedule_template_sessions_order",
        on: "schedule_template_sessions",
        columns: ["template_id", "position"],
        unique: true
      )
      try db.create(table: "schedule_template_audit") { table in
        table.column("id", .text).primaryKey()
        table.column("template_id", .text).notNull()
        table.column("action", .text).notNull()
          .check { $0 == "created" || $0 == "edited" || $0 == "reset" }
        table.column("occurred_at", .integer).notNull()
        table.column("before_json", .text)
        table.column("after_json", .text).notNull()
      }
      try db.create(
        index: "schedule_template_audit_time", on: "schedule_template_audit",
        columns: ["template_id", "occurred_at"])
    }
    return migrator
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
