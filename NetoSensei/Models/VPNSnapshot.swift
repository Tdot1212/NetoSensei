//
//  VPNSnapshot.swift
//  NetoSensei
//
//  VPN State Logging & Comparison System
//  Allows users to log network state and compare VPN configurations
//

import Foundation

// MARK: - VPN Snapshot Model

struct VPNSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date

    // VPN State (USER-DECLARED, not auto-detected)
    let vpnState: VPNState
    let declaredByUser: Bool  // Always true - user explicitly set the state
    let vpnLabel: String  // User-provided label: "Japan - Tokyo", "VPN OFF", etc.

    // Public IP & Geolocation
    let publicIP: String
    let geo: GeoLocation

    // Performance Metrics
    let performance: PerformanceMetrics

    // DNS Analysis
    let dns: DNSMetrics

    // Routing Analysis
    let routing: RoutingMetrics

    // Network Details
    let network: NetworkMetrics

    // Stability & Congestion Analysis (CRITICAL for video buffering)
    let stabilityMetrics: StabilityMetrics?
    let congestionAnalysis: CongestionAnalysisResult?
    let bufferbloatTest: BufferbloatTestResult?

    // VPN Visibility & Reputation Analysis (Why sites block you)
    let vpnVisibilityTest: VPNVisibilityTestResult?

    // User Notes
    var userNotes: String?

    enum VPNState: String, Codable {
        case on = "ON"
        case off = "OFF"
        case unknown = "UNKNOWN"
    }

    struct GeoLocation: Codable, Equatable {
        let country: String
        let countryCode: String
        let city: String?
        let asn: String?
        let isp: String?
        let isVPN: Bool
        let isProxy: Bool

        var displayLocation: String {
            if let city = city, !city.isEmpty {
                return "\(city), \(country)"
            }
            return country
        }
    }

    struct PerformanceMetrics: Codable, Equatable {
        let pingAvg: Double  // ms - to gateway
        let internetPing: Double?  // ms - to 1.1.1.1
        let jitter: Double  // ms
        let packetLoss: Double  // percentage
        let downloadMbps: Double  // Mbps
        let uploadMbps: Double?  // Mbps (if available)
    }

    struct DNSMetrics: Codable, Equatable {
        let resolver: String
        let latencyMs: Double
        let hijackDetected: Bool
        let dnsBehavior: String  // "Normal China ISP", "All Normal", etc.
    }

    struct RoutingMetrics: Codable, Equatable {
        let hopCount: Int
        let avgHopLatency: Double  // ms
        let routingQuality: String  // "Optimal", "Suboptimal", "Poor"
    }

    struct NetworkMetrics: Codable, Equatable {
        let connectionType: String  // "Wi-Fi", "Cellular", etc.

        // WiFi Radio State (comprehensive - from radio layer)
        let wifiSSID: String?
        let wifiBSSID: String?  // MAC address of access point (correlation key)
        let wifiRSSI: Int?  // dBm - Signal strength (VERY IMPORTANT)
        let wifiNoise: Int?  // dBm - Noise floor (VERY IMPORTANT for SNR)
        let wifiLinkSpeed: Int?  // Mbps - TX rate (actual airtime quality)
        let wifiChannel: Int?  // WiFi channel number
        let wifiChannelWidth: Int?  // MHz - 20, 40, 80, 160
        let wifiBand: String?  // "2.4 GHz", "5 GHz", "6 GHz"
        let wifiPHYMode: String?  // "802.11ac", "802.11ax", etc.
        let wifiMCSIndex: Int?  // Modulation and Coding Scheme (advanced)
        let wifiNSS: Int?  // Number of Spatial Streams

        // Network layer
        let localIP: String?

        // Computed properties
        var snr: Int? {
            // SNR = RSSI - Noise
            // > 30 dB = Excellent
            // 20-30 dB = OK
            // < 20 dB = Poor (congestion/interference)
            guard let rssi = wifiRSSI, let noise = wifiNoise else { return nil }
            return rssi - noise
        }

        var snrQuality: String {
            guard let snr = snr else { return "Unknown" }
            if snr > 30 { return "Excellent" }
            if snr >= 20 { return "OK" }
            return "Poor (interference/congestion)"
        }

        var rssiQuality: String {
            guard let rssi = wifiRSSI else { return "Unknown" }
            if rssi >= -50 { return "Excellent" }
            if rssi >= -60 { return "Good" }
            if rssi >= -70 { return "Marginal (buffering likely)" }
            return "Poor"
        }

        var channelCongestionRisk: String {
            // 80 MHz is fast but fragile
            // 40 MHz can be slower but more stable
            // 20 MHz is slow but most stable
            guard let width = wifiChannelWidth else { return "Unknown" }
            if width >= 80 { return "High (wide channel = fragile)" }
            if width >= 40 { return "Medium" }
            return "Low (narrow channel = stable)"
        }

        var modulationQuality: String {
            // MCS Index + NSS indicate modulation rate
            // Low MCS = router forcing low rate due to congestion/interference
            guard let mcs = wifiMCSIndex else { return "Unknown" }
            if mcs >= 7 { return "High (good conditions)" }
            if mcs >= 4 { return "Medium" }
            return "Low (congestion or airtime contention)"
        }
    }

    // MARK: - Comparison Helpers

    var displayName: String {
        vpnLabel
    }

    var shortTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: timestamp)
    }

    var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    // Quality score for ranking
    var qualityScore: Double {
        var score: Double = 0

        // Throughput (40%)
        if performance.downloadMbps >= 50 { score += 40 }
        else if performance.downloadMbps >= 25 { score += 30 }
        else if performance.downloadMbps >= 10 { score += 20 }
        else { score += 10 }

        // Latency (30%)
        if performance.pingAvg < 20 { score += 30 }
        else if performance.pingAvg < 50 { score += 20 }
        else if performance.pingAvg < 100 { score += 10 }

        // Packet Loss (20%)
        if performance.packetLoss < 0.5 { score += 20 }
        else if performance.packetLoss < 2.0 { score += 10 }

        // Jitter (10%)
        if performance.jitter < 10 { score += 10 }
        else if performance.jitter < 30 { score += 5 }

        return score
    }

    var qualityRating: String {
        let score = qualityScore
        if score >= 80 { return "Excellent" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Fair" }
        return "Poor"
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        vpnState: VPNState,
        declaredByUser: Bool = true,
        vpnLabel: String,
        publicIP: String,
        geo: GeoLocation,
        performance: PerformanceMetrics,
        dns: DNSMetrics,
        routing: RoutingMetrics,
        network: NetworkMetrics,
        stabilityMetrics: StabilityMetrics? = nil,
        congestionAnalysis: CongestionAnalysisResult? = nil,
        bufferbloatTest: BufferbloatTestResult? = nil,
        vpnVisibilityTest: VPNVisibilityTestResult? = nil,
        userNotes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.vpnState = vpnState
        self.declaredByUser = declaredByUser
        self.vpnLabel = vpnLabel
        self.publicIP = publicIP
        self.geo = geo
        self.performance = performance
        self.dns = dns
        self.routing = routing
        self.network = network
        self.stabilityMetrics = stabilityMetrics
        self.congestionAnalysis = congestionAnalysis
        self.bufferbloatTest = bufferbloatTest
        self.vpnVisibilityTest = vpnVisibilityTest
        self.userNotes = userNotes
    }
}

