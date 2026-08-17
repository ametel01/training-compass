import Foundation

/// The confirmation required before replacing the current locally authoritative
/// dataset. A replacement confirmation deliberately names the recovery step so
/// callers can put the export-first warning directly in their UI.
public enum TrainingImportConfirmation: Codable, Equatable, Sendable {
  case confirmed
  case confirmedReplacement
  case cancelled

  public static let confirmedAfterExport: Self = .confirmedReplacement
}

public enum TrainingImportPhase: String, Codable, Equatable, Sendable {
  case validating
  case checkingSpace
  case staging
  case migrating
  case validatingStaging
  case closingCurrentStore
  case swappingAuthoritativeStore
  case regeneratingProjections
  case completed
}

public struct TrainingImportProgress: Codable, Equatable, Sendable {
  public let phase: TrainingImportPhase
  public let fraction: Double
  public let message: String

  public init(phase: TrainingImportPhase, fraction: Double, message: String) {
    self.phase = phase
    self.fraction = min(max(fraction, 0), 1)
    self.message = message
  }
}

public typealias TrainingImportProgressHandler = @Sendable (TrainingImportProgress) -> Void

/// A deterministic seam for exercising interruption and injected-failure
/// recovery. Production composition uses the no-op observer.
public protocol TrainingImportPhaseObserver: Sendable {
  func didReach(_ phase: TrainingImportPhase) throws
}

public struct NoOpTrainingImportPhaseObserver: TrainingImportPhaseObserver {
  public init() {}
  public func didReach(_ phase: TrainingImportPhase) throws {}
}

public struct TrainingImportPreview: Equatable, Sendable {
  public let archive: TrainingCompassExport
  public let summary: TrainingExportSummary
  public let warning: String
  public let replacementWarning: String

  public init(
    archive: TrainingCompassExport,
    summary: TrainingExportSummary,
    warning: String =
      "Import replaces Locally Authoritative Data. The included HealthKit snapshot is reference material only and will not be installed.",
    replacementWarning: String =
      "Before replacing the current dataset, export the current data and confirm that you want to replace it."
  ) {
    self.archive = archive
    self.summary = summary
    self.warning = warning
    self.replacementWarning = replacementWarning
  }
}

public struct TrainingImportResult: Equatable, Sendable {
  public let recordCount: Int
  public let restoredTableCounts: [String: Int]
  public let healthKitMirrorInstalled: Bool

  public init(
    recordCount: Int,
    restoredTableCounts: [String: Int],
    healthKitMirrorInstalled: Bool = false
  ) {
    self.recordCount = recordCount
    self.restoredTableCounts = restoredTableCounts
    self.healthKitMirrorInstalled = healthKitMirrorInstalled
  }
}

public enum TrainingImportError: Error, Equatable, Sendable {
  case malformedArchive
  case invalidManifest
  case integrityMismatch
  case unsupportedSchema(Int)
  case incompleteArchive(String)
  case invalidRelationship(String)
  case invariantViolation(String)
  case confirmationRequired
  case replacementConfirmationRequired
  case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)
  case stagingFailed(String)
  case replacementFailed(String)
  case cleanupFailed

  public var privacySafeDescription: String {
    switch self {
    case .malformedArchive: return "The import archive could not be decoded."
    case .invalidManifest: return "The import manifest is invalid."
    case .integrityMismatch: return "The import integrity check failed."
    case .unsupportedSchema: return "This import schema is not supported."
    case .incompleteArchive(let detail): return "The import archive is incomplete: \(detail)."
    case .invalidRelationship(let detail):
      return "The import contains an invalid relationship: \(detail)."
    case .invariantViolation(let detail):
      return "The import violates a training data invariant: \(detail)."
    case .confirmationRequired: return "Import confirmation is required."
    case .replacementConfirmationRequired:
      return "Replacing current data requires export-first confirmation."
    case .insufficientSpace: return "There is not enough storage to safely restore this archive."
    case .stagingFailed: return "The import could not be prepared safely."
    case .replacementFailed: return "The validated replacement could not be installed."
    case .cleanupFailed: return "Temporary import files could not be cleaned up."
    }
  }
}

