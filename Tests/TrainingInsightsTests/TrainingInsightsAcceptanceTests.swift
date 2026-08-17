import TrainingDomain
import XCTest

@testable import TrainingInsights

/// Cross-feature approval coverage for issue #32. The individual calculators
/// remain independently tested; this seam verifies that their owner-facing
/// projections share the explanation and neutral-language contract.
final class TrainingInsightsAcceptanceTests: XCTestCase {
  func testAllDisplayedInsightFamiliesRemainExplainedAndNeutral() throws {
    let progress = E1RMProgressCalculator().calculate(
      from: [e1RMSession()],
      selectedLiftID: "squat",
      asOfDate: TrainingDate(year: 2026, month: 8, day: 15))
    let today = TrainingDate(year: 2026, month: 8, day: 15)
    let rolling = RollingWorkoutOverviewCalculator().calculate(
      records: [
        RollingWorkoutRecord(
          id: "workout-current", localDate: today, activityType: "Running",
          durationSeconds: 1_800, zoneTimes: .available([.zone2: 600])),
        RollingWorkoutRecord(
          id: "workout-baseline", localDate: today.adding(days: -7), activityType: "Cycling",
          durationSeconds: 900, zoneTimes: .unavailable(reason: "Samples unavailable"))
      ],
      asOf: today,
      coverage: .complete(lastReconciliation: "health-check"))
    let zone = HeartRateZoneCalculator().calculate(
      workoutStartDate: 1_000,
      workoutEndDate: 1_200,
      samples: [
        HeartRateSample(
          id: "heart-rate-1", startDate: 1_020, endDate: 1_080, beatsPerMinute: 140,
          source: "Watch"),
        HeartRateSample(
          id: "heart-rate-2", startDate: 1_150, endDate: 1_170, beatsPerMinute: 180,
          source: "Watch")
      ],
      maximumHeartRate: try MaximumHeartRate(beatsPerMinute: 200))
    let running = RunningPerformanceCalculator().calculate(
      records: [
        runningRecord(
          id: "run-reference", date: today, startDate: 2_000, importedAt: 20,
          duration: 1_800, distance: 5_000),
        runningRecord(
          id: "run-prior", date: today.adding(days: -1), startDate: 1_000, importedAt: 10,
          duration: 1_900, distance: 5_000)
      ],
      asOf: today,
      sourceCoverage: "Health Workouts: available",
      lastReconciliation: "health-check",
      excludedRunIDs: ["run-prior"])

    assertComplete(progress.explanation)
    assertComplete(rolling.workoutCount.explanation)
    assertComplete(rolling.totalDuration.explanation)
    for activity in rolling.activityTypes {
      assertComplete(activity.metric.explanation)
    }
    for metric in rolling.zoneMetrics {
      assertComplete(metric.explanation)
    }
    assertComplete(zone.explanation)
    for run in running.runs {
      assertComplete(run.explanation)
    }
    assertComplete(running.volume.count.explanation)
    assertComplete(running.volume.availableDuration.explanation)
    assertComplete(running.volume.availableDistance.explanation)
    assertComplete(try XCTUnwrap(running.comparison).explanation)

    XCTAssertEqual(zone.explanation.includedRecordIDs, ["heart-rate-1", "heart-rate-2"])
    XCTAssertTrue(zone.explanation.configuration?.contains("200") == true)
    XCTAssertTrue(
      running.comparison?.explanation.exclusions.contains {
        $0.recordID == "run-prior" && $0.reason == "Running Comparison Exclusion"
      } == true)
    XCTAssertEqual(Set(running.runs.map(\.id)).count, running.runs.count)

    let displayedLanguage = [
      progress.explanation.text,
      rolling.workoutCount.explanation.text,
      zone.explanation.text,
      running.runs.map(\.explanation.text).joined(separator: " "),
      running.comparison?.explanation.text ?? ""
    ].joined(separator: " ").lowercased()
    for forbidden in [
      "training-load score", "personal record", "goal", "fitness claim", "inferred effort",
      "race prediction", "causal claim", "recovery verdict", "automatic prescription"
    ] {
      XCTAssertFalse(displayedLanguage.contains(forbidden), "Forbidden language: \(forbidden)")
    }
  }

  func testHeartRateConfigurationReprojectsWithoutMutatingSamples() throws {
    let samples = [
      HeartRateSample(
        id: "sample", startDate: 1_000, endDate: 1_100, beatsPerMinute: 100, source: "Watch")
    ]
    let calculator = HeartRateZoneCalculator()
    let at200 = calculator.calculate(
      workoutStartDate: 1_000, workoutEndDate: 1_100, samples: samples,
      maximumHeartRate: try MaximumHeartRate(beatsPerMinute: 200))
    let at160 = calculator.calculate(
      workoutStartDate: 1_000, workoutEndDate: 1_100, samples: samples,
      maximumHeartRate: try MaximumHeartRate(beatsPerMinute: 160))

    XCTAssertEqual(at200.zoneDurations[.zone1], 100)
    XCTAssertEqual(at160.zoneDurations[.zone2], 100)
    XCTAssertEqual(samples.first?.beatsPerMinute, 100)
    XCTAssertEqual(at200.explanation.includedRecordIDs, at160.explanation.includedRecordIDs)
    XCTAssertNotEqual(at200.explanation.configuration, at160.explanation.configuration)
  }

  private func assertComplete(
    _ explanation: InsightExplanation, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertFalse(explanation.dateRange.isEmpty, file: file, line: line)
    XCTAssertFalse(explanation.sourceCoverage.isEmpty, file: file, line: line)
    XCTAssertFalse(explanation.calculationRule.isEmpty, file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Included records:"), file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Dates:"), file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Coverage:"), file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Comparison baseline:"), file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Missing data:"), file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Exclusions:"), file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Configuration:"), file: file, line: line)
    XCTAssertTrue(explanation.text.contains("Last reconciliation:"), file: file, line: line)
  }

  private func e1RMSession() -> E1RMSessionRecord {
    E1RMSessionRecord(
      cycleID: "cycle", cycleState: .completed, weekID: "week", weekKind: .week1,
      session: TrainingCycleSession(
        id: "session", intendedDate: TrainingDate(year: 2026, month: 8, day: 15),
        sourceTemplateSessionID: "template", primaryLiftID: "squat", assistanceLiftID: "bench",
        prescriptions: [
          TrainingSetPrescription(
            id: "plus", setNumber: 3, role: .primary, percentage: 0.85, repetitions: 5,
            weightKg: 85, isPlusSetEligible: true)
        ],
        status: .completed),
      results: [
        RecordedSetResult(
          id: "plus-result", sessionID: "session", prescriptionID: "plus",
          result: try! SetResult(weight: SetResultWeight(kg: 100), repetitions: 5), recordedAt: 1)
      ],
      correctedResultIDs: ["plus-result"])
  }

  private func runningRecord(
    id: String,
    date: TrainingDate,
    startDate: Double,
    importedAt: Double,
    duration: Double,
    distance: Double
  ) -> RunningWorkoutRecord {
    RunningWorkoutRecord(
      id: id, localDate: date, startDate: startDate, durationSeconds: duration,
      distanceMeters: distance, environment: .outdoor,
      heartRate: .unavailable(reason: "not checked"), source: "Acceptance Watch",
      sourceCoverage: "Health Workouts: available", importedAt: importedAt)
  }
}
