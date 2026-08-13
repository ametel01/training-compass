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
  public let nextPageToken: String?
  public let hasLimitedHistory: Bool
  public let reconciliationContext: String

  public init(
    workouts: [HealthWorkout],
    nextPageToken: String? = nil,
    hasLimitedHistory: Bool = false,
    reconciliationContext: String = "initial"
  ) {
    self.workouts = workouts
    self.nextPageToken = nextPageToken
    self.hasLimitedHistory = hasLimitedHistory
    self.reconciliationContext = reconciliationContext
  }
}

public protocol HealthWorkoutClient: HealthKitClient {
  func requestHealthAuthorization(_ request: HealthAuthorizationRequest) async throws
    -> HealthAuthorizationSnapshot
  func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage
}

public protocol HealthWorkoutRepository: Sendable {
  func upsertHealthWorkouts(_ workouts: [HealthWorkout], reconciliationContext: String) async throws
  func loadHealthWorkouts() async throws -> [HealthWorkout]
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
  private var authorization: HealthAuthorizationSnapshot

  public init(
    client: any HealthWorkoutClient,
    repository: any HealthWorkoutRepository,
    authorization: HealthAuthorizationSnapshot = .init(state: .notRequested)
  ) {
    self.client = client
    self.repository = repository
    self.authorization = authorization
  }

  public func authorizationSnapshot() -> HealthAuthorizationSnapshot { authorization }

  public func connectHealth() async throws -> HealthAuthorizationSnapshot {
    let snapshot = try await client.requestHealthAuthorization(.core)
    authorization = snapshot
    return snapshot
  }

  public func postponeHealth() {
    authorization = HealthAuthorizationSnapshot(state: .postponed, requested: .core)
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
    var token: String?
    var imported = 0
    var visible: [HealthWorkout] = []
    var limited = authorization.hasLimitedHistory
    var first = true
    repeat {
      let page = try await client.fetchWorkoutPage(after: token)
      limited = limited || page.hasLimitedHistory
      guard !page.workouts.isEmpty || first else {
        token = page.nextPageToken
        first = false
        continue
      }
      if !page.workouts.isEmpty {
        try await repository.upsertHealthWorkouts(
          page.workouts, reconciliationContext: page.reconciliationContext)
        imported += page.workouts.count
        visible.append(contentsOf: page.workouts)
      }
      first = false
      let state: HealthWorkoutImportState =
        limited ? .limitedHistory : (imported == 0 ? .successfulEmpty : .available)
      await progress?(
        .init(
          importedCount: imported, firstBatchVisible: imported > 0,
          isComplete: page.nextPageToken == nil, state: state))
      token = page.nextPageToken
    } while token != nil
    let state: HealthWorkoutImportState =
      limited ? .limitedHistory : (imported == 0 ? .successfulEmpty : .available)
    authorization = HealthAuthorizationSnapshot(
      state: .authorized, requested: authorization.requested, hasLimitedHistory: limited)
    await progress?(
      .init(
        importedCount: imported, firstBatchVisible: imported > 0, isComplete: true, state: state))
    return .init(
      state: state, importedCount: imported, visibleWorkouts: visible, hasLimitedHistory: limited)
  }

  public func cachedWorkouts() async throws -> [HealthWorkout] {
    try await repository.loadHealthWorkouts()
  }
}
