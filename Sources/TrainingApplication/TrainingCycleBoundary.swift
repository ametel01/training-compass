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
  case replacedSchedule
  case regenerated
  case discarded
  case activated
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

  public init(
    id: String,
    cycleID: String,
    action: TrainingCycleAuditAction,
    occurredAt: Int64,
    before: TrainingCycleSnapshot?,
    after: TrainingCycleSnapshot?
  ) {
    self.id = id
    self.cycleID = cycleID
    self.action = action
    self.occurredAt = occurredAt
    self.before = before
    self.after = after
  }
}

public struct TrainingCycleChangePreview: Equatable, Sendable {
  public let before: TrainingCycleSnapshot?
  public let after: TrainingCycle?
  public let action: TrainingCycleAuditAction

  public init(
    before: TrainingCycleSnapshot?,
    after: TrainingCycle?,
    action: TrainingCycleAuditAction
  ) {
    self.before = before
    self.after = after
    self.action = action
  }
}

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
    -> [TrainingCycleAuditEntry]
  { [] }
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

  public func defaultAnchorDate() -> TrainingDate {
    TrainingDate.monday(containing: clock.now(), calendar: calendar.calendar())
  }

  public func previewCreate(anchorDate: TrainingDate? = nil) async throws
    -> TrainingCycleChangePreview
  {
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
    -> TrainingCycleChangePreview
  {
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
    -> TrainingCycleAuditEntry
  {
    guard let after = preview.after else { throw TrainingCycleValidationError.noDraft }
    return try await repository.saveTrainingCycle(
      after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: preview.action
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
    return try await repository.saveTrainingCycle(
      preview.after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      action: .activated
    )
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
