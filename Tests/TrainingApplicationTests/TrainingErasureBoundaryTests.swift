import XCTest

@testable import TrainingApplication

final class TrainingErasureBoundaryTests: XCTestCase {
  func testRequiresExplicitConfirmationAndNamesEveryLocalCopy() async throws {
    let repository = ErasureRepositorySpy()
    let boundary = TrainingErasureBoundary(repository: repository)

    XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("Locally Authoritative Data"))
    XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("HealthKit Mirror"))
    XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("Derived Projections"))
    XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("preferences"))
    XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("sync state"))
    XCTAssertTrue(TrainingErasureCopy.confirmationMessage.contains("temporary exports"))
    XCTAssertTrue(TrainingErasureCopy.externalCopiesMessage.contains("device or iCloud backups"))
    XCTAssertTrue(TrainingErasureCopy.externalCopiesMessage.contains("previously shared exports"))
    XCTAssertTrue(TrainingErasureCopy.externalCopiesMessage.contains("HealthKit data"))
    XCTAssertFalse(TrainingErasureCopy.confirmationMessage.contains("backups"))
    XCTAssertFalse(TrainingErasureCopy.confirmationMessage.contains("HealthKit data"))

    do {
      _ = try await boundary.erase(confirmation: .cancelled)
      XCTFail("Cancellation should not erase local data")
    } catch let error as TrainingErasureError {
      XCTAssertEqual(error, .confirmationRequired)
    }
    let cancelledCalls = await repository.eraseCallCount
    XCTAssertEqual(cancelledCalls, 0)
  }

  func testConfirmedErasureDelegatesToRepository() async throws {
    let repository = ErasureRepositorySpy()
    let boundary = TrainingErasureBoundary(repository: repository)

    let result = try await boundary.erase(confirmation: .confirmed)

    XCTAssertEqual(result, .completed)
    let confirmedCalls = await repository.eraseCallCount
    XCTAssertEqual(confirmedCalls, 1)
  }
}

private actor ErasureRepositorySpy: TrainingErasureRepository {
  private(set) var eraseCallCount = 0

  func eraseAllData(progress: TrainingErasureProgressHandler?) async throws {
    eraseCallCount += 1
    progress?(.init(phase: .completed, fraction: 1, message: "Erased"))
  }
}
