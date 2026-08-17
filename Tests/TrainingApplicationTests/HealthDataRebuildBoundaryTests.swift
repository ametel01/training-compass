import Foundation
@testable import TrainingApplication
import XCTest

final class HealthDataRebuildBoundaryTests: XCTestCase {
    func testRebuildRequiresExplicitConfirmationAndStorageMargin() async throws {
        let repository = RebuildRepository()
        let boundary = HealthDataRebuildBoundary(
            client: RebuildClient(pages: []),
            repository: repository,
            authorization: .init(state: .authorized),
            requestedStreams: [.workouts],
            storageProvider: FixedStorageProvider(
                estimate: .init(stagingBytes: 100, safetyMarginBytes: 50, availableBytes: 149),
            ),
        )

        do {
            _ = try await boundary.rebuild(confirmation: .confirmed)
            XCTFail("expected storage refusal")
        } catch let HealthRebuildError.insufficientStorage(required, available) {
            XCTAssertEqual(required, 150)
            XCTAssertEqual(available, 149)
        }
        let didBegin = await repository.didBegin
        XCTAssertFalse(didBegin)
    }

    func testRebuildPausesBeforeMutationWhenResourcesAreConstrained() async throws {
        let repository = RebuildRepository()
        let client = RebuildClient(
            pages: [HealthWorkoutPage(workouts: [fixture("must-not-fetch")], anchor: nil)],
        )
        let boundary = HealthDataRebuildBoundary(
            client: client,
            repository: repository,
            authorization: .init(state: .authorized),
            requestedStreams: [.workouts],
            storageProvider: FixedStorageProvider(
                estimate: .init(stagingBytes: 1, safetyMarginBytes: 1, availableBytes: 2),
            ),
            resourceProvider: FixedResourceProvider(
                snapshot: .init(
                    lowPowerModeEnabled: true,
                    batteryLevel: 0.19,
                    thermalState: .serious,
                ),
            ),
        )

        do {
            _ = try await boundary.rebuild(confirmation: .confirmed)
            XCTFail("expected discretionary rebuild pause")
        } catch HealthRebuildError.resourcePressure {
            // Expected: the owner can retry when the device is ready.
        }
        let didBegin = await repository.didBegin
        let state = await repository.state
        let values = await repository.values
        XCTAssertFalse(didBegin)
        XCTAssertEqual(state?.phase, .paused)
        XCTAssertTrue(values.isEmpty)
    }

    func testResourceSnapshotPausesForEachDiscretionaryConstraint() {
        XCTAssertTrue(HealthRebuildResourceSnapshot.unconstrained.permitsDiscretionaryWork)
        XCTAssertFalse(
            HealthRebuildResourceSnapshot(
                availableStorageBytes: HealthRebuildResourceSnapshot.minimumAvailableStorageBytes - 1,
                lowPowerModeEnabled: false,
                batteryLevel: nil,
                thermalState: .nominal,
            ).permitsDiscretionaryWork,
        )
        XCTAssertFalse(
            HealthRebuildResourceSnapshot(
                lowPowerModeEnabled: true, batteryLevel: nil, thermalState: .nominal,
            ).permitsDiscretionaryWork,
        )
        XCTAssertFalse(
            HealthRebuildResourceSnapshot(
                lowPowerModeEnabled: false, batteryLevel: 0.19, thermalState: .nominal,
            ).permitsDiscretionaryWork,
        )
        XCTAssertFalse(
            HealthRebuildResourceSnapshot(
                lowPowerModeEnabled: false, batteryLevel: nil, thermalState: .critical,
            ).permitsDiscretionaryWork,
        )
    }

    func testRebuildCommitsBatchesRegeneratesProjectionsAndCompletes() async throws {
        let workout = fixture("returning-uuid")
        let repository = RebuildRepository()
        let boundary = HealthDataRebuildBoundary(
            client: RebuildClient(
                pages: [
                    HealthWorkoutPage(workouts: [workout], anchor: "batch-1"),
                    HealthWorkoutPage(workouts: [], anchor: nil),
                ],
            ),
            repository: repository,
            authorization: .init(state: .authorized),
            requestedStreams: [.workouts],
            storageProvider: FixedStorageProvider(
                estimate: .init(stagingBytes: 1, safetyMarginBytes: 1, availableBytes: 2),
            ),
        )

        let result = try await boundary.rebuild(confirmation: .confirmed)
        XCTAssertEqual(result.pagesCommitted, 2)
        XCTAssertEqual(result.additionsOrReplacements, 1)
        let didBegin = await repository.didBegin
        let didRegenerate = await repository.didRegenerate
        let values = await repository.values.map(\.healthKitUUID)
        XCTAssertTrue(didBegin)
        XCTAssertTrue(didRegenerate)
        XCTAssertEqual(values, ["returning-uuid"])
        XCTAssertEqual(result.state.phase, .completed)
    }

