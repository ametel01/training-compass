import TrainingDomain

/// The environment explicitly supplied by the Health workout source.  It is
/// never inferred from distance, route, device, or the workout's title.
public enum RunningEnvironment: String, Codable, CaseIterable, Equatable, Sendable {
  case outdoor
  case indoor
  case treadmill
  case unspecified

  public var displayName: String {
    switch self {
    case .outdoor: "Outdoor"
    case .indoor: "Indoor"
    case .treadmill: "Treadmill"
    case .unspecified: "Unspecified"
    }
  }
}

public enum RunningRouteAvailability: String, Codable, Equatable, Sendable {
  case available
  case unavailable
  case notChecked

  public var displayName: String {
    switch self {
    case .available: "Available"
    case .unavailable: "Not available"
    case .notChecked: "Not checked"
    }
  }
}

/// Time-weighted heart-rate context for one run.  The heart-rate value is
/// intentionally optional when associated samples do not cover enough of the
/// Health workout to support a comparison.
public struct RunningHeartRateContext: Codable, Equatable, Sendable {
  public let averageBeatsPerMinute: Double?
  public let coveredSeconds: Double
  public let workoutDurationSeconds: Double?
  public let source: String

  public init(
    averageBeatsPerMinute: Double?,
    coveredSeconds: Double,
    workoutDurationSeconds: Double?,
    source: String = "Source unavailable"
  ) {
    self.averageBeatsPerMinute = averageBeatsPerMinute
    self.coveredSeconds = max(0, coveredSeconds)
    self.workoutDurationSeconds = workoutDurationSeconds
    self.source = source.isEmpty ? "Source unavailable" : source
  }

  public var coverage: Double? {
    guard let workoutDurationSeconds, workoutDurationSeconds > 0 else { return nil }
    return coveredSeconds / workoutDurationSeconds
  }

  public var hasComparisonCoverage: Bool {
    guard let coverage else { return false }
    return coverage >= 0.8
  }

  public static func unavailable(reason: String) -> Self {
    .init(
      averageBeatsPerMinute: nil, coveredSeconds: 0, workoutDurationSeconds: nil, source: reason)
  }
}

/// Facts needed by the running projection.  The record is already known to be
/// source-classified as running; callers must not construct one by guessing
/// from a route, distance, or pace.
public struct RunningWorkoutRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let localDate: TrainingDate
  /// Unix seconds retained at full precision for stable chronology and exact
  /// tie-breaking.  UUID is used only when two values are equal.
  public let startDate: Double
  public let durationSeconds: Double?
  public let distanceMeters: Double?
  public let environment: RunningEnvironment
  public let elevationMeters: Double?
  public let routeAvailability: RunningRouteAvailability
  public let heartRate: RunningHeartRateContext
  public let source: String
  public let sourceCoverage: String
  public let lastReconciliation: String?
  public let importedAt: Double?

  public init(
    id: String,
    localDate: TrainingDate,
    startDate: Double,
    durationSeconds: Double?,
    distanceMeters: Double?,
    environment: RunningEnvironment = .unspecified,
    elevationMeters: Double? = nil,
    routeAvailability: RunningRouteAvailability = .notChecked,
    heartRate: RunningHeartRateContext = .unavailable(reason: "Heart-rate context unavailable"),
    source: String = "Source unavailable",
    sourceCoverage: String = "Health Workouts coverage unavailable",
    lastReconciliation: String? = nil,
    importedAt: Double? = nil
  ) {
    precondition(!id.isEmpty)
    self.id = id
    self.localDate = localDate
    self.startDate = startDate
    self.durationSeconds = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    self.distanceMeters = distanceMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    self.environment = environment
    self.elevationMeters = elevationMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    self.routeAvailability = routeAvailability
    self.heartRate = heartRate
    self.source = source.isEmpty ? "Source unavailable" : source
    self.sourceCoverage = sourceCoverage
    self.lastReconciliation = lastReconciliation
    self.importedAt = importedAt.flatMap { $0.isFinite ? $0 : nil }
  }

  public var averageRunningPace: RunningPace? {
    RunningPace(durationSeconds: durationSeconds, distanceMeters: distanceMeters)
  }

  public var averageRunningPaceSecondsPerKilometer: Double? {
    averageRunningPace?.secondsPerKilometer
  }

  /// HealthKit's running activity identifiers are source labels, not an app
  /// inference.  The numeric value is Apple's stable running activity value.
  public static func isSourceClassifiedRunning(activityType: String) -> Bool {
    let normalized = String(activityType.filter { !$0.isWhitespace }).lowercased()
    return normalized == "running" || normalized == "37"
  }
}

