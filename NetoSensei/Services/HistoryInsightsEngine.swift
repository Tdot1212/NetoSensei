//
//  HistoryInsightsEngine.swift
//  NetoSensei
//
//  Pure computation engine for generating meaningful insights from history data
//

import Foundation

// MARK: - History Insights Engine

struct HistoryInsightsEngine {

    // MARK: - Result Types

    struct Insights {
        let trend: Trend
        let bestHourRange: String?
        let worstHourRange: String?
        let vpnImpact: VPNImpact?
        let topIssue: TopIssue?
        let entryCount: Int
        let averageScore: Double
    }

    enum Trend: Equatable {
        case improving(delta: Int)
        case degrading(delta: Int)
        case stable
        case insufficient

        var displayText: String {
            switch self {
            case .improving(let delta): return "Improving (+\(delta) pts)"
            case .degrading(let delta): return "Degrading (-\(delta) pts)"
            case .stable: return "Stable"
            case .insufficient: return "Need more data"
            }
        }

        var systemImage: String {
            switch self {
            case .improving: return "arrow.up.right"
            case .degrading: return "arrow.down.right"
            case .stable: return "arrow.right"
            case .insufficient: return "info.circle"
            }
        }
    }

    struct VPNImpact {
        let withVPNAvgScore: Double
        let withoutVPNAvgScore: Double

        var scoreDelta: Double { withVPNAvgScore - withoutVPNAvgScore }
        var isVPNHurtingPerformance: Bool { scoreDelta < -10 }

        var displayText: String {
            let delta = Int(abs(scoreDelta))
            if isVPNHurtingPerformance {
                return "VPN reduces score by ~\(delta) points"
            } else if scoreDelta > 5 {
                return "VPN improves score by ~\(delta) points"
            } else {
                return "VPN has minimal impact"
            }
        }
    }

    struct TopIssue {
        let cause: String
        let frequency: Int
        let percentage: Double
        let suggestion: String

        var displayText: String {
            "\(cause) (\(Int(percentage))%)"
        }
    }

    // MARK: - Main Analysis

    static func analyze(entries: [NetworkHistoryEntry]) -> Insights {
        guard entries.count >= 3 else {
            return Insights(
                trend: .insufficient,
                bestHourRange: nil,
                worstHourRange: nil,
                vpnImpact: nil,
                topIssue: nil,
                entryCount: entries.count,
                averageScore: 0
            )
        }

        let trend = computeTrend(entries: entries)
        let (bestHour, worstHour) = computePeakHours(entries: entries)
        let vpnImpact = computeVPNImpact(entries: entries)
        let topIssue = computeTopIssue(entries: entries)

        let avgScore = entries.isEmpty ? 0 :
            Double(entries.map { $0.healthScore }.reduce(0, +)) / Double(entries.count)

        return Insights(
            trend: trend,
            bestHourRange: bestHour,
            worstHourRange: worstHour,
            vpnImpact: vpnImpact,
            topIssue: topIssue,
            entryCount: entries.count,
            averageScore: avgScore
        )
    }

    // MARK: - Trend Computation

    private static func computeTrend(entries: [NetworkHistoryEntry]) -> Trend {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 5 else { return .insufficient }

        let half = sorted.count / 2
        let firstHalf = Array(sorted.prefix(half))
        let secondHalf = Array(sorted.suffix(half))

        let firstAvg = Double(firstHalf.map { $0.healthScore }.reduce(0, +)) / Double(firstHalf.count)
        let secondAvg = Double(secondHalf.map { $0.healthScore }.reduce(0, +)) / Double(secondHalf.count)
        let delta = Int(secondAvg - firstAvg)

        if delta > 5 { return .improving(delta: delta) }
        if delta < -5 { return .degrading(delta: abs(delta)) }
        return .stable
    }

    // MARK: - Peak Hours Computation

