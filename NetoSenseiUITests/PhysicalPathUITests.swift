#if RADIO_ACCEPTANCE && !targetEnvironment(simulator)
import XCTest

/// Explicit acceptance run only. USB connection is verified by the operator before invocation.
final class PhysicalPathUITests: XCTestCase {
    @MainActor func testRealWiFiAndCellularComparisonAndRestoreWiFi() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        if settings.buttons["com.apple.settings.wifi"].waitForExistence(timeout: 3) {
            settings.buttons["com.apple.settings.wifi"].tap()
        }
        let power = settings.switches["wifiSettings.powerToggle"]
        XCTAssertTrue(power.waitForExistence(timeout: 10))
        let original = "1" // Original Wi-Fi state was observed enabled before acceptance.
        if power.value as? String != original { toggle(power) }
        XCTAssertTrue(wait(power, value: original))
        defer {
            settings.activate()
            if power.exists, power.value as? String != original { toggle(power); _ = wait(power, value: original) }
        }
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Diagnose"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Diagnose"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Advanced Tools (for power users)")).firstMatch.tap()
        app.swipeUp()
        let comparison = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Wi-Fi vs Cell")).firstMatch
        for _ in 0..<3 where !comparison.exists { app.swipeUp() }
        comparison.tap()
        let start = app.buttons["Compare Connections"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); start.tap()
        XCTAssertTrue(app.buttons["Test Again"].waitForExistence(timeout: 180))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "Mbps").count, 1, "Wi-Fi must produce measured throughput")
        capture(app, "Wi-Fi phase actual results")
        print("WIFI_PHASE_BEGIN\n"+app.debugDescription+"\nWIFI_PHASE_END")
        settings.activate()
        XCTAssertEqual(power.value as? String, "1")
        toggle(power)
        let disabled = wait(power, value: "0")
        let settingsShot = XCTAttachment(screenshot: settings.screenshot()); settingsShot.name = "Wi-Fi setting after switch"; settingsShot.lifetime = .keepAlways; add(settingsShot)
        guard disabled else { throw NSError(domain: "RadioAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wi-Fi setting did not switch off"]) }
        app.activate()
        // Let the monitor receive the changed radio path before starting another measurement.
        let waitUntil = Date().addingTimeInterval(5)
        while Date() < waitUntil { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        app.buttons["Test Again"].tap()
        XCTAssertTrue(app.buttons["Test Again"].waitForExistence(timeout: 180))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "Mbps").count, 2, "Both paths must produce measured throughput")
        XCTAssertFalse(app.staticTexts["Connection Issue"].exists)
        capture(app, "Cellular phase actual results")
        print("CELL_PHASE_BEGIN\n"+app.debugDescription+"\nCELL_PHASE_END")
        settings.activate()
        if power.value as? String == "0" { toggle(power) }
        XCTAssertTrue(wait(power, value: original))
        app.activate()
    }
    @MainActor private func toggle(_ power: XCUIElement) {
        power.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap()
    }
    @MainActor private func wait(_ element: XCUIElement, value: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)], timeout: 10) == .completed
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
#endif

#if RADIO_ACCEPTANCE && !targetEnvironment(simulator)
final class AssistantLiveAcceptanceUITests: XCTestCase {
    @MainActor func testRealDiscoveryAndRepeatedBaselineAndAfter() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        addUIInterruptionMonitor(withDescription: "Local network permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Diagnose"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Diagnose"].tap(); app.buttons["Wi-Fi Assistant"].tap()
        app.buttons["Check Wi-Fi and devices"].tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 2), alert.buttons["Allow"].exists { alert.buttons["Allow"].tap() }
        XCTAssertTrue(app.staticTexts["Checks complete · discovery is partial"].waitForExistence(timeout: 90))
        let scan = XCTAttachment(screenshot: app.screenshot()); scan.name = "Actual partial LAN scan"; scan.lifetime = .keepAlways; add(scan)
        let recognize = app.buttons["I recognize this device"].firstMatch
        if recognize.exists {
            reveal(recognize, in: app); recognize.tap()
            XCTAssertTrue(app.buttons["Recognized this scan · Undo"].exists)
            app.buttons["Recognized this scan · Undo"].firstMatch.tap()
        }
        let before = app.buttons["Measure before · 3 tests"]
        reveal(before, in: app); XCTAssertTrue(before.isHittable); before.tap()
        let after = app.buttons["Measure after · 3 tests"]
        let baselineFinished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in after.exists && after.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [baselineFinished], timeout: 300), .completed)
        let baseline = XCTAttachment(screenshot: app.screenshot()); baseline.name = "Actual three-test baseline"; baseline.lifetime = .keepAlways; add(baseline)
        reveal(after, in: app); after.tap()
        XCTAssertTrue(app.staticTexts["Median download"].waitForExistence(timeout: 300))
        app.swipeUp()
        let comparison = XCTAttachment(screenshot: app.screenshot()); comparison.name = "Actual three-before three-after comparison"; comparison.lifetime = .keepAlways; add(comparison)
        print("ASSISTANT_EVIDENCE_BEGIN\n"+app.debugDescription+"\nASSISTANT_EVIDENCE_END")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "This does not prove what caused it")).firstMatch.exists)
        app.buttons["Reset"].tap()
        XCTAssertFalse(after.isEnabled)
        XCTAssertFalse(app.staticTexts["Median download"].exists)
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
}
#endif
