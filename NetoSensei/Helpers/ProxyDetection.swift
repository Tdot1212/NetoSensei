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
}
