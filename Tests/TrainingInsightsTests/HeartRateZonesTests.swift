import Foundation
import TrainingDomain
@testable import TrainingInsights
import XCTest

final class HeartRateZonesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testEveryFixedBandBoundaryUsesFullPrecision() throws {
        let maximum = try MaximumHeartRate(beatsPerMinute: 200)
        let samples = [
            sample("below", offset: 0, bpm: 99.999),
            sample("zone1-lower", offset: 10, bpm: 100),
            sample("zone1-upper", offset: 20, bpm: 119.999),
            sample("zone2-lower", offset: 30, bpm: 120),
            sample("zone2-upper", offset: 40, bpm: 139.999),
            sample("zone3-lower", offset: 50, bpm: 140),
            sample("zone3-upper", offset: 60, bpm: 159.999),
            sample("zone4-lower", offset: 70, bpm: 160),
            sample("zone4-upper", offset: 80, bpm: 179.999),
            sample("zone5-lower", offset: 90, bpm: 180),
            sample("zone5-upper", offset: 100, bpm: 200),
        ]

        let result = HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(110).timeIntervalSince1970,
            samples: samples,
            maximumHeartRate: maximum,
        )

        XCTAssertEqual(result.state, .available)
        XCTAssertEqual(result.zoneDurations[.below50], 10)
        XCTAssertEqual(result.zoneDurations[.zone1], 20)
        XCTAssertEqual(result.zoneDurations[.zone2], 20)
        XCTAssertEqual(result.zoneDurations[.zone3], 20)
        XCTAssertEqual(result.zoneDurations[.zone4], 20)
        XCTAssertEqual(result.zoneDurations[.zone5], 20)
        XCTAssertEqual(result.coveredSeconds, 110, accuracy: 0.000_000_1)
        XCTAssertEqual(result.unavailableSeconds, 0, accuracy: 0.000_000_1)
        XCTAssertEqual(result.sourceSummaries.map(\.source), ["Watch"])
        XCTAssertEqual(result.sourceSummaries.first?.sampleIDs.count, samples.count)
    }

    func testShortGapBelongsToEarlierSampleAtExactlySixtySeconds() throws {
        let result = try HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(100).timeIntervalSince1970,
            samples: [
                sample("first", offset: 10, duration: 10, bpm: 90),
                sample("second", offset: 80, duration: 10, bpm: 180),
            ],
            maximumHeartRate: MaximumHeartRate(beatsPerMinute: 200),
        )

        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.below50]), 70, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.zone5]), 10, accuracy: 0.000_000_1)
        XCTAssertEqual(result.coveredSeconds, 80, accuracy: 0.000_000_1)
        XCTAssertEqual(result.unavailableSeconds, 20, accuracy: 0.000_000_1)
    }

    func testLongGapAndBothWorkoutEdgesRemainUnavailable() throws {
        let result = try HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(200).timeIntervalSince1970,
            samples: [
                sample("first", offset: 20, duration: 10, bpm: 90),
                sample("second", offset: 91, duration: 10, bpm: 180),
            ],
            maximumHeartRate: MaximumHeartRate(beatsPerMinute: 200),
        )

        XCTAssertEqual(result.coveredSeconds, 20, accuracy: 0.000_000_1)
        XCTAssertEqual(result.unavailableSeconds, 180, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.below50]), 10, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.zone5]), 10, accuracy: 0.000_000_1)
    }

    func testMissingMaximumRateLeavesProjectionUnavailableAndNeverBelowZone() {
        let result = HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(10).timeIntervalSince1970,
            samples: [sample("raw", offset: 0, bpm: 1)],
            maximumHeartRate: nil,
        )

        XCTAssertEqual(result.state, .unavailable(reason: "Maximum heart rate is not configured"))
        XCTAssertEqual(result.coveredSeconds, 0)
        XCTAssertTrue(result.zoneDurations.isEmpty)
    }

    func testChangingMaximumRateReprojectsUnchangedSamples() throws {
        let samples = [sample("sample", offset: 0, duration: 10, bpm: 100)]
        let calculator = HeartRateZoneCalculator()
        let at200 = try calculator.calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(10).timeIntervalSince1970,
            samples: samples,
            maximumHeartRate: MaximumHeartRate(beatsPerMinute: 200),
        )
        let at160 = try calculator.calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(10).timeIntervalSince1970,
            samples: samples,
            maximumHeartRate: MaximumHeartRate(beatsPerMinute: 160),
        )

        XCTAssertEqual(at200.zoneDurations[.zone1], 10)
        XCTAssertEqual(at160.zoneDurations[.zone2], 10)
        XCTAssertEqual(samples.first?.beatsPerMinute, 100)
        XCTAssertEqual(at160.maximumHeartRateBPM, 160)
    }

    func testAboveMaximumIsCoveredButNotSilentlyCountedAsBelowZone() throws {
        let result = try HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(10).timeIntervalSince1970,
            samples: [sample("above", offset: 0, duration: 10, bpm: 201)],
            maximumHeartRate: MaximumHeartRate(beatsPerMinute: 200),
        )

        XCTAssertEqual(result.coveredSeconds, 10)
        XCTAssertEqual(result.unclassifiedSeconds, 10)
        XCTAssertNil(result.zoneDurations[.below50])
        XCTAssertNil(result.zoneDurations[.zone5])
    }

    private func sample(
        _ id: String,
        offset: TimeInterval,
        duration: TimeInterval = 10,
        bpm: Double,
    ) -> HeartRateSample {
        HeartRateSample(
            id: id,
            startDate: start.addingTimeInterval(offset).timeIntervalSince1970,
            endDate: start.addingTimeInterval(offset + duration).timeIntervalSince1970,
            beatsPerMinute: bpm,
            source: "Watch",
        )
    }
}
