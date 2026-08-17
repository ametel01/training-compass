import CryptoKit
import Foundation

/// A JSON value that preserves the SQLite storage class of an authoritative record.
public enum TrainingExportJSONValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case blob(base64: String)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum ValueType: String, Codable { case null, boolean, integer, number, string, blob }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .null:
            self = .null
        case .boolean:
            self = try .boolean(container.decode(Bool.self, forKey: .value))
        case .integer:
            self = try .integer(container.decode(Int64.self, forKey: .value))
        case .number:
            self = try .number(container.decode(Double.self, forKey: .value))
        case .string:
            self = try .string(container.decode(String.self, forKey: .value))
        case .blob:
            self = try .blob(base64: container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(ValueType.null, forKey: .type)
        case let .boolean(value):
            try container.encode(ValueType.boolean, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .integer(value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .number(value):
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .string(value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .blob(value):
            try container.encode(ValueType.blob, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct TrainingExportRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let fields: [String: TrainingExportJSONValue]

    public init(id: String, fields: [String: TrainingExportJSONValue]) {
        self.id = id
        self.fields = fields
    }

    /// A deterministic identity for legacy rows that have no declared key.
    public static func stableID(table: String, fields: [String: TrainingExportJSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let canonical = (try? encoder.encode(fields)) ?? Data()
        let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return "\(table)#\(digest)"
    }
}

public struct TrainingExportTable: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let records: [TrainingExportRecord]

    public init(name: String, records: [TrainingExportRecord]) {
        self.name = name
        self.records = records
    }

    public var id: String {
        name
    }
}

public struct TrainingExportPreference: Codable, Equatable, Sendable, Identifiable {
    public let key: String
    public let value: TrainingExportJSONValue

    public init(key: String, value: TrainingExportJSONValue) {
        self.key = key
        self.value = value
    }

    public var id: String {
        key
    }
}

/// All records in the backup-participating authoritative store. Derived
/// projections and the reconstructible HealthKit store are intentionally absent.
public struct TrainingAuthoritativeExportData: Codable, Equatable, Sendable {
    public let tables: [TrainingExportTable]
    public let preferences: [TrainingExportPreference]

    public init(
        tables: [TrainingExportTable],
        preferences: [TrainingExportPreference] = [],
    ) {
        self.tables = tables
        self.preferences = preferences
    }

    public var recordCount: Int {
        tables.reduce(0) { $0 + $1.records.count }
    }

    public func table(named name: String) -> TrainingExportTable? {
        tables.first { $0.name == name }
    }
}

/// A mirror snapshot is reference material owned by HealthKit, never canonical
/// recovery data. The adapter may omit it when no mirror has been requested.
public struct TrainingHealthKitMirrorExport: Codable, Equatable, Sendable {
    public let source: String
    public let records: [TrainingExportTable]

    public init(
        records: [TrainingExportTable], source: String = "HealthKit Mirror (reference material)",
    ) {
        self.source = source
        self.records = records
    }
}

public protocol TrainingHealthKitMirrorExportProvider: Sendable {
    func exportHealthKitMirror() async throws -> TrainingHealthKitMirrorExport
}

public struct TrainingExportCreationContext: Codable, Equatable, Sendable {
    public let timeZoneIdentifier: String
    public let localeIdentifier: String

    public init(timeZoneIdentifier: String, localeIdentifier: String = "en_US_POSIX") {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localeIdentifier = localeIdentifier
    }
}

public struct TrainingExportManifest: Codable, Equatable, Sendable {
    public let archiveType: String
    public let schemaVersion: Int
    public let generatorVersion: String
    public let createdAt: Int64
    public let creationContext: TrainingExportCreationContext

    public init(
        archiveType: String = "training-compass-export",
        schemaVersion: Int = 1,
        generatorVersion: String,
        createdAt: Int64,
        creationContext: TrainingExportCreationContext,
    ) {
        self.archiveType = archiveType
        self.schemaVersion = schemaVersion
        self.generatorVersion = generatorVersion
        self.createdAt = createdAt
        self.creationContext = creationContext
    }
}

public struct TrainingExportSummary: Codable, Equatable, Sendable {
    public let recordCount: Int
    public let tableCounts: [String: Int]
    public let readableText: String

    public init(recordCount: Int, tableCounts: [String: Int], readableText: String) {
        self.recordCount = recordCount
        self.tableCounts = tableCounts
        self.readableText = readableText
    }
}

public struct TrainingExportIntegrity: Codable, Equatable, Sendable {
    public let algorithm: String
    public let digest: String

    public init(algorithm: String = "SHA-256", digest: String) {
        self.algorithm = algorithm
        self.digest = digest
    }
}

public struct TrainingCompassExport: Codable, Equatable, Sendable {
    public let manifest: TrainingExportManifest
    public let summary: TrainingExportSummary
    public let authoritativeData: TrainingAuthoritativeExportData
    public let healthKitMirror: TrainingHealthKitMirrorExport?
    public let integrity: TrainingExportIntegrity

    public init(
        manifest: TrainingExportManifest,
        summary: TrainingExportSummary,
        authoritativeData: TrainingAuthoritativeExportData,
        healthKitMirror: TrainingHealthKitMirrorExport?,
        integrity: TrainingExportIntegrity,
    ) {
        self.manifest = manifest
        self.summary = summary
        self.authoritativeData = authoritativeData
        self.healthKitMirror = healthKitMirror
        self.integrity = integrity
    }

    public func encodedData() throws -> Data {
        try TrainingExportCodec.encode(self)
    }

    public func hasValidIntegrity() -> Bool {
        (try? TrainingExportCodec.digest(for: self)) == integrity.digest
    }

    public func verifyIntegrity() throws {
        guard integrity.algorithm == "SHA-256", hasValidIntegrity() else {
            throw TrainingExportError.integrityMismatch
        }
    }

    /// Decodes one complete export document. Importers should call
    /// ``verifyIntegrity()`` and their domain validation after decoding.
    public static func decode(_ data: Data) throws -> TrainingCompassExport {
        try TrainingExportCodec.decode(data)
    }

    /// Builds the deterministic, empty v1 archive retained by the migration
    /// compatibility verifier. It uses the same codec and integrity envelope as
    /// production exports, while containing no user data.
    public static func makeCompatibilityFixture() throws -> TrainingCompassExport {
        let tableNames = [
            "gate_zero_metadata", "lifts", "lift_configuration_audit", "schedule_templates",
            "schedule_template_sessions", "schedule_template_audit", "training_cycles",
            "training_cycle_audit", "set_results", "set_result_audit", "omitted_sets",
            "additional_sets", "session_completions", "session_correction_audit",
            "training_max_proposals", "training_max_history", "health_workout_link_facts",
            "heart_rate_configuration", "running_comparison_exclusions", "health_workout_write_backs",
        ]
        let data = TrainingAuthoritativeExportData(
            tables: tableNames.map { name in
                if name == "gate_zero_metadata" {
                    return TrainingExportTable(
                        name: name,
                        records: [
                            TrainingExportRecord(
                                id: "gate-zero",
                                fields: [
                                    "schema_version": .integer(1),
                                    "owner_data_accepted": .integer(0),
                                ],
                            ),
                        ],
                    )
                }
                return TrainingExportTable(name: name, records: [])
            },
        )
        let summary = TrainingExportSummary(
            recordCount: 1,
            tableCounts: Dictionary(
                uniqueKeysWithValues: tableNames.map { ($0, $0 == "gate_zero_metadata" ? 1 : 0) },
            ),
            readableText: "Training Compass compatibility fixture",
        )
        let manifest = TrainingExportManifest(
            generatorVersion: "compatibility/1",
            createdAt: 0,
            creationContext: TrainingExportCreationContext(timeZoneIdentifier: "UTC"),
        )
        let unsigned = TrainingCompassExport(
            manifest: manifest,
            summary: summary,
            authoritativeData: data,
            healthKitMirror: nil,
            integrity: TrainingExportIntegrity(digest: ""),
        )
        return try TrainingCompassExport(
            manifest: manifest,
            summary: summary,
            authoritativeData: data,
            healthKitMirror: nil,
            integrity: TrainingExportIntegrity(digest: TrainingExportCodec.digest(for: unsigned)),
        )
    }
}

public enum TrainingExportConfirmation: Codable, Equatable, Sendable {
    case confirmed
    case cancelled
}

public enum TrainingExportShareOutcome: Codable, Equatable, Sendable {
    case shared
    case cancelled
    case recoverableFailure
}

public struct TrainingExportPreview: Equatable, Sendable {
    public let authoritativeData: TrainingAuthoritativeExportData
    public let healthKitMirror: TrainingHealthKitMirrorExport?
    public let summary: TrainingExportSummary
    public let warning: String
    public let requiresSensitiveDataConfirmation: Bool

    public init(
        authoritativeData: TrainingAuthoritativeExportData,
        healthKitMirror: TrainingHealthKitMirrorExport?,
        summary: TrainingExportSummary,
        warning: String =
            "This unencrypted archive contains sensitive fitness data. Store and share it carefully.",
        requiresSensitiveDataConfirmation: Bool = true,
    ) {
        self.authoritativeData = authoritativeData
        self.healthKitMirror = healthKitMirror
        self.summary = summary
        self.warning = warning
        self.requiresSensitiveDataConfirmation = requiresSensitiveDataConfirmation
    }
}

public struct TrainingExportArtifact: Equatable, Sendable {
    public let url: URL
    public let archive: TrainingCompassExport

    public init(url: URL, archive: TrainingCompassExport) {
        self.url = url
        self.archive = archive
    }
}

public protocol TrainingExportFileSystem: Sendable {
    func temporaryExportDirectory() throws -> URL
    func write(_ data: Data, to url: URL) throws
    func removeItem(at url: URL) throws
}

public protocol TrainingExportSpaceChecking: Sendable {
    func availableExportSpaceBytes() throws -> Int64
}

public struct FoundationTrainingExportFileSystem: TrainingExportFileSystem,
    TrainingExportSpaceChecking
{
    public init() {}

    public func temporaryExportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TrainingCompassExports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func availableExportSpaceBytes() throws -> Int64 {
        let values = try FileManager.default.temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey],
        )
        return Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

public enum TrainingExportError: Error, Equatable, Sendable {
    case unavailable
    case confirmationRequired
    case integrityMismatch
    case unsupportedSchema(Int)
    case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)
    case cleanupFailed

    public var privacySafeDescription: String {
        switch self {
        case .unavailable: "Export is unavailable."
        case .confirmationRequired: "Export confirmation is required."
        case .integrityMismatch: "The export integrity check failed."
        case .unsupportedSchema: "This export schema is not supported."
        case .insufficientSpace: "There is not enough temporary storage for this export."
        case .cleanupFailed: "The temporary export could not be cleaned up."
        }
    }
}

public protocol TrainingAuthoritativeExportRepository: Sendable {
    func loadAuthoritativeExportData() async throws -> TrainingAuthoritativeExportData
}

public extension TrainingAuthoritativeExportRepository {
    func loadAuthoritativeExportData() async throws -> TrainingAuthoritativeExportData {
        throw TrainingExportError.unavailable
    }
}

private struct TrainingExportDigestPayload: Codable {
    let manifest: TrainingExportManifest
    let summary: TrainingExportSummary
    let authoritativeData: TrainingAuthoritativeExportData
    let healthKitMirror: TrainingHealthKitMirrorExport?
}

enum TrainingExportCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func digest(for archive: TrainingCompassExport) throws -> String {
        let payload = TrainingExportDigestPayload(
            manifest: archive.manifest,
            summary: archive.summary,
            authoritativeData: archive.authoritativeData,
            healthKitMirror: archive.healthKitMirror,
        )
        let data = try encoder().encode(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode(_ archive: TrainingCompassExport) throws -> Data {
        try encoder().encode(archive)
    }

    static func decode(_ data: Data) throws -> TrainingCompassExport {
        try JSONDecoder().decode(TrainingCompassExport.self, from: data)
    }
}

public struct TrainingExportBoundary: Sendable {
    private let repository: any TrainingAuthoritativeExportRepository
    private let clock: any Clock
    private let timeZone: any TimeZoneProvider
    private let uuidGenerator: any UUIDGenerator
    private let fileSystem: any TrainingExportFileSystem
    private let mirrorProvider: (any TrainingHealthKitMirrorExportProvider)?
    private let generatorVersion: String

    public init(
        repository: any TrainingAuthoritativeExportRepository,
        clock: any Clock,
        timeZone: any TimeZoneProvider,
        uuidGenerator: any UUIDGenerator,
        fileSystem: any TrainingExportFileSystem = FoundationTrainingExportFileSystem(),
        mirrorProvider: (any TrainingHealthKitMirrorExportProvider)? = nil,
        generatorVersion: String = "TrainingCompass/1",
    ) {
        self.repository = repository
        self.clock = clock
        self.timeZone = timeZone
        self.uuidGenerator = uuidGenerator
        self.fileSystem = fileSystem
        self.mirrorProvider = mirrorProvider
        self.generatorVersion = generatorVersion
    }

    public func preview(includeHealthKitMirror: Bool = false) async throws -> TrainingExportPreview {
        try Task.checkCancellation()
        let data = try await repository.loadAuthoritativeExportData()
        try Task.checkCancellation()
        let mirror: TrainingHealthKitMirrorExport? =
            if includeHealthKitMirror {
                try await mirrorProvider?.exportHealthKitMirror()
            } else {
                nil
            }
        let counts = Dictionary(uniqueKeysWithValues: data.tables.map { ($0.name, $0.records.count) })
        let readable =
            ([
                "Training Compass Export preview",
                "Authoritative records: \(data.recordCount)",
                "Preferences: \(data.preferences.count)",
                "HealthKit mirror: \(mirror == nil ? "not included" : "reference material included")",
            ] + data.tables.map { "\($0.name): \($0.records.count)" }).joined(separator: "\n")
        return TrainingExportPreview(
            authoritativeData: data,
            healthKitMirror: mirror,
            summary: TrainingExportSummary(
                recordCount: data.recordCount,
                tableCounts: counts,
                readableText: readable,
            ),
        )
    }

    public func create(
        _ preview: TrainingExportPreview,
        confirmation: TrainingExportConfirmation,
    ) throws -> TrainingExportArtifact {
        guard confirmation == .confirmed else { throw TrainingExportError.confirmationRequired }
        let manifest = TrainingExportManifest(
            generatorVersion: generatorVersion,
            createdAt: Int64(clock.now().timeIntervalSince1970),
            creationContext: TrainingExportCreationContext(
                timeZoneIdentifier: timeZone.timeZone().identifier,
            ),
        )
        let unsigned = TrainingCompassExport(
            manifest: manifest,
            summary: preview.summary,
            authoritativeData: preview.authoritativeData,
            healthKitMirror: preview.healthKitMirror,
            integrity: TrainingExportIntegrity(digest: ""),
        )
        let archive = try TrainingCompassExport(
            manifest: manifest,
            summary: preview.summary,
            authoritativeData: preview.authoritativeData,
            healthKitMirror: preview.healthKitMirror,
            integrity: TrainingExportIntegrity(digest: TrainingExportCodec.digest(for: unsigned)),
        )
        let data = try archive.encodedData()
        let directory = try fileSystem.temporaryExportDirectory()
        let url = directory.appending(
            path:
            "TrainingCompass-\(manifest.createdAt)-\(uuidGenerator.makeUUID().uuidString).trainingcompass",
        )
        do {
            if let checker = fileSystem as? any TrainingExportSpaceChecking {
                let requiredBytes = Int64((Double(data.count) * 1.2).rounded(.up))
                let availableBytes = try checker.availableExportSpaceBytes()
                guard availableBytes >= requiredBytes else {
                    throw TrainingExportError.insufficientSpace(
                        requiredBytes: requiredBytes,
                        availableBytes: availableBytes,
                    )
                }
            }
            try fileSystem.write(data, to: url)
            return TrainingExportArtifact(url: url, archive: archive)
        } catch {
            try? fileSystem.removeItem(at: url)
            throw error
        }
    }

    /// The system share presenter calls this for both success and cancellation. A
    /// temporary artifact is never retained after the share sheet completes.
    public func completeShare(
        _ artifact: TrainingExportArtifact,
        outcome: TrainingExportShareOutcome,
    ) throws -> TrainingExportShareOutcome {
        do {
            try fileSystem.removeItem(at: artifact.url)
        } catch {
            throw TrainingExportError.cleanupFailed
        }
        return outcome
    }

    public func cleanup(_ artifact: TrainingExportArtifact) throws {
        _ = try completeShare(artifact, outcome: .recoverableFailure)
    }
}
