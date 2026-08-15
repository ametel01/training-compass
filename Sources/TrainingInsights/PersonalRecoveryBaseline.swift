import TrainingDomain

/// The independently reported Recovery Evidence measures.  They intentionally
/// remain separate: a baseline is a descriptive context for one measure, not a
/// score made from several measures.
public enum PersonalRecoveryBaselineMetric: String, Codable, CaseIterable, Equatable, Sendable {
  case primarySleepDuration
  case sleepDurationConsistency
  case sleepTimingConsistency
  case restingHeartRate
  case heartRateVariabilitySDNN

  public static var sleepDuration: Self { .primarySleepDuration }
  public static var durationConsistency: Self { .sleepDurationConsistency }
  public static var timingConsistency: Self { .sleepTimingConsistency }
  public static var hrvSDNN: Self { .heartRateVariabilitySDNN }

  public var displayName: String {
    switch self {
    case .primarySleepDuration: "Primary Sleep duration"
    case .sleepDurationConsistency: "Sleep duration consistency"
    case .sleepTimingConsistency: "Sleep timing consistency"
    case .restingHeartRate: "Resting heart rate"
    case .heartRateVariabilitySDNN: "HRV SDNN"
    }
  }

  public var unit: String {
    switch self {
    case .primarySleepDuration: "seconds"
    case .sleepDurationConsistency, .sleepTimingConsistency: "seconds"
    case .restingHeartRate: "bpm"
    case .heartRateVariabilitySDNN: "ms"
    }
  }

  public var directionWord: String {
    switch self {
    case .primarySleepDuration: "longer or shorter"
    case .sleepDurationConsistency, .sleepTimingConsistency: "more or less variable"
    case .restingHeartRate, .heartRateVariabilitySDNN: "higher or lower"
    }
  }
}

public enum PersonalRecoveryBaselineComparison: String, Codable, Equatable, Sendable {
  case below
  case within
  case above
  case unavailable

  public var displayName: String {
    switch self {
    case .below: "Below the recent middle half"
    case .within: "Within the recent middle half"
    case .above: "Above the recent middle half"
    case .unavailable: "No current comparison"
    }
  }
}

/// One valid daily value supplied by an application boundary.  TrainingInsights
/// knows nothing about HealthKit or sleep episodes; it only applies the
/// calendar, source, and statistical rules to this small value object.
public struct PersonalRecoveryBaselineObservation: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let date: TrainingDate
  public let value: Double
  public let sourceID: String?
  public let sourceName: String
  public let sourceIsComparable: Bool
  public let includedRecordIDs: [String]
  public let sourceCoverage: String
  public let missingData: [String]
  public let algorithmVersions: [String]
  public let lastReconciliation: String?
  public let isCurrent: Bool
  /// A source reconciliation may replace a current value after it was first
  /// observed. Corrected values remain visible but are not eligible for the
  /// cross-family self-check prompt.
  public let isCorrected: Bool

  public init(
    id: String,
    date: TrainingDate,
    value: Double,
    sourceID: String? = nil,
    sourceName: String = "Source unavailable",
    sourceIsComparable: Bool = true,
    includedRecordIDs: [String] = [],
    sourceCoverage: String = "Recorded daily observation",
    missingData: [String] = [],
    algorithmVersions: [String] = [],
    lastReconciliation: String? = nil,
    isCurrent: Bool = false,
    isCorrected: Bool = false
  ) {
    precondition(!id.isEmpty)
    // Zero is a valid consistency value: it means the recorded daily values
    // had no measured variation. Other measures are already validated at
    // their source boundary as positive quantities.
    precondition(value.isFinite && value >= 0)
    self.id = id
    self.date = date
    self.value = value
    self.sourceID = sourceID
    self.sourceName = sourceName.isEmpty ? "Source unavailable" : sourceName
    self.sourceIsComparable = sourceIsComparable
    self.includedRecordIDs = includedRecordIDs.isEmpty ? [id] : includedRecordIDs
    self.sourceCoverage = sourceCoverage
    self.missingData = missingData
    self.algorithmVersions = algorithmVersions
    self.lastReconciliation = lastReconciliation
    self.isCurrent = isCurrent
    self.isCorrected = isCorrected
  }
}

