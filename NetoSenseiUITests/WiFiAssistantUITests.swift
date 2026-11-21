import XCTest

final class WiFiAssistantUITests: XCTestCase {
    @MainActor
    func testAssistantExplainsCompatibilityAndRequiresBaseline() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let diagnose = app.tabBars.buttons["Diagnose"]
        XCTAssertTrue(diagnose.waitForExistence(timeout: 20))
        diagnose.tap()
        let assistant = app.buttons["Wi-Fi Assistant"]
        XCTAssertTrue(assistant.waitForExistence(timeout: 10))
        assistant.tap()
        XCTAssertTrue(app.staticTexts["Understand your Wi-Fi"].waitForExistence(timeout: 5))
        let first = XCTAttachment(screenshot: app.screenshot())
        first.name = "Wi-Fi Assistant - initial"
        first.lifetime = .keepAlways
        add(first)
        XCTAssertTrue(app.staticTexts["Choose what to fix"].exists)
        let after = app.buttons["Measure after · 3 tests"]
        for _ in 0..<8 where !after.isHittable { app.swipeUp() }
        XCTAssertTrue(after.exists)
        XCTAssertFalse(after.isEnabled)
        let compatibility = app.staticTexts["Router integration required"]
        for _ in 0..<8 where !compatibility.isHittable { app.swipeUp() }
        XCTAssertTrue(compatibility.exists)
        let last = XCTAttachment(screenshot: app.screenshot())
        last.name = "Wi-Fi Assistant - compatibility"
        last.lifetime = .keepAlways
        add(last)
    }

    @MainActor func testLiveResponsiveness() {
        #if !targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let diagnose = app.tabBars.buttons["Diagnose"]
        XCTAssertTrue(diagnose.waitForExistence(timeout: 20))
        diagnose.tap()
        app.buttons["Wi-Fi Assistant"].tap()
        let test = app.buttons["Check responsiveness"]
        XCTAssertTrue(test.waitForExistence(timeout: 10))
        test.tap()
        XCTAssertTrue(app.staticTexts["Responsiveness check complete"].waitForExistence(timeout: 200))
        let loaded = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "During download")).firstMatch
        XCTAssertTrue(loaded.exists)
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "Live HTTPS responsiveness"
        result.lifetime = .keepAlways
        add(result)
        #endif
    }

}

final class AccuracySmokeUITests: XCTestCase {
    @MainActor func testMainTabsAndDetailedEndpointValidation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        for tab in ["Speed", "Security", "History", "Home", "Diagnose"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
        }
        XCTAssertTrue(app.staticTexts["Current connection"].waitForExistence(timeout: 5))
        let run = app.buttons["diagnose.run"]
        let chooser = app.buttons["Choose a website"]
        for _ in 0..<4 where !chooser.isHittable { app.swipeUp() }
        chooser.tap()
        let hostname = app.textFields["diagnose.hostname"]
        XCTAssertTrue(hostname.waitForExistence(timeout: 5))
        hostname.tap()
        // Replace text using the keyboard; invalid input must fail before I/O.
        let value = (hostname.value as? String) ?? ""
        hostname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        hostname.typeText("invalid/path")
        if app.keyboards.firstMatch.exists { app.swipeUp() }
        for _ in 0..<4 where !run.isHittable { app.swipeUp() }
        run.tap()
        XCTAssertTrue(app.staticTexts["Enter a hostname such as www.apple.com, without a URL or path."].waitForExistence(timeout: 5))
        let endpointShot = XCTAttachment(screenshot: app.screenshot())
        endpointShot.name = "Endpoint Checks - validation"
        endpointShot.lifetime = .keepAlways
        add(endpointShot)
    }
}

final class ResolverToolsUITests: XCTestCase {
    @MainActor func testResolverInformationAndActualDNSBenchmark() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Diagnose"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Diagnose"].tap()
        let run = app.buttons["diagnose.run"]
        for _ in 0..<4 where !run.isHittable { app.swipeUp() }
        run.tap()
        let systemDNS = app.staticTexts["System resolver"]
        for _ in 0..<6 where !systemDNS.isHittable { app.swipeUp() }
        XCTAssertTrue(systemDNS.waitForExistence(timeout: 65))
        XCTAssertTrue(app.staticTexts["System Default"].exists)
        let benchmark = XCTAttachment(screenshot: app.screenshot())
        benchmark.name = "Full check - resolver evidence"
        benchmark.lifetime = .keepAlways
        add(benchmark)
    }
}

