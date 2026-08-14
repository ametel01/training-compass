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

public struct RunningPerformance: Codable, Equatable, Sendable {
  public let runs: [RunningRunSummary]
  public let selectedRunID: String?
  public let selectedRun: RunningRunSummary?
  public let volume: RunningVolume

  public init(
    runs: [RunningRunSummary],
    selectedRunID: String?,
    selectedRun: RunningRunSummary?,
    volume: RunningVolume
  ) {
    self.runs = runs
    self.selectedRunID = selectedRunID
    self.selectedRun = selectedRun
    self.volume = volume
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
    lastReconciliation: String? = nil
  ) -> RunningPerformance {
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
    return RunningPerformance(
      runs: summaries,
      selectedRunID: selectedID,
      selectedRun: selected,
      volume: RunningVolumeCalculator().calculate(
        records: records,
        asOf: asOf,
        sourceCoverage: sourceCoverage,
        lastReconciliation: lastReconciliation))
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
