import Foundation
@testable import TrainingApplication
import XCTest

final class TrainingEventLinkBoundaryTests: XCTestCase {
    func testCandidatesRankLikelyMatchesButKeepEveryUnlinkedExternalWorkoutSelectable()
        async throws
    {
        let completion = CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [completion],
            workouts: [
                makeWorkout(
                    id: "unusual",
                    activity: "running",
                    start: 1_703_980_800,
                    localDate: "2023-12-31",
                ),
                makeWorkout(
                    id: "likely",
                    activity: "traditional-strength-training",
                    start: 1_704_108_600,
                    localDate: "2024-01-01",
                ),
                makeWorkout(
                    id: "already-linked",
                    activity: "traditional-strength-training",
                    start: 1_704_108_000,
                    localDate: "2024-01-01",
                ),
                makeWorkout(
                    id: "app-authored",
                    activity: "traditional-strength-training",
                    start: 1_704_109_000,
                    localDate: "2024-01-01",
                    sourceBundleIdentifier: TrainingEventLinkBoundary.trainingCompassBundleIdentifier,
                ),
            ],
            links: [
                HealthWorkoutLinkFact(
                    id: "existing-link",
                    healthKitUUID: "already-linked",
                    localEntityKind: .session,
                    localEntityID: "other-session",
                    linkedAt: Date(timeIntervalSince1970: 1_704_109_500),
                ),
            ],
        )
        let boundary = TrainingEventLinkBoundary(
            cycleRepository: repository,
            resultRepository: repository,
            healthRepository: repository,
            linkRepository: repository,
            clock: TrainingEventFixedClock(),
            uuidGenerator: TrainingEventUUIDGenerator(),
        )

        let snapshot = try await boundary.linkingSnapshot(for: "session")