public typealias RunningRecord = RunningWorkoutRecord

public struct RunningPace: Codable, Equatable, Sendable {
  public let secondsPerKilometer: Double

  public init?(durationSeconds: Double?, distanceMeters: Double?) {
    guard let durationSeconds, let distanceMeters,
      durationSeconds.isFinite, durationSeconds > 0,
      distanceMeters.isFinite, distanceMeters > 0
    else { return nil }
    let seconds = durationSeconds / (distanceMeters / 1_000)
    guard seconds.isFinite, seconds > 0 else { return nil }
    self.secondsPerKilometer = seconds
  }

  public init?(secondsPerKilometer: Double) {
    guard secondsPerKilometer.isFinite, secondsPerKilometer > 0 else { return nil }
    self.secondsPerKilometer = secondsPerKilometer
  }

  public var minutesPerKilometer: Double { secondsPerKilometer / 60 }

  /// A display-only value.  Calculation and comparison always use the full
  /// precision `secondsPerKilometer` value.
  public var displayValue: String {
    let rounded = Int(secondsPerKilometer.rounded())
    let seconds = rounded % 60
    return "\(rounded / 60):\(seconds < 10 ? "0" : "")\(seconds) min/km"
  }
}

public typealias AverageRunningPace = RunningPace

public struct RunningVolumeMetric: Codable, Equatable, Sendable {
  public let currentValue: Double
  public let comparisonMedian: Double?
  public let explanation: InsightExplanation

  public init(currentValue: Double, comparisonMedian: Double?, explanation: InsightExplanation) {
    self.currentValue = currentValue
    self.comparisonMedian = comparisonMedian
    self.explanation = explanation
  }
}

public struct RunningVolumeWindow: Codable, Equatable, Sendable {
  public let start: TrainingDate
  public let end: TrainingDate

  public init(start: TrainingDate, end: TrainingDate) {
    precondition(start <= end)
    self.start = start
    self.end = end
  }

  public func contains(_ date: TrainingDate) -> Bool { date >= start && date <= end }

  public var displayName: String { "\(start.iso8601String) through \(end.iso8601String)" }
}

public struct RunningVolume: Codable, Equatable, Sendable {
  public let currentWindow: RunningVolumeWindow
  public let comparisonWindows: [RunningVolumeWindow]
  public let runs: [RunningWorkoutRecord]
  public let count: RunningVolumeMetric
  public let availableDuration: RunningVolumeMetric
  public let availableDistance: RunningVolumeMetric

  public init(
    currentWindow: RunningVolumeWindow,
    comparisonWindows: [RunningVolumeWindow],
    runs: [RunningWorkoutRecord],
    count: RunningVolumeMetric,
    availableDuration: RunningVolumeMetric,
    availableDistance: RunningVolumeMetric
  ) {
    self.currentWindow = currentWindow
    self.comparisonWindows = comparisonWindows
    self.runs = runs
    self.count = count
    self.availableDuration = availableDuration
    self.availableDistance = availableDistance
  }
}

public struct RunningRunSummary: Codable, Equatable, Identifiable, Sendable {
  public let record: RunningWorkoutRecord
  public let averageRunningPace: RunningPace?
  public let explanation: InsightExplanation

  public var id: String { record.id }
  public var averageRunningPaceSecondsPerKilometer: Double? {
    averageRunningPace?.secondsPerKilometer
  }

