import Foundation

/// The rebuild action is intentionally explicit. There is no implicit or
/// automatic conversion from an ordinary refresh into a destructive rebuild.
public enum HealthRebuildConfirmation: Equatable, Sendable {
  case confirmed
}

public enum HealthRebuildPhase: String, Codable, Equatable, Sendable {
  case idle
  case preparing
  case rebuilding
  case regeneratingProjections
  case paused
  case failed
  case completed
}

public enum HealthRebuildArea: String, Codable, Equatable, Sendable {
  case healthMirror
  case streamAnchors
  case derivedProjections
}

public struct HealthRebuildStorageEstimate: Codable, Equatable, Sendable {
  public let stagingBytes: Int
  public let safetyMarginBytes: Int
  public let availableBytes: Int

  public init(stagingBytes: Int, safetyMarginBytes: Int, availableBytes: Int) {
    self.stagingBytes = max(0, stagingBytes)
    self.safetyMarginBytes = max(0, safetyMarginBytes)
    self.availableBytes = max(0, availableBytes)
  }

  public var requiredBytes: Int { stagingBytes + safetyMarginBytes }
  public var hasCapacity: Bool { availableBytes >= requiredBytes }
}

public struct HealthRebuildStoragePolicy: Codable, Equatable, Sendable {
  public let estimatedBytesPerRecord: Int
  public let safetyMarginBytes: Int

  public init(
    estimatedBytesPerRecord: Int = 4_096,
    safetyMarginBytes: Int = 8 * 1_024 * 1_024
  ) {
    precondition(estimatedBytesPerRecord > 0)
    precondition(safetyMarginBytes >= 0)
    self.estimatedBytesPerRecord = estimatedBytesPerRecord
    self.safetyMarginBytes = safetyMarginBytes
  }

  public static let `default` = HealthRebuildStoragePolicy()
}

public enum HealthRebuildThermalState: String, Codable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical
}

/// OS conditions that make discretionary Health rebuild work unsafe to run.
/// A constrained snapshot pauses before the next page and never removes
/// already committed local data.
public struct HealthRebuildResourceSnapshot: Codable, Equatable, Sendable {
  public static let minimumAvailableStorageBytes = 500 * 1_024 * 1_024

  public let availableStorageBytes: Int
  public let lowPowerModeEnabled: Bool
  public let batteryLevel: Double?
  public let thermalState: HealthRebuildThermalState

  public init(
    availableStorageBytes: Int = .max,
    lowPowerModeEnabled: Bool,
    batteryLevel: Double?,
    thermalState: HealthRebuildThermalState
  ) {
    self.availableStorageBytes = max(0, availableStorageBytes)
    self.lowPowerModeEnabled = lowPowerModeEnabled
    self.batteryLevel = batteryLevel.map { min(1, max(0, $0)) }
    self.thermalState = thermalState
  }

  public static let unconstrained = HealthRebuildResourceSnapshot(
    lowPowerModeEnabled: false, batteryLevel: nil, thermalState: .nominal)

  public var permitsDiscretionaryWork: Bool {
    availableStorageBytes >= Self.minimumAvailableStorageBytes
      && !lowPowerModeEnabled
      && batteryLevel.map { $0 >= 0.2 } != false
      && thermalState != .serious
      && thermalState != .critical
  }
}

public protocol HealthRebuildResourceProviding: Sendable {
  func currentHealthRebuildResources() async -> HealthRebuildResourceSnapshot
}

public struct UnconstrainedHealthRebuildResourceProvider: HealthRebuildResourceProviding {
  public init() {}

  public func currentHealthRebuildResources() async -> HealthRebuildResourceSnapshot {
    .unconstrained
  }
}

public struct HealthRebuildState: Codable, Equatable, Sendable {
  public let phase: HealthRebuildPhase
  public let completedStreams: [HealthSyncStream]
  public let startedAt: Date
  public let updatedAt: Date

