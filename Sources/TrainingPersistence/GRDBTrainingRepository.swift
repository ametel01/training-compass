import Foundation
import TrainingApplication

public actor GRDBTrainingRepository: TrainingRepository {
  private let root: URL
  private let bootstrapper: ProtectedStoreBootstrapper
  private var stores: TrainingStores?

  public init(root: URL, bootstrapper: ProtectedStoreBootstrapper = .init()) {
    self.root = root
    self.bootstrapper = bootstrapper
  }

  public func prepareStores() async throws {
    guard stores == nil else { return }
    stores = try bootstrapper.open(in: root)
  }
}

public enum TrainingPersistenceModule {}
