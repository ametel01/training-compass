import Foundation
import HealthKitAdapter
import OSLog
import Observation
import TrainingApplication
import TrainingPersistence

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
  private let preparePreDataShell: PreparePreDataShell
  private let prepareUIScenario: (@Sendable () async throws -> Void)?
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
  let trainingEventLinkBoundary: TrainingEventLinkBoundary?

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
    trainingEventLinkBoundary: TrainingEventLinkBoundary? = nil,
    prepareUIScenario: (@Sendable () async throws -> Void)? = nil
  ) {
    self.preparePreDataShell = preparePreDataShell
    self.prepareUIScenario = prepareUIScenario
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
    self.trainingEventLinkBoundary = trainingEventLinkBoundary
  }

  func prepare() async {
    guard phase == .preparing else { return }
    do {
      _ = try await preparePreDataShell()
      try await prepareUIScenario?()
      phase = .ready
    } catch {
      phase = .failed
    }
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
    let fileSystem = FoundationApplicationFileSystem()
    let repository: any TrainingRepository
    do {
      let root = try fileSystem.applicationSupportDirectory()
      repository = GRDBTrainingRepository(root: root)
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
    let prepareUIScenario: (@Sendable () async throws -> Void)?
    if ProcessInfo.processInfo.environment["TRAINING_COMPASS_UI_SCENARIO"] == "event-linking",
      let scenarioRepository = repository as? GRDBTrainingRepository
    {
      prepareUIScenario = { @Sendable in
        try await TrainingEventUIScenario.seed(
          repository: scenarioRepository,
          now: dependencies.clock.now()
        )
      }
    } else {
      prepareUIScenario = nil
    }
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
        uuidGenerator: dependencies.uuidGenerator
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
      prepareUIScenario: prepareUIScenario
    )
  }
}

private enum TrainingEventUIScenario {
  static func seed(repository: GRDBTrainingRepository, now: Date) async throws {
    try await repository.eraseAllData(progress: nil)
    try await repository.prepareStores()

    let today = TrainingDate(date: now)
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "ui-template-session",
        intendedWeekday: .monday,
        primaryLiftID: "ui-squat",
        assistanceLiftID: "ui-bench"
      )
    ])
    let session = TrainingCycleSession(
      id: "ui-session",
      intendedDate: today,
      sourceTemplateSessionID: "ui-template-session",
      primaryLiftID: "ui-squat",
      assistanceLiftID: "ui-bench"
    )
    let timestamp = Int64(now.timeIntervalSince1970)
    let cycle = TrainingCycle(
      id: "ui-cycle",
      week1AnchorDate: today,
      weeks: [
        TrainingWeek(
          id: "ui-week",
          position: 1,
          kind: .week1,
          startDate: today,
          sessions: [session]
        )
      ],
      sourceTemplate: template.snapshot,
      includesProvisionalDeload: false,
      lifecycleState: .active,
      createdAt: timestamp - 60,
      updatedAt: timestamp - 30,
      liftSnapshots: [
        "ui-squat": LiftConfigurationSnapshot(
          identity: .progression(.squat),
          trainingMaxKg: 100,
          loadingIncrementKg: 2.5
        ),
        "ui-bench": LiftConfigurationSnapshot(
          identity: .progression(.benchPress),
          trainingMaxKg: 75,
          loadingIncrementKg: 2.5
        ),
      ]
    )
    _ = try await repository.saveTrainingCycle(
      cycle,
      expectedBefore: nil,
      auditID: "ui-cycle-audit",
      occurredAt: timestamp - 30,
      action: .activated
    )
    _ = try await repository.completeSession(
      CompletedSession(sessionID: session.id, confirmedAt: timestamp),
      confirmation: .confirmed
    )

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let unusualStart = calendar.date(byAdding: .day, value: -2, to: now) ?? now
    let workouts = [
      HealthWorkout(
        healthKitUUID: "ui-likely",
        activityType: "traditional-strength-training",
        startDate: now.addingTimeInterval(-3_600),
        endDate: now.addingTimeInterval(-1_800),
        duration: 1_800,
        sourceName: "Acceptance Watch",
        sourceBundleIdentifier: "com.example.acceptance",
        sourceProductType: "Watch",
        deviceName: "Acceptance Device",
        localDate: today.iso8601String,
        firstImportedAt: now,
        reconciliationContext: "ui-scenario"
      ),
      HealthWorkout(
        healthKitUUID: "ui-unusual",
        activityType: "running",
        startDate: unusualStart,
        endDate: unusualStart.addingTimeInterval(1_800),
        duration: 1_800,
        sourceName: "Acceptance Watch",
        sourceBundleIdentifier: "com.example.acceptance",
        sourceProductType: "Watch",
        deviceName: "Acceptance Device",
        localDate: TrainingDate(date: unusualStart, calendar: calendar).iso8601String,
        firstImportedAt: now,
        reconciliationContext: "ui-scenario"
      ),
    ]
    try await repository.upsertHealthWorkouts(workouts, reconciliationContext: "ui-scenario")
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
