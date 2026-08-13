import Foundation
import XCTest

@testable import TrainingApplication

final class HealthWorkoutBoundaryTests: XCTestCase {
  func testConnectRequestsReadOnlyCoreTypesAndImportsEveryPage() async throws {
    let client = FakeHealthClient(pages: [
      HealthWorkoutPage(workouts: [fixture("one")], nextPageToken: "next"),
      HealthWorkoutPage(workouts: [fixture("two")]),
    ])
    let repository = FakeHealthRepository()
    let boundary = HealthWorkoutImportBoundary(client: client, repository: repository)

    let authorization = try await boundary.connectHealth()
    XCTAssertEqual(authorization.state, .authorized)
    let request = await client.lastRequest
    XCTAssertEqual(request?.writeTypes, [])
    XCTAssertEqual(request?.readTypes, HealthAuthorizationRequest.core.readTypes)

    let progressCollector = ProgressCollector()
    let result = try await boundary.importWorkouts { update in
      await progressCollector.append(update)
    }
    XCTAssertEqual(result.state, .available)
    XCTAssertEqual(result.importedCount, 2)
    let committed = await repository.committed
    XCTAssertEqual(committed.map(\.healthKitUUID), ["one", "two"])
    let progress = await progressCollector.values
    XCTAssertTrue(progress.contains { $0.firstBatchVisible && !$0.isComplete })
    XCTAssertTrue(progress.last?.isComplete == true)
  }

  func testPostponingDoesNotRequestAccessAndLocalImportRemainsUnaffected() async throws {
    let client = FakeHealthClient(pages: [])
    let repository = FakeHealthRepository()
    let boundary = HealthWorkoutImportBoundary(client: client, repository: repository)
    await boundary.postponeHealth()

    let result = try await boundary.importWorkouts()
    XCTAssertEqual(result.state, .postponed)
    let request = await client.lastRequest
    XCTAssertNil(request)
    let committed = await repository.committed
    XCTAssertTrue(committed.isEmpty)
  }

  func testSuccessfulEmptyResultIsNotReportedAsDenied() async throws {
    let client = FakeHealthClient(pages: [HealthWorkoutPage(workouts: [])])
    let repository = FakeHealthRepository()
    let boundary = HealthWorkoutImportBoundary(
      client: client,
      repository: repository,
      authorization: .init(state: .authorized)
    )

    let result = try await boundary.importWorkouts()
    XCTAssertEqual(result.state, .successfulEmpty)
    let committed = await repository.committed
    XCTAssertTrue(committed.isEmpty)
  }

  func testLimitedHistoryIsRetainedInAuthorizationSnapshot() async throws {
    let client = FakeHealthClient(
      pages: [HealthWorkoutPage(workouts: [fixture("limited")], hasLimitedHistory: true)])
    let boundary = HealthWorkoutImportBoundary(
      client: client,
      repository: FakeHealthRepository(),
      authorization: .init(state: .authorized)
    )

    let result = try await boundary.importWorkouts()
    XCTAssertEqual(result.state, .limitedHistory)
    XCTAssertTrue(result.hasLimitedHistory)
    let authorization = await boundary.authorizationSnapshot()
    XCTAssertTrue(authorization.hasLimitedHistory)
  }

  func testCoordinatorResumesFromCommittedAnchorAndCoalescesTriggers() async throws {
    let client = SequencedHealthClient(pages: [
      HealthWorkoutPage(workouts: [fixture("one")], nextPageToken: "anchor-1"),
      HealthWorkoutPage(workouts: [], deletedHealthKitUUIDs: ["one"]),
    ])
    let repository = SyncRepository()
    let coordinator = HealthSyncCoordinator(client: client, repository: repository)

    async let first = coordinator.foreground()
    async let second = coordinator.observerInvalidated()
    let firstResult = try await first
    let secondResult = try await second
    XCTAssertEqual(firstResult.pagesCommitted, 2)
    XCTAssertEqual(secondResult.pagesCommitted, 2)
    let anchors = await client.requestedAnchors
    let checkpoint = await repository.checkpoint
    let loaded = try await repository.loadHealthWorkouts()
    XCTAssertEqual(anchors, [nil, "anchor-1"])
    XCTAssertEqual(checkpoint?.anchor, nil)
    XCTAssertTrue(loaded.isEmpty)
  }