  public init(
    phase: HealthRebuildPhase,
    completedStreams: [HealthSyncStream] = [],
    startedAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.phase = phase
    self.completedStreams = Array(Set(completedStreams)).sorted { $0.rawValue < $1.rawValue }
    self.startedAt = startedAt
    self.updatedAt = updatedAt
  }
}

public struct HealthRebuildProgress: Codable, Equatable, Sendable {
  public let phase: HealthRebuildPhase
  public let area: HealthRebuildArea
  public let stream: HealthSyncStream?
  public let completed: Int
  public let total: Int?
  public let message: String

  public init(
    phase: HealthRebuildPhase,
    area: HealthRebuildArea,
    stream: HealthSyncStream? = nil,
    completed: Int = 0,
    total: Int? = nil,
    message: String
  ) {
    self.phase = phase
    self.area = area
    self.stream = stream
    self.completed = max(0, completed)
    self.total = total.map { max(0, $0) }
    self.message = message
  }

  public var fraction: Double? {
    guard let total, total > 0 else { return nil }
    return min(1, Double(completed) / Double(total))
  }
}

public struct HealthRebuildResult: Codable, Equatable, Sendable {
  public let pagesCommitted: Int
  public let additionsOrReplacements: Int
  public let deletions: Int
  public let resumed: Bool
  public let state: HealthRebuildState

  public init(
    pagesCommitted: Int,
    additionsOrReplacements: Int,
    deletions: Int,
    resumed: Bool,
    state: HealthRebuildState
  ) {
    self.pagesCommitted = pagesCommitted
    self.additionsOrReplacements = additionsOrReplacements
    self.deletions = deletions
    self.resumed = resumed
    self.state = state
  }
}

public enum HealthRebuildError: Error, Equatable, Sendable {
  case confirmationRequired
  case authorizationRequired
  case insufficientStorage(requiredBytes: Int, availableBytes: Int)
  case resourcePressure
  case cancelled
  case authoritativeMigrationFailed
  case unavailable
}

/// Migration failures are deliberately classified. A reconstructible failure
/// can be repaired by rebuilding Health-derived state; an authoritative
/// failure must remain a normal launch/storage error and never expose this
/// action as a recovery path.
public enum HealthMigrationFailureKind: String, Codable, Equatable, Sendable {
  case reconstructible
  case authoritative
}

public struct HealthMigrationRecovery: Codable, Equatable, Sendable {
  public let kind: HealthMigrationFailureKind
  public let canOfferRebuild: Bool

  public init(kind: HealthMigrationFailureKind) {
    self.kind = kind
    self.canOfferRebuild = kind == .reconstructible
  }
}

public protocol HealthRebuildStorageProviding: Sendable {
  func estimateHealthRebuildStorage(
    policy: HealthRebuildStoragePolicy
  ) async throws -> HealthRebuildStorageEstimate
}

public struct DefaultHealthRebuildStorageProvider: HealthRebuildStorageProviding {
  public init() {}

  public func estimateHealthRebuildStorage(
    policy: HealthRebuildStoragePolicy
  ) async throws -> HealthRebuildStorageEstimate {
    // A repository-backed estimate is preferred in production. This fallback
    // keeps the application boundary useful for lightweight test stores.
    .init(stagingBytes: 0, safetyMarginBytes: policy.safetyMarginBytes, availableBytes: .max)
  }
}

