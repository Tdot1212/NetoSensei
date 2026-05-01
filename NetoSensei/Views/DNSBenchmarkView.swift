//
//  DNSBenchmarkView.swift
//  NetoSensei
//
//  DNS Benchmark view - tests resolution time for multiple DNS servers
//  IMPROVED: VPN-aware context, censorship check, how-to instructions
//

import SwiftUI

struct DNSBenchmarkView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = DNSBenchmarkViewModel()

    var body: some View {
        NavigationView {
            DNSBenchmarkContentView(vm: vm)
                .navigationTitle("DNS Benchmark")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }

                    if vm.hasResult && !vm.isRunning {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Run Again") {
                                Task {
                                    await vm.runBenchmark()
                                }
                            }
                        }
                    }
                }
        }
    }
}

// MARK: - Content View

struct DNSBenchmarkContentView: View {
    @ObservedObject var vm: DNSBenchmarkViewModel
    @State private var showDNSInstructions = false

    var body: some View {
        ScrollView {
            VStack(spacing: UIConstants.spacingL) {
                if vm.isRunning {
                    runningView
                } else if let result = vm.result {
                    resultsView(result: result)
                } else {
                    introView
                }
            }
            .padding()
        }
        .sheet(isPresented: $showDNSInstructions) {
            DNSInstructionsSheet()
        }
    }

    // MARK: - Intro View

