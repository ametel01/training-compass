import Foundation
import TrainingDomain

public struct LiftConfigurationRequest: Equatable, Sendable {
  public let id: String?
  public let identity: LiftIdentity
  public let trainingMaxKg: Double
  public let loadingIncrementKg: Double
  public let isCorrection: Bool

  public init(
    id: String? = nil,
    identity: LiftIdentity,
    trainingMaxKg: Double,
    loadingIncrementKg: Double = 2.5,
    isCorrection: Bool = false
  ) {
    self.id = id
    self.identity = identity
    self.trainingMaxKg = trainingMaxKg
    self.loadingIncrementKg = loadingIncrementKg
    self.isCorrection = isCorrection
  }
}

public struct LiftConfigurationListItem: Equatable, Sendable, Identifiable {
  public let identity: LiftIdentity
  public let configuration: LiftConfiguration?

  public var id: String { identity.kind.rawValue + ":" + identity.displayName }

  public init(identity: LiftIdentity, configuration: LiftConfiguration?) {
    self.identity = identity
    self.configuration = configuration
  }
}

public protocol LiftConfigurationRepository: Sendable {
  func loadLiftConfigurations() async throws -> [LiftConfiguration]
  func saveLiftConfiguration(
    _ configuration: LiftConfiguration,
    auditID: String,
    occurredAt: Int64,
    action: LiftConfigurationAuditAction
  ) async throws -> LiftConfigurationAuditEntry
  func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry]
}

public enum LiftConfigurationRepositoryError: Error, Equatable, Sendable {
  case unavailable
}

extension LiftConfigurationRepository {
  public func loadLiftConfigurations() async throws -> [LiftConfiguration] {
    throw LiftConfigurationRepositoryError.unavailable
  }

  public func saveLiftConfiguration(
    _ configuration: LiftConfiguration,
    auditID: String,
    occurredAt: Int64,
    action: LiftConfigurationAuditAction
  ) async throws -> LiftConfigurationAuditEntry {
    throw LiftConfigurationRepositoryError.unavailable
  }

  public func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] {
    throw LiftConfigurationRepositoryError.unavailable
  }
}

public struct LiftConfigurationBoundary: Sendable {
  private let repository: any LiftConfigurationRepository
  private let clock: any Clock
  private let uuidGenerator: any UUIDGenerator

  public init(
    repository: any LiftConfigurationRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator
  ) {
    self.repository = repository
    self.clock = clock
    self.uuidGenerator = uuidGenerator
  }

  public func list() async throws -> [LiftConfiguration] {
    try await repository.loadLiftConfigurations()
  }

  public func listTMs() async throws -> [LiftConfigurationListItem] {
    let configured = try await repository.loadLiftConfigurations()
    let byIdentity = Dictionary(
      configured.map { ($0.identity, $0) }, uniquingKeysWith: { _, last in last })
    let configuredNonProgression = configured.filter { $0.identity.progressionLift == nil }
      .sorted {
        $0.identity.displayName.localizedCaseInsensitiveCompare($1.identity.displayName)
          == .orderedAscending
      }
    let standard = LiftCatalog.progressionIdentities.map { identity in
      LiftConfigurationListItem(identity: identity, configuration: byIdentity[identity])
    }
    return standard
      + configuredNonProgression.map {
        LiftConfigurationListItem(identity: $0.identity, configuration: $0)
      }
  }

  @discardableResult
  public func save(_ request: LiftConfigurationRequest) async throws -> LiftConfigurationAuditEntry
  {
    let existing = try await repository.loadLiftConfigurations().first { configuration in
      configuration.id == request.id
    }
    let configuration = try LiftConfiguration(
      id: request.id ?? uuidGenerator.makeUUID().uuidString,
      identity: request.identity,
      trainingMax: try TrainingMax(kg: request.trainingMaxKg),
      loadingIncrement: try LoadingIncrement(kg: request.loadingIncrementKg)
    )
    let action: LiftConfigurationAuditAction
    if request.isCorrection {
      action = .corrected
    } else if existing == nil {
      action = .created
    } else {
      action = .edited
    }
    return try await repository.saveLiftConfiguration(
      configuration,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: Int64(clock.now().timeIntervalSince1970),
      action: action
    )
  }

  public func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] {
    try await repository.auditHistory(for: liftID)
  }
}

public enum LiftCatalog {
  public static let progressionIdentities: [LiftIdentity] =
    ProgressionLift.allCases.map(LiftIdentity.progression)
}