/// File operations used by import. Keeping this seam injectable makes failure
/// and low-storage paths testable without touching the user's filesystem.
public protocol TrainingImportFileSystem: Sendable {
  func read(_ url: URL) throws -> Data
  func availableImportSpaceBytes() throws -> Int64
}

public struct FoundationTrainingImportFileSystem: TrainingImportFileSystem {
  public init() {}

  public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

  public func availableImportSpaceBytes() throws -> Int64 {
    let values = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
  }
}

public protocol TrainingReplacementImportRepository: Sendable {
  func authoritativeStoreIsEmpty() async throws -> Bool
  /// Returns the total free space needed while the old store, its rollback
  /// copy, and the isolated replacement coexist. Implementations should
  /// include the 20 percent recovery margin in this value.
  func requiredImportSpaceBytes(archiveBytes: Int64) async throws -> Int64
  func replaceAuthoritativeData(
    _ data: TrainingAuthoritativeExportData,
    progress: TrainingImportProgressHandler?
  ) async throws
}

extension TrainingReplacementImportRepository {
  public func requiredImportSpaceBytes(archiveBytes: Int64) async throws -> Int64 {
    let safeBytes = max(archiveBytes, 0)
    return Int64((Double(safeBytes) * 1.2).rounded(.up))
  }
}

public struct TrainingImportBoundary: Sendable {
  private let repository: any TrainingReplacementImportRepository
  private let fileSystem: any TrainingImportFileSystem
  private let progress: TrainingImportProgressHandler?

  public init(
    repository: any TrainingReplacementImportRepository,
    fileSystem: any TrainingImportFileSystem = FoundationTrainingImportFileSystem(),
    progress: TrainingImportProgressHandler? = nil
  ) {
    self.repository = repository
    self.fileSystem = fileSystem
    self.progress = progress
  }

  /// Decodes and validates an archive without opening or changing the current
  /// store. This is the inspectable step used before the destructive decision.
  public func preview(data: Data) throws -> TrainingImportPreview {
    let archive = try Self.decodeAndValidate(data)
    return TrainingImportPreview(archive: archive, summary: archive.summary)
  }

  public func preview(at url: URL) throws -> TrainingImportPreview {
    try preview(data: fileSystem.read(url))
  }

  public func importArchive(
    data: Data,
    confirmation: TrainingImportConfirmation
  ) async throws -> TrainingImportResult {
    let archive = try Self.decodeAndValidate(data)
    guard confirmation != .cancelled else { throw TrainingImportError.confirmationRequired }

    let isEmpty = try await repository.authoritativeStoreIsEmpty()
    if !isEmpty, confirmation != .confirmedReplacement {
      throw TrainingImportError.replacementConfirmationRequired
    }

    let requiredBytes = try await repository.requiredImportSpaceBytes(
      archiveBytes: Int64(data.count))
    emit(
      .init(
        phase: .checkingSpace,
        fraction: 0.05,
        message: "Checking storage required for a recoverable replacement."
      ))
    let availableBytes = try fileSystem.availableImportSpaceBytes()
    guard availableBytes >= requiredBytes else {
      throw TrainingImportError.insufficientSpace(
        requiredBytes: requiredBytes,
        availableBytes: availableBytes
      )
    }

    try await repository.replaceAuthoritativeData(archive.authoritativeData, progress: progress)
    emit(.init(phase: .completed, fraction: 1, message: "Import completed."))
    return TrainingImportResult(
      recordCount: archive.authoritativeData.recordCount,
      restoredTableCounts: archive.summary.tableCounts,
      healthKitMirrorInstalled: false
    )
  }

  public func importArchive(
    at url: URL,
    confirmation: TrainingImportConfirmation
  ) async throws -> TrainingImportResult {
    try await importArchive(data: fileSystem.read(url), confirmation: confirmation)
  }

