import XCTest

final class ConnectionInvestigationUITests: XCTestCase {
    @MainActor func testSpeedSamplesOneAndFourRequests() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        app.tabBars.buttons["Speed"].tap()
        let entry = app.buttons["investigation.openSpeed"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        app.buttons["investigation.baseline"].tap()
        XCTAssertTrue(app.staticTexts["investigation.lead"].waitForExistence(timeout: 70))
        for _ in 0..<3 where !app.staticTexts["Four simultaneous HTTPS requests"].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["One HTTPS request"].exists)
        XCTAssertTrue(app.staticTexts["Four simultaneous HTTPS requests"].isHittable)
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "of 3 completed")).count, 2)
        capture("Guided download evidence", app)
    }

    @MainActor func testWebsiteBaselineAndMatchedComparison() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let diagnose = app.tabBars.buttons["Diagnose"]
        let tab = diagnose.exists ? diagnose : app.buttons["Diagnose"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let entry = app.buttons["investigation.openDiagnose"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.navigationBars["Guided investigation"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.textFields["investigation.hostname"].exists)

        app.buttons["investigation.baseline"].tap()
        XCTAssertTrue(app.staticTexts["investigation.lead"].waitForExistence(timeout: 45))
        capture("Guided investigation baseline", app)

        let compare = app.buttons["investigation.compare"]
        if !compare.isHittable { app.swipeUp() }
        XCTAssertTrue(compare.isHittable)
        compare.tap()
        XCTAssertTrue(app.staticTexts["investigation.verdict"].waitForExistence(timeout: 45))
        capture("Guided investigation verdict", app)
        app.navigationBars["Guided investigation"].buttons["Done"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    @MainActor func testSpeedAndSecurityLeadToTheInvestigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        for (tab, id, question) in [
            ("Speed", "investigation.openSpeed", "Does one download stall"),
            ("Security", "investigation.openSecurity", "Can encrypted DNS replies get through")
        ] {
            app.tabBars.buttons[tab].tap()
            let entry = app.buttons[id]
            for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.isHittable, tab)
            entry.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", question)).firstMatch.waitForExistence(timeout: 5))
            capture("Guided investigation from " + tab, app)
            if tab == "Security" {
                app.buttons["investigation.topic"].tap()
                app.buttons["VPN routing"].tap()
                XCTAssertTrue(app.textFields["investigation.hostname"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Do the same sites and IPv6")).firstMatch.exists)
            }
            app.navigationBars["Guided investigation"].buttons["Done"].tap()
        }
    }

    @MainActor private func capture(_ title: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = title
        shot.lifetime = .keepAlways
        add(shot)
    }
}
