//
//  VPNProfile.swift
//  NetoSensei
//
//  VPN Profile - Real benchmark data from manual VPN testing
//  No fake data, no simulation - just real measurements
//

import Foundation

// MARK: - VPN Profile

struct VPNProfile: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date

    // VPN Configuration
    let region: String  // e.g., "Japan - Tokyo"
    let country: String  // e.g., "Japan"
    let city: String  // e.g., "Tokyo"
    let protocolMode: String  // e.g., "Stealth", "WireGuard", "XProtocol"
    let publicIP: String

    // Performance Metrics (Real measurements)
    let latency: Double  // ms
    let jitter: Double  // ms
    let packetLoss: Double  // %
    let downloadSpeed: Double  // Mbps
    let uploadSpeed: Double  // Mbps

    // Stability Metrics
    let timeToStabilize: Double  // seconds (how long until connection is stable)
    let dnsLeakDetected: Bool
    let connectionQuality: ConnectionQuality

    // Calculated Scores
    let overallScore: Double  // 0-10
    let streamingQuality: StreamingQuality

    // User Notes (Optional)
    var notes: String?

    init(
        region: String,
        country: String,
        city: String,
        protocolMode: String,
        publicIP: String,
        latency: Double,
        jitter: Double,
        packetLoss: Double,
        downloadSpeed: Double,
        uploadSpeed: Double,
        timeToStabilize: Double,
        dnsLeakDetected: Bool,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.region = region
        self.country = country
        self.city = city
        self.protocolMode = protocolMode
        self.publicIP = publicIP
        self.latency = latency
        self.jitter = jitter
        self.packetLoss = packetLoss
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.timeToStabilize = timeToStabilize
        self.dnsLeakDetected = dnsLeakDetected
        self.notes = notes

        // Calculate connection quality
        self.connectionQuality = Self.calculateConnectionQuality(
            latency: latency,
            jitter: jitter,
            packetLoss: packetLoss
        )

        // Calculate overall score (0-10)
        self.overallScore = Self.calculateOverallScore(
            latency: latency,
            jitter: jitter,
            packetLoss: packetLoss,
            downloadSpeed: downloadSpeed,
            dnsLeakDetected: dnsLeakDetected
        )

        // Determine streaming quality
        self.streamingQuality = Self.determineStreamingQuality(
            latency: latency,
            downloadSpeed: downloadSpeed,
            jitter: jitter
        )
    }

    // MARK: - Score Calculations

    private static func calculateConnectionQuality(
        latency: Double,
        jitter: Double,
        packetLoss: Double
    ) -> ConnectionQuality {
        // Score based on real thresholds
        if latency < 30 && jitter < 10 && packetLoss < 0.5 {
            return .excellent
        } else if latency < 80 && jitter < 20 && packetLoss < 1.0 {
            return .good
        } else if latency < 150 && jitter < 50 && packetLoss < 3.0 {
            return .fair
        } else {
            return .poor
        }
    }

    private static func calculateOverallScore(
        latency: Double,
        jitter: Double,
        packetLoss: Double,
        downloadSpeed: Double,
        dnsLeakDetected: Bool
    ) -> Double {
        var score: Double = 10.0

        // Latency penalties
        if latency > 200 { score -= 4.0 }
        else if latency > 150 { score -= 3.0 }
        else if latency > 100 { score -= 2.0 }
        else if latency > 50 { score -= 1.0 }
        else if latency > 30 { score -= 0.5 }

        // Jitter penalties
        if jitter > 50 { score -= 2.0 }
        else if jitter > 30 { score -= 1.5 }
        else if jitter > 15 { score -= 1.0 }
        else if jitter > 10 { score -= 0.5 }

        // Packet loss penalties
        score -= (packetLoss * 0.5)  // Each 1% loss = -0.5 points

        // Speed penalties
        if downloadSpeed < 10 { score -= 1.5 }
        else if downloadSpeed < 25 { score -= 0.5 }

        // DNS leak penalty
        if dnsLeakDetected { score -= 2.0 }

        return max(0.0, min(10.0, score))
    }

    private static func determineStreamingQuality(
        latency: Double,
        downloadSpeed: Double,
        jitter: Double
    ) -> StreamingQuality {
        // Real thresholds for streaming
        if latency < 30 && downloadSpeed > 25 && jitter < 10 {
            return .fourK  // 4K smooth
        } else if latency < 80 && downloadSpeed > 15 && jitter < 20 {
            return .fullHD  // 1080p stable
        } else if latency < 150 && downloadSpeed > 8 && jitter < 50 {
            return .hd  // 720p
        } else {
            return .buffering  // Will buffer
        }
    }

    // MARK: - User-Friendly Descriptions

    var displayName: String {
        "\(region) • \(protocolMode)"
    }

    var scoreText: String {
        String(format: "%.1f/10", overallScore)
    }

    var scoreColor: String {
        if overallScore >= 8.0 { return "green" }
        else if overallScore >= 6.0 { return "blue" }
        else if overallScore >= 4.0 { return "orange" }
        else { return "red" }
    }

    var performanceSummary: String {
        """
        \(Int(latency))ms ping • \(String(format: "%.1f", downloadSpeed)) Mbps • \(String(format: "%.1f", packetLoss))% loss
        """
    }

    var streamingText: String {
        switch streamingQuality {
        case .fourK:
            return "🎬 4K streaming smooth"
        case .fullHD:
            return "🎬 1080p stable"
        case .hd:
            return "🎬 720p quality"
        case .buffering:
            return "⚠️ May buffer"
        }
    }
}

