import TrainingDomain

/// A source-aware heart-rate observation used by the pure zone calculator.
/// `source` is intentionally an application-owned label, never a HealthKit
/// object, so this module remains independent of Apple frameworks.
public struct HeartRateSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// Seconds since the Unix epoch. A scalar keeps the pure insights module
    /// independent of Foundation while retaining full timestamp precision.
    public let startDate: Double
    public let endDate: Double
    public let beatsPerMinute: Double
    public let source: String

    public init(
        id: String,
        startDate: Double,
        endDate: Double,
        beatsPerMinute: Double,
        source: String = "Source unavailable",
    ) {
        precondition(!id.isEmpty)
        precondition(endDate >= startDate)
        precondition(beatsPerMinute.isFinite && beatsPerMinute > 0)
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.beatsPerMinute = beatsPerMinute
        self.source = source.isEmpty ? "Source unavailable" : source
    }
}

/// A source-observed interval suitable for time-weighted calculations.
/// Instantaneous Health samples own time only until the next sample and only
/// when that gap is no longer than the same 60-second association ceiling used
/// by the zone projection.
public struct HeartRateWeightedInterval: Codable, Equatable, Sendable {
    public let startDate: Double
    public let endDate: Double
    public let beatsPerMinute: Double
    public let sampleID: String
    public let source: String

    public var durationSeconds: Double {
        endDate - startDate
    }
}

public struct HeartRateWeightedIntervalBuilder: Sendable {
    public init() {}

    public func intervals(
        workoutStartDate: Double,
        workoutEndDate: Double,
        samples: [HeartRateSample],
        maximumGapSeconds: Double = 60,
    ) -> [HeartRateWeightedInterval] {
        guard workoutEndDate > workoutStartDate else { return [] }
        let candidates = samples.filter {
            $0.endDate >= workoutStartDate && $0.startDate <= workoutEndDate
        }.sorted {
            if $0.startDate != $1.startDate {
                return $0.startDate < $1.startDate
            }
            return $0.id < $1.id
        }
        var result: [HeartRateWeightedInterval] = []
        var lastAssignedEnd = workoutStartDate

        for (index, sample) in candidates.enumerated() {
            let sampleStart = max(sample.startDate, workoutStartDate)
            let sampleEnd = min(sample.endDate, workoutEndDate)
            var assignedEnd = sampleEnd
            if let next = candidates.dropFirst(index + 1).first {
                let nextStart = min(max(next.startDate, workoutStartDate), workoutEndDate)
                let gap = nextStart - sampleEnd
                if gap >= 0, gap <= maximumGapSeconds {
                    assignedEnd = nextStart
                }
            }
            let assignedStart = max(sampleStart, lastAssignedEnd)
            guard assignedEnd > assignedStart else { continue }
            result.append(
                HeartRateWeightedInterval(
                    startDate: assignedStart,
                    endDate: assignedEnd,
                    beatsPerMinute: sample.beatsPerMinute,
                    sampleID: sample.id,
                    source: sample.source,
                ),
            )
            lastAssignedEnd = assignedEnd
        }
        return result
    }
}

public struct HeartRateZoneInterval: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let zone: RollingWorkoutZone?
    public let startDate: Double
    public let endDate: Double
    public let durationSeconds: Double
    public let sampleID: String
    public let source: String

    public init(
        id: String,
        zone: RollingWorkoutZone?,
        startDate: Double,
        endDate: Double,
        durationSeconds: Double,
        sampleID: String,
        source: String,
    ) {
        self.id = id
        self.zone = zone
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.sampleID = sampleID
        self.source = source
    }
}

public struct HeartRateZoneUnavailableInterval: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let startDate: Double
    public let endDate: Double
    public let reason: String

    public var durationSeconds: Double {
        endDate - startDate
    }

    public init(id: String, startDate: Double, endDate: Double, reason: String) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.reason = reason
    }
}

public struct HeartRateZoneSourceSummary: Codable, Equatable, Sendable, Identifiable {
    public let source: String
    public let coveredSeconds: Double
    public let sampleIDs: [String]

    public var id: String {
        source
    }

    public init(source: String, coveredSeconds: Double, sampleIDs: [String]) {
        self.source = source
        self.coveredSeconds = coveredSeconds
        self.sampleIDs = sampleIDs
    }
}

public enum HeartRateZoneProjectionState: Codable, Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

/// A transparent projection of one workout's associated heart-rate samples.
/// Coverage is the duration represented by source samples and permitted
/// inter-sample gaps; it is never extrapolated to workout edges.
public struct HeartRateZoneProjection: Codable, Equatable, Sendable {
    public let state: HeartRateZoneProjectionState
    public let zoneBoundaries: HeartRateZoneBoundaries?
    public let maximumHeartRateBPM: Double?
    public let zoneDurations: [RollingWorkoutZone: Double]
    public let coveredSeconds: Double
    public let unavailableSeconds: Double
    public let totalWorkoutDurationSeconds: Double
    public let intervals: [HeartRateZoneInterval]
    public let unavailableIntervals: [HeartRateZoneUnavailableInterval]
    public let sourceSummaries: [HeartRateZoneSourceSummary]

