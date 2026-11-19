//
//  SpeedTabView.swift
//  NetoSensei
//
//  Combined Speed tab with Speed Test and Streaming Capability
//

import SwiftUI

struct SpeedTabView: View {
    @StateObject private var speedVM = SpeedTestViewModel()
    @StateObject private var streamingVM = StreamingDiagnosticViewModel()
    @StateObject private var vpnBenchmark = VPNBenchmark()
    @State private var selectedSection: SpeedSection = .overview

    @State private var runPhase: String?
    @State private var runSummary: PerformanceSummary?
    @State private var runNotice: String?

    private struct PerformanceSummary {
        let speed: SpeedTestResult?
        let streaming: StreamingDiagnosticResult?
        let sites: [VPNBenchmark.BenchmarkResult]
        let path: Date

        var nextStep: String {
            if let streaming, !streaming.cdnReachable {
                return "Open \(streaming.platform.rawValue) and try playing a video. If it stalls, change one thing, such as moving closer to the router or switching VPN server, and run these checks again."
            }
            if sites.contains(where: { !$0.reachable || ($0.httpStatus ?? 0) >= 400 }) {
                return "Open any site you’re having trouble with in its app or Safari. If it still fails, change one thing about your connection and rerun these checks on the same Wi-Fi."
            }
            if speed == nil {
                return "Open a site you normally use to confirm the connection works, then run the checks again."
            }
            return "If you still notice lag, change one thing, such as moving closer to the router or switching VPN server, and run the same checks again."
        }
    }

    enum SpeedSection: String, CaseIterable {
        case overview = "Overview"
        case speedTest = "Speed"
        case streaming = "Streaming"
        case vpnSites = "VPN Sites"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Section Picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(SpeedSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(runPhase != nil)
                .padding()

                // Content based on selection
                switch selectedSection {
                case .overview:
                    overview
                case .speedTest:
                    speedTestContent
                case .streaming:
                    streamingContent
                case .vpnSites:
                    vpnBenchmarkContent
                }
            }
            .navigationTitle("Connection Test")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if selectedSection != .overview {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            if selectedSection == .speedTest, let result = speedVM.result {
                                ShareLink(
                                    item: DiagnosticReportGenerator.shared.generateSpeedTestReport(speedTest: result),
                                    subject: Text("NetoSensei Speed Test"),
                                    message: Text("My speed test results")
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            runAgainButton
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 16) {
                CardView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Check your connection")
                            .font(.title2.bold())
                        Text("Measure speed, sample the \(streamingVM.selectedPlatform.rawValue) endpoints and check popular sites in one run.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let runPhase {
                            HStack {
                                ProgressView()
                                Text(runPhase)
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            Button(runSummary == nil ? "Run all checks" : "Run all checks again", action: runAllChecks)
                                .buttonStyle(.borderedProminent)
                                .disabled(speedVM.isRunning || streamingVM.isRunning || vpnBenchmark.isRunning)
                                .accessibilityIdentifier("performance.runAll")
                        }
                        if let runNotice {
                            Text(runNotice).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let summary = runSummary {
                    summaryCard(summary)
                }
            }
            .padding()
        }
    }

    private func summaryCard(_ summary: PerformanceSummary) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What this run found").font(.headline)
                if summary.path != ExitPath.lastPathChange {
                    Text("The connection has changed since this run.").font(.footnote).foregroundStyle(.secondary)
                }
                if let speed = summary.speed {
                    let download = String(format: "%.1f Mbps down", speed.downloadSpeed)
                    let upload = speed.measuredUploadSpeed.map { String(format: "%.1f Mbps up", $0) } ?? "Upload unavailable"
                    Label("\(download) · \(upload)", systemImage: "speedometer")
                    let estimate = ConnectionCapabilityAnalyzer.analyze(from: speed).maxStreamingQuality.rawValue
                    Text("Streaming bandwidth estimate: \(estimate)").font(.footnote).foregroundStyle(.secondary)
                    if speed.ping == nil {
                        Text("Remote delay was unavailable. Call and gaming quality remain unverified.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Label("Speed could not be measured", systemImage: "speedometer")
                }
                if let streaming = summary.streaming {
                    let response = streaming.cdnPing.map { String(format: "%.0f ms HTTPS response", $0) } ?? "No HTTPS response"
                    Label("\(streaming.platform.rawValue) · \(response)", systemImage: "play.tv")
                }
                let successful = summary.sites.filter { ($0.httpStatus ?? 0) >= 200 && ($0.httpStatus ?? 0) < 400 }.count
                let httpErrors = summary.sites.filter { ($0.httpStatus ?? 0) >= 400 }.count
                let unanswered = summary.sites.filter { $0.httpStatus == nil }.count
                Label("\(successful) site successes · \(httpErrors) HTTP errors · \(unanswered) without response", systemImage: "globe")
                Text("Website responses and available bandwidth don’t establish video playback quality.")
                    .font(.footnote).foregroundStyle(.secondary)
                Divider()
                Text("Try this next").font(.headline)
                Text(summary.nextStep).font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("performance.summary")
        }
    }

    private func runAllChecks() {
        guard runPhase == nil, !speedVM.isRunning, !streamingVM.isRunning, !vpnBenchmark.isRunning else { return }
        runSummary = nil
        runNotice = nil
        runPhase = "1 of 3 · Measuring speed"
        Task { @MainActor in
            let path = ExitPath.lastPathChange
            defer { runPhase = nil }
            await speedVM.runSpeedTestAndWait()
            guard checkPath(path) else { return }
            runPhase = "2 of 3 · Checking streaming endpoints"
            await streamingVM.runStreamingDiagnostic()
            guard checkPath(path) else { return }
            runPhase = "3 of 3 · Checking sites"
            await vpnBenchmark.runBenchmark()
            guard checkPath(path) else { return }
            runSummary = PerformanceSummary(speed: speedVM.result, streaming: streamingVM.result,
                                            sites: vpnBenchmark.results, path: path)
        }
    }

    private func checkPath(_ startingPath: Date) -> Bool {
        guard startingPath != ExitPath.lastPathChange else { return true }
        runNotice = "The connection changed during the run. Run all checks again to get results from one connection."
        return false
    }

    // MARK: - Speed Test Content

    private var speedTestContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Show either the start card OR the full results view (not both)
                if speedVM.hasResult {
                    // Full results view (no duplicate small card)
                    SpeedTestContentView(vm: speedVM)
                } else {
                    // Start card (only when no results)
                    speedTestCard
                }
            }
            .padding()
        }
    }

