import SwiftUI

struct DiagnoseTabView: View {
    @StateObject private var diagnosis = FullDiagnosticViewModel()
    @ObservedObject private var monitor = NetworkMonitorService.shared
    @State private var host = "www.apple.com"
    @State private var showingWiFiAssistant = false
    @State private var showingInvestigation = false
    @FocusState private var editingHost: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    runCard
                    firstFinding
                    connectionSnapshot

                    Button { showingWiFiAssistant = true } label: {
                        CardView {
                            BriefActionLabel(title: "Wi-Fi Assistant", icon: "wifi")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(diagnosis.isRunning)

                    BriefSectionTitle(title: "Check results")
                    ForEach(FullDiagnosticViewModel.Check.allCases) { check in
                        checkCard(check)
                    }
                }
                .connectionBriefColumn()
            }
            .background(ConnectionBriefStyle.canvas)
            .navigationTitle("Diagnose")
            .toolbar {
                if !diagnosis.isRunning, let report = diagnosis.report(status: monitor.currentStatus) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: report) { Label("Share diagnostic report", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .sheet(isPresented: $showingWiFiAssistant) { WiFiAssistantView() }
            .sheet(isPresented: $showingInvestigation) { ConnectionInvestigationView(topic: .connection, host: host) }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder private var firstFinding: some View {
        if diagnosis.path == ExitPath.lastPathChange,
           case let .connection(_, verdict?) = diagnosis.results[.connection],
           !verdict.findings.isEmpty {
            FindingsCard(verdict: verdict, title: "What to try first", expandsFirstFinding: true)
                .id(verdict.generatedAt)
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
                Label("Full connection check", systemImage: "waveform.path")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Check DNS, site responses, security and performance on your current connection.")
                    .font(.subheadline)
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
                    checkProgress
                    Text("\(diagnosis.results.count) of \(FullDiagnosticViewModel.Check.allCases.count) checks finished")
                        .font(.subheadline.weight(.medium))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: diagnosis.results.count)
                    if diagnosis.running.contains(.speed) {
                        DiagnosticSpeedProgress()
                    } else if diagnosis.running.contains(.endpointSpeeds) {
                        note("Measuring download speed against individual endpoints…")
                    } else if diagnosis.running.contains(.comparison) {
                        note("Checking which connections can be compared…")
                    }
                    Button("Stop checks", role: .cancel) { diagnosis.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button(diagnosis.results.isEmpty ? "Run full check" : "Run full check again") {
                        editingHost = false
                        diagnosis.run(host: host)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("diagnose.run")
                    .disabled(monitor.isInitializing)
                    Text("Speed checks transfer data on the active connection, including cellular when it’s active.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Investigate a specific problem", systemImage: "arrow.triangle.branch") {
                        editingHost = false
                        showingInvestigation = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("investigation.openDiagnose")
                }
                if let message = diagnosis.message {
                    Text(message).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var checkProgress: some View {
        HStack(spacing: 5) {
            ForEach(FullDiagnosticViewModel.Check.allCases) { check in
                Capsule()
                    .fill(diagnosis.results[check] != nil ? AppColors.accent :
                            diagnosis.running.contains(check) ? AppColors.accent.opacity(0.48) : ConnectionBriefStyle.rule)
                    .frame(height: 5)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: diagnosis.results.count)
        .accessibilityHidden(true)
    }

    private func checkCard(_ check: FullDiagnosticViewModel.Check) -> some View {
        let isCurrent = diagnosis.path == ExitPath.lastPathChange
        let result = isCurrent ? diagnosis.results[check] : nil
        let isChecking = isCurrent && diagnosis.running.contains(check)
        return CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: checkIcon(result: result, isChecking: isChecking))
                        .foregroundStyle(result != nil || isChecking ? AppColors.accent : .secondary)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(check.rawValue)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                if let result {
                    checkDetails(result)
                    if check == .speed, case .unavailable(let reason) = result {
                        ConnectionNextStepView(step: .speedFailed(reason, connectionType: monitor.currentStatus.connectionType?.displayName))
                    }
                } else if isChecking {
                    ProgressView("Checking…").font(.subheadline)
                } else if diagnosis.isRunning {
                    note("Waiting for earlier checks.")
                } else if diagnosis.path != nil && !isCurrent {
                    note("Run on the current connection to see these readings.")
                } else if diagnosis.path != nil {
                    note("No reading collected.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkIcon(result: FullDiagnosticViewModel.Result?, isChecking: Bool) -> String {
        switch result {
        case .unavailable: return "minus.circle"
        case .some: return "doc.text"
        case .none: return isChecking ? "waveform" : "circle.dotted"
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
            ConnectionNextStepView(step: .speed(result))
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


private struct DiagnosticSpeedProgress: View {
    @ObservedObject private var speed = SpeedTestEngine.shared

    var body: some View {
        Text(phaseDescription)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var phaseDescription: String {
        switch speed.currentPhase {
        case .idle, .findingServer: return "Finding a speed test server…"
        case .testingPing: return "Measuring latency and idle responsiveness…"
        case .testingDownload: return "Measuring download speed…"
        case .testingUpload: return "Measuring upload speed…"
        case .complete: return "Saving speed readings…"
        }
    }
}
