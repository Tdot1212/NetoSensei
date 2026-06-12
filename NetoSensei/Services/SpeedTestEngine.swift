//
//  SpeedTestEngine.swift
//  NetoSensei
//
//  FIXED: Actor isolation, proper async/await, guaranteed completion
//

import Foundation
import Network

@MainActor
class SpeedTestEngine: ObservableObject {
    static let shared = SpeedTestEngine()

    @Published var isRunning = false
    @Published var currentPhase: TestPhase = .idle
    @Published var progress: Double = 0.0

    enum TestPhase {
        case idle
        case findingServer
        case testingPing
        case testingDownload
        case testingUpload
        case complete
    }

    private init() {}

    // MARK: - Run Speed Test (GUARANTEED TO COMPLETE)

    /// Whether the last speed test was against an overseas server (affects interpretation)
    @Published var lastTestWasOverseas: Bool = false

    func runSpeedTest() async -> SpeedTestResult {
        debugLog("🚀 SpeedTestEngine: Starting speed test")

        // Update MainActor state
        self.isRunning = true
        self.progress = 0.0

        // Capture network state (already on MainActor)
        let status = NetworkMonitorService.shared.currentStatus
        let connectionType = status.connectionType?.displayName ?? "Unknown"
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
        let ipAddress = status.publicIP
        let isInChina = SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false

        // Phase 1: Finding Server (10%)
        self.currentPhase = .findingServer; self.progress = 0.1
        selectedServer = await findBestServer()
        let serverLabel = isInternationalTest ? "\(currentServer.label) (overseas)" : currentServer.label
        debugLog("✅ Server selected: \(serverLabel)")

        // Phase 2: Testing Ping (20%)
        self.currentPhase = .testingPing; self.progress = 0.2
        // China-aware: prefer domestic resolvers when in-China-without-VPN
        // (same rule as NetworkMonitorService.getInternet).
        let preferDomestic = isInChina && !vpnActive
        let (ping, jitter, pingIntercepted) = await testLatency(preferDomestic: preferDomestic, vpnActive: vpnActive)
        debugLog("✅ Ping: \(ping.map { String(format: "%.0f", $0) + "ms" } ?? "unmeasurable")\(pingIntercepted ? " (intercepted)" : ""), Jitter: \(jitter.map { String(format: "%.0f", $0) + "ms" } ?? "—")")
        self.progress = 0.3

        // Phase 3: Testing Download (40%) - 30s timeout
        self.currentPhase = .testingDownload; self.progress = 0.4
        let (downloadSpeed, _) = await testDownloadSpeed(timeout: 30.0)
        if downloadSpeed == 0 && isInChina && !vpnActive {
            debugLog("⚠️ Download test failed — overseas server unreachable from China without VPN")
        } else {
            debugLog("✅ Download: \(downloadSpeed) Mbps")
        }
        self.progress = 0.7

        // Phase 4: Testing Upload (20%) - 20s timeout
        self.currentPhase = .testingUpload; self.progress = 0.75
        let uploadSpeed = await testUploadSpeed(timeout: 20.0)
        debugLog("✅ Upload: \(uploadSpeed) Mbps")
        self.progress = 0.9

        // Phase 5: Measure Packet Loss (10%)
        // INTERNAL CONSISTENCY (Phase 3 physics authority): a test run that just
        // moved real bytes cannot have 100% loss. Total probe failure with
        // working throughput = "probes blocked", reported as nil, never 100%.
        let throughputSucceeded = downloadSpeed > 0 || uploadSpeed > 0
        let packetLoss = await measurePacketLoss(throughputSucceeded: throughputSucceeded, vpnActive: vpnActive)
        debugLog("✅ Packet Loss: \(packetLoss.map { String(format: "%.1f", $0) + "%" } ?? "unmeasurable (probes blocked)")")
        self.progress = 1.0; self.currentPhase = .complete

        self.lastTestWasOverseas = isInternationalTest

        let result = SpeedTestResult(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            ping: ping,
            jitter: jitter,
            packetLoss: packetLoss,
            serverUsed: serverLabel,
            serverLocation: isInternationalTest ? "\(currentServer.location) (overseas)" : currentServer.location,
            testDuration: 0,
            connectionType: connectionType,
            vpnActive: vpnActive,
            ipAddress: ipAddress,
            latencyIntercepted: pingIntercepted
        )

        self.isRunning = false
        self.currentPhase = .idle

        debugLog("✅ SpeedTestEngine: Test complete")
        return result
    }

