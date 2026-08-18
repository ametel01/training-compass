import Foundation
import TrainingDomain

public struct HeartRateConfiguration: Codable, Equatable, Sendable {
    public let zoneBoundaries: HeartRateZoneBoundaries
    public let updatedAt: Int64

    public init(zoneBoundaries: HeartRateZoneBoundaries, updatedAt: Int64) {
        self.zoneBoundaries = zoneBoundaries
        self.updatedAt = updatedAt
    }

    public var maximumHeartRate: MaximumHeartRate {
        zoneBoundaries.maximumHeartRate
    }

    public var maximumHeartRateBPM: Double {
        maximumHeartRate.beatsPerMinute
    }

    public var restingHeartRateBPM: Double {
        zoneBoundaries.restingHeartRateBPM
    }
}

public enum HeartRateConfigurationRepositoryError: Error, Codable, Equatable, Sendable {
    case unavailable
    case staleConfiguration
}

public protocol HeartRateConfigurationRepository: Sendable {
    func loadHeartRateConfiguration() async throws -> HeartRateConfiguration?
    func saveHeartRateConfiguration(
        _ configuration: HeartRateConfiguration,
        expectedBefore: HeartRateConfiguration?,
    ) async throws
    func deleteHeartRateConfiguration() async throws
}

public extension HeartRateConfigurationRepository {
    func loadHeartRateConfiguration() async throws -> HeartRateConfiguration? {
        throw HeartRateConfigurationRepositoryError.unavailable
    }

    func saveHeartRateConfiguration(
        _: HeartRateConfiguration,
        expectedBefore _: HeartRateConfiguration?,
    ) async throws {
        throw HeartRateConfigurationRepositoryError.unavailable
    }

    func deleteHeartRateConfiguration() async throws {
        throw HeartRateConfigurationRepositoryError.unavailable
    }
}

public struct HeartRateConfigurationBoundary: Sendable {
    private let repository: any HeartRateConfigurationRepository
    private let clock: any Clock

    public init(repository: any HeartRateConfigurationRepository, clock: any Clock = SystemClock()) {
        self.repository = repository
        self.clock = clock
    }

    public func current() async throws -> HeartRateConfiguration? {
        try await repository.loadHeartRateConfiguration()
    }

    public func configure(
        restingHeartRateBPM: Double,
        maximumHeartRateBPM: Double,
        zone2MinimumBPM: Double,
        zone3MinimumBPM: Double,
        zone4MinimumBPM: Double,
        zone5MinimumBPM: Double,
    ) async throws -> HeartRateConfiguration {
        let maximumHeartRate = try MaximumHeartRate(beatsPerMinute: maximumHeartRateBPM)
        let zoneBoundaries = try HeartRateZoneBoundaries(
            restingHeartRateBPM: restingHeartRateBPM,
            maximumHeartRate: maximumHeartRate,
            zone2MinimumBPM: zone2MinimumBPM,
            zone3MinimumBPM: zone3MinimumBPM,
            zone4MinimumBPM: zone4MinimumBPM,
            zone5MinimumBPM: zone5MinimumBPM,
        )
        let before = try await repository.loadHeartRateConfiguration()
        let configuration = HeartRateConfiguration(
            zoneBoundaries: zoneBoundaries,
            updatedAt: Int64(clock.now().timeIntervalSince1970),
        )
        try await repository.saveHeartRateConfiguration(configuration, expectedBefore: before)
        return configuration
    }

    public func clear() async throws {
        try await repository.deleteHeartRateConfiguration()
    }
}
