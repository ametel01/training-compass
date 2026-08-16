import Foundation

public enum StoreMigrationPhase: String, Codable, Equatable, Sendable {
  case checkingSpace
  case migratingAuthoritative
  case migratingReconstructible
  case completed
}

public struct StoreMigrationProgress: Codable, Equatable, Sendable {
  public let phase: StoreMigrationPhase
  public let fraction: Double
  public let message: String

  public init(phase: StoreMigrationPhase, fraction: Double, message: String) {
    self.phase = phase
    self.fraction = min(max(fraction, 0), 1)
    self.message = message
  }
}

public typealias StoreMigrationProgressHandler = @Sendable (StoreMigrationProgress) -> Void

public protocol StoreMigrationSpaceProviding: Sendable {
  func availableMigrationSpaceBytes(at root: URL) throws -> Int64
}

public struct FoundationStoreMigrationSpaceProvider: StoreMigrationSpaceProviding {
  public init() {}

  public func availableMigrationSpaceBytes(at root: URL) throws -> Int64 {
    let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
  }
}

/// A privacy-safe, inspectable record written when a migration fails. It never
/// contains row data, identifiers, or the underlying SQLite error string.
public struct StoreMigrationDiagnostic: Codable, Equatable, Sendable {
  public let store: TrainingStoreKind
  public let attemptedVersion: Int
  public let attemptedMigration: String
  public let recovery: String

  public init(
    store: TrainingStoreKind,
    attemptedVersion: Int,
    attemptedMigration: String,
    recovery: String? = nil
  ) {
    self.store = store
    self.attemptedVersion = attemptedVersion
    self.attemptedMigration = attemptedMigration
    self.recovery =
      recovery
      ?? (store == .reconstructible
        ? "Use the already-confirmed Health Data Rebuild path after resolving the reported condition. Locally Authoritative Data remains unchanged."
        : "Retry migration after resolving the reported storage or database condition. Locally Authoritative Data was not erased.")
  }
}

public enum StoreMigrationError: Error, Equatable, Sendable {
  case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)

  public var privacySafeDescription: String {
    "There is not enough storage to safely migrate the local stores. No local data was erased."
  }
}
