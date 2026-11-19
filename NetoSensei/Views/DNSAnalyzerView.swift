import SwiftUI

struct DNSAnalyzerView: View {
    @StateObject private var analyzer = DNSAnalyzer.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DNS Information").font(.title2.bold())
                        Text("Review resolver information available to the app. DNS encryption and VPN query routing cannot be established from an open port, provider name, or gateway address.")
                        Button("Read DNS information") { Task { _ = await analyzer.runFullAnalysis() } }
                            .buttonStyle(.borderedProminent).disabled(analyzer.isAnalyzing)
                        if analyzer.isAnalyzing { ProgressView() }
                    }
                }
                if let result = analyzer.result {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Observed resolver information").font(.headline)
                            if result.systemDNS.isEmpty { Text("System resolver addresses are unavailable to this app.") }
                            ForEach(result.systemDNS) { server in
                                Text(server.ipAddress).font(.headline)
                                Text(server.provider.rawValue).foregroundStyle(.secondary)
                            }
                            Label("Encryption: unverified", systemImage: "questionmark.shield")
                            Label("VPN DNS routing: unverified", systemImage: "questionmark.shield")
                            Text("DNS Benchmark sends actual queries to selected test resolvers. A system lookup can include cached answers; neither measurement proves which DNS transport other apps use.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding()
        }.navigationTitle("DNS Information").navigationBarTitleDisplayMode(.inline)
    }
}
