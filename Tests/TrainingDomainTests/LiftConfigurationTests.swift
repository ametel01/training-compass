import Foundation
import XCTest

@testable import TrainingDomain

final class LiftConfigurationTests: XCTestCase {
  func testProgressionLiftCatalogUsesFourExactIdentities() {
    XCTAssertEqual(
      ProgressionLift.allCases.map(\.displayName),
      ["Squat", "Deadlift", "Bench Press", "Overhead Press"]
    )
  }

  func testVariantsAndCustomLiftsRemainDistinctFromProgressionIdentity() throws {
    let squat = LiftIdentity.progression(.squat)
    let lowBar = LiftIdentity.variant(name: "Low Bar Squat")
    let homeMade = LiftIdentity.custom(name: "Belt Squat")

    XCTAssertNotEqual(squat, lowBar)
    XCTAssertNotEqual(squat, homeMade)
    XCTAssertNotEqual(lowBar, homeMade)
    XCTAssertNil(lowBar.progressionLift)
    XCTAssertNil(homeMade.progressionLift)
  }

  func testTrainingMaxMayBeAnyPositiveKilogramReference() throws {
    XCTAssertEqual(try TrainingMax(kg: 87.3).kg, 87.3)
    XCTAssertThrowsError(try TrainingMax(kg: 0)) { error in
      XCTAssertEqual(error as? WeightValidationError, .mustBePositive(.trainingMax))
    }
    XCTAssertThrowsError(try TrainingMax(kg: .nan))
  }

  func testLoadingIncrementDefaultsToTwoPointFiveKilogramsAndMustBePositive() throws {
    let configuration = try LiftConfiguration(
      id: "lift-bench-press",
      identity: .progression(.benchPress),
      trainingMax: TrainingMax(kg: 72.3)
    )

    XCTAssertEqual(configuration.loadingIncrement.kg, 2.5)
    XCTAssertThrowsError(try LoadingIncrement(kg: -2.5))
  }

  func testPrescribedWeightRoundsNearestAndExactTieDownWithoutRoundingTrainingMax() throws {
    let squat = try LiftConfiguration(
      id: "lift-squat",
      identity: .progression(.squat),
      trainingMax: TrainingMax(kg: 101.0),
      loadingIncrement: LoadingIncrement(kg: 2.5)
    )

    XCTAssertEqual(try squat.prescribedWeight(forPercentage: 0.5).kg, 50.0)
    XCTAssertEqual(try squat.prescribedWeight(forPercentage: 0.525).kg, 52.5)
    XCTAssertEqual(squat.trainingMax.kg, 101.0)

    let oneKgIncrement = try LiftConfiguration(
      id: "lift-tie",
      identity: .custom(name: "Tie Lift"),
      trainingMax: TrainingMax(kg: 101),
      loadingIncrement: LoadingIncrement(kg: 1)
    )
    XCTAssertEqual(try oneKgIncrement.prescribedWeight(forPercentage: 0.5).kg, 50)
    XCTAssertEqual(try oneKgIncrement.prescribedWeight(forPercentage: 0.5001).kg, 51)
  }

  func testSetResultWeightCanBeNonLoadableAndReportsWarningInsteadOfRejectingIt() throws {
    let alignment = try SetResultWeight(kg: 51.25).alignment(to: LoadingIncrement(kg: 2.5))
    XCTAssertEqual(alignment, .notAligned)
  }

  func testSetResultValidatesRepetitionsWhileKeepingWeightAlignmentNonBlocking() throws {
    let result = try SetResult(
      weight: SetResultWeight(kg: 51.25),
      repetitions: 0
    )
    XCTAssertEqual(result.repetitions, 0)
    XCTAssertEqual(
      result.alignment(to: try LoadingIncrement(kg: 2.5)),
      .notAligned
    )
    XCTAssertThrowsError(
      try SetResult(weight: SetResultWeight(kg: 50), repetitions: -1)
    )
  }

  func testPrescriptionPercentagesRejectValuesAboveOneHundredPercent() throws {
    let squat = try LiftConfiguration(
      id: "lift-squat",
      identity: .progression(.squat),
      trainingMax: TrainingMax(kg: 100)
    )
    XCTAssertThrowsError(try squat.prescribedWeight(forPercentage: 1.01))
  }
}