  public init(
    record: RunningWorkoutRecord,
    averageRunningPace: RunningPace?,
    explanation: InsightExplanation
  ) {
    self.record = record
    self.averageRunningPace = averageRunningPace
    self.explanation = explanation
  }
}

public enum RunningComparisonDirection: String, Codable, Equatable, Sendable {
  case faster
  case slower
  case higher
  case lower
  case unchanged
  case unavailable

  public var displayName: String {
    switch self {
    case .faster: "Faster"
    case .slower: "Slower"
    case .higher: "Higher"
    case .lower: "Lower"
    case .unchanged: "Unchanged"
    case .unavailable: "Unavailable"
    }
  }
}

public struct RunningComparisonMetric: Codable, Equatable, Sendable {
  public let referenceValue: Double?
  public let comparisonValue: Double?
  public let difference: Double?
  public let direction: RunningComparisonDirection
  public let statement: String

  public init(
    referenceValue: Double?,
    comparisonValue: Double?,
    difference: Double?,
    direction: RunningComparisonDirection,
    statement: String
  ) {
    self.referenceValue = referenceValue
    self.comparisonValue = comparisonValue
    self.difference = difference
    self.direction = direction
    self.statement = statement
  }

  public var isAvailable: Bool { difference != nil }
}

public struct RunningComparisonExclusion: Codable, Equatable, Identifiable, Sendable {
  public let healthKitUUID: String
  public let excludedAt: Double

  public var id: String { healthKitUUID }

  public init(healthKitUUID: String, excludedAt: Double) {
    precondition(!healthKitUUID.isEmpty)
    self.healthKitUUID = healthKitUUID
    self.excludedAt = excludedAt
  }
}

public struct RunningComparisonBaseline: Codable, Equatable, Sendable {
  public let runIDs: [String]
  public let paceSecondsPerKilometer: Double?
  public let durationSeconds: Double?
  public let distanceMeters: Double?
  public let heartRateBeatsPerMinute: Double?

  public init(
    runIDs: [String],
    paceSecondsPerKilometer: Double?,
    durationSeconds: Double?,
    distanceMeters: Double?,
    heartRateBeatsPerMinute: Double?
  ) {
    self.runIDs = runIDs
    self.paceSecondsPerKilometer = paceSecondsPerKilometer
    self.durationSeconds = durationSeconds
    self.distanceMeters = distanceMeters
    self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
  }
}

public struct RunningPerformanceComparison: Codable, Equatable, Sendable {
  public let referenceRunID: String
  public let precedingComparableRunID: String?
  public let precedingComparableRun: RunningRunSummary?
  public let precedingFourComparableRunIDs: [String]
  public let baseline: RunningComparisonBaseline?
  public let pace: RunningComparisonMetric
  public let duration: RunningComparisonMetric
  public let distance: RunningComparisonMetric
  public let heartRate: RunningComparisonMetric
  public let medianPace: RunningComparisonMetric?
  public let medianDuration: RunningComparisonMetric?
  public let medianDistance: RunningComparisonMetric?
  public let medianHeartRate: RunningComparisonMetric?
  public let explanation: InsightExplanation

  public init(
    referenceRunID: String,
    precedingComparableRunID: String?,
    precedingComparableRun: RunningRunSummary?,
    precedingFourComparableRunIDs: [String],
    baseline: RunningComparisonBaseline?,
    pace: RunningComparisonMetric,
    duration: RunningComparisonMetric,
    distance: RunningComparisonMetric,
    heartRate: RunningComparisonMetric,
    medianPace: RunningComparisonMetric? = nil,
    medianDuration: RunningComparisonMetric? = nil,
    medianDistance: RunningComparisonMetric? = nil,
    medianHeartRate: RunningComparisonMetric? = nil,
    explanation: InsightExplanation
  ) {
    self.referenceRunID = referenceRunID
    self.precedingComparableRunID = precedingComparableRunID
    self.precedingComparableRun = precedingComparableRun
    self.precedingFourComparableRunIDs = precedingFourComparableRunIDs
    self.baseline = baseline
    self.pace = pace
    self.duration = duration
    self.distance = distance
    self.heartRate = heartRate
    self.medianPace = medianPace
    self.medianDuration = medianDuration
    self.medianDistance = medianDistance
    self.medianHeartRate = medianHeartRate
    self.explanation = explanation
  }

