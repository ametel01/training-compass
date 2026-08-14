import Foundation
@_exported import TrainingDomain
@_exported import TrainingInsights

public protocol Clock: Sendable {
  func now() -> Date
}

public protocol CalendarProvider: Sendable {
  func calendar() -> Calendar
}

public protocol TimeZoneProvider: Sendable {
  func timeZone() -> TimeZone
}

public protocol UUIDGenerator: Sendable {
  func makeUUID() -> UUID
}

public protocol ApplicationFileSystem: Sendable {
  func applicationSupportDirectory() throws -> URL
}

public protocol TrainingRepository: Sendable, LiftConfigurationRepository,
  ScheduleTemplateRepository, TrainingCycleRepository, SetResultRepository,
  TrainingMaxProposalRepository, TrainingAuthoritativeExportRepository,
  HeartRateConfigurationRepository
{
  func prepareStores() async throws
}

public enum HealthAuthorizationResult: Equatable, Sendable {
  case notRequested
  case requestCompleted
}

public protocol HealthKitClient: Sendable {
  func requestAuthorization() async throws -> HealthAuthorizationResult
}

public enum PrivacyLogEvent: String, Equatable, Sendable {
  case preDataStoresReady = "pre_data_stores_ready"
  case preDataStoresFailed = "pre_data_stores_failed"
}

public protocol PrivacyLogger: Sendable {
  func record(_ event: PrivacyLogEvent) async
}

public struct ApplicationDependencies: Sendable {
  public let clock: any Clock
  public let calendar: any CalendarProvider
  public let timeZone: any TimeZoneProvider
  public let uuidGenerator: any UUIDGenerator
  public let fileSystem: any ApplicationFileSystem
  public let exportFileSystem: any TrainingExportFileSystem
  public let importFileSystem: any TrainingImportFileSystem
  public let repository: any TrainingRepository
  public let healthKit: any HealthKitClient
  public let logger: any PrivacyLogger

  public init(
    clock: any Clock,
    calendar: any CalendarProvider,
    timeZone: any TimeZoneProvider,
    uuidGenerator: any UUIDGenerator,
    fileSystem: any ApplicationFileSystem,
    exportFileSystem: any TrainingExportFileSystem,
    importFileSystem: any TrainingImportFileSystem = FoundationTrainingImportFileSystem(),
    repository: any TrainingRepository,
    healthKit: any HealthKitClient,
    logger: any PrivacyLogger
  ) {
    self.clock = clock
    self.calendar = calendar
    self.timeZone = timeZone
    self.uuidGenerator = uuidGenerator
    self.fileSystem = fileSystem
    self.exportFileSystem = exportFileSystem
    self.importFileSystem = importFileSystem
    self.repository = repository
    self.healthKit = healthKit
    self.logger = logger
  }
}

public struct SystemClock: Clock {
  public init() {}

  public func now() -> Date { Date() }
}

public struct CurrentCalendarProvider: CalendarProvider {
  public init() {}

  public func calendar() -> Calendar { .current }
}

public struct CurrentTimeZoneProvider: TimeZoneProvider {
  public init() {}

  public func timeZone() -> TimeZone { .current }
}

public struct RandomUUIDGenerator: UUIDGenerator {
  public init() {}

  public func makeUUID() -> UUID { UUID() }
}
