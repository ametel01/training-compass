@testable import TrainingPersistence
import XCTest

final class TrainingPersistenceModuleTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(TrainingPersistenceModule.self)
    }
}
