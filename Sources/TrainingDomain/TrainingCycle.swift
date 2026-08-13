/// A calendar date without a time zone or time of day.
public struct TrainingDate: Codable, Comparable, Equatable, Hashable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    precondition(Self.isValid(year: year, month: month, day: day), "Invalid training date")
    self.year = year
    self.month = month
    self.day = day
  }

  public static func < (lhs: TrainingDate, rhs: TrainingDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  public var iso8601String: String {
    "\(Self.padded(year, width: 4))-\(Self.padded(month, width: 2))-\(Self.padded(day, width: 2))"
  }

  public func adding(days: Int) -> TrainingDate {
    let shifted = Self.daysFromCivil(year: year, month: month, day: day) + days
    let civil = Self.civilFromDays(shifted)
    return TrainingDate(year: civil.year, month: civil.month, day: civil.day)
  }

  private static func isValid(year: Int, month: Int, day: Int) -> Bool {
    guard (1...12).contains(month), year >= 1 else { return false }
    let daysInMonth = [
      31, Self.isLeap(year: year) ? 29 : 28, 31, 30, 31, 30,
      31, 31, 30, 31, 30, 31,
    ]
    return day >= 1 && day <= daysInMonth[month - 1]
  }

  private static func isLeap(year: Int) -> Bool {
    year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
  }

  private static func padded(_ value: Int, width: Int) -> String {
    let string = String(value)
    return String(repeating: "0", count: max(0, width - string.count)) + string
  }

  // Howard Hinnant's proleptic Gregorian civil-date conversion, expressed in
  // integer arithmetic so the domain does not depend on Foundation calendars.
  private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    var y = year
    y -= month <= 2 ? 1 : 0
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let monthPrime = month + (month > 2 ? -3 : 9)
    let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
    let shifted = days + 719_468
    let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    var year = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPrime = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
    let month = monthPrime + (monthPrime < 10 ? 3 : -9)
    year += month <= 2 ? 1 : 0
    return (year, month, day)
  }
}

public enum TrainingCycleLifecycleState: String, Codable, Equatable, Sendable {
  case draft
  case active
  case completed
  case abandoned

  public var displayName: String {
    rawValue.prefix(1).uppercased() + rawValue.dropFirst()
  }
}

public enum TrainingWeekKind: String, Codable, Equatable, Sendable {
  case week1
  case week2
  case week3
  case deload

  public var displayName: String {
    switch self {
    case .week1: "Training Week 1"
    case .week2: "Training Week 2"
    case .week3: "Training Week 3"
    case .deload: "Deload Week"
    }
  }

  public var isDeload: Bool { self == .deload }
}

/// The two prescription roles that can occur in a 5/3/1 session.
public enum TrainingPrescriptionRole: String, Codable, Equatable, Hashable, Sendable {
  case primary
  case assistance
}

/// The mutable disposition of a session within an otherwise immutable cycle.
public enum TrainingSessionStatus: String, Codable, Equatable, Hashable, Sendable {
  case scheduled
  case inProgress
  case completed
  case skipped

  public var isTerminal: Bool {
    self == .completed || self == .skipped
  }
}

/// A frozen, loadable prescription captured when a cycle is activated.
public struct TrainingSetPrescription: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public let setNumber: Int
  public let role: TrainingPrescriptionRole
  public let percentage: Double
  public let repetitions: Int
  public let weightKg: Double
  public let isPlusSetEligible: Bool

  public init(
    id: String,
    setNumber: Int,
    role: TrainingPrescriptionRole,
    percentage: Double,
    repetitions: Int,
    weightKg: Double,
    isPlusSetEligible: Bool = false
  ) {
    self.id = id
    self.setNumber = setNumber
    self.role = role
    self.percentage = percentage
    self.repetitions = repetitions
    self.weightKg = weightKg
    self.isPlusSetEligible = isPlusSetEligible
  }

  public var weight: Double { weightKg }
  public var isPlusSet: Bool { isPlusSetEligible }
}

