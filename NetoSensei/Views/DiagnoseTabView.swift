import SwiftUI

struct DiagnoseTabView: View {
    @StateObject private var diagnosis = FullDiagnosticViewModel()
    @ObservedObject private var monitor = NetworkMonitorService.shared
    @State private var host = "www.apple.com"
    @State private var showingWiFiAssistant = false
    @FocusState private var editingHost: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    connectionSnapshot
                    runCard

                    Button { showingWiFiAssistant = true } label: {
                        Label("Wi-Fi Assistant", systemImage: "wifi")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(diagnosis.isRunning)

                    ForEach(FullDiagnosticViewModel.Check.allCases) { check in
                        checkCard(check)
                    }


                }
                .padding()
            }
            .navigationTitle("Diagnose")
            .toolbar {
                if !diagnosis.isRunning, let report = diagnosis.report(status: monitor.currentStatus) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: report) { Label("Share diagnostic report", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .sheet(isPresented: $showingWiFiAssistant) { WiFiAssistantView() }
        }
    }

    private var connectionSnapshot: some View {
        let status = monitor.currentStatus
        return CardView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Current connection", systemImage: "network").font(.headline)
                reading("Interface", status.connectionType?.displayName ??
                        (monitor.isInitializing ? "Reading connection…" : "Unavailable"))
                if let name = status.wifi.ssid { reading("Wi-Fi", name) }
                if let ip = status.localIP { reading("Device address", ip) }
                if let gateway = status.router.gatewayIP { reading("Gateway address", gateway) }
                if status.measurementsPending {
                    if let latency = status.router.latency { reading("Gateway response", ms(latency)) }
                    if let latency = status.dns.displayableLatency { reading("DNS lookup", ms(latency)) }
                    if let latency = status.internet.displayableLatency { reading("Internet delay", ms(latency)) }
                    Text("Live readings are still being checked.").font(.footnote).foregroundStyle(.secondary)
                } else if !monitor.isInitializing {
                    reading("Gateway response", ms(status.router.latency))
                    reading("DNS lookup", ms(status.dns.displayableLatency))
                    reading("Internet delay", ms(status.internet.displayableLatency))
                    if status.measurementsIncomplete { note("Some live readings did not finish.") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("diagnose.connectionSnapshot")
    }

    private var runCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Full connection check").font(.title2.bold())
                Text("Run connection, DNS, endpoint, certificate, VPN and performance checks together.")
                    .foregroundStyle(.secondary)
                DisclosureGroup("Choose a website") {
                    TextField("Website hostname", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .focused($editingHost)
                        .accessibilityIdentifier("diagnose.hostname")
                        .padding(.vertical, 6)
                }
                .disabled(diagnosis.isRunning)
                if diagnosis.isRunning {
                    ProgressView(value: Double(diagnosis.results.count), total: Double(FullDiagnosticViewModel.Check.allCases.count))
                    Text("\(diagnosis.results.count) of \(FullDiagnosticViewModel.Check.allCases.count) checks finished")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Stop checks", role: .cancel) { diagnosis.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button(diagnosis.results.isEmpty ? "Run full check" : "Run full check again") {
                        editingHost = false
                        diagnosis.run(host: host)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("diagnose.run")
                    .disabled(monitor.isInitializing)
                    Text("Speed checks transfer data on the active connection, including cellular when it’s active.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message = diagnosis.message {
                    Text(message).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkCard(_ check: FullDiagnosticViewModel.Check) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Text(check.rawValue).font(.headline)
                if diagnosis.path == ExitPath.lastPathChange, let result = diagnosis.results[check] {
                    checkDetails(result)
                } else if diagnosis.running.contains(check) {
                    ProgressView("Checking…").font(.subheadline)
                } else if diagnosis.isRunning {
                    note("Waiting for earlier checks.")
                } else if diagnosis.path != nil && diagnosis.path != ExitPath.lastPathChange {
                    note("Run on the current connection to see these readings.")
                } else if diagnosis.path != nil {
                    note("No reading collected.")
                } else {
                    note("Ready to check")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func checkDetails(_ result: FullDiagnosticViewModel.Result) -> some View {
        switch result {
        case .connection(let result, let verdict):
            if let verdict {
                Text(verdict.headline).font(.subheadline.bold())
                note(verdict.coverage.line)
            }
            ForEach(Array(result.testsPerformed.enumerated()), id: \.offset) { _, check in
                reading(check.name, check.latency.map { ms($0) } ?? testStatus(check.result))
                note(check.details)
            }
        case .endpoints(let result):
            ForEach(result.hops) { hop in
                reading(hop.ipAddress, ms(hop.latency))
                if let method = hop.hostname { note(method) }
            }
            if result.hops.isEmpty { note("No endpoint responses were measured.") }
        case .dns(let analysis, let benchmark):
            reading("System resolver", analysis.systemDNS.first?.ipAddress ?? "Address unavailable")
            ForEach(benchmark.results) { resolver in
                reading(resolver.name, ms(resolver.latencyMs))
                note("\(resolver.individualLatencies.count) of 3 replies")
            }
            note(benchmark.recommendation.detail)
        case .security(let result):
            Text(result.verdict.displayText).font(.subheadline.bold())
            if let leak = result.vpnLeak { reading("VPN leak checks", leak.overallVerdict.displayText) }
            if let portal = result.captivePortal {
                Text(portal.recommendation).font(.subheadline)
            }
            if let encryption = result.dnsEncryption {
                reading("DNS over HTTPS probe", encryption.dohReachable ? "Valid reply" : "No valid reply")
                reading("DNS over TLS probe", encryption.dotReachable ? "Valid reply" : "No valid reply")
                note(encryption.recommendation)
            }
            ForEach(result.certificateInspections) { inspection in
                Text(inspection.hostname).font(.subheadline.bold())
                note(inspection.summary)
                if inspection.realIssuer != "—" { reading("Issuer", inspection.realIssuer) }
                if let version = inspection.protocolVersion { reading("TLS version", version) }
                if let latency = inspection.handshakeMs { reading("TLS handshake", ms(latency)) }
            }
            ForEach(result.recommendations, id: \.self) { note($0) }
        case .speed(let result):
            if let server = result.serverUsed { note(server) }
            reading("Download", String(format: "%.1f Mbps", result.downloadSpeed))
            reading("Upload", result.measuredUploadSpeed.map { String(format: "%.1f Mbps", $0) } ?? "Unavailable")
            if let response = result.responsiveness {
                reading("Idle HTTPS response", ms(response.idleMs))
                reading("During download", ms(response.downloadMs))
                reading("During upload", ms(response.uploadMs))
            }
        case .endpointSpeeds(let result):
            ForEach(result.results) { sample in
                reading(sample.endpoint, sample.displaySpeed)
                if let detail = sample.note { note(detail) }
            }
            note(result.explanation)
        case .comparison(let result):
            comparisonRow(result.wifiResult)
            comparisonRow(result.cellularResult)
            note(result.recommendation.description)
        case .unavailable(let explanation):
            note(explanation)
        }
    }

    private func testStatus(_ result: DiagnosticTest.TestResult) -> String {
        switch result {
        case .pass: return "Confirmed"
        case .warning: return "Needs attention"
        case .fail: return "No response"
        case .notApplicable: return "Not applicable"
        case .skipped: return "Skipped"
        }
    }

    private func comparisonRow(_ result: ConnectionTestResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            reading(result.connectionType.rawValue,
                    result.downloadSpeedMbps.map { String(format: "%.1f Mbps", $0) } ?? "Not measured")
            if let error = result.error { note(error) }
            else {
                Text(result.timestamp, style: .time).font(.footnote).foregroundStyle(.secondary)
                if let server = result.serverUsed { note(server) }
            }
        }
        .accessibilityIdentifier("diagnose.comparison.\(result.connectionType.rawValue)")
    }

    private func reading(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospacedDigit().multilineTextAlignment(.trailing) }
            .font(.subheadline)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }

    private func ms(_ value: Double?) -> String {
        value.map { String(format: "%.0f ms", $0) } ?? "Unavailable"
    }
}
