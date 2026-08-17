import Foundation
@testable import TrainingApplication
@testable import TrainingPersistence
import XCTest

final class UnifiedEventsAcceptanceTests: XCTestCase {
    func testLinkedEventSurvivesLateEnrichmentDeletionExactReappearanceRebuildAndUnlink()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "unified-events-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        let cycle = unifiedAcceptanceCycle()
        _ = try await repository.saveTrainingCycle(
            cycle, expectedBefore: nil, auditID: "cycle-created", occurredAt: 10, action: .activated,
        )
        _ = try await repository.completeSession(
            CompletedSession(sessionID: "session", confirmedAt: 20), confirmation: .confirmed,
        )

        let exactWorkout = unifiedAcceptanceWorkout(
            id: "exact-healthkit-uuid", activity: "traditional-strength-training",
        )
        try await repository.commitHealthWorkoutPage(
            HealthWorkoutPage(
                workouts: [exactWorkout],
                anchor: "initial-anchor",
                reconciliationContext: "initial-import",
            ),
            stream: .workouts,
            limits: .default,
        )
        let loadedSessionSnapshot = try await repository.loadSessionCorrectionSnapshot(
            sessionID: "session",
        )
        let sessionSnapshot = try XCTUnwrap(loadedSessionSnapshot)
        let loadedWorkouts = try await repository.loadHealthWorkouts()
        let storedWorkout = try XCTUnwrap(loadedWorkouts.first)
        let link = HealthWorkoutLinkFact(
            id: "unified-link",
            healthKitUUID: exactWorkout.healthKitUUID,
            localEntityKind: .session,
            localEntityID: "session",
            linkedAt: Date(timeIntervalSince1970: 30),
        )
        _ = try await repository.createHealthWorkoutLinkFact(
            link,
            expectedSessionUpdatedAt: sessionSnapshot.updatedAt,
            expectedWorkout: storedWorkout,
        )
        let boundary = TrainingEventLinkBoundary(
            cycleRepository: repository,
            resultRepository: repository,
            healthRepository: repository,
            linkRepository: repository,
            clock: UnifiedAcceptanceClock(date: Date(timeIntervalSince1970: 80)),
            uuidGenerator: RandomUUIDGenerator(),
        )

        let initiallyLinked = try await boundary.timeline()
        XCTAssertEqual(initiallyLinked.aggregateCount, 1)
        let initialEvent = try XCTUnwrap(initiallyLinked.events.first)
        XCTAssertEqual(initialEvent.id, "training-event:unified-link")
        XCTAssertEqual(initialEvent.sourceBadges, [.localTraining, .health])
        XCTAssertEqual(initialEvent.session?.sessionID, "session")
        XCTAssertEqual(initialEvent.healthWorkout?.healthKitUUID, exactWorkout.healthKitUUID)
        XCTAssertEqual(initialEvent.healthWorkout?.sourceName, "Acceptance Watch")
        XCTAssertEqual(
            initialEvent.healthWorkout?.sourceBundleIdentifier, "com.example.acceptance",
        )
        XCTAssertEqual(initialEvent.linkState, .linked)
        XCTAssertEqual(initialEvent.reconciliationContext, "initial-import")
        XCTAssertEqual(
            initialEvent.disagreements,
            [.localDate(session: "2024-01-01", health: "2024-01-02")],
        )
        XCTAssertEqual(initialEvent.healthWorkoutEnrichment?.heartRate.state, .loading)
        let initialLinkHistory = try await repository.loadHealthWorkoutLinkFacts(for: nil)
        XCTAssertEqual(initialLinkHistory, [link])

        let checkedAt = Date(timeIntervalSince1970: 40)
        let enrichment = HealthWorkoutEnrichment(
            healthKitUUID: exactWorkout.healthKitUUID,
            heartRate: .available(
                samples: [
                    HealthWorkoutHeartRateSample(
                        id: "heart-rate-sample",
                        startDate: exactWorkout.startDate.addingTimeInterval(10),
                        endDate: exactWorkout.startDate.addingTimeInterval(15),
                        beatsPerMinute: 145,
                        provenance: .init(
                            sourceName: "Acceptance Watch",
                            sourceBundleIdentifier: "com.example.acceptance",
                        ),
                    ),
                ],
                checkedAt: checkedAt,
                reconciliationContext: "late-heart-rate",
            ),
            distance: .available(
                value: 5000,
                unit: .meters,
                checkedAt: checkedAt,
                reconciliationContext: "late-distance",
            ),
            activeEnergy: .notAvailableFromHealth(
                checkedAt: checkedAt,
                reconciliationContext: "late-energy-unavailable",
            ),
        )
        try await repository.saveHealthWorkoutEnrichment(enrichment)
        let route = unifiedAcceptanceRoute(for: exactWorkout.healthKitUUID)
        let routeSaved = try await repository.saveHealthWorkoutRoute(route)
        XCTAssertTrue(routeSaved)

