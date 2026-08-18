import TrainingDomain
import XCTest

@testable import TrainingInsights

final class CardioProgressTests: XCTestCase {
  func testDriftDropsFirstTenMinutesThenSplitsRemainingElapsedTime() throws {
    let record = cardio(
      "run",
      duration: 20 * 60,
      distance: 3_000,
      samples: samples([
        (10 * 60, 140),
        (11 * 60, 140),
        (12 * 60, 140),
        (13 * 60, 140),
        (14 * 60, 140),
        (15 * 60, 147),
        (16 * 60, 147),
        (17 * 60, 147),
        (18 * 60, 147),
        (19 * 60, 147),
        (20 * 60, 147),
      ]),
    )

    let drift = try XCTUnwrap(
      CardioProgressCalculator().calculate(records: [record]).heartRateDrifts.first)

    XCTAssertEqual(try XCTUnwrap(drift.firstHalfAverageBPM), 140, accuracy: 0.000_001)
    XCTAssertEqual(try XCTUnwrap(drift.secondHalfAverageBPM), 147, accuracy: 0.000_001)
    XCTAssertEqual(try XCTUnwrap(drift.driftPercent), 5, accuracy: 0.000_001)
  }

  func testDriftClipsIntervalsAtTheHalfBoundaryAndTimeWeightsBothHalves() throws {
    let record = cardio(
      "run",
      duration: 14 * 60,
      distance: 2_000,
      samples: samples([
        (10 * 60, 100),
        (11 * 60, 120),
        (12 * 60, 120),
        (13 * 60, 140),
        (14 * 60, 140),
      ]),
    )

    let drift = try XCTUnwrap(
      CardioProgressCalculator().calculate(records: [record]).heartRateDrifts.first)

    XCTAssertEqual(try XCTUnwrap(drift.firstHalfAverageBPM), 110, accuracy: 0.000_001)
    XCTAssertEqual(try XCTUnwrap(drift.secondHalfAverageBPM), 130, accuracy: 0.000_001)
    XCTAssertEqual(try XCTUnwrap(drift.driftPercent), 18.181_818, accuracy: 0.000_01)
  }

  func testDriftIsUnavailableForShortOrSparseSessions() throws {
    let short = cardio("short", duration: 10 * 60, distance: 1_000, samples: [])
    let sparse = cardio(
      "sparse",
      duration: 20 * 60,
      distance: 2_000,
      samples: samples([(10 * 60, 120), (11 * 60, 120)]),
    )

    let result = CardioProgressCalculator().calculate(records: [short, sparse])

    XCTAssertEqual(
      result.heartRateDrifts.first(where: { $0.id == "short" })?.availability,
      .unavailable(reason: "Session is not longer than 10 minutes"),
    )
    XCTAssertEqual(
      result.heartRateDrifts.first(where: { $0.id == "sparse" })?.availability,
      .unavailable(reason: "Heart-rate coverage is below 80% in one or both halves"),
    )
  }

  func testEfficiencyUsesDistancePerHeartbeatAndSameActivityBaseline() throws {
    let latest = cardio(
      "latest", activity: "Running", start: 3_000, duration: 600, distance: 1_500,
      samples: constantSamples(bpm: 150, duration: 600, base: 3_000),
    )
    let priorRun = cardio(
      "prior-run", activity: "Running", start: 2_000, duration: 600, distance: 1_400,
      samples: constantSamples(bpm: 140, duration: 600, base: 2_000),
    )
    let ride = cardio(
      "ride", activity: "Cycling", start: 1_000, duration: 600, distance: 5_000,
      samples: constantSamples(bpm: 140, duration: 600, base: 1_000),
    )

    let efficiency = CardioProgressCalculator().calculate(records: [ride, latest, priorRun])
      .efficiency

    XCTAssertEqual(efficiency.activityType, "Running")
    XCTAssertEqual(try XCTUnwrap(efficiency.latestMetersPerHeartbeat), 1, accuracy: 0.000_001)
    XCTAssertEqual(try XCTUnwrap(efficiency.baselineMetersPerHeartbeat), 1, accuracy: 0.000_001)
    XCTAssertEqual(efficiency.direction, .unchanged)
    XCTAssertEqual(efficiency.comparisonCount, 1)
  }

  private func cardio(
    _ id: String,
    activity: String = "Running",
    start: Double = 0,
    duration: Double,
    distance: Double?,
    samples: [HeartRateSample],
  ) -> CardioWorkoutRecord {
    CardioWorkoutRecord(
      id: id,
      localDate: TrainingDate(year: 2026, month: 8, day: 18),
      activityType: activity,
      startDate: start,
      endDate: start + duration,
      distanceMeters: distance,
      heartRateSamples: samples,
    )
  }

  private func samples(
    _ values: [(offset: Double, bpm: Double)],
    base: Double = 0,
  ) -> [HeartRateSample] {
    values.enumerated().map { index, value in
      HeartRateSample(
        id: "sample-\(base)-\(index)",
        startDate: base + value.offset,
        endDate: base + value.offset,
        beatsPerMinute: value.bpm,
        source: "Watch",
      )
    }
  }

  private func constantSamples(
    bpm: Double,
    duration: Double,
    base: Double,
  ) -> [HeartRateSample] {
    samples(
      stride(from: 0.0, through: duration, by: 60).map { ($0, bpm) },
      base: base,
    )
  }
}
