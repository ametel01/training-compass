import Foundation
import HealthKitAdapter
import OSLog
import Observation
import TrainingApplication
import TrainingPersistence
import UIKit

@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case preparing
    case ready
    case failed
  }

  private(set) var phase: Phase = .preparing
  private(set) var isErasing = false
  private(set) var heartRateConfigurationRevision = 0
  private let preparePreDataShell: PreparePreDataShell
  let liftConfigurationBoundary: LiftConfigurationBoundary
  let scheduleTemplateBoundary: ScheduleTemplateBoundary
  let trainingCycleBoundary: TrainingCycleBoundary
  let sessionLoggingBoundary: SessionLoggingBoundary
  let progressBoundary: ProgressBoundary
  let trainingMaxProposalBoundary: TrainingMaxProposalBoundary
  let trainingExportBoundary: TrainingExportBoundary
  let trainingImportBoundary: TrainingImportBoundary?
  let trainingErasureBoundary: TrainingErasureBoundary?
  let healthWorkoutImportBoundary: HealthWorkoutImportBoundary?
  let healthDataRebuildBoundary: HealthDataRebuildBoundary?
  let healthWorkoutRouteBoundary: HealthWorkoutRouteBoundary?
  let healthWorkoutWriteBackBoundary: HealthWorkoutWriteBackBoundary?
  let trainingEventLinkBoundary: TrainingEventLinkBoundary?
  let rollingWorkoutOverviewBoundary: RollingWorkoutOverviewBoundary?
  let runningPerformanceBoundary: RunningPerformanceBoundary?
  let heartRateConfigurationBoundary: HeartRateConfigurationBoundary?
  let heartRateZoneProvider: HealthWorkoutHeartRateZoneProvider?

  init(
    preparePreDataShell: PreparePreDataShell,
    liftConfigurationBoundary: LiftConfigurationBoundary,
    scheduleTemplateBoundary: ScheduleTemplateBoundary,
    trainingCycleBoundary: TrainingCycleBoundary,
    sessionLoggingBoundary: SessionLoggingBoundary,
    progressBoundary: ProgressBoundary,
    trainingMaxProposalBoundary: TrainingMaxProposalBoundary,
    trainingExportBoundary: TrainingExportBoundary,
    trainingImportBoundary: TrainingImportBoundary? = nil,
    trainingErasureBoundary: TrainingErasureBoundary? = nil,
    healthWorkoutImportBoundary: HealthWorkoutImportBoundary? = nil,
    healthDataRebuildBoundary: HealthDataRebuildBoundary? = nil,
    healthWorkoutRouteBoundary: HealthWorkoutRouteBoundary? = nil,
    healthWorkoutWriteBackBoundary: HealthWorkoutWriteBackBoundary? = nil,
    trainingEventLinkBoundary: TrainingEventLinkBoundary? = nil,
    rollingWorkoutOverviewBoundary: RollingWorkoutOverviewBoundary? = nil,
    runningPerformanceBoundary: RunningPerformanceBoundary? = nil,
    heartRateConfigurationBoundary: HeartRateConfigurationBoundary? = nil,
    heartRateZoneProvider: HealthWorkoutHeartRateZoneProvider? = nil
  ) {
    self.preparePreDataShell = preparePreDataShell
    self.liftConfigurationBoundary = liftConfigurationBoundary
    self.scheduleTemplateBoundary = scheduleTemplateBoundary
    self.trainingCycleBoundary = trainingCycleBoundary
    self.sessionLoggingBoundary = sessionLoggingBoundary
    self.progressBoundary = progressBoundary
    self.trainingMaxProposalBoundary = trainingMaxProposalBoundary
    self.trainingExportBoundary = trainingExportBoundary
    self.trainingImportBoundary = trainingImportBoundary
    self.trainingErasureBoundary = trainingErasureBoundary
    self.healthWorkoutImportBoundary = healthWorkoutImportBoundary
    self.healthDataRebuildBoundary = healthDataRebuildBoundary
    self.healthWorkoutRouteBoundary = healthWorkoutRouteBoundary
    self.healthWorkoutWriteBackBoundary = healthWorkoutWriteBackBoundary
    self.trainingEventLinkBoundary = trainingEventLinkBoundary
    self.rollingWorkoutOverviewBoundary = rollingWorkoutOverviewBoundary
    self.runningPerformanceBoundary = runningPerformanceBoundary
    self.heartRateConfigurationBoundary = heartRateConfigurationBoundary
    self.heartRateZoneProvider = heartRateZoneProvider
  }

  func prepare() async {
    guard phase == .preparing else { return }
    do {
      _ = try await preparePreDataShell()
      phase = .ready
      await healthWorkoutWriteBackBoundary?.resumePendingWriteBacks()
    } catch {
      phase = .failed
    }
  }

  /// Replays durable, transient write-back work without touching the Health
  /// read/reconciliation pipeline. Access and terminal failures remain
  /// explicit owner actions.
  func resumeHealthWorkoutWriteBacks() async {
    guard phase == .ready else { return }
    await healthWorkoutWriteBackBoundary?.resumePendingWriteBacks()
  }

  func heartRateConfigurationDidChange() {
    heartRateConfigurationRevision += 1
  }

  func eraseAllData() async throws {
    guard let trainingErasureBoundary else {
      throw TrainingErasureError.unavailable
    }
    isErasing = true
    defer { isErasing = false }
    _ = try await trainingErasureBoundary.erase(confirmation: .confirmed)
    phase = .preparing
    await prepare()
  }

  static func live() -> AppModel {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let fileSystem = FoundationApplicationFileSystem()
    let repository: any TrainingRepository
    do {
      let root = try fileSystem.applicationSupportDirectory()
      repository = GRDBTrainingRepository.applicationRepository(root: root)
    } catch {
      repository = UnavailableTrainingRepository()
    }
    let dependencies = ApplicationDependencies(
      clock: SystemClock(),
      calendar: CurrentCalendarProvider(),
      timeZone: CurrentTimeZoneProvider(),
      uuidGenerator: RandomUUIDGenerator(),
      fileSystem: fileSystem,
      exportFileSystem: FoundationTrainingExportFileSystem(),
      importFileSystem: FoundationTrainingImportFileSystem(),
      repository: repository,
      healthKit: PreDataHealthKitAdapter(),
      logger: UnifiedPrivacyLogger()
    )
    let healthWorkoutWriteBackBoundary: HealthWorkoutWriteBackBoundary? = {
      guard let writeBackClient = dependencies.healthKit as? any HealthWorkoutWriteBackClient,
        let writeBackRepository = repository as? any HealthWorkoutWriteBackRepository
      else { return nil }
      return HealthWorkoutWriteBackBoundary(
        repository: writeBackRepository, client: writeBackClient, clock: dependencies.clock)
    }()
    return AppModel(
      preparePreDataShell: PreparePreDataShell(dependencies: dependencies),
      liftConfigurationBoundary: LiftConfigurationBoundary(
        repository: repository,
        clock: dependencies.clock,
        uuidGenerator: dependencies.uuidGenerator
      ),
      scheduleTemplateBoundary: ScheduleTemplateBoundary(
        repository: repository,
        clock: dependencies.clock,
        uuidGenerator: dependencies.uuidGenerator
      ),
      trainingCycleBoundary: TrainingCycleBoundary(
        repository: repository,
        clock: dependencies.clock,
        calendar: dependencies.calendar,
        uuidGenerator: dependencies.uuidGenerator
      ),
      sessionLoggingBoundary: SessionLoggingBoundary(
        repository: repository,
        clock: dependencies.clock,
        calendar: dependencies.calendar,
        uuidGenerator: dependencies.uuidGenerator,
        writeBackBoundary: healthWorkoutWriteBackBoundary
      ),
      progressBoundary: ProgressBoundary(repository: repository, clock: dependencies.clock),
      trainingMaxProposalBoundary: TrainingMaxProposalBoundary(
        repository: repository,
        clock: dependencies.clock,
        uuidGenerator: dependencies.uuidGenerator
      ),
      trainingExportBoundary: TrainingExportBoundary(
        repository: repository,
        clock: dependencies.clock,
        timeZone: dependencies.timeZone,
        uuidGenerator: dependencies.uuidGenerator,
        fileSystem: dependencies.exportFileSystem
      ),
      trainingImportBoundary: (repository as? any TrainingReplacementImportRepository).map {
        TrainingImportBoundary(repository: $0, fileSystem: dependencies.importFileSystem)
      },
      trainingErasureBoundary: (repository as? any TrainingErasureRepository).map {
        TrainingErasureBoundary(repository: $0)
      },
      healthWorkoutImportBoundary: {
        guard let healthClient = dependencies.healthKit as? any HealthWorkoutClient,
          let healthRepository = repository as? any HealthWorkoutRepository
        else { return nil }
        return HealthWorkoutImportBoundary(client: healthClient, repository: healthRepository)
      }(),
      healthDataRebuildBoundary: {
        guard let healthClient = dependencies.healthKit as? any HealthWorkoutClient,
          let healthRepository = repository as? any HealthWorkoutRepository
        else { return nil }
        let storageProvider = repository as? any HealthRebuildStorageProviding
        return HealthDataRebuildBoundary(
          client: healthClient,
          repository: healthRepository,
          storageProvider: storageProvider ?? DefaultHealthRebuildStorageProvider())
      }(),
      healthWorkoutRouteBoundary: {
        // Deterministic UI acceptance scenarios use synthetic workout IDs and
        // must never trigger a real Health authorization sheet merely because
        // their detail view is exercised.
        guard ProcessInfo.processInfo.environment["TRAINING_COMPASS_UI_SCENARIO"] == nil else {
          return nil
        }
        guard let routeClient = dependencies.healthKit as? any HealthWorkoutRouteClient,
          let routeRepository = repository as? any HealthWorkoutRouteRepository
        else { return nil }
        return HealthWorkoutRouteBoundary(
          client: routeClient,
          repository: routeRepository,
          resourceProvider: DeviceHealthWorkoutRouteResourceProvider())
      }(),
      healthWorkoutWriteBackBoundary: healthWorkoutWriteBackBoundary,
      trainingEventLinkBoundary: {
        guard let healthRepository = repository as? any HealthWorkoutRepository,
          let linkRepository = repository as? any TrainingEventLinkRepository
        else { return nil }
        return TrainingEventLinkBoundary(
          cycleRepository: repository,
          resultRepository: repository,
          healthRepository: healthRepository,
          linkRepository: linkRepository,
          clock: dependencies.clock,
          uuidGenerator: dependencies.uuidGenerator
        )
      }(),
      rollingWorkoutOverviewBoundary: {
        guard let healthRepository = repository as? any HealthWorkoutRepository else { return nil }
        return RollingWorkoutOverviewBoundary(
          repository: healthRepository,
          clock: dependencies.clock,
          calendar: dependencies.calendar,
          zoneProvider: HealthWorkoutHeartRateZoneProvider(configurationRepository: repository))
      }(),
      runningPerformanceBoundary: {
        guard let healthRepository = repository as? any HealthWorkoutRepository else { return nil }
        return RunningPerformanceBoundary(
          repository: healthRepository,
          routeRepository: repository as? any HealthWorkoutRouteRepository,
          clock: dependencies.clock,
          calendar: dependencies.calendar,
          zoneProvider: HealthWorkoutHeartRateZoneProvider(configurationRepository: repository))
      }(),
      heartRateConfigurationBoundary: HeartRateConfigurationBoundary(
        repository: repository,
        clock: dependencies.clock),
      heartRateZoneProvider: HealthWorkoutHeartRateZoneProvider(
        configurationRepository: repository)
    )
  }
}

