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
        switch app {
        case "Surge":
            return "Surge → Profile → enable “Use kill switch when VPN connection fails”. Also enable “Always Real IP” for the strictest fallback behaviour."
        case "Shadowrocket":
            return "Shadowrocket → Settings → Connection → set “On Demand” to ON, and enable “Anonymous Connection on Wi-Fi”. The On-Demand profile prevents traffic when the proxy isn’t connected."
        case "Quantumult":
            return "Quantumult X → Settings → enable “VPN On-Demand”. Configure the rule so the tunnel always re-establishes after a drop."
        case "Clash":
            return "Clash for iOS / ClashX → enable On-Demand in the iOS VPN profile (Settings → VPN → [profile] → Connect On Demand). Clash itself doesn’t expose a separate kill switch."
        case "Loon":
            return "Loon → General → Connection → enable “Connect On Demand”. Optionally enable “Disconnect on Sleep: OFF” to avoid silent drops."
        case "Stash":
            return "Stash → Settings → enable On-Demand. Stash exposes per-rule kill behaviour in advanced settings."
        case "mitmproxy", "Charles", "Proxyman", "Fiddler":
            return "You appear to be running a debugging proxy (\(app ?? "")). These tools don’t provide kill-switch guarantees — they’re for inspection, not protection. Disable HTTPS interception when you’re done debugging."
        case "IPSec tunnel":
            return """
                Detected an IPSec tunnel. Common apps that use IPSec: built-in iOS VPN profiles, Shadowrocket, Quantumult X. For kill-switch verification:

                • Built-in iOS VPN profile: Settings → VPN → [your profile] → enable “Connect On Demand”.
                • Shadowrocket: Settings → Connection → set “On Demand” to ON, and enable “Anonymous Connection on Wi-Fi”.
                • Quantumult X: Settings → enable “VPN On-Demand”. Configure the rule so the tunnel always re-establishes after a drop.
                """
        case .none:
            return "We couldn’t identify your VPN/proxy app. If you use the system VPN profile: Settings → VPN → [your profile] → enable “Connect On Demand”. If you use a third-party VPN app, look for settings labelled “kill switch”, “block connections without VPN”, or “on-demand”."
        default:
            return "Check your VPN/proxy app for a setting labelled “kill switch”, “block connections without VPN”, or “on-demand”."
        }
    }

    // MARK: - Standard manual test

    private let standardManualTest: [String] = [
        "Open Safari and load any HTTPS page (e.g. https://www.cloudflare.com). Confirm it loads.",
        "Switch to your VPN/proxy app and disconnect or pause it.",
        "Return to Safari and reload the page (or load https://1.1.1.1).",
        "If the page FAILS to load: kill-switch is working — traffic is blocked when the tunnel is down.",
        "If the page LOADS via your real ISP: kill-switch is NOT enforcing — your real IP is exposed during VPN drops. Re-enable kill-switch / On-Demand in your proxy app settings.",
    ]
}
