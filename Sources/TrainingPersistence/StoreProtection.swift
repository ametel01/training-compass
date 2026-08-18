import Foundation

public protocol StoreProtectionManaging: Sendable {
    func createDirectory(at url: URL) throws
    func applyCompleteFileProtection(to url: URL) throws
    func excludeFromBackup(_ url: URL) throws
    func verifyCompleteFileProtection(at url: URL) throws
    func verifyExcludedFromBackup(at url: URL) throws
}

public enum StoreProtectionError: Error, Equatable {
    case completeFileProtectionMissing(URL)
    case backupExclusionMissing(URL)
}

public struct FileManagerStoreProtection: StoreProtectionManaging {
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
                throw StoreProtectionError.completeFileProtectionMissing(url)
            }
        #else
            _ = url
        #endif
    }

    public func verifyExcludedFromBackup(at url: URL) throws {
        #if targetEnvironment(simulator)
            _ = url
            return
        #endif
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        guard values.isExcludedFromBackup == true else {
            throw StoreProtectionError.backupExclusionMissing(url)
        }
    }
}
