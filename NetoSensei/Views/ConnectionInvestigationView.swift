import Network
import SwiftUI

struct ConnectionInvestigationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("connectionRepair.canRestoreWiFi") private var canRestoreWiFi = false
    @FocusState private var editingHost: Bool
    @State private var topic: InvestigationTopic
    @State private var host: String
    @State private var before: InvestigationSample?
    @State private var after: InvestigationSample?
    @State private var beforeResolver: ResolverObservation = .unknown
    @State private var afterResolver: ResolverObservation = .unknown
    @State private var result: (InvestigationVerdict, String)?
    @State private var operation: Task<Void, Never>?
    @State private var progress = ""
    @State private var notice: String?
    @State private var alternateLead: InvestigationLead?
    @State private var previousOutcome: String?
    @State private var handoff: (action: ConnectionRepair, route: InvestigationRoute)?
    @State private var confirmingCellular = false
    @State private var askingAI = false

    init(topic: InvestigationTopic, host: String = ConnectionInvestigationRunner.defaultHost) {
        _topic = State(initialValue: topic)
        _host = State(initialValue: host)
    }

    private enum ResolverObservation: String, CaseIterable {
        case unknown = "Unavailable"
        case expected = "Expected resolver"
        case different = "Different resolver"

        var reading: InvestigationReading {
            InvestigationReading(label: "Browser resolver, reported by you",
                detail: rawValue, outcome: self == .unknown ? nil : self == .expected)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let before {
                        let lead = activeLead(for: before)
                        if let result {
                            resultCard(result, lead: lead)
                        }
                        if canRestoreWiFi { restorationCard }
                        if !canRestoreWiFi, ConnectionRepair.isAvailable(topic: topic, baseline: before, lead: lead) {
                            repairCard(before, lead: lead)
                        }
                        if topic == .privacy { EncryptedDNSRepairCard() }
                        nextCard(lead)
                        readingsCard("Baseline", sample: before, resolver: beforeResolver)
                        if let after {
                            readingsCard("Comparison", sample: after, resolver: afterResolver)
                        }
                        ShareLink(item: report(before: before, lead: lead)) {
                            Label("Share investigation", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        if canRestoreWiFi { restorationCard }
                        intakeCard
                    }
                }
                .connectionBriefColumn()
            }
            .background(ConnectionBriefStyle.canvas)
            .navigationTitle("Guided investigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if before != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Start over", action: startOver).disabled(operation != nil || handoff != nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { verifyHandoff() }
            }
            .confirmationDialog("Try cellular for this comparison?", isPresented: $confirmingCellular, titleVisibility: .visible) {
                Button("Switch with Shortcuts") { launch(.tryCellular) }
                Button("I’ll switch in Settings") { launch(.tryCellular, useShortcut: false) }
            } message: {
                Text(topic == .speed
                     ? "Wi-Fi will turn off. This test can use up to 24 MB of cellular data. Keep your VPN setting as it is."
                     : "Wi-Fi will turn off and iOS can use cellular data. Keep your VPN setting as it is.")
            }
            .onDisappear { operation?.cancel() }
        }
    }

    private var intakeCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                BriefSectionTitle(title: "What are you trying to solve?")
                Menu {
                    Picker("Problem", selection: $topic) {
                        ForEach(InvestigationTopic.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                } label: {
                    HStack {
                        Text(topic.rawValue).font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Choose a problem")
                .accessibilityValue(topic.rawValue)
                .accessibilityIdentifier("investigation.topic")
                .disabled(operation != nil)
                Text(topic.question).font(.subheadline)
                if topic.usesHostname {
                    TextField("Affected website hostname", text: $host)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                        .focused($editingHost)
                        .disabled(operation != nil)
                        .accessibilityIdentifier("investigation.hostname")
                }
                if topic == .speed {
                    Text("Each run requests up to 24 MB of test data over the active connection.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                runButton("Run baseline", isComparison: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func repairCard(_ sample: InvestigationSample, lead: InvestigationLead) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                BriefSectionTitle(title: "Switch and verify")
                Text("Switch to cellular, then return here. NetoSensei will repeat the same checks and tell you whether it helped.")
                    .font(.subheadline)
                Button(ConnectionRepair.tryCellular.title) { confirmingCellular = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("investigation.repair.cellular")
                    .disabled(operation != nil || handoff != nil)
                if topic == .speed && lead.change != .otherAccess {
                    Button(askingAI ? "Asking DeepSeek…" : "Choose a fix with DeepSeek") {
                        chooseRepair(for: sample)
                    }
                    .frame(minHeight: 44)
                    .disabled(operation != nil || handoff != nil)
                    .accessibilityIdentifier("investigation.repair.ai")
                }
                DisclosureGroup("Set up the Wi-Fi shortcuts") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("In Shortcuts, make a shortcut named NetoSensei Try Cellular with the Set Wi-Fi action set to Off. Create NetoSensei Restore Wi-Fi with Set Wi-Fi set to On. Keep cellular data enabled for the first shortcut.")
                        Link("Open Apple’s Shortcuts guide", destination: URL(string: "https://support.apple.com/guide/shortcuts/welcome/ios")!)
                            .frame(minHeight: 44)
                    }
                    .font(.subheadline)
                    .padding(.top, 8)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var restorationCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                BriefSectionTitle(title: "Return to Wi-Fi")
                Text("Restore Wi-Fi with Shortcuts or turn it back on in Settings → Wi-Fi. iOS chooses which known network to join.")
                    .font(.subheadline)
                Button(ConnectionRepair.restoreWiFi.title) { launch(.restoreWiFi) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("investigation.repair.restore")
                    .disabled(operation != nil || handoff != nil)
                if let handoff {
                    Button(handoff.action == .tryCellular ? "Check cellular" : "Check Wi-Fi", action: verifyHandoff)
                        .buttonStyle(.bordered)
                        .disabled(operation != nil)
                    Button("Cancel switch check") {
                        self.handoff = nil
                        notice = "The check was cancelled. You can restore Wi-Fi from this screen or in Settings."
                    }
                    .disabled(operation != nil)
                }
                if before == nil, let notice {
                    Text(notice).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func launch(_ action: ConnectionRepair, useShortcut: Bool = true) {
        guard operation == nil, handoff == nil else { return }
        let route = ConnectionInvestigationRunner.route()
        if action == .restoreWiFi, route.interface == "WiFi" {
            canRestoreWiFi = false
            notice = "Wi-Fi is already active."
            return
        }
        guard action == .restoreWiFi || route.interface == "WiFi" else {
            notice = "The active connection has changed. Check Wi-Fi in Settings before trying again."
            return
        }
        if action == .tryCellular, before?.route.generation != route.generation {
            notice = "Take a new baseline on this Wi-Fi before switching."
            return
        }
        handoff = (action, route)
        if action == .tryCellular { canRestoreWiFi = true }
        if !useShortcut {
            notice = "In Settings → Wi-Fi, turn Wi-Fi off. Return here when cellular is active."
            return
        }
        notice = "Return to NetoSensei after Shortcuts finishes."
        openURL(action.shortcutURL) { accepted in
            guard !accepted, handoff?.action == action else { return }
            handoff = nil
            if action == .tryCellular, ConnectionInvestigationRunner.route().interface == "WiFi" {
                canRestoreWiFi = false
            }
            notice = "Shortcuts couldn’t open. Check the shortcut setup or switch in Settings."
        }
    }

    private func verifyHandoff() {
        guard let handoff, operation == nil else { return }
        progress = "Confirming the connection switch…"
        notice = nil
        operation = Task { @MainActor in
            var confirmed = false
            for _ in 0..<20 {
                if Task.isCancelled { break }
                if handoff.action.confirmsChange(from: handoff.route, to: ConnectionInvestigationRunner.route()) {
                    confirmed = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
            var vpnIssue: String?
            if confirmed, handoff.action == .tryCellular, handoff.route.vpn.isLikelyOn {
                progress = "Checking the VPN on cellular…"
                _ = await ExitPath.resolveFresh(timeoutSeconds: 6)
                vpnIssue = handoff.route.comparisonIssue(after: ConnectionInvestigationRunner.route(), change: .otherAccess)
            }
            operation = nil
            self.handoff = nil
            if Task.isCancelled {
                notice = "The switch check stopped. Check your current connection in Settings."
            } else if !confirmed {
                notice = "The connection did not switch. Check that the shortcut ran and that the other connection is available."
            } else if let vpnIssue {
                notice = "Cellular is active. \(vpnIssue) Reconnect your VPN and run the comparison, or restore Wi-Fi."
                if let before {
                    alternateLead = ConnectionRepair.accessLead(from: activeLead(for: before))
                    result = nil
                    after = nil
                }
            } else if handoff.action == .restoreWiFi {
                canRestoreWiFi = false
                notice = "Wi-Fi is active again."
            } else if let before {
                alternateLead = ConnectionRepair.accessLead(from: activeLead(for: before))
                result = nil
                after = nil
                run(isComparison: true)
            }
        }
    }

    private func chooseRepair(for sample: InvestigationSample) {
        guard operation == nil, handoff == nil else { return }
        guard let key = AIKeyManager.shared.getKey(for: .deepseek) else {
            notice = "Set up a DeepSeek key in AI Settings, or choose a fix here."
            return
        }
        askingAI = true
        notice = nil
        progress = "Choosing a fix from the download results…"
        operation = Task { @MainActor in
            defer {
                askingAI = false
                operation = nil
            }
            do {
                let useCellular = try await WiFiAIAdvisor.recommendsCellular(evidence: ConnectionRepairEvidence(sample: sample), key: key)
                try Task.checkCancellation()
                if useCellular {
                    confirmingCellular = true
                } else {
                    notice = "DeepSeek chose Pause background transfers. Pause a large transfer, then run the comparison on this Wi-Fi."
                }
            } catch is CancellationError {
                notice = "DeepSeek selection stopped."
            } catch {
                notice = "DeepSeek couldn’t choose a fix. Use the options on this screen."
            }
        }
    }

    private func nextCard(_ lead: InvestigationLead) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                BriefSectionTitle(title: "What the baseline found")
                Text(lead.headline).font(.headline).accessibilityIdentifier("investigation.lead")
                Text(lead.evidence).font(.subheadline).foregroundStyle(.secondary)

                Divider()
                BriefSectionTitle(title: "Try one change")
                Text(lead.change.rawValue).font(.headline)
                Text(lead.change.instructions).font(.subheadline)
                if topic == .privacy {
                    Link("Cloudflare’s check for 1.1.1.1 users", destination: URL(string: "https://1.1.1.1/help")!)
                        .frame(minHeight: 44)
                    resolverPicker("Browser result before the change", selection: $beforeResolver)
                    resolverPicker("Browser result after the change", selection: $afterResolver)
                }
                if topic == .wifi {
                    Link("Apple’s Wi-Fi troubleshooting guide", destination: URL(string: "https://support.apple.com/en-us/111786")!)
                        .frame(minHeight: 44)
                }
                runButton(after == nil ? "Run comparison" : "Run comparison again", isComparison: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resolverPicker(_ title: String, selection: Binding<ResolverObservation>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ResolverObservation.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.navigationLink)
        .disabled(operation != nil)
        .onChange(of: selection.wrappedValue) {
            if after != nil { result = nil }
        }
    }

    @ViewBuilder private func runButton(_ title: String, isComparison: Bool) -> some View {
        if operation != nil {
            ProgressView(progress).font(.subheadline)
            Button("Stop", role: .cancel) {
                progress = "Stopping…"
                operation?.cancel()
            }
            .buttonStyle(.bordered)
        } else {
            Button(title) { run(isComparison: isComparison) }
                .disabled(handoff != nil)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier(isComparison ? "investigation.compare" : "investigation.baseline")
        }
        if let notice {
            Text(notice).font(.subheadline).foregroundStyle(ConnectionBriefStyle.cautionInk)
        }
    }

    private func readingsCard(_ title: String, sample: InvestigationSample, resolver: ResolverObservation) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                BriefSectionTitle(title: title)
                Text(sample.route.description).font(.subheadline).foregroundStyle(.secondary)
                Text(sample.at, style: .time).font(.caption).foregroundStyle(.secondary)
                let readings = sample.orderedReadings + (topic == .privacy ? [resolver.reading] : [])
                ForEach(Array(readings.enumerated()), id: \.offset) { _, item in
                    Divider()
                    Text(item.label).font(.subheadline.weight(.semibold))
                    Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultCard(_ result: (InvestigationVerdict, String), lead: InvestigationLead) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                BriefSectionTitle(title: result.0.title)
                    .accessibilityIdentifier("investigation.verdict")
                Text(result.1).font(.subheadline)
                if canRestoreWiFi, lead.change == .otherAccess, after?.route.interface == "Cellular" {
                    Text(result.0 == .improved
                         ? "Cellular helped this test. You can keep using it for the affected task or restore Wi-Fi to save cellular data."
                         : "Restore Wi-Fi if cellular didn’t help the task you were trying to complete.")
                        .font(.subheadline)
                }
                if topic == .vpn, let before, let after,
                   before.route.comparisonIssue(after: after.route, change: lead.change) == nil {
                    Text(ipv6Comparison(before, after)).font(.subheadline)
                }
                if let before, result.0 != .improved {
                    ShareLink(item: report(before: before, lead: lead)) {
                        Label("Share results with support", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                if topic != .privacy, lead.change != .otherAccess,
                   result.0 == .noChange || result.0 == .worsened, let after {
                    Button("Compare another connection") {
                        previousOutcome = "\(result.0.title) · \(result.1)"
                        before = after
                        self.after = nil
                        alternateLead = lead.acrossAccess
                        self.result = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(operation != nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func run(isComparison: Bool) {
        guard operation == nil else { return }
        editingHost = false
        notice = nil
        let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !topic.usesHostname || ConnectionInvestigationRunner.validHost(hostname) else {
            notice = "Enter a hostname such as www.apple.com, without a URL or path."
            return
        }
        let choice = topic
        progress = "Preparing the tests…"
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                var sample = try await ConnectionInvestigationRunner.run(topic: choice, host: hostname) { progress = $0 }
                if isComparison, var baseline = before {
                    if choice == .privacy {
                        baseline.readings[.resolver] = beforeResolver.reading
                        sample.readings[.resolver] = afterResolver.reading
                    }
                    let lead = activeLead(for: baseline)
                    after = sample
                    result = InvestigationReasoning.compare(baseline, sample, using: lead)
                } else {
                    before = sample
                }
            } catch is CancellationError {
                notice = "The run was stopped."
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    private func startOver() {
        before = nil
        after = nil
        result = nil
        notice = nil
        beforeResolver = .unknown
        afterResolver = .unknown
        alternateLead = nil
        previousOutcome = nil
    }

    private func activeLead(for sample: InvestigationSample) -> InvestigationLead {
        alternateLead ?? InvestigationReasoning.lead(for: topic, sample: sample)
    }

    private func ipv6Comparison(_ before: InvestigationSample, _ after: InvestigationSample) -> String {
        guard let first = before.ipv6.flatMap(IPv6Address.init),
              let second = after.ipv6.flatMap(IPv6Address.init) else {
            return "An IPv6 address was unavailable in at least one run. IPv6 routing and protection remain unverified."
        }
        return first == second
            ? "The two probes saw the same public IPv6 address."
            : "The two probes saw different public IPv6 addresses."
    }

    private func report(before: InvestigationSample, lead: InvestigationLead) -> String {
        var lines = ["NetoSensei · \(topic.rawValue)", topic.question, lead.headline, lead.evidence, lead.change.rawValue]
        func append(_ sample: InvestigationSample, title: String, resolver: ResolverObservation) {
            lines += ["", title, sample.at.formatted(date: .abbreviated, time: .shortened), sample.route.description]
            let readings = sample.orderedReadings
                + (topic == .privacy ? [resolver.reading] : [])
            for reading in readings { lines.append("\(reading.label) — \(reading.detail)") }
        }
        append(before, title: "Baseline", resolver: beforeResolver)
        if let after { append(after, title: "Comparison", resolver: afterResolver) }
        if let result { lines += ["", result.0.title, result.1] }
        if topic == .vpn, let after, before.route.comparisonIssue(after: after.route, change: lead.change) == nil {
            lines.append(ipv6Comparison(before, after))
        }
        if let previousOutcome { lines += ["", "Earlier comparison", previousOutcome] }
        return lines.joined(separator: "\n")
    }
}
