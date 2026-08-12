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

    app.tabBars.buttons["TMs"].tap()
    XCTAssertTrue(app.navigationBars["TMs"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Squat"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Deadlift"].exists)
    XCTAssertTrue(app.staticTexts["Bench Press"].exists)
    XCTAssertTrue(app.staticTexts["Overhead Press"].exists)
    XCTAssertTrue(app.buttons["tm.add-variant"].exists)
    XCTAssertTrue(app.buttons["tm.add-custom"].exists)

    let squatEdit = app.buttons.matching(identifier: "tm.edit.progression:Squat").firstMatch
    XCTAssertTrue(squatEdit.waitForExistence(timeout: 15))
    squatEdit.tap()
    let trainingMax = app.textFields["tm.training-max"]
    XCTAssertTrue(trainingMax.waitForExistence(timeout: 15))
    trainingMax.tap()
    if trainingMax.buttons["Clear text"].exists {
      trainingMax.buttons["Clear text"].tap()
    }
    trainingMax.typeText("100")
    app.buttons["tm.review"].tap()
    XCTAssertTrue(app.alerts["Confirm lift change"].waitForExistence(timeout: 15))
    app.alerts.buttons["Confirm"].tap()
    XCTAssertTrue(
      app.staticTexts["TM 100.00 kg · Increment 2.50 kg"].waitForExistence(timeout: 15)
    )
  }
}
