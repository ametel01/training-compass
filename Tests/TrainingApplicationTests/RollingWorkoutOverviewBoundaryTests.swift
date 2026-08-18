import Foundation
@testable import TrainingApplication
import XCTest

final class RollingWorkoutOverviewBoundaryTests: XCTestCase {
    func testLinkedDuplicateAndDeletedWorkoutDoNotInflateCurrentFacts() async throws {
        let first = workout(id: "linked", localDate: "2026-08-15", duration: 1000)
        let replacement = workout(id: "linked", localDate: "2026-08-15", duration: 1200)
        let deleted = workout(id: "deleted", localDate: "2026-08-15", duration: 1000)
        let repository = OverviewRepository(
            workouts: [first, replacement, deleted],
            deleted: ["deleted"],
            checkpoint: HealthSyncCheckpoint(
                stream: .workouts, anchor: "anchor", reconciliationContext: "complete",
            ),
        )
        let boundary = RollingWorkoutOverviewBoundary(
            repository: repository,
            clock: OverviewClock(),
            calendar: OverviewCalendar(),
        )

        let overview = try await boundary.overview(
            asOf: TrainingDate(year: 2026, month: 8, day: 15),
        )

        XCTAssertEqual(overview.workoutCount.currentValue, 1)
        XCTAssertEqual(overview.totalDuration.currentValue, 1200)
        XCTAssertEqual(overview.workoutCount.explanation.includedRecordIDs, ["linked"])
    }

    func testLateEnrichmentUpdatesZoneProjectionWithoutChangingWorkoutIdentity() async throws {
        let workout = workout(id: "late", localDate: "2026-08-15", duration: 1000)
        let repository = OverviewRepository(
            workouts: [workout],
            checkpoint: HealthSyncCheckpoint(
                stream: .workouts, anchor: "anchor", reconciliationContext: "complete",
            ),
        )
        let provider = OverviewZoneProvider()
        let boundary = RollingWorkoutOverviewBoundary(
            repository: repository,
            clock: OverviewClock(),
            calendar: OverviewCalendar(),
            zoneProvider: provider,
        )

        let before = try await boundary.overview(
            asOf: TrainingDate(year: 2026, month: 8, day: 15),
        )
        XCTAssertTrue(before.zoneMetrics.isEmpty)

        await provider.set(.available([.zone3: 42]))
        let after = try await boundary.overview(
            asOf: TrainingDate(year: 2026, month: 8, day: 15),
        )
        XCTAssertEqual(after.zoneMetrics.map(\.zone), [.zone3])
        XCTAssertEqual(after.zoneMetrics.first?.coveredSeconds, 42)
        XCTAssertEqual(after.workoutCount.currentValue, before.workoutCount.currentValue)
    }

    func testLimitedHistoryKeepsCurrentFactsAndWithholdsComparison() async throws {
        let repository = OverviewRepository(
            workouts: [workout(id: "limited", localDate: "2026-08-15", duration: 1000)],
            checkpoint: HealthSyncCheckpoint(
                stream: .workouts,
                anchor: "anchor",
                hasLimitedHistory: true,
                reconciliationContext: "limited",
            ),
        )
        let boundary = RollingWorkoutOverviewBoundary(
            repository: repository,
            clock: OverviewClock(),
            calendar: OverviewCalendar(),
        )

        let overview = try await boundary.overview(
            asOf: TrainingDate(year: 2026, month: 8, day: 15),
        )

        XCTAssertEqual(overview.workoutCount.currentValue, 1)
        XCTAssertNil(overview.workoutCount.comparisonMedian)
        XCTAssertTrue(overview.workoutCount.explanation.text.contains("limited history"))
    }