        let enriched = try await boundary.timeline()
        XCTAssertEqual(enriched.aggregateCount, 1)
        let enrichedEvent = try XCTUnwrap(enriched.events.first)
        XCTAssertEqual(enrichedEvent.id, initialEvent.id)
        XCTAssertEqual(enrichedEvent.healthWorkoutEnrichment, enrichment)
        XCTAssertEqual(enrichedEvent.healthWorkoutEnrichment?.heartRate.samples.count, 1)
        XCTAssertEqual(enrichedEvent.healthWorkoutEnrichment?.distance.quantity?.value, 5000)
        XCTAssertEqual(
            enrichedEvent.healthWorkoutEnrichment?.activeEnergy.state, .notAvailableFromHealth,
        )
        let retainedRoute = try await repository.loadHealthWorkoutRoute(for: exactWorkout.healthKitUUID)
        XCTAssertEqual(retainedRoute, route)
        XCTAssertLessThanOrEqual(route.points.count, HealthWorkoutRoute.maximumRetainedPoints)

        let changedWorkout = unifiedAcceptanceWorkout(
            id: exactWorkout.healthKitUUID, activity: "functional-strength-training",
        )
        try await repository.commitHealthWorkoutPage(
            HealthWorkoutPage(
                workouts: [changedWorkout],
                anchor: "replacement-anchor",
                reconciliationContext: "source-replacement",
            ),
            stream: .workouts,
            limits: .default,
        )
        let changedEnrichment = HealthWorkoutEnrichment(
            healthKitUUID: exactWorkout.healthKitUUID,
            heartRate: .available(
                samples: [
                    HealthWorkoutHeartRateSample(
                        id: "changed-heart-rate-sample",
                        startDate: changedWorkout.startDate.addingTimeInterval(20),
                        endDate: changedWorkout.startDate.addingTimeInterval(25),
                        beatsPerMinute: 150,
                        provenance: .init(sourceBundleIdentifier: "com.example.acceptance"),
                    ),
                ],
                checkedAt: Date(timeIntervalSince1970: 60),
                reconciliationContext: "changed-heart-rate",
            ),
            distance: .available(
                value: 6000,
                unit: .meters,
                checkedAt: Date(timeIntervalSince1970: 60),
                reconciliationContext: "changed-distance",
            ),
            activeEnergy: .available(
                value: 300,
                unit: .kilocalories,
                checkedAt: Date(timeIntervalSince1970: 60),
                reconciliationContext: "changed-energy",
            ),
        )
        try await repository.saveHealthWorkoutEnrichment(changedEnrichment)
        let changedRoute = unifiedAcceptanceRoute(
            for: exactWorkout.healthKitUUID,
            points: [
                .init(northSouthDegrees: 14.6195, eastWestDegrees: 121.0042),
                .init(northSouthDegrees: 14.6295, eastWestDegrees: 121.0142),
            ],
        )
        let changedRouteSaved = try await repository.saveHealthWorkoutRoute(changedRoute)
        XCTAssertTrue(changedRouteSaved)
        let changed = try await boundary.timeline()
        XCTAssertEqual(changed.aggregateCount, 1)
        XCTAssertEqual(changed.events.first?.id, initialEvent.id)
        XCTAssertEqual(changed.events.first?.session?.sessionID, "session")
        XCTAssertEqual(
            changed.events.first?.healthWorkout?.activityType, "functional-strength-training",
        )
        XCTAssertEqual(changed.events.first?.healthWorkoutEnrichment, changedEnrichment)
        let retainedChangedRoute = try await repository.loadHealthWorkoutRoute(
            for: exactWorkout.healthKitUUID,
        )
        XCTAssertEqual(retainedChangedRoute, changedRoute)

