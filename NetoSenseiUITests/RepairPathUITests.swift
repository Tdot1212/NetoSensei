import XCTest

final class RepairPathUITests: XCTestCase {
    @MainActor func testDNSAndIPv6OfferTestsAndExplainResults() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let tabBarButton = app.tabBars.buttons["Security"]
        let security = tabBarButton.exists ? tabBarButton : app.buttons["Security"].firstMatch
        XCTAssertTrue(security.waitForExistence(timeout: 10))
        security.tap()

        for (topic, title, resultPrefix) in [
            ("dns", "Verify DNS privacy", "DNS over HTTPS:"),
            ("ipv6", "Verify IPv6 routing", "Observed public IPv6")
        ] {
            let shortcut = app.buttons["privacy.shortcut." + topic]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
            for _ in 0..<3 where !shortcut.isHittable { app.swipeUp() }
            XCTAssertTrue(shortcut.isHittable)
            shortcut.tap()
            let navigation = app.navigationBars[title]
            XCTAssertTrue(navigation.waitForExistence(timeout: 6))
            XCTAssertTrue(app.staticTexts["What NetoSensei can check"].exists)
            if topic == "dns" {
                XCTAssertTrue(app.staticTexts["Set up encrypted DNS"].exists)
                let preflight = app.buttons["privacy.repair.preflight"]
                if preflight.exists {
                    for _ in 0..<3 where !preflight.isHittable { app.swipeUp() }
                    XCTAssertTrue(preflight.isHittable)
                    preflight.tap()
                    let profile = app.links["privacy.repair.profile"]
                    let unavailable = app.staticTexts["privacy.repair.unreachable"]
                    let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        profile.exists || app.buttons["privacy.repair.profile"].exists || unavailable.exists
                            || app.staticTexts["privacy.repair.vpn"].exists
                    }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
                }
                let setup = XCTAttachment(screenshot: app.screenshot())
                setup.name = "DNS action"
                setup.lifetime = .keepAlways
                add(setup)
            }
            let run = app.buttons["privacy.verification.run"]
            for _ in 0..<3 where !run.isHittable { app.swipeUp() }
            XCTAssertTrue(run.isHittable)
            run.tap()
            let observed = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", resultPrefix)).firstMatch
            let unavailable = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No IPv6 sample")).firstMatch
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                observed.exists || (topic == "ipv6" && unavailable.exists)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 35), .completed, topic)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = title
            attachment.lifetime = .keepAlways
            add(attachment)
            navigation.buttons["Done"].tap()
        }
    }

    @MainActor func testHistoryOpensComparisonGuide() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        let compare = app.buttons["Compare before and after"]
        XCTAssertTrue(compare.waitForExistence(timeout: 6))
        if !compare.isHittable { app.swipeUp() }
        compare.tap()
        XCTAssertTrue(app.navigationBars["Wi-Fi Assistant"].waitForExistence(timeout: 6))
    }

    @MainActor func testSpeedDisplaysAResultOrConcreteRecovery() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let speed = app.tabBars.buttons["Speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 10))
        speed.tap()
        app.segmentedControls.buttons["Speed"].tap()
        let start = app.buttons["Start Speed Test"]
        XCTAssertTrue(start.waitForExistence(timeout: 6))
        start.tap()
        let recovery = app.staticTexts["Speed could not be measured"]
        let result = app.buttons["Run Again"].firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            recovery.exists || result.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 230), .completed)
        if recovery.exists {
            XCTAssertTrue(app.buttons["Try Again"].exists)
            print("Speed acceptance outcome: recovery")
        } else {
            let measured = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Mbps")).firstMatch
            XCTAssertTrue(measured.exists)
            print("Speed acceptance outcome: measurement")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Speed outcome"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
