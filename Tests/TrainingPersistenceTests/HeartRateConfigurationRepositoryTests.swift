import Foundation
@testable import TrainingApplication
@testable import TrainingDomain
@testable import TrainingPersistence
import XCTest

final class HeartRateConfigurationRepositoryTests: XCTestCase {
    func testConfigurationPersistsAcrossRestartAndCanBeCleared() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GRDBTrainingRepository(root: root)
        let first = try configuration(maximum: 190, updatedAt: 10)

        try await repository.saveHeartRateConfiguration(first, expectedBefore: nil)
        let loadedFirst = try await repository.loadHeartRateConfiguration()
        XCTAssertEqual(loadedFirst, first)

        let replacement = try configuration(maximum: 175.5, updatedAt: 20)
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
        let first = try configuration(maximum: 190, updatedAt: 10)
        let second = try configuration(maximum: 180, updatedAt: 20)
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

    private func configuration(maximum: Double, updatedAt: Int64) throws
        -> HeartRateConfiguration
    {
        try HeartRateConfiguration(
            zoneBoundaries: HeartRateZoneBoundaries(
                restingHeartRateBPM: 64,
                maximumHeartRate: MaximumHeartRate(beatsPerMinute: maximum),
                zone2MinimumBPM: 131,
                zone3MinimumBPM: 142,
                zone4MinimumBPM: 153,
                zone5MinimumBPM: 165,
            ),
            updatedAt: updatedAt,
        )
    }
}