        XCTAssertNil(snapshot.selectedCandidateID)
        XCTAssertEqual(snapshot.candidates.map(\.healthKitUUID), ["likely", "unusual"])
        XCTAssertFalse(snapshot.candidates[0].requiresWarningAcknowledgement)
        XCTAssertTrue(snapshot.candidates[1].requiresWarningAcknowledgement)
        XCTAssertTrue(snapshot.candidates.allSatisfy(\.isSelectable))
    }

    func testUnusualCandidateRequiresExplicitWarningAcknowledgementBeforeDurableLink()
        async throws
    {
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [
                makeWorkout(
                    id: "unusual",
                    activity: "running",
                    start: 1_703_980_800,
                    localDate: "2023-12-31",
                ),
            ],
        )
        let boundary = makeBoundary(repository: repository)
        let snapshot = try await boundary.linkingSnapshot(for: "session")
        let candidate = try XCTUnwrap(snapshot.candidates.first)

        do {
            _ = try await boundary.confirmLink(
                candidate,
                to: "session",
                confirmation: .confirmed,
            )
            XCTFail("An unusual match must require a separate acknowledgement")
        } catch {
            XCTAssertEqual(error as? TrainingEventLinkError, .warningAcknowledgementRequired)
        }

        let link = try await boundary.confirmLink(
            candidate,
            to: "session",
            confirmation: .confirmedUnusualMatch,
        )

        XCTAssertEqual(link.healthKitUUID, "unusual")
        XCTAssertEqual(link.localEntityID, "session")
        let saved = await repository.currentLinks
        XCTAssertEqual(saved, [link])
    }

    func testCompletionCanExplicitlyLinkExternalWorkoutAndSuppressWriteBackSummary()
        async throws
    {
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .scheduled)],
            completions: [],
            workouts: [
                makeWorkout(
                    id: "completion-workout",
                    activity: "traditional-strength-training",
                    start: 1_704_108_600,
                    localDate: "2024-01-01",
                ),
            ],
        )
        let boundary = makeBoundary(repository: repository)
        let snapshot = try await boundary.completionLinkingSnapshot(for: "session")
        let candidate = try XCTUnwrap(snapshot.candidates.first)

        let result = try await boundary.completeSession(
            linking: candidate,
            to: "session",
            confirmation: .confirmed,
        )

        XCTAssertEqual(result.completion.sessionID, "session")
        XCTAssertTrue(result.link.linkedDuringCompletion)
        XCTAssertEqual(
            result.link.writeBackDisposition,
            .suppressedExternalWorkoutLinkedAtCompletion,
        )
        let saved = await repository.currentLinks
        XCTAssertEqual(saved, [result.link])
    }

    func testLinkedPairAppearsOnceInTimelineAndAggregateWhileRetainingBothSources()
        async throws
    {
        let linkedWorkout = makeWorkout(
            id: "linked-health",
            activity: "traditional-strength-training",
            start: 1_704_108_600,
            localDate: "2024-01-01",
        )
        let healthOnly = makeWorkout(
            id: "health-only",
            activity: "running",
            start: 1_704_115_800,
            localDate: "2024-01-01",
        )
        let link = HealthWorkoutLinkFact(
            id: "linked-event",
            healthKitUUID: linkedWorkout.healthKitUUID,
            localEntityKind: .session,
            localEntityID: "session",
            linkedAt: Date(timeIntervalSince1970: 1_704_110_500),
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [linkedWorkout, healthOnly],
            links: [link],
        )
        let boundary = makeBoundary(repository: repository)

        let timeline = try await boundary.timeline()

        XCTAssertEqual(timeline.aggregateCount, 2)
        XCTAssertEqual(timeline.events.count, 2)
        let linkedEvent = try XCTUnwrap(
            timeline.events.first(where: { $0.link?.id == link.id }),
        )
        XCTAssertEqual(linkedEvent.linkState, .linked)
        XCTAssertEqual(linkedEvent.session?.sessionID, "session")
        XCTAssertEqual(linkedEvent.healthWorkout?.healthKitUUID, "linked-health")
        XCTAssertEqual(linkedEvent.sourceBadges, [.localTraining, .health])
        XCTAssertEqual(linkedEvent.healthCoverage, .unknown)
        XCTAssertEqual(linkedEvent.healthWorkoutEnrichment?.heartRate.state, .loading)
        XCTAssertEqual(linkedEvent.healthWorkoutEnrichment?.distance.state, .loading)
        XCTAssertEqual(linkedEvent.healthWorkoutEnrichment?.activeEnergy.state, .loading)
    }

    func testLinkedEventExposesReconciliationAndSourceDisagreementWithoutOverwritingEitherFact()
        async throws
    {
        let workout = makeWorkout(
            id: "different-date", activity: "traditional-strength-training",
            start: 1_704_195_000, localDate: "2024-01-02",
        )
        let checkpoint = HealthSyncCheckpoint(
            stream: .workouts,
            anchor: "anchor-23",
            reconciliationContext: "observer-success",
            committedAt: Date(timeIntervalSince1970: 1_704_196_000),
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [workout],
            links: [
                HealthWorkoutLinkFact(
                    id: "different-date-link", healthKitUUID: workout.healthKitUUID,
                    localEntityKind: .session, localEntityID: "session",
                ),
            ],
            checkpoint: checkpoint,
        )

        let timeline = try await makeBoundary(repository: repository).timeline()
        let event = try XCTUnwrap(timeline.events.first)

        XCTAssertEqual(event.session?.session.intendedDate.iso8601String, "2024-01-01")
        XCTAssertEqual(event.healthWorkout?.localDate, "2024-01-02")
        XCTAssertEqual(
            event.disagreements,
            [.localDate(session: "2024-01-01", health: "2024-01-02")],
        )
        XCTAssertEqual(event.lastSuccessfulReconciliation, checkpoint.committedAt)
        XCTAssertEqual(event.reconciliationContext, checkpoint.reconciliationContext)
    }

    func testUnifiedLinkedViewRetainsWorkoutSourceAndPartialEnrichmentContext() async throws {
        let workout = makeWorkout(
            id: "enriched-linked", activity: "running",
            start: 1_704_108_600, localDate: "2024-01-01",
        )
        let checkedAt = Date(timeIntervalSince1970: 1_704_196_000)
        let enrichment = HealthWorkoutEnrichment(
            healthKitUUID: workout.healthKitUUID,
            heartRate: .failed(code: "heart-rate-query-failed"),
            distance: .available(
                value: 5000,
                unit: .meters,
                provenance: HealthSampleProvenance(sourceName: "External"),
                checkedAt: checkedAt,
                reconciliationContext: "distance-success",
            ),
            activeEnergy: .notAvailableFromHealth(
                checkedAt: checkedAt,
                reconciliationContext: "energy-success",
            ),
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [workout],
            links: [
                HealthWorkoutLinkFact(
                    id: "enriched-link", healthKitUUID: workout.healthKitUUID,
                    localEntityKind: .session, localEntityID: "session",
                ),
            ],
            checkpoint: HealthSyncCheckpoint(
                stream: .workouts,
                anchor: "limited-anchor",
                hasLimitedHistory: true,
                reconciliationContext: "limited-history",
                committedAt: checkedAt,
            ),
            enrichments: [workout.healthKitUUID: enrichment],
        )

        let timeline = try await makeBoundary(repository: repository).timeline()
        let event = try XCTUnwrap(timeline.events.first)

        XCTAssertEqual(event.sourceBadges, [.localTraining, .health])
        XCTAssertEqual(event.healthWorkout?.sourceName, "External")
        XCTAssertEqual(event.healthCoverage, .limitedHistory)
        XCTAssertEqual(event.healthWorkoutEnrichment, enrichment)
        XCTAssertEqual(event.healthWorkoutEnrichment?.heartRate.state, .failed)
        XCTAssertEqual(
            event.healthWorkoutEnrichment?.distance.reconciliationContext, "distance-success",
        )
        XCTAssertEqual(event.healthWorkoutEnrichment?.activeEnergy.state, .notAvailableFromHealth)
    }

    func testExplicitUnlinkRestoresTwoEventsWithoutDeletingExternalWorkout() async throws {
        let workout = makeWorkout(
            id: "linked-health",
            activity: "traditional-strength-training",
            start: 1_704_108_600,
            localDate: "2024-01-01",
        )
        let link = HealthWorkoutLinkFact(
            id: "link-to-remove",
            healthKitUUID: workout.healthKitUUID,
            localEntityKind: .session,
            localEntityID: "session",
            linkedAt: Date(timeIntervalSince1970: 1_704_110_500),
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [workout],
            links: [link],
        )
        let boundary = makeBoundary(repository: repository)

        let unlinked = try await boundary.unlink(link, confirmation: .confirmed)
        let timeline = try await boundary.timeline()

        XCTAssertFalse(unlinked.isActive)
        XCTAssertEqual(timeline.aggregateCount, 2)
        XCTAssertEqual(timeline.events.compactMap(\.session).count, 1)
        XCTAssertEqual(timeline.events.compactMap(\.healthWorkout).count, 1)
        let storedWorkouts = await repository.currentWorkouts
        XCTAssertEqual(storedWorkouts, [workout])
    }

    func testAlreadyLinkedSessionExposesItsLinkInsteadOfOfferingAnotherCandidate() async throws {
        let linkedWorkout = makeWorkout(
            id: "linked-health", activity: "traditional-strength-training",
            start: 1_704_108_600, localDate: "2024-01-01",
        )
        let availableWorkout = makeWorkout(
            id: "otherwise-available", activity: "traditional-strength-training",
            start: 1_704_108_000, localDate: "2024-01-01",
        )
        let link = HealthWorkoutLinkFact(
            id: "existing-link",
            healthKitUUID: linkedWorkout.healthKitUUID,
            localEntityKind: .session,
            localEntityID: "session",
            linkedAt: Date(timeIntervalSince1970: 1_704_110_500),
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [linkedWorkout, availableWorkout],
            links: [link],
        )

        let snapshot = try await makeBoundary(repository: repository).linkingSnapshot(for: "session")

        XCTAssertEqual(snapshot.activeLink, link)
        XCTAssertTrue(snapshot.candidates.isEmpty)
    }

    func testConcurrentWorkoutReplacementRejectsStaleCandidateWithoutCreatingLink() async throws {
        let original = makeWorkout(
            id: "changing-health", activity: "traditional-strength-training",
            start: 1_704_108_600, localDate: "2024-01-01",
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [original],
        )
        let boundary = makeBoundary(repository: repository)
        let linkingSnapshot = try await boundary.linkingSnapshot(for: "session")
        let candidate = try XCTUnwrap(linkingSnapshot.candidates.first)
        await repository.replaceWorkouts([
            makeWorkout(
                id: original.healthKitUUID, activity: "running",
                start: 1_704_108_600, localDate: "2024-01-01",
            ),
        ])

        do {
            _ = try await boundary.confirmLink(candidate, to: "session", confirmation: .confirmed)
            XCTFail("A changed Health Workout must invalidate the reviewed candidate")
        } catch {
            XCTAssertEqual(error as? TrainingEventLinkError, .staleCandidate)
        }
        let links = await repository.currentLinks
        XCTAssertTrue(links.isEmpty)
    }

    func testExactUUIDReconnectsRetainedLinkAfterMirrorWorkoutReturns() async throws {
        let workout = makeWorkout(
            id: "returning-health", activity: "traditional-strength-training",
            start: 1_704_108_600, localDate: "2024-01-01",
        )
        let link = HealthWorkoutLinkFact(
            id: "retained-link",
            healthKitUUID: workout.healthKitUUID,
            localEntityKind: .session,
            localEntityID: "session",
            linkedAt: Date(timeIntervalSince1970: 1_704_110_500),
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [],
            links: [link],
        )
        let boundary = makeBoundary(repository: repository)

        let absent = try await boundary.timeline()
        XCTAssertEqual(absent.aggregateCount, 1)
        XCTAssertEqual(absent.events.first?.id, "session:session")
        XCTAssertEqual(absent.events.first?.link, link)
        XCTAssertEqual(absent.events.first?.linkState, .formerLinkWorkoutUnavailable)
        await repository.replaceWorkouts([
            makeWorkout(
                id: "new-health", activity: "traditional-strength-training",
                start: 1_704_108_700, localDate: "2024-01-01",
            ),
        ])
        let whileMissing = try await boundary.linkingSnapshot(for: "session")
        XCTAssertNil(whileMissing.activeLink)
        XCTAssertEqual(whileMissing.candidates.map(\.healthKitUUID), ["new-health"])

        await repository.replaceWorkouts([workout])
        let reconnected = try await boundary.timeline()
        XCTAssertEqual(reconnected.aggregateCount, 1)
        XCTAssertEqual(reconnected.events.first?.linkState, .linked)
        XCTAssertEqual(reconnected.events.first?.healthWorkout, workout)
    }

    func testTimelineKeepsMissingProvenanceAndConflictingLinksVisible() async throws {
        let workout = HealthWorkout(
            healthKitUUID: "missing-provenance",
            activityType: "traditional-strength-training",
            startDate: Date(timeIntervalSince1970: 1_704_108_600),
            endDate: Date(timeIntervalSince1970: 1_704_109_600),
            duration: 1000,
            localDate: "2024-01-01",
            timeZoneSource: .unavailable,
        )
        let firstLink = HealthWorkoutLinkFact(
            id: "conflict-one", healthKitUUID: workout.healthKitUUID,
            localEntityKind: .session, localEntityID: "session", linkedAt: Date(timeIntervalSince1970: 20),
        )
        let secondLink = HealthWorkoutLinkFact(
            id: "conflict-two", healthKitUUID: workout.healthKitUUID,
            localEntityKind: .session, localEntityID: "another-session",
            linkedAt: Date(timeIntervalSince1970: 21),
        )
        let duplicateSessionLink = HealthWorkoutLinkFact(
            id: "conflict-duplicate", healthKitUUID: workout.healthKitUUID,
            localEntityKind: .session, localEntityID: "session",
            linkedAt: Date(timeIntervalSince1970: 22),
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [workout], links: [firstLink, secondLink, duplicateSessionLink],
        )

        let events = try await makeBoundary(repository: repository).timeline().events
        let linked = try XCTUnwrap(events.first(where: { $0.session != nil }))
        XCTAssertTrue(
            linked.disagreements.contains {
                if case .linkConflict(healthKitUUID: workout.healthKitUUID, sessionIDs: let sessionIDs) = $0 {
                    return sessionIDs == ["another-session", "session"]
                }
                return false
            },
        )
        XCTAssertTrue(linked.disagreements.contains(.missingHealthProvenance))
    }

    func testVersionedAppAuthoredSummariesCollapseAndExposeEqualVersionConflict() async throws {
        let syncIdentifier = HealthWorkoutWriteBackBoundary.syncIdentifier(for: "session")
        let versionOne = makeWorkout(
            id: "app-v1", activity: "traditional-strength-training", start: 1_704_108_600,
            localDate: "2024-01-01",
            sourceBundleIdentifier: TrainingEventLinkBoundary.trainingCompassBundleIdentifier,
        )
        let versionTwo = HealthWorkout(
            healthKitUUID: "app-v2", activityType: "traditional-strength-training",
            startDate: Date(timeIntervalSince1970: 1_704_108_600),
            endDate: Date(timeIntervalSince1970: 1_704_109_600), duration: 1000,
            sourceName: "Training Compass",
            sourceBundleIdentifier: TrainingEventLinkBoundary.trainingCompassBundleIdentifier,
            localDate: "2024-01-01", firstImportedAt: Date(timeIntervalSince1970: 1_704_110_000),
            appAuthoredSyncIdentifier: syncIdentifier, appAuthoredSyncVersion: 2,
        )
        let versionOneWithMetadata = HealthWorkout(
            healthKitUUID: versionOne.healthKitUUID, activityType: versionOne.activityType,
            startDate: versionOne.startDate, endDate: versionOne.endDate, duration: versionOne.duration,
            sourceName: versionOne.sourceName,
            sourceBundleIdentifier: versionOne.sourceBundleIdentifier,
            localDate: versionOne.localDate, firstImportedAt: versionOne.firstImportedAt,
            appAuthoredSyncIdentifier: syncIdentifier, appAuthoredSyncVersion: 1,
        )
        let repository = TrainingEventTestRepository(
            cycles: [makeCycle(status: .completed)],
            completions: [CompletedSession(sessionID: "session", confirmedAt: 1_704_110_400)],
            workouts: [versionOneWithMetadata, versionTwo],
        )
        let boundary = makeBoundary(repository: repository)

        let selected = try await boundary.timeline()
        XCTAssertEqual(selected.aggregateCount, 1)
        XCTAssertEqual(selected.events.first?.healthWorkout?.healthKitUUID, "app-v2")
        XCTAssertFalse(
            selected.events.first?.disagreements.contains {
                if case .writeBackConflict = $0 {
                    return true
                }
                return false
            } ?? false,
        )

        let equalVersion = HealthWorkout(
            healthKitUUID: "app-v3", activityType: versionTwo.activityType,
            startDate: versionTwo.startDate, endDate: versionTwo.endDate, duration: versionTwo.duration,
            sourceName: versionTwo.sourceName,
            sourceBundleIdentifier: versionTwo.sourceBundleIdentifier,
            localDate: versionTwo.localDate, firstImportedAt: versionTwo.firstImportedAt,
            appAuthoredSyncIdentifier: syncIdentifier, appAuthoredSyncVersion: 2,
        )
        await repository.replaceWorkouts([versionOneWithMetadata, versionTwo, equalVersion])
        let conflict = try await boundary.timeline()
        XCTAssertEqual(conflict.aggregateCount, 1)
        XCTAssertTrue(
            conflict.events.first?.disagreements.contains {
                if case .writeBackConflict(
                    syncIdentifier: syncIdentifier, syncVersion: 2, healthKitUUIDs: ["app-v2", "app-v3"],
                ) = $0 {
                    return true
                }
                return false
            } ?? false,
        )
    }

    private func makeBoundary(repository: TrainingEventTestRepository) -> TrainingEventLinkBoundary {
        TrainingEventLinkBoundary(
            cycleRepository: repository,
            resultRepository: repository,
            healthRepository: repository,
            linkRepository: repository,
            clock: TrainingEventFixedClock(),
            uuidGenerator: TrainingEventUUIDGenerator(),
        )
    }
}