    public init(
        state: HeartRateZoneProjectionState,
        zoneBoundaries: HeartRateZoneBoundaries? = nil,
        maximumHeartRateBPM: Double? = nil,
        zoneDurations: [RollingWorkoutZone: Double] = [:],
        coveredSeconds: Double = 0,
        unavailableSeconds: Double = 0,
        totalWorkoutDurationSeconds: Double = 0,
        intervals: [HeartRateZoneInterval] = [],
        unavailableIntervals: [HeartRateZoneUnavailableInterval] = [],
        sourceSummaries: [HeartRateZoneSourceSummary] = [],
    ) {
        self.state = state
        self.zoneBoundaries = zoneBoundaries
        self.maximumHeartRateBPM =
            maximumHeartRateBPM ?? zoneBoundaries?.maximumHeartRate.beatsPerMinute
        self.zoneDurations = zoneDurations
        self.coveredSeconds = coveredSeconds
        self.unavailableSeconds = unavailableSeconds
        self.totalWorkoutDurationSeconds = totalWorkoutDurationSeconds
        self.intervals = intervals
        self.unavailableIntervals = unavailableIntervals
        self.sourceSummaries = sourceSummaries
    }

    public var coverageOfWorkoutPercentage: Double {
        guard totalWorkoutDurationSeconds > 0 else { return 0 }
        return coveredSeconds / totalWorkoutDurationSeconds * 100
    }

    public var zonePercentagesOfCoveredTime: [RollingWorkoutZone: Double] {
        guard coveredSeconds > 0 else { return [:] }
        return zoneDurations.mapValues { $0 / coveredSeconds * 100 }
    }

    /// The same source-aware explanation used by the owner-facing zone detail.
    /// Keeping this at the projection seam ensures a workout-level derived value
    /// cannot be displayed without a path back to its samples and coverage.
    public var explanation: InsightExplanation {
        let included = sourceSummaries.flatMap(\.sampleIDs)
        let missing = unavailableIntervals.map {
            "\($0.reason) from \($0.startDate) through \($0.endDate)"
        }
        let sources = sourceSummaries.map { "\($0.source) (\($0.sampleIDs.count) samples)" }
        let coverage =
            if sources.isEmpty {
                "No associated heart-rate samples were available"
            } else {
                "Associated heart-rate sources: \(sources.joined(separator: ", "))"
            }
        let configuredRanges = zoneBoundaries?.summary ?? "not configured"
        return InsightExplanation(
            question: "How was this workout's Heart-Rate Zone time calculated?",
            includedRecordIDs: included,
            excludedRecords: [],
            formula:
            "Assign elapsed time to the earlier associated sample when the gap is at most 60 seconds; gaps over 60 seconds and workout edges remain unavailable.",
            dateRange:
            "Workout interval \(intervals.first?.startDate ?? 0) through \(intervals.last?.endDate ?? totalWorkoutDurationSeconds)",
            roundingRule:
            "Calculations retain full precision; displayed durations and percentages are rounded for presentation.",
            sourceState: String(describing: state),
            sourceCoverage: coverage,
            calculationRule:
            "Use the five continuous BPM ranges copied from Apple Watch; Zone 1 and Zone 5 are open-ended.",
            missingData: missing,
            configuration: configuredRanges,
        )
    }

    public static func unavailable(reason: String) -> Self {
        .init(state: .unavailable(reason: reason))
    }
}

/// Calculates the owner's configured Apple Watch zones using only source-observed intervals.
/// A short gap is attributed to the earlier sample; a gap over 60 seconds and
/// both workout edges remain unavailable.
public struct HeartRateZoneCalculator: Sendable {
    public static let maximumAssociatedGapSeconds = 60.0

    public init() {}

