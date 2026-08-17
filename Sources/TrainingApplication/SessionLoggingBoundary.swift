import Foundation
import TrainingDomain

public enum SetResultAuditAction: String, Codable, Equatable, Sendable {
    case recorded
}

public enum OmittedSetAuditAction: String, Codable, Equatable, Sendable {
    case omitted
}

public enum SessionCompletionConfirmation: Codable, Equatable, Sendable {
    case confirmed
}

public enum SessionReopenConfirmation: Codable, Equatable, Sendable {
    case confirmed
    case cancelled
}

public typealias SessionStatus = TrainingSessionStatus

public struct CompletedSession: Codable, Equatable, Identifiable, Sendable {
    public let sessionID: String
    public let confirmedAt: Int64

    public init(sessionID: String, confirmedAt: Int64) {
        self.sessionID = sessionID
        self.confirmedAt = confirmedAt
    }

    public var id: String {
        sessionID
    }
}

/// The complete current projection of one session. It is the optimistic-concurrency
/// token for a correction and the before/after payload retained in correction history.
public struct SessionCorrectionSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let sessionID: String
    public let status: TrainingSessionStatus
    public let intendedDate: TrainingDate
    public let primaryLiftID: String
    public let assistanceLiftID: String
    public let results: [RecordedSetResult]
    public let omissions: [OmittedSet]
    public let additionalSets: [AdditionalSet]
    public let completion: CompletedSession?
    public let updatedAt: Int64

    public init(
        sessionID: String,
        status: TrainingSessionStatus,
        intendedDate: TrainingDate,
        primaryLiftID: String,
        assistanceLiftID: String,
        results: [RecordedSetResult] = [],
        omissions: [OmittedSet] = [],
        additionalSets: [AdditionalSet] = [],
        completion: CompletedSession? = nil,
        updatedAt: Int64 = 0,
    ) {
        self.sessionID = sessionID
        self.status = status
        self.intendedDate = intendedDate
        self.primaryLiftID = primaryLiftID
        self.assistanceLiftID = assistanceLiftID
        self.results = results
        self.omissions = omissions
        self.additionalSets = additionalSets
        self.completion = completion
        self.updatedAt = updatedAt
    }

    public var id: String {
        sessionID
    }
}

/// A complete replacement for the mutable facts of a session. Prescriptions remain
/// owned by the activated cycle and therefore cannot be supplied here.
public struct SessionCorrectionRequest: Codable, Equatable, Sendable {
    public let sessionID: String
    public let status: TrainingSessionStatus
    public let intendedDate: TrainingDate
    public let primaryLiftID: String
    public let assistanceLiftID: String
    public let results: [RecordedSetResult]
    public let omissions: [OmittedSet]
    public let additionalSets: [AdditionalSet]
    public let completedAt: Int64?
    public let note: String?

    public init(
        sessionID: String,
        status: TrainingSessionStatus,
        intendedDate: TrainingDate,
        primaryLiftID: String,
        assistanceLiftID: String,
        results: [RecordedSetResult] = [],
        omissions: [OmittedSet] = [],
        additionalSets: [AdditionalSet] = [],
        completedAt: Int64? = nil,
        note: String? = nil,
    ) {
        self.sessionID = sessionID
        self.status = status
        self.intendedDate = intendedDate
        self.primaryLiftID = primaryLiftID
        self.assistanceLiftID = assistanceLiftID
        self.results = results
        self.omissions = omissions
        self.additionalSets = additionalSets
        self.completedAt = completedAt
        self.note = note?.isEmpty == true ? nil : note
    }

    public init(snapshot: SessionCorrectionSnapshot, note: String? = nil) {
        self.init(
            sessionID: snapshot.sessionID,
            status: snapshot.status,
            intendedDate: snapshot.intendedDate,
            primaryLiftID: snapshot.primaryLiftID,
            assistanceLiftID: snapshot.assistanceLiftID,
            results: snapshot.results,
            omissions: snapshot.omissions,
            additionalSets: snapshot.additionalSets,
            completedAt: snapshot.completion?.confirmedAt,
            note: note,
        )
    }
}

public struct SessionCorrectionAuditEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let cycleID: String
    public let sessionID: String
    public let occurredAt: Int64
    public let note: String?
    public let before: SessionCorrectionSnapshot
    public let after: SessionCorrectionSnapshot

    public init(
        id: String,
        cycleID: String,
        sessionID: String,
        occurredAt: Int64,
        note: String?,
        before: SessionCorrectionSnapshot,
        after: SessionCorrectionSnapshot,
    ) {
        self.id = id
        self.cycleID = cycleID
        self.sessionID = sessionID
        self.occurredAt = occurredAt
        self.note = note
        self.before = before
        self.after = after
    }
}

public typealias SessionCorrection = SessionCorrectionRequest

public struct SetResultAuditEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let prescriptionID: String
    public let action: SetResultAuditAction
    public let occurredAt: Int64
    public let before: RecordedSetResult?
    public let after: RecordedSetResult

    public init(
        id: String,
        sessionID: String,
        prescriptionID: String,
        action: SetResultAuditAction,
        occurredAt: Int64,
        before: RecordedSetResult?,
        after: RecordedSetResult,
    ) {
        self.id = id
        self.sessionID = sessionID
        self.prescriptionID = prescriptionID
        self.action = action
        self.occurredAt = occurredAt
        self.before = before
        self.after = after
    }
}

