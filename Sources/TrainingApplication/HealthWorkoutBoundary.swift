import Foundation

public enum TrainingEventLocalEntityKind: String, Codable, Equatable, Sendable {
  case session
}

/// An authoritative association between a local record and a HealthKit
/// object. It remains outside the rebuildable mirror so a returning Health
/// object reconnects to the same local fact without recreating history.
public struct HealthWorkoutLinkFact: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let healthKitUUID: String
  public let localEntityKind: TrainingEventLocalEntityKind
  public let localEntityID: String
  public let linkedAt: Date
  public let linkedDuringCompletion: Bool
  public let writeBackDisposition: TrainingEventWriteBackDisposition
  public let unlinkedAt: Date?

  public init(
    id: String,
    healthKitUUID: String,
    localEntityKind: TrainingEventLocalEntityKind,
    localEntityID: String,
    linkedAt: Date = Date(),
    linkedDuringCompletion: Bool = false,
    writeBackDisposition: TrainingEventWriteBackDisposition = .notApplicable,
    unlinkedAt: Date? = nil
  ) {
    self.id = id
    self.healthKitUUID = healthKitUUID
    self.localEntityKind = localEntityKind
    self.localEntityID = localEntityID
    self.linkedAt = linkedAt
    self.linkedDuringCompletion = linkedDuringCompletion
    self.writeBackDisposition = writeBackDisposition
    self.unlinkedAt = unlinkedAt
  }

  public var isActive: Bool { unlinkedAt == nil }
}

public enum TrainingEventWriteBackDisposition: String, Codable, Equatable, Sendable {
  case notApplicable
  case suppressedExternalWorkoutLinkedAtCompletion
}

/// The read surface requested by the first Health connection.  These are
/// application-owned values; HealthKit types never cross this boundary.
public enum HealthReadType: String, CaseIterable, Codable, Equatable, Sendable {
  case workouts
  case heartRate
  case distance
  case activeEnergy
  case sleep
  case restingHeartRate
  case heartRateVariability

  public var displayName: String {
    switch self {
    case .workouts: "Health Workouts"
    case .heartRate: "Workout heart rate"
    case .distance: "Workout distance"
    case .activeEnergy: "Active energy"
    case .sleep: "Sleep"
    case .restingHeartRate: "Resting heart rate"
    case .heartRateVariability: "Heart-rate variability (SDNN)"
    }
  }
}

public struct HealthAuthorizationRequest: Codable, Equatable, Sendable {
  public let readTypes: [HealthReadType]
  public let writeTypes: [HealthWriteType]

  public init(
    readTypes: [HealthReadType] = HealthReadType.allCases,
    writeTypes: [HealthWriteType] = []
  ) {
    self.readTypes = readTypes
    self.writeTypes = writeTypes
  }

  public static let core = HealthAuthorizationRequest(
    readTypes: [
      .workouts, .heartRate, .distance, .activeEnergy, .sleep, .restingHeartRate,
      .heartRateVariability,
    ],
    writeTypes: []
  )
}

public enum HealthWriteType: String, CaseIterable, Codable, Equatable, Sendable {
  case workouts

  public var displayName: String { "Write-back workouts" }
}

public enum HealthAuthorizationState: String, Codable, Equatable, Sendable {
  case notRequested
  case authorized
  case postponed
  case unavailable
}

public struct HealthAuthorizationSnapshot: Codable, Equatable, Sendable {
  public let state: HealthAuthorizationState
  public let requested: HealthAuthorizationRequest
  /// HealthKit may positively report that only a recent window is available.
  public let hasLimitedHistory: Bool

  public init(
    state: HealthAuthorizationState,
    requested: HealthAuthorizationRequest = .core,
    hasLimitedHistory: Bool = false
  ) {
    self.state = state
    self.requested = requested
    self.hasLimitedHistory = hasLimitedHistory
  }
}

public enum HealthWorkoutTimeZoneSource: String, Codable, Equatable, Sendable {
  case sourceMetadata
  case deviceAtFirstImport
  case unavailable

  public var displayName: String {
    switch self {
    case .sourceMetadata: "Source timezone metadata"
    case .deviceAtFirstImport: "Device timezone at first import"
    case .unavailable: "Timezone unavailable"
    }
  }
}

public typealias HealthWorkoutEnvironment = RunningEnvironment

/// A privacy-safe, reconstructible representation of one HealthKit workout.
/// The HealthKit UUID is the mirror identity; source and device fields are
/// optional because older HealthKit objects do not always provide them.
public struct HealthWorkout: Codable, Equatable, Sendable, Identifiable {
  public let healthKitUUID: String
  public let activityType: String
  public let startDate: Date
  public let endDate: Date
  public let duration: TimeInterval
  public let sourceName: String?
  public let sourceBundleIdentifier: String?
  public let sourceProductType: String?
  public let sourceOSVersion: String?
  public let deviceName: String?
  public let deviceModel: String?
  public let sourceTimeZoneIdentifier: String?
  public let localDate: String
  public let timeZoneSource: HealthWorkoutTimeZoneSource
  /// Source-owned running context.  Unspecified is retained when Health did
  /// not provide an environment rather than inferred from the activity name.
  public let runningEnvironment: RunningEnvironment
  public let elevationMeters: Double?
  public let firstImportedAt: Date
  public let reconciliationContext: String?

  public var id: String { healthKitUUID }

  public init(
    healthKitUUID: String,
    activityType: String,
    startDate: Date,
    endDate: Date,
    duration: TimeInterval,
    sourceName: String? = nil,
    sourceBundleIdentifier: String? = nil,
    sourceProductType: String? = nil,
    sourceOSVersion: String? = nil,
    deviceName: String? = nil,
    deviceModel: String? = nil,
    sourceTimeZoneIdentifier: String? = nil,
    localDate: String? = nil,
    timeZoneSource: HealthWorkoutTimeZoneSource = .unavailable,
    runningEnvironment: RunningEnvironment = .unspecified,
    elevationMeters: Double? = nil,
    firstImportedAt: Date = Date(),
    reconciliationContext: String? = nil
  ) {
    precondition(!healthKitUUID.isEmpty, "HealthKit UUID must be stable and non-empty")
    precondition(endDate >= startDate, "Workout end must not precede its start")
    self.healthKitUUID = healthKitUUID
    self.activityType = activityType
    self.startDate = startDate
    self.endDate = endDate
    self.duration = max(0, duration)
    self.sourceName = sourceName
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.sourceProductType = sourceProductType
    self.sourceOSVersion = sourceOSVersion
    self.deviceName = deviceName
    self.deviceModel = deviceModel
    self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
    self.localDate =
      localDate ?? Self.localDate(for: startDate, timeZoneIdentifier: sourceTimeZoneIdentifier)
    self.timeZoneSource = timeZoneSource
    self.runningEnvironment = runningEnvironment
    self.elevationMeters =
      elevationMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    self.firstImportedAt = firstImportedAt
    self.reconciliationContext = reconciliationContext
  }

  /// Source-compatible initializer retained for callers that predate the
  /// running environment field.
  public init(
    healthKitUUID: String,
    activityType: String,
    startDate: Date,
    endDate: Date,
    duration: TimeInterval,
    sourceName: String? = nil,
    sourceBundleIdentifier: String? = nil,
    sourceProductType: String? = nil,
    sourceOSVersion: String? = nil,
    deviceName: String? = nil,
    deviceModel: String? = nil,
    sourceTimeZoneIdentifier: String? = nil,
    localDate: String? = nil,
    timeZoneSource: HealthWorkoutTimeZoneSource = .unavailable,
    firstImportedAt: Date = Date(),
    reconciliationContext: String? = nil
  ) {
    self.init(
      healthKitUUID: healthKitUUID,
      activityType: activityType,
      startDate: startDate,
      endDate: endDate,
      duration: duration,
      sourceName: sourceName,
      sourceBundleIdentifier: sourceBundleIdentifier,
      sourceProductType: sourceProductType,
      sourceOSVersion: sourceOSVersion,
      deviceName: deviceName,
      deviceModel: deviceModel,
      sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
      localDate: localDate,
      timeZoneSource: timeZoneSource,
      runningEnvironment: .unspecified,
      elevationMeters: nil,
      firstImportedAt: firstImportedAt,
      reconciliationContext: reconciliationContext)
  }

