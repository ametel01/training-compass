import Foundation
import TrainingDomain

public struct TrainingCycleSessionRequest: Equatable, Sendable {
  public let id: String
  public let intendedDate: TrainingDate
  public let primaryLiftID: String
  public let assistanceLiftID: String

  public init(
    id: String,
    intendedDate: TrainingDate,
    primaryLiftID: String,
    assistanceLiftID: String
  ) {
    self.id = id
    self.intendedDate = intendedDate
    self.primaryLiftID = primaryLiftID
    self.assistanceLiftID = assistanceLiftID
  }
}

extension TrainingCycle {
  fileprivate func location(ofSession sessionID: String) -> (weekIndex: Int, sessionIndex: Int)? {
    for (weekIndex, week) in weeks.enumerated() {
      if let sessionIndex = week.sessions.firstIndex(where: { $0.id == sessionID }) {
        return (weekIndex, sessionIndex)
      }
    }
    return nil
  }
}

extension TrainingWeek {
  fileprivate func contains(_ date: TrainingDate) -> Bool {
    date >= startDate && date <= startDate.adding(days: 6)
  }
}

public struct TrainingWeekRequest: Equatable, Sendable {
  public let id: String
  public let position: Int
  public let kind: TrainingWeekKind
  public let startDate: TrainingDate
  public let sessions: [TrainingCycleSessionRequest]

  public init(
    id: String,
    position: Int,
    kind: TrainingWeekKind,
    startDate: TrainingDate,
    sessions: [TrainingCycleSessionRequest]
  ) {
    self.id = id
    self.position = position
    self.kind = kind
    self.startDate = startDate
    self.sessions = sessions
  }
}

public struct TrainingCycleEditRequest: Equatable, Sendable {
  public let id: String
  public let week1AnchorDate: TrainingDate
  public let weeks: [TrainingWeekRequest]

  public init(id: String, week1AnchorDate: TrainingDate, weeks: [TrainingWeekRequest]) {
    self.id = id
    self.week1AnchorDate = week1AnchorDate
    self.weeks = weeks
  }

  public init(cycle: TrainingCycle) {
    self.init(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: cycle.weeks.map { week in
        TrainingWeekRequest(
          id: week.id,
          position: week.position,
          kind: week.kind,
          startDate: week.startDate,
          sessions: week.sessions.map { session in
            TrainingCycleSessionRequest(
              id: session.id,
              intendedDate: session.intendedDate,
              primaryLiftID: session.primaryLiftID,
              assistanceLiftID: session.assistanceLiftID
            )
          }
        )
      }
    )
  }
}

public enum TrainingCycleAuditAction: String, Codable, Equatable, Sendable {
  case created
  case edited
  case calendarChanged
  case programEdited
  case savedWeekToTemplate
  case replacedSchedule
  case regenerated
  case discarded
  case activated
  case sessionSkipped
  case weekFinished
  case completed
  case abandoned

  public var changeKind: TrainingCycleChangeKind {
    switch self {
    case .calendarChanged: .calendarChange
    case .programEdited: .programEdit
    default: .other
    }
  }
}

public enum TrainingCycleChangeKind: String, Codable, Equatable, Sendable {
  case calendarChange
  case programEdit
  case other
}

public enum TrainingCycleActivationAnchorChoice: Equatable, Sendable {
  case retain
  case replace(TrainingDate)
}

public struct TrainingCycleActivationPreview: Equatable, Sendable {
  public let before: TrainingCycleSnapshot
  public let after: TrainingCycle
  public let activeBefore: TrainingCycleSnapshot?
  public let anchorChoice: TrainingCycleActivationAnchorChoice?
  public let cadenceChangesDeload: Bool
  public let deloadRemovalWarning: Bool

  public init(
    before: TrainingCycleSnapshot,
    after: TrainingCycle,
    activeBefore: TrainingCycleSnapshot?,
    anchorChoice: TrainingCycleActivationAnchorChoice?,
    cadenceChangesDeload: Bool,
    deloadRemovalWarning: Bool
  ) {
    self.before = before
    self.after = after
    self.activeBefore = activeBefore
    self.anchorChoice = anchorChoice
    self.cadenceChangesDeload = cadenceChangesDeload
    self.deloadRemovalWarning = deloadRemovalWarning
  }

  public var requiresDeloadConfirmation: Bool { cadenceChangesDeload }
  public var removesCustomizedDeload: Bool { deloadRemovalWarning }
  public var warning: String? {
    deloadRemovalWarning
      ? "This activation removes customized Deload work. Review and confirm before continuing."
      : nil
  }
}

public struct TrainingCycleAuditEntry: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let cycleID: String
  public let action: TrainingCycleAuditAction
  public let occurredAt: Int64
  public let before: TrainingCycleSnapshot?
  public let after: TrainingCycleSnapshot?
  public let note: String?
  public let targetID: String?

  public init(
    id: String,
    cycleID: String,
    action: TrainingCycleAuditAction,
    occurredAt: Int64,
    before: TrainingCycleSnapshot?,
    after: TrainingCycleSnapshot?,
    note: String? = nil,
    targetID: String? = nil
  ) {
    self.id = id
    self.cycleID = cycleID
    self.action = action
    self.occurredAt = occurredAt
    self.before = before
    self.after = after
    self.note = note?.isEmpty == true ? nil : note
    self.targetID = targetID?.isEmpty == true ? nil : targetID
  }

  public var changeKind: TrainingCycleChangeKind {
    action.changeKind
  }
}

public enum TrainingCycleLifecycleConfirmation: Codable, Equatable, Sendable {
  case confirmed
  case cancelled
}

public struct TrainingWeekFinishPreview: Equatable, Sendable {
  public let cycleID: String
  public let week: TrainingWeek
  public let warnings: [String]

  public init(cycleID: String, week: TrainingWeek, warnings: [String] = []) {
    self.cycleID = cycleID
    self.week = week
    self.warnings = warnings
  }

  public var requiresWarningAcknowledgement: Bool { !warnings.isEmpty }
  public var warning: String? { warnings.first }
}

public struct TrainingWeekSkipPreview: Equatable, Sendable {
  public let before: TrainingCycleSnapshot
  public let after: TrainingCycle
  public let sessions: [TrainingCycleSession]
  public let note: String?

  public init(
    before: TrainingCycleSnapshot,
    after: TrainingCycle,
    sessions: [TrainingCycleSession],
    note: String? = nil
  ) {
    self.before = before
    self.after = after
    self.sessions = sessions
    self.note = note?.isEmpty == true ? nil : note
  }

  public var skippedCount: Int { sessions.count }
}

public struct TrainingCycleCompletionPreview: Equatable, Sendable {
  public let before: TrainingCycleSnapshot
  public let after: TrainingCycle
  public let skippedSessions: [TrainingCycleSession]

  public init(
    before: TrainingCycleSnapshot,
    after: TrainingCycle,
    skippedSessions: [TrainingCycleSession]
  ) {
    self.before = before
    self.after = after
    self.skippedSessions = skippedSessions
  }

  public var skippedCount: Int { skippedSessions.count }
  public var summary: String {
    skippedSessions.isEmpty
      ? "No Sessions were Skipped."
      : "\(skippedSessions.count) Session\(skippedSessions.count == 1 ? "" : "s") will be recorded as Skipped."
  }
}

public struct TrainingCycleAbandonmentPreview: Equatable, Sendable {
  public let before: TrainingCycleSnapshot
  public let after: TrainingCycle
  public let unperformedSessions: [TrainingCycleSession]

  public init(
    before: TrainingCycleSnapshot,
    after: TrainingCycle,
    unperformedSessions: [TrainingCycleSession]
  ) {
    self.before = before
    self.after = after
    self.unperformedSessions = unperformedSessions
  }

  public var unperformedCount: Int { unperformedSessions.count }
}

