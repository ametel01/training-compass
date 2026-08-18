import Foundation

/// The only result categories that may cross the diagnostic boundary.
public enum PrivacyDiagnosticResult: String, Codable, Equatable, Sendable {
    case success
    case failure
    case paused
    case degraded
    case notApplicable
}

public enum PrivacyDiagnosticOperation: String, Codable, Equatable, Sendable {
    case preDataStoresReady = "pre_data_stores_ready"
    case preDataStoresFailed = "pre_data_stores_failed"
    case storeOpen = "store_open"
    case healthRefresh = "health_refresh"
}

public enum PrivacyDiagnosticThermalState: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public enum PrivacyDiagnosticBatteryState: String, Codable, Equatable, Sendable {
    case unplugged
    case charging
    case full
    case unknown
}

/// Coarse device state is useful for explaining a release-gate result without
/// recording a device identifier, a measurement, or a timestamp.
public struct PrivacyDiagnosticDeviceConditions: Codable, Equatable, Sendable {
    public let lowPowerMode: Bool
    public let thermalState: PrivacyDiagnosticThermalState
    public let batteryState: PrivacyDiagnosticBatteryState
    public let availableStorageMiB: Int64

    public init(
        lowPowerMode: Bool,
        thermalState: PrivacyDiagnosticThermalState,
        batteryState: PrivacyDiagnosticBatteryState,
        availableStorageMiB: Int64,
    ) {
        self.lowPowerMode = lowPowerMode
        self.thermalState = thermalState
        self.batteryState = batteryState
        self.availableStorageMiB = max(0, availableStorageMiB)
    }
}

/// A single privacy-safe production diagnostic. The shape is intentionally
/// closed: no dates, HealthKit identifiers, workout values, routes, or notes
/// can be added accidentally without changing this contract and its tests.
public struct PrivacyDiagnostic: Codable, Equatable, Sendable {
    public let operation: PrivacyDiagnosticOperation
    public let durationMilliseconds: Int64
    public let recordCount: Int64
    public let byteCount: Int64
    public let peakMemoryMiB: Int64
    public let resultCategory: PrivacyDiagnosticResult
    public let deviceConditions: PrivacyDiagnosticDeviceConditions

    public init(
        operation: PrivacyDiagnosticOperation,
        durationMilliseconds: Int64,
        recordCount: Int64,
        byteCount: Int64,
        peakMemoryMiB: Int64,
        resultCategory: PrivacyDiagnosticResult,
        deviceConditions: PrivacyDiagnosticDeviceConditions,
    ) {
        self.operation = operation
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.recordCount = max(0, recordCount)
        self.byteCount = max(0, byteCount)
        self.peakMemoryMiB = max(0, peakMemoryMiB)
        self.resultCategory = resultCategory
        self.deviceConditions = deviceConditions
    }
}

public enum PrivacyDiagnosticStoreError: Error, Equatable, Sendable {
    case invalidDirectory
    case exportAlreadyExists
}

public protocol PrivacyDiagnosticProtectionManaging: Sendable {
    func createDirectory(at url: URL) throws
    func applyCompleteFileProtection(to url: URL) throws
    func excludeFromBackup(_ url: URL) throws
    func verifyCompleteFileProtection(at url: URL) throws
    func verifyExcludedFromBackup(_ url: URL) throws
}

public struct FileManagerPrivacyDiagnosticProtection: PrivacyDiagnosticProtectionManaging {
    public init() {}

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func applyCompleteFileProtection(to url: URL) throws {
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(simulator)
            try (url as NSURL).setResourceValue(
                URLFileProtection.complete,
                forKey: .fileProtectionKey,
            )
        #else
            _ = url
        #endif
    }

