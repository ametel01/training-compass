import Foundation
import XCTest

@testable import TrainingApplication

final class SleepEpisodesTests: XCTestCase {
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }

  private func date(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
    calendar.date(
      from: DateComponents(year: 2023, month: 11, day: day, hour: hour, minute: minute))!
  }

  private func sample(
    _ id: String,
    start: Date,
    end: Date,
    source: String = "com.watch",
    stage: HealthSleepStage = .asleep,
    sourceName: String = "Watch"
  ) -> HealthSleepSample {
    HealthSleepSample(
      id: id,
      startDate: start,
      endDate: end,
      stage: stage,
      provenance: .init(sourceName: sourceName, sourceBundleIdentifier: source))
  }

  func testPreferredSourceWinsOverlapWithoutSummingAlternatives() {
    let samples = [
      sample("phone", start: date(22), end: date(23, 30), source: "com.phone", sourceName: "Phone"),
      sample("watch", start: date(22, 30), end: date(6, day: 15), source: "com.watch")
    ]
    let projection = SleepEpisodeCalculator().calculate(
      samples: samples,
      preference: .init(orderedSourceIDs: ["bundle:com.watch", "bundle:com.phone"]),
      calendar: calendar)

    XCTAssertEqual(projection.episodes.count, 1)
    XCTAssertEqual(projection.episodes[0].source.id, "bundle:com.watch")
    XCTAssertEqual(projection.episodes[0].durationSeconds, 7.5 * 60 * 60, accuracy: 0.001)
    XCTAssertEqual(projection.episodes[0].alternativeSources.map(\.id), ["bundle:com.phone"])
    XCTAssertTrue(projection.explanation.exclusions.contains { $0.recordID == "phone" })
  }

  func testExactNinetyMinuteGapJoinsAndLongerEpisodeIsPrimary() {
    let samples = [
      sample("first", start: date(22), end: date(23)),
      sample("second", start: date(0, 30, day: 15), end: date(2, day: 15)),
      sample("nap", start: date(13, day: 15), end: date(14, day: 15))
    ]
    let projection = SleepEpisodeCalculator().calculate(samples: samples, calendar: calendar)

    XCTAssertEqual(projection.episodes.count, 2)
    XCTAssertEqual(
      projection.primarySleep(on: TrainingDate(year: 2023, month: 11, day: 15))?.intervals.map(
        \.id), ["first", "second"])
    XCTAssertEqual(
      projection.naps(on: TrainingDate(year: 2023, month: 11, day: 15)).map(\.kind), [.nap])
    XCTAssertEqual(
      projection.episodes.first?.wakeUpDate, TrainingDate(year: 2023, month: 11, day: 15))
  }

  func testGapOverNinetyMinutesDoesNotInventContinuity() {
    let samples = [
      sample("first", start: date(22), end: date(23)),
      sample("second", start: date(0, 31, day: 15), end: date(2, day: 15))
    ]
    let projection = SleepEpisodeCalculator().calculate(samples: samples, calendar: calendar)

    XCTAssertEqual(projection.episodes.count, 2)
    XCTAssertEqual(projection.episodes.map(\.durationSeconds), [60 * 60, 89 * 60])
  }

  func testStageFilteringAndSourceIncomparableIntervalsRemainSeparate() {
    let samples = [
      sample("awake", start: date(21), end: date(22), stage: .awake),
      HealthSleepSample(
        id: "unknown-1", startDate: date(22), endDate: date(23), provenance: .init()),
      HealthSleepSample(
        id: "unknown-2", startDate: date(23, 30), endDate: date(0, 30, day: 15), provenance: .init()
      )
    ]
    let projection = SleepEpisodeCalculator().calculate(samples: samples, calendar: calendar)

    XCTAssertEqual(projection.episodes.count, 2)
    XCTAssertEqual(projection.episodes.map { $0.source.isComparable }, [false, false])
    XCTAssertTrue(projection.explanation.exclusions.isEmpty)
  }

  func testOverlappingIncomparableSourcesRemainExplicitInsteadOfBeingArbitrated() {
    let samples = [
      HealthSleepSample(
        id: "unknown-a",
        startDate: date(22),
        endDate: date(1, day: 15),
        provenance: .init()),
      HealthSleepSample(
        id: "unknown-b",
        startDate: date(23),
        endDate: date(2, day: 15),
        provenance: .init())
    ]
    let projection = SleepEpisodeCalculator().calculate(samples: samples, calendar: calendar)

    XCTAssertEqual(projection.episodes.count, 2)
    XCTAssertTrue(projection.episodes.allSatisfy { !$0.source.isComparable })
    XCTAssertTrue(projection.explanation.exclusions.isEmpty)
  }

  func testSleepStatusAndTimezoneAreRetainedInExplanation() {
    var pacific = Calendar(identifier: .gregorian)
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let checkedAt = date(12, day: 15)
    let status = HealthStreamStatus(
      stream: .sleep,
      requested: true,
      authorization: .authorized,
      coverage: .available,
      mirroredContent: .available,
      lastSuccessfulCheck: checkedAt,
      failure: .init(code: "sleep-refresh-failed", occurredAt: checkedAt.addingTimeInterval(1)))
    let snapshot = HealthRecoveryEvidenceSnapshot(
      sleep: [sample("cross-midnight", start: date(23), end: date(1, day: 15))],
      statuses: [status])

    let projection = snapshot.sleepEpisodes(calendar: pacific)
    XCTAssertEqual(
      projection.episodes.first?.wakeUpDate, TrainingDate(year: 2023, month: 11, day: 14))
    XCTAssertEqual(projection.status?.failure?.code, "sleep-refresh-failed")
    XCTAssertTrue(
      projection.explanation.missingData.contains("Sleep stream failure: sleep-refresh-failed"))
    XCTAssertEqual(projection.explanation.lastReconciliation, checkedAt.ISO8601Format())
    XCTAssertEqual(
      projection.episodes.first?.explanation.lastReconciliation, checkedAt.ISO8601Format())
  }

  func testReplacementDeletionAndSourceChangeRecomputeWithoutRetainingContinuity() {
    let original = [
      sample("original", start: date(22), end: date(23), source: "com.watch")
    ]
    let replacement = [
      sample("replacement", start: date(22), end: date(23), source: "com.phone")
    ]
    let calculator = SleepEpisodeCalculator()
    let first = calculator.calculate(samples: original, calendar: calendar)
    let changed = calculator.calculate(samples: replacement, calendar: calendar)
    let deleted = calculator.calculate(samples: [], calendar: calendar)

    XCTAssertEqual(first.episodes.first?.intervals.map(\.id), ["original"])
    XCTAssertEqual(changed.episodes.first?.intervals.map(\.id), ["replacement"])
    XCTAssertEqual(changed.episodes.first?.source.id, "bundle:com.phone")
    XCTAssertTrue(deleted.episodes.isEmpty)
    XCTAssertTrue(deleted.explanation.missingData.contains("No usable asleep intervals"))
  }

  func testTieUsesEarliestEpisodeDeterministically() {
    let samples = [
      sample("later", start: date(10, day: 15), end: date(11, day: 15), source: "com.phone"),
      sample("earlier", start: date(8, day: 15), end: date(9, day: 15), source: "com.watch")
    ]
    let projection = SleepEpisodeCalculator().calculate(samples: samples, calendar: calendar)

    XCTAssertEqual(
      projection.primarySleep(on: TrainingDate(year: 2023, month: 11, day: 15))?.id,
      "sleep:2023-11-15:earlier")
  }

  func testPreferenceCanBeChangedAndSnapshotExposesAvailableSources() {
    let samples = [
      sample("phone", start: date(22), end: date(23), source: "com.phone", sourceName: "Phone"),
      sample("watch", start: date(22), end: date(23), source: "com.watch")
    ]
    let snapshot = HealthRecoveryEvidenceSnapshot(sleep: samples)
    XCTAssertEqual(
      snapshot.availableSleepSources.map(\.id), ["bundle:com.phone", "bundle:com.watch"])
    let preference = SleepSourcePreference(orderedSourceIDs: [
      "bundle:com.watch", "bundle:com.phone"
    ])
    XCTAssertEqual(
      preference.moving(sourceID: "bundle:com.phone", to: 0).orderedSourceIDs.first,
      "bundle:com.phone")
    XCTAssertEqual(
      snapshot.sleepEpisodes(preference: preference, calendar: calendar).episodes.first?.source.id,
      "bundle:com.watch")
  }

  func testMidpointUsesEpisodeEnvelopeWhileDurationUsesAsleepUnion() throws {
    let samples = [
      sample("one", start: date(22), end: date(23)),
      sample("overlap", start: date(22, 30), end: date(23, 30))
    ]
    let episode = try XCTUnwrap(
      SleepEpisodeCalculator().calculate(samples: samples, calendar: calendar).episodes.first)

    XCTAssertEqual(episode.durationSeconds, 1.5 * 60 * 60, accuracy: 0.001)
    XCTAssertEqual(episode.midpoint, date(22, 45))
  }
}
