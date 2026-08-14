import Foundation
import TrainingDomain

public struct HeartRateConfiguration: Codable, Equatable, Sendable {
  public let maximumHeartRate: MaximumHeartRate
  public let updatedAt: Int64

  public init(maximumHeartRate: MaximumHeartRate, updatedAt: Int64) {
    self.maximumHeartRate = maximumHeartRate
    self.updatedAt = updatedAt
  }

  public var maximumHeartRateBPM: Double { maximumHeartRate.beatsPerMinute }
}

public enum HeartRateConfigurationRepositoryError: Error, Codable, Equatable, Sendable {
  case unavailable
  case staleConfiguration
}

public protocol HeartRateConfigurationRepository: Sendable {
  func loadHeartRateConfiguration() async throws -> HeartRateConfiguration?
  func saveHeartRateConfiguration(
    _ configuration: HeartRateConfiguration,
    expectedBefore: HeartRateConfiguration?
  ) async throws
  func deleteHeartRateConfiguration() async throws
}

extension HeartRateConfigurationRepository {
  public func loadHeartRateConfiguration() async throws -> HeartRateConfiguration? {
    throw HeartRateConfigurationRepositoryError.unavailable
  }

  public func saveHeartRateConfiguration(
    _ configuration: HeartRateConfiguration,
    expectedBefore: HeartRateConfiguration?
  ) async throws {
    throw HeartRateConfigurationRepositoryError.unavailable
  }

  public func deleteHeartRateConfiguration() async throws {
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

  public func configure(maximumHeartRateBPM: Double) async throws -> HeartRateConfiguration {
    let maximumHeartRate = try MaximumHeartRate(beatsPerMinute: maximumHeartRateBPM)
    let before = try await repository.loadHeartRateConfiguration()
    let configuration = HeartRateConfiguration(
      maximumHeartRate: maximumHeartRate,
      updatedAt: Int64(clock.now().timeIntervalSince1970))
    try await repository.saveHeartRateConfiguration(configuration, expectedBefore: before)
    return configuration
  }

  public func clear() async throws {
    try await repository.deleteHeartRateConfiguration()
  }
}
