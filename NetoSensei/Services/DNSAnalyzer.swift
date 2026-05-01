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
    let isEncrypted: Bool
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
    let isEncryptedDNS: Bool
    let encryptedDNSType: EncryptedDNSType?
    let leakTestResults: [DNSLeakTestResult]
    let hasLeak: Bool
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
        if hasLeak { return .poor }
        if isEncryptedDNS { return .excellent }
        if systemDNS.contains(where: { $0.provider.isPrivacyFocused }) { return .good }
        return .fair
    }

    enum SecurityRating: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        var icon: String {
            switch self {
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
class DNSAnalyzer: ObservableObject {
    static let shared = DNSAnalyzer()

    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var currentStep = ""
    @Published var result: DNSAnalysisResult?
    @Published var error: String?

    private init() {}

    // MARK: - Main Analysis

    func runFullAnalysis() async -> DNSAnalysisResult {
        return await BackgroundTaskManager.shared.runInBackground(
            id: "dnsAnalysis",
            name: "DNS Analysis",
            operation: {
                return await self.performFullAnalysis()
            },
            resultFormatter: { result in
                "Rating: \(result.securityRating.rawValue)"
            }
        )
    }

    private func performFullAnalysis() async -> DNSAnalysisResult {
        // FIX (Phase 6.1): scoped down to privacy/security analysis only.
        // Removed steps that produced bogus numbers:
        //   - "Detect actual DNS" probed UDP `.ready` (socket setup), not RTT
        //   - "Measure latency" used getaddrinfo through the system resolver,
        //     which goes through the proxy/VPN's local fake DNS — every server
        //     looked like 1ms. DNS Benchmark handles real per-server latency.
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        isAnalyzing = true
        progress = 0
        error = nil

        // Step 1: Get system DNS servers (the resolver actually in use)
        currentStep = "Reading system DNS..."
        progress = 0.2
        let systemDNS = await getSystemDNSServers()

        // Step 2: Check for encrypted DNS (DoH/DoT)
        currentStep = "Checking encryption..."
        progress = 0.5
        let (isEncrypted, encryptedType) = await checkEncryptedDNS()

        // Step 3: DNS leak test (only meaningful when VPN active)
        currentStep = "Testing for DNS leaks..."
        progress = 0.8
        var leakResults: [DNSLeakTestResult] = []
        var hasLeak = false

        if vpnActive {
            leakResults = await runDNSLeakTest()
            hasLeak = leakResults.contains { $0.isLeak }
        }

        let analysisResult = DNSAnalysisResult(
            systemDNS: systemDNS,
            isEncryptedDNS: isEncrypted,
            encryptedDNSType: encryptedType,
            leakTestResults: leakResults,
            hasLeak: hasLeak,
            timestamp: Date()
        )

        result = analysisResult
        progress = 1.0
        currentStep = "Complete"
        isAnalyzing = false

        return analysisResult
    }

    // MARK: - Get System DNS

    private nonisolated func getSystemDNSServers() async -> [DNSServerInfo] {
        var servers: [DNSServerInfo] = []

        // Read from existing NetworkMonitorService DNS info
        let resolverIP = await NetworkMonitorService.shared.currentStatus.dns.resolverIP
        if let ip = resolverIP {
            let provider = identifyProvider(ip: ip)
            servers.append(DNSServerInfo(
                ipAddress: ip,
                provider: provider,
                isEncrypted: false,
                latencyMs: await NetworkMonitorService.shared.currentStatus.dns.latency,
                isSystem: true
            ))
        }

        // Gateway as DNS forwarder
        let gatewayIP = await NetworkMonitorService.shared.currentStatus.router.gatewayIP
        if let gateway = gatewayIP, !servers.contains(where: { $0.ipAddress == gateway }) {
            servers.append(DNSServerInfo(
                ipAddress: gateway,
                provider: .local,
                isEncrypted: false,
                latencyMs: nil,
                isSystem: true
            ))
        }

        return servers
    }

    // FIX (Phase 6.1): `detectActualDNS`, `fetchCloudflareTrace`, `measureDNSLatency`,
    // and `probeDNS` were removed. They produced misleading per-server latency
    // numbers — `probeDNS` waited for UDP `.ready` (which fires after local
    // socket setup, not after a server response), and `measureDNSLatency`
    // used getaddrinfo (the system resolver, not the listed servers).
    // Real per-server DNS performance lives in DNSBenchmark.

    // MARK: - Check Encrypted DNS

    private nonisolated func checkEncryptedDNS() async -> (Bool, DNSAnalysisResult.EncryptedDNSType?) {
        // Heuristic: Check if DoT port 853 is reachable on known providers
        // If DoT is open and responding with TLS, encrypted DNS is likely configured

        let dotServers = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
        for server in dotServers {
            if await checkPort(ip: server, port: 853) {
                return (true, .dot)
            }
        }

        // Check if gateway is forwarding DNS on port 53 (traditional)
        let gatewayIP = await NetworkMonitorService.shared.currentStatus.router.gatewayIP
        if let gateway = gatewayIP {
            let gatewayHasDNS = await checkPort(ip: gateway, port: 53)
            if !gatewayHasDNS {
                // Gateway not serving DNS on 53 but resolution works = likely encrypted
                return (true, .doh)
            }
        }

        return (false, nil)
    }

    /// Thread-safe once-guard for NWConnection callbacks.
    private final class OnceFlag: @unchecked Sendable {
        private var _done = false
        private let lock = NSLock()
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _done { return false }
            _done = true
            return true
        }
    }

    private nonisolated func checkPort(ip: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ip)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(to: .hostPort(host: host, port: nwPort), using: .tcp)
            let flag = OnceFlag()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if flag.claim() {
                        continuation.resume(returning: false)
                    }
                case .waiting:
                    if flag.claim() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if flag.claim() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - DNS Leak Test

    private nonisolated func runDNSLeakTest() async -> [DNSLeakTestResult] {
        var results: [DNSLeakTestResult] = []

        // Resolve well-known domains and check which IP responds
        let testDomains = [
            ("resolver1.opendns.com", "OpenDNS"),
            ("whoami.akamai.net", "Akamai"),
        ]

        for (domain, serverName) in testDomains {
            if let ip = await resolveDomain(domain) {
                let provider = identifyProvider(ip: ip)

                // Leak = DNS resolving outside VPN tunnel (ISP or local DNS responding)
                let isLeak = provider == .isp
                    || provider == .chinaUnicom
                    || provider == .chinaTelecom
                    || provider == .chinaMobile
                    || provider == .local

                results.append(DNSLeakTestResult(
                    testServer: serverName,
                    respondingIP: ip,
                    provider: provider,
                    country: nil,
                    isLeak: isLeak
                ))
            }
        }

        return results
    }

    private nonisolated func resolveDomain(_ domain: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var hints = addrinfo(
                ai_flags: AI_DEFAULT,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )

            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(domain, nil, &hints, &result)

            defer {
                if result != nil { freeaddrinfo(result) }
            }

            guard status == 0, let res = result else {
                continuation.resume(returning: nil)
                return
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if let addr = res.pointee.ai_addr {
                getnameinfo(
                    addr, socklen_t(res.pointee.ai_addrlen),
                    &hostname, socklen_t(hostname.count),
                    nil, 0, NI_NUMERICHOST
                )
                continuation.resume(returning: String(cString: hostname))
            } else {
                continuation.resume(returning: nil)
            }
        }
    }

    // FIX (Phase 6.1): `measureDNSLatency` and `probeDNS` removed. They produced
    // misleading numbers — see the explanatory comment near `performFullAnalysis`.
    // Use DNSBenchmark for honest per-server DNS RTT.

    // MARK: - Helpers

    private nonisolated func identifyProvider(ip: String) -> DNSProviderType {
        if let known = knownDNSServers[ip] {
            return known
        }

        // Private IP ranges = local/router
        if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
            return .local
        }

        // Chinese IP ranges (common ISP prefixes)
        if ip.hasPrefix("202.") || ip.hasPrefix("221.") || ip.hasPrefix("211.") ||
            ip.hasPrefix("218.") || ip.hasPrefix("220.") || ip.hasPrefix("222.") {
            return .isp
        }

        return .unknown
    }
}