    func testEnrichmentFailureLeavesCoreWorkoutFactsAvailable() async throws {
        let repository = OverviewRepository(
            workouts: [workout(id: "enrichment-failed", localDate: "2026-08-15", duration: 900)],
            checkpoint: HealthSyncCheckpoint(
                stream: .workouts, anchor: "anchor", reconciliationContext: "complete",
            ),
            throwsWhenLoadingEnrichment: true,
        )
        let boundary = RollingWorkoutOverviewBoundary(
            repository: repository,
            clock: OverviewClock(),
            calendar: OverviewCalendar(),
        )

        let overview = try await boundary.overview(
            asOf: TrainingDate(year: 2026, month: 8, day: 15),
        )

        XCTAssertEqual(overview.workoutCount.currentValue, 1)
        XCTAssertEqual(overview.totalDuration.currentValue, 900)
        XCTAssertTrue(
            overview.zoneAvailabilityExplanation?.missingData.contains {
                $0.contains("Heart-rate enrichment has not been checked")
            } == true,
        )
    }

    func testHeartRateProjectionUsesConfiguredWatchRangesAndRetainsSourceCoverage() async throws {
        let workout = workout(id: "zones", localDate: "2026-08-15", duration: 100)
        let repository = try OverviewRepository(
            workouts: [workout],
            checkpoint: HealthSyncCheckpoint(
                stream: .workouts, anchor: "anchor", reconciliationContext: "complete",
            ),
            enrichment: enrichment(for: workout, bpm: 140),
            zoneBoundaries: watchBoundaries(),
        )
        let boundary = RollingWorkoutOverviewBoundary(
            repository: repository,
            clock: OverviewClock(),
            calendar: OverviewCalendar(),
            zoneProvider: HealthWorkoutHeartRateZoneProvider(configurationRepository: repository),
        )

        let overview = try await boundary.overview(
            asOf: TrainingDate(year: 2026, month: 8, day: 15),
        )

        XCTAssertEqual(overview.maximumHeartRateBPM, 177)
        XCTAssertEqual(
            overview.zoneMetrics.first(where: { $0.zone == RollingWorkoutZone.zone2 })?
                .coveredSeconds,
            100,
        )
        let zone2 = try XCTUnwrap(
            overview.zoneMetrics.first(where: { $0.zone == RollingWorkoutZone.zone2 }),
        )
        XCTAssertEqual(zone2.percentOfCoveredTime, 100)
        XCTAssertEqual(zone2.coverageOfTotalWorkoutDuration, 100)
        XCTAssertEqual(zone2.rangeDescription, "131–141 bpm")
        XCTAssertTrue(
            zone2.explanation.formula.contains("Apple Watch range: 131–141 bpm") == true,
        )
    }

    func testRawHeartRateRemainsVisibleButZonesStayUnavailableWithoutConfiguration() async {
        let workout = workout(id: "unconfigured", localDate: "2026-08-15", duration: 100)
        let repository = OverviewRepository(
            workouts: [workout],
            checkpoint: HealthSyncCheckpoint(
                stream: .workouts, anchor: "anchor", reconciliationContext: "complete",
            ),
            enrichment: enrichment(for: workout, bpm: 100),
        )
        let provider = HealthWorkoutHeartRateZoneProvider(configurationRepository: repository)

        let availability = await provider.zoneTimes(
            for: workout, enrichment: enrichment(for: workout, bpm: 100),
        )

        let expected: RollingWorkoutZoneTimeAvailability =
            .unavailable(reason: "Heart-rate zone boundaries are not configured")
        XCTAssertEqual(availability, expected)
    }

    private func watchBoundaries() throws -> HeartRateZoneBoundaries {
        try HeartRateZoneBoundaries(
            restingHeartRateBPM: 64,
            maximumHeartRate: MaximumHeartRate(beatsPerMinute: 177),
            zone2MinimumBPM: 131,
            zone3MinimumBPM: 142,
            zone4MinimumBPM: 153,
            zone5MinimumBPM: 165,
        )
    }

    private func workout(id: String, localDate: String, duration: TimeInterval) -> HealthWorkout {
        HealthWorkout(
            healthKitUUID: id,
            activityType: "Running",
            startDate: Date(timeIntervalSince1970: 1_755_206_400),
            endDate: Date(timeIntervalSince1970: 1_755_206_400 + duration),
            duration: duration,
            localDate: localDate,
            firstImportedAt: Date(timeIntervalSince1970: 10),
        )
    }