  public init(
    healthKitUUID: String,
    activityType: String,
    startDate: Date,
    endDate: Date,
    duration: TimeInterval,
    sourceName: String? = nil,
    sourceBundleIdentifier: String? = nil,
    sourceProductType: String? = nil,
    sourceOSVersion: String? = nil,
    deviceName: String? = nil,
    deviceModel: String? = nil,
    sourceTimeZoneIdentifier: String? = nil,
    localDate: String? = nil,
    timeZoneSource: HealthWorkoutTimeZoneSource = .unavailable,
    environment: RunningEnvironment,
    elevationMeters: Double? = nil,
    firstImportedAt: Date = Date(),
    reconciliationContext: String? = nil
  ) {
    self.init(
      healthKitUUID: healthKitUUID,
      activityType: activityType,
      startDate: startDate,
      endDate: endDate,
      duration: duration,
      sourceName: sourceName,
      sourceBundleIdentifier: sourceBundleIdentifier,
      sourceProductType: sourceProductType,
      sourceOSVersion: sourceOSVersion,
      deviceName: deviceName,
      deviceModel: deviceModel,
      sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
      localDate: localDate,
      timeZoneSource: timeZoneSource,
      runningEnvironment: environment,
      elevationMeters: elevationMeters,
      firstImportedAt: firstImportedAt,
      reconciliationContext: reconciliationContext)
  }

  public var environment: RunningEnvironment { runningEnvironment }
  public var sourceEnvironment: RunningEnvironment { runningEnvironment }

  private enum CodingKeys: String, CodingKey {
    case healthKitUUID, activityType, startDate, endDate, duration
    case sourceName, sourceBundleIdentifier, sourceProductType, sourceOSVersion
    case deviceName, deviceModel, sourceTimeZoneIdentifier, localDate, timeZoneSource
    case runningEnvironment, elevationMeters, firstImportedAt, reconciliationContext
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      healthKitUUID: try container.decode(String.self, forKey: .healthKitUUID),
      activityType: try container.decode(String.self, forKey: .activityType),
      startDate: try container.decode(Date.self, forKey: .startDate),
      endDate: try container.decode(Date.self, forKey: .endDate),
      duration: try container.decode(TimeInterval.self, forKey: .duration),
      sourceName: try container.decodeIfPresent(String.self, forKey: .sourceName),
      sourceBundleIdentifier: try container.decodeIfPresent(
        String.self, forKey: .sourceBundleIdentifier),
      sourceProductType: try container.decodeIfPresent(String.self, forKey: .sourceProductType),
      sourceOSVersion: try container.decodeIfPresent(String.self, forKey: .sourceOSVersion),
      deviceName: try container.decodeIfPresent(String.self, forKey: .deviceName),
      deviceModel: try container.decodeIfPresent(String.self, forKey: .deviceModel),
      sourceTimeZoneIdentifier: try container.decodeIfPresent(
        String.self, forKey: .sourceTimeZoneIdentifier),
      localDate: try container.decode(String.self, forKey: .localDate),
      timeZoneSource: try container.decode(
        HealthWorkoutTimeZoneSource.self, forKey: .timeZoneSource),
      runningEnvironment: try container.decodeIfPresent(
        RunningEnvironment.self, forKey: .runningEnvironment) ?? .unspecified,
      elevationMeters: try container.decodeIfPresent(Double.self, forKey: .elevationMeters),
      firstImportedAt: try container.decode(Date.self, forKey: .firstImportedAt),
      reconciliationContext: try container.decodeIfPresent(
        String.self, forKey: .reconciliationContext))
  }

  private static func localDate(for date: Date, timeZoneIdentifier: String?) -> String {
    var calendar = Calendar(identifier: .gregorian)
    if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
      calendar.timeZone = timeZone
    }
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }
}

public enum HealthWorkoutEnrichmentState: String, Codable, Equatable, Sendable {
  case loading
  case available
  case notAvailableFromHealth
  case failed

  public var displayName: String {
    switch self {
    case .loading: "Loading"
    case .available: "Available"
    case .notAvailableFromHealth: "Not available from Health"
    case .failed: "Update failed"
    }
  }
}

public struct HealthSampleProvenance: Codable, Equatable, Sendable {
  public let sourceName: String?
  public let sourceBundleIdentifier: String?
  public let sourceProductType: String?
  public let sourceOSVersion: String?
  public let deviceName: String?
  public let deviceModel: String?

  public init(
    sourceName: String? = nil,
    sourceBundleIdentifier: String? = nil,
    sourceProductType: String? = nil,
    sourceOSVersion: String? = nil,
    deviceName: String? = nil,
    deviceModel: String? = nil
  ) {
    self.sourceName = sourceName
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.sourceProductType = sourceProductType
    self.sourceOSVersion = sourceOSVersion
    self.deviceName = deviceName
    self.deviceModel = deviceModel
  }

  public var displayName: String {
    sourceName ?? sourceProductType ?? deviceName ?? sourceBundleIdentifier ?? "Source unavailable"
  }
}

/// A source-owned observed interval. No interval is synthesized between
/// samples or extended to the workout edges.
public struct HealthWorkoutHeartRateSample: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let startDate: Date
  public let endDate: Date
  public let beatsPerMinute: Double
  public let provenance: HealthSampleProvenance

  public init(
    id: String,
    startDate: Date,
    endDate: Date,
    beatsPerMinute: Double,
    provenance: HealthSampleProvenance = .init()
  ) {
    precondition(!id.isEmpty)
    precondition(endDate >= startDate)
    precondition(beatsPerMinute > 0 && beatsPerMinute.isFinite)
    self.id = id
    self.startDate = startDate
    self.endDate = endDate
    self.beatsPerMinute = beatsPerMinute
    self.provenance = provenance
  }
}

public struct HealthWorkoutHeartRateDetail: Codable, Equatable, Sendable {
  public let state: HealthWorkoutEnrichmentState
  public let samples: [HealthWorkoutHeartRateSample]
  public let lastSuccessfulCheck: Date?
  public let reconciliationContext: String?
  public let failureCode: String?

  private init(
    state: HealthWorkoutEnrichmentState,
    samples: [HealthWorkoutHeartRateSample] = [],
    lastSuccessfulCheck: Date? = nil,
    reconciliationContext: String? = nil,
    failureCode: String? = nil
  ) {
    self.state = state
    self.samples = samples.sorted {
      if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
      return $0.id < $1.id
    }
    self.lastSuccessfulCheck = lastSuccessfulCheck
    self.reconciliationContext = reconciliationContext
    self.failureCode = failureCode
  }

  public static let loading = HealthWorkoutHeartRateDetail(state: .loading)

  public static func available(
    samples: [HealthWorkoutHeartRateSample],
    checkedAt: Date,
    reconciliationContext: String
  ) -> Self {
    guard !samples.isEmpty else {
      return .notAvailableFromHealth(
        checkedAt: checkedAt, reconciliationContext: reconciliationContext)
    }
    return .init(
      state: .available,
      samples: samples,
      lastSuccessfulCheck: checkedAt,
      reconciliationContext: reconciliationContext)
  }

  public static func notAvailableFromHealth(
    checkedAt: Date,
    reconciliationContext: String
  ) -> Self {
    .init(
      state: .notAvailableFromHealth,
      lastSuccessfulCheck: checkedAt,
      reconciliationContext: reconciliationContext)
  }

  public static func failed(code: String) -> Self {
    .init(state: .failed, failureCode: code)
  }

  fileprivate func preservingLastSuccess(from cached: Self?) -> Self {
    guard state == .failed, let cached else { return self }
    return .init(
      state: .failed,
      samples: cached.samples,
      lastSuccessfulCheck: cached.lastSuccessfulCheck,
      reconciliationContext: cached.reconciliationContext,
      failureCode: failureCode)
  }
}

public enum HealthWorkoutQuantityUnit: String, Codable, Equatable, Sendable {
  case meters
  case kilocalories
}

public struct HealthWorkoutQuantity: Codable, Equatable, Sendable {
  public let value: Double
  public let unit: HealthWorkoutQuantityUnit
  public let provenance: HealthSampleProvenance

  public init(
    value: Double,
    unit: HealthWorkoutQuantityUnit,
    provenance: HealthSampleProvenance = .init()
  ) {
    precondition(value > 0 && value.isFinite)
    self.value = value
    self.unit = unit
    self.provenance = provenance
  }
}

public struct HealthWorkoutQuantityDetail: Codable, Equatable, Sendable {
  public let state: HealthWorkoutEnrichmentState
  public let quantity: HealthWorkoutQuantity?
  public let lastSuccessfulCheck: Date?
  public let reconciliationContext: String?
  public let failureCode: String?

  private init(
    state: HealthWorkoutEnrichmentState,
    quantity: HealthWorkoutQuantity? = nil,
    lastSuccessfulCheck: Date? = nil,
    reconciliationContext: String? = nil,
    failureCode: String? = nil
  ) {
    self.state = state
    self.quantity = quantity
    self.lastSuccessfulCheck = lastSuccessfulCheck
    self.reconciliationContext = reconciliationContext
    self.failureCode = failureCode
  }

  public static let loading = HealthWorkoutQuantityDetail(state: .loading)

  public static func available(
    value: Double,
    unit: HealthWorkoutQuantityUnit,
    provenance: HealthSampleProvenance = .init(),
    checkedAt: Date,
    reconciliationContext: String
  ) -> Self {
    guard value > 0, value.isFinite else {
      return .notAvailableFromHealth(
        checkedAt: checkedAt, reconciliationContext: reconciliationContext)
    }
    return .init(
      state: .available,
      quantity: .init(value: value, unit: unit, provenance: provenance),
      lastSuccessfulCheck: checkedAt,
      reconciliationContext: reconciliationContext)
  }

