import Foundation
@testable import TrainingApplication
import XCTest

/// Cross-feature approval coverage for issue #38. The focused stream, sleep,
/// baseline, and guidance tests remain useful on their own; this seam verifies
/// that the owner-visible Recovery Evidence milestone keeps those contracts
/// together without turning measurements into a training decision.
final class RecoveryEvidenceAcceptanceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let asOf = TrainingDate(year: 2026, month: 8, day: 29)

    func testRecoveryEvidenceApprovalEnvelopeIsSourceAwareCurrentAndExplained() {
        let watch = HealthRecoverySampleProvenance(
            sourceName: "Watch", sourceBundleIdentifier: "com.example.watch",
        )
        let ring = HealthRecoverySampleProvenance(
            sourceName: "Ring", sourceBundleIdentifier: "com.example.ring",
        )
        var sleep = (1 ... 14).map { day in
            HealthSleepSample(
                id: "sleep-\(day)", startDate: date(day, 1), endDate: date(day, 7), provenance: watch,
            )
        }
        // Exact 90-minute gap joins; a 91-minute gap stays a separate episode.
        sleep += [
            HealthSleepSample(
                id: "joined-a", startDate: date(27, 1), endDate: date(27, 2), provenance: watch,
            ),
            HealthSleepSample(
                id: "joined-b", startDate: date(27, 3, 30), endDate: date(27, 4, 30), provenance: watch,
            ),
            HealthSleepSample(
                id: "split-a", startDate: date(28, 1), endDate: date(28, 2), provenance: watch,
            ),
            HealthSleepSample(
                id: "split-b", startDate: date(28, 3, 31), endDate: date(28, 4, 31), provenance: watch,
            ),
            HealthSleepSample(
                id: "sleep-current", startDate: date(29, 1), endDate: date(29, 9), provenance: watch,
            ),
            // Overlap is represented once and changes only when the owner changes
            // the preferred source order.
            HealthSleepSample(
                id: "ring-current", startDate: date(29, 1, 30), endDate: date(29, 8), provenance: ring,
            ),
            HealthSleepSample(
                id: "nap-current", startDate: date(29, 13), endDate: date(29, 14), provenance: watch,
            ),
        ]

        let statuses = [
            status(.sleep), status(.restingHeartRate), status(.heartRateVariability),
        ]
        let snapshot = HealthRecoveryEvidenceSnapshot(
            sleep: sleep,
            restingHeartRate: (1 ... 14).map { resting("rest-\($0)", day: $0, value: 50 + Double($0)) }
                + [resting("rest-current", day: 29, value: 70)],
            heartRateVariability: (1 ... 14).map { hrv("hrv-\($0)", day: $0, value: 30 + Double($0)) }
                + [hrv("hrv-current", day: 29, value: 60)],
            statuses: statuses,
        )

        let defaultSleep = snapshot.sleepEpisodes(calendar: calendar)
        XCTAssertEqual(defaultSleep.primarySleep(on: asOf)?.source.id, "bundle:com.example.ring")
        XCTAssertEqual(
            defaultSleep.primarySleep(on: asOf)?.alternativeSources.map(\.id),
            ["bundle:com.example.watch"],
        )
        XCTAssertEqual(defaultSleep.primarySleep(on: asOf)?.durationSeconds, 6.5 * 60 * 60)
        XCTAssertTrue(defaultSleep.episodes.contains { $0.kind == .nap && $0.wakeUpDate == asOf })
        XCTAssertEqual(defaultSleep.episodes(on: TrainingDate(year: 2026, month: 8, day: 27)).count, 1)
        XCTAssertTrue(
            defaultSleep.episodes.contains {
                $0.intervals.map(\.id).contains("joined-a") && $0.intervals.map(\.id).contains("joined-b")
            },
        )
        let splitEpisodes = defaultSleep.episodes(on: TrainingDate(year: 2026, month: 8, day: 28))
        XCTAssertEqual(splitEpisodes.count, 2)
        XCTAssertTrue(splitEpisodes.contains { $0.intervals.map(\.id).contains("split-a") })
        XCTAssertTrue(splitEpisodes.contains { $0.intervals.map(\.id).contains("split-b") })

        let preferredWatch = snapshot.sleepEpisodes(
            preference: SleepSourcePreference(orderedSourceIDs: [
                "bundle:com.example.watch", "bundle:com.example.ring",
            ]),
            calendar: calendar,
        )
        XCTAssertEqual(preferredWatch.primarySleep(on: asOf)?.source.id, "bundle:com.example.watch")

        let observations = snapshot.dailyObservations(calendar: calendar, now: date(29, 12))
        XCTAssertEqual(observations.restingHeartRate.last?.date, asOf)
        XCTAssertEqual(observations.heartRateVariability.last?.date, asOf)
        XCTAssertEqual(observations.heartRateVariability.last?.value, 60)

        let baselines = snapshot.personalRecoveryBaselines(
            preference: SleepSourcePreference(orderedSourceIDs: ["bundle:com.example.watch"]),
            calendar: calendar,
            asOfDate: asOf,
            now: date(29, 12),
        )
        XCTAssertEqual(baselines.baselines.count, PersonalRecoveryBaselineMetric.allCases.count)
        XCTAssertTrue(baselines.baselines.allSatisfy(\.isEstablished))
        XCTAssertTrue(baselines.baseline(for: .primarySleepDuration)?.currentObservation?.date == asOf)
        XCTAssertTrue(
            baselines.baseline(for: .primarySleepDuration)?.explanation.sourceCoverage.contains(
                "Naps are excluded",
            )
                == true,
        )

        let guidance = snapshot.recoveryGuidance(
            preference: SleepSourcePreference(orderedSourceIDs: ["bundle:com.example.watch"]),
            calendar: calendar,
            asOfDate: asOf,
            now: date(29, 12),
        )
        XCTAssertTrue(guidance.isAvailable)
        XCTAssertNotNil(guidance.prompt)
        XCTAssertEqual(
            guidance.establishedFamilies, [.primarySleep, .restingHeartRate, .heartRateVariability],
        )
        XCTAssertFalse(guidance.summary?.contains("do not move together") == true)
        XCTAssertTrue(guidance.summary?.contains("Resting heart rate") == true)
        XCTAssertTrue(guidance.summary?.contains("HRV SDNN") == true)

        let explanations =
            defaultSleep.episodes.map(\.explanation)
                + observations.restingHeartRate.map(\.explanation)
                + observations.heartRateVariability.map(\.explanation)
                + baselines.baselines.map(\.explanation)
                + [guidance.explanation]
        for explanation in explanations {
            assertComplete(explanation)
        }

        let displayedLanguage = (explanations.map(\.text) + [guidance.prompt ?? ""]).joined(
            separator: " ",
        ).lowercased()
        for forbidden in [
            "score", "diagnosis", "medical", "injury risk", "causal", "performance prediction",
            "warning threshold", "training prescription",
        ] {
            XCTAssertFalse(
                displayedLanguage.contains(forbidden), "Forbidden Recovery language: \(forbidden)",
            )
        }
    }

    func testBaselineThresholdAndGuidanceWithholdingRemainDeterministic() {
        let forming = PersonalRecoveryBaselineCalculator().calculate(
            metric: .restingHeartRate,
            observations: (1 ... 13).map { observation("forming-\($0)", day: $0, value: 50) },
            asOfDate: asOf,
        )
        XCTAssertFalse(forming.isEstablished)
        XCTAssertEqual(forming.validObservationDays, 13)

        let established = PersonalRecoveryBaselineCalculator().calculate(
            metric: .restingHeartRate,
            observations: (1 ... 14).map { observation("established-\($0)", day: $0, value: 50) },
            asOfDate: asOf,
        )
        XCTAssertTrue(established.isEstablished)
        XCTAssertEqual(established.validObservationDays, 14)
        XCTAssertEqual(established.comparison, .unavailable)

        let projection = PersonalRecoveryBaselineProjection(
            baselines: [established], explanation: established.explanation,
        )
        let guidance = RecoveryGuidanceCalculator().calculate(baselines: projection, asOfDate: asOf)
        XCTAssertFalse(guidance.isAvailable)
        XCTAssertEqual(guidance.suppressionReason, .notEnoughEstablishedFamilies)
        XCTAssertNil(guidance.prompt)
        assertComplete(guidance.explanation)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute),
        )!
    }

    private func status(_ stream: HealthSyncStream) -> HealthStreamStatus {
        HealthStreamStatus(
            stream: stream,
            requested: true,
            authorization: .authorized,
            coverage: .available,
            mirroredContent: .available,
            reconciliation: .idle,
            lastSuccessfulCheck: date(29, 12),
        )
    }

    private func resting(_ id: String, day: Int, value: Double) -> HealthRestingHeartRateSample {
        HealthRestingHeartRateSample(
            id: id,
            date: date(day, 8),
            beatsPerMinute: value,
            provenance: .init(sourceName: "Watch", sourceBundleIdentifier: "com.example.watch"),
        )
    }

    private func hrv(_ id: String, day: Int, value: Double) -> HealthHRVSDNNSample {
        HealthHRVSDNNSample(
            id: id,
            date: date(day, 8),
            milliseconds: value,
            provenance: .init(sourceName: "Watch", sourceBundleIdentifier: "com.example.watch"),
        )
    }

    private func observation(_ id: String, day: Int, value: Double)
        -> PersonalRecoveryBaselineObservation
    {
        PersonalRecoveryBaselineObservation(
            id: id,
            date: TrainingDate(year: 2026, month: 8, day: day),
            value: value,
            sourceID: "bundle:com.example.watch",
            sourceName: "Watch",
            sourceIsComparable: true,
            includedRecordIDs: [id],
            sourceCoverage: "Health history available",
            lastReconciliation: "2026-08-29T12:00:00Z",
            isCurrent: false,
        )
    }

    private func assertComplete(
        _ explanation: InsightExplanation,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertFalse(explanation.dateRange.isEmpty, file: file, line: line)
        XCTAssertFalse(explanation.sourceState.isEmpty, file: file, line: line)
        XCTAssertFalse(explanation.sourceCoverage.isEmpty, file: file, line: line)
        XCTAssertFalse(explanation.calculationRule.isEmpty, file: file, line: line)
        XCTAssertFalse(explanation.comparisonBaseline?.isEmpty ?? true, file: file, line: line)
        XCTAssertNotNil(explanation.lastReconciliation, file: file, line: line)
        XCTAssertTrue(explanation.text.contains("Dates:"), file: file, line: line)
        XCTAssertTrue(explanation.text.contains("Coverage:"), file: file, line: line)
        XCTAssertTrue(explanation.text.contains("Comparison baseline:"), file: file, line: line)
        XCTAssertTrue(explanation.text.contains("Missing data:"), file: file, line: line)
        XCTAssertTrue(explanation.text.contains("Exclusions:"), file: file, line: line)
        XCTAssertTrue(explanation.text.contains("Last reconciliation:"), file: file, line: line)
    }
}