    // MARK: - Server Selection (China-aware)

    /// Speed test server descriptor
    struct SpeedTestServer {
        let hostname: String
        let label: String
        let location: String
        let isCloudflare: Bool  // Uses Cloudflare /__down / /__up API

        /// Build download URL for this server
        func downloadURL(bytes: Int) -> String {
            if isCloudflare {
                return "https://\(hostname)/__down?bytes=\(bytes)"
            }
            // For non-Cloudflare servers, download a fixed-size test file
            // We'll measure whatever we get
            return "https://\(hostname)/__down?bytes=\(bytes)"
        }

        /// Build upload URL for this server
        func uploadURL() -> String {
            return "https://\(hostname)/__up"
        }
    }

    /// China-domestic speed test servers (tried in order)
    private static let chinaDomesticServers: [SpeedTestServer] = [
        // Cloudflare has China PoPs via JD Cloud partnership — often reachable and fast domestically
        SpeedTestServer(hostname: "speed.cloudflare.com", label: "Cloudflare (China PoP)", location: "Cloudflare China", isCloudflare: true),
    ]

    private static let cloudflareServer = SpeedTestServer(
        hostname: "speed.cloudflare.com", label: "Cloudflare", location: "Cloudflare", isCloudflare: true
    )

    /// Selected server for current test
    private var selectedServer: String = "speed.cloudflare.com"

    /// Whether we're testing via an international path (affects result interpretation)
    private var isInternationalTest: Bool = false

    /// The selected server descriptor
    private var currentServer: SpeedTestServer = cloudflareServer

    private func selectBestServer() -> String {
        return selectedServer
    }

    /// Find the best reachable speed test server, considering China mode
    private func findBestServer() async -> String {
        let isInChina = SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        if isInChina && !vpnActive {
            // China without VPN: Try domestic servers first
            for server in Self.chinaDomesticServers {
                let (ok, latency) = await NetworkMonitorService.shared.pingHost(server.hostname, timeout: 3.0)
                if ok {
                    currentServer = server
                    // If latency < 80ms, likely hitting a China PoP (domestic);
                    // higher (or unmeasured) implies international routing. No 999
                    // sentinel — an absent latency simply isn't "domestic".
                    let isDomestic = (latency.map { $0 < 80 } ?? false)
                    isInternationalTest = !isDomestic
                    let routeLabel = isDomestic ? "domestic" : "international"
                    debugLog("[SpeedTest] In China, \(server.label) reachable (\(routeLabel), \(latency.map { "\(Int($0))ms" } ?? "latency n/a"))")
                    return server.hostname
                }
            }
            // No servers reachable
            isInternationalTest = true
            currentServer = Self.cloudflareServer
            debugLog("[SpeedTest] In China without VPN, all servers unreachable — speed test will likely fail")
            return "speed.cloudflare.com"
        }

        // Outside China or VPN active: use Cloudflare
        isInternationalTest = false
        currentServer = Self.cloudflareServer
        return "speed.cloudflare.com"
    }

    // MARK: - Latency Test (Phase 3: sentinel-free, interception-aware)
    //
    // Transport: the Phase 2.1 BSD TCP-handshake probe (NetworkLatencyProbe),
    // NOT the old URLSession HTTP-HEAD ping. Reasons:
    //   - It measures pure network RTT (no TLS/server time), so it is directly
    //     comparable to the gateway reference and the LatencyInterception
    //     detector applies cleanly.
    //   - The old 1.0s HTTP-HEAD timeout was the bug: through a latency-adding
    //     tunnel every HEAD exceeded 1.0s and all 10 samples failed -> the
    //     999ms sentinel, even though 35MB bulk transfers (20-45s timeouts)
    //     succeeded. A handshake either completes fast or is honestly absent.
    //
    // Returns (ping?, jitter?, intercepted): nil ping/jitter means unmeasurable
    // (probes failed OR a local proxy intercepted the handshake). NEVER 999.