  public static func notAvailableFromHealth(
    checkedAt: Date,
    reconciliationContext: String
  ) -> Self {
    .init(
      state: .notAvailableFromHealth,
      lastSuccessfulCheck: checkedAt,
      reconciliationContext: reconciliationContext)
  }

  public static func failed(code: String) -> Self {
    .init(state: .failed, failureCode: code)
  }

  fileprivate func preservingLastSuccess(from cached: Self?) -> Self {
    guard state == .failed, let cached else { return self }
    return .init(
      state: .failed,
      quantity: cached.quantity,
      lastSuccessfulCheck: cached.lastSuccessfulCheck,
      reconciliationContext: cached.reconciliationContext,
      failureCode: failureCode)
  }
}

public struct HealthWorkoutEnrichment: Codable, Equatable, Sendable, Identifiable {
  public let healthKitUUID: String
  public let heartRate: HealthWorkoutHeartRateDetail
  public let distance: HealthWorkoutQuantityDetail
  public let activeEnergy: HealthWorkoutQuantityDetail

  public var id: String { healthKitUUID }

  public init(
    healthKitUUID: String,
    heartRate: HealthWorkoutHeartRateDetail,
    distance: HealthWorkoutQuantityDetail,
    activeEnergy: HealthWorkoutQuantityDetail
  ) {
    precondition(!healthKitUUID.isEmpty)
    self.healthKitUUID = healthKitUUID
    self.heartRate = heartRate
    self.distance = distance
    self.activeEnergy = activeEnergy
  }

  public static func loading(healthKitUUID: String) -> Self {
    .init(
      healthKitUUID: healthKitUUID,
      heartRate: .loading,
      distance: .loading,
      activeEnergy: .loading)
  }

  public func preservingFailedDetails(from cached: Self?) -> Self {
    guard cached?.healthKitUUID == healthKitUUID else { return self }
    return .init(
      healthKitUUID: healthKitUUID,
      heartRate: heartRate.preservingLastSuccess(from: cached?.heartRate),
      distance: distance.preservingLastSuccess(from: cached?.distance),
      activeEnergy: activeEnergy.preservingLastSuccess(from: cached?.activeEnergy))
  }
}

/// The source badge shown wherever an imported workout is presented.  It is
/// deliberately separate from the activity type so a Health workout cannot be
/// mistaken for a locally recorded 5/3/1 Session.
public enum TrainingEventSource: String, Codable, Equatable, Sendable {
  case localTraining
  case health

  public var displayName: String {
    switch self {
    case .localTraining: "5/3/1 Session"
    case .health: "Health"
    }
  }
}

public enum TrainingEventKind: String, Codable, Equatable, Sendable {
  case healthWorkout
}

/// A source-owned event projection.  This first event slice intentionally
/// contains only Health workouts; local Sessions remain independently owned by
/// the Session boundaries and are never inferred or linked here.
public struct TrainingEvent: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let kind: TrainingEventKind
  public let source: TrainingEventSource
  public let localDate: String
  public let startDate: Date
  public let endDate: Date
  public let duration: TimeInterval
  public let activityType: String
  public let healthKitUUID: String
  public let sourceName: String?
  public let sourceBundleIdentifier: String?
  public let sourceProductType: String?
  public let sourceOSVersion: String?
  public let deviceName: String?
  public let deviceModel: String?
  public let sourceTimeZoneIdentifier: String?
  public let timeZoneSource: HealthWorkoutTimeZoneSource
  public let reconciliationContext: String?
  public let lastSuccessfulReconciliation: Date?
  public let healthCoverage: HealthStreamCoverage
  /// Reserved for the explicit linking slice. It is nil for every event in
  /// this issue, making the no-automatic-link rule observable at the seam.
  public let localSessionID: String?

  public init(
    workout: HealthWorkout,
    reconciliationContext: String? = nil,
    lastSuccessfulReconciliation: Date? = nil,
    healthCoverage: HealthStreamCoverage = .unknown
  ) {
    self.id = workout.healthKitUUID
    self.kind = .healthWorkout
    self.source = .health
    self.localDate = workout.localDate
    self.startDate = workout.startDate
    self.endDate = workout.endDate
    self.duration = workout.duration
    self.activityType = workout.activityType
    self.healthKitUUID = workout.healthKitUUID
    self.sourceName = workout.sourceName
    self.sourceBundleIdentifier = workout.sourceBundleIdentifier
    self.sourceProductType = workout.sourceProductType
    self.sourceOSVersion = workout.sourceOSVersion
    self.deviceName = workout.deviceName
    self.deviceModel = workout.deviceModel
    self.sourceTimeZoneIdentifier = workout.sourceTimeZoneIdentifier
    self.timeZoneSource = workout.timeZoneSource
    self.reconciliationContext = reconciliationContext ?? workout.reconciliationContext
    self.lastSuccessfulReconciliation = lastSuccessfulReconciliation
    self.healthCoverage = healthCoverage
    self.localSessionID = nil
  }

  public var sourceBadge: String { source.displayName }
}

public struct HealthWorkoutProvenance: Codable, Equatable, Sendable {
  public let sourceName: String?
  public let sourceBundleIdentifier: String?
  public let sourceProductType: String?
  public let sourceOSVersion: String?
  public let deviceName: String?
  public let deviceModel: String?
  public let sourceTimeZoneIdentifier: String?
  public let timeZoneSource: HealthWorkoutTimeZoneSource

  public init(workout: HealthWorkout) {
    sourceName = workout.sourceName
    sourceBundleIdentifier = workout.sourceBundleIdentifier
    sourceProductType = workout.sourceProductType
    sourceOSVersion = workout.sourceOSVersion
    deviceName = workout.deviceName
    deviceModel = workout.deviceModel
    sourceTimeZoneIdentifier = workout.sourceTimeZoneIdentifier
    timeZoneSource = workout.timeZoneSource
  }

  public var isAvailable: Bool {
    sourceName != nil || sourceBundleIdentifier != nil || deviceName != nil
      || sourceProductType != nil || sourceOSVersion != nil || deviceModel != nil
      || sourceTimeZoneIdentifier != nil || timeZoneSource != .unavailable
  }

  public var displayName: String {
    sourceName ?? sourceProductType ?? deviceName ?? sourceBundleIdentifier
      ?? "Source unavailable"
  }

  public var detailLabel: String {
    var details: [String] = []
    if let sourceProductType { details.append(sourceProductType) }
    if let deviceName { details.append(deviceName) }
    if let deviceModel, deviceModel != deviceName { details.append(deviceModel) }
    if let sourceBundleIdentifier { details.append(sourceBundleIdentifier) }
    if let sourceOSVersion { details.append("OS \(sourceOSVersion)") }
    if let sourceTimeZoneIdentifier { details.append(sourceTimeZoneIdentifier) }
    if details.isEmpty { return "Provenance unavailable" }
    return details.joined(separator: " · ")
  }
}

public enum HealthWorkoutPresentationState: String, Codable, Equatable, Sendable {
  case loading
  case cached
  case available
  case successfulEmpty
  case limitedHistory
  case delayedUpdate
  case firstFailure
  case deleted
  case unavailableProvenance
  case unavailable

  public var displayName: String {
    switch self {
    case .loading: "Loading"
    case .cached: "Cached"
    case .available: "Available"
    case .successfulEmpty: "No Health data currently available"
    case .limitedHistory: "Limited history"
    case .delayedUpdate: "Update delayed"
    case .firstFailure: "First check failed"
    case .deleted: "Deleted in Health"
    case .unavailableProvenance: "Provenance unavailable"
    case .unavailable: "Health unavailable"
    }
  }
}

public struct HealthWorkoutHistoryEntry: Codable, Equatable, Identifiable, Sendable {
  public let event: TrainingEvent
  public let provenance: HealthWorkoutProvenance
  public let enrichment: HealthWorkoutEnrichment
  public let state: HealthWorkoutPresentationState

  public init(
    event: TrainingEvent,
    provenance: HealthWorkoutProvenance,
    enrichment: HealthWorkoutEnrichment? = nil,
    state: HealthWorkoutPresentationState
  ) {
    self.event = event
    self.provenance = provenance
    self.enrichment = enrichment ?? .loading(healthKitUUID: event.healthKitUUID)
    self.state = state
  }

  public var id: String { event.id }
  public var healthKitUUID: String { event.healthKitUUID }
}

public struct HealthWorkoutHistorySnapshot: Codable, Equatable, Sendable {
  public let events: [HealthWorkoutHistoryEntry]
  public let state: HealthWorkoutPresentationState
  public let lastSuccessfulReconciliation: Date?
  public let reconciliationContext: String?
  /// Deleted UUIDs are retained as reconciliation evidence but are never
  /// returned as current events.
  public let deletedHealthKitUUIDs: [String]

