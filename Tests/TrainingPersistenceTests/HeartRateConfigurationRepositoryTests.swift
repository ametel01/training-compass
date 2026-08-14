import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingDomain
@testable import TrainingPersistence

final class HeartRateConfigurationRepositoryTests: XCTestCase {
  func testConfigurationPersistsAcrossRestartAndCanBeCleared() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let first = HeartRateConfiguration(
      maximumHeartRate: try MaximumHeartRate(beatsPerMinute: 190), updatedAt: 10)

    try await repository.saveHeartRateConfiguration(first, expectedBefore: nil)
    let loadedFirst = try await repository.loadHeartRateConfiguration()
    XCTAssertEqual(loadedFirst, first)

    let replacement = HeartRateConfiguration(
      maximumHeartRate: try MaximumHeartRate(beatsPerMinute: 175.5), updatedAt: 20)
    try await repository.saveHeartRateConfiguration(replacement, expectedBefore: first)
    let restarted = GRDBTrainingRepository(root: root)
    let loadedReplacement = try await restarted.loadHeartRateConfiguration()
    XCTAssertEqual(loadedReplacement, replacement)

    try await restarted.deleteHeartRateConfiguration()
    let afterClear = try await restarted.loadHeartRateConfiguration()
    XCTAssertNil(afterClear)
  }

  func testStaleConfigurationCannotOverwriteOwnerChoice() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let first = HeartRateConfiguration(
      maximumHeartRate: try MaximumHeartRate(beatsPerMinute: 190), updatedAt: 10)
    let second = HeartRateConfiguration(
      maximumHeartRate: try MaximumHeartRate(beatsPerMinute: 180), updatedAt: 20)
    try await repository.saveHeartRateConfiguration(first, expectedBefore: nil)
    try await repository.saveHeartRateConfiguration(second, expectedBefore: first)

    do {
      try await repository.saveHeartRateConfiguration(first, expectedBefore: first)
      XCTFail("Expected stale configuration to be rejected")
    } catch HeartRateConfigurationRepositoryError.staleConfiguration {
      // expected
    }
    let loaded = try await repository.loadHeartRateConfiguration()
    XCTAssertEqual(loaded, second)
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  }
}
