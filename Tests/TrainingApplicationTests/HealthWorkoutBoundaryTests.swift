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

  func testHealthStatusDerivesIndependentCoverageAndCompactLanguage() {
    let checked = HealthStreamStatus(
      stream: .workouts,
      authorization: .authorized,
      coverage: .available,
      mirroredContent: .available,
      lastSuccessfulCheck: Date(timeIntervalSince1970: 1_700_000_000)
    )
    XCTAssertEqual(checked.statusLabel, "Checked")
    XCTAssertEqual(checked.historyLabel, "History: History available")
    XCTAssertEqual(checked.contentLabel, "Content: Mirrored content available")
    XCTAssertTrue(checked.lastCheckedLabel.hasPrefix("Last checked:"))

    let empty = HealthStreamStatus(
      stream: .sleep,
      authorization: .authorized,
      coverage: .available,
      mirroredContent: .empty,
      lastSuccessfulCheck: Date(timeIntervalSince1970: 1_700_000_000)
    )
    XCTAssertEqual(empty.statusLabel, "Checked · successful empty")

    let updating = HealthStreamStatus(
      stream: .heartRate,
      authorization: .authorized,
      mirroredContent: .available,
      reconciliation: .updating,
      lastSuccessfulCheck: Date(timeIntervalSince1970: 1_700_000_000)
    )
    XCTAssertEqual(updating.statusLabel, "Updating")
    XCTAssertEqual(updating.attentionLabel, nil)

    let firstFailure = HealthStreamStatus(
      stream: .activeEnergy,
      authorization: .authorized,
      failure: .init(code: "health-check-failed")
    )
    XCTAssertTrue(firstFailure.statusLabel.contains("first check failed"))
    XCTAssertTrue(firstFailure.attentionLabel?.contains("Refresh Health Data") == true)
  }

  func testCoordinatorReportsAStatusForEveryRequestedStreamWithoutClaimingPermission()
    async
    throws
  {
    let client = FakeHealthClient(pages: [HealthWorkoutPage(workouts: [])])
    let repository = FakeHealthRepository()
    let coordinator = HealthSyncCoordinator(
      client: client,
      repository: repository,
      requestedStreams: HealthSyncStream.allCases,
      authorization: .init(state: .authorized)
    )

    let result = try await coordinator.foreground()
    XCTAssertEqual(result.streamStatuses.map(\.stream), HealthSyncStream.allCases)
    XCTAssertEqual(
      result.streamStatuses.first(where: { $0.stream == .workouts })?.statusLabel, "Checked")
    XCTAssertEqual(result.streamStatuses.count, HealthReadType.allCases.count)
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

  func testCoordinatorPreservesCachedStateOnPartialFailureAndRecovers() async throws {
    let client = FlakyHealthClient(workout: fixture("cached"))
    let repository = SyncRepository()
    let coordinator = HealthSyncCoordinator(
      client: client,
      repository: repository,
      requestedStreams: [.workouts, .sleep],
      authorization: .init(state: .authorized)
    )

    let first = try await coordinator.foreground()
    XCTAssertEqual(
      first.streamStatuses.first(where: { $0.stream == .workouts })?.statusLabel, "Checked")

    await client.setFailure(for: .sleep, enabled: true)
    let partial = try await coordinator.retry()
    let workoutStatus = try XCTUnwrap(
      partial.streamStatuses.first(where: { $0.stream == .workouts }))
    let sleepStatus = try XCTUnwrap(partial.streamStatuses.first(where: { $0.stream == .sleep }))
    XCTAssertNil(workoutStatus.failure)
    XCTAssertNotNil(sleepStatus.failure)
    XCTAssertTrue(sleepStatus.statusLabel.contains("cached data remains available"))

    await client.setFailure(for: .sleep, enabled: false)
    let recovered = try await coordinator.retry()
    XCTAssertNil(recovered.streamStatuses.first(where: { $0.stream == .sleep })?.failure)
  }

  func testHealthHistoryIsReverseChronologicalAndRetainsSourceAndReconciliationContext()
    async throws
  {
    let older = fixture("older")
    let newer = HealthWorkout(
      healthKitUUID: "newer",
      activityType: "running",
      startDate: older.startDate.addingTimeInterval(3_600),
      endDate: older.endDate.addingTimeInterval(3_600),
      duration: 900,
      sourceName: "Phone",
      sourceBundleIdentifier: "com.example.phone",
      sourceProductType: "iPhone",
      deviceName: "Owner iPhone",
      sourceTimeZoneIdentifier: "UTC",
      localDate: older.localDate,
      timeZoneSource: .sourceMetadata,
      firstImportedAt: older.firstImportedAt,
      reconciliationContext: "page-newer"
    )
    let repository = HistoryRepository(
      workouts: [older, newer],
      checkpoint: HealthSyncCheckpoint(
        stream: .workouts,
        anchor: "anchor-2",
        reconciliationContext: "observer-success",
        committedAt: Date(timeIntervalSince1970: 1_700_001_000)
      )
    )
    let boundary = HealthWorkoutImportBoundary(
      client: FakeHealthClient(pages: []),
      repository: repository,
      authorization: .init(state: .authorized)
    )

    let history = try await boundary.healthWorkoutHistory()

    XCTAssertEqual(history.state, .available)
    XCTAssertEqual(history.events.map(\.id), ["newer", "older"])
    XCTAssertEqual(history.events.first?.event.source, .health)
    XCTAssertEqual(history.events.first?.event.sourceBadge, "Health")
    XCTAssertEqual(history.events.first?.event.reconciliationContext, "observer-success")
    XCTAssertEqual(
      history.events.first?.event.lastSuccessfulReconciliation,
      Date(timeIntervalSince1970: 1_700_001_000)
    )
    XCTAssertEqual(history.events.first?.provenance.sourceName, "Phone")
  }

  func testTodayHealthHistoryUsesStableLocalDateAndDoesNotLinkToSession() async throws {
    let workout = fixture("today")
    let repository = HistoryRepository(workouts: [workout])
    let boundary = HealthWorkoutImportBoundary(
      client: FakeHealthClient(pages: []),
      repository: repository,
      authorization: .init(state: .authorized)
    )

    let events = try await boundary.todayHealthWorkouts(
      on: TrainingDate(year: 2023, month: 11, day: 14))

    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.event.kind, .healthWorkout)
    XCTAssertNil(events.first?.event.localSessionID)
    XCTAssertEqual(events.first?.event.localDate, "2023-11-14")
  }

  func testHistoryDeduplicatesRepeatedHealthKitUUIDsAndRetainsDeviceTimezoneSource()
    async
    throws
  {
    let first = HealthWorkout(
      healthKitUUID: "same-uuid",
      activityType: "running",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_060),
      duration: 60,
      localDate: "2023-11-14",
      timeZoneSource: .deviceAtFirstImport
    )
    let replacement = HealthWorkout(
      healthKitUUID: first.healthKitUUID,
      activityType: "cycling",
      startDate: first.startDate,
      endDate: first.endDate,
      duration: first.duration,
      localDate: first.localDate,
      timeZoneSource: .deviceAtFirstImport,
      reconciliationContext: "replacement"
    )
    let boundary = HealthWorkoutImportBoundary(
      client: FakeHealthClient(pages: []),
      repository: HistoryRepository(workouts: [first, replacement]),
      authorization: .init(state: .authorized)
    )

    let history = try await boundary.healthWorkoutHistory()

    XCTAssertEqual(history.events.count, 1)
    XCTAssertEqual(history.events.first?.event.activityType, "cycling")
    XCTAssertEqual(history.events.first?.event.timeZoneSource, .deviceAtFirstImport)
  }

  func testHistoryDistinguishesSuccessfulEmptyAndMissingProvenance() async throws {
    let emptyBoundary = HealthWorkoutImportBoundary(
      client: FakeHealthClient(pages: []),
      repository: HistoryRepository(),
      authorization: .init(state: .authorized)
    )
    let empty = try await emptyBoundary.healthWorkoutHistory()
    XCTAssertEqual(empty.state, .successfulEmpty)

    let noProvenance = HealthWorkout(
      healthKitUUID: "no-provenance",
      activityType: "other",
      startDate: Date(timeIntervalSince1970: 1_700_000_000),
      endDate: Date(timeIntervalSince1970: 1_700_000_060),
      duration: 60,
      localDate: "2023-11-14",
      timeZoneSource: .unavailable
    )
    let provenanceBoundary = HealthWorkoutImportBoundary(
      client: FakeHealthClient(pages: []),
      repository: HistoryRepository(workouts: [noProvenance]),
      authorization: .init(state: .authorized)
    )
    let provenance = try await provenanceBoundary.healthWorkoutHistory()
    XCTAssertEqual(provenance.events.first?.state, .unavailableProvenance)
    XCTAssertEqual(provenance.events.first?.provenance.displayName, "Source unavailable")
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

private actor FlakyHealthClient: HealthWorkoutClient {
  let workout: HealthWorkout
  private var failures: Set<HealthSyncStream> = []

  init(workout: HealthWorkout) { self.workout = workout }

  func requestAuthorization() async throws -> HealthAuthorizationResult { .requestCompleted }

  func requestHealthAuthorization(
    _ request: HealthAuthorizationRequest
  ) async throws -> HealthAuthorizationSnapshot {
    .init(state: .authorized, requested: request)
  }

  func setFailure(for stream: HealthSyncStream, enabled: Bool) {
    if enabled { failures.insert(stream) } else { failures.remove(stream) }
  }

  func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage {
    try await fetchHealthPage(for: .workouts, after: pageToken)
  }

  func fetchHealthPage(
    for stream: HealthSyncStream, after pageToken: String?
  ) async throws -> HealthWorkoutPage {
    if failures.contains(stream) { throw HealthSyncError.unavailable }
    return stream == .workouts
      ? HealthWorkoutPage(workouts: [workout])
      : HealthWorkoutPage(workouts: [])
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

  func loadHealthMirrorContent(for stream: HealthSyncStream) async throws
    -> HealthMirrorContentSnapshot
  {
    .init(stream: stream, recordCount: stream == .workouts && !values.isEmpty ? values.count : 0)
  }
}

private actor HistoryRepository: HealthWorkoutRepository {
  private var values: [HealthWorkout]
  private let storedCheckpoint: HealthSyncCheckpoint?

  init(
    workouts: [HealthWorkout] = [],
    checkpoint: HealthSyncCheckpoint? = HealthSyncCheckpoint(
      stream: .workouts,
      anchor: "history-anchor",
      reconciliationContext: "initial",
      committedAt: Date(timeIntervalSince1970: 1_700_000_800)
    )
  ) {
    self.values = workouts
    self.storedCheckpoint = checkpoint
  }

  func upsertHealthWorkouts(_ workouts: [HealthWorkout], reconciliationContext: String) async throws
  {
    values = workouts
  }

  func loadHealthWorkouts() async throws -> [HealthWorkout] { values }

  func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws -> HealthSyncCheckpoint?
  {
    stream == .workouts ? storedCheckpoint : nil
  }

  func loadHealthMirrorContent(for stream: HealthSyncStream) async throws
    -> HealthMirrorContentSnapshot
  {
    .init(stream: stream, recordCount: stream == .workouts ? values.count : 0)
  }
}
