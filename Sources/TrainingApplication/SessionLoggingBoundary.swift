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

public struct CompletedSession: Codable, Equatable, Identifiable, Sendable {
  public let sessionID: String
  public let confirmedAt: Int64

  public init(sessionID: String, confirmedAt: Int64) {
    self.sessionID = sessionID
    self.confirmedAt = confirmedAt
  }

  public var id: String { sessionID }
}

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
    after: RecordedSetResult
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
    omission: OmittedSet? = nil
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

  public var id: String { prescription.id }

  public var isResolved: Bool { result != nil || omission != nil }

  public var isFailed: Bool { result?.repetitions == 0 }
}

public enum TodaySessionState: String, Codable, Equatable, Sendable {
  case scheduled
  case inProgress
  case readyToComplete
  case completed

  public var displayName: String {
    switch self {
    case .scheduled: "Scheduled"
    case .inProgress: "In Progress"
    case .readyToComplete: "Ready to Complete"
    case .completed: "Completed"
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
    completion: CompletedSession? = nil
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

  public var id: String { session.id }
  public var state: TodaySessionState {
    if completion != nil { return .completed }
    if sets.allSatisfy(\.isResolved) { return .readyToComplete }
    if sets.contains(where: { $0.isResolved }) { return .inProgress }
    return .scheduled
  }

  public var results: [RecordedSetResult] {
    sets.compactMap(\.result)
  }

  public var omissions: [OmittedSet] { sets.compactMap(\.omission) }

  public var failedResults: [RecordedSetResult] { results.filter(\.result.isFailed) }

  public var plannedVersusActual: SessionWorkSummary {
    SessionWorkSummary(
      planned: session.prescriptions,
      performed: results,
      omitted: omissions,
      additional: additionalSets
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
    additional: [AdditionalSet]
  ) {
    self.planned = planned
    self.performed = performed
    self.omitted = omitted
    self.additional = additional
  }
}

public protocol SetResultRepository: Sendable {
  func loadSetResults(for sessionID: String) async throws -> [RecordedSetResult]
  func saveSetResult(
    _ result: RecordedSetResult,
    expectedBefore: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: SetResultAuditAction
  ) async throws -> SetResultAuditEntry
  func setResultAuditHistory(for sessionID: String) async throws -> [SetResultAuditEntry]
  func loadOmittedSets(for sessionID: String) async throws -> [OmittedSet]
  func saveOmittedSet(
    _ omission: OmittedSet,
    expectedResult: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: OmittedSetAuditAction
  ) async throws
  func loadAdditionalSets(for sessionID: String) async throws -> [AdditionalSet]
  func saveAdditionalSet(_ set: AdditionalSet) async throws -> AdditionalSet
  func deleteAdditionalSet(sessionID: String, id: String) async throws
  func reorderAdditionalSets(sessionID: String, orderedIDs: [String]) async throws
  func loadCompletedSession(sessionID: String) async throws -> CompletedSession?
  func completeSession(
    _ completion: CompletedSession,
    confirmation: SessionCompletionConfirmation
  ) async throws -> CompletedSession
}

public enum SetResultRepositoryError: Error, Equatable, Sendable {
  case unavailable
  case unknownSession
  case unknownPrescription
  case staleResult
}

extension SetResultRepository {
  public func loadSetResults(for sessionID: String) async throws -> [RecordedSetResult] { [] }

  public func saveSetResult(
    _ result: RecordedSetResult,
    expectedBefore: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: SetResultAuditAction
  ) async throws -> SetResultAuditEntry {
    throw SetResultRepositoryError.unavailable
  }

  public func setResultAuditHistory(for sessionID: String) async throws -> [SetResultAuditEntry] {
    []
  }

  public func loadOmittedSets(for sessionID: String) async throws -> [OmittedSet] { [] }

  public func saveOmittedSet(
    _ omission: OmittedSet,
    expectedResult: RecordedSetResult?,
    auditID: String,
    occurredAt: Int64,
    action: OmittedSetAuditAction
  ) async throws {
    throw SetResultRepositoryError.unavailable
  }

  public func loadAdditionalSets(for sessionID: String) async throws -> [AdditionalSet] { [] }

  public func saveAdditionalSet(_ set: AdditionalSet) async throws -> AdditionalSet {
    throw SetResultRepositoryError.unavailable
  }

  public func deleteAdditionalSet(sessionID: String, id: String) async throws {
    throw SetResultRepositoryError.unavailable
  }

  public func reorderAdditionalSets(sessionID: String, orderedIDs: [String]) async throws {
    throw SetResultRepositoryError.unavailable
  }

  public func loadCompletedSession(sessionID: String) async throws -> CompletedSession? { nil }

  public func completeSession(
    _ completion: CompletedSession,
    confirmation: SessionCompletionConfirmation
  ) async throws -> CompletedSession {
    throw SetResultRepositoryError.unavailable
  }
}

public struct SessionLoggingBoundary: Sendable {
  private let cycleRepository: any TrainingCycleRepository
  private let resultRepository: any SetResultRepository
  private let clock: any Clock
  private let calendar: any CalendarProvider
  private let uuidGenerator: any UUIDGenerator

  public init(
    cycleRepository: any TrainingCycleRepository,
    resultRepository: any SetResultRepository,
    clock: any Clock,
    calendar: any CalendarProvider,
    uuidGenerator: any UUIDGenerator
  ) {
    self.cycleRepository = cycleRepository
    self.resultRepository = resultRepository
    self.clock = clock
    self.calendar = calendar
    self.uuidGenerator = uuidGenerator
  }

  public init(
    repository: any TrainingRepository,
    clock: any Clock,
    calendar: any CalendarProvider,
    uuidGenerator: any UUIDGenerator
  ) {
    self.init(
      cycleRepository: repository,
      resultRepository: repository,
      clock: clock,
      calendar: calendar,
      uuidGenerator: uuidGenerator
    )
  }

  public init(
    repository: any TrainingRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator
  ) {
    self.init(
      repository: repository,
      clock: clock,
      calendar: CurrentCalendarProvider(),
      uuidGenerator: uuidGenerator
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
    let results = try await resultRepository.loadSetResults(for: session.id)
    let omissions = try await resultRepository.loadOmittedSets(for: session.id)
    let additionalSets = try await resultRepository.loadAdditionalSets(for: session.id)
    let completion = try await resultRepository.loadCompletedSession(sessionID: session.id)
    let byPrescriptionID = Dictionary(uniqueKeysWithValues: results.map { ($0.prescriptionID, $0) })
    let omissionsByPrescriptionID = Dictionary(
      uniqueKeysWithValues: omissions.map { ($0.prescriptionID, $0) })
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
        omission: omissionsByPrescriptionID[prescription.id]
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
      completion: completion
    )
  }

  @discardableResult
  public func recordSetResult(
    sessionID: String,
    prescriptionID: String,
    weightKg: Double,
    repetitions: Int,
    expectedBefore: RecordedSetResult? = nil
  ) async throws -> SetResultAuditEntry {
    let result = try SetResult(
      weight: SetResultWeight(kg: weightKg),
      repetitions: repetitions
    )
    let record = RecordedSetResult(
      id: expectedBefore?.id ?? uuidGenerator.makeUUID().uuidString,
      sessionID: sessionID,
      prescriptionID: prescriptionID,
      result: result,
      recordedAt: timestamp()
    )
    return try await resultRepository.saveSetResult(
      record,
      expectedBefore: expectedBefore,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .recorded
    )
  }

  @discardableResult
  public func omitSet(
    sessionID: String,
    prescriptionID: String,
    reason: String? = nil,
    expectedBefore: RecordedSetResult? = nil
  ) async throws -> OmittedSet {
    let current: RecordedSetResult?
    if let expectedBefore {
      current = expectedBefore
    } else {
      current = try await resultRepository.loadSetResults(for: sessionID)
        .first(where: { $0.prescriptionID == prescriptionID })
    }
    let omission = OmittedSet(
      sessionID: sessionID,
      prescriptionID: prescriptionID,
      reason: reason,
      omittedAt: timestamp()
    )
    try await resultRepository.saveOmittedSet(
      omission,
      expectedResult: current,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .omitted
    )
    return omission
  }

  @discardableResult
  public func addAdditionalSet(
    sessionID: String,
    liftID: String,
    weightKg: Double,
    repetitions: Int,
    note: String? = nil
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
      recordedAt: timestamp()
    )
    return try await resultRepository.saveAdditionalSet(set)
  }

  public func editAdditionalSet(
    sessionID: String,
    id: String,
    liftID: String,
    weightKg: Double,
    repetitions: Int,
    note: String? = nil
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
      recordedAt: timestamp()
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
    confirmation: SessionCompletionConfirmation
  ) async throws -> TodaySessionSnapshot {
    guard let current = try await activeSession(sessionID: sessionID) else {
      throw SessionLoggingError.unknownSession
    }
    guard current.sets.allSatisfy(\.isResolved) else {
      throw SessionLoggingError.incompleteSession
    }
    guard current.completion == nil else { throw SessionLoggingError.alreadyCompleted }
    let completion = try await resultRepository.completeSession(
      CompletedSession(sessionID: sessionID, confirmedAt: timestamp()),
      confirmation: confirmation
    )
    guard let snapshot = try await session(on: current.intendedDate) else {
      throw SessionLoggingError.unknownSession
    }
    _ = completion
    return snapshot
  }

  public func completeSession(
    sessionID: String,
    confirmed: Bool
  ) async throws -> TodaySessionSnapshot {
    guard confirmed else { throw SessionLoggingError.confirmationRequired }
    return try await completeSession(sessionID: sessionID, confirmation: .confirmed)
  }

  @discardableResult
  public func confirmSession(sessionID: String) async throws -> TodaySessionSnapshot {
    try await completeSession(sessionID: sessionID, confirmation: .confirmed)
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
      let currentSession = cycle.weeks.flatMap(\.sessions).first(where: { $0.id == sessionID })
    else { return nil }
    return try await session(on: currentSession.intendedDate)
  }

  private func timestamp() -> Int64 {
    Int64(clock.now().timeIntervalSince1970)
  }
}

public enum SessionLoggingError: Error, Equatable, Sendable {
  case unknownSession
  case incompleteSession
  case confirmationRequired
  case alreadyCompleted
  case unknownAdditionalSet
}
