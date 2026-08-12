import XCTest

@testable import TrainingInsights

final class TrainingInsightsModuleTests: XCTestCase {
  func testModuleLoadsWithoutFrameworkDependencies() {
    XCTAssertNotNil(TrainingInsightsModule.self)
  }
}