    private static func computePeakHours(entries: [NetworkHistoryEntry]) -> (best: String?, worst: String?) {
        var hourBuckets: [Int: [Int]] = [:]
        let calendar = Calendar.current

        for entry in entries {
            let hour = calendar.component(.hour, from: entry.timestamp)
            hourBuckets[hour, default: []].append(entry.healthScore)
        }

        // Only consider hours with at least 2 measurements
        let hourAverages = hourBuckets
            .filter { $0.value.count >= 2 }
            .mapValues { scores -> Double in
                Double(scores.reduce(0, +)) / Double(scores.count)
            }

        guard !hourAverages.isEmpty else { return (nil, nil) }

        let bestHour = hourAverages.max(by: { $0.value < $1.value })?.key
        let worstHour = hourAverages.min(by: { $0.value < $1.value })?.key

        // Don't show best/worst if they're the same or very close in score
        if let best = bestHour, let worst = worstHour,
           let bestScore = hourAverages[best], let worstScore = hourAverages[worst] {
            if best == worst || abs(bestScore - worstScore) < 10 {
                return (nil, nil)
            }
        }

        return (
            bestHour.map { formatHourRange($0) },
            worstHour.map { formatHourRange($0) }
        )
    }

    private static func formatHourRange(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"

        var startComps = DateComponents()
        startComps.hour = hour
        let startDate = Calendar.current.date(from: startComps) ?? Date()

        var endComps = DateComponents()
        endComps.hour = (hour + 2) % 24
        let endDate = Calendar.current.date(from: endComps) ?? Date()

        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    // MARK: - VPN Impact Computation

    private static func computeVPNImpact(entries: [NetworkHistoryEntry]) -> VPNImpact? {
        let withVPN = entries.filter { $0.vpnActive }
        let withoutVPN = entries.filter { !$0.vpnActive }

        // Need at least 3 measurements in each category
        guard withVPN.count >= 3, withoutVPN.count >= 3 else { return nil }

        let vpnAvg = Double(withVPN.map { $0.healthScore }.reduce(0, +)) / Double(withVPN.count)
        let noVPNAvg = Double(withoutVPN.map { $0.healthScore }.reduce(0, +)) / Double(withoutVPN.count)

        return VPNImpact(withVPNAvgScore: vpnAvg, withoutVPNAvgScore: noVPNAvg)
    }

    // MARK: - Top Issue Computation

    private static let fixSuggestions: [String: String] = [
        "VPNSlow": "Try switching to a closer VPN server or a faster VPN protocol (WireGuard).",
        "VPN Slow": "Try switching to a closer VPN server or a faster VPN protocol (WireGuard).",
        "ISPCongestion": "This often peaks during evenings. Try scheduling large downloads overnight.",
        "ISP Congestion": "This often peaks during evenings. Try scheduling large downloads overnight.",
        "DNSSlow": "Switch DNS to 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google) for faster lookups.",
        "DNS Slow": "Switch DNS to 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google) for faster lookups.",
        "RouterCongestion": "Too many devices on your WiFi. Restart your router or disconnect unused devices.",
        "Router Congestion": "Too many devices on your WiFi. Restart your router or disconnect unused devices.",
        "RouterUnreachable": "Your router may be down. Try restarting it or move closer to get better signal.",
        "Router Unreachable": "Your router may be down. Try restarting it or move closer to get better signal.",
        "GatewayLatencyElevated": "Move closer to your router or check for WiFi interference.",
        "Gateway Latency Elevated": "Move closer to your router or check for WiFi interference.",
        "HighLatency": "Check if background apps are using the network. Consider QoS on your router.",
        "PacketLoss": "Move closer to your router or use a wired connection.",
        "Speed Test": "Speed test completed - this is informational, not an issue.",
        "Unknown": "Run a full diagnostic to identify the root cause.",
        "None": "Everything looks good!"
    ]

    private static func computeTopIssue(entries: [NetworkHistoryEntry]) -> TopIssue? {
        guard !entries.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for entry in entries {
            // Skip "Unknown" and "Speed Test" as they're not real issues
            let cause = entry.rootCause
            if cause != "Unknown" && cause != "None" && cause != "Speed Test" {
                counts[cause, default: 0] += 1
            }
        }

        guard let (cause, count) = counts.max(by: { $0.value < $1.value }),
              count >= 2 else { return nil }

        let percentage = Double(count) / Double(entries.count) * 100
        let suggestion = fixSuggestions[cause] ?? fixSuggestions["Unknown"]!

        return TopIssue(
            cause: cause,
            frequency: count,
            percentage: percentage,
            suggestion: suggestion
        )
    }
}
