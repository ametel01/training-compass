import TrainingDomain
import XCTest

@testable import TrainingInsights

final class TrainingInsightsModuleTests: XCTestCase {
  func testModuleLoadsWithoutFrameworkDependencies() {
    XCTAssertNotNil(TrainingInsightsModule.self)
  }

  func testEpleyUsesActualWeightAndSpecialCasesOneRep() throws {
    XCTAssertEqual(
      E1RMFormula.estimate(weightKg: 100, repetitions: 1),
      100
    )
    XCTAssertEqual(
      try XCTUnwrap(E1RMFormula.estimate(weightKg: 100, repetitions: 5)),
      116.66666666666667,
      accuracy: 0.0000000001
    )
    XCTAssertNil(E1RMFormula.estimate(weightKg: 100, repetitions: 0))
  }

  func testProgressIncludesOnlyNormalPrimaryPlusSetResults() throws {
    let source = makeSource(
      weekKind: .week1,
      results: [
        result(id: "plus", prescriptionID: "plus", repetitions: 5),
        result(id: "assistance", prescriptionID: "assistance", repetitions: 10),
        result(id: "failed", prescriptionID: "failed-plus", repetitions: 0),
      ],
      additionalSets: [
        try AdditionalSet(
          id: "additional", sessionID: "session", position: 0, liftID: "squat",
          weightKg: 110, repetitions: 3, recordedAt: 1)
      ]
    )

    let progress = E1RMProgressCalculator().calculate(
      from: [source],
      selectedLiftID: "squat"
    )

    XCTAssertEqual(progress.observations.map(\.id), ["plus"])
    XCTAssertEqual(
      try XCTUnwrap(progress.observations.first?.estimatedKg), 116.66666666666667,
      accuracy: 0.0000000001)
    XCTAssertTrue(
      progress.excludedRecords.contains { $0.id == "assistance" && $0.reason == .assistanceSet })
    XCTAssertTrue(progress.excludedRecords.contains { $0.id == "failed" })
    XCTAssertTrue(
      progress.excludedRecords.contains { $0.id == "additional" && $0.reason == .additionalSet })
  }

  func testProgressDefaultsToLiftWithEligibleHistory() throws {
    let noData = makeSource(
      weekKind: .week1,
      sessionID: "bench-session",
      primaryLiftID: "bench",
      results: [result(id: "bench-assistance", prescriptionID: "assistance", repetitions: 10)]
    )
    let withData = makeSource(
      weekKind: .week2,
      sessionID: "squat-session",
      results: [result(id: "squat-plus", prescriptionID: "plus", repetitions: 5)]
    )

    let progress = E1RMProgressCalculator().calculate(from: [noData, withData])

    XCTAssertEqual(progress.selectedLiftID, "squat")
    XCTAssertEqual(progress.latest?.id, "squat-plus")
  }

  func testProgressRetainsPrecisionAndReportsNeutralTrailingTrendWithoutInterpolation() throws {
    let first = makeSource(
      weekKind: .week1,
      sessionID: "first-session",
      date: TrainingDate(year: 2026, month: 1, day: 1),
      results: [result(id: "first", prescriptionID: "plus", weightKg: 100, repetitions: 1)]
    )
    let latest = makeSource(
      weekKind: .week2,
      sessionID: "latest-session",
      date: TrainingDate(year: 2026, month: 3, day: 1),
      results: [result(id: "latest", prescriptionID: "plus", weightKg: 100, repetitions: 5)]
    )

    let progress = E1RMProgressCalculator().calculate(
      from: [first, latest],
      selectedLiftID: "squat"
    )

    XCTAssertEqual(progress.observations.count, 2)
    XCTAssertEqual(progress.latest?.id, "latest")
    XCTAssertEqual(progress.previous?.id, "first")
    XCTAssertEqual(progress.cycleBest?.id, "latest")
    XCTAssertEqual(progress.trailing90DayDirection, .upward)
    XCTAssertEqual(progress.observations.first?.displayValue, "100.0 kg")
    XCTAssertEqual(progress.observations.last?.displayValue, "116.7 kg")
    XCTAssertEqual(
      progress.explanation.roundingRule,
      "Displayed to one decimal place; calculations retain full precision.")
    XCTAssertTrue(progress.explanation.text.contains("Epley"))
    XCTAssertTrue(progress.explanation.text.contains("first"))
    XCTAssertTrue(progress.explanation.text.contains("latest"))
  }

