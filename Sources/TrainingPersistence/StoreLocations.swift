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

  public var authoritativeDatabase: URL {
    authoritativeDirectory.appending(path: "authoritative.sqlite", directoryHint: .notDirectory)
  }

  public var reconstructibleDatabase: URL {
    reconstructibleDirectory.appending(path: "reconstructible.sqlite", directoryHint: .notDirectory)
  }
}