/// A confirmed actual result for one immutable Set Prescription.
public struct RecordedSetResult: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let sessionID: String
  public let prescriptionID: String
  public let result: SetResult
  public let recordedAt: Int64

  public init(
    id: String,
    sessionID: String,
    prescriptionID: String,
    result: SetResult,
    recordedAt: Int64
  ) {
    self.id = id
    self.sessionID = sessionID
    self.prescriptionID = prescriptionID
    self.result = result
    self.recordedAt = recordedAt
  }

  public var weightKg: Double { result.weight.kg }
  public var repetitions: Int { result.repetitions }
}

/// A prescribed set the owner explicitly chose not to perform.
public struct OmittedSet: Codable, Equatable, Identifiable, Sendable {
  public let sessionID: String
  public let prescriptionID: String
  public let reason: String?
  public let omittedAt: Int64

  public init(
    sessionID: String,
    prescriptionID: String,
    reason: String? = nil,
    omittedAt: Int64
  ) {
    self.sessionID = sessionID
    self.prescriptionID = prescriptionID
    self.reason = reason?.nilIfEmpty
    self.omittedAt = omittedAt
  }

  public var id: String { "\(sessionID):\(prescriptionID)" }
}

/// An ordered, owner-recorded set that is not part of a Session's prescription.
public struct AdditionalSet: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let sessionID: String
  public let position: Int
  public let liftID: String
  public let weightKg: Double
  public let repetitions: Int
  public let note: String?
  public let recordedAt: Int64

  public init(
    id: String,
    sessionID: String,
    position: Int,
    liftID: String,
    weightKg: Double,
    repetitions: Int,
    note: String? = nil,
    recordedAt: Int64
  ) throws {
    guard !liftID.isEmpty else {
      throw AdditionalSetValidationError.emptyLift
    }
    guard position >= 0 else { throw AdditionalSetValidationError.invalidPosition }
    _ = try SetResultWeight(kg: weightKg)
    guard repetitions >= 0 else { throw AdditionalSetValidationError.invalidRepetitions }
    self.id = id
    self.sessionID = sessionID
    self.position = position
    self.liftID = liftID
    self.weightKg = weightKg
    self.repetitions = repetitions
    self.note = note?.nilIfEmpty
    self.recordedAt = recordedAt
  }
}

public enum AdditionalSetValidationError: Error, Codable, Equatable, Sendable {
  case emptyLift
  case invalidPosition
  case invalidRepetitions
}

extension String {
  fileprivate
    var nilIfEmpty: String?
  { isEmpty ? nil : self }
}

/// Short aliases keep the domain vocabulary convenient at call sites.
public enum FiveThreeOnePrescription {
  public struct Specification: Equatable, Sendable {
    public let percentage: Double
    public let repetitions: Int
    public let isPlusSetEligible: Bool

    public init(percentage: Double, repetitions: Int, isPlusSetEligible: Bool) {
      self.percentage = percentage
      self.repetitions = repetitions
      self.isPlusSetEligible = isPlusSetEligible
    }
  }

  public static func specifications(
    for kind: TrainingWeekKind,
    role: TrainingPrescriptionRole
  ) -> [Specification] {
    switch (kind, role) {
    case (.week1, .primary):
      [
        .init(percentage: 0.65, repetitions: 5, isPlusSetEligible: false),
        .init(percentage: 0.75, repetitions: 5, isPlusSetEligible: false),
        .init(percentage: 0.85, repetitions: 5, isPlusSetEligible: true),
      ]
    case (.week2, .primary):
      [
        .init(percentage: 0.70, repetitions: 3, isPlusSetEligible: false),
        .init(percentage: 0.80, repetitions: 3, isPlusSetEligible: false),
        .init(percentage: 0.90, repetitions: 3, isPlusSetEligible: true),
      ]
    case (.week3, .primary):
      [
        .init(percentage: 0.75, repetitions: 5, isPlusSetEligible: false),
        .init(percentage: 0.85, repetitions: 3, isPlusSetEligible: false),
        .init(percentage: 0.95, repetitions: 1, isPlusSetEligible: true),
      ]
    case (.deload, .primary):
      [
        .init(percentage: 0.40, repetitions: 5, isPlusSetEligible: false),
        .init(percentage: 0.50, repetitions: 5, isPlusSetEligible: false),
        .init(percentage: 0.60, repetitions: 5, isPlusSetEligible: false),
      ]
    case (.week1, .assistance), (.week2, .assistance), (.week3, .assistance):
      Array(repeating: .init(percentage: 0.65, repetitions: 10, isPlusSetEligible: false), count: 5)
    case (.deload, .assistance):
      Array(repeating: .init(percentage: 0.50, repetitions: 10, isPlusSetEligible: false), count: 5)
    }
  }
}

