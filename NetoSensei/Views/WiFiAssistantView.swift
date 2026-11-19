import SwiftUI

struct WiFiAssistantView: View {
    @StateObject private var assistant = WiFiAssistant()
    @ObservedObject private var monitor = NetworkMonitorService.shared
    @ObservedObject private var discovery = NetworkDeviceDiscovery.shared
    @ObservedObject private var speedEngine = SpeedTestEngine.shared
    @Environment(\.dismiss) private var dismiss
    @State private var guide: WiFiRepairGuide
    @AppStorage("NetoSensei.rememberedDeviceNames") private var rememberedNamesJSON = "[]"

    init(guide: WiFiRepairGuide = .lag) {
        _guide = State(initialValue: guide)
    }

    private var rememberedNames: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(rememberedNamesJSON.utf8))) ?? []
    }
    @State private var editingDevice: WiFiDeviceInventory.Observation?
    @State private var labelDraft = ""
    @State private var showDeviceHelp = false
    @State private var showAISettings = false
    @State private var adviceTask: Task<Void, Never>?
    @State private var adviceError: String?
    @State private var adviceStep: Int?
    @State private var hasDeepSeekKey = AIKeyManager.shared.hasKey(for: .deepseek)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Understand your Wi-Fi", systemImage: "wifi")
                                .font(.title2.bold())
                            Text("Find a practical fix for lag, slow downloads, or an unfamiliar device. Then measure whether the change helped.")
                            if assistant.isRunning {
                                ProgressView()
                                Button("Cancel check", role: .cancel) { assistant.cancel() }
                            }
                            Text(assistant.statusText).font(.subheadline).foregroundStyle(.secondary)
                            if let error = assistant.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            }
                            Button("Check Wi-Fi and devices") { assistant.scan() }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy)
                            Text("Local network permission is required for discovery. A scan cannot find every connected device.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if guide.isPerformance { responsivenessCard }
                    repairCard
                    if let checkedAt = assistant.checkedAt, let status = assistant.scanStatus,
                       let inventory = assistant.inventory {
                        if scanIsCurrent(status) {
                            evidenceCard(checkedAt: checkedAt, status: status)
                            devicesCard(inventory)
                        } else {
                            Text("The network changed. Check again to view current devices.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if guide.isPerformance { comparisonCard }
                    capabilitiesCard
                    if !assistant.actionHistory.isEmpty {
                        CardView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("This session").font(.headline)
                                ForEach(Array(assistant.actionHistory.enumerated()), id: \.offset) { _, event in
                                    Label(event, systemImage: "checkmark.circle")
                                }
                                Text("No router settings were changed.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Wi-Fi Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { assistant.reset() }.disabled(assistant.isRunning)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(assistant.isRunning) }
            }
            .interactiveDismissDisabled(assistant.isRunning)
            .sheet(isPresented: $showAISettings, onDismiss: {
                hasDeepSeekKey = AIKeyManager.shared.hasKey(for: .deepseek)
            }) { AISettingsView() }
            .onChange(of: guide) { _, _ in clearAdvice() }
            .onChange(of: adviceEvidence) { _, _ in clearAdvice() }
            .onDisappear { clearAdvice() }
            .sheet(isPresented: $showDeviceHelp) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(WiFiRepairGuide.security.steps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)")
                            }
                        }.padding()
                    }
                    .navigationTitle("Identify a device")
                    .toolbar { Button("Done") { showDeviceHelp = false } }
                }
            }
            .alert("Name this device", isPresented: Binding(
                get: { editingDevice != nil },
                set: { if !$0 { editingDevice = nil } }
            ), presenting: editingDevice) { device in
                TextField("e.g. My MacBook", text: $labelDraft)
                Button("Save") {
                    if let status = assistant.scanStatus, scanIsCurrent(status) {
                        let name = WiFiDeviceInventory.clean(labelDraft)
                        assistant.deviceLabels[device.address] = name
                        if let name {
                            assistant.recognizedIPs.insert(device.address)
                            updateRememberedNames(([name] + rememberedNames.filter { $0 != name }).prefix(30).map { $0 })
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { device in
                Text("Confirm this address on the device or router before saving. You can reuse the name in future scans.")
            }
        }
    }

    private func updateRememberedNames(_ names: [String]) {
        if let data = try? JSONEncoder().encode(names) {
            rememberedNamesJSON = String(decoding: data, as: UTF8.self)
        }
    }

    private var busy: Bool { assistant.isRunning || discovery.isScanning || speedEngine.isRunning }

    private func scanIsCurrent(_ status: NetworkStatus) -> Bool {
        monitor.currentStatus.wifi.isConnected && status.wifi.ssid == monitor.currentStatus.wifi.ssid &&
        status.wifi.bssid == monitor.currentStatus.wifi.bssid && assistant.scanPath == ExitPath.lastPathChange
    }

    private func evidenceCard(checkedAt: Date, status: NetworkStatus) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current measurements").font(.headline)
                Text(checkedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                AssistantEvidenceRow(title: "Wi-Fi", value: status.wifi.ssid ?? "Name unavailable",
                    detail: "Network name access depends on iOS permissions.")
                AssistantEvidenceRow(title: "Gateway response", value: status.router.displayableLatency.map { String(format: "%.1f ms", $0) } ?? "Unmeasured",
                    detail: "TCP connection time. An unanswered probe does not prove the router is offline.")
                AssistantEvidenceRow(title: "DNS lookup", value: status.dns.displayableLatency.map { String(format: "%.1f ms", $0) } ?? "Unmeasured",
                    detail: "A lookup from this phone; cached results can be faster than an uncached query.")
                Text("Slow responses alone cannot establish interference, router load, old firmware, or which app uses bandwidth.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var repairCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose what to fix").font(.headline)
                Picker("What do you want to fix?", selection: $guide) {
                    ForEach(WiFiRepairGuide.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
                aiRecommendation
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).").font(.subheadline.bold()).accessibilityHidden(true)
                        Text(step).font(.subheadline)
                    }
                }
                if guide == .security || guide == .speed {
                    if monitor.currentStatus.wifi.isConnected,
                       let url = WiFiRepairGuide.routerURL(gateway: DefaultRouteResolver.lanGateway()?.gateway,
                                                           localSubnet: IPv4Subnet.activeWiFi()) {
                        Link(destination: url) { Label("Try router’s local HTTPS page", systemImage: "arrow.up.right.square") }
                    }
                    Text("If the page is unavailable or Safari warns about its certificate, use your router’s official app or the address in its manual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var adviceEvidence: WiFiAdviceEvidence? {
        let currentScan = assistant.scanStatus.flatMap { scanIsCurrent($0) ? $0 : nil }
        let lastChange = ExitPath.lastPathChange
        let comparison = assistant.after.last.map { $0.timestamp >= lastChange } == true ? assistant.comparison : nil
        let quick = currentResponsiveness
        guard currentScan != nil || comparison != nil || quick != nil else { return nil }
        return WiFiAdviceEvidence(status: currentScan, comparison: comparison,
                                  respondingAddressCount: currentScan == nil ? nil : assistant.inventory?.otherAddressCount, response: quick)
    }

    @ViewBuilder private var aiRecommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let adviceStep {
                Label("DeepSeek’s suggested next step", systemImage: "sparkles").font(.subheadline.bold())
                Text(guide.steps[adviceStep]).font(.subheadline)
            }
            if let adviceError {
                Text(adviceError).font(.subheadline).foregroundStyle(.secondary)
            }
            if adviceTask != nil {
                ProgressView("Reviewing measurements…")
                Button("Cancel AI review") { clearAdvice() }
            } else if !hasDeepSeekKey {
                Button("Set up DeepSeek") { showAISettings = true }
            } else if let evidence = adviceEvidence {
                Button { requestAdvice(evidence) } label: {
                    Label(adviceStep == nil ? "Ask DeepSeek what to try first" : "Review again", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
                Text("Sends your selected issue, measured timings and speeds, VPN detection status, and the responding address count to DeepSeek. Device names, network names, and addresses stay on this phone.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Collect a responsiveness result, check Wi-Fi, or complete a comparison to get a suggestion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func requestAdvice(_ evidence: WiFiAdviceEvidence) {
        guard adviceTask == nil else { return }
        guard let key = AIKeyManager.shared.getKey(for: .deepseek) else {
            hasDeepSeekKey = false
            showAISettings = true
            return
        }
        let concern = guide
        adviceError = nil
        adviceStep = nil
        adviceTask = Task { @MainActor in
            defer { if !Task.isCancelled { adviceTask = nil } }
            do {
                let step = try await WiFiAIAdvisor.prioritize(concern, evidence: evidence, key: key)
                guard !Task.isCancelled, concern == guide, evidence == adviceEvidence else { return }
                adviceStep = step
            } catch {
                guard !Task.isCancelled else { return }
                adviceError = (error as? WiFiAIAdvisor.Failure)?.errorDescription ??
                    "Could not reach DeepSeek. You can still use the repair steps below."
            }
        }
    }

    private func clearAdvice() {
        adviceTask?.cancel()
        adviceTask = nil
        adviceStep = nil
        adviceError = nil
    }

    private func devicesCard(_ inventory: WiFiDeviceInventory) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Devices on this network").font(.headline)
                Text("\(inventory.otherAddressCount) other IPv4 addresses observed")
                    .font(.title3.bold())
                Text("This count excludes the gateway and this phone. It can include wired devices and miss sleeping, isolated, IPv6-only or nonresponding devices. Check the router’s client list for its current Wi-Fi count.")
                    .font(.caption).foregroundStyle(.secondary)
                if inventory.observations.isEmpty {
                    Text("No IPv4 addresses responded. Check Local Network permission in Settings and try again.")
                }
                ForEach(inventory.observations) { device in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(assistant.deviceLabels[device.address] ?? device.name ??
                              (device.isGateway ? "Router" : "Unnamed device"), systemImage: device.icon)
                            .font(.subheadline.bold())
                        Text(device.address).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let name = device.name, let source = device.source {
                            Text("\(source): \(name)").font(.caption).foregroundStyle(.secondary)
                        }
                        Button(assistant.recognizedIPs.contains(device.address) ? "Recognized this scan · Undo" : "I recognize this device") {
                            if !assistant.recognizedIPs.insert(device.address).inserted {
                                assistant.recognizedIPs.remove(device.address)
                            }
                        }.buttonStyle(.bordered)
                        Button(assistant.deviceLabels[device.address] == nil ? "Add label" : "Edit label") {
                            labelDraft = assistant.deviceLabels[device.address] ?? ""
                            editingDevice = device
                        }
                        .accessibilityHint("Saves the name for reuse and labels this address for the current scan")
                        if !device.isGateway && !rememberedNames.isEmpty {
                            Menu("Match a saved device") {
                                ForEach(rememberedNames, id: \.self) { name in
                                    Button(name) {
                                        labelDraft = name
                                        editingDevice = device
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                }
                if !inventory.advertisedNames.isEmpty {
                    DisclosureGroup("Names heard via Bonjour") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This list includes service names whose address may be unavailable. Several names can come from one device.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(inventory.advertisedNames, id: \.self) { name in Text(name).font(.subheadline) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("Confirm ownership on the device or in the router’s client list before blocking anything. Names and addresses can change.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("How to identify or block a device") { showDeviceHelp = true }
                if !rememberedNames.isEmpty {
                    DisclosureGroup("Manage saved device names") {
                        ForEach(rememberedNames, id: \.self) { name in
                            Button("Forget \(name)", role: .destructive) {
                                updateRememberedNames(rememberedNames.filter { $0 != name })
                            }
                        }
                    }
                }
            }
        }
    }

    private var currentResponsiveness: HTTPSResponsiveness? {
        guard let result = assistant.quickResult, result.timestamp >= ExitPath.lastPathChange else { return nil }
        return result.responsiveness
    }

    private var responsivenessCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Does traffic make your connection lag?").font(.headline)
                Text("Compare HTTPS response while idle and during one speed test. The transfers can use up to about 50 MB.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Check responsiveness") { assistant.checkResponsiveness() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                if let sample = currentResponsiveness {
                    quickResponseRow("Idle", sample.idleMs)
                    quickResponseRow("During download", sample.downloadMs)
                    quickResponseRow("During upload", sample.uploadMs)
                    if let idle = sample.idleMs,
                       [sample.downloadMs, sample.uploadMs].compactMap({ $0 }).contains(where: { $0 >= idle + 50 && $0 >= idle * 1.5 }) {
                        Text("The test endpoint responded more slowly under load. When you notice lag, pause other large transfers you control, then repeat the check in the same spot.")
                    } else {
                        Text("If you still notice lag, try one guided change and measure again. A short or incomplete transfer can leave too few samples.")
                    }
                    Text("These are HTTPS timings to the selected test server. They include server response time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quickResponseRow(_ title: String, _ response: Double?) -> some View {
        AssistantEvidenceRow(title: title,
            value: response.map { String(format: "%.0f ms", $0) } ?? "Unavailable", detail: nil)
    }

    private var comparisonCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Did your change help?").font(.headline)
                Text("Measure before you change anything. Try one step above, then measure again from the same Wi-Fi and VPN route.")
                Text("Each round runs three speed tests and can use around 150 MB. The test measures HTTPS response while idle and during transfers when enough probes complete.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(assistant.before.isEmpty ? "Measure before · 3 tests" : "Replace baseline · 3 tests") { assistant.measureBaseline() }
                    .buttonStyle(.bordered).disabled(busy)
                if !assistant.before.isEmpty {
                    Toggle("I’m changing VPN servers", isOn: $assistant.compareVPNExits)
                        .disabled(busy)
                        .onChange(of: assistant.compareVPNExits) { _, _ in assistant.after = [] }
                    if assistant.compareVPNExits {
                        Text("Switch servers in your VPN app. Keep this Wi-Fi connection. A comparison requires two different observed exits and the same test endpoint.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Measure after · 3 tests") { assistant.measureAfter() }
                    .buttonStyle(.borderedProminent).disabled(busy || assistant.before.isEmpty)
                if let comparison = assistant.comparison {
                    AssistantEvidenceRow(title: "Median download",
                        value: String(format: "%.1f → %.1f Mbps", comparison.beforeMbps, comparison.afterMbps),
                        detail: String(format: "Observed change: %+.1f%%. This does not prove what caused it.", comparison.changePercent))
                    if let before = comparison.beforeLatencyMs, let after = comparison.afterLatencyMs {
                        AssistantEvidenceRow(title: "Median idle delay", value: String(format: "%.1f → %.1f ms", before, after),
                            detail: "Idle delay from the speed test’s separate latency probe.")
                    } else {
                        Text("Idle delay comparison unavailable. A download speed change alone cannot show whether lag improved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let response = comparison.response {
                        Divider()
                        Text("HTTPS responsiveness").font(.subheadline.bold())
                        responseRow("While idle", response.idle)
                        responseRow("During download", response.download)
                        responseRow("During upload", response.upload)
                        Text("Lower is faster. The timings include the test server’s response and apply to this endpoint.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(comparison.rangesOverlap ? "The test ranges overlap. Normal variation may explain the difference." : "The measured ranges do not overlap. Repeat later to check whether the change persists.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !assistant.before.isEmpty {
                    Text("Baseline recorded. Make one change, then measure again.").font(.subheadline)
                }
            }
        }
    }

    private func responseRow(_ title: String, _ phase: WiFiSpeedComparison.ResponseComparison.Phase?) -> some View {
        if let phase {
            return AssistantEvidenceRow(title: title, value: String(format: "%.0f → %.0f ms", phase.before, phase.after),
                                        detail: phase.assessment)
        }
        return AssistantEvidenceRow(title: title, value: "Unavailable",
                                    detail: "Too few complete HTTPS samples for a comparison.")
    }

    private var capabilitiesCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Router compatibility").font(.headline)
                AssistantCapabilityRow(title: "Connection tests", availability: "Available across brands",
                    reason: "Test endpoints must be reachable. Local discovery also needs permission and a network that allows device-to-device traffic.")
                AssistantCapabilityRow(title: "Change settings or block devices", availability: "Router integration required",
                    reason: "The UniFi integration reads clients. Use your router’s official controls to change settings or manage access.")
                AssistantCapabilityRow(title: "Neighbor channels and app bandwidth", availability: "Unavailable from this iOS scan",
                    reason: "Requires supported router telemetry or a separate network agent. NetoSensei cannot inspect other apps’ traffic or enumerate nearby networks with general public iOS Wi-Fi APIs.")
            }
        }
    }
}

private struct AssistantEvidenceRow: View {
    let title: String
    let value: String
    let detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.headline)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

private struct AssistantCapabilityRow: View {
    let title: String
    let availability: String
    let reason: String
    var body: some View {
        AssistantEvidenceRow(title: title, value: availability, detail: reason)
    }
}