  public init(
    events: [HealthWorkoutHistoryEntry] = [],
    state: HealthWorkoutPresentationState,
    lastSuccessfulReconciliation: Date? = nil,
    reconciliationContext: String? = nil,
    deletedHealthKitUUIDs: [String] = []
  ) {
    self.events = events
    self.state = state
    self.lastSuccessfulReconciliation = lastSuccessfulReconciliation
    self.reconciliationContext = reconciliationContext
    self.deletedHealthKitUUIDs = deletedHealthKitUUIDs
  }
}

public struct HealthWorkoutPage: Codable, Equatable, Sendable {
  public let workouts: [HealthWorkout]
  /// Recovery samples are carried through the same bounded page/checkpoint
  /// envelope as workouts. Only the field matching the requested stream is
  /// populated by a production adapter.
  public let sleepSamples: [HealthSleepSample]
  public let restingHeartRateSamples: [HealthRestingHeartRateSample]
  public let heartRateVariabilitySamples: [HealthHRVSDNNSample]
  /// UUIDs returned by HealthKit's deleted-object collection.  Deletions are
  /// part of the same anchored page as additions and replacements.
  public let deletedHealthKitUUIDs: [String]
  public let nextPageToken: String?
  /// Durable stream anchor returned with this page.  Pagination tokens are
  /// separate so a real anchored query can finish after one bounded response.
  public let anchor: String?
  public let hasLimitedHistory: Bool
  public let reconciliationContext: String
  public let streamFacts: [HealthSyncFact]

  /// The page's durable checkpoint.  `nextPageToken` remains available for
  /// compatibility with the first Health import API.
  public var nextAnchor: String? { anchor ?? nextPageToken }

  public init(
    workouts: [HealthWorkout],
    nextPageToken: String? = nil,
    anchor: String? = nil,
    hasLimitedHistory: Bool = false,
    reconciliationContext: String = "initial",
    deletedHealthKitUUIDs: [String] = [],
    streamFacts: [HealthSyncFact] = [],
    sleepSamples: [HealthSleepSample] = [],
    restingHeartRateSamples: [HealthRestingHeartRateSample] = [],
    heartRateVariabilitySamples: [HealthHRVSDNNSample] = []
  ) {
    self.workouts = workouts
    self.sleepSamples = sleepSamples
    self.restingHeartRateSamples = restingHeartRateSamples
    self.heartRateVariabilitySamples = heartRateVariabilitySamples
    self.deletedHealthKitUUIDs = deletedHealthKitUUIDs
    self.nextPageToken = nextPageToken
    self.anchor = anchor
    self.hasLimitedHistory = hasLimitedHistory
    self.reconciliationContext = reconciliationContext
    self.streamFacts = streamFacts
  }

  /// Backward-compatible decoding for pages persisted or produced before
  /// Recovery Evidence fields were introduced.
  private enum CodingKeys: String, CodingKey {
    case workouts, sleepSamples, restingHeartRateSamples, heartRateVariabilitySamples
    case deletedHealthKitUUIDs, nextPageToken, anchor, hasLimitedHistory
    case reconciliationContext, streamFacts
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      workouts: try container.decodeIfPresent([HealthWorkout].self, forKey: .workouts) ?? [],
      nextPageToken: try container.decodeIfPresent(String.self, forKey: .nextPageToken),
      anchor: try container.decodeIfPresent(String.self, forKey: .anchor),
      hasLimitedHistory:
        try container.decodeIfPresent(Bool.self, forKey: .hasLimitedHistory) ?? false,
      reconciliationContext:
        try container.decodeIfPresent(String.self, forKey: .reconciliationContext) ?? "initial",
      deletedHealthKitUUIDs:
        try container.decodeIfPresent([String].self, forKey: .deletedHealthKitUUIDs) ?? [],
      streamFacts: try container.decodeIfPresent([HealthSyncFact].self, forKey: .streamFacts) ?? [],
      sleepSamples:
        try container.decodeIfPresent([HealthSleepSample].self, forKey: .sleepSamples) ?? [],
      restingHeartRateSamples: try container.decodeIfPresent(
        [HealthRestingHeartRateSample].self, forKey: .restingHeartRateSamples) ?? [],
      heartRateVariabilitySamples: try container.decodeIfPresent(
        [HealthHRVSDNNSample].self, forKey: .heartRateVariabilitySamples) ?? [])
  }

  public var recoverySamples: [HealthRecoverySample] {
    sleepSamples.map(HealthRecoverySample.sleep)
      + restingHeartRateSamples.map(HealthRecoverySample.restingHeartRate)
      + heartRateVariabilitySamples.map(HealthRecoverySample.heartRateVariability)
  }

  public func recoverySamples(for stream: HealthSyncStream) -> [HealthRecoverySample] {
    switch stream {
    case .sleep: sleepSamples.map(HealthRecoverySample.sleep)
    case .restingHeartRate: restingHeartRateSamples.map(HealthRecoverySample.restingHeartRate)
    case .heartRateVariability:
      heartRateVariabilitySamples.map(HealthRecoverySample.heartRateVariability)
    default: []
    }
  }
}

/// A small, reconstructible fact ledger for an anchored Health stream.  Facts
/// are deliberately application-owned and contain no HealthKit objects.
public struct HealthSyncFact: Codable, Equatable, Sendable, Identifiable {
  public enum Kind: String, Codable, Equatable, Sendable {
    case added
    case replaced
    case deleted
  }

  public let id: String
  public let kind: Kind
  public let healthKitUUID: String
  public let observedAt: Date

  public init(
    id: String? = nil,
    kind: Kind,
    healthKitUUID: String,
    observedAt: Date = Date()
  ) {
    self.id = id ?? "\(kind.rawValue):\(healthKitUUID):\(observedAt.timeIntervalSince1970)"
    self.kind = kind
    self.healthKitUUID = healthKitUUID
    self.observedAt = observedAt
  }
}

public enum HealthSyncStream: String, Codable, Equatable, Sendable, CaseIterable {
  case workouts
  case heartRate
  case distance
  case activeEnergy
  case sleep
  case restingHeartRate
  case heartRateVariability

  public init(_ type: HealthReadType) {
    switch type {
    case .workouts: self = .workouts
    case .heartRate: self = .heartRate
    case .distance: self = .distance
    case .activeEnergy: self = .activeEnergy
    case .sleep: self = .sleep
    case .restingHeartRate: self = .restingHeartRate
    case .heartRateVariability: self = .heartRateVariability
    }
  }

  public var readType: HealthReadType {
    switch self {
    case .workouts: .workouts
    case .heartRate: .heartRate
    case .distance: .distance
    case .activeEnergy: .activeEnergy
    case .sleep: .sleep
    case .restingHeartRate: .restingHeartRate
    case .heartRateVariability: .heartRateVariability
    }
  }

  public var displayName: String { readType.displayName }
}

public enum HealthStreamReconciliationState: String, Codable, Equatable, Sendable {
  case idle
  case updating
}

public enum HealthStreamCoverage: String, Codable, Equatable, Sendable {
  case unknown
  case limitedHistory
  case available

  public var displayName: String {
    switch self {
    case .unknown: "History not established"
    case .limitedHistory: "Limited recent history"
    case .available: "History available"
    }
  }
}

public enum HealthMirrorContent: String, Codable, Equatable, Sendable {
  case unknown
  case empty
  case available

  public var displayName: String {
    switch self {
    case .unknown: "Mirror availability not established"
    case .empty: "No mirrored content"
    case .available: "Mirrored content available"
    }
  }
}

/// A privacy-safe, per-stream failure.  The underlying HealthKit error is
/// intentionally not retained because it can expose device or account data.
public struct HealthStreamFailure: Codable, Equatable, Sendable {
  public let occurredAt: Date
  public let code: String

  public init(code: String, occurredAt: Date = Date()) {
    self.code = code
    self.occurredAt = occurredAt
  }
}

public struct HealthStreamStatus: Codable, Equatable, Sendable, Identifiable {
  public let stream: HealthSyncStream
  public let requested: Bool
  public let authorization: HealthAuthorizationState
  public let coverage: HealthStreamCoverage
  public let mirroredContent: HealthMirrorContent
  public let reconciliation: HealthStreamReconciliationState
  public let lastSuccessfulCheck: Date?
  public let failure: HealthStreamFailure?
  public let attemptCount: Int

  public var id: HealthSyncStream { stream }

  public init(
    stream: HealthSyncStream,
    requested: Bool = true,
    authorization: HealthAuthorizationState = .notRequested,
    coverage: HealthStreamCoverage = .unknown,
    mirroredContent: HealthMirrorContent = .unknown,
    reconciliation: HealthStreamReconciliationState = .idle,
    lastSuccessfulCheck: Date? = nil,
    failure: HealthStreamFailure? = nil,
    attemptCount: Int = 0
  ) {
    self.stream = stream
    self.requested = requested
    self.authorization = authorization
    self.coverage = coverage
    self.mirroredContent = mirroredContent
    self.reconciliation = reconciliation
    self.lastSuccessfulCheck = lastSuccessfulCheck
    self.failure = failure
    self.attemptCount = attemptCount
  }

