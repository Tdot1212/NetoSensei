//
//  NetworkDebugView.swift
//  NetoSensei
//
//  Hidden debug panel - tap version number 5 times to access
//  Shows raw network interface data, DNS servers, VPN detection details
//

import SwiftUI
import Network

struct NetworkDebugView: View {
    @StateObject private var detector = SmartVPNDetector.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @State private var isRefreshing = false
    @State private var debugSnapshot: DebugSnapshot?
    @Environment(\.dismiss) private var dismiss

    struct DebugSnapshot {
        let interfaces: [(name: String, ip: String, family: String)]
        let dnsServers: [String]
        let methodResults: [SmartVPNDetector.VPNDetectionResult.MethodResult]
        let rawSSIDInfo: String
        let pathStatus: String
        let detectionReasoning: String
        let vpnResult: SmartVPNDetector.VPNDetectionResult?
        let networkStatus: NetworkStatus
        let timestamp: Date
    }

    var body: some View {
        NavigationView {
            List {
                // VPN Detection Summary
                if let result = debugSnapshot?.vpnResult {
                    Section("VPN Detection") {
                        debugRow("Status", value: result.detectionStatus.rawValue,
                                 color: result.isVPNActive ? .orange : (result.detectionStatus == .possiblyActive ? .yellow : .green))
                        debugRow("VPN Active", value: result.isVPNActive ? "YES" : "NO",
                                 color: result.isVPNActive ? .orange : .green)
                        debugRow("Confidence", value: "\(Int(result.confidence * 100))%")
                        debugRow("Protocol", value: result.vpnProtocol ?? "N/A")
                        debugRow("IP Type", value: result.ipType ?? "N/A")
                        debugRow("Display Label", value: result.displayLabel ?? "N/A")
                        debugRow("Public IP", value: result.publicIP ?? "N/A")
                        debugRow("Country", value: "\(result.publicCountry ?? "?") (expected: \(result.expectedCountry ?? "?"))")
                        debugRow("ISP", value: result.publicISP ?? "N/A")
                        debugRow("IP Verified", value: result.ipVerified ? "YES (2+ sources agree)" : "NO (single source)",
                                 color: result.ipVerified ? .green : .yellow)
                        debugRow("China Mode", value: result.isLikelyInChina ? "YES" : "NO",
                                 color: result.isLikelyInChina ? .orange : .primary)
                        debugRow("Authoritative", value: result.isAuthoritative ? "YES (NEVPNManager)" : "NO (inferred)",
                                 color: result.isAuthoritative ? .green : .yellow)
                        if !result.inferenceReasons.isEmpty {
                            debugRow("Inference", value: result.inferenceReasons.joined(separator: "; "))
                        }
                    }

                    // Detection Reasoning
                    if !debugSnapshot!.detectionReasoning.isEmpty {
                        Section("Detection Reasoning") {
                            Text(debugSnapshot!.detectionReasoning)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Detection Methods
                if let methods = debugSnapshot?.methodResults, !methods.isEmpty {
                    Section("Detection Methods") {
                        ForEach(methods.indices, id: \.self) { i in
                            let m = methods[i]
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: m.detected ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundColor(m.detected ? .green : .red)
                                    Text(m.method).font(.headline)
                                    Spacer()
                                    Text(m.detected ? "DETECTED" : "clear")
                                        .font(.caption)
                                        .foregroundColor(m.detected ? .orange : .secondary)
                                }
                                Text(m.detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Network Interfaces
                if let interfaces = debugSnapshot?.interfaces {
                    Section("Network Interfaces (\(interfaces.count))") {
                        ForEach(interfaces.indices, id: \.self) { i in
                            let iface = interfaces[i]
                            HStack {
                                Text(iface.name)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(isVPNInterface(iface.name) ? .orange : .primary)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(iface.ip)
                                        .font(.system(.caption, design: .monospaced))
                                    Text(iface.family)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // DNS Servers
                if let dns = debugSnapshot?.dnsServers {
                    Section("DNS Servers (\(dns.count))") {
                        if dns.isEmpty {
                            Text("No DNS servers detected")
                                .foregroundColor(.secondary)
                        }
                        ForEach(dns, id: \.self) { server in
                            Text(server)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // WiFi / SSID Info
                Section("WiFi / SSID Debug") {
                    let status = debugSnapshot?.networkStatus ?? networkMonitor.currentStatus
                    debugRow("WiFi Connected", value: status.wifi.isConnected ? "YES" : "NO")
                    debugRow("SSID", value: status.wifi.ssid ?? "nil")
                    debugRow("BSSID", value: status.wifi.bssid ?? "nil")

                    if let raw = debugSnapshot?.rawSSIDInfo {
                        Text("Raw CNCopyCurrentNetworkInfo:")
                            .font(.caption.bold())
                        Text(raw)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // NWPathMonitor Status
                if let pathDesc = debugSnapshot?.pathStatus {
                    Section("NWPathMonitor") {
                        Text(pathDesc)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Network Status
                Section("Network Status") {
                    let status = debugSnapshot?.networkStatus ?? networkMonitor.currentStatus
                    debugRow("Connection Type", value: status.connectionType?.displayName ?? "Unknown")
                    debugRow("Internet Reachable", value: status.internet.isReachable ? "YES" : "NO")
                    debugRow("HTTP Test", value: status.internet.httpTestSuccess ? "PASS" : "FAIL")
                    debugRow("External Latency", value: status.internet.latencyToExternal.map { "\(Int($0))ms" } ?? "N/A")
                    debugRow("Router IP", value: status.router.gatewayIP ?? "N/A")
                    debugRow("Router Reachable", value: status.router.isReachable ? "YES" : "NO")
                    debugRow("Router Latency", value: status.router.latency.map { "\(Int($0))ms" } ?? "N/A")
                    debugRow("DNS Latency", value: status.dns.latency.map { "\(Int($0))ms" } ?? "N/A")
                    debugRow("Local IP", value: status.localIP ?? "N/A")
                    debugRow("Public IP", value: status.publicIP ?? "N/A")
                    debugRow("Is Hotspot", value: status.isHotspot ? "YES" : "NO")
                    debugRow("IPv6", value: status.isIPv6Enabled ? "YES" : "NO")
                }

                // Timestamp
                if let ts = debugSnapshot?.timestamp {
                    Section("Snapshot") {
                        debugRow("Captured", value: ts.formatted(date: .abbreviated, time: .standard))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Network Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .task {
                await refresh()
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        let result = await SmartVPNDetector.shared.detectVPN(forceRefresh: true)
        let debug = SmartVPNDetector.shared.lastDebugInfo

        debugSnapshot = DebugSnapshot(
            interfaces: debug?.interfaces ?? SmartVPNDetector.shared.getAllInterfaces(),
            dnsServers: debug?.dnsServers ?? [],
            methodResults: result.methodResults,
            rawSSIDInfo: debug?.rawSSIDInfo ?? SmartVPNDetector.shared.getRawSSIDInfo(),
            pathStatus: debug?.pathStatus ?? "",
            detectionReasoning: debug?.detectionReasoning ?? "",
            vpnResult: result,
            networkStatus: networkMonitor.currentStatus,
            timestamp: Date()
        )
        isRefreshing = false
    }

    private func debugRow(_ title: String, value: String, color: Color? = nil) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color ?? .primary)
        }
    }

    private func isVPNInterface(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "tap", "tun"].contains { name.hasPrefix($0) }
    }
}
