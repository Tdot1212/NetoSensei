//
//  PrivacyShieldService.swift
//  NetoSensei
//
//  Privacy and security check service for the Security tab
//  Performs: VPN status, DNS privacy, IP visibility, WebRTC leak, HTTPS integrity
//

import Foundation
import Network

// MARK: - Privacy Shield Status

struct PrivacyShieldStatus {
    let vpnStatus: CheckResult
    let dnsPrivacy: CheckResult
    let ipHidden: CheckResult
    let webRTCLeak: CheckResult
    let httpsIntegrity: CheckResult
    /// FIX (Sec Issue 2): 6th check — surface native ISP IPv6 that bypasses
    /// the VPN tunnel as a first-class verdict, not buried in a debug list.
    let ipv6Leak: CheckResult

    var overallStatus: OverallStatus {
        let checks = [vpnStatus, dnsPrivacy, ipHidden, webRTCLeak, httpsIntegrity, ipv6Leak]
        if checks.allSatisfy(\.passed) { return .protected }
        if checks.contains(where: { $0.severity == .failed }) { return .exposed }
        return .partiallyProtected
    }

    enum OverallStatus {
        case protected
        case partiallyProtected
        case exposed

        var displayText: String {
            switch self {
            case .protected: return "All Checks Passed"
            case .partiallyProtected: return "Privacy Unverified"
            case .exposed: return "Checks Failed"
            }
        }

        var systemImage: String {
            switch self {
            case .protected: return "checkmark.shield.fill"
            case .partiallyProtected: return "exclamationmark.shield.fill"
            case .exposed: return "xmark.shield.fill"
            }
        }
    }

    struct CheckResult {
        let passed: Bool
        let title: String
        let detail: String
        let recommendation: String?
        /// FIX (Sec Issue 2): explicit severity for tri-color rendering.
        /// Older call-sites construct CheckResult without specifying severity;
        /// for them, severity is derived from `passed` (true → .passed,
        /// false → .failed). Only the new IPv6 check uses `.warning`.
        private var explicitSeverity: Severity?

        enum Severity {
            case passed
            case warning
            case failed
        }

        var severity: Severity {
            if let s = explicitSeverity { return s }
            return passed ? .passed : .failed
        }

        // Backward-compatible initializer for the existing 5 checks.
        init(passed: Bool, title: String, detail: String, recommendation: String?) {
            self.passed = passed
            self.title = title
            self.detail = detail
            self.recommendation = recommendation
            self.explicitSeverity = nil
        }

        // New initializer that explicitly sets severity (used by IPv6 check).
        init(passed: Bool, title: String, detail: String, recommendation: String?, severity: Severity) {
            self.passed = passed
            self.title = title
            self.detail = detail
            self.recommendation = recommendation
            self.explicitSeverity = severity
        }
    }
}

// MARK: - Exposure Info

struct ExposureInfo {
    let publicIP: String?
    let visibleLocation: String?
    let visibleISP: String?
    let ipType: String
    let isRealIP: Bool

    var locationDetail: String {
        if let loc = visibleLocation {
            return "Approximate IP geolocation: \(loc). This is not a GPS location."
        }
        return "Location unknown"
    }
}

// MARK: - WiFi Safety Result

struct WiFiSafetyResult {
    let overallStatus: SafetyStatus
    let checks: [SafetyCheck]

    enum SafetyStatus {
        case safe
        case caution
        case unsafe

        var displayText: String {
            switch self {
            case .safe: return "Safe"
            case .caution: return "Caution"
            case .unsafe: return "Unsafe"
            }
        }

        var systemImage: String {
            switch self {
            case .safe: return "checkmark.circle.fill"
            case .caution: return "exclamationmark.triangle.fill"
            case .unsafe: return "xmark.octagon.fill"
            }
        }
    }

    struct SafetyCheck {
        let title: String
        let detail: String
        let status: CheckStatus

        enum CheckStatus {
            case passed
            case warning
            case failed
        }
    }
}

// MARK: - VPN Leak Test Result