// MARK: - Snapshot Comparison

struct VPNSnapshotComparison {
    let baseline: VPNSnapshot
    let comparison: VPNSnapshot

    // Performance Deltas
    var pingDelta: Double {
        comparison.performance.pingAvg - baseline.performance.pingAvg
    }

    var jitterDelta: Double {
        comparison.performance.jitter - baseline.performance.jitter
    }

    var packetLossDelta: Double {
        comparison.performance.packetLoss - baseline.performance.packetLoss
    }

    var throughputDelta: Double {
        comparison.performance.downloadMbps - baseline.performance.downloadMbps
    }

    var throughputDeltaPercent: Double {
        guard baseline.performance.downloadMbps > 0 else { return 0 }
        return ((comparison.performance.downloadMbps - baseline.performance.downloadMbps) / baseline.performance.downloadMbps) * 100
    }

    var dnsDelta: Double {
        comparison.dns.latencyMs - baseline.dns.latencyMs
    }

    // Quality comparison
    var qualityDelta: Double {
        comparison.qualityScore - baseline.qualityScore
    }

    var winner: VPNSnapshot {
        comparison.qualityScore >= baseline.qualityScore ? comparison : baseline
    }

    // Human-readable summary
    var summary: String {
        var parts: [String] = []

        // Throughput
        if throughputDelta > 5 {
            parts.append("+\(Int(throughputDelta)) Mbps faster")
        } else if throughputDelta < -5 {
            parts.append("\(Int(throughputDelta)) Mbps slower")
        }

        // Latency
        if pingDelta > 20 {
            parts.append("+\(Int(pingDelta))ms latency")
        } else if pingDelta < -20 {
            parts.append("\(Int(abs(pingDelta)))ms faster")
        }

        // Packet loss
        if packetLossDelta > 1.0 {
            parts.append("+\(String(format: "%.1f", packetLossDelta))% loss")
        } else if packetLossDelta < -1.0 {
            parts.append("\(String(format: "%.1f", abs(packetLossDelta)))% less loss")
        }

        if parts.isEmpty {
            return "Similar performance"
        }

        return parts.joined(separator: ", ")
    }