public struct TrainingCycleSession: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public let intendedDate: TrainingDate
  public let sourceTemplateSessionID: String
  public let primaryLiftID: String
  public let assistanceLiftID: String
  public let prescriptions: [TrainingSetPrescription]
  public let status: TrainingSessionStatus

  public init(
    id: String,
    intendedDate: TrainingDate,
    sourceTemplateSessionID: String,
    primaryLiftID: String,
    assistanceLiftID: String,
    prescriptions: [TrainingSetPrescription] = [],
    status: TrainingSessionStatus = .scheduled
  ) {
    self.id = id
    self.intendedDate = intendedDate
    self.sourceTemplateSessionID = sourceTemplateSessionID
    self.primaryLiftID = primaryLiftID
    self.assistanceLiftID = assistanceLiftID
    self.prescriptions = prescriptions
    self.status = status
  }

  private enum CodingKeys: String, CodingKey {
    case id, intendedDate, sourceTemplateSessionID, primaryLiftID, assistanceLiftID, prescriptions,
      status
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      intendedDate: try container.decode(TrainingDate.self, forKey: .intendedDate),
      sourceTemplateSessionID: try container.decode(String.self, forKey: .sourceTemplateSessionID),
      primaryLiftID: try container.decode(String.self, forKey: .primaryLiftID),
      assistanceLiftID: try container.decode(String.self, forKey: .assistanceLiftID),
      prescriptions: try container.decodeIfPresent(
        [TrainingSetPrescription].self, forKey: .prescriptions) ?? [],
      status: try container.decodeIfPresent(TrainingSessionStatus.self, forKey: .status)
        ?? .scheduled
    )
  }

  public var primaryLiftRole: String { primaryLiftID }
  public var assistanceLiftRole: String { assistanceLiftID }
}

public struct TrainingWeek: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public let position: Int
  public let kind: TrainingWeekKind
  public let startDate: TrainingDate
  public let sessions: [TrainingCycleSession]

  public init(
    id: String,
    position: Int,
    kind: TrainingWeekKind,
    startDate: TrainingDate,
    sessions: [TrainingCycleSession]
  ) {
    self.id = id
    self.position = position
    self.kind = kind
    self.startDate = startDate
    self.sessions = sessions
  }

  public var isDeload: Bool { kind.isDeload }

  /// A week is finished only when every planned session has a terminal disposition.
  public var isFinished: Bool {
    !sessions.isEmpty && sessions.allSatisfy { $0.status.isTerminal }
  }
}

public struct TrainingCycleSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let week1AnchorDate: TrainingDate
  public let weeks: [TrainingWeek]
  public let sourceTemplate: ScheduleTemplateSnapshot
  public let includesProvisionalDeload: Bool
  public let lifecycleState: TrainingCycleLifecycleState
  public let createdAt: Int64
  public let updatedAt: Int64
  public let liftSnapshots: [String: LiftConfigurationSnapshot]

  public init(
    id: String,
    week1AnchorDate: TrainingDate,
    weeks: [TrainingWeek],
    sourceTemplate: ScheduleTemplateSnapshot,
    includesProvisionalDeload: Bool,
    lifecycleState: TrainingCycleLifecycleState,
    createdAt: Int64 = 0,
    updatedAt: Int64 = 0,
    liftSnapshots: [String: LiftConfigurationSnapshot] = [:]
  ) {
    self.id = id
    self.week1AnchorDate = week1AnchorDate
    self.weeks = weeks
    self.sourceTemplate = sourceTemplate
    self.includesProvisionalDeload = includesProvisionalDeload
    self.lifecycleState = lifecycleState
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.liftSnapshots = liftSnapshots
  }

  private enum CodingKeys: String, CodingKey {
    case id, week1AnchorDate, weeks, sourceTemplate, includesProvisionalDeload,
      lifecycleState, createdAt, updatedAt, liftSnapshots
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      week1AnchorDate: try container.decode(TrainingDate.self, forKey: .week1AnchorDate),
      weeks: try container.decode([TrainingWeek].self, forKey: .weeks),
      sourceTemplate: try container.decode(ScheduleTemplateSnapshot.self, forKey: .sourceTemplate),
      includesProvisionalDeload: try container.decode(
        Bool.self, forKey: .includesProvisionalDeload),
      lifecycleState: try container.decode(
        TrainingCycleLifecycleState.self, forKey: .lifecycleState),
      createdAt: try container.decode(Int64.self, forKey: .createdAt),
      updatedAt: try container.decode(Int64.self, forKey: .updatedAt),
      liftSnapshots: try container.decodeIfPresent(
        [String: LiftConfigurationSnapshot].self, forKey: .liftSnapshots) ?? [:]
    )
  }
}

