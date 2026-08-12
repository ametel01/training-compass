import XCTest

@testable import TrainingPersistence

final class TrainingPersistenceModuleTests: XCTestCase {
  func testModuleLoads() {
    XCTAssertNotNil(TrainingPersistenceModule.self)
  }
}
