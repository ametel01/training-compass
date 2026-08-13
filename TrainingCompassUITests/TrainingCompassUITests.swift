import XCTest

final class TrainingCompassUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testLaunchShowsPreDataFourDestinationShell() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["Nothing scheduled today"].waitForExistence(timeout: 15))
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

    app.tabBars.buttons["Cycle"].tap()
    XCTAssertTrue(app.staticTexts["Cycle unavailable"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.staticTexts["Calendar Change"].exists)
  }

  func testFullAppErasureShowsScopedConfirmationAndExternalCopyWarning() throws {
    let app = XCUIApplication()
    app.launch()

    app.tabBars.buttons["TMs"].tap()
    XCTAssertTrue(app.navigationBars["TMs"].waitForExistence(timeout: 15))
    app.buttons["tm.data-recovery"].tap()
    XCTAssertTrue(app.buttons["tm.erase-all"].waitForExistence(timeout: 5))
    app.buttons["tm.erase-all"].tap()

    XCTAssertTrue(app.navigationBars["Erase All App Data"].waitForExistence(timeout: 5))
    let localScope = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "Locally Authoritative Data")
    ).firstMatch
    let externalCopies = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "previously shared exports")
    ).firstMatch
    XCTAssertTrue(localScope.exists)
    XCTAssertTrue(externalCopies.exists)

    app.buttons["erase.confirm"].tap()
    XCTAssertTrue(app.alerts["Erase All App Data"].waitForExistence(timeout: 5))
    app.alerts.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Erase All App Data"].exists)
  }

}
