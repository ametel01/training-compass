import Foundation
import TrainingInsights

/// The independent quantity streams that can be reduced to one daily
/// Recovery Evidence observation. Sleep remains an episode projection because
/// its source-owned intervals have different date and continuity semantics.
public enum HealthRecoveryObservationMetric: String, Codable, CaseIterable, Equatable, Sendable {
  case restingHeartRate
  case heartRateVariabilitySDNN

  /// Short alias for call sites that already use the stream's name.
  public static var heartRateVariability: Self { .heartRateVariabilitySDNN }

  public var displayName: String {
    switch self {
    case .restingHeartRate: "Resting heart rate"
    case .heartRateVariabilitySDNN: "HRV SDNN"
    }
  }

  public var unit: String {
    switch self {
    case .restingHeartRate: "bpm"
    case .heartRateVariabilitySDNN: "ms"
    }
  }

  public var stream: HealthSyncStream {
    switch self {
    case .restingHeartRate: .restingHeartRate
    case .heartRateVariabilitySDNN: .heartRateVariability
    }
  }
}

/// A stable source identity for daily quantity observations. The raw
/// provenance remains available on the included samples; this value is the
/// comparison identity used when reducing multiple samples on one date.
public struct HealthRecoveryObservationSource: Codable, Equatable, Hashable, Identifiable,
  Sendable {
  public let id: String
  public let displayName: String
  public let isComparable: Bool

  public init(id: String, displayName: String, isComparable: Bool = true) {
    precondition(!id.isEmpty)
    self.id = id
    self.displayName = displayName.isEmpty ? "Source unavailable" : displayName
    self.isComparable = isComparable
  }

  public init(provenance: HealthRecoverySampleProvenance) {
    if let bundle = Self.nonEmpty(provenance.sourceBundleIdentifier) {
      self.init(id: "bundle:\(bundle)", displayName: provenance.displayName)
    } else if let product = Self.nonEmpty(provenance.sourceProductType) {
      self.init(id: "product:\(product)", displayName: provenance.displayName)
    } else if let name = Self.nonEmpty(provenance.sourceName) {
      self.init(id: "name:\(name)", displayName: provenance.displayName)
    } else if let device = Self.nonEmpty(provenance.deviceName) {
      self.init(id: "device:\(device)", displayName: provenance.displayName)
    } else {
      self.init(id: "unavailable", displayName: provenance.displayName, isComparable: false)
    }
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return value
  }
}

extension HealthRecoverySampleProvenance {
  /// Source metadata is shown as context, never used to infer a measurement.
  public var detailLabel: String {
    var details: [String] = []
    if let sourceProductType { details.append(sourceProductType) }
    if let deviceName { details.append(deviceName) }
    if let deviceModel, deviceModel != deviceName { details.append(deviceModel) }
    if let sourceBundleIdentifier { details.append(sourceBundleIdentifier) }
    if let sourceOSVersion { details.append("OS \(sourceOSVersion)") }
    if details.isEmpty { return "Source metadata unavailable" }
    return details.joined(separator: " · ")
  }
}

/// The latest included sample is retained as context rather than treating its
/// timestamp as the daily value's date. This makes late replacement and
/// sparse-source behavior inspectable without inferring freshness from data.
public struct HealthRecoveryIncludedSampleContext: Codable, Equatable, Sendable {
  public let id: String
  public let date: Date
  public let provenance: HealthRecoverySampleProvenance

  public init(id: String, date: Date, provenance: HealthRecoverySampleProvenance) {
    self.id = id
    self.date = date
    self.provenance = provenance
  }

  public var source: HealthRecoveryObservationSource {
    HealthRecoveryObservationSource(provenance: provenance)
  }
}

