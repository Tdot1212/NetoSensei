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

    /// Internal dependency injection for controlled transport tests. The shared
    /// app instance uses real system services and sessions exclusively.
    struct Environment {
        var status: @MainActor () -> NetworkStatus
        var exit: @MainActor () async -> ExitPath.Resolution
        var latency: @MainActor () async -> (Double?, Double?, Bool)
        var pathChange: @MainActor () -> Date
        var makeSession: @Sendable () -> URLSession
        var now: @Sendable () -> TimeInterval
    }
    private let environment: Environment?
    nonisolated private let clock: @Sendable () -> TimeInterval
    init(environment: Environment? = nil) {
        self.environment = environment
        self.clock = environment?.now ?? { ProcessInfo.processInfo.systemUptime }
    }

    // MARK: - Run Speed Test (GUARANTEED TO COMPLETE)

    func runSpeedTest(measureResponsiveness: Bool = false, comparisonServer: String? = nil) async -> SpeedTestResult {
        let started = clock()
        guard !isRunning, !Task.isCancelled else {
            var unavailable = SpeedTestResult(
                downloadSpeed: 0, uploadSpeed: 0, ping: nil, jitter: nil, packetLoss: nil,
                testDuration: 0, connectionType: "Unknown", vpnActive: false
            )
            unavailable.testUnavailableReason = Task.isCancelled ? "Speed test cancelled." : "Another speed test is already running."
            return unavailable
        }
        debugLog("🚀 SpeedTestEngine: Starting speed test")

        // Update MainActor state
        self.isRunning = true
        defer { self.isRunning = false; self.currentPhase = .idle }
        let pathChangedAt = environment?.pathChange() ?? ExitPath.lastPathChange
        self.progress = 0.0
        AppLoadTracker.shared.begin("speedTest")            // Commit 7: the monitor must not judge this load
        defer { AppLoadTracker.shared.end("speedTest") }

        // Capture network state (already on MainActor)
        let status = environment?.status() ?? NetworkMonitorService.shared.currentStatus
        let connectionType = status.connectionType?.displayName ?? "Unknown"
        let ipAddress = status.publicIP
        // Phase 4: network identity for trend segmentation (same key concept
        // as DashboardViewModel.networkIdentityKey). Observed, never guessed.
        let networkSSID = status.wifi.ssid
        let localSubnet = NetworkSegment.subnet(of: status.localIP)

        // Phase 1: Finding Server (10%) — Commit 13: the exit path (country +
        // VPN state) is resolved FRESHLY, never read from a pre-switch cache.
        // Unresolvable → honest "not run".
        self.currentPhase = .findingServer; self.progress = 0.1
        let publicCountry: String?
        let vpnActive: Bool
        let exit: ExitPath.Resolution
        if let environment { exit = await environment.exit() } else { exit = await ExitPath.resolveFresh() }
        switch exit {
        case .resolved(let c, let v):
            publicCountry = c
            vpnActive = v
        case .unresolved(let reason):
            debugLog("⛔ Speed test not run — \(reason)")
            self.isRunning = false
            self.currentPhase = .idle
            var unavailable = SpeedTestResult(
                downloadSpeed: 0, uploadSpeed: 0, ping: nil, jitter: nil, packetLoss: nil,
                serverUsed: nil, serverLocation: nil, testDuration: 0,
                connectionType: connectionType, vpnActive: false, ipAddress: ipAddress,
                networkSSID: networkSSID, localSubnet: localSubnet, publicCountry: nil
            )
            unavailable.testUnavailableReason = reason
            return unavailable
        }
        let isInChina = SmartVPNDetector.shared.detectionResult?.isLikelyInChina ?? false
        // Fresh connections for this run's transfers: URLSession.shared keeps
        // pooled connections from the PREVIOUS network alive across a switch
        // (device log: "The network connection was lost" on the first upload).
        transferSession = environment?.makeSession() ?? Self.makeTransferSession()
        defer { transferSession?.invalidateAndCancel(); transferSession = nil }

        let decision = await selectServer(exitCountry: publicCountry, vpnActive: vpnActive, comparisonServer: comparisonServer)
        let serverLabel: String
        let serverRegion: SpeedTestServerSelection.Region
        switch decision {
        case .selected(let candidate, let region):
            selectedCandidate = candidate
            serverLabel = candidate.label
            serverRegion = region
            debugLog("✅ Server selected: \(candidate.label) (\(region.text))")
        case .unavailable(let reason):
            debugLog("⛔ Speed test not run — \(reason)")
            self.isRunning = false
            self.currentPhase = .idle
            var unavailable = SpeedTestResult(
                downloadSpeed: 0, uploadSpeed: 0, ping: nil, jitter: nil, packetLoss: nil,
                serverUsed: nil, serverLocation: nil, testDuration: 0,
                connectionType: connectionType, vpnActive: vpnActive, ipAddress: ipAddress,
                networkSSID: networkSSID, localSubnet: localSubnet, publicCountry: publicCountry
            )
            unavailable.testUnavailableReason = reason
            return unavailable
        }

        // Phase 2: Testing Ping (20%)
        self.currentPhase = .testingPing; self.progress = 0.2
        // China-aware: prefer domestic resolvers when in-China-without-VPN
        // (same rule as NetworkMonitorService.getInternet).
        let preferDomestic = isInChina && !vpnActive
        let latencyResult: (Double?, Double?, Bool)
        if let environment { latencyResult = await environment.latency() } else { latencyResult = await testLatency(preferDomestic: preferDomestic, vpnActive: vpnActive) }
        let (ping, jitter, pingIntercepted) = latencyResult
        debugLog("✅ Ping: \(ping.map { String(format: "%.0f", $0) + "ms" } ?? "unmeasurable")\(pingIntercepted ? " (intercepted)" : ""), Jitter: \(jitter.map { String(format: "%.0f", $0) + "ms" } ?? "—")")
        self.progress = 0.3

        let probeURL = measureResponsiveness && environment == nil ? selectedCandidate.probeURL : nil
        let probeSession = probeURL.map { _ in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 2
            configuration.timeoutIntervalForResource = 3
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        }
        defer { probeSession?.invalidateAndCancel() }
        var idleSamples: [Double] = []
        if let probeURL, let probeSession {
            for _ in 0..<5 {
                guard !Task.isCancelled else { break }
                if let elapsed = await Self.responseTime(probeURL, session: probeSession) {
                    idleSamples.append(elapsed)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        // Phase 3: Testing Download (40%) - 30s timeout
        self.currentPhase = .testingDownload; self.progress = 0.4
        let (downloadSpeed, downloadSamples) = await testDownloadSpeed(probeURL: probeURL, probes: probeSession)
        if downloadSpeed == 0 {
            debugLog("⚠️ Download test failed against \(serverLabel) (\(serverRegion.text)) — no bytes moved")
        } else {
            debugLog("✅ Download: \(downloadSpeed) Mbps")
        }
        self.progress = 0.7

        // Phase 4: Testing Upload (20%) — Commit 12: only if the selected
        // candidate declares upload support; otherwise nil with a reason.
        self.currentPhase = .testingUpload; self.progress = 0.75
        let uploadSpeed: Double
        let uploadUnavailableReason: String?
        var uploadSamples: [Double] = []
        switch SpeedTestServerSelection.uploadPlan(for: selectedCandidate) {
        case .measure(let url):
            (uploadSpeed, uploadSamples) = await testUploadSpeed(to: url, probeURL: probeURL, probes: probeSession)
            uploadUnavailableReason = nil
            debugLog("✅ Upload: \(uploadSpeed) Mbps")
        case .unsupported(let reason):
            uploadSpeed = 0
            uploadUnavailableReason = reason
            debugLog("ℹ️ Upload not measured — \(reason)")
        }
        self.progress = 0.9

        // TCP/HTTP attempts include retries, server policy and filtering. Their
        // failure ratio is not IP packet loss. Leave packet loss unmeasured.
        let packetLoss: Double? = nil
        self.progress = 1.0; self.currentPhase = .complete

        var result = SpeedTestResult(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            ping: ping,
            jitter: jitter,
            packetLoss: packetLoss,
            serverUsed: serverLabel,
            serverLocation: serverRegion.text,
            testDuration: clock() - started,
            connectionType: connectionType,
            vpnActive: vpnActive,
            ipAddress: ipAddress,
            latencyIntercepted: pingIntercepted,
            networkSSID: networkSSID,
            localSubnet: localSubnet,
            publicCountry: publicCountry
        )
        if let probeURL {
            result.responsiveness = HTTPSResponsiveness(
                endpoint: probeURL.absoluteString,
                idleMs: HTTPSResponsiveness.median(idleSamples),
                downloadMs: downloadSpeed > 0 ? HTTPSResponsiveness.median(downloadSamples) : nil,
                uploadMs: uploadSpeed > 0 ? HTTPSResponsiveness.median(uploadSamples) : nil
            )
        }
        result.measurementVersion = 2
        result.serverRegion = serverRegion.text
        result.uploadUnavailableReason = uploadUnavailableReason
        if (environment?.pathChange() ?? ExitPath.lastPathChange) != pathChangedAt {
            result.testUnavailableReason = "The network path changed during the test. Repeat on a stable connection."
        }

        if downloadSpeed <= 0 {
            result.testUnavailableReason = "No valid download transfer completed. Repeat the test when the endpoint is reachable."
        }
        if Task.isCancelled { result.testUnavailableReason = "Speed test cancelled." }
        self.isRunning = false
        self.currentPhase = .idle

        debugLog("✅ SpeedTestEngine: Test complete")
        return result
    }

    // MARK: - Server Selection (Commit 11/12: exit-path candidates, probe-qualified, no silent fallback)

    /// The candidate the current run measures against.
    private var selectedCandidate: SpeedTestServerSelection.Candidate = SpeedTestServerSelection.cloudflare

    /// Commit 13: per-run session so no pooled pre-switch connection is reused.
    private var transferSession: URLSession?
    nonisolated private static func makeTransferSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpAdditionalHeaders = ["Accept-Encoding": "identity", "Cache-Control": "no-cache"]
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 120
        return URLSession(configuration: c)
    }
    private var runSession: URLSession { transferSession ?? URLSession.shared }

    /// Probe every candidate for the exit country in order, then let the pure
    /// rules decide. Every candidate is probed (not just until the first
    /// qualifies) so the log — and the "Test Not Run" reason — show all of them.
    private func selectServer(exitCountry: String?, vpnActive: Bool, comparisonServer: String?) async -> SpeedTestServerSelection.Decision {
        let eligible = SpeedTestServerSelection.candidates(forExitCountry: exitCountry)
        let candidates = comparisonServer.map { label in eligible.filter { $0.label == label } } ?? eligible
        if candidates.isEmpty {
            return .unavailable(reason: "The baseline test server is unavailable on this route. Choose another VPN exit or repeat the baseline.")
        }
        var probes: [SpeedTestServerSelection.Probe] = []
        for c in candidates {
            if Task.isCancelled { break }
            let (ok, rtt) = await Self.probe(c, injectedSession: environment?.makeSession())
            debugLog("[SpeedTest] Candidate \(c.label) (\(c.hostname)) exit=\(exitCountry ?? "unknown") vpn=\(vpnActive): \(ok ? "reachable" : "unreachable")\(rtt.map { ", probe \(Int($0)) ms" } ?? "")")
            probes.append(.init(candidate: c, reachable: ok, rttMs: rtt))
        }
        let decision = SpeedTestServerSelection.decide(probes: probes, vpnActive: vpnActive, exitCountry: exitCountry)
        if case .unavailable(let reason) = decision {
            debugLog("[SpeedTest] No suitable server: \(reason)")
        }
        return decision
    }

    /// Commit 12 probe: GET the candidate's own zero-byte test endpoint on a
    /// FRESH connection (ephemeral session, no reuse) so the figure is the
    /// cold 3-RTT exchange the 400 ms rule was derived from; a pooled
    /// connection would understate distance. 2xx required — a host that
    /// answers but 404s the test path is not a candidate.
    nonisolated static let probeTimeoutSeconds: TimeInterval = 4.0

    nonisolated private static func probe(_ c: SpeedTestServerSelection.Candidate, injectedSession: URLSession? = nil) async -> (Bool, Double?) {
        guard let url = c.probeURL else { return (false, nil) }
        // Reachability cap, NOT the nearby rule: 4 s so a candidate behind a
        // VPN (the probe crosses the tunnel; the device run showed Cloudflare
        // at 1–2 s through one) can still answer. Direct paths are judged by
        // the 400 ms rule regardless of how long the cap is.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.probeTimeoutSeconds
        config.timeoutIntervalForResource = Self.probeTimeoutSeconds
        let session = injectedSession ?? URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let ms = Date().timeIntervalSince(start) * 1000
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (false, nil)
            }
            // NOT LatencyValidation.normalize: that filter discards ≥ 999 ms as a
            // sentinel, and the whole point here is to report a real 1162 ms.
            guard ms.isFinite, ms >= 0 else { return (true, nil) }
            return (true, ms)
        } catch {
            return (false, nil)
        }
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
            if Task.isCancelled { break }
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
        let samplesMs = samplesMs.filter { $0.isFinite && $0 >= 0 }
        guard !samplesMs.isEmpty else { return (nil, nil, false) }
        guard let medianPing = MeasurementStatistics.median(samplesMs) else { return (nil, nil, false) }

        if LatencyInterception.evaluate(externalRTTms: medianPing, gatewayRTTms: gatewayRTTms, vpnActive: vpnActive).intercepted {
            return (nil, nil, true)
        }

        return (medianPing, MeasurementStatistics.standardDeviation(samplesMs), false)
    }

    private func sampleDuringTransfer<Value>(
        url: URL?, session: URLSession?, transfer: () async throws -> Value
    ) async rethrows -> (Value, [Double]) {
        guard let url, let session else { return (try await transfer(), []) }
        let sampler = Task { @MainActor in
            var observations: [Double] = []
            while !Task.isCancelled {
                if let elapsed = await Self.responseTime(url, session: session), !Task.isCancelled {
                    observations.append(elapsed)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            return observations
        }
        defer { sampler.cancel() }
        return try await withTaskCancellationHandler {
            let value = try await transfer()
            sampler.cancel()
            return (value, await sampler.value)
        } onCancel: {
            sampler.cancel()
        }
    }

    private static func responseTime(_ url: URL, session: URLSession) async -> Double? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let started = ProcessInfo.processInfo.systemUptime
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url == url, data.count <= 1024,
              !(http.mimeType?.lowercased().contains("html") ?? false) else { return nil }
        return (ProcessInfo.processInfo.systemUptime - started) * 1000
    }

    // MARK: - Download Speed Test
    // FIXED: Use larger file size for more accurate measurements on fast connections
    // FIXED: Increased timeout to 90 seconds (25MB at 2 Mbps = ~100s each, so 2 tests need buffer)
    // FIXED: Return successful results even if second test times out

    private func testDownloadSpeed(probeURL: URL?, probes: URLSession?) async -> (Double, [Double]) {
        var collectedSpeeds: [Double] = []
        var matchingSamples: [Double] = []

        // FIXED: Progressive download sizing
        // Start with 5MB (works on slow connections / China), scale up if fast
        let testSizes: [(bytes: Int, label: String)] = [
            (5_000_000, "5MB"),    // First test: small, always completes
            (25_000_000, "25MB"),  // Second test: larger, more accurate for fast connections
        ]

        for (i, testSize) in testSizes.enumerated() {
            if Task.isCancelled { break }
            // Skip the large test if first test showed very slow speeds (<2 Mbps)
            if i == 1, let firstSpeed = collectedSpeeds.first, firstSpeed < 2.0 {
                debugLog("📥 Skipping \(testSize.label) test — connection too slow (\(String(format: "%.1f", firstSpeed)) Mbps)")
                break
            }

            do {
                let perTestTimeout = i == 0 ? 20.0 : 45.0
                let (speed, samples) = try await sampleDuringTransfer(url: probeURL, session: probes) {
                    try await withTimeout(seconds: perTestTimeout) {
                        let (candidate, session) = await MainActor.run { (self.selectedCandidate, self.runSession) }
                        guard let url = candidate.downloadURL(bytes: testSize.bytes) else {
                            throw SpeedTestTransferError.unsupported("download")
                        }

                        let start = self.clock()
                        var request = URLRequest(url: url)
                        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                        let (data, response) = try await session.data(for: request)
                        let duration = self.clock() - start
                        // Commit 12: a measurement needs a 2xx AND (about) the bytes
                        // asked for. A 200 HTML page or a 404 body is not throughput.
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            throw SpeedTestTransferError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                        }
                        guard http.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true,
                              !(http.mimeType?.lowercased().hasPrefix("text/") ?? false) else {
                            throw SpeedTestTransferError.unsupported("uncompressed binary response")
                        }
                        guard Double(data.count) >= Double(testSize.bytes) * 0.9 else {
                            throw SpeedTestTransferError.shortBody(got: data.count, wanted: testSize.bytes)
                        }

                        guard let mbps = MeasurementStatistics.throughputMbps(bytes: data.count, duration: duration) else {
                            throw SpeedTestTransferError.unsupported("valid transfer duration")
                        }

                        debugLog("📥 Download test \(i+1) (\(testSize.label)): \(String(format: "%.1f", mbps)) Mbps (\(data.count) bytes in \(String(format: "%.1f", duration))s)")
                        return mbps
                    }
                }

                if speed > 0 {
                    collectedSpeeds.append(speed)
                    matchingSamples = samples
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
            return (0, [])
        }
        return (bestSpeed, matchingSamples)
    }

    // MARK: - Upload Speed Test
    // FIXED: Use larger upload size for accurate measurements on fast connections
    // FIXED: Increased timeout to 60 seconds per test
    // FIXED: Return successful results even if second test times out

    private func testUploadSpeed(to uploadURL: URL, probeURL: URL?, probes: URLSession?) async -> (Double, [Double]) {
        var collectedSpeeds: [Double] = []
        var matchingSamples: [Double] = []

        // FIXED: Generate 10MB of test data for more accurate upload measurement
        let testData = Data(repeating: 0, count: 10_000_000)  // 10MB

        // FIXED: Create individual test tasks with their own timeouts
        for i in 0..<2 {
            if Task.isCancelled { break }
            do {
                // Each upload test gets 45 seconds
                let (speed, samples) = try await sampleDuringTransfer(url: probeURL, session: probes) {
                    try await withTimeout(seconds: 45.0) {
                        var request = URLRequest(url: uploadURL)
                        request.httpMethod = "POST"
                        request.httpBody = testData
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

                        let session = await MainActor.run { self.runSession }
                        let start = self.clock()
                        let (response, sentBytes) = try await UploadTransfer.perform(session: session, request: request)
                        let duration = self.clock() - start
                        // Commit 12: a rejected upload (405/413/…) returns fast and
                        // would read as a huge figure. Only a 2xx counts.
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            throw SpeedTestTransferError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                        }
                        guard sentBytes == Int64(testData.count),
                              let mbps = MeasurementStatistics.throughputMbps(bytes: Int(sentBytes), duration: duration) else {
                            throw SpeedTestTransferError.unsupported("valid transfer duration")
                        }

                        debugLog("📤 Upload test \(i+1): \(String(format: "%.1f", mbps)) Mbps (\(testData.count) bytes in \(String(format: "%.1f", duration))s)")
                        return mbps
                    }
                }

                if speed > 0 {
                    collectedSpeeds.append(speed)
                    matchingSamples.append(contentsOf: samples)
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
            return (0, [])
        }

        let avgSpeed = collectedSpeeds.reduce(0, +) / Double(collectedSpeeds.count)
        debugLog("📤 Upload result: \(String(format: "%.1f", avgSpeed)) Mbps (from \(collectedSpeeds.count) successful test(s))")
        return (avgSpeed, matchingSamples)
    }

    // Legacy helper retained for decoding/auditing old probe-failure behavior.
    /// Legacy probe-failure calculation, not used as an IP packet-loss metric.
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

/// Commit 12: why a transfer did not count as a measurement.
enum SpeedTestTransferError: LocalizedError, CustomStringConvertible {
    case unsupported(String)
    case badStatus(Int)
    case shortBody(got: Int, wanted: Int)

    var description: String {
        switch self {
        case .unsupported(let what): return "candidate does not support \(what)"
        case .badStatus(let code): return "HTTP \(code)"
        case .shortBody(let got, let wanted): return "short body (\(got) of \(wanted) bytes)"
        }
    }
    var errorDescription: String? { description }
}
