import Foundation
import XCTest

@testable import TrainingApplication

final class HealthWorkoutRouteBoundaryTests: XCTestCase {
  func testWorkoutImportAndOrdinaryEnrichmentNeverPrefetchRoute() async throws {
    let workout = routeWorkout("import-without-route-prefetch")
    let client = ImportAndRouteClient(
      workout: workout,
      route: retainedRoute(for: workout.healthKitUUID))
    let repository = RouteRepository()
    let importBoundary = HealthWorkoutImportBoundary(
      client: client,
      repository: repository,
      authorization: .init(
        state: .authorized,
        requested: HealthAuthorizationRequest(readTypes: [.workouts])))

    _ = try await importBoundary.importWorkouts()

    let afterImport = await client.routeCounts()
    XCTAssertEqual(afterImport, .init(authorizationRequests: 0, fetches: 0))

    let routeBoundary = HealthWorkoutRouteBoundary(client: client, repository: repository)
    _ = await routeBoundary.openRoute(for: workout.healthKitUUID)

    let afterDetailOpen = await client.routeCounts()
    XCTAssertEqual(afterDetailOpen, .init(authorizationRequests: 1, fetches: 1))
  }

  func testRouteAuthorizationAndFetchStartOnlyWhenWorkoutDetailOpens() async throws {
    let workout = routeWorkout("on-demand")
    let route = retainedRoute(for: workout.healthKitUUID)
    let client = RouteClient(results: [.success(route)])
    let repository = RouteRepository()
    let boundary = HealthWorkoutRouteBoundary(client: client, repository: repository)

    let initialAuthorizationRequests = await client.authorizationRequestCount
    let initialFetches = await client.fetchCount
    let initialState = await boundary.state(for: workout.healthKitUUID)
    XCTAssertEqual(initialAuthorizationRequests, 0)
    XCTAssertEqual(initialFetches, 0)
    XCTAssertEqual(initialState.state, .unavailable)

    let result = await boundary.openRoute(for: workout.healthKitUUID)

    XCTAssertEqual(result, .ready(route))
    let authorizationRequests = await client.authorizationRequestCount
    let fetches = await client.fetchCount
    let persisted = try await repository.loadHealthWorkoutRoute(for: workout.healthKitUUID)
    XCTAssertEqual(authorizationRequests, 1)
    XCTAssertEqual(fetches, 1)
    XCTAssertEqual(persisted, route)
  }

  func testOverlappingDetailOpensShareOneOperationPerWorkoutAndSerializeDifferentWorkouts()
    async
  {
    let firstWorkout = routeWorkout("first")
    let secondWorkout = routeWorkout("second")
    let client = SuspendedRouteClient(
      routes: [
        firstWorkout.healthKitUUID: retainedRoute(for: firstWorkout.healthKitUUID),
        secondWorkout.healthKitUUID: retainedRoute(for: secondWorkout.healthKitUUID),
      ])
    let boundary = HealthWorkoutRouteBoundary(client: client, repository: RouteRepository())

    let first = Task { await boundary.openRoute(for: firstWorkout.healthKitUUID) }
    let duplicate = Task { await boundary.openRoute(for: firstWorkout.healthKitUUID) }
    let second = Task { await boundary.openRoute(for: secondWorkout.healthKitUUID) }
    await client.waitUntilFetchStarts()

    let loading = await boundary.state(for: firstWorkout.healthKitUUID)
    let suspendedCounts = await client.counts()
    XCTAssertEqual(loading.state, .loading)
    XCTAssertEqual(suspendedCounts, .init(fetches: 1, peakConcurrentFetches: 1))

    await client.resumeAll()
    let firstResult = await first.value
    let duplicateResult = await duplicate.value
    let secondResult = await second.value
    let completedCounts = await client.counts()
    XCTAssertEqual(firstResult.state, .ready)
    XCTAssertEqual(duplicateResult.state, .ready)
    XCTAssertEqual(secondResult.state, .ready)
    XCTAssertEqual(completedCounts, .init(fetches: 2, peakConcurrentFetches: 1))
  }

  func testCancellationAndPersistenceFailureNeverRepresentAPartialRouteAsReady() async throws {
    let cancelledWorkout = routeWorkout("cancelled")
    let cancelledClient = SuspendedRouteClient(
      routes: [cancelledWorkout.healthKitUUID: retainedRoute(for: cancelledWorkout.healthKitUUID)])
    let cancelledRepository = RouteRepository()
    let cancelledBoundary = HealthWorkoutRouteBoundary(
      client: cancelledClient, repository: cancelledRepository)
    let operation = Task {
      await cancelledBoundary.openRoute(for: cancelledWorkout.healthKitUUID)
    }
    await cancelledClient.waitUntilFetchStarts()

    await cancelledBoundary.cancelRoute(for: cancelledWorkout.healthKitUUID)

    let cancelled = await operation.value
    XCTAssertEqual(cancelled.state, .cancelled)
    let cancelledPersisted = try await cancelledRepository.loadHealthWorkoutRoute(
      for: cancelledWorkout.healthKitUUID)
    XCTAssertNil(cancelledPersisted)

    let failedWorkout = routeWorkout("persistence-failure")
    let failedBoundary = HealthWorkoutRouteBoundary(
      client: RouteClient(results: [.success(retainedRoute(for: failedWorkout.healthKitUUID))]),
      repository: RouteRepository(failsOnSave: true))

    let failed = await failedBoundary.openRoute(for: failedWorkout.healthKitUUID)

    XCTAssertEqual(failed.state, .failed)
    XCTAssertNil(failed.route)
  }

