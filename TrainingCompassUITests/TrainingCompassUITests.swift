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

    private func keepScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        XCTAssertTrue(app.staticTexts["0 of 4 lifts ready"].exists)
        XCTAssertTrue(app.buttons["cycle.setup-training-maxes"].exists)
        XCTAssertFalse(app.buttons.matching(identifier: "save").firstMatch.exists)

        app.tabBars.buttons["TMs"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Squat"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Deadlift"].exists)
        XCTAssertTrue(app.staticTexts["Bench Press"].exists)
        XCTAssertTrue(app.staticTexts["Overhead Press"].exists)
        XCTAssertTrue(app.buttons["tm.data-recovery"].exists)

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
        XCTAssertTrue(app.staticTexts["100.0 kg"].waitForExistence(timeout: 15))

        app.tabBars.buttons["Cycle"].tap()
        XCTAssertTrue(app.staticTexts["Set up your first cycle"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["1 of 4 lifts ready"].exists)
        XCTAssertFalse(app.staticTexts["Calendar Change"].exists)

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Last 7 Days"].waitForExistence(timeout: 15))
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

        XCTAssertTrue(app.staticTexts["5/3/1 – Training Cycle"].waitForExistence(timeout: 15))
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
        for _ in 0 ..< 6 where !importHistory.exists {
            app.swipeUp()
        }
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
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(importHistory.waitForNonExistence(timeout: 15))
    }

    func testFullAppErasureShowsScopedConfirmationAndExternalCopyWarning() {
        let app = cleanApp()
        app.launch()

        app.tabBars.buttons["TMs"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
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

    func testHealthIsLimitedToApprovalRefreshAndAddingCompletedSessions() {
        let app = cleanApp()
        app.launch()

        app.tabBars.buttons["Health"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        let connect = app.buttons["health.connect"]
        let refresh = app.buttons["health.refresh-data"]
        XCTAssertTrue(
            connect.waitForExistence(timeout: 15) || refresh.waitForExistence(timeout: 15),
            "Health must expose either approval or refresh as its primary action",
        )
        if refresh.exists {
            XCTAssertTrue(app.switches["health.write-back.enabled"].exists)
        }
        for removedSection in [
            "Health Data Status", "Recovery Evidence", "Heart-Rate Zones", "Deep repair",
            "Health Workouts", "Optional Session summaries",
        ] {
            XCTAssertFalse(app.staticTexts[removedSection].exists)
        }
    }

    func testExplicitTrainingEventLinkingShowsWarningDualSourceDetailAndUnlink() {
        let app = XCUIApplication()
        app.launchEnvironment["TRAINING_COMPASS_UI_SCENARIO"] = "event-linking"
        app.launch()

        XCTAssertTrue(
            app.buttons["today.training-event.session:ui-session"].waitForExistence(timeout: 15),
        )
        XCTAssertTrue(app.staticTexts["today.session.saved"].exists)
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

    func testImportedHealthMirrorCanBeInspectedAcrossEveryTopLevelPage() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        let importedCount = app.descendants(matching: .any)["health.workouts.count"]
        let configuredExpected = ProcessInfo.processInfo.environment[
            "TRAINING_COMPASS_EXPECTED_IMPORTED_WORKOUTS",
        ].flatMap(Int.init)
        let expectedWorkouts: Int
        if let configuredExpected, configuredExpected > 0 {
            expectedWorkouts = configuredExpected
        } else {
            app.tabBars.buttons["Health"].tap()
            for _ in 0 ..< 12 where !importedCount.exists {
                app.swipeUp()
            }
            let observed = Int(importedCount.value as? String ?? "") ?? 0
            guard observed > 0 else {
                throw XCTSkip("No imported Health mirror is installed for the attended audit.")
            }
            expectedWorkouts = observed
            app.tabBars.buttons["Today"].tap()
        }
        keepScreenshot(app, named: "Imported data - Today")

        for tab in ["Cycle", "Progress", "TMs", "Health"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
            if tab == "Progress" {
                XCTAssertTrue(
                    app.staticTexts["Are my estimated 1RMs increasing?"].waitForExistence(timeout: 15),
                )
                XCTAssertTrue(app.staticTexts["Is my cardio efficiency improving?"].exists)
                let drift = app.staticTexts["How is my heart rate drifting?"]
                for _ in 0 ..< 8 where !drift.exists {
                    app.swipeUp()
                }
                XCTAssertTrue(drift.waitForExistence(timeout: 10))
                keepScreenshot(app, named: "Imported data - Progress drift")
            }
            keepScreenshot(app, named: "Imported data - \(tab)")
        }

        for _ in 0 ..< 12 where !importedCount.exists {
            app.swipeUp()
        }
        XCTAssertTrue(importedCount.waitForExistence(timeout: 10))
        XCTAssertEqual(
            importedCount.value as? String,
            "\(expectedWorkouts)",
            "The Health page must expose the expected imported workout count.",
        )
        keepScreenshot(app, named: "Imported data - Health workouts")
    }

    func testProgressIsLimitedToTheFourTrainingQuestions() {
        let app = XCUIApplication()
        app.launchEnvironment["TRAINING_COMPASS_INITIAL_TAB"] = "progress"
        app.launch()

        XCTAssertTrue(app.staticTexts["Are my estimated 1RMs increasing?"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["How much training is in each HR zone?"].exists)

        let efficiency = app.staticTexts["Is my cardio efficiency improving?"]
        for _ in 0 ..< 6 where !efficiency.exists {
            app.swipeUp()
        }
        XCTAssertTrue(efficiency.waitForExistence(timeout: 10))

        let drift = app.staticTexts["How is my heart rate drifting?"]
        for _ in 0 ..< 8 where !drift.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(drift.exists)
        XCTAssertTrue(drift.isHittable)
        keepScreenshot(app, named: "Progress - four questions")
    }
}