  public var median: RunningComparisonBaseline? { baseline }
  public var hasPrecedingComparableRun: Bool { precedingComparableRun != nil }
}

public typealias RunningComparison = RunningPerformanceComparison

public struct RunningPerformance: Codable, Equatable, Sendable {
  public let runs: [RunningRunSummary]
  public let selectedRunID: String?
  public let selectedRun: RunningRunSummary?
  public let volume: RunningVolume
  public let comparison: RunningPerformanceComparison?
  public let comparisonHistoryDays: Int
  public let excludedRunIDs: [String]

  public var selectedComparison: RunningPerformanceComparison? { comparison }
  public var runningComparison: RunningPerformanceComparison? { comparison }

  public init(
    runs: [RunningRunSummary],
    selectedRunID: String?,
    selectedRun: RunningRunSummary?,
    volume: RunningVolume,
    comparison: RunningPerformanceComparison? = nil,
    comparisonHistoryDays: Int = 90,
    excludedRunIDs: [String] = []
  ) {
    self.runs = runs
    self.selectedRunID = selectedRunID
    self.selectedRun = selectedRun
    self.volume = volume
    self.comparison = comparison
    self.comparisonHistoryDays = comparisonHistoryDays
    self.excludedRunIDs = excludedRunIDs.sorted()
  }
}

public struct RunningVolumeCalculator: Sendable {
  public init() {}

  public func calculate(
    records: [RunningWorkoutRecord],
    asOf: TrainingDate,
    sourceCoverage: String,
    lastReconciliation: String? = nil
  ) -> RunningVolume {
    let currentWindow = RunningVolumeWindow(start: asOf.adding(days: -6), end: asOf)
    let comparisonWindows = (1...4).map { index in
      let end = asOf.adding(days: -7 * index)
      return RunningVolumeWindow(start: end.adding(days: -6), end: end)
    }
    let current = records.filter { currentWindow.contains($0.localDate) }
    let comparisons = comparisonWindows.map { window in
      records.filter { window.contains($0.localDate) }
    }
    let horizon = RunningVolumeWindow(
      start: comparisonWindows.last?.start ?? asOf.adding(days: -34), end: asOf)
    let inHorizon = records.filter { horizon.contains($0.localDate) }
    let outside = records.filter { !horizon.contains($0.localDate) }
    let dateRange =
      "Current: \(currentWindow.displayName). Comparison: "
      + comparisonWindows.map(\.displayName).joined(separator: "; ")
    let dates = Set(inHorizon.map { $0.localDate.iso8601String }).sorted()
    let exclusions = outside.map {
      InsightExplanationExclusion(recordID: $0.id, reason: "Outside the 35-date volume horizon")
    }

    let countExplanation = makeExplanation(
      question: "How many source-classified running Health Workouts occurred?",
      records: inHorizon,
      dates: dates,
      dateRange: dateRange,
      sourceCoverage: sourceCoverage,
      baseline: "Median of four preceding non-overlapping seven-day periods",
      formula:
        "Count every source-classified running workout once, including runs with missing detail.",
      missing: [], exclusions: exclusions, lastReconciliation: lastReconciliation)
    let durationMissing = inHorizon.filter { $0.durationSeconds == nil }.map {
      "Duration unavailable for \($0.id)"
    }
    let durationExplanation = makeExplanation(
      question: "What positive HealthKit workout duration is available for running?",
      records: inHorizon.filter { $0.durationSeconds != nil },
      dates: dates,
      dateRange: dateRange,
      sourceCoverage: sourceCoverage,
      baseline: "Median of four preceding non-overlapping seven-day periods",
      formula:
        "Sum positive HealthKit workout duration; missing or non-positive duration contributes no duration but never removes the run from count.",
      missing: durationMissing, exclusions: exclusions, lastReconciliation: lastReconciliation)
    let distanceMissing = inHorizon.filter { $0.distanceMeters == nil }.map {
      "Distance unavailable for \($0.id)"
    }
    let distanceExplanation = makeExplanation(
      question: "What positive HealthKit distance is available for running?",
      records: inHorizon.filter { $0.distanceMeters != nil },
      dates: dates,
      dateRange: dateRange,
      sourceCoverage: sourceCoverage,
      baseline: "Median of four preceding non-overlapping seven-day periods",
      formula:
        "Sum positive HealthKit distance in metres; missing or non-positive distance contributes no distance but never removes the run from count.",
      missing: distanceMissing, exclusions: exclusions, lastReconciliation: lastReconciliation)

    return RunningVolume(
      currentWindow: currentWindow,
      comparisonWindows: comparisonWindows,
      runs: current.sorted(by: Self.chronologicalOrder),
      count: RunningVolumeMetric(
        currentValue: Double(current.count),
        comparisonMedian: median(comparisons.map { Double($0.count) }),
        explanation: countExplanation),
      availableDuration: RunningVolumeMetric(
        currentValue: current.compactMap(\.durationSeconds).reduce(0, +),
        comparisonMedian: median(comparisons.map { $0.compactMap(\.durationSeconds).reduce(0, +) }),
        explanation: durationExplanation),
      availableDistance: RunningVolumeMetric(
        currentValue: current.compactMap(\.distanceMeters).reduce(0, +),
        comparisonMedian: median(comparisons.map { $0.compactMap(\.distanceMeters).reduce(0, +) }),
        explanation: distanceExplanation))
  }