  public var isUpdating: Bool { reconciliation == .updating }

  /// A cached observation is current only when its stream completed a
  /// successful reconciliation on the same local calendar day. The sample's
  /// own timestamp is deliberately not used as a freshness signal.
  public func isCurrent(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard requested, let lastSuccessfulCheck else { return false }
    return calendar.isDate(lastSuccessfulCheck, inSameDayAs: date)
      && reconciliation == .idle && failure == nil
  }

  public var isCurrentToday: Bool { isCurrent() }

  /// Compact copy suitable for a status row.  It deliberately describes the
  /// last check, not the timestamp of the newest sample.
  public var statusLabel: String {
    if !requested { return "Not requested" }
    if authorization == .unavailable { return "Unavailable" }
    if isUpdating { return "Updating" }
    if let failure {
      return lastSuccessfulCheck == nil
        ? "Attention: first check failed (\(failure.code))"
        : "Attention: refresh failed; cached data remains available"
    }
    if lastSuccessfulCheck == nil { return "Not checked yet" }
    if mirroredContent == .empty { return "Checked · successful empty" }
    if coverage == .limitedHistory { return "Checked · limited history" }
    return "Checked"
  }

  public var lastCheckedLabel: String {
    guard let lastSuccessfulCheck else { return "Last checked: Never" }
    return "Last checked: \(lastSuccessfulCheck.formatted(date: .abbreviated, time: .shortened))"
  }

  public var historyLabel: String { "History: \(coverage.displayName)" }
  public var contentLabel: String { "Content: \(mirroredContent.displayName)" }

  public var attentionLabel: String? {
    if let failure {
      return lastSuccessfulCheck == nil
        ? "First check failed (\(failure.code)); try Refresh Health Data."
        : "Refresh failed; cached data remains available. Try Refresh Health Data again."
    }
    if coverage == .limitedHistory { return "Health reports limited history." }
    return nil
  }
}

public struct HealthDataStatus: Codable, Equatable, Sendable {
  public let authorization: HealthAuthorizationSnapshot
  public let streams: [HealthStreamStatus]

  public init(
    authorization: HealthAuthorizationSnapshot = .init(state: .notRequested),
    streams: [HealthStreamStatus] = []
  ) {
    self.authorization = authorization
    self.streams = streams.sorted { $0.stream.rawValue < $1.stream.rawValue }
  }

  public var isUpdating: Bool { streams.contains { $0.isUpdating } }
  public var hasActionableAttention: Bool { streams.contains { $0.attentionLabel != nil } }
  public var requestedStreams: [HealthStreamStatus] { streams.filter(\.requested) }

  public func currentStreams(on date: Date = Date(), calendar: Calendar = .current)
    -> [HealthStreamStatus]
  {
    streams.filter { $0.isCurrent(on: date, calendar: calendar) }
  }
}

public struct HealthSyncCheckpoint: Codable, Equatable, Sendable {
  public let stream: HealthSyncStream
  public let anchor: String?
  public let hasLimitedHistory: Bool
  public let reconciliationContext: String
  public let committedAt: Date

  public init(
    stream: HealthSyncStream,
    anchor: String?,
    hasLimitedHistory: Bool = false,
    reconciliationContext: String = "initial",
    committedAt: Date = Date()
  ) {
    self.stream = stream
    self.anchor = anchor
    self.hasLimitedHistory = hasLimitedHistory
    self.reconciliationContext = reconciliationContext
    self.committedAt = committedAt
  }
}

public struct HealthSyncBatchLimits: Codable, Equatable, Sendable {
  public let maxRecords: Int
  public let maxBytes: Int
  public let maxTransactionBytes: Int
  public let maxTransientBufferBytes: Int

  public init(
    maxRecords: Int = 100,
    maxBytes: Int = 1_048_576,
    maxTransactionBytes: Int = 4_194_304,
    maxTransientBufferBytes: Int = 8_388_608
  ) {
    precondition(maxRecords > 0)
    precondition(maxBytes > 0)
    precondition(maxTransactionBytes >= maxBytes)
    precondition(maxTransientBufferBytes >= maxTransactionBytes)
    self.maxRecords = maxRecords
    self.maxBytes = maxBytes
    self.maxTransactionBytes = maxTransactionBytes
    self.maxTransientBufferBytes = maxTransientBufferBytes
  }

  public static let `default` = HealthSyncBatchLimits()

  public func validate(page: HealthWorkoutPage) throws {
    let records =
      page.workouts.count + page.recoverySamples.count
      + page.deletedHealthKitUUIDs.count
    guard records <= maxRecords else { throw HealthSyncError.batchTooLarge }
    let encoded = try JSONEncoder().encode(page)
    guard encoded.count <= maxBytes,
      encoded.count <= maxTransactionBytes,
      encoded.count <= maxTransientBufferBytes
    else { throw HealthSyncError.batchTooLarge }
  }
}

public enum HealthSyncTrigger: String, Codable, Equatable, Sendable {
  case foreground
  case observer
  case unlock
  case retry
  case manualInvalidation
  case coalesced
}

public struct HealthSyncResult: Codable, Equatable, Sendable {
  public let trigger: HealthSyncTrigger
  public let pagesCommitted: Int
  public let additionsOrReplacements: Int
  public let deletions: Int
  public let checkpoint: HealthSyncCheckpoint?
  public let streamStatuses: [HealthStreamStatus]

  public init(
    trigger: HealthSyncTrigger,
    pagesCommitted: Int,
    additionsOrReplacements: Int,
    deletions: Int,
    checkpoint: HealthSyncCheckpoint?,
    streamStatuses: [HealthStreamStatus] = []
  ) {
    self.trigger = trigger
    self.pagesCommitted = pagesCommitted
    self.additionsOrReplacements = additionsOrReplacements
    self.deletions = deletions
    self.checkpoint = checkpoint
    self.streamStatuses = streamStatuses
  }
}

public protocol HealthWorkoutClient: HealthKitClient {
  func requestHealthAuthorization(_ request: HealthAuthorizationRequest) async throws
    -> HealthAuthorizationSnapshot
  func registerWorkoutObserver(
    onInvalidation: @escaping @Sendable () async -> Void
  ) async throws
  func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage
  func fetchHealthPage(
    for stream: HealthSyncStream, after pageToken: String?
  ) async throws -> HealthWorkoutPage
  func fetchWorkoutEnrichment(for workout: HealthWorkout) async -> HealthWorkoutEnrichment?
}

extension HealthWorkoutClient {
  /// Lightweight clients and deterministic test adapters may omit background
  /// delivery. The production HealthKit adapter overrides this seam.
  public func registerWorkoutObserver(
    onInvalidation: @escaping @Sendable () async -> Void
  ) async throws {}

  /// A client that only has the original workout seam can still participate in
  /// the status screen. Unsupported streams fail independently rather than
  /// being misrepresented as a successful empty Health result.
  public func fetchHealthPage(
    for stream: HealthSyncStream, after pageToken: String?
  ) async throws -> HealthWorkoutPage {
    guard stream == .workouts else { throw HealthSyncError.unavailable }
    return try await fetchWorkoutPage(after: pageToken)
  }

  public func fetchWorkoutEnrichment(for workout: HealthWorkout) async -> HealthWorkoutEnrichment? {
    nil
  }
}

public struct HealthMirrorContentSnapshot: Codable, Equatable, Sendable {
  public let stream: HealthSyncStream
  public let recordCount: Int?

  public init(stream: HealthSyncStream, recordCount: Int?) {
    self.stream = stream
    self.recordCount = recordCount
  }

  public var availability: HealthMirrorContent {
    guard let recordCount else { return .unknown }
    return recordCount > 0 ? .available : .empty
  }
}

public protocol HealthWorkoutRepository: Sendable {
  func upsertHealthWorkouts(_ workouts: [HealthWorkout], reconciliationContext: String) async throws
  func loadHealthWorkouts() async throws -> [HealthWorkout]
  func commitHealthWorkoutPage(
    _ page: HealthWorkoutPage,
    stream: HealthSyncStream,
    limits: HealthSyncBatchLimits
  ) async throws
  func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws -> HealthSyncCheckpoint?
  func loadHealthMirrorContent(for stream: HealthSyncStream) async throws
    -> HealthMirrorContentSnapshot
  func loadHealthWorkoutDeletionUUIDs() async throws -> [String]
  func saveHealthWorkoutEnrichment(_ enrichment: HealthWorkoutEnrichment) async throws
  func loadHealthWorkoutEnrichment(for healthKitUUID: String) async throws
    -> HealthWorkoutEnrichment?
  func loadHealthRebuildState() async throws -> HealthRebuildState?
  func beginHealthRebuild() async throws
  func updateHealthRebuildState(_ state: HealthRebuildState) async throws
  func regenerateHealthDerivedProjections() async throws
  func estimateHealthRebuildStorage(
    policy: HealthRebuildStoragePolicy
  ) async throws -> HealthRebuildStorageEstimate
  func loadHealthWorkoutLinkFacts(for healthKitUUID: String?) async throws
    -> [HealthWorkoutLinkFact]
  func upsertHealthRecoverySamples(
    _ samples: [HealthRecoverySample], stream: HealthSyncStream, reconciliationContext: String
  ) async throws
  func loadHealthRecoverySamples(for stream: HealthSyncStream) async throws
    -> [HealthRecoverySample]
}

