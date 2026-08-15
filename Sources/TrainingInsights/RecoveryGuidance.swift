import TrainingDomain

/// Sufficiently independent source families used only to gate the optional
/// cross-signal self-check. Sleep duration and both sleep consistency measures
/// intentionally remain one family.
public enum RecoveryEvidenceFamily: String, Codable, CaseIterable, Equatable, Sendable {
  case primarySleep
  case restingHeartRate
  case heartRateVariability

  public var displayName: String {
    switch self {
    case .primarySleep: "Primary Sleep"
    case .restingHeartRate: "Resting heart rate"
    case .heartRateVariability: "HRV SDNN"
    }
  }

  public var metrics: [PersonalRecoveryBaselineMetric] {
    switch self {
    case .primarySleep:
      [.primarySleepDuration, .sleepDurationConsistency, .sleepTimingConsistency]
    case .restingHeartRate: [.restingHeartRate]
    case .heartRateVariability: [.heartRateVariabilitySDNN]
    }
  }

  public init(metric: PersonalRecoveryBaselineMetric) {
    switch metric {
    case .primarySleepDuration, .sleepDurationConsistency, .sleepTimingConsistency:
      self = .primarySleep
    case .restingHeartRate: self = .restingHeartRate
    case .heartRateVariabilitySDNN: self = .heartRateVariability
    }
  }
}

public enum RecoveryGuidanceSuppressionReason: String, Codable, Equatable, Sendable {
  case disabled
  case notEnoughEstablishedFamilies
  case familyObservationUnavailable

  public var displayName: String {
    switch self {
    case .disabled: "Recovery Guidance is disabled"
    case .notEnoughEstablishedFamilies:
      "Fewer than two Recovery Evidence Families have established baselines"
    case .familyObservationUnavailable:
      "An established Recovery Evidence Family has no current comparable observation"
    }
  }

  // Compatibility vocabulary for callers that describe the same gate in
  // terms of current evidence rather than family state.
  public static var insufficientFamilies: Self { .notEnoughEstablishedFamilies }
  public static var unavailableCurrentEvidence: Self { .familyObservationUnavailable }
}

/// One independently reported current measurement included in the optional
/// self-check prompt. It carries the same neutral baseline comparison and
/// source context shown by the underlying baseline row.
public struct RecoveryGuidanceMeasurement: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let metric: PersonalRecoveryBaselineMetric
  public let family: RecoveryEvidenceFamily
  public let date: TrainingDate
  public let value: Double
  public let unit: String
  public let comparison: PersonalRecoveryBaselineComparison
  public let neutralDirection: String?
  public let differenceFromMedian: Double?
  public let sourceName: String
  public let sourceCoverage: String
  public let includedRecordIDs: [String]

  public init(
    metric: PersonalRecoveryBaselineMetric,
    date: TrainingDate,
    value: Double,
    comparison: PersonalRecoveryBaselineComparison,
    neutralDirection: String?,
    differenceFromMedian: Double?,
    sourceName: String,
    sourceCoverage: String,
    includedRecordIDs: [String]
  ) {
    self.id = "\(metric.rawValue):\(date.iso8601String)"
    self.metric = metric
    self.family = RecoveryEvidenceFamily(metric: metric)
    self.date = date
    self.value = value
    self.unit = metric.unit
    self.comparison = comparison
    self.neutralDirection = neutralDirection
    self.differenceFromMedian = differenceFromMedian
    self.sourceName = sourceName
    self.sourceCoverage = sourceCoverage
    self.includedRecordIDs = includedRecordIDs
  }

  public var displayName: String { metric.displayName }

  public var neutralDescription: String {
    let direction = neutralDirection ?? comparison.displayName
    return "\(metric.displayName): \(String(value)) \(unit), \(direction) the recent record"
  }
}

/// The explained output of the Recovery Guidance gate. A projection can keep
/// its measurements visible while withholding `prompt` for any gate reason.
public struct RecoveryGuidance: Codable, Equatable, Sendable {
  public let enabled: Bool
  public let isEligible: Bool
  public let isAvailable: Bool
  public let establishedFamilies: [RecoveryEvidenceFamily]
  public let measurements: [RecoveryGuidanceMeasurement]
  public let summary: String?
  public let prompt: String?
  public let suppressionReason: RecoveryGuidanceSuppressionReason?
  public let explanation: InsightExplanation

  public init(
    enabled: Bool,
    isEligible: Bool,
    establishedFamilies: [RecoveryEvidenceFamily],
    measurements: [RecoveryGuidanceMeasurement],
    summary: String?,
    prompt: String?,
    suppressionReason: RecoveryGuidanceSuppressionReason?,
    explanation: InsightExplanation
  ) {
    self.enabled = enabled
    self.isEligible = isEligible
    self.isAvailable = enabled && isEligible
    self.establishedFamilies = establishedFamilies
    self.measurements = measurements
    self.summary = summary
    self.prompt = prompt
    self.suppressionReason = suppressionReason
    self.explanation = explanation
  }

  public var canShowPrompt: Bool { isAvailable && prompt != nil }
  public var message: String? { prompt }
  public var familyCount: Int { establishedFamilies.count }
}

/// Applies the presentation-only Recovery Guidance policy. It never combines,
/// ranks, weights, votes, or interprets measurements and has no training input.
public struct RecoveryGuidanceCalculator: Sendable {
  public init() {}

