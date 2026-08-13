import Foundation
import TrainingApplication

#if canImport(HealthKit)
  import HealthKit
#endif

/// The real HealthKit adapter.  Its public surface is made only of
/// application-owned values so HealthKit cannot leak through the application
/// or persistence layers.
public actor PreDataHealthKitAdapter: HealthWorkoutClient {
  #if canImport(HealthKit)
    private let store: HKHealthStore
  #endif

  public init() {
    #if canImport(HealthKit)
      store = HKHealthStore()
    #endif
  }

  /// Kept for the Gate 0 seam and for callers that do not yet opt into the
  /// workout import workflow.
  public func requestAuthorization() async throws -> HealthAuthorizationResult {
    // The legacy seam is intentionally inert. Health connection callers use
    // requestHealthAuthorization(_:), which is only composed by the Health
    // destination after the owner explicitly taps Connect Health.
    return .notRequested
  }

  public func requestHealthAuthorization(
    _ request: HealthAuthorizationRequest
  ) async throws -> HealthAuthorizationSnapshot {
    #if canImport(HealthKit)
      guard HKHealthStore.isHealthDataAvailable() else {
        return .init(state: .unavailable, requested: request)
      }
      let readTypes = Set(request.readTypes.compactMap(Self.readType))
      let shareTypes = Set(request.writeTypes.compactMap(Self.writeType))
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
          if let error {
            continuation.resume(throwing: error)
          } else if success {
            continuation.resume(returning: ())
          } else {
            continuation.resume(returning: ())
          }
        }
      }
      // HealthKit intentionally does not reveal read denial.  Report only the
      // fact that the request completed and let the query determine whether
      // content is available.
      return .init(state: .authorized, requested: request)
    #else
      return .init(state: .unavailable, requested: request)
    #endif
  }

  public func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage {
    #if canImport(HealthKit)
      guard HKHealthStore.isHealthDataAvailable() else {
        return .init(workouts: [], reconciliationContext: "health-unavailable")
      }
      let page = try await fetchWorkouts(after: pageToken)
      return .init(
        workouts: page.workouts,
        nextPageToken: page.nextPageToken,
        reconciliationContext: "foreground-initial")
    #else
      return .init(workouts: [], reconciliationContext: "health-unavailable")
    #endif
  }

  #if canImport(HealthKit)
    private func fetchWorkouts(after pageToken: String?) async throws -> (
      workouts: [HealthWorkout], nextPageToken: String?
    ) {
      let sampleType = HKObjectType.workoutType()
      return try await withCheckedThrowingContinuation { continuation in
        let query = HKAnchoredObjectQuery(
          type: sampleType,
          predicate: nil,
          anchor: Self.anchor(from: pageToken),
          limit: 100
        ) { _, samples, _, anchor, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }
          let values = (samples as? [HKWorkout] ?? []).map { workout in
            Self.map(workout)
          }
          continuation.resume(
            returning: (values, Self.token(for: anchor)))
        }
        store.execute(query)
      }
    }

    private static func anchor(from token: String?) -> HKQueryAnchor? {
      guard let token, let data = Data(base64Encoded: token) else { return nil }
      return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func token(for anchor: HKQueryAnchor?) -> String? {
      guard let anchor,
        let data = try? NSKeyedArchiver.archivedData(
          withRootObject: anchor, requiringSecureCoding: true)
      else { return nil }
      return data.base64EncodedString()
    }

    private static func map(_ workout: HKWorkout) -> HealthWorkout {
      let sourceRevision = workout.sourceRevision
      let device = workout.device
      let timeZone = workout.metadata?[HKMetadataKeyTimeZone] as? String
      let timeZoneIdentifier = timeZone ?? TimeZone.current.identifier
      let source: HealthWorkoutTimeZoneSource =
        timeZone == nil ? .deviceAtFirstImport : .sourceMetadata
      let localDate = Self.localDate(for: workout.startDate, timeZoneIdentifier: timeZoneIdentifier)
      return HealthWorkout(
        healthKitUUID: workout.uuid.uuidString,
        activityType: String(workout.workoutActivityType.rawValue),
        startDate: workout.startDate,
        endDate: workout.endDate,
        duration: workout.duration,
        sourceName: sourceRevision.source.name,
        sourceBundleIdentifier: sourceRevision.source.bundleIdentifier,
        sourceProductType: sourceRevision.productType,
        sourceOSVersion:
          "\(sourceRevision.operatingSystemVersion.majorVersion).\(sourceRevision.operatingSystemVersion.minorVersion).\(sourceRevision.operatingSystemVersion.patchVersion)",
        deviceName: device?.name,
        deviceModel: device?.model,
        sourceTimeZoneIdentifier: timeZoneIdentifier,
        localDate: localDate,
        timeZoneSource: source,
        reconciliationContext: "foreground-initial"
      )
    }

    private static func readType(_ type: HealthReadType) -> HKObjectType? {
      switch type {
      case .workouts: HKObjectType.workoutType()
      case .heartRate: HKObjectType.quantityType(forIdentifier: .heartRate)
      case .activeEnergy: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
      case .sleep: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
      case .restingHeartRate: HKObjectType.quantityType(forIdentifier: .restingHeartRate)
      case .heartRateVariability:
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
      }
    }

    private static func localDate(for date: Date, timeZoneIdentifier: String) -> String? {
      guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = zone
      let parts = calendar.dateComponents([.year, .month, .day], from: date)
      return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func writeType(_ type: HealthWriteType) -> HKSampleType? {
      switch type {
      case .workouts: HKObjectType.workoutType()
      }
    }
  #endif
}

public enum HealthKitAdapterModule {}
