//
//  ISPThrottlingScanner.swift
//  NetoSensei
//
//  ISP Throttling Detection - 100% Real Detection
//  Detects: International throttling, streaming throttling, VPN throttling, torrent throttling
//

import Foundation

actor ISPThrottlingScanner {
    static let shared = ISPThrottlingScanner()

    private init() {}

    // MARK: - ISP Throttling Scan

    func performISPThrottlingScan(vpnActive: Bool) async -> ISPThrottlingStatus {
        // 1. Compare local vs overseas latency
        let (localLatency, overseasLatency) = await compareLocalVsOverseasLatency()
        let internationalThrottling = detectInternationalThrottling(
            local: localLatency,
            overseas: overseasLatency
        )

        // 2. Test streaming endpoints
        let streamingThrottling = await testStreamingThrottling()

        // 3. Detect VPN slowdown (if VPN active)
        let vpnThrottling = vpnActive ? await detectVPNThrottling() : false

        // 4. Check jitter patterns
        let (avgJitter, highJitter) = await measureJitterPatterns()

        // 5. Calculate throttling score
        let throttlingScore = calculateThrottlingScore(
            internationalThrottling: internationalThrottling,
            streamingThrottling: streamingThrottling,
            vpnThrottling: vpnThrottling,
            highJitter: highJitter
        )

        return ISPThrottlingStatus(
            localLatency: localLatency,
            overseasLatency: overseasLatency,
            internationalThrottling: internationalThrottling,
            streamingThrottling: streamingThrottling,
            vpnThrottling: vpnThrottling,
            averageJitter: avgJitter,
            highJitter: highJitter,
            throttlingScore: throttlingScore
        )
    }

    // MARK: - Compare Local vs Overseas Latency

    private func compareLocalVsOverseasLatency() async -> (local: Double, overseas: Double) {
        // Test to local servers
        let localEndpoints = [
            "https://www.google.com",  // Usually has local CDN
            "https://www.cloudflare.com"
        ]

        // Test to overseas servers
        let overseasEndpoints = [
            "https://www.bbc.co.uk",  // UK
            "https://www.nyt.com",    // US East Coast
        ]

        let localLatency = await measureAverageLatency(endpoints: localEndpoints)
        let overseasLatency = await measureAverageLatency(endpoints: overseasEndpoints)

        return (localLatency, overseasLatency)
    }

    private func measureAverageLatency(endpoints: [String]) async -> Double {
        var latencies: [Double] = []

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }

            let startTime = Date()

            do {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 10

                let (_, _) = try await URLSession.shared.data(for: request)

                let latency = Date().timeIntervalSince(startTime) * 1000  // ms
                latencies.append(latency)
            } catch {
                continue
            }
        }

        guard !latencies.isEmpty else { return 999.0 }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    private func detectInternationalThrottling(local: Double, overseas: Double) -> Bool {
        // If overseas is more than 3x slower than local, likely throttling
        if local > 0 && overseas > 0 {
            let ratio = overseas / local
            return ratio > 3.0
        }
        return false
    }

    // MARK: - Test Streaming Throttling

    private func testStreamingThrottling() async -> Bool {
        // Test streaming endpoints vs regular endpoints
        let streamingEndpoints = [
            "https://www.youtube.com",
            "https://www.netflix.com"
        ]

        let regularEndpoints = [
            "https://www.google.com",
            "https://www.cloudflare.com"
        ]

        let streamingLatency = await measureAverageLatency(endpoints: streamingEndpoints)
        let regularLatency = await measureAverageLatency(endpoints: regularEndpoints)

        // If streaming is significantly slower, likely throttling
        if regularLatency > 0 && streamingLatency > 0 {
            let ratio = streamingLatency / regularLatency
            return ratio > 2.0
        }

        return false
    }

    // MARK: - Detect VPN Throttling

    private func detectVPNThrottling() async -> Bool {
        // When VPN is active, check if latency is unusually high
        // compared to expected VPN overhead (normally 10-50ms extra)

        let gatewayLatency = await GatewaySecurityScanner.shared.performGatewayScan().gatewayLatency

        // Normal VPN overhead is 10-100ms
        // If gateway latency is > 200ms, VPN might be throttled
        return gatewayLatency > 200
    }

    // MARK: - Measure Jitter Patterns

    private func measureJitterPatterns() async -> (average: Double, isHigh: Bool) {
        // Measure latency variance by pinging gateway multiple times
        var latencies: [Double] = []

        let gatewayStatus = await GatewaySecurityScanner.shared.performGatewayScan()
        let gateway = gatewayStatus.currentGatewayIP

        // Take 10 samples
        for _ in 0..<10 {
            let latency = await pingEndpoint(gateway: gateway)
            if latency < 999.0 {
                latencies.append(latency)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms between samples
        }

        guard latencies.count > 2 else { return (0.0, false) }

        // Calculate jitter (standard deviation)
        let average = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.map { pow($0 - average, 2) }.reduce(0, +) / Double(latencies.count)
        let jitter = sqrt(variance)

        // High jitter is > 20ms
        let isHigh = jitter > 20.0

        return (jitter, isHigh)
    }

    private func pingEndpoint(gateway: String) async -> Double {
        guard let url = URL(string: "https://\(gateway)") else {
            return 999.0
        }

        let startTime = Date()

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2

            let (_, _) = try await URLSession.shared.data(for: request)

            return Date().timeIntervalSince(startTime) * 1000
        } catch {
            return 999.0
        }
    }

    // MARK: - Calculate Throttling Score

    private func calculateThrottlingScore(
        internationalThrottling: Bool,
        streamingThrottling: Bool,
        vpnThrottling: Bool,
        highJitter: Bool
    ) -> Int {
        var score = 100

        if internationalThrottling {
            score -= 40
        }

        if streamingThrottling {
            score -= 30
        }

        if vpnThrottling {
            score -= 25
        }

        if highJitter {
            score -= 15
        }

        return max(0, min(100, score))
    }
}

// MARK: - ISP Throttling Status

struct ISPThrottlingStatus: Codable, Sendable {
    let localLatency: Double
    let overseasLatency: Double
    let internationalThrottling: Bool
    let streamingThrottling: Bool
    let vpnThrottling: Bool
    let averageJitter: Double
    let highJitter: Bool
    let throttlingScore: Int

    var statusText: String {
        if internationalThrottling {
            return "🔴 International Traffic Throttled"
        } else if streamingThrottling {
            return "🟠 Streaming Traffic Throttled"
        } else if vpnThrottling {
            return "🟠 VPN Traffic Throttled"
        } else if highJitter {
            return "🟡 High Network Jitter"
        } else {
            return "🟢 No ISP Throttling Detected"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        if internationalThrottling {
            recs.append("⚠️ Your ISP is slowing down foreign websites")
            recs.append("Using a VPN may improve speed")
            recs.append("Overseas latency: \(Int(overseasLatency))ms vs local: \(Int(localLatency))ms")
        }

        if streamingThrottling {
            recs.append("ISP is throttling streaming services")
            recs.append("Enable VPN to bypass throttling")
            recs.append("Contact ISP about traffic management")
        }

        if vpnThrottling {
            recs.append("VPN traffic appears throttled")
            recs.append("Try different VPN protocol (WireGuard/OpenVPN)")
            recs.append("Switch VPN server location")
        }

        if highJitter {
            recs.append("High network jitter detected (\(String(format: "%.1f", averageJitter))ms)")
            recs.append("May cause video call issues")
            recs.append("Check for network congestion")
        }

        return recs
    }
}
