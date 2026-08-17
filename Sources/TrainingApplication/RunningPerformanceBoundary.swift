import Foundation

public protocol RunningComparisonExclusionRepository: Sendable {
    func loadRunningComparisonExclusions() async throws -> [String]
    func saveRunningComparisonExclusion(healthKitUUID: String) async throws
    func deleteRunningComparisonExclusion(healthKitUUID: String) async throws
}

public extension RunningComparisonExclusionRepository {
    func saveRunningComparisonExclusion(
        _ exclusion: RunningComparisonExclusion,
    ) async throws {
        try await saveRunningComparisonExclusion(healthKitUUID: exclusion.healthKitUUID)
    }
}

public enum RunningComparisonExclusionError: Error, Equatable, Sendable {
    case unavailable
    case invalidHealthKitUUID
}

/// Builds the source-classified running projection from the reconstructible
/// Health mirror.  No activity or environment is inferred at this seam.
public struct RunningPerformanceBoundary: Sendable {
    private let repository: any HealthWorkoutRepository
    private let routeRepository: (any HealthWorkoutRouteRepository)?
    private let exclusionRepository: (any RunningComparisonExclusionRepository)?
    private let clock: any Clock
    private let calendarProvider: any CalendarProvider
    private let zoneProvider: (any RollingWorkoutZoneProjectionProviding)?

    public init(
        repository: any HealthWorkoutRepository,
        routeRepository: (any HealthWorkoutRouteRepository)? = nil,
        exclusionRepository: (any RunningComparisonExclusionRepository)? = nil,
        clock: any Clock = SystemClock(),
        calendar: any CalendarProvider = CurrentCalendarProvider(),
        zoneProvider: (any RollingWorkoutZoneProjectionProviding)? = nil,
    ) {
        self.repository = repository
        self.routeRepository = routeRepository ?? (repository as? any HealthWorkoutRouteRepository)
        self.exclusionRepository =
            exclusionRepository ?? (repository as? any RunningComparisonExclusionRepository)
        self.clock = clock
        calendarProvider = calendar
        self.zoneProvider = zoneProvider
    }

    public func runningPerformance(
        selectedRunID: String? = nil,
        asOf date: TrainingDate? = nil,
        historyDays: Int = 90,
        comparisonHistoryDays: Int? = nil,
    ) async throws -> RunningPerformance {
        let asOf = date ?? TrainingDate(date: clock.now(), calendar: calendarProvider.calendar())
        let deleted = try await Set(repository.loadHealthWorkoutDeletionUUIDs())
        let excluded = try await Set(
            exclusionRepository?.loadRunningComparisonExclusions() ?? [],
        )
        let workouts = try await repository.loadHealthWorkouts()
        let workoutsByID = Dictionary(
            workouts.map { ($0.healthKitUUID, $0) },
            uniquingKeysWith: { first, replacement in
                replacement.firstImportedAt >= first.firstImportedAt ? replacement : first
            },
        )
        let checkpoint = try await repository.loadHealthSyncCheckpoint(for: .workouts)
        let coverage =
            checkpoint.map {
                $0.hasLimitedHistory ? HealthStreamCoverage.limitedHistory : .available
            } ?? .unknown
        let sourceCoverage = "Health Workouts: \(coverage.displayName)"
        var records: [RunningWorkoutRecord] = []

        for workout in workoutsByID.values
            where !deleted.contains(workout.healthKitUUID)
            && RunningWorkoutRecord.isSourceClassifiedRunning(activityType: workout.activityType)
        {
            let enrichment = try? await repository.loadHealthWorkoutEnrichment(
                for: workout.healthKitUUID,
            )
            let routeAvailability = await routeAvailability(for: workout.healthKitUUID)
            let heartRate = await heartRateContext(for: workout, enrichment: enrichment)
            let distance = positiveDistance(from: enrichment?.distance)
            records.append(
                RunningWorkoutRecord(
                    id: workout.healthKitUUID,
                    localDate: Self.parse(localDate: workout.localDate) ?? asOf,
                    startDate: workout.startDate.timeIntervalSince1970,
                    durationSeconds: workout.duration > 0 ? workout.duration : nil,
                    distanceMeters: distance,
                    environment: workout.runningEnvironment,
                    elevationMeters: workout.elevationMeters,
                    routeAvailability: routeAvailability,
                    heartRate: heartRate,
                    source: HealthWorkoutProvenance(workout: workout).displayName,
                    sourceCoverage: sourceCoverage,
                    lastReconciliation: checkpoint?.reconciliationContext,
                    importedAt: workout.firstImportedAt.timeIntervalSince1970,
                ),
            )
        }

        return RunningPerformanceCalculator().calculate(
            records: records,
            selectedRunID: selectedRunID,
            asOf: asOf,
            sourceCoverage: sourceCoverage,
            lastReconciliation: checkpoint?.reconciliationContext,
            excludedRunIDs: excluded,
            historyDays: comparisonHistoryDays ?? historyDays,
        )
    }