        let exported = try await repository.loadAuthoritativeExportData()
        XCTAssertNotNil(exported.table(named: "health_workout_link_facts"))
        XCTAssertNil(exported.table(named: "health_workout_enrichment"))
        XCTAssertNil(exported.table(named: "health_workout_routes"))
        XCTAssertFalse(
            exported.tables.contains { table in
                table.records.contains { record in
                    record.fields.values.contains(.number(14.5995))
                        || record.fields.values.contains(.number(120.9842))
                }
            },
        )

        try await repository.commitHealthWorkoutPage(
            HealthWorkoutPage(
                workouts: [],
                reconciliationContext: "external-deletion",
                deletedHealthKitUUIDs: [exactWorkout.healthKitUUID],
            ),
            stream: .workouts,
            limits: .default,
        )
        let afterDeletion = try await boundary.timeline()
        XCTAssertEqual(afterDeletion.aggregateCount, 1)
        XCTAssertEqual(afterDeletion.events.first?.linkState, .formerLinkWorkoutUnavailable)
        XCTAssertEqual(afterDeletion.events.first?.sourceBadges, [.localTraining])
        let deletedEnrichment = try await repository.loadHealthWorkoutEnrichment(
            for: exactWorkout.healthKitUUID,
        )
        let deletedRoute = try await repository.loadHealthWorkoutRoute(
            for: exactWorkout.healthKitUUID,
        )
        XCTAssertNil(deletedEnrichment)
        XCTAssertNil(deletedRoute)

        let similarNewIdentity = unifiedAcceptanceWorkout(
            id: "similar-new-healthkit-uuid", activity: changedWorkout.activityType,
        )
        try await repository.commitHealthWorkoutPage(
            HealthWorkoutPage(
                workouts: [similarNewIdentity],
                anchor: "new-identity-anchor",
                reconciliationContext: "similar-new-identity",
            ),
            stream: .workouts,
            limits: .default,
        )
        let withSimilarWorkout = try await boundary.timeline()
        XCTAssertEqual(withSimilarWorkout.aggregateCount, 2)
        XCTAssertEqual(
            Set(withSimilarWorkout.events.map(\.linkState)),
            [.formerLinkWorkoutUnavailable, .unlinked],
        )

        try await repository.commitHealthWorkoutPage(
            HealthWorkoutPage(
                workouts: [changedWorkout],
                anchor: "exact-return-anchor",
                reconciliationContext: "exact-uuid-reappearance",
            ),
            stream: .workouts,
            limits: .default,
        )
        let afterExactReturn = try await boundary.timeline()
        XCTAssertEqual(afterExactReturn.aggregateCount, 2)
        XCTAssertEqual(
            afterExactReturn.events.first(where: { $0.link?.id == link.id })?.linkState,
            .linked,
        )
        XCTAssertTrue(
            afterExactReturn.events.contains {
                $0.id == "health:\(similarNewIdentity.healthKitUUID)" && $0.linkState == .unlinked
            },
        )

        try await repository.beginHealthRebuild()
        let duringRebuild = try await boundary.timeline()
        XCTAssertEqual(duringRebuild.aggregateCount, 1)
        XCTAssertEqual(duringRebuild.events.first?.linkState, .formerLinkWorkoutUnavailable)
        let rebuildLinkHistory = try await repository.loadHealthWorkoutLinkFacts(for: nil)
        XCTAssertEqual(rebuildLinkHistory, [link])
        try await repository.commitHealthWorkoutPage(
            HealthWorkoutPage(
                workouts: [changedWorkout],
                reconciliationContext: "rebuild-exact-reconnection",
            ),
            stream: .workouts,
            limits: .default,
        )
        let afterRebuild = try await boundary.timeline()
        XCTAssertEqual(afterRebuild.events.first?.linkState, .linked)

        let unlinked = try await boundary.unlink(link, confirmation: .confirmed)
        XCTAssertFalse(unlinked.isActive)
        let afterUnlink = try await boundary.timeline()
        XCTAssertEqual(afterUnlink.aggregateCount, 2)
        XCTAssertTrue(afterUnlink.events.allSatisfy { $0.linkState == .unlinked })
        XCTAssertNotNil(afterUnlink.events.first { $0.session?.sessionID == "session" })
        XCTAssertNotNil(
            afterUnlink.events.first { $0.healthWorkout?.healthKitUUID == exactWorkout.healthKitUUID },
        )

