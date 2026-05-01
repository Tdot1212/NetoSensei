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
        print("🚀 SpeedTestEngine: Starting speed test")

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
        print("✅ Server selected: \(serverLabel)")

        // Phase 2: Testing Ping (20%) - 5s timeout
        self.currentPhase = .testingPing; self.progress = 0.2
        // China-aware ping target
        let pingTarget = (isInChina && !vpnActive) ? "www.baidu.com" : "cloudflare-dns.com"
        let (ping, jitter) = await testLatency(server: pingTarget, timeout: 5.0)
        print("✅ Ping: \(ping)ms, Jitter: \(jitter)ms")
        self.progress = 0.3

        // Phase 3: Testing Download (40%) - 30s timeout
        self.currentPhase = .testingDownload; self.progress = 0.4
        let (downloadSpeed, _) = await testDownloadSpeed(timeout: 30.0)
        if downloadSpeed == 0 && isInChina && !vpnActive {
            print("⚠️ Download test failed — overseas server unreachable from China without VPN")
        } else {
            print("✅ Download: \(downloadSpeed) Mbps")
        }
        self.progress = 0.7

        // Phase 4: Testing Upload (20%) - 20s timeout
        self.currentPhase = .testingUpload; self.progress = 0.75
        let uploadSpeed = await testUploadSpeed(timeout: 20.0)
        print("✅ Upload: \(uploadSpeed) Mbps")
        self.progress = 0.9

        // Phase 5: Measure Packet Loss (10%) - 5s timeout
        let packetLoss = await measurePacketLoss(timeout: 5.0)
        // CHINA RULE 5: 100% loss to ONE server ≠ network dead
        if packetLoss >= 100 && isInChina && !vpnActive {
            print("⚠️ Packet loss 100% — test endpoint may be unreachable or blocked from China")
        } else {
            print("✅ Packet Loss: \(packetLoss)%")
        }
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
            ipAddress: ipAddress
        )

        self.isRunning = false
        self.currentPhase = .idle

        print("✅ SpeedTestEngine: Test complete")
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
                    // If latency < 50ms, likely hitting a China PoP (domestic)
                    // If latency > 100ms, likely routing internationally
                    let isDomestic = (latency ?? 999) < 80
                    isInternationalTest = !isDomestic
                    let routeLabel = isDomestic ? "domestic" : "international"
                    print("[SpeedTest] In China, \(server.label) reachable (\(routeLabel), \(Int(latency ?? 0))ms)")
                    return server.hostname
                }
            }
            // No servers reachable
            isInternationalTest = true
            currentServer = Self.cloudflareServer
            print("[SpeedTest] In China without VPN, all servers unreachable — speed test will likely fail")
            return "speed.cloudflare.com"
        }

        // Outside China or VPN active: use Cloudflare
        isInternationalTest = false
        currentServer = Self.cloudflareServer
        return "speed.cloudflare.com"
    }

    // MARK: - Latency Test
    // FIXED: Test against the actual speed test server, not arbitrary hosts

    private func testLatency(server: String, timeout: TimeInterval) async -> (Double, Double) {
        do {
            return try await withTimeout(seconds: timeout) {
                var latencies: [Double] = []

                // Use the provided server for ping (China-aware target passed from caller)
                let testHost = server

                for _ in 0..<10 {
                    let (success, latency) = await NetworkMonitorService.shared.pingHost(testHost, timeout: 1.0)
                    if success, let lat = latency {
                        latencies.append(lat)
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                guard !latencies.isEmpty else {
                    return (999.0, 0.0)
                }

                // Calculate statistics
                let sortedLatencies = latencies.sorted()
                let medianPing = sortedLatencies[sortedLatencies.count / 2]  // Use median instead of avg
                let avgPing = latencies.reduce(0, +) / Double(latencies.count)
                let variance = latencies.map { pow($0 - avgPing, 2) }.reduce(0, +) / Double(latencies.count)
                let jitter = sqrt(variance)

                // Use median for display (more stable), jitter from all samples
                return (medianPing, jitter)
            }
        } catch {
            return (999.0, 0.0)
        }
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
                print("📥 Skipping \(testSize.label) test — connection too slow (\(String(format: "%.1f", firstSpeed)) Mbps)")
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

                    print("📥 Download test \(i+1) (\(testSize.label)): \(String(format: "%.1f", mbps)) Mbps (\(data.count) bytes in \(String(format: "%.1f", duration))s)")
                    return mbps
                }

                if speed > 0 {
                    collectedSpeeds.append(speed)
                }
            } catch {
                print("⚠️ Download test \(i+1) (\(testSize.label)) failed: \(error.localizedDescription)")
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        guard !collectedSpeeds.isEmpty else {
            print("⚠️ All download tests failed")
            return (0.0, nil)
        }

        // If we have both small and large test results, prefer the large test (more accurate)
        let bestSpeed = collectedSpeeds.count > 1 ? collectedSpeeds.last! : collectedSpeeds.first!
        let avgSpeed = collectedSpeeds.reduce(0, +) / Double(collectedSpeeds.count)
        let variance = collectedSpeeds.count > 1
            ? collectedSpeeds.map { pow($0 - avgSpeed, 2) }.reduce(0, +) / Double(collectedSpeeds.count)
            : 0.0
        let jitter = sqrt(variance)

        // Use the larger test result if available (more accurate), otherwise use first
        print("📥 Download result: \(String(format: "%.1f", bestSpeed)) Mbps (from \(collectedSpeeds.count) test(s))")
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

                    print("📤 Upload test \(i+1): \(String(format: "%.1f", mbps)) Mbps (\(testData.count) bytes in \(String(format: "%.1f", duration))s)")
                    return mbps
                }

                if speed > 0 {
                    collectedSpeeds.append(speed)
                }
            } catch {
                print("⚠️ Upload test \(i+1) failed: \(error.localizedDescription)")
                // Continue to use whatever successful results we have
            }

            // Short delay between tests
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s between tests
        }

        // FIXED: Return whatever successful measurements we collected
        guard !collectedSpeeds.isEmpty else {
            print("⚠️ All upload tests failed")
            return 0.0
        }

        let avgSpeed = collectedSpeeds.reduce(0, +) / Double(collectedSpeeds.count)
        print("📤 Upload result: \(String(format: "%.1f", avgSpeed)) Mbps (from \(collectedSpeeds.count) successful test(s))")
        return avgSpeed
    }

    // MARK: - Packet Loss Test

    private func measurePacketLoss(timeout: TimeInterval) async -> Double {
        do {
            return try await withTimeout(seconds: timeout) {
                var successCount = 0
                let totalPings = 10

                for _ in 0..<totalPings {
                    // FIXED: Use cloudflare-dns.com instead of 1.1.1.1
                    let (success, _) = await NetworkMonitorService.shared.pingHost("cloudflare-dns.com", timeout: 1.0)
                    if success { successCount += 1 }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                let lossPercentage = Double(totalPings - successCount) / Double(totalPings) * 100
                return lossPercentage
            }
        } catch {
            return 100.0
        }
    }
}