/// One neutral daily observation for resting heart rate or HRV SDNN.
public struct HealthRecoveryDailyObservation: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let metric: HealthRecoveryObservationMetric
  public let date: TrainingDate
  public let value: Double
  public let source: HealthRecoveryObservationSource
  public let sourceProvenance: HealthRecoverySampleProvenance
  public let sampleIDs: [String]
  public let sampleCount: Int
  public let latestIncludedSample: HealthRecoveryIncludedSampleContext
  public let algorithmVersions: [String]
  public let coverage: HealthStreamCoverage
  public let reconciliation: HealthStreamReconciliationState
  public let lastSuccessfulReconciliation: Date?
  public let failure: HealthStreamFailure?
  public let isCurrent: Bool
  /// A repeated source identity represents a corrected/reconciled value. It
  /// remains visible in Recovery Evidence but cannot gate cross-family guidance.
  public let isCorrected: Bool
  public let explanation: InsightExplanation

  public init(
    id: String,
    metric: HealthRecoveryObservationMetric,
    date: TrainingDate,
    value: Double,
    source: HealthRecoveryObservationSource,
    sourceProvenance: HealthRecoverySampleProvenance,
    sampleIDs: [String],
    latestIncludedSample: HealthRecoveryIncludedSampleContext,
    algorithmVersions: [String],
    coverage: HealthStreamCoverage,
    reconciliation: HealthStreamReconciliationState,
    lastSuccessfulReconciliation: Date?,
    failure: HealthStreamFailure?,
    isCurrent: Bool,
    isCorrected: Bool = false,
    explanation: InsightExplanation
  ) {
    precondition(!id.isEmpty)
    precondition(value.isFinite && value > 0)
    precondition(!sampleIDs.isEmpty)
    self.id = id
    self.metric = metric
    self.date = date
    self.value = value
    self.source = source
    self.sourceProvenance = sourceProvenance
    self.sampleIDs = sampleIDs
    self.sampleCount = sampleIDs.count
    self.latestIncludedSample = latestIncludedSample
    self.algorithmVersions = algorithmVersions
    self.coverage = coverage
    self.reconciliation = reconciliation
    self.lastSuccessfulReconciliation = lastSuccessfulReconciliation
    self.failure = failure
    self.isCurrent = isCurrent
    self.isCorrected = isCorrected
    self.explanation = explanation
  }

  public var unit: String { metric.unit }
  public var latestIncludedSampleID: String { latestIncludedSample.id }
  public var latestIncludedSampleDate: Date { latestIncludedSample.date }
  public var latestAlgorithmVersion: String? { algorithmVersions.last }
  public var sourceIsComparable: Bool { source.isComparable }
}

/// The application-owned daily projection for the two quantity streams.
public struct HealthRecoveryObservationProjection: Codable, Equatable, Sendable {
  public let restingHeartRate: [HealthRecoveryDailyObservation]
  public let heartRateVariability: [HealthRecoveryDailyObservation]
  public let statuses: [HealthStreamStatus]
  public let explanation: InsightExplanation

  public init(
    restingHeartRate: [HealthRecoveryDailyObservation] = [],
    heartRateVariability: [HealthRecoveryDailyObservation] = [],
    statuses: [HealthStreamStatus] = [],
    explanation: InsightExplanation
  ) {
    self.restingHeartRate = restingHeartRate.sorted { $0.date < $1.date }
    self.heartRateVariability = heartRateVariability.sorted { $0.date < $1.date }
    self.statuses = statuses
    self.explanation = explanation
  }

  public func observations(for metric: HealthRecoveryObservationMetric)
    -> [HealthRecoveryDailyObservation] {
    switch metric {
    case .restingHeartRate: restingHeartRate
    case .heartRateVariabilitySDNN: heartRateVariability
    }
  }

  public var isEmpty: Bool { restingHeartRate.isEmpty && heartRateVariability.isEmpty }
}

/// Reduces source-owned quantity samples into deterministic daily values.
///
/// Resting heart rate keeps the latest same-source sample on a date because
/// HealthKit may replace an estimate during the day. HRV SDNN uses the full-
/// precision median of all same-source samples on that date. Samples from
/// incomparable or conflicting sources suppress only that date; other dates
/// continue to project independently.
public struct HealthRecoveryObservationCalculator: Sendable {
  public init() {}

