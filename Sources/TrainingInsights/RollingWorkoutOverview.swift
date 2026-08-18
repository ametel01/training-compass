import TrainingDomain

public struct RollingWorkoutRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let localDate: TrainingDate
    public let activityType: String
    public let durationSeconds: Double?
    public let zoneTimes: RollingWorkoutZoneTimeAvailability

    public init(
        id: String,
        localDate: TrainingDate,
        activityType: String,
        durationSeconds: Double?,
        zoneTimes: RollingWorkoutZoneTimeAvailability,
    ) {
        self.id = id
        self.localDate = localDate
        self.activityType = activityType
        self.durationSeconds = durationSeconds
        self.zoneTimes = zoneTimes
    }

    public var heartRateProjection: HeartRateZoneProjection? {
        guard case .projected(let projection) = zoneTimes else { return nil }
        return projection
    }
}

public enum RollingWorkoutZone: String, Codable, CaseIterable, Equatable, Sendable {
    case zone1
    case zone2
    case zone3
    case zone4
    case zone5

    public var displayName: String {
        switch self {
        case .zone1: "Zone 1"
        case .zone2: "Zone 2"
        case .zone3: "Zone 3"
        case .zone4: "Zone 4"
        case .zone5: "Zone 5"
        }
    }
}

public enum RollingWorkoutZoneTimeAvailability: Codable, Equatable, Sendable {
    case available([RollingWorkoutZone: Double])
    case projected(HeartRateZoneProjection)
    case unavailable(reason: String)
}

public struct RollingWorkoutWindow: Codable, Equatable, Sendable {
    public let start: TrainingDate
    public let end: TrainingDate

    public init(start: TrainingDate, end: TrainingDate) {
        precondition(start <= end)
        self.start = start
        self.end = end
    }

    public func contains(_ date: TrainingDate) -> Bool {
        date >= start && date <= end
    }

    public var displayName: String {
        "\(start.iso8601String) through \(end.iso8601String)"
    }
}

public enum RollingWorkoutComparisonAvailability: Codable, Equatable, Sendable {
    case available
    case withheld(reason: String)
}

public struct RollingWorkoutNumericMetric: Codable, Equatable, Sendable {
    public let currentValue: Double
    public let comparisonMedian: Double?
    public let explanation: InsightExplanation

    public init(
        currentValue: Double,
        comparisonMedian: Double?,
        explanation: InsightExplanation,
    ) {
        self.currentValue = currentValue
        self.comparisonMedian = comparisonMedian
        self.explanation = explanation
    }
}

public struct RollingWorkoutActivityMetric: Codable, Equatable, Identifiable, Sendable {
    public let activityType: String
    public let metric: RollingWorkoutNumericMetric

    public var id: String {
        activityType
    }

    public init(activityType: String, metric: RollingWorkoutNumericMetric) {
        self.activityType = activityType
        self.metric = metric
    }
}

public struct RollingWorkoutZoneMetric: Codable, Equatable, Identifiable, Sendable {
    public let zone: RollingWorkoutZone
    public let coveredSeconds: Double
    public let comparisonMedianSeconds: Double?
    public let coveredWorkoutDurationSeconds: Double
    public let totalWorkoutDurationSeconds: Double
    public let coveredHeartRateSeconds: Double
    public let percentOfCoveredTime: Double
    public let coverageOfTotalWorkoutDuration: Double
    public let maximumHeartRateBPM: Double?
    public let rangeDescription: String?
    public let explanation: InsightExplanation

    public var id: RollingWorkoutZone {
        zone
    }

