import Foundation

public enum HealthWorkoutRouteAuthorizationState: String, Codable, Equatable, Sendable {
  case authorized
  case unavailable
}

public enum HealthWorkoutRouteState: String, Codable, Equatable, Sendable {
  case loading
  case unavailable
  case failed
  case cancelled
  case ready
}

public enum HealthWorkoutRouteSimplification: String, Codable, Equatable, Sendable {
  case boundedDouglasPeuckerV1
}

/// One display-ready point retained from a HealthKit route. The adapter never
/// exposes its original full-resolution input through this application seam.
public struct HealthWorkoutRoutePoint: Codable, Equatable, Sendable {
  public let northSouthDegrees: Double
  public let eastWestDegrees: Double

  public init(northSouthDegrees: Double, eastWestDegrees: Double) {
    precondition(northSouthDegrees.isFinite && (-90...90).contains(northSouthDegrees))
    precondition(eastWestDegrees.isFinite && (-180...180).contains(eastWestDegrees))
    self.northSouthDegrees = northSouthDegrees
    self.eastWestDegrees = eastWestDegrees
  }
}

public struct HealthWorkoutRouteSource: Codable, Equatable, Sendable {
  public let healthKitUUID: String
  public let provenance: HealthSampleProvenance

  public init(healthKitUUID: String, provenance: HealthSampleProvenance) {
    precondition(!healthKitUUID.isEmpty)
    self.healthKitUUID = healthKitUUID
    self.provenance = provenance
  }
}

public struct HealthWorkoutRouteSegment: Codable, Equatable, Sendable, Identifiable {
  public let source: HealthWorkoutRouteSource
  public let points: [HealthWorkoutRoutePoint]
  public let originalPointCount: Int

  public var id: String { source.healthKitUUID }

  public init(
    source: HealthWorkoutRouteSource,
    points: [HealthWorkoutRoutePoint],
    originalPointCount: Int
  ) {
    precondition(!points.isEmpty)
    precondition(originalPointCount >= points.count)
    self.source = source
    self.points = points
    self.originalPointCount = originalPointCount
  }
}

/// A reconstructible, display-ready route. Only simplified geometry may be
/// constructed at this boundary, and persisted values are capped at 2,000
/// points independently of the size of HealthKit's original result.
public struct HealthWorkoutRoute: Codable, Equatable, Sendable, Identifiable {
  public static let maximumRetainedPoints = 2_000

  public let healthKitUUID: String
  public let segments: [HealthWorkoutRouteSegment]
  public let retainedAt: Date
  public let simplification: HealthWorkoutRouteSimplification
  public let reconciliationContext: String
  /// Adapter-controlled work after HealthKit returns coordinate pages. HealthKit
  /// query wait is deliberately excluded so Acceptance Device runs can report it
  /// separately from the two-second application budget.
  public let adapterProcessingDurationMilliseconds: Double

  public var id: String { healthKitUUID }
  public var points: [HealthWorkoutRoutePoint] { segments.flatMap(\.points) }
  public var originalPointCount: Int { segments.reduce(0) { $0 + $1.originalPointCount } }
  public var sources: [HealthWorkoutRouteSource] { segments.map(\.source) }

  public init(
    healthKitUUID: String,
    segments: [HealthWorkoutRouteSegment],
    retainedAt: Date,
    simplification: HealthWorkoutRouteSimplification,
    reconciliationContext: String,
    adapterProcessingDurationMilliseconds: Double = 0
  ) {
    precondition(!healthKitUUID.isEmpty)
    precondition(!segments.isEmpty)
    precondition(segments.reduce(0) { $0 + $1.points.count } <= Self.maximumRetainedPoints)
    precondition(!reconciliationContext.isEmpty)
    precondition(
      adapterProcessingDurationMilliseconds.isFinite
        && adapterProcessingDurationMilliseconds >= 0)
    self.healthKitUUID = healthKitUUID
    self.segments = segments
    self.retainedAt = retainedAt
    self.simplification = simplification
    self.reconciliationContext = reconciliationContext
    self.adapterProcessingDurationMilliseconds = adapterProcessingDurationMilliseconds
  }
}

public enum HealthWorkoutRouteFailureCode: String, Codable, Equatable, Sendable {
  case identityOrSizeMismatch = "route-identity-or-size-mismatch"
  case operationFailed = "route-operation-failed"
  case persistenceRejected = "route-persistence-rejected"
  case resourcePressure = "route-resource-pressure"
}