/// A value excluded from the baseline remains named in the explanation.  This
/// is especially important when a source changes or a local date is missing.
public struct PersonalRecoveryBaselineExclusion: Codable, Equatable, Identifiable, Sendable {
  public let recordID: String
  public let date: TrainingDate
  public let reason: String

  public var id: String { "\(recordID):\(reason)" }

  public init(recordID: String, date: TrainingDate, reason: String) {
    self.recordID = recordID
    self.date = date
    self.reason = reason
  }
}

public struct PersonalRecoveryBaseline: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let metric: PersonalRecoveryBaselineMetric
  public let asOfDate: TrainingDate
  public let windowStart: TrainingDate
  public let windowEnd: TrainingDate
  public let minimumObservationDays: Int
  public let validObservationDays: Int
  public let observations: [PersonalRecoveryBaselineObservation]
  public let excludedObservations: [PersonalRecoveryBaselineExclusion]
  public let sourceID: String?
  public let sourceName: String?
  public let sourceCoverage: String
  public let algorithmVersions: [String]
  public let lastReconciliation: String?
  public let missingData: [String]
  public let median: Double?
  public let lowerQuartile: Double?
  public let upperQuartile: Double?
  public let currentObservation: PersonalRecoveryBaselineObservation?
  public let comparison: PersonalRecoveryBaselineComparison
  public let differenceFromMedian: Double?
  public let explanation: InsightExplanation

  public init(
    metric: PersonalRecoveryBaselineMetric,
    asOfDate: TrainingDate,
    windowStart: TrainingDate,
    windowEnd: TrainingDate,
    minimumObservationDays: Int,
    observations: [PersonalRecoveryBaselineObservation],
    excludedObservations: [PersonalRecoveryBaselineExclusion],
    sourceID: String?,
    sourceName: String?,
    median: Double?,
    lowerQuartile: Double?,
    upperQuartile: Double?,
    currentObservation: PersonalRecoveryBaselineObservation?,
    comparison: PersonalRecoveryBaselineComparison,
    differenceFromMedian: Double?,
    explanation: InsightExplanation,
    sourceCoverage: String = "Recorded daily observations",
    algorithmVersions: [String] = [],
    lastReconciliation: String? = nil,
    missingData: [String] = []
  ) {
    precondition(minimumObservationDays > 0)
    self.id = "\(metric.rawValue):\(asOfDate.iso8601String)"
    self.metric = metric
    self.asOfDate = asOfDate
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.minimumObservationDays = minimumObservationDays
    self.validObservationDays = observations.count
    self.observations = observations.sorted { $0.date < $1.date }
    self.excludedObservations = excludedObservations.sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      return $0.recordID < $1.recordID
    }
    self.sourceID = sourceID
    self.sourceName = sourceName
    self.sourceCoverage = sourceCoverage
    self.algorithmVersions = algorithmVersions.sorted()
    self.lastReconciliation = lastReconciliation
    self.missingData = missingData
    self.median = median
    self.lowerQuartile = lowerQuartile
    self.upperQuartile = upperQuartile
    self.currentObservation = currentObservation
    self.comparison = comparison
    self.differenceFromMedian = differenceFromMedian
    self.explanation = explanation
  }

  public var isEstablished: Bool {
    median != nil && lowerQuartile != nil && upperQuartile != nil
  }

  public var middle50Percent: ClosedRange<Double>? {
    guard let lowerQuartile, let upperQuartile else { return nil }
    return lowerQuartile...upperQuartile
  }

  public var currentValue: Double? { currentObservation?.value }

  public var comparisonLabel: String { comparison.displayName }

  public var classification: PersonalRecoveryBaselineComparison { comparison }
  public var baselineMedian: Double? { median }
  public var lowerBound: Double? { lowerQuartile }
  public var upperBound: Double? { upperQuartile }
  public var q1: Double? { lowerQuartile }
  public var q3: Double? { upperQuartile }
  public var exactDifferenceFromMedian: Double? { differenceFromMedian }

  public var neutralDirection: String? {
    guard let differenceFromMedian else { return nil }
    if differenceFromMedian == 0 { return "same as" }
    switch metric {
    case .primarySleepDuration:
      return differenceFromMedian > 0 ? "longer" : "shorter"
    case .sleepDurationConsistency, .sleepTimingConsistency:
      return differenceFromMedian > 0 ? "more variable" : "less variable"
    case .restingHeartRate, .heartRateVariabilitySDNN:
      return differenceFromMedian > 0 ? "higher" : "lower"
    }
  }

  public var comparisonDescription: String? {
    guard let neutralDirection, let differenceFromMedian else { return nil }
    return
      "\(neutralDirection) than the baseline median by \(differenceFromMedian) \(metric.unit)"
  }
}

