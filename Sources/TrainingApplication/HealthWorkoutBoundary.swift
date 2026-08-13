import Foundation

/// The read surface requested by the first Health connection.  These are
/// application-owned values; HealthKit types never cross this boundary.
public enum HealthReadType: String, CaseIterable, Codable, Equatable, Sendable {
  case workouts
  case heartRate
  case activeEnergy
  case sleep
  case restingHeartRate
  case heartRateVariability

  public var displayName: String {
    switch self {
    case .workouts: "Health Workouts"
    case .heartRate: "Workout heart rate"
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
      .workouts, .heartRate, .activeEnergy, .sleep, .restingHeartRate, .heartRateVariability,
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
}

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
    self.firstImportedAt = firstImportedAt
    self.reconciliationContext = reconciliationContext
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

public struct HealthWorkoutPage: Codable, Equatable, Sendable {
  public let workouts: [HealthWorkout]
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
    streamFacts: [HealthSyncFact] = []
  ) {
    self.workouts = workouts
    self.deletedHealthKitUUIDs = deletedHealthKitUUIDs
    self.nextPageToken = nextPageToken
    self.anchor = anchor
    self.hasLimitedHistory = hasLimitedHistory
    self.reconciliationContext = reconciliationContext
    self.streamFacts = streamFacts
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
  case activeEnergy
  case sleep
  case restingHeartRate
  case heartRateVariability

  public init(_ type: HealthReadType) {
    switch type {
    case .workouts: self = .workouts
    case .heartRate: self = .heartRate
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
    let records = page.workouts.count + page.deletedHealthKitUUIDs.count
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
  func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage
  func fetchHealthPage(
    for stream: HealthSyncStream, after pageToken: String?
  ) async throws -> HealthWorkoutPage
}

extension HealthWorkoutClient {
  /// A client that only has the original workout seam can still participate in
  /// the status screen. Unsupported streams fail independently rather than
  /// being misrepresented as a successful empty Health result.
  public func fetchHealthPage(
    for stream: HealthSyncStream, after pageToken: String?
  ) async throws -> HealthWorkoutPage {
    guard stream == .workouts else { throw HealthSyncError.unavailable }
    return try await fetchWorkoutPage(after: pageToken)
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
    if !page.workouts.isEmpty {
      try await upsertHealthWorkouts(
        page.workouts, reconciliationContext: page.reconciliationContext)
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
      requestedStreams: authorization.requested.readTypes.map(HealthSyncStream.init)
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
        ($0, HealthStreamStatus(stream: $0, authorization: authorization.state))
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

    for stream in requestedStreams {
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
        streams: self.requestedStreams, workoutProgress: workoutProgress
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
      for stream in requestedStreams {
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
          // The current reconstructible mirror stores workouts only. Other
          // requested streams are still queried independently, but their
          // records must never be written into the workout table.
          if stream == .workouts {
            try await repository.commitHealthWorkoutPage(page, stream: stream, limits: limits)
          }
          pages += 1
          changed += page.workouts.count
          deleted += page.deletedHealthKitUUIDs.count
          importedCount += stream == .workouts ? page.workouts.count : 0
          limited = limited || page.hasLimitedHistory
          fetchToken = page.nextPageToken
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
