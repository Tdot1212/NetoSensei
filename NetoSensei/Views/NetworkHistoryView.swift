//
//  NetworkHistoryView.swift
//  NetoSensei
//
//  Network history timeline with charts, insights, filtering, and management
//

import SwiftUI
import Charts

// MARK: - History Metric

enum HistoryMetric: String, CaseIterable {
    case healthScore = "Health"
    case latency = "Latency"
    case speed = "Speed"
}

// MARK: - Network History View

struct NetworkHistoryView: View {
    @StateObject private var historyManager = NetworkHistoryManager.shared
    @StateObject private var stabilityMonitor = ConnectionStabilityMonitor.shared
    @State private var selectedPeriod: HistoryPeriod = .last24h
    @State private var selectedMetric: HistoryMetric = .healthScore

    // NEW: Network filter
    @State private var selectedNetworkSSID: String? = nil

    // NEW: Toolbar / sheet management
    @State private var showingExportSheet = false
    @State private var showingDeleteConfirm = false
    @State private var deleteKeepBookmarked = false
    @State private var exportCSVContent: String = ""

    // Computed filtered entries
    private var filteredEntries: [NetworkHistoryEntry] {
        historyManager.entriesForPeriod(selectedPeriod, filteredBy: selectedNetworkSSID)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: UIConstants.spacingL) {
                    // Period picker
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(HistoryPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    // NEW: Network filter chips
                    if !historyManager.knownNetworks.isEmpty {
                        networkFilterChips
                    }

                    // Connection Stability Card
                    stabilityCard

                    // Chart section
                    if !historyManager.entries.isEmpty {
                        // Metric picker
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(HistoryMetric.allCases, id: \.self) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Chart
                        if #available(iOS 16, *) {
                            chartCard
                        } else {
                            legacyChartCard
                        }

                        // Baseline comparison
                        if let baseline = historyManager.baseline,
                           let latest = filteredEntries.first {
                            baselineComparisonCard(latest: latest, baseline: baseline)
                        }

                        // NEW: Enhanced insights card
                        insightsCard

                        // NEW: Recent tests with swipe actions
                        recentTestsCard
                    } else {
                        emptyStateCard
                    }
                }
                .padding()
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { prepareAndShowExport() }) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        Button(action: {
                            deleteKeepBookmarked = true
                            showingDeleteConfirm = true
                        }) {
                            Label("Delete All (Keep Bookmarked)", systemImage: "bookmark.slash")
                        }

                        Button(role: .destructive, action: {
                            deleteKeepBookmarked = false
                            showingDeleteConfirm = true
                        }) {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                deleteKeepBookmarked ? "Delete all except bookmarked entries?" : "Delete all history?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(deleteKeepBookmarked ? "Delete Unbookmarked" : "Delete All", role: .destructive) {
                    historyManager.clearHistory(keepBookmarked: deleteKeepBookmarked)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingExportSheet) {
                ShareSheet(activityItems: [exportCSVContent])
            }
        }
    }

    // MARK: - Network Filter Chips

    private var networkFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UIConstants.spacingS) {
                filterChip(label: "All Networks", icon: "network", ssid: nil)

                ForEach(historyManager.knownNetworks, id: \.self) { ssid in
                    filterChip(label: ssid, icon: "wifi", ssid: ssid)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func filterChip(label: String, icon: String, ssid: String?) -> some View {
        let isSelected = selectedNetworkSSID == ssid

        return Button(action: {
            HapticFeedback.selection()
            selectedNetworkSSID = ssid
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, UIConstants.spacingM)
            .padding(.vertical, UIConstants.spacingS)
            .background(isSelected ? AppColors.accent : AppColors.card)
            .foregroundColor(isSelected ? .white : AppColors.textPrimary)
            .cornerRadius(UIConstants.cornerRadiusM)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadiusM)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stability Card

    private var stabilityCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(AppColors.accent)
                    Text("Connection Stability")
                        .font(.headline)
                }

                HStack(spacing: UIConstants.spacingXL) {
                    VStack(alignment: .leading) {
                        Text("Uptime")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text(stabilityMonitor.uptimeStreakFormatted)
                            .font(.title3.bold())
                            .foregroundColor(AppColors.green)
                    }

                    VStack(alignment: .leading) {
                        Text("Drops (24h)")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text("\(stabilityMonitor.dropsLast24h)")
                            .font(.title3.bold())
                            .foregroundColor(stabilityMonitor.dropsLast24h == 0 ? AppColors.green : AppColors.yellow)
                    }

                    if let avgLatency = stabilityMonitor.averageLatency {
                        VStack(alignment: .leading) {
                            Text("Avg Latency")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text("\(Int(avgLatency))ms")
                                .font(.title3.bold())
                                .foregroundColor(latencyColor(avgLatency))
                        }
                    }
                }

                // Timeline visualization
                if !stabilityMonitor.events.isEmpty {
                    timelineVisualization
                }
            }
        }
    }

    private var timelineVisualization: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last 24 hours")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 2) {
                let buckets = stabilityMonitor.timelineBuckets(hours: 24)

                ForEach(0..<buckets.count, id: \.self) { index in
                    Circle()
                        .fill(buckets[index] ? AppColors.green : AppColors.red)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    // MARK: - Chart Card (iOS 16+) with Zone Backgrounds

    @available(iOS 16, *)
    private var chartCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Text(chartTitle)
                        .font(.headline)
                    Spacer()

                    // Score label showing current zone
                    if selectedMetric == .healthScore, let latest = filteredEntries.first {
                        Text(healthZoneLabel(latest.healthScore))
                            .font(.caption.bold())
                            .foregroundColor(healthColor(latest.healthScore))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(healthColor(latest.healthScore).opacity(0.2))
                            .cornerRadius(8)
                    }
                }

                Chart {
                    // Zone backgrounds for health score only
                    if selectedMetric == .healthScore {
                        // Green zone: 70-100
                        RectangleMark(
                            xStart: nil, xEnd: nil,
                            yStart: .value("", 70),
                            yEnd: .value("", 100)
                        )
                        .foregroundStyle(AppColors.green.opacity(0.08))

                        // Yellow zone: 40-69
                        RectangleMark(
                            xStart: nil, xEnd: nil,
                            yStart: .value("", 40),
                            yEnd: .value("", 70)
                        )
                        .foregroundStyle(AppColors.yellow.opacity(0.08))

                        // Red zone: 0-39
                        RectangleMark(
                            xStart: nil, xEnd: nil,
                            yStart: .value("", 0),
                            yEnd: .value("", 40)
                        )
                        .foregroundStyle(AppColors.red.opacity(0.08))
                    }

                    ForEach(filteredEntries) { entry in
                        switch selectedMetric {
                        case .healthScore:
                            LineMark(
                                x: .value("Time", entry.timestamp),
                                y: .value("Health", entry.healthScore)
                            )
                            .foregroundStyle(AppColors.accent)

                            PointMark(
                                x: .value("Time", entry.timestamp),
                                y: .value("Health", entry.healthScore)
                            )
                            .foregroundStyle(healthColor(entry.healthScore))

                        case .latency:
                            LineMark(
                                x: .value("Time", entry.timestamp),
                                y: .value("Latency", entry.latency)
                            )
                            .foregroundStyle(latencyColor(entry.latency))

                            PointMark(
                                x: .value("Time", entry.timestamp),
                                y: .value("Latency", entry.latency)
                            )
                            .foregroundStyle(latencyColor(entry.latency))

                        case .speed:
                            if let speed = entry.downloadSpeed {
                                BarMark(
                                    x: .value("Time", entry.timestamp),
                                    y: .value("Speed", speed)
                                )
                                .foregroundStyle(speedColor(speed))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .modifier(HealthScoreYScaleModifier(isHealthScore: selectedMetric == .healthScore))

                // Zone legend for health score
                if selectedMetric == .healthScore {
                    healthScoreZoneLegend
                }
            }
        }
    }

    private var healthScoreZoneLegend: some View {
        HStack(spacing: UIConstants.spacingM) {
            ForEach([("Good 70+", AppColors.green),
                     ("Fair 40-69", AppColors.yellow),
                     ("Poor 0-39", AppColors.red)], id: \.0) { label, color in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label).font(.caption2).foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private func healthZoneLabel(_ score: Int) -> String {
        switch score {
        case 70...: return "Good"
        case 40..<70: return "Fair"
        default: return "Poor"
        }
    }

    private var chartTitle: String {
        switch selectedMetric {
        case .healthScore: return "Health Score Over Time"
        case .latency: return "Latency Over Time (ms)"
        case .speed: return "Download Speed Over Time (Mbps)"
        }
    }

    // MARK: - Legacy Chart Card (iOS 15)

    private var legacyChartCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text(chartTitle)
                    .font(.headline)

                Text("Charts require iOS 16+")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)

                if !filteredEntries.isEmpty {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Avg Health")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text("\(Int(filteredEntries.map { Double($0.healthScore) }.reduce(0, +) / Double(filteredEntries.count)))")
                                .font(.title3.bold())
                        }

                        Spacer()

                        VStack(alignment: .leading) {
                            Text("Tests")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text("\(filteredEntries.count)")
                                .font(.title3.bold())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Baseline Comparison Card

    private func baselineComparisonCard(latest: NetworkHistoryEntry, baseline: NetworkHistoryEntry) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(AppColors.accent)
                    Text("Today vs Your Best")
                        .font(.headline)
                }

                // Speed comparison
                if let latestSpeed = latest.downloadSpeed, let baselineSpeed = baseline.downloadSpeed {
                    comparisonRow(
                        label: "Speed",
                        current: "\(String(format: "%.1f", latestSpeed)) Mbps",
                        baseline: baselineSpeed,
                        currentValue: latestSpeed,
                        isHigherBetter: true
                    )
                }

                // Latency comparison
                comparisonRow(
                    label: "Latency",
                    current: "\(Int(latest.latency))ms",
                    baseline: baseline.latency,
                    currentValue: latest.latency,
                    isHigherBetter: false
                )

                // Gateway comparison
                comparisonRow(
                    label: "Gateway",
                    current: "\(Int(latest.gatewayLatency))ms",
                    baseline: baseline.gatewayLatency,
                    currentValue: latest.gatewayLatency,
                    isHigherBetter: false
                )

                Divider()

                // Analysis
                Text(analyzeComparison(latest: latest, baseline: baseline))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private func comparisonRow(label: String, current: String, baseline: Double, currentValue: Double, isHigherBetter: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 70, alignment: .leading)

            Text(current)
                .font(.subheadline.bold())

            Spacer()

            // Comparison indicator
            let ratio = currentValue / baseline
            let percentChange = abs((ratio - 1.0) * 100)

            if percentChange < 10 {
                Text("→ same as best")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            } else if (isHigherBetter && ratio > 1) || (!isHigherBetter && ratio < 1) {
                Text("↑ \(Int(percentChange))% better")
                    .font(.caption)
                    .foregroundColor(AppColors.green)
            } else {
                let arrowLabel = isHigherBetter ? "↓" : "↑"
                let multiplier = isHigherBetter ? ratio : 1/ratio
                if multiplier < 0.5 {
                    Text("\(arrowLabel) \(String(format: "%.1f", 1/multiplier))x from best")
                        .font(.caption)
                        .foregroundColor(AppColors.red)
                } else {
                    Text("\(arrowLabel) \(Int(percentChange))% from best")
                        .font(.caption)
                        .foregroundColor(AppColors.yellow)
                }
            }
        }
    }

    private func analyzeComparison(latest: NetworkHistoryEntry, baseline: NetworkHistoryEntry) -> String {
        let gatewayDiff = abs(latest.gatewayLatency - baseline.gatewayLatency)
        let latencyRatio = latest.latency / max(baseline.latency, 1)

        if gatewayDiff < 10 && latencyRatio > 1.5 {
            if latest.vpnActive {
                return "→ Your local network is fine. Slowdown is from VPN routing."
            } else {
                return "→ Your local network is fine. Slowdown is from ISP/internet."
            }
        } else if gatewayDiff > 20 {
            return "→ Your local WiFi/router is slower than usual. Try restarting router."
        } else {
            return "→ Performance is close to your baseline."
        }
    }

    // MARK: - Enhanced Insights Card

    private var insightsCard: some View {
        let insights = HistoryInsightsEngine.analyze(entries: filteredEntries)

        return CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(AppColors.yellow)
                    Text("Insights")
                        .font(.headline)
                    Spacer()
                    Text("\(insights.entryCount) measurements")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Divider()

                // Trend row
                trendRow(insights.trend)

                // Best/worst time rows
                if let best = insights.bestHourRange {
                    insightRow(icon: "sun.max.fill", color: AppColors.green,
                              title: "Best time", value: best)
                }
                if let worst = insights.worstHourRange {
                    insightRow(icon: "moon.fill", color: AppColors.yellow,
                              title: "Slowest time", value: worst)
                }

                // VPN impact
                if let vpn = insights.vpnImpact {
                    Divider()
                    vpnImpactRow(vpn)
                }

                // Top issue with fix
                if let issue = insights.topIssue, issue.frequency > 1 {
                    Divider()
                    topIssueRow(issue)
                }
            }
        }
    }

    private func trendRow(_ trend: HistoryInsightsEngine.Trend) -> some View {
        HStack {
            Image(systemName: trend.systemImage)
                .foregroundColor(trendColor(trend))
            Text(trendLabel(trend))
                .font(.subheadline.bold())
                .foregroundColor(trendColor(trend))
            Spacer()
            Text(trendDetail(trend))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private func trendColor(_ trend: HistoryInsightsEngine.Trend) -> Color {
        switch trend {
        case .improving: return AppColors.green
        case .degrading: return AppColors.red
        case .stable: return AppColors.textSecondary
        case .insufficient: return AppColors.textSecondary
        }
    }

    private func trendLabel(_ trend: HistoryInsightsEngine.Trend) -> String {
        switch trend {
        case .improving: return "Improving"
        case .degrading: return "Degrading"
        case .stable: return "Stable"
        case .insufficient: return "Need more data"
        }
    }

    private func trendDetail(_ trend: HistoryInsightsEngine.Trend) -> String {
        switch trend {
        case .improving(let delta): return "+\(delta) pts avg"
        case .degrading(let delta): return "-\(delta) pts avg"
        case .stable: return "No significant change"
        case .insufficient: return "Run more diagnostics"
        }
    }

    private func insightRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 20)
            Text(title).font(.subheadline).foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value).font(.subheadline.bold())
        }
    }

    private func vpnImpactRow(_ vpn: HistoryInsightsEngine.VPNImpact) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.spacingS) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(AppColors.accent)
                Text("VPN Impact")
                    .font(.subheadline.bold())
            }

            HStack {
                metricPill(label: "No VPN", value: "\(Int(vpn.withoutVPNAvgScore))",
                          color: AppColors.green)
                Image(systemName: "arrow.right").foregroundColor(AppColors.textSecondary)
                metricPill(label: "With VPN", value: "\(Int(vpn.withVPNAvgScore))",
                          color: vpn.isVPNHurtingPerformance ? AppColors.yellow : AppColors.green)
            }

            if vpn.isVPNHurtingPerformance {
                Text("VPN reduces your avg health score by ~\(Int(abs(vpn.scoreDelta))) points. Try a closer server.")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private func metricPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.bold()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, UIConstants.spacingM)
        .padding(.vertical, UIConstants.spacingS)
        .background(AppColors.card)
        .cornerRadius(UIConstants.cornerRadiusS)
    }

    private func topIssueRow(_ issue: HistoryInsightsEngine.TopIssue) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.spacingS) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.yellow)
                Text("Most Common: \(issue.cause)")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(issue.percentage.rounded()))%")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            Text(issue.suggestion)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Recent Tests Card with Swipe Actions

    private var recentTestsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                Text("Recent Tests")
                    .font(.headline)

                ForEach(filteredEntries.prefix(10)) { entry in
                    entryRow(entry)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(action: { historyManager.toggleBookmark(for: entry.id) }) {
                                Label(entry.isBookmarked ? "Remove Bookmark" : "Bookmark",
                                      systemImage: entry.isBookmarked ? "bookmark.slash" : "bookmark")
                            }
                            Button(role: .destructive, action: { historyManager.deleteEntry(id: entry.id) }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                    if entry.id != filteredEntries.prefix(10).last?.id {
                        Divider()
                    }
                }

                // Swipe hint
                if filteredEntries.count > 0 {
                    Text("Long press for options")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func entryRow(_ entry: NetworkHistoryEntry) -> some View {
        HStack {
            // Bookmark indicator + health dot
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(healthColor(entry.healthScore))
                    .frame(width: 12, height: 12)
                if entry.isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.accent)
                        .offset(x: 8, y: -8)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.rootCause)
                        .font(.subheadline)
                    if let ssid = entry.wifiSSID, !ssid.isEmpty {
                        Text("(\(ssid))")
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Text(formatDate(entry.timestamp))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.healthScore)")
                    .font(.subheadline.bold())
                    .foregroundColor(healthColor(entry.healthScore))
                if let speed = entry.downloadSpeed {
                    Text("\(String(format: "%.1f", speed)) Mbps")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                } else if entry.vpnActive, let loc = entry.vpnServerLocation {
                    Text("VPN: \(loc)")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        CardView {
            VStack(spacing: UIConstants.spacingM) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.textSecondary)

                Text("No History Yet")
                    .font(.headline)

                Text("Run diagnostics and speed tests to build your network history.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    // MARK: - Export

    private func prepareAndShowExport() {
        Task {
            exportCSVContent = await historyManager.exportCSV()
            showingExportSheet = true
        }
    }

    // MARK: - Helpers

    private func healthColor(_ score: Int) -> Color {
        NetworkColors.forHealthScore(score)
    }

    private func latencyColor(_ latency: Double) -> Color {
        NetworkColors.forLatency(latency)
    }

    private func speedColor(_ speed: Double) -> Color {
        NetworkColors.forSpeed(speed)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Health Score Y Scale Modifier

@available(iOS 16, *)
struct HealthScoreYScaleModifier: ViewModifier {
    let isHealthScore: Bool

    func body(content: Content) -> some View {
        if isHealthScore {
            content.chartYScale(domain: 0...100)
        } else {
            content
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct NetworkHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NetworkHistoryView()
    }
}
