import SwiftUI

struct TracerouteView: View {
    @ObservedObject private var service = TracerouteService.shared
    @State private var destination = "www.apple.com"
    @FocusState private var editingHostname: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Endpoint Checks", systemImage: "point.3.connected.trianglepath.dotted").font(.title2.bold())
                        Text("Compare independent responses from your gateway and websites. These are not consecutive network hops, and cannot locate an ISP or router bottleneck.")
                        TextField("Hostname", text: $destination)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Endpoint hostname")
                            .focused($editingHostname)
                            .submitLabel(.done)
                            .onSubmit { editingHostname = false }
                        Button("Check endpoints") {
                            editingHostname = false
                            Task { _ = await service.runTraceroute(to: destination.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }.buttonStyle(.borderedProminent).disabled(service.isRunning)
                        if service.isRunning { ProgressView("Waiting for responses…") }
                        if let error = service.error { Text(error).foregroundStyle(.orange) }
                    }
                }
                if let result = service.result {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Measured responses").font(.headline)
                            ForEach(result.hops) { endpoint in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(endpoint.ipAddress).font(.headline)
                                    Text(endpoint.hostname ?? "Endpoint").font(.caption).foregroundStyle(.secondary)
                                    Text(endpoint.latency.map { String(format: "%.1f ms", $0) } ?? "No response measured")
                                }
                                Divider()
                            }
                            Text("If one site feels slow, enter that hostname and repeat on the same Wi-Fi. If you use a VPN, compare the same site after switching servers. A gateway TCP sample and a website HTTPS response measure different things.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("Endpoint Checks")
    }
}
