//
//  DiagnosticEngine.swift
//  NetoSensei
//
//  Intelligent network diagnostic engine
//

import Foundation

// FIXED: Added @MainActor for proper Swift 6 concurrency with @Published properties
@MainActor
class DiagnosticEngine: ObservableObject {
    static let shared = DiagnosticEngine()

    @Published var isRunning = false
    @Published var currentTest: String = ""
    @Published var progress: Double = 0.0

    private init() {
        // Empty init - NetworkMonitorService.shared accessed directly where needed
    }

    // MARK: - Run Full Diagnostic

    nonisolated func runDiagnostic() async -> DiagnosticResult {
        await MainActor.run {
            isRunning = true
            progress = 0.0
        }

        let startTime = Date()
        var tests: [DiagnosticTest] = []
        var issues: [IdentifiedIssue] = []

        // Get current network status
        let networkStatus = await MainActor.run { NetworkMonitorService.shared.currentStatus }

        // Step 1: Connectivity Tests (40% of progress)
        await MainActor.run { currentTest = "Testing connectivity..." }
        tests.append(contentsOf: await runConnectivityTests())
        await MainActor.run { progress = 0.4 }

        // Step 2: VPN Tests (if VPN is active) (20% of progress)
        if networkStatus.vpn.isActive {
            await MainActor.run { currentTest = "Testing VPN..." }
            tests.append(contentsOf: await runVPNTests())
        }
        await MainActor.run { progress = 0.6 }

        // Step 3: Congestion Tests (20% of progress)
        await MainActor.run { currentTest = "Testing for congestion..." }
        tests.append(contentsOf: await runCongestionTests())
        await MainActor.run { progress = 0.8 }

        // Step 4: Analyze Results (20% of progress)
        await MainActor.run { currentTest = "Analyzing results..." }
        issues = analyzeTestResults(tests, networkStatus: networkStatus)
        await MainActor.run { progress = 1.0 }

        let duration = Date().timeIntervalSince(startTime)

        // Build diagnostic result
        let result = buildDiagnosticResult(
            tests: tests,
            issues: issues,
            duration: duration,
            networkStatus: networkStatus
        )

        await MainActor.run {
            isRunning = false
            currentTest = ""
        }

        return result
    }

    // MARK: - Connectivity Tests

    nonisolated private func runConnectivityTests() async -> [DiagnosticTest] {
        var tests: [DiagnosticTest] = []

        // Test 1: Gateway Ping
        let gatewayTest = await testGateway()
        tests.append(gatewayTest)

        // Test 2: External Ping (Cloudflare)
        // FIXED: Use cloudflare-dns.com instead of 1.1.1.1 - more reliable through VPN
        let cloudflareTest = await testExternalHost("cloudflare-dns.com", name: "Cloudflare DNS")
        tests.append(cloudflareTest)

        // Test 3: External Ping (Google)
        let googleTest = await testExternalHost("8.8.8.8", name: "Google DNS")
        tests.append(googleTest)

        // Test 4: DNS Lookup
        let dnsTest = await testDNSLookup()
        tests.append(dnsTest)

        // Test 5: HTTP GET Test
        let httpTest = await testHTTPConnection()
        tests.append(httpTest)

        // Test 6: CDN Reachability
        let cdnTest = await testCDN()
        tests.append(cdnTest)

        return tests
    }

    nonisolated private func testGateway() async -> DiagnosticTest {
        let networkStatus = await MainActor.run { NetworkMonitorService.shared.currentStatus }
        let gatewayIP = networkStatus.router.gatewayIP

        guard let gateway = gatewayIP else {
            return DiagnosticTest(
                name: "Gateway Ping",
                result: .fail,
                latency: nil,
                details: "Could not determine gateway IP",
                timestamp: Date()
            )
        }

        let (success, latency) = await pingHost(gateway, timeout: 3.0)

        return DiagnosticTest(
            name: "Gateway Ping",
            result: success ? .pass : .fail,
            latency: latency,
            details: success ? "Gateway reachable at \(gateway)" : "Gateway unreachable",
            timestamp: Date()
        )
    }

    nonisolated private func testExternalHost(_ host: String, name: String) async -> DiagnosticTest {
        let (success, latency) = await pingHost(host, timeout: 5.0)

        return DiagnosticTest(
            name: name,
            result: success ? .pass : .fail,
            latency: latency,
            details: success ? "Reachable (\(String(format: "%.0f", latency ?? 0))ms)" : "Unreachable",
            timestamp: Date()
        )
    }

