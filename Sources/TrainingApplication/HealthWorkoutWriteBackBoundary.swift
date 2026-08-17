import Foundation

/// The only facts that may cross the write-back boundary.  In particular, this
/// type deliberately has no sets, loads, prescriptions, Training Maxes, notes,
/// or derived metrics.
public struct HealthWorkoutWriteBackSummary: Codable, Equatable, Sendable {
    public let sessionID: String
    public let syncIdentifier: String
    public let syncVersion: Int
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval

    public static let activityType = "Traditional Strength Training"

    public init(
        sessionID: String,
        syncIdentifier: String,
        syncVersion: Int = 1,
        startDate: Date,
        endDate: Date,
    ) {
        precondition(!sessionID.isEmpty)
        precondition(!syncIdentifier.isEmpty)
        precondition(syncVersion > 0)
        precondition(endDate >= startDate)
        self.sessionID = sessionID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.startDate = startDate
        self.endDate = endDate
        duration = max(0, endDate.timeIntervalSince(startDate))
    }
}

public enum HealthWorkoutWriteBackState: String, Codable, Equatable, Sendable {
    case notShared
    case queued
    case saving
    case savedToHealth
    case retryScheduled
    case healthAccessNeeded
    case couldntSave
    case deletedFromHealth
    case updatePending

    public var displayName: String {
        switch self {
        case .notShared: "Not shared"
        case .queued: "Queued"
        case .saving: "Saving"
        case .savedToHealth: "Saved to Health"
        case .retryScheduled: "Retry scheduled"
        case .healthAccessNeeded: "Health access needed"
        case .couldntSave: "Couldn't save"
        case .deletedFromHealth: "Deleted from Health"
        case .updatePending: "Update pending"
        }
    }

    /// States that should remain visible in the owner's quiet, aggregate status.
    /// Terminal local completion is never represented as an app-wide alert.
    public var requiresAttention: Bool {
        switch self {
        case .queued, .saving, .retryScheduled, .healthAccessNeeded, .couldntSave,
             .updatePending:
            true
        case .notShared, .savedToHealth, .deletedFromHealth:
            false
        }
    }

    /// States that may be retried automatically when the app gets a new
    /// protected-data or foreground opportunity. Access and terminal failures
    /// require an explicit owner action instead.
    public var resumesAutomatically: Bool {
        switch self {
        case .queued, .saving, .retryScheduled:
            true
        case .notShared, .savedToHealth, .healthAccessNeeded, .couldntSave,
             .deletedFromHealth, .updatePending:
            false
        }
    }
}

public struct HealthWorkoutWriteBackRecord: Codable, Equatable, Sendable, Identifiable {
    public let sessionID: String
    public let syncIdentifier: String
    public let syncVersion: Int
    public let state: HealthWorkoutWriteBackState
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval
    public let healthKitUUID: String?
    public let lastError: String?
    public let updatedAt: Date

    public init(
        sessionID: String,
        syncIdentifier: String,
        syncVersion: Int = 1,
        state: HealthWorkoutWriteBackState = .notShared,
        startDate: Date,
        endDate: Date,
        healthKitUUID: String? = nil,
        lastError: String? = nil,
        updatedAt: Date = Date(),
    ) {
        let summary = HealthWorkoutWriteBackSummary(
            sessionID: sessionID, syncIdentifier: syncIdentifier, syncVersion: syncVersion,
            startDate: startDate, endDate: endDate,
        )
        self.sessionID = summary.sessionID
        self.syncIdentifier = summary.syncIdentifier
        self.syncVersion = summary.syncVersion
        self.state = state
        self.startDate = summary.startDate
        self.endDate = summary.endDate
        duration = summary.duration
        self.healthKitUUID = healthKitUUID
        self.lastError = lastError
        self.updatedAt = updatedAt
    }

    public var id: String {
        sessionID
    }

    public var summary: HealthWorkoutWriteBackSummary {
        .init(
            sessionID: sessionID, syncIdentifier: syncIdentifier, syncVersion: syncVersion,
            startDate: startDate, endDate: endDate,
        )
    }
}

public struct HealthWorkoutWriteBackPreference: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let updatedAt: Date

    public init(enabled: Bool = false, updatedAt: Date = Date()) {
        self.enabled = enabled
        self.updatedAt = updatedAt
    }
}

public enum HealthWorkoutWriteBackClientError: Error, Equatable, Sendable {
    case unavailable
    case authorizationDenied
    case inaccessible
    case protectedDataUnavailable
}

