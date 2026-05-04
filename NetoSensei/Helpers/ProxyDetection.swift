//
//  ProxyDetection.swift
//  NetoSensei
//
//  Shared signatures for detecting local proxy/VPN apps. Consolidates
//  the proxy fake-IP ranges and known-proxy-app list that were previously
//  duplicated across multiple security scanners.
//

import Foundation

enum ProxyDetection {

    // MARK: - Fake-IP Ranges

    /// IP ranges used by local proxy apps (Surge, Shadowrocket, Quantumult,
    /// Clash, etc.) for fake-IP routing. A DNS response in these ranges is
    /// NOT a leak — it's the proxy doing local DNS so traffic can be routed
    /// through the tunnel. Used by DNS hijack detection, VPN leak checks,
    /// and Privacy Shield to suppress false positives.
    static let fakeIPRangePrefixes: [String] = [
        "198.18.",
        "198.19.",
        "100.100.",
        "10.10.10.",
        "28.0.0."
    ]

    /// Returns true if the given IP address starts with any known proxy fake-IP prefix.
    static func isProxyFakeIP(_ ipString: String) -> Bool {
        fakeIPRangePrefixes.contains { ipString.hasPrefix($0) }
    }

    // MARK: - Known proxy apps

    struct ProxyAppSignature {
        /// Canonical app name (display form).
        let app: String
        /// Lowercase substring searched for in cert issuer/subject or interface names.
        let needle: String
        let category: Category

        enum Category {
            /// Consumer VPN/proxy app (Surge, Shadowrocket, Clash, etc.)
            case vpnApp
            /// Debugging proxy (Charles, mitmproxy) — also covers the generic fingerprints.
            case debuggingProxy
        }
    }

    /// Canonical list of proxy/VPN app signatures. Used by:
    ///   - TLSAnalyzer.isProxyMITMCert (cert chain inspection)
    ///   - CertificateInspector.identifyProxyApp (cert chain → app name)
    ///   - KillSwitchAdvisor.detectProxyApp (SmartVPNDetector reasoning text)
    /// Drift used to be a problem; this is the single source.
    static let knownProxyApps: [ProxyAppSignature] = [
        // Consumer VPN/proxy apps
        .init(app: "Surge",         needle: "surge",         category: .vpnApp),
        .init(app: "Shadowrocket",  needle: "shadowrocket",  category: .vpnApp),
        .init(app: "Quantumult",    needle: "quantumult",    category: .vpnApp),
        .init(app: "Clash",         needle: "clash",         category: .vpnApp),
        .init(app: "Loon",          needle: "loon",          category: .vpnApp),
        .init(app: "Stash",         needle: "stash",         category: .vpnApp),
        // Debugging proxies
        .init(app: "mitmproxy",     needle: "mitmproxy",     category: .debuggingProxy),
        .init(app: "Charles",       needle: "charles",       category: .debuggingProxy),
        .init(app: "Proxyman",      needle: "proxyman",      category: .debuggingProxy),
        .init(app: "Fiddler",       needle: "fiddler",       category: .debuggingProxy),
        // Generic proxy/MITM CA fingerprints — useful when inspecting cert chains
        // (CA subjects often contain these tokens) but NOT against detector
        // reasoning text where "proxy" appears coincidentally.
        .init(app: "Generic proxy CA", needle: "generated", category: .debuggingProxy),
        .init(app: "Generic proxy CA", needle: "proxy",     category: .debuggingProxy),
        .init(app: "Generic proxy CA", needle: "debug",     category: .debuggingProxy),
    ]

    /// Find the first proxy app whose needle matches the given haystack
    /// (case-insensitive). Pass `includeGenericFingerprints: false` when
    /// searching free-form text (e.g. detection reasoning) where the
    /// generic tokens would cause false positives.
    static func detectProxyApp(
        in haystack: String,
        includeGenericFingerprints: Bool = true
    ) -> ProxyAppSignature? {
        let lower = haystack.lowercased()
        return knownProxyApps.first { entry in
            if !includeGenericFingerprints && entry.app == "Generic proxy CA" {
                return false
            }
            return lower.contains(entry.needle)
        }
    }
}