    nonisolated private func testDNSLookup() async -> DiagnosticTest {
        let start = Date()
        let success = await performDNSLookup("www.google.com")
        let latency = Date().timeIntervalSince(start) * 1000

        return DiagnosticTest(
            name: "DNS Lookup",
            result: success ? .pass : .fail,
            latency: latency,
            details: success ? "DNS resolution successful (\(String(format: "%.0f", latency))ms)" : "DNS lookup failed",
            timestamp: Date()
        )
    }

    nonisolated private func testHTTPConnection() async -> DiagnosticTest {
        let start = Date()
        guard let url = URL(string: "https://www.google.com") else {
            return DiagnosticTest(name: "HTTP Test", result: .fail, details: "Invalid URL", timestamp: Date())
        }

        do {
            let (_, response) = try await withTimeout(seconds: 5) {
                try await URLSession.shared.data(from: url)
            }
            let latency = Date().timeIntervalSince(start) * 1000
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            return DiagnosticTest(
                name: "HTTP GET Test",
                result: statusCode == 200 ? .pass : .fail,
                latency: latency,
                details: "HTTP \(statusCode) (\(String(format: "%.0f", latency))ms)",
                timestamp: Date()
            )
        } catch {
            let latency = Date().timeIntervalSince(start) * 1000
            return DiagnosticTest(
                name: "HTTP GET Test",
                result: .fail,
                latency: latency,
                details: "Request failed: \(error.localizedDescription)",
                timestamp: Date()
            )
        }
    }

    nonisolated private func testCDN() async -> DiagnosticTest {
        let start = Date()
        guard let url = URL(string: "https://www.cloudflare.com") else {
            return DiagnosticTest(name: "CDN Test", result: .fail, details: "Invalid URL", timestamp: Date())
        }

        do {
            let (_, response) = try await withTimeout(seconds: 5) {
                try await URLSession.shared.data(from: url)
            }
            let latency = Date().timeIntervalSince(start) * 1000
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            return DiagnosticTest(
                name: "CDN Reachability",
                result: statusCode == 200 ? .pass : .fail,
                latency: latency,
                details: "CDN reachable (\(String(format: "%.0f", latency))ms)",
                timestamp: Date()
            )
        } catch {
            return DiagnosticTest(
                name: "CDN Reachability",
                result: .fail,
                details: "CDN unreachable",
                timestamp: Date()
            )
        }
    }

    // MARK: - VPN Tests

    nonisolated private func runVPNTests() async -> [DiagnosticTest] {
        var tests: [DiagnosticTest] = []

        let networkStatus = await MainActor.run { NetworkMonitorService.shared.currentStatus }
        let vpn = networkStatus.vpn

        // Test 1: VPN Tunnel Active
        tests.append(DiagnosticTest(
            name: "VPN Tunnel Status",
            result: vpn.isActive ? .pass : .fail,
            details: vpn.isActive ? "VPN tunnel is active" : "VPN tunnel is inactive",
            timestamp: Date()
        ))

        // Test 2: VPN Tunnel Reachable
        if vpn.isActive {
            tests.append(DiagnosticTest(
                name: "VPN Tunnel Reachability",
                result: vpn.tunnelReachable ? .pass : .fail,
                latency: vpn.tunnelLatency,
                details: vpn.tunnelReachable ? "VPN server is reachable" : "VPN server unreachable",
                timestamp: Date()
            ))

            // Test 3: VPN Packet Loss
            if let packetLoss = vpn.packetLoss {
                tests.append(DiagnosticTest(
                    name: "VPN Packet Loss",
                    result: packetLoss < 5 ? .pass : .warning,
                    details: "Packet loss: \(String(format: "%.1f", packetLoss))%",
                    timestamp: Date()
                ))
            }

            // Test 4: VPN Protocol
            if let tunnelType = vpn.tunnelType {
                tests.append(DiagnosticTest(
                    name: "VPN Protocol",
                    result: .pass,
                    details: "Using \(tunnelType)",
                    timestamp: Date()
                ))
            }
        }

        return tests
    }

    // MARK: - Congestion Tests