  private func makeExplanation(
    question: String,
    records: [RunningWorkoutRecord],
    dates: [String],
    dateRange: String,
    sourceCoverage: String,
    baseline: String,
    formula: String,
    missing: [String],
    exclusions: [InsightExplanationExclusion],
    lastReconciliation: String?
  ) -> InsightExplanation {
    InsightExplanation(
      question: question,
      includedRecordIDs: records.map(\.id),
      excludedRecords: [],
      formula: formula,
      dateRange: dateRange,
      roundingRule: "Aggregate values retain full precision; display formatting is separate.",
      sourceState: sourceCoverage,
      includedDates: dates,
      sourceCoverage: sourceCoverage,
      calculationRule: formula,
      comparisonBaseline: baseline,
      missingData: missing,
      exclusions: exclusions,
      lastReconciliation: lastReconciliation)
  }

  private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }

  private static func chronologicalOrder(
    _ lhs: RunningWorkoutRecord,
    _ rhs: RunningWorkoutRecord
  ) -> Bool {
    if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
    return lhs.id > rhs.id
  }
}

public struct RunningPerformanceCalculator: Sendable {
  public init() {}

  public func calculate(
    records: [RunningWorkoutRecord],
    selectedRunID: String? = nil,
    asOf: TrainingDate,
    sourceCoverage: String,
    lastReconciliation: String? = nil,
    excludedRunIDs: [String],
    historyDays: Int = 90
  ) -> RunningPerformance {
    calculate(
      records: records,
      selectedRunID: selectedRunID,
      asOf: asOf,
      sourceCoverage: sourceCoverage,
      lastReconciliation: lastReconciliation,
      excludedRunIDs: Set(excludedRunIDs),
      historyDays: historyDays)
  }

