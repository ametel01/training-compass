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

  public func loadDraftTrainingCycle() async throws -> TrainingCycle? {
    try await loadTrainingCycle(state: .draft)
  }

  public func loadActiveTrainingCycle() async throws -> TrainingCycle? {
    try await loadTrainingCycle(state: .active)
  }

  public func completedTrainingCycleCount() async throws -> Int {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM training_cycles WHERE lifecycle_state = ?",
        arguments: [TrainingCycleLifecycleState.completed.rawValue]
      ) ?? 0
    }
  }

  public func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction
  ) async throws -> TrainingCycleAuditEntry {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      let existingDraft = try Self.trainingCycle(from: db, state: .draft)
      let existingForID = try Self.trainingCycle(from: db, id: cycle.id)
      if cycle.lifecycleState == .active,
        let existingActive = try Self.trainingCycle(from: db, state: .active),
        existingActive.id != cycle.id
      {
        throw TrainingCycleRepositoryError.activeCycleAlreadyExists
      }
      if cycle.lifecycleState == .draft,
        let existingDraft,
        existingDraft.id != cycle.id
      {
        throw TrainingCycleRepositoryError.draftAlreadyExists
      }
      let before = existingForID?.snapshot ?? existingDraft?.snapshot
      guard before == expectedBefore else {
        throw TrainingCycleRepositoryError.staleCycle
      }
      let cycleJSON = try Self.encodeSnapshot(cycle.snapshot)
      try db.execute(
        sql: """
          INSERT INTO training_cycles
            (id, lifecycle_state, anchor_date, includes_provisional_deload, cycle_json, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            lifecycle_state = excluded.lifecycle_state,
            anchor_date = excluded.anchor_date,
            includes_provisional_deload = excluded.includes_provisional_deload,
            cycle_json = excluded.cycle_json,
            updated_at = excluded.updated_at
          """,
        arguments: [
          cycle.id,
          cycle.lifecycleState.rawValue,
          cycle.week1AnchorDate.iso8601String,
          cycle.includesProvisionalDeload,
          cycleJSON,
          cycle.createdAt,
          cycle.updatedAt,
        ]
      )
      // Planned calendar and role edits are projected separately from the
      // cycle JSON so set results, omissions, additional work, and completion
      // facts remain untouched. Refresh only planned session fields in this
      // transaction, and remove projections for sessions safely removed while
      // Scheduled.
      let oldSessionIDs = Set(existingForID?.weeks.flatMap(\.sessions).map(\.id) ?? [])
      let newSessionIDs = Set(cycle.weeks.flatMap(\.sessions).map(\.id))
      for removedID in oldSessionIDs.subtracting(newSessionIDs) {
        try db.execute(
          sql: "DELETE FROM session_projections WHERE session_id = ? AND cycle_id = ?",
          arguments: [removedID, cycle.id]
        )
      }
      for session in cycle.weeks.flatMap(\.sessions) {
        try Self.upsertSessionProjection(
          db,
          cycleID: cycle.id,
          session: session,
          status: session.status,
          intendedDate: session.intendedDate,
          primaryLiftID: session.primaryLiftID,
          assistanceLiftID: session.assistanceLiftID,
          updatedAt: cycle.updatedAt
        )
      }
      try db.execute(
        sql: """
          INSERT INTO training_cycle_audit
            (id, cycle_id, action, occurred_at, before_json, after_json)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          auditID,
          cycle.id,
          action.rawValue,
          occurredAt,
          try before.map(Self.encodeSnapshot),
          cycleJSON,
        ]
      )
      return TrainingCycleAuditEntry(
        id: auditID,
        cycleID: cycle.id,
        action: action,
        occurredAt: occurredAt,
        before: before,
        after: cycle.snapshot
      )
    }
  }

  public func discardDraftTrainingCycle(
    expectedBefore: TrainingCycleSnapshot,
    auditID: String,
    occurredAt: Int64
  ) async throws -> TrainingCycleAuditEntry {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard let current = try Self.trainingCycle(from: db, id: expectedBefore.id),
        current.lifecycleState == .draft
      else {
        throw TrainingCycleRepositoryError.noDraft
      }
      guard current.snapshot == expectedBefore else {
        throw TrainingCycleRepositoryError.staleCycle
      }
      let beforeJSON = try Self.encodeSnapshot(expectedBefore)
      try db.execute(
        sql: "DELETE FROM training_cycles WHERE id = ?",
        arguments: [expectedBefore.id]
      )
      try db.execute(
        sql: """
          INSERT INTO training_cycle_audit
            (id, cycle_id, action, occurred_at, before_json, after_json)
          VALUES (?, ?, ?, ?, ?, NULL)
          """,
        arguments: [
          auditID,
          expectedBefore.id,
          TrainingCycleAuditAction.discarded.rawValue,
          occurredAt,
          beforeJSON,
        ]
      )
      return TrainingCycleAuditEntry(
        id: auditID,
        cycleID: expectedBefore.id,
        action: .discarded,
        occurredAt: occurredAt,
        before: expectedBefore,
        after: nil
      )
    }
  }

  public func trainingCycleAuditHistory(for cycleID: String) async throws
    -> [TrainingCycleAuditEntry]
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, cycle_id, action, occurred_at, before_json, after_json
          FROM training_cycle_audit
          WHERE cycle_id = ?
          ORDER BY occurred_at, rowid
          """,
        arguments: [cycleID]
      ).map(Self.trainingCycleAuditEntry(from:))
    }
  }

  public func loadSetResults(for sessionID: String) async throws -> [RecordedSetResult] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT result_json FROM set_results
          WHERE session_id = ?
          ORDER BY rowid
          """,
        arguments: [sessionID]
      ).map(Self.recordedSetResult(from:))
    }
  }

  public func saveSetResult(
    _ result: RecordedSetResult,
    expectedBefore: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: SetResultAuditAction
  ) async throws -> SetResultAuditEntry {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        let session = active.weeks.flatMap(\.sessions).first(where: { $0.id == result.sessionID })
      else {
        throw SetResultRepositoryError.unknownSession
      }
      guard !session.status.isTerminal else { throw SetResultRepositoryError.sessionLocked }
      guard session.prescriptions.contains(where: { $0.id == result.prescriptionID }) else {
        throw SetResultRepositoryError.unknownPrescription
      }

      let current = try Row.fetchOne(
        db,
        sql: """
          SELECT result_json FROM set_results
          WHERE session_id = ? AND prescription_id = ?
          """,
        arguments: [result.sessionID, result.prescriptionID]
      ).map(Self.recordedSetResult(from:))
      guard current == expectedBefore else {
        throw SetResultRepositoryError.staleResult
      }

      let afterJSON = try Self.encodeRecordedSetResult(result)
      try db.execute(
        sql: """
          INSERT INTO set_results (id, session_id, prescription_id, result_json, recorded_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(session_id, prescription_id) DO UPDATE SET
            id = excluded.id,
            result_json = excluded.result_json,
            recorded_at = excluded.recorded_at
          """,
        arguments: [
          result.id,
          result.sessionID,
          result.prescriptionID,
          afterJSON,
          result.recordedAt,
        ]
      )
      // A performed result supersedes an earlier Omitted disposition. Keeping this
      // in the same transaction guarantees the two states cannot coexist after a
      // restart or an interrupted write.
      try db.execute(
        sql: "DELETE FROM omitted_sets WHERE session_id = ? AND prescription_id = ?",
        arguments: [result.sessionID, result.prescriptionID]
      )
      try Self.upsertSessionProjection(
        db,
        cycleID: active.id,
        session: session,
        status: .inProgress,
        intendedDate: session.intendedDate,
        primaryLiftID: session.primaryLiftID,
        assistanceLiftID: session.assistanceLiftID,
        updatedAt: occurredAt
      )
      try db.execute(
        sql: """
          INSERT INTO set_result_audit
            (id, session_id, prescription_id, action, occurred_at, before_json, after_json)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          auditID,
          result.sessionID,
          result.prescriptionID,
          action.rawValue,
          occurredAt,
          try current.map(Self.encodeRecordedSetResult),
          afterJSON,
        ]
      )
      return SetResultAuditEntry(
        id: auditID,
        sessionID: result.sessionID,
        prescriptionID: result.prescriptionID,
        action: action,
        occurredAt: occurredAt,
        before: current,
        after: result
      )
    }
  }

  public func setResultAuditHistory(for sessionID: String) async throws
    -> [SetResultAuditEntry]
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, session_id, prescription_id, action, occurred_at, before_json, after_json
          FROM set_result_audit
          WHERE session_id = ?
          ORDER BY occurred_at, rowid
          """,
        arguments: [sessionID]
      ).map(Self.setResultAuditEntry(from:))
    }
  }

  public func loadOmittedSets(for sessionID: String) async throws -> [OmittedSet] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT session_id, prescription_id, reason, omitted_at
          FROM omitted_sets
          WHERE session_id = ?
          ORDER BY omitted_at, rowid
          """,
        arguments: [sessionID]
      ).map {
        OmittedSet(
          sessionID: $0["session_id"],
          prescriptionID: $0["prescription_id"],
          reason: $0["reason"],
          omittedAt: $0["omitted_at"]
        )
      }
    }
  }

  public func saveOmittedSet(
    _ omission: OmittedSet,
    expectedResult: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: OmittedSetAuditAction
  ) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        let session = active.weeks.flatMap(\.sessions).first(where: { $0.id == omission.sessionID })
      else { throw SetResultRepositoryError.unknownSession }
      guard !session.status.isTerminal else { throw SetResultRepositoryError.sessionLocked }
      guard session.prescriptions.contains(where: { $0.id == omission.prescriptionID }) else {
        throw SetResultRepositoryError.unknownPrescription
      }
      let current = try Row.fetchOne(
        db,
        sql: """
          SELECT result_json FROM set_results
          WHERE session_id = ? AND prescription_id = ?
          """,
        arguments: [omission.sessionID, omission.prescriptionID]
      ).map(Self.recordedSetResult(from:))
      guard current == expectedResult else { throw SetResultRepositoryError.staleResult }
      try db.execute(
        sql: """
          INSERT INTO omitted_sets (session_id, prescription_id, reason, omitted_at)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(session_id, prescription_id) DO UPDATE SET
            reason = excluded.reason,
            omitted_at = excluded.omitted_at
          """,
        arguments: [
          omission.sessionID, omission.prescriptionID, omission.reason, omission.omittedAt,
        ]
      )
      try db.execute(
        sql: "DELETE FROM set_results WHERE session_id = ? AND prescription_id = ?",
        arguments: [omission.sessionID, omission.prescriptionID]
      )
      try Self.upsertSessionProjection(
        db,
        cycleID: active.id,
        session: session,
        status: .inProgress,
        intendedDate: session.intendedDate,
        primaryLiftID: session.primaryLiftID,
        assistanceLiftID: session.assistanceLiftID,
        updatedAt: occurredAt
      )
      _ = auditID
      _ = occurredAt
      _ = action
    }
  }

  public func loadAdditionalSets(for sessionID: String) async throws -> [AdditionalSet] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, session_id, position, lift_id, weight_kg, repetitions, note, recorded_at
          FROM additional_sets
          WHERE session_id = ?
          ORDER BY position, rowid
          """,
        arguments: [sessionID]
      ).map { row in
        try AdditionalSet(
          id: row["id"],
          sessionID: row["session_id"],
          position: row["position"],
          liftID: row["lift_id"],
          weightKg: row["weight_kg"],
          repetitions: row["repetitions"],
          note: row["note"],
          recordedAt: row["recorded_at"]
        )
      }
    }
  }

  public func saveAdditionalSet(_ set: AdditionalSet) async throws -> AdditionalSet {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        active.weeks.flatMap(\.sessions).contains(where: { $0.id == set.sessionID })
      else { throw SetResultRepositoryError.unknownSession }
      guard let session = active.weeks.flatMap(\.sessions).first(where: { $0.id == set.sessionID }),
        !session.status.isTerminal
      else { throw SetResultRepositoryError.sessionLocked }
      let existing =
        try Row.fetchOne(
          db,
          sql: "SELECT id FROM additional_sets WHERE id = ? AND session_id = ?",
          arguments: [set.id, set.sessionID]
        ) != nil
      if existing {
        try db.execute(
          sql: """
            UPDATE additional_sets
            SET position = ?, lift_id = ?, weight_kg = ?, repetitions = ?, note = ?, recorded_at = ?
            WHERE id = ? AND session_id = ?
            """,
          arguments: [
            set.position, set.liftID, set.weightKg, set.repetitions, set.note, set.recordedAt,
            set.id, set.sessionID,
          ]
        )
      } else {
        try db.execute(
          sql: """
            INSERT INTO additional_sets
              (id, session_id, position, lift_id, weight_kg, repetitions, note, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            set.id, set.sessionID, set.position, set.liftID, set.weightKg, set.repetitions,
            set.note, set.recordedAt,
          ]
        )
      }
      try Self.upsertSessionProjection(
        db,
        cycleID: active.id,
        session: session,
        status: .inProgress,
        intendedDate: session.intendedDate,
        primaryLiftID: session.primaryLiftID,
        assistanceLiftID: session.assistanceLiftID,
        updatedAt: set.recordedAt
      )
      return set
    }
  }

  public func deleteAdditionalSet(sessionID: String, id: String) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        let session = active.weeks.flatMap(\.sessions).first(where: { $0.id == sessionID }),
        !session.status.isTerminal
      else { throw SetResultRepositoryError.sessionLocked }
      guard
        try Row.fetchOne(
          db,
          sql: "SELECT id FROM additional_sets WHERE id = ? AND session_id = ?",
          arguments: [id, sessionID]
        ) != nil
      else { throw SetResultRepositoryError.unknownPrescription }
      try db.execute(
        sql: "DELETE FROM additional_sets WHERE id = ? AND session_id = ?",
        arguments: [id, sessionID]
      )
      try Self.compactAdditionalSets(db, sessionID: sessionID)
    }
  }

  public func reorderAdditionalSets(sessionID: String, orderedIDs: [String]) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        let session = active.weeks.flatMap(\.sessions).first(where: { $0.id == sessionID }),
        !session.status.isTerminal
      else { throw SetResultRepositoryError.sessionLocked }
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT id FROM additional_sets WHERE session_id = ? ORDER BY position, rowid",
        arguments: [sessionID]
      )
      let currentIDs: [String] = rows.map { $0["id"] }
      guard Set(currentIDs) == Set(orderedIDs), currentIDs.count == orderedIDs.count else {
        throw SetResultRepositoryError.unknownPrescription
      }
      for (offset, id) in orderedIDs.enumerated() {
        try db.execute(
          sql: "UPDATE additional_sets SET position = ? WHERE id = ? AND session_id = ?",
          arguments: [offset + currentIDs.count, id, sessionID]
        )
      }
      for (offset, id) in orderedIDs.enumerated() {
        try db.execute(
          sql: "UPDATE additional_sets SET position = ? WHERE id = ? AND session_id = ?",
          arguments: [offset, id, sessionID]
        )
      }
    }
  }

  public func loadCompletedSession(sessionID: String) async throws -> CompletedSession? {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT session_id, confirmed_at FROM session_completions WHERE session_id = ?",
        arguments: [sessionID]
      ).map { CompletedSession(sessionID: $0["session_id"], confirmedAt: $0["confirmed_at"]) }
    }
  }

  public func completeSession(
    _ completion: CompletedSession,
    confirmation: SessionCompletionConfirmation
  ) async throws -> CompletedSession {
    guard confirmation == .confirmed else { throw SessionLoggingError.incompleteSession }
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        let session = active.weeks.flatMap(\.sessions).first(where: {
          $0.id == completion.sessionID
        })
      else { throw SetResultRepositoryError.unknownSession }
      guard !session.status.isTerminal else { throw SessionLoggingError.alreadyCompleted }
      let resultIDs = try Set(
        String.fetchAll(
          db,
          sql: "SELECT prescription_id FROM set_results WHERE session_id = ?",
          arguments: [completion.sessionID]
        )
      )
      let omittedIDs = try Set(
        String.fetchAll(
          db,
          sql: "SELECT prescription_id FROM omitted_sets WHERE session_id = ?",
          arguments: [completion.sessionID]
        )
      )
      guard
        session.prescriptions.allSatisfy({ resultIDs.contains($0.id) || omittedIDs.contains($0.id) }
        )
      else {
        throw SessionLoggingError.incompleteSession
      }
      try db.execute(
        sql: "INSERT INTO session_completions (session_id, confirmed_at) VALUES (?, ?)",
        arguments: [completion.sessionID, completion.confirmedAt]
      )
      try Self.upsertSessionProjection(
        db,
        cycleID: active.id,
        session: session,
        status: .completed,
        intendedDate: session.intendedDate,
        primaryLiftID: session.primaryLiftID,
        assistanceLiftID: session.assistanceLiftID,
        updatedAt: completion.confirmedAt
      )
      return completion
    }
  }

  public func loadSessionCorrectionSnapshot(sessionID: String) async throws
    -> SessionCorrectionSnapshot?
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      let rows = try Row.fetchAll(db, sql: "SELECT cycle_json FROM training_cycles")
      for row in rows {
        let cycle = try Self.projectedTrainingCycle(from: db, cycle: Self.trainingCycle(from: row))
        if let session = cycle.weeks.flatMap(\.sessions).first(where: { $0.id == sessionID }) {
          return try Self.correctionSnapshot(from: db, cycle: cycle, session: session)
        }
      }
      return nil
    }
  }

  public func sessionBelongsToTerminalCycle(sessionID: String) async throws -> Bool {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(db, sql: "SELECT lifecycle_state, cycle_json FROM training_cycles")
        .contains { row in
          guard let state = row["lifecycle_state"] as String?,
            state == TrainingCycleLifecycleState.completed.rawValue
              || state == TrainingCycleLifecycleState.abandoned.rawValue,
            let cycle = try? Self.trainingCycle(from: row)
          else { return false }
          return cycle.weeks.flatMap(\.sessions).contains(where: { $0.id == sessionID })
        }
    }
  }

  public func applySessionCorrection(
    _ request: SessionCorrectionRequest,
    expectedBefore: SessionCorrectionSnapshot?,
    confirmation: SessionReopenConfirmation,
    auditID: String,
    occurredAt: Int64
  ) async throws -> SessionCorrectionAuditEntry {
    guard confirmation == .confirmed else { throw SetResultRepositoryError.confirmationRequired }
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        let original = active.weeks.flatMap(\.sessions).first(where: { $0.id == request.sessionID })
      else {
        let hasTerminalSession = try Row.fetchAll(db, sql: "SELECT cycle_json FROM training_cycles")
          .contains { row in
            guard let cycle = try? Self.trainingCycle(from: row) else { return false }
            return cycle.lifecycleState != .active
              && cycle.weeks.flatMap(\.sessions).contains(where: { $0.id == request.sessionID })
          }
        throw hasTerminalSession
          ? SetResultRepositoryError.terminalCycle
          : SetResultRepositoryError.unknownSession
      }
      let current = try Self.correctionSnapshot(from: db, cycle: active, session: original)
      if let expectedBefore, expectedBefore != current {
        throw SetResultRepositoryError.staleCorrection
      }
      guard request.sessionID == original.id,
        !request.primaryLiftID.isEmpty,
        !request.assistanceLiftID.isEmpty,
        active.liftSnapshots[request.primaryLiftID] != nil,
        active.liftSnapshots[request.assistanceLiftID] != nil
      else { throw SetResultRepositoryError.invalidCorrection }
      let prescriptionIDs = Set(original.prescriptions.map(\.id))
      let resultIDs = request.results.map(\.prescriptionID)
      let omissionIDs = request.omissions.map(\.prescriptionID)
      guard Set(resultIDs).count == resultIDs.count,
        Set(omissionIDs).count == omissionIDs.count,
        Set(resultIDs).isDisjoint(with: omissionIDs),
        resultIDs.allSatisfy({ prescriptionIDs.contains($0) }),
        omissionIDs.allSatisfy({ prescriptionIDs.contains($0) }),
        request.results.allSatisfy({ $0.sessionID == request.sessionID }),
        request.omissions.allSatisfy({ $0.sessionID == request.sessionID }),
        request.additionalSets.allSatisfy({ $0.sessionID == request.sessionID }),
        Set(request.additionalSets.map(\.id)).count == request.additionalSets.count,
        request.additionalSets.map(\.position) == Array(0..<request.additionalSets.count)
      else { throw SetResultRepositoryError.invalidCorrection }
      if request.status == .completed {
        guard prescriptionIDs.isSubset(of: Set(resultIDs).union(omissionIDs)) else {
          throw SessionLoggingError.incompleteSession
        }
      }
      if request.status == .scheduled || request.status == .skipped {
        guard resultIDs.isEmpty, omissionIDs.isEmpty, request.additionalSets.isEmpty else {
          throw SetResultRepositoryError.invalidCorrection
        }
      }

      try db.execute(
        sql: "DELETE FROM set_results WHERE session_id = ?", arguments: [request.sessionID])
      try db.execute(
        sql: "DELETE FROM omitted_sets WHERE session_id = ?", arguments: [request.sessionID])
      try db.execute(
        sql: "DELETE FROM additional_sets WHERE session_id = ?", arguments: [request.sessionID])
      try db.execute(
        sql: "DELETE FROM session_completions WHERE session_id = ?", arguments: [request.sessionID])
      for result in request.results {
        try db.execute(
          sql:
            "INSERT INTO set_results (id, session_id, prescription_id, result_json, recorded_at) VALUES (?, ?, ?, ?, ?)",
          arguments: [
            result.id, result.sessionID, result.prescriptionID,
            try Self.encodeRecordedSetResult(result), result.recordedAt,
          ])
      }
      for omission in request.omissions {
        try db.execute(
          sql:
            "INSERT INTO omitted_sets (session_id, prescription_id, reason, omitted_at) VALUES (?, ?, ?, ?)",
          arguments: [
            omission.sessionID, omission.prescriptionID, omission.reason, omission.omittedAt,
          ])
      }
      for set in request.additionalSets {
        try db.execute(
          sql:
            "INSERT INTO additional_sets (id, session_id, position, lift_id, weight_kg, repetitions, note, recorded_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          arguments: [
            set.id, set.sessionID, set.position, set.liftID, set.weightKg, set.repetitions,
            set.note, set.recordedAt,
          ])
      }
      let completion: CompletedSession?
      if request.status == .completed {
        completion = CompletedSession(
          sessionID: request.sessionID,
          confirmedAt: request.completedAt ?? occurredAt
        )
        try db.execute(
          sql: "INSERT INTO session_completions (session_id, confirmed_at) VALUES (?, ?)",
          arguments: [completion!.sessionID, completion!.confirmedAt])
      } else {
        completion = nil
      }
      try Self.upsertSessionProjection(
        db,
        cycleID: active.id,
        session: original,
        status: request.status,
        intendedDate: request.intendedDate,
        primaryLiftID: request.primaryLiftID,
        assistanceLiftID: request.assistanceLiftID,
        updatedAt: occurredAt
      )
      let after = SessionCorrectionSnapshot(
        sessionID: request.sessionID,
        status: request.status,
        intendedDate: request.intendedDate,
        primaryLiftID: request.primaryLiftID,
        assistanceLiftID: request.assistanceLiftID,
        results: request.results.sorted { $0.prescriptionID < $1.prescriptionID },
        omissions: request.omissions.sorted { $0.prescriptionID < $1.prescriptionID },
        additionalSets: request.additionalSets.sorted { $0.position < $1.position },
        completion: completion,
        updatedAt: occurredAt
      )
      try db.execute(
        sql:
          "INSERT INTO session_correction_audit (id, cycle_id, session_id, occurred_at, note, before_json, after_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
        arguments: [
          auditID, active.id, request.sessionID, occurredAt, request.note,
          try Self.encodeCorrectionSnapshot(current), try Self.encodeCorrectionSnapshot(after),
        ])
      return SessionCorrectionAuditEntry(
        id: auditID,
        cycleID: active.id,
        sessionID: request.sessionID,
        occurredAt: occurredAt,
        note: request.note,
        before: current,
        after: after
      )
    }
  }

  public func sessionCorrectionAuditHistory(for sessionID: String) async throws
    -> [SessionCorrectionAuditEntry]
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql:
          "SELECT id, cycle_id, session_id, occurred_at, note, before_json, after_json FROM session_correction_audit WHERE session_id = ? ORDER BY occurred_at, rowid",
        arguments: [sessionID]
      ).map(Self.sessionCorrectionAuditEntry(from:))
    }
  }

  private func readyStores() async throws -> TrainingStores {
    try await prepareStores()
    guard let stores else { throw PersistenceError.storesUnavailable }
    return stores
  }

  private static func upsertSessionProjection(
    _ db: Database,
    cycleID: String,
    session: TrainingCycleSession,
    status: TrainingSessionStatus,
    intendedDate: TrainingDate,
    primaryLiftID: String,
    assistanceLiftID: String,
    updatedAt: Int64
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO session_projections
          (session_id, cycle_id, status, intended_date, primary_lift_id, assistance_lift_id, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET
          cycle_id = excluded.cycle_id,
          status = excluded.status,
          intended_date = excluded.intended_date,
          primary_lift_id = excluded.primary_lift_id,
          assistance_lift_id = excluded.assistance_lift_id,
          updated_at = excluded.updated_at
        """,
      arguments: [
        session.id, cycleID, status.rawValue, intendedDate.iso8601String,
        primaryLiftID, assistanceLiftID, updatedAt,
      ]
    )
  }

  private static func correctionSnapshot(
    from db: Database,
    cycle: TrainingCycle,
    session: TrainingCycleSession
  ) throws -> SessionCorrectionSnapshot {
    let results = try Row.fetchAll(
      db,
      sql: "SELECT result_json FROM set_results WHERE session_id = ? ORDER BY prescription_id",
      arguments: [session.id]
    ).map(recordedSetResult(from:))
    let omissions = try Row.fetchAll(
      db,
      sql:
        "SELECT session_id, prescription_id, reason, omitted_at FROM omitted_sets WHERE session_id = ? ORDER BY prescription_id",
      arguments: [session.id]
    ).map {
      OmittedSet(
        sessionID: $0["session_id"], prescriptionID: $0["prescription_id"], reason: $0["reason"],
        omittedAt: $0["omitted_at"]
      )
    }
    let additional = try Row.fetchAll(
      db,
      sql:
        "SELECT id, session_id, position, lift_id, weight_kg, repetitions, note, recorded_at FROM additional_sets WHERE session_id = ? ORDER BY position, rowid",
      arguments: [session.id]
    ).map { row in
      try AdditionalSet(
        id: row["id"], sessionID: row["session_id"], position: row["position"],
        liftID: row["lift_id"], weightKg: row["weight_kg"], repetitions: row["repetitions"],
        note: row["note"], recordedAt: row["recorded_at"]
      )
    }
    let completion = try Row.fetchOne(
      db,
      sql: "SELECT session_id, confirmed_at FROM session_completions WHERE session_id = ?",
      arguments: [session.id]
    ).map { CompletedSession(sessionID: $0["session_id"], confirmedAt: $0["confirmed_at"]) }
    let projectionUpdatedAt = try Int64.fetchOne(
      db,
      sql: "SELECT updated_at FROM session_projections WHERE session_id = ? AND cycle_id = ?",
      arguments: [session.id, cycle.id]
    )
    let fallbackUpdatedAt =
      [
        completion?.confirmedAt,
        results.map(\.recordedAt).max(),
        omissions.map(\.omittedAt).max(),
        additional.map(\.recordedAt).max(),
        cycle.updatedAt,
      ].compactMap { $0 }.max() ?? 0
    let status: TrainingSessionStatus
    if session.status == .completed || completion != nil {
      status = .completed
    } else if session.status == .skipped {
      status = .skipped
    } else if !results.isEmpty || !omissions.isEmpty || !additional.isEmpty {
      status = .inProgress
    } else {
      status = session.status
    }
    return SessionCorrectionSnapshot(
      sessionID: session.id,
      status: status,
      intendedDate: session.intendedDate,
      primaryLiftID: session.primaryLiftID,
      assistanceLiftID: session.assistanceLiftID,
      results: results,
      omissions: omissions,
      additionalSets: additional,
      completion: completion,
      updatedAt: projectionUpdatedAt ?? fallbackUpdatedAt
    )
  }

  private static func encodeCorrectionSnapshot(_ snapshot: SessionCorrectionSnapshot) throws
    -> String
  {
    let data = try JSONEncoder().encode(snapshot)
    guard let string = String(data: data, encoding: .utf8) else {
      throw PersistenceError.invalidSessionCorrectionAudit
    }
    return string
  }

  private static func correctionSnapshot(fromJSON value: String?) throws
    -> SessionCorrectionSnapshot
  {
    guard let value, let data = value.data(using: .utf8) else {
      throw PersistenceError.invalidSessionCorrectionAudit
    }
    do {
      return try JSONDecoder().decode(SessionCorrectionSnapshot.self, from: data)
    } catch {
      throw PersistenceError.invalidSessionCorrectionAudit
    }
  }

  private static func sessionCorrectionAuditEntry(from row: Row) throws
    -> SessionCorrectionAuditEntry
  {
    SessionCorrectionAuditEntry(
      id: row["id"],
      cycleID: row["cycle_id"],
      sessionID: row["session_id"],
      occurredAt: row["occurred_at"],
      note: row["note"],
      before: try correctionSnapshot(fromJSON: row["before_json"]),
      after: try correctionSnapshot(fromJSON: row["after_json"])
    )
  }

  private func loadTrainingCycle(state: TrainingCycleLifecycleState) async throws
    -> TrainingCycle?
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Self.trainingCycle(from: db, state: state)
    }
  }

  private static func encodeSnapshot(_ snapshot: TrainingCycleSnapshot) throws -> String {
    let data = try JSONEncoder().encode(snapshot)
    guard let string = String(data: data, encoding: .utf8) else {
      throw PersistenceError.invalidTrainingCycle
    }
    return string
  }

  private static func trainingCycle(from db: Database, state: TrainingCycleLifecycleState)
    throws -> TrainingCycle?
  {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT cycle_json FROM training_cycles
          WHERE lifecycle_state = ?
          ORDER BY updated_at DESC, rowid DESC LIMIT 1
          """,
        arguments: [state.rawValue]
      )
    else { return nil }
    return try projectedTrainingCycle(from: db, cycle: trainingCycle(from: row))
  }

  private static func trainingCycle(from db: Database, id: String) throws -> TrainingCycle? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: "SELECT cycle_json FROM training_cycles WHERE id = ?",
        arguments: [id]
      )
    else { return nil }
    return try projectedTrainingCycle(from: db, cycle: trainingCycle(from: row))
  }

  private static func projectedTrainingCycle(from db: Database, cycle: TrainingCycle)
    throws -> TrainingCycle
  {
    let weeks = try cycle.weeks.map { week in
      let sessions = try week.sessions.map { session in
        try projectedSession(from: db, cycleID: cycle.id, session: session)
      }
      return TrainingWeek(
        id: week.id,
        position: week.position,
        kind: week.kind,
        startDate: week.startDate,
        sessions: sessions
      )
    }
    return TrainingCycle(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: weeks,
      sourceTemplate: cycle.sourceTemplate,
      includesProvisionalDeload: cycle.includesProvisionalDeload,
      lifecycleState: cycle.lifecycleState,
      createdAt: cycle.createdAt,
      updatedAt: cycle.updatedAt,
      liftSnapshots: cycle.liftSnapshots
    )
  }

  private static func projectedSession(
    from db: Database,
    cycleID: String,
    session: TrainingCycleSession
  ) throws -> TrainingCycleSession {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT status, intended_date, primary_lift_id, assistance_lift_id
          FROM session_projections WHERE session_id = ? AND cycle_id = ?
          """,
        arguments: [session.id, cycleID]
      )
    else {
      let hasCompletion =
        try Row.fetchOne(
          db,
          sql: "SELECT 1 FROM session_completions WHERE session_id = ?",
          arguments: [session.id]
        ) != nil
      let workCount =
        try Int.fetchOne(
          db,
          sql: """
            SELECT (
              (SELECT COUNT(*) FROM set_results WHERE session_id = ?) +
              (SELECT COUNT(*) FROM omitted_sets WHERE session_id = ?) +
              (SELECT COUNT(*) FROM additional_sets WHERE session_id = ?)
            )
            """,
          arguments: [session.id, session.id, session.id]
        ) ?? 0
      let hasWork = workCount > 0
      let status =
        hasCompletion
        ? TrainingSessionStatus.completed
        : (hasWork ? .inProgress : session.status)
      return TrainingCycleSession(
        id: session.id,
        intendedDate: session.intendedDate,
        sourceTemplateSessionID: session.sourceTemplateSessionID,
        primaryLiftID: session.primaryLiftID,
        assistanceLiftID: session.assistanceLiftID,
        prescriptions: session.prescriptions,
        status: status
      )
    }
    guard let status = TrainingSessionStatus(rawValue: row["status"] as String) else {
      throw PersistenceError.invalidSessionProjection
    }
    let intendedDate = try parseTrainingDate(row["intended_date"] as String)
    return TrainingCycleSession(
      id: session.id,
      intendedDate: intendedDate,
      sourceTemplateSessionID: session.sourceTemplateSessionID,
      primaryLiftID: row["primary_lift_id"],
      assistanceLiftID: row["assistance_lift_id"],
      prescriptions: session.prescriptions,
      status: status
    )
  }

  private static func parseTrainingDate(_ value: String) throws -> TrainingDate {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { throw PersistenceError.invalidSessionProjection }
    return TrainingDate(year: parts[0], month: parts[1], day: parts[2])
  }

  private static func trainingCycle(from row: Row) throws -> TrainingCycle {
    guard let data = (row["cycle_json"] as String).data(using: .utf8) else {
      throw PersistenceError.invalidTrainingCycle
    }
    let snapshot = try JSONDecoder().decode(TrainingCycleSnapshot.self, from: data)
    return TrainingCycle(
      id: snapshot.id,
      week1AnchorDate: snapshot.week1AnchorDate,
      weeks: snapshot.weeks,
      sourceTemplate: snapshot.sourceTemplate,
      includesProvisionalDeload: snapshot.includesProvisionalDeload,
      lifecycleState: snapshot.lifecycleState,
      createdAt: snapshot.createdAt,
      updatedAt: snapshot.updatedAt,
      liftSnapshots: snapshot.liftSnapshots
    )
  }

  private static func trainingCycleAuditEntry(from row: Row) throws -> TrainingCycleAuditEntry {
    guard let action = TrainingCycleAuditAction(rawValue: row["action"]) else {
      throw PersistenceError.invalidTrainingCycleAudit
    }
    let before = try decodeSnapshot(row["before_json"] as String?)
    let after = try decodeSnapshot(row["after_json"] as String?)
    return TrainingCycleAuditEntry(
      id: row["id"],
      cycleID: row["cycle_id"],
      action: action,
      occurredAt: row["occurred_at"],
      before: before,
      after: after
    )
  }

  private static func decodeSnapshot(_ value: String?) throws -> TrainingCycleSnapshot? {
    guard let value else { return nil }
    guard let data = value.data(using: .utf8) else {
      throw PersistenceError.invalidTrainingCycleAudit
    }
    return try JSONDecoder().decode(TrainingCycleSnapshot.self, from: data)
  }

  private static func encodeRecordedSetResult(_ result: RecordedSetResult) throws -> String {
    let data = try JSONEncoder().encode(result)
    guard let string = String(data: data, encoding: .utf8) else {
      throw PersistenceError.invalidSetResult
    }
    return string
  }

  private static func recordedSetResult(from row: Row) throws -> RecordedSetResult {
    guard let data = (row["result_json"] as String).data(using: .utf8) else {
      throw PersistenceError.invalidSetResult
    }
    do {
      return try JSONDecoder().decode(RecordedSetResult.self, from: data)
    } catch {
      throw PersistenceError.invalidSetResult
    }
  }

  private static func compactAdditionalSets(_ db: Database, sessionID: String) throws {
    let ids = try String.fetchAll(
      db,
      sql: "SELECT id FROM additional_sets WHERE session_id = ? ORDER BY position, rowid",
      arguments: [sessionID]
    )
    for (offset, id) in ids.enumerated() {
      try db.execute(
        sql: "UPDATE additional_sets SET position = ? WHERE id = ? AND session_id = ?",
        arguments: [offset + ids.count, id, sessionID]
      )
    }
    for (offset, id) in ids.enumerated() {
      try db.execute(
        sql: "UPDATE additional_sets SET position = ? WHERE id = ? AND session_id = ?",
        arguments: [offset, id, sessionID]
      )
    }
  }

  private static func setResultAuditEntry(from row: Row) throws -> SetResultAuditEntry {
    guard let action = SetResultAuditAction(rawValue: row["action"] as String) else {
      throw PersistenceError.invalidSetResultAudit
    }
    let before = try decodeRecordedSetResult(row["before_json"] as String?)
    guard let after = try decodeRecordedSetResult(row["after_json"] as String?) else {
      throw PersistenceError.invalidSetResultAudit
    }
    return SetResultAuditEntry(
      id: row["id"],
      sessionID: row["session_id"],
      prescriptionID: row["prescription_id"],
      action: action,
      occurredAt: row["occurred_at"],
      before: before,
      after: after
    )
  }

  private static func decodeRecordedSetResult(_ value: String?) throws -> RecordedSetResult? {
    guard let value else { return nil }
    guard let data = value.data(using: .utf8) else {
      throw PersistenceError.invalidSetResultAudit
    }
    do {
      return try JSONDecoder().decode(RecordedSetResult.self, from: data)
    } catch {
      throw PersistenceError.invalidSetResultAudit
    }
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
  case invalidTrainingCycle
  case invalidTrainingCycleAudit
  case invalidSetResult
  case invalidSetResultAudit
  case invalidSessionProjection
  case invalidSessionCorrectionAudit
  case storesUnavailable
}

public enum TrainingPersistenceModule {}