  public func calculate(
    restingHeartRate: [HealthRestingHeartRateSample],
    heartRateVariability: [HealthHRVSDNNSample],
    statuses: [HealthStreamStatus] = [],
    calendar: Calendar = .current,
    now: Date = Date()
  ) -> HealthRecoveryObservationProjection {
    let restingStatus = statuses.first { $0.stream == .restingHeartRate }
    let variabilityStatus = statuses.first { $0.stream == .heartRateVariability }
    let restingResult = restingObservations(
      from: restingHeartRate, status: restingStatus, calendar: calendar, now: now)
    let variabilityResult = variabilityObservations(
      from: heartRateVariability, status: variabilityStatus, calendar: calendar, now: now)
    let allIncluded = restingResult.observations + variabilityResult.observations
    let dates = Array(Set(allIncluded.map { $0.date.iso8601String })).sorted()
    let explanation = InsightExplanation(
      question: "Which resting-heart-rate and HRV SDNN values were recorded on each date?",
      includedRecordIDs: allIncluded.flatMap(\.sampleIDs),
      excludedRecords: [],
      formula:
        "Resting heart rate uses the latest same-source sample on each date; HRV SDNN uses the full-precision median of same-source samples on each date.",
      dateRange: dates.isEmpty ? "No recorded dates" : dates.joined(separator: ", "),
      roundingRule:
        "Values retain full precision; display rounding does not change the stored observation.",
      sourceState: allIncluded.isEmpty
        ? "No comparable quantity source available" : "Source context is retained per observation.",
      includedDates: dates,
      sourceCoverage:
        "Only recorded positive Health samples are included; missing dates remain missing.",
      calculationRule:
        "Samples are grouped by their HealthKit sample date. Conflicting or incomparable source identities suppress only the affected date.",
      missingData: restingResult.missingData + variabilityResult.missingData,
      exclusions: [],
      lastReconciliation: nil,
      configuration: "Resting heart rate: latest same-source sample; HRV SDNN: daily median.")
    return HealthRecoveryObservationProjection(
      restingHeartRate: restingResult.observations,
      heartRateVariability: variabilityResult.observations,
      statuses: statuses.filter { RecoveryEvidenceStream($0.stream) != nil },
      explanation: explanation)
  }

  private struct Result: Sendable {
    let observations: [HealthRecoveryDailyObservation]
    let missingData: [String]
  }

  private func restingObservations(
    from samples: [HealthRestingHeartRateSample],
    status: HealthStreamStatus?,
    calendar: Calendar,
    now: Date
  ) -> Result {
    let unique = deduplicated(samples)
    let correctedIDs = repeatedIDs(samples.map(\.id))
    let grouped = Dictionary(grouping: unique) { trainingDate(for: $0.date, calendar: calendar) }
    var observations: [HealthRecoveryDailyObservation] = []
    var missing: [String] = []
    for (date, values) in grouped {
      let ordered = values.sorted {
        if $0.date != $1.date { return $0.date < $1.date }
        return $0.id < $1.id
      }
      guard let source = comparableSource(for: ordered.map(\.provenance)) else {
        missing.append("Resting heart rate on \(date.iso8601String) has incomparable sources")
        continue
      }
      guard let latest = ordered.last else { continue }
      observations.append(
        makeObservation(
          metric: .restingHeartRate,
          date: date,
          value: latest.beatsPerMinute,
          sampleIDs: ordered.map(\.id),
          latestDate: latest.date,
          latestID: latest.id,
          latestProvenance: latest.provenance,
          algorithmVersions: ordered.compactMap(\.provenance.algorithmVersion),
          source: source,
          isCorrected: correctedIDs.contains(latest.id),
          status: status,
          calendar: calendar,
          now: now))
    }
    return Result(observations: observations, missingData: missing)
  }