  func testResourcePressureRefusesWorkBeforeAuthorizationAndBeforePersistence() async throws {
    let workout = routeWorkout("resource-pressure")
    let route = retainedRoute(for: workout.healthKitUUID)
    let client = RouteClient(results: [.success(route)])
    let constrained = RouteResourceProvider(
      snapshots: [
        .init(
          availableStorageBytes: 499 * 1_024 * 1_024,
          lowPowerModeEnabled: false,
          batteryLevel: 1,
          thermalState: .nominal)
      ])
    let boundary = HealthWorkoutRouteBoundary(
      client: client,
      repository: RouteRepository(),
      resourceProvider: constrained)

    let result = await boundary.openRoute(for: workout.healthKitUUID)
    let constrainedCounts = await client.counts()

    XCTAssertEqual(result.state, .failed)
    XCTAssertEqual(result.failureCode, "route-resource-pressure")
    XCTAssertEqual(constrainedCounts, .init(authorizationRequests: 0, fetches: 0))

    let afterFetchRepository = RouteRepository()
    let changesAfterFetch = RouteResourceProvider(
      snapshots: [
        .unconstrained,
        .init(
          availableStorageBytes: .max,
          lowPowerModeEnabled: false,
          batteryLevel: 0.19,
          thermalState: .nominal),
      ])
    let afterFetchBoundary = HealthWorkoutRouteBoundary(
      client: RouteClient(results: [.success(route)]),
      repository: afterFetchRepository,
      resourceProvider: changesAfterFetch)

    let afterFetch = await afterFetchBoundary.openRoute(for: workout.healthKitUUID)
    let afterFetchPersisted = try await afterFetchRepository.loadHealthWorkoutRoute(
      for: workout.healthKitUUID)

    XCTAssertEqual(afterFetch.state, .failed)
    XCTAssertNil(afterFetchPersisted)
  }

  func testUnavailableIdentityMismatchAndRetryRemainBoundToTheExactWorkout() async throws {
    let workout = routeWorkout("exact-workout")
    let unavailableClient = RouteClient(results: [.success(nil)])
    let unavailableBoundary = HealthWorkoutRouteBoundary(
      client: unavailableClient,
      repository: RouteRepository())

    let unavailable = await unavailableBoundary.openRoute(for: workout.healthKitUUID)

    XCTAssertEqual(unavailable.state, .unavailable)

    let mismatched = retainedRoute(for: "different-workout")
    let expected = retainedRoute(for: workout.healthKitUUID)
    let retryRepository = RouteRepository()
    let retryClient = RouteClient(results: [.success(mismatched), .success(expected)])
    let retryBoundary = HealthWorkoutRouteBoundary(
      client: retryClient,
      repository: retryRepository)

    let failed = await retryBoundary.openRoute(for: workout.healthKitUUID)
    let retried = await retryBoundary.openRoute(for: workout.healthKitUUID)
    let persisted = try await retryRepository.loadHealthWorkoutRoute(for: workout.healthKitUUID)

    XCTAssertEqual(failed.failureCode, "route-identity-or-size-mismatch")
    XCTAssertNil(failed.route)
    XCTAssertEqual(retried, .ready(expected))
    XCTAssertEqual(persisted, expected)
  }

  private func routeWorkout(_ id: String) -> HealthWorkout {
    HealthWorkout(
      healthKitUUID: id,
      activityType: "running",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_600),
      duration: 600,
      sourceName: "Watch",
      sourceBundleIdentifier: "com.example.watch",
      sourceTimeZoneIdentifier: "UTC",
      localDate: "2023-11-14",
      timeZoneSource: .sourceMetadata,
      reconciliationContext: "route-test")
  }

  private func retainedRoute(for healthKitUUID: String) -> HealthWorkoutRoute {
    HealthWorkoutRoute(
      healthKitUUID: healthKitUUID,
      points: [
        .init(northSouthDegrees: 14.5995, eastWestDegrees: 120.9842),
        .init(northSouthDegrees: 14.6005, eastWestDegrees: 120.9852),
      ],
      originalPointCount: 2,
      sources: [
        .init(
          healthKitUUID: "route-1",
          provenance: .init(
            sourceName: "Watch", sourceBundleIdentifier: "com.example.watch"))
      ],
      retainedAt: Date(timeIntervalSince1970: 1_700_000_700),
      simplification: .boundedDouglasPeuckerV1,
      reconciliationContext: "workout-route-query")
  }
}

