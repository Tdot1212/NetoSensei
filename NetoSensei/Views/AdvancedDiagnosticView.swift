//
//  AdvancedDiagnosticView.swift
//  NetoSensei
//
//  Advanced diagnostic view with comprehensive network analysis
//

import SwiftUI

struct AdvancedDiagnosticView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var diagnosticService = AdvancedDiagnosticService.shared
    @State private var destination = "www.google.com"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if diagnosticService.isRunning {
                        // Progress View
                        DiagnosticProgressView(
                            progress: diagnosticService.progress,
                            currentTest: diagnosticService.currentTest
                        )
                    } else if let result = diagnosticService.currentResult {
                        // Results View
                        AdvancedDiagnosticResultsView(result: result)
                    } else {
                        // Initial State
                        AdvancedDiagnosticStartView(
                            destination: $destination,
                            onStart: startDiagnostics
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Advanced Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if diagnosticService.currentResult != nil && !diagnosticService.isRunning {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: startDiagnostics) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    private func startDiagnostics() {
        Task {
            _ = await diagnosticService.runFullAdvancedDiagnostics(destination: destination)
        }
    }
}

// MARK: - Start View

struct AdvancedDiagnosticStartView: View {
    @Binding var destination: String
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Advanced Network Diagnostics")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 15) {
                Text("This scan will test:")
                    .font(.headline)

                DiagnosticTestItem(icon: "wifi", title: "Local WiFi Throughput", subtitle: "Phone ↔ Router speed test")
                DiagnosticTestItem(icon: "point.3.connected.trianglepath.dotted", title: "Traceroute Analysis", subtitle: "Find exact bottleneck location")
                DiagnosticTestItem(icon: "lock.shield", title: "VPN Performance", subtitle: "Benchmark VPN regions")
                DiagnosticTestItem(icon: "waveform.path.ecg", title: "Network Noise Scan", subtitle: "Channel congestion detection")
                DiagnosticTestItem(icon: "cpu", title: "Router Load Test", subtitle: "CPU overload detection")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            VStack(spacing: 10) {
                Text("Test Destination")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("www.google.com", text: $destination)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
            }

            Button(action: onStart) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Advanced Scan")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Text("⏱️ This scan takes 2-3 minutes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct DiagnosticTestItem: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Progress View

struct DiagnosticProgressView: View {
    let progress: Double
    let currentTest: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)

            VStack(spacing: 8) {
                Text(currentTest)
                    .font(.headline)

                Text("\(Int(progress * 100))% Complete")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 300)
        }
        .padding()
    }
}

// MARK: - Results View

struct AdvancedDiagnosticResultsView: View {
    let result: AdvancedDiagnosticResult

    var body: some View {
        VStack(spacing: 20) {
            // A. WiFi Throughput
            if let wifiResult = result.wifiThroughputResult {
                WiFiThroughputCard(result: wifiResult)
            }

            // B. Traceroute
            if let traceResult = result.tracerouteResult {
                TracerouteCard(result: traceResult)
            }

            // C. VPN Benchmark
            if let vpnResult = result.vpnBenchmarkResult {
                VPNBenchmarkCard(result: vpnResult)
            }

            // D. Network Noise
            if let noiseResult = result.networkNoiseResult {
                NetworkNoiseCard(result: noiseResult)
            }

            // E. Router Load
            if let loadResult = result.routerLoadResult {
                RouterLoadCard(result: loadResult)
            }
        }
    }
}

// MARK: - WiFi Throughput Card

struct WiFiThroughputCard: View {
    let result: WiFiThroughputResult

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(.blue)

                Text("WiFi Throughput Test")
                    .font(.headline)

                Spacer()

                QualityBadge(quality: result.quality.rawValue, color: colorForQuality(result.quality))
            }

            // Speed Metrics
            HStack(spacing: 20) {
                MetricView(label: "Download", value: String(format: "%.1f Mbps", result.downloadSpeed), icon: "arrow.down.circle.fill", color: .green)
                MetricView(label: "Upload", value: String(format: "%.1f Mbps", result.uploadSpeed), icon: "arrow.up.circle.fill", color: .orange)
            }

            HStack(spacing: 20) {
                MetricView(label: "Latency", value: String(format: "%.0f ms", result.latency), icon: "timer", color: .blue)
                MetricView(label: "Jitter", value: String(format: "%.0f ms", result.jitter), icon: "waveform.path.ecg", color: .purple)
            }

            if let signal = result.signalStrength {
                MetricView(label: "Signal", value: "\(signal) dBm", icon: "antenna.radiowaves.left.and.right", color: .cyan)
            }

            // Issues
            if !result.issues.isEmpty {
                Divider()

                Text("Issues Detected")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.red)

                ForEach(result.issues, id: \.self) { issue in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text(issue)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func colorForQuality(_ quality: ThroughputQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .red
        }
    }
}

// MARK: - Traceroute Card

struct TracerouteCard: View {
    let result: TracerouteResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundColor(.green)

                Text("Traceroute Analysis")
                    .font(.headline)

                Spacer()