public enum SetResultCompletionState: String, Codable, Equatable, Sendable {
    case notRecorded
    case recorded
    case failed
    case omitted
}

public struct TodaySetSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let prescription: TrainingSetPrescription
    public let result: RecordedSetResult?
    public let omission: OmittedSet?
    public let completionState: SetResultCompletionState
    public let hasLoadingIncrementWarning: Bool

    public init(
        prescription: TrainingSetPrescription,
        result: RecordedSetResult?,
        hasLoadingIncrementWarning: Bool,
        omission: OmittedSet? = nil,
    ) {
        self.prescription = prescription
        self.result = result
        self.omission = result == nil ? omission : nil
        if let result {
            completionState = result.repetitions == 0 ? .failed : .recorded
        } else {
            completionState = omission != nil ? .omitted : .notRecorded
        }
        self.hasLoadingIncrementWarning = hasLoadingIncrementWarning
    }

    public var id: String {
        prescription.id
    }

    public var isResolved: Bool {
        result != nil || omission != nil
    }

    public var isFailed: Bool {
        result?.repetitions == 0
    }
}

public enum TodaySessionState: String, Codable, Equatable, Sendable {
    case scheduled
    case inProgress
    case readyToComplete
    case completed
    case skipped
    case unperformed

    public var displayName: String {
        switch self {
        case .scheduled: "Scheduled"
        case .inProgress: "In Progress"
        case .readyToComplete: "Ready to Complete"
        case .completed: "Completed"
        case .skipped: "Skipped"
        case .unperformed: "Unperformed"
        }
    }
}

public struct TodaySessionSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let cycleID: String
    public let weekID: String
    public let weekKind: TrainingWeekKind
    public let intendedDate: TrainingDate
    public let session: TrainingCycleSession
    public let primaryLift: LiftConfigurationSnapshot
    public let assistanceLift: LiftConfigurationSnapshot
    public let sets: [TodaySetSnapshot]
    public let additionalSets: [AdditionalSet]
    public let completion: CompletedSession?

    public init(
        cycleID: String,
        weekID: String,
        weekKind: TrainingWeekKind,
        intendedDate: TrainingDate,
        session: TrainingCycleSession,
        primaryLift: LiftConfigurationSnapshot,
        assistanceLift: LiftConfigurationSnapshot,
        sets: [TodaySetSnapshot],
        additionalSets: [AdditionalSet] = [],
        completion: CompletedSession? = nil,
    ) {
        self.cycleID = cycleID
        self.weekID = weekID
        self.weekKind = weekKind
        self.intendedDate = intendedDate
        self.session = session
        self.primaryLift = primaryLift
        self.assistanceLift = assistanceLift
        self.sets = sets
        self.additionalSets = additionalSets
        self.completion = completion
    }

    public var id: String {
        session.id
    }

    public var state: TodaySessionState {
        if session.status == .skipped {
            return .skipped
        }
        if session.status == .unperformed {
            return .unperformed
        }
        if completion != nil || session.status == .completed {
            return .completed
        }
        if sets.allSatisfy(\.isResolved) {
            return .readyToComplete
        }
        if sets.contains(where: \.isResolved) {
            return .inProgress
        }
        return .scheduled
    }

    public var results: [RecordedSetResult] {
        sets.compactMap(\.result)
    }

    public var omissions: [OmittedSet] {
        sets.compactMap(\.omission)
    }

    public var failedResults: [RecordedSetResult] {
        results.filter(\.result.isFailed)
    }

    public var plannedVersusActual: SessionWorkSummary {
        SessionWorkSummary(
            planned: session.prescriptions,
            performed: results,
            omitted: omissions,
            additional: additionalSets,
        )
    }
}

public struct SessionWorkSummary: Codable, Equatable, Sendable {
    public let planned: [TrainingSetPrescription]
    public let performed: [RecordedSetResult]
    public let omitted: [OmittedSet]
    public let additional: [AdditionalSet]

    public init(
        planned: [TrainingSetPrescription],
        performed: [RecordedSetResult],
        omitted: [OmittedSet],
        additional: [AdditionalSet],
    ) {
        self.planned = planned
        self.performed = performed
        self.omitted = omitted
        self.additional = additional
    }
}

public struct SessionCompletionPreview: Equatable, Sendable {
    public let snapshot: TodaySessionSnapshot
    public let warnings: [String]

    public init(snapshot: TodaySessionSnapshot, warnings: [String] = []) {
        self.snapshot = snapshot
        self.warnings = warnings
    }

    public var requiresWarningAcknowledgement: Bool {
        !warnings.isEmpty
    }

    public var warning: String? {
        warnings.first
    }
}

