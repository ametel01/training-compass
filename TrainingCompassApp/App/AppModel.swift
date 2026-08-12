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

  init(preparePreDataShell: PreparePreDataShell) {
    self.preparePreDataShell = preparePreDataShell
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
    return AppModel(preparePreDataShell: PreparePreDataShell(dependencies: dependencies))
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