  public func calculate(
    baselines: PersonalRecoveryBaselineProjection,
    asOfDate: TrainingDate,
    enabled: Bool = true
  ) -> RecoveryGuidance {
    let established = baselines.baselines.filter(\.isEstablished)
    let grouped = Dictionary(grouping: established) { RecoveryEvidenceFamily(metric: $0.metric) }
    let establishedFamilies = RecoveryEvidenceFamily.allCases.filter { grouped[$0] != nil }
    let currentFamilies = establishedFamilies.filter { family in
      guard let familyBaselines = grouped[family], !familyBaselines.isEmpty else { return false }
      return familyBaselines.allSatisfy {
        Self.hasEligibleCurrentObservation($0, asOfDate: asOfDate)
      }
    }
    let isEligible =
      establishedFamilies.count >= 2
      && currentFamilies.count == establishedFamilies.count
    let measurements =
      established
      .filter { Self.hasEligibleCurrentObservation($0, asOfDate: asOfDate) }
      .compactMap(Self.measurement)
      .sorted {
        let lhs = PersonalRecoveryBaselineMetric.allCases.firstIndex(of: $0.metric) ?? .max
        let rhs = PersonalRecoveryBaselineMetric.allCases.firstIndex(of: $1.metric) ?? .max
        return lhs < rhs
      }
    let summary = isEligible ? Self.summary(for: measurements) : nil
    let prompt =
      enabled && isEligible
      ? summary.map {
        "\($0) Consider how you feel before the session; you decide whether to keep or change the Session."
      }
      : nil
    let suppression: RecoveryGuidanceSuppressionReason? = {
      guard enabled else { return .disabled }
      guard establishedFamilies.count >= 2 else { return .notEnoughEstablishedFamilies }
      guard isEligible else { return .familyObservationUnavailable }
      return nil
    }()
    let missing = baselines.baselines.flatMap { baseline in
      baseline.missingData
        + (Self.hasEligibleCurrentObservation(baseline, asOfDate: asOfDate)
          ? []
          : [
            "\(baseline.metric.displayName) has no current source-comparable observation"
          ])
    }
    let familyState = establishedFamilies.map { family in
      let current = currentFamilies.contains(family) ? "current" : "not current"
      return "\(family.displayName): established, \(current)"
    }
    let explanation = InsightExplanation(
      question:
        "Which current recorded measurements are comparable across established source families?",
      includedRecordIDs: baselines.explanation.includedRecordIDs
        + measurements.flatMap(\.includedRecordIDs),
      excludedRecords: [],
      formula:
        "List each current measure independently; count source families only to decide whether the self-check prompt may appear. No values are combined or weighted.",
      dateRange: asOfDate.iso8601String,
      roundingRule:
        "Measurement values and baseline differences retain full precision; presentation may round only for display.",
      sourceState: familyState.isEmpty
        ? "No established source family" : familyState.joined(separator: "; "),
      includedDates: measurements.map { $0.date.iso8601String },
      sourceCoverage: "Each measurement retains its own recorded source and coverage context.",
      calculationRule:
        "Primary Sleep duration and consistency measures are one family; resting heart rate and HRV SDNN are separate families. A family must have a current, successful, comparable observation when its baseline is established.",
      comparisonBaseline:
        "Each measurement's preceding 28 local calendar days and middle 50 percent.",
      missingData: Array(Set(missing)).sorted(),
      exclusions: [],
      lastReconciliation: baselines.baselines.compactMap(\.lastReconciliation).sorted().last,
      configuration:
        "Minimum two established source families; guidance enabled: \(enabled ? "yes" : "no")."
    )
    return RecoveryGuidance(
      enabled: enabled,
      isEligible: isEligible,
      establishedFamilies: establishedFamilies,
      measurements: measurements,
      summary: summary,
      prompt: prompt,
      suppressionReason: suppression,
      explanation: explanation)
  }

  private static func hasEligibleCurrentObservation(
    _ baseline: PersonalRecoveryBaseline,
    asOfDate: TrainingDate
  ) -> Bool {
    guard let current = baseline.currentObservation else { return false }
    guard current.date == asOfDate else { return false }
    guard current.sourceIsComparable, current.isCurrent, !current.isCorrected else { return false }
    let blocked = current.missingData.map { $0.lowercased() }
    return !blocked.contains { value in
      ["failure", "failed", "updating", "stale", "corrected", "incomparable", "unavailable"]
        .contains { value.contains($0) }
    }
  }

  private static func measurement(
    _ baseline: PersonalRecoveryBaseline
  ) -> RecoveryGuidanceMeasurement? {
    guard let current = baseline.currentObservation else { return nil }
    return RecoveryGuidanceMeasurement(
      metric: baseline.metric,
      date: current.date,
      value: current.value,
      comparison: baseline.comparison,
      neutralDirection: baseline.neutralDirection,
      differenceFromMedian: baseline.differenceFromMedian,
      sourceName: current.sourceName,
      sourceCoverage: current.sourceCoverage,
      includedRecordIDs: current.includedRecordIDs)
  }

  private static func summary(for measurements: [RecoveryGuidanceMeasurement]) -> String {
    let differing = measurements.filter { $0.comparison != .within }
    let details = measurements.map(\.neutralDescription).joined(separator: "; ")
    let directions = Set(differing.map(\.comparison))
    if directions.contains(.above) && directions.contains(.below) {
      return "The measurements do not move together: \(details)"
    }
    if differing.count >= 2 {
      return "Several measurements differ from your recent record: \(details)"
    }
    if differing.count == 1 {
      return "One measurement differs from your recent record: \(details)"
    }
    return "The recorded measurements are described against your recent record: \(details)"
  }
}

public typealias RecoveryGuidanceProjection = RecoveryGuidance
public typealias RecoveryGuidanceFamily = RecoveryEvidenceFamily
public typealias HealthRecoveryEvidenceFamily = RecoveryEvidenceFamily
public typealias HealthRecoveryGuidance = RecoveryGuidance
public typealias HealthRecoveryGuidanceCalculator = RecoveryGuidanceCalculator
