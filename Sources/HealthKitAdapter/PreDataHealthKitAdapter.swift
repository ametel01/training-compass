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
      let readTypes = Set(request.readTypes.flatMap(Self.readTypes))
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

  public func registerWorkoutObserver(
    onInvalidation: @escaping @Sendable () async -> Void
  ) async throws {
    #if canImport(HealthKit)
      guard HKHealthStore.isHealthDataAvailable() else { return }
      let sampleType = HKObjectType.workoutType()
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) {
          _, completion, _ in
          completion()
          Task { await onInvalidation() }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { success, error in
          if let error {
            continuation.resume(throwing: error)
          } else if success {
            continuation.resume(returning: ())
          } else {
            continuation.resume(throwing: HealthKitAdapterError.observerRegistrationFailed)
          }
        }
      }
    #else
      throw HealthKitAdapterError.unavailable
    #endif
  }

  public func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage {
    #if canImport(HealthKit)
      guard HKHealthStore.isHealthDataAvailable() else {
        return .init(workouts: [], reconciliationContext: "health-unavailable")
      }
      let page = try await fetchWorkouts(after: pageToken)
      let hasContinuation = page.workouts.count >= 100
      return .init(
        workouts: page.workouts,
        nextPageToken: hasContinuation ? page.nextPageToken : nil,
        anchor: page.nextPageToken,
        reconciliationContext: "foreground-initial",
        deletedHealthKitUUIDs: page.deletedHealthKitUUIDs)
    #else
      return .init(workouts: [], reconciliationContext: "health-unavailable")
    #endif
  }

  public func fetchWorkoutEnrichment(for workout: HealthWorkout) async
    -> HealthWorkoutEnrichment?
  {
    #if canImport(HealthKit)
      guard HKHealthStore.isHealthDataAvailable(),
        let uuid = UUID(uuidString: workout.healthKitUUID)
      else { return nil }
      let context = "workout-associated-query"
      let checkedAt = Date()
      let healthWorkout: HKWorkout
      do {
        guard let fetched = try await fetchWorkout(uuid: uuid) else { return nil }
        healthWorkout = fetched
      } catch {
        return .init(
          healthKitUUID: workout.healthKitUUID,
          heartRate: .failed(code: "heart-rate-query-failed"),
          distance: .failed(code: "distance-query-failed"),
          activeEnergy: .failed(code: "active-energy-query-failed"))
      }

      let heartRate: HealthWorkoutHeartRateDetail
      do {
        let samples = try await fetchHeartRateSamples(for: healthWorkout)
        heartRate = .available(
          samples: samples,
          checkedAt: checkedAt,
          reconciliationContext: context)
      } catch {
        heartRate = .failed(code: "heart-rate-query-failed")
      }
      let provenance = Self.provenance(
        sourceRevision: healthWorkout.sourceRevision,
        device: healthWorkout.device)
      let distance =
        Self.distanceMeters(from: healthWorkout).map {
          HealthWorkoutQuantityDetail.available(
            value: $0,
            unit: .meters,
            provenance: provenance,
            checkedAt: checkedAt,
            reconciliationContext: context)
        } ?? .notAvailableFromHealth(checkedAt: checkedAt, reconciliationContext: context)
      let activeEnergy =
        Self.activeEnergyKilocalories(from: healthWorkout).map {
          HealthWorkoutQuantityDetail.available(
            value: $0,
            unit: .kilocalories,
            provenance: provenance,
            checkedAt: checkedAt,
            reconciliationContext: context)
        } ?? .notAvailableFromHealth(checkedAt: checkedAt, reconciliationContext: context)
      return .init(
        healthKitUUID: workout.healthKitUUID,
        heartRate: heartRate,
        distance: distance,
        activeEnergy: activeEnergy)
    #else
      return nil
    #endif
  }

  #if canImport(HealthKit)
    private func fetchWorkout(uuid: UUID) async throws -> HKWorkout? {
      try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
          sampleType: HKObjectType.workoutType(),
          predicate: HKQuery.predicateForObject(with: uuid),
          limit: 1,
          sortDescriptors: nil
        ) { _, samples, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: samples?.first as? HKWorkout)
          }
        }
        store.execute(query)
      }
    }

    private func fetchHeartRateSamples(for workout: HKWorkout) async throws
      -> [HealthWorkoutHeartRateSample]
    {
      guard let sampleType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
        return []
      }
      return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
          sampleType: sampleType,
          predicate: HKQuery.predicateForObjects(from: workout),
          limit: HKObjectQueryNoLimit,
          sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }
          let unit = HKUnit.count().unitDivided(by: .minute())
          let values = (samples as? [HKQuantitySample] ?? []).compactMap {
            sample -> HealthWorkoutHeartRateSample? in
            let beatsPerMinute = sample.quantity.doubleValue(for: unit)
            guard beatsPerMinute > 0, beatsPerMinute.isFinite else { return nil }
            return HealthWorkoutHeartRateSample(
              id: sample.uuid.uuidString,
              startDate: sample.startDate,
              endDate: sample.endDate,
              beatsPerMinute: beatsPerMinute,
              provenance: Self.provenance(
                sourceRevision: sample.sourceRevision,
                device: sample.device))
          }
          continuation.resume(returning: values)
        }
        store.execute(query)
      }
    }

    private func fetchWorkouts(after pageToken: String?) async throws -> (
      workouts: [HealthWorkout], deletedHealthKitUUIDs: [String], nextPageToken: String?
    ) {
      let sampleType = HKObjectType.workoutType()
      return try await withCheckedThrowingContinuation { continuation in
        let query = HKAnchoredObjectQuery(
          type: sampleType,
          predicate: nil,
          anchor: Self.anchor(from: pageToken),
          limit: 100
        ) { _, samples, deletedObjects, anchor, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }
          let values = (samples as? [HKWorkout] ?? []).map { workout in
            Self.map(workout)
          }
          let deleted = (deletedObjects ?? []).map(\.uuid.uuidString)
          continuation.resume(
            returning: (values, deleted, Self.token(for: anchor)))
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

    private static func readTypes(_ type: HealthReadType) -> [HKObjectType] {
      switch type {
      case .workouts: [HKObjectType.workoutType()]
      case .heartRate: [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap { $0 }
      case .distance:
        [
          HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
          HKObjectType.quantityType(forIdentifier: .distanceCycling),
          HKObjectType.quantityType(forIdentifier: .distanceSwimming),
          HKObjectType.quantityType(forIdentifier: .distanceWheelchair),
        ].compactMap { $0 }
      case .activeEnergy:
        [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap { $0 }
      case .sleep: [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)].compactMap { $0 }
      case .restingHeartRate:
        [HKObjectType.quantityType(forIdentifier: .restingHeartRate)].compactMap { $0 }
      case .heartRateVariability:
        [HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)].compactMap { $0 }
      }
    }

    private static func distanceMeters(from workout: HKWorkout) -> Double? {
      let types: [HKQuantityTypeIdentifier] = [
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceWheelchair,
      ]
      let values = types.compactMap { identifier -> Double? in
        guard let type = HKObjectType.quantityType(forIdentifier: identifier),
          let quantity = workout.statistics(for: type)?.sumQuantity()
        else { return nil }
        let value = quantity.doubleValue(for: .meter())
        return value > 0 && value.isFinite ? value : nil
      }
      let total = values.reduce(0, +)
      return total > 0 ? total : nil
    }

    private static func activeEnergyKilocalories(from workout: HKWorkout) -> Double? {
      guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
        let quantity = workout.statistics(for: type)?.sumQuantity()
      else { return nil }
      let value = quantity.doubleValue(for: .kilocalorie())
      return value > 0 && value.isFinite ? value : nil
    }

    private static func provenance(
      sourceRevision: HKSourceRevision,
      device: HKDevice?
    ) -> HealthSampleProvenance {
      let version = sourceRevision.operatingSystemVersion
      return HealthSampleProvenance(
        sourceName: sourceRevision.source.name,
        sourceBundleIdentifier: sourceRevision.source.bundleIdentifier,
        sourceProductType: sourceRevision.productType,
        sourceOSVersion:
          "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
        deviceName: device?.name,
        deviceModel: device?.model)
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

public enum HealthKitAdapterError: Error, Equatable, Sendable {
  case unavailable
  case observerRegistrationFailed
}