    public func excludeFromBackup(_ url: URL) throws {
        #if targetEnvironment(simulator)
            _ = url
            return
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    public func verifyCompleteFileProtection(at url: URL) throws {
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(simulator)
            let values = try url.resourceValues(forKeys: [.fileProtectionKey])
            guard values.fileProtection == .complete else {
                throw PrivacyDiagnosticStoreError.invalidDirectory
            }
        #else
            _ = url
        #endif
    }

    public func verifyExcludedFromBackup(_ url: URL) throws {
        #if targetEnvironment(simulator)
            _ = url
            return
        #endif
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        guard values.isExcludedFromBackup == true else {
            throw PrivacyDiagnosticStoreError.invalidDirectory
        }
    }
}

/// Durable, bounded storage for release diagnostics. Event age is represented
/// by the file-system modification date rather than serialized into the
/// diagnostic payload, so exported evidence contains no dates.
public actor PrivacyDiagnosticStore {
    public static let maximumEvents = 200
    public static let retentionWindow: TimeInterval = 7 * 24 * 60 * 60

    private let directory: URL
    private let clock: any Clock
    private let fileManager: FileManager
    private let protection: any PrivacyDiagnosticProtectionManaging

    public init(
        directory: URL,
        clock: any Clock = SystemClock(),
        fileManager: FileManager = .default,
        protection: any PrivacyDiagnosticProtectionManaging = FileManagerPrivacyDiagnosticProtection(),
    ) {
        self.directory = directory
        self.clock = clock
        self.fileManager = fileManager
        self.protection = protection
    }

    public func append(_ diagnostic: PrivacyDiagnostic) throws {
        guard directory.isFileURL else { throw PrivacyDiagnosticStoreError.invalidDirectory }
        try protection.createDirectory(at: directory)
        try protection.applyCompleteFileProtection(to: directory)
        try protection.excludeFromBackup(directory)
        try protection.verifyCompleteFileProtection(at: directory)
        try protection.verifyExcludedFromBackup(directory)
        let data = try JSONEncoder().encode(diagnostic)
        let filename = try "diagnostic-\(nextSequence())-\(UUID().uuidString).json"
        let destination = directory.appending(path: filename, directoryHint: .notDirectory)
        try data.write(to: destination, options: [.atomic])
        try protection.applyCompleteFileProtection(to: destination)
        try protection.excludeFromBackup(destination)
        try protection.verifyCompleteFileProtection(at: destination)
        try protection.verifyExcludedFromBackup(destination)
        try fileManager.setAttributes(
            [.modificationDate: clock.now()],
            ofItemAtPath: destination.path(percentEncoded: false),
        )
        try prune()
    }

    public func entries() throws -> [PrivacyDiagnostic] {
        try prune()
        let files = try diagnosticFiles().sorted { lhs, rhs in
            let lhsDate = modificationDate(for: lhs)
            let rhsDate = modificationDate(for: rhs)
            return lhsDate == rhsDate ? sequence(for: lhs) > sequence(for: rhs) : lhsDate > rhsDate
        }
        return try files.map {
            try JSONDecoder().decode(PrivacyDiagnostic.self, from: Data(contentsOf: $0))
        }
    }

    /// Explicit export is the only way diagnostics leave their private store.
    /// The caller owns the destination and must call `removeExport` after review
    /// or sharing has completed.
    public func export(to destination: URL) throws {
        guard destination.isFileURL else { throw PrivacyDiagnosticStoreError.invalidDirectory }
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw PrivacyDiagnosticStoreError.exportAlreadyExists
        }
        let payload = try JSONEncoder().encode(entries())
        try protection.createDirectory(at: destination.deletingLastPathComponent())
        try protection.applyCompleteFileProtection(to: destination.deletingLastPathComponent())
        try protection.excludeFromBackup(destination.deletingLastPathComponent())
        try protection.verifyCompleteFileProtection(at: destination.deletingLastPathComponent())
        try protection.verifyExcludedFromBackup(destination.deletingLastPathComponent())
        try payload.write(to: destination, options: [.atomic])
        try protection.applyCompleteFileProtection(to: destination)
        try protection.excludeFromBackup(destination)
        try protection.verifyCompleteFileProtection(at: destination)
        try protection.verifyExcludedFromBackup(destination)
    }

    public func removeExport(at destination: URL) throws {
        guard destination.isFileURL else { throw PrivacyDiagnosticStoreError.invalidDirectory }
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
    }

    private func diagnosticFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ).filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("diagnostic-") }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func prune() throws {
        let cutoff = clock.now().addingTimeInterval(-Self.retentionWindow)
        let files = try diagnosticFiles()
        for file in files where modificationDate(for: file) < cutoff {
            try fileManager.removeItem(at: file)
        }

        let retained = try diagnosticFiles().sorted { lhs, rhs in
            let lhsDate = modificationDate(for: lhs)
            let rhsDate = modificationDate(for: rhs)
            return lhsDate == rhsDate ? sequence(for: lhs) > sequence(for: rhs) : lhsDate > rhsDate
        }
        for file in retained.dropFirst(Self.maximumEvents) {
            try fileManager.removeItem(at: file)
        }
    }

    private func nextSequence() throws -> UInt64 {
        let highest = try diagnosticFiles().map(sequence(for:)).max() ?? 0
        return highest + 1
    }

    private func sequence(for url: URL) -> UInt64 {
        let components = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard components.count >= 3, let sequence = UInt64(components[1]) else { return 0 }
        return sequence
    }
}
