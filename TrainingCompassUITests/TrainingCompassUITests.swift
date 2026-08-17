import XCTest

final class TrainingCompassUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func cleanApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRAINING_COMPASS_UI_SCENARIO"] = "empty"
        return app
    }

    private func cycleReadyApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRAINING_COMPASS_UI_SCENARIO"] = "cycle-ready"
        return app
    }

    private func cycleImportApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRAINING_COMPASS_UI_SCENARIO"] = "cycle-import"
        return app
    }

    func testLaunchShowsPreDataFourDestinationShell() {
        let app = cleanApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Nothing scheduled today"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Cycle"].exists)
        XCTAssertTrue(app.tabBars.buttons["Progress"].exists)
        XCTAssertTrue(app.tabBars.buttons["TMs"].exists)

        app.tabBars.buttons["Cycle"].tap()
        XCTAssertTrue(app.staticTexts["Set up your first cycle"].exists)
        XCTAssertTrue(app.staticTexts["0 of 5 lifts ready"].exists)
        XCTAssertTrue(app.buttons["cycle.setup-training-maxes"].exists)
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
            app.staticTexts["TM 100.00 kg · Increment 2.50 kg"].waitForExistence(timeout: 15),
        )

        app.tabBars.buttons["Cycle"].tap()
        XCTAssertTrue(app.staticTexts["Set up your first cycle"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["1 of 5 lifts ready"].exists)
        XCTAssertFalse(app.staticTexts["Calendar Change"].exists)

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Rolling Workout Overview"].waitForExistence(timeout: 15))
    }

    func testNewCycleCanBeReviewedAndStartedFromCycleTab() {
        let app = cycleReadyApp()
        app.launch()

        app.tabBars.buttons["Cycle"].tap()
        let newCycle = app.buttons["cycle.new"]
        XCTAssertTrue(newCycle.waitForExistence(timeout: 15))
        newCycle.tap()

        XCTAssertTrue(app.navigationBars["New Training Cycle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["cycle.new.anchor"].exists)
        XCTAssertTrue(app.staticTexts["Weekly Schedule"].exists)
        XCTAssertTrue(app.staticTexts["Monday"].exists)
        XCTAssertTrue(app.staticTexts["Friday"].exists)
        let reviewScreenshot = XCTAttachment(screenshot: app.screenshot())
        reviewScreenshot.name = "New Training Cycle review"
        reviewScreenshot.lifetime = .keepAlways
        add(reviewScreenshot)

        let startCycle = app.buttons["cycle.new.start"]
        if !startCycle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(startCycle.waitForExistence(timeout: 5))
        startCycle.tap()
        let confirmation = app.alerts["Confirm Draft Training Cycle"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(
            confirmation.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "snapshots the current Training Maxes"),
            ).firstMatch.exists,
        )
        confirmation.buttons["Start Cycle"].tap()

        XCTAssertTrue(app.staticTexts["Active Training Cycle"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["cycle.activate"].exists)
        let activeScreenshot = XCTAttachment(screenshot: app.screenshot())
        activeScreenshot.name = "Active Training Cycle"
        activeScreenshot.lifetime = .keepAlways
        add(activeScreenshot)
    }

    func testPastCycleCanImportCompletedSessionTopSetReps() {
        let app = cycleImportApp()
        app.launch()

        app.tabBars.buttons["Cycle"].tap()
        let importHistory = app.buttons["cycle.import-history"]
        XCTAssertTrue(importHistory.waitForExistence(timeout: 15))
        importHistory.tap()

        XCTAssertTrue(app.navigationBars["Add Past Results"].waitForExistence(timeout: 5))
        let completedToggles = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "cycle.import.session."),
        )
        XCTAssertGreaterThan(completedToggles.count, 1)

        let repetitions = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "cycle.import.reps."),
        ).firstMatch
        XCTAssertTrue(repetitions.waitForExistence(timeout: 5))
        repetitions.tap()
        if repetitions.buttons["Clear text"].exists {
            repetitions.buttons["Clear text"].tap()
        }
        repetitions.typeText("9")
        app.buttons["cycle.import.keyboard-done"].tap()

        let importSessions = app.buttons["cycle.import.confirm"]
        for _ in 0 ..< 4 where !importSessions.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(importSessions.waitForExistence(timeout: 5))
        XCTAssertTrue(importSessions.isEnabled)
        let reviewScreenshot = XCTAttachment(screenshot: app.screenshot())
        reviewScreenshot.name = "Past cycle result import"
        reviewScreenshot.lifetime = .keepAlways
        add(reviewScreenshot)
        importSessions.tap()

        XCTAssertTrue(app.navigationBars["Add Past Results"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Cycle"].waitForExistence(timeout: 15))
        XCTAssertTrue(importHistory.waitForNonExistence(timeout: 15))
    }

    func testFullAppErasureShowsScopedConfirmationAndExternalCopyWarning() {
        let app = cleanApp()
        app.launch()

        app.tabBars.buttons["TMs"].tap()
        XCTAssertTrue(app.navigationBars["TMs"].waitForExistence(timeout: 15))
        app.buttons["tm.data-recovery"].tap()
        XCTAssertTrue(app.buttons["tm.erase-all"].waitForExistence(timeout: 5))
        app.buttons["tm.erase-all"].tap()

        XCTAssertTrue(app.navigationBars["Erase All App Data"].waitForExistence(timeout: 5))
        let localScope = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Locally Authoritative Data"),
        ).firstMatch
        let externalCopies = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "previously shared exports"),
        ).firstMatch
        XCTAssertTrue(localScope.exists)
        XCTAssertTrue(externalCopies.exists)
        let deleteHealthKit = app.switches["erase.delete-healthkit"]
        XCTAssertTrue(deleteHealthKit.exists)
        let ownershipCopy = "targets only objects authored by Training Compass"
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", ownershipCopy),
            ).firstMatch.exists,
        )

        let eraseButton = app.buttons["erase.confirm"]
        if !eraseButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(eraseButton.waitForExistence(timeout: 5))
        eraseButton.tap()
        XCTAssertTrue(app.alerts["Erase All App Data"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Erase All App Data"].exists)
    }

    func testHealthFoundationNavigationAndConfirmedRebuildControls() {
        let app = cleanApp()
        app.launch()

        app.tabBars.buttons["Health"].tap()
        XCTAssertTrue(app.navigationBars["Health Data Status"].waitForExistence(timeout: 15))
        for _ in 0 ..< 3 {
            app.swipeUp()
        }
        let connect = app.buttons["health.connect"]
        let checkAccess = app.buttons["health.check-access"]
        let refresh = app.buttons["health.refresh-data.toolbar"]
        XCTAssertTrue(
            connect.waitForExistence(timeout: 15) || checkAccess.waitForExistence(timeout: 15)
                || refresh.waitForExistence(timeout: 15),
            "Health must expose an explicit connection, access, or refresh action",
        )

        if connect.exists {
            connect.tap()
        } else if checkAccess.exists {
            checkAccess.tap()
        } else {
            refresh.tap()
        }
        if app.alerts["Health connection unavailable"].waitForExistence(timeout: 5) {
            app.alerts.buttons["OK"].tap()
        }
        for _ in 0 ..< 6 {
            if refresh.exists {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()
        XCTAssertTrue(app.staticTexts["Health Data Status"].exists)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        app.tabBars.buttons["Health"].tap()
        XCTAssertTrue(app.navigationBars["Health Data Status"].exists)

        for _ in 0 ..< 3 {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["health.rebuild"].waitForExistence(timeout: 5))
        app.buttons["health.rebuild"].tap()
        XCTAssertTrue(app.navigationBars["Health Data Rebuild"].waitForExistence(timeout: 5))
        let rebuild = app.buttons["health.rebuild.confirm"]
        XCTAssertTrue(rebuild.waitForExistence(timeout: 5))
        rebuild.tap()
        let cancel = app.sheets.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 5) {
            cancel.tap()
        }
        XCTAssertTrue(app.navigationBars["Health Data Rebuild"].exists)
    }

    func testExplicitTrainingEventLinkingShowsWarningDualSourceDetailAndUnlink() {
        let app = XCUIApplication()
        app.launchEnvironment["TRAINING_COMPASS_UI_SCENARIO"] = "event-linking"
        app.launch()

        XCTAssertTrue(
            app.buttons["today.training-event.session:ui-session"].waitForExistence(timeout: 15),
        )
        let likely = app.buttons["training-event.candidate.ui-likely"]
        let unusual = app.buttons["training-event.candidate.ui-unusual"]
        for _ in 0 ..< 8 {
            if likely.exists, unusual.exists {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(likely.waitForExistence(timeout: 10))
        XCTAssertTrue(unusual.exists)

        unusual.tap()
        XCTAssertTrue(
            app.sheets.staticTexts["Confirm unusual Training Event match?"].waitForExistence(
                timeout: 5,
            ),
        )
        XCTAssertTrue(app.sheets.buttons["Confirm Unusual Match"].exists)
        app.sheets.buttons["Confirm Unusual Match"].tap()
        for _ in 0 ..< 8 {
            app.swipeDown()
        }
        let linkedEvent = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.training-event.training-event:"),
        ).firstMatch
        XCTAssertTrue(linkedEvent.waitForExistence(timeout: 10))
        linkedEvent.tap()

        XCTAssertTrue(app.navigationBars["Training Event"].waitForExistence(timeout: 5))
        let sessionAuthority = app.staticTexts["5/3/1 Session · Training Compass authoritative"]
        let healthAuthority = app.staticTexts["Health Workout · HealthKit authoritative"]
        let noOverwrite = app.staticTexts["Neither source is silently overwritten."]
        var sawSessionAuthority = sessionAuthority.exists
        var sawHealthAuthority = healthAuthority.exists
        var sawNoOverwrite = noOverwrite.exists
        for _ in 0 ..< 8 {
            if sawSessionAuthority, sawHealthAuthority, sawNoOverwrite {
                break
            }
            app.swipeUp()
            sawSessionAuthority = sawSessionAuthority || sessionAuthority.exists
            sawHealthAuthority = sawHealthAuthority || healthAuthority.exists
            sawNoOverwrite = sawNoOverwrite || noOverwrite.exists
        }
        XCTAssertTrue(sawSessionAuthority)
        XCTAssertTrue(sawHealthAuthority)
        XCTAssertTrue(sawNoOverwrite)
        let unlink = app.buttons["training-event.unlink"]
        for _ in 0 ..< 8 {
            if unlink.exists {
                break
            }
            app.swipeDown()
        }
        XCTAssertTrue(unlink.exists)
        unlink.tap()
        XCTAssertTrue(app.sheets.buttons["Confirm Unlink"].waitForExistence(timeout: 5))
        app.sheets.buttons["Confirm Unlink"].tap()
        let unlinkedState = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Unlinked"),
        ).firstMatch
        XCTAssertTrue(unlinkedState.waitForExistence(timeout: 5))
    }
}
