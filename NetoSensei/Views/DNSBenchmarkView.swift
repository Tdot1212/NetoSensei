import SwiftUI

struct DNSBenchmarkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result: QuickDNSBenchmarkResult?
    @State private var running = false
    @State private var progress = 0.0
    @State private var phase = ""
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Compare DNS query responses").font(.title2.bold())
                            Text("Sends three actual DNS queries to each listed resolver. System Default uses the operating system and can include cached answers; it is shown separately and is not ranked.")
                            Text("A VPN or network policy may redirect these queries. Results do not prove DNS encryption, filtering, privacy, or a faster internet connection.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button(result == nil ? "Start Benchmark" : "Run Again") { run() }
                                .buttonStyle(.borderedProminent).disabled(running)
                            if running { ProgressView(value: progress); Text(phase).font(.caption) }
                        }
                    }
                    if let result {
                        CardView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(result.summary).font(.headline)
                                Text(result.recommendation.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(result.results) { server in
                            CardView {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(server.name).font(.headline)
                                    Text(server.address == "system" ? "System lookup (cache and OS work included)" : "Queries sent to \(server.address)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(server.latencyMs.map { String(format: "Mean response: %.1f ms", $0) } ?? "No validated answer received")
                                    Text("\(server.individualLatencies.count)/3 queries returned validated answers")
                                        .font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }.padding()
            }
            .navigationTitle("DNS Benchmark").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .onDisappear { task?.cancel() }
        }
    }
    private func run() {
        guard !running else { return }
        running = true; progress = 0
        task = Task { @MainActor in
            let measured = await DNSBenchmarkService.shared.benchmark { value, text in
                Task { @MainActor in progress = value; phase = text }
            }
            if !Task.isCancelled { result = measured }
            running = false
        }
    }
}
