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

/// A reconstructible, display-ready route. Only simplified geometry may be
/// constructed at this boundary, and persisted values are capped at 2,000
/// points independently of the size of HealthKit's original result.
public struct HealthWorkoutRoute: Codable, Equatable, Sendable, Identifiable {
  public static let maximumRetainedPoints = 2_000

  public let healthKitUUID: String
  public let points: [HealthWorkoutRoutePoint]
  public let originalPointCount: Int
  public let sources: [HealthWorkoutRouteSource]
  public let retainedAt: Date
  public let simplification: HealthWorkoutRouteSimplification
  public let reconciliationContext: String

  public var id: String { healthKitUUID }

  public init(
    healthKitUUID: String,
    points: [HealthWorkoutRoutePoint],
    originalPointCount: Int,
    sources: [HealthWorkoutRouteSource],
    retainedAt: Date,
    simplification: HealthWorkoutRouteSimplification,
    reconciliationContext: String
  ) {
    precondition(!healthKitUUID.isEmpty)
    precondition(!points.isEmpty && points.count <= Self.maximumRetainedPoints)
    precondition(originalPointCount >= points.count)
    precondition(!sources.isEmpty)
    precondition(!reconciliationContext.isEmpty)
    self.healthKitUUID = healthKitUUID
    self.points = points
    self.originalPointCount = originalPointCount
    self.sources = sources
    self.retainedAt = retainedAt
    self.simplification = simplification
    self.reconciliationContext = reconciliationContext
  }
}

public struct HealthWorkoutRouteSnapshot: Codable, Equatable, Sendable {
  public let state: HealthWorkoutRouteState
  public let route: HealthWorkoutRoute?
  public let failureCode: String?

  private init(
    state: HealthWorkoutRouteState,
    route: HealthWorkoutRoute? = nil,
    failureCode: String? = nil
  ) {
    self.state = state
    self.route = route
    self.failureCode = failureCode
  }

  public static let loading = HealthWorkoutRouteSnapshot(state: .loading)
  public static let unavailable = HealthWorkoutRouteSnapshot(state: .unavailable)
  public static let cancelled = HealthWorkoutRouteSnapshot(state: .cancelled)

  public static func failed(code: String) -> Self {
    .init(state: .failed, failureCode: code)
  }

  public static func ready(_ route: HealthWorkoutRoute) -> Self {
    .init(state: .ready, route: route)
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
  func saveHealthWorkoutRoute(_ route: HealthWorkoutRoute) async throws
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

  public init(
    client: any HealthWorkoutRouteClient,
    repository: any HealthWorkoutRouteRepository,
    maximumRetainedPoints: Int = HealthWorkoutRoute.maximumRetainedPoints,
    resourceProvider: any HealthWorkoutRouteResourceProviding =
      UnconstrainedHealthWorkoutRouteResourceProvider()
  ) {
    precondition(maximumRetainedPoints > 0)
    precondition(maximumRetainedPoints <= HealthWorkoutRoute.maximumRetainedPoints)
    self.client = client
    self.repository = repository
    self.maximumRetainedPoints = maximumRetainedPoints
    self.resourceProvider = resourceProvider
  }

  public func state(for healthKitUUID: String) async -> HealthWorkoutRouteSnapshot {
    if let state = states[healthKitUUID] { return state }
    if let route = try? await repository.loadHealthWorkoutRoute(for: healthKitUUID) {
      let ready = HealthWorkoutRouteSnapshot.ready(route)
      states[healthKitUUID] = ready
      return ready
    }
    return .unavailable
  }

  public func openRoute(for healthKitUUID: String) async -> HealthWorkoutRouteSnapshot {
    if let route = try? await repository.loadHealthWorkoutRoute(for: healthKitUUID) {
      let ready = HealthWorkoutRouteSnapshot.ready(route)
      states[healthKitUUID] = ready
      return ready
    }

    while let operation = inFlight {
      let result = await operation.task.value
      if inFlight?.healthKitUUID == operation.healthKitUUID {
        inFlight = nil
        states[operation.healthKitUUID] = result
      }
      if operation.healthKitUUID == healthKitUUID {
        return result
      }
    }

    states[healthKitUUID] = .loading
    let client = self.client
    let repository = self.repository
    let resourceProvider = self.resourceProvider
    let maximumRetainedPoints = self.maximumRetainedPoints
    let task = Task<HealthWorkoutRouteSnapshot, Never> {
      do {
        try Task.checkCancellation()
        guard await resourceProvider.currentRouteResources().permitsRouteWork else {
          return .failed(code: "route-resource-pressure")
        }
        let authorization = try await client.requestWorkoutRouteAuthorization()
        guard authorization == .authorized else { return .unavailable }
        try Task.checkCancellation()
        guard
          let route = try await client.fetchSimplifiedWorkoutRoute(
            for: healthKitUUID,
            maximumRetainedPoints: maximumRetainedPoints)
        else { return .unavailable }
        try Task.checkCancellation()
        guard route.healthKitUUID == healthKitUUID,
          route.points.count <= maximumRetainedPoints
        else { return .failed(code: "route-identity-or-size-mismatch") }
        guard await resourceProvider.currentRouteResources().permitsRouteWork else {
          return .failed(code: "route-resource-pressure")
        }
        try await repository.saveHealthWorkoutRoute(route)
        try Task.checkCancellation()
        return .ready(route)
      } catch is CancellationError {
        return .cancelled
      } catch {
        return .failed(code: "route-operation-failed")
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
    guard inFlight?.healthKitUUID == healthKitUUID else { return }
    inFlight?.task.cancel()
  }
}