    func testRebuildResumesFromDurableCheckpointAfterCancellation() async throws {
        let repository = RebuildRepository()
        let client = RebuildClient(
            pages: [
                HealthWorkoutPage(workouts: [fixture("one")], anchor: "batch-1"),
                HealthWorkoutPage(workouts: [fixture("two")], anchor: nil),
            ],
            pauseAfterFirstPage: true,
        )
        let boundary = HealthDataRebuildBoundary(
            client: client,
            repository: repository,
            authorization: .init(state: .authorized),
            requestedStreams: [.workouts],
            storageProvider: FixedStorageProvider(
                estimate: .init(stagingBytes: 1, safetyMarginBytes: 1, availableBytes: 2),
            ),
        )

        let task = Task {
            try await boundary.rebuild(confirmation: .confirmed)
        }
        await client.waitUntilPaused()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch HealthRebuildError.cancelled {
            let state = await repository.state
            XCTAssertEqual(state?.phase, .paused)
        }

        await client.resume()
        let result = try await boundary.rebuild(confirmation: .confirmed)
        XCTAssertTrue(result.resumed)
        let anchors = await client.anchors
        XCTAssertEqual(anchors, [nil, "batch-1", "batch-1"])
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
            reconciliationContext: "rebuild-test",
        )
    }
}

private struct FixedStorageProvider: HealthRebuildStorageProviding {
    let estimate: HealthRebuildStorageEstimate

    func estimateHealthRebuildStorage(
        policy _: HealthRebuildStoragePolicy,
    ) async throws -> HealthRebuildStorageEstimate {
        estimate
    }
}

private struct FixedResourceProvider: HealthRebuildResourceProviding {
    let snapshot: HealthRebuildResourceSnapshot

    func currentHealthRebuildResources() async -> HealthRebuildResourceSnapshot {
        snapshot
    }
}

private actor RebuildClient: HealthWorkoutClient {
    let pages: [HealthWorkoutPage]
    let pauseAfterFirstPage: Bool
    private(set) var index = 0
    private(set) var anchors: [String?] = []
    private var isPaused = false
    private var resumed = false

    init(pages: [HealthWorkoutPage], pauseAfterFirstPage: Bool = false) {
        self.pages = pages
        self.pauseAfterFirstPage = pauseAfterFirstPage
    }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        .requestCompleted
    }

    func requestHealthAuthorization(
        _ request: HealthAuthorizationRequest,
    ) async throws -> HealthAuthorizationSnapshot {
        .init(state: .authorized, requested: request)
    }

    func fetchWorkoutPage(after pageToken: String?) async throws -> HealthWorkoutPage {
        try await fetchHealthPage(for: .workouts, after: pageToken)
    }

    func fetchHealthPage(
        for _: HealthSyncStream, after pageToken: String?,
    ) async throws -> HealthWorkoutPage {
        anchors.append(pageToken)
        if pauseAfterFirstPage, index == 1, !resumed {
            isPaused = true
            try await Task.sleep(for: .seconds(60))
        }
        defer { index += 1 }
        return pages[min(index, pages.count - 1)]
    }

    func waitUntilPaused() async {
        while !isPaused {
            await Task.yield()
        }
    }

    func resume() {
        resumed = true
    }
}

private actor RebuildRepository: HealthWorkoutRepository {
    private(set) var values: [HealthWorkout] = []
    private(set) var state: HealthRebuildState?
    private(set) var checkpoint: HealthSyncCheckpoint?
    private(set) var didBegin = false
    private(set) var didRegenerate = false

    func upsertHealthWorkouts(_ workouts: [HealthWorkout], reconciliationContext _: String) async throws {
        values.append(contentsOf: workouts)
    }

    func loadHealthWorkouts() async throws -> [HealthWorkout] {
        values
    }

    func beginHealthRebuild() async throws {
        didBegin = true
        values.removeAll()
        state = .init(phase: .rebuilding)
        checkpoint = nil
    }

    func commitHealthWorkoutPage(
        _ page: HealthWorkoutPage,
        stream: HealthSyncStream,
        limits _: HealthSyncBatchLimits,
    ) async throws {
        for uuid in page.deletedHealthKitUUIDs {
            values.removeAll { $0.healthKitUUID == uuid }
        }
        for workout in page.workouts {
            values.removeAll { $0.healthKitUUID == workout.healthKitUUID }
            values.append(workout)
        }
        checkpoint = .init(
            stream: stream, anchor: page.nextAnchor, reconciliationContext: page.reconciliationContext,
        )
        state = state.map {
            HealthRebuildState(
                phase: $0.phase, completedStreams: $0.completedStreams, startedAt: $0.startedAt,
            )
        }
    }

    func loadHealthSyncCheckpoint(for _: HealthSyncStream) async throws -> HealthSyncCheckpoint? {
        checkpoint
    }

    func loadHealthMirrorContent(for stream: HealthSyncStream) async throws
        -> HealthMirrorContentSnapshot
    {
        .init(stream: stream, recordCount: values.count)
    }

    func loadHealthRebuildState() async throws -> HealthRebuildState? {
        state
    }

    func updateHealthRebuildState(_ state: HealthRebuildState) async throws {
        self.state = state
    }

    func regenerateHealthDerivedProjections() async throws {
        didRegenerate = true
    }
}
