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

public struct TrainingCycleSession: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public let intendedDate: TrainingDate
  public let sourceTemplateSessionID: String
  public let primaryLiftID: String
  public let assistanceLiftID: String

  public init(
    id: String,
    intendedDate: TrainingDate,
    sourceTemplateSessionID: String,
    primaryLiftID: String,
    assistanceLiftID: String
  ) {
    self.id = id
    self.intendedDate = intendedDate
    self.sourceTemplateSessionID = sourceTemplateSessionID
    self.primaryLiftID = primaryLiftID
    self.assistanceLiftID = assistanceLiftID
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

  public init(
    id: String,
    week1AnchorDate: TrainingDate,
    weeks: [TrainingWeek],
    sourceTemplate: ScheduleTemplateSnapshot,
    includesProvisionalDeload: Bool,
    lifecycleState: TrainingCycleLifecycleState,
    createdAt: Int64 = 0,
    updatedAt: Int64 = 0
  ) {
    self.id = id
    self.week1AnchorDate = week1AnchorDate
    self.weeks = weeks
    self.sourceTemplate = sourceTemplate
    self.includesProvisionalDeload = includesProvisionalDeload
    self.lifecycleState = lifecycleState
    self.createdAt = createdAt
    self.updatedAt = updatedAt
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

  public init(
    id: String,
    week1AnchorDate: TrainingDate,
    weeks: [TrainingWeek],
    sourceTemplate: ScheduleTemplateSnapshot,
    includesProvisionalDeload: Bool,
    lifecycleState: TrainingCycleLifecycleState = .draft,
    createdAt: Int64 = 0,
    updatedAt: Int64 = 0
  ) {
    self.id = id
    self.week1AnchorDate = week1AnchorDate
    self.weeks = weeks
    self.sourceTemplate = sourceTemplate
    self.includesProvisionalDeload = includesProvisionalDeload
    self.lifecycleState = lifecycleState
    self.createdAt = createdAt
    self.updatedAt = updatedAt
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
      updatedAt: updatedAt
    )
  }

  public var trainingWeeks: [TrainingWeek] { weeks }
  public var totalWeeks: Int { weeks.count }
  public var isDraft: Bool { lifecycleState == .draft }
  public var isActive: Bool { lifecycleState == .active }
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
}