struct VPNLeakTestResult {
    let dnsLeak: LeakCheck
    let ipLeak: LeakCheck
    let webRTCLeak: LeakCheck
    let overallVerdict: Verdict
    let vpnServerIP: String?
    let detectedDNSServers: [String]
    let timestamp: Date

    struct LeakCheck {
        let name: String
        let isLeaking: Bool
        let detail: String
        let severity: Severity
        let solution: String?

        enum Severity {
            case safe
            case warning
            case critical
        }
    }

    enum Verdict {
        case unverified
        case noLeaks
        case minorLeaks
        case majorLeaks
        case noVPN

        var displayText: String {
            switch self {
            case .unverified: return "Leak Protection Unverified"
            case .noLeaks: return "No Leaks Detected"
            case .minorLeaks: return "Minor Leaks Found"
            case .majorLeaks: return "Major Leaks Found"
            case .noVPN: return "No VPN Connected"
            }
        }

        var systemImage: String {
            switch self {
            case .unverified: return "questionmark.shield"
            case .noLeaks: return "checkmark.shield.fill"
            case .minorLeaks: return "exclamationmark.shield.fill"
            case .majorLeaks: return "xmark.shield.fill"
            case .noVPN: return "shield.slash.fill"
            }
        }
    }
}

// MARK: - Privacy Shield Service

@MainActor
class PrivacyShieldService: ObservableObject {
    static let shared = PrivacyShieldService()

    @Published var privacyStatus: PrivacyShieldStatus?
    @Published var exposureInfo: ExposureInfo?
    @Published var wifiSafetyResult: WiFiSafetyResult?
    @Published var isCheckingPrivacy = false
    @Published var isCheckingWiFi = false
    @Published var isRunningLeakTest = false
    @Published var lastLeakTestResult: VPNLeakTestResult?

    private init() {}

    // MARK: - Main Privacy Check

    func checkPrivacyShield() async {
        isCheckingPrivacy = true
        defer { isCheckingPrivacy = false }

        // Ensure SmartVPNDetector cache is populated before the 6 row-checks
        // read from it. forceRefresh: false respects the 30s cooldown — when
        // Full Check just ran, this is a no-op.
        _ = await SmartVPNDetector.shared.detectVPN(forceRefresh: false)

        // Run all checks concurrently
        async let vpnCheck = checkVPNStatus()
        async let dnsCheck = checkDNSPrivacy()
        async let ipCheck = checkIPHidden()
        async let webRTCCheck = checkWebRTCLeak()
        async let httpsCheck = checkHTTPSIntegrity()
        // FIX (Sec Issue 2): 6th check — surface native IPv6 leak.
        async let ipv6Check = checkIPv6Leak()

        let (vpn, dns, ip, webrtc, https, ipv6) =
            await (vpnCheck, dnsCheck, ipCheck, webRTCCheck, httpsCheck, ipv6Check)

        privacyStatus = PrivacyShieldStatus(
            vpnStatus: vpn,
            dnsPrivacy: dns,
            ipHidden: ip,
            webRTCLeak: webrtc,
            httpsIntegrity: https,
            ipv6Leak: ipv6
        )

        // Also update exposure info
        await updateExposureInfo()
    }

    // MARK: - IPv6 Leak Check (Sec Issue 2)

    /// Checks whether native ISP IPv6 is present alongside an active VPN.
    /// SmartVPNDetector already detects this via `IPv6 Check` method — this
    /// surfaces the same finding as a top-level Privacy Shield row.
    private func checkIPv6Leak() async -> PrivacyShieldStatus.CheckResult {
        PrivacyShieldStatus.CheckResult(passed: false, title: "IPv6 Protection Unverified",
            detail: "An interface address does not establish whether a remote IPv6 request bypasses a VPN. No end-to-end IPv6 routing test was completed.",
            recommendation: nil, severity: .warning)
    }

    // MARK: - VPN Status Check