        let restarted = GRDBTrainingRepository(root: root)
        try await restarted.prepareStores()
        let restartedCycles = try await restarted.loadTrainingCycles()
        let restartedCompletion = try await restarted.loadCompletedSession(sessionID: "session")
        let restartedLinks = try await restarted.loadHealthWorkoutLinkFacts(for: nil)
        let restartedWorkouts = try await restarted.loadHealthWorkouts()
        XCTAssertEqual(restartedCycles.map(\.id), [cycle.id])
        XCTAssertEqual(restartedCompletion?.sessionID, "session")
        XCTAssertEqual(restartedLinks, [unlinked])
        XCTAssertEqual(restartedWorkouts.map(\.healthKitUUID), [exactWorkout.healthKitUUID])
    }
}

private struct UnifiedAcceptanceClock: Clock {
    let date: Date

    func now() -> Date {
        date
    }
}

private func unifiedAcceptanceCycle() -> TrainingCycle {
    let date = TrainingDate(year: 2024, month: 1, day: 1)
    let template = ScheduleTemplate(sessions: [
        ScheduleSession(
            id: "template-session",
            intendedWeekday: .monday,
            primaryLiftID: "squat",
            assistanceLiftID: "bench",
        ),
    ])
    return TrainingCycle(
        id: "cycle",
        week1AnchorDate: date,
        weeks: [
            TrainingWeek(
                id: "week",
                position: 1,
                kind: .week1,
                startDate: date,
                sessions: [
                    TrainingCycleSession(
                        id: "session",
                        intendedDate: date,
                        sourceTemplateSessionID: "template-session",
                        primaryLiftID: "squat",
                        assistanceLiftID: "bench",
                    ),
                ],
            ),
        ],
        sourceTemplate: template.snapshot,
        includesProvisionalDeload: false,
        lifecycleState: .active,
        createdAt: 1,
        updatedAt: 10,
        liftSnapshots: [
            "squat": .init(
                identity: .progression(.squat), trainingMaxKg: 100, loadingIncrementKg: 2.5,
            ),
            "bench": .init(
                identity: .progression(.benchPress), trainingMaxKg: 75, loadingIncrementKg: 2.5,
            ),
        ],
    )
}

private func unifiedAcceptanceWorkout(id: String, activity: String) -> HealthWorkout {
    HealthWorkout(
        healthKitUUID: id,
        activityType: activity,
        startDate: Date(timeIntervalSince1970: 1_704_195_000),
        endDate: Date(timeIntervalSince1970: 1_704_198_600),
        duration: 3600,
        sourceName: "Acceptance Watch",
        sourceBundleIdentifier: "com.example.acceptance",
        sourceProductType: "Watch",
        sourceOSVersion: "26.0",
        deviceName: "Acceptance Device",
        deviceModel: "Synthetic",
        sourceTimeZoneIdentifier: "UTC",
        localDate: "2024-01-02",
        timeZoneSource: .sourceMetadata,
        firstImportedAt: Date(timeIntervalSince1970: 25),
        reconciliationContext: "acceptance-workout",
    )
}

private func unifiedAcceptanceRoute(
    for healthKitUUID: String,
    points: [HealthWorkoutRoutePoint] = [
        .init(northSouthDegrees: 14.5995, eastWestDegrees: 120.9842),
        .init(northSouthDegrees: 14.6095, eastWestDegrees: 120.9942),
    ],
) -> HealthWorkoutRoute {
    HealthWorkoutRoute(
        healthKitUUID: healthKitUUID,
        segments: [
            .init(
                source: .init(
                    healthKitUUID: "route-source",
                    provenance: .init(
                        sourceName: "Acceptance Watch",
                        sourceBundleIdentifier: "com.example.acceptance",
                    ),
                ),
                points: points,
                originalPointCount: 50000,
            ),
        ],
        retainedAt: Date(timeIntervalSince1970: 50),
        simplification: .boundedDouglasPeuckerV1,
        reconciliationContext: "route-on-demand",
        adapterProcessingDurationMilliseconds: 10,
    )
}