  public static func decodeAndValidate(_ data: Data) throws -> TrainingCompassExport {
    let archive: TrainingCompassExport
    do {
      archive = try TrainingCompassExport.decode(data)
    } catch {
      throw TrainingImportError.malformedArchive
    }
    guard archive.manifest.archiveType == "training-compass-export" else {
      throw TrainingImportError.invalidManifest
    }
    guard archive.manifest.schemaVersion == 1 else {
      throw TrainingImportError.unsupportedSchema(archive.manifest.schemaVersion)
    }
    guard !archive.manifest.generatorVersion.isEmpty,
      archive.manifest.createdAt >= 0,
      !archive.manifest.creationContext.timeZoneIdentifier.isEmpty,
      !archive.manifest.creationContext.localeIdentifier.isEmpty
    else {
      throw TrainingImportError.invalidManifest
    }
    do {
      try archive.verifyIntegrity()
    } catch {
      throw TrainingImportError.integrityMismatch
    }
    try validateAuthoritativeData(archive.authoritativeData, summary: archive.summary)
    if let mirror = archive.healthKitMirror,
      mirror.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw TrainingImportError.invalidManifest
    }
    return archive
  }

  public static func validateAuthoritativeData(
    _ data: TrainingAuthoritativeExportData,
    summary: TrainingExportSummary? = nil
  ) throws {
    let names = data.tables.map(\.name)
    guard Set(names).count == names.count else {
      throw TrainingImportError.incompleteArchive("duplicate table")
    }
    guard Set(names) == Self.authoritativeTableNames else {
      let missing = Self.authoritativeTableNames.subtracting(names).sorted().joined(separator: ", ")
      let extra = Set(names).subtracting(Self.authoritativeTableNames).sorted().joined(
        separator: ", ")
      if !missing.isEmpty { throw TrainingImportError.incompleteArchive("missing \(missing)") }
      throw TrainingImportError.incompleteArchive("unsupported table \(extra)")
    }
    guard data.preferences.isEmpty else {
      throw TrainingImportError.invariantViolation(
        "preferences are not supported by this store schema")
    }
    for table in data.tables {
      var ids = Set<String>()
      for record in table.records {
        guard !record.id.isEmpty else {
          throw TrainingImportError.incompleteArchive("duplicate identity in \(table.name)")
        }
        guard ids.insert(record.id).inserted else {
          throw TrainingImportError.incompleteArchive("duplicate identity in \(table.name)")
        }
        if let value = record.fields["id"] {
          guard case .string(let id) = value, !id.isEmpty, id == record.id else {
            throw TrainingImportError.invalidRelationship("stable identity for \(table.name)")
          }
        }
        for value in record.fields.values {
          switch value {
          case .number(let number) where !number.isFinite:
            throw TrainingImportError.invariantViolation("non-finite number in \(table.name)")
          case .blob(let base64):
            guard Data(base64Encoded: base64) != nil else {
              throw TrainingImportError.invariantViolation("invalid binary value in \(table.name)")
            }
          default: break
          }
        }
      }
    }
    if let summary {
      guard summary.recordCount == data.recordCount else {
        throw TrainingImportError.incompleteArchive("record count summary")
      }
      let expectedCounts = Dictionary(
        uniqueKeysWithValues: data.tables.map { ($0.name, $0.records.count) })
      guard summary.tableCounts == expectedCounts else {
        throw TrainingImportError.incompleteArchive("table count summary")
      }
      guard !summary.readableText.isEmpty else {
        throw TrainingImportError.incompleteArchive("readable summary")
      }
    }
  }

  private func emit(_ value: TrainingImportProgress) {
    progress?(value)
  }

  private static let authoritativeTableNames: Set<String> = [
    "gate_zero_metadata", "lifts", "lift_configuration_audit", "schedule_templates",
    "schedule_template_sessions", "schedule_template_audit", "training_cycles",
    "training_cycle_audit", "set_results", "set_result_audit", "omitted_sets", "additional_sets",
    "session_completions", "session_correction_audit", "training_max_proposals",
    "training_max_history", "health_workout_link_facts",
    "heart_rate_configuration", "running_comparison_exclusions",
    "health_workout_write_backs"
  ]
}

public typealias TrainingRestoreBoundary = TrainingImportBoundary
