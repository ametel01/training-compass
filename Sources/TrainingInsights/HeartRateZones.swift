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
    source: String = "Source unavailable"
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
    source: String
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

  public var durationSeconds: Double { endDate - startDate }

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

  public var id: String { source }

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
  public let maximumHeartRateBPM: Double?
  public let zoneDurations: [RollingWorkoutZone: Double]
  public let coveredSeconds: Double
  public let unavailableSeconds: Double
  public let unclassifiedSeconds: Double
  public let totalWorkoutDurationSeconds: Double
  public let intervals: [HeartRateZoneInterval]
  public let unavailableIntervals: [HeartRateZoneUnavailableInterval]
  public let sourceSummaries: [HeartRateZoneSourceSummary]

  public init(
    state: HeartRateZoneProjectionState,
    maximumHeartRateBPM: Double? = nil,
    zoneDurations: [RollingWorkoutZone: Double] = [:],
    coveredSeconds: Double = 0,
    unavailableSeconds: Double = 0,
    unclassifiedSeconds: Double = 0,
    totalWorkoutDurationSeconds: Double = 0,
    intervals: [HeartRateZoneInterval] = [],
    unavailableIntervals: [HeartRateZoneUnavailableInterval] = [],
    sourceSummaries: [HeartRateZoneSourceSummary] = []
  ) {
    self.state = state
    self.maximumHeartRateBPM = maximumHeartRateBPM
    self.zoneDurations = zoneDurations
    self.coveredSeconds = coveredSeconds
    self.unavailableSeconds = unavailableSeconds
    self.unclassifiedSeconds = unclassifiedSeconds
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
    let coverage: String
    if sources.isEmpty {
      coverage = "No associated heart-rate samples were available"
    } else {
      coverage = "Associated heart-rate sources: \(sources.joined(separator: ", "))"
    }
    let maximum = maximumHeartRateBPM.map { String($0) } ?? "not configured"
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
        "Fixed bands are 50–59%, 60–69%, 70–79%, 80–89%, and 90–100%; time above the configured maximum remains unclassified.",
      missingData: missing,
      configuration: "Maximum heart rate used: \(maximum) bpm.")
  }

  public static func unavailable(reason: String) -> Self {
    .init(state: .unavailable(reason: reason))
  }
}

/// Calculates fixed app-defined zones using only source-observed intervals.
/// A short gap is attributed to the earlier sample; a gap over 60 seconds and
/// both workout edges remain unavailable.
public struct HeartRateZoneCalculator: Sendable {
  public static let maximumAssociatedGapSeconds = 60.0

  public init() {}

