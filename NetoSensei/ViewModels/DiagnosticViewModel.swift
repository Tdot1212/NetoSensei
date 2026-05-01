//
//  DiagnosticViewModel.swift
//  NetoSensei
//
//  FIXED: Task.detached pattern, eliminated 80% deadlock, guaranteed completion
//  Swift 6 concurrency compliant - Updated 2025-12-17
//

import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
class DiagnosticViewModel: ObservableObject {
    @Published var result: DiagnosticResult?
    @Published var isRunning = false
    @Published var progress: Double = 0.0
    @Published var currentTest: String = ""
    @Published var errorMessage: String?
    @Published var analysis: RootCauseAnalyzer.Analysis?

    // FIXED: Removed nonisolated - NetworkMonitorService is @MainActor
    private let networkMonitor: NetworkMonitorService
    private let historyManager: HistoryManager
    private let rootCauseAnalyzer = RootCauseAnalyzer()
    // Using nonisolated(unsafe) to allow cleanup in deinit
    nonisolated(unsafe) private var diagnosticTask: Task<Void, Never>?

    // FIXED: Re-entry guard to prevent UI update loops
    private var isUpdatingUI = false

    init() {
        self.networkMonitor = NetworkMonitorService.shared
        self.historyManager = HistoryManager.shared
    }

    init(networkMonitor: NetworkMonitorService, historyManager: HistoryManager) {
        self.networkMonitor = networkMonitor
        self.historyManager = historyManager
    }

    // MARK: - Run Full Diagnostic (FIXED: Task.detached pattern)

    func runFullDiagnostic() {
        // CRITICAL: Prevent running while already in progress
        guard !isRunning else {
            print("⚠️ Diagnostic already in progress, ignoring tap")
            return
        }

        print("🚀 ========== DIAGNOSTIC STARTED ==========")

        // Cancel any existing diagnostic (should not happen with guard above, but defensive)
        diagnosticTask?.cancel()

        // FIXED: Set isRunning BEFORE creating Task to ensure UI updates immediately
        // This prevents the race condition where view body renders before Task starts
        isRunning = true
        progress = 0.0
        errorMessage = nil
        result = nil

        // Disable idle timer to prevent screen from turning off during diagnostics
        UIApplication.shared.isIdleTimerDisabled = true

        // Run in detached task to prevent UI blocking
        diagnosticTask = Task.detached { [weak self] in
            guard let self = self else {
                // Re-enable idle timer if task is cancelled early
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                return
            }
            print("📋 Diagnostic task created")

            do {
                print("✅ Diagnostic initialized, starting tests...")
                try Task.checkCancellation()

                // Capture network snapshot ONCE at the beginning (on MainActor)
                let networkSnapshot = await MainActor.run {
                    self.networkMonitor.currentStatus
                }
                print("✅ Network snapshot captured")

                // STEP 1: Ping Router/Gateway (0.1 = 10%) - 3s timeout
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentTest = "Testing router connection..."
                    self.progress = 0.1
                }
                let gateway = try await withTimeout(seconds: 3) {
                    await self.testGateway()
                }

                // STEP 2: Ping External Servers (0.2 = 20%) - 3s timeout
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentTest = "Testing external connectivity..."
                    self.progress = 0.2
                }
                let external = try await withTimeout(seconds: 3) {
                    await self.testExternal()
                }

                // STEP 3: DNS Tests (0.3 = 30%) - 3s timeout
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentTest = "Testing DNS resolution..."
                    self.progress = 0.3
                }
                let dns = try await withTimeout(seconds: 3) {
                    await self.testDNS()
                }

