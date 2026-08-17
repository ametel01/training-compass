import Foundation

/// The three independent Health streams that can contribute Recovery Evidence.
/// They intentionally remain separate from the workout stream: a successful
/// workout import never implies that a recovery measurement was readable.
public enum RecoveryEvidenceStream: String, Codable, CaseIterable, Equatable, Sendable {
    case sleep
    case restingHeartRate
    case heartRateVariability

    public init?(_ stream: HealthSyncStream) {
        switch stream {
        case .sleep: self = .sleep
        case .restingHeartRate: self = .restingHeartRate
        case .heartRateVariability: self = .heartRateVariability
        default: return nil
        }
    }

    public var healthSyncStream: HealthSyncStream {
        switch self {
        case .sleep: .sleep
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariability: .heartRateVariability
        }
    }
}

public struct HealthRecoverySampleProvenance: Codable, Equatable, Sendable {
    public let sourceName: String?
    public let sourceBundleIdentifier: String?
    public let sourceProductType: String?
    public let sourceOSVersion: String?
    public let deviceName: String?
    public let deviceModel: String?
    /// HealthKit may provide an algorithm revision for quantity samples. It is
    /// retained as opaque, source-provided text and is never interpreted.
    public let algorithmVersion: String?

    public init(
        sourceName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        sourceProductType: String? = nil,
        sourceOSVersion: String? = nil,
        deviceName: String? = nil,
        deviceModel: String? = nil,
        algorithmVersion: String? = nil,
    ) {
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceProductType = sourceProductType
        self.sourceOSVersion = sourceOSVersion
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.algorithmVersion = algorithmVersion
    }

    public var displayName: String {
        sourceName ?? sourceProductType ?? deviceName ?? sourceBundleIdentifier
            ?? "Source unavailable"
    }

    public var source: HealthRecoverySampleProvenance {
        self
    }

    public var algorithm: String? {
        algorithmVersion
    }
}

public enum HealthSleepStage: String, Codable, CaseIterable, Equatable, Sendable {
    case inBed
    case asleep
    case awake
    case asleepCore
    case asleepDeep
    case asleepREM
    case unknown
}

/// One source-owned sleep interval. Intervals are retained as reported; the
/// application does not fill gaps or merge overlapping sources at import time.
public struct HealthSleepSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let startDate: Date
    public let endDate: Date
    public let stage: HealthSleepStage
    public let provenance: HealthRecoverySampleProvenance

    public init(
        id: String,
        startDate: Date,
        endDate: Date,
        stage: HealthSleepStage = .asleep,
        provenance: HealthRecoverySampleProvenance = .init(),
    ) {
        precondition(!id.isEmpty)
        precondition(endDate >= startDate)
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.stage = stage
        self.provenance = provenance
    }

    public var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    public var time: Date {
        startDate
    }

    public var sample: TimeInterval {
        duration
    }

    public var sleepStage: HealthSleepStage {
        stage
    }
}

public struct HealthRestingHeartRateSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let date: Date
    public let beatsPerMinute: Double
    public let provenance: HealthRecoverySampleProvenance

    public init(
        id: String,
        date: Date,
        beatsPerMinute: Double,
        provenance: HealthRecoverySampleProvenance = .init(),
    ) {
        precondition(!id.isEmpty)
        precondition(beatsPerMinute > 0 && beatsPerMinute.isFinite)
        self.id = id
        self.date = date
        self.beatsPerMinute = beatsPerMinute
        self.provenance = provenance
    }

    public var sample: Double {
        beatsPerMinute
    }

    public var value: Double {
        beatsPerMinute
    }

    public var time: Date {
        date
    }
}

public struct HealthHRVSDNNSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let date: Date
    public let milliseconds: Double
    public let provenance: HealthRecoverySampleProvenance

    public init(
        id: String,
        date: Date,
        milliseconds: Double,
        provenance: HealthRecoverySampleProvenance = .init(),
    ) {
        precondition(!id.isEmpty)
        precondition(milliseconds > 0 && milliseconds.isFinite)
        self.id = id
        self.date = date
        self.milliseconds = milliseconds
        self.provenance = provenance
    }

    public var sample: Double {
        milliseconds
    }

    public var value: Double {
        milliseconds
    }

    public var time: Date {
        date
    }
}

// Descriptive aliases keep the application API readable at call sites that
// spell out the metric while retaining one canonical representation.
public typealias HealthSleepInterval = HealthSleepSample
public typealias HealthHeartRateVariabilitySDNNSample = HealthHRVSDNNSample
public typealias HealthHeartRateVariabilitySample = HealthHRVSDNNSample

public enum HealthRecoverySample: Codable, Equatable, Sendable, Identifiable {
    case sleep(HealthSleepSample)
    case restingHeartRate(HealthRestingHeartRateSample)
    case heartRateVariability(HealthHRVSDNNSample)

    public var id: String {
        switch self {
        case let .sleep(sample): sample.id
        case let .restingHeartRate(sample): sample.id
        case let .heartRateVariability(sample): sample.id
        }
    }

    public var stream: RecoveryEvidenceStream {
        switch self {
        case .sleep: .sleep
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariability: .heartRateVariability
        }
    }

    public var date: Date {
        switch self {
        case let .sleep(sample): sample.startDate
        case let .restingHeartRate(sample): sample.date
        case let .heartRateVariability(sample): sample.date
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case sleep, restingHeartRate, heartRateVariability }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sleep(value):
            try container.encode(Kind.sleep, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .restingHeartRate(value):
            try container.encode(Kind.restingHeartRate, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .heartRateVariability(value):
            try container.encode(Kind.heartRateVariability, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .sleep: self = try .sleep(container.decode(HealthSleepSample.self, forKey: .value))
        case .restingHeartRate:
            self = try .restingHeartRate(
                container.decode(HealthRestingHeartRateSample.self, forKey: .value),
            )
        case .heartRateVariability:
            self = try .heartRateVariability(
                container.decode(HealthHRVSDNNSample.self, forKey: .value),
            )
        }
    }
}

public struct HealthRecoveryEvidenceSnapshot: Codable, Equatable, Sendable {
    public let sleep: [HealthSleepSample]
    public let restingHeartRate: [HealthRestingHeartRateSample]
    public let heartRateVariability: [HealthHRVSDNNSample]
    public let statuses: [HealthStreamStatus]

    public init(
        sleep: [HealthSleepSample] = [],
        restingHeartRate: [HealthRestingHeartRateSample] = [],
        heartRateVariability: [HealthHRVSDNNSample] = [],
        statuses: [HealthStreamStatus] = [],
    ) {
        self.sleep = sleep.sorted { $0.startDate < $1.startDate }
        self.restingHeartRate = restingHeartRate.sorted { $0.date < $1.date }
        self.heartRateVariability = heartRateVariability.sorted { $0.date < $1.date }
        self.statuses = statuses
    }

    public var isEmpty: Bool {
        sleep.isEmpty && restingHeartRate.isEmpty && heartRateVariability.isEmpty
    }

    public var streamStatuses: [HealthStreamStatus] {
        statuses
    }
}