    public init(
        zone: RollingWorkoutZone,
        coveredSeconds: Double,
        comparisonMedianSeconds: Double?,
        coveredWorkoutDurationSeconds: Double,
        totalWorkoutDurationSeconds: Double,
        coveredHeartRateSeconds: Double? = nil,
        percentOfCoveredTime: Double? = nil,
        coverageOfTotalWorkoutDuration: Double? = nil,
        maximumHeartRateBPM: Double? = nil,
        rangeDescription: String? = nil,
        explanation: InsightExplanation,
    ) {
        self.zone = zone
        self.coveredSeconds = coveredSeconds
        self.comparisonMedianSeconds = comparisonMedianSeconds
        self.coveredWorkoutDurationSeconds = coveredWorkoutDurationSeconds
        self.totalWorkoutDurationSeconds = totalWorkoutDurationSeconds
        self.coveredHeartRateSeconds = coveredHeartRateSeconds ?? coveredWorkoutDurationSeconds
        self.percentOfCoveredTime =
            percentOfCoveredTime
            ?? (self.coveredHeartRateSeconds > 0
                ? coveredSeconds / self.coveredHeartRateSeconds * 100 : 0)
        self.coverageOfTotalWorkoutDuration =
            coverageOfTotalWorkoutDuration
            ?? (totalWorkoutDurationSeconds > 0
                ? self.coveredHeartRateSeconds / totalWorkoutDurationSeconds * 100 : 0)
        self.maximumHeartRateBPM = maximumHeartRateBPM
        self.rangeDescription = rangeDescription
        self.explanation = explanation
    }
}

public struct RollingWorkoutOverview: Codable, Equatable, Sendable {
    public let currentWindow: RollingWorkoutWindow
    public let comparisonWindows: [RollingWorkoutWindow]
    public let comparisonAvailability: RollingWorkoutComparisonAvailability
    public let workoutCount: RollingWorkoutNumericMetric
    public let totalDuration: RollingWorkoutNumericMetric
    public let activityTypes: [RollingWorkoutActivityMetric]
    public let zoneMetrics: [RollingWorkoutZoneMetric]
    public let zoneAvailabilityExplanation: InsightExplanation?
    public let maximumHeartRateBPM: Double?

    public init(
        currentWindow: RollingWorkoutWindow,
        comparisonWindows: [RollingWorkoutWindow],
        comparisonAvailability: RollingWorkoutComparisonAvailability,
        workoutCount: RollingWorkoutNumericMetric,
        totalDuration: RollingWorkoutNumericMetric,
        activityTypes: [RollingWorkoutActivityMetric],
        zoneMetrics: [RollingWorkoutZoneMetric],
        zoneAvailabilityExplanation: InsightExplanation?,
        maximumHeartRateBPM: Double? = nil,
    ) {
        self.currentWindow = currentWindow
        self.comparisonWindows = comparisonWindows
        self.comparisonAvailability = comparisonAvailability
        self.workoutCount = workoutCount
        self.totalDuration = totalDuration
        self.activityTypes = activityTypes
        self.zoneMetrics = zoneMetrics
        self.zoneAvailabilityExplanation = zoneAvailabilityExplanation
        self.maximumHeartRateBPM = maximumHeartRateBPM
    }
}

public struct RollingWorkoutOverviewCalculator: Sendable {
    public init() {}