public enum HealthWorkoutWriteBackDeletionFailure: String, Codable, Equatable, Sendable {
    case unavailable
    case authorizationDenied
    case protectedDataUnavailable
    case failed
    case persistenceFailed

    public var privacySafeDescription: String {
        switch self {
        case .unavailable: "HealthKit deletion is unavailable on this device."
        case .authorizationDenied: "HealthKit deletion access is unavailable."
        case .protectedDataUnavailable: "HealthKit is locked. Unlock the device and retry."
        case .failed, .persistenceFailed: "Some Training Compass Health summaries could not be deleted."
        }
    }
}

/// A replacement with an external Health Workout is a two-phase owner action:
/// the Training Compass object must be deleted before the external link is
/// committed.  Keeping this error distinct lets the UI offer a retry without
/// changing the existing write-back record or link.
public enum HealthWorkoutWriteBackReplacementError: Error, Equatable, Sendable {
    case deletionFailed
}

public protocol HealthWorkoutWriteBackClient: Sendable {
    func requestWriteAuthorization() async throws -> HealthAuthorizationSnapshot
    func saveWorkout(_ summary: HealthWorkoutWriteBackSummary) async throws -> String
    func workoutExists(syncIdentifier: String) async throws -> Bool
    func deleteWorkout(healthKitUUID: String) async throws
    func deleteWorkout(healthKitUUID: String, expectedSyncIdentifier: String) async throws
}

public extension HealthWorkoutWriteBackClient {
    /// Deletion is deliberately an optional capability for older clients and
    /// test doubles. The write-back boundary never uses it implicitly; callers
    /// must explicitly repair an app-owned duplicate.
    func deleteWorkout(healthKitUUID: String) async throws {
        _ = healthKitUUID
        throw HealthWorkoutWriteBackClientError.unavailable
    }

    func deleteWorkout(healthKitUUID: String, expectedSyncIdentifier: String) async throws {
        _ = expectedSyncIdentifier
        try await deleteWorkout(healthKitUUID: healthKitUUID)
    }
}

public extension HealthWorkoutWriteBackClient {
    /// Access checks are explicit and deliberately do not retry a queued
    /// operation. The owner can inspect the result and then choose Try Again.
    func checkWriteAuthorization() async throws -> HealthAuthorizationSnapshot {
        let snapshot = try await requestWriteAuthorization()
        switch snapshot.state {
        case .authorized:
            return snapshot
        case .unavailable:
            throw HealthWorkoutWriteBackClientError.unavailable
        case .notRequested, .postponed:
            throw HealthWorkoutWriteBackClientError.authorizationDenied
        }
    }
}

public protocol HealthWorkoutWriteBackRepository: Sendable {
    func loadHealthWorkoutWriteBackPreference() async throws -> HealthWorkoutWriteBackPreference
    func saveHealthWorkoutWriteBackPreference(_ preference: HealthWorkoutWriteBackPreference)
        async throws
    func loadHealthWorkoutWriteBack(sessionID: String) async throws -> HealthWorkoutWriteBackRecord?
    func loadHealthWorkoutWriteBacks() async throws -> [HealthWorkoutWriteBackRecord]
    func saveHealthWorkoutWriteBack(_ record: HealthWorkoutWriteBackRecord) async throws
    func loadHealthWorkoutLinkFacts(forLocalEntityID localEntityID: String) async throws
        -> [HealthWorkoutLinkFact]
}

public struct HealthWorkoutWriteBackRepairResult: Codable, Equatable, Sendable {
    public let syncIdentifier: String
    public let retainedHealthKitUUID: String
    public let deletedHealthKitUUIDs: [String]

    public init(
        syncIdentifier: String,
        retainedHealthKitUUID: String,
        deletedHealthKitUUIDs: [String],
    ) {
        self.syncIdentifier = syncIdentifier
        self.retainedHealthKitUUID = retainedHealthKitUUID
        self.deletedHealthKitUUIDs = deletedHealthKitUUIDs
    }
}

public struct HealthWorkoutWriteBackDeletionResult: Codable, Equatable, Sendable {
    public let deletedSyncIdentifiers: [String]
    public let remainingRecords: [HealthWorkoutWriteBackRecord]
    public let failure: HealthWorkoutWriteBackDeletionFailure?

