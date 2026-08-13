import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingDomain
@testable import TrainingPersistence

final class TrainingErasureRepositoryTests: XCTestCase {
  func testConfirmedErasureClosesAndRemovesBothStoresAndTemporaryExports() async throws {
    let root = temporaryRoot("complete")
    let exports = root.appending(path: "temporary-exports", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let preferences = PreferencesSpy()
    let repository = GRDBTrainingRepository(
      root: root,
      erasurePreferences: preferences,
      temporaryExportDirectory: exports
    )
    try await repository.prepareStores()
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    try Data("shared-locally-only".utf8).write(
      to: exports.appending(path: "archive.trainingcompass"))
    let locations = StoreLocations(root: root)

    try await repository.eraseAllData(progress: nil)

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: locations.authoritativeDirectory.path()))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: locations.reconstructibleDirectory.path()))
    XCTAssertFalse(FileManager.default.fileExists(atPath: exports.path()))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appending(path: "training-compass-erasure.pending").path()))
    let removeCalls = preferences.removeCallCount
    XCTAssertEqual(removeCalls, 1)

    let restarted = GRDBTrainingRepository(
      root: root,
      erasurePreferences: preferences,
      temporaryExportDirectory: exports
    )
    let isEmptyAfterRestart = try await restarted.authoritativeStoreIsEmpty()
    XCTAssertTrue(isEmptyAfterRestart)
  }

  func testInterruptedErasureIsCompletedBeforeRestartOpensStores() async throws {
    let root = temporaryRoot("interrupted")
    let exports = root.appending(path: "temporary-exports", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let observer = InterruptingErasureObserver(phase: .removingProtectedStores)
    let preferences = PreferencesSpy()
    let repository = GRDBTrainingRepository(
      root: root,
      erasurePhaseObserver: observer,
      erasurePreferences: preferences,
      temporaryExportDirectory: exports
    )
    try await repository.prepareStores()
    let locations = StoreLocations(root: root)
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)

    do {
      try await repository.eraseAllData(progress: nil)
      XCTFail("The injected interruption should stop the first attempt")
    } catch {}
    XCTAssertTrue(FileManager.default.fileExists(atPath: locations.authoritativeDirectory.path()))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: root.appending(path: "training-compass-erasure.pending").path()))

    let restarted = GRDBTrainingRepository(
      root: root,
      erasurePreferences: preferences,
      temporaryExportDirectory: exports
    )
    try await restarted.prepareStores()

    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appending(path: "training-compass-erasure.pending").path()))
    XCTAssertFalse(FileManager.default.fileExists(atPath: exports.path()))
    let isEmptyAfterRestart = try await restarted.authoritativeStoreIsEmpty()
    XCTAssertTrue(isEmptyAfterRestart)
    let removeCalls = preferences.removeCallCount
    XCTAssertEqual(removeCalls, 1)
  }

  private func temporaryRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
      .appending(
        path: "training-erasure-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
  }
}

private final class PreferencesSpy: TrainingErasurePreferences, @unchecked Sendable {
  private(set) var removeCallCount = 0
  private let lock = NSLock()

  func removeAll() throws {
    lock.lock()
    removeCallCount += 1
    lock.unlock()
  }
}

private struct InterruptingErasureObserver: TrainingErasurePhaseObserver {
  let phase: TrainingErasurePhase

  func didReach(_ phase: TrainingErasurePhase) throws {
    if phase == self.phase { throw Interruption.injected }
  }
}

private enum Interruption: Error { case injected }
