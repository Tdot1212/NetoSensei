//
//  WiFiComparisonCard.swift
//  NetoSensei
//
//  WiFi network quality tracking and comparison
//  Note: iOS does not allow scanning for nearby WiFi networks.
//  Instead, we track quality metrics of networks the user connects to.
//

import SwiftUI

// MARK: - WiFi Network Record

struct WiFiNetworkRecord: Identifiable, Codable {
    let id: UUID
    let ssid: String
    let bssid: String?
    let gatewayIP: String?
    let gatewayLatencyMs: Double?
    let dnsLatencyMs: Double?
    let internetLatencyMs: Double?
    let timestamp: Date
    let overallScore: Int // 0-100

    init(ssid: String, bssid: String?, gatewayIP: String?,
         gatewayLatencyMs: Double?, dnsLatencyMs: Double?,
         internetLatencyMs: Double?, timestamp: Date = Date()) {
        self.id = UUID()
        self.ssid = ssid
        self.bssid = bssid
        self.gatewayIP = gatewayIP
        self.gatewayLatencyMs = gatewayLatencyMs
        self.dnsLatencyMs = dnsLatencyMs
        self.internetLatencyMs = internetLatencyMs
        self.timestamp = timestamp

        // Calculate score
        var score = 100
        if let gw = gatewayLatencyMs {
            if gw > 50 { score -= 30 }
            else if gw > 20 { score -= 15 }
            else if gw > 10 { score -= 5 }
        }
        if let dns = dnsLatencyMs {
            if dns > 200 { score -= 25 }
            else if dns > 100 { score -= 15 }
            else if dns > 50 { score -= 5 }
        }
        if let internet = internetLatencyMs {
            if internet > 300 { score -= 25 }
            else if internet > 150 { score -= 15 }
            else if internet > 80 { score -= 5 }
        }
        self.overallScore = max(0, score)
    }
}

// MARK: - WiFi History Store

@MainActor
class WiFiHistoryStore: ObservableObject {
    static let shared = WiFiHistoryStore()

    @Published var records: [WiFiNetworkRecord] = []
    @Published var isScanning = false

    private let storageKey = "wifi_network_records"
    private let maxRecords = 100

    private init() {
        loadRecords()
    }

    func scanCurrentNetwork() async {
        isScanning = true
        defer { isScanning = false }

        let status = NetworkMonitorService.shared.currentStatus

        guard status.wifi.isConnected, let ssid = status.wifi.ssid else { return }

        let record = WiFiNetworkRecord(
            ssid: ssid,
            bssid: status.wifi.bssid,
            gatewayIP: status.router.gatewayIP,
            gatewayLatencyMs: status.router.latency,
            dnsLatencyMs: status.dns.latency,
            internetLatencyMs: status.internet.latencyToExternal
        )

        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        saveRecords()
    }

    /// Group records by SSID and return best score per network
    var networkSummaries: [NetworkSummary] {
        let grouped = Dictionary(grouping: records, by: { $0.ssid })
        return grouped.map { ssid, recs in
            let sorted = recs.sorted { $0.timestamp > $1.timestamp }
            let avgScore = recs.map(\.overallScore).reduce(0, +) / max(recs.count, 1)
            let bestScore = recs.map(\.overallScore).max() ?? 0
            let avgLatency = recs.compactMap(\.internetLatencyMs).reduce(0, +) /
                max(Double(recs.compactMap(\.internetLatencyMs).count), 1)
            return NetworkSummary(
                ssid: ssid,
                scanCount: recs.count,
                averageScore: avgScore,
                bestScore: bestScore,
                averageLatencyMs: avgLatency,
                lastSeen: sorted.first?.timestamp ?? Date(),
                isCurrentNetwork: ssid == NetworkMonitorService.shared.currentStatus.wifi.ssid
            )
        }
        .sorted { a, b in
            if a.isCurrentNetwork { return true }
            if b.isCurrentNetwork { return false }
            return a.averageScore > b.averageScore
        }
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WiFiNetworkRecord].self, from: data) else { return }
        records = decoded
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func clearHistory() {
        records = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    struct NetworkSummary: Identifiable {
        let id = UUID()
        let ssid: String
        let scanCount: Int
        let averageScore: Int
        let bestScore: Int
        let averageLatencyMs: Double
        let lastSeen: Date
        let isCurrentNetwork: Bool
    }
}

// MARK: - WiFi Comparison Card

struct WiFiComparisonCard: View {
    @StateObject private var store = WiFiHistoryStore.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Compare WiFi Networks")
                    .font(.headline)

                Spacer()

                Button(action: {
                    Task { await store.scanCurrentNetwork() }
                }) {
                    if store.isScanning {
                        ProgressView()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .disabled(store.isScanning)
            }
            .padding(.leading, 4)

            if store.networkSummaries.isEmpty {
                CardView {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No WiFi data yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Connect to WiFi networks and tap the refresh button to record quality metrics. Compare networks over time.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(store.networkSummaries.prefix(isExpanded ? 10 : 3)) { summary in
                        networkRow(summary)
                    }

                    if store.networkSummaries.count > 3 {
                        Button(action: { withAnimation { isExpanded.toggle() } }) {
                            Text(isExpanded ? "Show less" : "Show all \(store.networkSummaries.count) networks")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                // iOS limitation note
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("iOS cannot scan for nearby networks. This shows quality data for networks you've connected to.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func networkRow(_ summary: WiFiHistoryStore.NetworkSummary) -> some View {
        HStack(spacing: 12) {
            // Score indicator
            ZStack {
                Circle()
                    .stroke(scoreColor(summary.averageScore).opacity(0.3), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: CGFloat(summary.averageScore) / 100)
                    .stroke(scoreColor(summary.averageScore), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                Text("\(summary.averageScore)")
                    .font(.caption2.bold())
                    .foregroundColor(scoreColor(summary.averageScore))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(summary.ssid)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if summary.isCurrentNetwork {
                        Text("CONNECTED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(3)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(summary.scanCount) scan\(summary.scanCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if summary.averageLatencyMs > 0 {
                        Text("~\(Int(summary.averageLatencyMs))ms")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(timeAgo(summary.lastSeen))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Quality label
            Text(qualityLabel(summary.averageScore))
                .font(.caption2.bold())
                .foregroundColor(scoreColor(summary.averageScore))
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        if score >= 40 { return .orange }
        return .red
    }

    private func qualityLabel(_ score: Int) -> String {
        if score >= 80 { return "Excellent" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Fair" }
        return "Poor"
    }

    private func timeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        return "\(Int(elapsed / 86400))d ago"
    }
}
