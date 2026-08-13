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
    expectedBefore: LiftConfigurationSnapshot?,
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
      guard before == expectedBefore else {
        throw LiftConfigurationRepositoryError.staleConfiguration
      }
      let identity = Self.identityParts(configuration.identity)
      let timestamp = occurredAt
      let duplicate =
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM lifts
            WHERE identity_kind = ? AND identity_value = ? AND id <> ?
            """,
          arguments: [identity.kind, identity.value, id]
        ) ?? 0
      guard duplicate == 0 else {
        throw LiftConfigurationRepositoryError.duplicateIdentity
      }
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

  public func loadScheduleTemplate() async throws -> ScheduleTemplate? {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Self.scheduleTemplate(from: db)
    }
  }

  public func saveScheduleTemplate(
    _ template: ScheduleTemplate,
    expectedBefore: ScheduleTemplateSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: ScheduleTemplateAuditAction
  ) async throws -> ScheduleTemplateAuditEntry {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard !template.sessions.isEmpty else {
        throw ScheduleTemplateValidationError.emptyTemplate
      }
      let sessionIDs = template.sessions.map(\.id)
      guard sessionIDs.allSatisfy({ !$0.isEmpty }), Set(sessionIDs).count == sessionIDs.count else {
        throw ScheduleTemplateValidationError.duplicateSessionID
      }
      let before = try Self.scheduleTemplate(from: db)
      guard before?.snapshot == expectedBefore else {
        throw ScheduleTemplateRepositoryError.staleTemplate
      }
      guard before?.id == template.id || before == nil else {
        throw ScheduleTemplateRepositoryError.staleTemplate
      }
      for session in template.sessions {
        for liftID in [session.primaryLiftID, session.assistanceLiftID] {
          let configured =
            try Int.fetchOne(
              db,
              sql: "SELECT COUNT(*) FROM lifts WHERE id = ?",
              arguments: [liftID]
            ) ?? 0
          guard configured == 1 else {
            throw ScheduleTemplateValidationError.unconfiguredLift(liftID)
          }
        }
      }
      let timestamp = occurredAt
      try db.execute(
        sql: """
          INSERT INTO schedule_templates (id, created_at, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at
          """,
        arguments: [template.id, timestamp, timestamp]
      )
      try db.execute(
        sql: "DELETE FROM schedule_template_sessions WHERE template_id = ?",
        arguments: [template.id]
      )
      for (position, session) in template.sessions.enumerated() {
        try db.execute(
          sql: """
            INSERT INTO schedule_template_sessions
              (id, template_id, position, intended_weekday, primary_lift_id, assistance_lift_id)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            session.id,
            template.id,
            position,
            session.intendedWeekday.rawValue,
            session.primaryLiftID,
            session.assistanceLiftID,
          ]
        )
      }
      let beforeJSON = try before.map { try Self.encodeSnapshot($0.snapshot) }
      let afterJSON = try Self.encodeSnapshot(template.snapshot)
      try db.execute(
        sql: """
          INSERT INTO schedule_template_audit
            (id, template_id, action, occurred_at, before_json, after_json)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          auditID,
          template.id,
          action.rawValue,
          timestamp,
          beforeJSON,
          afterJSON,
        ]
      )
      return ScheduleTemplateAuditEntry(
        id: auditID,
        templateID: template.id,
        action: action,
        occurredAt: occurredAt,
        before: before?.snapshot,
        after: template.snapshot
      )
    }
  }

  public func scheduleTemplateAuditHistory() async throws -> [ScheduleTemplateAuditEntry] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, template_id, action, occurred_at, before_json, after_json
          FROM schedule_template_audit
          ORDER BY occurred_at, rowid
          """
      ).map(Self.scheduleTemplateAuditEntry(from:))
    }
  }

  private func readyStores() async throws -> TrainingStores {
    try await prepareStores()
    guard let stores else { throw PersistenceError.storesUnavailable }
    return stores
  }

  private static func scheduleTemplate(from db: Database) throws -> ScheduleTemplate? {
    guard
      let metadata = try Row.fetchOne(
        db,
        sql: "SELECT id FROM schedule_templates ORDER BY rowid LIMIT 1"
      )
    else {
      return nil
    }
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, intended_weekday, primary_lift_id, assistance_lift_id
        FROM schedule_template_sessions
        WHERE template_id = ?
        ORDER BY position, rowid
        """,
      arguments: [metadata["id"] as String]
    )
    let sessions = try rows.map { row -> ScheduleSession in
      guard let weekday = ScheduleWeekday(rawValue: row["intended_weekday"]) else {
        throw PersistenceError.invalidScheduleTemplate
      }
      return ScheduleSession(
        id: row["id"],
        intendedWeekday: weekday,
        primaryLiftID: row["primary_lift_id"],
        assistanceLiftID: row["assistance_lift_id"]
      )
    }
    guard !sessions.isEmpty else {
      throw PersistenceError.invalidScheduleTemplate
    }
    return ScheduleTemplate(id: metadata["id"], sessions: sessions)
  }

  private static func encodeSnapshot(_ snapshot: ScheduleTemplateSnapshot) throws -> String {
    let data = try JSONEncoder().encode(snapshot)
    guard let string = String(data: data, encoding: .utf8) else {
      throw PersistenceError.invalidScheduleTemplate
    }
    return string
  }

  private static func scheduleTemplateAuditEntry(from row: Row) throws
    -> ScheduleTemplateAuditEntry
  {
    guard let action = ScheduleTemplateAuditAction(rawValue: row["action"]) else {
      throw PersistenceError.invalidScheduleAudit
    }
    guard let afterData = (row["after_json"] as String).data(using: .utf8) else {
      throw PersistenceError.invalidScheduleAudit
    }
    let after = try JSONDecoder().decode(ScheduleTemplateSnapshot.self, from: afterData)
    let before: ScheduleTemplateSnapshot?
    let beforeJSON: String? = row["before_json"]
    if let beforeJSON {
      guard let beforeData = beforeJSON.data(using: .utf8) else {
        throw PersistenceError.invalidScheduleAudit
      }
      before = try JSONDecoder().decode(ScheduleTemplateSnapshot.self, from: beforeData)
    } else {
      before = nil
    }
    return ScheduleTemplateAuditEntry(
      id: row["id"],
      templateID: row["template_id"],
      action: action,
      occurredAt: row["occurred_at"],
      before: before,
      after: after
    )
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
    let beforeIdentityKind: String? = row["before_identity_kind"]
    let beforeIdentityValue: String? = row["before_identity_value"]
    let beforeTrainingMax: Double? = row["before_training_max_kg"]
    let beforeLoadingIncrement: Double? = row["before_loading_increment_kg"]
    let beforeValues = [
      beforeIdentityKind != nil,
      beforeIdentityValue != nil,
      beforeTrainingMax != nil,
      beforeLoadingIncrement != nil,
    ]
    guard beforeValues.allSatisfy({ $0 }) || beforeValues.allSatisfy({ !$0 }) else {
      throw PersistenceError.invalidAuditBefore
    }
    let before: LiftConfigurationSnapshot?
    if beforeValues.allSatisfy({ !$0 }) {
      before = nil
    } else if let beforeIdentityKind, let beforeIdentityValue, let beforeTrainingMax,
      let beforeLoadingIncrement
    {
      before = LiftConfigurationSnapshot(
        identity: try identity(
          kind: beforeIdentityKind,
          value: beforeIdentityValue
        ),
        trainingMaxKg: beforeTrainingMax,
        loadingIncrementKg: beforeLoadingIncrement
      )
    } else {
      throw PersistenceError.invalidAuditBefore
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
  case invalidAuditBefore
  case invalidScheduleAudit
  case invalidScheduleTemplate
  case storesUnavailable
}

public enum TrainingPersistenceModule {}
