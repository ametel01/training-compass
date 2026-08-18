import Foundation
import GRDB
import TrainingApplication

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
    private let spaceProvider: any StoreMigrationSpaceProviding
    private let progress: StoreMigrationProgressHandler?

    public init(
        protection: any StoreProtectionManaging = FileManagerStoreProtection(),
        checkpoint: any StoreBootstrapCheckpointing = NoOpStoreBootstrapCheckpoint(),
        spaceProvider: any StoreMigrationSpaceProviding = FoundationStoreMigrationSpaceProvider(),
        progress: StoreMigrationProgressHandler? = nil,
    ) {
        self.protection = protection
        self.checkpoint = checkpoint
        self.spaceProvider = spaceProvider
        self.progress = progress
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
        try recoverPendingAuthoritativeSwap(locations)
        try prepareDirectory(locations.authoritativeDirectory, excludedFromBackup: false)
        try prepareDirectory(locations.reconstructibleDirectory, excludedFromBackup: true)

        var configuration = Configuration()
        configuration.label = "TrainingCompass"
        let authoritative = try DatabaseQueue(
            path: locations.authoritativeDatabase.path(percentEncoded: false),
            configuration: configuration,
        )
        let reconstructible = try DatabaseQueue(
            path: locations.reconstructibleDatabase.path(percentEncoded: false),
            configuration: configuration,
        )

        emit(
            .init(
                phase: .checkingSpace,
                fraction: 0,
                message: "Checking recoverable migration space.",
            ),
        )
        try checkMigrationSpace(for: locations.authoritativeDatabase, at: locations.root)
        try checkMigrationSpace(for: locations.reconstructibleDatabase, at: locations.root)

        emit(
            .init(
                phase: .migratingAuthoritative,
                fraction: 0.1,
                message: "Migrating Locally Authoritative Data.",
            ),
        )
        do {
            try Self.authoritativeMigrator.migrate(authoritative)
            try updateSchemaVersion(authoritative, to: Self.authoritativeMigrator.migrations.count)
            try? FileManager.default.removeItem(at: locations.authoritativeMigrationDiagnostic)
        } catch {
            writeDiagnostic(
                store: .authoritative,
                database: authoritative,
                migrator: Self.authoritativeMigrator,
                location: locations.authoritativeMigrationDiagnostic,
            )
            throw error
        }
        try checkpoint.didMigrateAuthoritativeStore()
        emit(
            .init(
                phase: .migratingReconstructible,
                fraction: 0.55,
                message: "Migrating the reconstructible Health mirror.",
            ),
        )
        do {
            try Self.reconstructibleMigrator.migrate(reconstructible)
            try updateSchemaVersion(reconstructible, to: Self.reconstructibleMigrator.migrations.count)
            try? FileManager.default.removeItem(at: locations.reconstructibleMigrationDiagnostic)
        } catch {
            writeDiagnostic(
                store: .reconstructible,
                database: reconstructible,
                migrator: Self.reconstructibleMigrator,
                location: locations.reconstructibleMigrationDiagnostic,
            )
            throw error
        }

        try protection.applyCompleteFileProtection(to: locations.authoritativeDatabase)
        try protection.applyCompleteFileProtection(to: locations.reconstructibleDatabase)
        try protection.verifyCompleteFileProtection(at: locations.authoritativeDirectory)
        try protection.verifyCompleteFileProtection(at: locations.reconstructibleDirectory)
        try protection.verifyCompleteFileProtection(at: locations.authoritativeDatabase)
        try protection.verifyCompleteFileProtection(at: locations.reconstructibleDatabase)
        try protection.verifyExcludedFromBackup(at: locations.reconstructibleDirectory)

        emit(
            .init(
                phase: .completed,
                fraction: 1,
                message: "Protected stores are ready.",
            ),
        )

        return TrainingStores(
            authoritative: authoritative,
            reconstructible: reconstructible,
        )
    }

    private func emit(_ value: StoreMigrationProgress) {
        progress?(value)
    }

    private func updateSchemaVersion(_ database: DatabaseQueue, to version: Int) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE gate_zero_metadata SET schema_version = ?",
                arguments: [version],
            )
        }
    }

    private func checkMigrationSpace(for database: URL, at root: URL) throws {
        let currentBytes: Int64 = if let attributes = try? FileManager.default.attributesOfItem(
            atPath: database.path(percentEncoded: false),
        ),
            let fileSize = attributes[.size] as? NSNumber
        {
            max(0, fileSize.int64Value)
        } else {
            0
        }
        let (recoveryCopy, recoveryOverflow) = currentBytes.addingReportingOverflow(currentBytes)
        let (withJournal, journalOverflow) = recoveryCopy.addingReportingOverflow(64 * 1024)
        let required =
            recoveryOverflow || journalOverflow
                ? Int64.max
                : Int64((Double(withJournal) * 1.2).rounded(.up))
        let available = try spaceProvider.availableMigrationSpaceBytes(at: root)
        guard available >= required else {
            throw StoreMigrationError.insufficientSpace(
                requiredBytes: required, availableBytes: available,
            )
        }
    }

    private func writeDiagnostic(
        store: TrainingStoreKind,
        database: DatabaseQueue,
        migrator: DatabaseMigrator,
        location: URL,
    ) {
        let applied = (try? database.read { db in try migrator.appliedIdentifiers(db) }) ?? []
        let attemptedIndex =
            migrator.migrations.firstIndex { !applied.contains($0) } ?? migrator.migrations.count - 1
        let diagnostic = StoreMigrationDiagnostic(
            store: store,
            attemptedVersion: max(1, attemptedIndex + 1),
            attemptedMigration: migrator.migrations.indices.contains(attemptedIndex)
                ? migrator.migrations[attemptedIndex] : "unknown",
        )
        guard let data = try? JSONEncoder().encode(diagnostic) else { return }
        try? data.write(to: location, options: [.atomic])
    }

    /// Applies the same protection and backup invariants to a database installed
    /// by a replacement import before it becomes authoritative.
    public func protectAuthoritativeStore(in root: URL) throws {
        #if targetEnvironment(simulator)
            let simulatorRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "TrainingCompass", directoryHint: .isDirectory)
            let locations = StoreLocations(root: simulatorRoot)
        #else
            let locations = StoreLocations(root: root)
        #endif
        try protection.applyCompleteFileProtection(to: locations.authoritativeDatabase)
        try protection.verifyCompleteFileProtection(at: locations.authoritativeDirectory)
        try protection.verifyCompleteFileProtection(at: locations.authoritativeDatabase)
    }

    private func prepareDirectory(_ url: URL, excludedFromBackup: Bool) throws {
        try protection.createDirectory(at: url)
        try protection.applyCompleteFileProtection(to: url)
        if excludedFromBackup {
            try protection.excludeFromBackup(url)
        }
    }

    private func recoverPendingAuthoritativeSwap(_ locations: StoreLocations) throws {
        let fileManager = FileManager.default
        let markerExists = fileManager.fileExists(
            atPath: locations.authoritativeSwapMarker.path(percentEncoded: false),
        )
        let currentExists = fileManager.fileExists(
            atPath: locations.authoritativeDatabase.path(percentEncoded: false),
        )
        let backupExists = fileManager.fileExists(
            atPath: locations.authoritativeBackupDatabase.path(percentEncoded: false),
        )
        if !markerExists, !backupExists {
            if fileManager.fileExists(
                atPath: locations.authoritativeStagingDatabase.path(percentEncoded: false),
            ) {
                try fileManager.removeItem(at: locations.authoritativeStagingDatabase)
            }
            return
        }

        if !currentExists, backupExists {
            try fileManager.moveItem(
                at: locations.authoritativeBackupDatabase, to: locations.authoritativeDatabase,
            )
        } else if currentExists, backupExists {
            // A fully moved replacement is authoritative; the previous file is
            // only a rollback candidate and must not be reopened as live data.
            try fileManager.removeItem(at: locations.authoritativeBackupDatabase)
        }
        if markerExists {
            try fileManager.removeItem(at: locations.authoritativeSwapMarker)
        }
        if fileManager.fileExists(
            atPath: locations.authoritativeStagingDatabase.path(percentEncoded: false),
        ) {
            try fileManager.removeItem(at: locations.authoritativeStagingDatabase)
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
                unique: true,
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
                ],
            )
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
                unique: true,
            )
            try db.create(table: "schedule_template_audit") { table in
                table.column("id", .text).primaryKey()
                table.column("template_id", .text).notNull()
                table.column("action", .text).notNull()
                    .check {
                        $0 == "created" || $0 == "edited" || $0 == "reset"
                            || $0 == "savedFromTrainingWeek"
                    }
                table.column("occurred_at", .integer).notNull()
                table.column("before_json", .text)
                table.column("after_json", .text).notNull()
            }
            try db.create(
                index: "schedule_template_audit_time", on: "schedule_template_audit",
                columns: ["template_id", "occurred_at"],
            )
        }
        migrator.registerMigration("authoritative_v4_training_cycle") { db in
            try db.create(table: "training_cycles") { table in
                table.column("id", .text).primaryKey()
                table.column("lifecycle_state", .text).notNull()
                    .check { $0 == "draft" || $0 == "active" || $0 == "completed" || $0 == "abandoned" }
                table.column("anchor_date", .text).notNull()
                table.column("includes_provisional_deload", .boolean).notNull()
                table.column("cycle_json", .text).notNull()
                table.column("created_at", .integer).notNull()
                table.column("updated_at", .integer).notNull()
            }
            try db.create(
                index: "training_cycles_state", on: "training_cycles",
                columns: ["lifecycle_state", "updated_at"],
            )
            try db.execute(
                sql:
                "CREATE UNIQUE INDEX training_cycles_single_draft ON training_cycles (lifecycle_state) WHERE lifecycle_state = 'draft'",
            )
            try db.execute(
                sql:
                "CREATE UNIQUE INDEX training_cycles_single_active ON training_cycles (lifecycle_state) WHERE lifecycle_state = 'active'",
            )
            try db.create(table: "training_cycle_audit") { table in
                table.column("id", .text).primaryKey()
                table.column("cycle_id", .text).notNull()
                table.column("action", .text).notNull()
                table.column("occurred_at", .integer).notNull()
                table.column("before_json", .text)
                table.column("after_json", .text)
            }
            try db.create(
                index: "training_cycle_audit_time", on: "training_cycle_audit",
                columns: ["cycle_id", "occurred_at"],
            )
        }
        migrator.registerMigration("authoritative_v5_set_results") { db in
            try db.create(table: "set_results") { table in
                table.column("id", .text).primaryKey()
                table.column("session_id", .text).notNull()
                table.column("prescription_id", .text).notNull()
                table.column("result_json", .text).notNull()
                table.column("recorded_at", .integer).notNull()
            }
            try db.create(
                index: "set_results_session_prescription",
                on: "set_results",
                columns: ["session_id", "prescription_id"],
                unique: true,
            )
            try db.create(table: "set_result_audit") { table in
                table.column("id", .text).primaryKey()
                table.column("session_id", .text).notNull()
                table.column("prescription_id", .text).notNull()
                table.column("action", .text).notNull().check { $0 == "recorded" }
                table.column("occurred_at", .integer).notNull()
                table.column("before_json", .text)
                table.column("after_json", .text).notNull()
            }
            try db.create(
                index: "set_result_audit_session_time",
                on: "set_result_audit",
                columns: ["session_id", "occurred_at"],
            )
        }
        migrator.registerMigration("authoritative_v6_session_logging_completion") { db in
            try db.create(table: "omitted_sets") { table in
                table.column("session_id", .text).notNull()
                table.column("prescription_id", .text).notNull()
                table.column("reason", .text)
                table.column("omitted_at", .integer).notNull()
                table.primaryKey(["session_id", "prescription_id"])
            }
            try db.create(
                index: "omitted_sets_session",
                on: "omitted_sets",
                columns: ["session_id", "omitted_at"],
            )
            try db.create(table: "additional_sets") { table in
                table.column("id", .text).primaryKey()
                table.column("session_id", .text).notNull()
                table.column("position", .integer).notNull().check { $0 >= 0 }
                table.column("lift_id", .text).notNull().check { $0 != "" }
                table.column("weight_kg", .double).notNull().check { $0 > 0 }
                table.column("repetitions", .integer).notNull().check { $0 >= 0 }
                table.column("note", .text)
                table.column("recorded_at", .integer).notNull()
            }
            try db.create(
                index: "additional_sets_session_order",
                on: "additional_sets",
                columns: ["session_id", "position"],
                unique: true,
            )
            try db.create(table: "session_completions") { table in
                table.column("session_id", .text).primaryKey()
                table.column("confirmed_at", .integer).notNull()
            }
        }
        migrator.registerMigration("authoritative_v7_session_corrections") { db in
            try db.create(table: "session_projections") { table in
                table.column("session_id", .text).primaryKey()
                table.column("cycle_id", .text).notNull()
                table.column("status", .text).notNull()
                    .check {
                        $0 == "scheduled" || $0 == "inProgress" || $0 == "completed" || $0 == "skipped"
                    }
                table.column("intended_date", .text).notNull()
                table.column("primary_lift_id", .text).notNull().check { $0 != "" }
                table.column("assistance_lift_id", .text).notNull().check { $0 != "" }
                table.column("updated_at", .integer).notNull()
            }
            try db.create(
                index: "session_projections_cycle", on: "session_projections",
                columns: ["cycle_id", "updated_at"],
            )
            try db.create(table: "session_correction_audit") { table in
                table.column("id", .text).primaryKey()
                table.column("cycle_id", .text).notNull()
                table.column("session_id", .text).notNull()
                table.column("occurred_at", .integer).notNull()
                table.column("note", .text)
                table.column("before_json", .text).notNull()
                table.column("after_json", .text).notNull()
            }
            try db.create(
                index: "session_correction_audit_session_time", on: "session_correction_audit",
                columns: ["session_id", "occurred_at"],
            )
        }
        migrator.registerMigration("authoritative_v8_training_week_template_source") { db in
            try db.create(table: "schedule_template_audit_v8") { table in
                table.column("id", .text).primaryKey()
                table.column("template_id", .text).notNull()
                table.column("action", .text).notNull()
                    .check {
                        $0 == "created" || $0 == "edited" || $0 == "reset"
                            || $0 == "savedFromTrainingWeek"
                    }
                table.column("occurred_at", .integer).notNull()
                table.column("before_json", .text)
                table.column("after_json", .text).notNull()
            }
            try db.execute(
                sql: """
                INSERT INTO schedule_template_audit_v8
                  (id, template_id, action, occurred_at, before_json, after_json)
                SELECT id, template_id, action, occurred_at, before_json, after_json
                FROM schedule_template_audit
                """,
            )
            try db.drop(table: "schedule_template_audit")
            try db.rename(table: "schedule_template_audit_v8", to: "schedule_template_audit")
            try db.create(
                index: "schedule_template_audit_time", on: "schedule_template_audit",
                columns: ["template_id", "occurred_at"],
            )
        }
        migrator.registerMigration("authoritative_v9_cycle_lifecycle_notes") { db in
            try db.alter(table: "training_cycle_audit") { table in
                table.add(column: "note", .text)
            }
        }
        migrator.registerMigration("authoritative_v10_cycle_lifecycle_targets") { db in
            try db.alter(table: "training_cycle_audit") { table in
                table.add(column: "target_id", .text)
            }
        }
        migrator.registerMigration("authoritative_v11_training_max_proposals") { db in
            try db.create(table: "training_max_proposals") { table in
                table.column("id", .text).primaryKey()
                table.column("lift_id", .text).notNull().references("lifts", onDelete: .restrict)
                table.column("source_cycle_id", .text).notNull()
                table.column("status", .text).notNull()
                    .check {
                        $0 == "pending" || $0 == "accepted" || $0 == "rejected"
                            || $0 == "manuallyReplaced"
                    }
                table.column("proposal_json", .text).notNull()
                table.column("created_at", .integer).notNull()
                table.column("updated_at", .integer).notNull()
            }
            try db.create(
                index: "training_max_proposals_cycle_lift",
                on: "training_max_proposals",
                columns: ["source_cycle_id", "lift_id"],
                unique: true,
            )
            try db.create(table: "training_max_history") { table in
                table.column("id", .text).primaryKey()
                table.column("lift_id", .text).notNull().references("lifts", onDelete: .restrict)
                table.column("event", .text).notNull()
                table.column("occurred_at", .integer).notNull()
                table.column("history_json", .text).notNull()
            }
            try db.create(
                index: "training_max_history_lift_time",
                on: "training_max_history",
                columns: ["lift_id", "occurred_at"],
            )
            try db.execute(
                sql: """
                INSERT INTO training_max_history
                  (id, lift_id, event, occurred_at, history_json)
                SELECT
                  lifts.id || ':initial', lifts.id, 'initial', lifts.created_at,
                  json_object(
                    'id', lifts.id || ':initial', 'liftID', lifts.id, 'event', 'initial',
                    'occurredAt', lifts.created_at, 'beforeKg', NULL,
                    'afterKg', lifts.training_max_kg, 'proposalID', NULL, 'cycleID', NULL,
                    'effectiveCycleID', NULL, 'evidence', NULL, 'decision', NULL, 'note', NULL
                  )
                FROM lifts
                """,
            )
        }
        migrator.registerMigration("authoritative_v12_health_workout_link_facts") { db in
            try db.create(table: "health_workout_link_facts") { table in
                table.column("id", .text).primaryKey()
                table.column("healthkit_uuid", .text).notNull()
                table.column("local_entity_kind", .text).notNull()
                table.column("local_entity_id", .text).notNull()
                table.column("linked_at", .double).notNull()
            }
            try db.create(
                index: "health_workout_link_facts_uuid",
                on: "health_workout_link_facts",
                columns: ["healthkit_uuid", "linked_at"],
            )
        }
        migrator.registerMigration("authoritative_v13_training_event_links") { db in
            try db.alter(table: "health_workout_link_facts") { table in
                table.add(column: "linked_during_completion", .boolean).notNull().defaults(to: false)
                table.add(column: "write_back_disposition", .text).notNull()
                    .defaults(to: TrainingEventWriteBackDisposition.notApplicable.rawValue)
                table.add(column: "unlinked_at", .double)
            }
            try db.execute(
                sql: """
                CREATE UNIQUE INDEX health_workout_link_facts_active_uuid
                ON health_workout_link_facts (healthkit_uuid)
                WHERE unlinked_at IS NULL
                """,
            )
            try db.execute(
                sql: """
                  CREATE UNIQUE INDEX health_workout_link_facts_active_local_entity
                  ON health_workout_link_facts (local_entity_kind, local_entity_id)
                  WHERE unlinked_at IS NULL
                """,
            )
        }
        migrator.registerMigration("authoritative_v14_heart_rate_configuration") { db in
            try db.create(table: "heart_rate_configuration") { table in
                table.column("id", .integer).primaryKey()
                table.column("maximum_heart_rate_bpm", .double).notNull()
                    .check { $0 > 0 }
                table.column("updated_at", .integer).notNull()
            }
        }
        migrator.registerMigration("authoritative_v15_running_comparison_exclusions") { db in
            try db.create(table: "running_comparison_exclusions") { table in
                table.column("healthkit_uuid", .text).primaryKey()
                table.column("excluded_at", .double).notNull()
            }
        }
        migrator.registerMigration("authoritative_v16_health_workout_write_back") { db in
            try db.create(table: "health_workout_write_back_preferences") { table in
                table.column("id", .text).primaryKey()
                table.column("enabled", .boolean).notNull().defaults(to: false)
                table.column("updated_at", .double).notNull()
            }
            try db.execute(
                sql:
                "INSERT INTO health_workout_write_back_preferences (id, enabled, updated_at) VALUES ('default', 0, 0)",
            )
            try db.create(table: "health_workout_write_backs") { table in
                table.column("session_id", .text).primaryKey()
                table.column("sync_identifier", .text).notNull()
                table.column("sync_version", .integer).notNull().check { $0 > 0 }
                table.column("state", .text).notNull()
                table.column("start_date", .double).notNull()
                table.column("end_date", .double).notNull()
                table.column("duration", .double).notNull().check { $0 >= 0 }
                table.column("healthkit_uuid", .text)
                table.column("last_error", .text)
                table.column("updated_at", .double).notNull()
            }
            try db.create(
                index: "health_workout_write_backs_sync_identifier",
                on: "health_workout_write_backs", columns: ["sync_identifier"], unique: true,
            )
        }
        return migrator
    }

    public static var reconstructibleMigrator: DatabaseMigrator {
        var migrator = gateZeroMigrator(named: "reconstructible_v1_gate_zero")
        migrator.registerMigration("reconstructible_v2_health_workouts") { db in
            try db.create(table: "health_workouts") { table in
                table.column("healthkit_uuid", .text).primaryKey()
                table.column("activity_type", .text).notNull()
                table.column("start_date", .double).notNull()
                table.column("end_date", .double).notNull()
                table.column("duration", .double).notNull()
                table.column("source_name", .text)
                table.column("source_bundle_identifier", .text)
                table.column("source_product_type", .text)
                table.column("source_os_version", .text)
                table.column("device_name", .text)
                table.column("device_model", .text)
                table.column("source_timezone_identifier", .text)
                table.column("local_date", .text).notNull()
                table.column("timezone_source", .text).notNull()
                table.column("first_imported_at", .double).notNull()
                table.column("reconciliation_context", .text)
                table.column("updated_at", .double).notNull()
            }
            try db.create(
                index: "health_workouts_start_date", on: "health_workouts", columns: ["start_date"],
            )
            try db.create(
                index: "health_workouts_local_date", on: "health_workouts", columns: ["local_date"],
            )
        }
        migrator.registerMigration("reconstructible_v3_health_sync_ledger") { db in
            try db.create(table: "health_sync_streams") { table in
                table.column("stream", .text).primaryKey()
                table.column("anchor", .text)
                table.column("has_limited_history", .boolean).notNull().defaults(to: false)
                table.column("reconciliation_context", .text).notNull()
                table.column("committed_at", .double).notNull()
            }
            try db.create(table: "health_sync_facts") { table in
                table.column("id", .text).primaryKey()
                table.column("stream", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("healthkit_uuid", .text).notNull()
                table.column("observed_at", .double).notNull()
            }
            try db.create(
                index: "health_sync_facts_stream_time",
                on: "health_sync_facts",
                columns: ["stream", "observed_at"],
            )
            try db.create(table: "health_workout_deletions") { table in
                table.column("healthkit_uuid", .text).primaryKey()
                table.column("deleted_at", .double).notNull()
                table.column("reconciliation_context", .text).notNull()
            }
        }
        migrator.registerMigration("reconstructible_v4_health_rebuild_state") { db in
            try db.create(table: "health_rebuild_state") { table in
                table.column("id", .integer).primaryKey()
                table.column("phase", .text).notNull()
                table.column("completed_streams", .text).notNull()
                table.column("started_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
        }
        migrator.registerMigration("reconstructible_v5_workout_enrichment") { db in
            try db.create(table: "health_workout_enrichment") { table in
                table.column("healthkit_uuid", .text).primaryKey()
                table.column("enrichment_json", .text).notNull()
                table.column("updated_at", .double).notNull()
            }
        }
        migrator.registerMigration("reconstructible_v6_workout_routes") { db in
            try db.create(table: "health_workout_routes") { table in
                table.column("healthkit_uuid", .text).primaryKey()
                table.column("route_json", .text).notNull()
                table.column("updated_at", .double).notNull()
            }
        }
        migrator.registerMigration("reconstructible_v7_running_environment") { db in
            try db.alter(table: "health_workouts") { table in
                table.add(column: "running_environment", .text)
                    .notNull()
                    .defaults(to: "unspecified")
            }
        }
        migrator.registerMigration("reconstructible_v8_running_elevation") { db in
            try db.alter(table: "health_workouts") { table in
                table.add(column: "elevation_meters", .double)
                    .check { $0 >= 0 }
            }
        }
        migrator.registerMigration("reconstructible_v9_recovery_evidence") { db in
            try db.create(table: "health_recovery_samples") { table in
                table.column("stream", .text).notNull()
                table.column("sample_id", .text).notNull()
                table.column("sample_json", .text).notNull()
                table.column("sample_date", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.primaryKey(["stream", "sample_id"])
            }
            try db.create(
                index: "health_recovery_samples_stream_date",
                on: "health_recovery_samples",
                columns: ["stream", "sample_date"],
            )
        }
        migrator.registerMigration("reconstructible_v10_write_back_metadata") { db in
            try db.alter(table: "health_workouts") { table in
                table.add(column: "app_authored_sync_identifier", .text)
                table.add(column: "app_authored_sync_version", .integer)
            }
        }
        return migrator
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
                sql: "INSERT INTO gate_zero_metadata (schema_version, owner_data_accepted) VALUES (1, 0)",
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
