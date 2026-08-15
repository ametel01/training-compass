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
    endDate: Date
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
    self.duration = max(0, endDate.timeIntervalSince(startDate))
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
    updatedAt: Date = Date()
  ) {
    let summary = HealthWorkoutWriteBackSummary(
      sessionID: sessionID, syncIdentifier: syncIdentifier, syncVersion: syncVersion,
      startDate: startDate, endDate: endDate)
    self.sessionID = summary.sessionID
    self.syncIdentifier = summary.syncIdentifier
    self.syncVersion = summary.syncVersion
    self.state = state
    self.startDate = summary.startDate
    self.endDate = summary.endDate
    self.duration = summary.duration
    self.healthKitUUID = healthKitUUID
    self.lastError = lastError
    self.updatedAt = updatedAt
  }

  public var id: String { sessionID }
  public var summary: HealthWorkoutWriteBackSummary {
    .init(
      sessionID: sessionID, syncIdentifier: syncIdentifier, syncVersion: syncVersion,
      startDate: startDate, endDate: endDate)
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
}

public protocol HealthWorkoutWriteBackClient: Sendable {
  func requestWriteAuthorization() async throws -> HealthAuthorizationSnapshot
  func saveWorkout(_ summary: HealthWorkoutWriteBackSummary) async throws -> String
  func workoutExists(syncIdentifier: String) async throws -> Bool
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

extension HealthWorkoutWriteBackRepository {
  public func loadHealthWorkoutWriteBacks() async throws -> [HealthWorkoutWriteBackRecord] { [] }
  public func saveHealthWorkoutWriteBack(_ record: HealthWorkoutWriteBackRecord) async throws {
    _ = record
    throw HealthWorkoutWriteBackClientError.unavailable
  }
  public func loadHealthWorkoutLinkFacts(forLocalEntityID localEntityID: String) async throws
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
    self.disclosure =
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

  public init(
    repository: any HealthWorkoutWriteBackRepository,
    client: any HealthWorkoutWriteBackClient,
    clock: any Clock
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

  /// The preference is durable before authorization is requested. This makes
  /// an interrupted authorization sheet recoverable without a hidden request.
  @discardableResult
  public func setEnabled(_ enabled: Bool) async throws -> HealthAuthorizationSnapshot? {
    try await repository.saveHealthWorkoutWriteBackPreference(
      .init(enabled: enabled, updatedAt: clock.now()))
    guard enabled else { return nil }
    return try await client.requestWriteAuthorization()
  }

  public func preview(
    session: TodaySessionSnapshot,
    completedAt: Date
  ) -> SessionWriteBackPreview {
    .init(summary: summary(for: session, completedAt: completedAt))
  }

  public func state(for sessionID: String) async throws -> HealthWorkoutWriteBackRecord? {
    try await repository.loadHealthWorkoutWriteBack(sessionID: sessionID)
  }

  /// Queues a per-session decision and then attempts delivery. The queue record
  /// is committed before the HealthKit operation, so a locked device or failed
  /// save cannot lose the owner's choice.
  @discardableResult
  public func queue(
    session: TodaySessionSnapshot,
    completedAt: Date,
    choice: SessionWriteBackChoice
  ) async -> HealthWorkoutWriteBackRecord? {
    guard session.completion != nil else { return nil }
    do {
      let preference = try await repository.loadHealthWorkoutWriteBackPreference()
      let summary = summary(for: session, completedAt: completedAt)
      let existing = try await repository.loadHealthWorkoutWriteBack(sessionID: session.session.id)
      let hasExternalLink = try await repository.loadHealthWorkoutLinkFacts(
        forLocalEntityID: session.session.id
      ).contains { $0.isActive }
      if choice == .doNotShare || !preference.enabled || hasExternalLink {
        let record = HealthWorkoutWriteBackRecord(
          sessionID: summary.sessionID, syncIdentifier: summary.syncIdentifier,
          syncVersion: summary.syncVersion, state: .notShared,
          startDate: summary.startDate, endDate: summary.endDate,
          updatedAt: clock.now())
        try await repository.saveHealthWorkoutWriteBack(record)
        return record
      }
      if existing?.state == .savedToHealth, existing?.syncVersion == summary.syncVersion {
        return existing
      }
      let queued = HealthWorkoutWriteBackRecord(
        sessionID: summary.sessionID, syncIdentifier: summary.syncIdentifier,
        syncVersion: summary.syncVersion, state: .queued,
        startDate: summary.startDate, endDate: summary.endDate,
        healthKitUUID: existing?.healthKitUUID, updatedAt: clock.now())
      try await repository.saveHealthWorkoutWriteBack(queued)
      return await save(queued)
    } catch {
      return nil
    }
  }

  @discardableResult
  public func retry(sessionID: String) async -> HealthWorkoutWriteBackRecord? {
    do {
      guard let record = try await repository.loadHealthWorkoutWriteBack(sessionID: sessionID),
        record.state != .notShared
      else { return nil }
      return await save(record)
    } catch { return nil }
  }

  private func save(_ queued: HealthWorkoutWriteBackRecord) async -> HealthWorkoutWriteBackRecord? {
    let saving = HealthWorkoutWriteBackRecord(
      sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
      syncVersion: queued.syncVersion, state: .saving,
      startDate: queued.startDate, endDate: queued.endDate,
      healthKitUUID: queued.healthKitUUID, updatedAt: clock.now())
    do {
      try await repository.saveHealthWorkoutWriteBack(saving)
      if try await client.workoutExists(syncIdentifier: queued.syncIdentifier) {
        let saved = HealthWorkoutWriteBackRecord(
          sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
          syncVersion: queued.syncVersion, state: .savedToHealth,
          startDate: queued.startDate, endDate: queued.endDate,
          healthKitUUID: queued.healthKitUUID, updatedAt: clock.now())
        try await repository.saveHealthWorkoutWriteBack(saved)
        return saved
      }
      let healthKitUUID = try await client.saveWorkout(queued.summary)
      let saved = HealthWorkoutWriteBackRecord(
        sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
        syncVersion: queued.syncVersion, state: .savedToHealth,
        startDate: queued.startDate, endDate: queued.endDate,
        healthKitUUID: healthKitUUID, updatedAt: clock.now())
      try await repository.saveHealthWorkoutWriteBack(saved)
      return saved
    } catch HealthWorkoutWriteBackClientError.authorizationDenied {
      return await persistFailure(queued, state: .healthAccessNeeded, error: nil)
    } catch HealthWorkoutWriteBackClientError.inaccessible {
      return await persistFailure(queued, state: .retryScheduled, error: nil)
    } catch {
      return await persistFailure(queued, state: .couldntSave, error: String(describing: error))
    }
  }

  private func persistFailure(
    _ queued: HealthWorkoutWriteBackRecord,
    state: HealthWorkoutWriteBackState,
    error: String?
  ) async -> HealthWorkoutWriteBackRecord? {
    let failed = HealthWorkoutWriteBackRecord(
      sessionID: queued.sessionID, syncIdentifier: queued.syncIdentifier,
      syncVersion: queued.syncVersion, state: state,
      startDate: queued.startDate, endDate: queued.endDate,
      healthKitUUID: queued.healthKitUUID, lastError: error, updatedAt: clock.now())
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
          month: session.intendedDate.month, day: session.intendedDate.day)) ?? completedAt
    return .init(
      sessionID: session.session.id,
      syncIdentifier: Self.syncIdentifier(for: session.session.id),
      startDate: min(start, completedAt), endDate: completedAt)
  }
}