    public init(
        deletedSyncIdentifiers: [String],
        remainingRecords: [HealthWorkoutWriteBackRecord],
        failure: HealthWorkoutWriteBackDeletionFailure? = nil,
    ) {
        self.deletedSyncIdentifiers = deletedSyncIdentifiers
        self.remainingRecords = remainingRecords
        self.failure = failure
    }

    public var isComplete: Bool {
        remainingRecords.isEmpty && failure == nil
    }
}

public extension HealthWorkoutWriteBackRepository {
    func loadHealthWorkoutWriteBacks() async throws -> [HealthWorkoutWriteBackRecord] {
        []
    }

    func saveHealthWorkoutWriteBack(_ record: HealthWorkoutWriteBackRecord) async throws {
        _ = record
        throw HealthWorkoutWriteBackClientError.unavailable
    }

    func loadHealthWorkoutLinkFacts(forLocalEntityID localEntityID: String) async throws
        -> [HealthWorkoutLinkFact]
    {
        _ = localEntityID
        return []
    }
}

public enum SessionWriteBackChoice: Codable, Equatable, Sendable {
    case share
    case doNotShare
}

public struct SessionWriteBackPreview: Codable, Equatable, Sendable {
    public let summary: HealthWorkoutWriteBackSummary
    public let disclosure: String

    public init(summary: HealthWorkoutWriteBackSummary) {
        self.summary = summary
        disclosure =
            "Training Compass will share only a Traditional Strength Training summary with Apple Health: start, end, duration, and a stable sync identifier/version. Sets, loads, prescriptions, Training Maxes, e1RM, notes, and audit history stay local."
    }
}

/// Coordinates the optional delivery state. Local completion is intentionally
/// performed by SessionLoggingBoundary first; every client or persistence
/// failure is represented as write-back state and never thrown to the caller.
public struct HealthWorkoutWriteBackBoundary: Sendable {
    public static let syncIdentifierPrefix = "com.ametel01.trainingcompass.session."

    private let repository: any HealthWorkoutWriteBackRepository
    private let client: any HealthWorkoutWriteBackClient
    private let clock: any Clock
    private let deliveryLane = HealthWorkoutWriteBackDeliveryLane()

    public init(
        repository: any HealthWorkoutWriteBackRepository,
        client: any HealthWorkoutWriteBackClient,
        clock: any Clock,
    ) {
        self.repository = repository
        self.client = client
        self.clock = clock
    }

    public static func syncIdentifier(for sessionID: String) -> String {
        syncIdentifierPrefix + sessionID
    }

    public func preference() async throws -> HealthWorkoutWriteBackPreference {
        try await repository.loadHealthWorkoutWriteBackPreference()
    }

    public func checkWriteAccess() async throws -> HealthAuthorizationSnapshot {
        try await client.checkWriteAuthorization()
    }

    /// Resumes only durable work that was interrupted or classified as
    /// transient. Health access and terminal failures remain idle until the
    /// owner explicitly checks access or taps Try Again.
    @discardableResult
    public func resumePendingWriteBacks() async -> [HealthWorkoutWriteBackRecord] {
        await withDeliveryLane { await resumePendingWriteBacksUnlocked() }
    }

    private func resumePendingWriteBacksUnlocked() async -> [HealthWorkoutWriteBackRecord] {
        do {
            guard try await repository.loadHealthWorkoutWriteBackPreference().enabled else { return [] }
            let records = try await repository.loadHealthWorkoutWriteBacks()
            var recovered: [HealthWorkoutWriteBackRecord] = []
            for record in records where record.state.resumesAutomatically {
                if let result = await save(record) {
                    recovered.append(result)
                }
            }
            return recovered
        } catch {
            return []
        }
    }

