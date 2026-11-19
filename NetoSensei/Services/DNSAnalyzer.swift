//
//  DNSAnalyzer.swift
//  NetoSensei
//
//  DNS security & privacy analyzer — detects DNS provider, encryption,
//  DNS leaks (when VPN active), and measures resolution speed.
//

import Foundation
import Network

// MARK: - Data Models

struct DNSServerInfo: Identifiable, Equatable {
    let id = UUID()
    let ipAddress: String
    let provider: DNSProviderType
    let isEncrypted: Bool?
    let latencyMs: Double?
    let isSystem: Bool

    var displayName: String {
        if provider != .unknown { return provider.rawValue }
        return ipAddress
    }

    static func == (lhs: DNSServerInfo, rhs: DNSServerInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum DNSProviderType: String {
    case google = "Google DNS"
    case cloudflare = "Cloudflare"
    case cloudflareFamily = "Cloudflare Family"
    case quad9 = "Quad9"
    case openDNS = "OpenDNS"
    case openDNSFamily = "OpenDNS Family"
    case adGuard = "AdGuard"
    case nextDNS = "NextDNS"
    case aliDNS = "AliDNS"
    case dnsPod = "DNSPod"
    case dns114 = "114 DNS"
    case chinaUnicom = "China Unicom"
    case chinaTelecom = "China Telecom"
    case chinaMobile = "China Mobile"
    case isp = "ISP DNS"
    case local = "Local/Router"
    case unknown = "Unknown"

    var isPrivacyFocused: Bool {
        switch self {
        case .cloudflare, .cloudflareFamily, .quad9, .adGuard, .nextDNS:
            return true
        default:
            return false
        }
    }

    var icon: String {
        switch self {
        case .google: return "g.circle"
        case .cloudflare, .cloudflareFamily: return "cloud"
        case .quad9: return "9.circle"
        case .openDNS, .openDNSFamily: return "umbrella"
        case .adGuard: return "shield"
        case .nextDNS: return "arrow.right.circle"
        case .aliDNS, .dnsPod, .dns114: return "server.rack"
        case .chinaUnicom, .chinaTelecom, .chinaMobile: return "antenna.radiowaves.left.and.right"
        case .isp: return "building.2"
        case .local: return "wifi.router"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct DNSLeakTestResult: Identifiable {
    let id = UUID()
    let testServer: String
    let respondingIP: String
    let provider: DNSProviderType
    let country: String?
    let isLeak: Bool
}

struct DNSAnalysisResult {
    let systemDNS: [DNSServerInfo]
    let isEncryptedDNS: Bool?
    let encryptedDNSType: EncryptedDNSType?
    let leakTestResults: [DNSLeakTestResult]
    let hasLeak: Bool?
    let timestamp: Date

    // FIX (Phase 6.1): `detectedDNS` and `averageLatencyMs` were removed. The
    // previous per-server "latency" was bogus — it timed local UDP socket
    // setup (~1ms), never the round-trip to the actual DNS server. Real
    // DNS performance comparisons live in DNS Benchmark, which sends actual
    // queries and measures real RTT. DNS Analyzer is now privacy/security only.

    enum EncryptedDNSType: String {
        case doh = "DNS over HTTPS"
        case dot = "DNS over TLS"
        case unknown = "Unknown"
    }

    var securityRating: SecurityRating {
        if hasLeak == true { return .poor }
        guard let isEncryptedDNS else { return .unknown }
        return isEncryptedDNS ? .good : .fair
    }

    enum SecurityRating: String {
        case unknown = "Unverified"
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        var icon: String {
            switch self {
            case .unknown: return "questionmark.shield"
            case .excellent: return "checkmark.shield.fill"
            case .good: return "checkmark.shield"
            case .fair: return "exclamationmark.shield"
            case .poor: return "xmark.shield"
            }
        }
    }
}

// MARK: - Known DNS Database

private let knownDNSServers: [String: DNSProviderType] = [
    // Google
    "8.8.8.8": .google, "8.8.4.4": .google,
    "2001:4860:4860::8888": .google, "2001:4860:4860::8844": .google,

    // Cloudflare
    "1.1.1.1": .cloudflare, "1.0.0.1": .cloudflare,
    "2606:4700:4700::1111": .cloudflare, "2606:4700:4700::1001": .cloudflare,

    // Cloudflare Family
    "1.1.1.2": .cloudflareFamily, "1.0.0.2": .cloudflareFamily,
    "1.1.1.3": .cloudflareFamily, "1.0.0.3": .cloudflareFamily,

    // Quad9
    "9.9.9.9": .quad9, "149.112.112.112": .quad9, "2620:fe::fe": .quad9,

    // OpenDNS
    "208.67.222.222": .openDNS, "208.67.220.220": .openDNS,
    "208.67.222.123": .openDNSFamily, "208.67.220.123": .openDNSFamily,

    // AdGuard
    "94.140.14.14": .adGuard, "94.140.15.15": .adGuard,

    // China — AliDNS
    "223.5.5.5": .aliDNS, "223.6.6.6": .aliDNS,

    // China — DNSPod (Tencent)
    "119.29.29.29": .dnsPod, "182.254.116.116": .dnsPod,

    // China — 114 DNS
    "114.114.114.114": .dns114, "114.114.115.115": .dns114,

    // China Telecom
    "202.96.128.86": .chinaTelecom, "202.96.128.166": .chinaTelecom,

    // China Unicom
    "221.6.4.66": .chinaUnicom, "221.6.4.67": .chinaUnicom,

    // China Mobile
    "211.137.96.205": .chinaMobile, "211.138.180.2": .chinaMobile,
]

// MARK: - DNS Analyzer Service

@MainActor
final class DNSAnalyzer: ObservableObject {
    static let shared = DNSAnalyzer()
    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var currentStep = ""
    @Published var result: DNSAnalysisResult?
    @Published var error: String?
    private let resolver: () -> String?
    init(resolver: (() -> String?)? = nil) {
        self.resolver = resolver ?? { NetworkMonitorService.shared.currentStatus.dns.resolverIP }
    }
    func runFullAnalysis() async -> DNSAnalysisResult {
        isAnalyzing = true
        defer { isAnalyzing = false }
        currentStep = "Reading available resolver information"
        progress = 0.5; error = nil
        let servers = resolver().map { address in
            [DNSServerInfo(ipAddress: address, provider: Self.identifyProvider(ip: address), isEncrypted: nil, latencyMs: nil, isSystem: true)]
        } ?? []
        let observed = DNSAnalysisResult(systemDNS: servers, isEncryptedDNS: nil, encryptedDNSType: nil,
            leakTestResults: [], hasLeak: nil, timestamp: Date())
        result = observed; progress = 1; currentStep = "Complete"
        return observed
    }
    nonisolated static func identifyProvider(ip: String) -> DNSProviderType {
        if let provider = knownDNSServers[ip] { return provider }
        var address = in_addr()
        if inet_pton(AF_INET, ip, &address) == 1 {
            let value = UInt32(bigEndian: address.s_addr)
            if value >> 24 == 10 || value >> 16 == 0xC0A8 || value >> 20 == 0xAC1 { return .local }
        }
        return .unknown // Prefixes do not identify the operator of an arbitrary IP.
    }
}