                // STEP 4: HTTP GET Test (0.4 = 40%) - 5s timeout
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentTest = "Testing HTTP connectivity..."
                    self.progress = 0.5
                }
                let http = try await withTimeout(seconds: 5) {
                    await self.testHTTP()
                }

                // STEP 5: VPN Tunnel Check (0.5 = 50%) - 3s timeout
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentTest = "Checking VPN tunnel..."
                    self.progress = 0.6
                }
                let vpn = try await withTimeout(seconds: 3) {
                    await self.testVPN()
                }

                // STEP 6: ISP Congestion Check (0.6 = 60%) - 3s timeout
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentTest = "Testing ISP performance..."
                    self.progress = 0.7
                }
                let isp = try await withTimeout(seconds: 3) {
                    await self.testISP()
                }
                print("✅ testISP() completed")

                // STEP 7: Evaluate and produce result (0.7+ = 70-100%)
                await MainActor.run {
                    self.currentTest = "Analyzing results..."
                    self.progress = 0.8
                }

                print("✅ All tests completed, evaluating results...")

                // Use the snapshot we captured at the beginning (no MainActor access needed)
                let diagnosticResult = self.evaluate(
                    gateway: gateway,
                    external: external,
                    dns: dns,
                    http: http,
                    vpn: vpn,
                    isp: isp,
                    networkSnapshot: networkSnapshot
                )

                print("✅ Diagnostic result created")

                // Analyze root cause (on MainActor since rootCauseAnalyzer is MainActor-isolated)
                print("🧠 Analyzing root cause...")
                let rootCauseAnalysis = await MainActor.run {
                    self.rootCauseAnalyzer.analyze(diagnostic: diagnosticResult)
                }
                print("✅ Root cause identified: \(rootCauseAnalysis.primaryProblem.rawValue)")

                // Update UI and save to history
                print("📱 Updating UI on MainActor...")

                // FIXED: Use re-entry guard to prevent cascading updates
                await MainActor.run {
                    guard !self.isUpdatingUI else {
                        print("⚠️ Skipping re-entrant UI update")
                        return
                    }
                    self.isUpdatingUI = true
                    defer { self.isUpdatingUI = false }

                    // Update core UI properties first
                    self.result = diagnosticResult
                    self.analysis = rootCauseAnalysis
                    self.progress = 1.0
                    self.currentTest = "Diagnostic complete"
                    self.isRunning = false

                    // STEP 2: Call NetworkInterpreter - single source of truth for ALL status messages
                    // This ensures consistent messages across Dashboard, Diagnose, and all other screens
                    let vpnResult = SmartVPNDetector.shared.detectionResult
                    let vpnActive = vpn.details.contains("active") || (vpnResult?.isVPNActive ?? false)

                    _ = NetworkInterpreter.shared.interpret(
                        gatewayLatency: gateway.latency,
                        gatewayReachable: gateway.result == .pass,
                        externalLatency: external.latency,
                        externalReachable: external.result == .pass,
                        dnsLatency: dns.latency,
                        dnsReachable: dns.result != .fail,
                        httpSuccess: http.result == .pass,
                        vpnActive: vpnActive,
                        vpnServerLocation: vpnResult?.publicCity ?? vpnResult?.publicCountry,
                        vpnIP: vpnResult?.publicIP,
                        ispLatency: isp.latency,
                        ispReachable: isp.result != .fail,
                        wifiConnected: networkSnapshot.wifi.isConnected,
                        ssid: networkSnapshot.wifi.ssid,
                        publicIP: networkSnapshot.publicIP,
                        isp: vpnResult?.publicISP
                    )
                    print("🧠 NetworkInterpreter updated after diagnostic")

                    // Haptic feedback based on health score
                    if rootCauseAnalysis.healthScore >= 80 {
                        HapticFeedback.success()
                    } else if rootCauseAnalysis.healthScore >= 50 {
                        HapticFeedback.warning()
                    } else {
                        HapticFeedback.error()
                    }

                    // Re-enable idle timer
                    UIApplication.shared.isIdleTimerDisabled = false

                    print("✅ Diagnostic UI update finished")
                    print("📊 Health Score: \(rootCauseAnalysis.healthScore)/100")
                }

                // FIXED: Save history AFTER UI update completes, in background task
                // This prevents @Published property updates from triggering cascading refreshes
                let gatewayLatency = gateway.latency ?? 0
                let dnsLatency = dns.latency ?? 0
                let externalLatency = external.latency ?? 0
                let vpnActive = vpn.details.contains("active")
                let connectionType = networkSnapshot.connectionType?.displayName ?? "Unknown"
                let healthScore = rootCauseAnalysis.healthScore
                let rootCause = rootCauseAnalysis.primaryProblem.rawValue

                // NEW: Capture WiFi and VPN context for history
                let wifiSSID = networkSnapshot.wifi.ssid
                let wifiBSSID = networkSnapshot.wifi.bssid

                // Get VPN location from detector (must access on MainActor)
                let vpnServerLocation = await MainActor.run {
                    let vpnDetectionResult = SmartVPNDetector.shared.detectionResult
                    return vpnDetectionResult?.publicCity ?? vpnDetectionResult?.publicCountry
                }

                Task.detached { [weak self] in
                    guard let self = self else { return }

                    // Small delay to let UI settle before triggering more updates
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                    await MainActor.run {
                        // Save to history (triggers @Published update)
                        self.historyManager.addDiagnostic(diagnosticResult)
                    }

                    // Save to network history timeline for charts
                    let historyEntry = NetworkHistoryEntry(
                        healthScore: healthScore,
                        downloadSpeed: nil,
                        uploadSpeed: nil,
                        latency: externalLatency,
                        gatewayLatency: gatewayLatency,
                        dnsLatency: dnsLatency,
                        jitter: nil,
                        packetLoss: nil,
                        vpnActive: vpnActive,
                        vpnOverhead: nil,
                        rootCause: rootCause,
                        connectionType: connectionType,
                        wifiSSID: wifiSSID,
                        wifiBSSID: wifiBSSID,
                        vpnServerLocation: vpnServerLocation,
                        entryType: .diagnostic
                    )

                    await MainActor.run {
                        NetworkHistoryManager.shared.addEntry(historyEntry)
                    }

                    print("📊 History saved in background")
                }

            } catch is CancellationError {
                // User cancelled - just stop
                await MainActor.run {
                    self.errorMessage = "Diagnostic cancelled"
                    self.isRunning = false
                    HapticFeedback.light()
                    // Re-enable idle timer
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            } catch is TimeoutError {
                // Timeout - show partial results if we have any
                await MainActor.run {
                    self.errorMessage = "Diagnostic timed out - network may be blocked. Showing partial results."
                    self.isRunning = false
                    HapticFeedback.warning()
                    // Re-enable idle timer
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            } catch {
                // Other error
                await MainActor.run {
                    self.errorMessage = "Diagnostic failed: \(error.localizedDescription)"
                    self.isRunning = false
                    HapticFeedback.error()
                    // Re-enable idle timer
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }

            print("========== DIAGNOSTIC FINISHED ==========")
        }
    }

    func cancelDiagnostic() {
        diagnosticTask?.cancel()
        diagnosticTask = nil
        isRunning = false
        // Re-enable idle timer when manually cancelled
        UIApplication.shared.isIdleTimerDisabled = false
    }

    deinit {
        diagnosticTask?.cancel()
    }

    // MARK: - Test Functions (ALL NONISOLATED)

    private func testGateway() async -> DiagnosticTest {
        print("🔍 testGateway() started")

        let (success, latency) = await networkMonitor.pingHost("192.168.1.1", timeout: 2.0)
        let latencyMs = latency ?? 0

        print("🔍 testGateway() - success: \(success), latency: \(latencyMs)")

        if !success {
            return DiagnosticTest(
                name: "Router/Gateway",
                result: .fail,
                latency: latencyMs,
                details: "Cannot reach router - disconnected or router offline",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "Router/Gateway",
                result: .pass,
                latency: latencyMs,
                details: "Router reachable",
                timestamp: Date()
            )
        }
    }

    private func testExternal() async -> DiagnosticTest {
        print("🔍 testExternal() started")

        let (success, latency) = await networkMonitor.pingHost("1.1.1.1", timeout: 2.0)
        let latencyMs = latency ?? 0

        print("🔍 testExternal() - success: \(success), latency: \(latencyMs)")

        if !success {
            return DiagnosticTest(
                name: "External Connectivity",
                result: .fail,
                latency: latencyMs,
                details: "Cannot reach internet - ISP problem or firewall blocking",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "External Connectivity",
                result: .pass,
                latency: latencyMs,
                details: "Internet reachable",
                timestamp: Date()
            )
        }
    }

    private func testDNS() async -> DiagnosticTest {
        print("🔍 testDNS() started")

        let start = Date()
        let success = await safeDNSLookup(hostname: "www.apple.com", timeout: 2.0)
        let latency = Date().timeIntervalSince(start) * 1000

        print("🔍 testDNS() - success: \(success), latency: \(latency)")

        if !success {
            return DiagnosticTest(
                name: "DNS Resolution",
                result: .fail,
                latency: latency,
                details: "DNS lookup failed - DNS servers not responding",
                timestamp: Date()
            )
        } else if latency > 100 {
            return DiagnosticTest(
                name: "DNS Resolution",
                result: .warning,
                latency: latency,
                details: "DNS slow - consider switching to 1.1.1.1 or 8.8.8.8",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "DNS Resolution",
                result: .pass,
                latency: latency,
                details: "DNS working well",
                timestamp: Date()
            )
        }
    }

    private func testHTTP() async -> DiagnosticTest {
        print("🔍 testHTTP() started")

        let success = await safeHTTPCheck(url: "https://www.apple.com/library/test/success.html", timeout: 3.0)

        print("🔍 testHTTP() - success: \(success)")

        if !success {
            return DiagnosticTest(
                name: "HTTP Connectivity",
                result: .fail,
                latency: nil,
                details: "HTTP blocked - firewall or proxy issue",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "HTTP Connectivity",
                result: .pass,
                latency: nil,
                details: "HTTP working",
                timestamp: Date()
            )
        }
    }

    private func testVPN() async -> DiagnosticTest {
        print("🔍 testVPN() started")

        // FIXED: Check BOTH NetworkMonitor AND SmartVPNDetector for consistency
        // The SmartVPNDetector uses routing analysis which is more reliable
        let networkMonitorVPN = await MainActor.run {
            networkMonitor.currentStatus.vpn.isActive
        }

        // Also check SmartVPNDetector's cached result
        let smartDetectorVPN = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        }

        // If either detector thinks VPN is active, treat it as active
        // This prevents false negatives when one detector is slower
        let isActive = networkMonitorVPN || smartDetectorVPN

        print("🔍 testVPN() - networkMonitor: \(networkMonitorVPN), smartDetector: \(smartDetectorVPN), final: \(isActive)")

        if isActive {
            return DiagnosticTest(
                name: "VPN Tunnel",
                result: .pass,
                latency: nil,
                details: "VPN is active",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "VPN Tunnel",
                result: .pass,
                latency: nil,
                details: "No VPN detected",
                timestamp: Date()
            )
        }
    }

    private func testISP() async -> DiagnosticTest {
        print("🔍 testISP() started")

        // Do a fresh ping test instead of reading cached status
        let (success, latency) = await networkMonitor.pingHost("1.1.1.1", timeout: 2.0)
        let internetLatency = latency ?? 0

        print("🔍 testISP() - success: \(success), latency: \(internetLatency)")

        // Check if VPN is active to give accurate diagnosis
        let vpnActive = await MainActor.run {
            networkMonitor.currentStatus.vpn.isActive || (SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false)
        }

        if !success || internetLatency > 200 {
            // FIXED: Don't blame ISP when VPN is the actual cause
            let details = vpnActive
                ? "High latency (\(Int(internetLatency))ms) — caused by VPN routing"
                : "High latency detected — possible ISP congestion"

            return DiagnosticTest(
                name: "ISP Performance",
                result: .warning,
                latency: internetLatency,
                details: details,
                timestamp: Date()
            )
        } else if internetLatency > 100 {
            return DiagnosticTest(
                name: "ISP Performance",
                result: .pass,
                latency: internetLatency,
                details: "Moderate latency",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "ISP Performance",
                result: .pass,
                latency: internetLatency,
                details: "Good ISP performance",
                timestamp: Date()
            )
        }
    }

    // MARK: - Helper Functions

    private func safeDNSLookup(hostname: String, timeout: TimeInterval) async -> Bool {
        do {
            return try await withTimeout(seconds: timeout) {
                await withCheckedContinuation { continuation in
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
                    if result != nil {
                        freeaddrinfo(result)
                    }
                    continuation.resume(returning: status == 0)
                }
            }
        } catch {
            return false
        }
    }

    private func safeHTTPCheck(url: String, timeout: TimeInterval) async -> Bool {
        do {
            return try await withTimeout(seconds: timeout) {
                guard let url = URL(string: url) else { return false }
                let (_, response) = try await URLSession.shared.data(from: url)
                return (response as? HTTPURLResponse)?.statusCode == 200
            }
        } catch {
            return false
        }
    }

    // MARK: - Evaluate (NONISOLATED)

    nonisolated private func evaluate(
        gateway: DiagnosticTest,
        external: DiagnosticTest,
        dns: DiagnosticTest,
        http: DiagnosticTest,
        vpn: DiagnosticTest,
        isp: DiagnosticTest,
        networkSnapshot: NetworkStatus
    ) -> DiagnosticResult {
        var issues: [IdentifiedIssue] = []
        let tests = [gateway, external, dns, http, vpn, isp]

        // Rule 1: Gateway unreachable = Router problem
        if gateway.result == .fail {
            issues.append(IdentifiedIssue(
                category: .router,
                severity: .critical,
                title: "Router Unreachable",
                description: "Cannot reach your router/gateway. Your router may be offline or disconnected.",
                technicalDetails: gateway.details,
                estimatedImpact: "No internet access",
                fixAvailable: true,
                fixTitle: "Reconnect to WiFi",
                fixDescription: "Try disconnecting and reconnecting to your WiFi network.",
                fixAction: .reconnectWiFi
            ))
        }

        // Rule 2: Gateway OK but external fails = ISP problem
        if gateway.result == .pass && external.result == .fail {
            issues.append(IdentifiedIssue(
                category: .isp,
                severity: .critical,
                title: "Internet Service Provider Issue",
                description: "Your router is working but cannot reach the internet. This is likely an ISP outage.",
                technicalDetails: external.details,
                estimatedImpact: "No internet access",
                fixAvailable: true,
                fixTitle: "Contact Your ISP",
                fixDescription: "Call your internet service provider to report the outage.",
                fixAction: .contactISP
            ))
        }

        // Rule 3: DNS fails = DNS problem
        if dns.result == .fail {
            issues.append(IdentifiedIssue(
                category: .dns,
                severity: .moderate,
                title: "DNS Resolution Failure",
                description: "DNS servers are not responding. You cannot access websites by name.",
                technicalDetails: dns.details,
                estimatedImpact: "Cannot browse websites",
                fixAvailable: true,
                fixTitle: "Change DNS Servers",
                fixDescription: "Switch to Cloudflare (1.1.1.1) or Google (8.8.8.8) DNS.",
                fixAction: .switchDNS(recommended: "1.1.1.1")
            ))
        }

        // FIXED: Check for test warnings to avoid "All tests passed" contradiction
        let hasTestWarnings = tests.contains { $0.result == .warning }
        let hasTestFailures = tests.contains { $0.result == .fail }

        // Determine overall status
        let hasCritical = issues.contains { $0.severity == .critical }
        let hasModerate = issues.contains { $0.severity == .moderate }

        let overallStatus: NetworkHealth
        if hasCritical || hasTestFailures {
            overallStatus = .poor
        } else if hasModerate || hasTestWarnings {
            overallStatus = .fair
        } else {
            overallStatus = .excellent
        }

        // ISSUE 6 FIX: Summary considers test warnings and VPN overhead
        let summary: String
        let vpnActive = networkSnapshot.vpn.isActive
        let extLatency = networkSnapshot.internet.latencyToExternal ?? 0
        if issues.isEmpty && !hasTestWarnings && !hasTestFailures {
            if vpnActive && extLatency > 150 {
                summary = "All tests passed. VPN adds overhead (\(Int(extLatency))ms latency)."
            } else {
                summary = "All tests passed! Your network is healthy."
            }
        } else if issues.isEmpty && hasTestWarnings {
            let warningCount = tests.filter { $0.result == .warning }.count
            summary = "\(warningCount) test\(warningCount == 1 ? "" : "s") with warnings. Network functional but not optimal."
        } else if hasCritical {
            summary = "Critical issues detected affecting connectivity."
        } else {
            summary = "Minor issues detected but network is functional."
        }

        return DiagnosticResult(
            timestamp: Date(),
            testDuration: 0,
            testsPerformed: tests,
            issues: issues,
            primaryIssue: issues.first,
            summary: summary,
            overallStatus: overallStatus,
            recommendations: [],
            oneTapFix: issues.first,
            networkSnapshot: networkSnapshot
        )
    }

    // MARK: - Computed Properties

    var hasResult: Bool {
        result != nil
    }

    var severityColor: Color {
        guard let result = result else { return .gray }
        switch result.overallStatus {
        case .excellent: return AppColors.green
        case .fair: return AppColors.yellow
        case .poor: return AppColors.red
        case .unknown: return .gray
        }
    }

    var causeText: String {
        result?.issues.first?.title ?? "No issues detected"
    }

    var explanationText: String {
        result?.issues.first?.description ?? "Your network is working normally."
    }

    var recommendationText: String {
        result?.issues.first?.fixDescription ?? "No action needed."
    }
}