  func testFailedOmittedDeloadAndCorrectedRecordsRemainInspectableButNeverBecomePoints() throws {
    let failed = makeSource(
      weekKind: .week1,
      sessionID: "failed-session",
      results: [result(id: "failed-plus", prescriptionID: "plus", repetitions: 0)]
    )
    let omitted = makeSource(
      weekKind: .week2,
      sessionID: "omitted-session",
      results: [],
      omissions: [OmittedSet(sessionID: "session", prescriptionID: "plus", omittedAt: 1)]
    )
    let deload = makeSource(
      weekKind: .deload,
      sessionID: "deload-session",
      results: [result(id: "deload-plus", prescriptionID: "plus", repetitions: 5)]
    )
    let corrected = makeSource(
      weekKind: .week3,
      sessionID: "corrected-session",
      results: [result(id: "corrected-plus", prescriptionID: "plus", repetitions: 1)]
    )
    let correctedWithState = E1RMSessionRecord(
      cycleID: corrected.cycleID,
      cycleState: corrected.cycleState,
      weekID: corrected.weekID,
      weekKind: corrected.weekKind,
      session: corrected.session,
      results: corrected.results,
      correctedResultIDs: ["corrected-plus"]
    )

    let progress = E1RMProgressCalculator().calculate(
      from: [failed, omitted, deload, correctedWithState],
      selectedLiftID: "squat"
    )

    XCTAssertEqual(progress.observations.map(\.id), ["corrected-plus"])
    XCTAssertEqual(progress.observations.first?.correctionState, .corrected)
    XCTAssertTrue(
      progress.excludedRecords.contains { $0.id == "failed-plus" && $0.reason == .failedResult })
    XCTAssertTrue(
      progress.excludedRecords.contains { $0.id == "session:plus" && $0.reason == .omitted })
    XCTAssertTrue(
      progress.excludedRecords.contains { $0.id == "deload-plus" && $0.reason == .deloadWeek })
    XCTAssertEqual(progress.observations.first?.sourceLink.resultID, "corrected-plus")
  }

  private func makeSource(
    weekKind: TrainingWeekKind,
    sessionID: String = "session",
    date: TrainingDate = TrainingDate(year: 2026, month: 1, day: 1),
    primaryLiftID: String = "squat",
    results: [RecordedSetResult],
    omissions: [OmittedSet] = [],
    additionalSets: [AdditionalSet] = []
  ) -> E1RMSessionRecord {
    E1RMSessionRecord(
      cycleID: "cycle",
      cycleState: .completed,
      weekID: "week",
      weekKind: weekKind,
      session: TrainingCycleSession(
        id: sessionID,
        intendedDate: date,
        sourceTemplateSessionID: "template-session",
        primaryLiftID: primaryLiftID,
        assistanceLiftID: "bench",
        prescriptions: [
          TrainingSetPrescription(
            id: "plus", setNumber: 3, role: .primary, percentage: 0.85,
            repetitions: 5, weightKg: 85, isPlusSetEligible: true),
          TrainingSetPrescription(
            id: "assistance", setNumber: 1, role: .assistance, percentage: 0.65,
            repetitions: 10, weightKg: 65),
          TrainingSetPrescription(
            id: "failed-plus", setNumber: 2, role: .primary, percentage: 0.75,
            repetitions: 5, weightKg: 75),
        ],
        status: .completed
      ),
      results: results,
      omissions: omissions,
      additionalSets: additionalSets,
      correctedResultIDs: []
    )
  }

  private func result(
    id: String,
    prescriptionID: String,
    weightKg: Double = 100,
    repetitions: Int
  ) -> RecordedSetResult {
    RecordedSetResult(
      id: id,
      sessionID: "session",
      prescriptionID: prescriptionID,
      result: try! SetResult(weight: SetResultWeight(kg: weightKg), repetitions: repetitions),
      recordedAt: 1
    )
  }
}
