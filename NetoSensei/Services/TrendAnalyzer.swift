//
//  TrendAnalyzer.swift
//  NetoSensei
//
//  Analyzes speed test and diagnostic history for trend insights
//

import Foundation

struct TrendAnalyzer {

    struct TrendInsight: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let severity: Severity
        let metric: String
        let changePercent: Double?

        enum Severity {
            case positive, neutral, negative
        }
    }

    // MARK: - Speed Test Trend Analysis

    static func analyzeSpeedTrends(history: [SpeedTestResult]) -> [TrendInsight] {
        guard history.count >= 2 else { return [] }

        var insights: [TrendInsight] = []
        let sorted = history.sorted { $0.timestamp > $1.timestamp }

        // Compare last 3 tests average vs previous 3 tests average
        if sorted.count >= 6 {
            let recent = Array(sorted.prefix(3))
            let earlier = Array(sorted.dropFirst(3).prefix(3))

            let recentDownload = recent.map(\.downloadSpeed).reduce(0, +) / 3.0
            let earlierDownload = earlier.map(\.downloadSpeed).reduce(0, +) / 3.0

            if earlierDownload > 0 {
                let changePercent = ((recentDownload - earlierDownload) / earlierDownload) * 100

                if changePercent < -20 {
                    insights.append(TrendInsight(
                        title: "Download speed dropped",
                        description: "Down \(Int(abs(changePercent)))% compared to earlier tests (\(String(format: "%.0f", recentDownload)) vs \(String(format: "%.0f", earlierDownload)) Mbps)",
                        severity: .negative,
                        metric: "download",
                        changePercent: changePercent
                    ))
                } else if changePercent > 20 {
                    insights.append(TrendInsight(
                        title: "Download speed improved",
                        description: "Up \(Int(changePercent))% compared to earlier tests",
                        severity: .positive,
                        metric: "download",
                        changePercent: changePercent
                    ))
                }
            }

            // Latency trend
            let recentPing = recent.map(\.ping).reduce(0, +) / 3.0
            let earlierPing = earlier.map(\.ping).reduce(0, +) / 3.0

            if earlierPing > 0 {
                let latencyChange = ((recentPing - earlierPing) / earlierPing) * 100

                if latencyChange > 30 {
                    insights.append(TrendInsight(
                        title: "Latency has been increasing",
                        description: "Ping up \(Int(latencyChange))% over the past \(sorted.count) tests (\(Int(recentPing))ms avg now)",
                        severity: .negative,
                        metric: "latency",
                        changePercent: latencyChange
                    ))
                } else if latencyChange < -20 {
                    insights.append(TrendInsight(
                        title: "Latency has improved",
                        description: "Ping down \(Int(abs(latencyChange)))% (\(Int(recentPing))ms avg now)",
                        severity: .positive,
                        metric: "latency",
                        changePercent: latencyChange
                    ))
                }
            }
        }

        // Check for consistent packet loss
        let recentTests = Array(sorted.prefix(5))
        let lossyTests = recentTests.filter { $0.packetLoss > 1.0 }
        if lossyTests.count >= 3 {
            insights.append(TrendInsight(
                title: "Frequent packet loss",
                description: "Packet loss detected in \(lossyTests.count) of last \(recentTests.count) tests",
                severity: .negative,
                metric: "packetLoss",
                changePercent: nil
            ))
        }

        return insights
    }

    // MARK: - Diagnostic Trend Analysis

    static func analyzeDiagnosticTrends(history: [DiagnosticHistoryEntry]) -> [TrendInsight] {
        guard history.count >= 2 else { return [] }

        var insights: [TrendInsight] = []
        let sorted = history.sorted { $0.timestamp > $1.timestamp }
        let recent = Array(sorted.prefix(5))

        // Check for recurring failures
        let categoryCounts = Dictionary(grouping: recent, by: \.primaryIssueCategory)
            .mapValues(\.count)
            .filter { $0.key != "None" }

        for (category, count) in categoryCounts where count >= 3 {
            insights.append(TrendInsight(
                title: "\(category) issues recurring",
                description: "\(category) problems found in \(count) of your last \(recent.count) diagnostics",
                severity: .negative,
                metric: "diagnostic",
                changePercent: nil
            ))
        }

        // Check if recent diagnostics are improving
        if recent.count >= 3 {
            let recentIssueCount = recent.prefix(2).map(\.issueCount).reduce(0, +)
            let earlierIssueCount = recent.suffix(from: 2).prefix(2).map(\.issueCount).reduce(0, +)

            if recentIssueCount < earlierIssueCount && earlierIssueCount > 0 {
                insights.append(TrendInsight(
                    title: "Connection stability improved",
                    description: "Fewer issues detected in recent diagnostics",
                    severity: .positive,
                    metric: "stability",
                    changePercent: nil
                ))
            }
        }

        return insights
    }

    // MARK: - Combined Insights

    static func allInsights(speedHistory: [SpeedTestResult], diagnosticHistory: [DiagnosticHistoryEntry]) -> [TrendInsight] {
        let speedInsights = analyzeSpeedTrends(history: speedHistory)
        let diagInsights = analyzeDiagnosticTrends(history: diagnosticHistory)
        return speedInsights + diagInsights
    }

    /// FIX (Issue 7): Combined insights filtered against a live reference latency
    /// (typically the dashboard's currently-displayed avg latency from the
    /// stability monitor). Speed-test history can be days old and disagree
    /// wildly with the live measurement — when it does, suppress the
    /// "Latency has improved/worsened" insights so the dashboard doesn't
    /// contradict itself across cards.
    static func allInsights(
        speedHistory: [SpeedTestResult],
        diagnosticHistory: [DiagnosticHistoryEntry],
        referenceLatencyMs: Double?
    ) -> [TrendInsight] {
        let raw = allInsights(speedHistory: speedHistory, diagnosticHistory: diagnosticHistory)
        guard let ref = referenceLatencyMs, ref > 0 else { return raw }

        return raw.filter { insight in
            // Only filter latency-trend insights — other insights are independent.
            guard insight.metric == "latency" else { return true }
            // Determine the trend's "recent avg latency" by recomputing from
            // speedHistory, the same way analyzeSpeedTrends did. Cheap re-derive:
            let sorted = speedHistory.sorted { $0.timestamp > $1.timestamp }
            guard sorted.count >= 6 else { return true }
            let recent = Array(sorted.prefix(3))
            let recentPing = recent.map(\.ping).reduce(0, +) / 3.0
            // Drop insights whose recent value disagrees with the live reference
            // by more than 50% — they will only confuse the user.
            let diffRatio = abs(recentPing - ref) / max(ref, 1)
            return diffRatio < 0.5
        }
    }
}