    public func load(
        selectedRunID: String? = nil,
        historyDays: Int = 90,
    ) async throws -> RunningPerformance {
        try await runningPerformance(selectedRunID: selectedRunID, historyDays: historyDays)
    }

    public func excludeRunningComparison(_ healthKitUUID: String) async throws {
        guard !healthKitUUID.isEmpty else {
            throw RunningComparisonExclusionError.invalidHealthKitUUID
        }
        guard let exclusionRepository else {
            throw RunningComparisonExclusionError.unavailable
        }
        try await exclusionRepository.saveRunningComparisonExclusion(
            healthKitUUID: healthKitUUID,
        )
    }

    public func includeRunningComparison(_ healthKitUUID: String) async throws {
        guard !healthKitUUID.isEmpty else {
            throw RunningComparisonExclusionError.invalidHealthKitUUID
        }
        guard let exclusionRepository else {
            throw RunningComparisonExclusionError.unavailable
        }
        try await exclusionRepository.deleteRunningComparisonExclusion(
            healthKitUUID: healthKitUUID,
        )
    }

    public func excludeRun(_ healthKitUUID: String) async throws {
        try await excludeRunningComparison(healthKitUUID)
    }

    public func restoreRun(_ healthKitUUID: String) async throws {
        try await includeRunningComparison(healthKitUUID)
    }

    public func excludeRunFromComparison(_ healthKitUUID: String) async throws {
        try await excludeRunningComparison(healthKitUUID)
    }

    public func restoreRunToComparison(_ healthKitUUID: String) async throws {
        try await includeRunningComparison(healthKitUUID)
    }

    private func routeAvailability(for healthKitUUID: String) async -> RunningRouteAvailability {
        guard let routeRepository else { return .notChecked }
        return await (try? routeRepository.loadHealthWorkoutRoute(for: healthKitUUID)) != nil
            ? .available : .unavailable
    }

    private func heartRateContext(
        for workout: HealthWorkout,
        enrichment: HealthWorkoutEnrichment?,
    ) async -> RunningHeartRateContext {
        guard let enrichment else {
            return .unavailable(reason: "Heart-rate enrichment has not been checked")
        }
        if let zoneProvider {
            let availability = await zoneProvider.zoneTimes(for: workout, enrichment: enrichment)
            if case let .projected(projection) = availability {
                let samples = Dictionary(
                    uniqueKeysWithValues: enrichment.heartRate.samples.map { ($0.id, $0) },
                )
                let weighted = projection.intervals.reduce(into: (seconds: 0.0, bpmSeconds: 0.0)) {
                    guard let sample = samples[$1.sampleID] else { return }
                    $0.seconds += $1.durationSeconds
                    $0.bpmSeconds += $1.durationSeconds * sample.beatsPerMinute
                }
                return RunningHeartRateContext(
                    averageBeatsPerMinute: weighted.seconds > 0
                        ? weighted.bpmSeconds / weighted.seconds : nil,
                    coveredSeconds: weighted.seconds,
                    workoutDurationSeconds: workout.duration > 0 ? workout.duration : nil,
                    source: projection.sourceSummaries.map(\.source).joined(separator: ", "),
                )
            }
        }
        guard enrichment.heartRate.state == .available else {
            return .unavailable(reason: enrichment.heartRate.state.displayName)
        }
        let start = workout.startDate.timeIntervalSince1970
        let end = workout.endDate.timeIntervalSince1970
        let weighted = enrichment.heartRate.samples.reduce(into: (seconds: 0.0, bpmSeconds: 0.0)) {
            let lower = max(start, $1.startDate.timeIntervalSince1970)
            let upper = min(end, $1.endDate.timeIntervalSince1970)
            guard upper > lower else { return }
            let seconds = upper - lower
            $0.seconds += seconds
            $0.bpmSeconds += seconds * $1.beatsPerMinute
        }
        return RunningHeartRateContext(
            averageBeatsPerMinute: weighted.seconds > 0 ? weighted.bpmSeconds / weighted.seconds : nil,
            coveredSeconds: weighted.seconds,
            workoutDurationSeconds: workout.duration > 0 ? workout.duration : nil,
            source: Set(enrichment.heartRate.samples.map(\.provenance.displayName)).sorted().joined(
                separator: ", ",
            ),
        )
    }

    private func positiveDistance(from detail: HealthWorkoutQuantityDetail?) -> Double? {
        guard let detail, detail.state == .available, let quantity = detail.quantity,
              quantity.unit == .meters, quantity.value > 0, quantity.value.isFinite
        else { return nil }
        return quantity.value
    }

    private static func parse(localDate: String) -> TrainingDate? {
        let components = localDate.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return TrainingDate(year: components[0], month: components[1], day: components[2])
    }
}
