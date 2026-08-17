public enum PreDataShellState: Equatable, Sendable {
    case readyForEngineeringDataOnly
}

public struct PreparePreDataShell: Sendable {
    private let repository: any TrainingRepository
    private let healthKit: any HealthKitClient
    private let logger: any PrivacyLogger

    public init(
        repository: any TrainingRepository,
        healthKit: any HealthKitClient,
        logger: any PrivacyLogger,
    ) {
        self.repository = repository
        self.healthKit = healthKit
        self.logger = logger
    }

    public init(dependencies: ApplicationDependencies) {
        self.init(
            repository: dependencies.repository,
            healthKit: dependencies.healthKit,
            logger: dependencies.logger,
        )
    }

    public func callAsFunction() async throws -> PreDataShellState {
        // HealthKit is intentionally composed but untouched during Gate 0.
        _ = healthKit
        do {
            try await repository.prepareStores()
            await logger.record(.preDataStoresReady)
            return .readyForEngineeringDataOnly
        } catch {
            await logger.record(.preDataStoresFailed)
            throw error
        }
    }
}
