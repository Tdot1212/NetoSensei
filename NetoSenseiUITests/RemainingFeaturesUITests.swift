import XCTest

final class RemainingFeaturesUITests: XCTestCase {
    @MainActor func testMainSpeedStreamingSitesSecurityAndEndpointSpeeds() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Speed"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Speed"].tap()
        app.segmentedControls.buttons["Speed"].tap()
        let speed = app.buttons["Start Speed Test"]
        XCTAssertTrue(speed.waitForExistence(timeout: 10)); speed.tap()
        XCTAssertTrue(app.buttons["Run Again"].waitForExistence(timeout: 240))
        XCTAssertGreaterThan(app.staticTexts.matching(identifier: "Mbps").count, 0)
        capture(app,"Main speed test - actual transfer")
        app.segmentedControls.buttons["Streaming"].tap()
        let stream = app.buttons["Test Streaming"]
        XCTAssertTrue(stream.waitForExistence(timeout: 5)); stream.tap()
        XCTAssertTrue(app.staticTexts["These HTTPS responses show how the sampled endpoints answered. Actual video playback is a separate check."].waitForExistence(timeout: 60))
        capture(app,"Streaming - evidence coverage")
        app.segmentedControls.buttons["VPN Sites"].tap()
        let sites = app.buttons["Run Benchmark"]
        XCTAssertTrue(sites.waitForExistence(timeout: 5)); sites.tap()
        XCTAssertTrue(app.staticTexts["Google"].waitForExistence(timeout: 100))
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in sites.exists && sites.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for:[finished], timeout:100),.completed)
        capture(app,"Site benchmark - HTTP evidence")
        app.tabBars.buttons["History"].tap()
        capture(app,"History after actual speed test")
        app.tabBars.buttons["Diagnose"].tap()
        let run = app.buttons["diagnose.run"]
        reveal(run, in: app)
        run.tap()
        XCTAssertTrue(app.staticTexts["All checks finished."].waitForExistence(timeout: 330))
        let endpoints = app.staticTexts["Endpoint speeds"]
        reveal(endpoints, in: app)
        XCTAssertTrue(endpoints.exists)
        capture(app, "Unified diagnostics after actual transfers")
        app.tabBars.buttons["Home"].tap()
    }
    @MainActor func testCombinedPerformanceAndSecurityNextStep() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let speedTab = app.tabBars.buttons["Speed"]
        XCTAssertTrue(speedTab.waitForExistence(timeout: 20))
        speedTab.tap()
        let runAll = app.buttons["performance.runAll"]
        XCTAssertTrue(runAll.waitForExistence(timeout: 5))
        runAll.tap()
        let summary = app.staticTexts["What this run found"]
        let pathChanged = app.staticTexts["The connection changed during the run. Run all checks again to get results from one connection."]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in summary.exists || pathChanged.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 250), .completed)
        if pathChanged.exists {
            runAll.tap()
        }
        XCTAssertTrue(summary.waitForExistence(timeout: 250))
        capture(app, "Combined performance")
        let nextStep = app.staticTexts["Try this next"]
        reveal(nextStep, in: app)
        XCTAssertTrue(nextStep.isHittable)
        app.tabBars.buttons["Security"].tap()
        let security = app.buttons["Check security and get next steps"]
        XCTAssertTrue(security.waitForExistence(timeout: 10))
        security.tap()
        XCTAssertTrue(app.staticTexts["What to do next"].waitForExistence(timeout: 100))
        XCTAssertFalse(app.staticTexts["This network requires login. Verify the captive portal page is genuine before entering credentials."].exists)
        capture(app, "Security next steps")
    }

    @MainActor func testLocalDeviceIdentification() {
        #if targetEnvironment(simulator)
        return
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let tab = app.tabBars.buttons["Security"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        let scan = app.buttons["Look for devices"]
        reveal(scan, in: app)
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        let observed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "other IPv4 addresses observed")).firstMatch
        XCTAssertTrue(observed.waitForExistence(timeout: 90))
        let guide = app.buttons["Identify a phone or computer"]
        reveal(guide, in: app)
        XCTAssertTrue(guide.isHittable)
        guide.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Match the IPv4 address")).firstMatch.exists)
        capture(app, "Device identification")
        #endif
    }

    @MainActor private func reveal(_ element: XCUIElement,in app:XCUIApplication) {
        for _ in 0..<10 { if element.isHittable { return }; app.swipeUp() }
    }
    @MainActor private func done(_ app:XCUIApplication) {
        guard let button=app.buttons.matching(identifier:"Done").allElementsBoundByIndex.first(where:{$0.isHittable}) else { XCTFail("No visible Done button");return }
        button.tap()
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}
