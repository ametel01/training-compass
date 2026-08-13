import TrainingDomain

public enum TrainingInsightsModule {}

/// The Epley estimate is intentionally calculated from the actual recorded
/// Set Result. Prescribed weight and Loading Increment are never used here.
public enum E1RMFormula {
  public static let name = "Epley"
  public static let rule = "weight × (1 + repetitions ÷ 30)"

  public static func estimate(weightKg: Double, repetitions: Int) -> Double? {
    guard weightKg.isFinite, weightKg > 0, repetitions > 0 else { return nil }
    guard repetitions != 1 else { return weightKg }
    return weightKg * (1 + Double(repetitions) / 30)
  }
}

public enum E1RMCorrectionState: String, Codable, Equatable, Sendable {
  case original
  case corrected

  public var displayName: String {
    switch self {
    case .original: "Original"
    case .corrected: "Corrected"
    }
  }
}

public enum E1RMExclusionReason: String, Codable, Equatable, Sendable {
  case assistanceSet
  case additionalSet
  case deloadWeek
  case differentLift
  case failedResult
  case missingResult
  case omitted
  case notPlusSet
  case unknownPrescription

  public var displayName: String {
    switch self {
    case .assistanceSet: "Assistance Set"
    case .additionalSet: "Additional Set"
    case .deloadWeek: "Deload Week"
    case .differentLift: "Different Lift"
    case .failedResult: "Failed Result"
    case .missingResult: "No Plus Set Result"
    case .omitted: "Omitted Set"
    case .notPlusSet: "Not a Plus Set"
    case .unknownPrescription: "Unknown Prescription"
    }
  }
}

/// The complete source context for one Session. This type deliberately stays
/// in TrainingInsights so the calculator can be used without persistence or
/// SwiftUI; TrainingApplication supplies these records from its repositories.
public struct E1RMSessionRecord: Equatable, Sendable {
  public let cycleID: String
  public let cycleState: TrainingCycleLifecycleState
  public let weekID: String
  public let weekKind: TrainingWeekKind
  public let session: TrainingCycleSession
  public let primaryLiftName: String?
  public let results: [RecordedSetResult]
  public let omissions: [OmittedSet]
  public let additionalSets: [AdditionalSet]
  public let correctedResultIDs: [String]

  public init(
    cycleID: String,
    cycleState: TrainingCycleLifecycleState,
    weekID: String,
    weekKind: TrainingWeekKind,
    session: TrainingCycleSession,
    primaryLiftName: String? = nil,
    results: [RecordedSetResult] = [],
    omissions: [OmittedSet] = [],
    additionalSets: [AdditionalSet] = [],
    correctedResultIDs: [String] = []
  ) {
    self.cycleID = cycleID
    self.cycleState = cycleState
    self.weekID = weekID
    self.weekKind = weekKind
    self.session = session
    self.primaryLiftName = primaryLiftName
    self.results = results
    self.omissions = omissions
    self.additionalSets = additionalSets
    self.correctedResultIDs = correctedResultIDs
  }
}

public struct E1RMLiftOption: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct E1RMTrainingMaxContext: Codable, Equatable, Sendable {
  public let liftID: String
  public let liftName: String
  public let currentTrainingMaxKg: Double
  public let loadingIncrementKg: Double
  public let activeCycleTrainingMaxKg: Double?

  public init(
    liftID: String,
    liftName: String,
    currentTrainingMaxKg: Double,
    loadingIncrementKg: Double,
    activeCycleTrainingMaxKg: Double? = nil
  ) {
    self.liftID = liftID
    self.liftName = liftName
    self.currentTrainingMaxKg = currentTrainingMaxKg
    self.loadingIncrementKg = loadingIncrementKg
    self.activeCycleTrainingMaxKg = activeCycleTrainingMaxKg
  }
}

public struct E1RMObservation: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let resultID: String
  public let cycleID: String
  public let cycleState: TrainingCycleLifecycleState
  public let weekID: String
  public let weekKind: TrainingWeekKind
  public let sessionID: String
  public let prescriptionID: String
  public let liftID: String
  public let liftName: String
  public let date: TrainingDate
  public let weightKg: Double
  public let repetitions: Int
  public let estimatedKg: Double
  public let correctionState: E1RMCorrectionState

  public init(
    resultID: String,
    cycleID: String,
    cycleState: TrainingCycleLifecycleState,
    weekID: String,
    weekKind: TrainingWeekKind,
    sessionID: String,
    prescriptionID: String,
    liftID: String,
    liftName: String,
    date: TrainingDate,
    weightKg: Double,
    repetitions: Int,
    estimatedKg: Double,
    correctionState: E1RMCorrectionState
  ) {
    self.id = resultID
    self.resultID = resultID
    self.cycleID = cycleID
    self.cycleState = cycleState
    self.weekID = weekID
    self.weekKind = weekKind
    self.sessionID = sessionID
    self.prescriptionID = prescriptionID
    self.liftID = liftID
    self.liftName = liftName
    self.date = date
    self.weightKg = weightKg
    self.repetitions = repetitions
    self.estimatedKg = estimatedKg
    self.correctionState = correctionState
  }

  public var displayValue: String {
    let tenths = Int((estimatedKg * 10).rounded())
    return "\(tenths / 10).\(abs(tenths) % 10) kg"
  }

  public var sourceLink: E1RMSourceLink {
    E1RMSourceLink(
      resultID: resultID,
      cycleID: cycleID,
      weekID: weekID,
      sessionID: sessionID,
      prescriptionID: prescriptionID,
      correctionState: correctionState
    )
  }
}

