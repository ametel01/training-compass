import Foundation
import XCTest

@testable import TrainingApplication

final class SyntheticFixtureGeneratorTests: XCTestCase {
  func testGenerationIsDeterministicAndContainsNoOwnerData() {
    let generator = SyntheticFixtureGenerator()

    let first = generator.manifest(seed: 0x5443)
    let second = generator.manifest(seed: 0x5443)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.schemaVersion, 1)
    XCTAssertEqual(first.algorithmVersion, "gate-zero-lcg-v1")
    XCTAssertEqual(first.ownerDataAccepted, false)
    XCTAssertEqual(first.timeZoneIdentifier, "Etc/UTC")
    XCTAssertEqual(first.identifiers.count, 4)
    XCTAssertEqual(Set(first.identifiers).count, 4)
  }
}