    public func calculate(
        records: [RollingWorkoutRecord],
        asOf: TrainingDate,
        coverage: RollingWorkoutSourceCoverage,
    ) -> RollingWorkoutOverview {
        let currentWindow = RollingWorkoutWindow(start: asOf.adding(days: -6), end: asOf)
        let comparisonWindows = (1...4).map { index in
            let end = asOf.adding(days: -7 * index)
            return RollingWorkoutWindow(start: end.adding(days: -6), end: end)
        }
        let horizon = RollingWorkoutWindow(
            start: comparisonWindows.last?.start ?? asOf.adding(days: -34), end: asOf,
        )
        let currentRecords = records.filter { currentWindow.contains($0.localDate) }
        let comparisonRecords = comparisonWindows.map { window in
            records.filter { window.contains($0.localDate) }
        }
        let overviewRecords = recordsInWindows(currentWindow, comparisonWindows, records: records)
        let overviewDateRange =
            "Current: \(currentWindow.displayName). Comparison: "
            + comparisonWindows.map(\.displayName).joined(separator: "; ")
        let overviewDates = Set(overviewRecords.map(\.localDate.iso8601String)).sorted()
        let comparisonAvailability: RollingWorkoutComparisonAvailability =
            coverage.isComplete
            ? .available
            : .withheld(reason: coverage.withholdingReason)
        let exclusions = records.filter { !horizon.contains($0.localDate) }.map {
            InsightExplanationExclusion(
                recordID: $0.id,
                reason: "Outside the 35-date overview horizon",
            )
        }
        let countExplanation = explanation(
            question: "How many Health Workouts occurred in the current rolling window?",
            included: overviewRecords.map(\.id),
            includedDates: overviewDates,
            dateRange: overviewDateRange,
            exclusions: exclusions,
            coverage: coverage,
            baseline: comparisonAvailability,
            formula:
                "Count each available Health Workout once; linked Training Events use the HealthKit UUID once.",
            missing: [],
        )
        let countMedian =
            comparisonAvailability == .available
            ? median(comparisonRecords.map { Double($0.count) })
            : nil
        let count = RollingWorkoutNumericMetric(
            currentValue: Double(currentRecords.count),
            comparisonMedian: countMedian,
            explanation: countExplanation,
        )
        let activityTypes = Set(
            recordsInWindows(currentWindow, comparisonWindows, records: records).map {
                normalizedActivityType($0.activityType)
            },
        ).sorted().map { activityType in
            let current = currentRecords.filter {
                normalizedActivityType($0.activityType) == activityType
            }
            let baseline = comparisonRecords.map {
                Double($0.filter { normalizedActivityType($0.activityType) == activityType }.count)
            }
            return RollingWorkoutActivityMetric(
                activityType: activityType,
                metric: RollingWorkoutNumericMetric(
                    currentValue: Double(current.count),
                    comparisonMedian: comparisonAvailability == .available ? median(baseline) : nil,
                    explanation: explanation(
                        question: "How many \(activityType) Health Workouts occurred?",
                        included: overviewRecords.filter {
                            normalizedActivityType($0.activityType) == activityType
                        }.map(\.id),
                        includedDates: Set(
                            overviewRecords.filter {
                                normalizedActivityType($0.activityType) == activityType
                            }.map(\.localDate.iso8601String),
                        ).sorted(),
                        dateRange: overviewDateRange,
                        exclusions: exclusions,
                        coverage: coverage,
                        baseline: comparisonAvailability,
                        formula:
                            "Count this HealthKit activity type independently without combining unlike activities into a training-load score.",
                        missing: [],
                    ),
                ),
            )
        }
        let availableZoneRecords = recordsInWindows(
            currentWindow, comparisonWindows, records: records
        )
        .filter { Self.zoneProjection(for: $0) != nil }
        let zones = Set<RollingWorkoutZone>(
            availableZoneRecords.flatMap { record -> [RollingWorkoutZone] in
                if record.heartRateProjection != nil {
                    return RollingWorkoutZone.allCases
                }
                guard case .available(let times) = record.zoneTimes else { return [] }
                return times.compactMap { element in
                    element.value.isFinite && element.value > 0 ? element.key : nil
                }
            },
        ).sorted { $0.rawValue < $1.rawValue }
        let zoneMetrics = zones.map { zone in
            let currentZoneRecords = currentRecords.filter { record in
                guard let projection = Self.zoneProjection(for: record) else { return false }
                return validZoneDuration(projection.zoneDurations[zone]) != nil
            }
            let currentCovered = currentZoneRecords.reduce(0) { total, record in
                guard let projection = Self.zoneProjection(for: record) else { return total }
                return total + (validZoneDuration(projection.zoneDurations[zone]) ?? 0)
            }
            let baselineCovered = comparisonRecords.map { period in
                period.reduce(0) { total, record in
                    guard let projection = Self.zoneProjection(for: record) else { return total }
                    return total + (validZoneDuration(projection.zoneDurations[zone]) ?? 0)
                }
            }
            let coveredHeartRateSeconds = currentRecords.reduce(0) { total, record in
                guard let projection = Self.zoneProjection(for: record) else { return total }
                if record.heartRateProjection == nil {
                    return total
                        + projection.zoneDurations.values.compactMap(validZoneDuration).reduce(0, +)
                }
                return total + projection.coveredSeconds
            }
            let coveredWorkoutDuration = currentRecords.reduce(0) { total, record in
                guard let projection = Self.zoneProjection(for: record) else { return total }
                if record.heartRateProjection == nil {
                    return total + (validDuration(for: record) ?? 0)
                }
                return total + projection.coveredSeconds
            }
            let totalWorkoutDuration = currentRecords.compactMap(validDuration).reduce(0, +)
            let maximumHeartRateBPM = overviewRecords.compactMap {
                $0.heartRateProjection?.maximumHeartRateBPM
            }.first
            let zoneBoundaries = overviewRecords.compactMap {
                $0.heartRateProjection?.zoneBoundaries
            }.first
            let missing =
                overviewRecords.compactMap { record -> String? in
                    switch record.zoneTimes {
                    case .unavailable(let reason): return "\(record.id): \(reason)"
                    case .available, .projected: return nil
                    }
                }
                + overviewRecords.compactMap { record -> String? in
                    guard Self.zoneProjection(for: record) != nil,
                        validDuration(for: record) == nil
                    else { return nil }
                    return "Duration missing for \(record.id)"
                }
            return RollingWorkoutZoneMetric(
                zone: zone,
                coveredSeconds: currentCovered,
                comparisonMedianSeconds: comparisonAvailability == .available
                    ? median(baselineCovered) : nil,
                coveredWorkoutDurationSeconds: coveredWorkoutDuration,
                totalWorkoutDurationSeconds: totalWorkoutDuration,
                coveredHeartRateSeconds: coveredHeartRateSeconds,
                percentOfCoveredTime: coveredHeartRateSeconds > 0
                    ? currentCovered / coveredHeartRateSeconds * 100 : 0,
                coverageOfTotalWorkoutDuration: totalWorkoutDuration > 0
                    ? coveredHeartRateSeconds / totalWorkoutDuration * 100 : 0,
                maximumHeartRateBPM: maximumHeartRateBPM,
                rangeDescription: zoneBoundaries?.rangeDescription(for: zone),
                explanation: explanation(
                    question: "How much associated heart-rate time was in \(zone.displayName)?",
                    included: overviewRecords.filter { record in
                        guard let projection = Self.zoneProjection(for: record) else {
                            return false
                        }
                        return validZoneDuration(projection.zoneDurations[zone]) != nil
                    }.map(\.id),
                    includedDates: Set(
                        overviewRecords.compactMap { record in
                            guard let projection = Self.zoneProjection(for: record),
                                validZoneDuration(projection.zoneDurations[zone]) != nil
                            else { return nil }
                            return record.localDate.iso8601String
                        },
                    ).sorted(),
                    dateRange: overviewDateRange,
                    exclusions: exclusions,
                    coverage: coverage,
                    baseline: comparisonAvailability,
                    formula:
                        "Use only associated sample intervals supplied by Health; gaps over 60 seconds and workout edges remain unavailable. A gap at most 60 seconds is assigned to the earlier sample. Apple Watch range: \(zoneBoundaries?.rangeDescription(for: zone) ?? "not configured").",
                    missing: missing,
                ),
            )
        }
        let zoneAvailabilityExplanation: InsightExplanation? =
            zones.isEmpty
            ? explanation(
                question: "Is associated Heart-Rate Zone time available?",
                included: [],
                includedDates: overviewDates,
                dateRange: overviewDateRange,
                exclusions: exclusions,
                coverage: coverage,
                baseline: comparisonAvailability,
                formula:
                    "Heart-Rate Zone time is shown only when a configured zone projection supplies associated samples.",
                missing: currentRecords.compactMap { record in
                    switch record.zoneTimes {
                    case .unavailable(let reason): "\(record.id): \(reason)"
                    case .available, .projected: nil
                    }
                },
            )
            : nil
        let placeholderExplanation = explanation(
            question: "How much positive workout duration is available?",
            included: overviewRecords.compactMap { record in
                validDuration(for: record).map { _ in record.id }
            },
            includedDates: Set(
                overviewRecords.compactMap { record in
                    validDuration(for: record).map { _ in record.localDate.iso8601String }
                },
            ).sorted(),
            dateRange: overviewDateRange,
            exclusions: exclusions,
            coverage: coverage,
            baseline: comparisonAvailability,
            formula:
                "Sum only positive finite Health Workout duration; missing duration affects duration only.",
            missing: overviewRecords.filter { validDuration(for: $0) == nil }.map {
                "Duration missing for \($0.id)"
            },
        )
        return RollingWorkoutOverview(
            currentWindow: currentWindow,
            comparisonWindows: comparisonWindows,
            comparisonAvailability: comparisonAvailability,
            workoutCount: count,
            totalDuration: RollingWorkoutNumericMetric(
                currentValue: currentRecords.compactMap(validDuration).reduce(0, +),
                comparisonMedian: comparisonAvailability == .available
                    ? median(comparisonRecords.map { $0.compactMap(validDuration).reduce(0, +) })
                    : nil,
                explanation: placeholderExplanation,
            ),
            activityTypes: activityTypes,
            zoneMetrics: zoneMetrics,
            zoneAvailabilityExplanation: zoneAvailabilityExplanation,
            maximumHeartRateBPM: overviewRecords.compactMap {
                $0.heartRateProjection?.maximumHeartRateBPM
            }.first,
        )
    }

