//
//  TracerouteView.swift
//  NetoSensei
//
//  Network path visualization — shows hops between device and destination
//

import SwiftUI

struct TracerouteView: View {
    @StateObject private var service = TracerouteService.shared
    @State private var destination = "google.com"
    @State private var useCustomDestination = false
    @State private var hasRun = false

    private var vpnActive: Bool {
        SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if useCustomDestination {
                    destinationInput
                }

                actionButton

                if hasRun || service.isRunning {
                    resultsSection
                }

                if !hasRun && !service.isRunning {
                    explanationCard
                }
            }
            .padding()
        }
        .navigationTitle("Network Path")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Traceroute")
                    .font(.headline)
                Text("See the path your data takes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if vpnActive {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.caption)
                    Text("VPN")
                        .font(.caption.bold())
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Destination Input

    private var destinationInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            HStack {
                TextField("google.com", text: $destination)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                Button(action: { useCustomDestination = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        VStack(spacing: 12) {
            Button(action: runTrace) {
                HStack {
                    if service.isRunning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                        Text("Tracing hop \(service.currentHop)...")
                    } else {
                        Image(systemName: "play.fill")
                        Text(hasRun ? "Run Again" : "Trace Network Path")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(service.isRunning ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(service.isRunning)

            if !useCustomDestination && !service.isRunning {
                Button(action: { useCustomDestination = true }) {
                    Text("Custom destination")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary card
            if let result = service.result, !service.isRunning {
                summaryCard(result)
            }

            Text("Network Hops")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            // Hop list
            VStack(spacing: 0) {
                ForEach(Array(service.hops.enumerated()), id: \.element.id) { index, hop in
                    TracerouteHopRow(
                        hop: hop,
                        isLast: index == service.hops.count - 1,
                        isAnimating: service.isRunning && index == service.hops.count - 1
                    )

                    if index < service.hops.count - 1 {
                        TracerouteConnector()
                    }
                }

                if service.isRunning {
                    TracerouteConnector()
                    TracerouteScanningRow(hopNumber: service.currentHop)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Bottleneck highlight
            if let result = service.result, let bottleneck = result.bottleneckHop, !service.isRunning {
                bottleneckCard(bottleneck)
            }

            legendCard
        }
    }

    private func summaryCard(_ result: TracerouteResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Path to \(result.destination)")
                        .font(.subheadline.bold())
                    Text("\(result.hops.count) hops traced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0fms", result.totalLatency))
                        .font(.title2.bold())
                        .foregroundColor(.blue)
                    Text("total latency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack(spacing: 16) {
                TracerouteStatItem(label: "Hops", value: "\(result.hops.count)")
                TracerouteStatItem(label: "Latency", value: String(format: "%.0fms", result.totalLatency))

                if let bottleneck = result.bottleneckHop {
                    TracerouteStatItem(
                        label: "Bottleneck",
                        value: "Hop \(bottleneck.hopNumber)"
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func bottleneckCard(_ hop: TracerouteHop) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Bottleneck Detected")
                    .font(.subheadline.bold())
            }

            let name = hop.hostname ?? hop.ipAddress
            Text("Hop \(hop.hopNumber) (\(name)) added \(String(format: "%.0f", hop.latencyChange))ms of latency.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let result = service.result {
                Text(result.diagnosis)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Legend

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Understanding the path")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                TracerouteLegendItem(color: .green, text: "Local network (your router)")
                TracerouteLegendItem(color: .blue, text: "ISP / Internet backbone")
                TracerouteLegendItem(color: .orange, text: "VPN server (if active)")
                TracerouteLegendItem(color: .purple, text: "Destination (last hop)")
                TracerouteLegendItem(color: .gray, text: "Timeout (no response)")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("What is Traceroute?")
                    .font(.subheadline.bold())
            }

            Text("Traceroute shows each network hop between your device and a destination. It helps identify where slowdowns or problems occur in the network path.")
                .font(.caption)
                .foregroundColor(.secondary)

            if vpnActive {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.orange)
                    Text("VPN detected. The trace will show your traffic routing through the VPN server before reaching the destination.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func runTrace() {
        hasRun = true
        Task {
            if useCustomDestination && !destination.isEmpty {
                _ = await service.runTraceroute(to: destination)
            } else {
                _ = await service.runPracticalTraceroute(vpnActive: vpnActive)
            }
        }
    }
}

// MARK: - Hop Row

struct TracerouteHopRow: View {
    let hop: TracerouteHop
    let isLast: Bool
    let isAnimating: Bool

    private var isTimeout: Bool { hop.ipAddress == "*" }

    private var hopColor: Color {
        if isTimeout { return .gray }
        if isLast { return .purple }
        if hop.hopNumber == 1 { return .green }
        if hop.isp?.lowercased().contains("vpn") == true ||
           hop.hostname?.lowercased().contains("vpn") == true {
            return .orange
        }
        return .blue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Hop number badge
            ZStack {
                Circle()
                    .fill(hopColor.opacity(0.2))
                    .frame(width: 32, height: 32)

                if isAnimating {
                    Circle()
                        .stroke(hopColor, lineWidth: 2)
                        .frame(width: 32, height: 32)
                        .modifier(TraceroutePulse())
                }

                Text("\(hop.hopNumber)")
                    .font(.caption.bold())
                    .foregroundColor(hopColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if isTimeout {
                        Text("*")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text(hop.ipAddress)
                            .font(.system(.subheadline, design: .monospaced))
                    }

                    if let hostname = hop.hostname, !hostname.isEmpty {
                        Text("(\(hostname))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if !isTimeout {
                    HStack(spacing: 8) {
                        if let isp = hop.isp {
                            Text(isp)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if let asn = hop.asn {
                            Text(asn)
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(3)
                                .lineLimit(1)
                        }

                        if let loc = hop.location {
                            Text(countryFlag(loc))
                                .font(.caption)
                        }
                    }
                }
            }

            Spacer()

            // Latency
            VStack(alignment: .trailing, spacing: 2) {
                if isTimeout {
                    Text("*")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: "%.0fms", hop.latency))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(latencyColor(hop.latency))

                    if hop.latencyChange > 5 {
                        Text("+\(String(format: "%.0f", hop.latencyChange))")
                            .font(.caption2)
                            .foregroundColor(hop.latencyChange > 50 ? .red : .orange)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 50 { return .green }
        if ms < 150 { return .orange }
        return .red
    }

    private func countryFlag(_ code: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in code.uppercased().unicodeScalars {
            if let unicode = UnicodeScalar(base + scalar.value) {
                flag.append(String(unicode))
            }
        }
        return flag
    }
}

// MARK: - Connector

struct TracerouteConnector: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2, height: 20)
                .padding(.leading, 15)
            Spacer()
        }
    }
}

// MARK: - Scanning Row

struct TracerouteScanningRow: View {
    let hopNumber: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text("Probing hop \(hopNumber)...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Supporting Views

struct TracerouteStatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct TracerouteLegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TraceroutePulse: ViewModifier {
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(animate ? 1.3 : 1.0)
            .opacity(animate ? 0 : 1)
            .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: animate)
            .onAppear { animate = true }
    }
}