public struct E1RMSourceLink: Codable, Equatable, Sendable {
  public let resultID: String
  public let cycleID: String
  public let weekID: String
  public let sessionID: String
  public let prescriptionID: String
  public let correctionState: E1RMCorrectionState

  public init(
    resultID: String,
    cycleID: String,
    weekID: String,
    sessionID: String,
    prescriptionID: String,
    correctionState: E1RMCorrectionState
  ) {
    self.resultID = resultID
    self.cycleID = cycleID
    self.weekID = weekID
    self.sessionID = sessionID
    self.prescriptionID = prescriptionID
    self.correctionState = correctionState
  }
}

public struct E1RMExcludedRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let cycleID: String
  public let weekID: String
  public let sessionID: String
  public let prescriptionID: String?
  public let date: TrainingDate
  public let liftID: String?
  public let label: String
  public let reason: E1RMExclusionReason
  public let correctionState: E1RMCorrectionState?

  public init(
    id: String,
    cycleID: String,
    weekID: String,
    sessionID: String,
    prescriptionID: String? = nil,
    date: TrainingDate,
    liftID: String? = nil,
    label: String,
    reason: E1RMExclusionReason,
    correctionState: E1RMCorrectionState? = nil
  ) {
    self.id = id
    self.cycleID = cycleID
    self.weekID = weekID
    self.sessionID = sessionID
    self.prescriptionID = prescriptionID
    self.date = date
    self.liftID = liftID
    self.label = label
    self.reason = reason
    self.correctionState = correctionState
  }
}

public enum E1RMTrendDirection: String, Codable, Equatable, Sendable {
  case upward
  case downward
  case unchanged
  case insufficientData

  public var displayName: String {
    switch self {
    case .upward: "Higher"
    case .downward: "Lower"
    case .unchanged: "No clear change"
    case .insufficientData: "Insufficient data"
    }
  }
}

public struct InsightExplanation: Codable, Equatable, Sendable {
  public let question: String
  public let includedRecordIDs: [String]
  public let excludedRecords: [E1RMExcludedRecord]
  public let formula: String
  public let dateRange: String
  public let roundingRule: String
  public let sourceState: String
  public let text: String

  public init(
    question: String,
    includedRecordIDs: [String],
    excludedRecords: [E1RMExcludedRecord],
    formula: String,
    dateRange: String,
    roundingRule: String,
    sourceState: String
  ) {
    self.question = question
    self.includedRecordIDs = includedRecordIDs
    self.excludedRecords = excludedRecords
    self.formula = formula
    self.dateRange = dateRange
    self.roundingRule = roundingRule
    self.sourceState = sourceState
    let included = includedRecordIDs.isEmpty ? "none" : includedRecordIDs.joined(separator: ", ")
    let excluded =
      excludedRecords.isEmpty
      ? "none"
      : excludedRecords.map { "\($0.label) [\($0.reason.displayName)]" }.joined(separator: ", ")
    text =
      question + " Included records: " + included + ". Excluded records: " + excluded
      + ". Formula: " + formula + ". Dates: " + dateRange + ". " + roundingRule
      + " Source state: " + sourceState + "."
  }
}

public struct E1RMProgress: Codable, Equatable, Sendable {
  public let selectedLiftID: String?
  public let selectedLiftName: String?
  public let availableLifts: [E1RMLiftOption]
  public let observations: [E1RMObservation]
  public let excludedRecords: [E1RMExcludedRecord]
  public let latest: E1RMObservation?
  public let previous: E1RMObservation?
  public let cycleBest: E1RMObservation?
  public let allTimeBest: E1RMObservation?
  public let trailing90DayDirection: E1RMTrendDirection
  public let currentTrainingMaxContext: E1RMTrainingMaxContext?
  public let explanation: InsightExplanation