  public func calculate(
    records: [RunningWorkoutRecord],
    selectedRunID: String? = nil,
    asOf: TrainingDate,
    sourceCoverage: String,
    lastReconciliation: String? = nil,
    excludedRunIDs: Set<String> = [],
    historyDays: Int = 90
  ) -> RunningPerformance {
    let historyDays = max(1, historyDays)
    let ordered = records.sorted {
      if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
      return $0.id > $1.id
    }
    let summaries = ordered.map { record in
      RunningRunSummary(
        record: record,
        averageRunningPace: record.averageRunningPace,
        explanation: explanation(
          for: record, sourceCoverage: sourceCoverage, lastReconciliation: lastReconciliation))
    }
    let selectedID =
      selectedRunID.flatMap { id in ordered.contains { $0.id == id } ? id : nil }
      ?? records.max(by: { lhs, rhs in
        if lhs.importedAt != rhs.importedAt {
          return (lhs.importedAt ?? -.greatestFiniteMagnitude)
            < (rhs.importedAt ?? -.greatestFiniteMagnitude)
        }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.id < rhs.id
      })?.id
      ?? ordered.first?.id
    let selected = summaries.first { $0.id == selectedID }
    let builtComparison: RunningPerformanceComparison? = {
      guard let selected else { return nil }
      return comparison(
        reference: selected,
        summaries: summaries,
        excludedRunIDs: excludedRunIDs,
        historyDays: historyDays,
        sourceCoverage: sourceCoverage,
        lastReconciliation: lastReconciliation)
    }()
    return RunningPerformance(
      runs: summaries,
      selectedRunID: selectedID,
      selectedRun: selected,
      volume: RunningVolumeCalculator().calculate(
        records: records,
        asOf: asOf,
        sourceCoverage: sourceCoverage,
        lastReconciliation: lastReconciliation),
      comparison: builtComparison,
      comparisonHistoryDays: historyDays,
      excludedRunIDs: Array(excludedRunIDs))
  }

  private enum MetricKind {
    case pace
    case positiveDifference
  }

  private func comparison(
    reference: RunningRunSummary,
    summaries: [RunningRunSummary],
    excludedRunIDs: Set<String>,
    historyDays: Int,
    sourceCoverage: String,
    lastReconciliation: String?
  ) -> RunningPerformanceComparison {
    let referenceRecord = reference.record
    let candidates =
      summaries
      .filter { candidate in
        guard !excludedRunIDs.contains(reference.id),
          candidate.id != reference.id, !excludedRunIDs.contains(candidate.id)
        else { return false }
        guard isEarlier(candidate.record, than: referenceRecord) else { return false }
        guard referenceRecord.startDate - candidate.record.startDate <= Double(historyDays) * 86_400
        else {
          return false
        }
        return isComparable(candidate.record, to: referenceRecord)
      }
      .sorted { isEarlier($1.record, than: $0.record) }
    let preceding = candidates.first
    let four = Array(candidates.prefix(4))
    let baseline =
      four.count == 4
      ? RunningComparisonBaseline(
        runIDs: four.map(\.id),
        paceSecondsPerKilometer: median(four.compactMap(\.averageRunningPaceSecondsPerKilometer)),
        durationSeconds: median(four.compactMap(\.record.durationSeconds)),
        distanceMeters: median(four.compactMap(\.record.distanceMeters)),
        heartRateBeatsPerMinute: medianHeartRate(
          reference: reference.record, preceding: four.map(\.record))
      )
      : nil
    let baselineLabel =
      baseline.map {
        "Median of four preceding Comparable Runs: \($0.runIDs.joined(separator: ", "))"
      }
      ?? "No four-run median until four preceding Comparable Runs exist."
    let comparisonIDs = [reference.id] + four.map(\.id)
    let explanation = InsightExplanation(
      question: "How does running workout \(reference.id) compare with preceding Comparable Runs?",
      includedRecordIDs: comparisonIDs,
      excludedRecords: [],
      formula:
        "Comparable Run = positive duration and distance, matching source-owned environment, and full-precision distance within 5% of the selected run.",
      dateRange:
        "Selected run \(reference.record.localDate.iso8601String); history: preceding \(historyDays) days",
      roundingRule:
        "Pace is displayed to the nearest second per kilometre; duration to the nearest second and distance to the nearest metre. Differences retain full precision.",
      sourceState: sourceCoverage,
      includedDates: Set(
        comparisonIDs.compactMap { id in
          summaries.first { $0.id == id }?.record.localDate.iso8601String
        }
      ).sorted(),
      sourceCoverage: sourceCoverage,
      calculationRule:
        "Runs are ordered by HealthKit start time; UUID is used only for exact start-time ties. Unspecified environments match only Unspecified. Elevation and route are context, not eligibility.",
      comparisonBaseline: baselineLabel,
      missingData: comparisonMissingData(
        reference: reference, preceding: preceding, baseline: baseline),
      exclusions: summaries.filter { excludedRunIDs.contains($0.id) }.map {
        InsightExplanationExclusion(recordID: $0.id, reason: "Running Comparison Exclusion")
      },
      lastReconciliation: lastReconciliation ?? reference.record.lastReconciliation,
      configuration: "Comparable history defaults to 90 days and can be extended on demand.")
    return RunningPerformanceComparison(
      referenceRunID: reference.id,
      precedingComparableRunID: preceding?.id,
      precedingComparableRun: preceding,
      precedingFourComparableRunIDs: four.map(\.id),
      baseline: baseline,
      pace: metric(
        reference: reference.averageRunningPaceSecondsPerKilometer,
        comparison: preceding?.averageRunningPaceSecondsPerKilometer,
        kind: .pace,
        unit: "min/km"),
      duration: metric(
        reference: reference.record.durationSeconds,
        comparison: preceding?.record.durationSeconds,
        kind: .positiveDifference,
        unit: "seconds"),
      distance: metric(
        reference: reference.record.distanceMeters,
        comparison: preceding?.record.distanceMeters,
        kind: .positiveDifference,
        unit: "metres"),
      heartRate: metric(
        reference: comparableHeartRate(for: reference.record),
        comparison: preceding.flatMap { comparableHeartRate(for: $0.record) },
        kind: .positiveDifference,
        unit: "bpm"),
      medianPace: baseline.map {
        metric(
          reference: reference.averageRunningPaceSecondsPerKilometer,
          comparison: $0.paceSecondsPerKilometer,
          kind: .pace,
          unit: "min/km")
      },
      medianDuration: baseline.map {
        metric(
          reference: reference.record.durationSeconds,
          comparison: $0.durationSeconds,
          kind: .positiveDifference,
          unit: "seconds")
      },
      medianDistance: baseline.map {
        metric(
          reference: reference.record.distanceMeters,
          comparison: $0.distanceMeters,
          kind: .positiveDifference,
          unit: "metres")
      },
      medianHeartRate: baseline.map {
        metric(
          reference: comparableHeartRate(for: reference.record),
          comparison: $0.heartRateBeatsPerMinute,
          kind: .positiveDifference,
          unit: "bpm")
      },
      explanation: explanation)
  }