public struct HealthWorkoutRouteSnapshot: Codable, Equatable, Sendable {
  public let state: HealthWorkoutRouteState
  public let route: HealthWorkoutRoute?
  public let failureCode: HealthWorkoutRouteFailureCode?
  public let appProcessingDurationMilliseconds: Double?

  private init(
    state: HealthWorkoutRouteState,
    route: HealthWorkoutRoute? = nil,
    failureCode: HealthWorkoutRouteFailureCode? = nil,
    appProcessingDurationMilliseconds: Double? = nil
  ) {
    self.state = state
    self.route = route
    self.failureCode = failureCode
    self.appProcessingDurationMilliseconds = appProcessingDurationMilliseconds
  }

  public static let loading = HealthWorkoutRouteSnapshot(state: .loading)
  public static let unavailable = HealthWorkoutRouteSnapshot(state: .unavailable)
  public static let cancelled = HealthWorkoutRouteSnapshot(state: .cancelled)

  public static func failed(code: HealthWorkoutRouteFailureCode) -> Self {
    .init(state: .failed, failureCode: code)
  }

  public static func ready(
    _ route: HealthWorkoutRoute,
    appProcessingDurationMilliseconds: Double? = nil
  ) -> Self {
    .init(
      state: .ready,
      route: route,
      appProcessingDurationMilliseconds: appProcessingDurationMilliseconds)
  }
}

public protocol HealthWorkoutRouteClient: Sendable {
  func requestWorkoutRouteAuthorization() async throws -> HealthWorkoutRouteAuthorizationState
  func fetchSimplifiedWorkoutRoute(
    for healthKitUUID: String,
    maximumRetainedPoints: Int
  ) async throws -> HealthWorkoutRoute?
}

public protocol HealthWorkoutRouteRepository: Sendable {
  /// Returns false when the owning workout no longer exists, including a
  /// concurrent deletion or reconstructible rebuild.
  func saveHealthWorkoutRoute(_ route: HealthWorkoutRoute) async throws -> Bool
  func loadHealthWorkoutRoute(for healthKitUUID: String) async throws -> HealthWorkoutRoute?
}

public enum HealthWorkoutRouteThermalState: String, Codable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical
}

public struct HealthWorkoutRouteResourceSnapshot: Codable, Equatable, Sendable {
  public static let minimumAvailableStorageBytes = 500 * 1_024 * 1_024

  public let availableStorageBytes: Int
  public let lowPowerModeEnabled: Bool
  public let batteryLevel: Double?
  public let thermalState: HealthWorkoutRouteThermalState

  public init(
    availableStorageBytes: Int,
    lowPowerModeEnabled: Bool,
    batteryLevel: Double?,
    thermalState: HealthWorkoutRouteThermalState
  ) {
    self.availableStorageBytes = max(0, availableStorageBytes)
    self.lowPowerModeEnabled = lowPowerModeEnabled
    self.batteryLevel = batteryLevel.map { min(1, max(0, $0)) }
    self.thermalState = thermalState
  }

  public static let unconstrained = HealthWorkoutRouteResourceSnapshot(
    availableStorageBytes: .max,
    lowPowerModeEnabled: false,
    batteryLevel: nil,
    thermalState: .nominal)

  public var permitsRouteWork: Bool {
    availableStorageBytes >= Self.minimumAvailableStorageBytes
      && !lowPowerModeEnabled
      && batteryLevel.map { $0 >= 0.2 } != false
      && thermalState != .serious
      && thermalState != .critical
  }
}

public protocol HealthWorkoutRouteResourceProviding: Sendable {
  func currentRouteResources() async -> HealthWorkoutRouteResourceSnapshot
}

public struct UnconstrainedHealthWorkoutRouteResourceProvider:
  HealthWorkoutRouteResourceProviding
{
  public init() {}

  public func currentRouteResources() async -> HealthWorkoutRouteResourceSnapshot {
    .unconstrained
  }
}

