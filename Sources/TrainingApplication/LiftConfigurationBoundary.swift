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
        isCorrection: Bool = false,
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

    public var id: String {
        identity.kind.rawValue + ":" + identity.displayName
    }

    public init(identity: LiftIdentity, configuration: LiftConfiguration?) {
        self.identity = identity
        self.configuration = configuration
    }
}

public struct LiftConfigurationChangePreview: Equatable, Sendable {
    public let before: LiftConfigurationSnapshot?
    public let after: LiftConfiguration
    public let action: LiftConfigurationAuditAction

    public init(
        before: LiftConfigurationSnapshot?,
        after: LiftConfiguration,
        action: LiftConfigurationAuditAction,
    ) {
        self.before = before
        self.after = after
        self.action = action
    }
}

public protocol LiftConfigurationRepository: Sendable {
    func loadLiftConfigurations() async throws -> [LiftConfiguration]
    func saveLiftConfiguration(
        _ configuration: LiftConfiguration,
        expectedBefore: LiftConfigurationSnapshot?,
        auditID: String,
        occurredAt: Int64,
        action: LiftConfigurationAuditAction,
    ) async throws -> LiftConfigurationAuditEntry
    func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry]
}

public enum LiftConfigurationRepositoryError: Error, Equatable, Sendable {
    case unavailable
    case staleConfiguration
    case duplicateIdentity
    case unknownConfiguration
}

public extension LiftConfigurationRepository {
    func loadLiftConfigurations() async throws -> [LiftConfiguration] {
        throw LiftConfigurationRepositoryError.unavailable
    }

    func saveLiftConfiguration(
        _: LiftConfiguration,
        expectedBefore _: LiftConfigurationSnapshot?,
        auditID _: String,
        occurredAt _: Int64,
        action _: LiftConfigurationAuditAction,
    ) async throws -> LiftConfigurationAuditEntry {
        throw LiftConfigurationRepositoryError.unavailable
    }

    func auditHistory(for _: String) async throws -> [LiftConfigurationAuditEntry] {
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
        uuidGenerator: any UUIDGenerator,
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
            configured.map { ($0.identity, $0) }, uniquingKeysWith: { _, last in last },
        )
        let configuredNonProgression = configured.filter { $0.identity.progressionLift == nil }
            .sorted {
                let nameOrder = $0.identity.displayName.localizedCaseInsensitiveCompare(
                    $1.identity.displayName,
                )
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return $0.id < $1.id
            }
        let standard = LiftCatalog.progressionIdentities.map { identity in
            LiftConfigurationListItem(identity: identity, configuration: byIdentity[identity])
        }
        return standard
            + configuredNonProgression.map {
                LiftConfigurationListItem(identity: $0.identity, configuration: $0)
            }
    }

    public func preview(_ request: LiftConfigurationRequest) async throws
        -> LiftConfigurationChangePreview
    {
        let configured = try await repository.loadLiftConfigurations()
        let existing = configured.first { configuration in configuration.id == request.id }
        if request.id != nil, existing == nil {
            throw LiftConfigurationRepositoryError.unknownConfiguration
        }
        if configured.contains(where: {
            $0.identity == request.identity && $0.id != request.id
        }) {
            throw LiftConfigurationRepositoryError.duplicateIdentity
        }
        let after = try LiftConfiguration(
            id: request.id ?? uuidGenerator.makeUUID().uuidString,
            identity: request.identity,
            trainingMax: TrainingMax(kg: request.trainingMaxKg),
            loadingIncrement: LoadingIncrement(kg: request.loadingIncrementKg),
        )
        let action: LiftConfigurationAuditAction = if request.isCorrection {
            .corrected
        } else if existing == nil {
            .created
        } else {
            .edited
        }
        return LiftConfigurationChangePreview(
            before: existing?.snapshot,
            after: after,
            action: action,
        )
    }

    @discardableResult
    public func confirm(_ preview: LiftConfigurationChangePreview) async throws
        -> LiftConfigurationAuditEntry
    {
        try await repository.saveLiftConfiguration(
            preview.after,
            expectedBefore: preview.before,
            auditID: uuidGenerator.makeUUID().uuidString,
            occurredAt: Int64(clock.now().timeIntervalSince1970),
            action: preview.action,
        )
    }

    @discardableResult
    public func save(_ request: LiftConfigurationRequest) async throws -> LiftConfigurationAuditEntry {
        try await confirm(preview(request))
    }

    public func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] {
        try await repository.auditHistory(for: liftID)
    }
}

public enum LiftCatalog {
    public static let progressionIdentities: [LiftIdentity] =
        ProgressionLift.allCases.map(LiftIdentity.progression)
}
