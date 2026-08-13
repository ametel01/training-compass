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
  private let preparePreDataShell: PreparePreDataShell
  let liftConfigurationBoundary: LiftConfigurationBoundary
  let scheduleTemplateBoundary: ScheduleTemplateBoundary
  let trainingCycleBoundary: TrainingCycleBoundary

  init(
    preparePreDataShell: PreparePreDataShell,
    liftConfigurationBoundary: LiftConfigurationBoundary,
    scheduleTemplateBoundary: ScheduleTemplateBoundary,
    trainingCycleBoundary: TrainingCycleBoundary
  ) {
    self.preparePreDataShell = preparePreDataShell
    self.liftConfigurationBoundary = liftConfigurationBoundary
    self.scheduleTemplateBoundary = scheduleTemplateBoundary
    self.trainingCycleBoundary = trainingCycleBoundary
  }

  func prepare() async {
    guard phase == .preparing else { return }
    do {
      _ = try await preparePreDataShell()
      phase = .ready
    } catch {
      phase = .failed
    }
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
      repository: repository,
      healthKit: PreDataHealthKitAdapter(),
      logger: UnifiedPrivacyLogger()
    )
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
      )
    )
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
