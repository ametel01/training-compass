import Foundation
import GRDB
import TrainingApplication

public actor GRDBTrainingRepository: TrainingRepository {
  private let root: URL
  private let bootstrapper: ProtectedStoreBootstrapper
  private var stores: TrainingStores?

  public init(root: URL, bootstrapper: ProtectedStoreBootstrapper = .init()) {
    self.root = root
    self.bootstrapper = bootstrapper
  }

  public func prepareStores() async throws {
    guard stores == nil else { return }
    stores = try bootstrapper.open(in: root)
  }

  public func loadLiftConfigurations() async throws -> [LiftConfiguration] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, identity_kind, identity_value, training_max_kg, loading_increment_kg
          FROM lifts
          ORDER BY identity_value COLLATE NOCASE, id
          """
      ).map(Self.configuration(from:))
    }
  }

  public func saveLiftConfiguration(
    _ configuration: LiftConfiguration,
    auditID: String,
    occurredAt: Int64,
    action: LiftConfigurationAuditAction
  ) async throws -> LiftConfigurationAuditEntry {
    let stores = try await readyStores()
    let after = configuration.snapshot
    return try await stores.authoritative.write { db in
      let id = configuration.id
      let beforeRow = try Row.fetchOne(
        db,
        sql: """
          SELECT identity_kind, identity_value, training_max_kg, loading_increment_kg
          FROM lifts WHERE id = ?
          """,
        arguments: [id]
      )
      let before = try beforeRow.map(Self.snapshot(from:))
      let identity = Self.identityParts(configuration.identity)
      let timestamp = occurredAt
      try db.execute(
        sql: """
          INSERT INTO lifts
            (id, identity_kind, identity_value, training_max_kg, loading_increment_kg, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            identity_kind = excluded.identity_kind,
            identity_value = excluded.identity_value,
            training_max_kg = excluded.training_max_kg,
            loading_increment_kg = excluded.loading_increment_kg,
            updated_at = excluded.updated_at
          """,
        arguments: [
          id,
          identity.kind,
          identity.value,
          configuration.trainingMax.kg,
          configuration.loadingIncrement.kg,
          timestamp,
          timestamp,
        ]
      )
      try db.execute(
        sql: """
          INSERT INTO lift_configuration_audit
            (id, lift_id, action, occurred_at,
             before_identity_kind, before_identity_value, before_training_max_kg, before_loading_increment_kg,
             after_identity_kind, after_identity_value, after_training_max_kg, after_loading_increment_kg)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          auditID,
          id,
          action.rawValue,
          timestamp,
          before.map { Self.identityParts($0.identity).kind },
          before.map { Self.identityParts($0.identity).value },
          before?.trainingMaxKg,
          before?.loadingIncrementKg,
          identity.kind,
          identity.value,
          after.trainingMaxKg,
          after.loadingIncrementKg,
        ]
      )
      return LiftConfigurationAuditEntry(
        id: auditID,
        liftID: configuration.id,
        action: action,
        occurredAt: occurredAt,
        before: before,
        after: after
      )
    }
  }

  public func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, lift_id, action, occurred_at,
                 before_identity_kind, before_identity_value, before_training_max_kg, before_loading_increment_kg,
                 after_identity_kind, after_identity_value, after_training_max_kg, after_loading_increment_kg
          FROM lift_configuration_audit
          WHERE lift_id = ?
          ORDER BY occurred_at, rowid
          """,
        arguments: [liftID]
      ).map(Self.auditEntry(from:))
    }
  }

  private func readyStores() async throws -> TrainingStores {
    try await prepareStores()
    guard let stores else { throw PersistenceError.storesUnavailable }
    return stores
  }

  private static func identityParts(_ identity: LiftIdentity) -> (kind: String, value: String) {
    switch identity {
    case .progression(let lift):
      (LiftIdentity.Kind.progression.rawValue, lift.rawValue)
    case .variant(let name):
      (LiftIdentity.Kind.variant.rawValue, name)
    case .custom(let name):
      (LiftIdentity.Kind.custom.rawValue, name)
    }
  }

  private static func identity(kind: String, value: String) throws -> LiftIdentity {
    switch kind {
    case LiftIdentity.Kind.progression.rawValue:
      guard let lift = ProgressionLift(rawValue: value) else {
        throw PersistenceError.invalidIdentity
      }
      return .progression(lift)
    case LiftIdentity.Kind.variant.rawValue:
      return .variant(name: value)
    case LiftIdentity.Kind.custom.rawValue:
      return .custom(name: value)
    default:
      throw PersistenceError.invalidIdentity
    }
  }

  private static func configuration(from row: Row) throws -> LiftConfiguration {
    try LiftConfiguration(
      id: row["id"],
      identity: identity(kind: row["identity_kind"], value: row["identity_value"]),
      trainingMax: try TrainingMax(kg: row["training_max_kg"]),
      loadingIncrement: try LoadingIncrement(kg: row["loading_increment_kg"])
    )
  }

  private static func snapshot(from row: Row) throws -> LiftConfigurationSnapshot {
    LiftConfigurationSnapshot(
      identity: try identity(kind: row["identity_kind"], value: row["identity_value"]),
      trainingMaxKg: row["training_max_kg"],
      loadingIncrementKg: row["loading_increment_kg"]
    )
  }

  private static func auditEntry(from row: Row) throws -> LiftConfigurationAuditEntry {
    let before: LiftConfigurationSnapshot?
    if row["before_identity_kind"] as String? == nil {
      before = nil
    } else {
      before = LiftConfigurationSnapshot(
        identity: try identity(
          kind: row["before_identity_kind"],
          value: row["before_identity_value"]
        ),
        trainingMaxKg: row["before_training_max_kg"],
        loadingIncrementKg: row["before_loading_increment_kg"]
      )
    }
    guard let action = LiftConfigurationAuditAction(rawValue: row["action"]) else {
      throw PersistenceError.invalidAuditAction
    }
    return LiftConfigurationAuditEntry(
      id: row["id"],
      liftID: row["lift_id"],
      action: action,
      occurredAt: row["occurred_at"],
      before: before,
      after: LiftConfigurationSnapshot(
        identity: try identity(
          kind: row["after_identity_kind"],
          value: row["after_identity_value"]
        ),
        trainingMaxKg: row["after_training_max_kg"],
        loadingIncrementKg: row["after_loading_increment_kg"]
      )
    )
  }
}

public enum PersistenceError: Error, Equatable, Sendable {
  case invalidIdentity
  case invalidAuditAction
  case storesUnavailable
}

public enum TrainingPersistenceModule {}
