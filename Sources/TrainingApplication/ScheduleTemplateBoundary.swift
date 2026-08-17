import Foundation
import TrainingDomain

public struct ScheduleSessionRequest: Equatable, Sendable {
  public let id: String?
  public let intendedWeekday: ScheduleWeekday
  public let primaryLiftID: String
  public let assistanceLiftID: String

  public init(
    id: String? = nil,
    intendedWeekday: ScheduleWeekday,
    primaryLiftID: String,
    assistanceLiftID: String
  ) {
    self.id = id
    self.intendedWeekday = intendedWeekday
    self.primaryLiftID = primaryLiftID
    self.assistanceLiftID = assistanceLiftID
  }
}

public struct ScheduleTemplateRequest: Equatable, Sendable {
  public let sessions: [ScheduleSessionRequest]

  public init(sessions: [ScheduleSessionRequest]) {
    self.sessions = sessions
  }
}

public struct ScheduleTemplateChangePreview: Equatable, Sendable {
  public let before: ScheduleTemplateSnapshot?
  public let after: ScheduleTemplate
  public let action: ScheduleTemplateAuditAction

  public init(
    before: ScheduleTemplateSnapshot?,
    after: ScheduleTemplate,
    action: ScheduleTemplateAuditAction
  ) {
    self.before = before
    self.after = after
    self.action = action
  }
}

public protocol ScheduleTemplateRepository: Sendable {
  func loadScheduleTemplate() async throws -> ScheduleTemplate?
  func saveScheduleTemplate(
    _ template: ScheduleTemplate,
    expectedBefore: ScheduleTemplateSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: ScheduleTemplateAuditAction
  ) async throws -> ScheduleTemplateAuditEntry
  func scheduleTemplateAuditHistory() async throws -> [ScheduleTemplateAuditEntry]
}

public enum ScheduleTemplateRepositoryError: Error, Equatable, Sendable {
  case unavailable
  case staleTemplate
  case duplicateSessionID
}

extension ScheduleTemplateRepository {
  public func loadScheduleTemplate() async throws -> ScheduleTemplate? {
    throw ScheduleTemplateRepositoryError.unavailable
  }

  public func saveScheduleTemplate(
    _ template: ScheduleTemplate,
    expectedBefore: ScheduleTemplateSnapshot?,
    auditID: String,
    occurredAt: Int64,
    action: ScheduleTemplateAuditAction
  ) async throws -> ScheduleTemplateAuditEntry {
    throw ScheduleTemplateRepositoryError.unavailable
  }

  public func scheduleTemplateAuditHistory() async throws -> [ScheduleTemplateAuditEntry] {
    throw ScheduleTemplateRepositoryError.unavailable
  }
}

public struct ScheduleTemplateBoundary: Sendable {
  private let repository: any ScheduleTemplateRepository
  private let liftRepository: any LiftConfigurationRepository
  private let clock: any Clock
  private let uuidGenerator: any UUIDGenerator

  public init(
    repository: any ScheduleTemplateRepository,
    liftRepository: any LiftConfigurationRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator
  ) {
    self.repository = repository
    self.liftRepository = liftRepository
    self.clock = clock
    self.uuidGenerator = uuidGenerator
  }

  public init(
    repository: any TrainingRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator
  ) {
    self.init(
      repository: repository,
      liftRepository: repository,
      clock: clock,
      uuidGenerator: uuidGenerator
    )
  }

  public func list() async throws -> ScheduleTemplate {
    if let template = try await repository.loadScheduleTemplate() {
      return template
    }
    return try await defaultTemplate()
  }

  public func availableLifts() async throws -> [LiftConfiguration] {
    try await liftRepository.loadLiftConfigurations().sorted {
      let nameOrder = $0.identity.displayName.localizedCaseInsensitiveCompare(
        $1.identity.displayName
      )
      if nameOrder != .orderedSame {
        return nameOrder == .orderedAscending
      }
      return $0.id < $1.id
    }
  }