    var detailedSummary: String {
        """
        Comparing: \(baseline.displayName) → \(comparison.displayName)

        📊 Throughput: \(String(format: "%.1f", baseline.performance.downloadMbps)) Mbps → \(String(format: "%.1f", comparison.performance.downloadMbps)) Mbps (\(throughputDelta > 0 ? "+" : "")\(String(format: "%.1f", throughputDelta)) Mbps, \(throughputDeltaPercent > 0 ? "+" : "")\(String(format: "%.0f", throughputDeltaPercent))%)
        ⏱️ Latency: \(String(format: "%.0f", baseline.performance.pingAvg))ms → \(String(format: "%.0f", comparison.performance.pingAvg))ms (\(pingDelta > 0 ? "+" : "")\(String(format: "%.0f", pingDelta))ms)
        📉 Packet Loss: \(String(format: "%.1f", baseline.performance.packetLoss))% → \(String(format: "%.1f", comparison.performance.packetLoss))% (\(packetLossDelta > 0 ? "+" : "")\(String(format: "%.1f", packetLossDelta))%)
        🌐 DNS: \(String(format: "%.0f", baseline.dns.latencyMs))ms → \(String(format: "%.0f", comparison.dns.latencyMs))ms (\(dnsDelta > 0 ? "+" : "")\(String(format: "%.0f", dnsDelta))ms)

        🏆 Winner: \(winner.displayName) (Quality: \(winner.qualityRating))
        """
    }
}

// MARK: - Snapshot Statistics

struct VPNSnapshotStatistics {
    let snapshots: [VPNSnapshot]

    var averageThroughput: Double {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map { $0.performance.downloadMbps }.reduce(0, +) / Double(snapshots.count)
    }

    var averageLatency: Double {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map { $0.performance.pingAvg }.reduce(0, +) / Double(snapshots.count)
    }

    var bestSnapshot: VPNSnapshot? {
        snapshots.max(by: { $0.qualityScore < $1.qualityScore })
    }

    var worstSnapshot: VPNSnapshot? {
        snapshots.min(by: { $0.qualityScore < $1.qualityScore })
    }

    var vpnOnSnapshots: [VPNSnapshot] {
        snapshots.filter { $0.vpnState == .on }
    }

    var vpnOffSnapshots: [VPNSnapshot] {
        snapshots.filter { $0.vpnState == .off }
    }

    var countrySummary: [String: Int] {
        var summary: [String: Int] = [:]
        for snapshot in snapshots {
            summary[snapshot.geo.country, default: 0] += 1
        }
        return summary
    }
}