  public init(
    selectedLiftID: String?,
    selectedLiftName: String?,
    availableLifts: [E1RMLiftOption],
    observations: [E1RMObservation],
    excludedRecords: [E1RMExcludedRecord],
    latest: E1RMObservation?,
    previous: E1RMObservation?,
    cycleBest: E1RMObservation?,
    allTimeBest: E1RMObservation?,
    trailing90DayDirection: E1RMTrendDirection,
    currentTrainingMaxContext: E1RMTrainingMaxContext?,
    explanation: InsightExplanation
  ) {
    self.selectedLiftID = selectedLiftID
    self.selectedLiftName = selectedLiftName
    self.availableLifts = availableLifts
    self.observations = observations
    self.excludedRecords = excludedRecords
    self.latest = latest
    self.previous = previous
    self.cycleBest = cycleBest
    self.allTimeBest = allTimeBest
    self.trailing90DayDirection = trailing90DayDirection
    self.currentTrainingMaxContext = currentTrainingMaxContext
    self.explanation = explanation
  }

  public var hasLongerHistory: Bool { observations.count > 2 }
}

public struct E1RMProgressCalculator: Sendable {
  public init() {}

  public func calculate(
    from sources: [E1RMSessionRecord],
    selectedLiftID: String? = nil,
    currentTrainingMaxContexts: [String: E1RMTrainingMaxContext] = [:],
    sourceState: String = "Current local authoritative Set Results",
    asOfDate: TrainingDate? = nil
  ) -> E1RMProgress {
    let availableLifts = liftOptions(from: sources)
    let selectedID =
      selectedLiftID
      ?? availableLifts.first(where: { hasEligibleObservation(for: $0.id, in: sources) })?.id
      ?? availableLifts.first?.id
    let selectedName = availableLifts.first(where: { $0.id == selectedID })?.name
    var observations: [E1RMObservation] = []
    var excluded: [E1RMExcludedRecord] = []

    for source in sources {
      let prescriptions = source.session.prescriptions
      let plus =
        prescriptions
        .filter { $0.role == .primary && $0.isPlusSetEligible }
        .max { $0.setNumber < $1.setNumber }
      let resultsByPrescription = Dictionary(
        uniqueKeysWithValues: source.results.map { ($0.prescriptionID, $0) })
      let omissionsByPrescription = Dictionary(
        uniqueKeysWithValues: source.omissions.map { ($0.prescriptionID, $0) })

      for result in source.results {
        let prescription = prescriptions.first { $0.id == result.prescriptionID }
        let reason: E1RMExclusionReason?
        if source.weekKind.isDeload {
          reason = .deloadWeek
        } else if prescription == nil {
          reason = .unknownPrescription
        } else if prescription?.role != .primary {
          reason = .assistanceSet
        } else if prescription?.isPlusSetEligible != true || prescription?.id != plus?.id {
          reason = .notPlusSet
        } else if source.session.primaryLiftID != selectedID {
          reason = .differentLift
        } else if result.repetitions == 0 {
          reason = .failedResult
        } else {
          reason = nil
        }
        if let reason {
          excluded.append(excludedResult(result, source: source, reason: reason))
        } else if let estimate = E1RMFormula.estimate(
          weightKg: result.weightKg, repetitions: result.repetitions),
          let prescription
        {
          observations.append(
            E1RMObservation(
              resultID: result.id,
              cycleID: source.cycleID,
              cycleState: source.cycleState,
              weekID: source.weekID,
              weekKind: source.weekKind,
              sessionID: source.session.id,
              prescriptionID: prescription.id,
              liftID: source.session.primaryLiftID,
              liftName: selectedName ?? source.session.primaryLiftID,
              date: source.session.intendedDate,
              weightKg: result.weightKg,
              repetitions: result.repetitions,
              estimatedKg: estimate,
              correctionState: source.correctedResultIDs.contains(result.id)
                ? .corrected : .original
            )
          )
        }
      }

      for omission in source.omissions {
        let prescription = prescriptions.first { $0.id == omission.prescriptionID }
        excluded.append(
          E1RMExcludedRecord(
            id: omission.id,
            cycleID: source.cycleID,
            weekID: source.weekID,
            sessionID: source.session.id,
            prescriptionID: omission.prescriptionID,
            date: source.session.intendedDate,
            liftID: source.session.primaryLiftID,
            label: omission.id,
            reason: source.weekKind.isDeload
              ? .deloadWeek
              : prescription?.role == .assistance ? .assistanceSet : .omitted,
            correctionState: nil
          )
        )
      }

      for additional in source.additionalSets {
        excluded.append(
          E1RMExcludedRecord(
            id: additional.id,
            cycleID: source.cycleID,
            weekID: source.weekID,
            sessionID: source.session.id,
            date: source.session.intendedDate,
            liftID: additional.liftID,
            label: additional.id,
            reason: .additionalSet
          )
        )
      }

      if let plus, source.session.primaryLiftID == selectedID, !source.weekKind.isDeload,
        resultsByPrescription[plus.id] == nil, omissionsByPrescription[plus.id] == nil
      {
        excluded.append(
          E1RMExcludedRecord(
            id: "\(source.session.id):\(plus.id):missing",
            cycleID: source.cycleID,
            weekID: source.weekID,
            sessionID: source.session.id,
            prescriptionID: plus.id,
            date: source.session.intendedDate,
            liftID: source.session.primaryLiftID,
            label: plus.id,
            reason: .missingResult
          )
        )
      }
    }

    observations.sort { lhs, rhs in
      if lhs.date != rhs.date { return lhs.date < rhs.date }
      return lhs.id < rhs.id
    }
    let latest = observations.last
    let previous = observations.dropLast().last
    let cycleBest =
      latest.map { latest in
        observations.filter { $0.cycleID == latest.cycleID }.max(by: bestFirst)
      } ?? nil
    let allTimeBest = observations.max(by: bestFirst)
    let direction = trailingDirection(observations, asOfDate: asOfDate)
    let dateRange: String
    if let first = observations.first?.date, let last = observations.last?.date {
      dateRange = "\(first.iso8601String) through \(last.iso8601String)"
    } else {
      dateRange = "No included dates"
    }
    let explanation = InsightExplanation(
      question: selectedName.map { "How is \($0) e1RM changing?" } ?? "How is e1RM changing?",
      includedRecordIDs: observations.map(\.resultID),
      excludedRecords: excluded,
      formula:
        "\(E1RMFormula.name): \(E1RMFormula.rule); one repetition equals lifted weight; zero repetitions produce no estimate.",
      dateRange: dateRange,
      roundingRule: "Displayed to one decimal place; calculations retain full precision.",
      sourceState: sourceState
    )
    return E1RMProgress(
      selectedLiftID: selectedID,
      selectedLiftName: selectedName,
      availableLifts: availableLifts,
      observations: observations,
      excludedRecords: excluded,
      latest: latest,
      previous: previous,
      cycleBest: cycleBest,
      allTimeBest: allTimeBest,
      trailing90DayDirection: direction,
      currentTrainingMaxContext: selectedID.flatMap { currentTrainingMaxContexts[$0] },
      explanation: explanation
    )
  }

