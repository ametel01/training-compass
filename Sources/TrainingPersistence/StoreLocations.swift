import Foundation

public struct StoreLocations: Equatable, Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public var authoritativeDirectory: URL {
    root.appending(path: "authoritative", directoryHint: .isDirectory)
  }

  public var reconstructibleDirectory: URL {
    root.appending(path: "reconstructible", directoryHint: .isDirectory)
  }

  public var diagnosticsDirectory: URL {
    root.appending(path: "diagnostics", directoryHint: .isDirectory)
  }

  public var authoritativeDatabase: URL {
    authoritativeDirectory.appending(path: "authoritative.sqlite", directoryHint: .notDirectory)
  }

  /// A same-volume staging path. It is deliberately next to the live database
  /// so a replacement can use filesystem rename semantics rather than copying
  /// bytes across volumes.
  public var authoritativeStagingDatabase: URL {
    authoritativeDirectory.appending(
      path: "authoritative.importing.sqlite", directoryHint: .notDirectory)
  }

  public var authoritativeBackupDatabase: URL {
    authoritativeDirectory.appending(
      path: "authoritative.previous.sqlite", directoryHint: .notDirectory)
  }

  public var authoritativeSwapMarker: URL {
    authoritativeDirectory.appending(
      path: "authoritative.swap.pending", directoryHint: .notDirectory)
  }

  public var reconstructibleDatabase: URL {
    reconstructibleDirectory.appending(path: "reconstructible.sqlite", directoryHint: .notDirectory)
  }

  public var authoritativeMigrationDiagnostic: URL {
    authoritativeDirectory.appending(
      path: "authoritative.migration-diagnostic.json", directoryHint: .notDirectory)
  }

  public var reconstructibleMigrationDiagnostic: URL {
    reconstructibleDirectory.appending(
      path: "reconstructible.migration-diagnostic.json", directoryHint: .notDirectory)
  }
}