    private func enrichment(for workout: HealthWorkout, bpm: Double) -> HealthWorkoutEnrichment {
        HealthWorkoutEnrichment(
            healthKitUUID: workout.healthKitUUID,
            heartRate: .available(
                samples: [
                    HealthWorkoutHeartRateSample(
                        id: "sample", startDate: workout.startDate, endDate: workout.endDate,
                        beatsPerMinute: bpm, provenance: HealthSampleProvenance(sourceName: "Watch"),
                    ),
                ],
                checkedAt: workout.endDate,
                reconciliationContext: "complete",
            ),
            distance: .notAvailableFromHealth(
                checkedAt: workout.endDate, reconciliationContext: "complete",
            ),
            activeEnergy: .notAvailableFromHealth(
                checkedAt: workout.endDate, reconciliationContext: "complete",
            ),
        )
    }
}

private actor OverviewRepository: HealthWorkoutRepository, HeartRateConfigurationRepository {
    private var workouts: [HealthWorkout]
    private let deleted: [String]
    private let checkpoint: HealthSyncCheckpoint?
    private let throwsWhenLoadingEnrichment: Bool
    private let enrichment: HealthWorkoutEnrichment?
    private var zoneBoundaries: HeartRateZoneBoundaries?

    init(
        workouts: [HealthWorkout],
        deleted: [String] = [],
        checkpoint: HealthSyncCheckpoint? = nil,
        throwsWhenLoadingEnrichment: Bool = false,
        enrichment: HealthWorkoutEnrichment? = nil,
        zoneBoundaries: HeartRateZoneBoundaries? = nil,
    ) {
        self.workouts = workouts
        self.deleted = deleted
        self.checkpoint = checkpoint
        self.throwsWhenLoadingEnrichment = throwsWhenLoadingEnrichment
        self.enrichment = enrichment
        self.zoneBoundaries = zoneBoundaries
    }

    func upsertHealthWorkouts(
        _ workouts: [HealthWorkout],
        reconciliationContext _: String,
    ) async throws {
        self.workouts = workouts
    }

    func loadHealthWorkouts() async throws -> [HealthWorkout] {
        workouts
    }

    func loadHealthWorkoutDeletionUUIDs() async throws -> [String] {
        deleted
    }

    func loadHealthWorkoutEnrichment(for _: String) async throws
        -> HealthWorkoutEnrichment?
    {
        if throwsWhenLoadingEnrichment {
            throw OverviewRepositoryError.enrichmentUnavailable
        }
        return enrichment
    }

    func loadHeartRateConfiguration() async throws -> HeartRateConfiguration? {
        zoneBoundaries.map { HeartRateConfiguration(zoneBoundaries: $0, updatedAt: 1) }
    }

    func saveHeartRateConfiguration(
        _ configuration: HeartRateConfiguration,
        expectedBefore _: HeartRateConfiguration?,
    ) async throws {
        zoneBoundaries = configuration.zoneBoundaries
    }

    func deleteHeartRateConfiguration() async throws {
        zoneBoundaries = nil
    }

    func loadHealthSyncCheckpoint(for stream: HealthSyncStream) async throws
        -> HealthSyncCheckpoint?
    {
        stream == .workouts ? checkpoint : nil
    }
}

private enum OverviewRepositoryError: Error {
    case enrichmentUnavailable
}

private actor OverviewZoneProvider: RollingWorkoutZoneProjectionProviding {
    private var value: RollingWorkoutZoneTimeAvailability = .unavailable(reason: "not ready")

    func set(_ value: RollingWorkoutZoneTimeAvailability) {
        self.value = value
    }

    func zoneTimes(
        for _: HealthWorkout,
        enrichment _: HealthWorkoutEnrichment?,
    ) async -> RollingWorkoutZoneTimeAvailability {
        value
    }
}

private struct OverviewClock: Clock {
    func now() -> Date {
        Date(timeIntervalSince1970: 1_755_206_400)
    }
}

private struct OverviewCalendar: CalendarProvider {
    func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
