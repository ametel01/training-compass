import TrainingApplication

#if canImport(HealthKit)
  import HealthKit
#endif

/// Gate 0 composes the HealthKit seam but deliberately exposes no authorization path.
public actor PreDataHealthKitAdapter: HealthKitClient {
  public init() {}

  public func requestAuthorization() async throws -> HealthAuthorizationResult {
    .notRequested
  }
}

public enum HealthKitAdapterModule {}
