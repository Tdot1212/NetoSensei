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
    /// Diagnosis v2: the ONE verdict for this Quick Check (score, state,
    /// findings, coverage). RootCauseAnalyzer and NetworkInterpreter are no
    /// longer consulted — see docs/DIAGNOSIS_V2_DESIGN_2026_09_19.md.
    @Published var verdict: NetworkVerdict?

    // FIXED: Removed nonisolated - NetworkMonitorService is @MainActor
    private let networkMonitor: NetworkMonitorService
    private let historyManager: HistoryManager
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
            debugLog("⚠️ Diagnostic already in progress, ignoring tap")
            return
        }

        debugLog("🚀 ========== DIAGNOSTIC STARTED ==========")

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
            debugLog("📋 Diagnostic task created")

            do {
                debugLog("✅ Diagnostic initialized, starting tests...")
                try Task.checkCancellation()

                // Capture network snapshot ONCE at the beginning (on MainActor)
                let networkSnapshot = await MainActor.run {
                    self.networkMonitor.currentStatus
                }
                debugLog("✅ Network snapshot captured")

                // STEP 1: Ping Router/Gateway (0.1 = 10%) - 3s timeout
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentTest = "Testing router connection..."
                    self.progress = 0.1
                }
                let gateway = try await withTimeout(seconds: 3) {
                    await self.testGateway(snapshot: networkSnapshot)
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
                let isp = self.ispPlaceholder()
                debugLog("✅ ISP step recorded as not run (superseded by the Internet check)")

                // STEP 7: Evaluate and produce result (0.7+ = 70-100%)
                await MainActor.run {
                    self.currentTest = "Analyzing results..."
                    self.progress = 0.8
                }

                debugLog("✅ All tests completed, evaluating results...")

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

                debugLog("✅ Diagnostic result created")

                // Diagnosis v2: ONE verdict, composed on the MainActor from the
                // Quick Check's reachability results layered over the monitor's
                // interception-aware latencies (VerdictInputs). No second engine.
                debugLog("📱 Updating UI on MainActor...")

                // FIXED: Use re-entry guard to prevent cascading updates
                let composed: NetworkVerdict = await MainActor.run {
                    let v = VerdictInputs.verdict(forQuickCheck: diagnosticResult, status: self.networkMonitor.currentStatus)
                    guard !self.isUpdatingUI else {
                        debugLog("⚠️ Skipping re-entrant UI update")
                        return v
                    }
                    self.isUpdatingUI = true
                    defer { self.isUpdatingUI = false }

                    // Update core UI properties first
                    self.result = diagnosticResult
                    self.verdict = v
                    self.progress = 1.0
                    self.currentTest = "Diagnostic complete"
                    self.isRunning = false

                    // Haptic feedback follows the verdict state
                    switch v.state {
                    case .working: HapticFeedback.success()
                    case .degraded, .unknown: HapticFeedback.warning()
                    case .broken: HapticFeedback.error()
                    }

                    // Re-enable idle timer
                    UIApplication.shared.isIdleTimerDisabled = false

                    debugLog("✅ Diagnostic UI update finished")
                    debugLog("🧭 Verdict: \(v.state.rawValue) score=\(v.scoreText) — \(v.headline) [\(v.coverage.line)]")
                    return v
                }

                // FIXED: Save history AFTER UI update completes, in background task
                // This prevents @Published property updates from triggering cascading refreshes
                let gatewayLatency = gateway.latency ?? 0
                let dnsLatency = dns.latency ?? 0
                let externalLatency = external.latency  // Phase 4: nil stays nil (unmeasured), never 0
                let vpnActive = vpn.details.contains("active")
                let connectionType = networkSnapshot.connectionType?.displayName ?? "Unknown"
                // History keeps a 0–100 number; an unscored verdict (coverage floor unmet) is stored as 0
                // only because NetworkHistoryEntry.healthScore is non-optional (post-trip cleanup).
                let healthScore = composed.score?.value ?? 0
                let rootCause = composed.primary?.headline ?? (composed.state == .working ? "No Issues" : composed.headline)

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

                    debugLog("📊 History saved in background")
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

            debugLog("========== DIAGNOSTIC FINISHED ==========")
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

    /// Diagnosis v2, Commit 1. The target is the REAL default gateway from the
    /// routing table (DefaultRouteResolver), never a literal address.
    ///   - Cellular-only, or no gateway can be read/inferred → NOT APPLICABLE.
    ///     There is no router to test; this is not a failure and costs nothing.
    ///   - Gateway read from the routing table and it doesn't answer → FAIL.
    ///   - Gateway only *assumed* by the legacy heuristic and it doesn't answer
    ///     → WARNING "couldn't confirm": a guessed address not answering is not
    ///     evidence that the router is down.
    private func testGateway(snapshot: NetworkStatus) async -> DiagnosticTest {
        debugLog("🔍 testGateway() started")

        let isCellularOnly = snapshot.connectionType == .cellular && !snapshot.wifi.isConnected
        guard !isCellularOnly else {
            debugLog("🔍 testGateway() - not applicable: cellular-only path")
            return DiagnosticTest(
                name: "Router/Gateway",
                result: .notApplicable,
                latency: nil,
                details: "Not applicable — on cellular there is no local router to test",
                timestamp: Date()
            )
        }

        guard let gateway = networkMonitor.detectedGateway() else {
            debugLog("🔍 testGateway() - not applicable: no gateway address could be read or inferred")
            return DiagnosticTest(
                name: "Router/Gateway",
                result: .notApplicable,
                latency: nil,
                details: "Not applicable — this network's router address couldn't be determined",
                timestamp: Date()
            )
        }

        let (success, latency) = await networkMonitor.pingHost(gateway.ip, timeout: 2.0)
        debugLog("🔍 testGateway() - target: \(gateway.ip)\(gateway.isAssumed ? " (assumed)" : " (routing table)"), success: \(success), latency: \(latency.map { String(Int($0)) } ?? "nil")")

        if success {
            return DiagnosticTest(
                name: "Router/Gateway",
                result: .pass,
                latency: latency,
                details: "Router \(gateway.ip) reachable",
                timestamp: Date()
            )
        }
        if gateway.isAssumed {
            return DiagnosticTest(
                name: "Router/Gateway",
                result: .warning,
                latency: nil,
                details: "Couldn't confirm the router — \(gateway.ip) was inferred, not read from the routing table, and it didn't answer",
                timestamp: Date()
            )
        }
        return DiagnosticTest(
            name: "Router/Gateway",
            result: .fail,
            latency: nil,
            details: "Router \(gateway.ip) didn't answer — disconnected, router offline, or a VPN is blocking local access",
            timestamp: Date()
        )
    }

    /// Commit 6: the target follows the SAME China-aware rule as
    /// NetworkMonitorService.getInternet() (1.1.1.1 is throttled/blocked in
    /// mainland China without a VPN, which read as "no internet" next to a
    /// passing web check on the real device), and a failed probe carries nil
    /// latency — never 0.
    private func testExternal() async -> DiagnosticTest {
        debugLog("🔍 testExternal() started")

        let preferDomestic = await MainActor.run { NetworkMonitorService.preferDomesticTargets() }
        let host = NetworkMonitorService.externalPingHost(preferDomestic: preferDomestic)
        let (success, latency) = await networkMonitor.pingHost(host, timeout: 2.0)
        let measured = success ? LatencyValidation.normalize(latency) : nil

        debugLog("🔍 testExternal() - target: \(host)\(preferDomestic ? " (domestic, in China without VPN)" : ""), success: \(success), latency: \(measured.map { String(Int($0)) } ?? "nil")")

        if !success {
            return DiagnosticTest(
                name: "External Connectivity",
                result: .fail,
                latency: nil,
                details: "\(host) didn't answer within 2 s — no internet, or this network blocks it",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "External Connectivity",
                result: .pass,
                latency: measured,
                details: "Internet reachable (\(host))",
                timestamp: Date()
            )
        }
    }

    private func testDNS() async -> DiagnosticTest {
        debugLog("🔍 testDNS() started")

        let start = Date()
        let success = await safeDNSLookup(hostname: "www.apple.com", timeout: 2.0)
        let latency = Date().timeIntervalSince(start) * 1000

        debugLog("🔍 testDNS() - success: \(success), latency: \(success ? String(format: "%.1f", latency) : "nil")")

        if !success {
            // Commit 6: the elapsed time of a FAILED lookup is the timeout, not a
            // resolution time — it must not be stored as latency.
            return DiagnosticTest(
                name: "DNS Resolution",
                result: .fail,
                latency: nil,
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
        debugLog("🔍 testHTTP() started")

        let success = await safeHTTPCheck(url: "https://www.apple.com/library/test/success.html", timeout: 3.0)

        debugLog("🔍 testHTTP() - success: \(success)")

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
        debugLog("🔍 testVPN() started")

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
        let authoritative = await MainActor.run {
            SmartVPNDetector.shared.detectionResult?.isAuthoritative ?? false
        }

        debugLog("🔍 testVPN() - networkMonitor: \(networkMonitorVPN), smartDetector: \(smartDetectorVPN), final: \(isActive)")

        // Diagnosis v2, Commit 1: this step reports the VPN STATE, it is not a
        // test that can pass. No VPN → NOT APPLICABLE (never counted as a pass).
        if isActive {
            return DiagnosticTest(
                name: "VPN Tunnel",
                result: .pass,
                latency: nil,
                details: authoritative
                    ? "VPN active (confirmed by the system)"
                    : "VPN or proxy active (inferred from routing/IP — not confirmed by the system)",
                timestamp: Date()
            )
        } else {
            return DiagnosticTest(
                name: "VPN Tunnel",
                result: .notApplicable,
                latency: nil,
                details: "Not applicable — no VPN in use",
                timestamp: Date()
            )
        }
    }

    /// Diagnosis v2, Commit 1: the old "ISP Performance" step re-pinged the
    /// same 1.1.1.1 the Internet check had just pinged and reported the second
    /// sample as an independent finding (the two could disagree by chance).
    /// One measurement, one row: this step is recorded as NOT RUN and the
    /// Internet check above is the only source for the provider path.
    nonisolated private func ispPlaceholder() -> DiagnosticTest {
        DiagnosticTest(
            name: "ISP Performance",
            result: .skipped,
            latency: nil,
            details: "Not run — same path as the Internet check above; a second ping would not be a second finding",
            timestamp: Date()
        )
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
        // Diagnosis v2, Commit 1: only claim the checks that actually ran.
        let ranCount = tests.filter { $0.result == .pass || $0.result == .warning || $0.result == .fail }.count
        let notRunCount = tests.count - ranCount
        let coverage = notRunCount == 0 ? "All \(ranCount) checks" : "\(ranCount) of \(tests.count) checks"
        if issues.isEmpty && !hasTestWarnings && !hasTestFailures {
            if vpnActive && extLatency > 150 {
                summary = "\(coverage) passed. VPN adds overhead (\(Int(extLatency))ms latency)."
            } else {
                summary = notRunCount == 0
                    ? "\(coverage) passed. Your network is healthy."
                    : "\(coverage) passed; \(notRunCount) didn't apply on this network."
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
