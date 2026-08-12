import XCTest

final class TrainingCompassUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testLaunchShowsPreDataFourDestinationShell() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["PRE-DATA BUILD"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["Today"].exists)
    XCTAssertTrue(app.tabBars.buttons["Cycle"].exists)
    XCTAssertTrue(app.tabBars.buttons["Progress"].exists)
    XCTAssertTrue(app.tabBars.buttons["TMs"].exists)

    app.tabBars.buttons["Cycle"].tap()
    XCTAssertTrue(app.staticTexts["Cycle unavailable"].exists)
    XCTAssertFalse(app.buttons.matching(identifier: "save").firstMatch.exists)
  }
}