    private func checkVPNStatus() async -> PrivacyShieldStatus.CheckResult {
        let vpnResult = SmartVPNDetector.shared.detectionResult
        let vpnState = vpnResult?.vpnState ?? .unknown

        switch vpnState {
        case .on:
            return PrivacyShieldStatus.CheckResult(
                passed: true,
                title: "VPN",
                detail: "VPN connected (confirmed by system)",
                recommendation: nil
            )
        case .probablyOn:
            return PrivacyShieldStatus.CheckResult(
                passed: true,
                title: "VPN",
                detail: "VPN/Proxy detected (inferred from IP, not confirmed by system)",
                recommendation: nil
            )
        case .connecting:
            return PrivacyShieldStatus.CheckResult(
                passed: false,
                title: "VPN",
                detail: "VPN is connecting...",
                recommendation: "Wait for VPN connection to complete"
            )
        default:
            return PrivacyShieldStatus.CheckResult(
                passed: false,
                title: "VPN",
                detail: "No VPN detected; HTTPS can still encrypt application traffic",
                recommendation: nil, severity: .warning
            )
        }
    }

    // MARK: - DNS Privacy Check

    private func checkDNSPrivacy() async -> PrivacyShieldStatus.CheckResult {
        let vpnResult = SmartVPNDetector.shared.detectionResult
        let vpnActive = vpnResult?.isVPNActive ?? false

        // If no VPN, DNS privacy isn't expected
        guard vpnActive else {
            return PrivacyShieldStatus.CheckResult(
                passed: false,
                title: "DNS Privacy Unverified",
                detail: "The active DNS transport has not been measured. Encrypted DNS can also be configured without a VPN.",
                recommendation: nil, severity: .warning
            )
        }

        // Neither a VPN-active flag nor the configured resolver proves the
        // transport taken by a DNS query. No resolver-path test exists here.
        return PrivacyShieldStatus.CheckResult(
            passed: false,
            title: "DNS Privacy Unverified",
            detail: "VPN is active, but the DNS query path was not measured",
            recommendation: "Review DNS settings in your VPN app",
            severity: .warning
        )
    }

    // MARK: - IP Hidden Check

    private func checkIPHidden() async -> PrivacyShieldStatus.CheckResult {
        let ip = SmartVPNDetector.shared.detectionResult?.publicIP
        return PrivacyShieldStatus.CheckResult(passed: false, title: "IP Routing Unverified",
            detail: ip.map { "Observed public egress: \($0). A baseline and per-route comparison are needed to establish VPN bypass." }
                ?? "Public egress unavailable; VPN bypass cannot be assessed.",
            recommendation: nil, severity: .warning)
    }

    // MARK: - WebRTC Leak Check

    private func checkWebRTCLeak() async -> PrivacyShieldStatus.CheckResult {
        // WebRTC leaks are a BROWSER issue, not relevant for native iOS apps.
        // iOS apps do not use WebRTC for IP discovery.
        // Showing this check as always-passed with honest explanation.
        return PrivacyShieldStatus.CheckResult(
            passed: false,
            title: "Browser WebRTC Unverified",
            detail: "This native check does not test browser WebRTC behavior",
            recommendation: nil, severity: .warning
        )
    }

    // MARK: - HTTPS Integrity Check

    private func checkHTTPSIntegrity() async -> PrivacyShieldStatus.CheckResult {
        // FIXED: Test HTTPS with China-accessible sites
        // google.com is blocked in China, causing false "HTTPS blocked" alarms
        let testURLs = [
            "https://www.apple.com",
            "https://www.baidu.com",
            "https://www.qq.com"
        ]

        var passedCount = 0

        for urlString in testURLs {
            guard let url = URL(string: urlString) else { continue }

            do {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 5
                let session = URLSession(configuration: config)

                let (_, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    passedCount += 1
                }
            } catch {
                // Connection failed
            }
        }

        let allPassed = passedCount == testURLs.count
        let somePassed = passedCount > 0

        if allPassed {
            return PrivacyShieldStatus.CheckResult(
                passed: true,
                title: "HTTPS",
                detail: "HTTPS connections work correctly to all test sites",
                recommendation: nil
            )
        } else if somePassed {
            // CHINA RULE 4: Overseas HTTPS timeout ≠ Interception
            return PrivacyShieldStatus.CheckResult(
                passed: true,
                title: "HTTPS",
                detail: "HTTPS works to \(passedCount)/\(testURLs.count) test sites. Some may be unreachable cross-border.",
                recommendation: nil
            )
        } else {
            return PrivacyShieldStatus.CheckResult(
                passed: false,
                title: "HTTPS",
                detail: "Cross-border HTTPS unreachable — this may be a network restriction, not interception",
                recommendation: (SmartVPNDetector.shared.detectionResult?.vpnState.isLikelyOn ?? false)
                    ? "HTTPS unreachable despite VPN — check VPN server or network restrictions"
                    : "Try connecting to a VPN or check network restrictions"
            )
        }
    }