public protocol SetResultRepository: Sendable {
    func loadSetResults(for sessionID: String) async throws -> [RecordedSetResult]
    func saveSetResult(
        _ result: RecordedSetResult,
        expectedBefore: RecordedSetResult?,
        auditID: String,
        occurredAt: Int64,
        action: SetResultAuditAction,
    ) async throws -> SetResultAuditEntry
    func setResultAuditHistory(for sessionID: String) async throws -> [SetResultAuditEntry]
    func loadOmittedSets(for sessionID: String) async throws -> [OmittedSet]
    func saveOmittedSet(
        _ omission: OmittedSet,
        expectedResult: RecordedSetResult?,
        auditID: String,
        occurredAt: Int64,
        action: OmittedSetAuditAction,
    ) async throws
    func loadAdditionalSets(for sessionID: String) async throws -> [AdditionalSet]
    func saveAdditionalSet(_ set: AdditionalSet) async throws -> AdditionalSet
    func deleteAdditionalSet(sessionID: String, id: String) async throws
    func reorderAdditionalSets(sessionID: String, orderedIDs: [String]) async throws
    func loadCompletedSession(sessionID: String) async throws -> CompletedSession?
    func completeSession(
        _ completion: CompletedSession,
        confirmation: SessionCompletionConfirmation,
    ) async throws -> CompletedSession
    func loadSessionCorrectionSnapshot(sessionID: String) async throws -> SessionCorrectionSnapshot?
    func sessionBelongsToTerminalCycle(sessionID: String) async throws -> Bool
    func applySessionCorrection(
        _ request: SessionCorrectionRequest,
        expectedBefore: SessionCorrectionSnapshot?,
        confirmation: SessionReopenConfirmation,
        auditID: String,
        occurredAt: Int64,
    ) async throws -> SessionCorrectionAuditEntry
    func sessionCorrectionAuditHistory(for sessionID: String) async throws
        -> [SessionCorrectionAuditEntry]
}

public enum SetResultRepositoryError: Error, Equatable, Sendable {
    case unavailable
    case unknownSession
    case unknownPrescription
    case staleResult
    case staleCorrection
    case sessionLocked
    case invalidCorrection
    case terminalCycle
    case confirmationRequired
}

public extension SetResultRepository {
    func loadSetResults(for _: String) async throws -> [RecordedSetResult] {
        []
    }

    func saveSetResult(
        _: RecordedSetResult,
        expectedBefore _: RecordedSetResult?,
        auditID _: String,
        occurredAt _: Int64,
        action _: SetResultAuditAction,
    ) async throws -> SetResultAuditEntry {
        throw SetResultRepositoryError.unavailable
    }

    func setResultAuditHistory(for _: String) async throws -> [SetResultAuditEntry] {
        []
    }

    func loadOmittedSets(for _: String) async throws -> [OmittedSet] {
        []
    }

    func saveOmittedSet(
        _: OmittedSet,
        expectedResult _: RecordedSetResult?,
        auditID _: String,
        occurredAt _: Int64,
        action _: OmittedSetAuditAction,
    ) async throws {
        throw SetResultRepositoryError.unavailable
    }

    func loadAdditionalSets(for _: String) async throws -> [AdditionalSet] {
        []
    }

    func saveAdditionalSet(_: AdditionalSet) async throws -> AdditionalSet {
        throw SetResultRepositoryError.unavailable
    }

    func deleteAdditionalSet(sessionID _: String, id _: String) async throws {
        throw SetResultRepositoryError.unavailable
    }

    func reorderAdditionalSets(sessionID _: String, orderedIDs _: [String]) async throws {
        throw SetResultRepositoryError.unavailable
    }

    func loadCompletedSession(sessionID _: String) async throws -> CompletedSession? {
        nil
    }

    func completeSession(
        _: CompletedSession,
        confirmation _: SessionCompletionConfirmation,
    ) async throws -> CompletedSession {
        throw SetResultRepositoryError.unavailable
    }

    func loadSessionCorrectionSnapshot(sessionID _: String) async throws
        -> SessionCorrectionSnapshot?
    {
        nil
    }

    func sessionBelongsToTerminalCycle(sessionID _: String) async throws -> Bool {
        false
    }

    func applySessionCorrection(
        _: SessionCorrectionRequest,
        expectedBefore _: SessionCorrectionSnapshot?,
        confirmation _: SessionReopenConfirmation,
        auditID _: String,
        occurredAt _: Int64,
    ) async throws -> SessionCorrectionAuditEntry {
        throw SetResultRepositoryError.unavailable
    }

    func sessionCorrectionAuditHistory(for _: String) async throws
        -> [SessionCorrectionAuditEntry]
    {
        []
    }
}

public struct SessionLoggingBoundary: Sendable {
    private let cycleRepository: any TrainingCycleRepository
    private let resultRepository: any SetResultRepository
    private let clock: any Clock
    private let calendar: any CalendarProvider
    private let uuidGenerator: any UUIDGenerator
    private let writeBackBoundary: HealthWorkoutWriteBackBoundary?

    public init(
        cycleRepository: any TrainingCycleRepository,
        resultRepository: any SetResultRepository,
        clock: any Clock,
        calendar: any CalendarProvider,
        uuidGenerator: any UUIDGenerator,
        writeBackBoundary: HealthWorkoutWriteBackBoundary? = nil,
    ) {
        self.cycleRepository = cycleRepository
        self.resultRepository = resultRepository
        self.clock = clock
        self.calendar = calendar
        self.uuidGenerator = uuidGenerator
        self.writeBackBoundary = writeBackBoundary
    }