  private func liftOptions(from sources: [E1RMSessionRecord]) -> [E1RMLiftOption] {
    var names: [String: String] = [:]
    for source in sources where !source.session.primaryLiftID.isEmpty {
      names[source.session.primaryLiftID] = source.primaryLiftName ?? source.session.primaryLiftID
    }
    return names.keys.sorted().map { E1RMLiftOption(id: $0, name: names[$0] ?? $0) }
  }

  private func hasEligibleObservation(for liftID: String, in sources: [E1RMSessionRecord]) -> Bool {
    sources.contains { source in
      guard !source.weekKind.isDeload, source.session.primaryLiftID == liftID else { return false }
      let plus = source.session.prescriptions
        .filter { $0.role == .primary && $0.isPlusSetEligible }
        .max { $0.setNumber < $1.setNumber }
      guard let plus else { return false }
      return source.results.contains {
        $0.prescriptionID == plus.id
          && E1RMFormula.estimate(weightKg: $0.weightKg, repetitions: $0.repetitions) != nil
      }
    }
  }

  private func excludedResult(
    _ result: RecordedSetResult,
    source: E1RMSessionRecord,
    reason: E1RMExclusionReason
  ) -> E1RMExcludedRecord {
    E1RMExcludedRecord(
      id: result.id,
      cycleID: source.cycleID,
      weekID: source.weekID,
      sessionID: source.session.id,
      prescriptionID: result.prescriptionID,
      date: source.session.intendedDate,
      liftID: source.session.primaryLiftID,
      label: result.id,
      reason: reason,
      correctionState: source.correctedResultIDs.contains(result.id) ? .corrected : .original
    )
  }

  private func bestFirst(_ lhs: E1RMObservation, _ rhs: E1RMObservation) -> Bool {
    if lhs.estimatedKg != rhs.estimatedKg { return lhs.estimatedKg < rhs.estimatedKg }
    return lhs.date < rhs.date
  }

  private func trailingDirection(
    _ observations: [E1RMObservation],
    asOfDate: TrainingDate?
  ) -> E1RMTrendDirection {
    guard let end = asOfDate ?? observations.last?.date else { return .insufficientData }
    let start = end.adding(days: -89)
    let window = observations.filter { $0.date >= start && $0.date <= end }
    guard let first = window.first, let last = window.last, first.id != last.id else {
      return .insufficientData
    }
    let delta = last.estimatedKg - first.estimatedKg
    if abs(delta) < 0.000000001 { return .unchanged }
    return delta > 0 ? .upward : .downward
  }
}

public typealias EstimatedOneRepMax = E1RMFormula
public typealias E1RMProgressInsight = E1RMProgress