private actor DeviceHealthWorkoutRouteResourceProvider: HealthWorkoutRouteResourceProviding {
  func currentRouteResources() async -> HealthWorkoutRouteResourceSnapshot {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
    let available =
      (try? root?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage) ?? Int64.max
    let processInfo = ProcessInfo.processInfo
    let thermalState: HealthWorkoutRouteThermalState =
      switch processInfo.thermalState {
      case .nominal: .nominal
      case .fair: .fair
      case .serious: .serious
      case .critical: .critical
      @unknown default: .serious
      }
    let batteryLevel: Double? = await MainActor.run {
      let level = UIDevice.current.batteryLevel
      return level < 0 ? 0 : Double(level)
    }
    return HealthWorkoutRouteResourceSnapshot(
      availableStorageBytes: Int(min(Int64(Int.max), max(0, available))),
      lowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
      batteryLevel: batteryLevel,
      thermalState: thermalState)
  }
}

private enum AppCompositionError: Error {
  case applicationSupportUnavailable
}

private actor UnavailableTrainingRepository: TrainingRepository {
  func prepareStores() async throws {
    throw AppCompositionError.applicationSupportUnavailable
  }
}

private struct FoundationApplicationFileSystem: ApplicationFileSystem {
  func applicationSupportDirectory() throws -> URL {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return root.appending(path: "TrainingCompass", directoryHint: .isDirectory)
  }
}

private actor UnifiedPrivacyLogger: PrivacyLogger {
  private let logger = Logger(
    subsystem: "com.ametel01.trainingcompass",
    category: "application"
  )

  func record(_ event: PrivacyLogEvent) async {
    logger.notice("event=\(event.rawValue, privacy: .public)")
  }
}
