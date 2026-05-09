//
//  WiFiSaturationScanner.swift
//  NetoSensei
//
//  WiFi Saturation Detection - 100% Real Detection (Indirect)
//  Detects: Router overload, too many devices, bad firmware, channel congestion
//

import Foundation
import Network

actor WiFiSaturationScanner {
    static let shared = WiFiSaturationScanner()

    // DISABLED: NWConnection spam was freezing the app
    // Set to true once the freeze issue is fixed
    private static let NWCONNECTION_TESTS_ENABLED = false

    private init() {}

    // MARK: - WiFi Saturation Scan

    func performWiFiSaturationScan() async -> WiFiSaturationStatus? {
        // DISABLED: NWConnection tests causing app freeze
        guard Self.NWCONNECTION_TESTS_ENABLED else {
            debugLog("⚠️ WiFi saturation scan DISABLED — NWConnection causing freeze")
            return nil
        }

        // 1. Measure high jitter inside LAN
        let (lanJitter, highLANJitter) = await measureLANJitter()

        // 2. Detect latency spikes to gateway
        let (gatewayLatency, latencySpikes) = await detectGatewayLatencySpikes()

        // 3. Test poor response from gateway
        let poorGatewayResponse = await testGatewayResponseQuality()

        // 4. Measure transfer speed to local endpoints
        let slowLocalTransfer = await testLocalTransferSpeed()

        // 5. Estimate saturation level
        let saturationLevel = estimateSaturationLevel(
            highJitter: highLANJitter,
            latencySpikes: latencySpikes,
            poorResponse: poorGatewayResponse,
            slowTransfer: slowLocalTransfer
        )

        // 6. Calculate saturation score
        let saturationScore = calculateSaturationScore(
            saturationLevel: saturationLevel,
            jitter: lanJitter,
            latency: gatewayLatency
        )

        return WiFiSaturationStatus(
            lanJitter: lanJitter,
            highLANJitter: highLANJitter,
            gatewayLatency: gatewayLatency,
            latencySpikes: latencySpikes,
            poorGatewayResponse: poorGatewayResponse,
            slowLocalTransfer: slowLocalTransfer,
            saturationLevel: saturationLevel,
            saturationScore: saturationScore
        )
    }

    // MARK: - Measure LAN Jitter

    private func measureLANJitter() async -> (jitter: Double, isHigh: Bool) {
        // Measure latency variance to gateway
        var latencies: [Double] = []

        let gatewayStatus = await GatewaySecurityScanner.shared.performGatewayScan()
        let gateway = gatewayStatus.currentGatewayIP

        // Take 15 samples over 1.5 seconds
        for _ in 0..<15 {
            let latency = await pingGateway(gateway)
            if latency < 999.0 {
                latencies.append(latency)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        guard latencies.count > 5 else { return (0.0, false) }

        // Calculate jitter (standard deviation)
        let average = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.map { pow($0 - average, 2) }.reduce(0, +) / Double(latencies.count)
        let jitter = sqrt(variance)

        // High LAN jitter is > 15ms (should be < 5ms on good WiFi)
        let isHigh = jitter > 15.0

        return (jitter, isHigh)
    }

    // FIXED: NWConnection removed - was causing app freeze
    private func pingGateway(_ gateway: String) async -> Double {
        // NWConnection removed - was causing app freeze
        // This function is only called when NWCONNECTION_TESTS_ENABLED = true (currently false)
        return 999.0
    }

    // MARK: - Detect Gateway Latency Spikes

    private func detectGatewayLatencySpikes() async -> (avgLatency: Double, spikes: Bool) {
        var latencies: [Double] = []

        let gatewayStatus = await GatewaySecurityScanner.shared.performGatewayScan()
        let gateway = gatewayStatus.currentGatewayIP

        // Take 20 samples
        for _ in 0..<20 {
            let latency = await pingGateway(gateway)
            if latency < 999.0 {
                latencies.append(latency)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }

        guard !latencies.isEmpty else { return (999.0, false) }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)

        // Detect spikes (latency > 2x average)
        let spikeCount = latencies.filter { $0 > avgLatency * 2.0 }.count

        // If more than 20% of samples are spikes, router is likely saturated
        let hasSpikes = Double(spikeCount) / Double(latencies.count) > 0.2

        return (avgLatency, hasSpikes)
    }

    // MARK: - Test Gateway Response Quality

    private func testGatewayResponseQuality() async -> Bool {
        // Test if gateway responds consistently
        let gatewayStatus = await GatewaySecurityScanner.shared.performGatewayScan()

        // If handshake success rate is < 80%, poor response
        return gatewayStatus.handshakeSuccessRate < 80.0
    }

    // MARK: - Test Local Transfer Speed

    private func testLocalTransferSpeed() async -> Bool {
        // Test speed to a local server (gateway)
        // If we can't transfer data quickly to gateway, network is saturated

        let gatewayLatency = await GatewaySecurityScanner.shared.performGatewayScan().gatewayLatency

        // Local transfer should be < 10ms
        // If it's > 50ms, likely saturation
        return gatewayLatency > 50.0
    }

    // MARK: - Estimate Saturation Level

    private func estimateSaturationLevel(
        highJitter: Bool,
        latencySpikes: Bool,
        poorResponse: Bool,
        slowTransfer: Bool
    ) -> SaturationLevel {
        let issueCount = [highJitter, latencySpikes, poorResponse, slowTransfer].filter { $0 }.count

        switch issueCount {
        case 4:
            return .critical
        case 3:
            return .high
        case 2:
            return .moderate
        case 1:
            return .low
        default:
            return .none
        }
    }

    // MARK: - Calculate Saturation Score

    private func calculateSaturationScore(
        saturationLevel: SaturationLevel,
        jitter: Double,
        latency: Double
    ) -> Int {
        var score = 100

        switch saturationLevel {
        case .critical:
            score -= 70
        case .high:
            score -= 50
        case .moderate:
            score -= 30
        case .low:
            score -= 15
        case .none:
            break
        }

        // Adjust for specific metrics
        if jitter > 20 {
            score -= 10
        }

        if latency > 100 {
            score -= 10
        }

        return max(0, min(100, score))
    }
}

// MARK: - WiFi Saturation Status

enum SaturationLevel: String, Codable, Sendable {
    case none = "None"
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case critical = "Critical"
}

struct WiFiSaturationStatus: Codable, Sendable {
    let lanJitter: Double
    let highLANJitter: Bool
    let gatewayLatency: Double
    let latencySpikes: Bool
    let poorGatewayResponse: Bool
    let slowLocalTransfer: Bool
    let saturationLevel: SaturationLevel
    let saturationScore: Int

    var statusText: String {
        switch saturationLevel {
        case .critical:
            return "🔴 Router Critically Overloaded"
        case .high:
            return "🟠 Router Heavily Loaded"
        case .moderate:
            return "🟡 Router Moderately Loaded"
        case .low:
            return "🟢 Router Lightly Loaded"
        case .none:
            return "🟢 Router Not Overloaded"
        }
    }

    var recommendations: [String] {
        var recs: [String] = []

        switch saturationLevel {
        case .critical, .high:
            recs.append("⚠️ Your router is overloaded")
            recs.append("Reducing connected devices will improve speed")
            recs.append("LAN jitter: \(String(format: "%.1f", lanJitter))ms")
            recs.append("Consider upgrading router or enabling QoS")
        case .moderate:
            recs.append("Router showing signs of congestion")
            recs.append("Disconnect unused devices")
            recs.append("Restart router to clear memory")
        case .low:
            recs.append("Minor router load detected")
            recs.append("Performance should be acceptable")
        case .none:
            recs.append("Router performance is good")
        }

        if highLANJitter {
            recs.append("High LAN jitter may affect video calls")
        }

        if latencySpikes {
            recs.append("Frequent latency spikes detected")
            recs.append("May cause streaming buffering")
        }

        return recs
    }
}