    public init(
        repository: any TrainingRepository,
        clock: any Clock,
        calendar: any CalendarProvider,
        uuidGenerator: any UUIDGenerator,
        writeBackBoundary: HealthWorkoutWriteBackBoundary?,
    ) {
        self.init(
            cycleRepository: repository,
            resultRepository: repository,
            clock: clock,
            calendar: calendar,
            uuidGenerator: uuidGenerator,
            writeBackBoundary: writeBackBoundary,
        )
    }

    public init(
        repository: any TrainingRepository,
        clock: any Clock,
        calendar: any CalendarProvider,
        uuidGenerator: any UUIDGenerator,
    ) {
        self.init(
            repository: repository,
            clock: clock,
            calendar: calendar,
            uuidGenerator: uuidGenerator,
            writeBackBoundary: nil,
        )
    }

    public init(
        repository: any TrainingRepository,
        clock: any Clock,
        uuidGenerator: any UUIDGenerator,
    ) {
        self.init(
            cycleRepository: repository,
            resultRepository: repository,
            clock: clock,
            calendar: CurrentCalendarProvider(),
            uuidGenerator: uuidGenerator,
            writeBackBoundary: nil,
        )
    }

    public func today() async throws -> TodaySessionSnapshot? {
        try await session(on: TrainingDate(date: clock.now(), calendar: calendar.calendar()))
    }

    public func session(on date: TrainingDate) async throws -> TodaySessionSnapshot? {
        guard let cycle = try await cycleRepository.loadActiveTrainingCycle() else { return nil }
        guard
            let located = cycle.weeks.enumerated().flatMap({ weekIndex, week in
                week.sessions.map { (weekIndex, week, $0) }
            }).first(where: { $0.2.intendedDate == date })
        else {
            return nil
        }
        let (_, week, session) = located
        return try await snapshot(cycle: cycle, week: week, session: session)
    }

    private func snapshot(
        cycle: TrainingCycle,
        week: TrainingWeek,
        session: TrainingCycleSession,
    ) async throws -> TodaySessionSnapshot {
        let results = try await resultRepository.loadSetResults(for: session.id)
        let omissions = try await resultRepository.loadOmittedSets(for: session.id)
        let additionalSets = try await resultRepository.loadAdditionalSets(for: session.id)
        let completion = try await resultRepository.loadCompletedSession(sessionID: session.id)
        let byPrescriptionID = Dictionary(uniqueKeysWithValues: results.map { ($0.prescriptionID, $0) })
        let omissionsByPrescriptionID = Dictionary(
            uniqueKeysWithValues: omissions.map { ($0.prescriptionID, $0) },
        )
        let primaryLift = try liftSnapshot(for: session.primaryLiftID, in: cycle)
        let assistanceLift = try liftSnapshot(for: session.assistanceLiftID, in: cycle)
        let primaryIncrement = try LoadingIncrement(kg: primaryLift.loadingIncrementKg)
        let assistanceIncrement = try LoadingIncrement(kg: assistanceLift.loadingIncrementKg)
        let sets = session.prescriptions.map { prescription in
            let increment = prescription.role == .primary ? primaryIncrement : assistanceIncrement
            let result = byPrescriptionID[prescription.id]
            let warning = result?.result.alignment(to: increment) == .notAligned
            return TodaySetSnapshot(
                prescription: prescription,
                result: result,
                hasLoadingIncrementWarning: warning,
                omission: omissionsByPrescriptionID[prescription.id],
            )
        }
        return TodaySessionSnapshot(
            cycleID: cycle.id,
            weekID: week.id,
            weekKind: week.kind,
            intendedDate: session.intendedDate,
            session: session,
            primaryLift: primaryLift,
            assistanceLift: assistanceLift,
            sets: sets,
            additionalSets: additionalSets,
            completion: completion,
        )
    }

    @discardableResult
    public func recordSetResult(
        sessionID: String,
        prescriptionID: String,
        weightKg: Double,
        repetitions: Int,
        expectedBefore: RecordedSetResult? = nil,
    ) async throws -> SetResultAuditEntry {
        let result = try SetResult(
            weight: SetResultWeight(kg: weightKg),
            repetitions: repetitions,
        )
        let record = RecordedSetResult(
            id: expectedBefore?.id ?? uuidGenerator.makeUUID().uuidString,
            sessionID: sessionID,
            prescriptionID: prescriptionID,
            result: result,
            recordedAt: timestamp(),
        )
        return try await resultRepository.saveSetResult(
            record,
            expectedBefore: expectedBefore,
            auditID: uuidGenerator.makeUUID().uuidString,
            occurredAt: timestamp(),
            action: .recorded,
        )
    }

