import Foundation
import GRDB
import TrainingApplication

private enum ApplicationAcceptanceScenario {
  case empty
  case eventLinking

  init?(environmentValue: String?) {
    switch environmentValue {
    case "empty": self = .empty
    case "event-linking": self = .eventLinking
    default: return nil
    }
  }
}

public actor GRDBTrainingRepository: TrainingRepository, TrainingReplacementImportRepository,
  TrainingErasureRepository, HealthWorkoutRepository, HealthRebuildStorageProviding,
  HealthWorkoutRouteRepository, TrainingEventLinkRepository,
  RunningComparisonExclusionRepository, HealthWorkoutWriteBackRepository
{
  private let root: URL
  private let bootstrapper: ProtectedStoreBootstrapper
  private let phaseObserver: any TrainingImportPhaseObserver
  private let erasurePhaseObserver: any TrainingErasurePhaseObserver
  private let erasurePreferences: any TrainingErasurePreferences
  private let temporaryExportDirectory: URL
  private let applicationAcceptanceScenario: ApplicationAcceptanceScenario?
  private var stores: TrainingStores?
  private var hasPreparedApplicationAcceptanceScenario = false

  public init(
    root: URL,
    bootstrapper: ProtectedStoreBootstrapper = .init(),
    phaseObserver: any TrainingImportPhaseObserver = NoOpTrainingImportPhaseObserver(),
    erasurePhaseObserver: any TrainingErasurePhaseObserver = NoOpTrainingErasurePhaseObserver(),
    erasurePreferences: any TrainingErasurePreferences = FoundationTrainingErasurePreferences(),
    temporaryExportDirectory: URL = FileManager.default.temporaryDirectory
      .appending(path: "TrainingCompassExports", directoryHint: .isDirectory)
  ) {
    self.root = root
    self.bootstrapper = bootstrapper
    self.phaseObserver = phaseObserver
    self.erasurePhaseObserver = erasurePhaseObserver
    self.erasurePreferences = erasurePreferences
    self.temporaryExportDirectory = temporaryExportDirectory
    self.applicationAcceptanceScenario = nil
  }

  private init(applicationRoot root: URL) {
    self.root = root
    self.bootstrapper = .init()
    self.phaseObserver = NoOpTrainingImportPhaseObserver()
    self.erasurePhaseObserver = NoOpTrainingErasurePhaseObserver()
    self.erasurePreferences = FoundationTrainingErasurePreferences()
    self.temporaryExportDirectory = FileManager.default.temporaryDirectory
      .appending(path: "TrainingCompassExports", directoryHint: .isDirectory)
    self.applicationAcceptanceScenario = ApplicationAcceptanceScenario(
      environmentValue: ProcessInfo.processInfo.environment["TRAINING_COMPASS_UI_SCENARIO"])
  }

  public static func applicationRepository(root: URL) -> GRDBTrainingRepository {
    GRDBTrainingRepository(applicationRoot: root)
  }

  public static func applicationDataRoot(fallback root: URL) -> URL {
    #if targetEnvironment(simulator)
      return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "TrainingCompass", directoryHint: .isDirectory)
    #else
      return root
    #endif
  }

  public func prepareStores() async throws {
    if stores == nil {
      try recoverPendingErasure()
      stores = try bootstrapper.open(in: root)
    }
    guard let applicationAcceptanceScenario,
      !hasPreparedApplicationAcceptanceScenario
    else { return }
    hasPreparedApplicationAcceptanceScenario = true
    do {
      switch applicationAcceptanceScenario {
      case .empty:
        try await eraseAllData(progress: nil)
        try await prepareStores()
      case .eventLinking:
        try await seedTrainingEventAcceptanceScenario(now: Date())
      }
    } catch {
      hasPreparedApplicationAcceptanceScenario = false
      throw error
    }
  }

  /// Removes every copy owned by this installation. A marker is written before
  /// closing the first database and removed only after all cleanup succeeds;
  /// launch recovery therefore completes an interrupted erase before opening a
  /// new store and can never expose a partial mixture as current state.
  public func eraseAllData(progress: TrainingErasureProgressHandler?) async throws {
    let locations = actualLocations()
    let marker = erasureMarker(for: locations)
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(at: locations.root, withIntermediateDirectories: true)
      if !fileManager.fileExists(atPath: marker.path()) {
        guard fileManager.createFile(atPath: marker.path(), contents: Data("pending".utf8)) else {
          throw TrainingErasureError.cleanupFailed
        }
      }

      try reachErasurePhase(
        .closingStores, fraction: 0.15, message: "Closing protected stores.", progress: progress)
      if let stores {
        try stores.authoritative.close()
        try stores.reconstructible.close()
        self.stores = nil
      }

      try reachErasurePhase(
        .removingProtectedStores,
        fraction: 0.45,
        message: "Removing Locally Authoritative Data and Derived Projections.",
        progress: progress
      )
      try removeIfPresent(locations.authoritativeDirectory)
      try removeIfPresent(locations.reconstructibleDirectory)
      try removeIfPresent(locations.diagnosticsDirectory)

      try reachErasurePhase(
        .removingTemporaryExports,
        fraction: 0.7,
        message: "Removing temporary exports.",
        progress: progress
      )
      try removeIfPresent(temporaryExportDirectory)

      try reachErasurePhase(
        .clearingPreferences,
        fraction: 0.9,
        message: "Clearing preferences and sync state.",
        progress: progress
      )
      try erasurePreferences.removeAll()
      try removeIfPresent(marker)
      progress?(.init(phase: .completed, fraction: 1, message: "App data erased."))
    } catch let error as TrainingErasureError {
      throw error
    } catch {
      throw TrainingErasureError.cleanupFailed
    }
  }

  public func authoritativeStoreIsEmpty() async throws -> Bool {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      let tables = try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
      )
      for table in tables
      where table != "gate_zero_metadata" && table != "grdb_migrations"
        && table != "health_workout_write_back_preferences"
      {
        let quoted = Self.quoteIdentifier(table)
        if (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(quoted)")) ?? 0 > 0 {
          return false
        }
      }
      return true
    }
  }

  /// During replacement import the current authoritative file must remain
  /// available as a rollback copy while the new SQLite file is staged. Count
  /// both sides of that coexistence and add the same recovery margin used by
  /// the import boundary. This check is deliberately conservative: SQLite
  /// journals and filesystem allocation can exceed the logical JSON size.
  public func requiredImportSpaceBytes(archiveBytes: Int64) async throws -> Int64 {
    let currentBytes: Int64
    let databaseURL = actualLocations().authoritativeDatabase
    if let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path()),
      let fileSize = attributes[.size] as? NSNumber
    {
      currentBytes = max(0, fileSize.int64Value)
    } else {
      currentBytes = 0
    }
    let archive = max(0, archiveBytes)
    let (coexistence, overflow) = archive.addingReportingOverflow(currentBytes)
    guard !overflow else { return Int64.max }
    let (minimum, minimumOverflow) = coexistence.addingReportingOverflow(64 * 1024)
    guard !minimumOverflow else { return Int64.max }
    let margin = Double(minimum) * 1.2
    guard margin.isFinite, margin < Double(Int64.max) else { return Int64.max }
    return Int64(margin.rounded(.up))
  }

  public func replaceAuthoritativeData(
    _ data: TrainingAuthoritativeExportData,
    progress: TrainingImportProgressHandler?
  ) async throws {
    do {
      try TrainingImportBoundary.validateAuthoritativeData(data)
      try await performReplacement(data, progress: progress)
    } catch let error as TrainingImportError {
      throw error
    } catch {
      throw TrainingImportError.replacementFailed(String(describing: error))
    }
  }

  public func loadAuthoritativeExportData() async throws -> TrainingAuthoritativeExportData {
    let stores = try await readyStores()
    return try await stores.authoritative.read(Self.authoritativeExportData(from:))
  }

  public func upsertHealthWorkouts(
    _ workouts: [HealthWorkout],
    reconciliationContext: String
  ) async throws {
    guard !workouts.isEmpty else { return }
    let stores = try await readyStores()
    try await stores.reconstructible.write { db in
      for workout in workouts {
        try db.execute(
          sql: """
            INSERT INTO health_workouts
              (healthkit_uuid, activity_type, start_date, end_date, duration,
               source_name, source_bundle_identifier, source_product_type, source_os_version,
               device_name, device_model, source_timezone_identifier, local_date, timezone_source,
               running_environment,
               elevation_meters,
               first_imported_at, reconciliation_context, app_authored_sync_identifier,
               app_authored_sync_version, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(healthkit_uuid) DO UPDATE SET
              activity_type = excluded.activity_type,
              start_date = excluded.start_date,
              end_date = excluded.end_date,
              duration = excluded.duration,
              source_name = excluded.source_name,
              source_bundle_identifier = excluded.source_bundle_identifier,
              source_product_type = excluded.source_product_type,
              source_os_version = excluded.source_os_version,
              device_name = excluded.device_name,
              device_model = excluded.device_model,
              source_timezone_identifier = CASE
                WHEN health_workouts.timezone_source IN
                  ('sourceMetadata', 'deviceAtFirstImport', 'unavailable')
                THEN health_workouts.source_timezone_identifier
                ELSE excluded.source_timezone_identifier
              END,
              local_date = CASE
                WHEN health_workouts.timezone_source IN
                  ('sourceMetadata', 'deviceAtFirstImport', 'unavailable')
                THEN health_workouts.local_date
                ELSE excluded.local_date
              END,
              timezone_source = CASE
                WHEN health_workouts.timezone_source IN
                  ('sourceMetadata', 'deviceAtFirstImport', 'unavailable')
                THEN health_workouts.timezone_source
                ELSE excluded.timezone_source
              END,
              running_environment = excluded.running_environment,
              elevation_meters = excluded.elevation_meters,
              reconciliation_context = excluded.reconciliation_context,
              app_authored_sync_identifier = excluded.app_authored_sync_identifier,
              app_authored_sync_version = excluded.app_authored_sync_version,
              updated_at = excluded.updated_at
            WHERE excluded.app_authored_sync_version IS NULL
              OR health_workouts.app_authored_sync_version IS NULL
              OR excluded.app_authored_sync_version >= health_workouts.app_authored_sync_version
            """,
          arguments: [
            workout.healthKitUUID,
            workout.activityType,
            workout.startDate.timeIntervalSince1970,
            workout.endDate.timeIntervalSince1970,
            workout.duration,
            workout.sourceName,
            workout.sourceBundleIdentifier,
            workout.sourceProductType,
            workout.sourceOSVersion,
            workout.deviceName,
            workout.deviceModel,
            workout.sourceTimeZoneIdentifier,
            workout.localDate,
            workout.timeZoneSource.rawValue,
            workout.runningEnvironment.rawValue,
            workout.elevationMeters,
            workout.firstImportedAt.timeIntervalSince1970,
            workout.reconciliationContext ?? reconciliationContext,
            workout.appAuthoredSyncIdentifier,
            workout.appAuthoredSyncVersion,
            Date().timeIntervalSince1970,
          ]
        )
        try db.execute(
          sql: "DELETE FROM health_workout_deletions WHERE healthkit_uuid = ?",
          arguments: [workout.healthKitUUID]
        )
      }
    }
  }

  public func loadHealthWorkouts() async throws -> [HealthWorkout] {
    let stores = try await readyStores()
    return try await stores.reconstructible.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT healthkit_uuid, activity_type, start_date, end_date, duration,
                 source_name, source_bundle_identifier, source_product_type, source_os_version,
                 device_name, device_model, source_timezone_identifier, local_date, timezone_source,
                 running_environment,
                 elevation_meters,
                 first_imported_at, reconciliation_context,
                 app_authored_sync_identifier, app_authored_sync_version
          FROM health_workouts ORDER BY start_date, healthkit_uuid
          """
      ).map { row in
        guard let timezoneSource = HealthWorkoutTimeZoneSource(rawValue: row["timezone_source"])
        else {
          throw PersistenceError.invalidHealthWorkout
        }
        return HealthWorkout(
          healthKitUUID: row["healthkit_uuid"],
          activityType: row["activity_type"],
          startDate: Date(timeIntervalSince1970: row["start_date"]),
          endDate: Date(timeIntervalSince1970: row["end_date"]),
          duration: row["duration"],
          sourceName: row["source_name"] as String?,
          sourceBundleIdentifier: row["source_bundle_identifier"] as String?,
          sourceProductType: row["source_product_type"] as String?,
          sourceOSVersion: row["source_os_version"] as String?,
          deviceName: row["device_name"] as String?,
          deviceModel: row["device_model"] as String?,
          sourceTimeZoneIdentifier: row["source_timezone_identifier"] as String?,
          localDate: row["local_date"],
          timeZoneSource: timezoneSource,
          runningEnvironment: RunningEnvironment(rawValue: row["running_environment"] as String)
            ?? .unspecified,
          elevationMeters: row["elevation_meters"] as Double?,
          firstImportedAt: Date(timeIntervalSince1970: row["first_imported_at"]),
          reconciliationContext: row["reconciliation_context"] as String?,
          appAuthoredSyncIdentifier: row["app_authored_sync_identifier"] as String?,
          appAuthoredSyncVersion: row["app_authored_sync_version"] as Int?
        )
      }
    }
  }

  /// Commits one anchored Health page as a single reconstructible transaction.
  /// The workout rows, deletion ledger, fact ledger, and stream checkpoint are
  /// all updated together; a failed statement therefore leaves the previous
  /// anchor and cached view untouched.
  public func commitHealthWorkoutPage(
    _ page: HealthWorkoutPage,
    stream: HealthSyncStream,
    limits: HealthSyncBatchLimits
  ) async throws {
    try limits.validate(page: page)
    let stores = try await readyStores()
    let committedAt = Date()
    try await stores.reconstructible.write { db in
      let existingUUIDs: Set<String> =
        stream == .workouts
        ? Set(try String.fetchAll(db, sql: "SELECT healthkit_uuid FROM health_workouts"))
        : []
      let existingRecoveryIDs: Set<String> =
        RecoveryEvidenceStream(stream) != nil
        ? Set(
          try String.fetchAll(
            db,
            sql: "SELECT sample_id FROM health_recovery_samples WHERE stream = ?",
            arguments: [stream.rawValue]))
        : []
      let recoverySamples = page.recoverySamples(for: stream)
      for workout in page.workouts where stream == .workouts {
        try db.execute(
          sql: """
            INSERT INTO health_workouts
              (healthkit_uuid, activity_type, start_date, end_date, duration,
               source_name, source_bundle_identifier, source_product_type, source_os_version,
               device_name, device_model, source_timezone_identifier, local_date, timezone_source,
               running_environment,
               elevation_meters,
               first_imported_at, reconciliation_context, app_authored_sync_identifier,
               app_authored_sync_version, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(healthkit_uuid) DO UPDATE SET
              activity_type = excluded.activity_type,
              start_date = excluded.start_date,
              end_date = excluded.end_date,
              duration = excluded.duration,
              source_name = excluded.source_name,
              source_bundle_identifier = excluded.source_bundle_identifier,
              source_product_type = excluded.source_product_type,
              source_os_version = excluded.source_os_version,
              device_name = excluded.device_name,
              device_model = excluded.device_model,
              source_timezone_identifier = CASE
                WHEN health_workouts.timezone_source IN
                  ('sourceMetadata', 'deviceAtFirstImport', 'unavailable')
                THEN health_workouts.source_timezone_identifier
                ELSE excluded.source_timezone_identifier
              END,
              local_date = CASE
                WHEN health_workouts.timezone_source IN
                  ('sourceMetadata', 'deviceAtFirstImport', 'unavailable')
                THEN health_workouts.local_date
                ELSE excluded.local_date
              END,
              timezone_source = CASE
                WHEN health_workouts.timezone_source IN
                  ('sourceMetadata', 'deviceAtFirstImport', 'unavailable')
                THEN health_workouts.timezone_source
                ELSE excluded.timezone_source
              END,
              running_environment = excluded.running_environment,
              elevation_meters = excluded.elevation_meters,
              reconciliation_context = excluded.reconciliation_context,
              app_authored_sync_identifier = excluded.app_authored_sync_identifier,
              app_authored_sync_version = excluded.app_authored_sync_version,
              updated_at = excluded.updated_at
            WHERE excluded.app_authored_sync_version IS NULL
              OR health_workouts.app_authored_sync_version IS NULL
              OR excluded.app_authored_sync_version >= health_workouts.app_authored_sync_version
            """,
          arguments: [
            workout.healthKitUUID,
            workout.activityType,
            workout.startDate.timeIntervalSince1970,
            workout.endDate.timeIntervalSince1970,
            workout.duration,
            workout.sourceName,
            workout.sourceBundleIdentifier,
            workout.sourceProductType,
            workout.sourceOSVersion,
            workout.deviceName,
            workout.deviceModel,
            workout.sourceTimeZoneIdentifier,
            workout.localDate,
            workout.timeZoneSource.rawValue,
            workout.runningEnvironment.rawValue,
            workout.elevationMeters,
            workout.firstImportedAt.timeIntervalSince1970,
            workout.reconciliationContext ?? page.reconciliationContext,
            workout.appAuthoredSyncIdentifier,
            workout.appAuthoredSyncVersion,
            committedAt.timeIntervalSince1970,
          ]
        )
        try db.execute(
          sql: "DELETE FROM health_workout_deletions WHERE healthkit_uuid = ?",
          arguments: [workout.healthKitUUID]
        )
      }
      for sample in recoverySamples {
        let kind: HealthSyncFact.Kind =
          existingRecoveryIDs.contains(sample.id) ? .replaced : .added
        let id =
          "\(stream.rawValue):\(kind.rawValue):\(sample.id):\(page.nextAnchor ?? "final")"
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO health_sync_facts
              (id, stream, kind, healthkit_uuid, observed_at)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            id, stream.rawValue, kind.rawValue, sample.id,
            committedAt.timeIntervalSince1970,
          ])
      }
      for sample in recoverySamples {
        let encoded = String(
          decoding: try JSONEncoder().encode(sample), as: UTF8.self)
        try db.execute(
          sql: """
            INSERT INTO health_recovery_samples
              (stream, sample_id, sample_json, sample_date, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(stream, sample_id) DO UPDATE SET
              sample_json = excluded.sample_json,
              sample_date = excluded.sample_date,
              updated_at = excluded.updated_at
            """,
          arguments: [
            stream.rawValue, sample.id, encoded, sample.date.timeIntervalSince1970,
            committedAt.timeIntervalSince1970,
          ])
      }
      if RecoveryEvidenceStream(stream) != nil {
        for uuid in Set(page.deletedHealthKitUUIDs) where !uuid.isEmpty {
          try db.execute(
            sql: "DELETE FROM health_recovery_samples WHERE stream = ? AND sample_id = ?",
            arguments: [stream.rawValue, uuid])
        }
      }

      for uuid in Set(page.deletedHealthKitUUIDs) where stream == .workouts && !uuid.isEmpty {
        try db.execute(
          sql: "DELETE FROM health_workouts WHERE healthkit_uuid = ?",
          arguments: [uuid]
        )
        try db.execute(
          sql: "DELETE FROM health_workout_enrichment WHERE healthkit_uuid = ?",
          arguments: [uuid]
        )
        try db.execute(
          sql: "DELETE FROM health_workout_routes WHERE healthkit_uuid = ?",
          arguments: [uuid]
        )
        try db.execute(
          sql: """
            INSERT INTO health_workout_deletions
              (healthkit_uuid, deleted_at, reconciliation_context)
            VALUES (?, ?, ?)
            ON CONFLICT(healthkit_uuid) DO UPDATE SET
              deleted_at = excluded.deleted_at,
              reconciliation_context = excluded.reconciliation_context
            """,
          arguments: [uuid, committedAt.timeIntervalSince1970, page.reconciliationContext]
        )
      }

      for workout in page.workouts where stream == .workouts {
        let kind: HealthSyncFact.Kind =
          existingUUIDs.contains(workout.healthKitUUID)
          ? .replaced
          : .added
        let id =
          "\(stream.rawValue):\(kind.rawValue):\(workout.healthKitUUID):\(page.nextAnchor ?? "final")"
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO health_sync_facts
              (id, stream, kind, healthkit_uuid, observed_at)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            id, stream.rawValue, kind.rawValue, workout.healthKitUUID,
            committedAt.timeIntervalSince1970,
          ]
        )
      }
      for fact in page.streamFacts {
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO health_sync_facts
              (id, stream, kind, healthkit_uuid, observed_at)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            fact.id, stream.rawValue, fact.kind.rawValue, fact.healthKitUUID,
            fact.observedAt.timeIntervalSince1970,
          ]
        )
      }
      for uuid in Set(page.deletedHealthKitUUIDs) where !uuid.isEmpty {
        let id = "\(stream.rawValue):deleted:\(uuid):\(page.nextAnchor ?? "final")"
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO health_sync_facts
              (id, stream, kind, healthkit_uuid, observed_at)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            id, stream.rawValue, HealthSyncFact.Kind.deleted.rawValue, uuid,
            committedAt.timeIntervalSince1970,
          ]
        )
      }

      try db.execute(
        sql: """
          INSERT INTO health_sync_streams
            (stream, anchor, has_limited_history, reconciliation_context, committed_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(stream) DO UPDATE SET
            anchor = excluded.anchor,
            has_limited_history = excluded.has_limited_history,
            reconciliation_context = excluded.reconciliation_context,
            committed_at = excluded.committed_at
          """,
        arguments: [
          stream.rawValue,
          page.nextAnchor,
          page.hasLimitedHistory,
          page.reconciliationContext,
          committedAt.timeIntervalSince1970,
        ]
      )
    }
  }

  public func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws
    -> HealthSyncCheckpoint?
  {
    let stores = try await readyStores()
    return try await stores.reconstructible.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT anchor, has_limited_history, reconciliation_context, committed_at
          FROM health_sync_streams WHERE stream = ?
          """,
        arguments: [stream.rawValue]
      ).map { row in
        HealthSyncCheckpoint(
          stream: stream,
          anchor: row["anchor"] as String?,
          hasLimitedHistory: row["has_limited_history"],
          reconciliationContext: row["reconciliation_context"],
          committedAt: Date(timeIntervalSince1970: row["committed_at"])
        )
      }
    }
  }

  public func loadHealthMirrorContent(for stream: HealthSyncStream) async throws
    -> HealthMirrorContentSnapshot
  {
    let stores = try await readyStores()
    let count = try await stores.reconstructible.read { db -> Int in
      let table: String
      switch stream {
      case .workouts: table = "health_workouts"
      case .heartRate, .distance, .activeEnergy, .sleep, .restingHeartRate,
        .heartRateVariability:
        table = "health_recovery_samples"
      }
      if table == "health_recovery_samples" {
        return try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM \(table) WHERE stream = ?",
          arguments: [stream.rawValue]) ?? 0
      }
      return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
    }
    return .init(stream: stream, recordCount: count)
  }

  public func upsertHealthRecoverySamples(
    _ samples: [HealthRecoverySample],
    stream: HealthSyncStream,
    reconciliationContext: String
  ) async throws {
    guard !samples.isEmpty else { return }
    let stores = try await readyStores()
    let now = Date().timeIntervalSince1970
    try await stores.reconstructible.write { db in
      for sample in samples where sample.stream.healthSyncStream == stream {
        let encoded = String(decoding: try JSONEncoder().encode(sample), as: UTF8.self)
        try db.execute(
          sql: """
            INSERT INTO health_recovery_samples
              (stream, sample_id, sample_json, sample_date, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(stream, sample_id) DO UPDATE SET
              sample_json = excluded.sample_json,
              sample_date = excluded.sample_date,
              updated_at = excluded.updated_at
            """,
          arguments: [
            stream.rawValue, sample.id, encoded, sample.date.timeIntervalSince1970, now,
          ])
      }
    }
  }

  public func loadHealthRecoverySamples(for stream: HealthSyncStream) async throws
    -> [HealthRecoverySample]
  {
    guard RecoveryEvidenceStream(stream) != nil else { return [] }
    let stores = try await readyStores()
    return try await stores.reconstructible.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT sample_json FROM health_recovery_samples
          WHERE stream = ? ORDER BY sample_date, sample_id
          """,
        arguments: [stream.rawValue]
      ).compactMap { json in
        try? JSONDecoder().decode(HealthRecoverySample.self, from: Data(json.utf8))
      }
    }
  }

  public func loadHealthWorkoutDeletionUUIDs() async throws -> [String] {
    let stores = try await readyStores()
    return try await stores.reconstructible.read { db in
      try String.fetchAll(
        db,
        sql:
          "SELECT healthkit_uuid FROM health_workout_deletions ORDER BY deleted_at DESC, healthkit_uuid"
      )
    }
  }

  public func saveHealthWorkoutEnrichment(_ enrichment: HealthWorkoutEnrichment) async throws {
    let stores = try await readyStores()
    let encoded = String(
      decoding: try JSONEncoder().encode(enrichment),
      as: UTF8.self
    )
    try await stores.reconstructible.write { db in
      let workoutExists =
        try Bool.fetchOne(
          db,
          sql: "SELECT EXISTS(SELECT 1 FROM health_workouts WHERE healthkit_uuid = ?)",
          arguments: [enrichment.healthKitUUID]
        ) ?? false
      guard workoutExists else { return }
      try db.execute(
        sql: """
          INSERT INTO health_workout_enrichment (healthkit_uuid, enrichment_json, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(healthkit_uuid) DO UPDATE SET
            enrichment_json = excluded.enrichment_json,
            updated_at = excluded.updated_at
          """,
        arguments: [
          enrichment.healthKitUUID,
          encoded,
          Date().timeIntervalSince1970,
        ]
      )
    }
  }

  public func loadHealthWorkoutEnrichment(for healthKitUUID: String) async throws
    -> HealthWorkoutEnrichment?
  {
    let stores = try await readyStores()
    return try await stores.reconstructible.read { db in
      guard
        let encoded = try String.fetchOne(
          db,
          sql: "SELECT enrichment_json FROM health_workout_enrichment WHERE healthkit_uuid = ?",
          arguments: [healthKitUUID]
        )
      else { return nil }
      return try JSONDecoder().decode(HealthWorkoutEnrichment.self, from: Data(encoded.utf8))
    }
  }

  public func saveHealthWorkoutRoute(_ route: HealthWorkoutRoute) async throws -> Bool {
    let stores = try await readyStores()
    let encoded = String(decoding: try JSONEncoder().encode(route), as: UTF8.self)
    return try await stores.reconstructible.write { db in
      let workoutExists =
        try Bool.fetchOne(
          db,
          sql: "SELECT EXISTS(SELECT 1 FROM health_workouts WHERE healthkit_uuid = ?)",
          arguments: [route.healthKitUUID]
        ) ?? false
      guard workoutExists else { return false }
      try db.execute(
        sql: """
          INSERT INTO health_workout_routes (healthkit_uuid, route_json, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(healthkit_uuid) DO UPDATE SET
            route_json = excluded.route_json,
            updated_at = excluded.updated_at
          """,
        arguments: [route.healthKitUUID, encoded, Date().timeIntervalSince1970]
      )
      return true
    }
  }

  public func loadHealthWorkoutRoute(for healthKitUUID: String) async throws
    -> HealthWorkoutRoute?
  {
    let stores = try await readyStores()
    return try await stores.reconstructible.read { db in
      guard
        let encoded = try String.fetchOne(
          db,
          sql: "SELECT route_json FROM health_workout_routes WHERE healthkit_uuid = ?",
          arguments: [healthKitUUID]
        )
      else { return nil }
      let route = try JSONDecoder().decode(HealthWorkoutRoute.self, from: Data(encoded.utf8))
      guard route.healthKitUUID == healthKitUUID,
        !route.segments.isEmpty,
        route.points.count <= HealthWorkoutRoute.maximumRetainedPoints,
        route.originalPointCount >= route.points.count
      else { return nil }
      return route
    }
  }

  public func estimateHealthRebuildStorage(
    policy: HealthRebuildStoragePolicy
  ) async throws -> HealthRebuildStorageEstimate {
    let stores = try await readyStores()
    let recordCount = try await stores.reconstructible.read { db -> Int in
      let workouts = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM health_workouts") ?? 0
      let recovery = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM health_recovery_samples") ?? 0
      return workouts + recovery
    }
    let stagingBytes = max(
      policy.estimatedBytesPerRecord, recordCount * policy.estimatedBytesPerRecord)
    let available =
      (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage)
      ?? Int64.max
    return .init(
      stagingBytes: stagingBytes,
      safetyMarginBytes: policy.safetyMarginBytes,
      availableBytes: Int(min(Int64(Int.max), max(0, available))))
  }

  public func loadHealthRebuildState() async throws -> HealthRebuildState? {
    let stores = try await readyStores()
    return try await stores.reconstructible.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT phase, completed_streams, started_at, updated_at
          FROM health_rebuild_state WHERE id = 1
          """
      ).map { row in
        let streams =
          (try? JSONDecoder().decode(
            [HealthSyncStream].self, from: Data((row["completed_streams"] as String).utf8))) ?? []
        return HealthRebuildState(
          phase: HealthRebuildPhase(rawValue: row["phase"] as String) ?? .failed,
          completedStreams: streams,
          startedAt: Date(timeIntervalSince1970: row["started_at"]),
          updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
      }
    }
  }

  public func beginHealthRebuild() async throws {
    let stores = try await readyStores()
    let now = Date().timeIntervalSince1970
    let encoded = String(data: try JSONEncoder().encode([HealthSyncStream]()), encoding: .utf8)!
    try await stores.reconstructible.write { db in
      // Only reconstructible Health state is discarded. The authoritative
      // store (sessions, results, audits, and future link facts) is untouched.
      try db.execute(sql: "DELETE FROM health_workout_routes")
      try db.execute(sql: "DELETE FROM health_workout_enrichment")
      try db.execute(sql: "DELETE FROM health_workouts")
      try db.execute(sql: "DELETE FROM health_workout_deletions")
      try db.execute(sql: "DELETE FROM health_recovery_samples")
      try db.execute(sql: "DELETE FROM health_sync_facts")
      try db.execute(sql: "DELETE FROM health_sync_streams")
      try db.execute(
        sql: """
          INSERT INTO health_rebuild_state (id, phase, completed_streams, started_at, updated_at)
          VALUES (1, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            phase = excluded.phase,
            completed_streams = excluded.completed_streams,
            started_at = excluded.started_at,
            updated_at = excluded.updated_at
          """,
        arguments: [HealthRebuildPhase.rebuilding.rawValue, encoded, now, now]
      )
    }
  }

  public func updateHealthRebuildState(_ state: HealthRebuildState) async throws {
    let stores = try await readyStores()
    let encoded = String(
      data: try JSONEncoder().encode(state.completedStreams), encoding: .utf8)!
    try await stores.reconstructible.write { db in
      try db.execute(
        sql: """
          INSERT INTO health_rebuild_state (id, phase, completed_streams, started_at, updated_at)
          VALUES (1, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            phase = excluded.phase,
            completed_streams = excluded.completed_streams,
            started_at = excluded.started_at,
            updated_at = excluded.updated_at
          """,
        arguments: [
          state.phase.rawValue, encoded, state.startedAt.timeIntervalSince1970,
          state.updatedAt.timeIntervalSince1970,
        ]
      )
    }
  }

  public func regenerateHealthDerivedProjections() async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write(Self.regenerateProjections)
  }

  func saveHealthWorkoutLinkFact(_ fact: HealthWorkoutLinkFact) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      try db.execute(
        sql: """
          INSERT INTO health_workout_link_facts
            (id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
             linked_during_completion, write_back_disposition, unlinked_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            healthkit_uuid = excluded.healthkit_uuid,
            local_entity_kind = excluded.local_entity_kind,
            local_entity_id = excluded.local_entity_id,
            linked_at = excluded.linked_at,
            linked_during_completion = excluded.linked_during_completion,
            write_back_disposition = excluded.write_back_disposition,
            unlinked_at = excluded.unlinked_at
          """,
        arguments: [
          fact.id, fact.healthKitUUID, fact.localEntityKind.rawValue, fact.localEntityID,
          fact.linkedAt.timeIntervalSince1970,
          fact.linkedDuringCompletion, fact.writeBackDisposition.rawValue,
          fact.unlinkedAt?.timeIntervalSince1970,
        ]
      )
    }
  }

  public func loadHealthWorkoutLinkFacts(for healthKitUUID: String? = nil) async throws
    -> [HealthWorkoutLinkFact]
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      let rows: [Row]
      if let healthKitUUID {
        rows = try Row.fetchAll(
          db,
          sql: """
            SELECT id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
                   linked_during_completion, write_back_disposition, unlinked_at
            FROM health_workout_link_facts WHERE healthkit_uuid = ? ORDER BY linked_at, id
            """,
          arguments: [healthKitUUID]
        )
      } else {
        rows = try Row.fetchAll(
          db,
          sql: """
            SELECT id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
                   linked_during_completion, write_back_disposition, unlinked_at
            FROM health_workout_link_facts ORDER BY linked_at, id
            """
        )
      }
      return try rows.map {
        guard
          let localEntityKind = TrainingEventLocalEntityKind(rawValue: $0["local_entity_kind"]),
          let disposition = TrainingEventWriteBackDisposition(
            rawValue: $0["write_back_disposition"])
        else { throw TrainingEventLinkRepositoryError.invalidLink }
        return HealthWorkoutLinkFact(
          id: $0["id"], healthKitUUID: $0["healthkit_uuid"],
          localEntityKind: localEntityKind, localEntityID: $0["local_entity_id"],
          linkedAt: Date(timeIntervalSince1970: $0["linked_at"]),
          linkedDuringCompletion: $0["linked_during_completion"],
          writeBackDisposition: disposition,
          unlinkedAt: ($0["unlinked_at"] as Double?).map(Date.init(timeIntervalSince1970:))
        )
      }
    }
  }

  public func loadHealthWorkoutLinkFacts(forLocalEntityID localEntityID: String) async throws
    -> [HealthWorkoutLinkFact]
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
                 linked_during_completion, write_back_disposition, unlinked_at
          FROM health_workout_link_facts
          WHERE local_entity_kind = ? AND local_entity_id = ? ORDER BY linked_at, id
          """,
        arguments: [TrainingEventLocalEntityKind.session.rawValue, localEntityID]
      ).map {
        guard let kind = TrainingEventLocalEntityKind(rawValue: $0["local_entity_kind"]),
          let disposition = TrainingEventWriteBackDisposition(
            rawValue: $0["write_back_disposition"])
        else { throw TrainingEventLinkRepositoryError.invalidLink }
        return HealthWorkoutLinkFact(
          id: $0["id"], healthKitUUID: $0["healthkit_uuid"], localEntityKind: kind,
          localEntityID: $0["local_entity_id"],
          linkedAt: Date(timeIntervalSince1970: $0["linked_at"]),
          linkedDuringCompletion: $0["linked_during_completion"],
          writeBackDisposition: disposition,
          unlinkedAt: ($0["unlinked_at"] as Double?).map(Date.init(timeIntervalSince1970:)))
      }
    }
  }

  public func createHealthWorkoutLinkFact(
    _ fact: HealthWorkoutLinkFact,
    expectedSessionUpdatedAt: Int64,
    expectedWorkout: HealthWorkout
  ) async throws -> HealthWorkoutLinkFact {
    guard fact.localEntityKind == .session, fact.isActive,
      !fact.linkedDuringCompletion,
      fact.writeBackDisposition == .notApplicable,
      fact.healthKitUUID == expectedWorkout.healthKitUUID,
      expectedWorkout.sourceBundleIdentifier
        != TrainingEventLinkBoundary.trainingCompassBundleIdentifier
    else { throw TrainingEventLinkRepositoryError.invalidLink }

    let currentWorkouts = try await loadHealthWorkouts()
    let currentWorkout = currentWorkouts.first {
      $0.healthKitUUID == expectedWorkout.healthKitUUID
    }
    guard currentWorkout == expectedWorkout else {
      throw TrainingEventLinkRepositoryError.staleCandidate
    }

    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT status, updated_at FROM session_projections
            WHERE session_id = ?
            """,
          arguments: [fact.localEntityID]
        ),
        (row["status"] as String) == TrainingSessionStatus.completed.rawValue,
        (row["updated_at"] as Int64) == expectedSessionUpdatedAt,
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM session_completions WHERE session_id = ?",
          arguments: [fact.localEntityID]
        ) == 1
      else { throw TrainingEventLinkRepositoryError.staleCandidate }

      let activeCollisions = try Row.fetchAll(
        db,
        sql: """
          SELECT id, healthkit_uuid FROM health_workout_link_facts
          WHERE unlinked_at IS NULL
            AND (healthkit_uuid = ? OR (local_entity_kind = ? AND local_entity_id = ?))
          """,
        arguments: [fact.healthKitUUID, fact.localEntityKind.rawValue, fact.localEntityID]
      )
      let availableWorkoutIDs = Set(currentWorkouts.map(\.healthKitUUID))
      guard
        !activeCollisions.contains(where: {
          ($0["healthkit_uuid"] as String) == fact.healthKitUUID
            || availableWorkoutIDs.contains($0["healthkit_uuid"] as String)
        })
      else { throw TrainingEventLinkRepositoryError.duplicateLink }
      for collision in activeCollisions {
        try db.execute(
          sql: "UPDATE health_workout_link_facts SET unlinked_at = ? WHERE id = ?",
          arguments: [fact.linkedAt.timeIntervalSince1970, collision["id"] as String]
        )
      }

      try db.execute(
        sql: """
          INSERT INTO health_workout_link_facts
            (id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
             linked_during_completion, write_back_disposition, unlinked_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
          """,
        arguments: [
          fact.id, fact.healthKitUUID, fact.localEntityKind.rawValue, fact.localEntityID,
          fact.linkedAt.timeIntervalSince1970, fact.linkedDuringCompletion,
          fact.writeBackDisposition.rawValue,
        ]
      )
      return fact
    }
  }

  public func completeSessionAndCreateHealthWorkoutLinkFact(
    completion: CompletedSession,
    fact: HealthWorkoutLinkFact,
    expectedSessionUpdatedAt: Int64,
    expectedWorkout: HealthWorkout
  ) async throws -> TrainingEventCompletionLinkResult {
    guard fact.localEntityKind == .session, fact.localEntityID == completion.sessionID,
      fact.isActive, fact.linkedDuringCompletion,
      fact.writeBackDisposition == .suppressedExternalWorkoutLinkedAtCompletion,
      fact.healthKitUUID == expectedWorkout.healthKitUUID,
      expectedWorkout.sourceBundleIdentifier
        != TrainingEventLinkBoundary.trainingCompassBundleIdentifier
    else { throw TrainingEventLinkRepositoryError.invalidLink }

    let currentWorkout = try await loadHealthWorkouts().first {
      $0.healthKitUUID == expectedWorkout.healthKitUUID
    }
    guard currentWorkout == expectedWorkout else {
      throw TrainingEventLinkRepositoryError.staleCandidate
    }

    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard let active = try Self.trainingCycle(from: db, state: .active),
        let session = active.weeks.flatMap(\.sessions).first(where: {
          $0.id == completion.sessionID
        }),
        !session.status.isTerminal,
        let projection = try Row.fetchOne(
          db,
          sql: "SELECT updated_at FROM session_projections WHERE session_id = ?",
          arguments: [completion.sessionID]
        ),
        (projection["updated_at"] as Int64) == expectedSessionUpdatedAt
      else { throw TrainingEventLinkRepositoryError.staleCandidate }

      let resultIDs = try Set(
        String.fetchAll(
          db,
          sql: "SELECT prescription_id FROM set_results WHERE session_id = ?",
          arguments: [completion.sessionID]
        ))
      let omittedIDs = try Set(
        String.fetchAll(
          db,
          sql: "SELECT prescription_id FROM omitted_sets WHERE session_id = ?",
          arguments: [completion.sessionID]
        ))
      guard
        session.prescriptions.allSatisfy({
          resultIDs.contains($0.id) || omittedIDs.contains($0.id)
        })
      else { throw SessionLoggingError.incompleteSession }

      let duplicate =
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM health_workout_link_facts
            WHERE unlinked_at IS NULL
              AND (healthkit_uuid = ? OR (local_entity_kind = ? AND local_entity_id = ?))
            """,
          arguments: [fact.healthKitUUID, fact.localEntityKind.rawValue, fact.localEntityID]
        ) ?? 0
      guard duplicate == 0 else { throw TrainingEventLinkRepositoryError.duplicateLink }

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
      try db.execute(
        sql: """
          INSERT INTO health_workout_link_facts
            (id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
             linked_during_completion, write_back_disposition, unlinked_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
          """,
        arguments: [
          fact.id, fact.healthKitUUID, fact.localEntityKind.rawValue, fact.localEntityID,
          fact.linkedAt.timeIntervalSince1970, fact.linkedDuringCompletion,
          fact.writeBackDisposition.rawValue,
        ]
      )
      return TrainingEventCompletionLinkResult(completion: completion, link: fact)
    }
  }

  public func unlinkHealthWorkoutLinkFact(
    id: String,
    expectedLinkedAt: Date,
    unlinkedAt: Date
  ) async throws -> HealthWorkoutLinkFact {
    guard unlinkedAt >= expectedLinkedAt else {
      throw TrainingEventLinkRepositoryError.invalidLink
    }
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
                   linked_during_completion, write_back_disposition
            FROM health_workout_link_facts
            WHERE id = ? AND unlinked_at IS NULL
            """,
          arguments: [id]
        ),
        Date(timeIntervalSince1970: row["linked_at"]) == expectedLinkedAt,
        let localEntityKind = TrainingEventLocalEntityKind(rawValue: row["local_entity_kind"]),
        let disposition = TrainingEventWriteBackDisposition(
          rawValue: row["write_back_disposition"])
      else { throw TrainingEventLinkRepositoryError.staleCandidate }
      try db.execute(
        sql: "UPDATE health_workout_link_facts SET unlinked_at = ? WHERE id = ?",
        arguments: [unlinkedAt.timeIntervalSince1970, id]
      )
      return HealthWorkoutLinkFact(
        id: row["id"],
        healthKitUUID: row["healthkit_uuid"],
        localEntityKind: localEntityKind,
        localEntityID: row["local_entity_id"],
        linkedAt: expectedLinkedAt,
        linkedDuringCompletion: row["linked_during_completion"],
        writeBackDisposition: disposition,
        unlinkedAt: unlinkedAt
      )
    }
  }

  public func unlinkActiveHealthWorkoutLinkFacts(
    forLocalEntityID localEntityID: String,
    unlinkedAt: Date
  ) async throws -> [HealthWorkoutLinkFact] {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      guard unlinkedAt.timeIntervalSince1970.isFinite else {
        throw TrainingEventLinkRepositoryError.invalidLink
      }
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
                 linked_during_completion, write_back_disposition
          FROM health_workout_link_facts
          WHERE local_entity_kind = ? AND local_entity_id = ? AND unlinked_at IS NULL
          ORDER BY linked_at, id
          """,
        arguments: [TrainingEventLocalEntityKind.session.rawValue, localEntityID]
      )
      let links = try rows.map { row -> HealthWorkoutLinkFact in
        guard
          let localEntityKind = TrainingEventLocalEntityKind(rawValue: row["local_entity_kind"]),
          let disposition = TrainingEventWriteBackDisposition(
            rawValue: row["write_back_disposition"])
        else { throw TrainingEventLinkRepositoryError.invalidLink }
        let linkedAt = Date(timeIntervalSince1970: row["linked_at"] as Double)
        guard unlinkedAt >= linkedAt else {
          throw TrainingEventLinkRepositoryError.invalidLink
        }
        return HealthWorkoutLinkFact(
          id: row["id"], healthKitUUID: row["healthkit_uuid"],
          localEntityKind: localEntityKind, localEntityID: row["local_entity_id"],
          linkedAt: linkedAt,
          linkedDuringCompletion: row["linked_during_completion"],
          writeBackDisposition: disposition,
          unlinkedAt: unlinkedAt
        )
      }
      try db.execute(
        sql:
          "UPDATE health_workout_link_facts SET unlinked_at = ? WHERE local_entity_kind = ? AND local_entity_id = ? AND unlinked_at IS NULL",
        arguments: [
          unlinkedAt.timeIntervalSince1970,
          TrainingEventLocalEntityKind.session.rawValue,
          localEntityID,
        ]
      )
      return links
    }
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

  public func loadHeartRateConfiguration() async throws -> HeartRateConfiguration? {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql:
            "SELECT maximum_heart_rate_bpm, updated_at FROM heart_rate_configuration WHERE id = 1"
        )
      else { return nil }
      guard
        let maximum = try? MaximumHeartRate(beatsPerMinute: row["maximum_heart_rate_bpm"] as Double)
      else { throw HeartRateConfigurationRepositoryError.unavailable }
      return HeartRateConfiguration(
        maximumHeartRate: maximum, updatedAt: row["updated_at"] as Int64)
    }
  }

  public func saveHeartRateConfiguration(
    _ configuration: HeartRateConfiguration,
    expectedBefore: HeartRateConfiguration?
  ) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      let current = try Row.fetchOne(
        db,
        sql: "SELECT maximum_heart_rate_bpm, updated_at FROM heart_rate_configuration WHERE id = 1"
      ).flatMap { row -> HeartRateConfiguration? in
        guard
          let maximum = try? MaximumHeartRate(
            beatsPerMinute: row["maximum_heart_rate_bpm"] as Double)
        else { return nil }
        return HeartRateConfiguration(
          maximumHeartRate: maximum, updatedAt: row["updated_at"] as Int64)
      }
      guard current == expectedBefore else {
        throw HeartRateConfigurationRepositoryError.staleConfiguration
      }
      try db.execute(
        sql: """
          INSERT INTO heart_rate_configuration (id, maximum_heart_rate_bpm, updated_at)
          VALUES (1, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            maximum_heart_rate_bpm = excluded.maximum_heart_rate_bpm,
            updated_at = excluded.updated_at
          """,
        arguments: [configuration.maximumHeartRateBPM, configuration.updatedAt])
    }
  }

  public func deleteHeartRateConfiguration() async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      try db.execute(sql: "DELETE FROM heart_rate_configuration")
    }
  }

  public func loadRunningComparisonExclusions() async throws -> [String] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try String.fetchAll(
        db,
        sql:
          "SELECT healthkit_uuid FROM running_comparison_exclusions ORDER BY excluded_at, healthkit_uuid"
      )
    }
  }

  public func saveRunningComparisonExclusion(healthKitUUID: String) async throws {
    guard !healthKitUUID.isEmpty else { return }
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      try db.execute(
        sql: """
          INSERT INTO running_comparison_exclusions (healthkit_uuid, excluded_at)
          VALUES (?, ?)
          ON CONFLICT(healthkit_uuid) DO UPDATE SET excluded_at = excluded.excluded_at
          """,
        arguments: [healthKitUUID, Date().timeIntervalSince1970])
    }
  }

  public func deleteRunningComparisonExclusion(healthKitUUID: String) async throws {
    guard !healthKitUUID.isEmpty else { return }
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      try db.execute(
        sql: "DELETE FROM running_comparison_exclusions WHERE healthkit_uuid = ?",
        arguments: [healthKitUUID])
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
      let historyEvent: TrainingMaxHistoryEvent
      switch action {
      case .created: historyEvent = .initial
      case .edited: historyEvent = .manual
      case .corrected: historyEvent = .correction
      }
      let history = TrainingMaxHistoryEntry(
        id: auditID + ":tm",
        liftID: id,
        event: historyEvent,
        occurredAt: timestamp,
        beforeKg: before?.trainingMaxKg,
        afterKg: after.trainingMaxKg
      )
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO training_max_history
            (id, lift_id, event, occurred_at, history_json)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          history.id, history.liftID, history.event.rawValue, history.occurredAt,
          try Self.encodeTrainingMaxHistory(history),
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

  public func loadTrainingCycles() async throws -> [TrainingCycle] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT cycle_json FROM training_cycles
          ORDER BY anchor_date, updated_at, rowid
          """
      ).map { row in
        try Self.projectedTrainingCycle(from: db, cycle: Self.trainingCycle(from: row))
      }
    }
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

  public func loadTrainingMaxProposals() async throws -> [TrainingMaxProposal] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT proposal_json FROM training_max_proposals
          ORDER BY source_cycle_id, lift_id, rowid
          """
      ).map(Self.trainingMaxProposal(from:))
    }
  }

  public func saveTrainingMaxProposal(
    _ proposal: TrainingMaxProposal,
    expectedBefore: TrainingMaxProposal?,
    auditID: String,
    occurredAt: Int64,
    history: TrainingMaxHistoryEntry?
  ) async throws -> TrainingMaxProposal {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      let current = try Row.fetchOne(
        db,
        sql: "SELECT proposal_json FROM training_max_proposals WHERE id = ?",
        arguments: [proposal.id]
      ).map(Self.trainingMaxProposal(from:))
      guard current == expectedBefore else {
        throw TrainingMaxProposalRepositoryError.staleProposal
      }
      let json = try Self.encodeTrainingMaxProposal(proposal)
      try db.execute(
        sql: """
          INSERT INTO training_max_proposals
            (id, lift_id, source_cycle_id, status, proposal_json, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            lift_id = excluded.lift_id,
            source_cycle_id = excluded.source_cycle_id,
            status = excluded.status,
            proposal_json = excluded.proposal_json,
            updated_at = excluded.updated_at
          """,
        arguments: [
          proposal.id, proposal.liftID, proposal.sourceCycleID, proposal.status.rawValue,
          json, proposal.createdAt, proposal.updatedAt,
        ]
      )
      if let history {
        try db.execute(
          sql: """
            INSERT INTO training_max_history
              (id, lift_id, event, occurred_at, history_json)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            history.id, history.liftID, history.event.rawValue, history.occurredAt,
            try Self.encodeTrainingMaxHistory(history),
          ]
        )
      }
      _ = auditID
      _ = occurredAt
      return proposal
    }
  }

  public func decideTrainingMaxProposal(
    _ proposal: TrainingMaxProposal,
    expectedBefore: TrainingMaxProposal,
    configuration: LiftConfiguration?,
    expectedConfiguration: LiftConfigurationSnapshot?,
    auditID: String,
    occurredAt: Int64,
    history: TrainingMaxHistoryEntry,
    liftAuditID: String
  ) async throws -> TrainingMaxProposal {
    let stores = try await readyStores()
    return try await stores.authoritative.write { db in
      let currentProposal = try Row.fetchOne(
        db,
        sql: "SELECT proposal_json FROM training_max_proposals WHERE id = ?",
        arguments: [proposal.id]
      ).map(Self.trainingMaxProposal(from:))
      guard currentProposal == expectedBefore else {
        throw TrainingMaxProposalRepositoryError.staleProposal
      }
      if let configuration {
        let before = try Row.fetchOne(
          db,
          sql:
            "SELECT identity_kind, identity_value, training_max_kg, loading_increment_kg FROM lifts WHERE id = ?",
          arguments: [configuration.id]
        ).map(Self.snapshot(from:))
        guard before == expectedConfiguration else {
          throw LiftConfigurationRepositoryError.staleConfiguration
        }
        let identity = Self.identityParts(configuration.identity)
        try db.execute(
          sql: """
            UPDATE lifts SET identity_kind = ?, identity_value = ?, training_max_kg = ?,
              loading_increment_kg = ?, updated_at = ? WHERE id = ?
            """,
          arguments: [
            identity.kind, identity.value, configuration.trainingMax.kg,
            configuration.loadingIncrement.kg, occurredAt, configuration.id,
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
            liftAuditID, configuration.id, LiftConfigurationAuditAction.edited.rawValue, occurredAt,
            before.map { Self.identityParts($0.identity).kind },
            before.map { Self.identityParts($0.identity).value }, before?.trainingMaxKg,
            before?.loadingIncrementKg, identity.kind, identity.value,
            configuration.trainingMax.kg, configuration.loadingIncrement.kg,
          ]
        )
        let manualHistory = TrainingMaxHistoryEntry(
          id: liftAuditID + ":tm", liftID: configuration.id, event: .manual,
          occurredAt: occurredAt, beforeKg: before?.trainingMaxKg,
          afterKg: configuration.trainingMax.kg
        )
        try db.execute(
          sql:
            "INSERT INTO training_max_history (id, lift_id, event, occurred_at, history_json) VALUES (?, ?, ?, ?, ?)",
          arguments: [
            manualHistory.id, manualHistory.liftID, manualHistory.event.rawValue,
            manualHistory.occurredAt, try Self.encodeTrainingMaxHistory(manualHistory),
          ]
        )
      }
      try db.execute(
        sql:
          "UPDATE training_max_proposals SET status = ?, proposal_json = ?, updated_at = ? WHERE id = ?",
        arguments: [
          proposal.status.rawValue, try Self.encodeTrainingMaxProposal(proposal),
          proposal.updatedAt,
          proposal.id,
        ]
      )
      try db.execute(
        sql:
          "INSERT INTO training_max_history (id, lift_id, event, occurred_at, history_json) VALUES (?, ?, ?, ?, ?)",
        arguments: [
          history.id, history.liftID, history.event.rawValue, history.occurredAt,
          try Self.encodeTrainingMaxHistory(history),
        ]
      )
      _ = auditID
      return proposal
    }
  }

  public func loadTrainingMaxHistory(for liftID: String?) async throws
    -> [TrainingMaxHistoryEntry]
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      let sql: String
      let arguments: StatementArguments
      if let liftID {
        sql = """
          SELECT history_json FROM training_max_history
          WHERE lift_id = ? ORDER BY occurred_at, rowid
          """
        arguments = [liftID]
      } else {
        sql = "SELECT history_json FROM training_max_history ORDER BY occurred_at, rowid"
        arguments = []
      }
      return try Row.fetchAll(db, sql: sql, arguments: arguments).map(
        Self.trainingMaxHistory(from:))
    }
  }

  public func markTrainingMaxProposalsEffective(cycleID: String) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      let latestCompletedCycleID = try String.fetchOne(
        db,
        sql: """
          SELECT id FROM training_cycles
          WHERE lifecycle_state = ?
          ORDER BY updated_at DESC, rowid DESC LIMIT 1
          """,
        arguments: [TrainingCycleLifecycleState.completed.rawValue]
      )
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT proposal_json FROM training_max_proposals
          WHERE status IN (?, ?)
            AND source_cycle_id = (
              SELECT id FROM training_cycles
              WHERE lifecycle_state = ?
              ORDER BY updated_at DESC, rowid DESC LIMIT 1
            )
          """,
        arguments: [
          TrainingMaxProposalStatus.accepted.rawValue,
          TrainingMaxProposalStatus.manuallyReplaced.rawValue,
          TrainingCycleLifecycleState.completed.rawValue,
        ]
      )
      // Effective cycle is a projection of the next activated cycle and
      // remains recoverable in the JSON history ledger.
      for row in rows {
        let proposal = try Self.trainingMaxProposal(from: row)
        guard proposal.effectiveCycleID == nil else { continue }
        let updated = TrainingMaxProposal(
          id: proposal.id, liftID: proposal.liftID, liftName: proposal.liftName,
          sourceCycleID: proposal.sourceCycleID,
          currentTrainingMaxKg: proposal.currentTrainingMaxKg,
          proposedTrainingMaxKg: proposal.proposedTrainingMaxKg,
          incrementKg: proposal.incrementKg, evidence: proposal.evidence,
          status: proposal.status, decision: proposal.decision,
          decidedAt: proposal.decidedAt, effectiveCycleID: cycleID,
          createdAt: proposal.createdAt, updatedAt: proposal.updatedAt
        )
        try db.execute(
          sql: "UPDATE training_max_proposals SET proposal_json = ? WHERE id = ?",
          arguments: [try Self.encodeTrainingMaxProposal(updated), proposal.id]
        )
      }
      let historyRows = try Row.fetchAll(
        db, sql: "SELECT history_json FROM training_max_history")
      for row in historyRows {
        let history = try Self.trainingMaxHistory(from: row)
        guard history.effectiveCycleID == nil,
          history.cycleID == latestCompletedCycleID,
          history.event == .accepted || history.event == .manuallyReplaced
        else { continue }
        let updated = TrainingMaxHistoryEntry(
          id: history.id, liftID: history.liftID, event: history.event,
          occurredAt: history.occurredAt, beforeKg: history.beforeKg, afterKg: history.afterKg,
          proposalID: history.proposalID, cycleID: history.cycleID,
          effectiveCycleID: cycleID, evidence: history.evidence,
          decision: history.decision, note: history.note
        )
        try db.execute(
          sql: "UPDATE training_max_history SET history_json = ? WHERE id = ?",
          arguments: [try Self.encodeTrainingMaxHistory(updated), history.id]
        )
      }
    }
  }

  public func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction
  ) async throws -> TrainingCycleAuditEntry {
    try await saveTrainingCycle(
      cycle,
      expectedBefore: expectedBefore,
      auditID: auditID,
      occurredAt: occurredAt,
      action: action,
      note: nil,
      targetID: nil
    )
  }

  public func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction,
    note: String?,
    targetID: String?
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
        // A removed local Session cannot continue to own an active external
        // link. Keep the row as historical evidence rather than deleting it.
        try db.execute(
          sql:
            "UPDATE health_workout_link_facts SET unlinked_at = ? WHERE local_entity_kind = ? AND local_entity_id = ? AND unlinked_at IS NULL",
          arguments: [occurredAt, TrainingEventLocalEntityKind.session.rawValue, removedID]
        )
        try db.execute(
          sql: "DELETE FROM session_projections WHERE session_id = ? AND cycle_id = ?",
          arguments: [removedID, cycle.id]
        )
      }
      for session in cycle.weeks.flatMap(\.sessions) {
        if session.status == .skipped || session.status == .unperformed {
          // Skipped and Unperformed are explicit local dispositions. They
          // sever an external association but never mutate the Health object.
          try db.execute(
            sql:
              "UPDATE health_workout_link_facts SET unlinked_at = ? WHERE local_entity_kind = ? AND local_entity_id = ? AND unlinked_at IS NULL",
            arguments: [occurredAt, TrainingEventLocalEntityKind.session.rawValue, session.id]
          )
        }
        if session.status == .unperformed {
          // The v7 projection CHECK constraint intentionally predates the
          // Unperformed terminal history state. Removing its projection lets
          // the cycle JSON remain authoritative without weakening old schema
          // constraints; projectedSession falls back to the stored status.
          try db.execute(
            sql: "DELETE FROM session_projections WHERE session_id = ? AND cycle_id = ?",
            arguments: [session.id, cycle.id]
          )
        } else {
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
      }
      try db.execute(
        sql: """
          INSERT INTO training_cycle_audit
            (id, cycle_id, action, occurred_at, before_json, after_json, note, target_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          auditID,
          cycle.id,
          action.rawValue,
          occurredAt,
          try before.map(Self.encodeSnapshot),
          cycleJSON,
          note?.isEmpty == true ? nil : note,
          targetID?.isEmpty == true ? nil : targetID,
        ]
      )
      return TrainingCycleAuditEntry(
        id: auditID,
        cycleID: cycle.id,
        action: action,
        occurredAt: occurredAt,
        before: before,
        after: cycle.snapshot,
        note: note,
        targetID: targetID
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
          SELECT id, cycle_id, action, occurred_at, before_json, after_json, note, target_id
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

  public func loadHealthWorkoutWriteBackPreference() async throws
    -> HealthWorkoutWriteBackPreference
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql:
            "SELECT enabled, updated_at FROM health_workout_write_back_preferences WHERE id = 'default'"
        )
      else { return .init() }
      return .init(
        enabled: row["enabled"], updatedAt: Date(timeIntervalSince1970: row["updated_at"]))
    }
  }

  public func saveHealthWorkoutWriteBackPreference(
    _ preference: HealthWorkoutWriteBackPreference
  ) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      try db.execute(
        sql: """
          INSERT INTO health_workout_write_back_preferences (id, enabled, updated_at)
          VALUES ('default', ?, ?)
          ON CONFLICT(id) DO UPDATE SET enabled = excluded.enabled,
            updated_at = excluded.updated_at
          """,
        arguments: [preference.enabled, preference.updatedAt.timeIntervalSince1970])
    }
  }

  public func loadHealthWorkoutWriteBack(sessionID: String)
    async throws -> HealthWorkoutWriteBackRecord?
  {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT session_id, sync_identifier, sync_version, state, start_date, end_date, duration,
                 healthkit_uuid, last_error, updated_at
          FROM health_workout_write_backs WHERE session_id = ?
          """,
        arguments: [sessionID]
      ).map(Self.healthWorkoutWriteBackRecord(from:))
    }
  }

  public func loadHealthWorkoutWriteBacks() async throws -> [HealthWorkoutWriteBackRecord] {
    let stores = try await readyStores()
    return try await stores.authoritative.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT session_id, sync_identifier, sync_version, state, start_date, end_date, duration,
                 healthkit_uuid, last_error, updated_at
          FROM health_workout_write_backs ORDER BY updated_at, session_id
          """
      ).map(Self.healthWorkoutWriteBackRecord(from:))
    }
  }

  public func saveHealthWorkoutWriteBack(_ record: HealthWorkoutWriteBackRecord) async throws {
    let stores = try await readyStores()
    try await stores.authoritative.write { db in
      try db.execute(
        sql: """
          INSERT INTO health_workout_write_backs
            (session_id, sync_identifier, sync_version, state, start_date, end_date, duration,
             healthkit_uuid, last_error, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(session_id) DO UPDATE SET
            sync_identifier = excluded.sync_identifier,
            sync_version = excluded.sync_version,
            state = excluded.state,
            start_date = excluded.start_date,
            end_date = excluded.end_date,
            duration = excluded.duration,
            healthkit_uuid = excluded.healthkit_uuid,
            last_error = excluded.last_error,
            updated_at = excluded.updated_at
          """,
        arguments: [
          record.sessionID, record.syncIdentifier, record.syncVersion, record.state.rawValue,
          record.startDate.timeIntervalSince1970, record.endDate.timeIntervalSince1970,
          record.duration, record.healthKitUUID, record.lastError,
          record.updatedAt.timeIntervalSince1970,
        ])
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
      let completedSnapshot = SessionCorrectionSnapshot(
        sessionID: completion.sessionID,
        status: .completed,
        intendedDate: session.intendedDate,
        primaryLiftID: session.primaryLiftID,
        assistanceLiftID: session.assistanceLiftID,
        completion: completion,
        updatedAt: completion.confirmedAt)
      try Self.reconcileHealthWorkoutWriteBack(
        db,
        sessionID: completion.sessionID,
        before: completedSnapshot,
        after: completedSnapshot,
        occurredAt: completion.confirmedAt)
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

      if request.status == .scheduled || request.status == .skipped
        || request.status == .unperformed
      {
        // Keep the association as an auditable historical fact while the
        // local Session moves away from completed work.
        try db.execute(
          sql:
            "UPDATE health_workout_link_facts SET unlinked_at = ? WHERE local_entity_kind = ? AND local_entity_id = ? AND unlinked_at IS NULL",
          arguments: [occurredAt, TrainingEventLocalEntityKind.session.rawValue, request.sessionID]
        )
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
      try Self.reconcileHealthWorkoutWriteBack(
        db,
        sessionID: request.sessionID,
        before: current,
        after: after,
        occurredAt: occurredAt)
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

  /// Keeps the durable local write-back intent aligned with a correction. This
  /// runs in the same transaction as the Session mutation; a later HealthKit
  /// failure can therefore leave a queued version without ever rolling back
  /// the owner's local correction.
  private static func reconcileHealthWorkoutWriteBack(
    _ db: Database,
    sessionID: String,
    before: SessionCorrectionSnapshot,
    after: SessionCorrectionSnapshot,
    occurredAt: Int64
  ) throws {
    guard
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT sync_identifier, sync_version, state, start_date, end_date, healthkit_uuid FROM health_workout_write_backs WHERE session_id = ?",
        arguments: [sessionID]),
      let state = HealthWorkoutWriteBackState(rawValue: row["state"] as String),
      state != .notShared
    else { return }

    if after.status == .scheduled || after.status == .skipped || after.status == .unperformed {
      try db.execute(
        sql:
          "UPDATE health_workout_write_backs SET state = ?, healthkit_uuid = NULL, updated_at = ? WHERE session_id = ?",
        arguments: [HealthWorkoutWriteBackState.notShared.rawValue, Double(occurredAt), sessionID])
      return
    }
    if after.status != .completed {
      try db.execute(
        sql: "UPDATE health_workout_write_backs SET state = ?, updated_at = ? WHERE session_id = ?",
        arguments: [
          HealthWorkoutWriteBackState.updatePending.rawValue, Double(occurredAt), sessionID,
        ])
      return
    }

    let completedAt = after.completion?.confirmedAt ?? occurredAt
    let startDate = Self.writeBackStartDate(for: after.intendedDate, fallback: completedAt)
    let endDate = Double(completedAt)
    let currentStart = row["start_date"] as Double
    let currentEnd = row["end_date"] as Double
    let factsChanged = currentStart != startDate || currentEnd != endDate
    let nextVersion = (row["sync_version"] as Int64) + (factsChanged ? 1 : 0)
    let nextState: HealthWorkoutWriteBackState =
      factsChanged ? .queued : (state == .updatePending ? .savedToHealth : state)
    try db.execute(
      sql:
        "UPDATE health_workout_write_backs SET sync_version = ?, state = ?, start_date = ?, end_date = ?, duration = ?, updated_at = ? WHERE session_id = ?",
      arguments: [
        nextVersion, nextState.rawValue, startDate, endDate, max(0, endDate - startDate),
        Double(occurredAt), sessionID,
      ])
    _ = before
  }

  private static func writeBackStartDate(for date: TrainingDate, fallback: Int64) -> Double {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(
      from: DateComponents(year: date.year, month: date.month, day: date.day))?
      .timeIntervalSince1970
      ?? Double(fallback)
  }

  private func performReplacement(
    _ data: TrainingAuthoritativeExportData,
    progress: TrainingImportProgressHandler?
  ) async throws {
    let locations = actualLocations()
    var replacementCompleted = false
    defer {
      if !replacementCompleted {
        try? FileManager.default.removeItem(at: locations.authoritativeStagingDatabase)
      }
    }
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: locations.authoritativeDirectory, withIntermediateDirectories: true)
    try? fileManager.removeItem(at: locations.authoritativeStagingDatabase)
    try? fileManager.removeItem(at: locations.authoritativeBackupDatabase)

    try phaseObserver.didReach(.staging)
    progress?(
      .init(phase: .staging, fraction: 0.15, message: "Preparing an isolated staging database."))
    var staged: DatabaseQueue?
    do {
      var configuration = Configuration()
      configuration.label = "TrainingCompassImport"
      staged = try DatabaseQueue(
        path: locations.authoritativeStagingDatabase.path(), configuration: configuration)
      guard let stagingDatabase = staged else {
        throw TrainingImportError.stagingFailed("staging database unavailable")
      }
      try phaseObserver.didReach(.migrating)
      progress?(
        .init(phase: .migrating, fraction: 0.3, message: "Migrating the archive into staging."))
      try ProtectedStoreBootstrapper.authoritativeMigrator.migrate(stagingDatabase)
      try await stagingDatabase.write { db in
        try Self.insert(data, into: db)
        try phaseObserver.didReach(.validatingStaging)
        progress?(
          .init(
            phase: .validatingStaging, fraction: 0.55,
            message: "Validating relationships and domain invariants."))
        try Self.validateStagedStore(db)
        try phaseObserver.didReach(.regeneratingProjections)
        progress?(
          .init(
            phase: .regeneratingProjections, fraction: 0.7,
            message: "Regenerating derived session projections."))
        try Self.regenerateProjections(db)
      }
      try stagingDatabase.close()
      staged = nil
    } catch {
      let failure = error
      try? staged?.close()
      try? fileManager.removeItem(at: locations.authoritativeStagingDatabase)
      if let importError = failure as? TrainingImportError { throw importError }
      throw TrainingImportError.stagingFailed(String(describing: failure))
    }

    try phaseObserver.didReach(.closingCurrentStore)
    progress?(
      .init(
        phase: .closingCurrentStore, fraction: 0.8,
        message: "Closing the current store before replacement."))
    let current = try await readyStores()
    try current.authoritative.close()
    try current.reconstructible.close()
    stores = nil

    try phaseObserver.didReach(.swappingAuthoritativeStore)
    progress?(
      .init(
        phase: .swappingAuthoritativeStore, fraction: 0.9,
        message: "Installing the validated replacement."))
    do {
      if fileManager.fileExists(atPath: locations.authoritativeBackupDatabase.path()) {
        try fileManager.removeItem(at: locations.authoritativeBackupDatabase)
      }
      guard fileManager.createFile(atPath: locations.authoritativeSwapMarker.path(), contents: nil)
      else {
        throw TrainingImportError.replacementFailed("swap marker unavailable")
      }
      let hadCurrent = fileManager.fileExists(atPath: locations.authoritativeDatabase.path())
      if hadCurrent {
        try fileManager.moveItem(
          at: locations.authoritativeDatabase, to: locations.authoritativeBackupDatabase)
      }
      do {
        try fileManager.moveItem(
          at: locations.authoritativeStagingDatabase, to: locations.authoritativeDatabase)
        try bootstrapper.protectAuthoritativeStore(in: root)
      } catch {
        try? fileManager.removeItem(at: locations.authoritativeDatabase)
        if hadCurrent, fileManager.fileExists(atPath: locations.authoritativeBackupDatabase.path())
        {
          try? fileManager.moveItem(
            at: locations.authoritativeBackupDatabase, to: locations.authoritativeDatabase)
        }
        throw error
      }
      if fileManager.fileExists(atPath: locations.authoritativeBackupDatabase.path()) {
        try fileManager.removeItem(at: locations.authoritativeBackupDatabase)
      }
      try? fileManager.removeItem(at: locations.authoritativeSwapMarker)
      replacementCompleted = true
    } catch {
      try? fileManager.removeItem(at: locations.authoritativeStagingDatabase)
      throw TrainingImportError.replacementFailed(String(describing: error))
    }
  }

  private func actualLocations() -> StoreLocations {
    StoreLocations(root: Self.applicationDataRoot(fallback: root))
  }

  private func erasureMarker(for locations: StoreLocations) -> URL {
    locations.root.appending(path: "training-compass-erasure.pending", directoryHint: .notDirectory)
  }

  private func recoverPendingErasure() throws {
    let locations = actualLocations()
    let marker = erasureMarker(for: locations)
    guard FileManager.default.fileExists(atPath: marker.path()) else { return }
    do {
      try removeIfPresent(locations.authoritativeDirectory)
      try removeIfPresent(locations.reconstructibleDirectory)
      try removeIfPresent(locations.diagnosticsDirectory)
      try removeIfPresent(temporaryExportDirectory)
      try erasurePreferences.removeAll()
      try removeIfPresent(marker)
    } catch {
      throw TrainingErasureError.cleanupFailed
    }
  }

  private func removeIfPresent(_ url: URL) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path()) else { return }
    try fileManager.removeItem(at: url)
  }

  private func reachErasurePhase(
    _ phase: TrainingErasurePhase,
    fraction: Double,
    message: String,
    progress: TrainingErasureProgressHandler?
  ) throws {
    try erasurePhaseObserver.didReach(phase)
    progress?(.init(phase: phase, fraction: fraction, message: message))
  }

  private static func insert(_ data: TrainingAuthoritativeExportData, into db: Database) throws {
    let tableNames = try String.fetchAll(
      db,
      sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
    )
    let available = Set(tableNames)
    let byName = Dictionary(uniqueKeysWithValues: data.tables.map { ($0.name, $0) })
    for tableName in importTableOrder {
      guard let table = byName[tableName] else { continue }
      guard available.contains(table.name) else {
        throw TrainingImportError.incompleteArchive("table \(table.name)")
      }
      let quotedTable = quoteIdentifier(table.name)
      if table.name == "gate_zero_metadata"
        || table.name == "health_workout_write_back_preferences"
      {
        try db.execute(sql: "DELETE FROM \(quotedTable)")
      }
      let schemaColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(\(quotedTable))")
        .map { $0["name"] as String }
      let expected = Set(schemaColumns)
      for record in table.records {
        let provided = Set(record.fields.keys)
        let legacyColumns = legacyImportColumns[table.name] ?? []
        guard provided == expected || provided == expected.subtracting(legacyColumns) else {
          throw TrainingImportError.incompleteArchive("columns in \(table.name)")
        }
        let orderedValues = schemaColumns.map { column in
          databaseValue(
            record.fields[column]
              ?? legacyImportDefault(table: table.name, column: column)
              ?? .null
          )
        }
        let placeholders = Array(repeating: "?", count: schemaColumns.count).joined(separator: ", ")
        let quotedColumns = schemaColumns.map(quoteIdentifier).joined(separator: ", ")
        try db.execute(
          sql: "INSERT INTO \(quotedTable) (\(quotedColumns)) VALUES (\(placeholders))",
          arguments: StatementArguments(orderedValues.map(\.storage.value))
        )
      }
    }
    // Historical exports carry the Gate 0 marker's original schema value. The
    // staged database has already run the current migration chain, so
    // normalize that marker before invariant validation.
    try db.execute(
      sql: "UPDATE gate_zero_metadata SET schema_version = ?, owner_data_accepted = 0",
      arguments: [ProtectedStoreBootstrapper.authoritativeMigrator.migrations.count]
    )
  }

  private static func validateStagedStore(_ db: Database) throws {
    let foreignKeys = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
    guard foreignKeys.isEmpty else {
      throw TrainingImportError.invalidRelationship("foreign key check")
    }
    let cycles = try Row.fetchAll(
      db, sql: "SELECT id, lifecycle_state, cycle_json FROM training_cycles")
    var cycleIDs = Set<String>()
    var sessionIDs = Set<String>()
    var prescriptionIDs = Set<String>()
    let liftIDs = Set(try String.fetchAll(db, sql: "SELECT id FROM lifts"))
    let liftRows = try Row.fetchAll(
      db,
      sql:
        "SELECT id, identity_kind, identity_value, training_max_kg, loading_increment_kg FROM lifts"
    )
    for row in liftRows {
      let kind = row["identity_kind"] as String
      let value = row["identity_value"] as String
      let identity: LiftIdentity?
      switch kind {
      case "progression": identity = ProgressionLift(rawValue: value).map(LiftIdentity.progression)
      case "variant": identity = .variant(name: value)
      case "custom": identity = .custom(name: value)
      default: identity = nil
      }
      guard let identity,
        (try? LiftConfiguration(
          id: row["id"], identity: identity,
          trainingMaxKg: row["training_max_kg"],
          loadingIncrementKg: row["loading_increment_kg"]
        )) != nil
      else {
        throw TrainingImportError.invariantViolation("lift configuration")
      }
    }
    let metadataCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gate_zero_metadata") ?? 0
    let metadataValid =
      try Int.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM gate_zero_metadata WHERE schema_version = ? AND owner_data_accepted = 0",
        arguments: [ProtectedStoreBootstrapper.authoritativeMigrator.migrations.count]
      ) ?? 0
    guard metadataCount == 1, metadataValid == 1 else {
      throw TrainingImportError.invariantViolation("gate zero metadata")
    }
    let maximumHeartRateRows = try Row.fetchAll(
      db,
      sql: "SELECT id, maximum_heart_rate_bpm, updated_at FROM heart_rate_configuration")
    guard maximumHeartRateRows.count <= 1 else {
      throw TrainingImportError.invariantViolation("maximum heart rate configuration")
    }
    for row in maximumHeartRateRows {
      guard (row["id"] as Int64) == 1,
        (try? MaximumHeartRate(beatsPerMinute: row["maximum_heart_rate_bpm"] as Double)) != nil,
        (row["updated_at"] as Int64) >= 0
      else {
        throw TrainingImportError.invariantViolation("maximum heart rate configuration")
      }
    }
    for row in cycles {
      let cycle = try trainingCycle(from: row)
      guard cycle.id == (row["id"] as String), cycleIDs.insert(cycle.id).inserted else {
        throw TrainingImportError.invariantViolation("training cycle identity")
      }
      guard cycle.lifecycleState.rawValue == (row["lifecycle_state"] as String) else {
        throw TrainingImportError.invariantViolation("cycle lifecycle state")
      }
      guard cycle.liftSnapshots.keys.allSatisfy({ liftIDs.contains($0) }) else {
        throw TrainingImportError.invalidRelationship("cycle lift snapshot")
      }
      for session in cycle.weeks.flatMap(\.sessions) {
        guard sessionIDs.insert(session.id).inserted else {
          throw TrainingImportError.invariantViolation("duplicate session identity")
        }
        guard cycle.liftSnapshots[session.primaryLiftID] != nil,
          cycle.liftSnapshots[session.assistanceLiftID] != nil
        else {
          throw TrainingImportError.invalidRelationship("session lift")
        }
        for prescription in session.prescriptions {
          guard prescriptionIDs.insert(prescription.id).inserted else {
            throw TrainingImportError.invariantViolation("duplicate prescription identity")
          }
        }
      }
    }
    let templateIDs = Set(try String.fetchAll(db, sql: "SELECT id FROM schedule_templates"))
    for row in try Row.fetchAll(db, sql: "SELECT template_id FROM schedule_template_audit") {
      guard templateIDs.contains(row["template_id"]) else {
        throw TrainingImportError.invalidRelationship("schedule template audit")
      }
    }
    for row in try Row.fetchAll(db, sql: "SELECT cycle_id FROM training_cycle_audit") {
      guard cycleIDs.contains(row["cycle_id"]) else {
        throw TrainingImportError.invalidRelationship("cycle audit")
      }
    }
    for row in try Row.fetchAll(
      db, sql: "SELECT session_id, cycle_id FROM session_correction_audit")
    {
      guard sessionIDs.contains(row["session_id"]), cycleIDs.contains(row["cycle_id"]) else {
        throw TrainingImportError.invalidRelationship("session correction audit")
      }
    }
    for row in try Row.fetchAll(db, sql: "SELECT session_id, prescription_id FROM set_result_audit")
    {
      guard sessionIDs.contains(row["session_id"]), prescriptionIDs.contains(row["prescription_id"])
      else {
        throw TrainingImportError.invalidRelationship("set result audit")
      }
    }
    for row in try Row.fetchAll(
      db, sql: "SELECT session_id, prescription_id, result_json FROM set_results")
    {
      guard sessionIDs.contains(row["session_id"]), prescriptionIDs.contains(row["prescription_id"])
      else {
        throw TrainingImportError.invalidRelationship("set result")
      }
      _ = try recordedSetResult(from: row)
    }
    for row in try Row.fetchAll(db, sql: "SELECT session_id, prescription_id FROM omitted_sets") {
      guard sessionIDs.contains(row["session_id"]), prescriptionIDs.contains(row["prescription_id"])
      else {
        throw TrainingImportError.invalidRelationship("omitted set")
      }
    }
    for row in try Row.fetchAll(db, sql: "SELECT session_id, lift_id FROM additional_sets") {
      guard sessionIDs.contains(row["session_id"]), liftIDs.contains(row["lift_id"]) else {
        throw TrainingImportError.invalidRelationship("additional set")
      }
    }
    let completedSessionIDs = Set(
      try String.fetchAll(db, sql: "SELECT session_id FROM session_completions")
    )
    for sessionID in completedSessionIDs {
      guard sessionIDs.contains(sessionID) else {
        throw TrainingImportError.invalidRelationship("session completion")
      }
    }
    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT id, healthkit_uuid, local_entity_kind, local_entity_id, linked_at,
               linked_during_completion, write_back_disposition, unlinked_at
        FROM health_workout_link_facts
        """
    ) {
      let id = row["id"] as String
      let healthKitUUID = row["healthkit_uuid"] as String
      let localEntityKind = TrainingEventLocalEntityKind(
        rawValue: row["local_entity_kind"] as String)
      let localEntityID = row["local_entity_id"] as String
      let linkedAt = row["linked_at"] as Double
      let linkedDuringCompletion = row["linked_during_completion"] as Bool
      let disposition = TrainingEventWriteBackDisposition(
        rawValue: row["write_back_disposition"] as String)
      let unlinkedAt = row["unlinked_at"] as Double?
      guard !id.isEmpty, !healthKitUUID.isEmpty, localEntityKind == .session,
        sessionIDs.contains(localEntityID), linkedAt.isFinite,
        unlinkedAt?.isFinite ?? true, unlinkedAt.map({ $0 >= linkedAt }) ?? true,
        disposition != nil,
        linkedDuringCompletion
          ? disposition == .suppressedExternalWorkoutLinkedAtCompletion
          : disposition == .notApplicable
      else {
        throw TrainingImportError.invalidRelationship("training event link")
      }
    }
    for row in try Row.fetchAll(
      db,
      sql: "SELECT healthkit_uuid, excluded_at FROM running_comparison_exclusions"
    ) {
      let uuid = row["healthkit_uuid"] as String
      guard !uuid.isEmpty, (row["excluded_at"] as Double).isFinite else {
        throw TrainingImportError.invariantViolation("running comparison exclusion")
      }
    }
    for row in try Row.fetchAll(db, sql: "SELECT proposal_json FROM training_max_proposals") {
      let data = try JSONDecoder().decode(
        TrainingMaxProposal.self, from: Data((row["proposal_json"] as String).utf8))
      guard liftIDs.contains(data.liftID), cycleIDs.contains(data.sourceCycleID) else {
        throw TrainingImportError.invalidRelationship("training max proposal")
      }
    }
    for row in try Row.fetchAll(db, sql: "SELECT history_json FROM training_max_history") {
      let data = try JSONDecoder().decode(
        TrainingMaxHistoryEntry.self, from: Data((row["history_json"] as String).utf8))
      guard liftIDs.contains(data.liftID) else {
        throw TrainingImportError.invalidRelationship("training max history")
      }
    }
  }

  private static func regenerateProjections(_ db: Database) throws {
    try db.execute(sql: "DELETE FROM session_projections")
    for row in try Row.fetchAll(db, sql: "SELECT cycle_json FROM training_cycles") {
      let cycle = try trainingCycle(from: row)
      for session in cycle.weeks.flatMap(\.sessions) where session.status != .unperformed {
        try upsertSessionProjection(
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
    }
  }

  private static func databaseValue(_ value: TrainingExportJSONValue) -> DatabaseValue {
    switch value {
    case .null: return .null
    case .boolean(let value): return value.databaseValue
    case .integer(let value): return value.databaseValue
    case .number(let value): return value.databaseValue
    case .string(let value): return value.databaseValue
    case .blob(let value): return (Data(base64Encoded: value) ?? Data()).databaseValue
    }
  }

  private static func quoteIdentifier(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  private static let importTableOrder = [
    "gate_zero_metadata", "lifts", "schedule_templates", "schedule_template_sessions",
    "training_cycles", "set_results", "omitted_sets", "additional_sets", "session_completions",
    "lift_configuration_audit", "schedule_template_audit", "training_cycle_audit",
    "set_result_audit",
    "session_correction_audit", "training_max_proposals", "training_max_history",
    "health_workout_link_facts", "heart_rate_configuration",
    "running_comparison_exclusions", "health_workout_write_backs",
  ]

  private static let legacyImportColumns: [String: Set<String>] = [
    "health_workout_link_facts": [
      "linked_during_completion", "write_back_disposition", "unlinked_at",
    ]
  ]

  private static func legacyImportDefault(
    table: String,
    column: String
  ) -> TrainingExportJSONValue? {
    guard table == "health_workout_link_facts" else { return nil }
    switch column {
    case "linked_during_completion": return .boolean(false)
    case "write_back_disposition":
      return .string(TrainingEventWriteBackDisposition.notApplicable.rawValue)
    case "unlinked_at": return .null
    default: return nil
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
      let status: TrainingSessionStatus
      if session.status == .unperformed {
        status = .unperformed
      } else if hasCompletion {
        status = .completed
      } else {
        status = hasWork ? .inProgress : session.status
      }
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
      after: after,
      note: row["note"],
      targetID: row["target_id"]
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

  private static func encodeTrainingMaxProposal(_ proposal: TrainingMaxProposal) throws -> String {
    let data = try JSONEncoder().encode(proposal)
    guard let string = String(data: data, encoding: .utf8) else {
      throw PersistenceError.invalidTrainingMaxProposal
    }
    return string
  }

  private static func trainingMaxProposal(from row: Row) throws -> TrainingMaxProposal {
    guard let data = (row["proposal_json"] as String).data(using: .utf8) else {
      throw PersistenceError.invalidTrainingMaxProposal
    }
    do {
      return try JSONDecoder().decode(TrainingMaxProposal.self, from: data)
    } catch {
      throw PersistenceError.invalidTrainingMaxProposal
    }
  }

  private static func encodeTrainingMaxHistory(_ history: TrainingMaxHistoryEntry) throws -> String
  {
    let data = try JSONEncoder().encode(history)
    guard let string = String(data: data, encoding: .utf8) else {
      throw PersistenceError.invalidTrainingMaxHistory
    }
    return string
  }

  private static func trainingMaxHistory(from row: Row) throws -> TrainingMaxHistoryEntry {
    guard let data = (row["history_json"] as String).data(using: .utf8) else {
      throw PersistenceError.invalidTrainingMaxHistory
    }
    do {
      return try JSONDecoder().decode(TrainingMaxHistoryEntry.self, from: data)
    } catch {
      throw PersistenceError.invalidTrainingMaxHistory
    }
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

  private static func healthWorkoutWriteBackRecord(from row: Row)
    throws -> HealthWorkoutWriteBackRecord
  {
    guard let state = HealthWorkoutWriteBackState(rawValue: row["state"] as String) else {
      throw PersistenceError.invalidHealthWorkoutWriteBack
    }
    let startDate = Date(timeIntervalSince1970: row["start_date"] as Double)
    let endDate = Date(timeIntervalSince1970: row["end_date"] as Double)
    guard row["sync_version"] as Int64 > 0,
      startDate <= endDate,
      (row["duration"] as Double).isFinite,
      (row["duration"] as Double) >= 0
    else { throw PersistenceError.invalidHealthWorkoutWriteBack }
    return .init(
      sessionID: row["session_id"], syncIdentifier: row["sync_identifier"],
      syncVersion: row["sync_version"], state: state,
      startDate: startDate, endDate: endDate,
      healthKitUUID: row["healthkit_uuid"], lastError: row["last_error"],
      updatedAt: Date(timeIntervalSince1970: row["updated_at"]))
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

  private static func authoritativeExportData(from db: Database) throws
    -> TrainingAuthoritativeExportData
  {
    let tableNames = try String.fetchAll(
      db,
      sql: """
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """
    )
    let exportTableNames = tableNames.filter {
      !$0.hasSuffix("_projections") && $0 != "grdb_migrations"
        && $0 != "health_workout_write_back_preferences"
    }
    let tables = try exportTableNames.map { tableName -> TrainingExportTable in
      let quotedName = "\"" + tableName.replacingOccurrences(of: "\"", with: "\"\"") + "\""
      let rows = try Row.fetchAll(db, sql: "SELECT rowid, * FROM \(quotedName) ORDER BY rowid")
      let records = rows.map { row -> TrainingExportRecord in
        let columns = Array(row.columnNames)
        let values = Array(row.databaseValues)
        var fields: [String: TrainingExportJSONValue] = [:]
        for (index, column) in columns.enumerated() where column != "rowid" {
          fields[column] = exportValue(values[index])
        }
        let id = stableExportRecordID(table: tableName, fields: fields)
        return TrainingExportRecord(id: id, fields: fields)
      }
      return TrainingExportTable(name: tableName, records: records)
    }
    let preferences =
      tables
      .filter {
        ["preferences", "user_preferences", "app_preferences"].contains($0.name.lowercased())
      }
      .flatMap { table in
        table.records.compactMap { record -> TrainingExportPreference? in
          guard let key = preferenceKey(for: record) else { return nil }
          return TrainingExportPreference(
            key: key,
            value: record.fields["value"] ?? .null
          )
        }
      }
    return TrainingAuthoritativeExportData(tables: tables, preferences: preferences)
  }

  private static func stableExportRecordID(
    table: String,
    fields: [String: TrainingExportJSONValue]
  ) -> String {
    if let id = fields["id"], case .string(let value) = id { return value }
    let identityColumns = ["session_id", "prescription_id", "lift_id", "cycle_id", "template_id"]
    let parts = identityColumns.compactMap { column -> String? in
      guard let value = fields[column] else { return nil }
      switch value {
      case .string(let string): return "\(column)=\(string)"
      case .integer(let integer): return "\(column)=\(integer)"
      default: return nil
      }
    }
    if !parts.isEmpty { return parts.joined(separator: "|") }
    return TrainingExportRecord.stableID(table: table, fields: fields)
  }

  private static func preferenceKey(for record: TrainingExportRecord) -> String? {
    for field in ["key", "name", "id"] {
      if let value = record.fields[field], case .string(let string) = value, !string.isEmpty {
        return string
      }
    }
    return record.id
  }

  private static func exportValue(_ value: DatabaseValue) -> TrainingExportJSONValue {
    switch value.storage {
    case .null:
      return .null
    case .int64(let value):
      return .integer(value)
    case .double(let value):
      return .number(value)
    case .string(let value):
      return .string(value)
    case .blob(let value):
      return .blob(base64: value.base64EncodedString())
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
  case invalidTrainingMaxProposal
  case invalidTrainingMaxHistory
  case storesUnavailable
  case invalidHealthWorkout
  case invalidHealthWorkoutWriteBack
}

public enum TrainingPersistenceModule {}
