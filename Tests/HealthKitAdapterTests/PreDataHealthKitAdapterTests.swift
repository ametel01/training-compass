import XCTest

@testable import HealthKitAdapter

final class PreDataHealthKitAdapterTests: XCTestCase {
  func testKeepsHealthAuthorizationInaccessibleDuringGateZero() async throws {
    let adapter = PreDataHealthKitAdapter()

    let result = try await adapter.requestAuthorization()

    XCTAssertEqual(result, .notRequested)
  }
}
