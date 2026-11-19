import SwiftUI

/// One entry point for the shared tools, rather than a second measurement engine.
struct NewAdvancedDiagnosticView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Tool?
    private enum Tool: String, Identifiable {
        case performance, security, dns, endpoints
        var id: String { rawValue }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Detailed Checks").font(.title2.bold())
                            Text("Use the same measurement tools as the main tabs. Each result explains what was measured and what remains unknown.")
                            Text("Speed tests transfer data. Security checks cannot certify that a network is safe or that every VPN route is protected.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    tool("Performance and before/after", detail: "Repeated real throughput measurements and local discovery", symbol: "speedometer", value: .performance)
                    tool("Security evidence", detail: "TLS, portal and privacy checks with incomplete states", symbol: "shield", value: .security)
                    tool("DNS benchmark", detail: "Compare responses from reachable test resolvers", symbol: "server.rack", value: .dns)
                    tool("Endpoint checks", detail: "Independent gateway and HTTPS responses; no invented hops", symbol: "network", value: .endpoints)
                }.padding()
            }
            .navigationTitle("Detailed Checks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $selection) { tool in
                switch tool {
                case .performance: WiFiAssistantView()
                case .security: CombinedSecurityCheckSheet()
                case .dns: DNSBenchmarkView()
                case .endpoints: NavigationStack {
                    TracerouteView().toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Done") { selection = nil } }
                    }
                }
                }
            }
        }
    }
    private func tool(_ title: String, detail: String, symbol: String, value: Tool) -> some View {
        Button { selection = value } label: {
            CardView {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: symbol).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("detailed.\(value.rawValue)")
    }
}