                if !result.hops.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // FIX (Phase 2): traceroute is sandboxed on iOS — show an honest
            // platform-limitation message instead of "Check your internet
            // connection" / "Try again later", which were misleading users.
            if result.hops.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Traceroute unavailable — iOS restricts ICMP traceroute for third-party apps. This is a platform limitation, not a network issue.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                // Diagnosis
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)

                    Text(result.diagnosis)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Bottleneck
                if let bottleneck = result.bottleneckHop {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bottleneck Detected")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)

                        HopRowView(hop: bottleneck, isBottleneck: true)
                    }
                }

                // Hop List (expandable)
                if isExpanded {
                    Divider()

                    Text("All Hops")
                        .font(.subheadline)
                        .fontWeight(.bold)

                    ForEach(result.hops) { hop in
                        HopRowView(hop: hop, isBottleneck: hop.id == result.bottleneckHop?.id)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct HopRowView: View {
    let hop: TracerouteHop
    let isBottleneck: Bool

    var body: some View {
        HStack {
            Text("\(hop.hopNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(isBottleneck ? Color.red : Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(hop.hostname ?? hop.ipAddress)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let isp = hop.isp {
                    Text(isp)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f ms", hop.latency))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(colorForHopStatus(hop.status))

                if hop.latencyChange > 0 {
                    Text("+\(String(format: "%.0f ms", hop.latencyChange))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(isBottleneck ? Color.red.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }

    private func colorForHopStatus(_ status: HopStatus) -> Color {
        switch status {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .slow: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - VPN Benchmark Card

struct VPNBenchmarkCard: View {
    let result: VPNBenchmarkResult

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(.purple)

                Text("VPN Performance")
                    .font(.headline)

                Spacer()

                if result.isVPNActive {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            if result.isVPNActive {
                if let region = result.detectedVPNRegion, let provider = result.detectedVPNProvider {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Region: \(region)")
                                .font(.caption)
                            Text("Provider: \(provider)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }

                if let overhead = result.vpnOverhead {
                    HStack {
                        Text("VPN Overhead")
                            .font(.subheadline)

                        Spacer()

                        Text(String(format: "%.1f%%", overhead))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(colorForEfficiency(result.efficiency))
                    }
                }

                if !result.regionalBenchmarks.isEmpty {
                    Divider()

                    Text("Suggested Regions")
                        .font(.subheadline)
                        .fontWeight(.bold)

                    ForEach(result.regionalBenchmarks.prefix(3)) { benchmark in
                        RegionBenchmarkRow(benchmark: benchmark)
                    }
                }
            } else {
                Text("VPN is not active")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func colorForEfficiency(_ efficiency: VPNEfficiency) -> Color {
        switch efficiency {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

struct RegionBenchmarkRow: View {
    let benchmark: VPNRegionBenchmark

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(benchmark.region)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(benchmark.country)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f ms", benchmark.latency))
                    .font(.caption)

                Text(String(format: "~%.0f Mbps", benchmark.estimatedSpeed))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

// MARK: - Network Noise Card

struct NetworkNoiseCard: View {
    let result: NetworkNoiseResult

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.orange)

                Text("Network Noise Scan")
                    .font(.headline)

                Spacer()

                QualityBadge(quality: result.overallNoiseLevel.rawValue, color: colorForNoiseLevel(result.overallNoiseLevel))
            }

            // Current Info
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(result.currentChannel)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Frequency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", result.currentFrequency)) GHz")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Signal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(result.currentSignalStrength) dBm")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
            }

            Divider()

            // Congestion & Interference
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channel Congestion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(describing: result.channelCongestion).capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Interference")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(describing: result.interference).capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            // Recommendation
            if let suggested = result.suggestedChannel {
                Divider()

                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)

                    Text("Switch to channel \(suggested) for better performance")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func colorForNoiseLevel(_ level: NoiseLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .severe: return .red
        }
    }
}

// MARK: - Router Load Card

struct RouterLoadCard: View {
    let result: RouterLoadResult

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.red)

                Text("Router Load Test")
                    .font(.headline)

                Spacer()

                QualityBadge(quality: result.routerHealth.rawValue, color: colorForRouterHealth(result.routerHealth))
            }

            // Latency Impact
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baseline Latency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f ms", result.baselineLatency))
                        .font(.subheadline)
                        .fontWeight(.bold)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Under Load")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f ms", result.loadedLatency))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(result.isRouterOverloaded ? .red : .primary)
                }
            }

            // Increase Metrics
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latency Increase")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "+%.0f%%", result.percentageIncrease))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(result.percentageIncrease > 50 ? .red : .green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Throughput Drop")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "-%.0f%%", result.throughputDrop))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(result.throughputDrop > 25 ? .red : .green)
                }
            }

            Divider()

            // Diagnosis
            HStack {
                Image(systemName: result.isRouterOverloaded ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(result.isRouterOverloaded ? .red : .green)

                Text(result.diagnosis)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .background(result.isRouterOverloaded ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func colorForRouterHealth(_ health: RouterHealth) -> Color {
        switch health {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .overloaded: return .red
        }
    }
}

// MARK: - Helper Views

struct MetricView: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QualityBadge: View {
    let quality: String
    let color: Color

    var body: some View {
        Text(quality)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

#Preview {
    AdvancedDiagnosticView()
}