public struct TrainingCycle: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let week1AnchorDate: TrainingDate
  public let weeks: [TrainingWeek]
  public let sourceTemplate: ScheduleTemplateSnapshot
  public let includesProvisionalDeload: Bool
  public let lifecycleState: TrainingCycleLifecycleState
  public let createdAt: Int64
  public let updatedAt: Int64
  public let liftSnapshots: [String: LiftConfigurationSnapshot]

  public init(
    id: String,
    week1AnchorDate: TrainingDate,
    weeks: [TrainingWeek],
    sourceTemplate: ScheduleTemplateSnapshot,
    includesProvisionalDeload: Bool,
    lifecycleState: TrainingCycleLifecycleState = .draft,
    createdAt: Int64 = 0,
    updatedAt: Int64 = 0,
    liftSnapshots: [String: LiftConfigurationSnapshot] = [:]
  ) {
    self.id = id
    self.week1AnchorDate = week1AnchorDate
    self.weeks = weeks
    self.sourceTemplate = sourceTemplate
    self.includesProvisionalDeload = includesProvisionalDeload
    self.lifecycleState = lifecycleState
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.liftSnapshots = liftSnapshots
  }

  private enum CodingKeys: String, CodingKey {
    case id, week1AnchorDate, weeks, sourceTemplate, includesProvisionalDeload,
      lifecycleState, createdAt, updatedAt, liftSnapshots
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      week1AnchorDate: try container.decode(TrainingDate.self, forKey: .week1AnchorDate),
      weeks: try container.decode([TrainingWeek].self, forKey: .weeks),
      sourceTemplate: try container.decode(ScheduleTemplateSnapshot.self, forKey: .sourceTemplate),
      includesProvisionalDeload: try container.decode(
        Bool.self, forKey: .includesProvisionalDeload),
      lifecycleState: try container.decode(
        TrainingCycleLifecycleState.self, forKey: .lifecycleState),
      createdAt: try container.decode(Int64.self, forKey: .createdAt),
      updatedAt: try container.decode(Int64.self, forKey: .updatedAt),
      liftSnapshots: try container.decodeIfPresent(
        [String: LiftConfigurationSnapshot].self, forKey: .liftSnapshots) ?? [:]
    )
  }

  public var snapshot: TrainingCycleSnapshot {
    TrainingCycleSnapshot(
      id: id,
      week1AnchorDate: week1AnchorDate,
      weeks: weeks,
      sourceTemplate: sourceTemplate,
      includesProvisionalDeload: includesProvisionalDeload,
      lifecycleState: lifecycleState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      liftSnapshots: liftSnapshots
    )
  }

  public var trainingWeeks: [TrainingWeek] { weeks }
  public var totalWeeks: Int { weeks.count }
  public var isDraft: Bool { lifecycleState == .draft }
  public var isActive: Bool { lifecycleState == .active }

  public var trainingMaxSnapshots: [String: LiftConfigurationSnapshot] { liftSnapshots }
}

public enum TrainingCycleValidationError: Error, Equatable, Sendable {
  case invalidWeekOrder
  case invalidWeekCount
  case invalidSessionDate
  case emptyTemplate
  case unconfiguredLift(String)
  case draftAlreadyExists
  case noDraft
  case staleDraft
  case activeCycleAlreadyExists
  case pastAnchorRequiresChoice
  case deloadConfirmationRequired
  case missingTrainingMax(String)
}