  public func defaultTemplate() async throws -> ScheduleTemplate {
    let configured = try await liftRepository.loadLiftConfigurations()
    let byIdentity = Dictionary(
      configured.map { ($0.identity, $0.id) }, uniquingKeysWith: { _, last in last })
    let sessions = try DefaultSchedule.entries.enumerated().map { index, entry in
      guard let primaryLiftID = byIdentity[entry.primaryIdentity],
        let assistanceLiftID = byIdentity[entry.assistanceIdentity]
      else {
        let missing =
          byIdentity[entry.primaryIdentity] == nil
          ? entry.primaryIdentity.displayName
          : entry.assistanceIdentity.displayName
        throw ScheduleTemplateValidationError.unconfiguredLift(missing)
      }
      return ScheduleSession(
        id: "default-session-\(index + 1)",
        intendedWeekday: entry.intendedWeekday,
        primaryLiftID: primaryLiftID,
        assistanceLiftID: assistanceLiftID
      )
    }
    return ScheduleTemplate(sessions: sessions)
  }

  public func preview(_ request: ScheduleTemplateRequest) async throws
    -> ScheduleTemplateChangePreview {
    let existing = try await repository.loadScheduleTemplate()
    let after = try await makeTemplate(from: request, id: existing?.id ?? "schedule-template")
    return ScheduleTemplateChangePreview(
      before: existing?.snapshot,
      after: after,
      action: existing == nil ? .created : .edited
    )
  }

  public func previewReset() async throws -> ScheduleTemplateChangePreview {
    let existing = try await repository.loadScheduleTemplate()
    let after = try await defaultTemplate()
    return ScheduleTemplateChangePreview(
      before: existing?.snapshot,
      after: after,
      action: .reset
    )
  }

  @discardableResult
  public func confirm(_ preview: ScheduleTemplateChangePreview) async throws
    -> ScheduleTemplateAuditEntry {
    try await repository.saveScheduleTemplate(
      preview.after,
      expectedBefore: preview.before,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: Int64(clock.now().timeIntervalSince1970),
      action: preview.action
    )
  }

  @discardableResult
  public func save(_ request: ScheduleTemplateRequest) async throws
    -> ScheduleTemplateAuditEntry {
    try await confirm(try await preview(request))
  }

  @discardableResult
  public func reset() async throws -> ScheduleTemplateAuditEntry {
    try await confirm(try await previewReset())
  }

  public func auditHistory() async throws -> [ScheduleTemplateAuditEntry] {
    try await repository.scheduleTemplateAuditHistory()
  }

  private func makeTemplate(from request: ScheduleTemplateRequest, id: String) async throws
    -> ScheduleTemplate {
    guard !request.sessions.isEmpty else {
      throw ScheduleTemplateValidationError.emptyTemplate
    }
    let configured = try await liftRepository.loadLiftConfigurations()
    let configuredIDs = Set(configured.map(\.id))
    var seenIDs = Set<String>()
    let sessions = try request.sessions.map { request in
      let sessionID = request.id ?? uuidGenerator.makeUUID().uuidString
      guard seenIDs.insert(sessionID).inserted else {
        throw ScheduleTemplateValidationError.duplicateSessionID
      }
      guard !request.primaryLiftID.isEmpty,
        !request.assistanceLiftID.isEmpty,
        configuredIDs.contains(request.primaryLiftID),
        configuredIDs.contains(request.assistanceLiftID)
      else {
        let missing =
          !configuredIDs.contains(request.primaryLiftID)
          ? request.primaryLiftID
          : request.assistanceLiftID
        throw ScheduleTemplateValidationError.unconfiguredLift(missing)
      }
      return ScheduleSession(
        id: sessionID,
        intendedWeekday: request.intendedWeekday,
        primaryLiftID: request.primaryLiftID,
        assistanceLiftID: request.assistanceLiftID
      )
    }
    return ScheduleTemplate(id: id, sessions: sessions)
  }
}