    // MARK: - Exposure Info Update

    func updateExposureInfo() async {
        let vpnResult = SmartVPNDetector.shared.detectionResult
        let vpnActive = vpnResult?.isVPNActive ?? false

        let publicIP = vpnResult?.publicIP
        let country = vpnResult?.publicCountry
        let city = vpnResult?.publicCity
        let isp = vpnResult?.publicISP

        let ipType = "Unverified (provider metadata only)"

        let location: String?
        if let c = city, let co = country {
            location = "\(c), \(co)"
        } else if let co = country {
            location = co
        } else {
            location = nil
        }

        exposureInfo = ExposureInfo(
            publicIP: publicIP,
            visibleLocation: location,
            visibleISP: isp,
            ipType: ipType,
            isRealIP: !vpnActive
        )
    }

    // MARK: - WiFi Safety Check

    func checkWiFiSafety(portal: CaptivePortalResult, vpn: SmartVPNDetector.VPNDetectionResult) async -> WiFiSafetyResult {
        isCheckingWiFi = true
        defer { isCheckingWiFi = false }

        var checks: [WiFiSafetyResult.SafetyCheck] = []

        // 1. Check if network is open (no password)
        let networkStatus = NetworkMonitorService.shared.currentStatus
        let ssid = networkStatus.wifi.ssid

        // We can't directly detect if WiFi is open on iOS without entitlements
        // But we can note the SSID for the user
        if let ssid = ssid {
            checks.append(WiFiSafetyResult.SafetyCheck(
                title: "Network: \(ssid)",
                detail: "Connected to WiFi network",
                status: .passed
            ))
        } else {
            checks.append(WiFiSafetyResult.SafetyCheck(
                title: "Network: Unknown",
                detail: "Could not identify WiFi network",
                status: .warning
            ))
        }

        // 2. Check VPN status
        let vpnActive = vpn.vpnState.isLikelyOn
        checks.append(WiFiSafetyResult.SafetyCheck(
            title: "VPN Protection",
            detail: vpnActive ? "Possible VPN or proxy. Traffic coverage is unverified." : "No VPN detected; HTTPS can still encrypt application traffic",
            status: .warning
        ))

        checks.append(WiFiSafetyResult.SafetyCheck(title: "Captive Portal",
            detail: portal.verdict == .noPortal ? "Known portal probes returned expected responses" : (portal.verdict == .portalDetected ? "Login page detected by the portal probes" : "Login requirement unverified"),
            status: portal.verdict == .noPortal ? .passed : .warning))
        checks.append(WiFiSafetyResult.SafetyCheck(title: "DNS Query Integrity",
            detail: "Not verified. A successful lookup does not establish DNS integrity.", status: .warning))

        // 5. Check HTTPS
        let httpsWorks = await checkBasicHTTPS()
        checks.append(WiFiSafetyResult.SafetyCheck(
            title: "HTTPS Connections",
            detail: httpsWorks ? "A tested HTTPS endpoint responded" : "HTTPS response unavailable; cause unknown",
            status: httpsWorks ? .passed : .warning
        ))

        // Determine overall status
        let failedCount = checks.filter { $0.status == .failed }.count
        let warningCount = checks.filter { $0.status == .warning }.count

        let overallStatus: WiFiSafetyResult.SafetyStatus
        if failedCount > 0 {
            overallStatus = .unsafe
        } else if warningCount > 0 {
            overallStatus = .caution
        } else {
            overallStatus = .safe
        }

        let result = WiFiSafetyResult(overallStatus: overallStatus, checks: checks)
        wifiSafetyResult = result
        return result
    }