extension HealthWorkoutRepository {
  /// Compatibility fallback for repositories that predate anchored
  /// reconciliation.  Production persistence overrides this with one DB
  /// transaction; test doubles can continue to implement only the original
  /// upsert/load surface.
  public func commitHealthWorkoutPage(
    _ page: HealthWorkoutPage,
    stream: HealthSyncStream,
    limits: HealthSyncBatchLimits
  ) async throws {
    try limits.validate(page: page)
    if stream == .workouts && !page.workouts.isEmpty {
      try await upsertHealthWorkouts(
        page.workouts, reconciliationContext: page.reconciliationContext)
    }
    let recovery = page.recoverySamples(for: stream)
    if !recovery.isEmpty {
      try await upsertHealthRecoverySamples(
        recovery, stream: stream, reconciliationContext: page.reconciliationContext)
    }
  }

  public func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws
    -> HealthSyncCheckpoint?
  {
    nil
  }

  public func loadHealthMirrorContent(for stream: HealthSyncStream) async throws
    -> HealthMirrorContentSnapshot
  {
    .init(stream: stream, recordCount: nil)
  }

  public func loadHealthWorkoutDeletionUUIDs() async throws -> [String] { [] }

  public func saveHealthWorkoutEnrichment(_ enrichment: HealthWorkoutEnrichment) async throws {}

  public func loadHealthWorkoutEnrichment(for healthKitUUID: String) async throws
    -> HealthWorkoutEnrichment?
  { nil }

  public func loadHealthRebuildState() async throws -> HealthRebuildState? {
    throw HealthSyncError.unavailable
  }

  public func beginHealthRebuild() async throws {
    throw HealthSyncError.unavailable
  }

  public func updateHealthRebuildState(_ state: HealthRebuildState) async throws {
    throw HealthSyncError.unavailable
  }

  public func regenerateHealthDerivedProjections() async throws {
    throw HealthSyncError.unavailable
  }

  public func estimateHealthRebuildStorage(
    policy: HealthRebuildStoragePolicy
  ) async throws -> HealthRebuildStorageEstimate {
    try await DefaultHealthRebuildStorageProvider().estimateHealthRebuildStorage(policy: policy)
  }

  public func loadHealthWorkoutLinkFacts(for healthKitUUID: String?) async throws
    -> [HealthWorkoutLinkFact]
  { throw HealthSyncError.unavailable }

  public func upsertHealthRecoverySamples(
    _ samples: [HealthRecoverySample], stream: HealthSyncStream, reconciliationContext: String
  ) async throws {}

  public func loadHealthRecoverySamples(for stream: HealthSyncStream) async throws
    -> [HealthRecoverySample]
  { [] }

}

public enum HealthSyncError: Error, Equatable, Sendable {
  case batchTooLarge
  case unavailable
}

public enum HealthWorkoutImportState: String, Codable, Equatable, Sendable {
  case notRequested
  case loading
  case cached
  case available
  case successfulEmpty
  case limitedHistory
  case postponed
  case unavailable
  case failed
}

public struct HealthWorkoutImportProgress: Equatable, Sendable {
  public let importedCount: Int
  public let firstBatchVisible: Bool
  public let isComplete: Bool
  public let state: HealthWorkoutImportState

  public init(
    importedCount: Int,
    firstBatchVisible: Bool,
    isComplete: Bool,
    state: HealthWorkoutImportState
  ) {
    self.importedCount = importedCount
    self.firstBatchVisible = firstBatchVisible
    self.isComplete = isComplete
    self.state = state
  }
}

public struct HealthWorkoutImportResult: Equatable, Sendable {
  public let state: HealthWorkoutImportState
  public let importedCount: Int
  public let visibleWorkouts: [HealthWorkout]
  public let hasLimitedHistory: Bool

  public init(
    state: HealthWorkoutImportState,
    importedCount: Int,
    visibleWorkouts: [HealthWorkout],
    hasLimitedHistory: Bool
  ) {
    self.state = state
    self.importedCount = importedCount
    self.visibleWorkouts = visibleWorkouts
    self.hasLimitedHistory = hasLimitedHistory
  }
}

public enum HealthWorkoutImportError: Error, Equatable, Sendable {
  case authorizationRequired
  case repositoryUnavailable
}