    nonisolated private func runCongestionTests() async -> [DiagnosticTest] {
        var tests: [DiagnosticTest] = []

        // Get current network status
        let currentStatus = await MainActor.run { NetworkMonitorService.shared.currentStatus }

        // Test router latency stability
        let routerStabilityTest = await testLatencyStability(
            host: currentStatus.router.gatewayIP ?? "192.168.1.1",
            name: "Router Latency Stability",
            samples: 5
        )
        tests.append(routerStabilityTest)

        // Test ISP latency stability
        // FIXED: Use cloudflare-dns.com instead of 1.1.1.1 - more reliable through VPN
        let ispStabilityTest = await testLatencyStability(
            host: "cloudflare-dns.com",
            name: "ISP Latency Stability",
            samples: 5
        )
        tests.append(ispStabilityTest)

        return tests
    }

    nonisolated private func testLatencyStability(host: String, name: String, samples: Int) async -> DiagnosticTest {
        var latencies: [Double] = []

        for _ in 0..<samples {
            let (success, latency) = await pingHost(host, timeout: 2.0)
            if success, let lat = latency {
                latencies.append(lat)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms between pings
        }

        guard !latencies.isEmpty else {
            return DiagnosticTest(
                name: name,
                result: .fail,
                details: "Could not measure latency",
                timestamp: Date()
            )
        }

        let avg = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.map { pow($0 - avg, 2) }.reduce(0, +) / Double(latencies.count)
        let jitter = sqrt(variance)

        let isStable = jitter < 20  // Jitter under 20ms is considered stable

        return DiagnosticTest(
            name: name,
            result: isStable ? .pass : .warning,
            latency: avg,
            details: "Avg: \(String(format: "%.0f", avg))ms, Jitter: \(String(format: "%.0f", jitter))ms",
            timestamp: Date()
        )
    }

    // MARK: - Issue Analysis (Decision Engine)

    nonisolated private func analyzeTestResults(_ tests: [DiagnosticTest], networkStatus: NetworkStatus) -> [IdentifiedIssue] {
        var issues: [IdentifiedIssue] = []

        // Rule 1: Router unreachable
        if let gatewayTest = tests.first(where: { $0.name == "Gateway Ping" }),
           gatewayTest.result == .fail {
            issues.append(IdentifiedIssue(
                category: .router,
                severity: .critical,
                title: "Router Unreachable",
                description: "Your router is not responding. This blocks all internet access.",
                technicalDetails: "Gateway ping failed",
                estimatedImpact: "Complete network failure",
                fixAvailable: true,
                fixTitle: "Restart Router or Reconnect Wi-Fi",
                fixDescription: "Try reconnecting to Wi-Fi or restarting your router.",
                fixAction: .reconnectWiFi
            ))
        }
        // Rule 2: Router reachable but internet down
        else if let gatewayTest = tests.first(where: { $0.name == "Gateway Ping" }),
                gatewayTest.result == .pass,
                let cloudflareTest = tests.first(where: { $0.name == "Cloudflare DNS" }),
                cloudflareTest.result == .fail {
            issues.append(IdentifiedIssue(
                category: .isp,
                severity: .critical,
                title: "ISP Connection Down",
                description: "Your router is working, but your ISP connection is down or blocked.",
                technicalDetails: "Gateway reachable, external hosts unreachable",
                estimatedImpact: "No internet access",
                fixAvailable: true,
                fixTitle: "Switch DNS or Wait",
                fixDescription: "Try switching to Cloudflare DNS (1.1.1.1) or contact your ISP.",
                fixAction: .switchDNS(recommended: "1.1.1.1")
            ))
        }
        // Rule 3: VPN tunnel dead
        else if networkStatus.vpn.isActive && !networkStatus.vpn.tunnelReachable {
            issues.append(IdentifiedIssue(
                category: .vpn,
                severity: .critical,
                title: "VPN Tunnel Dead",
                description: "Your VPN is active but the tunnel is not passing traffic.",
                technicalDetails: "VPN active but server unreachable",
                estimatedImpact: "Internet blocked by dead VPN tunnel",
                fixAvailable: true,
                fixTitle: "Reconnect VPN",
                fixDescription: "Reconnect to your VPN or switch servers.",
                fixAction: .reconnectVPN
            ))
        }
        // Rule 4: DNS slow
        else if let dnsTest = tests.first(where: { $0.name == "DNS Lookup" }),
                let latency = dnsTest.latency, latency > 200 {
            issues.append(IdentifiedIssue(
                category: .dns,
                severity: .moderate,
                title: "DNS Bottleneck",
                description: "DNS resolution is very slow (\(String(format: "%.0f", latency))ms).",
                technicalDetails: "DNS latency > 200ms",
                estimatedImpact: "Slow page loading and initial connections",
                fixAvailable: true,
                fixTitle: "Switch to Cloudflare DNS",
                fixDescription: "Use a faster DNS server like Cloudflare (1.1.1.1).",
                fixAction: .switchDNS(recommended: "1.1.1.1")
            ))
        }
        // REMOVED: Rule 5 - Weak Wi-Fi
        // iOS has NO public API for WiFi RSSI measurement
        // networkStatus.wifi.rssi is always nil
        // We cannot detect weak WiFi signal on iOS
        // Rule 6: High VPN latency
        if networkStatus.vpn.isActive,
           let vpnLatency = networkStatus.vpn.tunnelLatency,
           vpnLatency > 150 {
            issues.append(IdentifiedIssue(
                category: .vpn,
                severity: .moderate,
                title: "High VPN Latency",
                description: "Your VPN server is slow (\(String(format: "%.0f", vpnLatency))ms).",
                technicalDetails: "VPN latency: \(String(format: "%.0f", vpnLatency))ms",
                estimatedImpact: "Noticeable lag in browsing and streaming",
                fixAvailable: true,
                fixTitle: "Switch VPN Server",
                fixDescription: "Connect to a closer VPN server.",
                fixAction: .switchVPNServer
            ))
        }

        return issues
    }

    // MARK: - Build Diagnostic Result

    nonisolated private func buildDiagnosticResult(
        tests: [DiagnosticTest],
        issues: [IdentifiedIssue],
        duration: TimeInterval,
        networkStatus: NetworkStatus
    ) -> DiagnosticResult {

        // FIXED: Check for test warnings to avoid "All tests passed" contradiction
        let hasTestWarnings = tests.contains { $0.result == .warning }
        let hasTestFailures = tests.contains { $0.result == .fail }

        // Determine overall status
        let overallStatus: NetworkHealth
        if issues.contains(where: { $0.severity == .critical }) || hasTestFailures {
            overallStatus = .poor
        } else if issues.contains(where: { $0.severity == .moderate }) || hasTestWarnings {
            overallStatus = .fair
        } else {
            overallStatus = .excellent
        }

        // Generate summary - ISSUE 6 FIX: Consult latency metrics and VPN overhead
        // to prevent "All tests passed" when latency is degraded by VPN
        let summary: String
        let vpnActive = networkStatus.vpn.isActive
        let highLatency = (networkStatus.internet.latencyToExternal ?? 0) > 150

        if issues.isEmpty && !hasTestWarnings && !hasTestFailures {
            if vpnActive && highLatency {
                let latency = Int(networkStatus.internet.latencyToExternal ?? 0)
                summary = "All tests passed. VPN adds overhead (\(latency)ms latency) — normal for international connections."
            } else if highLatency {
                let latency = Int(networkStatus.internet.latencyToExternal ?? 0)
                summary = "All tests passed, but latency is elevated (\(latency)ms). Connection is functional."
            } else {
                summary = "All tests passed! Your network is performing well."
            }
        } else if issues.isEmpty && hasTestWarnings {
            let warningCount = tests.filter { $0.result == .warning }.count
            summary = "\(warningCount) test\(warningCount == 1 ? "" : "s") with warnings. Network functional but not optimal."
        } else if issues.count == 1 {
            summary = issues[0].description
        } else {
            summary = "Found \(issues.count) issues affecting your network performance."
        }

        // Primary issue (highest severity)
        let primaryIssue = issues.first(where: { $0.severity == .critical }) ?? issues.first

        // One-tap fix (issue with fix available)
        let oneTapFix = issues.first(where: { $0.fixAvailable })

        // Recommendations
        let recommendations = issues.compactMap { $0.fixDescription }

        return DiagnosticResult(
            timestamp: Date(),
            testDuration: duration,
            testsPerformed: tests,
            issues: issues,
            primaryIssue: primaryIssue,
            summary: summary,
            overallStatus: overallStatus,
            recommendations: recommendations,
            oneTapFix: oneTapFix,
            networkSnapshot: networkStatus
        )
    }

    // MARK: - Helper Functions

    nonisolated private func pingHost(_ host: String, timeout: TimeInterval) async -> (Bool, Double?) {
        // Delegate to NetworkMonitorService
        return await NetworkMonitorService.shared.pingHost(host, timeout: timeout)
    }

    nonisolated private func performDNSLookup(_ hostname: String) async -> Bool {
        return await withCheckedContinuation { continuation in
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
            let status = getaddrinfo(hostname, nil, &hints, &result)
            freeaddrinfo(result)

            continuation.resume(returning: status == 0)
        }
    }
}
