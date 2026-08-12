import XCTest

@testable import TrainingDomain

final class TrainingDomainModuleTests: XCTestCase {
  func testModuleLoadsWithoutFrameworkDependencies() {
    XCTAssertNotNil(TrainingDomainModule.self)
  }
}