/// Connects Health and imports the first durable workout batch.  The caller
/// may dismiss progress after receiving the first callback; the task continues
/// and every page is committed before the next page is fetched.
public actor HealthWorkoutImportBoundary {
  private let client: any HealthWorkoutClient
  private let repository: any HealthWorkoutRepository
  private let coordinator: HealthSyncCoordinator
  private var authorization: HealthAuthorizationSnapshot
  private var preferredSleepSourceOrder = SleepSourcePreference()
  private var observerRegistered = false

  public init(
    client: any HealthWorkoutClient,
    repository: any HealthWorkoutRepository,
    authorization: HealthAuthorizationSnapshot = .init(state: .notRequested)
  ) {
    self.client = client
    self.repository = repository
    self.coordinator = HealthSyncCoordinator(
      client: client,
      repository: repository,
      requestedStreams: authorization.requested.readTypes.map(HealthSyncStream.init),
      authorization: authorization
    )
    self.authorization = authorization
  }

  public func authorizationSnapshot() -> HealthAuthorizationSnapshot { authorization }

  public func healthDataStatus() async -> HealthDataStatus {
    await coordinator.statusSnapshot(authorization: authorization)
  }

  public func connectHealth() async throws -> HealthAuthorizationSnapshot {
    let snapshot = try await client.requestHealthAuthorization(.core)
    authorization = snapshot
    await coordinator.setAuthorization(snapshot)
    return snapshot
  }

  public func postponeHealth() async {
    authorization = HealthAuthorizationSnapshot(state: .postponed, requested: .core)
    await coordinator.setAuthorization(authorization)
  }

  public func registerHealthObserver() async throws {
    guard authorization.state == .authorized else {
      throw HealthWorkoutImportError.authorizationRequired
    }
    guard !observerRegistered else { return }
    try await client.registerWorkoutObserver { [weak self] in
      guard let self else { return }
      _ = try? await self.refreshHealthData(trigger: .observer)
    }
    observerRegistered = true
  }

  /// Refreshes every requested stream through the same coordinator used by
  /// first import.  It never clears mirrored rows and it never writes back to
  /// HealthKit.
  public func refreshHealthData(trigger: HealthSyncTrigger = .foreground) async throws
    -> HealthSyncResult
  {
    guard authorization.state == .authorized else {
      if authorization.state == .postponed {
        return HealthSyncResult(
          trigger: trigger, pagesCommitted: 0, additionsOrReplacements: 0, deletions: 0,
          checkpoint: nil, streamStatuses: (await healthDataStatus()).streams)
      }
      throw HealthWorkoutImportError.authorizationRequired
    }
    return try await coordinator.synchronize(trigger: trigger)
  }

  public func importWorkouts(
    progress: (@Sendable (HealthWorkoutImportProgress) async -> Void)? = nil
  ) async throws -> HealthWorkoutImportResult {
    guard authorization.state == .authorized else {
      if authorization.state == .postponed {
        return .init(
          state: .postponed, importedCount: 0, visibleWorkouts: [], hasLimitedHistory: false)
      }
      throw HealthWorkoutImportError.authorizationRequired
    }
    let result = try await coordinator.synchronize(
      trigger: .foreground,
      workoutProgress: progress
    )
    let visible = (try? await repository.loadHealthWorkouts()) ?? []
    let limited =
      result.streamStatuses.first(where: { $0.stream == .workouts })?.coverage
      == .limitedHistory
    let imported = result.additionsOrReplacements
    let state: HealthWorkoutImportState =
      limited ? .limitedHistory : (visible.isEmpty ? .successfulEmpty : .available)
    authorization = HealthAuthorizationSnapshot(
      state: .authorized, requested: authorization.requested, hasLimitedHistory: limited)
    await coordinator.setAuthorization(authorization)
    return .init(
      state: state, importedCount: imported, visibleWorkouts: visible, hasLimitedHistory: limited)
  }

  public func cachedWorkouts() async throws -> [HealthWorkout] {
    try await repository.loadHealthWorkouts()
  }

  /// Returns the independently mirrored Recovery Evidence streams. A missing
  /// stream is represented by an empty collection plus its own status; it is
  /// never inferred from another stream's success.
  public func recoveryEvidence() async -> HealthRecoveryEvidenceSnapshot {
    let status = await coordinator.statusSnapshot(authorization: authorization)
    let sleep = (try? await repository.loadHealthRecoverySamples(for: .sleep)) ?? []
    let resting = (try? await repository.loadHealthRecoverySamples(for: .restingHeartRate)) ?? []
    let variability =
      (try? await repository.loadHealthRecoverySamples(for: .heartRateVariability)) ?? []
    return HealthRecoveryEvidenceSnapshot(
      sleep: sleep.compactMap {
        guard case .sleep(let sample) = $0 else { return nil }
        return sample
      },
      restingHeartRate: resting.compactMap {
        guard case .restingHeartRate(let sample) = $0 else { return nil }
        return sample
      },
      heartRateVariability: variability.compactMap {
        guard case .heartRateVariability(let sample) = $0 else { return nil }
        return sample
      },
      statuses: status.streams.filter { RecoveryEvidenceStream($0.stream) != nil })
  }

  /// Returns current Health-only Training Events with source and reconciliation
  /// context. The mirror is the only source of current events, so a deleted
  /// HealthKit UUID is retained only in `deletedHealthKitUUIDs` and never
  /// reintroduced into the timeline.
  public func healthWorkoutHistory() async throws -> HealthWorkoutHistorySnapshot {
    let workouts = try await repository.loadHealthWorkouts()
    let status = await coordinator.statusSnapshot(authorization: authorization)
    let workoutStatus = status.streams.first(where: { $0.stream == .workouts })
    let checkpoint = try? await repository.loadHealthSyncCheckpoint(for: .workouts)
    let deleted = (try? await repository.loadHealthWorkoutDeletionUUIDs()) ?? []
    let lastSuccessful = workoutStatus?.lastSuccessfulCheck ?? checkpoint?.committedAt
    let context = checkpoint?.reconciliationContext

    var workoutsByUUID: [String: HealthWorkout] = [:]
    for workout in workouts { workoutsByUUID[workout.healthKitUUID] = workout }
    var enrichmentsByUUID: [String: HealthWorkoutEnrichment] = [:]
    for workout in workoutsByUUID.values {
      if let enrichment = try? await repository.loadHealthWorkoutEnrichment(
        for: workout.healthKitUUID)
      {
        enrichmentsByUUID[workout.healthKitUUID] = enrichment
      }
    }
    let events = workoutsByUUID.values
      .sorted {
        if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
        return $0.healthKitUUID > $1.healthKitUUID
      }
      .map { workout in
        let provenance = HealthWorkoutProvenance(workout: workout)
        let entryState: HealthWorkoutPresentationState =
          provenance.isAvailable
          ? .available
          : .unavailableProvenance
        return HealthWorkoutHistoryEntry(
          event: TrainingEvent(
            workout: workout,
            reconciliationContext: context,
            lastSuccessfulReconciliation: lastSuccessful,
            healthCoverage: workoutStatus?.coverage ?? .unknown
          ),
          provenance: provenance,
          enrichment: enrichmentsByUUID[workout.healthKitUUID],
          state: entryState
        )
      }

    let state = Self.historyState(
      events: events,
      status: workoutStatus,
      authorization: authorization,
      deletedHealthKitUUIDs: deleted
    )
    return HealthWorkoutHistorySnapshot(
      events: events,
      state: state,
      lastSuccessfulReconciliation: lastSuccessful,
      reconciliationContext: context,
      deletedHealthKitUUIDs: deleted
    )
  }

  /// Returns the owner-controlled source ordering used for sleep projection.
  /// The ordering is kept separate from Health reconciliation so replacing or
  /// deleting a sample cannot rewrite the owner's preference.
  public func sleepSourcePreference() -> SleepSourcePreference {
    preferredSleepSourceOrder
  }

  public func setSleepSourcePreference(_ preference: SleepSourcePreference) {
    preferredSleepSourceOrder = preference
  }

  /// Recomputes deterministic Primary Sleep and Nap episodes from the current
  /// mirrored sleep stream.  A failed or missing refresh therefore leaves the
  /// last mirrored intervals inspectable without claiming new continuity.
  public func sleepEpisodes(calendar: Calendar = Calendar(identifier: .gregorian)) async
    -> SleepEpisodeProjection
  {
    let evidence = await recoveryEvidence()
    return evidence.sleepEpisodes(preference: preferredSleepSourceOrder, calendar: calendar)
  }

  /// Returns neutral daily resting-heart-rate and HRV SDNN observations from
  /// the independent mirrored streams. The projection retains each stream's
  /// source, coverage, reconciliation, and algorithm context; it never treats
  /// one stream's success as evidence that another stream is current.
  public func dailyRecoveryObservations(
    calendar: Calendar = .current,
    now: Date = Date()
  ) async -> HealthRecoveryObservationProjection {
    let evidence = await recoveryEvidence()
    return evidence.dailyObservations(calendar: calendar, now: now)
  }

  /// Descriptive alias for callers that use the shorter Recovery Evidence
  /// vocabulary at the application boundary.
  public func recoveryObservations(
    calendar: Calendar = .current,
    now: Date = Date()
  ) async -> HealthRecoveryObservationProjection {
    await dailyRecoveryObservations(calendar: calendar, now: now)
  }

  public func todayHealthWorkouts(on date: TrainingDate) async throws
    -> [HealthWorkoutHistoryEntry]
  {
    let history = try await healthWorkoutHistory()
    return history.events.filter { $0.event.localDate == date.iso8601String }
  }

  private static func historyState(
    events: [HealthWorkoutHistoryEntry],
    status: HealthStreamStatus?,
    authorization: HealthAuthorizationSnapshot,
    deletedHealthKitUUIDs: [String]
  ) -> HealthWorkoutPresentationState {
    if authorization.state == .unavailable { return .unavailable }
    if let status {
      if status.reconciliation == .updating {
        return events.isEmpty ? .loading : .cached
      }
      if let failure = status.failure {
        return status.lastSuccessfulCheck == nil
          || failure.occurredAt <= status.lastSuccessfulCheck!
          ? .firstFailure
          : .delayedUpdate
      }
      if status.coverage == .limitedHistory { return .limitedHistory }
      if status.mirroredContent == .empty && status.lastSuccessfulCheck != nil {
        return deletedHealthKitUUIDs.isEmpty ? .successfulEmpty : .deleted
      }
    }
    if !deletedHealthKitUUIDs.isEmpty { return .deleted }
    if events.isEmpty {
      return deletedHealthKitUUIDs.isEmpty ? .loading : .deleted
    }
    if events.allSatisfy({ $0.state == .unavailableProvenance }) {
      return .unavailableProvenance
    }
    if authorization.state != .authorized { return .cached }
    return .available
  }
}

