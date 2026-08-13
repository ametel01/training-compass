import Foundation
import TrainingDomain

public enum SetResultAuditAction: String, Codable, Equatable, Sendable {
  case recorded
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
}

public struct TodaySetSnapshot: Codable, Equatable, Sendable, Identifiable {
  public let prescription: TrainingSetPrescription
  public let result: RecordedSetResult?
  public let completionState: SetResultCompletionState
  public let hasLoadingIncrementWarning: Bool

  public init(
    prescription: TrainingSetPrescription,
    result: RecordedSetResult?,
    hasLoadingIncrementWarning: Bool
  ) {
    self.prescription = prescription
    self.result = result
    completionState = result == nil ? .notRecorded : .recorded
    self.hasLoadingIncrementWarning = hasLoadingIncrementWarning
  }

  public var id: String { prescription.id }
}

public enum TodaySessionState: String, Codable, Equatable, Sendable {
  case scheduled
  case inProgress
  case readyToComplete

  public var displayName: String {
    switch self {
    case .scheduled: "Scheduled"
    case .inProgress: "In Progress"
    case .readyToComplete: "Ready to Complete"
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

  public init(
    cycleID: String,
    weekID: String,
    weekKind: TrainingWeekKind,
    intendedDate: TrainingDate,
    session: TrainingCycleSession,
    primaryLift: LiftConfigurationSnapshot,
    assistanceLift: LiftConfigurationSnapshot,
    sets: [TodaySetSnapshot]
  ) {
    self.cycleID = cycleID
    self.weekID = weekID
    self.weekKind = weekKind
    self.intendedDate = intendedDate
    self.session = session
    self.primaryLift = primaryLift
    self.assistanceLift = assistanceLift
    self.sets = sets
  }

  public var id: String { session.id }
  public var state: TodaySessionState {
    if sets.allSatisfy({ $0.result != nil }) { return .readyToComplete }
    if sets.contains(where: { $0.result != nil }) { return .inProgress }
    return .scheduled
  }

  public var results: [RecordedSetResult] {
    sets.compactMap(\.result)
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
    let byPrescriptionID = Dictionary(uniqueKeysWithValues: results.map { ($0.prescriptionID, $0) })
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
        hasLoadingIncrementWarning: warning
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
      sets: sets
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

  private func timestamp() -> Int64 {
    Int64(clock.now().timeIntervalSince1970)
  }
}