  private func variabilityObservations(
    from samples: [HealthHRVSDNNSample],
    status: HealthStreamStatus?,
    calendar: Calendar,
    now: Date
  ) -> Result {
    let unique = deduplicated(samples)
    let correctedIDs = repeatedIDs(samples.map(\.id))
    let grouped = Dictionary(grouping: unique) { trainingDate(for: $0.date, calendar: calendar) }
    var observations: [HealthRecoveryDailyObservation] = []
    var missing: [String] = []
    for (date, values) in grouped {
      let ordered = values.sorted {
        if $0.date != $1.date { return $0.date < $1.date }
        return $0.id < $1.id
      }
      guard let source = comparableSource(for: ordered.map(\.provenance)) else {
        missing.append("HRV SDNN on \(date.iso8601String) has incomparable sources")
        continue
      }
      let numbers = ordered.map(\.milliseconds).sorted()
      let midpoint = numbers.count / 2
      let median =
        numbers.count.isMultiple(of: 2)
        ? (numbers[midpoint - 1] + numbers[midpoint]) / 2
        : numbers[midpoint]
      guard let latest = ordered.last else { continue }
      observations.append(
        makeObservation(
          metric: .heartRateVariabilitySDNN,
          date: date,
          value: median,
          sampleIDs: ordered.map(\.id),
          latestDate: latest.date,
          latestID: latest.id,
          latestProvenance: latest.provenance,
          algorithmVersions: ordered.compactMap(\.provenance.algorithmVersion),
          source: source,
          isCorrected: correctedIDs.contains(latest.id),
          status: status,
          calendar: calendar,
          now: now))
    }
    return Result(observations: observations, missingData: missing)
  }

  private func makeObservation(
    metric: HealthRecoveryObservationMetric,
    date: TrainingDate,
    value: Double,
    sampleIDs: [String],
    latestDate: Date,
    latestID: String,
    latestProvenance: HealthRecoverySampleProvenance,
    algorithmVersions: [String],
    source: HealthRecoveryObservationSource,
    isCorrected: Bool = false,
    status: HealthStreamStatus?,
    calendar: Calendar,
    now: Date
  ) -> HealthRecoveryDailyObservation {
    let uniqueAlgorithms = Array(Set(algorithmVersions)).sorted()
    let lastSuccessful = status?.lastSuccessfulCheck
    let current = status?.isCurrent(on: now, calendar: calendar) == true
    let missing = statusMissingData(status)
    let sourceContext = "\(source.displayName) [\(source.id)]"
    let algorithmContext =
      uniqueAlgorithms.isEmpty
      ? "Algorithm revision: not provided by Health"
      : "Algorithm revisions: \(uniqueAlgorithms.joined(separator: ", "))"
    let explanation = InsightExplanation(
      question: "What recorded \(metric.displayName) value belongs to \(date.iso8601String)?",
      includedRecordIDs: sampleIDs,
      excludedRecords: [],
      formula: metric == .restingHeartRate
        ? "Latest same-source positive sample on the HealthKit sample date."
        : "Full-precision median of same-source positive samples on the HealthKit sample date.",
      dateRange: date.iso8601String,
      roundingRule: "The stored value is full precision; presentation may round \(metric.unit).",
      sourceState: "Source: \(sourceContext). \(algorithmContext)",
      includedDates: [date.iso8601String],
      sourceCoverage:
        "Health stream coverage: \(status?.coverage.displayName ?? "not established"); \(sampleIDs.count) included sample(s); latest included sample: \(latestDate.ISO8601Format()).",
      calculationRule: metric == .restingHeartRate
        ? "A replacement for the same HealthKit sample identity replaces the prior value; no other date is changed."
        : "Odd counts use the middle sorted value; even counts use the arithmetic mean of the two middle sorted values.",
      comparisonBaseline:
        "No baseline is combined into this daily observation; personal 28-day baselines use the preceding local calendar days independently.",
      missingData: missing,
      exclusions: [],
      lastReconciliation: lastSuccessful?.ISO8601Format(),
      configuration: "Current for comparison: \(current ? "yes" : "no").")
    return HealthRecoveryDailyObservation(
      id: "\(metric.rawValue):\(date.iso8601String)",
      metric: metric,
      date: date,
      value: value,
      source: source,
      sourceProvenance: latestProvenance,
      sampleIDs: sampleIDs,
      latestIncludedSample: .init(id: latestID, date: latestDate, provenance: latestProvenance),
      algorithmVersions: uniqueAlgorithms,
      coverage: status?.coverage ?? .unknown,
      reconciliation: status?.reconciliation ?? .idle,
      lastSuccessfulReconciliation: lastSuccessful,
      failure: status?.failure,
      isCurrent: current,
      isCorrected: isCorrected,
      explanation: explanation)
  }

