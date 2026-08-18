import Foundation
import TrainingDomain
import XCTest

@testable import TrainingInsights

final class HeartRateZonesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testAppleWatchBoundariesCreateFiveContinuousZones() throws {
        let samples = [
            sample("zone1-lower", offset: 0, bpm: 64),
            sample("zone1-upper", offset: 10, bpm: 130.999),
            sample("zone2-lower", offset: 20, bpm: 131),
            sample("zone2-upper", offset: 30, bpm: 141.999),
            sample("zone3-lower", offset: 40, bpm: 142),
            sample("zone3-upper", offset: 50, bpm: 152.999),
            sample("zone4-lower", offset: 60, bpm: 153),
            sample("zone4-upper", offset: 70, bpm: 164.999),
            sample("zone5-lower", offset: 80, bpm: 165),
            sample("zone5-open-ended", offset: 90, bpm: 200),
        ]

        let result = HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(100).timeIntervalSince1970,
            samples: samples,
            zoneBoundaries: try watchBoundaries(),
        )

        XCTAssertEqual(result.state, .available)
        for zone in RollingWorkoutZone.allCases {
            XCTAssertEqual(result.zoneDurations[zone], 20)
        }
        XCTAssertEqual(result.coveredSeconds, 100, accuracy: 0.000_000_1)
        XCTAssertEqual(result.unavailableSeconds, 0, accuracy: 0.000_000_1)
        XCTAssertEqual(result.sourceSummaries.map(\.source), ["Watch"])
        XCTAssertEqual(result.sourceSummaries.first?.sampleIDs.count, samples.count)
    }

    func testShortGapBelongsToEarlierSampleAtExactlySixtySeconds() throws {
        let result = HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(100).timeIntervalSince1970,
            samples: [
                sample("first", offset: 10, duration: 10, bpm: 100),
                sample("second", offset: 80, duration: 10, bpm: 165),
            ],
            zoneBoundaries: try watchBoundaries(),
        )

        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.zone1]), 70, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.zone5]), 10, accuracy: 0.000_000_1)
        XCTAssertEqual(result.coveredSeconds, 80, accuracy: 0.000_000_1)
        XCTAssertEqual(result.unavailableSeconds, 20, accuracy: 0.000_000_1)
    }

    func testInstantaneousHealthSamplesOwnTimeUntilTheNextNearbySample() throws {
        let result = HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(30).timeIntervalSince1970,
            samples: [
                sample("first", offset: 0, duration: 0, bpm: 100),
                sample("second", offset: 10, duration: 0, bpm: 142),
                sample("third", offset: 20, duration: 0, bpm: 165),
            ],
            zoneBoundaries: try watchBoundaries(),
        )

        XCTAssertEqual(result.zoneDurations[.zone1], 10)
        XCTAssertEqual(result.zoneDurations[.zone3], 10)
        XCTAssertNil(result.zoneDurations[.zone5])
        XCTAssertEqual(result.coveredSeconds, 20)
        XCTAssertEqual(result.unavailableSeconds, 10)
    }

    func testLongGapAndBothWorkoutEdgesRemainUnavailable() throws {
        let result = HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(200).timeIntervalSince1970,
            samples: [
                sample("first", offset: 20, duration: 10, bpm: 100),
                sample("second", offset: 91, duration: 10, bpm: 165),
            ],
            zoneBoundaries: try watchBoundaries(),
        )

        XCTAssertEqual(result.coveredSeconds, 20, accuracy: 0.000_000_1)
        XCTAssertEqual(result.unavailableSeconds, 180, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.zone1]), 10, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(result.zoneDurations[.zone5]), 10, accuracy: 0.000_000_1)
    }

    func testMissingBoundariesLeaveProjectionUnavailable() {
        let result = HeartRateZoneCalculator().calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(10).timeIntervalSince1970,
            samples: [sample("raw", offset: 0, bpm: 100)],
            zoneBoundaries: nil,
        )

        XCTAssertEqual(
            result.state,
            .unavailable(reason: "Heart-rate zone boundaries are not configured"),
        )
        XCTAssertEqual(result.coveredSeconds, 0)
        XCTAssertTrue(result.zoneDurations.isEmpty)
    }

    func testChangingBoundariesReprojectsUnchangedSamples() throws {
        let samples = [sample("sample", offset: 0, duration: 10, bpm: 140)]
        let calculator = HeartRateZoneCalculator()
        let watch = calculator.calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(10).timeIntervalSince1970,
            samples: samples,
            zoneBoundaries: try watchBoundaries(),
        )
        let alternate = calculator.calculate(
            workoutStartDate: start.timeIntervalSince1970,
            workoutEndDate: start.addingTimeInterval(10).timeIntervalSince1970,
            samples: samples,
            zoneBoundaries: try boundaries(
                resting: 50, maximum: 200, zone2: 100, zone3: 120, zone4: 140, zone5: 160,
            ),
        )

        XCTAssertEqual(watch.zoneDurations[.zone2], 10)
        XCTAssertEqual(alternate.zoneDurations[.zone4], 10)
        XCTAssertEqual(samples.first?.beatsPerMinute, 140)
        XCTAssertEqual(watch.maximumHeartRateBPM, 177)
    }

    func testWatchRangeDescriptionsMatchOwnerSuppliedProfile() throws {
        let boundaries = try watchBoundaries()

        XCTAssertEqual(boundaries.rangeDescription(for: .zone1), "≤130 bpm")
        XCTAssertEqual(boundaries.rangeDescription(for: .zone2), "131–141 bpm")
        XCTAssertEqual(boundaries.rangeDescription(for: .zone3), "142–152 bpm")
        XCTAssertEqual(boundaries.rangeDescription(for: .zone4), "153–164 bpm")
        XCTAssertEqual(boundaries.rangeDescription(for: .zone5), "≥165 bpm")
    }

    func testZoneStartsMustBeWholeBPMValues() {
        XCTAssertThrowsError(
            try boundaries(
                resting: 64, maximum: 177, zone2: 131.5, zone3: 142, zone4: 153, zone5: 165,
            ),
        ) { error in
            XCTAssertEqual(
                error as? HeartRateZoneBoundaryValidationError,
                .boundariesMustBeWholeBPM,
            )
        }
    }

    private func watchBoundaries() throws -> HeartRateZoneBoundaries {
        try boundaries(resting: 64, maximum: 177, zone2: 131, zone3: 142, zone4: 153, zone5: 165)
    }

    private func boundaries(
        resting: Double,
        maximum: Double,
        zone2: Double,
        zone3: Double,
        zone4: Double,
        zone5: Double,
    ) throws -> HeartRateZoneBoundaries {
        try HeartRateZoneBoundaries(
            restingHeartRateBPM: resting,
            maximumHeartRate: MaximumHeartRate(beatsPerMinute: maximum),
            zone2MinimumBPM: zone2,
            zone3MinimumBPM: zone3,
            zone4MinimumBPM: zone4,
            zone5MinimumBPM: zone5,
        )
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
