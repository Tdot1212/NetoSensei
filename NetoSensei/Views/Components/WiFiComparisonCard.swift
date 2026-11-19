import SwiftUI

/// Shows the shared diagnostic history. No second store or synthetic Wi-Fi score.
struct WiFiComparisonCard: View {
    @ObservedObject private var history = NetworkHistoryManager.shared
    @State private var expanded = false
    private var observations: [NetworkHistoryEntry] {
        history.entries.filter { $0.wifiSSID != nil }.sorted { $0.timestamp > $1.timestamp }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Wi-Fi observations", systemImage: "clock.arrow.circlepath").font(.headline)
            CardView {
                VStack(alignment: .leading, spacing: 12) {
                    if observations.isEmpty {
                        Text("No Wi-Fi diagnostic history yet.")
                        Text("Run Quick Check or a speed test on a named Wi-Fi network to save an observation.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(observations.prefix(expanded ? 10 : 3)) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.wifiSSID ?? "Unidentified network").font(.subheadline.bold())
                                Text(entry.timestamp, style: .date).font(.caption).foregroundStyle(.secondary)
                                Text(entry.vpnActive ? "VPN detected during this observation" : "VPN not detected during this observation").font(.caption)
                                Text(entry.latency.map { String(format: "Observed external response: %.1f ms", $0) } ?? "External response time unavailable")
                                    .font(.caption)
                            }
                            Divider()
                        }
                        if observations.count > 3 {
                            Button(expanded ? "Show less" : "Show recent observations") { expanded.toggle() }
                        }
                    }
                    Text("iOS does not provide nearby Wi-Fi scanning. These are dated observations, not current rankings of nearby networks. Different routes, VPN states and test servers are not directly comparable.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