    public func calculate(
        workoutStartDate: Double,
        workoutEndDate: Double,
        samples: [HeartRateSample],
        zoneBoundaries: HeartRateZoneBoundaries?,
    ) -> HeartRateZoneProjection {
        let totalDuration = workoutEndDate - workoutStartDate
        guard totalDuration.isFinite, totalDuration > 0 else {
            return .unavailable(reason: "Workout duration is unavailable")
        }
        guard let zoneBoundaries else {
            return .unavailable(reason: "Heart-rate zone boundaries are not configured")
        }

        let weightedIntervals = HeartRateWeightedIntervalBuilder().intervals(
            workoutStartDate: workoutStartDate,
            workoutEndDate: workoutEndDate,
            samples: samples,
            maximumGapSeconds: Self.maximumAssociatedGapSeconds,
        )

        guard !weightedIntervals.isEmpty else {
            return HeartRateZoneProjection(
                state: .available,
                zoneBoundaries: zoneBoundaries,
                unavailableSeconds: totalDuration,
                totalWorkoutDurationSeconds: totalDuration,
                unavailableIntervals: [
                    HeartRateZoneUnavailableInterval(
                        id: "unavailable:0", startDate: workoutStartDate, endDate: workoutEndDate,
                        reason: "Workout edge",
                    ),
                ],
            )
        }

        var zoneDurations: [RollingWorkoutZone: Double] = [:]
        var intervals: [HeartRateZoneInterval] = []
        var sourceCovered: [String: (duration: Double, sampleIDs: [String])] = [:]
        var coveredSeconds = 0.0
        for weighted in weightedIntervals {
            let duration = weighted.durationSeconds
            let zone = zone(for: weighted.beatsPerMinute, boundaries: zoneBoundaries)
            intervals.append(
                HeartRateZoneInterval(
                    id: "\(weighted.sampleID):\(intervals.count)",
                    zone: zone,
                    startDate: weighted.startDate,
                    endDate: weighted.endDate,
                    durationSeconds: duration,
                    sampleID: weighted.sampleID,
                    source: weighted.source,
                ),
            )
            coveredSeconds += duration
            var sourceValue = sourceCovered[weighted.source] ?? (0, [])
            sourceValue.duration += duration
            if !sourceValue.sampleIDs.contains(weighted.sampleID) {
                sourceValue.sampleIDs.append(weighted.sampleID)
            }
            sourceCovered[weighted.source] = sourceValue
            zoneDurations[zone, default: 0] += duration
        }

        var unavailableIntervals: [HeartRateZoneUnavailableInterval] = []
        var cursor = workoutStartDate
        for interval in intervals.sorted(by: { $0.startDate < $1.startDate }) {
            if interval.startDate > cursor {
                unavailableIntervals.append(
                    HeartRateZoneUnavailableInterval(
                        id: "unavailable:\(unavailableIntervals.count)", startDate: cursor,
                        endDate: interval.startDate,
                        reason: cursor == workoutStartDate ? "Workout edge" : "Gap over 60 seconds",
                    ),
                )
            }
            cursor = max(cursor, interval.endDate)
        }
        if cursor < workoutEndDate {
            unavailableIntervals.append(
                HeartRateZoneUnavailableInterval(
                    id: "unavailable:\(unavailableIntervals.count)", startDate: cursor,
                    endDate: workoutEndDate,
                    reason: cursor == workoutStartDate ? "Workout edge" : "Workout edge",
                ),
            )
        }

        return HeartRateZoneProjection(
            state: .available,
            zoneBoundaries: zoneBoundaries,
            zoneDurations: zoneDurations,
            coveredSeconds: coveredSeconds,
            unavailableSeconds: max(0, totalDuration - coveredSeconds),
            totalWorkoutDurationSeconds: totalDuration,
            intervals: intervals,
            unavailableIntervals: unavailableIntervals,
            sourceSummaries: sourceCovered.keys.sorted().map { source in
                let value = sourceCovered[source] ?? (0, [])
                return HeartRateZoneSourceSummary(
                    source: source, coveredSeconds: value.duration, sampleIDs: value.sampleIDs,
                )
            },
        )
    }

    private func zone(for bpm: Double, boundaries: HeartRateZoneBoundaries) -> RollingWorkoutZone {
        switch bpm {
        case ..<boundaries.zone2MinimumBPM: .zone1
        case ..<boundaries.zone3MinimumBPM: .zone2
        case ..<boundaries.zone4MinimumBPM: .zone3
        case ..<boundaries.zone5MinimumBPM: .zone4
        default: .zone5
        }
    }
}

public extension HeartRateZoneBoundaries {
    func rangeDescription(for zone: RollingWorkoutZone) -> String {
        switch zone {
        case .zone1: "≤\(bpmText(zone2MinimumBPM - 1)) bpm"
        case .zone2: "\(bpmText(zone2MinimumBPM))–\(bpmText(zone3MinimumBPM - 1)) bpm"
        case .zone3: "\(bpmText(zone3MinimumBPM))–\(bpmText(zone4MinimumBPM - 1)) bpm"
        case .zone4: "\(bpmText(zone4MinimumBPM))–\(bpmText(zone5MinimumBPM - 1)) bpm"
        case .zone5: "≥\(bpmText(zone5MinimumBPM)) bpm"
        }
    }

    var summary: String {
        "Apple Watch ranges: "
            + RollingWorkoutZone.allCases.map {
                "\($0.displayName) \(rangeDescription(for: $0))"
            }.joined(separator: ", ")
            + "; resting \(bpmText(restingHeartRateBPM)) bpm; maximum \(bpmText(maximumHeartRate.beatsPerMinute)) bpm."
    }

    private func bpmText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
