//
//  KillSwitchAdvisor.swift
//  NetoSensei
//
//  Pure advisory service — no network calls, no probes, no claims about
//  what's enabled. iOS does not let third-party apps:
//   • Toggle a VPN on/off (NEVPNManager requires entitlement)
//   • Read whether kill-switch is enabled in another app's profile
//   • Simulate a tunnel drop
//
//  So we cannot truly "test" a kill-switch. What we CAN do is detect which
//  proxy app is in use (via the proxy CA already on the trust chain — TLSAnalyzer
//  has the same list) and render app-specific guidance for the user to
//  verify the setting themselves, plus a manual-test recipe.
//

import Foundation

// MARK: - Advice

struct KillSwitchAdvice {
    /// Best-guess proxy app, if we can identify one. nil = unknown / native VPN profile.
    let detectedProxyApp: String?
    /// One-paragraph, app-specific instruction.
    let guidance: String
    /// Manual test the user can perform — toggle proxy off, observe whether
    /// pages still load.
    let manualTestSteps: [String]
    /// Honest disclaimer for the UI to display verbatim.
    let disclaimer: String

    let generatedAt: Date
}

// MARK: - Service

@MainActor
final class KillSwitchAdvisor {
    static let shared = KillSwitchAdvisor()
    private init() {}

    /// Build kill-switch guidance based on what we can infer about the user's
    /// proxy/VPN setup. Synchronous: no network calls.
    func checkKillSwitchGuidance() -> KillSwitchAdvice {
        let detected = detectProxyApp()
        let guidance = guidanceFor(detected)

        return KillSwitchAdvice(
            detectedProxyApp: detected,
            guidance: guidance,
            manualTestSteps: standardManualTest,
            disclaimer: "This is guidance, not an automated test. iOS does not allow third-party apps to control VPN state or read another app's settings.",
            generatedAt: Date()
        )
    }

    // MARK: - Detect proxy app

    /// Walk the inferenceReasons + method-result detail strings exposed by
    /// SmartVPNDetector (which already reports the proxy CA name when seen).
    /// If nothing matches, we return nil rather than guess — the guidance
    /// downgrades gracefully to "generic" copy.
    /// CLEANUP 6: signatures live in ProxyDetection.knownProxyApps. We pass
    /// includeGenericFingerprints: false because the detector's reasoning
    /// text contains the word "proxy" coincidentally (e.g. "likely VPN/proxy"),
    /// which would cause a false-positive match against the generic needle.
    private func detectProxyApp() -> String? {
        guard let detection = SmartVPNDetector.shared.detectionResult else { return nil }
        // Build a single haystack string from all the detector's surfaces
        // that mention CA / interface details.
        var haystack = ""
        haystack.append(detection.inferenceReasons.joined(separator: " "))
        for method in detection.methodResults {
            haystack.append(" ")
            haystack.append(method.detail)
        }
        let lower = haystack.lowercased()

        if let match = ProxyDetection.detectProxyApp(
            in: lower,
            includeGenericFingerprints: false
        ) {
            return match.app
        }

        // Fallback: identify by tunnel interface family. SmartVPNDetector's
        // method-result details surface enumerated interface names like
        // "ipsec5 (10.x.x.x)". Useful when the proxy isn't doing TLS
        // interception (so no proxy CA shows up in the trust chain).
        if lower.contains("ipsec") {
            return "IPSec tunnel"
        }
        return nil
    }

    // MARK: - Per-app guidance

    private func guidanceFor(_ app: String?) -> String {
        let hint = app.map { "Possible app/interface hint: \($0). This is not verification of its settings. " } ?? "The VPN/proxy app could not be identified. "
        return hint + "Check the provider's current documentation for block-without-VPN protection. Automatic reconnect or On-Demand alone does not prove traffic is blocked during tunnel failure."
    }

    // MARK: - Standard manual test

    private let standardManualTest: [String] = [
        "Read the VPN provider's documented kill-switch test. Automatic reconnection and traffic blocking are different capabilities.",
        "Use a trusted network and non-sensitive test requests. Record normal VPN egress before the test.",
        "Follow the provider's controlled tunnel-failure procedure and observe fresh remote requests and public egress, including IPv6.",
        "A failed page alone is inconclusive: offline connectivity, filtering or server failure can cause it. Cached content is also inconclusive.",
        "Restore the original connection. Protection remains unverified unless observations establish the expected fail-closed routing."
    ]
}