public struct TrainingCycleSessionHistory: Codable, Equatable, Sendable, Identifiable {
  public let cycleID: String
  public let weekID: String
  public let weekKind: TrainingWeekKind
  public let planned: TrainingCycleSession
  public let results: [RecordedSetResult]
  public let omissions: [OmittedSet]
  public let additionalSets: [AdditionalSet]

  public init(
    cycleID: String,
    weekID: String,
    weekKind: TrainingWeekKind,
    planned: TrainingCycleSession,
    results: [RecordedSetResult] = [],
    omissions: [OmittedSet] = [],
    additionalSets: [AdditionalSet] = []
  ) {
    self.cycleID = cycleID
    self.weekID = weekID
    self.weekKind = weekKind
    self.planned = planned
    self.results = results
    self.omissions = omissions
    self.additionalSets = additionalSets
  }

  public var id: String { planned.id }
}

public struct TrainingCycleHistoryEntry: Codable, Equatable, Sendable, Identifiable {
  public let cycle: TrainingCycle
  public let audits: [TrainingCycleAuditEntry]
  public let sessions: [TrainingCycleSessionHistory]

  public init(
    cycle: TrainingCycle,
    audits: [TrainingCycleAuditEntry] = [],
    sessions: [TrainingCycleSessionHistory] = []
  ) {
    self.cycle = cycle
    self.audits = audits
    self.sessions = sessions
  }

  public var id: String { cycle.id }
  public var lifecycleBadge: String { cycle.lifecycleState.displayName }
  public var includesDeloadBadge: Bool { cycle.weeks.contains(where: \.isDeload) }
  public var week1AnchorDate: TrainingDate { cycle.week1AnchorDate }
}

public struct TrainingCycleChangePreview: Equatable, Sendable {
  public let before: TrainingCycleSnapshot?
  public let after: TrainingCycle?
  public let action: TrainingCycleAuditAction
  public let warnings: [String]
  public let changeKind: TrainingCycleChangeKind
  public let note: String?

  public init(
    before: TrainingCycleSnapshot?,
    after: TrainingCycle?,
    action: TrainingCycleAuditAction,
    warnings: [String] = [],
    changeKind: TrainingCycleChangeKind? = nil,
    note: String? = nil
  ) {
    self.before = before
    self.after = after
    self.action = action
    self.warnings = warnings
    self.changeKind = changeKind ?? action.changeKind
    self.note = note?.isEmpty == true ? nil : note
  }

  public var requiresWarningAcknowledgement: Bool { !warnings.isEmpty }
  public var warning: String? { warnings.first }
}

public struct TrainingCycleCalendarChangeRequest: Equatable, Sendable {
  public let cycleID: String
  public let sessionID: String
  public let intendedDate: TrainingDate

  public init(cycleID: String, sessionID: String, intendedDate: TrainingDate) {
    self.cycleID = cycleID
    self.sessionID = sessionID
    self.intendedDate = intendedDate
  }

  public init(sessionID: String, intendedDate: TrainingDate) {
    self.init(cycleID: "", sessionID: sessionID, intendedDate: intendedDate)
  }
}

public typealias CalendarChangeRequest = TrainingCycleCalendarChangeRequest
public typealias ProgramEditRequest = TrainingCycleEditRequest

public protocol TrainingCycleRepository: Sendable {
  func loadDraftTrainingCycle() async throws -> TrainingCycle?
  func loadActiveTrainingCycle() async throws -> TrainingCycle?
  func completedTrainingCycleCount() async throws -> Int
  func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction
  ) async throws -> TrainingCycleAuditEntry
  func discardDraftTrainingCycle(
    expectedBefore: TrainingCycleSnapshot,
    auditID: String,
    occurredAt: Int64
  ) async throws -> TrainingCycleAuditEntry
  func trainingCycleAuditHistory(for cycleID: String) async throws -> [TrainingCycleAuditEntry]
  func loadTrainingCycles() async throws -> [TrainingCycle]
  func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction,
    note: String?,
    targetID: String?
  ) async throws -> TrainingCycleAuditEntry
}

public enum TrainingCycleRepositoryError: Error, Equatable, Sendable {
  case unavailable
  case staleCycle
  case draftAlreadyExists
  case noDraft
  case activeCycleAlreadyExists
}

extension TrainingCycleRepository {
  public func loadDraftTrainingCycle() async throws -> TrainingCycle? { nil }
  public func loadActiveTrainingCycle() async throws -> TrainingCycle? { nil }
  public func completedTrainingCycleCount() async throws -> Int { 0 }
  public func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction
  ) async throws -> TrainingCycleAuditEntry {
    throw TrainingCycleRepositoryError.unavailable
  }
  public func discardDraftTrainingCycle(
    expectedBefore: TrainingCycleSnapshot,
    auditID: String,
    occurredAt: Int64
  ) async throws -> TrainingCycleAuditEntry {
    throw TrainingCycleRepositoryError.unavailable
  }
  public func trainingCycleAuditHistory(for cycleID: String) async throws
    -> [TrainingCycleAuditEntry] { [] }

  public func loadTrainingCycles() async throws -> [TrainingCycle] { [] }

  public func saveTrainingCycle(
    _ cycle: TrainingCycle,
    expectedBefore: TrainingCycleSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: TrainingCycleAuditAction,
    note: String? = nil,
    targetID: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    try await saveTrainingCycle(
      cycle,
      expectedBefore: expectedBefore,
      auditID: auditID,
      occurredAt: occurredAt,
      action: action
    )
  }
}

public struct TrainingCycleBoundary: Sendable {
  private let repository: any TrainingCycleRepository
  private let scheduleTemplateBoundary: ScheduleTemplateBoundary
  private let liftRepository: any LiftConfigurationRepository
  private let clock: any Clock
  private let calendar: any CalendarProvider
  private let uuidGenerator: any UUIDGenerator

  public init(
    repository: any TrainingCycleRepository,
    scheduleTemplateBoundary: ScheduleTemplateBoundary,
    liftRepository: any LiftConfigurationRepository,
    clock: any Clock,
    calendar: any CalendarProvider,
    uuidGenerator: any UUIDGenerator
  ) {
    self.repository = repository
    self.scheduleTemplateBoundary = scheduleTemplateBoundary
    self.liftRepository = liftRepository
    self.clock = clock
    self.calendar = calendar
    self.uuidGenerator = uuidGenerator
  }

  public init(
    repository: any TrainingCycleRepository,
    scheduleTemplateBoundary: ScheduleTemplateBoundary,
    liftRepository: any LiftConfigurationRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator
  ) {
    self.init(
      repository: repository,
      scheduleTemplateBoundary: scheduleTemplateBoundary,
      liftRepository: liftRepository,
      clock: clock,
      calendar: CurrentCalendarProvider(),
      uuidGenerator: uuidGenerator
    )
  }

