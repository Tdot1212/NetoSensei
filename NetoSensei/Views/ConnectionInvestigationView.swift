import Network
import SwiftUI

struct ConnectionInvestigationView: View {
    @Environment(\.dismiss) private var dismiss
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
                        Button("Start over", action: startOver).disabled(operation != nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
                if topic == .vpn, let before, let after,
                   before.route.comparisonIssue(after: after.route, change: lead.change) == nil {
                    Text(ipv6Comparison(before, after)).font(.subheadline)
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