public struct PersonalRecoveryBaselineProjection: Codable, Equatable, Sendable {
  public let baselines: [PersonalRecoveryBaseline]
  public let explanation: InsightExplanation

  public init(
    baselines: [PersonalRecoveryBaseline] = [],
    explanation: InsightExplanation
  ) {
    self.baselines = baselines.sorted {
      let lhsIndex = PersonalRecoveryBaselineMetric.allCases.firstIndex(of: $0.metric) ?? .max
      let rhsIndex = PersonalRecoveryBaselineMetric.allCases.firstIndex(of: $1.metric) ?? .max
      return lhsIndex < rhsIndex
    }
    self.explanation = explanation
  }

  public func baseline(for metric: PersonalRecoveryBaselineMetric) -> PersonalRecoveryBaseline? {
    baselines.first { $0.metric == metric }
  }

  public var establishedBaselines: [PersonalRecoveryBaseline] {
    baselines.filter(\.isEstablished)
  }
}

/// Calculates one independent personal baseline at a time.  The current date
/// is never included in its own reference window, and absent dates are never
/// synthesized.
public struct PersonalRecoveryBaselineCalculator: Sendable {
  public static let referenceWindowDays = 28
  public static let minimumObservationDays = 14

  public init() {}

  public func calculate(
    metric: PersonalRecoveryBaselineMetric,
    observations: [PersonalRecoveryBaselineObservation],
    asOfDate: TrainingDate,
    minimumObservationDays: Int = Self.minimumObservationDays
  ) -> PersonalRecoveryBaseline {
    precondition(minimumObservationDays > 0)
    let windowStart = asOfDate.adding(days: -Self.referenceWindowDays)
    let windowEnd = asOfDate.adding(days: -1)
    let inWindow = observations.filter { $0.date >= windowStart && $0.date <= windowEnd }
    let currentCandidates = observations.filter {
      $0.date == asOfDate && $0.isCurrent && $0.sourceIsComparable
    }
    let current = currentCandidates.sorted { $0.id < $1.id }.last

    var exclusions: [PersonalRecoveryBaselineExclusion] = []
    var valid = inWindow.filter { observation in
      guard observation.sourceIsComparable else {
        exclusions.append(
          .init(
            recordID: observation.id, date: observation.date, reason: "Source is not comparable"))
        return false
      }
      guard observation.value.isFinite && observation.value >= 0 else {
        exclusions.append(
          .init(
            recordID: observation.id, date: observation.date,
            reason: "Value is not a valid non-negative observation"))
        return false
      }
      return true
    }

    // A source change must not silently join unlike observations.  When a
    // current value exists, it defines the source required for comparison. For
    // a forming baseline, the most recent comparable source is the only source
    // used so that a later source revision cannot blend with its predecessor.
    let comparisonSourceID =
      current?.sourceID
      ?? valid.sorted { lhs, rhs in
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id > rhs.id
      }.first?.sourceID
    if let comparisonSourceID {
      valid = valid.filter { observation in
        guard observation.sourceID == comparisonSourceID else {
          exclusions.append(
            .init(
              recordID: observation.id,
              date: observation.date,
              reason: "Source changed; not combined with \(comparisonSourceID)"))
          return false
        }
        return true
      }
    } else if valid.contains(where: { $0.sourceID != nil }) {
      valid = valid.filter { observation in
        guard observation.sourceID != nil else {
          exclusions.append(
            .init(
              recordID: observation.id, date: observation.date,
              reason: "Source identity unavailable"))
          return false
        }
        return true
      }
    }

    // A daily measure has one value per local date.  Keep the deterministic
    // final identity when a caller accidentally supplies duplicate revisions.
    var byDate: [TrainingDate: PersonalRecoveryBaselineObservation] = [:]
    // Input order is the reconciliation order, so a later representation of
    // the same local date is the correction that remains visible.
    for observation in valid {
      if let previous = byDate[observation.date] {
        exclusions.append(
          .init(
            recordID: previous.id,
            date: previous.date,
            reason: "Duplicate daily observation; latest identity retained"))
      }
      byDate[observation.date] = observation
    }
    valid = byDate.values.sorted { $0.date < $1.date }

    let numbers = valid.map(\.value).sorted()
    let established = numbers.count >= minimumObservationDays
    let median = established ? quantile(numbers, probability: 0.5) : nil
    let lower = established ? quantile(numbers, probability: 0.25) : nil
    let upper = established ? quantile(numbers, probability: 0.75) : nil
    let compatibleCurrent: PersonalRecoveryBaselineObservation? = {
      guard let current, current.sourceIsComparable else { return nil }
      guard comparisonSourceID == nil || current.sourceID == comparisonSourceID else {
        return nil
      }
      return current
    }()
    let comparison: PersonalRecoveryBaselineComparison
    if let compatibleCurrent, let lower, let upper {
      if compatibleCurrent.value < lower {
        comparison = .below
      } else if compatibleCurrent.value > upper {
        comparison = .above
      } else {
        comparison = .within
      }
    } else {
      comparison = .unavailable
    }
    let difference = compatibleCurrent.flatMap { current in median.map { current.value - $0 } }

    let includedIDs = valid.flatMap(\.includedRecordIDs)
    let includedDates = valid.map { $0.date.iso8601String }
    let sourceNames = Set(valid.map(\.sourceName)).sorted()
    let sourceIDs = Set(valid.compactMap(\.sourceID)).sorted()
    let missing = Set(
      observations.flatMap(\.missingData)
        + (numbers.count < minimumObservationDays
          ? [
            "Only \(numbers.count) valid observation days; at least \(minimumObservationDays) are required"
          ]
          : [])
        + (compatibleCurrent == nil
          ? ["No source-comparable current observation is available"] : [])
    ).sorted()
    let sourceDescription =
      sourceNames.isEmpty
      ? "No comparable source"
      : sourceNames.joined(separator: ", ")
    let sourceIdentityDescription =
      sourceIDs.isEmpty
      ? "identity unavailable"
      : sourceIDs.joined(separator: ", ")
    let reconciliation = observations.compactMap(\.lastReconciliation).sorted().last
    let coverageDescription = Set(observations.map(\.sourceCoverage)).sorted()
      .joined(separator: "; ")
    let algorithmVersions = Set(observations.flatMap(\.algorithmVersions)).sorted()
    let algorithmDescription =
      algorithmVersions.isEmpty
      ? "Algorithm context: not provided by source"
      : "Algorithm context: \(algorithmVersions.joined(separator: ", "))"
    let baselineLabel =
      established
      ? "\(numbers.count) valid days from \(windowStart.iso8601String) through \(windowEnd.iso8601String); median and 25th–75th percentiles"
      : "Withheld until \(minimumObservationDays) valid days are available (\(numbers.count) present)"
    let differenceLabel = difference.map { String($0) } ?? "unavailable"
    let currentLabel: String
    if let compatibleCurrent {
      currentLabel =
        "Current \(compatibleCurrent.value) on \(compatibleCurrent.date.iso8601String): \(comparison.displayName); difference from median \(differenceLabel)"
    } else {
      currentLabel = "No current source-comparable observation"
    }
    let explanation = InsightExplanation(
      question:
        "How does the current \(metric.displayName) compare with the preceding 28 local calendar days?",
      includedRecordIDs: includedIDs + (compatibleCurrent?.includedRecordIDs ?? []),
      excludedRecords: [],
      formula:
        "Median and middle 50 percent (25th–75th percentiles) of one valid daily \(metric.displayName) at a time.",
      dateRange:
        "\(windowStart.iso8601String) through \(asOfDate.iso8601String) (current day excluded from baseline)",
      roundingRule:
        "Stored values, median, quartiles, and current difference retain full precision; presentation may round only for display.",
      sourceState:
        "Source: \(sourceDescription) (\(sourceIdentityDescription)). \(algorithmDescription). \(currentLabel)",
      includedDates: includedDates + (compatibleCurrent.map { [$0.date.iso8601String] } ?? []),
      sourceCoverage:
        "Recorded source coverage: \(coverageDescription.isEmpty ? "unavailable" : coverageDescription). Only valid daily observations are included; missing dates are ignored and never filled or carried forward.",
      calculationRule:
        "The preceding 28 local calendar dates are \(windowStart.iso8601String) through \(windowEnd.iso8601String). Source changes, incomparable sources, and duplicate daily revisions are excluded rather than combined.",
      comparisonBaseline: baselineLabel,
      missingData: missing,
      exclusions: exclusions.map {
        .init(recordID: $0.recordID, reason: "\($0.reason) on \($0.date.iso8601String)")
      },
      lastReconciliation: reconciliation,
      configuration:
        "Minimum valid days: \(minimumObservationDays). Quartiles: linearly interpolated order statistics. \(metric.directionWord)."
    )

    return PersonalRecoveryBaseline(
      metric: metric,
      asOfDate: asOfDate,
      windowStart: windowStart,
      windowEnd: windowEnd,
      minimumObservationDays: minimumObservationDays,
      observations: valid,
      excludedObservations: exclusions,
      sourceID: comparisonSourceID,
      sourceName: sourceNames.first,
      median: median,
      lowerQuartile: lower,
      upperQuartile: upper,
      currentObservation: compatibleCurrent,
      comparison: comparison,
      differenceFromMedian: difference,
      explanation: explanation,
      sourceCoverage: coverageDescription.isEmpty
        ? "No recorded source coverage" : coverageDescription,
      algorithmVersions: algorithmVersions,
      lastReconciliation: reconciliation,
      missingData: missing)
  }