  public func calculate(
    workoutStartDate: Double,
    workoutEndDate: Double,
    samples: [HeartRateSample],
    maximumHeartRate: MaximumHeartRate?
  ) -> HeartRateZoneProjection {
    let totalDuration = workoutEndDate - workoutStartDate
    guard totalDuration.isFinite, totalDuration > 0 else {
      return .unavailable(reason: "Workout duration is unavailable")
    }
    guard let maximumHeartRate else {
      return .unavailable(reason: "Maximum heart rate is not configured")
    }

    let candidates = samples.compactMap { sample -> HeartRateSample? in
      let start = max(sample.startDate, workoutStartDate)
      let end = min(sample.endDate, workoutEndDate)
      guard end > start else { return nil }
      return HeartRateSample(
        id: sample.id,
        startDate: start,
        endDate: end,
        beatsPerMinute: sample.beatsPerMinute,
        source: sample.source)
    }.sorted {
      if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
      return $0.id < $1.id
    }

    guard !candidates.isEmpty else {
      return HeartRateZoneProjection(
        state: .available,
        maximumHeartRateBPM: maximumHeartRate.beatsPerMinute,
        unavailableSeconds: totalDuration,
        totalWorkoutDurationSeconds: totalDuration,
        unavailableIntervals: [
          HeartRateZoneUnavailableInterval(
            id: "unavailable:0", startDate: workoutStartDate, endDate: workoutEndDate,
            reason: "Workout edge")
        ])
    }

    var zoneDurations: [RollingWorkoutZone: Double] = [:]
    var intervals: [HeartRateZoneInterval] = []
    var sourceCovered: [String: (duration: Double, sampleIDs: [String])] = [:]
    var coveredSeconds = 0.0
    var unclassifiedSeconds = 0.0
    var lastAssignedEnd: Double?

    for (index, sample) in candidates.enumerated() {
      // HealthKit intervals are normally disjoint. If a source returns an
      // overlap, assign each instant once in stable order rather than
      // inflating coverage.
      let start = max(sample.startDate, lastAssignedEnd ?? sample.startDate)
      guard sample.endDate > start else { continue }
      var duration = sample.endDate - start
      let nextStart = candidates.dropFirst(index + 1).first?.startDate
      if let nextStart {
        let gap = nextStart - sample.endDate
        if gap >= 0 && gap <= Self.maximumAssociatedGapSeconds {
          duration += min(gap, workoutEndDate - sample.endDate)
        }
      }
      guard duration > 0, duration.isFinite else { continue }

      let zone = zone(for: sample.beatsPerMinute, maximum: maximumHeartRate.beatsPerMinute)
      intervals.append(
        HeartRateZoneInterval(
          id: "\(sample.id):\(intervals.count)",
          zone: zone,
          startDate: start,
          endDate: start + duration,
          durationSeconds: duration,
          sampleID: sample.id,
          source: sample.source))
      coveredSeconds += duration
      var sourceValue = sourceCovered[sample.source] ?? (0, [])
      sourceValue.duration += duration
      if !sourceValue.sampleIDs.contains(sample.id) {
        sourceValue.sampleIDs.append(sample.id)
      }
      sourceCovered[sample.source] = sourceValue
      if let zone {
        zoneDurations[zone, default: 0] += duration
      } else {
        unclassifiedSeconds += duration
      }
      lastAssignedEnd = max(lastAssignedEnd ?? sample.endDate, sample.endDate)
    }

    var unavailableIntervals: [HeartRateZoneUnavailableInterval] = []
    var cursor = workoutStartDate
    for interval in intervals.sorted(by: { $0.startDate < $1.startDate }) {
      if interval.startDate > cursor {
        unavailableIntervals.append(
          HeartRateZoneUnavailableInterval(
            id: "unavailable:\(unavailableIntervals.count)", startDate: cursor,
            endDate: interval.startDate,
            reason: cursor == workoutStartDate ? "Workout edge" : "Gap over 60 seconds"))
      }
      cursor = max(cursor, interval.endDate)
    }
    if cursor < workoutEndDate {
      unavailableIntervals.append(
        HeartRateZoneUnavailableInterval(
          id: "unavailable:\(unavailableIntervals.count)", startDate: cursor,
          endDate: workoutEndDate,
          reason: cursor == workoutStartDate ? "Workout edge" : "Workout edge"))
    }

    return HeartRateZoneProjection(
      state: .available,
      maximumHeartRateBPM: maximumHeartRate.beatsPerMinute,
      zoneDurations: zoneDurations,
      coveredSeconds: coveredSeconds,
      unavailableSeconds: max(0, totalDuration - coveredSeconds),
      unclassifiedSeconds: unclassifiedSeconds,
      totalWorkoutDurationSeconds: totalDuration,
      intervals: intervals,
      unavailableIntervals: unavailableIntervals,
      sourceSummaries: sourceCovered.keys.sorted().map { source in
        let value = sourceCovered[source] ?? (0, [])
        return HeartRateZoneSourceSummary(
          source: source, coveredSeconds: value.duration, sampleIDs: value.sampleIDs)
      })
  }

  private func zone(for bpm: Double, maximum: Double) -> RollingWorkoutZone? {
    let percentage = bpm / maximum
    switch percentage {
    case ..<0.5: return .below50
    case ..<0.6: return .zone1
    case ..<0.7: return .zone2
    case ..<0.8: return .zone3
    case ..<0.9: return .zone4
    case ...1.0: return .zone5
    default: return nil
    }
  }
}