private actor RouteClient: HealthWorkoutRouteClient {
  struct Counts: Equatable {
    let authorizationRequests: Int
    let fetches: Int
  }

  private let results: [Result<HealthWorkoutRoute?, Error>]
  private var index = 0
  private(set) var authorizationRequestCount = 0
  private(set) var fetchCount = 0

  init(results: [Result<HealthWorkoutRoute?, Error>]) {
    self.results = results
  }

  func requestWorkoutRouteAuthorization() async throws -> HealthWorkoutRouteAuthorizationState {
    authorizationRequestCount += 1
    return .authorized
  }

  func fetchSimplifiedWorkoutRoute(
    for healthKitUUID: String,
    maximumRetainedPoints: Int
  ) async throws -> HealthWorkoutRoute? {
    fetchCount += 1
    defer { index += 1 }
    return try results[min(index, results.count - 1)].get()
  }

  func counts() -> Counts {
    .init(authorizationRequests: authorizationRequestCount, fetches: fetchCount)
  }
}

private actor RouteRepository: HealthWorkoutRouteRepository, HealthWorkoutRepository {
  private var routes: [String: HealthWorkoutRoute] = [:]
  private var workouts: [HealthWorkout] = []
  private let failsOnSave: Bool

  init(failsOnSave: Bool = false) {
    self.failsOnSave = failsOnSave
  }

  func saveHealthWorkoutRoute(_ route: HealthWorkoutRoute) async throws {
    if failsOnSave { throw RouteTestError.persistence }
    routes[route.healthKitUUID] = route
  }

  func loadHealthWorkoutRoute(for healthKitUUID: String) async throws -> HealthWorkoutRoute? {
    routes[healthKitUUID]
  }

  func upsertHealthWorkouts(
    _ workouts: [HealthWorkout],
    reconciliationContext: String
  ) async throws {
    for workout in workouts {
      self.workouts.removeAll { $0.healthKitUUID == workout.healthKitUUID }
      self.workouts.append(workout)
    }
  }

  func loadHealthWorkouts() async throws -> [HealthWorkout] { workouts }
}

private enum RouteTestError: Error {
  case persistence
}

private actor SuspendedRouteClient: HealthWorkoutRouteClient {
  struct Counts: Equatable {
    let fetches: Int
    let peakConcurrentFetches: Int
  }

  private let routes: [String: HealthWorkoutRoute]
  private var fetches = 0
  private var activeFetches = 0
  private var peakConcurrentFetches = 0
  private var shouldSuspend = true

  init(routes: [String: HealthWorkoutRoute]) {
    self.routes = routes
  }

  func requestWorkoutRouteAuthorization() async throws -> HealthWorkoutRouteAuthorizationState {
    .authorized
  }

  func fetchSimplifiedWorkoutRoute(
    for healthKitUUID: String,
    maximumRetainedPoints: Int
  ) async throws -> HealthWorkoutRoute? {
    fetches += 1
    activeFetches += 1
    peakConcurrentFetches = max(peakConcurrentFetches, activeFetches)
    defer { activeFetches -= 1 }
    while shouldSuspend {
      try await Task.sleep(for: .milliseconds(10))
    }
    return routes[healthKitUUID]
  }

  func waitUntilFetchStarts() async {
    while fetches == 0 { await Task.yield() }
  }

  func resumeAll() {
    shouldSuspend = false
  }

  func counts() -> Counts {
    .init(fetches: fetches, peakConcurrentFetches: peakConcurrentFetches)
  }
}

private actor RouteResourceProvider: HealthWorkoutRouteResourceProviding {
  private let snapshots: [HealthWorkoutRouteResourceSnapshot]
  private var index = 0

  init(snapshots: [HealthWorkoutRouteResourceSnapshot]) {
    self.snapshots = snapshots
  }

  func currentRouteResources() async -> HealthWorkoutRouteResourceSnapshot {
    defer { index += 1 }
    return snapshots[min(index, snapshots.count - 1)]
  }
}

private actor ImportAndRouteClient: HealthWorkoutClient, HealthWorkoutRouteClient {
  struct Counts: Equatable {
    let authorizationRequests: Int
    let fetches: Int
  }

  private let workout: HealthWorkout
  private let route: HealthWorkoutRoute
  private var authorizationRequests = 0
  private var fetches = 0

  init(workout: HealthWorkout, route: HealthWorkoutRoute) {
    self.workout = workout
    self.route = route
  }

  func requestAuthorization() async throws -> HealthAuthorizationResult { .requestCompleted }

  func requestHealthAuthorization(
    _ request: HealthAuthorizationRequest
  ) async throws -> HealthAuthorizationSnapshot {
    .init(state: .authorized, requested: request)
  }

  func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage {
    .init(workouts: [workout], reconciliationContext: "ordinary-import")
  }

  func requestWorkoutRouteAuthorization() async throws -> HealthWorkoutRouteAuthorizationState {
    authorizationRequests += 1
    return .authorized
  }

  func fetchSimplifiedWorkoutRoute(
    for healthKitUUID: String,
    maximumRetainedPoints: Int
  ) async throws -> HealthWorkoutRoute? {
    fetches += 1
    return route.healthKitUUID == healthKitUUID ? route : nil
  }

  func routeCounts() -> Counts {
    .init(authorizationRequests: authorizationRequests, fetches: fetches)
  }
}