  private func metric(
    reference: Double?, comparison: Double?, kind: MetricKind, unit: String
  ) -> RunningComparisonMetric {
    guard let reference, let comparison else {
      return .init(
        referenceValue: reference,
        comparisonValue: comparison,
        difference: nil,
        direction: .unavailable,
        statement: "Unavailable: a positive, comparable value is not available for both runs.")
    }
    let difference = reference - comparison
    let displayReference = displayValue(reference, kind: kind)
    let displayComparison = displayValue(comparison, kind: kind)
    if displayReference == displayComparison {
      return .init(
        referenceValue: reference,
        comparisonValue: comparison,
        difference: difference,
        direction: .unchanged,
        statement: "Unchanged at displayed precision (\(displayReference) \(unit)).")
    }
    let direction: RunningComparisonDirection
    switch kind {
    case .pace:
      direction = difference < 0 ? .faster : .slower
    case .positiveDifference:
      direction = difference > 0 ? .higher : .lower
    }
    return .init(
      referenceValue: reference,
      comparisonValue: comparison,
      difference: difference,
      direction: direction,
      statement:
        "\(direction.displayName) by \(displayDifference(abs(difference), kind: kind)) \(unit).")
  }

  private func isComparable(_ candidate: RunningWorkoutRecord, to reference: RunningWorkoutRecord)
    -> Bool
  {
    guard let candidateDistance = candidate.distanceMeters,
      let candidateDuration = candidate.durationSeconds,
      let referenceDistance = reference.distanceMeters,
      let referenceDuration = reference.durationSeconds,
      candidateDistance > 0, candidateDuration > 0, referenceDistance > 0, referenceDuration > 0
    else { return false }
    guard candidate.environment == reference.environment else { return false }
    let tolerance = referenceDistance * 0.05
    return candidateDistance >= referenceDistance - tolerance
      && candidateDistance <= referenceDistance + tolerance
  }