// MARK: - Connection Quality

enum ConnectionQuality: String, Codable, Sendable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🔵"
        case .fair: return "🟡"
        case .poor: return "🔴"
        }
    }
}

// MARK: - Streaming Quality

enum StreamingQuality: String, Codable, Sendable {
    case fourK = "4K"
    case fullHD = "1080p"
    case hd = "720p"
    case buffering = "Buffering"
}

// MARK: - WiFi Baseline Profile

struct WiFiBaselineProfile: Codable, Sendable {
    let timestamp: Date
    let publicIP: String
    let latency: Double
    let jitter: Double
    let packetLoss: Double
    let downloadSpeed: Double
    let uploadSpeed: Double

    var displaySummary: String {
        """
        WiFi Baseline (No VPN)
        \(Int(latency))ms • \(String(format: "%.1f", downloadSpeed)) Mbps • \(String(format: "%.1f", packetLoss))% loss
        """
    }
}

// MARK: - VPN vs WiFi Comparison

struct VPNComparison: Sendable {
    let baseline: WiFiBaselineProfile
    let vpnProfile: VPNProfile

    var latencyIncrease: Double {
        vpnProfile.latency - baseline.latency
    }

    var speedDecrease: Double {
        baseline.downloadSpeed - vpnProfile.downloadSpeed
    }

    var speedDecreasePercentage: Double {
        guard baseline.downloadSpeed > 0 else { return 0 }
        return (speedDecrease / baseline.downloadSpeed) * 100
    }

    var diagnosis: String {
        var issues: [String] = []

        if latencyIncrease > 100 {
            issues.append("VPN adds \(Int(latencyIncrease))ms latency (high)")
        } else if latencyIncrease > 50 {
            issues.append("VPN adds \(Int(latencyIncrease))ms latency")
        }

        if speedDecreasePercentage > 70 {
            issues.append("VPN slows speed by \(Int(speedDecreasePercentage))% (severe)")
        } else if speedDecreasePercentage > 40 {
            issues.append("VPN slows speed by \(Int(speedDecreasePercentage))%")
        }

        if vpnProfile.jitter > baseline.jitter * 3 {
            issues.append("VPN connection is unstable")
        }

        if issues.isEmpty {
            return "✅ Your WiFi is fine, VPN has minimal impact"
        } else {
            return "🔴 " + issues.joined(separator: "\n• ")
        }
    }

    var recommendation: String {
        if speedDecreasePercentage > 70 || latencyIncrease > 100 {
            return "Try a different VPN region or protocol"
        } else if speedDecreasePercentage > 40 {
            return "Consider switching to a closer VPN server"
        } else {
            return "VPN performance is acceptable"
        }
    }
}