    private static func zoneProjection(for record: RollingWorkoutRecord)
        -> HeartRateZoneProjection?
    {
        switch record.zoneTimes {
        case .projected(let projection):
            guard case .available = projection.state else { return nil }
            return projection
        case .available(let times):
            let positive = times.filter { $0.value.isFinite && $0.value > 0 }
            guard !positive.isEmpty else { return nil }
            return HeartRateZoneProjection(
                state: .available,
                zoneDurations: positive,
                coveredSeconds: positive.values.reduce(0, +),
                totalWorkoutDurationSeconds: record.durationSeconds ?? 0,
            )
        case .unavailable:
            return nil
        }
    }

    private func recordsInWindows(
        _ currentWindow: RollingWorkoutWindow,
        _ comparisonWindows: [RollingWorkoutWindow],
        records: [RollingWorkoutRecord],
    ) -> [RollingWorkoutRecord] {
        let windows = [currentWindow] + comparisonWindows
        return records.filter { record in windows.contains { $0.contains(record.localDate) } }
    }

    private func normalizedActivityType(_ activityType: String) -> String {
        activityType.contains(where: { !$0.isWhitespace })
            ? activityType
            : "Activity type unavailable"
    }

    private func validZoneDuration(_ duration: Double?) -> Double? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private func validDuration(for record: RollingWorkoutRecord) -> Double? {
        guard let duration = record.durationSeconds, duration.isFinite, duration > 0 else {
            return nil
        }
        return duration
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        if sorted.count % 2 == 1 {
            return sorted[sorted.count / 2]
        }
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    private func explanation(
        question: String,
        included: [String],
        includedDates: [String],
        dateRange: String,
        exclusions: [InsightExplanationExclusion],
        coverage: RollingWorkoutSourceCoverage,
        baseline: RollingWorkoutComparisonAvailability,
        formula: String,
        missing: [String],
    ) -> InsightExplanation {
        InsightExplanation(
            question: question,
            includedRecordIDs: included,
            excludedRecords: [],
            formula: formula,
            dateRange: dateRange,
            roundingRule: "Calculations retain full precision.",
            sourceState: coverage.description,
            includedDates: includedDates,
            sourceCoverage: coverage.description,
            comparisonBaseline: String(describing: baseline),
            missingData: missing,
            exclusions: exclusions,
            lastReconciliation: coverage.lastReconciliation,
        )
    }
}

public struct RollingWorkoutSourceCoverage: Codable, Equatable, Sendable {
    public let isComplete: Bool
    public let withholdingReason: String
    public let lastReconciliation: String?

    public static func complete(lastReconciliation: String?) -> Self {
        .init(isComplete: true, withholdingReason: "", lastReconciliation: lastReconciliation)
    }

    public static func incomplete(
        reason: String,
        lastReconciliation: String? = nil,
    ) -> Self {
        .init(isComplete: false, withholdingReason: reason, lastReconciliation: lastReconciliation)
    }

    private init(isComplete: Bool, withholdingReason: String, lastReconciliation: String?) {
        self.isComplete = isComplete
        self.withholdingReason = withholdingReason
        self.lastReconciliation = lastReconciliation
    }

    public var description: String {
        isComplete
            ? "Health Workouts stream checked through the complete comparison horizon"
            : withholdingReason
    }
}
