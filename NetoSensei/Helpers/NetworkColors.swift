//
//  NetworkColors.swift
//  NetoSensei
//
//  Consistent color scale for network metrics - Apple HIG Compliance
//  Use these functions everywhere to ensure visual consistency
//

import SwiftUI

struct NetworkColors {

    // MARK: - Latency Colors

    /// Color for latency values (ms)
    /// < 30ms: Green (excellent)
    /// 30-60ms: Blue (good)
    /// 60-150ms: Yellow (fair)
    /// 150-300ms: Orange (poor)
    /// > 300ms: Red (critical)
    static func forLatency(_ ms: Double) -> Color {
        switch ms {
        case ..<30: return .green
        case ..<60: return .blue
        case ..<150: return .yellow
        case ..<300: return .orange
        default: return .red
        }
    }

    /// Gateway latency has tighter thresholds since it's local network
    /// < 10ms: Green (excellent)
    /// 10-30ms: Blue (good)
    /// 30-50ms: Yellow (fair)
    /// 50-100ms: Orange (poor)
    /// > 100ms: Red (critical)
    static func forGatewayLatency(_ ms: Double) -> Color {
        switch ms {
        case ..<10: return .green
        case ..<30: return .blue
        case ..<50: return .yellow
        case ..<100: return .orange
        default: return .red
        }
    }

    // MARK: - Speed Colors

    /// Color for download/upload speed (Mbps)
    /// > 50: Green (excellent)
    /// 25-50: Blue (good)
    /// 10-25: Yellow (fair)
    /// 5-10: Orange (poor)
    /// < 5: Red (critical)
    static func forSpeed(_ mbps: Double) -> Color {
        switch mbps {
        case 50...: return .green
        case 25...: return .blue
        case 10...: return .yellow
        case 5...: return .orange
        default: return .red
        }
    }

    // MARK: - Health Score Colors

    /// Color for health scores (0-100)
    /// 80+: Green (excellent)
    /// 60-80: Blue (good)
    /// 40-60: Yellow (fair)
    /// 20-40: Orange (poor)
    /// < 20: Red (critical)
    static func forHealthScore(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60...: return .blue
        case 40...: return .yellow
        case 20...: return .orange
        default: return .red
        }
    }

    // MARK: - Packet Loss Colors

    /// Color for packet loss percentage
    /// < 0.5%: Green (excellent)
    /// 0.5-1%: Yellow (warning)
    /// 1-3%: Orange (poor)
    /// > 3%: Red (critical)
    static func forPacketLoss(_ percent: Double) -> Color {
        switch percent {
        case ..<0.5: return .green
        case ..<1: return .yellow
        case ..<3: return .orange
        default: return .red
        }
    }

    // MARK: - Jitter Colors

    /// Color for jitter (latency variation) in ms
    /// < 5ms: Green (excellent)
    /// 5-15ms: Blue (good)
    /// 15-30ms: Yellow (fair)
    /// 30-50ms: Orange (poor)
    /// > 50ms: Red (critical)
    static func forJitter(_ ms: Double) -> Color {
        switch ms {
        case ..<5: return .green
        case ..<15: return .blue
        case ..<30: return .yellow
        case ..<50: return .orange
        default: return .red
        }
    }

    // MARK: - Connection Drops Colors

    /// Color for connection drops count in 24h
    /// 0: Green (excellent)
    /// 1-2: Yellow (warning)
    /// 3-5: Orange (poor)
    /// > 5: Red (critical)
    static func forDrops(_ count: Int) -> Color {
        switch count {
        case 0: return .green
        case 1...2: return .yellow
        case 3...5: return .orange
        default: return .red
        }
    }

    // MARK: - DNS Latency Colors

    /// Color for DNS resolution time (ms)
    /// < 30ms: Green (excellent)
    /// 30-75ms: Blue (good)
    /// 75-150ms: Yellow (fair)
    /// 150-300ms: Orange (poor)
    /// > 300ms: Red (critical)
    static func forDNSLatency(_ ms: Double) -> Color {
        switch ms {
        case ..<30: return .green
        case ..<75: return .blue
        case ..<150: return .yellow
        case ..<300: return .orange
        default: return .red
        }
    }

    // MARK: - VPN Overhead Colors

    /// Color for VPN overhead (additional latency in ms)
    /// < 30ms: Green (excellent)
    /// 30-75ms: Blue (good)
    /// 75-150ms: Yellow (fair)
    /// 150-250ms: Orange (poor)
    /// > 250ms: Red (critical)
    static func forVPNOverhead(_ ms: Double) -> Color {
        switch ms {
        case ..<30: return .green
        case ..<75: return .blue
        case ..<150: return .yellow
        case ..<250: return .orange
        default: return .red
        }
    }

    // MARK: - Security Status Colors

    /// Color for security audit status
    static func forSecurityStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "passed", "secure": return .green
        case "warning", "moderate risk": return .yellow
        case "failed", "high risk": return .red
        default: return .gray
        }
    }

    // MARK: - WiFi Quality Colors

    /// Color for WiFi quality based on gateway latency and stability
    static func forWiFiQuality(_ quality: String) -> Color {
        switch quality.lowercased() {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .yellow
        case "poor": return .orange
        case "critical": return .red
        default: return .gray
        }
    }
}

// MARK: - Color Extension for Convenience

extension Color {
    /// Network-aware latency color
    static func networkLatency(_ ms: Double) -> Color {
        NetworkColors.forLatency(ms)
    }

    /// Network-aware speed color
    static func networkSpeed(_ mbps: Double) -> Color {
        NetworkColors.forSpeed(mbps)
    }

    /// Network-aware health score color
    static func networkHealth(_ score: Int) -> Color {
        NetworkColors.forHealthScore(score)
    }
}