    /// Imports a session that was completed before Training Compass began
    /// tracking the active cycle. The owner supplies the only variable result
    /// retained by a 5/3/1 spreadsheet—the primary plus-set repetitions—while
    /// unresolved supporting sets are recorded exactly as prescribed.
    @discardableResult
    public func importCompletedSession(
        sessionID: String,
        topSetRepetitions: Int,
    ) async throws -> TodaySessionSnapshot {
        guard let current = try await activeSession(sessionID: sessionID) else {
            throw SessionLoggingError.unknownSession
        }
        guard current.completion == nil, !current.session.status.isTerminal else {
            throw SessionLoggingError.alreadyCompleted
        }
        guard
            let topSet = current.sets.first(where: {
                $0.prescription.role == .primary && $0.prescription.isPlusSetEligible
            })
        else {
            throw SessionLoggingError.missingTopSetPrescription
        }

        for set in current.sets {
            if set.id == topSet.id {
                _ = try await recordSetResult(
                    sessionID: sessionID,
                    prescriptionID: set.id,
                    weightKg: set.prescription.weightKg,
                    repetitions: topSetRepetitions,
                    expectedBefore: set.result,
                )
            } else if !set.isResolved {
                _ = try await recordSetResult(
                    sessionID: sessionID,
                    prescriptionID: set.id,
                    weightKg: set.prescription.weightKg,
                    repetitions: set.prescription.repetitions,
                )
            }
        }

        return try await completeSession(
            sessionID: sessionID,
            confirmation: .confirmed,
            acknowledgeLaterWeek: true,
        )
    }

    @discardableResult
    public func omitSet(
        sessionID: String,
        prescriptionID: String,
        reason: String? = nil,
        expectedBefore: RecordedSetResult? = nil,
    ) async throws -> OmittedSet {
        let current: RecordedSetResult? = if let expectedBefore {
            expectedBefore
        } else {
            try await resultRepository.loadSetResults(for: sessionID)
                .first(where: { $0.prescriptionID == prescriptionID })
        }
        let omission = OmittedSet(
            sessionID: sessionID,
            prescriptionID: prescriptionID,
            reason: reason,
            omittedAt: timestamp(),
        )
        try await resultRepository.saveOmittedSet(
            omission,
            expectedResult: current,
            auditID: uuidGenerator.makeUUID().uuidString,
            occurredAt: timestamp(),
            action: .omitted,
        )
        return omission
    }

    @discardableResult
    public func addAdditionalSet(
        sessionID: String,
        liftID: String,
        weightKg: Double,
        repetitions: Int,
        note: String? = nil,
    ) async throws -> AdditionalSet {
        let existing = try await resultRepository.loadAdditionalSets(for: sessionID)
        let set = try AdditionalSet(
            id: uuidGenerator.makeUUID().uuidString,
            sessionID: sessionID,
            position: existing.count,
            liftID: liftID,
            weightKg: weightKg,
            repetitions: repetitions,
            note: note,
            recordedAt: timestamp(),
        )
        return try await resultRepository.saveAdditionalSet(set)
    }

    public func editAdditionalSet(
        sessionID: String,
        id: String,
        liftID: String,
        weightKg: Double,
        repetitions: Int,
        note: String? = nil,
    ) async throws -> AdditionalSet {
        let existing = try await resultRepository.loadAdditionalSets(for: sessionID)
        guard let current = existing.first(where: { $0.id == id }) else {
            throw SessionLoggingError.unknownAdditionalSet
        }
        let replacement = try AdditionalSet(
            id: current.id,
            sessionID: sessionID,
            position: current.position,
            liftID: liftID,
            weightKg: weightKg,
            repetitions: repetitions,
            note: note,
            recordedAt: timestamp(),
        )
        return try await resultRepository.saveAdditionalSet(replacement)
    }

    public func removeAdditionalSet(sessionID: String, id: String) async throws {
        try await resultRepository.deleteAdditionalSet(sessionID: sessionID, id: id)
    }

    public func reorderAdditionalSets(sessionID: String, orderedIDs: [String]) async throws {
        try await resultRepository.reorderAdditionalSets(sessionID: sessionID, orderedIDs: orderedIDs)
    }

    @discardableResult
    public func completeSession(
        sessionID: String,
        confirmation: SessionCompletionConfirmation,
    ) async throws -> TodaySessionSnapshot {
        try await completeSession(
            sessionID: sessionID,
            confirmation: confirmation,
            acknowledgeLaterWeek: false,
        )
    }

    public func previewCompleteSession(sessionID: String) async throws -> SessionCompletionPreview {
        guard let current = try await activeSession(sessionID: sessionID) else {
            throw SessionLoggingError.unknownSession
        }
        guard current.sets.allSatisfy(\.isResolved) else {
            throw SessionLoggingError.incompleteSession
        }
        guard let cycle = try await cycleRepository.loadActiveTrainingCycle(),
              let week = cycle.weeks.first(where: { $0.id == current.weekID })
        else { throw SessionLoggingError.unknownSession }
        let hasEarlierUnfinishedWeek = cycle.weeks.contains {
            $0.position < week.position && !$0.isFinished
        }
        let warnings =
            hasEarlierUnfinishedWeek
                ? [
                    "An earlier Training Week remains unfinished. Completing this later Session is allowed only after acknowledging the warning.",
                ]
                : []
        return SessionCompletionPreview(snapshot: current, warnings: warnings)
    }