    /// Handshake samples per ping measurement. 8 balances jitter stability
    /// against runtime; each sample is one NetworkLatencyProbe round-trip.
    private static let pingSampleCount = 8
    /// Gap between samples (matches the original 50ms cadence).
    private static let pingSampleGapNanos: UInt64 = 50_000_000
    /// Overall wall-clock budget for the ping phase. Partial samples are kept
    /// (no cancellation), so a slow path yields whatever completed rather than
    /// a sentinel. Bounds the pathological all-fail case.
    private static let pingBudgetSeconds: TimeInterval = 8.0

    private func testLatency(preferDomestic: Bool, vpnActive: Bool) async -> (ping: Double?, jitter: Double?, intercepted: Bool) {
        // Fresh, honest gateway reference (LAN traffic is unproxied) — Phase 2.1 reuse.
        let gatewayRefMs = await NetworkMonitorService.shared.measureGatewayReferenceRTT()

        var samplesMs: [Double] = []
        let start = Date()
        for _ in 0..<Self.pingSampleCount {
            if Date().timeIntervalSince(start) > Self.pingBudgetSeconds { break }
            if let rttSec = await NetworkLatencyProbe.shared.measureExternalLatency(preferDomestic: preferDomestic) {
                samplesMs.append(rttSec * 1000.0)
            }
            try? await Task.sleep(nanoseconds: Self.pingSampleGapNanos)
        }

        if samplesMs.isEmpty {
            debugLog("[SpeedTest] Ping unmeasurable — all handshake probes failed (gatewayRef=\(gatewayRefMs.map { String(format: "%.1f", $0) } ?? "nil")ms)")
        }
        let verdict = Self.pingVerdict(samplesMs: samplesMs, gatewayRTTms: gatewayRefMs, vpnActive: vpnActive)
        if verdict.intercepted {
            debugLog("[SpeedTest] Ping intercepted by local proxy (median vs gateway \(gatewayRefMs.map { String(format: "%.1f", $0) } ?? "nil")ms)")
        }
        return verdict
    }

    /// Pure ping verdict (Phase 3, testable without network I/O):
    ///   - no samples            -> (nil, nil, false)  unmeasurable, NEVER 999
    ///   - median intercepted    -> (nil, nil, true)   local proxy stub answered it
    ///   - otherwise             -> (median, jitter, false)  real measurement
    /// Interception reuses the Phase 2.1 LatencyInterception detector so an
    /// implausibly-low handshake vs the gateway is excluded, not shown as a
    /// fabricated ~1ms "great" ping.
    nonisolated static func pingVerdict(samplesMs: [Double], gatewayRTTms: Double?, vpnActive: Bool) -> (ping: Double?, jitter: Double?, intercepted: Bool) {
        guard !samplesMs.isEmpty else { return (nil, nil, false) }

        let sorted = samplesMs.sorted()
        let medianPing = sorted[sorted.count / 2]

        if LatencyInterception.evaluate(externalRTTms: medianPing, gatewayRTTms: gatewayRTTms, vpnActive: vpnActive).intercepted {
            return (nil, nil, true)
        }

        let avg = samplesMs.reduce(0, +) / Double(samplesMs.count)
        let variance = samplesMs.map { pow($0 - avg, 2) }.reduce(0, +) / Double(samplesMs.count)
        return (medianPing, sqrt(variance), false)
    }

    // MARK: - Download Speed Test
    // FIXED: Use larger file size for more accurate measurements on fast connections
    // FIXED: Increased timeout to 90 seconds (25MB at 2 Mbps = ~100s each, so 2 tests need buffer)
    // FIXED: Return successful results even if second test times out