    private var speedTestCard: some View {
        CardView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "speedometer")
                        .font(.title2)
                        .foregroundColor(AppColors.accent)
                    Text("Speed Test")
                        .font(.headline)
                    Spacer()
                }

                if speedVM.isRunning {
                    VStack(spacing: 12) {
                        ProgressView(value: speedVM.progress)
                            .tint(AppColors.accent)

                        Text(speedVM.phaseDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("\(Int(speedVM.progress * 100))%")
                            .font(.title2.bold())
                            .foregroundColor(AppColors.accent)
                    }
                    .padding()
                } else if !speedVM.hasResult {
                    VStack(spacing: 12) {
                        Text("Measure your download speed, upload speed, ping, and jitter.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            speedVM.runSpeedTest()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Speed Test")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                } else if let result = speedVM.result {
                    // Quick summary
                    HStack(spacing: 20) {
                        // Download
                        VStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                            Text("\(String(format: "%.1f", result.downloadSpeed))")
                                .font(.title2.bold())
                                .foregroundColor(NetworkColors.forSpeed(result.downloadSpeed))
                            Text("Mbps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Upload
                        VStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.green)
                            Text("\(String(format: "%.1f", result.uploadSpeed))")
                                .font(.title2.bold())
                                .foregroundColor(NetworkColors.forSpeed(result.uploadSpeed))
                            Text("Mbps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Ping (Phase 3: nil = unmeasurable → "—", never 999)
                        VStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            Text(result.ping.map { "\(Int($0))" } ?? "—")
                                .font(.title2.bold())
                                .foregroundColor(result.ping.map { NetworkColors.forLatency($0) } ?? AppColors.yellow)
                            Text("ms")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Streaming Content

    private var streamingContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Streaming Test Card
                streamingTestCard

                // Results (if available)
                if streamingVM.hasResult {
                    StreamingDiagnosticContentView(vm: streamingVM, currentSpeed: speedVM.result)
                }
            }
            .padding()
        }
    }

    private var streamingTestCard: some View {
        CardView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "play.tv.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                    Text("Streaming Capability")
                        .font(.headline)
                    Spacer()
                }

                if streamingVM.isRunning {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Testing streaming capability...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if !streamingVM.hasResult {
                    VStack(spacing: 12) {
                        Text("Check streaming endpoint responses. Playback quality, CDN bandwidth and real-time suitability require additional measurements.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            Task {
                                await streamingVM.runStreamingDiagnostic()
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Test Streaming")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                } else if streamingVM.hasResult {
                    // FIX (Speed Issue 1/6): Icon row reads from
                    // ConnectionCapabilityAnalyzer — the SAME source that the
                    // per-service detail and the Speed Test "What can you do"
                    // checklist read from. Eliminates the contradiction where
                    // the icons said "no 4K" but the detail said "Netflix 4K UHD".
                    //
                    // Also: prefer the latest main-Speed-Test result when
                    // available — it has download/upload/ping/jitter/loss in
                    // one place. Fall back to streaming throughput numbers.
                    Text("These HTTPS responses show how the sampled endpoints answered. Actual video playback is a separate check.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - VPN Benchmark Content

    private var vpnBenchmarkContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card with run button
                CardView {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "globe.badge.chevron.backward")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("VPN Site Reachability")
                                .font(.headline)
                            Spacer()
                        }

                        Text("Test how fast popular international services respond through your connection.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if vpnBenchmark.isRunning {
                            ProgressView(value: vpnBenchmark.progress)
                                .tint(AppColors.accent)
                            Text("Testing \(Int(vpnBenchmark.progress * 100))%...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                Task { await vpnBenchmark.runBenchmark() }
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Run Benchmark")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColors.accent)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                    }
                }

                // Results
                if !vpnBenchmark.results.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(vpnBenchmark.results) { result in
                            vpnBenchmarkRow(result)
                        }
                    }

                    // FIX (Speed Issue 5): Explain what these numbers mean so
                    // a 1-second figure isn't read as a failure.
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Times describe full HTTPS responses over the current route, including any active VPN. A response or HTTP error does not prove that the service can play content or that every app uses the VPN.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private func vpnBenchmarkRow(_ result: VPNBenchmark.BenchmarkResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.destination.icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.destination.rawValue)
                    .font(.subheadline.bold())
                if let code = result.httpStatus {
                    Text("HTTP \(code)").font(.caption2).foregroundStyle(.secondary)
                }
                if let error = result.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if result.reachable, let latency = result.latencyMs {
                Text("\(Int(latency))ms")
                    .font(.subheadline.bold().monospaced())
                    .foregroundColor(benchmarkLatencyColor(latency))
            }

            Text(result.qualityRating)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(benchmarkBadgeColor(result).opacity(0.15))
                .foregroundColor(benchmarkBadgeColor(result))
                .cornerRadius(6)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    /// FIX (Speed Issue 5): Color thresholds match the qualityRating strings
    /// in `VPNBenchmark.BenchmarkResult.qualityRating`. Previously the
    /// rating said "Slow" but the badge was painted red anyway because the
    /// color thresholds were on a different scale.
    private func benchmarkLatencyColor(_ latency: Double) -> Color {
        if latency < 500 { return .green }
        if latency < 1000 { return Color(red: 0.6, green: 0.8, blue: 0.2) }  // light green / yellow-green
        if latency < 2000 { return .yellow }
        return .red
    }

    private func benchmarkBadgeColor(_ result: VPNBenchmark.BenchmarkResult) -> Color {
        guard result.reachable, let latency = result.latencyMs else { return .red }
        if let code = result.httpStatus, code >= 400 { return .orange }
        return benchmarkLatencyColor(latency)
    }

    /// FIX (Speed Issue 1/6): badge now reflects the full ActivityRating —
    /// excellent/good = green check, degraded = yellow warning, poor = red X.
    /// Previously every non-green case collapsed to a flat red X regardless
    /// of nuance.
    private func capabilityBadge(icon: String, label: String, rating: ActivityRating) -> some View {
        let tint: Color = {
            switch rating {
            case .unknown: return .secondary
            case .excellent, .good: return .green
            case .degraded: return .yellow
            case .poor: return .red
            }
        }()
        return VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(tint)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)

            Image(systemName: rating.sfSymbol)
                .font(.caption)
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Run Again Button

    @ViewBuilder
    private var runAgainButton: some View {
        switch selectedSection {
        case .overview:
            EmptyView()
        case .speedTest:
            if speedVM.hasResult && !speedVM.isRunning {
                Button("Run Again") {
                    speedVM.reset()
                    speedVM.runSpeedTest()
                }
            }
        case .streaming:
            if streamingVM.hasResult && !streamingVM.isRunning {
                Button("Run Again") {
                    Task {
                        streamingVM.reset()
                        await streamingVM.runStreamingDiagnostic()
                    }
                }
            }
        case .vpnSites:
            if !vpnBenchmark.results.isEmpty && !vpnBenchmark.isRunning {
                Button("Run Again") {
                    Task { await vpnBenchmark.runBenchmark() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SpeedTabView()
}
