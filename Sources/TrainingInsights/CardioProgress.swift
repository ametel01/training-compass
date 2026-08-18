import TrainingDomain

public struct CardioWorkoutRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let localDate: TrainingDate
  public let activityType: String
  public let startDate: Double
  public let endDate: Double
  public let distanceMeters: Double?
  public let heartRateSamples: [HeartRateSample]

  public init(
    id: String,
    localDate: TrainingDate,
    activityType: String,
    startDate: Double,
    endDate: Double,
    distanceMeters: Double? = nil,
    heartRateSamples: [HeartRateSample] = [],
  ) {
    self.id = id
    self.localDate = localDate
    self.activityType = activityType
    self.startDate = startDate
    self.endDate = endDate
    self.distanceMeters = distanceMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    self.heartRateSamples = heartRateSamples
  }
}

public enum CardioInsightDirection: String, Codable, Equatable, Sendable {
  case improving
  case declining
  case unchanged
  case unavailable

  public var displayName: String {
    switch self {
    case .improving: "Improving"
    case .declining: "Declining"
    case .unchanged: "No change"
    case .unavailable: "Not enough data"
    }
  }
}

public struct CardioEfficiencyTrend: Codable, Equatable, Sendable {
  public let direction: CardioInsightDirection
  public let activityType: String?
  public let latestMetersPerHeartbeat: Double?
  public let baselineMetersPerHeartbeat: Double?
  public let percentChange: Double?
  public let comparisonCount: Int
}

public enum CardioHeartRateDriftAvailability: Codable, Equatable, Sendable {
  case available
  case unavailable(reason: String)
}

public struct CardioHeartRateDrift: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let localDate: TrainingDate
  public let activityType: String
  public let availability: CardioHeartRateDriftAvailability
  public let firstHalfAverageBPM: Double?
  public let secondHalfAverageBPM: Double?
  public let driftPercent: Double?
  public let firstHalfCoverage: Double
  public let secondHalfCoverage: Double
}

public struct CardioProgress: Codable, Equatable, Sendable {
  public let efficiency: CardioEfficiencyTrend
  public let heartRateDrifts: [CardioHeartRateDrift]
}

public struct CardioProgressCalculator: Sendable {
  public static let warmupSeconds = 10 * 60.0
  public static let minimumCoverage = 0.8

  public init() {}

  public func calculate(records: [CardioWorkoutRecord]) -> CardioProgress {
    let ordered = records.sorted {
      if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
      return $0.id < $1.id
    }
    return CardioProgress(
      efficiency: efficiency(records: ordered),
      heartRateDrifts: ordered.map(drift),
    )
  }

  private func drift(_ record: CardioWorkoutRecord) -> CardioHeartRateDrift {
    let analysisStart = record.startDate + Self.warmupSeconds
    guard record.endDate > analysisStart else {
      return unavailableDrift(record, reason: "Session is not longer than 10 minutes")
    }
    let midpoint = analysisStart + (record.endDate - analysisStart) / 2
    let intervals = HeartRateWeightedIntervalBuilder().intervals(
      workoutStartDate: record.startDate,
      workoutEndDate: record.endDate,
      samples: record.heartRateSamples,
    )
    let first = average(intervals, from: analysisStart, to: midpoint)
    let second = average(intervals, from: midpoint, to: record.endDate)
    let halfDuration = midpoint - analysisStart
    let firstCoverage = halfDuration > 0 ? first.coveredSeconds / halfDuration : 0
    let secondCoverage = halfDuration > 0 ? second.coveredSeconds / halfDuration : 0
    guard firstCoverage >= Self.minimumCoverage, secondCoverage >= Self.minimumCoverage,
      let firstBPM = first.averageBPM, let secondBPM = second.averageBPM, firstBPM > 0
    else {
      return CardioHeartRateDrift(
        id: record.id,
        localDate: record.localDate,
        activityType: record.activityType,
        availability: .unavailable(
          reason: "Heart-rate coverage is below 80% in one or both halves"),
        firstHalfAverageBPM: first.averageBPM,
        secondHalfAverageBPM: second.averageBPM,
        driftPercent: nil,
        firstHalfCoverage: firstCoverage,
        secondHalfCoverage: secondCoverage,
      )
    }
    return CardioHeartRateDrift(
      id: record.id,
      localDate: record.localDate,
      activityType: record.activityType,
      availability: .available,
      firstHalfAverageBPM: firstBPM,
      secondHalfAverageBPM: secondBPM,
      driftPercent: (secondBPM - firstBPM) / firstBPM * 100,
      firstHalfCoverage: firstCoverage,
      secondHalfCoverage: secondCoverage,
    )
  }