private func makeCycle(status: TrainingSessionStatus) -> TrainingCycle {
    let session = TrainingCycleSession(
        id: "session",
        intendedDate: TrainingDate(year: 2024, month: 1, day: 1),
        sourceTemplateSessionID: "template-session",
        primaryLiftID: "squat",
        assistanceLiftID: "bench",
        prescriptions: [],
        status: status,
    )
    return TrainingCycle(
        id: "cycle",
        week1AnchorDate: TrainingDate(year: 2024, month: 1, day: 1),
        weeks: [
            TrainingWeek(
                id: "week",
                position: 1,
                kind: .week1,
                startDate: TrainingDate(year: 2024, month: 1, day: 1),
                sessions: [session],
            ),
        ],
        sourceTemplate: ScheduleTemplateSnapshot(
            id: "template",
            sessions: [
                ScheduleSession(
                    id: "template-session",
                    intendedWeekday: .monday,
                    primaryLiftID: "squat",
                    assistanceLiftID: "bench",
                ),
            ],
        ),
        includesProvisionalDeload: false,
        lifecycleState: .active,
        createdAt: 1_704_067_200,
        updatedAt: 1_704_110_400,
        liftSnapshots: [:],
    )
}

private func makeWorkout(
    id: String,
    activity: String,
    start: TimeInterval,
    localDate: String,
    sourceBundleIdentifier: String? = "com.example.external",
) -> HealthWorkout {
    HealthWorkout(
        healthKitUUID: id,
        activityType: activity,
        startDate: Date(timeIntervalSince1970: start),
        endDate: Date(timeIntervalSince1970: start + 3600),
        duration: 3600,
        sourceName: "External",
        sourceBundleIdentifier: sourceBundleIdentifier,
        localDate: localDate,
        firstImportedAt: Date(timeIntervalSince1970: 1_704_110_000),
    )
}