  public init(
    repository: any TrainingRepository,
    clock: any Clock,
    calendar: any CalendarProvider,
    uuidGenerator: any UUIDGenerator
  ) {
    self.init(
      repository: repository,
      scheduleTemplateBoundary: ScheduleTemplateBoundary(
        repository: repository,
        clock: clock,
        uuidGenerator: uuidGenerator
      ),
      liftRepository: repository,
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

  public func draft() async throws -> TrainingCycle? {
    try await repository.loadDraftTrainingCycle()
  }

  public func active() async throws -> TrainingCycle? {
    try await repository.loadActiveTrainingCycle()
  }

  public func completedCount() async throws -> Int {
    try await repository.completedTrainingCycleCount()
  }

  // MARK: Session, week, and cycle lifecycle

  /// Returns a preview for explicitly skipping one still-Scheduled Session.
  /// Passing an intended date never changes a Session's status; only this
  /// confirmed action does.
  public func previewSkipSession(
    sessionID: String,
    note: String? = nil
  ) async throws -> TrainingCycleChangePreview {
    let cycle = try await activeCycleForLifecycle()
    guard let location = cycle.location(ofSession: sessionID) else {
      throw TrainingCycleValidationError.scheduledSessionRequired
    }
    let current = cycle.weeks[location.weekIndex].sessions[location.sessionIndex]
    guard current.status == .scheduled else {
      throw TrainingCycleValidationError.scheduledSessionRequired
    }
    let after = replacingSession(
      in: cycle,
      weekIndex: location.weekIndex,
      sessionIndex: location.sessionIndex,
      status: .skipped
    )
    return TrainingCycleChangePreview(
      before: cycle.snapshot,
      after: after,
      action: .sessionSkipped,
      changeKind: .other,
      note: note
    )
  }

  @discardableResult
  public func skipSession(
    sessionID: String,
    confirmation: TrainingCycleLifecycleConfirmation,
    note: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    guard confirmation == .confirmed else {
      throw TrainingCycleValidationError.confirmationRequired
    }
    let preview = try await previewSkipSession(sessionID: sessionID, note: note)
    return try await repository.saveTrainingCycle(
      try requireCycle(preview.after),
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .sessionSkipped,
      note: note,
      targetID: nil
    )
  }

  /// Previews skipping every remaining Scheduled Session in one Training Week.
  /// Persistence records one status/audit mutation per affected Session even
  /// though the owner confirms the bulk action once.
  public func previewSkipRemainingSessions(
    in weekID: String,
    note: String? = nil
  ) async throws -> TrainingWeekSkipPreview {
    let cycle = try await activeCycleForLifecycle()
    guard let weekIndex = cycle.weeks.firstIndex(where: { $0.id == weekID }) else {
      throw TrainingCycleValidationError.invalidWeekOrder
    }
    let week = cycle.weeks[weekIndex]
    let scheduled = week.sessions.filter { $0.status == .scheduled }
    guard !scheduled.isEmpty else { throw TrainingCycleValidationError.weekNotFinishable }
    let after = replacingSessions(
      in: cycle,
      weekIndex: weekIndex,
      statuses: Dictionary(
        uniqueKeysWithValues: scheduled.map { ($0.id, TrainingSessionStatus.skipped) })
    )
    return TrainingWeekSkipPreview(
      before: cycle.snapshot,
      after: after,
      sessions: scheduled,
      note: note
    )
  }

  @discardableResult
  public func skipRemainingSessions(
    in weekID: String,
    confirmation: TrainingCycleLifecycleConfirmation,
    note: String? = nil
  ) async throws -> [TrainingCycleAuditEntry] {
    guard confirmation == .confirmed else {
      throw TrainingCycleValidationError.confirmationRequired
    }
    let preview = try await previewSkipRemainingSessions(in: weekID, note: note)
    var entries: [TrainingCycleAuditEntry] = []
    var currentBefore = preview.before
    var currentCycle = try await activeCycleForLifecycle()
    for session in preview.sessions {
      let cycle = try requireCycle(
        replacingSessions(
          in: currentCycle,
          weekIndex: try weekIndex(for: weekID, in: currentBefore),
          statuses: [session.id: .skipped]
        )
      )
      let entry = try await repository.saveTrainingCycle(
        cycle,
        expectedBefore: currentBefore,
        auditID: uuidGenerator.makeUUID().uuidString,
        occurredAt: timestamp(),
        action: .sessionSkipped,
        note: note,
        targetID: nil
      )
      entries.append(entry)
      currentBefore = cycle.snapshot
      currentCycle = cycle
    }
    return entries
  }

  public func previewFinishWeek(weekID: String) async throws -> TrainingWeekFinishPreview {
    let cycle = try await activeCycleForLifecycle()
    guard let weekIndex = cycle.weeks.firstIndex(where: { $0.id == weekID }) else {
      throw TrainingCycleValidationError.invalidWeekOrder
    }
    let week = cycle.weeks[weekIndex]
    guard week.isFinishable else { throw TrainingCycleValidationError.weekNotFinishable }
    let audits = try await repository.trainingCycleAuditHistory(for: cycle.id)
    let finishedWeekIDs = Set(
      cycle.weeks.compactMap { week in
        let latest = audits.last { audit in
          audit.targetID == week.id || audit.action == .sessionSkipped
        }
        return latest?.action == .weekFinished ? week.id : nil
      }
    )
    let unfinishedEarlierWeeks = cycle.weeks[..<weekIndex].filter {
      !$0.isFinished || !finishedWeekIDs.contains($0.id)
    }
    let warnings =
      unfinishedEarlierWeeks.isEmpty
      ? []
      : [
        "Earlier Training Weeks remain unfinished. Finishing this later week is allowed only after acknowledging the warning."
      ]
    return TrainingWeekFinishPreview(cycleID: cycle.id, week: week, warnings: warnings)
  }

  @discardableResult
  public func finishWeek(
    weekID: String,
    confirmation: TrainingCycleLifecycleConfirmation,
    acknowledgeEarlierWeeks: Bool = false,
    note: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    guard confirmation == .confirmed else {
      throw TrainingCycleValidationError.confirmationRequired
    }
    let preview = try await previewFinishWeek(weekID: weekID)
    guard !preview.requiresWarningAcknowledgement else {
      throw TrainingCycleValidationError.weekSequenceWarningRequired
    }
    guard let cycle = try await repository.loadActiveTrainingCycle() else {
      throw TrainingCycleValidationError.noActiveCycle
    }
    return try await repository.saveTrainingCycle(
      cycle,
      expectedBefore: cycle.snapshot,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .weekFinished,
      note: note,
      targetID: weekID
    )
  }

  public func previewCompleteCycle() async throws -> TrainingCycleCompletionPreview {
    let cycle = try await activeCycleForLifecycle()
    guard cycle.weeks.allSatisfy(\.isFinished) else {
      throw TrainingCycleValidationError.cycleNotFinishable
    }
    let audits = try await repository.trainingCycleAuditHistory(for: cycle.id)
    let finishedWeekIDs = Set(
      cycle.weeks.compactMap { week in
        let latest = audits.last { audit in
          audit.targetID == week.id || audit.action == .sessionSkipped
        }
        return latest?.action == .weekFinished ? week.id : nil
      }
    )
    guard cycle.weeks.allSatisfy({ finishedWeekIDs.contains($0.id) }) else {
      throw TrainingCycleValidationError.cycleNotFinishable
    }
    let skipped = cycle.weeks.flatMap(\.sessions).filter { $0.status == .skipped }
    let after = TrainingCycle(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: cycle.weeks,
      sourceTemplate: cycle.sourceTemplate,
      includesProvisionalDeload: cycle.includesProvisionalDeload,
      lifecycleState: .completed,
      createdAt: cycle.createdAt,
      updatedAt: timestamp(),
      liftSnapshots: cycle.liftSnapshots
    )
    return TrainingCycleCompletionPreview(
      before: cycle.snapshot,
      after: after,
      skippedSessions: skipped
    )
  }

  @discardableResult
  public func completeCycle(
    confirmation: TrainingCycleLifecycleConfirmation,
    note: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    guard confirmation == .confirmed else {
      throw TrainingCycleValidationError.confirmationRequired
    }
    let preview = try await previewCompleteCycle()
    let audit = try await repository.saveTrainingCycle(
      preview.after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .completed,
      note: note,
      targetID: nil
    )
    if let proposalRepository = repository as? any TrainingMaxProposalRepository {
      let proposalBoundary = TrainingMaxProposalBoundary(
        proposalRepository: proposalRepository,
        cycleRepository: repository,
        resultRepository: repository as? any SetResultRepository,
        liftRepository: liftRepository,
        clock: clock,
        uuidGenerator: uuidGenerator
      )
      _ = try await proposalBoundary.generateMissingProposals()
    }
    return audit
  }

  public func previewAbandonCycle(note: String? = nil) async throws
    -> TrainingCycleAbandonmentPreview {
    let cycle = try await activeCycleForLifecycle()
    let pending = cycle.weeks.flatMap(\.sessions).filter {
      $0.status == .scheduled || $0.status == .inProgress
    }
    let weeks = cycle.weeks.map { week in
      TrainingWeek(
        id: week.id,
        position: week.position,
        kind: week.kind,
        startDate: week.startDate,
        sessions: week.sessions.map { session in
          pending.contains(where: { $0.id == session.id })
            ? replacing(session, status: .unperformed)
            : session
        }
      )
    }
    let after = TrainingCycle(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: weeks,
      sourceTemplate: cycle.sourceTemplate,
      includesProvisionalDeload: cycle.includesProvisionalDeload,
      lifecycleState: .abandoned,
      createdAt: cycle.createdAt,
      updatedAt: timestamp(),
      liftSnapshots: cycle.liftSnapshots
    )
    return TrainingCycleAbandonmentPreview(
      before: cycle.snapshot,
      after: after,
      unperformedSessions: pending
    )
  }

  @discardableResult
  public func abandonCycle(
    confirmation: TrainingCycleLifecycleConfirmation,
    note: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    guard confirmation == .confirmed else {
      throw TrainingCycleValidationError.confirmationRequired
    }
    let preview = try await previewAbandonCycle(note: note)
    let audit = try await repository.saveTrainingCycle(
      preview.after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .abandoned,
      note: note,
      targetID: nil
    )
    if let linkRepository = repository as? any TrainingEventLinkRepository {
      for session in preview.unperformedSessions {
        _ = try await linkRepository.unlinkActiveHealthWorkoutLinkFacts(
          forLocalEntityID: session.id,
          unlinkedAt: clock.now()
        )
      }
    }
    return audit
  }

  public func history() async throws -> [TrainingCycleHistoryEntry] {
    let cycles = try await repository.loadTrainingCycles().sorted {
      if $0.week1AnchorDate != $1.week1AnchorDate {
        return $0.week1AnchorDate < $1.week1AnchorDate
      }
      return $0.updatedAt < $1.updatedAt
    }
    let resultRepository = repository as? any SetResultRepository
    return try await cycles.asyncMap { cycle in
      let sessions = try await cycle.weeks.flatMap { week in
        week.sessions.map { session in
          (week, session)
        }
      }.asyncMap { week, session in
        TrainingCycleSessionHistory(
          cycleID: cycle.id,
          weekID: week.id,
          weekKind: week.kind,
          planned: session,
          results: try await resultRepository?.loadSetResults(for: session.id) ?? [],
          omissions: try await resultRepository?.loadOmittedSets(for: session.id) ?? [],
          additionalSets: try await resultRepository?.loadAdditionalSets(for: session.id) ?? []
        )
      }
      return TrainingCycleHistoryEntry(
        cycle: cycle,
        audits: try await repository.trainingCycleAuditHistory(for: cycle.id),
        sessions: sessions
      )
    }
  }

  public func loadHistory() async throws -> [TrainingCycleHistoryEntry] { try await history() }

  // Vocabulary aliases keep the use case discoverable at call sites that
  // name the aggregate explicitly.
  public func previewCompleteTrainingCycle() async throws -> TrainingCycleCompletionPreview {
    try await previewCompleteCycle()
  }

  @discardableResult
  public func completeTrainingCycle(
    confirmation: TrainingCycleLifecycleConfirmation,
    note: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    try await completeCycle(confirmation: confirmation, note: note)
  }

  public func previewAbandonTrainingCycle(note: String? = nil) async throws
    -> TrainingCycleAbandonmentPreview {
    try await previewAbandonCycle(note: note)
  }

  @discardableResult
  public func abandonTrainingCycle(
    confirmation: TrainingCycleLifecycleConfirmation,
    note: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    try await abandonCycle(confirmation: confirmation, note: note)
  }

  @discardableResult
  public func finishTrainingWeek(
    weekID: String,
    confirmation: TrainingCycleLifecycleConfirmation,
    acknowledgeEarlierWeeks: Bool = false,
    note: String? = nil
  ) async throws -> TrainingCycleAuditEntry {
    try await finishWeek(
      weekID: weekID,
      confirmation: confirmation,
      acknowledgeEarlierWeeks: acknowledgeEarlierWeeks,
      note: note
    )
  }

  @discardableResult
  public func skipAllRemainingSessionsInWeek(
    weekID: String,
    confirmation: TrainingCycleLifecycleConfirmation,
    note: String? = nil
  ) async throws -> [TrainingCycleAuditEntry] {
    try await skipRemainingSessions(in: weekID, confirmation: confirmation, note: note)
  }

  private func activeCycleForLifecycle() async throws -> TrainingCycle {
    guard let cycle = try await repository.loadActiveTrainingCycle() else {
      throw TrainingCycleValidationError.noActiveCycle
    }
    return cycle
  }

  private func requireCycle(_ cycle: TrainingCycle?) throws -> TrainingCycle {
    guard let cycle else { throw TrainingCycleValidationError.noActiveCycle }
    return cycle
  }

  private func replacingSession(
    in cycle: TrainingCycle,
    weekIndex: Int,
    sessionIndex: Int,
    status: TrainingSessionStatus
  ) -> TrainingCycle {
    let statuses = [cycle.weeks[weekIndex].sessions[sessionIndex].id: status]
    return replacingSessions(in: cycle, weekIndex: weekIndex, statuses: statuses)
  }

  private func replacingSessions(
    in cycle: TrainingCycle,
    weekIndex: Int,
    statuses: [String: TrainingSessionStatus]
  ) -> TrainingCycle {
    var weeks = cycle.weeks
    let week = weeks[weekIndex]
    weeks[weekIndex] = TrainingWeek(
      id: week.id,
      position: week.position,
      kind: week.kind,
      startDate: week.startDate,
      sessions: week.sessions.map { session in
        guard let status = statuses[session.id] else { return session }
        return replacing(session, status: status)
      }
    )
    return TrainingCycle(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: weeks,
      sourceTemplate: cycle.sourceTemplate,
      includesProvisionalDeload: cycle.includesProvisionalDeload,
      lifecycleState: cycle.lifecycleState,
      createdAt: cycle.createdAt,
      updatedAt: timestamp(),
      liftSnapshots: cycle.liftSnapshots
    )
  }

  private func replacing(_ session: TrainingCycleSession, status: TrainingSessionStatus)
    -> TrainingCycleSession {
    TrainingCycleSession(
      id: session.id,
      intendedDate: session.intendedDate,
      sourceTemplateSessionID: session.sourceTemplateSessionID,
      primaryLiftID: session.primaryLiftID,
      assistanceLiftID: session.assistanceLiftID,
      prescriptions: session.prescriptions,
      status: status
    )
  }

  private func weekIndex(for weekID: String, in snapshot: TrainingCycleSnapshot) throws -> Int {
    guard let index = snapshot.weeks.firstIndex(where: { $0.id == weekID }) else {
      throw TrainingCycleValidationError.invalidWeekOrder
    }
    return index
  }

  public func defaultAnchorDate() -> TrainingDate {
    TrainingDate.monday(containing: clock.now(), calendar: calendar.calendar())
  }

  public func previewCreate(anchorDate: TrainingDate? = nil) async throws
    -> TrainingCycleChangePreview {
    guard try await repository.loadDraftTrainingCycle() == nil else {
      throw TrainingCycleValidationError.draftAlreadyExists
    }
    let template = try await scheduleTemplateBoundary.list()
    let completed = try await repository.completedTrainingCycleCount()
    let cycle = try await makeCycle(
      id: uuidGenerator.makeUUID().uuidString,
      anchorDate: anchorDate ?? defaultAnchorDate(),
      template: template.snapshot,
      includeDeload: (completed + 1).isMultiple(of: 2),
      createdAt: timestamp()
    )
    return TrainingCycleChangePreview(before: nil, after: cycle, action: .created)
  }

  public func previewCreate(anchorDate: Date) async throws -> TrainingCycleChangePreview {
    try await previewCreate(
      anchorDate: TrainingDate(date: anchorDate, calendar: calendar.calendar())
    )
  }

  public func previewEdit(_ request: TrainingCycleEditRequest) async throws
    -> TrainingCycleChangePreview {
    guard let existing = try await repository.loadDraftTrainingCycle() else {
      throw TrainingCycleValidationError.noDraft
    }
    guard request.id == existing.id else { throw TrainingCycleValidationError.staleDraft }
    let cycle = try await makeEditedCycle(request, existing: existing)
    return TrainingCycleChangePreview(
      before: existing.snapshot,
      after: cycle,
      action: .edited
    )
  }

  /// Previews a Calendar Change against the Active Training Cycle, or the Draft
  /// when no Active Training Cycle exists. A Calendar Change is intentionally
  /// narrow: it can only move a Scheduled Session's date.
  public func previewCalendarChange(
    sessionID: String,
    intendedDate: TrainingDate
  ) async throws -> TrainingCycleChangePreview {
    try await previewCalendarChange(
      TrainingCycleCalendarChangeRequest(sessionID: sessionID, intendedDate: intendedDate)
    )
  }

  public func previewCalendarChange(
    sessionID: String,
    to intendedDate: TrainingDate
  ) async throws -> TrainingCycleChangePreview {
    try await previewCalendarChange(sessionID: sessionID, intendedDate: intendedDate)
  }

  public func previewCalendarChange(
    cycleID: String,
    sessionID: String,
    to intendedDate: TrainingDate
  ) async throws -> TrainingCycleChangePreview {
    try await previewCalendarChange(
      TrainingCycleCalendarChangeRequest(
        cycleID: cycleID, sessionID: sessionID, intendedDate: intendedDate
      )
    )
  }

  public func previewCalendarChange(
    _ request: TrainingCycleCalendarChangeRequest
  ) async throws -> TrainingCycleChangePreview {
    let cycle = try await editableCycle(id: request.cycleID)
    guard let (weekIndex, sessionIndex) = cycle.location(ofSession: request.sessionID) else {
      throw TrainingCycleValidationError.staleDraft
    }
    let week = cycle.weeks[weekIndex]
    let current = week.sessions[sessionIndex]
    guard current.status == .scheduled else {
      throw TrainingCycleValidationError.scheduledSessionRequired
    }
    let replacement = TrainingCycleSession(
      id: current.id,
      intendedDate: request.intendedDate,
      sourceTemplateSessionID: current.sourceTemplateSessionID,
      primaryLiftID: current.primaryLiftID,
      assistanceLiftID: current.assistanceLiftID,
      prescriptions: current.prescriptions,
      status: current.status
    )
    var weeks = cycle.weeks
    var sessions = week.sessions
    sessions[sessionIndex] = replacement
    weeks[weekIndex] = TrainingWeek(
      id: week.id,
      position: week.position,
      kind: week.kind,
      startDate: week.startDate,
      sessions: sessions
    )
    let warnings: [String] =
      week.contains(request.intendedDate)
      ? []
      : [
        "This Calendar Change moves the Session outside its Training Week's intended date range. Review and confirm to continue."
      ]
    let after = TrainingCycle(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: weeks,
      sourceTemplate: cycle.sourceTemplate,
      includesProvisionalDeload: cycle.includesProvisionalDeload,
      lifecycleState: cycle.lifecycleState,
      createdAt: cycle.createdAt,
      updatedAt: timestamp(),
      liftSnapshots: cycle.liftSnapshots
    )
    return TrainingCycleChangePreview(
      before: cycle.snapshot,
      after: after,
      action: .calendarChanged,
      warnings: warnings,
      changeKind: .calendarChange
    )
  }

  @discardableResult
  public func confirmCalendarChange(
    _ preview: TrainingCycleChangePreview,
    acknowledgeOutsideWeek: Bool = false
  ) async throws -> TrainingCycleAuditEntry {
    guard preview.action == .calendarChanged else {
      throw TrainingCycleValidationError.staleDraft
    }
    guard !preview.requiresWarningAcknowledgement || acknowledgeOutsideWeek else {
      throw TrainingCycleValidationError.calendarChangeWarningRequired
    }
    guard let after = preview.after else { throw TrainingCycleValidationError.noDraft }
    return try await repository.saveTrainingCycle(
      after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: preview.action,
      note: preview.note
    )
  }

  /// Previews a Program Edit. The Training Week sequence and its start dates are
  /// fixed; only Scheduled Sessions may be added, removed, or have lift roles
  /// changed. Date changes remain the responsibility of Calendar Changes.
  public func previewProgramEdit(
    _ request: TrainingCycleEditRequest
  ) async throws -> TrainingCycleChangePreview {
    let cycle = try await editableCycle(id: request.id)
    guard request.id == cycle.id else { throw TrainingCycleValidationError.staleDraft }
    let edited = try await makeProgramEditedCycle(request, existing: cycle)
    return TrainingCycleChangePreview(
      before: cycle.snapshot,
      after: edited,
      action: .programEdited,
      changeKind: .programEdit
    )
  }

  @discardableResult
  public func confirmProgramEdit(
    _ preview: TrainingCycleChangePreview
  ) async throws -> TrainingCycleAuditEntry {
    guard preview.action == .programEdited else {
      throw TrainingCycleValidationError.staleDraft
    }
    return try await confirm(preview)
  }

  /// Saves one normal Training Week as the reusable Schedule Template. The
  /// resulting template contains only ordered lift roles and intended weekdays;
  /// dates, prescriptions, statuses, and logged work are not copied.
  public func previewSaveWeekToTemplate(
    cycleID: String? = nil,
    weekPosition: Int
  ) async throws -> ScheduleTemplateChangePreview {
    let cycle = try await editableCycle(id: cycleID ?? "")
    guard let week = cycle.weeks.first(where: { $0.position == weekPosition }) else {
      throw TrainingCycleValidationError.invalidWeekOrder
    }
    guard !week.kind.isDeload else { throw TrainingCycleValidationError.invalidWeekOrder }
    let sourceByID = Dictionary(
      uniqueKeysWithValues: cycle.sourceTemplate.sessions.map {
        ($0.id, $0)
      })
    let requests = try week.sessions.map { session -> ScheduleSessionRequest in
      let weekday: ScheduleWeekday
      if let source = sourceByID[session.sourceTemplateSessionID] {
        weekday = source.intendedWeekday
      } else {
        let offset = daysBetween(week.startDate, session.intendedDate)
        guard (0...6).contains(offset), let value = ScheduleWeekday(rawValue: offset + 1) else {
          throw TrainingCycleValidationError.invalidSessionDate
        }
        weekday = value
      }
      return ScheduleSessionRequest(
        id: sourceByID[session.sourceTemplateSessionID]?.id,
        intendedWeekday: weekday,
        primaryLiftID: session.primaryLiftID,
        assistanceLiftID: session.assistanceLiftID
      )
    }
    let preview = try await scheduleTemplateBoundary.preview(
      ScheduleTemplateRequest(sessions: requests)
    )
    return ScheduleTemplateChangePreview(
      before: preview.before,
      after: preview.after,
      action: .savedFromTrainingWeek
    )
  }

  public func previewSaveTrainingWeekToTemplate(
    cycleID: String? = nil,
    weekPosition: Int
  ) async throws -> ScheduleTemplateChangePreview {
    try await previewSaveWeekToTemplate(cycleID: cycleID, weekPosition: weekPosition)
  }

  @discardableResult
  public func confirmSaveWeekToTemplate(
    _ preview: ScheduleTemplateChangePreview
  ) async throws -> ScheduleTemplateAuditEntry {
    guard preview.action == .savedFromTrainingWeek else {
      throw ScheduleTemplateRepositoryError.staleTemplate
    }
    return try await scheduleTemplateBoundary.confirm(preview)
  }

  public func previewReplaceSchedule() async throws -> TrainingCycleChangePreview {
    guard let existing = try await repository.loadDraftTrainingCycle() else {
      throw TrainingCycleValidationError.noDraft
    }
    let template = try await scheduleTemplateBoundary.list()
    let completed = try await repository.completedTrainingCycleCount()
    let replacement = try await makeCycle(
      id: existing.id,
      anchorDate: existing.week1AnchorDate,
      template: template.snapshot,
      includeDeload: (completed + 1).isMultiple(of: 2),
      createdAt: existing.createdAt
    )
    return TrainingCycleChangePreview(
      before: existing.snapshot,
      after: replacement,
      action: .replacedSchedule
    )
  }

  public func previewRegenerate() async throws -> TrainingCycleChangePreview {
    guard let existing = try await repository.loadDraftTrainingCycle() else {
      throw TrainingCycleValidationError.noDraft
    }
    let template = try await scheduleTemplateBoundary.list()
    let completed = try await repository.completedTrainingCycleCount()
    let replacement = try await makeCycle(
      id: existing.id,
      anchorDate: existing.week1AnchorDate,
      template: template.snapshot,
      includeDeload: (completed + 1).isMultiple(of: 2),
      createdAt: timestamp()
    )
    return TrainingCycleChangePreview(
      before: existing.snapshot,
      after: replacement,
      action: .regenerated
    )
  }

  @discardableResult
  public func confirm(_ preview: TrainingCycleChangePreview) async throws
    -> TrainingCycleAuditEntry {
    guard !preview.requiresWarningAcknowledgement else {
      throw TrainingCycleValidationError.calendarChangeWarningRequired
    }
    guard let after = preview.after else { throw TrainingCycleValidationError.noDraft }
    return try await repository.saveTrainingCycle(
      after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: preview.action,
      note: preview.note
    )
  }

  @discardableResult
  public func create(anchorDate: TrainingDate? = nil) async throws -> TrainingCycleAuditEntry {
    try await confirm(try await previewCreate(anchorDate: anchorDate))
  }

  @discardableResult
  public func save(_ request: TrainingCycleEditRequest) async throws -> TrainingCycleAuditEntry {
    try await confirm(try await previewEdit(request))
  }

  @discardableResult
  public func replaceSchedule() async throws -> TrainingCycleAuditEntry {
    try await confirm(try await previewReplaceSchedule())
  }

  @discardableResult
  public func regenerate() async throws -> TrainingCycleAuditEntry {
    try await confirm(try await previewRegenerate())
  }

  /// Builds the immutable Active Training Cycle without changing the draft.
  /// A draft whose anchor is before today must be resolved explicitly with
  /// `.retain` or `.replace(...)`; activation never shifts dates implicitly.
  public func previewActivation(
    anchorChoice: TrainingCycleActivationAnchorChoice? = nil
  ) async throws -> TrainingCycleActivationPreview {
    guard let draft = try await repository.loadDraftTrainingCycle() else {
      throw TrainingCycleValidationError.noDraft
    }
    let active = try await repository.loadActiveTrainingCycle()
    guard active == nil else { throw TrainingCycleValidationError.activeCycleAlreadyExists }

    if let proposalRepository = repository as? any TrainingMaxProposalRepository {
      let proposalBoundary = TrainingMaxProposalBoundary(
        proposalRepository: proposalRepository,
        cycleRepository: repository,
        resultRepository: repository as? any SetResultRepository,
        liftRepository: liftRepository,
        clock: clock,
        uuidGenerator: uuidGenerator
      )
      if try await proposalBoundary.hasPendingProposals() {
        throw TrainingCycleValidationError.pendingTrainingMaxProposals
      }
    }

    if draft.week1AnchorDate < today(), anchorChoice == nil {
      throw TrainingCycleValidationError.pastAnchorRequiresChoice
    }
    let chosenAnchor: TrainingDate
    switch anchorChoice {
    case .retain, nil:
      chosenAnchor = draft.week1AnchorDate
    case .replace(let date):
      chosenAnchor = date
    }

    let completed = try await repository.completedTrainingCycleCount()
    let shouldIncludeDeload = (completed + 1).isMultiple(of: 2)
    let cadenceChanged = draft.includesProvisionalDeload != shouldIncludeDeload
    let removalWarning =
      cadenceChanged && draft.includesProvisionalDeload
      && hasCustomizedDeload(draft)
    let cadenceAdjusted = try adjustCadence(
      draft,
      includeDeload: shouldIncludeDeload,
      anchorDate: chosenAnchor
    )
    let activated = try await activateCycle(cadenceAdjusted)
    return TrainingCycleActivationPreview(
      before: draft.snapshot,
      after: activated,
      activeBefore: active?.snapshot,
      anchorChoice: anchorChoice,
      cadenceChangesDeload: cadenceChanged,
      deloadRemovalWarning: removalWarning
    )
  }

  public func previewActivation(
    anchorDate: TrainingDate,
    replacingAnchor: Bool = true
  ) async throws -> TrainingCycleActivationPreview {
    try await previewActivation(
      anchorChoice: replacingAnchor ? .replace(anchorDate) : .retain
    )
  }

  @discardableResult
  public func confirmActivation(
    _ preview: TrainingCycleActivationPreview,
    confirmDeloadChange: Bool = true
  ) async throws -> TrainingCycleAuditEntry {
    guard !preview.cadenceChangesDeload || confirmDeloadChange else {
      throw TrainingCycleValidationError.deloadConfirmationRequired
    }
    guard try await repository.loadActiveTrainingCycle() == nil else {
      throw TrainingCycleValidationError.activeCycleAlreadyExists
    }
    let audit = try await repository.saveTrainingCycle(
      preview.after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .activated
    )
    if let proposalRepository = repository as? any TrainingMaxProposalRepository {
      try await proposalRepository.markTrainingMaxProposalsEffective(cycleID: preview.after.id)
    }
    return audit
  }

  @discardableResult
  public func activate(
    anchorChoice: TrainingCycleActivationAnchorChoice? = nil,
    confirmDeloadChange: Bool = true
  ) async throws -> TrainingCycleAuditEntry {
    try await confirmActivation(
      try await previewActivation(anchorChoice: anchorChoice),
      confirmDeloadChange: confirmDeloadChange
    )
  }

  public func previewDiscard() async throws -> TrainingCycleChangePreview {
    guard let existing = try await repository.loadDraftTrainingCycle() else {
      throw TrainingCycleValidationError.noDraft
    }
    return TrainingCycleChangePreview(
      before: existing.snapshot,
      after: nil,
      action: .discarded
    )
  }

  @discardableResult
  public func discard() async throws -> TrainingCycleAuditEntry {
    let preview = try await previewDiscard()
    guard let before = preview.before else { throw TrainingCycleValidationError.noDraft }
    return try await repository.discardDraftTrainingCycle(
      expectedBefore: before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp()
    )
  }

  public func auditHistory(for cycleID: String) async throws -> [TrainingCycleAuditEntry] {
    try await repository.trainingCycleAuditHistory(for: cycleID)
  }

  private func editableCycle(id: String) async throws -> TrainingCycle {
    let active = try await repository.loadActiveTrainingCycle()
    let draft = try await repository.loadDraftTrainingCycle()
    let cycle: TrainingCycle?
    if !id.isEmpty {
      cycle = [active, draft].compactMap { $0 }.first(where: { $0.id == id })
    } else {
      cycle = active ?? draft
    }
    guard let cycle else { throw TrainingCycleValidationError.noDraft }
    return cycle
  }

  private func makeProgramEditedCycle(
    _ request: TrainingCycleEditRequest,
    existing: TrainingCycle
  ) async throws -> TrainingCycle {
    guard request.week1AnchorDate == existing.week1AnchorDate else {
      throw TrainingCycleValidationError.invalidWeekOrder
    }
    guard request.weeks.count == existing.weeks.count,
      request.weeks.map(\.position) == existing.weeks.map(\.position),
      request.weeks.map(\.kind) == existing.weeks.map(\.kind),
      request.weeks.map(\.id) == existing.weeks.map(\.id)
    else { throw TrainingCycleValidationError.invalidWeekOrder }

    let configuredIDs = Set(try await liftRepository.loadLiftConfigurations().map(\.id))
    var requestedIDs = Set<String>()
    let weeks = try request.weeks.map { requestWeek in
      let existingWeek = existing.weeks[requestWeek.position - 1]
      guard requestWeek.startDate == existingWeek.startDate else {
        throw TrainingCycleValidationError.invalidWeekOrder
      }
      var sessions: [TrainingCycleSession] = []
      for requestSession in requestWeek.sessions {
        let id = requestSession.id.isEmpty ? uuidGenerator.makeUUID().uuidString : requestSession.id
        guard requestedIDs.insert(id).inserted else {
          throw TrainingCycleValidationError.invalidWeekOrder
        }
        guard configuredIDs.contains(requestSession.primaryLiftID) else {
          throw TrainingCycleValidationError.unconfiguredLift(requestSession.primaryLiftID)
        }
        guard configuredIDs.contains(requestSession.assistanceLiftID) else {
          throw TrainingCycleValidationError.unconfiguredLift(requestSession.assistanceLiftID)
        }
        let original = existingWeek.sessions.first(where: { $0.id == id })
        if let original {
          let rolesChanged =
            original.primaryLiftID != requestSession.primaryLiftID
            || original.assistanceLiftID != requestSession.assistanceLiftID
          guard
            original.status == .scheduled
              || (!rolesChanged
                && requestSession.intendedDate == original.intendedDate)
          else {
            throw TrainingCycleValidationError.scheduledSessionRequired
          }
          guard requestSession.intendedDate == original.intendedDate else {
            throw TrainingCycleValidationError.invalidSessionDate
          }
          if !rolesChanged {
            sessions.append(original)
          } else {
            let prescriptions: [TrainingSetPrescription]
            if existing.isActive {
              let primary = try makePrescriptions(
                role: .primary, liftID: requestSession.primaryLiftID,
                kind: existingWeek.kind, snapshots: existing.liftSnapshots
              )
              let assistance = try makePrescriptions(
                role: .assistance, liftID: requestSession.assistanceLiftID,
                kind: existingWeek.kind, snapshots: existing.liftSnapshots
              )
              prescriptions = primary + assistance
            } else {
              prescriptions = []
            }
            sessions.append(
              TrainingCycleSession(
                id: original.id,
                intendedDate: original.intendedDate,
                sourceTemplateSessionID: original.sourceTemplateSessionID,
                primaryLiftID: requestSession.primaryLiftID,
                assistanceLiftID: requestSession.assistanceLiftID,
                prescriptions: prescriptions,
                status: .scheduled
              ))
          }
        } else {
          guard requestSession.intendedDate >= requestWeek.startDate,
            requestSession.intendedDate <= requestWeek.startDate.adding(days: 6)
          else { throw TrainingCycleValidationError.invalidSessionDate }
          let prescriptions: [TrainingSetPrescription]
          if existing.isActive {
            prescriptions =
              try makePrescriptions(
                role: .primary, liftID: requestSession.primaryLiftID,
                kind: requestWeek.kind, snapshots: existing.liftSnapshots
              )
              + makePrescriptions(
                role: .assistance, liftID: requestSession.assistanceLiftID,
                kind: requestWeek.kind, snapshots: existing.liftSnapshots
              )
          } else {
            prescriptions = []
          }
          sessions.append(
            TrainingCycleSession(
              id: id,
              intendedDate: requestSession.intendedDate,
              sourceTemplateSessionID: id,
              primaryLiftID: requestSession.primaryLiftID,
              assistanceLiftID: requestSession.assistanceLiftID,
              prescriptions: prescriptions
            ))
        }
      }
      guard !sessions.isEmpty else { throw TrainingCycleValidationError.emptyTemplate }
      return TrainingWeek(
        id: existingWeek.id,
        position: existingWeek.position,
        kind: existingWeek.kind,
        startDate: existingWeek.startDate,
        sessions: sessions
      )
    }

    let existingSessions = existing.weeks.flatMap(\.sessions)
    let removed = existingSessions.filter { !requestedIDs.contains($0.id) }
    guard removed.allSatisfy({ $0.status == .scheduled }) else {
      throw TrainingCycleValidationError.scheduledSessionRequired
    }
    return TrainingCycle(
      id: existing.id,
      week1AnchorDate: existing.week1AnchorDate,
      weeks: weeks,
      sourceTemplate: existing.sourceTemplate,
      includesProvisionalDeload: existing.includesProvisionalDeload,
      lifecycleState: existing.lifecycleState,
      createdAt: existing.createdAt,
      updatedAt: timestamp(),
      liftSnapshots: existing.liftSnapshots
    )
  }

  private func timestamp() -> Int64 {
    Int64(clock.now().timeIntervalSince1970)
  }

  private func today() -> TrainingDate {
    TrainingDate(date: clock.now(), calendar: calendar.calendar())
  }

  private func adjustCadence(
    _ draft: TrainingCycle,
    includeDeload: Bool,
    anchorDate: TrainingDate
  ) throws -> TrainingCycle {
    var weeks = draft.weeks
    if !includeDeload, weeks.last?.kind == .deload {
      weeks.removeLast()
    }

    let dayShift = daysBetween(draft.week1AnchorDate, anchorDate)
    let shiftedWeeks = weeks.enumerated().map { index, week in
      let weekStart = week.startDate.adding(days: dayShift)
      let sessions = week.sessions.map { session in
        TrainingCycleSession(
          id: session.id,
          intendedDate: session.intendedDate.adding(days: dayShift),
          sourceTemplateSessionID: session.sourceTemplateSessionID,
          primaryLiftID: session.primaryLiftID,
          assistanceLiftID: session.assistanceLiftID,
          prescriptions: session.prescriptions
        )
      }
      return TrainingWeek(
        id: week.id,
        position: index + 1,
        kind: week.kind,
        startDate: weekStart,
        sessions: sessions
      )
    }
    if includeDeload, !shiftedWeeks.contains(where: { $0.kind == .deload }) {
      let startDate = anchorDate.adding(days: shiftedWeeks.count * 7)
      let sessions = draft.sourceTemplate.sessions.map { templateSession in
        TrainingCycleSession(
          id: uuidGenerator.makeUUID().uuidString,
          intendedDate: startDate.adding(days: templateSession.intendedWeekday.rawValue - 1),
          sourceTemplateSessionID: templateSession.id,
          primaryLiftID: templateSession.primaryLiftID,
          assistanceLiftID: templateSession.assistanceLiftID
        )
      }
      weeks =
        shiftedWeeks + [
          TrainingWeek(
            id: uuidGenerator.makeUUID().uuidString,
            position: shiftedWeeks.count + 1,
            kind: .deload,
            startDate: startDate,
            sessions: sessions
          )
        ]
    } else {
      weeks = shiftedWeeks
    }
    return TrainingCycle(
      id: draft.id,
      week1AnchorDate: anchorDate,
      weeks: weeks,
      sourceTemplate: draft.sourceTemplate,
      includesProvisionalDeload: includeDeload,
      lifecycleState: .draft,
      createdAt: draft.createdAt,
      updatedAt: timestamp()
    )
  }

  private func daysBetween(_ from: TrainingDate, _ to: TrainingDate) -> Int {
    var date = from
    var days = 0
    if date < to {
      while date < to {
        date = date.adding(days: 1)
        days += 1
      }
    } else {
      while to < date {
        date = date.adding(days: -1)
        days -= 1
      }
    }
    return days
  }

  private func hasCustomizedDeload(_ cycle: TrainingCycle) -> Bool {
    guard let week = cycle.weeks.last, week.kind == .deload else { return false }
    guard week.sessions.count == cycle.sourceTemplate.sessions.count else { return true }
    return zip(week.sessions, cycle.sourceTemplate.sessions).contains { session, template in
      session.primaryLiftID != template.primaryLiftID
        || session.assistanceLiftID != template.assistanceLiftID
        || session.sourceTemplateSessionID != template.id
        || session.intendedDate
          != week.startDate.adding(days: template.intendedWeekday.rawValue - 1)
    }
  }

  private func activateCycle(_ draft: TrainingCycle) async throws -> TrainingCycle {
    let configurations = try await liftRepository.loadLiftConfigurations()
    let byID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
    let usedIDs = Set(
      draft.weeks.flatMap { week in
        week.sessions.flatMap { [$0.primaryLiftID, $0.assistanceLiftID] }
      })
    var snapshots: [String: LiftConfigurationSnapshot] = [:]
    for id in usedIDs {
      guard let configuration = byID[id] else {
        throw TrainingCycleValidationError.unconfiguredLift(id)
      }
      guard configuration.trainingMax.kg.isFinite, configuration.trainingMax.kg > 0 else {
        throw TrainingCycleValidationError.missingTrainingMax(id)
      }
      snapshots[id] = configuration.snapshot
    }

    let weeks = try draft.weeks.map { week in
      let sessions = try week.sessions.map { session in
        let primary = try makePrescriptions(
          role: .primary,
          liftID: session.primaryLiftID,
          kind: week.kind,
          snapshots: snapshots
        )
        let assistance = try makePrescriptions(
          role: .assistance,
          liftID: session.assistanceLiftID,
          kind: week.kind,
          snapshots: snapshots
        )
        return TrainingCycleSession(
          id: session.id,
          intendedDate: session.intendedDate,
          sourceTemplateSessionID: session.sourceTemplateSessionID,
          primaryLiftID: session.primaryLiftID,
          assistanceLiftID: session.assistanceLiftID,
          prescriptions: primary + assistance
        )
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
      id: draft.id,
      week1AnchorDate: draft.week1AnchorDate,
      weeks: weeks,
      sourceTemplate: draft.sourceTemplate,
      includesProvisionalDeload: draft.includesProvisionalDeload,
      lifecycleState: .active,
      createdAt: draft.createdAt,
      updatedAt: timestamp(),
      liftSnapshots: snapshots
    )
  }

  private func makePrescriptions(
    role: TrainingPrescriptionRole,
    liftID: String,
    kind: TrainingWeekKind,
    snapshots: [String: LiftConfigurationSnapshot]
  ) throws -> [TrainingSetPrescription] {
    guard let snapshot = snapshots[liftID] else {
      throw TrainingCycleValidationError.missingTrainingMax(liftID)
    }
    return try FiveThreeOnePrescription.specifications(for: kind, role: role).enumerated().map {
      index, specification in
      TrainingSetPrescription(
        id: uuidGenerator.makeUUID().uuidString,
        setNumber: index + 1,
        role: role,
        percentage: specification.percentage,
        repetitions: specification.repetitions,
        weightKg: try snapshot.prescribedWeightKg(forPercentage: specification.percentage),
        isPlusSetEligible: specification.isPlusSetEligible
      )
    }
  }

  private func makeEditedCycle(
    _ request: TrainingCycleEditRequest,
    existing: TrainingCycle
  ) async throws -> TrainingCycle {
    guard request.weeks.count == existing.weeks.count else {
      throw TrainingCycleValidationError.invalidWeekCount
    }
    guard request.weeks.map(\.position) == existing.weeks.map(\.position),
      request.weeks.map(\.kind) == existing.weeks.map(\.kind),
      request.weeks.map(\.id) == existing.weeks.map(\.id)
    else {
      throw TrainingCycleValidationError.invalidWeekOrder
    }
    let configuredIDs = Set(try await liftRepository.loadLiftConfigurations().map(\.id))
    let weeks = try request.weeks.map { week in
      let existingWeek = existing.weeks[week.position - 1]
      guard week.startDate == existingWeek.startDate,
        week.sessions.count == existingWeek.sessions.count,
        week.sessions.map(\.id) == existingWeek.sessions.map(\.id)
      else {
        throw TrainingCycleValidationError.invalidWeekOrder
      }
      let sessions = try week.sessions.map { session in
        guard configuredIDs.contains(session.primaryLiftID) else {
          throw TrainingCycleValidationError.unconfiguredLift(session.primaryLiftID)
        }
        guard configuredIDs.contains(session.assistanceLiftID) else {
          throw TrainingCycleValidationError.unconfiguredLift(session.assistanceLiftID)
        }
        return TrainingCycleSession(
          id: session.id,
          intendedDate: session.intendedDate,
          sourceTemplateSessionID: existingWeek.sessions.first(
            where: { $0.id == session.id }
          )?.sourceTemplateSessionID ?? session.id,
          primaryLiftID: session.primaryLiftID,
          assistanceLiftID: session.assistanceLiftID
        )
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
      id: existing.id,
      week1AnchorDate: request.week1AnchorDate,
      weeks: weeks,
      sourceTemplate: existing.sourceTemplate,
      includesProvisionalDeload: existing.includesProvisionalDeload,
      lifecycleState: .draft,
      createdAt: existing.createdAt,
      updatedAt: timestamp()
    )
  }

  private func makeCycle(
    id: String,
    anchorDate: TrainingDate,
    template: ScheduleTemplateSnapshot,
    includeDeload: Bool,
    createdAt: Int64
  ) async throws -> TrainingCycle {
    guard !template.sessions.isEmpty else { throw TrainingCycleValidationError.emptyTemplate }
    let configuredIDs = Set(try await liftRepository.loadLiftConfigurations().map(\.id))
    for session in template.sessions {
      guard configuredIDs.contains(session.primaryLiftID) else {
        throw TrainingCycleValidationError.unconfiguredLift(session.primaryLiftID)
      }
      guard configuredIDs.contains(session.assistanceLiftID) else {
        throw TrainingCycleValidationError.unconfiguredLift(session.assistanceLiftID)
      }
    }
    let kinds: [TrainingWeekKind]
    if includeDeload {
      kinds = [.week1, .week2, .week3, .deload]
    } else {
      kinds = [.week1, .week2, .week3]
    }
    let weeks = kinds.enumerated().map { index, kind in
      let startDate = anchorDate.adding(days: index * 7)
      let sessions = template.sessions.map { templateSession in
        TrainingCycleSession(
          id: uuidGenerator.makeUUID().uuidString,
          intendedDate: startDate.adding(days: templateSession.intendedWeekday.rawValue - 1),
          sourceTemplateSessionID: templateSession.id,
          primaryLiftID: templateSession.primaryLiftID,
          assistanceLiftID: templateSession.assistanceLiftID
        )
      }
      return TrainingWeek(
        id: uuidGenerator.makeUUID().uuidString,
        position: index + 1,
        kind: kind,
        startDate: startDate,
        sessions: sessions
      )
    }
    return TrainingCycle(
      id: id,
      week1AnchorDate: anchorDate,
      weeks: weeks,
      sourceTemplate: template,
      includesProvisionalDeload: includeDeload,
      lifecycleState: .draft,
      createdAt: createdAt,
      updatedAt: createdAt
    )
  }
}

extension Array {
  fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
    var values: [T] = []
    values.reserveCapacity(count)
    for element in self {
      values.append(try await transform(element))
    }
    return values
  }
}