    @discardableResult
    public func completeSession(
        sessionID: String,
        confirmation: SessionCompletionConfirmation,
        acknowledgeLaterWeek: Bool,
    ) async throws -> TodaySessionSnapshot {
        guard let current = try await activeSession(sessionID: sessionID) else {
            throw SessionLoggingError.unknownSession
        }
        guard current.sets.allSatisfy(\.isResolved) else {
            throw SessionLoggingError.incompleteSession
        }
        let preview = try await previewCompleteSession(sessionID: sessionID)
        guard !preview.requiresWarningAcknowledgement || acknowledgeLaterWeek else {
            throw SessionLoggingError.weekSequenceWarningRequired
        }
        guard current.completion == nil else { throw SessionLoggingError.alreadyCompleted }
        let completion = try await resultRepository.completeSession(
            CompletedSession(sessionID: sessionID, confirmedAt: timestamp()),
            confirmation: confirmation,
        )
        guard let snapshot = try await activeSession(sessionID: sessionID) else {
            throw SessionLoggingError.unknownSession
        }
        if let writeBackBoundary, let completion = snapshot.completion {
            _ = await writeBackBoundary.reconcileCompletedSession(
                snapshot,
                completedAt: Date(timeIntervalSince1970: TimeInterval(completion.confirmedAt)),
            )
        }
        _ = completion
        return snapshot
    }

    public func completeSession(
        sessionID: String,
        confirmed: Bool,
    ) async throws -> TodaySessionSnapshot {
        guard confirmed else { throw SessionLoggingError.confirmationRequired }
        return try await completeSession(sessionID: sessionID, confirmation: .confirmed)
    }

    @discardableResult
    public func confirmSession(sessionID: String) async throws -> TodaySessionSnapshot {
        try await completeSession(sessionID: sessionID, confirmation: .confirmed)
    }

    /// Reopens a terminal session after an explicit confirmation. The current
    /// records are retained, while the completion/skipped disposition is removed.
    @discardableResult
    public func reopenSession(
        sessionID: String,
        confirmation: SessionReopenConfirmation,
        note: String? = nil,
    ) async throws -> TodaySessionSnapshot {
        guard confirmation == .confirmed else {
            throw SessionLoggingError.confirmationRequired
        }
        guard try await !resultRepository.sessionBelongsToTerminalCycle(sessionID: sessionID) else {
            throw SetResultRepositoryError.terminalCycle
        }
        guard let current = try await correctionSnapshot(sessionID: sessionID) else {
            throw SessionLoggingError.unknownSession
        }
        guard current.status.isTerminal else {
            throw SessionLoggingError.sessionNotTerminal
        }
        let request = SessionCorrectionRequest(
            sessionID: current.sessionID,
            status: .inProgress,
            intendedDate: current.intendedDate,
            primaryLiftID: current.primaryLiftID,
            assistanceLiftID: current.assistanceLiftID,
            results: current.results,
            omissions: current.omissions,
            additionalSets: current.additionalSets,
            note: note,
        )
        _ = try await resultRepository.applySessionCorrection(
            request,
            expectedBefore: current,
            confirmation: confirmation,
            auditID: uuidGenerator.makeUUID().uuidString,
            occurredAt: timestamp(),
        )
        if let writeBackBoundary {
            _ = await writeBackBoundary.markSessionEditing(sessionID: request.sessionID)
        }
        try await unlinkExternalWorkoutIfNeeded(
            sessionID: request.sessionID, resultingStatus: request.status,
        )
        guard let reopened = try await activeSession(sessionID: request.sessionID) else {
            throw SessionLoggingError.unknownSession
        }
        return reopened
    }

    public func reopen(
        sessionID: String,
        confirmation: SessionReopenConfirmation,
        note: String? = nil,
    ) async throws -> TodaySessionSnapshot {
        try await reopenSession(sessionID: sessionID, confirmation: confirmation, note: note)
    }

    /// Atomically replaces the mutable facts of a session and records one
    /// before/after correction audit entry. The activated prescriptions remain
    /// outside the request and cannot be structurally rewritten.
    @discardableResult
    public func correctSession(
        _ request: SessionCorrectionRequest,
        confirmation: SessionReopenConfirmation,
        expectedBefore: SessionCorrectionSnapshot? = nil,
    ) async throws -> SessionCorrectionAuditEntry {
        guard confirmation == .confirmed else {
            throw SessionLoggingError.confirmationRequired
        }
        guard try await !resultRepository.sessionBelongsToTerminalCycle(sessionID: request.sessionID)
        else {
            throw SetResultRepositoryError.terminalCycle
        }
        guard try await activeSession(sessionID: request.sessionID) != nil else {
            if let terminal = try await resultRepository.loadSessionCorrectionSnapshot(
                sessionID: request.sessionID,
            ), terminal.status.isTerminal {
                throw SetResultRepositoryError.terminalCycle
            }
            throw SessionLoggingError.unknownSession
        }
        let current: SessionCorrectionSnapshot? = if let expectedBefore {
            expectedBefore
        } else {
            try await correctionSnapshot(sessionID: request.sessionID)
        }
        let audit = try await resultRepository.applySessionCorrection(
            request,
            expectedBefore: current,
            confirmation: confirmation,
            auditID: uuidGenerator.makeUUID().uuidString,
            occurredAt: timestamp(),
        )
        if let writeBackBoundary {
            if request.status == .completed, let completedAt = request.completedAt,
               let snapshot = try? await activeSession(sessionID: request.sessionID)
            {
                _ = await writeBackBoundary.reconcileCompletedSession(
                    snapshot, completedAt: Date(timeIntervalSince1970: TimeInterval(completedAt)),
                )
            } else if request.status == .scheduled || request.status == .skipped
                || request.status == .unperformed
            {
                _ = await writeBackBoundary.unlinkSessionSummary(sessionID: request.sessionID)
            }
        }
        try await unlinkExternalWorkoutIfNeeded(
            sessionID: request.sessionID, resultingStatus: request.status,
        )
        return audit
    }

