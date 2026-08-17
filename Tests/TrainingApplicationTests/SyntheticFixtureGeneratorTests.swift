import Foundation
@testable import TrainingApplication
import XCTest

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

    func testVerificationEnvelopeCoversTheResolvedScaleWithoutOwnerData() {
        let envelope = SyntheticFixtureGenerator().verificationEnvelope(seed: 21571)

        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.algorithmVersion, "verification-envelope-lcg-v1")
        XCTAssertEqual(envelope.seed, 21571)
        XCTAssertFalse(envelope.ownerDataAccepted)
        XCTAssertEqual(envelope.coverageYears, 15)
        XCTAssertEqual(envelope.healthWorkouts, 25000)
        XCTAssertEqual(envelope.heartRateSamples, 10_000_000)
        XCTAssertEqual(envelope.sleepIntervals, 250_000)
        XCTAssertEqual(envelope.restingHeartRateSamples, 50000)
        XCTAssertEqual(envelope.hrvSamples, 100_000)
        XCTAssertEqual(envelope.trainingCycles, 500)
        XCTAssertEqual(envelope.sessions, 10000)
        XCTAssertEqual(envelope.sets, 250_000)
        XCTAssertEqual(envelope.routes, 2000)
        XCTAssertEqual(envelope.routeRetainedPoints, 2000)
        XCTAssertEqual(envelope.identifierSamples.count, 4)
        XCTAssertEqual(Set(envelope.identifierSamples).count, 4)
        XCTAssertTrue(envelope.matchesResolvedScale)
    }

    func testVerificationEnvelopeIsDeterministicForTheSameSeed() {
        let generator = SyntheticFixtureGenerator()

        XCTAssertEqual(
            generator.verificationEnvelope(seed: 0x5443),
            generator.verificationEnvelope(seed: 0x5443),
        )
    }
}
