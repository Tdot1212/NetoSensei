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
    @State private var selectedSection: SpeedSection = .speedTest

    enum SpeedSection: String, CaseIterable {
        case speedTest = "Speed Test"
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
                .padding()

                // Content based on selection
                switch selectedSection {
                case .speedTest:
                    speedTestContent
                case .streaming:
                    streamingContent
                case .vpnSites:
                    vpnBenchmarkContent
                }
            }
            .navigationTitle("Speed & Streaming")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Share button (for speed test only)
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
        .navigationViewStyle(.stack)
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

                        // Ping
                        VStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            Text("\(Int(result.ping))")
                                .font(.title2.bold())
                                .foregroundColor(NetworkColors.forLatency(result.ping))
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
                    StreamingDiagnosticContentView(vm: streamingVM)
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
                        Text("Test your connection's ability to stream 4K, gaming, video calls, and more.")
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
                } else if let result = streamingVM.result {
                    // FIX (Speed Issue 1/6): Icon row reads from
                    // ConnectionCapabilityAnalyzer — the SAME source that the
                    // per-service detail and the Speed Test "What can you do"
                    // checklist read from. Eliminates the contradiction where
                    // the icons said "no 4K" but the detail said "Netflix 4K UHD".
                    //
                    // Also: prefer the latest main-Speed-Test result when
                    // available — it has download/upload/ping/jitter/loss in
                    // one place. Fall back to streaming throughput numbers.
                    let capability: ConnectionCapability = {
                        if let speed = HistoryManager.shared.speedTestHistory.first {
                            return ConnectionCapabilityAnalyzer.analyze(from: speed)
                        }
                        return ConnectionCapabilityAnalyzer.analyze(
                            downloadMbps: result.cdnThroughput,
                            uploadMbps: 0,
                            pingMs: result.cdnPing,
                            jitterMs: 0
                        )
                    }()

                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            capabilityBadge(icon: "4k.tv",        label: "4K",     rating: capability.streaming4K)
                            capabilityBadge(icon: "play.rectangle", label: "HD",   rating: capability.streamingHD)
                            capabilityBadge(icon: "gamecontroller", label: "Gaming", rating: capability.gaming)
                            capabilityBadge(icon: "video",        label: "Calls",  rating: capability.videoCalls)
                        }
                    }
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
                        Text("Times shown include full HTTP request through your VPN tunnel. For international VPN connections (China to US), 500-2000ms is normal. Under 1 second is good.")
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
        return benchmarkLatencyColor(latency)
    }

    /// FIX (Speed Issue 1/6): badge now reflects the full ActivityRating —
    /// excellent/good = green check, degraded = yellow warning, poor = red X.
    /// Previously every non-green case collapsed to a flat red X regardless
    /// of nuance.
    private func capabilityBadge(icon: String, label: String, rating: ActivityRating) -> some View {
        let tint: Color = {
            switch rating {
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
