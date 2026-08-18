public enum ScheduleWeekday: Int, CaseIterable, Codable, Comparable, Equatable, Hashable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    public static func < (lhs: ScheduleWeekday, rhs: ScheduleWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }
}

public struct ScheduleSession: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let intendedWeekday: ScheduleWeekday
    public let primaryLiftID: String
    public let assistanceLiftID: String

    public init(
        id: String,
        intendedWeekday: ScheduleWeekday,
        primaryLiftID: String,
        assistanceLiftID: String,
    ) {
        self.id = id
        self.intendedWeekday = intendedWeekday
        self.primaryLiftID = primaryLiftID
        self.assistanceLiftID = assistanceLiftID
    }
}

public struct ScheduleTemplate: Codable, Equatable, Sendable {
    public let id: String
    public let sessions: [ScheduleSession]

    public init(id: String = "schedule-template", sessions: [ScheduleSession]) {
        self.id = id
        self.sessions = sessions
    }

    public var snapshot: ScheduleTemplateSnapshot {
        ScheduleTemplateSnapshot(id: id, sessions: sessions)
    }
}

public struct ScheduleTemplateSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let sessions: [ScheduleSession]

    public init(id: String, sessions: [ScheduleSession]) {
        self.id = id
        self.sessions = sessions
    }
}

public enum ScheduleTemplateAuditAction: String, Codable, Equatable, Sendable {
    case created
    case edited
    case reset
    /// A normal Training Week was explicitly used as the source for this template.
    /// The week’s dates, prescriptions, statuses, and logged work are not part of
    /// the resulting template snapshot.
    case savedFromTrainingWeek
}

public struct ScheduleTemplateAuditEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let templateID: String
    public let action: ScheduleTemplateAuditAction
    public let occurredAt: Int64
    public let before: ScheduleTemplateSnapshot?
    public let after: ScheduleTemplateSnapshot

    public init(
        id: String,
        templateID: String,
        action: ScheduleTemplateAuditAction,
        occurredAt: Int64,
        before: ScheduleTemplateSnapshot?,
        after: ScheduleTemplateSnapshot,
    ) {
        self.id = id
        self.templateID = templateID
        self.action = action
        self.occurredAt = occurredAt
        self.before = before
        self.after = after
    }
}

public struct DefaultScheduleEntry: Equatable, Sendable {
    public let intendedWeekday: ScheduleWeekday
    public let primaryIdentity: LiftIdentity
    public let assistanceIdentity: LiftIdentity

    public init(
        intendedWeekday: ScheduleWeekday,
        primaryIdentity: LiftIdentity,
        assistanceIdentity: LiftIdentity,
    ) {
        self.intendedWeekday = intendedWeekday
        self.primaryIdentity = primaryIdentity
        self.assistanceIdentity = assistanceIdentity
    }
}

public enum DefaultSchedule {
    public static let entries: [DefaultScheduleEntry] = [
        DefaultScheduleEntry(
            intendedWeekday: .monday,
            primaryIdentity: .progression(.squat),
            assistanceIdentity: .progression(.benchPress),
        ),
        DefaultScheduleEntry(
            intendedWeekday: .tuesday,
            primaryIdentity: .progression(.overheadPress),
            assistanceIdentity: .progression(.deadlift),
        ),
        DefaultScheduleEntry(
            intendedWeekday: .thursday,
            primaryIdentity: .progression(.benchPress),
            assistanceIdentity: .progression(.squat),
        ),
        DefaultScheduleEntry(
            intendedWeekday: .friday,
            primaryIdentity: .progression(.deadlift),
            assistanceIdentity: .progression(.overheadPress),
        ),
    ]
}

public enum ScheduleTemplateValidationError: Error, Equatable, Sendable {
    case emptyTemplate
    case duplicateSessionID
    case unconfiguredLift(String)
}