  private func fixture(_ id: String) -> HealthWorkout {
    HealthWorkout(
      healthKitUUID: id,
      activityType: "traditional-strength-training",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_600),
      duration: 600,
      sourceName: "Synthetic Health",
      sourceBundleIdentifier: "com.example.synthetic",
      sourceTimeZoneIdentifier: "UTC",
      timeZoneSource: .sourceMetadata,
      firstImportedAt: Date(timeIntervalSince1970: 1_700_000_700),
      reconciliationContext: "test"
    )
  }
}

private actor FakeHealthClient: HealthWorkoutClient {
  let pages: [HealthWorkoutPage]
  private(set) var pageIndex = 0
  private(set) var lastRequest: HealthAuthorizationRequest?

  init(pages: [HealthWorkoutPage]) { self.pages = pages }

  func requestAuthorization() async throws -> HealthAuthorizationResult { .requestCompleted }

  func requestHealthAuthorization(
    _ request: HealthAuthorizationRequest
  ) async throws -> HealthAuthorizationSnapshot {
    lastRequest = request
    return .init(state: .authorized, requested: request)
  }

  func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage {
    defer { pageIndex += 1 }
    return pages[min(pageIndex, max(0, pages.count - 1))]
  }
}

private actor FakeHealthRepository: HealthWorkoutRepository {
  private(set) var committed: [HealthWorkout] = []

  func upsertHealthWorkouts(_ workouts: [HealthWorkout], reconciliationContext: String) async throws
  {
    committed.append(contentsOf: workouts)
  }

  func loadHealthWorkouts() async throws -> [HealthWorkout] { committed }
}

private actor ProgressCollector {
  private(set) var values: [HealthWorkoutImportProgress] = []
  func append(_ value: HealthWorkoutImportProgress) { values.append(value) }
}

private actor SequencedHealthClient: HealthWorkoutClient {
  let pages: [HealthWorkoutPage]
  private(set) var requestedAnchors: [String?] = []
  private var index = 0

  init(pages: [HealthWorkoutPage]) { self.pages = pages }

  func requestAuthorization() async throws -> HealthAuthorizationResult { .requestCompleted }

  func requestHealthAuthorization(
    _ request: HealthAuthorizationRequest
  ) async throws -> HealthAuthorizationSnapshot {
    .init(state: .authorized, requested: request)
  }

  func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage {
    requestedAnchors.append(pageToken)
    let page = pages[min(index, pages.count - 1)]
    index += 1
    return page
  }
}

private actor SyncRepository: HealthWorkoutRepository {
  private var values: [HealthWorkout] = []
  private(set) var checkpoint: HealthSyncCheckpoint?

  func upsertHealthWorkouts(_ workouts: [HealthWorkout], reconciliationContext: String) async throws
  {
    values = workouts
  }

  func loadHealthWorkouts() async throws -> [HealthWorkout] { values }

  func commitHealthWorkoutPage(
    _ page: HealthWorkoutPage,
    stream: HealthSyncStream,
    limits: HealthSyncBatchLimits
  ) async throws {
    for uuid in page.deletedHealthKitUUIDs { values.removeAll { $0.healthKitUUID == uuid } }
    for workout in page.workouts {
      values.removeAll { $0.healthKitUUID == workout.healthKitUUID }
      values.append(workout)
    }
    checkpoint = HealthSyncCheckpoint(
      stream: stream,
      anchor: page.nextAnchor,
      reconciliationContext: page.reconciliationContext
    )
  }

  func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws -> HealthSyncCheckpoint?
  {
    checkpoint
  }
}