    private func testDownloadSpeed(timeout: TimeInterval) async -> (Double, Double?) {
        var collectedSpeeds: [Double] = []

        // FIXED: Progressive download sizing
        // Start with 5MB (works on slow connections / China), scale up if fast
        let testSizes: [(bytes: Int, label: String)] = [
            (5_000_000, "5MB"),    // First test: small, always completes
            (25_000_000, "25MB"),  // Second test: larger, more accurate for fast connections
        ]

        for (i, testSize) in testSizes.enumerated() {
            // Skip the large test if first test showed very slow speeds (<2 Mbps)
            if i == 1, let firstSpeed = collectedSpeeds.first, firstSpeed < 2.0 {
                debugLog("📥 Skipping \(testSize.label) test — connection too slow (\(String(format: "%.1f", firstSpeed)) Mbps)")
                break
            }

            do {
                let perTestTimeout = i == 0 ? 20.0 : 45.0
                let speed = try await withTimeout(seconds: perTestTimeout) {
                    let server = await MainActor.run { self.selectedServer }
                    let testURL = "https://\(server)/__down?bytes=\(testSize.bytes)"
                    guard let url = URL(string: testURL) else { return 0.0 }

                    let start = Date()
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let duration = Date().timeIntervalSince(start)

                    let megabits = Double(data.count) * 8 / 1_000_000
                    let mbps = megabits / duration

                    debugLog("📥 Download test \(i+1) (\(testSize.label)): \(String(format: "%.1f", mbps)) Mbps (\(data.count) bytes in \(String(format: "%.1f", duration))s)")
                    return mbps
                }

                if speed > 0 {
                    collectedSpeeds.append(speed)
                }
            } catch {
                debugLog("⚠️ Download test \(i+1) (\(testSize.label)) failed: \(error.localizedDescription)")
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        // The last entry is the most recent / largest-size test, which is also the
        // most accurate. .last is also a single element when only one test ran, so
        // this naturally handles both single- and multi-result cases.
        guard let bestSpeed = collectedSpeeds.last else {
            debugLog("⚠️ All download tests failed")
            return (0.0, nil)
        }

        let avgSpeed = collectedSpeeds.reduce(0, +) / Double(collectedSpeeds.count)
        let variance = collectedSpeeds.count > 1
            ? collectedSpeeds.map { pow($0 - avgSpeed, 2) }.reduce(0, +) / Double(collectedSpeeds.count)
            : 0.0
        let jitter = sqrt(variance)

        // Use the larger test result if available (more accurate), otherwise use first
        debugLog("📥 Download result: \(String(format: "%.1f", bestSpeed)) Mbps (from \(collectedSpeeds.count) test(s))")
        return (bestSpeed, jitter)
    }

    // MARK: - Upload Speed Test
    // FIXED: Use larger upload size for accurate measurements on fast connections
    // FIXED: Increased timeout to 60 seconds per test
    // FIXED: Return successful results even if second test times out

    private func testUploadSpeed(timeout: TimeInterval) async -> Double {
        var collectedSpeeds: [Double] = []

        // FIXED: Generate 10MB of test data for more accurate upload measurement
        let testData = Data(repeating: 0, count: 10_000_000)  // 10MB

        // FIXED: Create individual test tasks with their own timeouts
        for i in 0..<2 {
            do {
                // Each upload test gets 45 seconds
                let speed = try await withTimeout(seconds: 45.0) {
                    let server = await MainActor.run { self.selectedServer }
                    let testURL = "https://\(server)/__up"
                    guard let url = URL(string: testURL) else { return 0.0 }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.httpBody = testData
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

                    let start = Date()
                    let (_, _) = try await URLSession.shared.data(for: request)
                    let duration = Date().timeIntervalSince(start)
                    let megabits = Double(testData.count) * 8 / 1_000_000
                    let mbps = megabits / duration

                    debugLog("📤 Upload test \(i+1): \(String(format: "%.1f", mbps)) Mbps (\(testData.count) bytes in \(String(format: "%.1f", duration))s)")
                    return mbps
                }

                if speed > 0 {
                    collectedSpeeds.append(speed)
                }
            } catch {
                debugLog("⚠️ Upload test \(i+1) failed: \(error.localizedDescription)")
                // Continue to use whatever successful results we have
            }

            // Short delay between tests
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s between tests
        }

        // FIXED: Return whatever successful measurements we collected
        guard !collectedSpeeds.isEmpty else {
            debugLog("⚠️ All upload tests failed")
            return 0.0
        }

        let avgSpeed = collectedSpeeds.reduce(0, +) / Double(collectedSpeeds.count)
        debugLog("📤 Upload result: \(String(format: "%.1f", avgSpeed)) Mbps (from \(collectedSpeeds.count) successful test(s))")
        return avgSpeed
    }

    // MARK: - Packet Loss Test (Phase 3: sentinel-free, consistency-gated)
    //
    // Returns nil when loss is UNMEASURABLE — never a 100% / 0% sentinel.
    // The physics authority: you can only measure loss on a path you can reach
    // at all. If zero probe rounds round-trip, that is "probes blocked", not
    // "100% loss" — and it is self-refuting when throughput simultaneously
    // succeeded (the old bug: 100% loss next to 71 Mbps). Real loss is only
    // reported when >= 1 probe round actually got through.

    /// Probe rounds; each round races 3 targets so one blocked host can't poison
    /// the metric (a round counts as reached if ANY target answers).
    private static let lossProbeRounds = 10
    /// Per-probe timeout. Loss probes need to be quick, but not so tight that a
    /// tunnel's added latency fakes a failure (that asymmetry caused the bug).
    private static let lossProbeTimeoutSeconds: TimeInterval = 1.5
    /// Overall budget; rounds actually run form the denominator.
    private static let lossBudgetSeconds: TimeInterval = 6.0

    private func measurePacketLoss(throughputSucceeded: Bool, vpnActive: Bool) async -> Double? {
        let targets = ["apple.com", "1.1.1.1", "www.baidu.com"]
        var successCount = 0
        var roundsRun = 0
        let start = Date()

        for _ in 0..<Self.lossProbeRounds {
            if Date().timeIntervalSince(start) > Self.lossBudgetSeconds { break }
            async let r1 = NetworkMonitorService.shared.pingHost(targets[0], timeout: Self.lossProbeTimeoutSeconds)
            async let r2 = NetworkMonitorService.shared.pingHost(targets[1], timeout: Self.lossProbeTimeoutSeconds)
            async let r3 = NetworkMonitorService.shared.pingHost(targets[2], timeout: Self.lossProbeTimeoutSeconds)
            let results = await [r1, r2, r3]
            roundsRun += 1
            if results.contains(where: { $0.0 == true }) {
                successCount += 1
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let loss = Self.packetLossPercent(roundsRun: roundsRun, successCount: successCount)
        if loss == nil {
            let reason = throughputSucceeded
                ? "throughput succeeded but 0/\(roundsRun) probe rounds got through → probes blocked by VPN/proxy, not packet loss"
                : "0/\(roundsRun) probe rounds got through → path unreachable, loss unmeasurable"
            debugLog("[SpeedTest] Packet loss unmeasurable — \(reason) (vpnActive=\(vpnActive))")
        }
        return loss
    }

    /// Pure packet-loss verdict (Phase 3, testable without network I/O).
    /// The physics authority: loss is only measurable on a path at least one
    /// probe reached. Zero successes -> nil ("probes blocked"), NEVER 100% —
    /// which would be self-refuting next to a successful throughput run. With
    /// >= 1 success, the honest percentage over the rounds actually run
    /// (e.g. 2 of 10 rounds failed -> 20%).
    nonisolated static func packetLossPercent(roundsRun: Int, successCount: Int) -> Double? {
        guard roundsRun > 0, successCount > 0 else { return nil }
        return Double(roundsRun - successCount) / Double(roundsRun) * 100
    }
}