  private func statusMissingData(_ status: HealthStreamStatus?) -> [String] {
    guard let status else { return ["No reconciliation status is available for this stream"] }
    var result: [String] = []
    if let failure = status.failure {
      result.append("\(status.stream.displayName) stream failure: \(failure.code)")
    }
    if status.isUpdating {
      result.append("\(status.stream.displayName) stream reconciliation is still updating")
    }
    if status.coverage == .limitedHistory {
      result.append("Health reports limited history for this stream")
    }
    return result
  }

  private func comparableSource(
    for provenances: [HealthRecoverySampleProvenance]
  ) -> HealthRecoveryObservationSource? {
    let sources = provenances.map(HealthRecoveryObservationSource.init)
    guard let first = sources.first, first.isComparable,
      sources.allSatisfy({ $0.isComparable && $0.id == first.id })
    else { return nil }
    return first
  }

  private func deduplicated(
    _ samples: [HealthRestingHeartRateSample]
  ) -> [HealthRestingHeartRateSample] {
    var byID: [String: HealthRestingHeartRateSample] = [:]
    for sample in samples {
      guard let existing = byID[sample.id] else {
        byID[sample.id] = sample
        continue
      }
      // A later sample date wins regardless of input order. For a same-date
      // UUID revision, reconciliation order is the only available revision
      // marker, so the newest incoming representation wins (including lower
      // corrected values and provenance-only changes).
      if sample.date >= existing.date {
        byID[sample.id] = sample
      }
    }
    return Array(byID.values)
  }

  private func repeatedIDs(_ ids: [String]) -> Set<String> {
    var counts: [String: Int] = [:]
    for id in ids { counts[id, default: 0] += 1 }
    return Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
  }

  private func deduplicated(
    _ samples: [HealthHRVSDNNSample]
  ) -> [HealthHRVSDNNSample] {
    var byID: [String: HealthHRVSDNNSample] = [:]
    for sample in samples {
      guard let existing = byID[sample.id] else {
        byID[sample.id] = sample
        continue
      }
      if sample.date >= existing.date {
        byID[sample.id] = sample
      }
    }
    return Array(byID.values)
  }

  private func trainingDate(for date: Date, calendar: Calendar) -> TrainingDate {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return TrainingDate(
      year: components.year ?? 1,
      month: components.month ?? 1,
      day: components.day ?? 1)
  }
}

extension HealthRecoveryEvidenceSnapshot {
  /// Projects the mirrored quantity streams without mutating the snapshot or
  /// treating a successful stream check as proof that another stream is fresh.
  public func dailyObservations(
    calendar: Calendar = .current,
    now: Date = Date()
  ) -> HealthRecoveryObservationProjection {
    HealthRecoveryObservationCalculator().calculate(
      restingHeartRate: restingHeartRate,
      heartRateVariability: heartRateVariability,
      statuses: statuses,
      calendar: calendar,
      now: now)
  }

  public func recoveryObservations(
    calendar: Calendar = .current,
    now: Date = Date()
  ) -> HealthRecoveryObservationProjection {
    dailyObservations(calendar: calendar, now: now)
  }
}
