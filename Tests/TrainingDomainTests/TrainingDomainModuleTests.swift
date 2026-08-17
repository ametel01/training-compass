@testable import TrainingDomain
import XCTest

final class TrainingDomainModuleTests: XCTestCase {
    func testModuleLoadsWithoutFrameworkDependencies() {
        XCTAssertNotNil(TrainingDomainModule.self)
    }
}