  private func isEarlier(_ lhs: RunningWorkoutRecord, than rhs: RunningWorkoutRecord) -> Bool {
    if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
    return lhs.id < rhs.id
  }

  private func comparableHeartRate(for record: RunningWorkoutRecord) -> Double? {
    guard record.heartRate.hasComparisonCoverage else { return nil }
    return record.heartRate.averageBeatsPerMinute
  }

  private func medianHeartRate(
    reference: RunningWorkoutRecord, preceding: [RunningWorkoutRecord]
  ) -> Double? {
    guard comparableHeartRate(for: reference) != nil,
      preceding.count == 4,
      preceding.allSatisfy({ comparableHeartRate(for: $0) != nil })
    else { return nil }
    return median(preceding.compactMap { comparableHeartRate(for: $0) })
  }

  private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2
      : sorted[middle]
  }

  private func displayValue(_ value: Double, kind: MetricKind) -> Int {
    switch kind {
    case .pace, .positiveDifference: return Int(value.rounded())
    }
  }

  private func displayDifference(_ value: Double, kind: MetricKind) -> String {
    switch kind {
    case .pace:
      let rounded = Int(value.rounded())
      let seconds = rounded % 60
      return "\(rounded / 60):\(seconds < 10 ? "0" : "")\(seconds)"
    case .positiveDifference: return String(Int(value.rounded()))
    }
  }

  private func comparisonMissingData(
    reference: RunningRunSummary,
    preceding: RunningRunSummary?,
    baseline: RunningComparisonBaseline?
  ) -> [String] {
    var missing: [String] = []
    if preceding == nil { missing.append("No preceding Comparable Run is available") }
    if baseline == nil {
      missing.append("Four preceding Comparable Runs are required for the median")
    }
    if comparableHeartRate(for: reference.record) == nil {
      missing.append("Selected run heart-rate coverage is below 80% or unavailable")
    }
    if let preceding, comparableHeartRate(for: preceding.record) == nil {
      missing.append("Preceding Comparable Run heart-rate coverage is below 80% or unavailable")
    }
    if baseline != nil, baseline?.heartRateBeatsPerMinute == nil {
      missing.append(
        "Median heart-rate comparison requires at least 80% coverage for all five runs")
    }
    return missing
  }

  private func explanation(
    for record: RunningWorkoutRecord,
    sourceCoverage: String,
    lastReconciliation: String?
  ) -> InsightExplanation {
    var missing: [String] = []
    if record.durationSeconds == nil { missing.append("HealthKit workout duration unavailable") }
    if record.distanceMeters == nil { missing.append("HealthKit distance unavailable") }
    if record.elevationMeters == nil { missing.append("Elevation unavailable") }
    if record.routeAvailability != .available {
      missing.append("Route: \(record.routeAvailability.displayName)")
    }
    if record.heartRate.averageBeatsPerMinute == nil {
      missing.append("Heart-rate context unavailable")
    }
    return InsightExplanation(
      question: "What facts are available for running workout \(record.id)?",
      includedRecordIDs: [record.id],
      excludedRecords: [],
      formula: "Average Running Pace = HealthKit workout duration ÷ positive HealthKit distance.",
      dateRange: record.localDate.iso8601String,
      roundingRule:
        "Pace calculations retain full precision and display minutes per kilometre rounded to the nearest second.",
      sourceState: record.source,
      includedDates: [record.localDate.iso8601String],
      sourceCoverage: sourceCoverage,
      calculationRule:
        "Run Date is the stable source-timezone date captured at first import; the date owns the whole run across midnight.",
      missingData: missing,
      lastReconciliation: lastReconciliation ?? record.lastReconciliation,
      configuration: "Environment is source-owned: \(record.environment.displayName).")
  }
}