    @discardableResult
    public func correct(
        _ request: SessionCorrectionRequest,
        confirmation: SessionReopenConfirmation,
        expectedBefore: SessionCorrectionSnapshot? = nil,
    ) async throws -> SessionCorrectionAuditEntry {
        try await correctSession(
            request, confirmation: confirmation, expectedBefore: expectedBefore,
        )
    }

    @discardableResult
    public func skipSession(
        sessionID: String,
        confirmation: SessionReopenConfirmation,
        note: String? = nil,
    ) async throws -> TodaySessionSnapshot {
        guard confirmation == .confirmed else {
            throw SessionLoggingError.confirmationRequired
        }
        guard let cycle = try await cycleRepository.loadActiveTrainingCycle(),
              let located = cycle.weeks.enumerated().first(where: {
                  $0.element.sessions.contains(where: { $0.id == sessionID })
              })
        else {
            throw SessionLoggingError.unknownSession
        }
        let weekIndex = located.offset
        guard
            let sessionIndex = cycle.weeks[weekIndex].sessions.firstIndex(where: {
                $0.id == sessionID
            })
        else { throw SessionLoggingError.unknownSession }
        let current = cycle.weeks[weekIndex].sessions[sessionIndex]
        guard current.status == .scheduled || current.status == .inProgress else {
            throw SessionLoggingError.sessionNotTerminal
        }
        if current.status == .inProgress {
            guard let snapshot = try await correctionSnapshot(sessionID: sessionID) else {
                throw SessionLoggingError.unknownSession
            }
            let request = SessionCorrectionRequest(
                sessionID: sessionID,
                status: .skipped,
                intendedDate: snapshot.intendedDate,
                primaryLiftID: snapshot.primaryLiftID,
                assistanceLiftID: snapshot.assistanceLiftID,
                note: note,
            )
            _ = try await correctSession(
                request, confirmation: confirmation, expectedBefore: snapshot,
            )
            guard let skipped = try await activeSession(sessionID: sessionID) else {
                throw SessionLoggingError.unknownSession
            }
            return skipped
        }
        let replacementSession = TrainingCycleSession(
            id: current.id,
            intendedDate: current.intendedDate,
            sourceTemplateSessionID: current.sourceTemplateSessionID,
            primaryLiftID: current.primaryLiftID,
            assistanceLiftID: current.assistanceLiftID,
            prescriptions: current.prescriptions,
            status: .skipped,
        )
        var weeks = cycle.weeks
        var sessions = weeks[weekIndex].sessions
        sessions[sessionIndex] = replacementSession
        weeks[weekIndex] = TrainingWeek(
            id: weeks[weekIndex].id,
            position: weeks[weekIndex].position,
            kind: weeks[weekIndex].kind,
            startDate: weeks[weekIndex].startDate,
            sessions: sessions,
        )
        let replacement = TrainingCycle(
            id: cycle.id,
            week1AnchorDate: cycle.week1AnchorDate,
            weeks: weeks,
            sourceTemplate: cycle.sourceTemplate,
            includesProvisionalDeload: cycle.includesProvisionalDeload,
            lifecycleState: cycle.lifecycleState,
            createdAt: cycle.createdAt,
            updatedAt: timestamp(),
            liftSnapshots: cycle.liftSnapshots,
        )
        _ = try await cycleRepository.saveTrainingCycle(
            replacement,
            expectedBefore: cycle.snapshot,
            auditID: uuidGenerator.makeUUID().uuidString,
            occurredAt: timestamp(),
            action: .sessionSkipped,
            note: note,
            targetID: nil,
        )
        guard let skipped = try await activeSession(sessionID: sessionID) else {
            throw SessionLoggingError.unknownSession
        }
        return skipped
    }

    public func skip(
        sessionID: String,
        confirmation: SessionReopenConfirmation,
        note: String? = nil,
    ) async throws -> TodaySessionSnapshot {
        try await skipSession(sessionID: sessionID, confirmation: confirmation, note: note)
    }