  public func calculateProjection(
    observations: [PersonalRecoveryBaselineMetric: [PersonalRecoveryBaselineObservation]],
    asOfDate: TrainingDate,
    minimumObservationDays: Int = Self.minimumObservationDays
  ) -> PersonalRecoveryBaselineProjection {
    let baselines = PersonalRecoveryBaselineMetric.allCases.filter {
      observations[$0] != nil
    }.map { metric in
      calculate(
        metric: metric,
        observations: observations[metric] ?? [],
        asOfDate: asOfDate,
        minimumObservationDays: minimumObservationDays)
    }
    let explanation = InsightExplanation(
      question:
        "Which independent Recovery Evidence measures have an established personal baseline?",
      includedRecordIDs: baselines.flatMap { $0.explanation.includedRecordIDs },
      excludedRecords: [],
      formula:
        "Calculate one median and middle 50 percent band per measure; never combine measures into a score.",
      dateRange: asOfDate.iso8601String,
      roundingRule: "All baseline statistics and differences retain full precision.",
      sourceState: baselines.map {
        "\($0.metric.displayName): \($0.isEstablished ? "established" : "forming")"
      }.joined(separator: "; "),
      includedDates: baselines.flatMap { $0.explanation.includedDates },
      sourceCoverage:
        "Each measure retains its own source, coverage, missing-data, and reconciliation context.",
      calculationRule:
        "A measure's current date is excluded from that measure's 28-day baseline; missing dates are not synthesized.",
      comparisonBaseline: baselines.map { "\($0.metric.displayName): \($0.comparison.displayName)" }
        .joined(separator: "; "),
      missingData: baselines.flatMap { $0.explanation.missingData },
      exclusions: baselines.flatMap { $0.explanation.exclusions },
      lastReconciliation: baselines.compactMap { $0.explanation.lastReconciliation }.sorted().last,
      configuration: "Independent measures only; no combined score or ranking.")
    return PersonalRecoveryBaselineProjection(baselines: baselines, explanation: explanation)
  }

  private func quantile(_ sorted: [Double], probability: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    guard sorted.count > 1 else { return sorted[0] }
    let position = probability * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    if lower == upper { return sorted[lower] }
    let fraction = position - Double(lower)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
  }
}

public typealias RecoveryBaseline = PersonalRecoveryBaseline
public typealias RecoveryBaselineObservation = PersonalRecoveryBaselineObservation
public typealias RecoveryBaselineCalculator = PersonalRecoveryBaselineCalculator
