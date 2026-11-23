import XCTest

final class HomeConnectionUITests: XCTestCase {
    @MainActor func testCellularHomeWithUnavailableLatency() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-testCellularHome"]
        app.launch()

        let status = app.staticTexts["home.internetStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Internet connected")
        let nextCheck = app.staticTexts["home.nextCheckReason"]
        XCTAssertTrue(nextCheck.isHittable)
        XCTAssertTrue(nextCheck.label.contains("Direct delay is unavailable"))
        XCTAssertTrue(app.buttons["home.openSpeed"].isHittable)
        XCTAssertTrue(app.staticTexts["Network latency"].exists)
        XCTAssertTrue(app.staticTexts["Unavailable"].exists)
        XCTAssertFalse(app.staticTexts["home.router"].exists)
        XCTAssertFalse(app.staticTexts["What's happening"].exists)
        capture(app, "Home - cellular with missing delay")

        let details = app.buttons["Check details"]
        XCTAssertTrue(details.isHittable)
        details.tap()
        XCTAssertTrue(app.staticTexts["Connection quality score unavailable"].exists)
        capture(app, "Home - check details")

        let latency = app.buttons["How latency is measured"]
        for _ in 0..<4 where !latency.isHittable { app.swipeUp() }
        XCTAssertTrue(latency.isHittable)
        latency.tap()
        XCTAssertTrue(app.navigationBars["About Latency"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["About Latency"].exists)
        XCTAssertTrue(app.staticTexts["162 ms"].firstMatch.exists)
        app.navigationBars["About Latency"].buttons["Done"].tap()

        let radio = app.buttons["About cellular measurements"]
        for _ in 0..<5 {
            if radio.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(radio.isHittable)
        radio.tap()
        XCTAssertTrue(app.staticTexts["Signal strength"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["AI Provider Settings"].tap()
        XCTAssertTrue(app.navigationBars["AI Settings"].waitForExistence(timeout: 3))
        app.navigationBars["AI Settings"].buttons["Done"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()

        app.buttons["AI Assistant"].tap()
        XCTAssertTrue(app.navigationBars["AI Assistant"].waitForExistence(timeout: 3))
        capture(app, "AI Assistant from Home")
        app.navigationBars["AI Assistant"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["AI Assistant"].waitForExistence(timeout: 3))
    }

    @MainActor func testHomeShortcutsLeadToTheExistingWorkflows() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-testCellularHome"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.internetStatus"].waitForExistence(timeout: 5))
        for (identifier, tab, label) in [
            ("home.openDiagnose", "Diagnose", "diagnose.run"),
            ("home.openSpeed", "Speed", "performance.runAll"),
            ("home.openSecurity", "Security", "Check security and get next steps")
        ] {
            let shortcut = app.buttons[identifier]
            for _ in 0..<4 {
                if shortcut.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(shortcut.isHittable, identifier)
            shortcut.tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 8), label)
            capture(app, "Connection brief - " + tab)
            app.tabBars.buttons["Home"].tap()
        }
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["24h"].waitForExistence(timeout: 5))
        capture(app, "Connection brief - History")
    }

    @MainActor func testHistoryRangesAndDeleteConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        app.tabBars.buttons["History"].tap()

        for period in ["7d", "30d", "24h"] {
            let button = app.segmentedControls.buttons[period]
            XCTAssertTrue(button.isHittable)
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
        let menu = app.buttons["History actions"]
        menu.tap()
        app.buttons["Delete All (Keep Bookmarked)"].tap()
        XCTAssertTrue(app.buttons["Delete Unbookmarked"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        menu.tap()
        app.buttons["Delete All"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(menu.isHittable)
    }

    @MainActor func testSecurityDeviceToolsOpenAndClose() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        app.tabBars.buttons["Security"].tap()

        for (identifier, title) in [
            ("security.deviceAssistant", "Wi-Fi Assistant"),
            ("security.uniFi", "UniFi Clients"),
            ("security.deviceHistory", "Device History")
        ] {
            let entry = app.buttons[identifier]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            for _ in 0..<3 {
                if entry.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(entry.isHittable, title)
            entry.tap()
            let navigation = app.navigationBars[title]
            XCTAssertTrue(navigation.waitForExistence(timeout: 5), title)
            if title == "UniFi Clients" {
                XCTAssertFalse(app.buttons["Find my consoles"].isEnabled)
            }
            if title == "Device History" {
                navigation.buttons["Network alerts"].tap()
                XCTAssertTrue(app.navigationBars["Alerts"].waitForExistence(timeout: 3))
                app.navigationBars["Alerts"].buttons["Done"].tap()
            }
            let done = navigation.buttons["Done"]
            XCTAssertTrue(done.isHittable, title)
            done.tap()
            XCTAssertTrue(navigation.waitForNonExistence(timeout: 5), title)
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