    /// The preference is durable before authorization is requested. This makes
    /// an interrupted authorization sheet recoverable without a hidden request.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async throws -> HealthAuthorizationSnapshot? {
        try await repository.saveHealthWorkoutWriteBackPreference(
            .init(enabled: enabled, updatedAt: clock.now()),
        )
        guard enabled else { return nil }
        return try await client.requestWriteAuthorization()
    }

    public func preview(
        session: TodaySessionSnapshot,
        completedAt: Date,
    ) -> SessionWriteBackPreview {
        .init(summary: summary(for: session, completedAt: completedAt))
    }

    public func state(for sessionID: String) async throws -> HealthWorkoutWriteBackRecord? {
        try await repository.loadHealthWorkoutWriteBack(sessionID: sessionID)
    }

    public func records() async throws -> [HealthWorkoutWriteBackRecord] {
        try await repository.loadHealthWorkoutWriteBacks()
    }

    /// Deletes only summaries whose durable write-back record identifies an
    /// external HealthKit object. The adapter rechecks source ownership and the
    /// stable sync identifier before deleting. Successful records are marked
    /// deleted while failed records retain their UUID for a later retry.
    public func deleteAllAppAuthoredSummaries() async -> HealthWorkoutWriteBackDeletionResult {
        await withDeliveryLane {
            guard let records = try? await repository.loadHealthWorkoutWriteBacks() else {
                return .init(
                    deletedSyncIdentifiers: [], remainingRecords: [], failure: .unavailable,
                )
            }

            var deletedSyncIdentifiers: [String] = []
            var remainingRecords: [HealthWorkoutWriteBackRecord] = []
            var failure: HealthWorkoutWriteBackDeletionFailure?
            for record in records where record.state != .notShared && record.state != .deletedFromHealth {
                guard let healthKitUUID = record.healthKitUUID else {
                    // A saved record without a durable UUID may still refer to an
                    // app-authored object found by sync identity. Preserve its local
                    // identity and require an explicit retry rather than erasing it.
                    if record.state == .savedToHealth {
                        remainingRecords.append(record)
                        failure = failure ?? .failed
                    }
                    continue
                }
                do {
                    try await self.client.deleteWorkout(
                        healthKitUUID: healthKitUUID, expectedSyncIdentifier: record.syncIdentifier,
                    )
                    let deleted = HealthWorkoutWriteBackRecord(
                        sessionID: record.sessionID,
                        syncIdentifier: record.syncIdentifier,
                        syncVersion: record.syncVersion,
                        state: .deletedFromHealth,
                        startDate: record.startDate,
                        endDate: record.endDate,
                        healthKitUUID: healthKitUUID,
                        updatedAt: self.clock.now(),
                    )
                    do {
                        try await self.repository.saveHealthWorkoutWriteBack(deleted)
                        deletedSyncIdentifiers.append(record.syncIdentifier)
                    } catch {
                        remainingRecords.append(record)
                        failure = failure ?? .persistenceFailed
                    }
                } catch {
                    remainingRecords.append(record)
                    failure = failure ?? Self.deletionFailure(for: error)
                }
            }
            return .init(
                deletedSyncIdentifiers: deletedSyncIdentifiers,
                remainingRecords: remainingRecords,
                failure: failure,
            )
        }
    }

    /// Records that HealthKit removed an app-authored object without recreating
    /// it.  The local Session and its stable sync identity remain authoritative;
    /// only the delivery state changes.
    @discardableResult
    public func markDeletedFromHealth(healthKitUUID: String) async
        -> HealthWorkoutWriteBackRecord?
    {
        await withDeliveryLane {
            guard let loadedRecords = try? await repository.loadHealthWorkoutWriteBacks(),
                  let current = loadedRecords.first(where: { $0.healthKitUUID == healthKitUUID })
            else { return nil }
            guard current.state != .notShared, current.state != .deletedFromHealth else { return current }
            let deleted = HealthWorkoutWriteBackRecord(
                sessionID: current.sessionID,
                syncIdentifier: current.syncIdentifier,
                syncVersion: current.syncVersion,
                state: .deletedFromHealth,
                startDate: current.startDate,
                endDate: current.endDate,
                healthKitUUID: current.healthKitUUID,
                updatedAt: clock.now(),
            )
            try? await repository.saveHealthWorkoutWriteBack(deleted)
            return deleted
        }
    }

    /// Reconciles HealthKit's current app-authored objects with the durable
    /// delivery ledger.  Exact UUID return is safe to reconnect; a different
    /// UUID carrying the same sync identifier is intentionally left alone until
    /// the owner explicitly restores or repairs it.
    @discardableResult
    public func reconcileImportedWorkouts(_ workouts: [HealthWorkout]) async
        -> [HealthWorkoutWriteBackRecord]
    {
        await withDeliveryLane {
            guard let records = try? await repository.loadHealthWorkoutWriteBacks() else {
                return []
            }
            var reconciled: [HealthWorkoutWriteBackRecord] = []
            for current in records {
                guard
                    let healthKitUUID = current.healthKitUUID,
                    let workout = workouts.first(where: {
                        $0.healthKitUUID == healthKitUUID
                            && $0.isAppAuthored
                            && $0.appAuthoredSyncIdentifier == current.syncIdentifier
                    })
                else { continue }
                let version = max(current.syncVersion, workout.appAuthoredSyncVersion ?? 0)
                guard current.state == .deletedFromHealth || current.syncVersion != version else {
                    continue
                }
                let restored = HealthWorkoutWriteBackRecord(
                    sessionID: current.sessionID,
                    syncIdentifier: current.syncIdentifier,
                    syncVersion: version,
                    state: .savedToHealth,
                    startDate: current.startDate,
                    endDate: current.endDate,
                    healthKitUUID: healthKitUUID,
                    updatedAt: clock.now(),
                )
                try? await repository.saveHealthWorkoutWriteBack(restored)
                reconciled.append(restored)
            }
            return reconciled
        }
    }

    /// Explicitly restores a deleted summary.  Restoration always creates a
    /// fresh HealthKit object with the next version and never runs as part of a
    /// retry, foreground refresh, or ordinary import.
    @discardableResult
    public func restoreToHealth(
        session: TodaySessionSnapshot,
        completedAt: Date,
    ) async -> HealthWorkoutWriteBackRecord? {
        await withDeliveryLane {
            guard
                let completion = session.completion,
                completion.sessionID == session.session.id,
                let current = try? await repository.loadHealthWorkoutWriteBack(
                    sessionID: session.session.id,
                ),
                current.state == .deletedFromHealth
            else { return nil }
            let summary = summary(for: session, completedAt: completedAt)
            let queued = HealthWorkoutWriteBackRecord(
                sessionID: summary.sessionID,
                syncIdentifier: summary.syncIdentifier,
                syncVersion: current.syncVersion + 1,
                state: .queued,
                startDate: summary.startDate,
                endDate: summary.endDate,
                healthKitUUID: nil,
                updatedAt: clock.now(),
            )
            do {
                try await repository.saveHealthWorkoutWriteBack(queued)
                return await save(queued)
            } catch {
                return queued
            }
        }
    }

    /// Short alias for call sites that already use the write-back vocabulary.
    @discardableResult
    public func restore(
        session: TodaySessionSnapshot,
        completedAt: Date,
    ) async -> HealthWorkoutWriteBackRecord? {
        await restoreToHealth(session: session, completedAt: completedAt)
    }

    /// Deletes the current Training Compass-owned object as the first phase of
    /// an explicit replacement with an external Health Workout.  Ownership is
    /// checked by the adapter; a failure leaves this record unchanged so the
    /// owner can retry safely.
    @discardableResult
    public func deleteAppAuthoredSummaryForReplacement(sessionID: String) async throws
        -> HealthWorkoutWriteBackRecord?
    {
        try await withDeliveryLaneThrowing {
            guard
                let current = try await repository.loadHealthWorkoutWriteBack(sessionID: sessionID),
                current.state != .notShared
            else { return nil }
            guard let healthKitUUID = current.healthKitUUID,
                  current.state != .deletedFromHealth
            else {
                let unshared = HealthWorkoutWriteBackRecord(
                    sessionID: current.sessionID,
                    syncIdentifier: current.syncIdentifier,
                    syncVersion: current.syncVersion,
                    state: .notShared,
                    startDate: current.startDate,
                    endDate: current.endDate,
                    updatedAt: clock.now(),
                )
                try await repository.saveHealthWorkoutWriteBack(unshared)
                return unshared
            }
            do {
                try await client.deleteWorkout(healthKitUUID: healthKitUUID)
            } catch {
                throw HealthWorkoutWriteBackReplacementError.deletionFailed
            }
            let unshared = HealthWorkoutWriteBackRecord(
                sessionID: current.sessionID,
                syncIdentifier: current.syncIdentifier,
                syncVersion: current.syncVersion,
                state: .notShared,
                startDate: current.startDate,
                endDate: current.endDate,
                updatedAt: clock.now(),
            )
            try await repository.saveHealthWorkoutWriteBack(unshared)
            return unshared
        }
    }

    /// Marks an existing app-authored summary stale after a local Session is
    /// reopened. The local edit has already committed before this durable state
    /// transition, so a persistence failure cannot roll back the edit.
    @discardableResult
    public func markSessionEditing(sessionID: String) async -> HealthWorkoutWriteBackRecord? {
        await withDeliveryLane {
            guard
                let current = try? await repository.loadHealthWorkoutWriteBack(sessionID: sessionID),
                current.state != .notShared
            else { return nil }
            let pending = HealthWorkoutWriteBackRecord(
                sessionID: current.sessionID,
                syncIdentifier: current.syncIdentifier,
                syncVersion: current.syncVersion,
                state: .updatePending,
                startDate: current.startDate,
                endDate: current.endDate,
                healthKitUUID: current.healthKitUUID,
                updatedAt: clock.now(),
            )
            try? await repository.saveHealthWorkoutWriteBack(pending)
            return pending
        }
    }

    /// Reconciles a completed local Session against its already-shared summary.
    /// Only start/end facts advance the version. Set edits remain local facts and
    /// therefore do not create another HealthKit object.
    @discardableResult
    public func reconcileCompletedSession(
        _ session: TodaySessionSnapshot,
        completedAt: Date,
    ) async -> HealthWorkoutWriteBackRecord? {
        await withDeliveryLane {
            guard let completion = session.completion, completion.sessionID == session.session.id,
                  let current = try? await repository.loadHealthWorkoutWriteBack(
                      sessionID: session.session.id,
                  ),
                  current.state != .notShared
            else { return nil }
            let summary = summary(for: session, completedAt: completedAt)
            let factsChanged =
                current.startDate != summary.startDate || current.endDate != summary.endDate
            if !factsChanged {
                guard current.state == .updatePending else { return current }
                let restored = HealthWorkoutWriteBackRecord(
                    sessionID: current.sessionID,
                    syncIdentifier: current.syncIdentifier,
                    syncVersion: current.syncVersion,
                    state: .savedToHealth,
                    startDate: current.startDate,
                    endDate: current.endDate,
                    healthKitUUID: current.healthKitUUID,
                    updatedAt: clock.now(),
                )
                try? await repository.saveHealthWorkoutWriteBack(restored)
                return restored
            }
            let queued = HealthWorkoutWriteBackRecord(
                sessionID: summary.sessionID,
                syncIdentifier: summary.syncIdentifier,
                syncVersion: current.syncVersion + 1,
                state: .queued,
                startDate: summary.startDate,
                endDate: summary.endDate,
                healthKitUUID: current.healthKitUUID,
                updatedAt: clock.now(),
            )
            do {
                try await repository.saveHealthWorkoutWriteBack(queued)
                return await save(queued)
            } catch {
                // The durable queued record is the source of truth when a client save
                // fails; never surface that failure as a local Session failure.
                return queued
            }
        }
    }

    /// Removes the local relationship without deleting the Health object. The
    /// owner can separately choose an app-owned duplicate repair operation.
    @discardableResult
    public func unlinkSessionSummary(sessionID: String) async -> HealthWorkoutWriteBackRecord? {
        await withDeliveryLane {
            guard
                let current = try? await repository.loadHealthWorkoutWriteBack(sessionID: sessionID),
                current.state != .notShared
            else { return nil }
            let unlinked = HealthWorkoutWriteBackRecord(
                sessionID: current.sessionID,
                syncIdentifier: current.syncIdentifier,
                syncVersion: current.syncVersion,
                state: .notShared,
                startDate: current.startDate,
                endDate: current.endDate,
                updatedAt: clock.now(),
            )
            try? await repository.saveHealthWorkoutWriteBack(unlinked)
            return unlinked
        }
    }

    /// Explicitly deletes only the extra app-authored objects supplied by the
    /// caller. The caller must provide a retained object and the client is
    /// responsible for the final HealthKit ownership check.
    public func repairAppAuthoredConflict(
        syncIdentifier: String,
        retainedHealthKitUUID: String,
        extraHealthKitUUIDs: [String],
        appAuthoredHealthKitUUIDs: Set<String>,
    ) async -> HealthWorkoutWriteBackRepairResult? {
        let extras = Array(Set(extraHealthKitUUIDs)).filter {
            $0 != retainedHealthKitUUID && appAuthoredHealthKitUUIDs.contains($0)
        }.sorted()
        guard
            extras.count == Set(extraHealthKitUUIDs).filter({ $0 != retainedHealthKitUUID }).count
        else {
            return nil
        }
        var deleted: [String] = []
        for uuid in extras {
            do {
                try await client.deleteWorkout(healthKitUUID: uuid)
                deleted.append(uuid)
            } catch {
                return nil
            }
        }
        return .init(
            syncIdentifier: syncIdentifier,
            retainedHealthKitUUID: retainedHealthKitUUID,
            deletedHealthKitUUIDs: deleted,
        )
    }

    /// Convenience repair entry point for a mirror projection. Ownership is
    /// derived from the imported objects rather than trusted from a UUID-only
    /// list, and every candidate must belong to the requested sync identifier.
    public func repairAppAuthoredConflict(
        syncIdentifier: String,
        retainedHealthKitUUID: String,
        extraHealthKitUUIDs: [String],
        appAuthoredWorkouts: [HealthWorkout],
    ) async -> HealthWorkoutWriteBackRepairResult? {
        guard
            appAuthoredWorkouts.allSatisfy({
                $0.isAppAuthored && $0.appAuthoredSyncIdentifier == syncIdentifier
            })
        else { return nil }
        return await repairAppAuthoredConflict(
            syncIdentifier: syncIdentifier,
            retainedHealthKitUUID: retainedHealthKitUUID,
            extraHealthKitUUIDs: extraHealthKitUUIDs,
            appAuthoredHealthKitUUIDs: Set(appAuthoredWorkouts.map(\.healthKitUUID)),
        )
    }

    /// Queues a per-session decision and then attempts delivery. The queue record
    /// is committed before the HealthKit operation, so a locked device or failed
    /// save cannot lose the owner's choice.
    @discardableResult
    public func queue(
        session: TodaySessionSnapshot,
        completedAt: Date,
        choice: SessionWriteBackChoice,
    ) async -> HealthWorkoutWriteBackRecord? {
        await withDeliveryLane {
            await queueUnlocked(session: session, completedAt: completedAt, choice: choice)
        }
    }

    private func queueUnlocked(
        session: TodaySessionSnapshot,
        completedAt: Date,
        choice: SessionWriteBackChoice,
    ) async -> HealthWorkoutWriteBackRecord? {
        guard session.completion != nil else { return nil }
        do {
            let preference = try await repository.loadHealthWorkoutWriteBackPreference()
            let summary = summary(for: session, completedAt: completedAt)
            let existing = try await repository.loadHealthWorkoutWriteBack(sessionID: session.session.id)
            let hasExternalLink = try await repository.loadHealthWorkoutLinkFacts(
                forLocalEntityID: session.session.id,
            ).contains { $0.isActive }
            if choice == .doNotShare || !preference.enabled || hasExternalLink {
                let record = HealthWorkoutWriteBackRecord(
                    sessionID: summary.sessionID, syncIdentifier: summary.syncIdentifier,
                    syncVersion: summary.syncVersion, state: .notShared,
                    startDate: summary.startDate, endDate: summary.endDate,
                    updatedAt: clock.now(),
                )
                try await repository.saveHealthWorkoutWriteBack(record)
                return record
            }
            // A HealthKit deletion is a durable owner choice.  It remains visible
            // until Restore to Health is explicitly selected.
            if existing?.state == .deletedFromHealth {
                return existing
            }
            if existing?.state == .savedToHealth, existing?.syncVersion == summary.syncVersion {
                return existing
            }
            let queued = HealthWorkoutWriteBackRecord(
                sessionID: summary.sessionID, syncIdentifier: summary.syncIdentifier,
                syncVersion: summary.syncVersion, state: .queued,
                startDate: summary.startDate, endDate: summary.endDate,
                healthKitUUID: existing?.healthKitUUID, updatedAt: clock.now(),
            )
            try await repository.saveHealthWorkoutWriteBack(queued)
            return await save(queued)
        } catch {
            return nil
        }
    }

    @discardableResult
    public func retry(sessionID: String) async -> HealthWorkoutWriteBackRecord? {
        await withDeliveryLane { await retryUnlocked(sessionID: sessionID) }
    }

    private func retryUnlocked(sessionID: String) async -> HealthWorkoutWriteBackRecord? {
        do {
            guard let record = try await repository.loadHealthWorkoutWriteBack(sessionID: sessionID),
                  record.state != .notShared
            else { return nil }
            if record.state == .deletedFromHealth {
                return record
            }
            return await save(record)
        } catch { return nil }
    }

    private func save(_ queued: HealthWorkoutWriteBackRecord) async -> HealthWorkoutWriteBackRecord? {
        let saving = HealthWorkoutWriteBackRecord(
            sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
            syncVersion: queued.syncVersion, state: .saving,
            startDate: queued.startDate, endDate: queued.endDate,
            healthKitUUID: queued.healthKitUUID, updatedAt: clock.now(),
        )
        do {
            try await repository.saveHealthWorkoutWriteBack(saving)
            // An existing UUID means this is a replacement version. Reusing the
            // existence shortcut here would incorrectly suppress the newer HealthKit
            // object; the shortcut is only for an interrupted first save where no
            // UUID was durably recorded yet.
            if queued.healthKitUUID == nil, queued.syncVersion == 1,
               try await client.workoutExists(syncIdentifier: queued.syncIdentifier)
            {
                let saved = HealthWorkoutWriteBackRecord(
                    sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
                    syncVersion: queued.syncVersion, state: .savedToHealth,
                    startDate: queued.startDate, endDate: queued.endDate,
                    healthKitUUID: queued.healthKitUUID, updatedAt: clock.now(),
                )
                try await repository.saveHealthWorkoutWriteBack(saved)
                return saved
            }
            let healthKitUUID = try await client.saveWorkout(queued.summary)
            let saved = HealthWorkoutWriteBackRecord(
                sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
                syncVersion: queued.syncVersion, state: .savedToHealth,
                startDate: queued.startDate, endDate: queued.endDate,
                healthKitUUID: healthKitUUID, updatedAt: clock.now(),
            )
            try await repository.saveHealthWorkoutWriteBack(saved)
            return saved
        } catch is CancellationError {
            // Cancellation (background expiry, termination, or an explicit task
            // cancellation) is not a terminal write failure. Leave a durable
            // retryable state so the next launch/foreground opportunity can resume.
            return await persistFailure(queued, state: .retryScheduled, error: nil)
        } catch let error as HealthWorkoutWriteBackClientError {
            switch error {
            case .authorizationDenied, .unavailable:
                return await persistFailure(queued, state: .healthAccessNeeded, error: nil)
            case .inaccessible, .protectedDataUnavailable:
                return await persistFailure(queued, state: .retryScheduled, error: nil)
            }
        } catch {
            return await persistFailure(queued, state: .couldntSave, error: String(describing: error))
        }
    }

    private func persistFailure(
        _ queued: HealthWorkoutWriteBackRecord,
        state: HealthWorkoutWriteBackState,
        error: String?,
    ) async -> HealthWorkoutWriteBackRecord? {
        let failed = HealthWorkoutWriteBackRecord(
            sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
            syncVersion: queued.syncVersion, state: state,
            startDate: queued.startDate, endDate: queued.endDate,
            healthKitUUID: queued.healthKitUUID, lastError: error, updatedAt: clock.now(),
        )
        try? await repository.saveHealthWorkoutWriteBack(failed)
        return failed
    }

    private func summary(for session: TodaySessionSnapshot, completedAt: Date)
        -> HealthWorkoutWriteBackSummary
    {
        let calendar = Calendar(identifier: .gregorian)
        let start =
            calendar.date(
                from: DateComponents(
                    timeZone: TimeZone(secondsFromGMT: 0), year: session.intendedDate.year,
                    month: session.intendedDate.month, day: session.intendedDate.day,
                ),
            ) ?? completedAt
        return .init(
            sessionID: session.session.id,
            syncIdentifier: Self.syncIdentifier(for: session.session.id),
            startDate: min(start, completedAt), endDate: completedAt,
        )
    }

    private static func deletionFailure(for error: any Error)
        -> HealthWorkoutWriteBackDeletionFailure
    {
        switch error as? HealthWorkoutWriteBackClientError {
        case .unavailable: .unavailable
        case .authorizationDenied: .authorizationDenied
        case .protectedDataUnavailable, .inaccessible: .protectedDataUnavailable
        case nil: .failed
        }
    }

    private func withDeliveryLane<T: Sendable>(
        _ operation: @escaping @Sendable () async -> T,
    ) async -> T {
        await deliveryLane.acquire()
        let result = await operation()
        await deliveryLane.release()
        return result
    }

    private func withDeliveryLaneThrowing<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T,
    ) async throws -> T {
        await deliveryLane.acquire()
        do {
            let result = try await operation()
            await deliveryLane.release()
            return result
        } catch {
            await deliveryLane.release()
            throw error
        }
    }
}

private actor HealthWorkoutWriteBackDeliveryLane {
    private var isBusy = false

    func acquire() async {
        while isBusy {
            await Task.yield()
        }
        isBusy = true
    }

    func release() {
        isBusy = false
    }
}