private struct TrainingEventFixedClock: Clock {
    func now() -> Date {
        Date(timeIntervalSince1970: 1_704_110_500)
    }
}

private final class TrainingEventUUIDGenerator: UUIDGenerator, @unchecked Sendable {
    func makeUUID() -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
    }
}

private actor TrainingEventTestRepository: TrainingCycleRepository, SetResultRepository,
    HealthWorkoutRepository, TrainingEventLinkRepository
{
    let cycles: [TrainingCycle]
    private var completions: [CompletedSession]
    private var workouts: [HealthWorkout]
    private var links: [HealthWorkoutLinkFact]
    private let checkpoint: HealthSyncCheckpoint?
    private let enrichments: [String: HealthWorkoutEnrichment]

    var currentLinks: [HealthWorkoutLinkFact] {
        links
    }

    var currentWorkouts: [HealthWorkout] {
        workouts
    }

    init(
        cycles: [TrainingCycle],
        completions: [CompletedSession],
        workouts: [HealthWorkout],
        links: [HealthWorkoutLinkFact] = [],
        checkpoint: HealthSyncCheckpoint? = nil,
        enrichments: [String: HealthWorkoutEnrichment] = [:],
    ) {
        self.cycles = cycles
        self.completions = completions
        self.workouts = workouts
        self.links = links
        self.checkpoint = checkpoint
        self.enrichments = enrichments
    }

    func loadTrainingCycles() async throws -> [TrainingCycle] {
        cycles
    }

    func loadCompletedSession(sessionID: String) async throws -> CompletedSession? {
        completions.first { $0.sessionID == sessionID }
    }

    func loadSessionCorrectionSnapshot(sessionID: String) async throws
        -> SessionCorrectionSnapshot?
    {
        guard
            let cycle = cycles.first(where: {
                $0.weeks.flatMap(\.sessions).contains(where: { $0.id == sessionID })
            }),
            let session = cycle.weeks.flatMap(\.sessions).first(where: { $0.id == sessionID })
        else { return nil }
        return SessionCorrectionSnapshot(
            sessionID: sessionID,
            status: session.status,
            intendedDate: session.intendedDate,
            primaryLiftID: session.primaryLiftID,
            assistanceLiftID: session.assistanceLiftID,
            completion: completions.first(where: { $0.sessionID == sessionID }),
            updatedAt: cycle.updatedAt,
        )
    }

    func loadHealthWorkouts() async throws -> [HealthWorkout] {
        workouts
    }

    func loadHealthWorkoutEnrichment(for healthKitUUID: String) async throws
        -> HealthWorkoutEnrichment?
    {
        enrichments[healthKitUUID]
    }

    func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws -> HealthSyncCheckpoint? {
        stream == .workouts ? checkpoint : nil
    }

    func upsertHealthWorkouts(
        _: [HealthWorkout],
        reconciliationContext _: String,
    ) async throws {}

    func replaceWorkouts(_ replacements: [HealthWorkout]) {
        workouts = replacements
    }

    func loadHealthWorkoutLinkFacts(for healthKitUUID: String?) async throws
        -> [HealthWorkoutLinkFact]
    {
        guard let healthKitUUID else { return links }
        return links.filter { $0.healthKitUUID == healthKitUUID }
    }

    func createHealthWorkoutLinkFact(
        _ fact: HealthWorkoutLinkFact,
        expectedSessionUpdatedAt: Int64,
        expectedWorkout: HealthWorkout,
    ) async throws -> HealthWorkoutLinkFact {
        guard expectedSessionUpdatedAt == cycles[0].updatedAt,
              workouts.contains(expectedWorkout)
        else { throw TrainingEventLinkRepositoryError.staleCandidate }
        guard
            !links.contains(where: {
                $0.healthKitUUID == fact.healthKitUUID || $0.localEntityID == fact.localEntityID
            })
        else { throw TrainingEventLinkRepositoryError.duplicateLink }
        links.append(fact)
        return fact
    }

    func completeSessionAndCreateHealthWorkoutLinkFact(
        completion: CompletedSession,
        fact: HealthWorkoutLinkFact,
        expectedSessionUpdatedAt: Int64,
        expectedWorkout: HealthWorkout,
    ) async throws -> TrainingEventCompletionLinkResult {
        guard expectedSessionUpdatedAt == cycles[0].updatedAt,
              workouts.contains(expectedWorkout),
              completions.allSatisfy({ $0.sessionID != completion.sessionID }),
              links.allSatisfy({
                  $0.healthKitUUID != fact.healthKitUUID && $0.localEntityID != fact.localEntityID
              })
        else { throw TrainingEventLinkRepositoryError.staleCandidate }
        completions.append(completion)
        links.append(fact)
        return TrainingEventCompletionLinkResult(completion: completion, link: fact)
    }

    func unlinkHealthWorkoutLinkFact(
        id: String,
        expectedLinkedAt: Date,
        unlinkedAt: Date,
    ) async throws -> HealthWorkoutLinkFact {
        guard
            let index = links.firstIndex(where: {
                $0.id == id && $0.linkedAt == expectedLinkedAt && $0.isActive
            })
        else { throw TrainingEventLinkRepositoryError.staleCandidate }
        let current = links[index]
        let unlinked = HealthWorkoutLinkFact(
            id: current.id,
            healthKitUUID: current.healthKitUUID,
            localEntityKind: current.localEntityKind,
            localEntityID: current.localEntityID,
            linkedAt: current.linkedAt,
            linkedDuringCompletion: current.linkedDuringCompletion,
            writeBackDisposition: current.writeBackDisposition,
            unlinkedAt: unlinkedAt,
        )
        links[index] = unlinked
        return unlinked
    }
}