/// Owns the one serialized route-operation lane. Route authorization and
/// queries are reachable only through `openRoute`, never workout import or
/// ordinary enrichment.
public actor HealthWorkoutRouteBoundary {
  private struct Operation: Sendable {
    let healthKitUUID: String
    let task: Task<HealthWorkoutRouteSnapshot, Never>
  }

  private let client: any HealthWorkoutRouteClient
  private let repository: any HealthWorkoutRouteRepository
  private let resourceProvider: any HealthWorkoutRouteResourceProviding
  private let maximumRetainedPoints: Int
  private var inFlight: Operation?
  private var states: [String: HealthWorkoutRouteSnapshot] = [:]
  private var cancellationGenerations: [String: Int] = [:]

  public init(
    client: any HealthWorkoutRouteClient,
    repository: any HealthWorkoutRouteRepository,
    maximumRetainedPoints: Int = HealthWorkoutRoute.maximumRetainedPoints,
    resourceProvider: any HealthWorkoutRouteResourceProviding =
      UnconstrainedHealthWorkoutRouteResourceProvider()
  ) {
    precondition(maximumRetainedPoints >= 2)
    precondition(maximumRetainedPoints <= HealthWorkoutRoute.maximumRetainedPoints)
    self.client = client
    self.repository = repository
    self.maximumRetainedPoints = maximumRetainedPoints
    self.resourceProvider = resourceProvider
  }

  public func state(for healthKitUUID: String) async -> HealthWorkoutRouteSnapshot {
    if states[healthKitUUID]?.state == .loading { return .loading }
    if let route = try? await repository.loadHealthWorkoutRoute(for: healthKitUUID) {
      let ready = HealthWorkoutRouteSnapshot.ready(route)
      states[healthKitUUID] = ready
      return ready
    }
    return .unavailable
  }

  public func openRoute(for healthKitUUID: String) async -> HealthWorkoutRouteSnapshot {
    let cancellationGeneration = cancellationGenerations[healthKitUUID, default: 0]
    if let route = try? await repository.loadHealthWorkoutRoute(for: healthKitUUID) {
      let ready = HealthWorkoutRouteSnapshot.ready(route)
      states[healthKitUUID] = ready
      return ready
    }

    states[healthKitUUID] = .loading
    while let operation = inFlight {
      let result = await operation.task.value
      if inFlight?.healthKitUUID == operation.healthKitUUID {
        inFlight = nil
        states[operation.healthKitUUID] = result
      }
      if operation.healthKitUUID == healthKitUUID {
        return result
      }
      guard cancellationGenerations[healthKitUUID, default: 0] == cancellationGeneration else {
        states[healthKitUUID] = .cancelled
        return .cancelled
      }
    }

    guard cancellationGenerations[healthKitUUID, default: 0] == cancellationGeneration else {
      states[healthKitUUID] = .cancelled
      return .cancelled
    }

    let client = self.client
    let repository = self.repository
    let resourceProvider = self.resourceProvider
    let maximumRetainedPoints = self.maximumRetainedPoints
    let task = Task<HealthWorkoutRouteSnapshot, Never> {
      do {
        try Task.checkCancellation()
        guard await resourceProvider.currentRouteResources().permitsRouteWork else {
          return .failed(code: .resourcePressure)
        }
        let authorization = try await client.requestWorkoutRouteAuthorization()
        guard authorization == .authorized else { return .unavailable }
        try Task.checkCancellation()
        guard
          let route = try await client.fetchSimplifiedWorkoutRoute(
            for: healthKitUUID,
            maximumRetainedPoints: maximumRetainedPoints)
        else { return .unavailable }
        let postFetchStart = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        guard route.healthKitUUID == healthKitUUID,
          route.points.count <= maximumRetainedPoints
        else { return .failed(code: .identityOrSizeMismatch) }
        guard await resourceProvider.currentRouteResources().permitsRouteWork else {
          return .failed(code: .resourcePressure)
        }
        guard try await repository.saveHealthWorkoutRoute(route) else {
          return .failed(code: .persistenceRejected)
        }
        guard try await repository.loadHealthWorkoutRoute(for: healthKitUUID) == route else {
          return .failed(code: .persistenceRejected)
        }
        try Task.checkCancellation()
        let postFetchMilliseconds =
          (ProcessInfo.processInfo.systemUptime - postFetchStart) * 1_000
        return .ready(
          route,
          appProcessingDurationMilliseconds: route.adapterProcessingDurationMilliseconds
            + postFetchMilliseconds)
      } catch is CancellationError {
        return .cancelled
      } catch {
        return .failed(code: .operationFailed)
      }
    }
    inFlight = Operation(healthKitUUID: healthKitUUID, task: task)
    let result = await task.value
    if inFlight?.healthKitUUID == healthKitUUID {
      inFlight = nil
    }
    states[healthKitUUID] = result
    return result
  }

  public func cancelRoute(for healthKitUUID: String) {
    cancellationGenerations[healthKitUUID, default: 0] += 1
    if inFlight?.healthKitUUID == healthKitUUID {
      inFlight?.task.cancel()
    }
  }
}
