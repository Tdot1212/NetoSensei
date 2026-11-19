//
//  DetailCards.swift
//  NetoSensei
//
//  VPN Details, WiFi Details expandable cards, and VPN Leak Test result sheet
//

import SwiftUI

// MARK: - VPN Details Card

struct VPNDetailsCard: View {
    @ObservedObject private var vpnDetector = SmartVPNDetector.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @ObservedObject private var privacyService = PrivacyShieldService.shared
    @State private var isExpanded = false

    var body: some View {
        // Only show when VPN is detected
        let vpnActive = vpnDetector.detectionResult?.isVPNActive ?? false
        if vpnActive {
            VStack(alignment: .leading, spacing: 12) {
                Text("VPN Details")
                    .font(.headline)
                    .padding(.leading, 4)

                CardView {
                    VStack(spacing: 0) {
                        // Header - always visible
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vpnDetector.detectionResult?.isAuthoritative == true
                                         ? "VPN Active"
                                         : "VPN/Proxy Detected (inferred)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(vpnDetector.detectionResult?.publicISP ?? "Unknown provider")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        // Expanded details
                        if isExpanded, let result = vpnDetector.detectionResult {
                            Divider()
                                .padding(.vertical, 8)

                            // VPN Health Score
                            vpnHealthSection

                            Divider()
                                .padding(.vertical, 4)

                            VStack(spacing: 10) {
                                detailRow(title: "Observed public IP", value: result.publicIP ?? "Unknown")
                                detailRow(title: "Estimated IP location", value: formatLocation(city: result.publicCity, country: result.publicCountry))
                                detailRow(title: "IP organization", value: result.publicISP ?? "Unknown")
                                detailRow(title: "IP Type", value: detectIPType(isp: result.publicISP))
                                detailRow(title: "Protocol Hint", value: detectProtocolHint())
                                detailRow(title: "Detection", value: result.isAuthoritative
                                         ? "Confirmed (iOS system)"
                                         : "Inferred from connection hints")
                                if !result.inferenceReasons.isEmpty {
                                    detailRow(title: "Reasoning", value: result.inferenceReasons.joined(separator: "\n"))
                                }
                                detailRow(title: "Tunnel Interface", value: getVPNInterfaceName())

                                // DNS through VPN
                                let dnsInfo = networkMonitor.currentStatus.dns
                                if let resolver = dnsInfo.resolverIP {
                                    detailRow(title: "DNS Server", value: resolver)
                                }

                                // Connection uptime (from detection timestamp)
                                detailRow(title: "Detected", value: formatTimestamp(result.timestamp))

                                // Detection method results
                                if !result.methodResults.isEmpty {
                                    Divider()
                                        .padding(.vertical, 4)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Detection Methods")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)

                                        ForEach(result.methodResults.indices, id: \.self) { index in
                                            let method = result.methodResults[index]
                                            // FIX (Sec Issue 5): Three-state icon — green ✓ for
                                            // genuine positives, gray ⓘ for "platform limitation /
                                            // not applicable" results, gray ⊗ for genuine negatives.
                                            // Previously platform-limit results rendered as ⊗ and
                                            // looked like failures.
                                            let iconName: String = {
                                                if method.detected { return "checkmark.circle.fill" }
                                                if method.isInformational { return "info.circle" }
                                                return "xmark.circle"
                                            }()
                                            let iconColor: Color = method.detected ? .green : .gray
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: iconName)
                                                    .font(.caption2)
                                                    .foregroundColor(iconColor)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(method.method)
                                                        .font(.caption.bold())
                                                    Text(method.detail)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }

                                // iOS limitations note
                                Divider()
                                    .padding(.vertical, 4)

                                Text("iOS can only detect VPNs registered with the system. Third-party proxy apps and router-level VPNs may not be detected directly.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var vpnHealthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("VPN protection unverified", systemImage: "questionmark.shield")
                .font(.subheadline.bold())
            Text("A detected VPN interface does not establish encryption, absence of leaks, or its performance impact. Review the individual connection checks.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatLocation(city: String?, country: String?) -> String {
        if let c = city, let co = country, !c.isEmpty {
            return "\(c), \(co)"
        } else if let co = country {
            return co
        }
        return "Unknown"
    }

    private func detectIPType(isp: String?) -> String { "Unverified (organization name only)" }
    private func detectProtocolHint() -> String { "Unverified (interface names do not identify protocol)" }

    private func getVPNInterfaceName() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "None" }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        var vpnInterfaces: [String] = []
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                if !vpnInterfaces.contains(name) {
                    vpnInterfaces.append(name)
                }
            }
        }

        return vpnInterfaces.isEmpty ? "None detected" : vpnInterfaces.joined(separator: ", ")
    }

    private func formatTimestamp(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        return "\(Int(elapsed / 86400))d ago"
    }
}

// MARK: - WiFi Details Card

struct WiFiDetailsCard: View {
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @State private var isExpanded = false

    var body: some View {
        let wifi = networkMonitor.currentStatus.wifi
        guard wifi.isConnected else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("WiFi Details")
                    .font(.headline)
                    .padding(.leading, 4)

                CardView {
                    VStack(spacing: 0) {
                        // Header
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                            HStack {
                                Image(systemName: "wifi")
                                    .foregroundColor(.blue)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wifi.ssid ?? "Connected")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("Tap for details")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            Divider()
                                .padding(.vertical, 8)

                            let status = networkMonitor.currentStatus

                            VStack(spacing: 10) {
                                // SSID
                                wifiDetailRow(title: "Network Name (SSID)", value: wifi.ssid ?? "Unavailable")

                                // BSSID (Router MAC)
                                wifiDetailRow(title: "Access point ID (BSSID)", value: wifi.bssid ?? "Unavailable")

                                // Local IP
                                wifiDetailRow(title: "Your Local IP", value: status.localIP ?? "Unknown")

                                // Gateway / Router IP
                                wifiDetailRow(title: "Router IP (Gateway)", value: status.router.gatewayIP ?? "Unknown")

                                // Router latency
                                if let latency = status.router.latency {
                                    wifiDetailRow(title: "Router Latency", value: "\(Int(latency))ms")
                                }

                                // DNS Servers
                                if let dns = status.dns.resolverIP {
                                    wifiDetailRow(title: "DNS Server", value: dns)
                                }

                                // DNS Latency
                                if let dnsLatency = status.dns.latency {
                                    wifiDetailRow(title: "DNS Latency", value: "\(Int(dnsLatency))ms")
                                }

                                // IPv6
                                wifiDetailRow(title: "IPv6", value: status.isIPv6Enabled ? "Supported" : "Not available")

                                // Hotspot detection
                                if status.isHotspot {
                                    HStack(spacing: 6) {
                                        Image(systemName: "personalhotspot")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text("Connected via mobile hotspot")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.top, 4)
                                }

                                Divider()
                                Text("For channel, band or security mode, check your router’s Wi-Fi settings.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        )
    }

    private func wifiUnavailableRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("Not available on iOS")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .italic()
        }
    }

    private func wifiDetailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - VPN Leak Test Result Sheet

struct VPNLeakTestResultSheet: View {
    let result: VPNLeakTestResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let result = result {
                        // Overall verdict
                        VStack(spacing: 12) {
                            Image(systemName: result.overallVerdict.systemImage)
                                .font(.system(size: 60))
                                .foregroundColor(verdictColor(result.overallVerdict))

                            Text(result.overallVerdict.displayText)
                                .font(.title.bold())
                                .foregroundColor(verdictColor(result.overallVerdict))

                            if result.overallVerdict == .noVPN {
                                Text("Connect to a VPN first, then run this test")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding()

                        if result.overallVerdict != .noVPN {
                            // VPN Server info
                            if let serverIP = result.vpnServerIP {
                                HStack {
                                    Image(systemName: "server.rack")
                                        .foregroundColor(.blue)
                                    Text("VPN Server: \(serverIP)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                            }

                            // Leak check results
                            VStack(spacing: 0) {
                                leakCheckRow(result.dnsLeak)
                                Divider()
                                leakCheckRow(result.ipLeak)
                                Divider()
                                leakCheckRow(result.webRTCLeak)
                            }
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)

                            // DNS servers detected
                            if !result.detectedDNSServers.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("DNS Servers Detected")
                                        .font(.subheadline.bold())

                                    ForEach(result.detectedDNSServers, id: \.self) { server in
                                        HStack {
                                            Image(systemName: "server.rack")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                            Text(server)
                                                .font(.caption.monospaced())
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }

                            // Solutions section
                            let solutions = [result.dnsLeak, result.ipLeak, result.webRTCLeak]
                                .compactMap { $0.solution }

                            if !solutions.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recommendations")
                                        .font(.subheadline.bold())

                                    ForEach(solutions.indices, id: \.self) { index in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "lightbulb.fill")
                                                .font(.caption)
                                                .foregroundColor(.yellow)
                                            Text(solutions[index])
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }

                        Spacer()
                    } else {
                        ProgressView("Running leak test...")
                    }
                }
            }
            .navigationTitle("VPN Leak Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func leakCheckRow(_ check: VPNLeakTestResult.LeakCheck) -> some View {
        HStack {
            Image(systemName: severityIcon(check.severity))
                .foregroundColor(severityColor(check.severity))

            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.subheadline.bold())
                Text(check.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func verdictColor(_ verdict: VPNLeakTestResult.Verdict) -> Color {
        switch verdict {
        case .unverified: return .gray
        case .noLeaks: return .green
        case .minorLeaks: return .yellow
        case .majorLeaks: return .red
        case .noVPN: return .gray
        }
    }

    private func severityIcon(_ severity: VPNLeakTestResult.LeakCheck.Severity) -> String {
        switch severity {
        case .safe: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    private func severityColor(_ severity: VPNLeakTestResult.LeakCheck.Severity) -> Color {
        switch severity {
        case .safe: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}
