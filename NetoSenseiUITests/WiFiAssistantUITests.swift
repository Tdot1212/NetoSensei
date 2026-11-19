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
        let tools = app.buttons["detailedChecks"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        XCTAssertTrue(app.staticTexts["Detailed Checks"].firstMatch.waitForExistence(timeout: 5))
        let toolsShot = XCTAttachment(screenshot: app.screenshot())
        toolsShot.name = "Detailed Checks - shared tools"
        toolsShot.lifetime = .keepAlways
        add(toolsShot)
        app.buttons["detailed.endpoints"].tap()
        let hostname = app.textFields["Endpoint hostname"]
        XCTAssertTrue(hostname.waitForExistence(timeout: 5))
        hostname.tap()
        // Replace text using the keyboard; invalid input must fail before I/O.
        let value = (hostname.value as? String) ?? ""
        hostname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        hostname.typeText("invalid/path")
        app.buttons["Check endpoints"].tap()
        XCTAssertTrue(app.staticTexts["Enter a hostname, such as www.apple.com, without a URL or path."].waitForExistence(timeout: 5))
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
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Advanced Tools (for power users)")).firstMatch.tap()
        app.swipeUp()
        let dnsInfo = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DNS Analyzer")).firstMatch
        for _ in 0..<4 where !dnsInfo.exists { app.swipeUp() }
        XCTAssertTrue(dnsInfo.waitForExistence(timeout: 5)); dnsInfo.tap()
        XCTAssertTrue(app.buttons["Read DNS information"].waitForExistence(timeout: 5))
        app.buttons["Read DNS information"].tap()
        XCTAssertTrue(app.staticTexts["Encryption: unverified"].waitForExistence(timeout: 10))
        let info = XCTAttachment(screenshot: app.screenshot()); info.name = "DNS information - observed and unverified"; info.lifetime = .keepAlways; add(info)
        app.buttons["Done"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DNS Benchmark")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Start Benchmark"].waitForExistence(timeout: 5))
        app.buttons["Start Benchmark"].tap()
        XCTAssertTrue(app.buttons["Run Again"].waitForExistence(timeout: 65))
        XCTAssertTrue(app.staticTexts["System Default"].exists)
        let benchmark = XCTAttachment(screenshot: app.screenshot()); benchmark.name = "DNS benchmark - real query results"; benchmark.lifetime = .keepAlways; add(benchmark)
        app.buttons["Close"].tap()
    }
}

final class LiveDiagnosticToolsUITests: XCTestCase {
    @MainActor func testQuickCheckAndTLSAnalysisFinishWithEvidence() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Diagnose"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Diagnose"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Quick Check")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Results"].waitForExistence(timeout: 65))
        let quick = XCTAttachment(screenshot: app.screenshot()); quick.name = "Quick Check - actual network"; quick.lifetime = .keepAlways; add(quick)
        app.swipeDown()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Advanced Tools (for power users)")).firstMatch.tap()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "TLS Analyzer")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Analyze"].waitForExistence(timeout: 5))
        let host = app.textFields["example.com"]
        host.tap(); host.typeText("www.apple.com")
        app.buttons["Analyze"].tap()
        let finished = NSPredicate { _, _ in app.buttons["Analyze"].exists && app.buttons["Analyze"].isEnabled }
        expectation(for: finished, evaluatedWith: nil)
        waitForExpectations(timeout: 45)
        // A completed analysis presents a rating or an explicit unavailable reason.
        XCTAssertTrue(app.staticTexts["Security Rating"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Couldn't assess")).firstMatch.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let tls = XCTAttachment(screenshot: app.screenshot()); tls.name = "TLS - actual connection evidence"; tls.lifetime = .keepAlways; add(tls)
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
