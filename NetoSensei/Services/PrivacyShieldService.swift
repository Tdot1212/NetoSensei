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
        let passedCount = checks.filter { $0.passed }.count
        let warningCount = checks.filter { $0.severity == .warning }.count

        // FIX (Sec Issue 2): Any warning-severity check (e.g. IPv6 leak under
        // VPN) downgrades the top verdict — the previous logic counted only
        // pass/fail and would still say "All Checks Passed" while a real leak
        // was flagged underneath.
        if passedCount == checks.count {
            return .protected
        } else if warningCount > 0 && passedCount + warningCount >= 4 {
            return .partiallyProtected
        } else if passedCount >= 3 {
            return .partiallyProtected
        } else {
            return .exposed
        }
    }

    enum OverallStatus {
        case protected
        case partiallyProtected
        case exposed

        var displayText: String {
            switch self {
            case .protected: return "All Checks Passed"
            case .partiallyProtected: return "Partial Protection"
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
            return isRealIP ? "Your real location is visible" : "Websites think you're in \(loc)"
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
        case noLeaks
        case minorLeaks
        case majorLeaks
        case noVPN

        var displayText: String {
            switch self {
            case .noLeaks: return "No Leaks Detected"
            case .minorLeaks: return "Minor Leaks Found"
            case .majorLeaks: return "Major Leaks Found"
            case .noVPN: return "No VPN Connected"
            }
        }

        var systemImage: String {
            switch self {
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
        let vpnResult = SmartVPNDetector.shared.detectionResult
        let vpnLikelyOn = vpnResult?.vpnState.isLikelyOn ?? false

        // The IPv6 Check method emits "Native ISP IPv6 present" when residential
        // IPv6 is exposed outside the tunnel.
        let nativeIPv6Detected: Bool = {
            guard let methods = vpnResult?.methodResults else { return false }
            return methods.contains {
                $0.method == "IPv6 Check" && $0.detail.lowercased().contains("native isp ipv6")
            }
        }()

        if vpnLikelyOn && nativeIPv6Detected {
            // Real partial-protection state — VPN is up but IPv6 bypasses it.
            return PrivacyShieldStatus.CheckResult(
                passed: false,
                title: "IPv6 Leak",
                detail: "Your ISP IPv6 address is visible to websites that prefer IPv6. VPN protection is incomplete.",
                recommendation: "To fix: disable IPv6 in your proxy app settings (Surge / Shadowrocket: Settings → IPv6 → Off), OR use a VPN profile that tunnels IPv6.",
                severity: .warning
            )
        }

        // No VPN: IPv6 leak doesn't apply (no tunnel to leak around).
        // VPN active and no native IPv6: pass.
        return PrivacyShieldStatus.CheckResult(
            passed: true,
            title: "IPv6 Leak",
            detail: vpnLikelyOn
                ? "No native IPv6 leak detected — IPv6 traffic appears to route through VPN"
                : "Not applicable — no VPN active",
            recommendation: nil,
            severity: .passed
        )
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
                detail: "No VPN detected — traffic visible to ISP",
                recommendation: "Connect to a VPN to encrypt your traffic"
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
                title: "DNS Private",
                detail: "DNS queries are visible to your ISP",
                recommendation: "Connect to a VPN to hide DNS queries"
            )
        }

        // Check if DNS resolver appears to be through VPN
        // Chinese ISP DNS servers typically start with these prefixes
        let chinaISPDNS = ["202.96.", "218.2.", "114.114.", "119.29.", "223.5.", "223.6.", "182.254."]

        // Get current DNS resolver from network status
        let dnsServer = NetworkMonitorService.shared.currentStatus.dns.resolverIP

        if let dns = dnsServer, chinaISPDNS.contains(where: { dns.hasPrefix($0) }) {
            return PrivacyShieldStatus.CheckResult(
                passed: false,
                title: "DNS Private",
                detail: "DNS queries may be leaking to your local ISP (\(dns))",
                recommendation: "Configure your VPN to use its own DNS servers"
            )
        }

        return PrivacyShieldStatus.CheckResult(
            passed: true,
            title: "DNS Private",
            detail: "DNS queries go through your VPN",
            recommendation: nil
        )
    }

    // MARK: - IP Hidden Check

    private func checkIPHidden() async -> PrivacyShieldStatus.CheckResult {
        let vpnResult = SmartVPNDetector.shared.detectionResult
        let vpnState = vpnResult?.vpnState ?? .unknown
        let isAuthoritative = vpnResult?.isAuthoritative ?? false

        guard vpnState.isLikelyOn else {
            let ip = vpnResult?.publicIP ?? "Unknown"
            let isp = vpnResult?.publicISP ?? "your ISP"
            // Don't say "IP Hidden" when it's a residential ISP
            return PrivacyShieldStatus.CheckResult(
                passed: false,
                title: "IP Visibility",
                detail: "Your IP (\(ip)) from \(isp) is visible to websites",
                recommendation: "Connect to a VPN to route through a different IP"
            )
        }

        let publicCountry = vpnResult?.publicCountry ?? ""
        let deviceLocale = Locale.current.region?.identifier ?? ""
        let isRerouted = !publicCountry.isEmpty && publicCountry != deviceLocale

        return PrivacyShieldStatus.CheckResult(
            passed: isRerouted,
            title: "IP Visibility",
            detail: isRerouted
                ? "Traffic routed through \(publicCountry) IP\(isAuthoritative ? " (VPN confirmed)" : " (inferred)")"
                : "VPN active but IP country matches your location",
            recommendation: isRerouted ? nil : "Try a VPN server in a different region"
        )
    }

    // MARK: - WebRTC Leak Check

    private func checkWebRTCLeak() async -> PrivacyShieldStatus.CheckResult {
        // WebRTC leaks are a BROWSER issue, not relevant for native iOS apps.
        // iOS apps do not use WebRTC for IP discovery.
        // Showing this check as always-passed with honest explanation.
        return PrivacyShieldStatus.CheckResult(
            passed: true,
            title: "WebRTC",
            detail: "Not applicable — WebRTC leaks only affect web browsers, not native iOS apps",
            recommendation: nil
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

        // Determine IP type based on ISP name
        let ipType: String
        if let ispName = isp?.lowercased() {
            if ispName.contains("vpn") || ispName.contains("private") ||
               ispName.contains("hosting") || ispName.contains("cloud") ||
               ispName.contains("data center") {
                ipType = "Data Center / VPN"
            } else {
                ipType = "Residential"
            }
        } else {
            ipType = "Unknown"
        }

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

    func checkWiFiSafety() async {
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
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        checks.append(WiFiSafetyResult.SafetyCheck(
            title: "VPN Protection",
            detail: vpnActive ? "Traffic is encrypted" : "Traffic is not encrypted",
            status: vpnActive ? .passed : .warning
        ))

        // 3. Check for captive portal (try connecting to a known URL)
        let hasCaptivePortal = await checkCaptivePortal()
        checks.append(WiFiSafetyResult.SafetyCheck(
            title: "Captive Portal",
            detail: hasCaptivePortal ? "Login page detected" : "No login page required",
            status: hasCaptivePortal ? .warning : .passed
        ))

        // 4. Check DNS hijacking
        let dnsHijacked = await checkDNSHijacking()
        checks.append(WiFiSafetyResult.SafetyCheck(
            title: "DNS Security",
            detail: dnsHijacked ? "DNS may be tampered" : "DNS appears normal",
            status: dnsHijacked ? .failed : .passed
        ))

        // 5. Check HTTPS
        let httpsWorks = await checkBasicHTTPS()
        checks.append(WiFiSafetyResult.SafetyCheck(
            title: "HTTPS Connections",
            detail: httpsWorks ? "HTTPS works correctly" : "HTTPS may be blocked or intercepted",
            status: httpsWorks ? .passed : .failed
        ))

        // Determine overall status
        let failedCount = checks.filter { $0.status == .failed }.count
        let warningCount = checks.filter { $0.status == .warning }.count

        let overallStatus: WiFiSafetyResult.SafetyStatus
        if failedCount > 0 {
            overallStatus = .unsafe
        } else if warningCount > 1 || (!vpnActive && warningCount > 0) {
            overallStatus = .caution
        } else {
            overallStatus = .safe
        }

        wifiSafetyResult = WiFiSafetyResult(overallStatus: overallStatus, checks: checks)
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

            // Same fake-IP ranges as DNSSecurityScanner.testDNSHijacking
            let proxyFakeRanges = ["198.18.", "198.19.", "100.100.", "10.10.10.", "28.0.0."]
            let resolvedIPs = addresses.compactMap { Self.ipString(from: $0) }
            let allProxyFake = !resolvedIPs.isEmpty && resolvedIPs.allSatisfy { ip in
                proxyFakeRanges.contains(where: { ip.hasPrefix($0) })
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
            verdict = .minorLeaks
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
        // Check DNS servers - if they belong to local ISP while VPN is active, DNS is leaking
        let dnsServers = getDNSServers()
        let localISPDNS = ["202.96.", "218.2.", "114.114.", "119.29.", "223.5.", "223.6.", "182.254.",
                           "61.139.", "218.6.", "221.228.", "112.124.", "101.226."]

        let leakingServers = dnsServers.filter { server in
            localISPDNS.contains(where: { server.hasPrefix($0) })
        }

        if !leakingServers.isEmpty {
            return VPNLeakTestResult.LeakCheck(
                name: "DNS Leak",
                isLeaking: true,
                detail: "DNS queries going to local ISP (\(leakingServers.first ?? "unknown")) instead of VPN",
                severity: .critical,
                solution: "Enable 'Use VPN DNS' in your VPN app settings, or manually set DNS to 1.1.1.1 or 8.8.8.8"
            )
        }

        // Also test by resolving through different DNS path
        let resolvedNormally = await resolveDomain("myip.opendns.com")

        if let resolved = resolvedNormally, resolved != vpnResult.publicIP {
            // If resolver returns a proxy fake-IP, the proxy is handling DNS
            // locally — that's expected, not a leak.
            let proxyFakeRanges = ["198.18.", "198.19.", "100.100.", "10.10.10.", "28.0.0."]
            if proxyFakeRanges.contains(where: { resolved.hasPrefix($0) }) {
                return VPNLeakTestResult.LeakCheck(
                    name: "DNS Leak",
                    isLeaking: false,
                    detail: "DNS handled locally by proxy (\(resolved)) — normal for fake-IP routing",
                    severity: .safe,
                    solution: nil
                )
            }
            return VPNLeakTestResult.LeakCheck(
                name: "DNS Leak",
                isLeaking: true,
                detail: "DNS resolver returns different IP (\(resolved)) than VPN exit IP",
                severity: .warning,
                solution: "Your DNS may be going outside the VPN tunnel. Check VPN DNS settings."
            )
        }

        return VPNLeakTestResult.LeakCheck(
            name: "DNS Leak",
            isLeaking: false,
            detail: "DNS queries are going through the VPN tunnel",
            severity: .safe,
            solution: nil
        )
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

        if detectedIPs.count > 1 {
            return VPNLeakTestResult.LeakCheck(
                name: "IP Leak",
                isLeaking: true,
                detail: "Multiple IPs detected: \(detectedIPs.joined(separator: ", ")). Some traffic may bypass VPN.",
                severity: .critical,
                solution: "Disable split-tunneling in your VPN app, or ensure all traffic routes through VPN"
            )
        }

        // Check if IP matches expected VPN location (not local country)
        let deviceCountry = Locale.current.region?.identifier ?? ""
        let vpnCountry = vpnResult.publicCountry ?? ""

        if !vpnCountry.isEmpty && vpnCountry == deviceCountry {
            // Could be same-country VPN server, which is fine
            return VPNLeakTestResult.LeakCheck(
                name: "IP Leak",
                isLeaking: false,
                detail: "Public IP (\(vpnResult.publicIP ?? "unknown")) is consistent. VPN server is in your country.",
                severity: .safe,
                solution: nil
            )
        }

        return VPNLeakTestResult.LeakCheck(
            name: "IP Leak",
            isLeaking: false,
            detail: "Public IP (\(vpnResult.publicIP ?? "unknown")) is consistent across all tests",
            severity: .safe,
            solution: nil
        )
    }

    private func performWebRTCLeakTest() async -> VPNLeakTestResult.LeakCheck {
        // On iOS native apps, WebRTC leaks don't apply
        // But we check if local IP is accessible (browsers could leak it)
        let localIP = getLocalIP()

        if let ip = localIP {
            return VPNLeakTestResult.LeakCheck(
                name: "WebRTC Leak",
                isLeaking: false,
                detail: "Native apps are safe. Browsers could expose local IP (\(ip)) via WebRTC.",
                severity: .warning,
                solution: "Use a browser extension to disable WebRTC, or use Safari (which blocks WebRTC leaks by default)"
            )
        }

        return VPNLeakTestResult.LeakCheck(
            name: "WebRTC Leak",
            isLeaking: false,
            detail: "No WebRTC leak risk detected",
            severity: .safe,
            solution: nil
        )
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
        await withCheckedContinuation { continuation in
            var hints = addrinfo(
                ai_flags: AI_DEFAULT,
                ai_family: AF_INET,
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

            guard status == 0, let addrInfo = result else {
                continuation.resume(returning: nil)
                return
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen,
                       &hostname, socklen_t(hostname.count),
                       nil, 0, NI_NUMERICHOST)

            let ip = String(cString: hostname)
            continuation.resume(returning: ip.isEmpty ? nil : ip)
        }
    }
}