    /// Skips each remaining Scheduled Session in a Training Week. The owner
    /// confirms once, while the repository receives one audited mutation per
    /// Session. There is intentionally no cycle-wide bulk skip operation.
    @discardableResult
    public func skipRemainingSessions(
        in weekID: String,
        confirmation: SessionReopenConfirmation,
        note: String? = nil,
    ) async throws -> [TodaySessionSnapshot] {
        guard confirmation == .confirmed else {
            throw SessionLoggingError.confirmationRequired
        }
        guard var cycle = try await cycleRepository.loadActiveTrainingCycle(),
              let weekIndex = cycle.weeks.firstIndex(where: { $0.id == weekID })
        else { throw SessionLoggingError.unknownSession }
        let scheduled = cycle.weeks[weekIndex].sessions.filter { $0.status == .scheduled }
        guard !scheduled.isEmpty else { throw SessionLoggingError.sessionNotTerminal }
        for session in scheduled {
            let week = cycle.weeks[weekIndex]
            let sessions = week.sessions.map { current in
                guard current.id == session.id else { return current }
                return TrainingCycleSession(
                    id: current.id,
                    intendedDate: current.intendedDate,
                    sourceTemplateSessionID: current.sourceTemplateSessionID,
                    primaryLiftID: current.primaryLiftID,
                    assistanceLiftID: current.assistanceLiftID,
                    prescriptions: current.prescriptions,
                    status: .skipped,
                )
            }
            var weeks = cycle.weeks
            weeks[weekIndex] = TrainingWeek(
                id: week.id,
                position: week.position,
                kind: week.kind,
                startDate: week.startDate,
                sessions: sessions,
            )
            let replacement = TrainingCycle(
                id: cycle.id,
                week1AnchorDate: cycle.week1AnchorDate,
                weeks: weeks,
                sourceTemplate: cycle.sourceTemplate,
                includesProvisionalDeload: cycle.includesProvisionalDeload,
                lifecycleState: cycle.lifecycleState,
                createdAt: cycle.createdAt,
                updatedAt: timestamp(),
                liftSnapshots: cycle.liftSnapshots,
            )
            _ = try await cycleRepository.saveTrainingCycle(
                replacement,
                expectedBefore: cycle.snapshot,
                auditID: uuidGenerator.makeUUID().uuidString,
                occurredAt: timestamp(),
                action: .sessionSkipped,
                note: note,
                targetID: nil,
            )
            cycle = replacement
        }
        var snapshots: [TodaySessionSnapshot] = []
        for scheduledSession in scheduled {
            if let snapshot = try await activeSession(sessionID: scheduledSession.id) {
                snapshots.append(snapshot)
            }
        }
        return snapshots
    }

    public func skipWeek(
        weekID: String,
        confirmation: SessionReopenConfirmation,
        note: String? = nil,
    ) async throws -> [TodaySessionSnapshot] {
        try await skipRemainingSessions(in: weekID, confirmation: confirmation, note: note)
    }

    public func correctionSnapshot(sessionID: String) async throws
        -> SessionCorrectionSnapshot?
    {
        if let snapshot = try await resultRepository.loadSessionCorrectionSnapshot(sessionID: sessionID) {
            return snapshot
        }
        guard let current = try await activeSession(sessionID: sessionID) else { return nil }
        return SessionCorrectionSnapshot(
            sessionID: current.id,
            status: current.session.status,
            intendedDate: current.intendedDate,
            primaryLiftID: current.session.primaryLiftID,
            assistanceLiftID: current.session.assistanceLiftID,
            results: current.results,
            omissions: current.omissions,
            additionalSets: current.additionalSets,
            completion: current.completion,
        )
    }

    public func correctionAuditHistory(for sessionID: String) async throws
        -> [SessionCorrectionAuditEntry]
    {
        try await resultRepository.sessionCorrectionAuditHistory(for: sessionID)
    }

    public func auditHistory(for sessionID: String) async throws -> [SetResultAuditEntry] {
        try await resultRepository.setResultAuditHistory(for: sessionID)
    }

    private func liftSnapshot(for id: String, in cycle: TrainingCycle) throws
        -> LiftConfigurationSnapshot
    {
        guard let snapshot = cycle.liftSnapshots[id] else {
            throw SetResultRepositoryError.unknownPrescription
        }
        return snapshot
    }

    private func activeSession(sessionID: String) async throws -> TodaySessionSnapshot? {
        guard let cycle = try await cycleRepository.loadActiveTrainingCycle(),
              let located = cycle.weeks.enumerated().flatMap({ weekIndex, week in
                  week.sessions.map { (weekIndex, week, $0) }
              }).first(where: { $0.2.id == sessionID })
        else { return nil }
        return try await snapshot(cycle: cycle, week: located.1, session: located.2)
    }

    private func timestamp() -> Int64 {
        Int64(clock.now().timeIntervalSince1970)
    }

    private func unlinkExternalWorkoutIfNeeded(
        sessionID: String,
        resultingStatus: TrainingSessionStatus,
    ) async throws {
        guard
            resultingStatus == .scheduled || resultingStatus == .skipped
            || resultingStatus == .unperformed,
            let linkRepository = resultRepository as? any TrainingEventLinkRepository
        else { return }
        _ = try await linkRepository.unlinkActiveHealthWorkoutLinkFacts(
            forLocalEntityID: sessionID,
            unlinkedAt: clock.now(),
        )
    }
}

public enum SessionLoggingError: Error, Equatable, Sendable {
    case unknownSession
    case incompleteSession
    case confirmationRequired
    case alreadyCompleted
    case unknownAdditionalSet
    case sessionNotTerminal
    case weekSequenceWarningRequired
    case missingTopSetPrescription
}

/// Convenience boundary for callers that do not need the ordinary Today
/// logging operations. It shares the same repository and concurrency seams.
public typealias SessionCorrectionBoundary = SessionLoggingBoundary