final class LiveDiagnosticToolsUITests: XCTestCase {
    @MainActor func testFullCheckFinishesWithConnectionAndTLSReadings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let diagnose = app.tabBars.buttons["Diagnose"]
        XCTAssertTrue(diagnose.waitForExistence(timeout: 20))
        diagnose.tap()
        XCTAssertTrue(app.staticTexts["Current connection"].waitForExistence(timeout: 5))
        let run = app.buttons["diagnose.run"]
        for _ in 0..<4 where !run.isHittable { app.swipeUp() }
        run.tap()
        XCTAssertTrue(app.buttons["Stop checks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["All checks finished."].waitForExistence(timeout: 330))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Full connection check"
        attachment.lifetime = .keepAlways
        add(attachment)
        let hostname = app.staticTexts["www.apple.com"]
        for _ in 0..<12 where !hostname.exists { app.swipeUp() }
        XCTAssertTrue(hostname.exists)
    }

    @MainActor func testStoppingFullCheckKeepsNavigationResponsive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let diagnose = app.tabBars.buttons["Diagnose"]
        XCTAssertTrue(diagnose.waitForExistence(timeout: 20))
        diagnose.tap()
        let run = app.buttons["diagnose.run"]
        for _ in 0..<4 where !run.isHittable { app.swipeUp() }
        run.tap()
        let stop = app.buttons["Stop checks"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let history = app.tabBars.buttons["History"]
        history.tap()
        XCTAssertTrue(history.isSelected)
        diagnose.tap()
        stop.tap()
        XCTAssertTrue(run.waitForExistence(timeout: 20))
    }
}

#if !targetEnvironment(simulator)
final class WiFiDeviceInventoryLiveUITests: XCTestCase {
    @MainActor func testRealScanShowsCountsAndRouterIdentificationSteps() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Diagnose"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Diagnose"].tap()
        app.buttons["Wi-Fi Assistant"].tap()
        app.buttons["Check Wi-Fi and devices"].tap()
        XCTAssertTrue(app.staticTexts["Checks complete · discovery is partial"].waitForExistence(timeout: 80))
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "other IPv4 addresses observed")).firstMatch
        for _ in 0..<10 where !count.isHittable { app.swipeUp() }
        XCTAssertTrue(count.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Live Wi-Fi inventory"
        shot.lifetime = .keepAlways
        add(shot)
        let label = app.buttons["Add label"].firstMatch
        if label.exists {
            for _ in 0..<10 where !label.isHittable { app.swipeUp() }
            label.tap()
            let alert = app.alerts["Label device for this scan"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let field = alert.textFields.firstMatch
            field.tap()
            field.typeText("Test device label")
            alert.buttons["Save"].tap()
            XCTAssertTrue(app.staticTexts["Test device label"].exists)
        }
        let help = app.buttons["How to identify or block a device"]
        for _ in 0..<12 where !help.isHittable { app.swipeUp() }
        help.tap()
        XCTAssertTrue(app.navigationBars["Identify a device"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Connected devices, Clients or Network map")).firstMatch.exists)
    }
}
#endif

#if DEEPSEEK_ACCEPTANCE && !targetEnvironment(simulator)
final class WiFiDeepSeekLiveUITests: XCTestCase {
    @MainActor func testDeepSeekRecommendationAppearsAfterScan() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let diagnose = app.tabBars.buttons["Diagnose"]
        XCTAssertTrue(diagnose.waitForExistence(timeout: 20))
        diagnose.tap()
        app.buttons["Wi-Fi Assistant"].tap()
        app.buttons["Check Wi-Fi and devices"].tap()
        let review = app.buttons["Ask DeepSeek what to try first"]
        XCTAssertTrue(review.waitForExistence(timeout: 90))
        for _ in 0..<6 where !review.isHittable { app.swipeUp() }
        review.tap()
        let result = app.staticTexts["DeepSeek’s suggested next step"]
        XCTAssertTrue(result.waitForExistence(timeout: 35))
        for _ in 0..<4 where !result.isHittable { app.swipeUp() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "DeepSeek recommendation in Wi-Fi Assistant"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
#endif