    // MARK: - Helper Methods

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    private func checkCaptivePortal() async -> Bool {
        // Apple's captive portal check URL
        let captiveCheckURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!

        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            let session = URLSession(configuration: config)

            let (data, response) = try await session.data(from: captiveCheckURL)

            // If we get redirected or don't get "Success", there's a captive portal
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let content = String(data: data, encoding: .utf8) ?? ""
                    return !content.contains("Success")
                }
            }
            return true
        } catch {
            // If we can't connect, assume no captive portal issue
            return false
        }
    }

    private func checkDNSHijacking() async -> Bool {
        // Try to resolve a non-existent domain.
        // If it resolves to a real IP, DNS is likely being hijacked.
        // Proxy fake-IP routing (Surge/Shadowrocket) returns 198.18.x.x for
        // every domain including NXDOMAIN — that's not hijacking, it's normal
        // proxy behavior, so we exempt those ranges.
        let fakeDomain = "this-domain-does-not-exist-\(UUID().uuidString.prefix(8)).com"

        return await withCheckedContinuation { continuation in
            let host = CFHostCreateWithName(nil, fakeDomain as CFString).takeRetainedValue()
            CFHostStartInfoResolution(host, .addresses, nil)

            var resolved = DarwinBoolean(false)
            guard let addresses = CFHostGetAddressing(host, &resolved)?.takeUnretainedValue() as? [Data],
                  !addresses.isEmpty else {
                continuation.resume(returning: false)
                return
            }

            // CLEANUP 5: shared ranges via ProxyDetection.isProxyFakeIP
            let resolvedIPs = addresses.compactMap { Self.ipString(from: $0) }
            let allProxyFake = !resolvedIPs.isEmpty && resolvedIPs.allSatisfy { ip in
                ProxyDetection.isProxyFakeIP(ip)
            }
            // Real IPs returned for NXDOMAIN → ISP hijack. Proxy fake → normal.
            continuation.resume(returning: !allProxyFake)
        }
    }

    private static func ipString(from sockaddrData: Data) -> String? {
        sockaddrData.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let sa = base.assumingMemoryBound(to: sockaddr.self)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(sa, socklen_t(sockaddrData.count),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            return result == 0 ? String(cString: host) : nil
        }
    }

    private func checkBasicHTTPS() async -> Bool {
        // FIXED: Use apple.com instead of google.com (blocked in China)
        guard let url = URL(string: "https://www.apple.com") else { return false }

        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            let session = URLSession(configuration: config)

            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - VPN Leak Test

    /// - Parameter prefetchedVPNResult: when non-nil, skip the internal
    ///   force-refresh of `SmartVPNDetector` and use the supplied snapshot.
    ///   The combined Security Check flow refreshes once up front and passes
    ///   the result here — eliminating a redundant cache invalidation that
    ///   would race with `checkWiFiSafety()` reading the same shared cache.
    ///   Legacy call-sites pass nothing → behavior is unchanged.
    func runVPNLeakTest(
        prefetchedVPNResult: SmartVPNDetector.VPNDetectionResult? = nil
    ) async -> VPNLeakTestResult {
        isRunningLeakTest = true
        defer { isRunningLeakTest = false }

        // Use the prefetched detection result when supplied; otherwise force a
        // fresh detection (legacy behavior).
        let vpnResult: SmartVPNDetector.VPNDetectionResult
        if let prefetched = prefetchedVPNResult {
            vpnResult = prefetched
        } else {
            vpnResult = await SmartVPNDetector.shared.detectVPN(forceRefresh: true)
        }
        let vpnActive = vpnResult.isVPNActive

        // If no VPN, return early
        guard vpnActive else {
            return VPNLeakTestResult(
                dnsLeak: VPNLeakTestResult.LeakCheck(
                    name: "DNS Leak",
                    isLeaking: false,
                    detail: "No VPN connected to test",
                    severity: .safe,
                    solution: nil
                ),
                ipLeak: VPNLeakTestResult.LeakCheck(
                    name: "IP Leak",
                    isLeaking: false,
                    detail: "No VPN connected to test",
                    severity: .safe,
                    solution: nil
                ),
                webRTCLeak: VPNLeakTestResult.LeakCheck(
                    name: "WebRTC Leak",
                    isLeaking: false,
                    detail: "No VPN connected to test",
                    severity: .safe,
                    solution: nil
                ),
                overallVerdict: .noVPN,
                vpnServerIP: nil,
                detectedDNSServers: [],
                timestamp: Date()
            )
        }

        // Run leak tests concurrently
        async let dnsCheck = performDNSLeakTest(vpnResult: vpnResult)
        async let ipCheck = performIPLeakTest(vpnResult: vpnResult)
        async let webrtcCheck = performWebRTCLeakTest()

        let (dns, ip, webrtc) = await (dnsCheck, ipCheck, webrtcCheck)

        // Determine overall verdict
        let criticalCount = [dns, ip, webrtc].filter { $0.severity == .critical }.count
        let warningCount = [dns, ip, webrtc].filter { $0.severity == .warning }.count

        let verdict: VPNLeakTestResult.Verdict
        if criticalCount > 0 {
            verdict = .majorLeaks
        } else if warningCount > 0 {
            verdict = .unverified
        } else {
            verdict = .noLeaks
        }

        // Get DNS servers used
        let dnsServers = getDNSServers()

        let result = VPNLeakTestResult(
            dnsLeak: dns,
            ipLeak: ip,
            webRTCLeak: webrtc,
            overallVerdict: verdict,
            vpnServerIP: vpnResult.publicIP,
            detectedDNSServers: dnsServers,
            timestamp: Date()
        )
        lastLeakTestResult = result
        return result
    }

    private func performDNSLeakTest(vpnResult: SmartVPNDetector.VPNDetectionResult) async -> VPNLeakTestResult.LeakCheck {
        VPNLeakTestResult.LeakCheck(name: "DNS Privacy", isLeaking: false,
            detail: "Not measured. Resolver addresses and ordinary hostname answers do not establish the route of DNS queries.",
            severity: .warning, solution: "Review DNS routing in your VPN app. A controlled DNS leak test is required to verify protection.")
    }

    private func performIPLeakTest(vpnResult: SmartVPNDetector.VPNDetectionResult) async -> VPNLeakTestResult.LeakCheck {
        // Compare public IP from multiple services
        // If they return different IPs, there may be a split-tunnel leak
        let services = [
            "https://api.ipify.org?format=json",
            "https://ipwho.is/"
        ]

        var detectedIPs: Set<String> = []
        if let vpnIP = vpnResult.publicIP {
            detectedIPs.insert(vpnIP)
        }

        for serviceURL in services {
            guard let url = URL(string: serviceURL) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ip = json["ip"] as? String {
                    detectedIPs.insert(ip)
                }
            } catch {
                // Service unavailable, skip
            }
        }

        return VPNLeakTestResult.LeakCheck(name: "Observed public IP", isLeaking: false,
            detail: detectedIPs.isEmpty
                ? "No public IP response was obtained; leak protection is unverified."
                : "Observed: \(detectedIPs.sorted().joined(separator: ", ")). Multiple IPs may reflect IPv4/IPv6 or routing differences. No direct-path baseline was measured.",
            severity: .warning, solution: "Verify the expected VPN exit and split-tunnel settings in your VPN app.")
    }

    private func performWebRTCLeakTest() async -> VPNLeakTestResult.LeakCheck {
        VPNLeakTestResult.LeakCheck(name: "Browser WebRTC", isLeaking: false,
            detail: "Browser WebRTC behavior was not tested by this native network check.",
            severity: .warning, solution: nil)
    }

    private func getDNSServers() -> [String] {
        // Read DNS servers from resolv.conf (works on iOS)
        var servers: [String] = []
        guard let content = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else {
            // Fallback: check NetworkMonitorService cached DNS
            if let dns = NetworkMonitorService.shared.currentStatus.dns.resolverIP {
                return [dns]
            }
            return []
        }

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("nameserver") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    servers.append(parts[1])
                }
            }
        }

        return servers
    }

    private func resolveDomain(_ domain: String) async -> String? {
        await SystemDNSResolver.resolve(domain)?.addresses.first
    }
}