  private func efficiency(records: [CardioWorkoutRecord]) -> CardioEfficiencyTrend {
    let points = records.compactMap { record -> (record: CardioWorkoutRecord, value: Double)? in
      guard let distance = record.distanceMeters else { return nil }
      let duration = record.endDate - record.startDate
      guard duration > 0 else { return nil }
      let intervals = HeartRateWeightedIntervalBuilder().intervals(
        workoutStartDate: record.startDate,
        workoutEndDate: record.endDate,
        samples: record.heartRateSamples,
      )
      let heartRate = average(intervals, from: record.startDate, to: record.endDate)
      guard heartRate.coveredSeconds / duration >= Self.minimumCoverage,
        let bpm = heartRate.averageBPM, bpm > 0
      else { return nil }
      let beats = bpm * duration / 60
      return (record, distance / beats)
    }
    guard let latest = points.first else {
      return CardioEfficiencyTrend(
        direction: .unavailable,
        activityType: nil,
        latestMetersPerHeartbeat: nil,
        baselineMetersPerHeartbeat: nil,
        percentChange: nil,
        comparisonCount: 0,
      )
    }
    let comparisons = points.dropFirst().filter {
      $0.record.activityType.lowercased() == latest.record.activityType.lowercased()
    }.prefix(4).map(\.value)
    guard let baseline = median(Array(comparisons)), baseline > 0 else {
      return CardioEfficiencyTrend(
        direction: .unavailable,
        activityType: latest.record.activityType,
        latestMetersPerHeartbeat: latest.value,
        baselineMetersPerHeartbeat: nil,
        percentChange: nil,
        comparisonCount: 0,
      )
    }
    let change = (latest.value - baseline) / baseline * 100
    let direction: CardioInsightDirection =
      if abs(change) < 0.000_001 {
        .unchanged
      } else if change > 0 {
        .improving
      } else {
        .declining
      }
    return CardioEfficiencyTrend(
      direction: direction,
      activityType: latest.record.activityType,
      latestMetersPerHeartbeat: latest.value,
      baselineMetersPerHeartbeat: baseline,
      percentChange: change,
      comparisonCount: comparisons.count,
    )
  }

  private func average(
    _ intervals: [HeartRateWeightedInterval],
    from start: Double,
    to end: Double,
  ) -> (averageBPM: Double?, coveredSeconds: Double) {
    let weighted = intervals.reduce(into: (seconds: 0.0, bpmSeconds: 0.0)) { result, interval in
      let lower = max(start, interval.startDate)
      let upper = min(end, interval.endDate)
      guard upper > lower else { return }
      let seconds = upper - lower
      result.seconds += seconds
      result.bpmSeconds += seconds * interval.beatsPerMinute
    }
    return (
      weighted.seconds > 0 ? weighted.bpmSeconds / weighted.seconds : nil,
      weighted.seconds,
    )
  }

  private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2
      : sorted[middle]
  }

  private func unavailableDrift(
    _ record: CardioWorkoutRecord,
    reason: String,
  ) -> CardioHeartRateDrift {
    CardioHeartRateDrift(
      id: record.id,
      localDate: record.localDate,
      activityType: record.activityType,
      availability: .unavailable(reason: reason),
      firstHalfAverageBPM: nil,
      secondHalfAverageBPM: nil,
      driftPercent: nil,
      firstHalfCoverage: 0,
      secondHalfCoverage: 0,
    )
  }
}