/// Coordinates foreground, unlock, observer, retry, and manual invalidation
/// requests.  The actor owns the single in-flight task, so overlapping
/// triggers share work and an observer never starts a polling loop.
public actor HealthSyncCoordinator {
  private let client: any HealthWorkoutClient
  private let repository: any HealthWorkoutRepository
  private let limits: HealthSyncBatchLimits
  private let requestedStreams: [HealthSyncStream]
  private var inFlight: Task<HealthSyncResult, Error>?
  private var authorization: HealthAuthorizationSnapshot
  private var statuses: [HealthSyncStream: HealthStreamStatus]

  public init(
    client: any HealthWorkoutClient,
    repository: any HealthWorkoutRepository,
    limits: HealthSyncBatchLimits = .default,
    requestedStreams: [HealthSyncStream] = [.workouts],
    authorization: HealthAuthorizationSnapshot = .init(state: .notRequested)
  ) {
    self.client = client
    self.repository = repository
    self.limits = limits
    self.requestedStreams = requestedStreams.isEmpty ? [.workouts] : requestedStreams
    self.authorization = authorization
    self.statuses = Dictionary(
      uniqueKeysWithValues: self.requestedStreams.map {
        (
          $0,
          HealthStreamStatus(
            stream: $0,
            requested: authorization.requested.readTypes.contains($0.readType),
            authorization: authorization.state)
        )
      })
  }

  public func setAuthorization(_ snapshot: HealthAuthorizationSnapshot) {
    authorization = snapshot
    for stream in requestedStreams {
      let current = statuses[stream] ?? HealthStreamStatus(stream: stream)
      statuses[stream] = HealthStreamStatus(
        stream: stream,
        requested: snapshot.requested.readTypes.contains(stream.readType),
        authorization: snapshot.state,
        coverage: current.coverage,
        mirroredContent: current.mirroredContent,
        reconciliation: current.reconciliation,
        lastSuccessfulCheck: current.lastSuccessfulCheck,
        failure: current.failure,
        attemptCount: current.attemptCount
      )
    }
  }

  public func statusSnapshot(
    authorization snapshot: HealthAuthorizationSnapshot? = nil
  ) async -> HealthDataStatus {
    if let snapshot { setAuthorization(snapshot) }
    var hydrated = statuses
    for stream in requestedStreams {
      let current = hydrated[stream] ?? HealthStreamStatus(stream: stream)
      let checkpoint = try? await repository.loadHealthSyncCheckpoint(for: stream)
      let mirror = try? await repository.loadHealthMirrorContent(for: stream)
      let checkpointCoverage: HealthStreamCoverage =
        checkpoint.map { $0.hasLimitedHistory ? .limitedHistory : .available } ?? current.coverage
      let checkpointDate = checkpoint?.committedAt
      let lastCheck: Date?
      switch (current.lastSuccessfulCheck, checkpointDate) {
      case (let left?, let right?): lastCheck = max(left, right)
      case (let left?, nil): lastCheck = left
      case (nil, let right?): lastCheck = right
      case (nil, nil): lastCheck = nil
      }
      let mirrorAvailability = mirror?.availability ?? .unknown
      let resolvedMirror =
        mirrorAvailability == .unknown ? current.mirroredContent : mirrorAvailability
      hydrated[stream] = HealthStreamStatus(
        stream: stream,
        requested: snapshot?.requested.readTypes.contains(stream.readType)
          ?? current.requested,
        authorization: snapshot?.state ?? authorization.state,
        coverage: checkpointCoverage,
        mirroredContent: resolvedMirror,
        reconciliation: current.reconciliation,
        lastSuccessfulCheck: lastCheck,
        failure: current.failure,
        attemptCount: current.attemptCount
      )
    }
    return HealthDataStatus(
      authorization: snapshot ?? authorization,
      streams: requestedStreams.compactMap { hydrated[$0] }
    )
  }

  public func synchronize(
    trigger: HealthSyncTrigger = .foreground,
    workoutProgress: (@Sendable (HealthWorkoutImportProgress) async -> Void)? = nil
  ) async throws -> HealthSyncResult {
    if let inFlight {
      return try await inFlight.value
    }

    let activeStreams = requestedStreams.filter { statuses[$0]?.requested ?? true }
    for stream in activeStreams {
      let current = statuses[stream] ?? HealthStreamStatus(stream: stream)
      statuses[stream] = HealthStreamStatus(
        stream: stream, requested: current.requested, authorization: authorization.state,
        coverage: current.coverage, mirroredContent: current.mirroredContent,
        reconciliation: .updating, lastSuccessfulCheck: current.lastSuccessfulCheck,
        failure: current.failure, attemptCount: current.attemptCount + 1)
    }
    let task = Task { [client, repository, limits] in
      try await Self.reconcile(
        client: client, repository: repository, limits: limits, trigger: trigger,
        streams: activeStreams, workoutProgress: workoutProgress
      )
    }
    inFlight = task
    do {
      let result = try await task.value
      inFlight = nil
      let mergedStatuses = result.streamStatuses.map { status in
        guard let failure = status.failure, let current = statuses[status.stream] else {
          statuses[status.stream] = status
          return status
        }
        let merged = HealthStreamStatus(
          stream: status.stream,
          requested: current.requested,
          authorization: current.authorization,
          coverage: current.coverage,
          mirroredContent: current.mirroredContent,
          reconciliation: .idle,
          lastSuccessfulCheck: current.lastSuccessfulCheck,
          failure: failure,
          attemptCount: current.attemptCount
        )
        statuses[status.stream] = merged
        return merged
      }
      return HealthSyncResult(
        trigger: result.trigger,
        pagesCommitted: result.pagesCommitted,
        additionsOrReplacements: result.additionsOrReplacements,
        deletions: result.deletions,
        checkpoint: result.checkpoint,
        streamStatuses: mergedStatuses
      )
    } catch {
      inFlight = nil
      for stream in activeStreams {
        let current = statuses[stream] ?? HealthStreamStatus(stream: stream)
        statuses[stream] = HealthStreamStatus(
          stream: stream, requested: current.requested, authorization: authorization.state,
          coverage: current.coverage, mirroredContent: current.mirroredContent,
          reconciliation: .idle, lastSuccessfulCheck: current.lastSuccessfulCheck,
          failure: .init(code: "cancelled-or-unavailable"), attemptCount: current.attemptCount)
      }
      throw error
    }
  }

  public func foreground() async throws -> HealthSyncResult {
    try await synchronize(trigger: .foreground)
  }

  public func observerInvalidated() async throws -> HealthSyncResult {
    try await synchronize(trigger: .observer)
  }

  public func unlocked() async throws -> HealthSyncResult {
    try await synchronize(trigger: .unlock)
  }

  public func retry() async throws -> HealthSyncResult {
    try await synchronize(trigger: .retry)
  }

  public func invalidate() async throws -> HealthSyncResult {
    try await synchronize(trigger: .manualInvalidation)
  }

  private struct StreamOutcome: Sendable {
    let stream: HealthSyncStream
    let pages: Int
    let additions: Int
    let deletions: Int
    let checkpoint: HealthSyncCheckpoint?
    let status: HealthStreamStatus
  }

  private static func reconcile(
    client: any HealthWorkoutClient,
    repository: any HealthWorkoutRepository,
    limits: HealthSyncBatchLimits,
    trigger: HealthSyncTrigger,
    streams: [HealthSyncStream],
    workoutProgress: (@Sendable (HealthWorkoutImportProgress) async -> Void)?
  ) async throws -> HealthSyncResult {
    var outcomes: [StreamOutcome] = []
    var importedCount = 0
    for stream in streams {
      try Task.checkCancellation()
      do {
        var checkpoint = try await repository.loadHealthSyncCheckpoint(for: stream)
        var fetchToken = checkpoint?.anchor
        var pages = 0
        var changed = 0
        var deleted = 0
        var limited = checkpoint?.hasLimitedHistory ?? false
        repeat {
          try Task.checkCancellation()
          let page = try await client.fetchHealthPage(for: stream, after: fetchToken)
          // Every stream page is committed through the same repository seam so
          // its facts and anchor are durable even when that stream has no
          // reconstructible mirror table yet. The repository decides which
          // source-owned records belong in each mirror.
          try await repository.commitHealthWorkoutPage(page, stream: stream, limits: limits)
          pages += 1
          changed += page.workouts.count + page.recoverySamples(for: stream).count
          deleted += page.deletedHealthKitUUIDs.count
          importedCount += stream == .workouts ? page.workouts.count : 0
          limited = limited || page.hasLimitedHistory
          fetchToken = page.nextAnchor
          checkpoint = HealthSyncCheckpoint(
            stream: stream,
            anchor: page.nextAnchor,
            hasLimitedHistory: limited,
            reconciliationContext: page.reconciliationContext
          )
          if stream == .workouts {
            let state: HealthWorkoutImportState =
              limited ? .limitedHistory : (importedCount == 0 ? .successfulEmpty : .available)
            await workoutProgress?(
              .init(
                importedCount: importedCount, firstBatchVisible: importedCount > 0,
                isComplete: fetchToken == nil, state: state))
          }
        } while fetchToken != nil
        if stream == .workouts {
          // Re-query every current workout after an incremental workout page,
          // including an empty one. Associated samples may arrive or be
          // deleted without HealthKit replacing the workout object itself.
          for workout in try await repository.loadHealthWorkouts() {
            guard
              let queried = await client.fetchWorkoutEnrichment(for: workout),
              queried.healthKitUUID == workout.healthKitUUID
            else { continue }
            let cached = try await repository.loadHealthWorkoutEnrichment(
              for: workout.healthKitUUID)
            try await repository.saveHealthWorkoutEnrichment(
              queried.preservingFailedDetails(from: cached))
          }
        }
        let mirror = try? await repository.loadHealthMirrorContent(for: stream)
        let mirroredContent = mirror?.availability ?? .unknown
        let status = HealthStreamStatus(
          stream: stream,
          requested: true,
          authorization: .authorized,
          coverage: limited ? .limitedHistory : .available,
          mirroredContent: mirroredContent,
          reconciliation: .idle,
          lastSuccessfulCheck: checkpoint?.committedAt,
          failure: nil,
          attemptCount: 1
        )
        outcomes.append(
          StreamOutcome(
            stream: stream, pages: pages, additions: changed, deletions: deleted,
            checkpoint: checkpoint, status: status))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        outcomes.append(
          StreamOutcome(
            stream: stream, pages: 0, additions: 0, deletions: 0, checkpoint: nil,
            status: HealthStreamStatus(
              stream: stream, requested: true, authorization: .authorized,
              reconciliation: .idle,
              failure: .init(code: "health-check-failed"), attemptCount: 1)))
      }
    }
    let workout = outcomes.first(where: { $0.stream == .workouts })
    return HealthSyncResult(
      trigger: trigger,
      pagesCommitted: outcomes.reduce(0) { $0 + $1.pages },
      additionsOrReplacements: outcomes.reduce(0) { $0 + $1.additions },
      deletions: outcomes.reduce(0) { $0 + $1.deletions },
      checkpoint: workout?.checkpoint,
      streamStatuses: outcomes.map(\.status)
    )
  }
}
