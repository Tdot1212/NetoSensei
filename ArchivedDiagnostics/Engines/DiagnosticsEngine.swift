//
//  DiagnosticsEngine.swift
//  NetoSensei
//
//  Diagnostics Engine Coordinator - Orchestrates all diagnostic tests
//

import Foundation
import Network

actor DiagnosticsEngine {
    static let shared = DiagnosticsEngine()
    typealias ProgressCallback = (Double, String) -> Void

    private init() {}

    // MARK: - Universal Hard Timeout Wrapper

    private func withHardTimeout<T>(
        seconds: Int = 5,
        fallback: T,
        operation: @escaping () async throws -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask {
                (try? await operation()) ?? fallback
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                return fallback
            }

            // FIXED: Safe unwrap instead of force unwrap
            let result = await group.next() ?? fallback
            group.cancelAll()
            return result
        }
    }

    // MARK: - Run Advanced Diagnostics

    func runAdvancedDiagnostics(
        targetHost: String = "www.google.com",
        onProgress: ProgressCallback? = nil
    ) async -> AdvancedDiagnosticSummary {

        // REAL DIAGNOSTICS ONLY:
        // 1. DNS Hijacking (100% real)
        // 2. VPN Leak (100% real)
        // 3. Routing traceroute (semi-real - real latency)
        // 4. Performance metrics (100% real)

        var dnsHijackResults: [DNSHijackResult] = []
        var vpnLeakResult: VPNLeakResult?
        var routingInterpretation: RoutingInterpretation?
        var performanceMetrics: PerformanceMetrics?
        // Commit 7 (design §B): every step records whether it ran, failed, or
        // did not apply. A timed-out check is a FAILED record, never a
        // synthesized "clean" result.
        var records: [CheckRecord] = []

        // 1. DNS Hijacking Test (25%) - 3s timeout
        onProgress?(0.25, "Checking for DNS hijacking...")
        debugLog("🔧 [DiagnosticsEngine] About to call SecurityEngine.shared.runDNSHijackTest()...")
        let dnsTestResult = await withHardTimeout(
            seconds: 3,
            fallback: Result<[DNSHijackResult], DiagnosticError>.failure(.timeout)
        ) {
            await SecurityEngine.shared.runDNSHijackTest()
        }
        debugLog("🔧 [DiagnosticsEngine] DNS hijack test returned with \(dnsTestResult)")
        switch dnsTestResult {
        case .success(let results) where !results.isEmpty:
            dnsHijackResults = results
            records.append(.ran(.dnsHijack, Double(results.count), unit: ""))
        case .success:
            records.append(.failed(.dnsHijack, .error("returned no results")))
        case .failure(let e):
            records.append(.failed(.dnsHijack, Self.reason(for: e)))
        }

        // 2. VPN Leak Test (50%) - 3s timeout
        onProgress?(0.5, "Testing for VPN leaks...")
        debugLog("🔧 [DiagnosticsEngine] About to call SecurityEngine.shared.runVPNLeakTest()...")
        let vpnLeakTestResult = await withHardTimeout(
            seconds: 3,
            fallback: Result<VPNLeakResult, DiagnosticError>.failure(.timeout)
        ) {
            await SecurityEngine.shared.runVPNLeakTest()
        }
        debugLog("🔧 [DiagnosticsEngine] VPN leak test returned with \(vpnLeakTestResult)")
        switch vpnLeakTestResult {
        case .success(let result) where result.vpnIP == "N/A - No VPN Active":
            vpnLeakResult = result                       // kept for the UI's "no VPN" row
            records.append(.notApplicable(.vpnLeak, "no VPN in use"))
        case .success(let result):
            vpnLeakResult = result
            records.append(.ran(.vpnLeak, result.leaked ? 1 : 0, unit: ""))
        case .failure(let e):
            vpnLeakResult = nil                          // never a synthesized "not leaked"
            records.append(.failed(.vpnLeak, Self.reason(for: e)))
        }

        // 3. Routing Traceroute (70%) - 5s timeout
        onProgress?(0.7, "Running traceroute analysis...")
        let tracerouteResult = await withHardTimeout(
            seconds: 5,
            fallback: Result<[RoutingHop], DiagnosticError>.failure(.timeout)
        ) {
            await RoutingEngine.shared.runTraceroute(to: targetHost)
        }
        switch tracerouteResult {
        case .success(let hops) where !hops.isEmpty:
            routingInterpretation = await RoutingEngine.shared.interpretRoute(hops)
            records.append(.ran(.traceroute, Double(hops.count), unit: ""))
        case .success:
            records.append(.failed(.traceroute, .error("no hops answered")))
        case .failure(let e):
            records.append(.failed(.traceroute, Self.reason(for: e)))
        }

        // 4. Performance Tests (85%) - 5s timeout
        onProgress?(0.85, "Measuring network performance...")
        let performanceResult = await PerformanceEngine.shared.runPerformanceTest(host: targetHost)
        switch performanceResult {
        case .success(let metrics):
            performanceMetrics = metrics
            if let throughput = metrics.throughput {
                records.append(.ran(.performance, throughput, unit: "Mbps"))
            } else {
                records.append(.failed(.performance, .error("No throughput measurement")))
            }
        case .failure(let e):
            records.append(.failed(.performance, Self.reason(for: e)))
        }

        // 5. Intelligent Diagnosis (95%)
        onProgress?(0.95, "Analyzing symptoms...")
        let networkDiagnosis: NetworkDiagnosisResult? = nil // Replaced by the shared coverage-aware verdict pipeline.

        // Complete (100%)
        onProgress?(1.0, "Diagnostics complete")

        // Build summary
        let summary = AdvancedDiagnosticSummary(
            timestamp: Date(),
            arpResult: nil,
            dnsHijackResults: dnsHijackResults,
            vpnLeakResult: vpnLeakResult,
            routingInterpretation: routingInterpretation,
            performanceMetrics: performanceMetrics,
            vpnRegionScores: [],
            wifiChannels: [],
            lanDevices: [],
            networkDiagnosis: networkDiagnosis,
            coverage: Coverage(records: records)
        )
        debugLog("🔧 [DiagnosticsEngine] Threat level: \(summary.overallThreatLevel.rawValue) — coverage: \(summary.coverage?.line ?? "-")")

        return summary
    }

    /// Map a DiagnosticError to the coverage vocabulary (Commit 7).
    private static func reason(for error: DiagnosticError) -> FailureReason {
        switch error {
        case .timeout: return .timeout
        case .noResponse, .unreachable: return .error("host unreachable")
        case .invalidData: return .error("returned invalid data")
        case .permissionDenied: return .blocked
        case .unknown(let s): return .error(s)
        }
    }

    // MARK: - Intelligent Diagnosis

    func runSecurityScan(onProgress: ProgressCallback? = nil) async -> AdvancedDiagnosticSummary {

        var dnsHijackResults: [DNSHijackResult] = []
        var vpnLeakResult: VPNLeakResult?

        var records: [CheckRecord] = []

        // 1. DNS Test (50%)
        onProgress?(0.5, "Testing DNS...")
        let dnsTestResult = await SecurityEngine.shared.runDNSHijackTest()
        switch dnsTestResult {
        case .success(let results) where !results.isEmpty:
            dnsHijackResults = results
            records.append(.ran(.dnsHijack, Double(results.count), unit: ""))
        case .success:
            records.append(.failed(.dnsHijack, .error("returned no results")))
        case .failure(let e):
            records.append(.failed(.dnsHijack, Self.reason(for: e)))
        }

        // 2. VPN Leak Test (100%)
        onProgress?(1.0, "Testing VPN...")
        let vpnLeakTestResult = await SecurityEngine.shared.runVPNLeakTest()
        switch vpnLeakTestResult {
        case .success(let result) where result.vpnIP == "N/A - No VPN Active":
            vpnLeakResult = result
            records.append(.notApplicable(.vpnLeak, "no VPN in use"))
        case .success(let result):
            vpnLeakResult = result
            records.append(.ran(.vpnLeak, result.leaked ? 1 : 0, unit: ""))
        case .failure(let e):
            records.append(.failed(.vpnLeak, Self.reason(for: e)))
        }

        return AdvancedDiagnosticSummary(
            timestamp: Date(),
            arpResult: nil,
            dnsHijackResults: dnsHijackResults,
            vpnLeakResult: vpnLeakResult,
            routingInterpretation: nil,
            performanceMetrics: nil,
            vpnRegionScores: [],
            wifiChannels: [],
            lanDevices: [],
            networkDiagnosis: nil,
            coverage: Coverage(records: records)
        )
    }

    // MARK: - Run Performance-Only Test

    func runPerformanceTest(targetHost: String, onProgress: ProgressCallback? = nil) async -> AdvancedDiagnosticSummary {

        var routingInterpretation: RoutingInterpretation?
        var performanceMetrics: PerformanceMetrics?

        // 1. Traceroute
        onProgress?(0.4, "Running traceroute...")
        let tracerouteResult = await RoutingEngine.shared.runTraceroute(to: targetHost)
        if case .success(let hops) = tracerouteResult {
            routingInterpretation = await RoutingEngine.shared.interpretRoute(hops)
        }

        // 2. Performance metrics
        onProgress?(0.7, "Measuring performance...")
        let performanceResult = await PerformanceEngine.shared.runPerformanceTest(host: targetHost)
        if case .success(let metrics) = performanceResult {
            performanceMetrics = metrics
        }

        // 3. Intelligent Diagnosis
        onProgress?(0.95, "Analyzing symptoms...")
        let networkDiagnosis: NetworkDiagnosisResult? = nil // Replaced by the shared coverage-aware verdict pipeline.

        onProgress?(1.0, "Complete")

        return AdvancedDiagnosticSummary(
            timestamp: Date(),
            arpResult: nil,
            dnsHijackResults: [],
            vpnLeakResult: nil,
            routingInterpretation: routingInterpretation,
            performanceMetrics: performanceMetrics,
            vpnRegionScores: [],
            wifiChannels: [],
            lanDevices: [],
            networkDiagnosis: networkDiagnosis,
            coverage: Coverage(records: [
                .notRun(.dnsHijack, "security checks not part of the performance test"),
                .notRun(.vpnLeak, "security checks not part of the performance test"),
                routingInterpretation != nil ? .ran(.traceroute, 1, unit: "") : .failed(.traceroute, .timeout),
                performanceMetrics?.throughput.map { .ran(.performance, $0, unit: "Mbps") } ?? .failed(.performance, .error("No throughput measurement"))
            ])
        )
    }
}
