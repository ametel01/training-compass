import Foundation

/// The destructive decision required before removing all data owned by this
/// installation. Cancellation is deliberately represented so callers cannot
/// accidentally treat dismissal as consent.
public enum TrainingErasureConfirmation: Codable, Equatable, Sendable {
  case confirmed
  case cancelled
}

public enum TrainingErasurePhase: String, Codable, Equatable, Sendable {
  case closingStores
  case removingProtectedStores
  case removingTemporaryExports
  case clearingPreferences
  case completed
}

public struct TrainingErasureProgress: Codable, Equatable, Sendable {
  public let phase: TrainingErasurePhase
  public let fraction: Double
  public let message: String

  public init(phase: TrainingErasurePhase, fraction: Double, message: String) {
    self.phase = phase
    self.fraction = min(max(fraction, 0), 1)
    self.message = message
  }
}

public typealias TrainingErasureProgressHandler = @Sendable (TrainingErasureProgress) -> Void

public protocol TrainingErasurePhaseObserver: Sendable {
  func didReach(_ phase: TrainingErasurePhase) throws
}

public struct NoOpTrainingErasurePhaseObserver: TrainingErasurePhaseObserver {
  public init() {}
  public func didReach(_ phase: TrainingErasurePhase) throws {}
}

/// A storage seam for the complete local-erasure transaction. Implementations
/// must leave a durable retry marker until every local copy has been removed.
public protocol TrainingErasureRepository: Sendable {
  func eraseAllData(progress: TrainingErasureProgressHandler?) async throws
}

public enum TrainingErasureError: Error, Equatable, Sendable {
  case confirmationRequired
  case unavailable
  case cleanupFailed

  public var privacySafeDescription: String {
    switch self {
    case .confirmationRequired: return "Erasing app data requires explicit confirmation."
    case .unavailable: return "Full app erasure is unavailable."
    case .cleanupFailed: return "Some local app data could not be removed safely."
    }
  }
}

public enum TrainingErasureResult: Equatable, Sendable {
  case completed
  case healthKitDeletionIncomplete(HealthWorkoutWriteBackDeletionResult)
}

/// These strings are shared by the boundary and the UI so the confirmation
/// cannot drift into a broader promise than the implementation provides.
public enum TrainingErasureCopy {
  public static let title = "Erase All App Data"

  public static let confirmationMessage = """
    This permanently removes all Training Compass data on this installation:
    • Locally Authoritative Data
    • the HealthKit Mirror
    • Derived Projections
    • preferences
    • sync state
    • temporary exports
    Completed and Abandoned Training Cycles can only be removed through this whole-app action.
    """

  public static let externalCopiesMessage = """
    device or iCloud backups, previously shared exports, and HealthKit data outside Training Compass-authored summaries are separate copies outside this local-erasure promise. Backups, shared exports, and workouts saved by another source remain.
    """

  public static let healthKitChoiceMessage = """
    Optionally delete Training Compass HealthKit summaries first. This targets only objects authored by Training Compass. It does not remove HealthKit backups, shared exports, or workouts saved by another source.
    """

  public static let healthKitDeletionFailureMessage = """
    Some Training Compass Health summaries remain in HealthKit. Retry to delete them, or choose Erase Local Data Anyway to remove local evidence while leaving those external copies in HealthKit.
    """
}

public struct TrainingErasureBoundary: Sendable {
  private let repository: any TrainingErasureRepository
  private let healthWorkoutWriteBackBoundary: HealthWorkoutWriteBackBoundary?
  private let progress: TrainingErasureProgressHandler?

  public init(
    repository: any TrainingErasureRepository,
    healthWorkoutWriteBackBoundary: HealthWorkoutWriteBackBoundary? = nil,
    progress: TrainingErasureProgressHandler? = nil
  ) {
    self.repository = repository
    self.healthWorkoutWriteBackBoundary = healthWorkoutWriteBackBoundary
    self.progress = progress
  }

  public func erase(
    confirmation: TrainingErasureConfirmation,
    deleteHealthKitWriteBacks: Bool = false
  ) async throws -> TrainingErasureResult {
    guard confirmation == .confirmed else { throw TrainingErasureError.confirmationRequired }
    if deleteHealthKitWriteBacks {
      guard let healthWorkoutWriteBackBoundary else {
        return .healthKitDeletionIncomplete(
          .init(deletedSyncIdentifiers: [], remainingRecords: [], failure: .unavailable))
      }
      let deletion = await healthWorkoutWriteBackBoundary.deleteAllAppAuthoredSummaries()
      guard deletion.isComplete else {
        return .healthKitDeletionIncomplete(deletion)
      }
    }
    try await repository.eraseAllData(progress: progress)
    return .completed
  }

  public func eraseAllData(
    confirmation: TrainingErasureConfirmation,
    deleteHealthKitWriteBacks: Bool = false
  ) async throws -> TrainingErasureResult {
    try await erase(
      confirmation: confirmation, deleteHealthKitWriteBacks: deleteHealthKitWriteBacks)
  }
}

/// Preferences and sync state are kept behind a seam so erasure can be proved
/// without touching a user's actual defaults in tests.
public protocol TrainingErasurePreferences: Sendable {
  func removeAll() throws
}

public struct FoundationTrainingErasurePreferences: TrainingErasurePreferences {
  private let suiteName: String

  public init(suiteName: String = "com.ametel01.trainingcompass") {
    self.suiteName = suiteName
  }

  public func removeAll() throws {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
  }
}