/// Performs a confirmed, resumable deep repair. Every Health page is committed
/// before the next page is requested, so cancellation, lock, termination, and
/// background expiry leave a durable checkpoint that can be resumed later.
public actor HealthDataRebuildBoundary {
  private let client: any HealthWorkoutClient
  private let repository: any HealthWorkoutRepository
  private let writeBackBoundary: HealthWorkoutWriteBackBoundary?
  private let storageProvider: (any HealthRebuildStorageProviding)?
  private let policy: HealthRebuildStoragePolicy
  private let resourceProvider: any HealthRebuildResourceProviding
  private let limits: HealthSyncBatchLimits
  private let requestedStreams: [HealthSyncStream]
  private var authorization: HealthAuthorizationSnapshot

  public init(
    client: any HealthWorkoutClient,
    repository: any HealthWorkoutRepository,
    authorization: HealthAuthorizationSnapshot = .init(state: .notRequested),
    requestedStreams: [HealthSyncStream]? = nil,
    storageProvider: (any HealthRebuildStorageProviding)? = nil,
    policy: HealthRebuildStoragePolicy = .default,
    limits: HealthSyncBatchLimits = .default,
    resourceProvider: any HealthRebuildResourceProviding =
      UnconstrainedHealthRebuildResourceProvider(),
    writeBackBoundary: HealthWorkoutWriteBackBoundary? = nil
  ) {
    self.client = client
    self.repository = repository
    self.writeBackBoundary = writeBackBoundary
    self.authorization = authorization
    let streams = requestedStreams ?? authorization.requested.readTypes.map(HealthSyncStream.init)
    self.requestedStreams = streams.isEmpty ? [.workouts] : streams
    self.storageProvider = storageProvider
    self.policy = policy
    self.limits = limits
    self.resourceProvider = resourceProvider
  }

  public func setAuthorization(_ snapshot: HealthAuthorizationSnapshot) {
    authorization = snapshot
  }

  public func currentState() async -> HealthRebuildState? {
    try? await repository.loadHealthRebuildState()
  }

  public func migrationRecovery(for kind: HealthMigrationFailureKind) -> HealthMigrationRecovery {
    HealthMigrationRecovery(kind: kind)
  }

  /// Returns retained authoritative associations for an exact HealthKit UUID.
  /// An empty result never authorizes deleting local training or audit history.
  public func retainedLinkFacts(for healthKitUUID: String) async -> [HealthWorkoutLinkFact] {
    (try? await repository.loadHealthWorkoutLinkFacts(for: healthKitUUID)) ?? []
  }

  public func rebuild(
    confirmation: HealthRebuildConfirmation,
    progress: (@Sendable (HealthRebuildProgress) async -> Void)? = nil
  ) async throws -> HealthRebuildResult {
    guard confirmation == .confirmed else { throw HealthRebuildError.confirmationRequired }
    guard authorization.state == .authorized else {
      throw HealthRebuildError.authorizationRequired
    }

    let estimate = try await estimateStorage()
    guard estimate.hasCapacity else {
      throw HealthRebuildError.insufficientStorage(
        requiredBytes: estimate.requiredBytes, availableBytes: estimate.availableBytes)
    }
    let existing = try? await repository.loadHealthRebuildState()
    guard await resourceProvider.currentHealthRebuildResources().permitsDiscretionaryWork else {
      let paused = HealthRebuildState(
        phase: .paused,
        completedStreams: existing?.completedStreams ?? [],
        startedAt: existing?.startedAt ?? Date())
      try? await repository.updateHealthRebuildState(paused)
      await progress?(
        .init(
          phase: .paused, area: .healthMirror,
          message: "Rebuild paused until battery, storage, power, and thermal conditions recover."))
      throw HealthRebuildError.resourcePressure
    }
    let resumable = existing?.phase == .paused || existing?.phase == .rebuilding
    if !resumable {
      await progress?(
        .init(
          phase: .preparing, area: .healthMirror,
          message: "Preparing a protected staging area for Health data."))
      try await repository.beginHealthRebuild()
    }

    var state =
      try await repository.loadHealthRebuildState()
      ?? HealthRebuildState(phase: .rebuilding)
    var pagesCommitted = 0
    var additions = 0
    var deletions = 0

    do {
      try await repository.updateHealthRebuildState(
        .init(
          phase: .rebuilding, completedStreams: state.completedStreams,
          startedAt: state.startedAt))
      for stream in requestedStreams where !state.completedStreams.contains(stream) {
        try Task.checkCancellation()
        var checkpoint = try await repository.loadHealthSyncCheckpoint(for: stream)
        var token = checkpoint?.anchor
        var streamPages = 0
        await progress?(
          .init(
            phase: .rebuilding, area: stream == .workouts ? .healthMirror : .streamAnchors,
            stream: stream, message: "Rebuilding (stream.displayName)."))
        repeat {
          try Task.checkCancellation()
          guard await resourceProvider.currentHealthRebuildResources().permitsDiscretionaryWork
          else {
            throw HealthRebuildError.resourcePressure
          }
          let page = try await client.fetchHealthPage(for: stream, after: token)
          try await repository.commitHealthWorkoutPage(page, stream: stream, limits: limits)
          if stream == .workouts, let writeBackBoundary {
            for uuid in Set(page.deletedHealthKitUUIDs) {
              _ = await writeBackBoundary.markDeletedFromHealth(healthKitUUID: uuid)
            }
            _ = await writeBackBoundary.reconcileImportedWorkouts(page.workouts)
          }
          streamPages += 1
          pagesCommitted += 1
          additions += page.workouts.count
          deletions += page.deletedHealthKitUUIDs.count
          token = page.nextAnchor
          checkpoint = .init(
            stream: stream, anchor: token,
            hasLimitedHistory: page.hasLimitedHistory,
            reconciliationContext: page.reconciliationContext)
          await progress?(
            .init(
              phase: .rebuilding,
              area: stream == .workouts ? .healthMirror : .streamAnchors,
              stream: stream, completed: streamPages,
              message: "Committed \(streamPages) batch(es) for \(stream.displayName)."))
        } while token != nil

        state = .init(
          phase: .rebuilding,
          completedStreams: state.completedStreams + [stream],
          startedAt: state.startedAt)
        try await repository.updateHealthRebuildState(state)
      }

      try Task.checkCancellation()
      guard await resourceProvider.currentHealthRebuildResources().permitsDiscretionaryWork else {
        throw HealthRebuildError.resourcePressure
      }
      await progress?(
        .init(
          phase: .regeneratingProjections, area: .derivedProjections,
          message: "Regenerating derived projections from local authoritative data."))
      try await repository.regenerateHealthDerivedProjections()
      state = .init(
        phase: .completed, completedStreams: requestedStreams, startedAt: state.startedAt)
      try await repository.updateHealthRebuildState(state)
      await progress?(
        .init(
          phase: .completed, area: .derivedProjections, completed: 1, total: 1,
          message: "Health data rebuild completed."))
      return .init(
        pagesCommitted: pagesCommitted, additionsOrReplacements: additions,
        deletions: deletions, resumed: resumable, state: state)
    } catch is CancellationError {
      let paused = HealthRebuildState(
        phase: .paused, completedStreams: state.completedStreams, startedAt: state.startedAt)
      try? await repository.updateHealthRebuildState(paused)
      await progress?(
        .init(
          phase: .paused, area: .healthMirror,
          message: "Rebuild paused. Your next confirmed rebuild resumes from the last batch."))
      throw HealthRebuildError.cancelled
    } catch let error as HealthRebuildError {
      if case .authoritativeMigrationFailed = error { throw error }
      if case .resourcePressure = error {
        let paused = HealthRebuildState(
          phase: .paused, completedStreams: state.completedStreams, startedAt: state.startedAt)
        try? await repository.updateHealthRebuildState(paused)
        await progress?(
          .init(
            phase: .paused, area: .healthMirror,
            message:
              "Rebuild paused until battery, storage, power, and thermal conditions recover."))
        throw error
      }
      let failed = HealthRebuildState(
        phase: .failed, completedStreams: state.completedStreams, startedAt: state.startedAt)
      try? await repository.updateHealthRebuildState(failed)
      throw error
    } catch {
      let failed = HealthRebuildState(
        phase: .failed, completedStreams: state.completedStreams, startedAt: state.startedAt)
      try? await repository.updateHealthRebuildState(failed)
      throw HealthRebuildError.unavailable
    }
  }

  private func estimateStorage() async throws -> HealthRebuildStorageEstimate {
    if let storageProvider {
      return try await storageProvider.estimateHealthRebuildStorage(policy: policy)
    }
    return try await repository.estimateHealthRebuildStorage(policy: policy)
  }
}