    private var introView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: UIConstants.iconSizeXL * 2))
                .foregroundColor(AppColors.accent)

            VStack(spacing: UIConstants.spacingM) {
                Text("DNS Benchmark")
                    .font(.largeTitle.bold())

                Text("Test which DNS server is fastest from your location. Faster DNS means quicker page loads.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal)
            }

            // What's new info
            CardView {
                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(AppColors.yellow)
                        Text("Enhanced Testing")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("Tests 3 different domains per server (avoids cache)")
                        bulletPoint("Shows reliability % and jitter")
                        bulletPoint("Detects cached results")
                        bulletPoint("Checks DNS filtering/censorship")
                        bulletPoint("VPN-aware recommendations")
                    }
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                }
            }

            // DNS Servers info
            CardView {
                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    Text("Servers to Test")
                        .font(.headline)

                    ForEach(DNSBenchmarkService.servers, id: \.address) { server in
                        HStack {
                            Text(server.name)
                                .font(.subheadline)
                            Spacer()
                            Text(server.address)
                                .font(.caption.monospaced())
                                .foregroundColor(AppColors.textSecondary)
                            Text(server.region)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(server.region == "China" ? AppColors.yellow.opacity(0.2) : AppColors.accent.opacity(0.2))
                                .foregroundColor(server.region == "China" ? AppColors.yellow : AppColors.accent)
                                .cornerRadius(4)
                        }
                    }
                }
            }

            Button(action: {
                Task {
                    await vm.runBenchmark()
                }
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Benchmark")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.accent)
                .foregroundColor(.white)
                .cornerRadius(UIConstants.cornerRadiusL)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, UIConstants.spacingXL)

            Spacer()
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    // MARK: - Running View

    private var runningView: some View {
        VStack(spacing: UIConstants.spacingXL) {
            Spacer()

            ProgressView(value: vm.progress) {
                VStack(spacing: UIConstants.spacingS) {
                    Text("Testing DNS Servers...")
                        .font(.headline)

                    Text("\(Int(vm.progress * 100))%")
                        .font(.title.bold())
                        .foregroundColor(AppColors.accent)
                }
            }
            .progressViewStyle(.linear)
            .tint(AppColors.accent)
            .frame(width: 250)

            Text(vm.currentTest)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Results View

    @ViewBuilder
    private func resultsView(result: QuickDNSBenchmarkResult) -> some View {
        // Summary Card
        CardView {
            VStack(spacing: UIConstants.spacingM) {
                if let fastest = result.fastestServer {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(AppColors.yellow)
                        Text("Fastest: \(fastest.name)")
                            .font(.title3.bold())
                    }

                    if let latency = fastest.latencyMs {
                        HStack(spacing: 4) {
                            Text("\(Int(latency))ms")
                                .font(.title.bold())
                                .foregroundColor(AppColors.green)

                            if fastest.isCached {
                                Text("(may be cached)")
                                    .font(.caption)
                                    .foregroundColor(AppColors.yellow)
                            }
                        }
                    }
                }

                Text(result.summary)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }

        // VPN Context Section (if VPN is active)
        if result.isVPNActive {
            vpnContextCard(vpnCountry: result.vpnCountry)
        }

        // Results List
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Text("All Results")
                        .font(.headline)
                    Spacer()
                    Text("* = may be cached")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                ForEach(result.results.sorted(by: { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) })) { server in
                    dnsServerRow(server: server)
                    if server.id != result.results.last?.id {
                        Divider()
                    }
                }
            }
        }

        // Censorship Check (if available)
        if let censorshipSummary = result.censorshipSummary {
            censorshipCard(summary: censorshipSummary)
        }

        // Understanding Your Results
        understandingResultsCard(result: result)

        // Recommendation Card
        recommendationCard(recommendation: result.recommendation)

        // How to Change DNS
        Button(action: {
            showDNSInstructions = true
        }) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(AppColors.accent)
                Text("How to Change DNS on iPhone")
                    .font(.subheadline)
                    .foregroundColor(AppColors.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(UIConstants.cornerRadiusM)
        }
        .buttonStyle(.plain)
    }

    // MARK: - VPN Context Card

    private func vpnContextCard(vpnCountry: String?) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(AppColors.accent)
                    Text("You're on VPN")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "globe")
                            .foregroundColor(AppColors.yellow)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Why Global DNS is Slow")
                                .font(.subheadline.bold())
                            Text("Global DNS servers (Cloudflare, Google) appear slow because your requests travel through the VPN tunnel to \(vpnCountry ?? "another country") and back. This is normal VPN behavior.")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(Color.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speed vs. Privacy Tradeoff")
                                .font(.subheadline.bold())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("🇨🇳 China DNS (Alibaba, Tencent, 114)")
                                    .font(.caption.bold())
                                Text("Fast but may filter content or log queries")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)

                                Text("🌍 Global DNS (Cloudflare, Google)")
                                    .font(.caption.bold())
                                    .padding(.top, 4)
                                Text("Slower through VPN but no filtering")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppColors.accent)
                            .frame(width: 20)
                        Text("Your VPN app likely handles DNS automatically. Check your VPN's settings if you want to customize DNS behavior.")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Censorship Card

    private func censorshipCard(summary: CensorshipSummary) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "eye.slash")
                        .foregroundColor(Color.orange)
                    Text("DNS Filtering Check")
                        .font(.headline)
                }

                Text("Tested if your current DNS can resolve commonly filtered domains:")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)

                if let systemResults = summary.serverResults["System Default"] {
                    ForEach(systemResults) { result in
                        HStack {
                            Image(systemName: result.resolved ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.resolved ? AppColors.green : AppColors.red)
                                .frame(width: 20)

                            Text(result.domain)
                                .font(.subheadline)

                            Spacer()

                            if result.resolved {
                                Text("Resolves")
                                    .font(.caption)
                                    .foregroundColor(AppColors.green)
                            } else {
                                Text("Blocked/Failed")
                                    .font(.caption)
                                    .foregroundColor(AppColors.red)
                            }
                        }
                    }

                    let blockedCount = systemResults.filter { !$0.resolved }.count
                    if blockedCount > 0 {
                        Divider()
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(AppColors.yellow)
                            Text("\(blockedCount) domain(s) blocked. Use a VPN or switch to a global DNS (1.1.1.1) to access these sites.")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Understanding Results Card

    private func understandingResultsCard(result: QuickDNSBenchmarkResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(AppColors.accent)
                    Text("Understanding Your Results")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    if !result.isVPNActive {
                        // Non-VPN explanations
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle")
                                .foregroundColor(AppColors.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What is DNS?")
                                    .font(.subheadline.bold())
                                Text("DNS is like a phone book for the internet. When you visit a website, DNS looks up its IP address. Faster DNS = faster page loads.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    // Cached results explanation
                    let cachedResults = result.results.filter { $0.isCached }
                    if !cachedResults.isEmpty {
                        Divider()
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(AppColors.yellow)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("About Cached Results")
                                    .font(.subheadline.bold())
                                Text("Results marked with * (under 2ms) may be hitting a local cache, not the actual DNS server. Real-world performance may differ.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    // Reliability explanation
                    let unreliableResults = result.results.filter { $0.successRate < 0.8 }
                    if !unreliableResults.isEmpty {
                        Divider()
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(Color.orange)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Unreliable Servers")
                                    .font(.subheadline.bold())
                                let names = unreliableResults.map { $0.name }.joined(separator: ", ")
                                Text("\(names) had low success rates. These servers may be blocked or overloaded from your location.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recommendation Card

    private func recommendationCard(recommendation: DNSRecommendation) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                HStack {
                    Image(systemName: recommendationIcon(recommendation.priority))
                        .foregroundColor(recommendationColor(recommendation.priority))
                    Text(recommendation.title)
                        .font(.headline)
                }

                Text(recommendation.detail)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textPrimary)

                if let action = recommendation.action {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(AppColors.accent)
                        Text(action)
                            .font(.caption)
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
        }
    }

    private func recommendationIcon(_ priority: DNSRecommendation.Priority) -> String {
        switch priority {
        case .info: return "lightbulb.fill"
        case .suggestion: return "hand.point.right.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private func recommendationColor(_ priority: DNSRecommendation.Priority) -> Color {
        switch priority {
        case .info: return AppColors.accent
        case .suggestion: return AppColors.yellow
        case .warning: return Color.orange
        }
    }

    // MARK: - Server Row

    private func dnsServerRow(server: QuickDNSServerResult) -> some View {
        HStack {
            Image(systemName: server.statusIcon)
                .foregroundColor(statusColor(server.statusColor))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(server.name)
                        .font(.subheadline.bold())
                    if server.isFastest {
                        Text("FASTEST")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.green)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    if server.isCached {
                        Text("CACHED?")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppColors.yellow.opacity(0.3))
                            .foregroundColor(AppColors.yellow)
                            .cornerRadius(3)
                    }
                }
                HStack(spacing: 8) {
                    Text(server.address)
                        .font(.caption.monospaced())
                        .foregroundColor(AppColors.textSecondary)

                    if server.successRate < 1.0 && !server.failed {
                        Text("Reliability: \(server.reliabilityText)")
                            .font(.caption2)
                            .foregroundColor(server.successRate >= 0.8 ? AppColors.textSecondary : Color.orange)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(server.displayLatency)
                    .font(.subheadline.bold().monospaced())
                    .foregroundColor(statusColor(server.statusColor))

                if let jitter = server.jitter, jitter > 10 {
                    Text("±\(Int(jitter))ms")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private func statusColor(_ colorName: String) -> Color {
        switch colorName {
        case "green": return AppColors.green
        case "yellow": return AppColors.yellow
        case "red": return AppColors.red
        default: return .gray
        }
    }
}

// MARK: - DNS Instructions Sheet

struct DNSInstructionsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    Text("How to Change DNS on iPhone")
                        .font(.title2.bold())
                        .padding(.bottom)

                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(AppColors.accent)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(instruction.title)
                                    .font(.subheadline.bold())
                                Text(instruction.detail)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical)

                    // Quick Copy section
                    VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                        Text("Popular DNS Addresses")
                            .font(.headline)

                        dnsAddressRow(name: "Cloudflare", primary: "1.1.1.1", secondary: "1.0.0.1")
                        dnsAddressRow(name: "Google", primary: "8.8.8.8", secondary: "8.8.4.4")
                        dnsAddressRow(name: "Alibaba (China)", primary: "223.5.5.5", secondary: "223.6.6.6")
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var instructions: [(title: String, detail: String)] {
        [
            ("Open Settings", "Tap the Settings app on your home screen"),
            ("Tap Wi-Fi", "Find and tap the Wi-Fi option"),
            ("Tap ⓘ next to your network", "Look for the small (i) icon next to your connected network name"),
            ("Scroll to Configure DNS", "Scroll down and tap \"Configure DNS\""),
            ("Select Manual", "Change from \"Automatic\" to \"Manual\""),
            ("Remove existing DNS", "Tap the red minus button next to any existing DNS entries"),
            ("Add new DNS server", "Tap \"Add Server\" and enter the DNS IP address (e.g., 1.1.1.1)"),
            ("Add secondary (optional)", "Add a backup DNS server (e.g., 1.0.0.1)"),
            ("Tap Save", "Tap \"Save\" in the top right corner")
        ]
    }

    private func dnsAddressRow(name: String, primary: String, secondary: String) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
            Spacer()
            Text("\(primary), \(secondary)")
                .font(.caption.monospaced())
                .foregroundColor(AppColors.accent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
class DNSBenchmarkViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var currentTest = ""
    @Published var result: QuickDNSBenchmarkResult?

    var hasResult: Bool { result != nil }

    func runBenchmark() async {
        isRunning = true
        progress = 0
        currentTest = "Starting..."

        result = await DNSBenchmarkService.shared.benchmark { [weak self] progress, status in
            Task { @MainActor in
                self?.progress = progress
                self?.currentTest = status
            }
        }

        isRunning = false
    }
}

// MARK: - Preview

struct DNSBenchmarkView_Previews: PreviewProvider {
    static var previews: some View {
        DNSBenchmarkView()
    }
}
