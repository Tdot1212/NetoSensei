//
//  TrendAnalyzer.swift
//  NetoSensei
//
//  Analyzes speed test and diagnostic history for trend insights.
//
//  Accuracy audit Phase 4 (Trends honesty): every comparison is confined to
//  ONE network segment (see NetworkSegment) — the segment of the newest
//  record, i.e. the network the user is on now. A change of network or VPN
//  state is a state change, not a trend; comparing across it produced the
//  live bug "Download speed dropped — Down 93% (7 vs 122 Mbps)" where 122 was
//  Wi-Fi and 7 was cellular+VPN. Insufficient same-segment samples → no
//  insight. Silence beats garbage.
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
        /// The "recent" average the insight was computed from, so a caller can
        /// sanity-check it against a live reading without re-deriving history.
        let recentValue: Double?

        enum Severity {
            case positive, neutral, negative
        }

        init(title: String, description: String, severity: Severity, metric: String,
             changePercent: Double?, recentValue: Double? = nil) {
            self.title = title
            self.description = description
            self.severity = severity
            self.metric = metric
            self.changePercent = changePercent
            self.recentValue = recentValue
        }
    }

    // MARK: - Tunables

    /// Records per comparison window (recent vs earlier), within one segment.
    static let windowSize = 3
    /// Minimum same-segment records before any delta insight can be emitted.
    static var minimumSamplesForDelta: Int { windowSize * 2 }
    /// Same-segment records inspected for the packet-loss frequency insight.
    static let lossWindow = 5

    static let networkChangedMetric = "networkChanged"

    // MARK: - Speed Test Trend Analysis

    static func analyzeSpeedTrends(history: [SpeedTestResult]) -> [TrendInsight] {
        guard history.count >= 2 else { return [] }

        var insights: [TrendInsight] = []
        let sorted = history.sorted { $0.timestamp > $1.timestamp }
        guard let newest = sorted.first else { return [] }

        // The comparison base is the CURRENT network. Every other segment is
        // a different network and is excluded from every comparison below.
        let currentSegment = newest.segmentKey
        let sameSegment = sorted.filter { $0.segmentKey == currentSegment }

        // Cross-segment honesty: if the newest result is on a different
        // network than the one before it, say so instead of computing a
        // delta across the change. Neutral, self-clearing (disappears after
        // the next test on this network).
        if sorted.count >= 2, sorted[1].segmentKey != currentSegment {
            insights.append(TrendInsight(
                title: "Network changed",
                description: "Comparisons reset — trends resume after a few tests on this network.",
                severity: .neutral,
                metric: networkChangedMetric,
                changePercent: nil
            ))
        }

        // Delta insights: recent window vs earlier window, same segment only.
        if sameSegment.count >= minimumSamplesForDelta {
            let recent = Array(sameSegment.prefix(windowSize))
            let earlier = Array(sameSegment.dropFirst(windowSize).prefix(windowSize))

            // Download (always measured; 0 = failed test, excluded from the mean)
            if let (recentDownload, earlierDownload) = windowMeans(
                recent: recent.map { $0.downloadSpeed > 0 ? $0.downloadSpeed : nil },
                earlier: earlier.map { $0.downloadSpeed > 0 ? $0.downloadSpeed : nil }
            ) {
                let changePercent = ((recentDownload - earlierDownload) / earlierDownload) * 100
                if changePercent < -20 {
                    insights.append(TrendInsight(
                        title: "Download speed dropped",
                        description: "Down \(Int(abs(changePercent)))% compared to earlier tests on this network (\(String(format: "%.0f", recentDownload)) vs \(String(format: "%.0f", earlierDownload)) Mbps)",
                        severity: .negative,
                        metric: "download",
                        changePercent: changePercent,
                        recentValue: recentDownload
                    ))
                } else if changePercent > 20 {
                    insights.append(TrendInsight(
                        title: "Download speed improved",
                        description: "Up \(Int(changePercent))% compared to earlier tests on this network",
                        severity: .positive,
                        metric: "download",
                        changePercent: changePercent,
                        recentValue: recentDownload
                    ))
                }
            }

            // Latency (Phase 3: optional — only measured pings are averaged)
            if let (recentPing, earlierPing) = windowMeans(
                recent: recent.map { $0.ping },
                earlier: earlier.map { $0.ping }
            ) {
                let latencyChange = ((recentPing - earlierPing) / earlierPing) * 100
                if latencyChange > 30 {
                    insights.append(TrendInsight(
                        title: "Latency has been increasing",
                        description: "Ping up \(Int(latencyChange))% over the last \(sameSegment.count) tests on this network (\(Int(recentPing))ms avg now)",
                        severity: .negative,
                        metric: "latency",
                        changePercent: latencyChange,
                        recentValue: recentPing
                    ))
                } else if latencyChange < -20 {
                    insights.append(TrendInsight(
                        title: "Latency has improved",
                        description: "Ping down \(Int(abs(latencyChange)))% (\(Int(recentPing))ms avg now)",
                        severity: .positive,
                        metric: "latency",
                        changePercent: latencyChange,
                        recentValue: recentPing
                    ))
                }
            }
        }

        // Frequent packet loss — same network only. nil loss = unmeasurable,
        // which is not evidence of loss.
        let recentTests = Array(sameSegment.prefix(lossWindow))
        let lossyTests = recentTests.filter { ($0.packetLoss ?? 0) > 1.0 }
        if lossyTests.count >= 3 {
            insights.append(TrendInsight(
                title: "Frequent packet loss",
                description: "Packet loss detected in \(lossyTests.count) of the last \(recentTests.count) tests on this network",
                severity: .negative,
                metric: "packetLoss",
                changePercent: nil
            ))
        }

        return insights
    }

    /// Means of the measured values in each window. nil unless BOTH windows
    /// contain at least one measured value and the earlier mean is > 0 (a
    /// ratio against nothing is not a change).
    static func windowMeans(recent: [Double?], earlier: [Double?]) -> (recent: Double, earlier: Double)? {
        let r = recent.compactMap { $0 }
        let e = earlier.compactMap { $0 }
        guard !r.isEmpty, !e.isEmpty else { return nil }
        let recentMean = r.reduce(0, +) / Double(r.count)
        let earlierMean = e.reduce(0, +) / Double(e.count)
        guard earlierMean > 0 else { return nil }
        return (recentMean, earlierMean)
    }

    // MARK: - Diagnostic Trend Analysis

    static func analyzeDiagnosticTrends(history: [DiagnosticHistoryEntry]) -> [TrendInsight] {
        guard history.count >= 2 else { return [] }

        var insights: [TrendInsight] = []
        let sorted = history.sorted { $0.timestamp > $1.timestamp }
        guard let newest = sorted.first else { return [] }

        // Phase 4: same-network only. Legacy entries (no identity, key nil)
        // only ever compare with other legacy entries and age out.
        let currentSegment = newest.segmentKey
        let sameSegment = sorted.filter { $0.segmentKey == currentSegment }
        let recent = Array(sameSegment.prefix(5))
        guard recent.count >= 2 else { return [] }

        // Check for recurring failures
        let categoryCounts = Dictionary(grouping: recent, by: \.primaryIssueCategory)
            .mapValues(\.count)
            .filter { $0.key != "None" }

        for (category, count) in categoryCounts where count >= 3 {
            insights.append(TrendInsight(
                title: "\(category) issues recurring",
                description: "\(category) problems found in \(count) of your last \(recent.count) diagnostics on this network",
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
                    description: "Fewer issues detected in recent diagnostics on this network",
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
        return ordered(speedInsights + diagInsights)
    }

    /// Diagnosis v2 also-fix: the Trends card shows at most two insights, so
    /// order by what matters — real problems first, then improvements, then
    /// the neutral "Network changed" line. A stable sort keeps the original
    /// order within a severity.
    static func ordered(_ insights: [TrendInsight]) -> [TrendInsight] {
        func rank(_ s: TrendInsight.Severity) -> Int {
            switch s { case .negative: return 0; case .positive: return 1; case .neutral: return 2 }
        }
        return insights.enumerated()
            .sorted { (rank($0.element.severity), $0.offset) < (rank($1.element.severity), $1.offset) }
            .map { $0.element }
    }

    /// FIX (Issue 7): Combined insights filtered against a live reference latency
    /// (typically the dashboard's currently-displayed avg latency from the
    /// stability monitor). Speed-test history can be days old and disagree
    /// wildly with the live measurement — when it does, suppress the
    /// "Latency has improved/worsened" insights so the dashboard doesn't
    /// contradict itself across cards.
    ///
    /// Phase 4: the recent average is carried on the insight itself
    /// (`recentValue`, computed over the same network segment), so this filter
    /// no longer re-derives it from unsegmented history.
    static func allInsights(
        speedHistory: [SpeedTestResult],
        diagnosticHistory: [DiagnosticHistoryEntry],
        referenceLatencyMs: Double?
    ) -> [TrendInsight] {
        let raw = allInsights(speedHistory: speedHistory, diagnosticHistory: diagnosticHistory)
        guard let ref = referenceLatencyMs, ref > 0 else { return raw }

        return raw.filter { insight in
            // Only filter latency-trend insights — other insights are independent.
            guard insight.metric == "latency", let recentPing = insight.recentValue else { return true }
            // Drop insights whose recent value disagrees with the live reference
            // by more than 50% — they will only confuse the user.
            let diffRatio = abs(recentPing - ref) / max(ref, 1)
            return diffRatio < 0.5
        }
    }
}
